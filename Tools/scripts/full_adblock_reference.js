        (function() {
            'use strict';
            if (!location.hostname.includes('youtube.com')) return;
            if (window._maiYTAdBlock) return;
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
            // CAPA 0.5: Deshabilitar experiment flags de detección (técnica uBlock Origin)
            // ============================================================
            // Spoof ad detection flags (sin tocar Object.prototype — demasiado agresivo)
            // Se aplican directamente en los objetos de YouTube cuando se detectan

            // Deshabilitar flags cuando ytcfg esté disponible
            function disableDetectionFlags() {
                try {
                    if (window.yt && window.yt.config_ && window.yt.config_.EXPERIMENT_FLAGS) {
                        var flags = window.yt.config_.EXPERIMENT_FLAGS;
                        flags.service_worker_enabled = false;
                        flags.web_enable_ab_rsp_cl = false;
                        flags.ab_pl_man = false;
                        flags.web_gel_timeout_cap = false;
                    }
                    if (window.ytcfg && typeof window.ytcfg.set === 'function') {
                        window.ytcfg.set('EXPERIMENT_FLAGS', Object.assign(
                            {},
                            (window.ytcfg.get && window.ytcfg.get('EXPERIMENT_FLAGS')) || {},
                            {
                                service_worker_enabled: false,
                                web_enable_ab_rsp_cl: false,
                                ab_pl_man: false
                            }
                        ));
                    }
                } catch(e) {}
            }
            // Intentar inmediatamente y también después
            disableDetectionFlags();
            setTimeout(disableDetectionFlags, 1000);
            setTimeout(disableDetectionFlags, 3000);

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

            // Campos que NUNCA se deben tocar (necesarios para video playback)
            var PROTECTED_KEYS = ['streamingData', 'serviceIntegrityDimensions', 'attestation',
                                  'playabilityStatus', 'videoDetails', 'microformat',
                                  'storyboards', 'captions', 'heartbeatParams'];

            function deepClean(obj, depth) {
                if (!obj || typeof obj !== 'object' || depth > 20) return false;
                var cleaned = false;

                // Vaciar campos de ads (NO borrar — YouTube verifica que existan)
                // Arrays se reemplazan con [], objetos con {}, strings con ''
                for (var i = 0; i < AD_KEYS.length; i++) {
                    if (obj.hasOwnProperty(AD_KEYS[i])) {
                        var val = obj[AD_KEYS[i]];
                        if (Array.isArray(val)) {
                            obj[AD_KEYS[i]] = [];
                        } else if (typeof val === 'object' && val !== null) {
                            obj[AD_KEYS[i]] = {};
                        } else {
                            obj[AD_KEYS[i]] = null;
                        }
                        cleaned = true;
                    }
                }

                // playerConfig.adConfig — vaciar, no borrar
                if (obj.playerConfig) {
                    if (obj.playerConfig.adConfig) { obj.playerConfig.adConfig = {}; cleaned = true; }
                    if (obj.playerConfig.adsConfig) { obj.playerConfig.adsConfig = {}; cleaned = true; }
                }

                // playbackTracking — vaciar URLs de tracking
                if (obj.playbackTracking) {
                    if (obj.playbackTracking.videostatsAdUrl) {
                        obj.playbackTracking.videostatsAdUrl = {};
                        cleaned = true;
                    }
                    if (obj.playbackTracking.ptrackingUrl) {
                        obj.playbackTracking.ptrackingUrl = {};
                        cleaned = true;
                    }
                }

                // === ENFORCEMENT MESSAGE (2026) — vaciar el popup de "ad blocker detectado" ===
                if (obj.auxiliaryUi && obj.auxiliaryUi.messageRenderers) {
                    if (obj.auxiliaryUi.messageRenderers.enforcementMessageViewModel) {
                        obj.auxiliaryUi.messageRenderers.enforcementMessageViewModel = {};
                        cleaned = true;
                    }
                    if (obj.auxiliaryUi.messageRenderers.bkaEnforcementMessageViewModel) {
                        obj.auxiliaryUi.messageRenderers.bkaEnforcementMessageViewModel = {};
                        cleaned = true;
                    }
                }

                // openPopupConfig — deshabilitar modal de enforcement
                if (obj.openPopupConfig && obj.openPopupConfig.supportedPopups) {
                    if (obj.openPopupConfig.supportedPopups.adBlockMessageViewModel !== undefined) {
                        obj.openPopupConfig.supportedPopups.adBlockMessageViewModel = false;
                        cleaned = true;
                    }
                }

                // Recursión en contenedores conocidos (NUNCA entrar en PROTECTED_KEYS)
                var containers = ['playerResponse', 'response', 'onResponseReceivedEndpoints',
                                  'engagementPanels', 'contents', 'results', 'actions',
                                  'frameworkUpdates', 'auxiliaryUi', 'messageRenderers'];
                for (var c = 0; c < containers.length; c++) {
                    // Saltar si es un campo protegido
                    var isProtected = false;
                    for (var p = 0; p < PROTECTED_KEYS.length; p++) {
                        if (containers[c] === PROTECTED_KEYS[p]) { isProtected = true; break; }
                    }
                    if (isProtected) continue;

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

            // 1a. JSON.parse override — SOLO limpiar objetos que son respuestas de YouTube
            // (no limpiar streamingData, serviceIntegrityDimensions, attestation, etc.)
            JSON.parse = function() {
                var result = _origParse.apply(this, arguments);
                if (result && typeof result === 'object') {
                    // Solo limpiar si el objeto tiene firma de respuesta YouTube con ads
                    if (result.adPlacements || result.playerAds || result.adSlots ||
                        result.playerResponse || result.onResponseReceivedEndpoints ||
                        (result.auxiliaryUi && result.auxiliaryUi.messageRenderers)) {
                        if (deepClean(result, 0)) _n('jp');
                    }
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

            // 1d. Intercept fetch — solo limpiar POST body, NO modificar respuestas
            // (modificar respuestas corrompe streamingData y YouTube detecta la alteración)
            var _origFetch = window.fetch;
            window.fetch = function() {
                var url = arguments[0];
                var urlStr = (typeof url === 'string') ? url : (url && url.url ? url.url : '');
                if (urlStr.includes('/youtubei/v1/') && arguments[1] && arguments[1].body) {
                    try {
                        var body = _origParse(arguments[1].body);
                        if (body.adSignalsInfo) { delete body.adSignalsInfo; }
                        arguments[1].body = _origStringify(body);
                    } catch(e) {}
                }
                return _origFetch.apply(this, arguments);
            };

            // 1e. Intercept XMLHttpRequest — solo limpiar POST body, NO modificar respuestas
            var XHR = XMLHttpRequest.prototype;
            var _xhrOpen = XHR.open;
            XHR.open = function(method, url) {
                this._maiUrl = url || '';
                return _xhrOpen.apply(this, arguments);
            };
            var _xhrSend = XHR.send;
            XHR.send = function() {
                var url = this._maiUrl || '';
                if (url.includes('/youtubei/v1/') && arguments[0]) {
                    try {
                        var body = _origParse(arguments[0]);
                        if (body.adSignalsInfo) delete body.adSignalsInfo;
                        arguments[0] = _origStringify(body);
                    } catch(e) {}
                }
                return _xhrSend.apply(this, arguments);
            };

            // 1f. Response.prototype.json — deshabilitado (modificar respuestas rompe video)
            // La limpieza se hace via JSON.parse override y property traps

            // ============================================================
            // CAPA 2: CSS cosmético
            // ============================================================
            var css = document.createElement('style');
            css.id = 'mai-yt-adblock';
            css.textContent = [
                // === SOLO feed/page ads (SEGURO — nunca afecta el video player) ===
                'ytd-ad-slot-renderer', 'ytd-banner-promo-renderer',
                'ytd-statement-banner-renderer', 'ytd-in-feed-ad-layout-renderer',
                'ytd-promoted-sparkles-web-renderer', 'ytd-promoted-sparkles-text-search-renderer',
                'ytd-display-ad-renderer', 'ytd-companion-slot-renderer',
                'ytd-player-legacy-desktop-watch-ads-renderer',
                '#masthead-ad', '#player-ads',
                '#panels > ytd-engagement-panel-section-list-renderer[target-id="engagement-panel-ads"]',
                'ytd-merch-shelf-renderer',
                // Enforcement popups (2026) — fuera del player, seguro ocultar
                'ytd-enforcement-message-view-model',
                'yt-upsell-dialog-renderer', '#upsell-dialog',
                'tp-yt-iron-overlay-backdrop',
                'yt-mealbar-promo-renderer',
                // Skip button UI (ocultar para no confundir)
                '.ytp-ad-skip-ad-slot',
                '.ytp-ad-preview-container',
                '.ytp-ad-message-container',
                '.ytp-ad-persistent-progress-bar-container',
                '.ytp-ad-survey-question-container',
                '.ytp-ad-info-dialog-container'
            ].join(',') + '{ display: none !important; }';
            // === Player-level ad overlays: solo ocultar DURANTE ads (via .ad-showing parent) ===
            css.textContent += '\\n' + [
                '.ad-showing .ytp-ad-module',
                '.ad-showing .ytp-ad-overlay-container',
                '.ad-showing .ytp-ad-player-overlay',
                '.ad-showing .ytp-ad-player-overlay-layout',
                '.ad-showing .ytp-ad-action-interstitial',
                '.ad-showing .ytp-ad-action-interstitial-background-container',
                '.ad-showing .ytp-ad-action-interstitial-background',
                '.ad-showing .ytp-ad-image-overlay',
                '.ad-showing .ytp-ad-text-overlay',
                '.ad-showing .ytp-ad-player-overlay-flyout-cta',
                '.ad-showing .ytp-ad-player-overlay-skip-or-preview'
            ].join(',') + '{ display: none !important; }';
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

                // Paso 4: OCULTAR elementos de ad (NO remover — el player necesita el DOM intacto)
                var adNodes = document.querySelectorAll(
                    '.ytp-ad-module, .ytp-ad-overlay-container, .ad-showing .ytp-ad-player-overlay'
                );
                for (var r = 0; r < adNodes.length; r++) {
                    try { adNodes[r].style.display = 'none'; } catch(e) {}
                }

                // Paso 5: Cerrar diálogo de "ad blocker detectado" + enforcement popup completo
                var enforcementSelectors = [
                    'tp-yt-paper-dialog', 'yt-upsell-dialog-renderer',
                    'ytd-enforcement-message-view-model',
                    'yt-playability-error-supported-renderers',
                    'yt-player-error-message-renderer',
                    // Overlay backdrop oscuro (2026 — el elemento principal que bloquea el video)
                    'tp-yt-iron-overlay-backdrop',
                    // Popup container
                    'ytd-popup-container'
                ];
                for (var es = 0; es < enforcementSelectors.length; es++) {
                    var elems = document.querySelectorAll(enforcementSelectors[es]);
                    for (var d = 0; d < elems.length; d++) {
                        try {
                            // Para tp-yt-iron-overlay-backdrop: siempre remover (es el overlay oscuro)
                            // Para otros: solo si son visibles
                            if (enforcementSelectors[es] === 'tp-yt-iron-overlay-backdrop') {
                                elems[d].removeAttribute('opened');
                                elems[d].style.display = 'none';
                                elems[d].remove();
                                _n('backdrop_rm');
                            } else if (enforcementSelectors[es] === 'ytd-popup-container') {
                                // Solo remover popups de enforcement, no todos los popups
                                if (elems[d].querySelector('ytd-enforcement-message-view-model') ||
                                    elems[d].querySelector('yt-upsell-dialog-renderer')) {
                                    var popup = elems[d].querySelector('tp-yt-paper-dialog');
                                    if (popup) popup.remove();
                                    _n('popup_rm');
                                }
                            } else if (elems[d].offsetParent !== null ||
                                       getComputedStyle(elems[d]).display !== 'none') {
                                elems[d].remove();
                                _n('popup_rm');
                            }
                        } catch(e) {}
                    }
                }
                // Restaurar scroll del body (YouTube lo bloquea cuando muestra enforcement)
                try {
                    document.body.style.setProperty('overflow', 'auto', 'important');
                    document.body.style.setProperty('overflow-y', 'auto', 'important');
                    document.documentElement.style.setProperty('overflow', 'auto', 'important');
                } catch(e) {}

                // Paso 6: Remover overlay negro (dark background over video)
                var darkOverlays = document.querySelectorAll(
                    '.ytp-ad-action-interstitial-background-container, ' +
                    '.ytp-ad-action-interstitial-slot, ' +
                    '.ytp-ad-action-interstitial-background, ' +
                    '.ytp-ad-player-overlay-layout, ' +
                    '.ytp-ad-overlay-ad-info-button-container'
                );
                for (var k = 0; k < darkOverlays.length; k++) {
                    try { darkOverlays[k].remove(); _n('dark_rm'); } catch(e) {}
                }

                // Paso 7: Si el video está pausado por el ad system, forzar play
                var vid = document.querySelector('video');
                if (vid && vid.paused && !vid.ended) {
                    try { vid.play(); } catch(e) {}
                    // Simular tecla 'k' (play/pause de YouTube) como backup
                    try {
                        document.dispatchEvent(new KeyboardEvent('keydown', {
                            key: 'k', code: 'KeyK', keyCode: 75, bubbles: true
                        }));
                    } catch(e) {}
                }

                // Paso 8: Remover clase ad-showing del player para desbloquear controles
                if (player.classList.contains('ad-showing')) {
                    player.classList.remove('ad-showing');
                }
                if (player.classList.contains('ad-interrupting')) {
                    player.classList.remove('ad-interrupting');
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
                                tag === 'ytd-enforcement-message-view-model' ||
                                tag === 'tp-yt-iron-overlay-backdrop' ||
                                tag === 'yt-playability-error-supported-renderers' ||
                                tag === 'yt-player-error-message-renderer' ||
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
                    // Re-deshabilitar detection flags en cada navegación
                    disableDetectionFlags();
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
