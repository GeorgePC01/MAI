//
//  CEFBridge.mm
//  MAI Browser - Chromium Embedded Framework Bridge
//
//  Wraps CEF C API using Objective-C++ for Swift consumption.
//  Uses struct-based C API with manual reference counting.
//

#import "include/CEFBridge.h"
#include "include/capi/cef_app_capi.h"
#include "include/capi/cef_browser_capi.h"
#include "include/capi/cef_client_capi.h"
#include "include/capi/cef_life_span_handler_capi.h"
#include "include/capi/cef_load_handler_capi.h"
#include "include/capi/cef_display_handler_capi.h"
#include "include/capi/cef_permission_handler_capi.h"
#include "include/capi/cef_request_handler_capi.h"
#include "include/capi/cef_browser_process_handler_capi.h"
#include "include/capi/cef_jsdialog_handler_capi.h"
#include "include/cef_api_hash.h"
#include "include/wrapper/cef_library_loader.h"

#import <ScreenCaptureKit/ScreenCaptureKit.h>
#import <CoreImage/CoreImage.h>

#include <atomic>
#include <stdio.h>

// File-based logging for permission debugging (NSLog may not appear in system logs)
static void cef_log_to_file(const char* fmt, ...) __attribute__((format(printf, 1, 2)));
static void cef_log_to_file(const char* fmt, ...) {
    FILE* f = fopen("/tmp/cef_permission.log", "a");
    if (!f) return;
    // Write timestamp
    NSString* ts = [NSDateFormatter localizedStringFromDate:[NSDate date]
                                                 dateStyle:NSDateFormatterShortStyle
                                                 timeStyle:NSDateFormatterMediumStyle];
    fprintf(f, "[%s] ", [ts UTF8String]);
    va_list args;
    va_start(args, fmt);
    vfprintf(f, fmt, args);
    va_end(args);
    fprintf(f, "\n");
    fflush(f);
    fclose(f);
}

// MARK: - Global State

static BOOL g_cefInitialized = NO;
static cef_browser_t* g_browser = NULL;
static NSView* g_browserView = NULL;
static NSTimer* g_messagePumpTimer = nil;
static __weak id<CEFBridgeDelegate> g_delegate = nil;

// MARK: - Reference Counting Helpers

/// Increment reference count on a CEF base struct
static inline void cef_addref(cef_base_ref_counted_t* base) {
    if (base && base->add_ref) {
        base->add_ref(base);
    }
}

/// Decrement reference count on a CEF base struct
static inline int cef_release(cef_base_ref_counted_t* base) {
    if (base && base->release) {
        return base->release(base);
    }
    return 0;
}

// MARK: - Base Ref Counted Implementation

/// Reference counted base for all CEF handler structs
typedef struct {
    std::atomic<int> ref_count;
} ref_count_data_t;

/// Initialize a cef_base_ref_counted_t with proper ref counting
static void init_base_ref_counted(cef_base_ref_counted_t* base, size_t struct_size) {
    base->size = struct_size;

    // Allocate ref count data
    ref_count_data_t* data = new ref_count_data_t();
    data->ref_count = 1;

    // Store pointer in unused padding area after the struct
    // We use a static map instead for cleaner approach
    static NSMapTable<NSValue*, NSValue*>* refCountMap = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        refCountMap = [NSMapTable strongToStrongObjectsMapTable];
    });

    NSValue* key = [NSValue valueWithPointer:base];
    NSValue* val = [NSValue valueWithPointer:data];
    [refCountMap setObject:val forKey:key];

    base->add_ref = [](cef_base_ref_counted_t* self) {
        static NSMapTable<NSValue*, NSValue*>* map = nil;
        static dispatch_once_t token;
        dispatch_once(&token, ^{
            // This will be the same map as above since dispatch_once is idempotent
            map = [NSMapTable strongToStrongObjectsMapTable];
        });

        // Find ref count data
        NSValue* k = [NSValue valueWithPointer:self];
        NSValue* v = [refCountMap objectForKey:k];
        if (v) {
            ref_count_data_t* d = (ref_count_data_t*)[v pointerValue];
            d->ref_count.fetch_add(1, std::memory_order_relaxed);
        }
    };

    base->release = [](cef_base_ref_counted_t* self) -> int {
        NSValue* k = [NSValue valueWithPointer:self];
        NSValue* v = [refCountMap objectForKey:k];
        if (v) {
            ref_count_data_t* d = (ref_count_data_t*)[v pointerValue];
            int newCount = d->ref_count.fetch_sub(1, std::memory_order_acq_rel) - 1;
            if (newCount == 0) {
                [refCountMap removeObjectForKey:k];
                delete d;
                free(self);
                return 1;
            }
            return 0;
        }
        return 0;
    };

    base->has_one_ref = [](cef_base_ref_counted_t* self) -> int {
        NSValue* k = [NSValue valueWithPointer:self];
        NSValue* v = [refCountMap objectForKey:k];
        if (v) {
            ref_count_data_t* d = (ref_count_data_t*)[v pointerValue];
            return d->ref_count.load(std::memory_order_acquire) == 1 ? 1 : 0;
        }
        return 0;
    };

    base->has_at_least_one_ref = [](cef_base_ref_counted_t* self) -> int {
        NSValue* k = [NSValue valueWithPointer:self];
        NSValue* v = [refCountMap objectForKey:k];
        if (v) {
            ref_count_data_t* d = (ref_count_data_t*)[v pointerValue];
            return d->ref_count.load(std::memory_order_acquire) >= 1 ? 1 : 0;
        }
        return 0;
    };
}

// MARK: - Simple Ref Counting (stack-allocated handlers)

/// Simplified ref counting for handlers that live as long as the browser
/// Uses a single global ref count map
static NSMutableDictionary<NSValue*, NSNumber*>* g_refCounts = nil;

static void ensure_ref_map() {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        g_refCounts = [NSMutableDictionary dictionary];
    });
}

static void simple_add_ref(cef_base_ref_counted_t* self) {
    ensure_ref_map();
    NSValue* key = [NSValue valueWithPointer:self];
    NSNumber* count = g_refCounts[key] ?: @1;
    g_refCounts[key] = @(count.intValue + 1);
}

static int simple_release(cef_base_ref_counted_t* self) {
    ensure_ref_map();
    NSValue* key = [NSValue valueWithPointer:self];
    NSNumber* count = g_refCounts[key] ?: @1;
    int newCount = count.intValue - 1;
    if (newCount <= 0) {
        [g_refCounts removeObjectForKey:key];
        return 1;
    }
    g_refCounts[key] = @(newCount);
    return 0;
}

