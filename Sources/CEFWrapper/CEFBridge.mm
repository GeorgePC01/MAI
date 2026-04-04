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
#include "include/capi/cef_resource_request_handler_capi.h"
#include "include/capi/cef_browser_process_handler_capi.h"
#include "include/capi/cef_jsdialog_handler_capi.h"
#include "include/capi/cef_request_context_capi.h"
// NOTE: Views framework headers removed — Views is incompatible with
// external_message_pump=1 on macOS (requires MessagePumpNSApplication).
#include "include/capi/cef_devtools_message_observer_capi.h"
#include "include/cef_api_hash.h"
#include "include/wrapper/cef_library_loader.h"

#import <ScreenCaptureKit/ScreenCaptureKit.h>
#import <CoreImage/CoreImage.h>

#include <atomic>
#include <stdio.h>
#include <cxxabi.h>
#include <exception>
#include <setjmp.h>
#include <signal.h>

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

// Standalone mode: Teams in its own NSWindow (still Alloy-style, but separate window)
static BOOL g_isStandaloneMode = NO;
static NSWindow* g_standaloneNSWindow = nil;

// CDP (Chrome DevTools Protocol) state
static cef_registration_t* g_cdpRegistration = NULL;
static __weak id<CEFBridgeCDPDelegate> g_cdpDelegate = nil;
static int g_cdpMessageId = 0;

// Browser generation counter — incremented on each browser creation/release.
// Dispatch blocks from on_schedule_message_pump_work capture this value
// and skip execution if it no longer matches (stale blocks from old browser).
static int g_browserGeneration = 0;

// Forward declarations
static void stopMessagePump(void);
static void startMessagePump(void);
static void safe_do_message_loop_work(void);
static void enumerate_cookies_for_url(const char* label);

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
    NSLog(@"[CEF] Browser closed (standalone=%d)", g_isStandaloneMode);
    // Only clear g_browser if it matches the closing browser.
    // If a new browser was already created (e.g., window switch), g_browser
    // points to the NEW browser and we must NOT release it here.
    BOOL wasCurrentBrowser = NO;
    if (g_browser) {
        int closingId = browser->get_identifier(browser);
        int currentId = g_browser->get_identifier(g_browser);
        if (closingId == currentId) {
            cef_release(&g_browser->base);
            g_browser = NULL;
            g_browserView = nil;
            wasCurrentBrowser = YES;
        } else {
            NSLog(@"[CEF] on_before_close: skipping (closing=%d, current=%d)", closingId, currentId);
        }
    } else {
        // g_browser already NULL (e.g., forceReleaseBrowser was called)
        wasCurrentBrowser = YES;
    }

    // Close standalone NSWindow if present
    if (g_isStandaloneMode && g_standaloneNSWindow) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [g_standaloneNSWindow close];
            g_standaloneNSWindow = nil;
        });
        g_isStandaloneMode = NO;
    }

    // Only stop message pump if the CURRENT browser closed.
    // If a stale browser is closing while a new one is active, the new browser
    // still needs the message pump running.
    if (wasCurrentBrowser) {
        stopMessagePump();

        dispatch_async(dispatch_get_main_queue(), ^{
            id<CEFBridgeDelegate> delegate = g_delegate;
            if ([delegate respondsToSelector:@selector(cefBrowserDidClose)]) {
                [delegate cefBrowserDidClose];
            }
        });
    }
}

/// Handle popup requests — Microsoft auth (MFA) requires popups that share cookies.
/// Instead of opening a new window, navigate the current browser to the popup URL.
/// This keeps the contextID cookie in the same browser context.
static int CEF_CALLBACK on_before_popup(
    cef_life_span_handler_t* self,
    cef_browser_t* browser,
    cef_frame_t* frame,
    int popup_id,
    const cef_string_t* target_url,
    const cef_string_t* target_frame_name,
    cef_window_open_disposition_t target_disposition,
    int user_gesture,
    const cef_popup_features_t* popupFeatures,
    cef_window_info_t* windowInfo,
    cef_client_t** client,
    cef_browser_settings_t* settings,
    cef_dictionary_value_t** extra_info,
    int* no_javascript_access) {

    NSString* url = target_url ? nsstring_from_cef_string(target_url) : @"";
    NSLog(@"[CEF] on_before_popup: %@", url);
    cef_log_to_file("POPUP request: %s", [url UTF8String]);

    // Allow Microsoft auth popups by navigating in the same browser window.
    // This preserves the contextID cookie that MFA sets during the auth flow.
    if ([url containsString:@"login.microsoftonline.com"] ||
        [url containsString:@"login.live.com"] ||
        [url containsString:@"login.microsoft.com"] ||
        [url containsString:@"accounts.google.com"] ||
        [url containsString:@"appleid.apple.com"]) {

        cef_log_to_file("POPUP -> navigating in same browser (auth URL): %s", [url UTF8String]);
        // Navigate main frame to the popup URL instead of opening new window
        if (browser) {
            cef_frame_t* mainFrame = browser->get_main_frame(browser);
            if (mainFrame) {
                cef_string_t cefURL = cef_string_from_nsstring(url);
                mainFrame->load_url(mainFrame, &cefURL);
                cef_string_clear(&cefURL);
                cef_release(&mainFrame->base);
            }
        }
        return 1; // Cancel popup (we navigated instead)
    }

    // Block all other popups (ads, etc.)
    cef_log_to_file("POPUP -> blocked (non-auth URL): %s", [url UTF8String]);
    return 1;
}

static void init_life_span_handler() {
    init_simple_ref(&g_lifeSpanHandler.base, sizeof(cef_life_span_handler_t));
    g_lifeSpanHandler.on_after_created = on_after_created;
    g_lifeSpanHandler.do_close = do_close;
    g_lifeSpanHandler.on_before_close = on_before_close;
    g_lifeSpanHandler.on_before_popup = on_before_popup;
}

// Forward declarations for window capture (defined after Permission Handler)
static BOOL g_isCapturing = NO;
static BOOL g_framePending = NO;
static float g_jpegQuality = 0.92;
static float g_jpegQualityMax = 0.95;
static float g_jpegQualityMin = 0.80;
static float g_jpegQualityStepDown = 0.03;
static float g_jpegQualityStepUp = 0.01;
static void stopWindowCapture(void);

// MARK: - Load Handler

static cef_load_handler_t g_loadHandler;

// Google passive login loop detector
static int g_googlePassiveCount = 0;
static NSTimeInterval g_googlePassiveFirstTime = 0;


