import SwiftUI
import WebKit

/// Container que envuelve WKWebView para uso en SwiftUI
/// Mantiene todas las WebViews vivas y solo muestra la actual
/// Tabs suspendidas muestran un snapshot en lugar de WebView
struct WebViewContainer: View {
    @EnvironmentObject var browserState: BrowserState

    var body: some View {
        ZStack {
            if browserState.tabs.isEmpty {
                EmptyStateView()
            } else {
                // Mantener todas las WebViews vivas, solo mostrar la actual
                ForEach(browserState.tabs) { tab in
                    if tab.isSuspended {
                        // Tab suspendida: mostrar snapshot
                        SuspendedTabView(tab: tab)
                            .opacity(tab.id == browserState.currentTab?.id ? 1 : 0)
                            .allowsHitTesting(tab.id == browserState.currentTab?.id)
                    } else {
                        // Tab activa: mostrar WebView
                        WebViewRepresentable(tab: tab, browserState: browserState)
                            .opacity(tab.id == browserState.currentTab?.id ? 1 : 0)
                            .allowsHitTesting(tab.id == browserState.currentTab?.id)
                    }
                }
            }
        }
    }
}

/// Vista para tabs suspendidas - muestra snapshot con opción de restaurar
struct SuspendedTabView: View {
    @ObservedObject var tab: Tab
    @EnvironmentObject var browserState: BrowserState