static int simple_has_one_ref(cef_base_ref_counted_t* self) {
    ensure_ref_map();
    NSValue* key = [NSValue valueWithPointer:self];
    NSNumber* count = g_refCounts[key] ?: @1;
    return count.intValue == 1 ? 1 : 0;
}

static int simple_has_at_least_one_ref(cef_base_ref_counted_t* self) {
    ensure_ref_map();
    NSValue* key = [NSValue valueWithPointer:self];
    NSNumber* count = g_refCounts[key] ?: @1;
    return count.intValue >= 1 ? 1 : 0;
}

static void init_simple_ref(cef_base_ref_counted_t* base, size_t size) {
    memset(base, 0, size);
    base->size = size;
    base->add_ref = simple_add_ref;
    base->release = simple_release;
    base->has_one_ref = simple_has_one_ref;
    base->has_at_least_one_ref = simple_has_at_least_one_ref;

    // Set initial ref count
    ensure_ref_map();
    NSValue* key = [NSValue valueWithPointer:base];
    g_refCounts[key] = @1;
}

// MARK: - CEF String Helpers

/// Create a cef_string_t from an NSString
static cef_string_t cef_string_from_nsstring(NSString* str) {
    cef_string_t cefStr = {};
    if (str) {
        const char* utf8 = [str UTF8String];
        cef_string_utf8_to_utf16(utf8, strlen(utf8), &cefStr);
    }
    return cefStr;
}

/// Create an NSString from a cef_string_t
static NSString* nsstring_from_cef_string(const cef_string_t* cefStr) {
    if (!cefStr || !cefStr->str || cefStr->length == 0) {
        return @"";
    }
    cef_string_utf8_t utf8Str = {};
    cef_string_utf16_to_utf8(cefStr->str, cefStr->length, &utf8Str);
    NSString* result = [NSString stringWithUTF8String:utf8Str.str];
    cef_string_utf8_clear(&utf8Str);
    return result ?: @"";
}

// MARK: - Life Span Handler

static cef_life_span_handler_t g_lifeSpanHandler;

static void CEF_CALLBACK on_after_created(cef_life_span_handler_t* self,
                                           cef_browser_t* browser) {
    NSLog(@"[CEF] Browser created");
    g_browser = browser;
    if (browser) {
        cef_addref(&browser->base);
    }
}

static int CEF_CALLBACK do_close(cef_life_span_handler_t* self,
                                  cef_browser_t* browser) {
    NSLog(@"[CEF] Browser closing");
    return 0; // Allow close
}

static void CEF_CALLBACK on_before_close(cef_life_span_handler_t* self,
                                          cef_browser_t* browser) {
    NSLog(@"[CEF] Browser closed");
    if (g_browser) {
        cef_release(&g_browser->base);
        g_browser = NULL;
    }
    g_browserView = nil;

    dispatch_async(dispatch_get_main_queue(), ^{
        id<CEFBridgeDelegate> delegate = g_delegate;
        if ([delegate respondsToSelector:@selector(cefBrowserDidClose)]) {
            [delegate cefBrowserDidClose];
        }
    });
}

static void init_life_span_handler() {
    init_simple_ref(&g_lifeSpanHandler.base, sizeof(cef_life_span_handler_t));
    g_lifeSpanHandler.on_after_created = on_after_created;
    g_lifeSpanHandler.do_close = do_close;
    g_lifeSpanHandler.on_before_close = on_before_close;
    // on_before_popup: NULL (block popups, handle in WebKit)
}

// Forward declarations for window capture (defined after Permission Handler)
static BOOL g_isCapturing = NO;
static void stopWindowCapture(void);

// MARK: - Load Handler

static cef_load_handler_t g_loadHandler;