static void CEF_CALLBACK on_loading_state_change(cef_load_handler_t* self,
                                                   cef_browser_t* browser,
                                                   int isLoading,
                                                   int canGoBack,
                                                   int canGoForward) {
    // Re-enabled for diagnostic logging only
    if (!isLoading && browser) {
        cef_frame_t* frame = browser->get_main_frame(browser);
        if (frame) {
            cef_string_userfree_t frameUrl = frame->get_url(frame);
            if (frameUrl) {
                NSString* urlStr = nsstring_from_cef_string(frameUrl);

                // FIX: Google passive login loop breaker.
                // When Meet redirects to accounts.google.com?passive=true,
                // Google checks for a valid session. If session is missing/invalid,
                // instead of showing the login form, the page loops every ~1s.
                // Detect 3+ loads within 10s and strip passive=true to force the form.
                if ([urlStr containsString:@"accounts.google.com"] &&
                    [urlStr containsString:@"passive=true"]) {
                    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
                    if (now - g_googlePassiveFirstTime > 10.0) {
                        // Reset counter if >10s since first detection
                        g_googlePassiveCount = 0;
                        g_googlePassiveFirstTime = now;
                    }
                    g_googlePassiveCount++;
                    cef_log_to_file("Google passive login: attempt %d", g_googlePassiveCount);

                    if (g_googlePassiveCount >= 3) {
                        g_googlePassiveCount = 0;
                        // Strip passive=true and sacu=1 to show actual login form
                        NSString* fixedUrl = [urlStr stringByReplacingOccurrencesOfString:@"passive=true"
                                                                              withString:@"passive=false"];
                        fixedUrl = [fixedUrl stringByReplacingOccurrencesOfString:@"&sacu=1"
                                                                      withString:@""];
                        cef_log_to_file("Google passive loop BROKEN — forcing login form");
                        cef_string_t navUrl = cef_string_from_nsstring(fixedUrl);
                        frame->load_url(frame, &navUrl);
                        cef_string_clear(&navUrl);
                        cef_string_userfree_free(frameUrl);
                        cef_release(&frame->base);
                        return; // Don't process further
                    }
                } else if (![urlStr containsString:@"accounts.google.com"]) {
                    g_googlePassiveCount = 0; // Reset when navigating away
                }

                // Match video conference HOSTNAMES only — not query params!
                // login.live.com URLs contain "teams.microsoft.com" in the
                // redirect_uri parameter, so containsString would incorrectly
                // inject WebRTC patches on login pages, breaking authentication.
                BOOL isVideoConferenceSite =
                    [urlStr hasPrefix:@"https://meet.google.com"] ||
                    [urlStr hasPrefix:@"https://zoom.us"] ||
                    [urlStr hasPrefix:@"https://teams.microsoft.com"] ||
                    [urlStr hasPrefix:@"https://teams.live.com"] ||
                    [urlStr hasPrefix:@"https://teams.cloud.microsoft"];
                if (isVideoConferenceSite) {

                    // Common JS: error handlers, codec diagnostics, H.264 SDP removal,
                    // and WebRTC interceptors for logging.
                    // In standalone Chrome-style mode: NO getDisplayMedia override
                    // (Chrome's native DesktopMediaPicker works).
                    // In embedded Alloy mode: getDisplayMedia override with native
                    // picker + getUserMedia fallback.
                    NSMutableString* js = [NSMutableString stringWithString:
                        @"(function(){"
                        "if(window.__maiPickerInstalled)return;"
                        "window.__maiPickerInstalled=true;"
                        "console.log('[MAI] Installing WebRTC patches (standalone=%s)'.replace('%s',"];

                    // Inject standalone mode flag as JS boolean
                    [js appendFormat:@"'%@'));", g_isStandaloneMode ? @"true" : @"false"];

                    [js appendString:
                        // Global error catcher with stack traces
                        @"if(!window.__maiErrorHandler){"
                            "window.__maiErrorHandler=true;"
                            "window.addEventListener('unhandledrejection',function(e){"
                                "const r=e.reason;"
                                "if(r&&r.stack)console.log('[MAI] UNHANDLED REJECTION:',r.message,'\\n'+r.stack);"
                            "});"
                            "window.addEventListener('error',function(e){"
                                "if(e.error&&e.error.stack)console.log('[MAI] GLOBAL ERROR:',e.error.message,'\\n'+e.error.stack);"
                            "});"
                        "}"

                        // === SPOOF 2: navigator.permissions.query for display-capture ===
                        // CEF Alloy may return 'denied' for display-capture permission.
                        // Teams checks this before calling getDisplayMedia.
                        "if(!window.__maiPermSpoofed){"
                            "window.__maiPermSpoofed=true;"
                            "const origQuery=navigator.permissions.query.bind(navigator.permissions);"
                            "navigator.permissions.query=function(desc){"
                                "console.log('[MAI] permissions.query:', JSON.stringify(desc));"
                                "if(desc&&desc.name==='display-capture'){"
                                    "console.log('[MAI] Spoofing display-capture permission to prompt');"
                                    "return Promise.resolve({state:'prompt',name:'display-capture',onchange:null});"
                                "}"
                                "return origQuery(desc);"
                            "};"
                            "console.log('[MAI] Permission spoofing installed');"
                        "}"

                        // === SPOOF 3: MediaStreamTrack.getSettings displaySurface ===
                        // Teams may check for displaySurface property in track settings.
                        "if(!window.__maiTrackSpoofed){"
                            "window.__maiTrackSpoofed=true;"
                            "const origGetSettings=MediaStreamTrack.prototype.getSettings;"
                            "MediaStreamTrack.prototype.getSettings=function(){"
                                "const s=origGetSettings.call(this);"
                                "if(this.kind==='video'&&this.label&&this.label.includes('Screen')&&!s.displaySurface){"
                                    "s.displaySurface='monitor';"
                                    "s.cursor='always';"
                                    "console.log('[MAI] Added displaySurface to track settings:', JSON.stringify(s));"
                                "}"
                                "return s;"
                            "};"
                        "}"

                        // Log available WebRTC codecs once for diagnostics
                        "try{"
                            "const vc=RTCRtpSender.getCapabilities('video');"
                            "if(vc&&vc.codecs){"
                                "const names=[...new Set(vc.codecs.map(c=>c.mimeType))];"
                                "console.log('[MAI] WebRTC video codecs:', names.join(', '));"
                                "console.log('[MAI] H264 available:', names.some(n=>n.includes('264')));"
                            "}"
                        "}catch(e){console.warn('[MAI] Codec check failed:', e);}"

                        // Intercept RTCPeerConnection — diagnostic logging for WebRTC
                        "if(!window.__maiRTCPatched){"
                            "window.__maiRTCPatched=true;"

                            "const origSetLocal=RTCPeerConnection.prototype.setLocalDescription;"
                            "RTCPeerConnection.prototype.setLocalDescription=function(desc){"
                                "if(desc&&desc.sdp){"
                                    "const codecs=desc.sdp.split('\\n').filter(l=>/^a=rtpmap/.test(l)).map(l=>l.split(' ')[1]);"
                                    "console.log('[MAI] setLocalDescription('+desc.type+') codecs:', codecs.join(', '));"
                                "}"
                                "return origSetLocal.apply(this,[desc]);"
                            "};"

                            "const origSetRemote=RTCPeerConnection.prototype.setRemoteDescription;"
                            "RTCPeerConnection.prototype.setRemoteDescription=function(desc){"
                                "if(desc&&desc.sdp){"
                                    "const codecs=desc.sdp.split('\\n').filter(l=>/^a=rtpmap/.test(l)).map(l=>l.split(' ')[1]);"
                                    "console.log('[MAI] setRemoteDescription('+desc.type+') codecs:', codecs.join(', '));"
                                "}"
                                "return origSetRemote.apply(this,[desc]);"
                            "};"

                            "const origAddTrack=RTCPeerConnection.prototype.addTrack;"
                            "RTCPeerConnection.prototype.addTrack=function(track){"
                                "console.log('[MAI] addTrack:', track.kind, track.label, track.readyState);"
                                "return origAddTrack.apply(this,arguments);"
                            "};"

                            // Log replaceTrack for screen sharing diagnostics
                            "const origReplaceTrack=RTCRtpSender.prototype.replaceTrack;"
                            "RTCRtpSender.prototype.replaceTrack=function(track){"
                                "console.log('[MAI] replaceTrack:', track?(track.kind+':'+track.label+':'+track.readyState):'null');"
                                "return origReplaceTrack.apply(this,arguments);"
                            "};"

                            "const origAddTransceiver=RTCPeerConnection.prototype.addTransceiver;"
                            "RTCPeerConnection.prototype.addTransceiver=function(trackOrKind,init){"
                                "const label=typeof trackOrKind==='string'?trackOrKind:trackOrKind.label||trackOrKind.kind;"
                                "console.log('[MAI] addTransceiver:', label, init?JSON.stringify(init):'');"
                                "return origAddTransceiver.apply(this,arguments);"
                            "};"

                            "const origCreateOffer=RTCPeerConnection.prototype.createOffer;"
                            "RTCPeerConnection.prototype.createOffer=function(opts){"
                                "console.log('[MAI] createOffer called, senders:', this.getSenders().map(s=>s.track?(s.track.kind+':'+s.track.label):null).filter(Boolean).join(', '));"
                                "return origCreateOffer.apply(this,arguments);"
                            "};"

                            "const origClose=RTCPeerConnection.prototype.close;"
                            "RTCPeerConnection.prototype.close=function(){"
                                "console.log('[MAI] RTCPeerConnection.close()');"
                                "return origClose.apply(this,arguments);"
                            "};"
                        "}"];

                    // Override getDisplayMedia with native screen/window picker
                    // Flow: JS prompt('MAI_SCREEN_PICKER') → ObjC JSDialog handler →
                    // SCShareableContent → NSAlert picker → SCStream capture →
                    // JPEG base64 frames → window.__maiFrame → VideoFrame/canvas → WebRTC
                    //
                    // Dual-path: VideoFrame API (no canvas, direct frame injection, 15fps)
                    //            Canvas fallback (captureStream(5), for older engines)
                    [js appendString:
                        @"if(navigator.mediaDevices){"
                            "navigator.mediaDevices.getDisplayMedia=function(constraints){"
                                "return new Promise(function(resolve,reject){"
                                    "console.log('[MAI] getDisplayMedia: showing native picker');"
                                    "var result=prompt('MAI_SCREEN_PICKER');"
                                    "if(!result){"
                                        "console.log('[MAI] getDisplayMedia: user cancelled');"
                                        "reject(new DOMException('Permission denied','NotAllowedError'));"
                                        "return;"
                                    "}"
                                    "console.log('[MAI] getDisplayMedia: selected source:', result);"
                                    "var isScreen=result.startsWith('screen:');"
                                    "var stream;"

                                    // Detect VideoFrame API support
                                    "var useVideoFrame=typeof MediaStreamTrackGenerator==='function';"
                                    "console.log('[MAI] VideoFrame API available:', useVideoFrame);"

                                    "if(useVideoFrame){"
                                        // === VideoFrame path: direct frame injection, no canvas ===
                                        "var generator=new MediaStreamTrackGenerator({kind:'video'});"
                                        "var writer=generator.writable.getWriter();"
                                        "var frameProcessing=false;"

                                        "window.__maiFrame=function(b64){"
                                            "if(frameProcessing)return;"
                                            "frameProcessing=true;"
                                            "fetch('data:image/jpeg;base64,'+b64)"
                                                ".then(function(r){return r.blob();})"
                                                ".then(function(blob){return createImageBitmap(blob);})"
                                                ".then(function(bmp){"
                                                    "var vf=new VideoFrame(bmp,{timestamp:performance.now()*1000});"
                                                    "writer.write(vf);"
                                                    "bmp.close();"
                                                    "frameProcessing=false;"
                                                "})"
                                                ".catch(function(e){"
                                                    "console.warn('[MAI] VideoFrame error:',e);"
                                                    "frameProcessing=false;"
                                                "});"
                                        "};"

                                        "stream=new MediaStream([generator]);"
                                        "console.log('[MAI] Using VideoFrame API path (15fps, no canvas)');"

                                    "}else{"
                                        // === Canvas fallback: existing relay ===
                                        "var canvas=document.createElement('canvas');"
                                        "canvas.width=1920;canvas.height=1080;"
                                        "var ctx=canvas.getContext('2d');"

                                        "ctx.fillStyle='#000';"
                                        "ctx.fillRect(0,0,1920,1080);"
                                        "ctx.fillStyle='#fff';ctx.font='24px sans-serif';"
                                        "ctx.fillText('Starting screen share...',60,60);"

                                        "var img=new Image();"
                                        "window.__maiFrame=function(b64){"
                                            "img.onload=function(){"
                                                "if(canvas.width!==img.naturalWidth||canvas.height!==img.naturalHeight){"
                                                    "canvas.width=img.naturalWidth;canvas.height=img.naturalHeight;"
                                                "}"
                                                "ctx.drawImage(img,0,0);"
                                            "};"
                                            "img.src='data:image/jpeg;base64,'+b64;"
                                        "};"

                                        "stream=canvas.captureStream(5);"
                                        "console.log('[MAI] Using canvas fallback path (5fps)');"
                                    "}"

                                    // NOTE: Silent audio track REMOVED (v0.7.2).
                                    // Adding a silent AudioContext + OscillatorNode track caused
                                    // Google Meet to replaceTrack() the microphone sender with it,
                                    // killing the real mic track (state→ended). This triggered SDP
                                    // BUNDLE codec collision errors [111:audio/opus] x2 and left
                                    // the user without microphone. getDisplayMedia should return
                                    // video-only — Meet/Teams/Zoom keep mic on a separate getUserMedia.

                                    // Shared: displaySurface metadata + cleanup
                                    "var vt=stream.getVideoTracks()[0];"
                                    "if(vt){"
                                        "var origGS=vt.getSettings.bind(vt);"
                                        "vt.getSettings=function(){"
                                            "var s=origGS();"
                                            "s.displaySurface=isScreen?'monitor':'window';"
                                            "s.cursor='always';"
                                            "s.width=1920;s.height=1080;"
                                            "return s;"
                                        "};"

                                        "vt.addEventListener('ended',function(){"
                                            "console.log('[MAI] Screen share track ended, stopping capture');"
                                            "if(useVideoFrame&&writer){"
                                                "try{writer.close();}catch(e){}"
                                            "}"
                                            "prompt('MAI_STOP_CAPTURE');"
                                            "window.__maiFrame=null;"
                                        "});"
                                    "}"

                                    "console.log('[MAI] getDisplayMedia: returning stream, tracks:', "
                                        "stream.getTracks().map(function(t){return t.kind+':'+t.readyState;}).join(', '));"
                                    "resolve(stream);"
                                "});"
                            "};"
                        "}"];

                    [js appendString:@"})();"];

                    cef_string_t script = cef_string_from_nsstring(js);
                    cef_string_t scriptUrl = cef_string_from_nsstring(@"about:blank");
                    frame->execute_java_script(frame, &script, &scriptUrl, 0);
                    cef_string_clear(&script);
                    cef_string_clear(&scriptUrl);
                    cef_log_to_file("Injected getDisplayMedia override on %s",
                                    [urlStr UTF8String]);
                }

                // DIAGNOSTIC ONLY: Log document.cookie at form submit time.
                // Does NOT intercept or override anything — just reads.
                if ([urlStr containsString:@"login.live.com"]) {
                    // Enumerate cookies in CEF's internal store for this URL
                    NSString* enumLabel = [NSString stringWithFormat:@"page-loaded:%@",
                        [urlStr length] > 60 ? [urlStr substringToIndex:60] : urlStr];
                    enumerate_cookies_for_url([enumLabel UTF8String]);

                    NSString* diagJS = @"(function(){"
                        "if(window.__maiDiag)return;"
                        "window.__maiDiag=true;"
                        // Log cookies when page loads
                        "console.log('[MAI-DIAG] Page: '+location.href.substring(0,80));"
                        "console.log('[MAI-DIAG] Cookies on load: '+document.cookie);"
                        // TEST: Can JavaScript WRITE cookies?
                        "try{"
                            "document.cookie='MAI_TEST=1;path=/;secure;SameSite=None';"
                            "var afterSet=document.cookie;"
                            "console.log('[MAI-DIAG] After setting test cookie: '+afterSet);"
                            "console.log('[MAI-DIAG] JS cookie write '+(afterSet.indexOf('MAI_TEST')>=0?'WORKS':'FAILED'));"
                        "}catch(e){console.log('[MAI-DIAG] Cookie write error: '+e.message);}"
                        // Log cookies at form submit time
                        "document.addEventListener('submit',function(e){"
                            "console.log('[MAI-DIAG] FORM SUBMIT to: '+(e.target.action||'').substring(0,120));"
                            "console.log('[MAI-DIAG] Cookies at submit: '+document.cookie);"
                            // Also log all form fields being submitted
                            "var fd=new FormData(e.target);"
                            "var fields=[];"
                            "fd.forEach(function(v,k){fields.push(k+'='+(k.toLowerCase().indexOf('pass')>=0?'***':v.substring(0,30)))});"
                            "console.log('[MAI-DIAG] Form fields: '+fields.join('; '));"
                        "},true);"
                        // Check if any global variable holds contextID
                        "try{console.log('[MAI-DIAG] ServerData: '+(typeof ServerData!='undefined'?JSON.stringify(Object.keys(ServerData)):'undefined'));}catch(e){}"
                        "try{console.log('[MAI-DIAG] $Config: '+(typeof $Config!='undefined'?JSON.stringify(Object.keys($Config).slice(0,20)):'undefined'));}catch(e){}"
                        // Periodically log cookie changes (every 2s for 30s)
                        "var count=0;"
                        "var iv=setInterval(function(){"
                            "console.log('[MAI-DIAG] Cookies['+count+']: '+document.cookie);"
                            "if(++count>=15)clearInterval(iv);"
                        "},2000);"
                    "})();";
                    cef_string_t dScript = cef_string_from_nsstring(diagJS);
                    cef_string_t dUrl = cef_string_from_nsstring(@"about:blank");
                    frame->execute_java_script(frame, &dScript, &dUrl, 0);
                    cef_string_clear(&dScript);
                    cef_string_clear(&dUrl);
                    cef_log_to_file("Injected DIAGNOSTIC on %s",
                                    [urlStr UTF8String]);
                }

                // Password capture for ALL CEF pages with login forms (Fix #15)
                // Uses prompt('MAI_PASSWORD_CAPTURE:base64json') as JS→ObjC channel
                NSString* pwCaptureJS = @"(function(){"
                    "if(window._maiCEFPasswordCapture)return;"
                    "window._maiCEFPasswordCapture=true;"
                    "function _e(s){return btoa(unescape(encodeURIComponent(s)));}"
                    "function _isSameDomain(fa){"
                        "if(!fa||fa===''||fa==='#')return true;"
                        "try{var u=new URL(fa,window.location.href);"
                        "var cd=window.location.hostname.split('.').slice(-2).join('.');"
                        "var ad=u.hostname.split('.').slice(-2).join('.');"
                        "return cd===ad;}catch(e){return true;}"
                    "}"
                    "function captureCreds(passField){"
                        "var form=passField.closest('form');"
                        "if(form&&!_isSameDomain(form.action)){"
                            "console.log('[MAI] CEF password capture blocked: cross-domain form action');return;"
                        "}"
                        "var container=form||document.body;"
                        "var inputs=container.querySelectorAll("
                            "'input[type=\"text\"],input[type=\"email\"],input[name*=\"user\"],input[name*=\"email\"],input[name*=\"login\"],input[autocomplete=\"username\"]'"
                        ");"
                        "var username='';"
                        "for(var i=0;i<inputs.length;i++){"
                            "if(inputs[i].value.trim()){username=inputs[i].value.trim();break;}"
                        "}"
                        "var password=passField.value;"
                        "if(username&&password&&password.length>=3){"
                            "var payload=_e(JSON.stringify({host:window.location.hostname,username:username,password:password}));"
                            "prompt('MAI_PASSWORD_CAPTURE:'+payload);"
                        "}"
                    "}"
                    "document.addEventListener('submit',function(e){"
                        "var pass=e.target.querySelector('input[type=\"password\"]');"
                        "if(pass)captureCreds(pass);"
                    "},true);"
                    "document.addEventListener('click',function(e){"
                        "var btn=e.target.closest('button[type=\"submit\"],input[type=\"submit\"],button:not([type])');"
                        "if(!btn)return;"
                        "var form=btn.closest('form');"
                        "if(!form)return;"
                        "var pass=form.querySelector('input[type=\"password\"]');"
                        "if(pass)setTimeout(function(){captureCreds(pass);},100);"
                    "},true);"
                    "})();";
                cef_string_t pwUrl = cef_string_from_nsstring(urlStr);
                cef_string_t pwJS = cef_string_from_nsstring(pwCaptureJS);
                frame->execute_java_script(frame, &pwJS, &pwUrl, 0);
                cef_string_clear(&pwUrl);
                cef_string_clear(&pwJS);

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

/// Capture console.log messages from JS — critical for [MAI] diagnostics
static int CEF_CALLBACK on_console_message(cef_display_handler_t* self,
                                            cef_browser_t* browser,
                                            cef_log_severity_t level,
                                            const cef_string_t* message,
                                            const cef_string_t* source,
                                            int line) {
    if (!message) return 0;
    NSString* msg = nsstring_from_cef_string(message);
    if (!msg) return 0;
    // Log ALL console messages for verbose debugging
    cef_log_to_file("JS %s", [msg UTF8String]);
    return 0; // Allow default handling
}

static void init_display_handler() {
    init_simple_ref(&g_displayHandler.base, sizeof(cef_display_handler_t));
    g_displayHandler.on_address_change = on_address_change;
    g_displayHandler.on_title_change = on_title_change;
    g_displayHandler.on_media_access_change = on_media_access_change;
    g_displayHandler.on_console_message = on_console_message;
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

// MARK: - Screen Picker Helper (Chrome-style NSPanel)

@interface MAIPickerHelper : NSObject <NSWindowDelegate>
@property (nonatomic, strong) NSScrollView* windowsScrollView;
@property (nonatomic, strong) NSScrollView* screensScrollView;
@property (nonatomic, weak) NSView* tabIndicator;
@property (nonatomic, weak) NSButton* tabWindows;
@property (nonatomic, weak) NSButton* tabScreens;
- (void)tabChanged:(NSButton*)sender;
- (void)shareClicked:(id)sender;
- (void)cancelClicked:(id)sender;
- (void)windowWillClose:(NSNotification*)notification;
@end

@implementation MAIPickerHelper
- (void)tabChanged:(NSButton*)sender {
    BOOL showWindows = (sender.tag == 0);
    self.windowsScrollView.hidden = !showWindows;
    self.screensScrollView.hidden = showWindows;
    // Update tab colors
    self.tabWindows.contentTintColor = showWindows ? [NSColor systemBlueColor] : [NSColor secondaryLabelColor];
    self.tabScreens.contentTintColor = showWindows ? [NSColor secondaryLabelColor] : [NSColor systemBlueColor];
    // Move underline
    if (self.tabIndicator) {
        NSButton* activeBtn = showWindows ? self.tabWindows : self.tabScreens;
        NSRect f = self.tabIndicator.frame;
        f.origin.x = activeBtn.frame.origin.x;
        f.size.width = activeBtn.frame.size.width;
        self.tabIndicator.frame = f;
    }
}
- (void)shareClicked:(id)sender { [NSApp stopModalWithCode:NSModalResponseOK]; }
- (void)cancelClicked:(id)sender { [NSApp stopModalWithCode:NSModalResponseCancel]; }
- (void)windowWillClose:(NSNotification*)notification { [NSApp stopModalWithCode:NSModalResponseCancel]; }
@end

// MARK: - Window Capture (ScreenCaptureKit direct capture for window sharing)

@interface MAICaptureOutput : NSObject <SCStreamOutput>
@end

static SCStream* g_captureStream = nil;
static MAICaptureOutput* g_captureOutput = nil;
static CIContext* g_ciContext = nil;

static void stopWindowCapture(void) {
    if (g_captureStream) {
        g_isCapturing = NO;
        g_framePending = NO;
        g_jpegQuality = 0.92;
        [g_captureStream stopCaptureWithCompletionHandler:^(NSError* error) {
            cef_log_to_file("Window capture stopped");
        }];
        g_captureStream = nil;
    }
    g_isCapturing = NO;
}

static void startCaptureWithFilter(SCContentFilter* filter, NSString* label) {
    stopWindowCapture();

    SCStreamConfiguration* config = [[SCStreamConfiguration alloc] init];
    config.width = 1920;
    config.height = 1080;
    config.minimumFrameInterval = CMTimeMake(1, 15); // 15 fps (matches Teams constraints)
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
        cef_log_to_file("Capture: Failed to add output: %s", [[error description] UTF8String]);
        g_captureStream = nil;
        return;
    }

    g_isCapturing = YES;
    [g_captureStream startCaptureWithCompletionHandler:^(NSError* startError) {
        if (startError) {
            cef_log_to_file("Capture: Failed to start: %s", [[startError description] UTF8String]);
            g_isCapturing = NO;
        } else {
            cef_log_to_file("Capture: Started successfully for '%s'", [label UTF8String]);
        }
    }];
}

static void startWindowCapture(SCWindow* window) {
    SCContentFilter* filter = [[SCContentFilter alloc] initWithDesktopIndependentWindow:window];
    startCaptureWithFilter(filter, window.title ?: @"Unknown window");
}

static void startDisplayCapture(SCDisplay* display) {
    // Capture entire display excluding nothing
    SCContentFilter* filter = [[SCContentFilter alloc]
        initWithDisplay:display excludingWindows:@[]];
    startCaptureWithFilter(filter, [NSString stringWithFormat:@"Display %u", display.displayID]);
}

@implementation MAICaptureOutput

- (void)stream:(SCStream *)stream
    didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
                   ofType:(SCStreamOutputType)type {
    if (type != SCStreamOutputTypeScreen) return;
    if (!g_browser || !g_isCapturing) return;

    // Adaptive: if previous frame still pending on main queue, skip & reduce quality
    if (g_framePending) {
        if (g_jpegQuality > g_jpegQualityMin) g_jpegQuality -= g_jpegQualityStepDown;
        return; // Drop frame
    }

    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (!pixelBuffer) return;

    // Convert to JPEG using reusable CIContext with adaptive quality
    if (!g_ciContext) g_ciContext = [CIContext contextWithOptions:@{kCIContextWorkingColorSpace: (__bridge id)CGColorSpaceCreateWithName(kCGColorSpaceSRGB)}];
    CIImage* ciImage = [CIImage imageWithCVPixelBuffer:pixelBuffer];
    CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    NSData* jpegData = [g_ciContext JPEGRepresentationOfImage:ciImage
                                                   colorSpace:cs
                                                      options:@{(id)kCGImageDestinationLossyCompressionQuality: @(g_jpegQuality)}];
    CGColorSpaceRelease(cs);
    if (!jpegData) return;

    NSString* base64 = [jpegData base64EncodedStringWithOptions:0];

    // Log first frame and periodic updates
    static int frameCount = 0;
    frameCount++;
    if (frameCount == 1 || frameCount % 25 == 0) {
        cef_log_to_file("Window capture: Frame %d, quality=%.2f, JPEG=%lu bytes, base64=%lu chars",
                        frameCount, g_jpegQuality, (unsigned long)jpegData.length, (unsigned long)base64.length);
    }

    g_framePending = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!g_browser || !g_isCapturing) { g_framePending = NO; return; }

        NSString* js = [NSString stringWithFormat:
            @"window.__maiFrame&&window.__maiFrame('%@')", base64];
        // Frame delivered - increase quality towards max
        if (g_jpegQuality < g_jpegQualityMax) g_jpegQuality += g_jpegQualityStepUp;
        cef_frame_t* frame = g_browser->get_main_frame(g_browser);
        if (frame) {
            cef_string_t script = cef_string_from_nsstring(js);
            cef_string_t url = cef_string_from_nsstring(@"about:blank");
            frame->execute_java_script(frame, &script, &url, 0);
            cef_string_clear(&script);
            cef_string_clear(&url);
            cef_release(&frame->base);
        }
        g_framePending = NO;
    });
}

@end

// MARK: - JSDialog Handler (Screen/Window Picker)

static cef_jsdialog_handler_t g_jsdialogHandler;

// Store enumerated sources for lookup after user selection
static NSArray<SCWindow*>* g_enumeratedWindows = nil;
static NSArray<SCDisplay*>* g_enumeratedDisplays = nil;

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

    // Handle password capture from CEF login forms (Fix #15)
    if ([message hasPrefix:@"MAI_PASSWORD_CAPTURE:"]) {
        NSString* b64Payload = [message substringFromIndex:[@"MAI_PASSWORD_CAPTURE:" length]];
        NSData* jsonData = [[NSData alloc] initWithBase64EncodedString:b64Payload options:0];
        if (jsonData) {
            NSDictionary* creds = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
            if (creds) {
                NSString* host = creds[@"host"];
                NSString* username = creds[@"username"];
                NSString* password = creds[@"password"];
                if (host && username && password) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        id<CEFBridgeDelegate> delegate = g_delegate;
                        if ([delegate respondsToSelector:@selector(cefBrowserDidCapturePasswordForHost:username:password:)]) {
                            [delegate cefBrowserDidCapturePasswordForHost:host username:username password:password];
                        }
                    });
                }
            }
        }
        cef_string_t empty = {};
        callback->cont(callback, 1, &empty);
        return 1;
    }

    if (![message isEqualToString:@"MAI_SCREEN_PICKER"]) return 0;

    cef_log_to_file("Screen picker: Intercepted MAI_SCREEN_PICKER prompt");
    cef_addref(&callback->base);

    // Extract domain NOW while origin_url is still valid (CEF frees it after on_jsdialog returns)
    NSString* pickerDomain = @"este sitio";
    if (origin_url && origin_url->str && origin_url->length > 0) {
        NSString* originStr = nsstring_from_cef_string(origin_url);
        if ([originStr hasPrefix:@"http"]) {
            NSURL* url = [NSURL URLWithString:originStr];
            if (url.host) pickerDomain = [url.host copy];
        }
    }

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

            // Track type: "S:idx" for screen, "W:idx" for window
            NSMutableArray<NSString*>* sourceTypes = [NSMutableArray array];

            // Enumerate screens
            NSArray<SCDisplay*>* displays = content.displays;
            g_enumeratedDisplays = [displays copy];
            for (NSUInteger i = 0; i < displays.count; i++) {
                [sourceTypes addObject:[NSString stringWithFormat:@"S:%lu", (unsigned long)i]];
            }

            // Filter and store windows
            NSMutableArray<SCWindow*>* filteredWindows = [NSMutableArray array];
            NSString* myAppName = [[NSProcessInfo processInfo] processName];
            for (SCWindow* window in content.windows) {
                if (!window.title || window.title.length == 0) continue;
                if (window.owningApplication &&
                    [window.owningApplication.applicationName isEqualToString:myAppName]) continue;
                if (window.frame.size.width < 100 || window.frame.size.height < 100) continue;

                [sourceTypes addObject:[NSString stringWithFormat:
                    @"W:%lu", (unsigned long)filteredWindows.count]];
                [filteredWindows addObject:window];
            }

            g_enumeratedWindows = [filteredWindows copy];

            if (sourceTypes.count == 0) {
                cef_string_t empty = {};
                callback->cont(callback, 0, &empty);
                cef_release(&callback->base);
                return;
            }

            cef_log_to_file("Screen picker: Found %lu screens + %lu windows",
                            (unsigned long)displays.count,
                            (unsigned long)filteredWindows.count);

            // --- Chrome-style screen picker with NSPanel ---

            static const CGFloat kThumbW = 280.0;
            static const CGFloat kThumbH = 180.0;
            static const CGFloat kItemW = 300.0;
            static const CGFloat kItemH = 220.0;
            static const CGFloat kPadding = 16.0;
            static const int kColumns = 2;

            // Use domain extracted BEFORE async block (origin_url is freed by CEF after on_jsdialog returns)
            NSString* domain = pickerDomain;

            // Helper: get real display name from NSScreen
            NSString* (^getDisplayName)(SCDisplay*, NSUInteger) = ^NSString*(SCDisplay* display, NSUInteger index) {
                for (NSScreen* screen in NSScreen.screens) {
                    NSNumber* screenNumber = screen.deviceDescription[@"NSScreenNumber"];
                    if (screenNumber && [screenNumber unsignedIntValue] == display.displayID) {
                        return screen.localizedName;
                    }
                }
                return [NSString stringWithFormat:@"Pantalla %lu", (unsigned long)(index + 1)];
            };

            // Helper: create scaled thumbnail from CGImage
            NSImage* (^makeThumbnail)(CGImageRef) = ^NSImage*(CGImageRef cgImg) {
                if (!cgImg) {
                    NSImage* placeholder = [[NSImage alloc] initWithSize:NSMakeSize(kThumbW, kThumbH)];
                    [placeholder lockFocus];
                    [[NSColor darkGrayColor] setFill];
                    NSRectFill(NSMakeRect(0, 0, kThumbW, kThumbH));
                    [placeholder unlockFocus];
                    return placeholder;
                }
                NSImage* img = [[NSImage alloc] initWithCGImage:cgImg size:NSZeroSize];
                NSImage* thumb = [[NSImage alloc] initWithSize:NSMakeSize(kThumbW, kThumbH)];
                [thumb lockFocus];
                [[NSColor blackColor] setFill];
                NSRectFill(NSMakeRect(0, 0, kThumbW, kThumbH));
                [img drawInRect:NSMakeRect(0, 0, kThumbW, kThumbH)
                       fromRect:NSZeroRect
                      operation:NSCompositingOperationSourceOver
                       fraction:1.0];
                [thumb unlockFocus];
                return thumb;
            };

            // Map views to source indices
            NSMapTable<NSView*, NSNumber*>* viewTagMap =
                [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsObjectPointerPersonality
                                      valueOptions:NSPointerFunctionsObjectPersonality];

            // Helper: create one picker item view (thumbnail + label)
            NSView* (^makeItem)(NSImage*, NSString*, NSInteger) = ^NSView*(NSImage* thumb, NSString* name, NSInteger itemTag) {
                NSView* item = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, kItemW, kItemH)];
                item.wantsLayer = YES;
                item.layer.cornerRadius = 8.0;
                item.layer.borderWidth = 2.0;
                item.layer.borderColor = [NSColor clearColor].CGColor;
                [viewTagMap setObject:@(itemTag) forKey:item];

                NSImageView* iv = [[NSImageView alloc] initWithFrame:
                    NSMakeRect((kItemW - kThumbW) / 2.0, 34, kThumbW, kThumbH)];
                iv.image = thumb;
                iv.imageScaling = NSImageScaleProportionallyUpOrDown;
                iv.wantsLayer = YES;
                iv.layer.cornerRadius = 4.0;
                iv.layer.masksToBounds = YES;
                [item addSubview:iv];

                NSTextField* lbl = [NSTextField labelWithString:name];
                lbl.frame = NSMakeRect(2, 4, kItemW - 4, 28);
                lbl.alignment = NSTextAlignmentCenter;
                lbl.font = [NSFont systemFontOfSize:11.0];
                lbl.lineBreakMode = NSLineBreakByTruncatingTail;
                lbl.maximumNumberOfLines = 2;
                [item addSubview:lbl];

                return item;
            };

            // Build items for screens
            NSMutableArray<NSView*>* screenItems = [NSMutableArray array];
            for (NSUInteger i = 0; i < displays.count; i++) {
                CGImageRef cgImg = CGDisplayCreateImage(displays[i].displayID);
                NSImage* thumb = makeThumbnail(cgImg);
                if (cgImg) CGImageRelease(cgImg);
                NSString* name = getDisplayName(displays[i], i);
                NSView* item = makeItem(thumb, name, (NSInteger)i);
                [screenItems addObject:item];
            }

            // Build items for windows
            NSMutableArray<NSView*>* windowItems = [NSMutableArray array];
            for (NSUInteger i = 0; i < filteredWindows.count; i++) {
                CGImageRef cgImg = CGWindowListCreateImage(
                    CGRectNull,
                    kCGWindowListOptionIncludingWindow,
                    filteredWindows[i].windowID,
                    kCGWindowImageBoundsIgnoreFraming);
                NSImage* thumb = makeThumbnail(cgImg);
                if (cgImg) CGImageRelease(cgImg);
                NSString* appName = filteredWindows[i].owningApplication.applicationName ?: @"Unknown";
                NSString* title = filteredWindows[i].title ?: @"";
                NSString* name = [NSString stringWithFormat:@"%@ - %@", appName, title];
                NSView* item = makeItem(thumb, name, (NSInteger)(displays.count + i));
                [windowItems addObject:item];
            }

            // Layout helper: arrange items in a grid (no section header)
            NSView* (^makeGrid)(NSArray<NSView*>*) = ^NSView*(NSArray<NSView*>* items) {
                if (items.count == 0) return [[NSView alloc] initWithFrame:NSZeroRect];
                NSUInteger rows = (items.count + kColumns - 1) / kColumns;
                CGFloat gridW = kColumns * kItemW + (kColumns - 1) * kPadding;
                CGFloat gridH = rows * kItemH + (rows - 1) * kPadding;

                NSView* grid = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, gridW, gridH)];
                for (NSUInteger i = 0; i < items.count; i++) {
                    NSUInteger col = i % kColumns;
                    NSUInteger row = i / kColumns;
                    CGFloat x = col * (kItemW + kPadding);
                    CGFloat y = gridH - (row + 1) * kItemH - row * kPadding;
                    NSView* item = items[i];
                    [item setFrameOrigin:NSMakePoint(x, y)];
                    [grid addSubview:item];
                }
                return grid;
            };

            NSView* windowsGrid = makeGrid(windowItems);
            NSView* screensGrid = makeGrid(screenItems);

            // Grid content dimensions
            CGFloat gridContentW = kColumns * kItemW + (kColumns - 1) * kPadding + 20;
            CGFloat maxVisibleH = 420.0;

            // Windows scroll view
            CGFloat wGridH = windowsGrid.frame.size.height;
            CGFloat wVisibleH = fmin(wGridH, maxVisibleH);
            NSScrollView* windowsScrollView = [[NSScrollView alloc]
                initWithFrame:NSMakeRect(0, 0, gridContentW, fmax(wVisibleH, 100))];
            windowsScrollView.hasVerticalScroller = (wGridH > maxVisibleH);
            windowsScrollView.documentView = windowsGrid;
            windowsScrollView.drawsBackground = NO;

            // Screens scroll view
            CGFloat sGridH = screensGrid.frame.size.height;
            CGFloat sVisibleH = fmin(sGridH, maxVisibleH);
            NSScrollView* screensScrollView = [[NSScrollView alloc]
                initWithFrame:NSMakeRect(0, 0, gridContentW, fmax(sVisibleH, 100))];
            screensScrollView.hasVerticalScroller = (sGridH > maxVisibleH);
            screensScrollView.documentView = screensGrid;
            screensScrollView.drawsBackground = NO;

            // --- Build NSPanel ---
            CGFloat panelW = fmax(gridContentW + 40, 680);
            CGFloat gridAreaH = fmax(fmax(wVisibleH, sVisibleH), 200);
            // Title(22) + subtitle(16) + gap(12) + tabs(30) + separator(3) + gap(12) + grid + gap(16) + toggle(24) + gap(16) + buttons(32) + gap(16)
            CGFloat panelH = 22 + 16 + 12 + 30 + 3 + 12 + gridAreaH + 16 + 24 + 16 + 32 + 16;
            CGFloat panelInset = 20.0;

            NSPanel* panel = [[NSPanel alloc]
                initWithContentRect:NSMakeRect(0, 0, panelW, panelH)
                          styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                            backing:NSBackingStoreBuffered
                              defer:NO];
            panel.title = @"";
            panel.floatingPanel = YES;
            panel.becomesKeyOnlyIfNeeded = NO;
            panel.level = NSModalPanelWindowLevel;
            [panel center];

            NSView* contentView = panel.contentView;
            contentView.wantsLayer = YES;

            // Picker helper (retains scroll views, handles actions)
            MAIPickerHelper* helper = [[MAIPickerHelper alloc] init];
            helper.windowsScrollView = windowsScrollView;
            helper.screensScrollView = screensScrollView;
            panel.delegate = helper;

            // Keep helper alive for the duration of the modal
            static MAIPickerHelper* s_activeHelper = nil;
            s_activeHelper = helper;

            // Current Y cursor (top-down layout)
            CGFloat curY = panelH - panelInset;

            // Title label
            curY -= 20;
            NSString* titleText = domain.length > 0
                ? [NSString stringWithFormat:@"Elige qu\u00e9 quieres compartir con %@", domain]
                : @"Elige qu\u00e9 quieres compartir";
            NSTextField* titleLabel = [NSTextField labelWithString:titleText];
            titleLabel.frame = NSMakeRect(panelInset, curY, panelW - 2 * panelInset, 20);
            titleLabel.font = [NSFont boldSystemFontOfSize:14.0];
            titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
            [contentView addSubview:titleLabel];

            // Subtitle label
            curY -= 18;
            NSTextField* subtitleLabel = [NSTextField labelWithString:
                @"El sitio podr\u00e1 ver el contenido de tu pantalla"];
            subtitleLabel.frame = NSMakeRect(panelInset, curY, panelW - 2 * panelInset, 16);
            subtitleLabel.font = [NSFont systemFontOfSize:11.0];
            subtitleLabel.textColor = [NSColor secondaryLabelColor];
            [contentView addSubview:subtitleLabel];

            // Tab bar (Chrome-style: text labels with blue underline)
            curY -= 42;
            CGFloat tabW = (panelW - 2 * panelInset) / 2.0;
            CGFloat tabH = 28.0;

            NSButton* tabWindows = [[NSButton alloc] initWithFrame:NSMakeRect(panelInset, curY, tabW, tabH)];
            tabWindows.title = @"Ventana";
            tabWindows.bordered = NO;
            tabWindows.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightMedium];
            tabWindows.contentTintColor = [NSColor secondaryLabelColor];
            [contentView addSubview:tabWindows];

            NSButton* tabScreens = [[NSButton alloc] initWithFrame:NSMakeRect(panelInset + tabW, curY, tabW, tabH)];
            tabScreens.title = @"Pantalla completa";
            tabScreens.bordered = NO;
            tabScreens.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightMedium];
            tabScreens.contentTintColor = [NSColor systemBlueColor];
            [contentView addSubview:tabScreens];

            // Blue underline indicator (2px, under active tab)
            NSView* tabIndicator = [[NSView alloc] initWithFrame:
                NSMakeRect(panelInset + tabW, curY - 2, tabW, 2)];
            tabIndicator.wantsLayer = YES;
            tabIndicator.layer.backgroundColor = [NSColor systemBlueColor].CGColor;
            [contentView addSubview:tabIndicator];

            // Separator line
            NSView* tabSeparator = [[NSView alloc] initWithFrame:
                NSMakeRect(panelInset, curY - 3, panelW - 2 * panelInset, 1)];
            tabSeparator.wantsLayer = YES;
            tabSeparator.layer.backgroundColor = [[NSColor separatorColor] CGColor];
            [contentView addSubview:tabSeparator];

            // Tab click handlers
            tabWindows.target = helper;
            tabWindows.action = @selector(tabChanged:);
            tabWindows.tag = 0;
            tabScreens.target = helper;
            tabScreens.action = @selector(tabChanged:);
            tabScreens.tag = 1;

            // Connect helper to tab UI elements
            helper.tabIndicator = tabIndicator;
            helper.tabWindows = tabWindows;
            helper.tabScreens = tabScreens;

            // Position scroll views in the grid area
            curY -= (gridAreaH + 12);
            CGFloat scrollX = (panelW - gridContentW) / 2.0;

            windowsScrollView.frame = NSMakeRect(scrollX, curY, gridContentW, gridAreaH);
            screensScrollView.frame = NSMakeRect(scrollX, curY, gridContentW, gridAreaH);
            [contentView addSubview:windowsScrollView];
            [contentView addSubview:screensScrollView];

            // Default tab: "Pantalla completa" (index 1) → show screens, hide windows
            windowsScrollView.hidden = YES;
            screensScrollView.hidden = NO;

            // Selection state
            __block NSInteger selectedIndex = -1;

            // Highlight helper
            void (^updateSelection)(NSInteger) = ^(NSInteger newIndex) {
                // Update both grids
                NSArray<NSView*>* allGrids = @[windowsGrid, screensGrid];
                for (NSView* grid in allGrids) {
                    for (NSView* sub in grid.subviews) {
                        NSNumber* subTag = [viewTagMap objectForKey:sub];
                        if (subTag && sub.wantsLayer) {
                            BOOL match = ([subTag integerValue] == newIndex);
                            sub.layer.borderColor = match
                                ? [NSColor systemBlueColor].CGColor
                                : [NSColor clearColor].CGColor;
                            sub.layer.backgroundColor = match
                                ? [[NSColor systemBlueColor] colorWithAlphaComponent:0.06].CGColor
                                : [NSColor clearColor].CGColor;
                        }
                    }
                }
                selectedIndex = newIndex;
            };

            // Select first screen by default (since screens tab is default)
            if (displays.count > 0) {
                updateSelection(0);
            }

            // All items for click detection
            NSMutableArray<NSView*>* allItems = [NSMutableArray array];
            [allItems addObjectsFromArray:screenItems];
            [allItems addObjectsFromArray:windowItems];

            // Audio toggle with speaker icon
            curY -= 36;
            NSImageView* speakerIcon = [[NSImageView alloc] initWithFrame:NSMakeRect(panelInset, curY, 20, 20)];
            if (@available(macOS 11.0, *)) {
                speakerIcon.image = [NSImage imageWithSystemSymbolName:@"speaker.wave.2" accessibilityDescription:@"Audio"];
                speakerIcon.contentTintColor = [NSColor secondaryLabelColor];
            }
            [contentView addSubview:speakerIcon];

            NSButton* audioToggle = [NSButton checkboxWithTitle:@"Compartir tambi\u00e9n el audio del sistema"
                                                         target:nil action:nil];
            audioToggle.frame = NSMakeRect(panelInset + 26, curY, panelW - 2 * panelInset - 26, 20);
            audioToggle.font = [NSFont systemFontOfSize:12.0];
            audioToggle.state = NSControlStateValueOff;
            [contentView addSubview:audioToggle];

            // Buttons row
            curY -= 48;
            CGFloat btnW = 90.0;
            CGFloat btnH = 32.0;
            CGFloat btnSpacing = 10.0;

            // Share button (red, right-aligned)
            NSButton* shareBtn = [[NSButton alloc] initWithFrame:
                NSMakeRect(panelW - panelInset - btnW, curY, btnW, btnH)];
            shareBtn.title = @"Compartir";
            shareBtn.bezelStyle = NSBezelStyleRounded;
            shareBtn.target = helper;
            shareBtn.action = @selector(shareClicked:);
            shareBtn.keyEquivalent = @"\r";
            shareBtn.wantsLayer = YES;
            shareBtn.bezelColor = [NSColor systemBlueColor];
            [contentView addSubview:shareBtn];

            // Cancel button (left of Share)
            NSButton* cancelBtn = [[NSButton alloc] initWithFrame:
                NSMakeRect(panelW - panelInset - 2 * btnW - btnSpacing, curY, btnW, btnH)];
            cancelBtn.title = @"Cancelar";
            cancelBtn.bezelStyle = NSBezelStyleRounded;
            cancelBtn.target = helper;
            cancelBtn.action = @selector(cancelClicked:);
            cancelBtn.keyEquivalent = @"\033"; // Escape
            [contentView addSubview:cancelBtn];

            // Click monitor for item selection (checks visible scroll view)
            __block id clickMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown
                handler:^NSEvent*(NSEvent* event) {
                    // Determine which scroll view is visible
                    NSScrollView* activeScroll = windowsScrollView.hidden ? screensScrollView : windowsScrollView;
                    NSView* activeGrid = (NSView*)activeScroll.documentView;

                    NSPoint loc = [activeScroll convertPoint:[event locationInWindow] fromView:nil];
                    if (!NSPointInRect(loc, activeScroll.bounds)) return event;

                    NSPoint docLoc = [activeGrid convertPoint:[event locationInWindow] fromView:nil];
                    for (NSView* item in allItems) {
                        if (item.superview != activeGrid) continue;
                        NSPoint itemLoc = [item convertPoint:docLoc fromView:activeGrid];
                        if (NSPointInRect(itemLoc, item.bounds)) {
                            NSNumber* itemTag = [viewTagMap objectForKey:item];
                            if (itemTag) updateSelection([itemTag integerValue]);
                            break;
                        }
                    }
                    return event;
                }];

            // Run modal
            NSModalResponse response = [NSApp runModalForWindow:panel];

            // Cleanup
            [NSEvent removeMonitor:clickMonitor];
            clickMonitor = nil;
            [panel orderOut:nil];
            s_activeHelper = nil;

            if (response == NSModalResponseOK && selectedIndex >= 0) {
                NSString* type = sourceTypes[selectedIndex];

                if ([type hasPrefix:@"S:"]) {
                    NSInteger dispIdx = [[type substringFromIndex:2] integerValue];
                    SCDisplay* selectedDisplay = g_enumeratedDisplays[dispIdx];
                    NSString* sourceId = [NSString stringWithFormat:@"screen:%u:0",
                                          selectedDisplay.displayID];
                    cef_log_to_file("Screen picker: User selected display %u (%s) -> %s",
                                    selectedDisplay.displayID,
                                    [getDisplayName(selectedDisplay, dispIdx) UTF8String],
                                    [sourceId UTF8String]);
                    startDisplayCapture(selectedDisplay);
                    cef_string_t result = cef_string_from_nsstring(sourceId);
                    callback->cont(callback, 1, &result);
                    cef_string_clear(&result);
                } else if ([type hasPrefix:@"W:"]) {
                    NSInteger winIdx = [[type substringFromIndex:2] integerValue];
                    SCWindow* selectedWindow = g_enumeratedWindows[winIdx];
                    NSString* sourceId = [NSString stringWithFormat:@"window:%u:0",
                                          selectedWindow.windowID];
                    cef_log_to_file("Screen picker: User selected window '%s' -> %s",
                                    [selectedWindow.title UTF8String], [sourceId UTF8String]);
                    startWindowCapture(selectedWindow);
                    cef_string_t result = cef_string_from_nsstring(sourceId);
                    callback->cont(callback, 1, &result);
                    cef_string_clear(&result);
                }
            } else {
                cef_log_to_file("Screen picker: User cancelled");
                cef_string_t empty = {};
                callback->cont(callback, 0, &empty);
            }

            g_enumeratedWindows = nil;
            g_enumeratedDisplays = nil;
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

