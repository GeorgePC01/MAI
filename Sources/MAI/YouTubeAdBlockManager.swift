import Foundation
import WebKit
import Combine

/// Gestiona el bloqueo de anuncios de YouTube mediante 4 capas de defensa:
/// 1. JS injection (JSON.parse override + fetch intercept + ytInitialPlayerResponse trap)
/// 2. CSS cosmético (oculta elementos de UI de ads)
/// 3. MutationObserver auto-skip (fallback si un ad escapa)
/// 4. WKContentRuleList (bloqueo de URLs de ads a nivel de red)
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

    /// Compila reglas de bloqueo de red para URLs de ads de YouTube
    func compileNetworkRules() async {
        let rules = """
        [
            {
                "trigger": { "url-filter": "doubleclick\\\\.net", "if-domain": ["*youtube.com"] },
                "action": { "type": "block" }
            },
            {
                "trigger": { "url-filter": "/pagead/", "if-domain": ["*youtube.com"] },
                "action": { "type": "block" }
            },
            {
                "trigger": { "url-filter": "/api/stats/ads", "if-domain": ["*youtube.com"] },
                "action": { "type": "block" }
            },
            {
                "trigger": { "url-filter": "ptracking", "if-domain": ["*youtube.com"] },
                "action": { "type": "block" }
            },
            {
                "trigger": { "url-filter": "get_midroll_info", "if-domain": ["*youtube.com"] },
                "action": { "type": "block" }
            },
            {
                "trigger": { "url-filter": "/pagead/interaction/", "if-domain": ["*youtube.com"] },
                "action": { "type": "block" }
            },
            {
                "trigger": { "url-filter": "googleads\\\\.g\\\\.doubleclick\\\\.net" },
                "action": { "type": "block" }
            },
            {
                "trigger": { "url-filter": "ad\\\\.youtube\\\\.com" },
                "action": { "type": "block" }
            },
            {
                "trigger": { "url-filter": "/generate_204", "if-domain": ["*youtube.com"] },
                "action": { "type": "block" }
            },
            {
                "trigger": { "url-filter": "youtube\\\\.com/get_video_info.*ad" },
                "action": { "type": "block" }
            }
        ]
        """

        do {
            let ruleList = try await WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: "YouTubeAdBlock",
                encodedContentRuleList: rules
            )
            await MainActor.run {
                self.compiledRuleList = ruleList
                print("🛡️ YouTube ad block rules compiled (\(rules.components(separatedBy: "\"type\": \"block\"").count - 1) rules)")
            }
        } catch {
            print("⚠️ Failed to compile YouTube ad block rules: \(error)")
        }
    }

    // MARK: - Capas 1-3: JavaScript injection

    /// Script combinado de las 3 capas JS, solo se activa en youtube.com.
    /// Enfoque principal: eliminar datos de ads ANTES de que el player los procese,
    /// y si un ad escapa, forzar skip inmediato (mute + 16x speed + click skip).
    var adBlockScript: String {
        return """
        (function() {
            if (!location.hostname.includes('youtube.com')) return;

            var _notify = function(t) {
                try { window.webkit.messageHandlers.youtubeAdBlocked.postMessage(t); } catch(e) {}
            };

            // === CAPA 1: Interceptar y limpiar datos de ads ===

            var _origParse = JSON.parse;

            // Lista exhaustiva de claves de ads en playerResponse y respuestas API
            var AD_KEYS = [
                'adPlacements', 'playerAds', 'adSlots', 'adBreakParams',
                'adBreakHeartbeatParams', 'instreamAdBreak', 'linearAdSequenceRenderer',
                'adPlacementRenderer', 'actionCompanionAdRenderer', 'adVideoId',
                'instreamAdPlayerOverlayRenderer', 'adLayoutLoggingData',
                'instreamAdContentRenderer', 'prerollAdRenderer'
            ];

            // Limpieza recursiva profunda de campos de ads
            function deepClean(obj, depth) {
                if (!obj || typeof obj !== 'object' || depth > 12) return false;
                var cleaned = false;
                // Limpiar claves de ads de nivel superior
                for (var i = 0; i < AD_KEYS.length; i++) {
                    if (obj[AD_KEYS[i]] !== undefined) {
                        delete obj[AD_KEYS[i]];
                        cleaned = true;
                    }
                }
                // Limpiar playerConfig.adConfig si existe
                if (obj.playerConfig && obj.playerConfig.adConfig) {
                    delete obj.playerConfig.adConfig;
                    cleaned = true;
                }
                // Buscar recursivamente en objetos anidados conocidos
                var nested = ['playerResponse', 'response', 'onResponseReceivedEndpoints',
                              'engagementPanels', 'contents', 'results'];
                for (var n = 0; n < nested.length; n++) {
                    if (obj[nested[n]]) {
                        if (Array.isArray(obj[nested[n]])) {
                            for (var a = 0; a < obj[nested[n]].length; a++) {
                                if (deepClean(obj[nested[n]][a], depth + 1)) cleaned = true;
                            }
                        } else {
                            if (deepClean(obj[nested[n]], depth + 1)) cleaned = true;
                        }
                    }
                }
                return cleaned;
            }

            // 1a. Override JSON.parse — toda respuesta parseada pasa por aquí
            JSON.parse = function() {
                var obj = _origParse.apply(this, arguments);
                if (obj && typeof obj === 'object') {
                    if (deepClean(obj, 0)) _notify('json_clean');
                }
                return obj;
            };
            JSON.parse.toString = function() { return 'function parse() { [native code] }'; };

            // 1b. Trap ytInitialPlayerResponse — blob inicial de la página
            try {
                var _ytIPR = window.ytInitialPlayerResponse;
                Object.defineProperty(window, 'ytInitialPlayerResponse', {
                    get: function() { return _ytIPR; },
                    set: function(val) {
                        if (val && typeof val === 'object') {
                            if (deepClean(val, 0)) _notify('initial_clean');
                        }
                        _ytIPR = val;
                    },
                    configurable: true
                });
            } catch(e) {}

            // 1c. Trap ytInitialData — datos iniciales de página con ads en feed
            try {
                var _ytID = window.ytInitialData;
                Object.defineProperty(window, 'ytInitialData', {
                    get: function() { return _ytID; },
                    set: function(val) {
                        if (val && typeof val === 'object') {
                            deepClean(val, 0);
                        }
                        _ytID = val;
                    },
                    configurable: true
                });
            } catch(e) {}

            // 1d. Intercept fetch — limpiar respuestas de player/next/ad_break
            var _origFetch = window.fetch;
            window.fetch = function() {
                var url = arguments[0];
                var urlStr = (typeof url === 'string') ? url : (url && url.url ? url.url : '');
                var isAdEndpoint = urlStr.includes('/youtubei/v1/player')
                    || urlStr.includes('/youtubei/v1/next')
                    || urlStr.includes('/youtubei/v1/ad_break')
                    || urlStr.includes('/youtubei/v1/browse');
                if (isAdEndpoint) {
                    return _origFetch.apply(this, arguments).then(function(response) {
                        var clone = response.clone();
                        return clone.text().then(function(text) {
                            try {
                                var data = _origParse(text);
                                if (deepClean(data, 0)) _notify('fetch_clean');
                                return new Response(JSON.stringify(data), {
                                    status: response.status,
                                    statusText: response.statusText,
                                    headers: response.headers
                                });
                            } catch(e) {
                                return response;
                            }
                        });
                    });
                }
                return _origFetch.apply(this, arguments);
            };

            // 1e. Intercept XMLHttpRequest — YouTube usa XHR además de fetch
            var _origXHROpen = XMLHttpRequest.prototype.open;
            var _origXHRSend = XMLHttpRequest.prototype.send;
            XMLHttpRequest.prototype.open = function(method, url) {
                this._maiUrl = url || '';
                return _origXHROpen.apply(this, arguments);
            };
            XMLHttpRequest.prototype.send = function() {
                var self = this;
                var url = self._maiUrl || '';
                var isAdXHR = url.includes('/youtubei/v1/player')
                    || url.includes('/youtubei/v1/next')
                    || url.includes('/youtubei/v1/ad_break')
                    || url.includes('get_midroll_info');
                if (isAdXHR) {
                    self.addEventListener('readystatechange', function() {
                        if (self.readyState === 4) {
                            try {
                                var data = _origParse(self.responseText);
                                if (deepClean(data, 0)) {
                                    Object.defineProperty(self, 'responseText', {
                                        get: function() { return JSON.stringify(data); }
                                    });
                                    Object.defineProperty(self, 'response', {
                                        get: function() { return JSON.stringify(data); }
                                    });
                                    _notify('xhr_clean');
                                }
                            } catch(e) {}
                        }
                    });
                }
                return _origXHRSend.apply(this, arguments);
            };

            // 1f. Intercept Response.prototype.json — atrapa .json() en fetch responses
            var _origResJson = Response.prototype.json;
            Response.prototype.json = function() {
                return _origResJson.apply(this, arguments).then(function(data) {
                    if (data && typeof data === 'object') {
                        if (deepClean(data, 0)) _notify('resp_json_clean');
                    }
                    return data;
                });
            };

            // === CAPA 2: CSS cosmético ===
            var style = document.createElement('style');
            style.textContent = [
                '.ytp-ad-module',
                '.ytp-ad-overlay-container',
                '.ytp-ad-overlay-slot',
                '.ytp-ad-text-overlay',
                '.ytp-ad-image-overlay',
                '.ytp-ad-player-overlay',
                '.ytp-ad-action-interstitial',
                '.ytp-ad-skip-ad-slot',
                'ytd-ad-slot-renderer',
                'ytd-banner-promo-renderer',
                'ytd-statement-banner-renderer',
                'ytd-in-feed-ad-layout-renderer',
                'ytd-promoted-sparkles-web-renderer',
                'ytd-promoted-sparkles-text-search-renderer',
                'ytd-display-ad-renderer',
                'ytd-companion-slot-renderer',
                'ytd-player-legacy-desktop-watch-ads-renderer',
                '#masthead-ad',
                '#player-ads',
                '#panels > ytd-engagement-panel-section-list-renderer[target-id="engagement-panel-ads"]',
                'ytd-merch-shelf-renderer',
                '.ytd-rich-item-renderer:has(ytd-ad-slot-renderer)',
                'tp-yt-paper-dialog:has(.ytd-enforcement-message-view-model)',
                'ytd-popup-container:has(.ytd-enforcement-message-view-model)',
                '.ad-interrupting',
                '.ad-showing .ytp-ad-overlay-container'
            ].join(',') + '{ display: none !important; }';
            (document.head || document.documentElement).appendChild(style);

            // === CAPA 3: Detección activa + skip forzado de ads incrustados ===

            var _adActive = false;

            function forceSkipAd() {
                var player = document.querySelector('.html5-video-player');
                if (!player) return;

                var isAd = player.classList.contains('ad-showing')
                    || player.classList.contains('ad-interrupting')
                    || document.querySelector('.ytp-ad-player-overlay');

                if (!isAd) {
                    // Si estábamos en ad y ya no, restaurar estado
                    if (_adActive) {
                        _adActive = false;
                        var v = document.querySelector('video');
                        if (v) {
                            v.muted = false;
                            v.playbackRate = 1;
                        }
                    }
                    return;
                }

                _adActive = true;

                // 3a. Intentar click en todos los botones de skip conocidos
                var skipSelectors = [
                    '.ytp-skip-ad-button',
                    '.ytp-ad-skip-button',
                    '.ytp-ad-skip-button-modern',
                    '.ytp-ad-skip-button-slot button',
                    'button.ytp-ad-overlay-close-button',
                    '.ytp-ad-survey-answer-button',
                    '[id^="skip-button"]',
                    'button[data-tooltip-target-id="a]d-skip-button"]'
                ];
                for (var s = 0; s < skipSelectors.length; s++) {
                    var btn = document.querySelector(skipSelectors[s]);
                    if (btn) {
                        btn.click();
                        _notify('skip_click');
                        return;
                    }
                }

                // 3b. Forzar skip: mute + velocidad máxima + saltar al final
                var video = document.querySelector('video');
                if (video) {
                    video.muted = true;
                    // Velocidad máxima para pasar el ad lo más rápido posible
                    try { video.playbackRate = 16; } catch(e) {
                        try { video.playbackRate = 8; } catch(e2) {}
                    }
                    // Si tiene duración finita, saltar al final
                    if (video.duration && isFinite(video.duration) && video.duration > 0) {
                        video.currentTime = video.duration - 0.1;
                        _notify('jump_end');
                    }
                }

                // 3c. Intentar usar la API interna del player de YouTube
                try {
                    var ytPlayer = document.getElementById('movie_player');
                    if (ytPlayer) {
                        // skipAd() es método interno del player
                        if (typeof ytPlayer.skipAd === 'function') {
                            ytPlayer.skipAd();
                            _notify('api_skip');
                        }
                        // cancelPlayback detiene el ad
                        if (typeof ytPlayer.cancelPlayback === 'function' && isAd) {
                            // Solo si realmente es un ad (no el video principal)
                            var adState = ytPlayer.getAdState ? ytPlayer.getAdState() : -1;
                            if (adState > 0) {
                                ytPlayer.cancelPlayback();
                                _notify('api_cancel');
                            }
                        }
                    }
                } catch(e) {}
            }

            // MutationObserver para reaccionar a cambios de clase del player
            var observer = new MutationObserver(function(mutations) {
                for (var i = 0; i < mutations.length; i++) {
                    var m = mutations[i];
                    if (m.type === 'attributes' && m.attributeName === 'class') {
                        forceSkipAd();
                    }
                    if (m.type === 'childList' && m.addedNodes.length > 0) {
                        for (var j = 0; j < m.addedNodes.length; j++) {
                            var node = m.addedNodes[j];
                            if (node.nodeType === 1) {
                                var tag = node.tagName ? node.tagName.toLowerCase() : '';
                                if (tag === 'ytd-ad-slot-renderer' ||
                                    tag === 'ytd-promoted-sparkles-web-renderer' ||
                                    (node.classList && node.classList.contains('ytp-ad-module'))) {
                                    node.remove();
                                    _notify('node_rm');
                                }
                            }
                        }
                    }
                }
            });

            // Polling de seguridad: cada 500ms verificar si hay un ad reproduciéndose
            // (el MutationObserver a veces no detecta cambios de clase internos)
            var _pollInterval = null;
            function startAdPoll() {
                if (_pollInterval) return;
                _pollInterval = setInterval(function() {
                    forceSkipAd();
                }, 500);
            }

            // Interceptar 'playing' en el video para detectar ads que escaparon
            function hookVideoEvents() {
                var video = document.querySelector('video');
                if (!video || video._maiHooked) return;
                video._maiHooked = true;
                video.addEventListener('playing', function() {
                    // Verificar si es un ad
                    setTimeout(forceSkipAd, 50);
                });
                video.addEventListener('loadstart', function() {
                    setTimeout(forceSkipAd, 100);
                });
            }

            function attachObserver() {
                var player = document.querySelector('.html5-video-player');
                if (player) {
                    observer.observe(player, { attributes: true, childList: true, subtree: true });
                    observer.observe(document.body, { childList: true, subtree: true });
                    hookVideoEvents();
                    startAdPoll();
                    // Check immediately
                    forceSkipAd();
                } else {
                    setTimeout(attachObserver, 500);
                }
            }

            // Re-attach on YouTube SPA navigation (pushState/popState)
            var _origPushState = history.pushState;
            history.pushState = function() {
                _origPushState.apply(this, arguments);
                setTimeout(function() {
                    hookVideoEvents();
                    forceSkipAd();
                }, 1000);
            };
            window.addEventListener('popstate', function() {
                setTimeout(function() {
                    hookVideoEvents();
                    forceSkipAd();
                }, 1000);
            });
            // yt-navigate-finish fires on YouTube SPA page transitions
            window.addEventListener('yt-navigate-finish', function() {
                setTimeout(function() {
                    hookVideoEvents();
                    forceSkipAd();
                }, 500);
            });

            if (document.readyState === 'loading') {
                document.addEventListener('DOMContentLoaded', attachObserver);
            } else {
                attachObserver();
            }
        })();
        """
    }
}
