import Foundation
import WebKit

/// Gestiona el auto-rechazo de cookie banners y el envío del header GPC (Global Privacy Control)
class CookieBannerManager: ObservableObject {
    static let shared = CookieBannerManager()

    @Published var autoDismissCookieBanners: Bool {
        didSet { UserDefaults.standard.set(autoDismissCookieBanners, forKey: "autoDismissCookieBanners") }
    }
    @Published var sendGPC: Bool {
        didSet { UserDefaults.standard.set(sendGPC, forKey: "sendGPC") }
    }
    @Published var bannersBlocked: Int {
        didSet { UserDefaults.standard.set(bannersBlocked, forKey: "cookieBannersBlocked") }
    }

    /// WKContentRuleList compilada para ocultar cookie banners via CSS
    var compiledRuleList: WKContentRuleList?

    private init() {
        self.autoDismissCookieBanners = UserDefaults.standard.object(forKey: "autoDismissCookieBanners") as? Bool ?? true
        self.sendGPC = UserDefaults.standard.object(forKey: "sendGPC") as? Bool ?? true
        self.bannersBlocked = UserDefaults.standard.integer(forKey: "cookieBannersBlocked")
    }

    func resetCount() {
        bannersBlocked = 0
    }

    // MARK: - WKContentRuleList (CSS hiding)