// MARK: - Cookie Access Filter (allow ALL cookies for Teams auth)

static cef_cookie_access_filter_t g_cookieFilter;

static int CEF_CALLBACK can_send_cookie(
    cef_cookie_access_filter_t* self,
    cef_browser_t* browser,
    cef_frame_t* frame,
    cef_request_t* request,
    const cef_cookie_t* cookie) {
    // Log cookies for Microsoft auth domains
    if (cookie && cookie->name.str) {
        NSString* domain = cookie->domain.str ? nsstring_from_cef_string(&cookie->domain) : @"";
        if ([domain containsString:@"live.com"]) {
            // Full details for login.live.com to debug contextID
            NSString* name = nsstring_from_cef_string(&cookie->name);
            NSString* value = cookie->value.str ? nsstring_from_cef_string(&cookie->value) : @"";
            NSString* valPreview = [value length] > 80 ?
                [NSString stringWithFormat:@"%@...(len=%lu)", [value substringToIndex:80], (unsigned long)[value length]] :
                value;
            cef_log_to_file("COOKIE-SEND: name=%s domain=%s httponly=%d secure=%d samesite=%d val=%s",
                [name UTF8String], [domain UTF8String],
                cookie->httponly, cookie->secure, (int)cookie->same_site,
                [valPreview UTF8String]);
        } else if ([domain containsString:@"microsoft"] ||
                   [domain containsString:@"msftauth"] || [domain containsString:@"teams"]) {
            NSString* name = nsstring_from_cef_string(&cookie->name);
            cef_log_to_file("COOKIE-SEND: name=%s domain=%s", [name UTF8String], [domain UTF8String]);
        }
    }
    return 1; // Allow all cookies to be sent
}

