import Foundation
import WebKit

/// Gestor de privacidad con soporte para OAuth
class PrivacyManager: ObservableObject {
    static let shared = PrivacyManager()

    // MARK: - Configuraciones (sincronizadas con @AppStorage)

    @Published var blockTrackers: Bool {
        didSet { UserDefaults.standard.set(blockTrackers, forKey: "blockTrackers") }
    }
    @Published var blockAds: Bool {
        didSet { UserDefaults.standard.set(blockAds, forKey: "blockAds") }
    }
    @Published var blockThirdPartyCookies: Bool {
        didSet { UserDefaults.standard.set(blockThirdPartyCookies, forKey: "blockThirdPartyCookies") }
    }
    @Published var fingerprintProtection: Bool {
        didSet { UserDefaults.standard.set(fingerprintProtection, forKey: "fingerprintProtection") }
    }

    // MARK: - Dominios de OAuth (whitelist)

    /// Dominios esenciales para OAuth que NUNCA se bloquean
    private let oauthWhitelist: Set<String> = [
        // Google OAuth y servicios esenciales
        "accounts.google.com",
        "accounts.google.es",
        "accounts.google.com.mx",
        "oauth2.googleapis.com",
        "www.googleapis.com",
        "apis.google.com",
        "ssl.gstatic.com",
        "www.gstatic.com",
        "csi.gstatic.com",
        "fonts.gstatic.com",
        "fonts.googleapis.com",
        "lh3.googleusercontent.com",
        "googleusercontent.com",
        "mail.google.com",
        "play.google.com",
        "myaccount.google.com",
        "ogs.google.com",
        "clients1.google.com",
        "clients2.google.com",
        "clients3.google.com",
        "clients4.google.com",
        "clients5.google.com",
        "clients6.google.com",
        "signaler-pa.googleapis.com",
        "content-autofill.googleapis.com",

        // Microsoft OAuth / Office 365
        "login.microsoftonline.com",
        "login.live.com",
        "login.windows.net",
        "account.live.com",
        "aadcdn.msauth.net",
        "aadcdn.msftauth.net",
        "logincdn.msauth.net",

        // Apple OAuth
        "appleid.apple.com",
        "idmsa.apple.com",
        "gsa.apple.com",

        // GitHub OAuth
        "github.com",
        "api.github.com",

        // Facebook OAuth
        "www.facebook.com",
        "facebook.com",
        "m.facebook.com",

        // Twitter/X OAuth
        "api.twitter.com",
        "twitter.com",
        "x.com",

        // Amazon OAuth
        "www.amazon.com",
        "amazon.com",
        "na.account.amazon.com",

        // LinkedIn OAuth
        "www.linkedin.com",
        "linkedin.com",

        // Dropbox OAuth
        "www.dropbox.com",
        "dropbox.com",

        // Auth0 (popular auth provider)
        "auth0.com",

        // Okta (enterprise auth)
        "okta.com",

        // Recaptcha y verificación (necesarios para login)
        "www.google.com",
        "www.recaptcha.net",
        "recaptcha.net",
        "challenges.cloudflare.com",
        "hcaptcha.com",
        "js.hcaptcha.com"
    ]

    // MARK: - Dominios de Trackers/Ads a bloquear

    private let trackerDomains: Set<String> = [
        // Tracking
        "googleadservices.com",
        "doubleclick.net",
        "googlesyndication.com",
        "googletagmanager.com",
        "google-analytics.com",
        "analytics.google.com",
        "facebook.net",
        "pixel.facebook.com",
        "connect.facebook.net",
        "analytics.twitter.com",
        "ads.twitter.com",
        "t.co",
        "scorecardresearch.com",
        "quantserve.com",
        "mixpanel.com",
        "segment.io",
        "segment.com",
        "amplitude.com",
        "hotjar.com",
        "crazyegg.com",
        "fullstory.com",
        "mouseflow.com",
        "clarity.ms",

        // Ads
        "amazon-adsystem.com",
        "adsrvr.org",
        "adnxs.com",
        "criteo.com",
        "criteo.net",
        "outbrain.com",
        "taboola.com",
        "pubmatic.com",
        "rubiconproject.com",
        "openx.net",
        "advertising.com",
        "adroll.com",
        "mediavine.com",
        "moatads.com",
        "adsafeprotected.com"
    ]

