import Foundation

/// Gestiona el modo de compatibilidad Chrome para tabs WebKit.
/// Permite que sitios que solo aceptan Chrome funcionen en WebKit
/// mediante spoofing de User-Agent y propiedades JavaScript.
class ChromeCompatManager {
    static let shared = ChromeCompatManager()

    // MARK: - User-Agent Strings

    static let safariUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.2 Safari/605.1.15"

    static let chromeUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.7632.68 Safari/537.36"

    // MARK: - Chrome Spoofing Script

    /// JavaScript que inyecta propiedades de Chrome en WebKit
    static let chromeSpoofingScript = """
    (function() {
        // 1. Simular objeto window.chrome
        if (!window.chrome) {
            window.chrome = {
                runtime: {},
                loadTimes: function() { return {}; },
                csi: function() { return {}; }
            };
        }

        // 2. Simular navigator.userAgentData (Chrome UA-CH API)
        if (!navigator.userAgentData) {
            Object.defineProperty(navigator, 'userAgentData', {
                get: () => ({
                    brands: [
                        { brand: "Chromium", version: "145" },
                        { brand: "Google Chrome", version: "145" },
                        { brand: "Not-A.Brand", version: "99" }
                    ],
                    mobile: false,
                    platform: "macOS",
                    getHighEntropyValues: function(hints) {
                        return Promise.resolve({
                            brands: this.brands,
                            mobile: false,
                            platform: "macOS",
                            platformVersion: "15.0.0",
                            architecture: "arm",
                            model: "",
                            uaFullVersion: "145.0.7632.68"
                        });
                    }
                }),
                configurable: true
            });
        }

        // 3. Vendor = Google (Safari usa "Apple Computer, Inc.")
        Object.defineProperty(navigator, 'vendor', {
            get: () => 'Google Inc.',
            configurable: true
        });

        // 4. Ocultar webdriver
        Object.defineProperty(navigator, 'webdriver', {
            get: () => false,
            configurable: true
        });
    })();
    """

    // MARK: - Persistencia por dominio

    private var domainPreferences: [String: Bool] = [:]
    private let filePath: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let maiDir = appSupport.appendingPathComponent("MAI", isDirectory: true)
        try? FileManager.default.createDirectory(at: maiDir, withIntermediateDirectories: true)
        self.filePath = maiDir.appendingPathComponent("chrome_compat_domains.json")
        loadPreferences()
    }

    func isEnabled(domain: String) -> Bool {
        return domainPreferences[domain] ?? false
    }

    func setPreference(domain: String, enabled: Bool) {
        if enabled {
            domainPreferences[domain] = true
        } else {
            domainPreferences.removeValue(forKey: domain)
        }
        savePreferences()
    }

    var enabledDomains: [String] {
        domainPreferences.filter { $0.value }.map { $0.key }.sorted()
    }

    func removeAll() {
        domainPreferences.removeAll()
        savePreferences()
    }

    // MARK: - JSON Persistence

    private func loadPreferences() {
        guard FileManager.default.fileExists(atPath: filePath.path),
              let data = try? Data(contentsOf: filePath),
              let decoded = try? JSONDecoder().decode([String: Bool].self, from: data) else { return }
        domainPreferences = decoded
    }

    private func savePreferences() {
        guard let data = try? JSONEncoder().encode(domainPreferences) else { return }
        try? data.write(to: filePath, options: .atomic)
    }
}
