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

    private init() {
        self.blockYouTubeAds = UserDefaults.standard.object(forKey: "blockYouTubeAds") as? Bool ?? true
        self.adsBlocked = UserDefaults.standard.integer(forKey: "youtubeAdsBlocked")
    }

    func incrementAdsBlocked() {
        DispatchQueue.main.async {
            self.adsBlocked += 1
        }
    }

    func resetCount() {
        adsBlocked = 0
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
            { "trigger": { "url-filter": "/generate_204", "if-domain": ["*youtube.com"] }, "action": { "type": "block" } },
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

    // MARK: - Script principal (atDocumentStart)

    var adBlockScript: String {
        return """
        (function() {
            'use strict';
            if (!location.hostname.includes('youtube.com')) return;
            if (window._maiYTAdBlock) return; // No re-inyectar
            window._maiYTAdBlock = true;

            var _n = function(t) {
                try { window.webkit.messageHandlers.youtubeAdBlocked.postMessage(t); } catch(e) {}
            };
            var _origParse = JSON.parse;
            var _origStringify = JSON.stringify;

            // ============================================================
            // CAPA 0: Bloquear ServiceWorker (YouTube lo usa para cachear ads)
            // ============================================================
            if (navigator.serviceWorker) {
                var _origReg = navigator.serviceWorker.register;
                navigator.serviceWorker.register = function() {
                    // Permitir SW pero limpiar cache de ads periódicamente
                    return _origReg.apply(this, arguments);
                };
                // Limpiar caches de ads existentes
                if (window.caches) {
                    caches.keys().then(function(names) {
                        names.forEach(function(name) {
                            if (name.includes('ad') || name.includes('pagead')) {
                                caches.delete(name);
                            }
                        });
                    });
                }
            }

            // ============================================================
            // CAPA 1: Interceptar y eliminar datos de ads
            // ============================================================

            // Claves exhaustivas de ads en YouTube API responses
            var AD_KEYS = [
                'adPlacements', 'playerAds', 'adSlots', 'adBreakParams',
                'adBreakHeartbeatParams', 'instreamAdBreak', 'linearAdSequenceRenderer',
                'adPlacementRenderer', 'actionCompanionAdRenderer', 'adVideoId',
                'instreamAdPlayerOverlayRenderer', 'adLayoutLoggingData',
                'instreamAdContentRenderer', 'prerollAdRenderer',
                'adPlaybackTracking', 'adInfoRenderer', 'adNextParams',
                'adModule', 'adThrottled', 'playerAdParams', 'adRequestConfig'
            ];

            function deepClean(obj, depth) {
                if (!obj || typeof obj !== 'object' || depth > 15) return false;
                var cleaned = false;

                // Borrar todas las claves de ads
                for (var i = 0; i < AD_KEYS.length; i++) {
                    if (obj.hasOwnProperty(AD_KEYS[i])) {
                        delete obj[AD_KEYS[i]];
                        cleaned = true;
                    }
                }

                // playerConfig.adConfig
                if (obj.playerConfig) {
                    if (obj.playerConfig.adConfig) { delete obj.playerConfig.adConfig; cleaned = true; }
                    if (obj.playerConfig.adsConfig) { delete obj.playerConfig.adsConfig; cleaned = true; }
                }

                // playbackTracking.videostatsAdUrl
                if (obj.playbackTracking) {
                    if (obj.playbackTracking.videostatsAdUrl) {
                        delete obj.playbackTracking.videostatsAdUrl;
                        cleaned = true;
                    }
                    if (obj.playbackTracking.ptrackingUrl) {
                        delete obj.playbackTracking.ptrackingUrl;
                        cleaned = true;
                    }
                }

                // Recursión en contenedores conocidos
                var containers = ['playerResponse', 'response', 'onResponseReceivedEndpoints',
                                  'engagementPanels', 'contents', 'results', 'actions',
                                  'frameworkUpdates', 'responseContext'];
                for (var c = 0; c < containers.length; c++) {
                    var val = obj[containers[c]];
                    if (val) {
                        if (Array.isArray(val)) {
                            for (var a = 0; a < val.length; a++) {
                                if (deepClean(val[a], depth + 1)) cleaned = true;
                            }
                        } else if (typeof val === 'object') {
                            if (deepClean(val, depth + 1)) cleaned = true;
                        }
                    }
                }

                return cleaned;
            }

            // 1a. JSON.parse override — todo JSON parseado se limpia
            JSON.parse = function() {
                var result = _origParse.apply(this, arguments);
                if (result && typeof result === 'object') {
                    if (deepClean(result, 0)) _n('jp');
                }
                return result;
            };
            // Anti-detección: parecer nativo
            try {
                Object.defineProperty(JSON.parse, 'name', { value: 'parse' });
                Object.defineProperty(JSON.parse, 'length', { value: 2 });
            } catch(e) {}
            JSON.parse.toString = _origParse.toString.bind(_origParse);

            // 1b. Property traps — interceptar ANTES de que el player lea los datos
            function trapProperty(obj, prop) {
                try {
                    var _val = obj[prop];
                    Object.defineProperty(obj, prop, {
                        get: function() { return _val; },
                        set: function(v) {
                            if (v && typeof v === 'object') {
                                if (deepClean(v, 0)) _n('trap_' + prop);
                            }
                            _val = v;
                        },
                        configurable: true,
                        enumerable: true
                    });
                } catch(e) {}
            }
            trapProperty(window, 'ytInitialPlayerResponse');
            trapProperty(window, 'ytInitialData');
            trapProperty(window, 'ytPlayerConfig');

            // 1c. Trap ytcfg.set — YouTube usa esto para inyectar config del player
            try {
                var _origYtcfg = window.ytcfg;
                Object.defineProperty(window, 'ytcfg', {
                    get: function() { return _origYtcfg; },
                    set: function(v) {
                        _origYtcfg = v;
                        if (v && typeof v.set === 'function') {
                            var _origSet = v.set;
                            v.set = function() {
                                // Interceptar configuración del player
                                if (arguments[0] && typeof arguments[0] === 'object') {
                                    var cfg = arguments[0];
                                    if (cfg.PLAYER_VARS) {
                                        try {
                                            var pv = typeof cfg.PLAYER_VARS === 'string'
                                                ? _origParse(cfg.PLAYER_VARS) : cfg.PLAYER_VARS;
                                            if (pv.embedded_player_response) {
                                                var epr = typeof pv.embedded_player_response === 'string'
                                                    ? _origParse(pv.embedded_player_response) : pv.embedded_player_response;
                                                deepClean(epr, 0);
                                                pv.embedded_player_response = _origStringify(epr);
                                            }
                                            deepClean(pv, 0);
                                            cfg.PLAYER_VARS = _origStringify(pv);
                                        } catch(e) {}
                                    }
                                    if (cfg.INNERTUBE_CONTEXT) {
                                        deepClean(cfg.INNERTUBE_CONTEXT, 0);
                                    }
                                }
                                return _origSet.apply(this, arguments);
                            };
                        }
                    },
                    configurable: true,
                    enumerable: true
                });
            } catch(e) {}

            // 1d. Intercept fetch
            var _origFetch = window.fetch;
            window.fetch = function() {
                var url = arguments[0];
                var urlStr = (typeof url === 'string') ? url : (url && url.url ? url.url : '');
                if (urlStr.includes('/youtubei/v1/player') ||
                    urlStr.includes('/youtubei/v1/next') ||
                    urlStr.includes('/youtubei/v1/ad_break') ||
                    urlStr.includes('/youtubei/v1/browse') ||
                    urlStr.includes('/youtubei/v1/reel')) {

                    // Intentar modificar el POST body para quitar ad signals
                    if (arguments[1] && arguments[1].body) {
                        try {
                            var body = _origParse(arguments[1].body);
                            if (body.adSignalsInfo) { delete body.adSignalsInfo; }
                            if (body.params && typeof body.params === 'string' && body.params.includes('ad')) {
                                // No borrar params completo — solo limpiar si es puramente de ads
                            }
                            arguments[1].body = _origStringify(body);
                        } catch(e) {}
                    }

                    return _origFetch.apply(this, arguments).then(function(response) {
                        if (!response.ok) return response;
                        var clone = response.clone();
                        return clone.text().then(function(text) {
                            try {
                                var data = _origParse(text);
                                if (deepClean(data, 0)) _n('fc');
                                return new Response(_origStringify(data), {
                                    status: response.status,
                                    statusText: response.statusText,
                                    headers: response.headers
                                });
                            } catch(e) { return response; }
                        });
                    });
                }
                return _origFetch.apply(this, arguments);
            };

            // 1e. Intercept XMLHttpRequest con Proxy para responseText inmutable
            var XHR = XMLHttpRequest.prototype;
            var _xhrOpen = XHR.open;
            XHR.open = function(method, url) {
                this._maiUrl = url || '';
                return _xhrOpen.apply(this, arguments);
            };
            var _xhrSend = XHR.send;
            XHR.send = function() {
                var xhr = this;
                var url = xhr._maiUrl || '';
                if (url.includes('/youtubei/v1/player') ||
                    url.includes('/youtubei/v1/next') ||
                    url.includes('/youtubei/v1/ad_break') ||
                    url.includes('get_midroll_info')) {

                    // Modificar POST body si posible
                    if (arguments[0]) {
                        try {
                            var body = _origParse(arguments[0]);
                            if (body.adSignalsInfo) delete body.adSignalsInfo;
                            arguments[0] = _origStringify(body);
                        } catch(e) {}
                    }

                    var _origGetResp = Object.getOwnPropertyDescriptor(XMLHttpRequest.prototype, 'responseText');
                    xhr.addEventListener('readystatechange', function() {
                        if (xhr.readyState === 4) {
                            try {
                                var raw = _origGetResp ? _origGetResp.get.call(xhr) : xhr.responseText;
                                var data = _origParse(raw);
                                if (deepClean(data, 0)) {
                                    var cleaned = _origStringify(data);
                                    Object.defineProperty(xhr, 'responseText', { get: function() { return cleaned; }, configurable: true });
                                    Object.defineProperty(xhr, 'response', { get: function() { return cleaned; }, configurable: true });
                                    _n('xc');
                                }
                            } catch(e) {}
                        }
                    });
                }
                return _xhrSend.apply(this, arguments);
            };

            // 1f. Response.prototype.json override
            var _origResJson = Response.prototype.json;
            Response.prototype.json = function() {
                return _origResJson.apply(this, arguments).then(function(data) {
                    if (data && typeof data === 'object') {
                        if (deepClean(data, 0)) _n('rj');
                    }
                    return data;
                });
            };

            // ============================================================
            // CAPA 2: CSS cosmético
            // ============================================================
            var css = document.createElement('style');
            css.id = 'mai-yt-adblock';
            css.textContent = [
                // Player ads
                '.ytp-ad-module', '.ytp-ad-overlay-container', '.ytp-ad-overlay-slot',
                '.ytp-ad-text-overlay', '.ytp-ad-image-overlay', '.ytp-ad-player-overlay',
                '.ytp-ad-action-interstitial', '.ytp-ad-skip-ad-slot',
                '.ytp-ad-message-container', '.ytp-ad-persistent-progress-bar-container',
                '.ytp-ad-preview-container', '.ytp-ad-survey-question-container',
                // Feed/page ads
                'ytd-ad-slot-renderer', 'ytd-banner-promo-renderer',
                'ytd-statement-banner-renderer', 'ytd-in-feed-ad-layout-renderer',
                'ytd-promoted-sparkles-web-renderer', 'ytd-promoted-sparkles-text-search-renderer',
                'ytd-display-ad-renderer', 'ytd-companion-slot-renderer',
                'ytd-player-legacy-desktop-watch-ads-renderer',
                '#masthead-ad', '#player-ads',
                '#panels > ytd-engagement-panel-section-list-renderer[target-id="engagement-panel-ads"]',
                'ytd-merch-shelf-renderer',
                '.ytd-rich-item-renderer:has(ytd-ad-slot-renderer)',
                // Ad blocker detection popups
                'tp-yt-paper-dialog:has(.ytd-enforcement-message-view-model)',
                'ytd-popup-container:has(.ytd-enforcement-message-view-model)',
                'yt-upsell-dialog-renderer', '#upsell-dialog',
                'ytd-enforcement-message-view-model',
                // Misc
                '.ad-interrupting', '.ad-showing .ytp-ad-overlay-container',
                '.ytp-ad-info-dialog-container'
            ].join(',') + '{ display: none !important; visibility: hidden !important; height: 0 !important; }';
            (document.head || document.documentElement).appendChild(css);

            // ============================================================
            // CAPA 3: Monitoreo activo + skip forzado
            // ============================================================

            var _adActive = false;
            var _lastVideoSrc = '';
            var _contentVideoSrc = ''; // Guardar src del video de contenido (no ad)

            function forceSkipAd() {
                var player = document.querySelector('.html5-video-player');
                if (!player) return;

                var isAd = player.classList.contains('ad-showing')
                    || player.classList.contains('ad-interrupting');

                // Verificación adicional: overlay visible
                if (!isAd) {
                    var overlay = document.querySelector('.ytp-ad-player-overlay');
                    if (overlay && overlay.offsetParent !== null) isAd = true;
                }

                // Verificación: el propio player reporta ad
                if (!isAd) {
                    try {
                        var mp = document.getElementById('movie_player');
                        if (mp && typeof mp.getAdState === 'function') {
                            var adState = mp.getAdState();
                            if (adState === 1 || adState === 2) isAd = true;
                        }
                    } catch(e) {}
                }

                if (!isAd) {
                    if (_adActive) {
                        _adActive = false;
                        var v = document.querySelector('video');
                        if (v) {
                            v.muted = false;
                            v.playbackRate = 1;
                        }
                    }
                    // Guardar src de contenido para poder detectar cambios a ad
                    var cv = document.querySelector('video');
                    if (cv && cv.src && !cv.src.includes('blob:')) {
                        _contentVideoSrc = cv.src;
                    }
                    return;
                }

                // === ES UN AD — ELIMINARLO ===
                _adActive = true;
                _n('ad_detected');

                // Paso 1: Click en TODOS los botones de skip posibles
                var skipSelectors = [
                    '.ytp-skip-ad-button', '.ytp-ad-skip-button',
                    '.ytp-ad-skip-button-modern', '.ytp-ad-skip-button-slot button',
                    '.ytp-ad-skip-button-slot .ytp-ad-skip-button-container button',
                    'button.ytp-ad-overlay-close-button', '.ytp-ad-survey-answer-button',
                    '[id^="skip-button"]', '.videoAdUiSkipButton',
                    // Botones nuevos de YouTube (2025+)
                    '.ytp-ad-button-icon', 'button[data-purpose="skip"]'
                ];
                for (var s = 0; s < skipSelectors.length; s++) {
                    var btns = document.querySelectorAll(skipSelectors[s]);
                    for (var b = 0; b < btns.length; b++) {
                        try { btns[b].click(); _n('sc'); } catch(e) {}
                    }
                }

                // Paso 2: Forzar skip con video element
                var video = document.querySelector('video');
                if (video) {
                    video.muted = true;
                    video.volume = 0;
                    // Velocidad máxima
                    try { video.playbackRate = 16; } catch(e) {
                        try { video.playbackRate = 10; } catch(e2) {
                            try { video.playbackRate = 8; } catch(e3) {}
                        }
                    }
                    // Saltar al final
                    if (video.duration && isFinite(video.duration) && video.duration > 0.5) {
                        video.currentTime = video.duration;
                        _n('je');
                    }
                }

                // Paso 3: API interna del player
                try {
                    var ytPlayer = document.getElementById('movie_player');
                    if (ytPlayer) {
                        if (typeof ytPlayer.skipAd === 'function') ytPlayer.skipAd();
                        if (typeof ytPlayer.finishAd === 'function') ytPlayer.finishAd();
                        if (typeof ytPlayer.getAdState === 'function' && ytPlayer.getAdState() > 0) {
                            if (typeof ytPlayer.stopVideo === 'function') ytPlayer.stopVideo();
                            if (typeof ytPlayer.cancelPlayback === 'function') ytPlayer.cancelPlayback();
                            // Forzar carga del video real
                            if (typeof ytPlayer.loadVideoById === 'function') {
                                try {
                                    var vData = ytPlayer.getVideoData();
                                    if (vData && vData.video_id) {
                                        ytPlayer.loadVideoById(vData.video_id);
                                        _n('reload_content');
                                    }
                                } catch(e2) {}
                            }
                            _n('api');
                        }
                    }
                } catch(e) {}

                // Paso 4: Remover elementos de ad del DOM
                var adNodes = document.querySelectorAll(
                    '.ytp-ad-module, .ytp-ad-overlay-container, .ad-showing .ytp-ad-player-overlay'
                );
                for (var r = 0; r < adNodes.length; r++) {
                    try { adNodes[r].remove(); } catch(e) {}
                }

                // Paso 5: Cerrar diálogo de "ad blocker detectado"
                var dialogs = document.querySelectorAll(
                    'tp-yt-paper-dialog, yt-upsell-dialog-renderer, ytd-enforcement-message-view-model'
                );
                for (var d = 0; d < dialogs.length; d++) {
                    try {
                        if (dialogs[d].offsetParent !== null) {
                            dialogs[d].remove();
                            _n('popup_rm');
                        }
                    } catch(e) {}
                }
            }

            // Patcher del player: override métodos de ads una vez que el player exista
            var _playerPatched = false;
            function patchPlayer() {
                if (_playerPatched) return;
                var mp = document.getElementById('movie_player');
                if (!mp) return;
                _playerPatched = true;

                // Override getAdState para siempre reportar "sin ad"
                if (typeof mp.getAdState === 'function') {
                    mp.getAdState = function() { return -1; };
                }
                // Override isAdPlaying
                if (typeof mp.isAdPlaying === 'function') {
                    mp.isAdPlaying = function() { return false; };
                }
                // Interceptar loadVideoByPlayerVars para limpiar datos de ad
                if (typeof mp.loadVideoByPlayerVars === 'function') {
                    var _origLoad = mp.loadVideoByPlayerVars;
                    mp.loadVideoByPlayerVars = function(vars) {
                        if (vars && typeof vars === 'object') {
                            deepClean(vars, 0);
                        }
                        return _origLoad.apply(this, arguments);
                    };
                }
                // Interceptar cueVideoByPlayerVars
                if (typeof mp.cueVideoByPlayerVars === 'function') {
                    var _origCue = mp.cueVideoByPlayerVars;
                    mp.cueVideoByPlayerVars = function(vars) {
                        if (vars && typeof vars === 'object') {
                            deepClean(vars, 0);
                        }
                        return _origCue.apply(this, arguments);
                    };
                }
                _n('player_patched');
            }

            // MutationObserver
            var observer = new MutationObserver(function(mutations) {
                for (var i = 0; i < mutations.length; i++) {
                    var m = mutations[i];
                    if (m.type === 'attributes') {
                        if (m.attributeName === 'class' || m.attributeName === 'src') {
                            forceSkipAd();
                        }
                    }
                    if (m.type === 'childList') {
                        for (var j = 0; j < m.addedNodes.length; j++) {
                            var node = m.addedNodes[j];
                            if (node.nodeType !== 1) continue;
                            var tag = (node.tagName || '').toLowerCase();
                            if (tag === 'ytd-ad-slot-renderer' ||
                                tag === 'ytd-promoted-sparkles-web-renderer' ||
                                tag === 'ytd-in-feed-ad-layout-renderer' ||
                                tag === 'ytd-display-ad-renderer' ||
                                tag === 'ytd-banner-promo-renderer' ||
                                (node.classList && (
                                    node.classList.contains('ytp-ad-module') ||
                                    node.classList.contains('ad-showing')
                                ))) {
                                try { node.remove(); _n('nr'); } catch(e) {}
                            }
                        }
                        if (!_playerPatched) patchPlayer();
                    }
                }
            });

            // Polling agresivo: 250ms
            var _pollId = null;
            function startPoll() {
                if (_pollId) return;
                _pollId = setInterval(function() {
                    forceSkipAd();
                    if (!_playerPatched) patchPlayer();
                }, 250);
            }

            // Hook en video element
            function hookVideo() {
                var video = document.querySelector('video');
                if (!video || video._maiHooked) return;
                video._maiHooked = true;

                // Monitorear cambios de src
                var _origSrcSet = Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype, 'src');
                if (_origSrcSet && _origSrcSet.set) {
                    // No override src setter — puede romper playback
                    // En su lugar, escuchar eventos
                }

                video.addEventListener('loadstart', function() { setTimeout(forceSkipAd, 50); });
                video.addEventListener('playing', function() { setTimeout(forceSkipAd, 50); });
                video.addEventListener('loadedmetadata', function() {
                    // Si el video dura <90s y estamos en ad-showing, probablemente es un ad
                    var player = document.querySelector('.html5-video-player');
                    if (player && player.classList.contains('ad-showing') && video.duration < 90) {
                        video.muted = true;
                        video.currentTime = video.duration;
                        _n('meta_skip');
                    }
                });
            }

            function attachAll() {
                var player = document.querySelector('.html5-video-player');
                if (player) {
                    observer.observe(player, { attributes: true, attributeFilter: ['class'], childList: true, subtree: true });
                    observer.observe(document.body, { childList: true, subtree: true });
                    hookVideo();
                    startPoll();
                    patchPlayer();
                    forceSkipAd();
                } else {
                    setTimeout(attachAll, 300);
                }
            }

            // Navegación SPA de YouTube
            function onNavigation() {
                setTimeout(function() {
                    hookVideo();
                    forceSkipAd();
                    _playerPatched = false; // Re-parchar en nueva página
                    patchPlayer();
                    // Re-limpiar datos globales
                    if (window.ytInitialPlayerResponse) deepClean(window.ytInitialPlayerResponse, 0);
                    if (window.ytInitialData) deepClean(window.ytInitialData, 0);
                }, 300);
            }
            var _origPush = history.pushState;
            history.pushState = function() {
                _origPush.apply(this, arguments);
                onNavigation();
            };
            window.addEventListener('popstate', onNavigation);
            window.addEventListener('yt-navigate-finish', onNavigation);
            window.addEventListener('yt-page-data-updated', onNavigation);

            // Iniciar
            if (document.readyState === 'loading') {
                document.addEventListener('DOMContentLoaded', attachAll);
            } else {
                attachAll();
            }
        })();
        """
    }

    // MARK: - Script post-carga (atDocumentEnd)

    /// Script que se ejecuta DESPUÉS de que la página cargó, para limpiar
    /// cualquier dato de ads que haya escapado a las trampas del atDocumentStart
    var cleanupScript: String {
        return """
        (function() {
            if (!location.hostname.includes('youtube.com')) return;

            var _origParse = JSON.parse;
            var AD_KEYS = [
                'adPlacements', 'playerAds', 'adSlots', 'adBreakParams',
                'adBreakHeartbeatParams', 'instreamAdBreak', 'linearAdSequenceRenderer',
                'adPlacementRenderer', 'actionCompanionAdRenderer', 'adVideoId',
                'instreamAdPlayerOverlayRenderer', 'adLayoutLoggingData',
                'instreamAdContentRenderer', 'prerollAdRenderer',
                'adPlaybackTracking', 'adInfoRenderer', 'adNextParams',
                'adModule', 'adThrottled', 'playerAdParams', 'adRequestConfig'
            ];

            function cleanObj(obj, depth) {
                if (!obj || typeof obj !== 'object' || depth > 15) return;
                for (var i = 0; i < AD_KEYS.length; i++) {
                    if (obj.hasOwnProperty(AD_KEYS[i])) delete obj[AD_KEYS[i]];
                }
                if (obj.playerConfig && obj.playerConfig.adConfig) delete obj.playerConfig.adConfig;
                if (obj.playbackTracking && obj.playbackTracking.videostatsAdUrl) {
                    delete obj.playbackTracking.videostatsAdUrl;
                }
                var containers = ['playerResponse', 'response', 'contents', 'results'];
                for (var c = 0; c < containers.length; c++) {
                    if (obj[containers[c]]) {
                        if (Array.isArray(obj[containers[c]])) {
                            obj[containers[c]].forEach(function(item) { cleanObj(item, depth + 1); });
                        } else {
                            cleanObj(obj[containers[c]], depth + 1);
                        }
                    }
                }
            }

            // Limpiar datos globales que ya se setearon
            if (window.ytInitialPlayerResponse) cleanObj(window.ytInitialPlayerResponse, 0);
            if (window.ytInitialData) cleanObj(window.ytInitialData, 0);
            if (window.ytPlayerConfig) cleanObj(window.ytPlayerConfig, 0);

            // Limpiar ytcfg si tiene datos de ads
            try {
                if (window.ytcfg && typeof window.ytcfg.get === 'function') {
                    var pv = window.ytcfg.get('PLAYER_VARS');
                    if (pv) {
                        var pvObj = typeof pv === 'string' ? _origParse(pv) : pv;
                        cleanObj(pvObj, 0);
                    }
                }
            } catch(e) {}

            // Remover nodos de ads que ya están en el DOM
            var adSelectors = [
                'ytd-ad-slot-renderer', 'ytd-banner-promo-renderer',
                'ytd-promoted-sparkles-web-renderer', 'ytd-in-feed-ad-layout-renderer',
                'ytd-display-ad-renderer', '#masthead-ad', '#player-ads',
                'ytd-player-legacy-desktop-watch-ads-renderer'
            ];
            adSelectors.forEach(function(sel) {
                document.querySelectorAll(sel).forEach(function(el) { el.remove(); });
            });

            // Verificar si hay un ad reproduciéndose ahora mismo
            var player = document.querySelector('.html5-video-player');
            if (player && (player.classList.contains('ad-showing') || player.classList.contains('ad-interrupting'))) {
                var video = document.querySelector('video');
                if (video) {
                    video.muted = true;
                    try { video.playbackRate = 16; } catch(e) {}
                    if (video.duration && isFinite(video.duration)) {
                        video.currentTime = video.duration;
                    }
                }
                // Click skip
                var skip = document.querySelector('.ytp-skip-ad-button, .ytp-ad-skip-button, .ytp-ad-skip-button-modern');
                if (skip) skip.click();
            }

            try { window.webkit.messageHandlers.youtubeAdBlocked.postMessage('cleanup_done'); } catch(e) {}
        })();
        """
    }
}