static int CEF_CALLBACK can_save_cookie(
    cef_cookie_access_filter_t* self,
    cef_browser_t* browser,
    cef_frame_t* frame,
    cef_request_t* request,
    cef_response_t* response,
    const cef_cookie_t* cookie) {
    // Log ALL cookies for Microsoft auth domains with full details
    if (cookie && cookie->name.str) {
        NSString* domain = cookie->domain.str ? nsstring_from_cef_string(&cookie->domain) : @"";
        if ([domain containsString:@"microsoft"] || [domain containsString:@"live.com"] ||
            [domain containsString:@"msftauth"] || [domain containsString:@"teams"]) {
            NSString* name = nsstring_from_cef_string(&cookie->name);
            NSString* value = cookie->value.str ? nsstring_from_cef_string(&cookie->value) : @"";
            NSString* path = cookie->path.str ? nsstring_from_cef_string(&cookie->path) : @"";
            // Truncate value for log readability
            NSString* valPreview = [value length] > 80 ?
                [NSString stringWithFormat:@"%@...(len=%lu)", [value substringToIndex:80], (unsigned long)[value length]] :
                value;
            cef_log_to_file("COOKIE-SAVE: name=%s domain=%s path=%s httponly=%d secure=%d samesite=%d val=%s",
                [name UTF8String], [domain UTF8String], [path UTF8String],
                cookie->httponly, cookie->secure, (int)cookie->same_site,
                [valPreview UTF8String]);
        }
    }
    return 1; // Allow all cookies to be saved
}

