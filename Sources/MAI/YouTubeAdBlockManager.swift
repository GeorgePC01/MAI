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

    /// Script combinado de las 3 capas JS, solo se activa en youtube.com
    var adBlockScript: String {
        return """
        (function() {
            if (!location.hostname.includes('youtube.com')) return;

            // === CAPA 1: Interceptar datos de ads en JSON/fetch ===

            // 1a. Override JSON.parse para limpiar ads de toda respuesta parseada
            const _origParse = JSON.parse;
            JSON.parse = function(text) {
                const obj = _origParse.apply(this, arguments);
                if (obj && typeof obj === 'object') {
                    cleanAdFields(obj);
                }
                return obj;
            };
            // Preserve toString for detection avoidance
            JSON.parse.toString = function() { return 'function parse() { [native code] }'; };

            function cleanAdFields(obj) {
                if (!obj || typeof obj !== 'object') return;
                const adKeys = ['adPlacements', 'playerAds', 'adSlots', 'adBreakParams',
                                'adBreakHeartbeatParams', 'instreamAdBreak'];
                let cleaned = false;
                for (const key of adKeys) {
                    if (obj[key]) {
                        delete obj[key];
                        cleaned = true;
                    }
                }
                // Clean nested playerResponse
                if (obj.playerResponse) cleanAdFields(obj.playerResponse);
                if (obj.response) cleanAdFields(obj.response);
                if (cleaned) {
                    try { window.webkit.messageHandlers.youtubeAdBlocked.postMessage('cleaned'); } catch(e) {}
                }
            }

            // 1b. Trap ytInitialPlayerResponse to clean ads from initial page load
            try {
                let _ytInitial = window.ytInitialPlayerResponse;
                Object.defineProperty(window, 'ytInitialPlayerResponse', {
                    get: function() { return _ytInitial; },
                    set: function(val) {
                        if (val && typeof val === 'object') {
                            cleanAdFields(val);
                        }
                        _ytInitial = val;
                    },
                    configurable: true
                });
            } catch(e) {}

            // 1c. Intercept fetch for player/next API responses
            const _origFetch = window.fetch;
            window.fetch = function() {
                const url = arguments[0];
                const urlStr = (typeof url === 'string') ? url : (url && url.url ? url.url : '');
                if (urlStr.includes('/youtubei/v1/player') || urlStr.includes('/youtubei/v1/next')) {
                    return _origFetch.apply(this, arguments).then(function(response) {
                        const clone = response.clone();
                        // Replace response body with cleaned version
                        return clone.text().then(function(text) {
                            try {
                                const data = _origParse(text);
                                cleanAdFields(data);
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

            // === CAPA 2: CSS cosmético — ocultar elementos de UI de ads ===
            const style = document.createElement('style');
            style.textContent = `
                .ytp-ad-module,
                .ytp-ad-overlay-container,
                .ytp-ad-overlay-slot,
                ytd-ad-slot-renderer,
                ytd-banner-promo-renderer,
                ytd-statement-banner-renderer,
                ytd-in-feed-ad-layout-renderer,
                ytd-promoted-sparkles-web-renderer,
                ytd-promoted-sparkles-text-search-renderer,
                ytd-display-ad-renderer,
                ytd-companion-slot-renderer,
                #masthead-ad,
                #player-ads,
                #panels > ytd-engagement-panel-section-list-renderer[target-id="engagement-panel-ads"],
                ytd-merch-shelf-renderer,
                .ytd-rich-item-renderer:has(ytd-ad-slot-renderer),
                tp-yt-paper-dialog:has(.ytd-enforcement-message-view-model),
                ytd-popup-container:has(.ytd-enforcement-message-view-model)
                { display: none !important; }
            `;
            (document.head || document.documentElement).appendChild(style);

            // === CAPA 3: MutationObserver auto-skip fallback ===
            function skipAd() {
                const player = document.querySelector('.html5-video-player');
                if (!player) return;
                if (player.classList.contains('ad-showing')) {
                    // Try clicking skip button
                    const skipBtn = document.querySelector('.ytp-skip-ad-button, .ytp-ad-skip-button, .ytp-ad-skip-button-modern, button[class*="skip"]');
                    if (skipBtn) {
                        skipBtn.click();
                        try { window.webkit.messageHandlers.youtubeAdBlocked.postMessage('skipped'); } catch(e) {}
                        return;
                    }
                    // Force skip by jumping to end
                    const video = document.querySelector('video');
                    if (video && video.duration && isFinite(video.duration)) {
                        video.currentTime = video.duration;
                        try { window.webkit.messageHandlers.youtubeAdBlocked.postMessage('forced_skip'); } catch(e) {}
                    }
                }
            }

            // Observe player class changes for ad-showing
            const observer = new MutationObserver(function(mutations) {
                for (const m of mutations) {
                    if (m.type === 'attributes' && m.attributeName === 'class') {
                        skipAd();
                    }
                    // Also check for new ad nodes
                    if (m.type === 'childList' && m.addedNodes.length > 0) {
                        for (const node of m.addedNodes) {
                            if (node.nodeType === 1 && (
                                node.tagName === 'YTD-AD-SLOT-RENDERER' ||
                                node.classList?.contains('ytp-ad-module')
                            )) {
                                node.remove();
                                try { window.webkit.messageHandlers.youtubeAdBlocked.postMessage('removed_node'); } catch(e) {}
                            }
                        }
                    }
                }
            });

            // Start observing once player is available
            function attachObserver() {
                const player = document.querySelector('.html5-video-player');
                if (player) {
                    observer.observe(player, { attributes: true, childList: true, subtree: true });
                    // Also observe body for feed ads
                    observer.observe(document.body, { childList: true, subtree: true });
                } else {
                    setTimeout(attachObserver, 1000);
                }
            }

            if (document.readyState === 'loading') {
                document.addEventListener('DOMContentLoaded', attachObserver);
            } else {
                attachObserver();
            }
        })();
        """
    }
}