static void CEF_CALLBACK on_loading_state_change(cef_load_handler_t* self,
                                                   cef_browser_t* browser,
                                                   int isLoading,
                                                   int canGoBack,
                                                   int canGoForward) {
    // Inject getDisplayMedia override on video conference sites
    if (!isLoading && browser) {
        cef_frame_t* frame = browser->get_main_frame(browser);
        if (frame) {
            cef_string_userfree_t frameUrl = frame->get_url(frame);
            if (frameUrl) {
                NSString* urlStr = nsstring_from_cef_string(frameUrl);
                if ([urlStr containsString:@"meet.google.com"] ||
                    [urlStr containsString:@"zoom.us"] ||
                    [urlStr containsString:@"teams.microsoft.com"]) {

                    NSString* js =
                        @"(function(){"
                        "if(window.__maiPickerInstalled)return;"
                        "window.__maiPickerInstalled=true;"
                        "console.log('[MAI] Installing getDisplayMedia override');"
                        "const real=navigator.mediaDevices.getDisplayMedia.bind(navigator.mediaDevices);"
                        "navigator.mediaDevices.getDisplayMedia=async function(c){"
                            "console.log('[MAI] getDisplayMedia intercepted, constraints:', JSON.stringify(c));"
                            "const s=window.prompt('MAI_SCREEN_PICKER');"
                            "console.log('[MAI] Picker result:', s);"
                            "if(!s)throw new DOMException('Permission denied','NotAllowedError');"
                            "if(s==='SCREEN'){"
                                "console.log('[MAI] Calling real getDisplayMedia for screen');"
                                "return real.call(navigator.mediaDevices,c);"
                            "}else if(s==='WINDOW'){"
                                "try{"
                                    "console.log('[MAI] Creating canvas stream for window capture');"
                                    "const cv=document.createElement('canvas');"
                                    "cv.width=1280;cv.height=720;"
                                    "const cx=cv.getContext('2d');"
                                    // Draw initial black frame so stream is never empty
                                    "cx.fillStyle='#000';"
                                    "cx.fillRect(0,0,1280,720);"
                                    "cx.fillStyle='#fff';cx.font='24px sans-serif';"
                                    "cx.fillText('Connecting...',560,360);"
                                    // captureStream(5) = auto-produce frames at 5fps
                                    "const st=cv.captureStream(5);"
                                    "const vt=st.getVideoTracks()[0];"
                                    "console.log('[MAI] Canvas track created, state:', vt.readyState,"
                                        "'settings:', JSON.stringify(vt.getSettings()));"
                                    // Override getSettings to fake displaySurface metadata
                                    "const origGS=vt.getSettings.bind(vt);"
                                    "vt.getSettings=function(){"
                                        "const r=origGS();"
                                        "r.displaySurface='window';"
                                        "r.logicalSurface=true;"
                                        "r.cursor='always';"
                                        "return r;"
                                    "};"
                                    // Add silent audio track (Meet may require audio)
                                    "try{"
                                        "const actx=new AudioContext();"
                                        "const osc=actx.createOscillator();"
                                        "const gn=actx.createGain();"
                                        "gn.gain.value=0;"
                                        "osc.connect(gn);"
                                        "const dest=actx.createMediaStreamDestination();"
                                        "gn.connect(dest);"
                                        "osc.start();"
                                        "st.addTrack(dest.stream.getAudioTracks()[0]);"
                                        "console.log('[MAI] Added silent audio track');"
                                        "vt.addEventListener('ended',function(){"
                                            "actx.close();"
                                        "});"
                                    "}catch(ae){console.warn('[MAI] Audio track failed:',ae);}"
                                    // Frame receiver from native SCStream capture
                                    "window.__maiFrame=function(d){"
                                        "const im=new Image();"
                                        "im.onload=function(){"
                                            "if(cv.width!==im.width||cv.height!==im.height){"
                                                "cv.width=im.width;cv.height=im.height;"
                                            "}"
                                            "cx.drawImage(im,0,0);"
                                        "};"
                                        "im.src='data:image/jpeg;base64,'+d;"
                                    "};"
                                    "vt.addEventListener('ended',function(){"
                                        "console.log('[MAI] Window track ended');"
                                        "delete window.__maiFrame;"
                                        "try{window.prompt('MAI_STOP_CAPTURE');}catch(e){}"
                                    "});"
                                    "console.log('[MAI] Returning stream with',st.getTracks().length,'tracks');"
                                    "return st;"
                                "}catch(e){"
                                    "console.error('[MAI] Window capture JS error:',e);"
                                    "throw e;"
                                "}"
                            "}"
                            "return real.call(navigator.mediaDevices,c);"
                        "};"
                        "})();";

                    cef_string_t script = cef_string_from_nsstring(js);
                    cef_string_t scriptUrl = cef_string_from_nsstring(@"about:blank");
                    frame->execute_java_script(frame, &script, &scriptUrl, 0);
                    cef_string_clear(&script);
                    cef_string_clear(&scriptUrl);
                    cef_log_to_file("Injected getDisplayMedia override on %s",
                                    [urlStr UTF8String]);
                }
                cef_string_userfree_free(frameUrl);
            }
            cef_release(&frame->base);
        }
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        id<CEFBridgeDelegate> delegate = g_delegate;
        if (isLoading) {
            if ([delegate respondsToSelector:@selector(cefBrowserDidStartLoading)]) {
                [delegate cefBrowserDidStartLoading];
            }
        } else {
            if ([delegate respondsToSelector:@selector(cefBrowserDidFinishLoading)]) {
                [delegate cefBrowserDidFinishLoading];
            }
        }
    });
}

static void init_load_handler() {
    init_simple_ref(&g_loadHandler.base, sizeof(cef_load_handler_t));
    g_loadHandler.on_loading_state_change = on_loading_state_change;
}

// MARK: - Display Handler

static cef_display_handler_t g_displayHandler;

static void CEF_CALLBACK on_address_change(cef_display_handler_t* self,
                                             cef_browser_t* browser,
                                             cef_frame_t* frame,
                                             const cef_string_t* url) {
    if (!frame || !frame->is_main(frame)) return;

    NSString* urlStr = nsstring_from_cef_string(url);
    dispatch_async(dispatch_get_main_queue(), ^{
        id<CEFBridgeDelegate> delegate = g_delegate;
        if ([delegate respondsToSelector:@selector(cefBrowserDidUpdateURL:)]) {
            [delegate cefBrowserDidUpdateURL:urlStr];
        }
    });
}

static void CEF_CALLBACK on_title_change(cef_display_handler_t* self,
                                           cef_browser_t* browser,
                                           const cef_string_t* title) {
    NSString* titleStr = nsstring_from_cef_string(title);
    dispatch_async(dispatch_get_main_queue(), ^{
        id<CEFBridgeDelegate> delegate = g_delegate;
        if ([delegate respondsToSelector:@selector(cefBrowserDidUpdateTitle:)]) {
            [delegate cefBrowserDidUpdateTitle:titleStr];
        }
    });
}

static void CEF_CALLBACK on_media_access_change(cef_display_handler_t* self,
                                                  cef_browser_t* browser,
                                                  int has_video_access,
                                                  int has_audio_access) {
    cef_log_to_file("*** MEDIA ACCESS CHANGED *** video=%d, audio=%d",
                    has_video_access, has_audio_access);
    NSLog(@"[CEF] *** MEDIA ACCESS CHANGED *** video=%d, audio=%d",
          has_video_access, has_audio_access);
}

static void init_display_handler() {
    init_simple_ref(&g_displayHandler.base, sizeof(cef_display_handler_t));
    g_displayHandler.on_address_change = on_address_change;
    g_displayHandler.on_title_change = on_title_change;
    g_displayHandler.on_media_access_change = on_media_access_change;
}

// MARK: - Permission Handler (Media Capture)

static cef_permission_handler_t g_permissionHandler;