    var body: some View {
        ZStack {
            // Fondo
            Color(NSColor.textBackgroundColor)

            // Snapshot si existe
            if let snapshot = tab.suspendedSnapshot {
                Image(nsImage: snapshot)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .opacity(0.5)
                    .blur(radius: 2)
            }

            // Overlay con mensaje
            VStack(spacing: 16) {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)

                Text("Tab Suspendida")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(tab.title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Text("💾 RAM liberada: ~70 MB")
                    .font(.caption)
                    .foregroundColor(.green)

                Button(action: { browserState.resumeTab(tab) }) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Restaurar Tab")
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(NSColor.windowBackgroundColor).opacity(0.95))
                    .shadow(radius: 10)
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Controlador de ventana para popups OAuth
class OAuthWindowController: NSWindowController, WKNavigationDelegate {
    private var popupWebView: WKWebView?
    private static var activeControllers: [OAuthWindowController] = []

    convenience init(window: NSWindow, webView: WKWebView) {
        self.init(window: window)
        self.popupWebView = webView

        // Mantener referencia activa
        OAuthWindowController.activeControllers.append(self)

        // Observar cuando se cierra la ventana
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose),
            name: NSWindow.willCloseNotification,
            object: window
        )
    }

    @objc private func windowWillClose(_ notification: Notification) {
        // Remover de controllers activos
        OAuthWindowController.activeControllers.removeAll { $0 === self }
        NotificationCenter.default.removeObserver(self)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
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

        // Forzar que WKWebView siga el tema del sistema (no heredar de la app)
        webView.underPageBackgroundColor = NSColor.textBackgroundColor

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
    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
        var tab: Tab
        var browserState: BrowserState
        private var observations: [NSKeyValueObservation] = []
        private var activeDownloads: [WKDownload: URL] = [:]

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

            // Debug: ver a dónde estamos navegando
            if let url = webView.url {
                print("📍 Navegación iniciada: \(url.absoluteString)")
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            tab.isLoading = false
            browserState.isLoading = false

            // Si terminamos de cargar SafeLinks, extraer y navegar a URL real
            if let currentURL = webView.url,
               currentURL.absoluteString.contains("safelinks.protection.outlook.com") {
                if let realURL = extractSafeLinksURL(from: currentURL) {
                    print("🔗 SafeLinks cargó, redirigiendo a: \(realURL.absoluteString)")
                    webView.load(URLRequest(url: realURL))
                    return
                }
            }

            tab.updateFromWebView(webView)

            // No registrar SafeLinks ni about:blank en historial
            if let url = webView.url?.absoluteString,
               !url.contains("safelinks.protection.outlook.com"),
               url != "about:blank" {
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

            // Bloquear navegación a about:blank que viene de SafeLinks (borra la página)
            if url.absoluteString == "about:blank" {
                // Verificar si la página actual es SafeLinks
                if let currentURL = webView.url?.absoluteString,
                   currentURL.contains("safelinks.protection.outlook.com") {
                    print("🚫 Bloqueando redirección a about:blank desde SafeLinks")
                    decisionHandler(.cancel)
                    return
                }
                // También bloquear si la pestaña tiene una URL real y alguien quiere borrarla
                if let currentURL = webView.url,
                   currentURL.absoluteString != "about:blank",
                   !currentURL.absoluteString.isEmpty {
                    print("🚫 Bloqueando redirección sospechosa a about:blank")
                    decisionHandler(.cancel)
                    return
                }
            }

            // Interceptar Microsoft SafeLinks y extraer URL real
            if let realURL = extractSafeLinksURL(from: url) {
                print("🔗 SafeLinks interceptado, redirigiendo a: \(realURL.absoluteString)")
                decisionHandler(.cancel)
                DispatchQueue.main.async {
                    webView.load(URLRequest(url: realURL))
                }
                return
            }

            // Verificar si debe bloquearse (respeta whitelist de OAuth)
            if PrivacyManager.shared.shouldBlock(url: url) {
                PrivacyManager.shared.recordBlockedRequest(url: url, type: .tracker)
                print("🛡️ Bloqueado: \(url.host ?? url.absoluteString)")
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }

        /// Extrae la URL real de Microsoft SafeLinks
        private func extractSafeLinksURL(from url: URL) -> URL? {
            guard let host = url.host?.lowercased(),
                  host.contains("safelinks.protection.outlook.com") else {
                return nil
            }

            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let queryItems = components.queryItems,
                  let urlParam = queryItems.first(where: { $0.name == "url" })?.value,
                  let decodedString = urlParam.removingPercentEncoding,
                  let realURL = URL(string: decodedString) else {
                return nil
            }

            return realURL
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
            let targetURL = navigationAction.request.url
            let sourceURL = navigationAction.sourceFrame.request.url

            print("🔗 createWebViewWith:")
            print("   - Target URL: \(targetURL?.absoluteString ?? "nil")")
            print("   - Source URL: \(sourceURL?.absoluteString ?? "nil")")

            // Caso especial: URL es about:blank o nil pero tenemos un sourceURL de SafeLinks
            // SafeLinks usa window.open('about:blank') y luego navega via JavaScript
            if (targetURL == nil || targetURL?.absoluteString == "about:blank") {
                // Verificar si el source es SafeLinks
                if let source = sourceURL, source.absoluteString.contains("safelinks.protection.outlook.com") {
                    // Extraer la URL real del SafeLinks source
                    if let realURL = extractSafeLinksURL(from: source) {
                        print("🔗 SafeLinks detectado en source, abriendo: \(realURL.absoluteString)")
                        browserState.createTab(url: realURL.absoluteString)
                        return nil
                    }
                }

                // Si no podemos extraer nada útil, retornar nil
                print("🔗 window.open con about:blank sin URL útil - ignorando")
                return nil
            }

            guard let url = targetURL else { return nil }

            // Interceptar SafeLinks y extraer URL real
            if let realURL = extractSafeLinksURL(from: url) {
                print("🔗 SafeLinks en target, redirigiendo a: \(realURL.absoluteString)")
                browserState.createTab(url: realURL.absoluteString)
                return nil
            }

            // Detectar si es un popup de OAuth
            let isPopup = windowFeatures.menuBarVisibility?.boolValue == false ||
                          windowFeatures.toolbarsVisibility?.boolValue == false ||
                          (windowFeatures.width != nil && windowFeatures.height != nil)

            let oauthDomains = ["accounts.google.com", "login.microsoftonline.com",
                               "appleid.apple.com", "github.com", "auth0.com",
                               "clerk.com", "anthropic.com", "claude.ai"]

            let isOAuthDomain = oauthDomains.contains { url.host?.contains($0) == true }

            if isPopup || isOAuthDomain {
                return createOAuthPopupWindow(configuration: configuration, url: url, windowFeatures: windowFeatures)
            } else {
                browserState.createTab(url: url.absoluteString)
                return nil
            }
        }

        /// Crea una ventana popup para flujos OAuth
        private func createOAuthPopupWindow(configuration: WKWebViewConfiguration, url: URL, windowFeatures: WKWindowFeatures) -> WKWebView? {
            // Crear WebView para el popup
            let popupWebView = WKWebView(frame: .zero, configuration: configuration)
            popupWebView.navigationDelegate = self
            popupWebView.uiDelegate = self

            // User agent de Safari
            popupWebView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.2 Safari/605.1.15"

            // Calcular tamaño de ventana
            let width = windowFeatures.width?.doubleValue ?? 500
            let height = windowFeatures.height?.doubleValue ?? 700

            // Crear ventana
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Iniciar sesión"
            window.contentView = popupWebView
            window.center()

            // CRÍTICO: Hacer que la ventana aparezca al frente
            window.level = .floating  // Siempre encima de ventanas normales
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)

            // Guardar referencia para que no se destruya
            let windowController = OAuthWindowController(window: window, webView: popupWebView)
            windowController.showWindow(nil)

            // Después de 1 segundo, bajar el nivel para que no sea molesto
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                window.level = .normal
            }

            print("🔐 Popup OAuth abierto: \(url.host ?? url.absoluteString)")

            return popupWebView
        }

        /// Cerrar popup cuando OAuth termina
        func webViewDidClose(_ webView: WKWebView) {
            // Buscar y cerrar la ventana del popup
            for window in NSApp.windows {
                if window.contentView == webView {
                    window.close()
                    print("🔐 Popup OAuth cerrado")
                    break
                }
            }
        }

        // MARK: - Media Permissions (Camera/Microphone)

        /// Manejar solicitudes de permisos de cámara y micrófono
        func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            let mediaType: String
            switch type {
            case .camera:
                mediaType = "cámara"
            case .microphone:
                mediaType = "micrófono"
            case .cameraAndMicrophone:
                mediaType = "cámara y micrófono"
            @unknown default:
                mediaType = "dispositivo multimedia"
            }

            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Permiso de \(mediaType)"
                alert.informativeText = "\(origin.host) quiere acceder a tu \(mediaType).\n\n¿Permitir acceso?"
                alert.alertStyle = .informational
                alert.addButton(withTitle: "Permitir")
                alert.addButton(withTitle: "Denegar")

                let response = alert.runModal()
                if response == .alertFirstButtonReturn {
                    print("🎥 Permiso de \(mediaType) concedido a \(origin.host)")
                    decisionHandler(.grant)
                } else {
                    print("🎥 Permiso de \(mediaType) denegado a \(origin.host)")
                    decisionHandler(.deny)
                }
            }
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

        // MARK: - Downloads

        /// Manejar respuestas de navegación que deberían ser descargas
        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            // Verificar si es un archivo descargable
            if let mimeType = navigationResponse.response.mimeType {
                let downloadableMimeTypes = [
                    "application/octet-stream",
                    "application/zip",
                    "application/pdf",
                    "application/x-tar",
                    "application/gzip",
                    "application/x-gzip",
                    "application/x-compressed",
                    "application/x-download",
                    "application/force-download",
                    "application/json",
                    "text/plain",
                    "text/csv"
                ]

                // Si el Content-Disposition indica descarga o es un tipo descargable
                let isAttachment = (navigationResponse.response as? HTTPURLResponse)?
                    .value(forHTTPHeaderField: "Content-Disposition")?
                    .contains("attachment") ?? false

                let isDownloadableMime = downloadableMimeTypes.contains(mimeType) ||
                                         mimeType.hasPrefix("application/") && !mimeType.contains("html")

                if isAttachment || (isDownloadableMime && !navigationResponse.canShowMIMEType) {
                    // Iniciar descarga
                    decisionHandler(.download)
                    return
                }
            }

            decisionHandler(.allow)
        }

