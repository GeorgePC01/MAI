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
                if (!obj || typeof obj !== 'object' || depth > 20) return;
                for (var i = 0; i < AD_KEYS.length; i++) {
                    if (obj.hasOwnProperty(AD_KEYS[i])) {
                        obj[AD_KEYS[i]] = Array.isArray(obj[AD_KEYS[i]]) ? [] : {};
                    }
                }
                if (obj.playerConfig && obj.playerConfig.adConfig) obj.playerConfig.adConfig = {};
                if (obj.playbackTracking && obj.playbackTracking.videostatsAdUrl) {
                    obj.playbackTracking.videostatsAdUrl = {};
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

            // Feed/page ads — SEGURO remover (fuera del player)
            var safeToRemove = [
                'ytd-ad-slot-renderer', 'ytd-banner-promo-renderer',
                'ytd-promoted-sparkles-web-renderer', 'ytd-in-feed-ad-layout-renderer',
                'ytd-display-ad-renderer', '#masthead-ad',
                'ytd-player-legacy-desktop-watch-ads-renderer',
                'ytd-enforcement-message-view-model',
                'tp-yt-iron-overlay-backdrop',
                'yt-mealbar-promo-renderer'
            ];
            // Guardia: nunca tocar elementos dentro del player (settings, captions, etc.)
            function _isPlayerUI(el) {
                try { return !!(el && el.closest && el.closest('.html5-video-player')); } catch(e) { return false; }
            }
            safeToRemove.forEach(function(sel) {
                document.querySelectorAll(sel).forEach(function(el) {
                    if (_isPlayerUI(el)) return;
                    el.remove();
                });
            });
            // Player-level ads — solo OCULTAR (el player necesita el DOM)
            var hideOnly = [
                '.ytp-ad-action-interstitial-background-container',
                '.ytp-ad-action-interstitial-slot',
                '.ytp-ad-action-interstitial-background',
                '.ytp-ad-player-overlay-layout',
                '#player-ads'
            ];
            hideOnly.forEach(function(sel) {
                document.querySelectorAll(sel).forEach(function(el) {
                    el.style.display = 'none';
                });
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

            // Restaurar scroll y limpiar enforcement flags
            try {
                document.body.style.setProperty('overflow', 'auto', 'important');
                document.body.style.setProperty('overflow-y', 'auto', 'important');
            } catch(e) {}

            // Deshabilitar experiment flags de detección
            try {
                if (window.yt && window.yt.config_ && window.yt.config_.EXPERIMENT_FLAGS) {
                    window.yt.config_.EXPERIMENT_FLAGS.service_worker_enabled = false;
                    window.yt.config_.EXPERIMENT_FLAGS.web_enable_ab_rsp_cl = false;
                    window.yt.config_.EXPERIMENT_FLAGS.ab_pl_man = false;
                }
            } catch(e) {}

            // Limpiar enforcement de auxiliaryUi si existe
            try {
                if (window.ytInitialPlayerResponse && window.ytInitialPlayerResponse.auxiliaryUi) {
                    var mr = window.ytInitialPlayerResponse.auxiliaryUi.messageRenderers;
                    if (mr) {
                        delete mr.enforcementMessageViewModel;
                        delete mr.bkaEnforcementMessageViewModel;
                    }
                }
            } catch(e) {}

            try { window.webkit.messageHandlers.youtubeAdBlocked.postMessage('cleanup_done'); } catch(e) {}
        })();
