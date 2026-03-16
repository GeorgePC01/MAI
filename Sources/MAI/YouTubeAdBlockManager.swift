import Foundation
import WebKit
import Combine

/// Gestiona el bloqueo de anuncios de YouTube mediante 5 capas de defensa:
/// 0. ServiceWorker blocking (evita que YouTube cachee datos de ads)
/// 1. JS injection (JSON.parse override + fetch/XHR intercept + property traps + player API patch)
/// 2. CSS cosmético (oculta elementos de UI de ads)
/// 3. Active monitoring (MutationObserver + polling 250ms + video src tracking + skip forzado)
/// 4. WKContentRuleList (bloqueo de URLs de ads a nivel de red)
/// 5. Post-load cleanup script (atDocumentEnd) + re-injection on SPA navigation
class YouTubeAdBlockManager: ObservableObject {
    static let shared = YouTubeAdBlockManager()

    @Published var blockYouTubeAds: Bool {
        didSet {
            UserDefaults.standard.set(blockYouTubeAds, forKey: "blockYouTubeAds")
        }
    }

    @Published var adsBlocked: Int {
        didSet {
            UserDefaults.standard.set(adsBlocked, forKey: "youtubeAdsBlocked")
        }
    }

    /// Compiled WKContentRuleList for network-level blocking
    var compiledRuleList: WKContentRuleList?

    /// Script descargado del servidor (cifrado, más reciente que el embebido)
    private var _remoteAdBlockScript: String?
    private var _remoteCleanupScript: String?
    private var _lastRemoteFetch: Date?

    private init() {
        self.blockYouTubeAds = UserDefaults.standard.object(forKey: "blockYouTubeAds") as? Bool ?? true
        self.adsBlocked = UserDefaults.standard.integer(forKey: "youtubeAdsBlocked")
        // Intentar cargar scripts remotos en background
        _fetchRemoteScripts()
    }

    func incrementAdsBlocked() {
        DispatchQueue.main.async {
            self.adsBlocked += 1
        }
    }

    func resetCount() {
        adsBlocked = 0
    }

    // MARK: - Shadow WebView (Doble Reproducción)
    // Un WebView invisible "absorbe" los ads. Cuando el contenido está limpio,
    // el WebView principal recarga la misma URL (YouTube no repite ads en la misma sesión).

    /// Shadow WebView que reproduce ads en background
    private var shadowWebView: WKWebView?
    /// Delegate del shadow WebView
    private var shadowDelegate: ShadowNavigationDelegate?
    /// URL que el shadow está procesando
    private var shadowURL: URL?
    /// Timer para monitorear el shadow
    private var shadowTimer: Timer?
    /// Callback cuando el shadow terminó de procesar ads
    private var shadowCompletion: ((URL) -> Void)?
    /// Tiempo máximo de espera para el shadow (segundos)
    private let shadowTimeout: TimeInterval = 30

    /// Inicia la doble reproducción: crea un shadow WebView que absorbe los ads
    func startShadowPlayback(url: URL, dataStore: WKWebsiteDataStore, completion: @escaping (URL) -> Void) {
        // Limpiar shadow anterior si existe
        cleanupShadow()

        guard url.host?.contains("youtube.com") == true,
              url.absoluteString.contains("/watch") else {
            completion(url) // No es YouTube video, pasar directo
            return
        }

        print("🎭 Shadow WebView: iniciando para \(url.absoluteString)")
        shadowURL = url
        shadowCompletion = completion

        // Crear configuración mínima para el shadow (comparte cookies via dataStore)
        let config = WKWebViewConfiguration()
        config.websiteDataStore = dataStore // MISMAS cookies que el principal
        config.mediaTypesRequiringUserActionForPlayback = [] // Autoplay
        config.applicationNameForUserAgent = "Version/18.2 Safari/605.1.15"

        // Script que: 1) mute video, 2) acelera ads, 3) notifica cuando contenido limpio
        let shadowScript = WKUserScript(
            source: shadowMonitorScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(shadowScript)

        // Crear delegate
        let delegate = ShadowNavigationDelegate(manager: self)
        config.userContentController.add(delegate, name: "maiShadowReady")
        shadowDelegate = delegate

        // Crear WebView oculto (1x1 pixel, fuera de pantalla)
        let webView = WKWebView(frame: NSRect(x: -9999, y: -9999, width: 1, height: 1), configuration: config)
        webView.navigationDelegate = delegate
        webView.customUserAgent = ChromeCompatManager.safariUserAgent
        shadowWebView = webView

        // Cargar la URL
        webView.load(URLRequest(url: url))

        // Timer de timeout
        let startTime = Date()
        shadowTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            let elapsed = Date().timeIntervalSince(startTime)

            if elapsed >= self.shadowTimeout {
                // Timeout — el shadow no pudo terminar, enviar al principal de todos modos
                print("🎭 Shadow WebView: timeout después de \(Int(elapsed))s, continuando")
                self.shadowComplete()
            }
        }
    }

