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

/// Gestor centralizado de configuración web para compartir cookies entre tabs
class WebViewConfigurationManager {
    static let shared = WebViewConfigurationManager()

    /// Data store persistente compartido entre todas las tabs
    let dataStore: WKWebsiteDataStore

    private init() {
        // Usar el data store por defecto que persiste cookies y sesiones
        self.dataStore = WKWebsiteDataStore.default()
    }

    /// Crea una configuración para una nueva WebView
    func createConfiguration() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()

        // CRÍTICO: Usar data store persistente para cookies/sesiones OAuth
        config.websiteDataStore = dataStore

        // Identificarse como Safari en la configuración
        config.applicationNameForUserAgent = "Version/18.2 Safari/605.1.15"

        // Preferencias de JavaScript
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        // Habilitar fullscreen de elementos HTML5
        if #available(macOS 12.0, *) {
            config.preferences.isElementFullscreenEnabled = true
        }

        // Habilitar reproducción de medios sin interacción
        config.mediaTypesRequiringUserActionForPlayback = []
        config.suppressesIncrementalRendering = false

        // Preferencias web - CRÍTICO para Google
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        if #available(macOS 12.3, *) {
            preferences.preferredContentMode = .desktop
        }
        config.defaultWebpagePreferences = preferences

        // Inyectar script anti-detección al inicio de cada página
        let antiDetectionScript = WKUserScript(
            source: Self.navigatorSpoofingScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false  // También en iframes (importante para OAuth)
        )
        config.userContentController.addUserScript(antiDetectionScript)

        return config
    }

    /// Script para ocultar propiedades que delatan WKWebView
    private static let navigatorSpoofingScript = """
    (function() {
        // Ocultar detección de WebDriver (WKWebView lo expone)
        Object.defineProperty(navigator, 'webdriver', {
            get: () => false,
            configurable: true
        });

        // Vendor correcto de Safari
        Object.defineProperty(navigator, 'vendor', {
            get: () => 'Apple Computer, Inc.',
            configurable: true
        });

        // Plataforma correcta
        Object.defineProperty(navigator, 'platform', {
            get: () => 'MacIntel',
            configurable: true
        });

        // Ocultar userAgentData (Chrome-specific, Safari no lo tiene)
        Object.defineProperty(navigator, 'userAgentData', {
            get: () => undefined,
            configurable: true
        });

        // Eliminar rastros de Chrome si existen
        if (window.chrome !== undefined) {
            delete window.chrome;
        }

        // Asegurar que plugins parezcan de Safari
        Object.defineProperty(navigator, 'plugins', {
            get: () => {
                return {
                    length: 5,
                    item: (i) => null,
                    namedItem: (name) => null,
                    refresh: () => {}
                };
            },
            configurable: true
        });

        // Languages de Safari
        Object.defineProperty(navigator, 'languages', {
            get: () => ['es-ES', 'es', 'en-US', 'en'],
            configurable: true
        });
    })();
    """
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
        // Usar configuración compartida para persistir cookies y sesiones OAuth
        let config = WebViewConfigurationManager.shared.createConfiguration()

        // Crear WebView con configuración compartida
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true

        // User-Agent de Safari 18.2 (macOS Sequoia) para compatibilidad con Google
        // Usar formato estándar que Google reconoce
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.2 Safari/605.1.15"

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
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            // Verificar si debe bloquearse (respeta whitelist de OAuth)
            if PrivacyManager.shared.shouldBlock(url: url) {
                PrivacyManager.shared.recordBlockedRequest()
                print("🛡️ Bloqueado: \(url.host ?? url.absoluteString)")
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }

        // Manejar challenges de autenticación (certificados HTTPS, auth básica)
        func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            let protectionSpace = challenge.protectionSpace

            // Manejar certificados de servidor (HTTPS)
            if protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
                if let serverTrust = protectionSpace.serverTrust {
                    let credential = URLCredential(trust: serverTrust)
                    completionHandler(.useCredential, credential)
                    return
                }
            }

            // Manejar autenticación HTTP básica (mostrar diálogo)
            if protectionSpace.authenticationMethod == NSURLAuthenticationMethodHTTPBasic ||
               protectionSpace.authenticationMethod == NSURLAuthenticationMethodHTTPDigest {
                DispatchQueue.main.async {
                    self.showAuthenticationDialog(for: protectionSpace) { username, password in
                        if let username = username, let password = password {
                            let credential = URLCredential(user: username, password: password, persistence: .forSession)
                            completionHandler(.useCredential, credential)
                        } else {
                            completionHandler(.cancelAuthenticationChallenge, nil)
                        }
                    }
                }
                return
            }

            // Para otros tipos, usar el comportamiento por defecto
            completionHandler(.performDefaultHandling, nil)
        }

        private func showAuthenticationDialog(for protectionSpace: URLProtectionSpace, completion: @escaping (String?, String?) -> Void) {
            let alert = NSAlert()
            alert.messageText = "Autenticación requerida"
            alert.informativeText = "El sitio \(protectionSpace.host) requiere usuario y contraseña"
            alert.addButton(withTitle: "Iniciar sesión")
            alert.addButton(withTitle: "Cancelar")

            let usernameField = NSTextField(frame: NSRect(x: 0, y: 28, width: 200, height: 24))
            usernameField.placeholderString = "Usuario"

            let passwordField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
            passwordField.placeholderString = "Contraseña"

            let stackView = NSStackView(views: [usernameField, passwordField])
            stackView.orientation = .vertical
            stackView.spacing = 4
            stackView.frame = NSRect(x: 0, y: 0, width: 200, height: 56)

            alert.accessoryView = stackView

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                completion(usernameField.stringValue, passwordField.stringValue)
            } else {
                completion(nil, nil)
            }
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

        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
            let alert = NSAlert()
            alert.messageText = prompt
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Cancelar")

            let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
            textField.stringValue = defaultText ?? ""
            alert.accessoryView = textField

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                completionHandler(textField.stringValue)
            } else {
                completionHandler(nil)
            }
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

