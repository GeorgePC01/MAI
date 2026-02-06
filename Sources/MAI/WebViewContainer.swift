import SwiftUI
import WebKit

/// Container que envuelve WKWebView para uso en SwiftUI
struct WebViewContainer: View {
    @EnvironmentObject var browserState: BrowserState

    var body: some View {
        if let tab = browserState.currentTab {
            WebViewRepresentable(tab: tab, browserState: browserState)
                .id(tab.id)  // Forzar recreación cuando cambia tab
        } else {
            EmptyStateView()
        }
    }
}

/// Vista cuando no hay tabs
struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "globe")
                .font(.system(size: 64))
                .foregroundColor(.secondary)

            Text("MAI Browser")
                .font(.title)
                .fontWeight(.semibold)

            Text("Escribe una dirección para comenzar")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
    }
}

/// Wrapper de WKWebView para SwiftUI
struct WebViewRepresentable: NSViewRepresentable {
    @ObservedObject var tab: Tab
    @ObservedObject var browserState: BrowserState

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()

        // Configuración de preferencias
        config.preferences.javaScriptCanOpenWindowsAutomatically = false

        // IMPORTANTE: Habilitar fullscreen de elementos HTML5 (videos de YouTube, etc.)
        if #available(macOS 12.0, *) {
            config.preferences.isElementFullscreenEnabled = true
        }

        // Habilitar reproducción de medios
        config.mediaTypesRequiringUserActionForPlayback = []

        // Preferencias web
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        config.defaultWebpagePreferences = preferences

        // Crear WebView
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true

        // Guardar referencia en el tab
        tab.webView = webView

        // Observadores de KVO
        context.coordinator.setupObservers(for: webView)

        // Cargar URL inicial si existe
        if let url = URL(string: tab.url), tab.url != "about:blank" {
            webView.load(URLRequest(url: url))
        }

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Aplicar zoom si cambió
        webView.pageZoom = tab.zoomLevel
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(tab: tab, browserState: browserState)
    }

    /// Coordinator para manejar delegados de WKWebView
    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var tab: Tab
        var browserState: BrowserState
        private var observations: [NSKeyValueObservation] = []

        init(tab: Tab, browserState: BrowserState) {
            self.tab = tab
            self.browserState = browserState
        }

        deinit {
            observations.forEach { $0.invalidate() }
        }

        func setupObservers(for webView: WKWebView) {
            // Observar cambios en URL
            let urlObservation = webView.observe(\.url, options: .new) { [weak self] webView, _ in
                DispatchQueue.main.async {
                    self?.tab.updateFromWebView(webView)
                }
            }

            // Observar título
            let titleObservation = webView.observe(\.title, options: .new) { [weak self] webView, _ in
                DispatchQueue.main.async {
                    self?.tab.updateFromWebView(webView)
                }
            }

            // Observar progreso de carga
            let progressObservation = webView.observe(\.estimatedProgress, options: .new) { [weak self] webView, _ in
                DispatchQueue.main.async {
                    self?.tab.loadProgress = webView.estimatedProgress
                    self?.browserState.loadingProgress = webView.estimatedProgress
                }
            }

            // Observar estado de carga
            let loadingObservation = webView.observe(\.isLoading, options: .new) { [weak self] webView, _ in
                DispatchQueue.main.async {
                    self?.tab.isLoading = webView.isLoading
                    self?.browserState.isLoading = webView.isLoading
                }
            }

            // Observar canGoBack/canGoForward
            let backObservation = webView.observe(\.canGoBack, options: .new) { [weak self] webView, _ in
                DispatchQueue.main.async {
                    self?.tab.canGoBack = webView.canGoBack
                }
            }

            let forwardObservation = webView.observe(\.canGoForward, options: .new) { [weak self] webView, _ in
                DispatchQueue.main.async {
                    self?.tab.canGoForward = webView.canGoForward
                }
            }

            observations = [
                urlObservation,
                titleObservation,
                progressObservation,
                loadingObservation,
                backObservation,
                forwardObservation
            ]
        }

        // MARK: - WKNavigationDelegate

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            tab.isLoading = true
            browserState.isLoading = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            tab.isLoading = false
            browserState.isLoading = false
            tab.updateFromWebView(webView)

            // Registrar en historial
            if let url = webView.url?.absoluteString {
                HistoryManager.shared.recordVisit(
                    url: url,
                    title: webView.title ?? url
                )
            }

            // Obtener favicon
            fetchFavicon(for: webView)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            tab.isLoading = false
            browserState.isLoading = false
            print("Navigation failed: \(error.localizedDescription)")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            tab.isLoading = false
            browserState.isLoading = false
            print("Provisional navigation failed: \(error.localizedDescription)")
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Permitir toda navegación por ahora
            // TODO: Implementar bloqueo de ads/trackers aquí
            decisionHandler(.allow)
        }

        // MARK: - WKUIDelegate

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            // Abrir links con target="_blank" en nueva pestaña
            if let url = navigationAction.request.url {
                browserState.createTab(url: url.absoluteString)
            }
            return nil
        }

        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            let alert = NSAlert()
            alert.messageText = "Mensaje de la página"
            alert.informativeText = message
            alert.addButton(withTitle: "OK")
            alert.runModal()
            completionHandler()
        }

        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            let alert = NSAlert()
            alert.messageText = "Confirmar"
            alert.informativeText = message
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Cancelar")
            let response = alert.runModal()
            completionHandler(response == .alertFirstButtonReturn)
        }

        // MARK: - Helpers

        private func fetchFavicon(for webView: WKWebView) {
            guard let url = webView.url else { return }

            let faviconURL = url.scheme.map { "\($0)://\(url.host ?? "")/favicon.ico" } ?? ""
            guard let iconURL = URL(string: faviconURL) else { return }

            URLSession.shared.dataTask(with: iconURL) { [weak self] data, _, _ in
                if let data = data, let image = NSImage(data: data) {
                    DispatchQueue.main.async {
                        self?.tab.favicon = image
                    }
                }
            }.resume()
        }
    }
}