    /// Script JS para el shadow WebView — mute, acelera, y detecta cuando termina el ad
    private var shadowMonitorScript: String {
        return """
        (function() {
            if (!location.hostname.includes('youtube.com')) return;

            var _checkCount = 0;
            var _adSeen = false;
            var _contentReady = false;

            function checkState() {
                _checkCount++;
                var player = document.querySelector('.html5-video-player');
                var video = document.querySelector('video');

                // Siempre mantener mute
                if (video) {
                    video.muted = true;
                    video.volume = 0;
                }

                if (!player) return;

                var isAd = player.classList.contains('ad-showing')
                    || player.classList.contains('ad-interrupting');

                if (isAd) {
                    _adSeen = true;
                    // Acelerar el ad al máximo
                    if (video) {
                        try { video.playbackRate = 16; } catch(e) {
                            try { video.playbackRate = 8; } catch(e2) {}
                        }
                        // Saltar al final
                        if (video.duration && isFinite(video.duration) && video.duration > 0) {
                            video.currentTime = video.duration - 0.1;
                        }
                    }
                    // Click skip buttons
                    var skips = document.querySelectorAll(
                        '.ytp-skip-ad-button, .ytp-ad-skip-button, [id^="skip-button"], .ytp-ad-skip-button-modern'
                    );
                    for (var i = 0; i < skips.length; i++) {
                        try { skips[i].click(); } catch(e) {}
                    }
                    // Cerrar popups
                    var popups = document.querySelectorAll(
                        'tp-yt-iron-overlay-backdrop, ytd-enforcement-message-view-model, ' +
                        'ytd-mealbar-promo-renderer, yt-upsell-dialog-renderer'
                    );
                    for (var p = 0; p < popups.length; p++) {
                        try { popups[p].remove(); } catch(e) {}
                    }
                    // Dismiss buttons
                    var dismiss = document.querySelectorAll(
                        '#dismiss-button, button[aria-label="Close"], button[aria-label="Cerrar"], ' +
                        '.yt-mealbar-promo-renderer__dismiss-button'
                    );
                    for (var d = 0; d < dismiss.length; d++) {
                        try { dismiss[d].click(); } catch(e) {}
                    }
                } else if (_adSeen || _checkCount > 20) {
                    // Ad terminó o nunca hubo ad (después de 10s de checks)
                    if (!_contentReady) {
                        _contentReady = true;
                        // Pausar video del shadow para no consumir bandwidth
                        if (video) {
                            video.pause();
                            video.muted = true;
                        }
                        // Notificar a Swift que el contenido está listo
                        try {
                            window.webkit.messageHandlers.maiShadowReady.postMessage('ready');
                        } catch(e) {}
                    }
                }
            }

            // Polling agresivo 100ms
            setInterval(checkState, 100);

            // También notificar si el video empieza a reproducir contenido
            function onVideoPlay() {
                var player = document.querySelector('.html5-video-player');
                if (player && !player.classList.contains('ad-showing')) {
                    if (!_contentReady) {
                        _contentReady = true;
                        var video = document.querySelector('video');
                        if (video) { video.pause(); video.muted = true; }
                        try {
                            window.webkit.messageHandlers.maiShadowReady.postMessage('ready');
                        } catch(e) {}
                    }
                }
            }

            // Esperar a que el video element exista
            function waitForVideo() {
                var video = document.querySelector('video');
                if (video) {
                    video.muted = true;
                    video.volume = 0;
                    video.addEventListener('playing', onVideoPlay);
                } else {
                    setTimeout(waitForVideo, 200);
                }
            }
            waitForVideo();
        })();
        """
    }

    /// Llamado cuando el shadow terminó de procesar ads
    func shadowComplete() {
        guard let url = shadowURL, let completion = shadowCompletion else {
            cleanupShadow()
            return
        }
        print("🎭 Shadow WebView: ads absorbidos, recargando en principal")
        let savedCompletion = completion
        let savedURL = url
        cleanupShadow()
        DispatchQueue.main.async {
            savedCompletion(savedURL)
        }
    }

