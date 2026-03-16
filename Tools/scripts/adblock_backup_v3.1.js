        (function() {
            'use strict';
            if (!location.hostname.includes('youtube.com')) return;
            if (window._maiYTAdBlock) return;
            window._maiYTAdBlock = true;

            var _n = function(t) {
                try { window.webkit.messageHandlers.youtubeAdBlocked.postMessage(t); } catch(e) {}
            };

            // ============================================================
            // CAPA 1: CSS — ocultar ads de feed/página (SEGURO, no toca video)
            // ============================================================
            var css = document.createElement('style');
            css.id = 'mai-yt-adblock';
            css.textContent = [
                // Feed/page ads
                'ytd-ad-slot-renderer', 'ytd-banner-promo-renderer',
                'ytd-statement-banner-renderer', 'ytd-in-feed-ad-layout-renderer',
                'ytd-promoted-sparkles-web-renderer', 'ytd-promoted-sparkles-text-search-renderer',
                'ytd-display-ad-renderer', 'ytd-companion-slot-renderer',
                'ytd-player-legacy-desktop-watch-ads-renderer',
                '#masthead-ad',
                '#panels > ytd-engagement-panel-section-list-renderer[target-id="engagement-panel-ads"]',
                'ytd-merch-shelf-renderer',
                // Enforcement popups
                'ytd-enforcement-message-view-model',
                'tp-yt-iron-overlay-backdrop',
                'yt-upsell-dialog-renderer', '#upsell-dialog',
                'yt-mealbar-promo-renderer'
            ].join(',') + '{ display: none !important; }';
            (document.head || document.documentElement).appendChild(css);

            // ============================================================
            // CAPA 2: Manejo de ads en video
            // Verificado seguro: mute, overlay, click skip, playbackRate, currentTime
            // PROHIBIDO: classList.remove, DOM remove de .ytp-ad-module,
            //   JSON.parse override, fetch/XHR intercept, Response.json override,
            //   setTimeout override, WKContentRuleList network blocking
            // Ref: memoria #1587, #1561, #1577, #1567, #1568
            // ============================================================
            var _wasAd = false;
            var _savedVolume = 1;
            var _overlayShown = false;
            var _adStartTime = 0;
            var _contentPlayed = false; // true después de que el video de contenido empieza
            var _contentVideoId = null; // video ID del contenido (no del ad)

            function showAdOverlay() {
                if (_overlayShown) return;
                _overlayShown = true;
                var existing = document.getElementById('mai-ad-overlay');
                if (existing) return;
                var ov = document.createElement('div');
                ov.id = 'mai-ad-overlay';
                ov.style.cssText = 'position:absolute;top:0;left:0;width:100%;height:100%;' +
                    'background:rgba(0,0,0,0.92);z-index:9999;display:flex;align-items:center;' +
                    'justify-content:center;flex-direction:column;pointer-events:none;';
                ov.innerHTML = '<div style="color:#fff;font-size:16px;font-family:-apple-system,Arial,sans-serif;">' +
                    'Saltando anuncio...</div>' +
                    '<div style="color:#666;font-size:12px;margin-top:6px;font-family:-apple-system,Arial,sans-serif;">' +
                    'MAI Ad Blocker</div>';
                var container = document.querySelector('.html5-video-container') ||
                                document.querySelector('#movie_player');
                if (container) {
                    container.style.position = 'relative';
                    container.appendChild(ov);
                }
            }

            function hideAdOverlay() {
                _overlayShown = false;
                var ov = document.getElementById('mai-ad-overlay');
                if (ov) ov.remove();
            }

            // ============================================================
            // CAPA 3: Click skip button (simula acción humana — seguro)
            // YouTube muestra el botón después de ~5s de ad
            // Selectores múltiples porque YouTube los cambia frecuentemente
            // ============================================================
            // ============================================================
            // SKIP BUTTON — detección + click instantáneo
            // 3 estrategias: selectores CSS, texto, aria-label
            // + MutationObserver dedicado que clickea al instante
            // ============================================================
            var _skipSelectors = [
                // Selectores principales (2024-2026)
                '.ytp-skip-ad-button',
                '.ytp-ad-skip-button',
                '.ytp-ad-skip-button-modern',
                // Container slots
                '.ytp-ad-skip-button-slot button',
                '.ytp-ad-skip-button-container button',
                '.ytp-ad-skip-button-slot .ytp-ad-skip-button-container',
                // Texto del botón (YouTube 2026 pill-shaped)
                '.ytp-ad-skip-button-text',
                // Por ID
                '[id^="skip-button"]',
                '[id^="skip-button"] button',
                // Overlay close
                'button.ytp-ad-overlay-close-button',
                // Genéricos
                'button[data-purpose="skip"]',
                '.videoAdUiSkipButton',
                // Survey skip
                '.ytp-ad-survey-answer-button',
                // YouTube 2026: botón dentro de yt-button-shape
                '.ytp-ad-skip-button-slot yt-button-shape button',
                '.ytp-ad-skip-button-slot .yt-spec-button-shape-next'
            ];
            var _skipAllSelector = _skipSelectors.join(',');

            function forceClick(el) {
                if (!el) return false;
                try {
                    // Método 1: click directo
                    el.click();
                    // Método 2: MouseEvent completo (simula humano)
                    el.dispatchEvent(new MouseEvent('pointerdown', {bubbles: true, cancelable: true}));
                    el.dispatchEvent(new MouseEvent('pointerup', {bubbles: true, cancelable: true}));
                    el.dispatchEvent(new MouseEvent('click', {bubbles: true, cancelable: true}));
                    return true;
                } catch(e) { return false; }
            }

            function clickSkipButton() {
                var clicked = false;
                // Estrategia 1: selectores CSS
                var btns = document.querySelectorAll(_skipAllSelector);
                for (var b = 0; b < btns.length; b++) {
                    var btn = btns[b];
                    if (btn.offsetParent !== null || btn.offsetWidth > 0 ||
                        getComputedStyle(btn).display !== 'none') {
                        if (forceClick(btn)) { clicked = true; _n('skip_css'); }
                    }
                }
                // Estrategia 2: texto en elementos del player
                if (!clicked) {
                    var playerEl = document.querySelector('#movie_player') || document.querySelector('.html5-video-player');
                    if (playerEl) {
                        var allEls = playerEl.querySelectorAll('button, [role="button"], a, span, div[tabindex]');
                        for (var ab = 0; ab < allEls.length; ab++) {
                            var txt = (allEls[ab].textContent || '').toLowerCase().trim();
                            if (txt === 'skip' || txt === 'skip ad' || txt === 'skip ads' ||
                                txt === 'saltar' || txt === 'saltar anuncio' || txt === 'saltar anuncios' ||
                                txt === 'omitir' || txt === 'omitir anuncio' ||
                                txt === 'passer' || txt.includes('überspringen') ||
                                txt === 'pular' || txt === 'pular anúncio') {
                                if (forceClick(allEls[ab])) { clicked = true; _n('skip_txt'); }
                            }
                        }
                    }
                }
                // Estrategia 3: aria-label
                if (!clicked) {
                    var ariaSkip = document.querySelectorAll(
                        '[aria-label*="Skip" i], [aria-label*="Saltar" i], ' +
                        '[aria-label*="Omitir" i], [aria-label*="Passer" i], ' +
                        '[aria-label*="Pular" i]'
                    );
                    for (var ai = 0; ai < ariaSkip.length; ai++) {
                        if (forceClick(ariaSkip[ai])) { clicked = true; _n('skip_aria'); }
                    }
                }
                return clicked;
            }

            // MutationObserver DEDICADO para skip button
            // Detecta cuando YouTube agrega el botón skip al DOM y lo clickea al instante
            var _skipObserver = new MutationObserver(function(mutations) {
                if (location.pathname.indexOf('/watch') !== 0) return;
                for (var i = 0; i < mutations.length; i++) {
                    var m = mutations[i];
                    if (m.type === 'childList') {
                        for (var j = 0; j < m.addedNodes.length; j++) {
                            var node = m.addedNodes[j];
                            if (node.nodeType !== 1) continue;
                            // Verificar si el nodo agregado ES un skip button
                            try {
                                if (node.matches && node.matches(_skipAllSelector)) {
                                    setTimeout(function() { forceClick(node); _n('skip_obs_direct'); }, 50);
                                }
                                // Verificar si CONTIENE un skip button
                                var inner = node.querySelectorAll ? node.querySelectorAll(_skipAllSelector) : [];
                                for (var k = 0; k < inner.length; k++) {
                                    (function(el) {
                                        setTimeout(function() { forceClick(el); _n('skip_obs_inner'); }, 50);
                                    })(inner[k]);
                                }
                            } catch(e) {}
                        }
                    }
                    // Detectar cambios de atributos (botón se hace visible via style/class change)
                    if (m.type === 'attributes' && m.target && m.target.nodeType === 1) {
                        try {
                            if (m.target.matches && m.target.matches(_skipAllSelector)) {
                                var el = m.target;
                                if (el.offsetParent !== null || el.offsetWidth > 0) {
                                    setTimeout(function() { forceClick(el); _n('skip_obs_attr'); }, 50);
                                }
                            }
                        } catch(e) {}
                    }
                }
            });
            // Observar el player y el body para skip buttons
            function attachSkipObserver() {
                var player = document.querySelector('#movie_player') || document.querySelector('.html5-video-player');
                var target = player || document.body;
                _skipObserver.observe(target, {
                    childList: true, subtree: true,
                    attributes: true, attributeFilter: ['style', 'class', 'hidden']
                });
                if (player && target !== document.body) {
                    _skipObserver.observe(document.body, { childList: true, subtree: true });
                }
            }
            // Adjuntar apenas haya player o en 1s
            setTimeout(attachSkipObserver, 1000);

            // ============================================================
            // Auto-cerrar popups de enforcement (seguro — fuera del player)
            // NO remover .ytp-ad-module (#1587: rompe state machine)
            // ============================================================
            function closePopups() {
                var popupSelectors = [
                    'ytd-mealbar-promo-renderer',
                    'ytd-enforcement-message-view-model',
                    'yt-upsell-dialog-renderer',
                    'tp-yt-iron-overlay-backdrop'
                ];
                for (var ps = 0; ps < popupSelectors.length; ps++) {
                    var els = document.querySelectorAll(popupSelectors[ps]);
                    for (var e = 0; e < els.length; e++) {
                        try { els[e].remove(); } catch(ex) {}
                    }
                }
                // Click dismiss buttons
                var dismiss = document.querySelectorAll(
                    '#dismiss-button, button[aria-label="Close"], button[aria-label="Cerrar"],' +
                    'button[aria-label="No thanks"], button[aria-label="No, gracias"]'
                );
                for (var d = 0; d < dismiss.length; d++) {
                    try { dismiss[d].click(); } catch(e) {}
                }
                // Cerrar diálogos abiertos (Centro de Anuncios, etc.)
                var dialogs = document.querySelectorAll('tp-yt-paper-dialog[aria-hidden="false"], tp-yt-paper-dialog[open]');
                for (var di = 0; di < dialogs.length; di++) {
                    try { dialogs[di].remove(); } catch(e) {}
                }
                // Restaurar scroll
                try {
                    document.body.style.setProperty('overflow', 'auto', 'important');
                } catch(e) {}
            }

            // ============================================================
            // CAPAS AGRESIVAS — inyectadas DESPUÉS de que el contenido empieza
            // Solo se activan cuando _contentPlayed = true (video > 2s)
            // Previenen mid-roll ads sin romper el stream ya establecido
            // ============================================================
            var _aggressiveInjected = false;
            function injectAggressiveLayers() {
                if (_aggressiveInjected) return;
                _aggressiveInjected = true;

                var _origParse = JSON.parse;
                var _origStringify = JSON.stringify;

                // --- Capa A1: Detection flag spoofing ---
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
                            { service_worker_enabled: false, web_enable_ab_rsp_cl: false, ab_pl_man: false }
                        ));
                    }
                } catch(e) {}

                // --- Capa A2: ServiceWorker ad cache cleanup ---
                if (window.caches) {
                    try {
                        caches.keys().then(function(names) {
                            names.forEach(function(name) {
                                if (name.includes('ad') || name.includes('pagead')) {
                                    caches.delete(name);
                                }
                            });
                        });
                    } catch(e) {}
                }

                // --- Capa A3: Player API patching ---
                // getAdState=-1, isAdPlaying=false — el player cree que no hay ads
                function patchPlayerAPI() {
                    var mp = document.getElementById('movie_player');
                    if (!mp) return false;
                    try {
                        if (typeof mp.getAdState === 'function') {
                            mp.getAdState = function() { return -1; };
                        }
                        if (typeof mp.isAdPlaying === 'function') {
                            mp.isAdPlaying = function() { return false; };
                        }
                        // Interceptar loadVideoByPlayerVars para limpiar datos de ad
                        if (typeof mp.loadVideoByPlayerVars === 'function' && !mp._maiPatched) {
                            mp._maiPatched = true;
                            var _origLoad = mp.loadVideoByPlayerVars;
                            mp.loadVideoByPlayerVars = function(vars) {
                                if (_contentPlayed && vars && typeof vars === 'object') {
                                    cleanAdKeys(vars, 0);
                                }
                                return _origLoad.apply(this, arguments);
                            };
                        }
                        if (typeof mp.cueVideoByPlayerVars === 'function' && !mp._maiCuePatched) {
                            mp._maiCuePatched = true;
                            var _origCue = mp.cueVideoByPlayerVars;
                            mp.cueVideoByPlayerVars = function(vars) {
                                if (_contentPlayed && vars && typeof vars === 'object') {
                                    cleanAdKeys(vars, 0);
                                }
                                return _origCue.apply(this, arguments);
                            };
                        }
                    } catch(e) {}
                    return true;
                }

                // --- Capa A4: Limpiar ad keys de objetos (selectivo, protege streamingData) ---
                var AD_KEYS = [
                    'adPlacements', 'playerAds', 'adSlots', 'adBreakParams',
                    'adBreakHeartbeatParams', 'instreamAdBreak', 'linearAdSequenceRenderer',
                    'adPlacementRenderer', 'actionCompanionAdRenderer', 'adVideoId',
                    'instreamAdPlayerOverlayRenderer', 'adLayoutLoggingData',
                    'instreamAdContentRenderer', 'prerollAdRenderer',
                    'adPlaybackTracking', 'adInfoRenderer', 'adNextParams',
                    'adModule', 'adThrottled', 'playerAdParams', 'adRequestConfig'
                ];
                var PROTECTED = ['streamingData', 'serviceIntegrityDimensions', 'attestation',
                                 'playabilityStatus', 'videoDetails', 'microformat',
                                 'storyboards', 'captions', 'heartbeatParams'];

                function cleanAdKeys(obj, depth) {
                    if (!obj || typeof obj !== 'object' || depth > 15) return false;
                    var cleaned = false;
                    for (var i = 0; i < AD_KEYS.length; i++) {
                        if (obj.hasOwnProperty(AD_KEYS[i])) {
                            var val = obj[AD_KEYS[i]];
                            if (Array.isArray(val)) obj[AD_KEYS[i]] = [];
                            else if (typeof val === 'object' && val !== null) obj[AD_KEYS[i]] = {};
                            else obj[AD_KEYS[i]] = null;
                            cleaned = true;
                        }
                    }
                    if (obj.playerConfig) {
                        if (obj.playerConfig.adConfig) { obj.playerConfig.adConfig = {}; cleaned = true; }
                        if (obj.playerConfig.adsConfig) { obj.playerConfig.adsConfig = {}; cleaned = true; }
                    }
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
                    // Recursión selectiva — NUNCA entrar en PROTECTED
                    var containers = ['playerResponse', 'response', 'onResponseReceivedEndpoints',
                                      'engagementPanels', 'contents', 'results', 'actions',
                                      'frameworkUpdates', 'auxiliaryUi', 'messageRenderers'];
                    for (var c = 0; c < containers.length; c++) {
                        var skip = false;
                        for (var p = 0; p < PROTECTED.length; p++) {
                            if (containers[c] === PROTECTED[p]) { skip = true; break; }
                        }
                        if (skip) continue;
                        var v = obj[containers[c]];
                        if (v) {
                            if (Array.isArray(v)) {
                                for (var a = 0; a < v.length; a++) {
                                    if (cleanAdKeys(v[a], depth + 1)) cleaned = true;
                                }
                            } else if (typeof v === 'object') {
                                if (cleanAdKeys(v, depth + 1)) cleaned = true;
                            }
                        }
                    }
                    return cleaned;
                }

                // --- Capa A5: JSON.parse selective override ---
                // Solo limpia cuando _contentPlayed=true (stream ya establecido)
                // Cuando SPA navega a nuevo video, _contentPlayed se resetea a false
                // así no corrompe los datos iniciales del nuevo video
                JSON.parse = function() {
                    var result = _origParse.apply(this, arguments);
                    if (_contentPlayed && result && typeof result === 'object') {
                        if (result.adPlacements || result.playerAds || result.adSlots ||
                            result.playerResponse || result.onResponseReceivedEndpoints ||
                            (result.auxiliaryUi && result.auxiliaryUi.messageRenderers)) {
                            if (cleanAdKeys(result, 0)) _n('jp_agg');
                        }
                    }
                    return result;
                };
                try {
                    Object.defineProperty(JSON.parse, 'name', { value: 'parse' });
                    Object.defineProperty(JSON.parse, 'length', { value: 2 });
                } catch(e) {}
                JSON.parse.toString = _origParse.toString.bind(_origParse);

                // --- Capa A6: fetch/XHR POST body cleaning ---
                // Solo limpia requests salientes, NO toca respuestas
                var _origFetch = window.fetch;
                window.fetch = function() {
                    var url = arguments[0];
                    var urlStr = (typeof url === 'string') ? url : (url && url.url ? url.url : '');
                    if (urlStr.includes('/youtubei/v1/') && arguments[1] && arguments[1].body) {
                        try {
                            var body = _origParse(arguments[1].body);
                            if (body.adSignalsInfo) delete body.adSignalsInfo;
                            arguments[1].body = _origStringify(body);
                        } catch(e) {}
                    }
                    return _origFetch.apply(this, arguments);
                };

                var XHR = XMLHttpRequest.prototype;
                var _xhrOpen = XHR.open;
                var _xhrSend = XHR.send;
                XHR.open = function(method, url) {
                    this._maiUrl = url || '';
                    return _xhrOpen.apply(this, arguments);
                };
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

                // --- Capa A7: Property traps + ytcfg.set intercept ---
                function trapProp(obj, prop) {
                    try {
                        var _val = obj[prop];
                        Object.defineProperty(obj, prop, {
                            get: function() { return _val; },
                            set: function(v) {
                                if (_contentPlayed && v && typeof v === 'object') {
                                    cleanAdKeys(v, 0);
                                }
                                _val = v;
                            },
                            configurable: true, enumerable: true
                        });
                    } catch(e) {}
                }
                trapProp(window, 'ytInitialPlayerResponse');
                trapProp(window, 'ytInitialData');
                trapProp(window, 'ytPlayerConfig');

                // ytcfg.set intercept
                try {
                    if (window.ytcfg && typeof window.ytcfg.set === 'function' && !window.ytcfg._maiPatched) {
                        window.ytcfg._maiPatched = true;
                        var _origSet = window.ytcfg.set;
                        window.ytcfg.set = function() {
                            if (_contentPlayed && arguments[0] && typeof arguments[0] === 'object') {
                                var cfg = arguments[0];
                                if (cfg.PLAYER_VARS) {
                                    try {
                                        var pv = typeof cfg.PLAYER_VARS === 'string'
                                            ? _origParse(cfg.PLAYER_VARS) : cfg.PLAYER_VARS;
                                        cleanAdKeys(pv, 0);
                                        cfg.PLAYER_VARS = _origStringify(pv);
                                    } catch(e) {}
                                }
                                if (cfg.INNERTUBE_CONTEXT) cleanAdKeys(cfg.INNERTUBE_CONTEXT, 0);
                            }
                            return _origSet.apply(this, arguments);
                        };
                    }
                } catch(e) {}

                // Limpiar datos globales ya existentes
                if (window.ytInitialPlayerResponse) cleanAdKeys(window.ytInitialPlayerResponse, 0);
                if (window.ytInitialData) cleanAdKeys(window.ytInitialData, 0);

                // Parchear player API inmediatamente y re-intentar
                patchPlayerAPI();
                setTimeout(patchPlayerAPI, 1000);
                setTimeout(patchPlayerAPI, 3000);

                _n('aggressive_7layers_active');
            }

            // ============================================================
            // Loop principal
            // ============================================================
            function handleAds() {
                // Solo manejar video ads en páginas /watch
                // En homepage/search, el CSS y MutationObserver manejan feed ads
                if (location.pathname.indexOf('/watch') !== 0) return;

                closePopups();

                var player = document.querySelector('.html5-video-player');
                if (!player) return;

                var isAd = player.classList.contains('ad-showing')
                    || player.classList.contains('ad-interrupting');

                if (!isAd) {
                    if (_wasAd) {
                        // Ad terminó — restaurar audio y velocidad
                        _wasAd = false;
                        _adStartTime = 0;
                        hideAdOverlay();
                        var v = document.querySelector('video');
                        if (v) {
                            v.muted = false;
                            v.volume = _savedVolume;
                            v.playbackRate = 1;
                            if (v.paused) try { v.play(); } catch(e) {}
                        }
                        startPolling(false); // Polling normal 200ms
                        _n('ad_ended');
                    }
                    // Después de que el contenido empiece a reproducirse,
                    // inyectar capas agresivas para PREVENIR mid-roll ads
                    // SOLO en páginas de video (/watch), NO en homepage/search/etc.
                    if (!_contentPlayed && location.pathname.indexOf('/watch') === 0) {
                        var cv = document.querySelector('video');
                        if (cv && cv.currentTime > 2 && !cv.paused) {
                            _contentPlayed = true;
                            injectAggressiveLayers();
                            _n('aggressive_injected');
                        }
                    }
                    return;
                }

                // === AD DETECTADO (pre-roll o mid-roll que escapó) ===
                var video = document.querySelector('video');

                if (!_wasAd) {
                    _adStartTime = Date.now();
                    if (video) _savedVolume = video.volume || 1;
                    startPolling(true); // Polling rápido 50ms durante ad
                    _n('ad_detected');
                }
                _wasAd = true;

                // Acción 1: Mute (seguro — YouTube NO detecta)
                if (video) {
                    video.muted = true;
                    video.volume = 0;
                }

                // Acción 2: Overlay visual
                showAdOverlay();

                // Acción 3: Click skip button (seguro — simula humano)
                clickSkipButton();

                // Acción 4: Acelerar ad
                if (video) {
                    try { video.playbackRate = 16; } catch(e) {
                        try { video.playbackRate = 8; } catch(e2) {}
                    }
                    if (video.duration && isFinite(video.duration) && video.duration > 0) {
                        video.currentTime = video.duration - 0.1;
                    }
                }
            }

            // ============================================================
            // MutationObserver — remover feed ads dinámicos (seguro)
            // Solo elementos FUERA del player
            // ============================================================
            var observer = new MutationObserver(function(mutations) {
                for (var i = 0; i < mutations.length; i++) {
                    var m = mutations[i];
                    if (m.type === 'childList') {
                        for (var j = 0; j < m.addedNodes.length; j++) {
                            var node = m.addedNodes[j];
                            if (node.nodeType !== 1) continue;
                            var tag = (node.tagName || '').toLowerCase();
                            if (tag === 'ytd-ad-slot-renderer' ||
                                tag === 'ytd-promoted-sparkles-web-renderer' ||
                                tag === 'ytd-in-feed-ad-layout-renderer' ||
                                tag === 'ytd-display-ad-renderer' ||
                                tag === 'ytd-banner-promo-renderer') {
                                try { node.remove(); _n('nr'); } catch(e) {}
                            }
                        }
                    }
                }
            });

            // Polling adaptativo: 200ms normal, 50ms durante ads
            var _pollInterval = null;
            function startPolling(fast) {
                if (_pollInterval) clearInterval(_pollInterval);
                _pollInterval = setInterval(handleAds, fast ? 50 : 200);
            }
            startPolling(false);

            function attachAll() {
                var player = document.querySelector('.html5-video-player');
                if (player) {
                    observer.observe(document.body, { childList: true, subtree: true });
                    handleAds();
                } else {
                    setTimeout(attachAll, 500);
                }
            }

            // SPA navigation hooks — reset estado para nuevo video
            function onNav() {
                _contentPlayed = false;
                _contentVideoId = null;
                _wasAd = false;
                _adStartTime = 0;
                _aggressiveInjected = false; // Re-inyectar capas agresivas para nuevo video
                hideAdOverlay();
                startPolling(false);
                setTimeout(handleAds, 500);
            }
            window.addEventListener('yt-navigate-finish', onNav);
            window.addEventListener('yt-page-data-updated', onNav);

            if (document.readyState === 'loading') {
                document.addEventListener('DOMContentLoaded', attachAll);
            } else {
                attachAll();
            }
        })();