    // MARK: - Initialization

    private init() {
        self.blockTrackers = UserDefaults.standard.object(forKey: "blockTrackers") as? Bool ?? true
        self.blockAds = UserDefaults.standard.object(forKey: "blockAds") as? Bool ?? true
        self.blockThirdPartyCookies = UserDefaults.standard.object(forKey: "blockThirdPartyCookies") as? Bool ?? true
        self.fingerprintProtection = UserDefaults.standard.object(forKey: "fingerprintProtection") as? Bool ?? true
    }

    // MARK: - Public Methods

    /// Determina si un dominio está en la whitelist de OAuth
    func isOAuthDomain(_ host: String) -> Bool {
        let lowercaseHost = host.lowercased()
        return oauthWhitelist.contains { domain in
            lowercaseHost == domain || lowercaseHost.hasSuffix("." + domain)
        }
    }

    /// Determina si una URL debe ser bloqueada
    func shouldBlock(url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }

        // NUNCA bloquear dominios de OAuth
        if isOAuthDomain(host) {
            return false
        }

        // Bloquear trackers si está habilitado
        if blockTrackers || blockAds {
            for tracker in trackerDomains {
                if host == tracker || host.hasSuffix("." + tracker) {
                    return true
                }
            }
        }

        return false
    }

    /// Crea reglas de bloqueo de contenido para WKWebView
    func createContentBlockingRules() async throws -> WKContentRuleList? {
        guard blockTrackers || blockAds else { return nil }

        var rules: [[String: Any]] = []

        // Crear reglas para cada tracker
        for domain in trackerDomains {
            // Verificar que no esté en whitelist (por si acaso)
            guard !oauthWhitelist.contains(domain) else { continue }

            let rule: [String: Any] = [
                "trigger": [
                    "url-filter": ".*\\.\(domain.replacingOccurrences(of: ".", with: "\\.")).*"
                ],
                "action": [
                    "type": "block"
                ]
            ]
            rules.append(rule)
        }

        guard !rules.isEmpty else { return nil }

        let jsonData = try JSONSerialization.data(withJSONObject: rules)
        guard let jsonString = String(data: jsonData, encoding: .utf8) else { return nil }

        return try await WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "MAIPrivacyRules",
            encodedContentRuleList: jsonString
        )
    }

    /// Estadísticas de bloqueo
    @Published var blockedRequestsCount: Int = 0
    @Published var blockedRequests: [BlockedRequest] = []

    struct BlockedRequest: Identifiable {
        let id = UUID()
        let url: String
        let domain: String
        let timestamp: Date
        let type: BlockType

        enum BlockType: String {
            case tracker = "Rastreador"
            case ad = "Anuncio"
            case thirdPartyCookie = "Cookie terceros"
        }
    }

    func recordBlockedRequest(url: URL, type: BlockedRequest.BlockType = .tracker) {
        DispatchQueue.main.async {
            self.blockedRequestsCount += 1

            let request = BlockedRequest(
                url: url.absoluteString,
                domain: url.host ?? "desconocido",
                timestamp: Date(),
                type: type
            )

            // Mantener solo los últimos 100 para no usar mucha RAM
            self.blockedRequests.insert(request, at: 0)
            if self.blockedRequests.count > 100 {
                self.blockedRequests = Array(self.blockedRequests.prefix(100))
            }
        }
    }

    func resetBlockedCount() {
        blockedRequestsCount = 0
        blockedRequests.removeAll()
    }
}
