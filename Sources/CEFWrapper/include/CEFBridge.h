//
//  CEFBridge.h
//  MAI Browser - Chromium Embedded Framework Bridge
//
//  Objective-C interface wrapping CEF C API for Swift consumption.
//  CEF is used ONLY for video conferencing tabs (Meet/Zoom/Teams).
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// Delegate protocol for CEF browser events
@protocol CEFBridgeDelegate <NSObject>
@optional
- (void)cefBrowserDidStartLoading;
- (void)cefBrowserDidFinishLoading;
- (void)cefBrowserDidUpdateURL:(NSString *)url;
- (void)cefBrowserDidUpdateTitle:(NSString *)title;
- (void)cefBrowserDidUpdateLoadProgress:(double)progress;
- (void)cefBrowserDidClose;
@end

/// Bridge between CEF C API and Swift/Objective-C
@interface CEFBridge : NSObject

/// Whether CEF has been initialized
@property (class, readonly) BOOL isInitialized;

/// Whether a CEF browser is currently active
@property (class, readonly) BOOL hasBrowser;

/// Delegate for browser events
@property (class, weak, nullable) id<CEFBridgeDelegate> delegate;

/// Initialize CEF subsystem (lazy - only called when first video conference tab opens)
/// @return YES if initialization succeeded
+ (BOOL)initializeCEF;

/// Shutdown CEF subsystem and release all resources
+ (void)shutdownCEF;

/// Create a new Chromium browser view for embedding in SwiftUI
/// @param url Initial URL to load
/// @param frame Initial frame for the view
/// @return NSView containing the Chromium browser, or nil on failure
+ (nullable NSView *)createBrowserViewWithURL:(NSString *)url
                                        frame:(NSRect)frame;

/// Navigate the active CEF browser to a new URL
/// @param url The URL to navigate to
+ (void)loadURL:(NSString *)url;

/// Close the active CEF browser and release its resources
+ (void)closeBrowser;

/// Execute JavaScript in the active CEF browser
/// @param script JavaScript code to execute
+ (void)executeJavaScript:(NSString *)script;

/// Get the current URL of the active CEF browser
+ (nullable NSString *)currentURL;

/// Get the current title of the active CEF browser
+ (nullable NSString *)currentTitle;

@end

NS_ASSUME_NONNULL_END