static void init_cookie_access_filter() {
    init_simple_ref(&g_cookieFilter.base, sizeof(cef_cookie_access_filter_t));
    g_cookieFilter.can_send_cookie = can_send_cookie;
    g_cookieFilter.can_save_cookie = can_save_cookie;
}

// MARK: - Resource Request Handler (provides cookie filter)

static cef_resource_request_handler_t g_resourceRequestHandler;

static cef_cookie_access_filter_t* CEF_CALLBACK get_cookie_access_filter(
    cef_resource_request_handler_t* self,
    cef_browser_t* browser,
    cef_frame_t* frame,
    cef_request_t* request) {
    // DISABLED: Return NULL to use CEF's default cookie handling.
    // Having a cookie filter in the path (even one that allows all cookies)
    // may change CEF's internal cookie code path and cause issues with
    // Microsoft's OAuth cookie test (co=0 on oauth20_authorize.srf).
    return NULL;
}

// Log Set-Cookie headers from login.live.com responses
static void log_set_cookie_headers(cef_response_t* response, const char* context) {
    if (!response) return;

    cef_string_multimap_t headerMap = cef_string_multimap_alloc();
    response->get_header_map(response, headerMap);
    size_t count = cef_string_multimap_size(headerMap);

    for (size_t i = 0; i < count; i++) {
        cef_string_t key = {};
        cef_string_t val = {};
        cef_string_multimap_key(headerMap, i, &key);
        cef_string_multimap_value(headerMap, i, &val);

        NSString* keyStr = key.str ? nsstring_from_cef_string(&key) : @"";
        if ([keyStr.lowercaseString isEqualToString:@"set-cookie"]) {
            NSString* valStr = val.str ? nsstring_from_cef_string(&val) : @"";
            NSString* preview = [valStr length] > 200 ?
                [NSString stringWithFormat:@"%@...(len=%lu)", [valStr substringToIndex:200], (unsigned long)[valStr length]] :
                valStr;
            cef_log_to_file("SET-COOKIE-HDR [%s]: %s", context, [preview UTF8String]);
        }

        cef_string_clear(&key);
        cef_string_clear(&val);
    }
    cef_string_multimap_free(headerMap);
}