static int CEF_CALLBACK on_request_media_access_permission(
    cef_permission_handler_t* self,
    cef_browser_t* browser,
    cef_frame_t* frame,
    const cef_string_t* requesting_origin,
    uint32_t requested_permissions,
    cef_media_access_callback_t* callback) {

    NSString* origin = nsstring_from_cef_string(requesting_origin);

    // Decode permission flags for logging
    // CEF_MEDIA_PERMISSION_DEVICE_AUDIO_CAPTURE = 1 << 0
    // CEF_MEDIA_PERMISSION_DEVICE_VIDEO_CAPTURE = 1 << 1
    // CEF_MEDIA_PERMISSION_DESKTOP_AUDIO_CAPTURE = 1 << 2
    // CEF_MEDIA_PERMISSION_DESKTOP_VIDEO_CAPTURE = 1 << 3
    BOOL hasDeviceAudio = (requested_permissions & (1 << 0)) != 0;
    BOOL hasDeviceVideo = (requested_permissions & (1 << 1)) != 0;
    BOOL hasDesktopAudio = (requested_permissions & (1 << 2)) != 0;
    BOOL hasDesktopVideo = (requested_permissions & (1 << 3)) != 0;

    cef_log_to_file("*** MEDIA ACCESS REQUEST ***");
    cef_log_to_file("  Origin: %s", [origin UTF8String]);
    cef_log_to_file("  Raw permissions: 0x%x (%u)", requested_permissions, requested_permissions);
    cef_log_to_file("  Device Audio: %s, Device Video: %s",
          hasDeviceAudio ? "YES" : "NO", hasDeviceVideo ? "YES" : "NO");
    cef_log_to_file("  Desktop Audio: %s, Desktop Video (Screen): %s",
          hasDesktopAudio ? "YES" : "NO", hasDesktopVideo ? "YES" : "NO");
    NSLog(@"[CEF] *** MEDIA ACCESS REQUEST *** perms=0x%x from %@", requested_permissions, origin);

    // Auto-grant all requested permissions for video conferencing
    if (callback) {
        cef_log_to_file("  -> GRANTING all requested permissions: 0x%x", requested_permissions);
        callback->cont(callback, requested_permissions);
    }
    return 1; // Handled
}

/// Called when Chrome-style permission prompt should be shown.
/// With Alloy style, default handling is IGNORE (effectively deny).
/// We auto-accept all permission prompts for video conferencing.
static int CEF_CALLBACK on_show_permission_prompt(
    cef_permission_handler_t* self,
    cef_browser_t* browser,
    uint64_t prompt_id,
    const cef_string_t* requesting_origin,
    uint32_t requested_permissions,
    cef_permission_prompt_callback_t* callback) {

    NSString* origin = nsstring_from_cef_string(requesting_origin);
    cef_log_to_file("*** PERMISSION PROMPT *** id=%llu from %s perms=0x%x",
                    prompt_id, [origin UTF8String], requested_permissions);
    NSLog(@"[CEF] Permission prompt id=%llu from %@ permissions=0x%x - auto-accepting",
          prompt_id, origin, requested_permissions);

    if (callback) {
        cef_log_to_file("  -> ACCEPTING permission prompt %llu", prompt_id);
        callback->cont(callback, CEF_PERMISSION_RESULT_ACCEPT);
    }
    return 1; // Handled
}

static void CEF_CALLBACK on_dismiss_permission_prompt(
    cef_permission_handler_t* self,
    cef_browser_t* browser,
    uint64_t prompt_id,
    cef_permission_request_result_t result) {
    NSLog(@"[CEF] Permission prompt %llu dismissed with result %d", prompt_id, result);
}

static void init_permission_handler() {
    init_simple_ref(&g_permissionHandler.base, sizeof(cef_permission_handler_t));
    g_permissionHandler.on_request_media_access_permission = on_request_media_access_permission;
    g_permissionHandler.on_show_permission_prompt = on_show_permission_prompt;
    g_permissionHandler.on_dismiss_permission_prompt = on_dismiss_permission_prompt;
}

// MARK: - Window Capture (ScreenCaptureKit direct capture for window sharing)

@interface MAICaptureOutput : NSObject <SCStreamOutput>
@end

static SCStream* g_captureStream = nil;
static MAICaptureOutput* g_captureOutput = nil;
static CIContext* g_ciContext = nil;

static void stopWindowCapture(void) {
    if (g_captureStream) {
        g_isCapturing = NO;
        [g_captureStream stopCaptureWithCompletionHandler:^(NSError* error) {
            cef_log_to_file("Window capture stopped");
        }];
        g_captureStream = nil;
    }
    g_isCapturing = NO;
}

static void startWindowCapture(SCWindow* window) {
    stopWindowCapture();

    SCContentFilter* filter = [[SCContentFilter alloc] initWithDesktopIndependentWindow:window];
    SCStreamConfiguration* config = [[SCStreamConfiguration alloc] init];
    config.width = 1280;
    config.height = 720;
    config.minimumFrameInterval = CMTimeMake(1, 5); // 5 fps
    config.pixelFormat = kCVPixelFormatType_32BGRA;
    config.showsCursor = YES;

    g_captureStream = [[SCStream alloc] initWithFilter:filter configuration:config delegate:nil];

    if (!g_captureOutput) {
        g_captureOutput = [[MAICaptureOutput alloc] init];
    }

    NSError* error = nil;
    [g_captureStream addStreamOutput:g_captureOutput
                                type:SCStreamOutputTypeScreen
                   sampleHandlerQueue:dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0)
                               error:&error];
    if (error) {
        cef_log_to_file("Window capture: Failed to add output: %s", [[error description] UTF8String]);
        g_captureStream = nil;
        return;
    }

    g_isCapturing = YES;
    [g_captureStream startCaptureWithCompletionHandler:^(NSError* startError) {
        if (startError) {
            cef_log_to_file("Window capture: Failed to start: %s", [[startError description] UTF8String]);
            g_isCapturing = NO;
        } else {
            cef_log_to_file("Window capture: Started successfully for '%s'",
                            [window.title UTF8String]);
        }
    }];
}

@implementation MAICaptureOutput

- (void)stream:(SCStream *)stream
    didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
                   ofType:(SCStreamOutputType)type {
    if (type != SCStreamOutputTypeScreen) return;
    if (!g_browser || !g_isCapturing) return;

    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (!pixelBuffer) return;

    // Convert to JPEG using reusable CIContext
    if (!g_ciContext) g_ciContext = [CIContext context];
    CIImage* ciImage = [CIImage imageWithCVPixelBuffer:pixelBuffer];
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    NSData* jpegData = [g_ciContext JPEGRepresentationOfImage:ciImage
                                                   colorSpace:cs
                                                      options:@{(id)kCGImageDestinationLossyCompressionQuality: @0.5}];
    CGColorSpaceRelease(cs);
    if (!jpegData) return;

    NSString* base64 = [jpegData base64EncodedStringWithOptions:0];

    // Log first frame and periodic updates
    static int frameCount = 0;
    frameCount++;
    if (frameCount == 1 || frameCount % 25 == 0) {
        cef_log_to_file("Window capture: Frame %d sent, JPEG=%lu bytes, base64=%lu chars",
                        frameCount, (unsigned long)jpegData.length, (unsigned long)base64.length);
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        if (!g_browser || !g_isCapturing) return;

        NSString* js = [NSString stringWithFormat:
            @"window.__maiFrame&&window.__maiFrame('%@')", base64];
        cef_frame_t* frame = g_browser->get_main_frame(g_browser);
        if (frame) {
            cef_string_t script = cef_string_from_nsstring(js);
            cef_string_t url = cef_string_from_nsstring(@"about:blank");
            frame->execute_java_script(frame, &script, &url, 0);
            cef_string_clear(&script);
            cef_string_clear(&url);
            cef_release(&frame->base);
        }
    });
}