    /// Limpiar shadow WebView y recursos
    func cleanupShadow() {
        shadowTimer?.invalidate()
        shadowTimer = nil
        shadowWebView?.stopLoading()
        shadowWebView?.navigationDelegate = nil
        if let delegate = shadowDelegate {
            shadowWebView?.configuration.userContentController.removeScriptMessageHandler(forName: "maiShadowReady")
        }
        shadowWebView = nil
        shadowDelegate = nil
        shadowURL = nil
        shadowCompletion = nil
    }

    /// Verifica si una URL es un video de YouTube que necesita shadow playback
    func isYouTubeVideo(_ url: URL) -> Bool {
        guard let host = url.host else { return false }
        return host.contains("youtube.com") && url.absoluteString.contains("/watch")
    }

    // MARK: - Capa 4: WKContentRuleList (Network-level blocking)

    func compileNetworkRules() async {
        let rules = """
        [
            { "trigger": { "url-filter": "doubleclick\\\\.net", "if-domain": ["*youtube.com"] }, "action": { "type": "block" } },
            { "trigger": { "url-filter": "/pagead/", "if-domain": ["*youtube.com"] }, "action": { "type": "block" } },
            { "trigger": { "url-filter": "/api/stats/ads", "if-domain": ["*youtube.com"] }, "action": { "type": "block" } },
            { "trigger": { "url-filter": "ptracking", "if-domain": ["*youtube.com"] }, "action": { "type": "block" } },
            { "trigger": { "url-filter": "get_midroll_info", "if-domain": ["*youtube.com"] }, "action": { "type": "block" } },
            { "trigger": { "url-filter": "/pagead/interaction/", "if-domain": ["*youtube.com"] }, "action": { "type": "block" } },
            { "trigger": { "url-filter": "googleads\\\\.g\\\\.doubleclick\\\\.net" }, "action": { "type": "block" } },
            { "trigger": { "url-filter": "ad\\\\.youtube\\\\.com" }, "action": { "type": "block" } },
            { "trigger": { "url-filter": "youtube\\\\.com/get_video_info.*ad" }, "action": { "type": "block" } },
            { "trigger": { "url-filter": "/youtubei/v1/log_event", "if-domain": ["*youtube.com"] }, "action": { "type": "block" } },
            { "trigger": { "url-filter": "play\\\\.google\\\\.com/log", "if-domain": ["*youtube.com"] }, "action": { "type": "block" } },
            { "trigger": { "url-filter": "/youtubei/v1/ad_break", "if-domain": ["*youtube.com"] }, "action": { "type": "block" } }
        ]
        """

        do {
            let ruleList = try await WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: "YouTubeAdBlock",
                encodedContentRuleList: rules
            )
            await MainActor.run {
                self.compiledRuleList = ruleList
                print("🛡️ YouTube ad block rules compiled (13 rules)")
            }
        } catch {
            print("⚠️ Failed to compile YouTube ad block rules: \(error)")
        }
    }

    // MARK: - Remote Script Loading (punto 7: scripts efímeros desde servidor)

    /// Intenta descargar scripts actualizados del servidor MAI.
    /// Los scripts remotos están cifrados con la misma clave AES y son efímeros
    /// (no se guardan en disco, solo en memoria de la sesión actual).
    private func _fetchRemoteScripts() {
        guard let url = URL(string: "https://mai-browser.com/api/v1/scripts") else { return }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
        request.httpMethod = "GET"
        request.setValue(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0", forHTTPHeaderField: "X-MAI-Version")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self, error == nil,
                  let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let data = data else { return }

            // Respuesta: JSON con { "adblock": "<base64 encrypted>", "cleanup": "<base64 encrypted>", "version": N }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let adblockB64 = json["adblock"] as? String,
                  let adblockData = Data(base64Encoded: adblockB64) else { return }

            let decrypted = WKRenderPipeline.shared.decrypt(identifier: "remote_adblock", data: adblockData)
            if !decrypted.isEmpty {
                DispatchQueue.main.async {
                    self._remoteAdBlockScript = decrypted
                    self._lastRemoteFetch = Date()
                    WKRenderPipeline.shared.evict(identifier: "remote_adblock")
                }
            }

            if let cleanupB64 = json["cleanup"] as? String,
               let cleanupData = Data(base64Encoded: cleanupB64) {
                let cleanupDecrypted = WKRenderPipeline.shared.decrypt(identifier: "remote_cleanup", data: cleanupData)
                if !cleanupDecrypted.isEmpty {
                    DispatchQueue.main.async {
                        self._remoteCleanupScript = cleanupDecrypted
                        WKRenderPipeline.shared.evict(identifier: "remote_cleanup")
                    }
                }
            }
        }.resume()
    }

    // MARK: - Script principal (atDocumentStart)

    var adBlockScript: String {
        // DEBUG: inyectar script raw desde disco para testing directo
        #if DEBUG
        if let rawPath = Bundle.main.resourceURL?.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Tools/scripts/adblock.js"),
           let rawScript = try? String(contentsOf: rawPath, encoding: .utf8), !rawScript.isEmpty {
            print("🛡️ YouTube AdBlock: usando script RAW desde disco (\(rawScript.count) chars)")
            return rawScript
        }
        // Fallback: leer desde path absoluto del proyecto
        if let rawScript = try? String(contentsOfFile: NSHomeDirectory() + "/Documents/MAI/Tools/scripts/adblock.js", encoding: .utf8), !rawScript.isEmpty {
            print("🛡️ YouTube AdBlock: usando script RAW desde ~/Documents/MAI (\(rawScript.count) chars)")
            return rawScript
        }
        print("⚠️ YouTube AdBlock: no se pudo leer script raw, intentando descifrado")
        #endif

        // Prioridad 1: script remoto (más reciente, efímero)
        if let remote = _remoteAdBlockScript, !remote.isEmpty { return remote }

        // Prioridad 2: script embebido cifrado
        let decrypted = WKRenderPipeline.shared.decryptFragmented(
            identifier: "adblock",
            fragments: [
                EncryptedScripts.adblock_f0, EncryptedScripts.adblock_f1,
                EncryptedScripts.adblock_f2, EncryptedScripts.adblock_f3,
                EncryptedScripts.adblock_f4, EncryptedScripts.adblock_f5,
                EncryptedScripts.adblock_f6, EncryptedScripts.adblock_f7
            ],
            order: EncryptedScripts.adblock_order,
            salts: EncryptedScripts.adblock_salts,
            expectedHash: EncryptedScripts.adblock_hash
        )
        if !decrypted.isEmpty {
            print("🛡️ YouTube AdBlock: script descifrado OK (\(decrypted.count) chars)")
            return decrypted
        }
        print("⚠️ YouTube AdBlock: descifrado FALLÓ — usando fallback CSS")

        // Fallback mínimo: solo CSS cosmético si todo falla
        return """
        (function() {
            if (!location.hostname.includes('youtube.com')) return;
            var c=document.createElement('style');c.textContent='ytd-ad-slot-renderer,ytd-banner-promo-renderer,ytd-in-feed-ad-layout-renderer{display:none!important}';
            (document.head||document.documentElement).appendChild(c);
        })();
        """
    }

    // MARK: - Script post-carga (atDocumentEnd)

    var cleanupScript: String {
        if let remote = _remoteCleanupScript, !remote.isEmpty { return remote }
        let decrypted = WKRenderPipeline.shared.decryptFragmented(
            identifier: "cleanup",
            fragments: [
                EncryptedScripts.cleanup_f0, EncryptedScripts.cleanup_f1,
                EncryptedScripts.cleanup_f2, EncryptedScripts.cleanup_f3,
                EncryptedScripts.cleanup_f4, EncryptedScripts.cleanup_f5,
                EncryptedScripts.cleanup_f6, EncryptedScripts.cleanup_f7
            ],
            order: EncryptedScripts.cleanup_order,
            salts: EncryptedScripts.cleanup_salts,
            expectedHash: EncryptedScripts.cleanup_hash
        )
        if !decrypted.isEmpty { return decrypted }
        return "(function(){})();"
    }
}

// MARK: - Shadow WebView Navigation Delegate
class ShadowNavigationDelegate: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    weak var manager: YouTubeAdBlockManager?

    init(manager: YouTubeAdBlockManager) {
        self.manager = manager
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "maiShadowReady" {
            print("🎭 Shadow WebView: mensaje 'ready' recibido")
            manager?.shadowComplete()
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("🎭 Shadow WebView: página cargada")
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(.allow)
    }
}