static int CEF_CALLBACK on_resource_response_cb(
    cef_resource_request_handler_t* self,
    cef_browser_t* browser,
    cef_frame_t* frame,
    cef_request_t* request,
    cef_response_t* response) {

    if (request && response) {
        cef_string_userfree_t urlStr = request->get_url(request);
        if (urlStr) {
            NSString* url = nsstring_from_cef_string(urlStr);
            if ([url containsString:@"login.live.com"]) {
                int status = response->get_status(response);
                NSString* urlPreview = [url length] > 100 ?
                    [url substringToIndex:100] : url;
                cef_log_to_file("RESPONSE: status=%d url=%s", status, [urlPreview UTF8String]);
                log_set_cookie_headers(response, "response");

                // After key responses, enumerate the cookie store
                if ([url containsString:@"Me.htm"] || [url containsString:@"oauth20_authorize"]) {
                    NSString* label = [NSString stringWithFormat:@"after-response:%@",
                        [url containsString:@"Me.htm"] ? @"Me.htm" : @"oauth20_authorize"];
                    enumerate_cookies_for_url([label UTF8String]);
                }
            }
            cef_string_userfree_free(urlStr);
        }
    }
    return 0; // Don't modify/retry the request
}

static void CEF_CALLBACK on_resource_redirect_cb(
    cef_resource_request_handler_t* self,
    cef_browser_t* browser,
    cef_frame_t* frame,
    cef_request_t* request,
    cef_response_t* response,
    cef_string_t* new_url) {

    if (request && response && new_url) {
        NSString* newUrlStr = new_url->str ? nsstring_from_cef_string(new_url) : @"";

        // Microsoft redirect logging
        if ([newUrlStr containsString:@"login.live.com"] ||
            [newUrlStr containsString:@"login.microsoftonline.com"]) {

            cef_string_userfree_t oldUrlStr = request->get_url(request);
            NSString* oldUrl = oldUrlStr ? nsstring_from_cef_string(oldUrlStr) : @"";
            NSString* oldPreview = [oldUrl length] > 80 ? [oldUrl substringToIndex:80] : oldUrl;
            NSString* newPreview = [newUrlStr length] > 80 ? [newUrlStr substringToIndex:80] : newUrlStr;

            int status = response->get_status(response);
            cef_log_to_file("REDIRECT: %d from=%s to=%s", status, [oldPreview UTF8String], [newPreview UTF8String]);
            log_set_cookie_headers(response, "redirect");

            if (oldUrlStr) cef_string_userfree_free(oldUrlStr);
        }
    }
}

// on_before_resource_load: Ensures cookies are sent with login.live.com requests.
// FIX: Chromium 145 sets DO_NOT_SEND_COOKIES (load_flag 0x80000) on form POST
// navigations, which prevents the Cookie header from being sent with
// ppsecure/post.srf. This causes Microsoft's contextID cookie validation to fail.
// We force UR_FLAG_ALLOW_STORED_CREDENTIALS on all login.live.com requests
// so that CEF maps credentials_mode = kInclude, overriding the load flag.
static cef_return_value_t CEF_CALLBACK on_before_resource_load_cb(
    cef_resource_request_handler_t* self,
    cef_browser_t* browser,
    cef_frame_t* frame,
    cef_request_t* request,
    cef_callback_t* callback) {

    if (!request) return RV_CONTINUE;

    cef_string_userfree_t urlStr = request->get_url(request);
    if (!urlStr) return RV_CONTINUE;

    NSString* url = nsstring_from_cef_string(urlStr);
    cef_string_userfree_free(urlStr);

    // FIX: Chromium 145 sets DO_NOT_SEND_COOKIES (0x80000) on many request types,
    // preventing cookies from being sent. This breaks authentication on Google Meet,
    // Microsoft Teams, and Zoom. Since CEF is ONLY used for video conferencing sites,
    // force UR_FLAG_ALLOW_STORED_CREDENTIALS on ALL requests unconditionally.
    // This makes cookie behavior match a normal browser.
    int flags = request->get_flags(request);
    if (!(flags & UR_FLAG_ALLOW_STORED_CREDENTIALS)) {
        request->set_flags(request, flags | UR_FLAG_ALLOW_STORED_CREDENTIALS);
    }

    return RV_CONTINUE;
}

// Cookie visitor callback to enumerate cookies in the store
static cef_cookie_visitor_t g_cookieVisitor;

static int CEF_CALLBACK cookie_visitor_visit(
    cef_cookie_visitor_t* self,
    const cef_cookie_t* cookie,
    int count,
    int total,
    int* deleteCookie) {

    if (!cookie) return 1;

    NSString* name = cookie->name.str ? nsstring_from_cef_string(&cookie->name) : @"?";
    NSString* value = cookie->value.str ? nsstring_from_cef_string(&cookie->value) : @"";
    NSString* domain = cookie->domain.str ? nsstring_from_cef_string(&cookie->domain) : @"?";
    NSString* path = cookie->path.str ? nsstring_from_cef_string(&cookie->path) : @"/";

    NSString* valPreview = [value length] > 80 ?
        [NSString stringWithFormat:@"%@...", [value substringToIndex:80]] : value;

    cef_log_to_file("COOKIE-STORE [%d/%d]: name=%s value=%s domain=%s path=%s httponly=%d secure=%d",
                    count+1, total,
                    [name UTF8String], [valPreview UTF8String],
                    [domain UTF8String], [path UTF8String],
                    cookie->httponly, cookie->secure);

    *deleteCookie = 0;
    return 1;  // Continue visiting
}

static void enumerate_cookies_for_url(const char* label) {
    cef_request_context_t* ctx = cef_request_context_get_global_context();
    if (!ctx) {
        cef_log_to_file("COOKIE-ENUM [%s]: No global request context!", label);
        return;
    }

    cef_cookie_manager_t* mgr = ctx->get_cookie_manager(ctx, NULL);
    if (!mgr) {
        cef_log_to_file("COOKIE-ENUM [%s]: No cookie manager!", label);
        ctx->base.base.release(&ctx->base.base);
        return;
    }

    cef_log_to_file("COOKIE-ENUM [%s]: Enumerating all cookies for login.live.com...", label);

    // Visit cookies for login.live.com
    init_simple_ref(&g_cookieVisitor.base, sizeof(cef_cookie_visitor_t));
    g_cookieVisitor.visit = cookie_visitor_visit;

    cef_string_t urlStr = cef_string_from_nsstring(@"https://login.live.com/");
    int ok = mgr->visit_url_cookies(mgr, &urlStr, 1, &g_cookieVisitor);
    cef_string_clear(&urlStr);

    cef_log_to_file("COOKIE-ENUM [%s]: visit_url_cookies returned %d", label, ok);

    mgr->base.release(&mgr->base);
    ctx->base.base.release(&ctx->base.base);
}

static void init_resource_request_handler() {
    init_simple_ref(&g_resourceRequestHandler.base,
                    sizeof(cef_resource_request_handler_t));
    g_resourceRequestHandler.get_cookie_access_filter = get_cookie_access_filter;
    g_resourceRequestHandler.on_before_resource_load = on_before_resource_load_cb;
    g_resourceRequestHandler.on_resource_response = on_resource_response_cb;
    g_resourceRequestHandler.on_resource_redirect = on_resource_redirect_cb;
}

// MARK: - Request Handler (provides resource request handler)

static cef_request_handler_t g_requestHandler;

static cef_resource_request_handler_t* CEF_CALLBACK get_resource_request_handler_cb(
    cef_request_handler_t* self,
    cef_browser_t* browser,
    cef_frame_t* frame,
    cef_request_t* request,
    int is_navigation,
    int is_download,
    const cef_string_t* request_initiator,
    int* disable_default_handling) {
    // Re-enabled for diagnostic cookie logging (filter still returns NULL)
    simple_add_ref(&g_resourceRequestHandler.base);
    return &g_resourceRequestHandler;
}

// Called when a renderer process crashes or is terminated
static void CEF_CALLBACK on_render_process_terminated(
    cef_request_handler_t* self,
    cef_browser_t* browser,
    cef_termination_status_t status,
    int error_code,
    const cef_string_t* error_string) {

    const char* statusStr = "unknown";
    switch (status) {
        case TS_ABNORMAL_TERMINATION: statusStr = "abnormal exit"; break;
        case TS_PROCESS_WAS_KILLED:   statusStr = "killed"; break;
        case TS_PROCESS_CRASHED:      statusStr = "crashed"; break;
        case TS_PROCESS_OOM:          statusStr = "out of memory"; break;
        default: break;
    }
    NSLog(@"[CEF] Renderer process terminated: %s (error_code=%d)", statusStr, error_code);

    // Notify delegate on main thread
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([CEFBridge.delegate respondsToSelector:@selector(cefBrowserRendererCrashedWithStatus:)]) {
            [CEFBridge.delegate cefBrowserRendererCrashedWithStatus:(int)status];
        }
    });

    // Auto-reload: get current URL and reload the page after a short delay
    if (browser) {
        cef_frame_t* mainFrame = browser->get_main_frame(browser);
        if (mainFrame) {
            cef_string_userfree_t urlStr = mainFrame->get_url(mainFrame);
            if (urlStr) {
                cef_string_utf8_t urlUtf8 = {};
                cef_string_to_utf8(urlStr->str, urlStr->length, &urlUtf8);
                NSString* currentURL = [NSString stringWithUTF8String:urlUtf8.str];
                cef_string_utf8_clear(&urlUtf8);
                cef_string_userfree_free(urlStr);

                NSLog(@"[CEF] Auto-reloading crashed tab: %@", currentURL);

                // Reload after 1s to let CEF recover
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                    dispatch_get_main_queue(), ^{
                        if (g_browser) {
                            cef_string_t cefURL = {};
                            cef_string_from_utf8([currentURL UTF8String],
                                                 [currentURL lengthOfBytesUsingEncoding:NSUTF8StringEncoding],
                                                 &cefURL);
                            cef_frame_t* frame = g_browser->get_main_frame(g_browser);
                            if (frame) {
                                frame->load_url(frame, &cefURL);
                                cef_release(&frame->base);
                            }
                            cef_string_clear(&cefURL);
                        }
                    });
            }
            cef_release(&mainFrame->base);
        }
    }
}

static void init_request_handler() {
    init_simple_ref(&g_requestHandler.base, sizeof(cef_request_handler_t));
    g_requestHandler.get_resource_request_handler = get_resource_request_handler_cb;
    g_requestHandler.on_render_process_terminated = on_render_process_terminated;
}

static cef_request_handler_t* CEF_CALLBACK get_request_handler(cef_client_t* self) {
    simple_add_ref(&g_requestHandler.base);
    return &g_requestHandler;
}

static void init_client() {
    init_simple_ref(&g_client.base, sizeof(cef_client_t));
    g_client.get_life_span_handler = get_life_span_handler;
    g_client.get_load_handler = get_load_handler;
    g_client.get_display_handler = get_display_handler;
    g_client.get_permission_handler = get_permission_handler;
    g_client.get_jsdialog_handler = get_jsdialog_handler;
    g_client.get_request_handler = get_request_handler;
}

// MARK: - Standalone Native Window for Teams
// CEF Views framework is INCOMPATIBLE with external_message_pump=1 on macOS
// because Views requires MessagePumpNSApplication (only created by CefRunMessageLoop).
// Instead, we create a native NSWindow and embed an Alloy-style CEF browser in it.
// getDisplayMedia uses our custom native picker (ScreenCaptureKit + JSDialog handler).

// MARK: - Browser Process Handler
// Required when using external_message_pump = 1.
// CEF calls on_schedule_message_pump_work to tell us when to process messages.

static cef_browser_process_handler_t g_browserProcessHandler;