@end

// MARK: - JSDialog Handler (Screen/Window Picker)

static cef_jsdialog_handler_t g_jsdialogHandler;

// Store enumerated windows for lookup after user selection
static NSArray<SCWindow*>* g_enumeratedWindows = nil;

static int CEF_CALLBACK on_jsdialog(
    cef_jsdialog_handler_t* self,
    cef_browser_t* browser,
    const cef_string_t* origin_url,
    cef_jsdialog_type_t dialog_type,
    const cef_string_t* message_text,
    const cef_string_t* default_prompt_text,
    cef_jsdialog_callback_t* callback,
    int* suppress_message) {

    if (dialog_type != JSDIALOGTYPE_PROMPT) return 0;

    NSString* message = nsstring_from_cef_string(message_text);

    // Handle stop capture signal
    if ([message isEqualToString:@"MAI_STOP_CAPTURE"]) {
        stopWindowCapture();
        cef_string_t empty = {};
        callback->cont(callback, 1, &empty);
        return 1;
    }

    if (![message isEqualToString:@"MAI_SCREEN_PICKER"]) return 0;

    cef_log_to_file("Screen picker: Intercepted MAI_SCREEN_PICKER prompt");
    cef_addref(&callback->base);

    [SCShareableContent getShareableContentExcludingDesktopWindows:NO
                                             onScreenWindowsOnly:YES
                                               completionHandler:^(SCShareableContent* content, NSError* error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error || !content) {
                cef_log_to_file("Screen picker: SCShareableContent error: %s",
                                error ? [[error description] UTF8String] : "nil content");
                cef_string_t empty = {};
                callback->cont(callback, 0, &empty);
                cef_release(&callback->base);
                return;
            }

            NSMutableArray<NSString*>* displayNames = [NSMutableArray array];
            // Track type: "S" for screen, "W:idx" for window
            NSMutableArray<NSString*>* sourceTypes = [NSMutableArray array];

            // Add screens
            NSArray<SCDisplay*>* displays = content.displays;
            if (displays.count == 1) {
                [displayNames addObject:@"\xF0\x9F\x96\xA5 Entire screen"];
                [sourceTypes addObject:@"S"];
            } else {
                for (NSUInteger i = 0; i < displays.count; i++) {
                    [displayNames addObject:[NSString stringWithFormat:
                        @"\xF0\x9F\x96\xA5 Screen %lu", (unsigned long)(i + 1)]];
                    [sourceTypes addObject:@"S"];
                }
            }

            // Filter and store windows
            NSMutableArray<SCWindow*>* filteredWindows = [NSMutableArray array];
            NSString* myAppName = [[NSProcessInfo processInfo] processName];
            for (SCWindow* window in content.windows) {
                if (!window.title || window.title.length == 0) continue;
                if (window.owningApplication &&
                    [window.owningApplication.applicationName isEqualToString:myAppName]) continue;
                if (window.frame.size.width < 100 || window.frame.size.height < 100) continue;

                NSString* appName = window.owningApplication.applicationName ?: @"Unknown";
                [displayNames addObject:[NSString stringWithFormat:
                    @"\xF0\x9F\xAA\x9F %@ - %@", appName, window.title]];
                [sourceTypes addObject:[NSString stringWithFormat:
                    @"W:%lu", (unsigned long)filteredWindows.count]];
                [filteredWindows addObject:window];
            }

            g_enumeratedWindows = [filteredWindows copy];

            if (displayNames.count == 0) {
                cef_string_t empty = {};
                callback->cont(callback, 0, &empty);
                cef_release(&callback->base);
                return;
            }

            cef_log_to_file("Screen picker: Found %lu screens + %lu windows",
                            (unsigned long)displays.count,
                            (unsigned long)filteredWindows.count);

            NSAlert* alert = [[NSAlert alloc] init];
            alert.messageText = @"Share your screen";
            alert.informativeText = @"Choose what to share:";
            [alert addButtonWithTitle:@"Share"];
            [alert addButtonWithTitle:@"Cancel"];

            NSPopUpButton* popup = [[NSPopUpButton alloc]
                                    initWithFrame:NSMakeRect(0, 0, 350, 28)];
            for (NSString* name in displayNames) {
                [popup addItemWithTitle:name];
            }
            alert.accessoryView = popup;

            NSModalResponse response = [alert runModal];

            if (response == NSAlertFirstButtonReturn) {
                NSInteger idx = popup.indexOfSelectedItem;
                NSString* type = sourceTypes[idx];

                if ([type isEqualToString:@"S"]) {
                    // Screen selected → JS will call real getDisplayMedia (auto-select handles it)
                    cef_log_to_file("Screen picker: User selected screen");
                    cef_string_t result = cef_string_from_nsstring(@"SCREEN");
                    callback->cont(callback, 1, &result);
                    cef_string_clear(&result);
                } else if ([type hasPrefix:@"W:"]) {
                    // Window selected → start native capture
                    NSInteger winIdx = [[type substringFromIndex:2] integerValue];
                    SCWindow* selectedWindow = g_enumeratedWindows[winIdx];
                    cef_log_to_file("Screen picker: User selected window '%s'",
                                    [selectedWindow.title UTF8String]);
                    startWindowCapture(selectedWindow);
                    cef_string_t result = cef_string_from_nsstring(@"WINDOW");
                    callback->cont(callback, 1, &result);
                    cef_string_clear(&result);
                }
            } else {
                cef_log_to_file("Screen picker: User cancelled");
                cef_string_t empty = {};
                callback->cont(callback, 0, &empty);
            }

            g_enumeratedWindows = nil;
            cef_release(&callback->base);
        });
    }];

    return 1;
}

static void init_jsdialog_handler() {
    init_simple_ref(&g_jsdialogHandler.base, sizeof(cef_jsdialog_handler_t));
    g_jsdialogHandler.on_jsdialog = on_jsdialog;
}