        /// Cuando se inicia una descarga desde navegación
        func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
            download.delegate = self
            print("📥 Descarga iniciada desde navegación")
        }

        /// Cuando se inicia una descarga desde acción (click en link de descarga)
        func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
            download.delegate = self
            print("📥 Descarga iniciada desde acción")
        }

        // MARK: - WKDownloadDelegate

        func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
            // Mostrar diálogo de guardar archivo
            DispatchQueue.main.async {
                let savePanel = NSSavePanel()
                savePanel.nameFieldStringValue = suggestedFilename
                savePanel.canCreateDirectories = true

                // Intentar detectar la extensión
                if let ext = suggestedFilename.components(separatedBy: ".").last {
                    savePanel.allowedContentTypes = [.init(filenameExtension: ext) ?? .data]
                }

                if savePanel.runModal() == .OK, let url = savePanel.url {
                    self.activeDownloads[download] = url
                    print("📥 Guardando en: \(url.path)")
                    completionHandler(url)
                } else {
                    print("📥 Descarga cancelada por usuario")
                    completionHandler(nil)
                }
            }
        }

        func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
            activeDownloads.removeValue(forKey: download)
            print("❌ Error en descarga: \(error.localizedDescription)")

            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Error de descarga"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }

        func downloadDidFinish(_ download: WKDownload) {
            if let url = activeDownloads.removeValue(forKey: download) {
                print("✅ Descarga completada: \(url.lastPathComponent)")

                DispatchQueue.main.async {
                    // Mostrar notificación de éxito
                    let alert = NSAlert()
                    alert.messageText = "Descarga completada"
                    alert.informativeText = url.lastPathComponent
                    alert.alertStyle = .informational
                    alert.addButton(withTitle: "Abrir")
                    alert.addButton(withTitle: "Mostrar en Finder")
                    alert.addButton(withTitle: "OK")

                    let response = alert.runModal()
                    if response == .alertFirstButtonReturn {
                        // Abrir archivo
                        NSWorkspace.shared.open(url)
                    } else if response == .alertSecondButtonReturn {
                        // Mostrar en Finder
                        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
                    }
                }
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