static void CEF_CALLBACK on_context_initialized(
    cef_browser_process_handler_t* self) {
    NSLog(@"[CEF] Context initialized - CEF is fully ready");
    // NOTE: Cookie preferences are set AFTER cef_initialize() returns,
    // not here. The global request context is not fully ready during
    // this callback (called within cef_initialize), and accessing it
    // causes SIGBUS crash (0xcdcdcdcd uninitialized memory).
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

    // Capture current browser generation to detect stale blocks after browser switch
    int gen = g_browserGeneration;

    if (delay_ms <= 0) {
        // Work needed ASAP - dispatch immediately to main thread
        dispatch_async(dispatch_get_main_queue(), ^{
            if (g_cefInitialized && g_browser && gen == g_browserGeneration) {
                safe_do_message_loop_work();
            }
        });
    } else {
        // Schedule delayed work
        dispatch_after(
            dispatch_time(DISPATCH_TIME_NOW, delay_ms * NSEC_PER_MSEC),
            dispatch_get_main_queue(),
            ^{
                if (g_cefInitialized && g_browser && gen == g_browserGeneration) {
                    safe_do_message_loop_work();
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

    // Log process type for debugging
    NSString* procType = process_type ? nsstring_from_cef_string(process_type) : @"browser";
    NSLog(@"[CEF] on_before_command_line_processing for: %@", procType);

    // Enable media stream APIs
    cef_string_t mediaStream = cef_string_from_nsstring(@"enable-media-stream");
    command_line->append_switch(command_line, &mediaStream);
    cef_string_clear(&mediaStream);

    // Enable getUserMedia screen capturing — allows getUserMedia() with
    // chromeMediaSource:'desktop' + chromeMediaSourceId to create REAL desktop
    // capture tracks (is_screencast=true). This is the Electron/teams-for-linux
    // approach and produces proper video-content-type RTP headers (0x01).
    cef_string_t screenCapFlag = cef_string_from_nsstring(@"enable-usermedia-screen-capturing");
    command_line->append_switch(command_line, &screenCapFlag);
    cef_string_clear(&screenCapFlag);

    // Auto-accept camera/mic WITHOUT affecting screen capture.
    // NOTE: --use-fake-ui-for-media-stream was removed because it causes
    // NotReadableError for getDisplayMedia() in Alloy mode (CEF Forum #20150).
    // Our on_request_media_access_permission + on_show_permission_prompt callbacks
    // handle all permission grants.
    cef_string_t autoAccept = cef_string_from_nsstring(@"auto-accept-camera-and-microphone-capture");
    command_line->append_switch(command_line, &autoAccept);
    cef_string_clear(&autoAccept);

    // Disable GPU sandbox for macOS compatibility
    cef_string_t flag4 = cef_string_from_nsstring(@"disable-gpu-sandbox");
    command_line->append_switch(command_line, &flag4);
    cef_string_clear(&flag4);

    // Use mock keychain to avoid macOS Keychain access prompts.
    // The cookie issue was NOT caused by mock-keychain — it was caused by
    // Chromium's DO_NOT_SEND_COOKIES load flag on form POST navigations,
    // which we fix via UR_FLAG_ALLOW_STORED_CREDENTIALS in on_before_resource_load.
    cef_string_t flag5 = cef_string_from_nsstring(@"use-mock-keychain");
    command_line->append_switch(command_line, &flag5);
    cef_string_clear(&flag5);

    // Disable Chrome-specific features that crash or are unneeded in embedded CEF.
    // ThirdPartyCookiePhaseout: REQUIRED for Google login. Chromium 145 blocks
    // third-party cookies by default, which breaks accounts.google.com cookie
    // test (redirect loop with "Cookies are disabled"). CEF lacks Chrome's
    // Related Website Sets that whitelist Google cross-domain cookies.
    // Microsoft auth works fine with this disabled — the earlier co=0 issue
    // was caused by ThirdPartyStoragePartitioning, not ThirdPartyCookiePhaseout.
    {
        cef_string_t dfKey = cef_string_from_nsstring(@"disable-features");

        // Disable ALL Rust-based codecs/renderers in Chromium 145.
        // The Rust↔C++↔ObjC bridge creates dynamic ObjC classes that are
        // incompatible with macOS 26.3.1 — causes "unrecognized selector
        // sent to instance" crash (SIGTRAP) during cef_do_message_loop_work.
        // Crash stack shows: SymphoniaDecoder, rust_bmp, xml_ffi.
        // Disabling falls back to stable C/C++ implementations.
        //
        // FontationsFontBackend → CoreText (macOS native)
        // RustPngDecoder → libpng (C)
        // RustAudioDecoder (Symphonia) → platform audio decoder
        // RustColorProvider → C++ color provider
        NSString* features =
            @"MediaRouter,PwaNavigationCapturing,WebAppInstallation,"
            @"WebAppSystemMediaControls,DesktopPWAsAdditionalWindowingControls,"
            @"ChromeWebAppShortcutCopier,BackForwardCache,"
            @"ThirdPartyCookiePhaseout,"
            @"FontationsFontBackend,RustPngDecoder,"
            @"RustAudioDecoder,RustColorProvider";

        NSLog(@"[CEF] Adding disable-features: %@", features);
        cef_string_t dfVal = cef_string_from_nsstring(features);
        command_line->append_switch_with_value(command_line, &dfKey, &dfVal);
        cef_string_clear(&dfKey);
        cef_string_clear(&dfVal);
    }

    // Disable extensions (not needed for video conferencing)
    cef_string_t flag7 = cef_string_from_nsstring(@"disable-extensions");
    command_line->append_switch(command_line, &flag7);
    cef_string_clear(&flag7);

    // NOTE: --disable-site-isolation-trials was REMOVED.
    // Chromium's cookie engine is designed for site-isolated processes.
    // Disabling site isolation can cause cross-origin cookie issues.

    // Whitelist Microsoft auth servers for integrated auth
    cef_string_t authKey = cef_string_from_nsstring(@"auth-server-whitelist");
    cef_string_t authVal = cef_string_from_nsstring(@"*.microsoft.com,*.microsoftonline.com,*.live.com");
    command_line->append_switch_with_value(command_line, &authKey, &authVal);
    cef_string_clear(&authKey);
    cef_string_clear(&authVal);

    // Net-log for screen sharing diagnostics
    cef_string_t netLogKey = cef_string_from_nsstring(@"log-net-log");
    cef_string_t netLogVal = cef_string_from_nsstring(@"/tmp/cef_netlog.json");
    command_line->append_switch_with_value(command_line, &netLogKey, &netLogVal);
    cef_string_clear(&netLogKey);
    cef_string_clear(&netLogVal);
    cef_string_t netLogCapKey = cef_string_from_nsstring(@"net-log-capture-mode");
    cef_string_t netLogCapVal = cef_string_from_nsstring(@"IncludeSensitive");
    command_line->append_switch_with_value(command_line, &netLogCapKey, &netLogCapVal);
    cef_string_clear(&netLogCapKey);
    cef_string_clear(&netLogCapVal);

    // NOTE: --enable-blink-features=MediaStreamInsertableStreams was tested
    // but removed — it may interfere with Google's cookie test on
    // accounts.google.com. MediaStreamTrackGenerator should be available
    // by default in Chromium 145 (shipped in Chrome 94). If typeof check
    // fails at runtime, re-enable with cookie impact testing.

    // NOTE: --auto-select-desktop-capture-source removed — it is Chrome-layer
    // only and has NO effect in Alloy mode (CEF Issue #3667).

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

// MARK: - Message Pump with crash recovery
//
// CEF 145's internal Chromium code has an incompatibility with macOS 26.3.1:
// during cef_do_message_loop_work(), Chromium's Rust↔ObjC bridge sends an
// unrecognized selector to a dynamic class → NSInvalidArgumentException →
// C++ noexcept → std::terminate → SIGTRAP → process death.
//
// We cannot prevent the exception (it's deep inside CEF). We cannot catch it
// with @try/@catch (C++ noexcept bypasses ObjC exception handling). We cannot
// swizzle reportException: (std::terminate calls abort() regardless).
//
// The ONLY remaining option: catch the SIGTRAP signal and use longjmp to
// recover from the crash, skipping the failed cef_do_message_loop_work() call.

static sigjmp_buf g_pumpJmpBuf;
static volatile sig_atomic_t g_inMessagePump = 0;
static struct sigaction g_oldSigtrapAction;
static struct sigaction g_oldSigabrtAction;
static int g_pumpCrashCount = 0;

static void cef_crash_signal_handler(int sig) {
    if (g_inMessagePump) {
        // We're inside cef_do_message_loop_work() — recover via longjmp
        g_inMessagePump = 0;
        siglongjmp(g_pumpJmpBuf, sig);
        // NEVER REACHED
    }
    // Not in our message pump — restore original handler and re-raise
    if (sig == SIGTRAP) {
        sigaction(SIGTRAP, &g_oldSigtrapAction, NULL);
    } else {
        sigaction(SIGABRT, &g_oldSigabrtAction, NULL);
    }
    raise(sig);
}

static void install_pump_signal_handlers() {
    struct sigaction sa = {};
    sa.sa_handler = cef_crash_signal_handler;
    sa.sa_flags = 0; // No SA_RESTART — we want the signal to interrupt
    sigemptyset(&sa.sa_mask);

    sigaction(SIGTRAP, &sa, &g_oldSigtrapAction);
    sigaction(SIGABRT, &sa, &g_oldSigabrtAction);
    NSLog(@"[CEF] Signal handlers installed for SIGTRAP/SIGABRT recovery");
}

/// Safe wrapper around cef_do_message_loop_work() that catches SIGTRAP/SIGABRT
/// from CEF's internal Chromium crash and recovers instead of dying.
static void safe_do_message_loop_work() {
    if (!g_cefInitialized) return;

    g_inMessagePump = 1;
    int sig = sigsetjmp(g_pumpJmpBuf, 1); // 1 = save signal mask
    if (sig == 0) {
        // Normal path — call CEF
        cef_do_message_loop_work();
    } else {
        // Recovery path — we caught a signal from inside cef_do_message_loop_work
        g_pumpCrashCount++;
        NSLog(@"[CEF] ⚠️ Recovered from signal %d in message pump (crash #%d)",
              sig, g_pumpCrashCount);
    }
    g_inMessagePump = 0;
}

static void startMessagePump() {
    if (g_messagePumpTimer) return;

    // Install signal handlers for crash recovery
    install_pump_signal_handlers();

    // Fallback timer at 30Hz. The primary pump is on_schedule_message_pump_work,
    // this covers edge cases (UI tracking mode, missed callbacks).
    // Uses safe_do_message_loop_work() which catches SIGTRAP/SIGABRT as safety net.
    g_messagePumpTimer = [NSTimer scheduledTimerWithTimeInterval:1.0/30.0
                                                         repeats:YES
                                                           block:^(NSTimer* timer) {
        if (g_cefInitialized && g_browser) {
            safe_do_message_loop_work();
        }
    }];
    [[NSRunLoop mainRunLoop] addTimer:g_messagePumpTimer
                              forMode:NSRunLoopCommonModes];
}

static void stopMessagePump() {
    [g_messagePumpTimer invalidate];
    g_messagePumpTimer = nil;
}

// MARK: - Uncaught Exception Logger

static void mai_uncaught_exception_handler(NSException* exception) {
    NSString* info = [NSString stringWithFormat:
        @"=== MAI Uncaught Exception ===\n"
        @"Name: %@\n"
        @"Reason: %@\n"
        @"UserInfo: %@\n"
        @"Stack:\n%@\n",
        exception.name, exception.reason, exception.userInfo,
        [exception.callStackSymbols componentsJoinedByString:@"\n"]];
    [info writeToFile:@"/tmp/mai_exception.log"
           atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSLog(@"[CEF] FATAL EXCEPTION: %@", exception.reason);
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

    // Install global exception logger to capture the ACTUAL selector name
    // from CEF's "unrecognized selector" crash. This fires before the process
    // dies and writes details to /tmp/mai_exception.log for diagnosis.
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSSetUncaughtExceptionHandler(&mai_uncaught_exception_handler);
    });

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
    init_cookie_access_filter();
    init_resource_request_handler();
    init_request_handler();
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
    settings.persist_session_cookies = 1;  // Keep session cookies across restarts

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

    // Cache paths — persistent location so cookies/sessions survive app restarts
    NSArray* appSupport = NSSearchPathForDirectoriesInDomains(
        NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString* rootCachePath = [[appSupport firstObject] stringByAppendingPathComponent:@"MAI/CEF"];
    NSString* profilePath = [rootCachePath stringByAppendingPathComponent:@"Default"];
    [[NSFileManager defaultManager] createDirectoryAtPath:profilePath
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    cef_string_t rcPath = cef_string_from_nsstring(rootCachePath);
    cef_string_set(rcPath.str, rcPath.length, &settings.root_cache_path, 1);
    cef_string_clear(&rcPath);
    // cache_path must be set for persistent cookie storage (not just root_cache_path)
    cef_string_t cpPath = cef_string_from_nsstring(profilePath);
    cef_string_set(cpPath.str, cpPath.length, &settings.cache_path, 1);
    cef_string_clear(&cpPath);

    // User agent — plain Chrome with REAL version number (145.0.7632.68).
    // Chrome/145.0.0.0 is non-standard and Microsoft servers fingerprint the UA
    // to adjust the auth flow. Must match the actual Chromium version in CEF.
    // Edge UA was removed because it triggers BSSO checks that fail in CEF.
    NSString* userAgent = @"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                          @"AppleWebKit/537.36 (KHTML, like Gecko) "
                          @"Chrome/145.0.7632.68 Safari/537.36";
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
        // Cookie preferences handled via command-line flags:
        // --disable-features includes ThirdPartyCookiePhaseout,
        // ThirdPartyStoragePartitioning, PartitionedCookies
        // plus persist_session_cookies=1 in CEF settings.
        // Programmatic set_preference crashes due to CEF C API
        // ownership semantics (use-after-free on cef_value_t).
    } else {
        NSLog(@"[CEF] ERROR: Initialization failed (code: %d)", cef_get_exit_code());
    }

    return result ? YES : NO;
}

+ (void)shutdownCEF {
    if (!g_cefInitialized) return;

    NSLog(@"[CEF] Shutting down...");

    // Force-release browser synchronously. Do NOT use closeBrowser + message pump loop:
    // closeBrowser is async (sends IPC to renderer), and pumping messages via
    // cef_do_message_loop_work() during shutdown hits stale internal CEF objects,
    // causing "unrecognized selector" crashes (SIGTRAP in applicationWillTerminate).
    // forceReleaseBrowser is synchronous: stops capture, stops message pump,
    // NULLs g_browser, and releases the reference — no message pumping needed.
    if (g_browser) {
        [self forceReleaseBrowser];
    } else {
        // No browser, but still stop capture and message pump
        stopWindowCapture();
        stopMessagePump();
    }

    // Shutdown CEF — safe now that browser is released and message pump is stopped
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

    // Force-release existing browser if any.
    // Must use forceReleaseBrowser (synchronous) instead of closeBrowser (async)
    // because closeBrowser's on_before_close fires later and can NULL-out
    // the NEW browser's g_browser reference, causing a crash.
    if (g_browser) {
        [self forceReleaseBrowser];
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
    // NOTE: parent_view on macOS FORCES Alloy style regardless of runtime_style.
    // getDisplayMedia screen sharing uses our ScreenCaptureKit → Canvas pipeline.
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
        // Restart message pump if it was stopped (e.g., after previous browser close)
        startMessagePump();
        NSLog(@"[CEF] Browser created successfully");
    } else {
        NSLog(@"[CEF] ERROR: Failed to create browser");
        return nil;
    }

    return hostView;
}

+ (void)openStandaloneBrowserWithURL:(NSString *)url {
    if (!g_cefInitialized) {
        if (![self initializeCEF]) {
            NSLog(@"[CEF] ERROR: Cannot open standalone browser - CEF init failed");
            return;
        }
    }

    // Force-release existing browser (see createBrowserViewWithURL comment)
    if (g_browser) {
        [self forceReleaseBrowser];
    }

    NSLog(@"[CEF] Creating standalone NSWindow browser for: %@", url);
    g_isStandaloneMode = YES;

    // Create native NSWindow
    NSWindow* window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(100, 100, 1280, 800)
                  styleMask:(NSWindowStyleMaskTitled |
                             NSWindowStyleMaskClosable |
                             NSWindowStyleMaskResizable |
                             NSWindowStyleMaskMiniaturizable)
                    backing:NSBackingStoreBuffered
                      defer:NO];
    [window setTitle:@"MAI - Teams"];
    [window setReleasedWhenClosed:NO];

    NSView* contentView = window.contentView;
    contentView.wantsLayer = YES;

    // Window info — embed CEF in the native NSWindow's content view.
    // parent_view forces Alloy style on macOS (per cef_types_mac.h).
    // getDisplayMedia is handled by our native picker (JSDialog + ScreenCaptureKit).
    cef_window_info_t windowInfo = {};
    windowInfo.size = sizeof(cef_window_info_t);
    windowInfo.parent_view = (__bridge void*)contentView;
    windowInfo.bounds.x = 0;
    windowInfo.bounds.y = 0;
    windowInfo.bounds.width = (int)contentView.bounds.size.width;
    windowInfo.bounds.height = (int)contentView.bounds.size.height;
    windowInfo.runtime_style = CEF_RUNTIME_STYLE_DEFAULT;

    // Browser settings
    cef_browser_settings_t browserSettings = {};
    browserSettings.size = sizeof(cef_browser_settings_t);
    browserSettings.webgl = STATE_ENABLED;

    // URL
    cef_string_t cefURL = cef_string_from_nsstring(url);

    // Add ref to client before passing
    simple_add_ref(&g_client.base);

    // Create browser synchronously — embedded in native NSWindow
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
        g_standaloneNSWindow = window;
        g_browserView = contentView;
        startMessagePump();
        [window makeKeyAndOrderFront:nil];
        [window center];
        NSLog(@"[CEF] Standalone NSWindow browser created successfully");
    } else {
        NSLog(@"[CEF] ERROR: Failed to create standalone browser");
        g_isStandaloneMode = NO;
        window = nil;
    }
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

    NSLog(@"[CEF] Closing browser (standalone=%d)", g_isStandaloneMode);

    // Stop any active window capture before closing
    stopWindowCapture();

    cef_browser_host_t* host = g_browser->get_host(g_browser);
    if (host) {
        host->close_browser(host, 1); // force_close = true
        cef_release(&host->base);
    }

    // Browser will be set to NULL in on_before_close callback.
    // Standalone NSWindow is closed in on_before_close too.
}

+ (void)safeCloseBrowser {
    // Delegate to forceReleaseBrowser — the message pump loop that was here
    // caused "unrecognized selector" crashes when cef_do_message_loop_work()
    // dispatched messages to partially torn-down CEF objects.
    [self forceReleaseBrowser];
}

+ (void)forceReleaseBrowser {
    if (!g_browser) return;

    NSLog(@"[CEF] Force-releasing browser (standalone=%d)", g_isStandaloneMode);

    // Invalidate any pending dispatch blocks from on_schedule_message_pump_work
    g_browserGeneration++;

    // Detach CDP observer BEFORE releasing browser
    if (g_cdpRegistration) {
        cef_release(&g_cdpRegistration->base);
        g_cdpRegistration = NULL;
    }

    // Stop capture and message pump FIRST to prevent any further CEF callbacks
    stopWindowCapture();
    stopMessagePump();

    // CRITICAL: Set g_browser to NULL BEFORE any view manipulation.
    cef_browser_t* browserToRelease = g_browser;
    g_browser = NULL;

    NSView* viewToClean = g_browserView;
    g_browserView = nil;
    if (viewToClean) {
        for (NSView* subview in [viewToClean.subviews copy]) {
            [subview removeFromSuperview];
        }
    }

    // Close standalone NSWindow if present
    if (g_isStandaloneMode && g_standaloneNSWindow) {
        [g_standaloneNSWindow close];
        g_standaloneNSWindow = nil;
        g_isStandaloneMode = NO;
    }

    // Release browser reference LAST
    if (browserToRelease) {
        cef_release(&browserToRelease->base);
    }

    NSLog(@"[CEF] Browser force-released");

    // Notify delegate
    dispatch_async(dispatch_get_main_queue(), ^{
        id<CEFBridgeDelegate> delegate = g_delegate;
        if ([delegate respondsToSelector:@selector(cefBrowserDidClose)]) {
            [delegate cefBrowserDidClose];
        }
    });
}

+ (void)killHelperProcesses {
    // Find and kill MAI Helper processes spawned by CEF.
    // These are GPU, Renderer, Network, and Storage subprocesses.
    NSTask* task = [[NSTask alloc] init];
    task.launchPath = @"/usr/bin/pkill";
    task.arguments = @[@"-f", @"MAI Helper"];
    @try {
        [task launch];
        [task waitUntilExit];
        NSLog(@"[CEF] Helper processes terminated (pkill exit code: %d)", task.terminationStatus);
    } @catch (NSException* e) {
        NSLog(@"[CEF] Failed to kill helper processes: %@", e);
    }
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

// MARK: - CDP (Chrome DevTools Protocol)

+ (void)setCDPDelegate:(nullable id<CEFBridgeCDPDelegate>)delegate {
    g_cdpDelegate = delegate;
}

+ (BOOL)cdpAttach {
    if (!g_browser) return NO;

    cef_browser_host_t* host = g_browser->get_host(g_browser);
    if (!host) return NO;

    // Remove previous observer if any
    if (g_cdpRegistration) {
        cef_release(&g_cdpRegistration->base);
        g_cdpRegistration = NULL;
    }

    // Create DevTools message observer
    cef_dev_tools_message_observer_t* observer =
        (cef_dev_tools_message_observer_t*)calloc(1, sizeof(cef_dev_tools_message_observer_t));

    init_simple_ref(&observer->base, sizeof(cef_dev_tools_message_observer_t));

    // on_dev_tools_message: raw JSON message (return false to let it propagate)
    observer->on_dev_tools_message = [](cef_dev_tools_message_observer_t* self,
                                        cef_browser_t* browser,
                                        const void* message,
                                        size_t message_size) -> int {
        return 0; // Let it propagate to method_result / event callbacks
    };

    // on_dev_tools_method_result: response to a command we sent
    observer->on_dev_tools_method_result = [](cef_dev_tools_message_observer_t* self,
                                              cef_browser_t* browser,
                                              int message_id,
                                              int success,
                                              const void* result,
                                              size_t result_size) {
        NSString* json = nil;
        if (result && result_size > 0) {
            json = [[NSString alloc] initWithBytes:result length:result_size encoding:NSUTF8StringEncoding];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [g_cdpDelegate cdpDidReceiveMethodResult:message_id success:(success != 0) result:json ?: @"{}"];
        });
    };

    // on_dev_tools_event: async events (Debugger.paused, Debugger.scriptParsed, etc.)
    observer->on_dev_tools_event = [](cef_dev_tools_message_observer_t* self,
                                      cef_browser_t* browser,
                                      const cef_string_t* method,
                                      const void* params,
                                      size_t params_size) {
        NSString* methodStr = nsstring_from_cef_string(method);
        NSString* paramsJson = nil;
        if (params && params_size > 0) {
            paramsJson = [[NSString alloc] initWithBytes:params length:params_size encoding:NSUTF8StringEncoding];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [g_cdpDelegate cdpDidReceiveEvent:methodStr params:paramsJson ?: @"{}"];
        });
    };

    observer->on_dev_tools_agent_attached = [](cef_dev_tools_message_observer_t* self,
                                               cef_browser_t* browser) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [g_cdpDelegate cdpDidAttach];
        });
    };

    observer->on_dev_tools_agent_detached = [](cef_dev_tools_message_observer_t* self,
                                               cef_browser_t* browser) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [g_cdpDelegate cdpDidDetach];
        });
    };

    g_cdpRegistration = host->add_dev_tools_message_observer(host, observer);
    cef_release(&observer->base);
    cef_release(&host->base);

    return (g_cdpRegistration != NULL);
}

+ (void)cdpDetach {
    if (g_cdpRegistration) {
        cef_release(&g_cdpRegistration->base);
        g_cdpRegistration = NULL;
    }
}

+ (int)cdpSendMethod:(NSString *)method params:(nullable NSString *)paramsJson {
    if (!g_browser) return 0;

    cef_browser_host_t* host = g_browser->get_host(g_browser);
    if (!host) return 0;

    int msgId = ++g_cdpMessageId;

    // Build JSON-RPC message: {"id": N, "method": "...", "params": {...}}
    NSString* json;
    if (paramsJson && paramsJson.length > 0) {
        json = [NSString stringWithFormat:@"{\"id\":%d,\"method\":\"%@\",\"params\":%@}", msgId, method, paramsJson];
    } else {
        json = [NSString stringWithFormat:@"{\"id\":%d,\"method\":\"%@\",\"params\":{}}", msgId, method];
    }

    const char* utf8 = [json UTF8String];
    int result = host->send_dev_tools_message(host, utf8, strlen(utf8));
    cef_release(&host->base);

    return result ? msgId : 0;
}

@end
