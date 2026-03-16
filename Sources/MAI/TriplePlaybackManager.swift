import Foundation
import WebKit

/// Triple Playback: 2 WebViews con role-swap para YouTube ad blocking sin interrupción.
/// Scout WebView corre en paralelo (muted, baja resolución), detecta y absorbe ads.
/// Cuando Main encuentra un ad → swap instantáneo: Scout se muestra, Main absorbe.
class TriplePlaybackManager {
    static let shared = TriplePlaybackManager()

    // MARK: - State Machine

    enum ScoutState: String {
        case idle           // No hay scout activo
        case loading        // Scout cargando la URL
        case scouting       // Scout reproduciendo video, monitoreando ads
        case adDetected     // Scout detectó un ad
        case absorbing      // Scout absorbiendo el ad (16x + skip)
        case swapReady      // Scout terminó de absorber, listo para ser Main
    }

    // MARK: - Properties

    /// Scout WebView (invisible, 320x180, muted)
    private(set) var scoutWebView: WKWebView?
    /// Delegate del scout
    private var scoutDelegate: ScoutNavigationDelegate?
    /// Estado actual del scout
    private(set) var scoutState: ScoutState = .idle
    /// Video ID actual
    private(set) var currentVideoID: String?
    /// URL actual del video
    private(set) var currentVideoURL: URL?
    /// Si el sistema está activo
    private(set) var isActive: Bool = false
    /// WebView principal actual (referencia weak)
    weak var mainWebView: WKWebView?
    /// Tab asociado
    weak var activeTab: Tab?
    /// Contador de videos consecutivos sin ads (auto-desactivar después de 3)
    private var consecutiveNoAds: Int = 0
    /// Timer de monitoreo
    private var monitorTimer: Timer?
    /// Timeout del scout (30s)
    private let scoutTimeout: TimeInterval = 30
    /// Timestamp de inicio del scout
    private var scoutStartTime: Date?
    /// Volumen guardado del main antes del swap
    private var savedVolume: Double = 1.0
    /// Callback para realizar el swap visual en SwiftUI
    var onSwapRequested: ((_ scoutWebView: WKWebView) -> Void)?
    /// Callback para restaurar después del swap
    var onSwapCompleted: (() -> Void)?
    /// Flag: el scout ya fue swappeado (es ahora el visible)
    private(set) var isSwapped: Bool = false

    private init() {}

    // MARK: - Lifecycle

    /// Activa triple playback para una URL de YouTube
    func activate(for tab: Tab, videoURL: URL, mainWebView: WKWebView, dataStore: WKWebsiteDataStore) {
        guard isYouTubeVideo(videoURL) else { return }

        // Si ya está activo para el mismo video, no recrear
        let videoID = extractVideoID(from: videoURL)
        if isActive && currentVideoID == videoID { return }

        print("🎬 TriplePlayback: activando para \(videoURL.absoluteString)")

        // Limpiar scout anterior
        deactivate()

        isActive = true
        activeTab = tab
        self.mainWebView = mainWebView
        currentVideoURL = videoURL
        currentVideoID = videoID
        scoutState = .loading
        consecutiveNoAds = 0
        isSwapped = false

        // Crear Scout WebView
        createScoutWebView(dataStore: dataStore, url: videoURL)
    }

    /// Desactiva triple playback y libera recursos
    func deactivate() {
        guard isActive else { return }
        print("🎬 TriplePlayback: desactivando")

        monitorTimer?.invalidate()
        monitorTimer = nil

        // Limpiar scout
        scoutWebView?.stopLoading()
        if let delegate = scoutDelegate {
            scoutWebView?.configuration.userContentController.removeScriptMessageHandler(forName: "maiScoutStatus")
        }
        scoutWebView?.navigationDelegate = nil
        scoutWebView = nil
        scoutDelegate = nil

        scoutState = .idle
        isActive = false
        currentVideoID = nil
        currentVideoURL = nil
        mainWebView = nil
        activeTab = nil
        scoutStartTime = nil
        isSwapped = false
    }

    // MARK: - Scout WebView Creation

    private func createScoutWebView(dataStore: WKWebsiteDataStore, url: URL) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = dataStore // Mismas cookies que Main
        config.mediaTypesRequiringUserActionForPlayback = [] // Autoplay