static cef_jsdialog_handler_t* CEF_CALLBACK get_jsdialog_handler(cef_client_t* self) {
    simple_add_ref(&g_jsdialogHandler.base);
    return &g_jsdialogHandler;
}

// MARK: - Client Handler

static cef_client_t g_client;

static cef_life_span_handler_t* CEF_CALLBACK get_life_span_handler(cef_client_t* self) {
    simple_add_ref(&g_lifeSpanHandler.base);
    return &g_lifeSpanHandler;
}

static cef_load_handler_t* CEF_CALLBACK get_load_handler(cef_client_t* self) {
    simple_add_ref(&g_loadHandler.base);
    return &g_loadHandler;
}

static cef_display_handler_t* CEF_CALLBACK get_display_handler(cef_client_t* self) {
    simple_add_ref(&g_displayHandler.base);
    return &g_displayHandler;
}

static cef_permission_handler_t* CEF_CALLBACK get_permission_handler(cef_client_t* self) {
    simple_add_ref(&g_permissionHandler.base);
    return &g_permissionHandler;
}

static void init_client() {
    init_simple_ref(&g_client.base, sizeof(cef_client_t));
    g_client.get_life_span_handler = get_life_span_handler;
    g_client.get_load_handler = get_load_handler;
    g_client.get_display_handler = get_display_handler;
    g_client.get_permission_handler = get_permission_handler;
    g_client.get_jsdialog_handler = get_jsdialog_handler;
}

// MARK: - Browser Process Handler
// Required when using external_message_pump = 1.
// CEF calls on_schedule_message_pump_work to tell us when to process messages.

static cef_browser_process_handler_t g_browserProcessHandler;

static void CEF_CALLBACK on_context_initialized(
    cef_browser_process_handler_t* self) {
    NSLog(@"[CEF] Context initialized - CEF is fully ready");
}

static void CEF_CALLBACK on_before_child_process_launch(
    cef_browser_process_handler_t* self,
    cef_command_line_t* command_line) {
    if (!command_line) return;

    // Log the subprocess being launched for debugging
    cef_string_userfree_t cmdStr = command_line->get_command_line_string(command_line);
    if (cmdStr) {
        NSString* cmd = nsstring_from_cef_string(cmdStr);
        NSLog(@"[CEF] Launching child process: %@", [cmd substringToIndex:MIN(cmd.length, 200)]);
        cef_string_userfree_free(cmdStr);
    }
}

/// Called from ANY thread when CEF needs message pump work.
/// This is the critical callback for external_message_pump integration.
/// Without this, CEF can't schedule time-critical work like IPC setup.
static void CEF_CALLBACK on_schedule_message_pump_work(
    cef_browser_process_handler_t* self,
    int64_t delay_ms) {

    if (!g_cefInitialized) return;

    if (delay_ms <= 0) {
        // Work needed ASAP - dispatch immediately to main thread
        dispatch_async(dispatch_get_main_queue(), ^{
            if (g_cefInitialized) {
                cef_do_message_loop_work();
            }
        });
    } else {
        // Schedule delayed work, replacing any pending scheduled call
        dispatch_after(
            dispatch_time(DISPATCH_TIME_NOW, delay_ms * NSEC_PER_MSEC),
            dispatch_get_main_queue(),
            ^{
                if (g_cefInitialized) {
                    cef_do_message_loop_work();
                }
            });
    }
}

static void init_browser_process_handler() {
    init_simple_ref(&g_browserProcessHandler.base,
                    sizeof(cef_browser_process_handler_t));
    g_browserProcessHandler.on_context_initialized = on_context_initialized;
    g_browserProcessHandler.on_before_child_process_launch = on_before_child_process_launch;
    g_browserProcessHandler.on_schedule_message_pump_work = on_schedule_message_pump_work;
}

// MARK: - App Handler

static cef_app_t g_app;

static void CEF_CALLBACK on_before_command_line_processing(
    cef_app_t* self,
    const cef_string_t* process_type,
    cef_command_line_t* command_line) {

    if (!command_line) return;

    // Auto-select "Entire screen" for screen sharing via getDisplayMedia().
    // In embedded CEF mode, Chrome can't show its own picker UI.
    // Our custom JS picker handles source selection; this flag ensures
    // screen capture works when the user selects a screen option.
    cef_string_t autoSelName = cef_string_from_nsstring(@"auto-select-desktop-capture-source");
    cef_string_t autoSelVal = cef_string_from_nsstring(@"Entire screen");
    command_line->append_switch_with_value(command_line, &autoSelName, &autoSelVal);
    cef_string_clear(&autoSelName);
    cef_string_clear(&autoSelVal);

    // Enable ScreenCaptureKit (macOS 14+) for native system picker.
    // The macOS system picker (SCContentSharingPicker) shows Screens, Windows, and Apps
    // without requiring Chrome's Views-based DesktopMediaPickerViews dialog,
    // which doesn't work properly in embedded non-Views CEF windows.
    cef_string_t enableFeaturesName = cef_string_from_nsstring(@"enable-features");
    cef_string_t enableFeaturesVal = cef_string_from_nsstring(
        @"UseSCContentSharingPicker,ScreenCaptureKitStreamPickerSonoma,"
        @"ScreenCaptureKitPickerScreen,ScreenCaptureKitMacScreen");
    command_line->append_switch_with_value(command_line, &enableFeaturesName, &enableFeaturesVal);
    cef_string_clear(&enableFeaturesName);
    cef_string_clear(&enableFeaturesVal);

    // Disable GPU sandbox for macOS compatibility
    cef_string_t flag4 = cef_string_from_nsstring(@"disable-gpu-sandbox");
    command_line->append_switch(command_line, &flag4);
    cef_string_clear(&flag4);

    // Use mock keychain to avoid macOS Keychain password prompts
    cef_string_t flag5 = cef_string_from_nsstring(@"use-mock-keychain");
    command_line->append_switch(command_line, &flag5);
    cef_string_clear(&flag5);

    // Disable Chrome-specific features that can crash in embedded CEF context
    cef_string_t flag6name = cef_string_from_nsstring(@"disable-features");
    cef_string_t flag6val = cef_string_from_nsstring(
        @"MediaRouter,PwaNavigationCapturing,WebAppInstallation,"
        @"WebAppSystemMediaControls,DesktopPWAsAdditionalWindowingControls,"
        @"ChromeWebAppShortcutCopier,BackForwardCache");
    command_line->append_switch_with_value(command_line, &flag6name, &flag6val);
    cef_string_clear(&flag6name);
    cef_string_clear(&flag6val);

    // Disable extensions (not needed for video conferencing)
    cef_string_t flag7 = cef_string_from_nsstring(@"disable-extensions");
    command_line->append_switch(command_line, &flag7);
    cef_string_clear(&flag7);

    // Log the full command line for debugging
    cef_string_userfree_t fullCmd = command_line->get_command_line_string(command_line);
    if (fullCmd) {
        NSString* cmdStr = nsstring_from_cef_string(fullCmd);
        cef_log_to_file("COMMAND LINE: %s", [cmdStr UTF8String]);
        NSLog(@"[CEF] Command line: %@", cmdStr);
        cef_string_userfree_free(fullCmd);
    }
}