    /// Compila reglas CSS para ocultar cookie banners conocidos
    func compileRules() {
        let rules = Self.cssHidingRules
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "cookie-banner-hider",
            encodedContentRuleList: rules
        ) { [weak self] ruleList, error in
            if let ruleList = ruleList {
                DispatchQueue.main.async {
                    self?.compiledRuleList = ruleList
                }
            } else if let error = error {
                print("⚠️ Cookie banner rule compilation failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - GPC JavaScript (navigator.globalPrivacyControl)

    /// Script que establece navigator.globalPrivacyControl = true
    static let gpcScript: String = """
    (function() {
        if (window.__maiGPC) return;
        window.__maiGPC = true;

        // Global Privacy Control signal
        try {
            Object.defineProperty(navigator, 'globalPrivacyControl', {
                value: true,
                writable: false,
                configurable: false,
                enumerable: true
            });
        } catch(e) {}

        // DNT (Do Not Track) legacy signal
        try {
            Object.defineProperty(navigator, 'doNotTrack', {
                value: '1',
                writable: false,
                configurable: false,
                enumerable: true
            });
        } catch(e) {}
    })();
    """

    // MARK: - Cookie Banner Auto-Dismiss Script

    /// Script principal que detecta y auto-rechaza cookie banners
    /// Funciona con: OneTrust, Cookiebot, TrustArc, Quantcast, CookieYes,
    /// Osano, Didomi, Klaro, CookieConsent, GDPR Cookie Compliance, y genéricos
    static let bannerDismissScript: String = """
    (function() {
        if (window.__maiCookieBanner) return;
        window.__maiCookieBanner = true;

        const MAX_ATTEMPTS = 15;
        const INTERVAL_MS = 800;
        let attempts = 0;
        let dismissed = false;

        // Selectores de botones "Rechazar" / "Solo necesarias" / "Decline" por framework
        const rejectSelectors = [
            // OneTrust (muy común)
            '#onetrust-reject-all-handler',
            '.onetrust-close-btn-handler',
            'button[id*="reject"]',

            // Cookiebot
            '#CybotCookiebotDialogBodyButtonDecline',
            '#CybotCookiebotDialogBodyLevelButtonLevelOptinDeclineAll',
            'a#CybotCookiebotDialogBodyContentTextAboutCookiesLink',

            // Quantcast / CMP
            '.qc-cmp2-summary-buttons button[mode="secondary"]',
            'button.qc-cmp2-decline-button',
            '.qc-cmp-button[onclick*="reject"]',

            // TrustArc / TrustE
            '.truste-consent-required',
            '#truste-consent-button',
            'a.acceptAll[onclick*="reject"]',

            // Didomi
            '#didomi-notice-disagree-button',
            'button[aria-label*="Disagree"]',
            'button[aria-label*="Rechazar"]',
            'button[aria-label*="Reject"]',

            // Klaro
            '.klaro .cn-decline',
            'button.cm-btn-decline',

            // CookieYes / CookieLaw
            '#cookie_action_close_header_reject',
            'button[data-cky-tag="reject-button"]',

            // Osano
            '.osano-cm-deny',
            '.osano-cm-dialog__close',

            // GDPR Cookie Compliance
            'button[data-action="reject"]',
            '.gdpr-cm-reject',

            // IAB TCF CMP genérico
            'button[title*="Reject"]',
            'button[title*="Rechazar"]',
            'button[title*="Decline"]',
            'button[title*="Refuse"]',
            'button[title*="Deny"]',

            // Genéricos por texto (amplio)
            'button[class*="reject"]',
            'button[class*="decline"]',
            'button[class*="deny"]',
            'button[id*="decline"]',
            'button[id*="deny"]',
            'a[class*="reject"]',
            'a[id*="reject"]',

            // Cookie Notice genérico
            '.cookie-notice-dismiss',
            '.cc-dismiss',
            '.cc-deny',
            '.cc-btn.cc-deny',

            // Complianz
            '.cmplz-deny',
            '#cmplz-deny-btn',

            // Borlabs Cookie
            'a[data-cookie-refuse]',
            '#BorlabsCookieBoxRefuseButton'
        ];

        // Selectores de botones "Aceptar necesarias solamente" (fallback si no hay "Rechazar")
        const necessaryOnlySelectors = [
            'button[data-action="necessary"]',
            'button[class*="necessary"]',
            'button[class*="essential"]',
            'button[id*="necessary"]',
            '#cookie-necessary',
            '.js-accept-essential',
            'button[data-gdpr="necessary"]'
        ];

        // Selectores de banners para detectar presencia
        const bannerSelectors = [
            '#onetrust-banner-sdk',
            '#CybotCookiebotDialog',
            '#qcCmpUi',
            '.truste-consent-content',
            '#didomi-notice',
            '.klaro',
            '.osano-cm-window',
            '.gdpr-cookie-notice',
            '[class*="cookie-banner"]',
            '[class*="cookie-consent"]',
            '[class*="cookie-notice"]',
            '[class*="cookieConsent"]',
            '[class*="CookieConsent"]',
            '[id*="cookie-banner"]',
            '[id*="cookie-consent"]',
            '[id*="cookie-notice"]',
            '[id*="gdpr"]',
            '[id*="GDPR"]',
            '.cc-window',
            '#cookie-law-info-bar',
            '.cmplz-cookiebanner'
        ];

        function tryDismiss() {
            if (dismissed || attempts >= MAX_ATTEMPTS) return;
            attempts++;

            // 1. Intentar hacer click en "Rechazar"
            for (const sel of rejectSelectors) {
                const btn = document.querySelector(sel);
                if (btn && btn.offsetParent !== null) {
                    btn.click();
                    dismissed = true;
                    window.webkit?.messageHandlers?.cookieBannerDismissed?.postMessage('rejected');
                    return;
                }
            }

            // 2. Fallback: "Solo necesarias"
            for (const sel of necessaryOnlySelectors) {
                const btn = document.querySelector(sel);
                if (btn && btn.offsetParent !== null) {
                    btn.click();
                    dismissed = true;
                    window.webkit?.messageHandlers?.cookieBannerDismissed?.postMessage('necessary');
                    return;
                }
            }

            // 3. Búsqueda por texto en botones visibles (último recurso)
            const rejectTexts = [
                'rechazar', 'reject', 'decline', 'deny', 'refuse',
                'no acepto', 'no thanks', 'non merci', 'ablehnen',
                'solo necesarias', 'only necessary', 'essential only',
                'manage preferences', 'gestionar preferencias'
            ];
            const buttons = document.querySelectorAll('button, a[role="button"], [class*="btn"]');
            for (const btn of buttons) {
                const text = (btn.textContent || '').trim().toLowerCase();
                if (text.length > 2 && text.length < 50) {
                    for (const rt of rejectTexts) {
                        if (text.includes(rt)) {
                            btn.click();
                            dismissed = true;
                            window.webkit?.messageHandlers?.cookieBannerDismissed?.postMessage('text-match');
                            return;
                        }
                    }
                }
            }
        }

        // Ejecutar al cargar y luego periódicamente (banners con delay)
        if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', tryDismiss);
        } else {
            tryDismiss();
        }

        // Observer para banners que aparecen después del DOMContentLoaded
        const observer = new MutationObserver(function(mutations) {
            if (dismissed) { observer.disconnect(); return; }
            for (const sel of bannerSelectors) {
                if (document.querySelector(sel)) {
                    setTimeout(tryDismiss, 300);
                    return;
                }
            }
        });
        observer.observe(document.documentElement, { childList: true, subtree: true });

        // Polling con backoff como último recurso
        const timer = setInterval(function() {
            if (dismissed || attempts >= MAX_ATTEMPTS) {
                clearInterval(timer);
                observer.disconnect();
                return;
            }
            tryDismiss();
        }, INTERVAL_MS);

        // Limpiar después de 15 segundos max
        setTimeout(function() {
            clearInterval(timer);
            observer.disconnect();
        }, 15000);
    })();
    """

    // MARK: - CSS Hiding Rules (WKContentRuleList JSON)

    /// Reglas CSS para ocultar banners de cookies conocidos mientras el JS los rechaza
    static let cssHidingRules: String = """
    [
        {
            "trigger": {"url-filter": ".*"},
            "action": {"type": "css-display-none", "selector": "#onetrust-banner-sdk, #onetrust-consent-sdk"}
        },
        {
            "trigger": {"url-filter": ".*"},
            "action": {"type": "css-display-none", "selector": "#CybotCookiebotDialog, #CybotCookiebotDialogBodyUnderlay"}
        },
        {
            "trigger": {"url-filter": ".*"},
            "action": {"type": "css-display-none", "selector": "#qcCmpUi, .qc-cmp-showing"}
        },
        {
            "trigger": {"url-filter": ".*"},
            "action": {"type": "css-display-none", "selector": ".truste-consent-content, #truste-consent-track"}
        },
        {
            "trigger": {"url-filter": ".*"},
            "action": {"type": "css-display-none", "selector": "#didomi-notice, .didomi-popup-backdrop"}
        },
        {
            "trigger": {"url-filter": ".*"},
            "action": {"type": "css-display-none", "selector": ".osano-cm-window, .osano-cm-dialog__backdrop"}
        },
        {
            "trigger": {"url-filter": ".*"},
            "action": {"type": "css-display-none", "selector": ".klaro .cookie-notice, .klaro .cookie-modal"}
        },
        {
            "trigger": {"url-filter": ".*"},
            "action": {"type": "css-display-none", "selector": "#cookie-law-info-bar, .cookie-law-info-bar"}
        },
        {
            "trigger": {"url-filter": ".*"},
            "action": {"type": "css-display-none", "selector": ".cmplz-cookiebanner, #cmplz-cookiebanner-container"}
        },
        {
            "trigger": {"url-filter": ".*"},
            "action": {"type": "css-display-none", "selector": ".cc-window.cc-banner, .cc-revoke"}
        },
        {
            "trigger": {"url-filter": ".*"},
            "action": {"type": "css-display-none", "selector": "[id*='cookie-consent'], [class*='cookie-consent-banner']"}
        },
        {
            "trigger": {"url-filter": ".*"},
            "action": {"type": "css-display-none", "selector": "[id*='gdpr-banner'], [class*='gdpr-banner']"}
        },
        {
            "trigger": {"url-filter": ".*"},
            "action": {"type": "css-display-none", "selector": ".cookie-notice, #cookie-notice, [class*='cookieNotice']"}
        },
        {
            "trigger": {"url-filter": ".*"},
            "action": {"type": "css-display-none", "selector": "#BorlabsCookieBox, .borlabs-cookie-overlay"}
        },
        {
            "trigger": {"url-filter": ".*", "resource-type": ["script"]},
            "action": {"type": "block"},
            "trigger": {"url-filter": "consent\\\\.cookiebot\\\\.com"}
        },
        {
            "trigger": {"url-filter": "consent\\\\.cookiefirst\\\\.com", "resource-type": ["script"]},
            "action": {"type": "block"}
        },
        {
            "trigger": {"url-filter": "cdn\\\\.privacy-mgmt\\\\.com", "resource-type": ["script"]},
            "action": {"type": "block"}
        }
    ]
    """
}