        // Inyectar script del scout
        let script = WKUserScript(
            source: scoutScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(script)

        // Message handler
        let delegate = ScoutNavigationDelegate(manager: self)
        config.userContentController.add(delegate, name: "maiScoutStatus")
        scoutDelegate = delegate

        // Scout WebView: 320x180 (baja resolución = menos RAM)
        // Posicionado fuera de pantalla
        let webView = WKWebView(
            frame: NSRect(x: -9999, y: -9999, width: 320, height: 180),
            configuration: config
        )
        webView.navigationDelegate = delegate
        webView.customUserAgent = ChromeCompatManager.safariUserAgent
        scoutWebView = webView

        // Cargar la URL
        webView.load(URLRequest(url: url))
        scoutStartTime = Date()

        // Timer de monitoreo
        monitorTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkScoutTimeout()
        }
    }

    // MARK: - Scout Messages

    /// Llamado por ScoutNavigationDelegate cuando recibe un mensaje del scout JS
    func handleScoutMessage(_ body: [String: Any]) {
        guard isActive else { return }

        guard let type = body["type"] as? String else { return }

        switch type {
        case "status":
            handleScoutStatus(body)
        case "adStart":
            handleAdStart(body)
        case "adEnd":
            handleAdEnd(body)
        case "navigation":
            handleScoutNavigation(body)
        case "noAd":
            handleNoAd(body)
        default:
            break
        }
    }

    private func handleScoutStatus(_ body: [String: Any]) {
        let isAd = body["isAd"] as? Bool ?? false
        let currentTime = body["currentTime"] as? Double ?? 0

        if isAd && scoutState == .scouting {
            scoutState = .adDetected
            print("🎬 TriplePlayback: Scout detectó ad en t=\(String(format: "%.1f", currentTime))s")
        } else if !isAd && scoutState != .idle && scoutState != .loading {
            if scoutState == .absorbing || scoutState == .adDetected {
                scoutState = .swapReady
                print("🎬 TriplePlayback: Scout terminó de absorber ad, listo para swap")
            } else {
                scoutState = .scouting
            }
        }
    }

    private func handleAdStart(_ body: [String: Any]) {
        scoutState = .absorbing
        let currentTime = body["currentTime"] as? Double ?? 0
        print("🎬 TriplePlayback: Ad iniciado en scout (t=\(String(format: "%.1f", currentTime))s)")

        // Notificar al Main que se prepare para swap
        checkSwapCondition()
    }

    private func handleAdEnd(_ body: [String: Any]) {
        scoutState = .swapReady
        let currentTime = body["currentTime"] as? Double ?? 0
        print("🎬 TriplePlayback: Ad terminado en scout (t=\(String(format: "%.1f", currentTime))s)")

        // Si el Main también tiene un ad, hacer swap ahora
        checkMainForAd()
    }

    private func handleNoAd(_ body: [String: Any]) {
        consecutiveNoAds += 1
        scoutState = .scouting

        if consecutiveNoAds >= 3 {
            print("🎬 TriplePlayback: 3 videos sin ads, auto-desactivando")
            deactivate()
        }
    }

    private func handleScoutNavigation(_ body: [String: Any]) {
        guard let newVideoID = body["videoId"] as? String else { return }

        if newVideoID != currentVideoID {
            print("🎬 TriplePlayback: Scout detectó navegación SPA → \(newVideoID)")
            currentVideoID = newVideoID
            scoutState = .scouting
            scoutStartTime = Date()
        }
    }

    // MARK: - Swap Logic

    /// Verifica si el Main tiene un ad y necesita swap
    func checkMainForAd() {
        guard isActive, let mainWV = mainWebView else { return }

        let checkJS = """
        (function() {
            var player = document.querySelector('.html5-video-player');
            if (!player) return JSON.stringify({isAd: false});
            var isAd = player.classList.contains('ad-showing')
                || player.classList.contains('ad-interrupting');
            return JSON.stringify({isAd: isAd});
        })();
        """

        mainWV.evaluateJavaScript(checkJS) { [weak self] result, _ in
            guard let self = self,
                  let json = result as? String,
                  let data = json.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let isAd = dict["isAd"] as? Bool else { return }

            if isAd {
                DispatchQueue.main.async {
                    self.performSwap()
                }
            }
        }
    }

    /// Llamado desde el forceSkipAd JS del Main cuando detecta un ad
    /// y triple playback está activo
    func onMainAdDetected() {
        guard isActive else { return }

        // Si el scout ya pasó el ad, hacer swap inmediato
        if scoutState == .swapReady || scoutState == .scouting {
            DispatchQueue.main.async {
                self.performSwap()
            }
        }
    }

    /// Verifica si se necesita swap (llamado cuando scout termina de absorber)
    private func checkSwapCondition() {
        // El swap se ejecuta cuando:
        // 1. El Main detecta un ad (notificado via onMainAdDetected)
        // 2. O cuando el scout termina y el main ya tiene ad
        checkMainForAd()
    }

    /// Ejecuta el swap: Scout se vuelve visible, Main se oculta y absorbe
    func performSwap() {
        guard isActive, !isSwapped,
              let scout = scoutWebView,
              let main = mainWebView else { return }

        print("🎬 TriplePlayback: SWAP ejecutándose")

        // 1. Silenciar Main instantáneamente
        main.evaluateJavaScript("""
            (function() {
                var v = document.querySelector('video');
                if (v) {
                    window._maiSavedVolume = v.volume;
                    v.volume = 0;
                    v.muted = true;
                    // Acelerar para pasar el ad rápido
                    try { v.playbackRate = 16; } catch(e) {
                        try { v.playbackRate = 8; } catch(e2) {}
                    }
                }
            })();
        """) { _, _ in }

        // 2. Activar audio en Scout y restaurar velocidad normal
        scout.evaluateJavaScript("""
            (function() {
                var v = document.querySelector('video');
                if (v) {
                    v.muted = false;
                    v.volume = 1;
                    v.playbackRate = 1;
                    if (v.paused) try { v.play(); } catch(e) {}
                }
                // Marcar como Main activo
                window._maiIsMainView = true;
                window._maiIsScout = false;
            })();
        """) { _, _ in }

        // 3. Notificar al SwiftUI para hacer el swap visual
        isSwapped = true
        onSwapRequested?(scout)

        // 4. El Main ahora se convierte en "absorber" del ad
        // (ya está muted y acelerado desde paso 1)

        // 5. Monitorear cuando el Main termine de absorber el ad
        startMainAbsorptionMonitor()
    }

    /// Monitorea el ex-Main (ahora oculto) mientras absorbe el ad
    private func startMainAbsorptionMonitor() {
        guard let main = mainWebView else { return }

        // Polling cada 200ms para ver si el ad terminó en Main
        let timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self, weak main] timer in
            guard let self = self, let mainWV = main else {
                timer.invalidate()
                return
            }

            mainWV.evaluateJavaScript("""
                (function() {
                    var player = document.querySelector('.html5-video-player');
                    if (!player) return 'unknown';
                    var isAd = player.classList.contains('ad-showing')
                        || player.classList.contains('ad-interrupting');
                    return isAd ? 'ad' : 'clean';
                })();
            """) { [weak self] result, _ in
                guard let self = self, let status = result as? String else { return }
                if status == "clean" {
                    timer.invalidate()
                    self.onMainAdAbsorbed()
                }
            }
        }
        // Timeout: si después de 30s Main sigue en ad, forzar estado
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak timer] in
            timer?.invalidate()
        }
    }

    /// Main terminó de absorber el ad — intercambiar roles
    private func onMainAdAbsorbed() {
        guard isActive else { return }

        print("🎬 TriplePlayback: Main absorbió ad, intercambiando roles")

        // Restaurar Main: mute, velocidad normal → se convierte en nuevo Scout
        mainWebView?.evaluateJavaScript("""
            (function() {
                var v = document.querySelector('video');
                if (v) {
                    v.muted = true;
                    v.volume = 0;
                    v.playbackRate = 1;
                }
                window._maiIsScout = true;
                window._maiIsMainView = false;
            })();
        """) { _, _ in }

        // Intercambiar referencias: el Scout actual (visible) se vuelve Main
        // y el Main actual (oculto) se vuelve Scout
        let oldScout = scoutWebView
        let oldMain = mainWebView

        // El scout (ahora visible) es el nuevo main
        mainWebView = oldScout
        // El main (ahora oculto, ad absorbido) es el nuevo scout
        scoutWebView = oldMain

        isSwapped = false
        scoutState = .scouting
        scoutStartTime = Date()

        // Inyectar script de scout en el nuevo scout (ex-Main)
        oldMain?.evaluateJavaScript(scoutInjectionScript) { _, _ in }

        onSwapCompleted?()
    }

    // MARK: - Timeout

    private func checkScoutTimeout() {
        guard isActive, let startTime = scoutStartTime else { return }

        let elapsed = Date().timeIntervalSince(startTime)
        if elapsed >= scoutTimeout {
            print("🎬 TriplePlayback: Scout timeout después de \(Int(elapsed))s")
            // No desactivar, solo resetear el estado del scout
            scoutState = .scouting
            scoutStartTime = Date()
        }
    }

    // MARK: - SPA Navigation

    /// Llamado cuando se detecta navegación SPA en YouTube (nuevo video)
    func handleSPANavigation(newURL: URL) {
        guard isActive else { return }

        let newVideoID = extractVideoID(from: newURL)
        if newVideoID != currentVideoID {
            print("🎬 TriplePlayback: SPA navigation → \(newURL.absoluteString)")
            currentVideoID = newVideoID
            currentVideoURL = newURL
            consecutiveNoAds = 0
            scoutState = .loading
            scoutStartTime = Date()
            isSwapped = false

            // Scout carga el nuevo video
            scoutWebView?.load(URLRequest(url: newURL))
        }
    }

    // MARK: - Helpers

    func isYouTubeVideo(_ url: URL) -> Bool {
        guard let host = url.host else { return false }
        return host.contains("youtube.com") && url.absoluteString.contains("/watch")
    }

    private func extractVideoID(from url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else { return nil }
        return queryItems.first(where: { $0.name == "v" })?.value
    }

    /// Si el sistema está activo para un tab específico
    func isActiveFor(tab: Tab) -> Bool {
        return isActive && activeTab?.id == tab.id
    }

    /// Si triple playback debería activarse para esta URL
    func shouldActivate(for url: URL) -> Bool {
        guard YouTubeAdBlockManager.shared.blockYouTubeAds else { return false }
        return isYouTubeVideo(url)
    }

    // MARK: - Scout JS Script

    /// Script inyectado en el Main WebView para notificar a Swift cuando detecta un ad
    /// Trabaja en conjunto con el forceSkipAd existente
    var mainAdDetectionScript: String {
        return """
        (function() {
            if (window._maiTriplePlayback) return;
            window._maiTriplePlayback = true;

            // Monitorear ads en el Main y notificar a Swift para swap
            var _tpLastAdState = false;
            function checkForAdSwap() {
                var player = document.querySelector('.html5-video-player');
                if (!player) return;
                var isAd = player.classList.contains('ad-showing')
                    || player.classList.contains('ad-interrupting');

                if (isAd && !_tpLastAdState) {
                    // Ad acaba de empezar — notificar a Swift
                    try {
                        window.webkit.messageHandlers.maiTriplePlaybackSwap.postMessage({
                            action: 'adDetected',
                            videoId: new URLSearchParams(location.search).get('v'),
                            currentTime: document.querySelector('video')?.currentTime || 0
                        });
                    } catch(e) {}
                }
                _tpLastAdState = isAd;
            }

            // Polling cada 100ms
            setInterval(checkForAdSwap, 100);

            // SPA navigation — notificar para resync del scout
            window.addEventListener('yt-navigate-finish', function() {
                try {
                    window.webkit.messageHandlers.maiTriplePlaybackSwap.postMessage({
                        action: 'spaNavigation',
                        url: location.href,
                        videoId: new URLSearchParams(location.search).get('v')
                    });
                } catch(e) {}
            });
        })();
        """
    }

    /// Script inyectado en el Scout WebView
    /// Mantiene video muted, detecta ads, reporta estado cada 500ms
    private var scoutScript: String {
        return """
        (function() {
            if (!location.hostname.includes('youtube.com')) return;
            if (window._maiScoutActive) return;
            window._maiScoutActive = true;
            window._maiIsScout = true;
            window._maiIsMainView = false;

            var _adSeen = false;
            var _adActive = false;
            var _checkCount = 0;
            var _lastAdState = false;

            function reportStatus() {
                _checkCount++;
                var player = document.querySelector('.html5-video-player');
                var video = document.querySelector('video');

                // Siempre mantener muted
                if (video && window._maiIsScout) {
                    video.muted = true;
                    video.volume = 0;
                }

                if (!player || !video) return;

                var isAd = player.classList.contains('ad-showing')
                    || player.classList.contains('ad-interrupting');

                // Check adicional via API
                if (!isAd) {
                    try {
                        var mp = document.getElementById('movie_player');
                        if (mp && typeof mp.getAdState === 'function') {
                            var st = mp.getAdState();
                            if (st === 1 || st === 2) isAd = true;
                        }
                    } catch(e) {}
                }

                // Extraer video ID
                var videoId = null;
                try {
                    var urlParams = new URLSearchParams(location.search);
                    videoId = urlParams.get('v');
                } catch(e) {}

                var msg = {
                    type: 'status',
                    videoId: videoId,
                    currentTime: video.currentTime || 0,
                    duration: video.duration || 0,
                    isAd: isAd,
                    paused: video.paused
                };

                // Detectar transiciones
                if (isAd && !_lastAdState) {
                    // Ad empezó
                    _adSeen = true;
                    _adActive = true;
                    msg.type = 'adStart';
                    msg.adDuration = video.duration || 0;
                } else if (!isAd && _lastAdState) {
                    // Ad terminó
                    _adActive = false;
                    msg.type = 'adEnd';
                    msg.resumeTime = video.currentTime;
                }

                _lastAdState = isAd;

                // Si hay ad, absorberlo
                if (isAd && window._maiIsScout) {
                    // Acelerar al máximo
                    try { video.playbackRate = 16; } catch(e) {
                        try { video.playbackRate = 8; } catch(e2) {}
                    }
                    // Saltar al final si es posible
                    if (video.duration && isFinite(video.duration) && video.duration > 0) {
                        video.currentTime = video.duration - 0.1;
                    }
                    // Click skip buttons
                    var skips = document.querySelectorAll(
                        '.ytp-skip-ad-button, .ytp-ad-skip-button, ' +
                        '.ytp-ad-skip-button-modern, [id^="skip-button"], ' +
                        '.ytp-ad-skip-button-slot button'
                    );
                    for (var i = 0; i < skips.length; i++) {
                        try { skips[i].click(); } catch(e) {}
                    }
                    // Cerrar popups de enforcement
                    var popups = document.querySelectorAll(
                        'tp-yt-iron-overlay-backdrop, ytd-enforcement-message-view-model, ' +
                        'yt-upsell-dialog-renderer'
                    );
                    for (var p = 0; p < popups.length; p++) {
                        try { popups[p].remove(); } catch(e) {}
                    }
                }

                // Si no hubo ad después de 20 checks (10 segundos)
                if (!_adSeen && _checkCount > 20) {
                    msg.type = 'noAd';
                }

                try {
                    window.webkit.messageHandlers.maiScoutStatus.postMessage(msg);
                } catch(e) {}
            }

            // SPA navigation detection
            function onNav() {
                _checkCount = 0;
                _adSeen = false;
                _adActive = false;
                _lastAdState = false;

                var videoId = null;
                try {
                    var urlParams = new URLSearchParams(location.search);
                    videoId = urlParams.get('v');
                } catch(e) {}

                try {
                    window.webkit.messageHandlers.maiScoutStatus.postMessage({
                        type: 'navigation',
                        videoId: videoId,
                        url: location.href
                    });
                } catch(e) {}
            }

            window.addEventListener('yt-navigate-finish', onNav);
            window.addEventListener('yt-page-data-updated', onNav);

            // Esperar que el video exista
            function waitForVideo() {
                var video = document.querySelector('video');
                if (video) {
                    video.muted = true;
                    video.volume = 0;
                    // Polling cada 500ms
                    setInterval(reportStatus, 500);
                } else {
                    setTimeout(waitForVideo, 200);
                }
            }
            waitForVideo();
        })();
        """
    }

    /// Script que se inyecta en un WebView que se convierte en Scout
    /// (cuando Main y Scout intercambian roles)
    private var scoutInjectionScript: String {
        return """
        (function() {
            window._maiIsScout = true;
            window._maiIsMainView = false;
            var video = document.querySelector('video');
            if (video) {
                video.muted = true;
                video.volume = 0;
            }
            // Si ya hay script de scout corriendo, solo actualizar flags
            if (window._maiScoutActive) return;
            \(scoutScript)
        })();
        """
    }
}

// MARK: - Scout Navigation Delegate

class ScoutNavigationDelegate: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    weak var manager: TriplePlaybackManager?

    init(manager: TriplePlaybackManager) {
        self.manager = manager
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "maiScoutStatus" else { return }

        if let body = message.body as? [String: Any] {
            manager?.handleScoutMessage(body)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("🎬 TriplePlayback Scout: página cargada")
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("🎬 TriplePlayback Scout: navegación falló - \(error.localizedDescription)")
    }
}