static cef_browser_process_handler_t* CEF_CALLBACK get_browser_process_handler(
    cef_app_t* self) {
    simple_add_ref(&g_browserProcessHandler.base);
    return &g_browserProcessHandler;
}

static void init_app() {
    init_simple_ref(&g_app.base, sizeof(cef_app_t));
    g_app.on_before_command_line_processing = on_before_command_line_processing;
    g_app.get_browser_process_handler = get_browser_process_handler;
}

// MARK: - Message Pump (fallback timer)
// The primary pump is driven by on_schedule_message_pump_work callback.
// This fallback timer ensures work is processed even if callbacks are missed.

static void startMessagePump() {
    if (g_messagePumpTimer) return;

    // Fallback timer at 30Hz - the on_schedule_message_pump_work callback
    // handles the real-time scheduling, this is just a safety net.
    g_messagePumpTimer = [NSTimer scheduledTimerWithTimeInterval:1.0/30.0
                                                         repeats:YES
                                                           block:^(NSTimer* timer) {
        if (g_cefInitialized) {
            cef_do_message_loop_work();
        }
    }];
    // Ensure timer fires during UI tracking (e.g., window dragging)
    [[NSRunLoop mainRunLoop] addTimer:g_messagePumpTimer
                              forMode:NSRunLoopCommonModes];
}

static void stopMessagePump() {
    [g_messagePumpTimer invalidate];
    g_messagePumpTimer = nil;
}

// MARK: - CEFBridge Implementation

@implementation CEFBridge

+ (BOOL)isInitialized {
    return g_cefInitialized;
}

+ (BOOL)hasBrowser {
    return g_browser != NULL;
}

+ (void)setDelegate:(id<CEFBridgeDelegate>)delegate {
    g_delegate = delegate;
}

+ (id<CEFBridgeDelegate>)delegate {
    return g_delegate;
}

+ (BOOL)initializeCEF {
    if (g_cefInitialized) return YES;

    NSLog(@"[CEF] Initializing Chromium Embedded Framework...");

    // Step 1: Dynamically load the CEF framework library (REQUIRED on macOS)
    // Direct linking causes crashes because Chromium's initialization code runs
    // before the API version is configured.
    static void* g_libraryLoader = NULL;
    if (!g_libraryLoader) {
        NSString* frameworksPath = [[NSBundle mainBundle] privateFrameworksPath];
        NSString* cefLibPath = [frameworksPath stringByAppendingPathComponent:
                                @"Chromium Embedded Framework.framework/Chromium Embedded Framework"];
        NSLog(@"[CEF] Loading framework from: %@", cefLibPath);

        if (!cef_load_library([cefLibPath UTF8String])) {
            NSLog(@"[CEF] ERROR: Failed to load CEF framework library");
            return NO;
        }
        NSLog(@"[CEF] Framework library loaded successfully");
    }

    // Step 2: Configure API version (REQUIRED for CEF 133+)
    const char* apiHash = cef_api_hash(CEF_API_VERSION, 0);
    NSLog(@"[CEF] API version: %d, hash: %s", CEF_API_VERSION, apiHash ? apiHash : "NULL");

    // Step 3: Initialize handlers
    init_life_span_handler();
    init_load_handler();
    init_display_handler();
    init_permission_handler();
    init_jsdialog_handler();
    init_client();
    init_browser_process_handler();
    init_app();

    // Step 4: Configure CEF settings
    cef_settings_t settings = {};
    settings.size = sizeof(cef_settings_t);
    settings.no_sandbox = 1;
    settings.external_message_pump = 1;  // We drive the message pump via NSTimer
    settings.multi_threaded_message_loop = 0;
    settings.windowless_rendering_enabled = 0;

    // Set log severity to INFO for debugging screen capture
    settings.log_severity = LOGSEVERITY_INFO;

    // Write CEF logs to a file for debugging
    NSString* logPath = @"/tmp/cef_debug.log";
    cef_string_t logFile = cef_string_from_nsstring(logPath);
    cef_string_set(logFile.str, logFile.length, &settings.log_file, 1);
    cef_string_clear(&logFile);

    // Set paths
    NSString* frameworkPath = [[NSBundle mainBundle] privateFrameworksPath];
    NSString* cefFrameworkPath = [frameworkPath stringByAppendingPathComponent:
                                  @"Chromium Embedded Framework.framework"];

    // Framework directory
    cef_string_t fwDir = cef_string_from_nsstring(cefFrameworkPath);
    cef_string_set(fwDir.str, fwDir.length, &settings.framework_dir_path, 1);
    cef_string_clear(&fwDir);

    // Main bundle path (for helper process resolution)
    NSString* mainBundlePath = [[NSBundle mainBundle] bundlePath];
    cef_string_t mbPath = cef_string_from_nsstring(mainBundlePath);
    cef_string_set(mbPath.str, mbPath.length, &settings.main_bundle_path, 1);
    cef_string_clear(&mbPath);

    // Browser subprocess path (MAI Helper)
    NSString* helperPath = [frameworkPath stringByAppendingPathComponent:
                            @"MAI Helper.app/Contents/MacOS/MAI Helper"];
    cef_string_t bsPath = cef_string_from_nsstring(helperPath);
    cef_string_set(bsPath.str, bsPath.length, &settings.browser_subprocess_path, 1);
    cef_string_clear(&bsPath);

    // Cache path
    NSString* cachePath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"MAI_CEF_Cache"];
    [[NSFileManager defaultManager] createDirectoryAtPath:cachePath
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    cef_string_t cPath = cef_string_from_nsstring(cachePath);
    cef_string_set(cPath.str, cPath.length, &settings.root_cache_path, 1);
    cef_string_clear(&cPath);

    // User agent (Chrome-like for maximum compatibility)
    NSString* userAgent = @"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                          @"AppleWebKit/537.36 (KHTML, like Gecko) "
                          @"Chrome/145.0.0.0 Safari/537.36";
    cef_string_t ua = cef_string_from_nsstring(userAgent);
    cef_string_set(ua.str, ua.length, &settings.user_agent, 1);
    cef_string_clear(&ua);

    // Step 5: Build main args from real process arguments
    NSArray<NSString *>* arguments = [[NSProcessInfo processInfo] arguments];
    int argc = (int)arguments.count;
    char** argv = (char**)malloc(sizeof(char*) * (argc + 1));
    for (int i = 0; i < argc; i++) {
        argv[i] = strdup([arguments[i] UTF8String]);
    }
    argv[argc] = NULL;

    cef_main_args_t mainArgs = {};
    mainArgs.argc = argc;
    mainArgs.argv = argv;

    // Step 6: Initialize CEF (no cef_execute_process needed - we use separate helper)
    int result = cef_initialize(&mainArgs, &settings, &g_app, NULL);

    // Clean up argv
    for (int i = 0; i < argc; i++) free(argv[i]);
    free(argv);

    if (result) {
        g_cefInitialized = YES;
        startMessagePump();
        NSLog(@"[CEF] Initialization successful");
    } else {
        NSLog(@"[CEF] ERROR: Initialization failed (code: %d)", cef_get_exit_code());
    }

    return result ? YES : NO;
}

