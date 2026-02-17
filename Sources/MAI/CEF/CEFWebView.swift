import SwiftUI
import AppKit
import CEFWrapper

/// NSViewRepresentable wrapper for CEF Chromium browser view.
/// Used only for video conferencing tabs (Meet/Zoom/Teams) where
/// screen sharing requires Chromium's WebRTC implementation.
struct CEFWebView: NSViewRepresentable {
    let url: String
    @ObservedObject var tab: Tab

    /// Container view that hosts the CEF browser.
    /// CRITICAL: Browser creation is deferred until this view is added to a window.
    /// CEF on macOS requires the parent view to be in a window for the compositor
    /// to create render surfaces. Without a window, the renderer process can't start.
    class CEFHostView: NSView {
        var browserView: NSView?
        var pendingURL: String?
        weak var coordinator: Coordinator?
        var browserCreated = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // Schedule browser creation on the NEXT run loop iteration.
            // CEF initialization registers run loop observers that must not fire
            // during the same iteration as view hierarchy updates.
            if window != nil && !browserCreated, let url = pendingURL {
                browserCreated = true  // Prevent duplicate scheduling
                let capturedURL = url
                DispatchQueue.main.async { [weak self] in
                    self?.createBrowser(url: capturedURL)
                }
            }
        }

        override func layout() {
            super.layout()
            // Resize CEF browser view to fill host
            browserView?.frame = bounds
        }

        private func createBrowser(url: String) {
            guard window != nil else {
                NSLog("[CEF] Window gone before browser creation, aborting")
                browserCreated = false
                return
            }

            // Initialize CEF if needed (lazy initialization)
            if !CEFBridge.isInitialized {
                let success = CEFBridge.initializeCEF()
                if !success {
                    print("[CEF] Failed to initialize CEF")
                    return
                }
            }

            // Set delegate to receive browser events
            if let coordinator = coordinator {
                CEFBridge.delegate = coordinator
            }

            // Use our actual bounds (should be non-zero now that we're in a window)
            let frame = bounds.isEmpty ? NSRect(x: 0, y: 0, width: 800, height: 600) : bounds
            NSLog("[CEF] Creating browser in window, frame: \(frame)")

            if let cefView = CEFBridge.createBrowserView(withURL: url, frame: frame) {
                cefView.frame = bounds
                cefView.autoresizingMask = [.width, .height]
                addSubview(cefView)
                browserView = cefView
                NSLog("[CEF] Browser view added to host (in window)")
            } else {
                NSLog("[CEF] ERROR: createBrowserView returned nil")
            }
        }
    }

    func makeNSView(context: Context) -> CEFHostView {
        let hostView = CEFHostView()
        hostView.autoresizingMask = [.width, .height]
        hostView.wantsLayer = true

        // Store URL and coordinator for deferred browser creation
        hostView.pendingURL = url
        hostView.coordinator = context.coordinator

        return hostView
    }

    func updateNSView(_ hostView: CEFHostView, context: Context) {
        // URL changes are tracked via CEFBridgeDelegate callbacks.
    }

    static func dismantleNSView(_ hostView: CEFHostView, coordinator: Coordinator) {
        // Close the CEF browser when the view is removed
        CEFBridge.closeBrowser()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(tab: tab)
    }

    /// Coordinator receives CEF browser events and updates the Tab model
    class Coordinator: NSObject, CEFBridgeDelegate {
        var tab: Tab

        init(tab: Tab) {
            self.tab = tab
        }

        func cefBrowserDidStartLoading() {
            DispatchQueue.main.async { [weak self] in
                self?.tab.isLoading = true
            }
        }

        func cefBrowserDidFinishLoading() {
            DispatchQueue.main.async { [weak self] in
                self?.tab.isLoading = false
            }
        }

        func cefBrowserDidUpdateURL(_ url: String) {
            DispatchQueue.main.async { [weak self] in
                self?.tab.url = url
            }
        }

        func cefBrowserDidUpdateTitle(_ title: String) {
            DispatchQueue.main.async { [weak self] in
                self?.tab.title = title
            }
        }

        func cefBrowserDidUpdateLoadProgress(_ progress: Double) {
            DispatchQueue.main.async { [weak self] in
                self?.tab.loadProgress = progress
            }
        }

        func cefBrowserDidClose() {
            DispatchQueue.main.async { [weak self] in
                self?.tab.isLoading = false
            }
        }
    }
}
