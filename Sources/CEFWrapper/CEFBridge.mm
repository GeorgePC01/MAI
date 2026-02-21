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
// NOTE: Views framework headers removed — Views is incompatible with
// external_message_pump=1 on macOS (requires MessagePumpNSApplication).
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

// Standalone mode: Teams in its own NSWindow (still Alloy-style, but separate window)
static BOOL g_isStandaloneMode = NO;
static NSWindow* g_standaloneNSWindow = nil;

// Forward declarations
static void stopMessagePump(void);
static void startMessagePump(void);

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
    if (g_browser) {
        cef_release(&g_browser->base);
        g_browser = NULL;
    }
    g_browserView = nil;

    // Close standalone NSWindow if present
    if (g_isStandaloneMode && g_standaloneNSWindow) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [g_standaloneNSWindow close];
            g_standaloneNSWindow = nil;
        });
        g_isStandaloneMode = NO;
    }

    // Stop message pump - no browser to service.
    // CRITICAL: Must stop here to prevent cef_do_message_loop_work() from
    // accessing deallocated NSViews (causes unrecognized selector crash).
    stopMessagePump();

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
static BOOL g_framePending = NO;
static float g_jpegQuality = 0.85;
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
                    [urlStr containsString:@"teams.microsoft.com"] ||
                    [urlStr containsString:@"teams.live.com"]) {

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

                        // === SPOOF 1: Add H.264 to RTCRtpSender/Receiver.getCapabilities ===
                        // Teams checks for H.264 support before attempting screen sharing.
                        // Our CEF build lacks proprietary codecs, so we fake H.264 in
                        // getCapabilities. The actual SDP negotiation will strip H.264
                        // (see maiRemoveH264 below), forcing VP9/AV1 fallback.
                        "if(!window.__maiCodecSpoofed){"
                            "window.__maiCodecSpoofed=true;"
                            "const h264Codecs=["
                                "{mimeType:'video/H264',clockRate:90000,sdpFmtpLine:'level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=42001f'},"
                                "{mimeType:'video/H264',clockRate:90000,sdpFmtpLine:'level-asymmetry-allowed=1;packetization-mode=0;profile-level-id=42001f'},"
                                "{mimeType:'video/H264',clockRate:90000,sdpFmtpLine:'level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=42e01f'},"
                                "{mimeType:'video/H264',clockRate:90000,sdpFmtpLine:'level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=4d001f'},"
                                "{mimeType:'video/H264',clockRate:90000,sdpFmtpLine:'level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=640032'}"
                            "];"
                            "const origSenderCaps=RTCRtpSender.getCapabilities;"
                            "RTCRtpSender.getCapabilities=function(kind){"
                                "const caps=origSenderCaps.call(this,kind);"
                                "if(kind==='video'&&caps&&caps.codecs){"
                                    "const hasH264=caps.codecs.some(c=>c.mimeType.includes('264'));"
                                    "if(!hasH264){"
                                        "caps.codecs=[...h264Codecs,...caps.codecs];"
                                        "console.log('[MAI] Spoofed H.264 into Sender.getCapabilities');"
                                    "}"
                                "}"
                                "return caps;"
                            "};"
                            "const origRecvCaps=RTCRtpReceiver.getCapabilities;"
                            "RTCRtpReceiver.getCapabilities=function(kind){"
                                "const caps=origRecvCaps.call(this,kind);"
                                "if(kind==='video'&&caps&&caps.codecs){"
                                    "const hasH264=caps.codecs.some(c=>c.mimeType.includes('264'));"
                                    "if(!hasH264){"
                                        "caps.codecs=[...h264Codecs,...caps.codecs];"
                                        "console.log('[MAI] Spoofed H.264 into Receiver.getCapabilities');"
                                    "}"
                                "}"
                                "return caps;"
                            "};"
                            "console.log('[MAI] H.264 codec spoofing installed');"
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

                        // Log available WebRTC codecs once for diagnostics (AFTER spoofing)
                        "try{"
                            "const vc=RTCRtpSender.getCapabilities('video');"
                            "if(vc&&vc.codecs){"
                                "const names=[...new Set(vc.codecs.map(c=>c.mimeType))];"
                                "console.log('[MAI] WebRTC video codecs (with spoof):', names.join(', '));"
                                "console.log('[MAI] H264 available:', names.some(n=>n.includes('264')));"
                            "}"
                        "}catch(e){console.warn('[MAI] Codec check failed:', e);}"

                        // Intercept RTCPeerConnection — remove H.264 from SDP since our CEF
                        // build lacks proprietary codecs. Forces VP9/AV1 negotiation instead.
                        "if(!window.__maiRTCPatched){"
                            "window.__maiRTCPatched=true;"

                            // Helper: remove H.264 codec lines from SDP
                            "function maiRemoveH264(sdp){"
                                "const lines=sdp.split('\\r\\n');"
                                "const h264pts=new Set();"
                                "lines.forEach(l=>{"
                                    "const m=l.match(/^a=rtpmap:(\\d+)\\s+H264\\//i);"
                                    "if(m)h264pts.add(m[1]);"
                                "});"
                                "if(h264pts.size===0)return sdp;"
                                "console.log('[MAI] Removing H.264 payload types:', [...h264pts].join(','));"
                                "const rtxPts=new Set();"
                                "lines.forEach(l=>{"
                                    "const m=l.match(/^a=fmtp:(\\d+)\\s+apt=(\\d+)/);"
                                    "if(m&&h264pts.has(m[2]))rtxPts.add(m[1]);"
                                "});"
                                "const removePts=new Set([...h264pts,...rtxPts]);"
                                "const filtered=lines.filter(l=>{"
                                    "for(const pt of removePts){"
                                        "if(l.match(new RegExp('^a=rtpmap:'+pt+'\\\\s')))return false;"
                                        "if(l.match(new RegExp('^a=rtcp-fb:'+pt+'\\\\s')))return false;"
                                        "if(l.match(new RegExp('^a=fmtp:'+pt+'\\\\s')))return false;"
                                    "}"
                                    "return true;"
                                "});"
                                "const result=filtered.map(l=>{"
                                    "if(l.startsWith('m=video')){"
                                        "const parts=l.split(' ');"
                                        "const cleaned=parts.filter((p,i)=>i<3||!removePts.has(p));"
                                        "return cleaned.join(' ');"
                                    "}"
                                    "return l;"
                                "});"
                                "return result.join('\\r\\n');"
                            "}"

                            "const origSetLocal=RTCPeerConnection.prototype.setLocalDescription;"
                            "RTCPeerConnection.prototype.setLocalDescription=function(desc){"
                                "if(desc&&desc.sdp){"
                                    "const h264Count=desc.sdp.split('\\n').filter(l=>/H264/i.test(l)).length;"
                                    "if(h264Count>0){"
                                        "console.log('[MAI] SDP '+desc.type+': removing '+h264Count+' H264 lines');"
                                        "desc=Object.assign({},desc,{sdp:maiRemoveH264(desc.sdp)});"
                                    "}"
                                    "const codecs=desc.sdp.split('\\n').filter(l=>/^a=rtpmap/.test(l)).map(l=>l.split(' ')[1]);"
                                    "console.log('[MAI] setLocalDescription('+desc.type+') codecs:', codecs.join(', '));"
                                "}"
                                "return origSetLocal.apply(this,[desc]);"
                            "};"

                            "const origSetRemote=RTCPeerConnection.prototype.setRemoteDescription;"
                            "RTCPeerConnection.prototype.setRemoteDescription=function(desc){"
                                "if(desc&&desc.sdp){"
                                    "const h264Count=desc.sdp.split('\\n').filter(l=>/H264/i.test(l)).length;"
                                    "if(h264Count>0){"
                                        "console.log('[MAI] Remote SDP '+desc.type+': removing '+h264Count+' H264 lines');"
                                        "desc=Object.assign({},desc,{sdp:maiRemoveH264(desc.sdp)});"
                                    "}"
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

                            // === KEY FIX: Intercept setCodecPreferences ===
                            // Teams uses setCodecPreferences to restrict to H.264+AV1.
                            // After our SDP H.264 removal, only AV1 remains and server
                            // rejects it. Fix: always inject VP8/VP9 into preferences
                            // so they survive H.264 removal.
                            "const origSetCodecPrefs=RTCRtpTransceiver.prototype.setCodecPreferences;"
                            "if(origSetCodecPrefs){"
                                "RTCRtpTransceiver.prototype.setCodecPreferences=function(codecs){"
                                    "if(!codecs||codecs.length===0)return origSetCodecPrefs.call(this,codecs);"
                                    "const hasVideo=codecs.some(c=>c.mimeType&&c.mimeType.startsWith('video/'));"
                                    "if(hasVideo){"
                                        "const hasVP8=codecs.some(c=>c.mimeType==='video/VP8');"
                                        "const hasVP9=codecs.some(c=>c.mimeType==='video/VP9');"
                                        "if(!hasVP8||!hasVP9){"
                                            "const realCaps=origSenderCaps?origSenderCaps.call(RTCRtpSender,'video'):null;"
                                            "if(realCaps&&realCaps.codecs){"
                                                "const vp8=realCaps.codecs.filter(c=>c.mimeType==='video/VP8');"
                                                "const vp9=realCaps.codecs.filter(c=>c.mimeType==='video/VP9');"
                                                "const rtx=realCaps.codecs.filter(c=>c.mimeType==='video/rtx');"
                                                "if(!hasVP8&&vp8.length)codecs=[...codecs,...vp8,...rtx.slice(0,1)];"
                                                "if(!hasVP9&&vp9.length)codecs=[...codecs,...vp9,...rtx.slice(0,1)];"
                                                "console.log('[MAI] setCodecPreferences: injected VP8/VP9, total codecs:', codecs.length,"
                                                    "codecs.map(c=>c.mimeType).join(', '));"
                                            "}"
                                        "}else{"
                                            "console.log('[MAI] setCodecPreferences: VP8/VP9 already present');"
                                        "}"
                                    "}"
                                    "return origSetCodecPrefs.call(this,codecs);"
                                "};"
                            "}"

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

                    // Diagnostic-only getDisplayMedia logging via Proxy (invisible to toString)
                    [js appendString:
                        @"if(navigator.mediaDevices&&navigator.mediaDevices.getDisplayMedia){"
                            "const _realGDM=navigator.mediaDevices.getDisplayMedia.bind(navigator.mediaDevices);"
                            "navigator.mediaDevices.getDisplayMedia=new Proxy(_realGDM,{"
                                "apply:function(target,thisArg,args){"
                                    "console.log('[MAI] getDisplayMedia called, constraints:', JSON.stringify(args[0]));"
                                    "return target.apply(thisArg,args).then(function(s){"
                                        "console.log('[MAI] getDisplayMedia SUCCESS, tracks:', s.getTracks().map(t=>t.kind+':'+t.label+':'+t.readyState).join(', '));"
                                        "var vt=s.getVideoTracks();"
                                        "if(vt.length)console.log('[MAI] Track settings:', JSON.stringify(vt[0].getSettings()));"
                                        "return s;"
                                    "},function(e){"
                                        "console.log('[MAI] getDisplayMedia FAILED:', e.name, e.message);"
                                        "throw e;"
                                    "});"
                                "}"
                            "});"
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
        g_jpegQuality = 0.85;
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
        if (g_jpegQuality > 0.4) g_jpegQuality -= 0.05;
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
        if (g_jpegQuality < 0.85) g_jpegQuality += 0.02;
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
            g_enumeratedDisplays = [displays copy];
            if (displays.count == 1) {
                [displayNames addObject:@"\xF0\x9F\x96\xA5 Entire screen"];
                [sourceTypes addObject:@"S:0"];
            } else {
                for (NSUInteger i = 0; i < displays.count; i++) {
                    [displayNames addObject:[NSString stringWithFormat:
                        @"\xF0\x9F\x96\xA5 Screen %lu", (unsigned long)(i + 1)]];
                    [sourceTypes addObject:[NSString stringWithFormat:@"S:%lu", (unsigned long)i]];
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

                if ([type hasPrefix:@"S:"]) {
                    // Screen selected → return Chromium source ID for getUserMedia
                    // Format: "screen:DISPLAY_ID:0" (same as Electron desktopCapturer)
                    NSInteger dispIdx = [[type substringFromIndex:2] integerValue];
                    SCDisplay* selectedDisplay = g_enumeratedDisplays[dispIdx];
                    NSString* sourceId = [NSString stringWithFormat:@"screen:%u:0",
                                          selectedDisplay.displayID];
                    cef_log_to_file("Screen picker: User selected display %u → %s",
                                    selectedDisplay.displayID, [sourceId UTF8String]);
                    // Also start SCStream capture as fallback if getUserMedia fails
                    startDisplayCapture(selectedDisplay);
                    cef_string_t result = cef_string_from_nsstring(sourceId);
                    callback->cont(callback, 1, &result);
                    cef_string_clear(&result);
                } else if ([type hasPrefix:@"W:"]) {
                    // Window selected → return Chromium source ID for getUserMedia
                    // Format: "window:WINDOW_ID:0"
                    NSInteger winIdx = [[type substringFromIndex:2] integerValue];
                    SCWindow* selectedWindow = g_enumeratedWindows[winIdx];
                    NSString* sourceId = [NSString stringWithFormat:@"window:%u:0",
                                          selectedWindow.windowID];
                    cef_log_to_file("Screen picker: User selected window '%s' → %s",
                                    [selectedWindow.title UTF8String], [sourceId UTF8String]);
                    // Also start SCStream capture as fallback if getUserMedia fails
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

static void init_client() {
    init_simple_ref(&g_client.base, sizeof(cef_client_t));
    g_client.get_life_span_handler = get_life_span_handler;
    g_client.get_load_handler = get_load_handler;
    g_client.get_display_handler = get_display_handler;
    g_client.get_permission_handler = get_permission_handler;
    g_client.get_jsdialog_handler = get_jsdialog_handler;
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
            if (g_cefInitialized && g_browser) {
                cef_do_message_loop_work();
            }
        });
    } else {
        // Schedule delayed work, replacing any pending scheduled call
        dispatch_after(
            dispatch_time(DISPATCH_TIME_NOW, delay_ms * NSEC_PER_MSEC),
            dispatch_get_main_queue(),
            ^{
                if (g_cefInitialized && g_browser) {
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
        if (g_cefInitialized && g_browser) {
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

    // Cache path — persistent location so cookies/sessions survive app restarts
    NSArray* appSupport = NSSearchPathForDirectoriesInDomains(
        NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString* cachePath = [[appSupport firstObject] stringByAppendingPathComponent:@"MAI/CEF"];
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

    // Pump remaining messages to let browser close complete
    for (int i = 0; i < 100 && g_browser != NULL; i++) {
        cef_do_message_loop_work();
        usleep(10000);
    }

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

    // Close existing browser if any
    if (g_browser) {
        [self closeBrowser];
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
    if (!g_browser) return;

    NSLog(@"[CEF] Safe-closing browser (synchronous)");

    stopWindowCapture();

    // Stop the 30Hz timer FIRST to prevent async cef_do_message_loop_work calls.
    // We'll manually pump messages in a controlled loop below.
    stopMessagePump();

    // Initiate the close
    cef_browser_host_t* host = g_browser->get_host(g_browser);
    if (host) {
        host->close_browser(host, 1); // force_close = true
        cef_release(&host->base);
    }

    // Manually pump CEF messages until on_before_close sets g_browser = NULL.
    // This lets CEF process the close sequence (IPC with renderer, cleanup)
    // without the 30Hz timer interfering.
    NSLog(@"[CEF] Pumping messages for close sequence...");
    for (int i = 0; i < 300 && g_browser != NULL; i++) {
        cef_do_message_loop_work();
        // Brief sleep to allow IPC processing
        usleep(10000); // 10ms
    }

    if (g_browser == NULL) {
        NSLog(@"[CEF] Browser closed cleanly via on_before_close");
    } else {
        // Timeout — force release as fallback
        NSLog(@"[CEF] Close timed out after 3s, force-releasing");
        cef_browser_t* b = g_browser;
        g_browser = NULL;
        g_browserView = nil;
        cef_release(&b->base);
    }
}

+ (void)forceReleaseBrowser {
    if (!g_browser) return;

    NSLog(@"[CEF] Force-releasing browser (standalone=%d)", g_isStandaloneMode);

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

@end