+ (void)shutdownCEF {
    if (!g_cefInitialized) return;

    NSLog(@"[CEF] Shutting down...");

    // Stop any active window capture
    stopWindowCapture();

    // Close browser first
    [self closeBrowser];

    // Stop message pump
    stopMessagePump();

    // Shutdown CEF
    cef_shutdown();
    g_cefInitialized = NO;

    // Unload the CEF framework library
    cef_unload_library();

    NSLog(@"[CEF] Shutdown complete");
}

+ (NSView *)createBrowserViewWithURL:(NSString *)url frame:(NSRect)frame {
    if (!g_cefInitialized) {
        NSLog(@"[CEF] ERROR: CEF not initialized, call initializeCEF first");
        return nil;
    }

    // Close existing browser if any
    if (g_browser) {
        [self closeBrowser];
    }

    NSLog(@"[CEF] Creating browser view for: %@", url);

    // Create host view
    NSView* hostView = [[NSView alloc] initWithFrame:frame];
    hostView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    hostView.wantsLayer = YES;

    // Window info for embedding in our view
    cef_window_info_t windowInfo = {};
    windowInfo.size = sizeof(cef_window_info_t);
    windowInfo.parent_view = (__bridge void*)hostView;
    windowInfo.bounds.x = (int)frame.origin.x;
    windowInfo.bounds.y = (int)frame.origin.y;
    windowInfo.bounds.width = (int)frame.size.width;
    windowInfo.bounds.height = (int)frame.size.height;
    // Use Chrome runtime style - required for getDisplayMedia() screen sharing.
    // Alloy style lacks the DesktopMediaPicker, so getDisplayMedia() fails silently.
    // Chrome style provides the built-in desktop media picker UI.
    // With parent_view set, Chrome renders content-only (no address bar/tabs).
    windowInfo.runtime_style = CEF_RUNTIME_STYLE_DEFAULT;

    // Browser settings
    cef_browser_settings_t browserSettings = {};
    browserSettings.size = sizeof(cef_browser_settings_t);

    // Enable WebRTC for video conferencing
    browserSettings.webgl = STATE_ENABLED;

    // URL
    cef_string_t cefURL = cef_string_from_nsstring(url);

    // Add ref to client before passing to create_browser
    simple_add_ref(&g_client.base);

    // Create browser synchronously
    g_browser = cef_browser_host_create_browser_sync(
        &windowInfo,
        &g_client,
        &cefURL,
        &browserSettings,
        NULL,  // extra_info
        NULL   // request_context (use default)
    );

    cef_string_clear(&cefURL);

    if (g_browser) {
        g_browserView = hostView;
        NSLog(@"[CEF] Browser created successfully");
    } else {
        NSLog(@"[CEF] ERROR: Failed to create browser");
        return nil;
    }

    return hostView;
}

+ (void)loadURL:(NSString *)url {
    if (!g_browser) return;

    cef_frame_t* mainFrame = g_browser->get_main_frame(g_browser);
    if (mainFrame) {
        cef_string_t cefURL = cef_string_from_nsstring(url);
        mainFrame->load_url(mainFrame, &cefURL);
        cef_string_clear(&cefURL);
        cef_release(&mainFrame->base);
    }
}

+ (void)closeBrowser {
    if (!g_browser) return;

    NSLog(@"[CEF] Closing browser");

    cef_browser_host_t* host = g_browser->get_host(g_browser);
    if (host) {
        host->close_browser(host, 1); // force_close = true
        cef_release(&host->base);
    }

    // Browser will be set to NULL in on_before_close callback
}

+ (void)executeJavaScript:(NSString *)script {
    if (!g_browser) return;

    cef_frame_t* mainFrame = g_browser->get_main_frame(g_browser);
    if (mainFrame) {
        cef_string_t cefScript = cef_string_from_nsstring(script);
        cef_string_t cefURL = cef_string_from_nsstring(@"about:blank");
        mainFrame->execute_java_script(mainFrame, &cefScript, &cefURL, 0);
        cef_string_clear(&cefScript);
        cef_string_clear(&cefURL);
        cef_release(&mainFrame->base);
    }
}

+ (NSString *)currentURL {
    if (!g_cefInitialized || !g_browser) return nil;

    cef_frame_t* mainFrame = g_browser->get_main_frame(g_browser);
    if (!mainFrame) return nil;

    cef_string_userfree_t url = mainFrame->get_url(mainFrame);
    NSString* result = nil;
    if (url) {
        result = nsstring_from_cef_string(url);
        cef_string_userfree_free(url);
    }
    cef_release(&mainFrame->base);

    return result;
}

+ (NSString *)currentTitle {
    if (!g_browser) return nil;

    cef_browser_host_t* host = g_browser->get_host(g_browser);
    if (!host) return nil;

    // Title comes from display handler callback, not from browser directly
    cef_release(&host->base);
    return nil; // Title is tracked via delegate callbacks
}

@end
