import Foundation
import WebKit

/// Manages downloading, parsing, and compiling EasyList/EasyPrivacy filter lists
/// into WKContentRuleList for native WebKit content blocking.
///
/// RAM impact: ~2-5 MB per compiled list (rules run inside WebKit process, not app memory)
/// WebKit limit: ~50,000 rules per content rule list
class EasyListManager: ObservableObject {
    static let shared = EasyListManager()

    // MARK: - Filter List Definitions

    struct FilterList {
        let identifier: String
        let url: URL
        let name: String
    }

    let filterLists: [FilterList] = [
        FilterList(
            identifier: "MAI_EasyList",
            url: URL(string: "https://easylist.to/easylist/easylist.txt")!,
            name: "EasyList (Ads)"
        ),
        FilterList(
            identifier: "MAI_EasyPrivacy",
            url: URL(string: "https://easylist.to/easylist/easyprivacy.txt")!,
            name: "EasyPrivacy (Trackers)"
        )
    ]

    // MARK: - State

    @Published var compiledRuleLists: [WKContentRuleList] = []
    @Published var isLoaded = false
    @Published var isLoading = false
    @Published var totalRulesCount: Int = 0
    @Published var lastUpdateDate: Date?
    @Published var statusMessage: String = "No cargado"

    // MARK: - Configuration

    private let maxRulesPerList = 45000
    private let updateInterval: TimeInterval = 7 * 24 * 60 * 60 // 1 week

    private let cacheDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("MAI/EasyList", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private init() {
        // Load last update date from disk
        let metaFile = cacheDirectory.appendingPathComponent("global.meta.plist")
        if let meta = NSDictionary(contentsOf: metaFile) as? [String: Any],
           let date = meta["lastUpdate"] as? Date {
            lastUpdateDate = date
        }
    }

    // MARK: - Public API

    /// Load and compile all filter lists. Call once at app startup.
    func loadFilterLists() async {
        await MainActor.run {
            isLoading = true
            statusMessage = "Descargando listas..."
        }

        var allRules: [WKContentRuleList] = []
        var totalCount = 0

        for list in filterLists {
            do {
                let rawText = try await fetchFilterList(list)
                let jsonRules = parseFilterList(rawText)
                let ruleCount = jsonRules.count
                totalCount += ruleCount

                await MainActor.run {
                    statusMessage = "Compilando \(list.name)..."
                }

                if let compiled = try await compileRules(jsonRules, identifier: list.identifier) {
                    allRules.append(compiled)
                    print("✅ \(list.name): \(ruleCount) reglas compiladas")
                }
            } catch {
                print("⚠️ Error cargando \(list.name): \(error.localizedDescription)")
                // Try WebKit's internal compiled cache
                if let cached = try? await WKContentRuleListStore.default().contentRuleList(forIdentifier: list.identifier) {
                    allRules.append(cached)
                    print("📦 \(list.name): usando caché de WebKit")
                }
            }
        }

        // Add OAuth whitelist as ignore-previous-rules (must be last)
        if let oauthRules = try? await compileOAuthWhitelist() {
            allRules.append(oauthRules)
        }

        // Save global metadata
        let metaFile = cacheDirectory.appendingPathComponent("global.meta.plist")
        let meta: [String: Any] = ["lastUpdate": Date(), "totalRules": totalCount]
        (meta as NSDictionary).write(to: metaFile, atomically: true)

        // Capture values for MainActor closure (Swift 6 sendable)
        let finalRules = allRules
        let finalCount = totalCount

        await MainActor.run {
            self.compiledRuleLists = finalRules
            self.totalRulesCount = finalCount
            self.isLoaded = true
            self.isLoading = false
            self.lastUpdateDate = Date()
            self.statusMessage = "\(finalCount) reglas activas"
        }

        print("🛡️ EasyList: \(totalCount) reglas totales en \(allRules.count) listas")
    }

    /// Force re-download all lists ignoring cache
    func forceUpdate() async {
        for list in filterLists {
            let metaFile = cacheDirectory.appendingPathComponent("\(list.identifier).meta.plist")
            try? FileManager.default.removeItem(at: metaFile)
        }
        await loadFilterLists()
    }

    // MARK: - Download / Cache

    private func fetchFilterList(_ list: FilterList) async throws -> String {
        let cachedFile = cacheDirectory.appendingPathComponent("\(list.identifier).txt")
        let metaFile = cacheDirectory.appendingPathComponent("\(list.identifier).meta.plist")

        // Check if cache is fresh
        if let meta = NSDictionary(contentsOf: metaFile) as? [String: Any],
           let lastUpdate = meta["lastUpdate"] as? Date,
           Date().timeIntervalSince(lastUpdate) < updateInterval,
           let cached = try? String(contentsOf: cachedFile, encoding: .utf8) {
            print("📦 \(list.name): usando caché (actualizado \(Self.formatDate(lastUpdate)))")
            return cached
        }

        // Download fresh
        print("⬇️ Descargando \(list.name)...")
        let (data, response) = try await URLSession.shared.data(from: list.url)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        guard let text = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "EasyList", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid encoding"])
        }

        // Save to disk
        try text.write(to: cachedFile, atomically: true, encoding: .utf8)
        let fileMeta: [String: Any] = ["lastUpdate": Date(), "size": data.count]
        (fileMeta as NSDictionary).write(to: metaFile, atomically: true)

        return text
    }

    // MARK: - Parser (Adblock Plus format → WebKit JSON)

    func parseFilterList(_ text: String) -> [[String: Any]] {
        var rules: [[String: Any]] = []
        let lines = text.components(separatedBy: .newlines)

        for line in lines {
            guard rules.count < maxRulesPerList else { break }

            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip comments, empty lines, headers
            if trimmed.isEmpty || trimmed.hasPrefix("!") || trimmed.hasPrefix("[") { continue }

            // CSS hiding rules: ##.selector or domain##.selector
            if trimmed.contains("##") && !trimmed.contains("#@#") {
                if let rule = parseCSSHidingRule(trimmed) {
                    rules.append(rule)
                }
                continue
            }

            // Skip CSS exception rules
            if trimmed.contains("#@#") { continue }

            // Exception rules: @@||domain^
            if trimmed.hasPrefix("@@") {
                if let rule = parseExceptionRule(String(trimmed.dropFirst(2))) {
                    rules.append(rule)
                }
                continue
            }

            // Blocking rules
            if let rule = parseBlockingRule(trimmed) {
                rules.append(rule)
            }
        }

        return rules
    }

    // MARK: - Rule Parsers

    private func parseBlockingRule(_ line: String) -> [String: Any]? {
        var pattern = line
        var trigger: [String: Any] = [:]
        var loadType: [String]?
        var resourceTypes: [String]?

        // Extract options after $
        if let dollarIndex = pattern.lastIndex(of: "$") {
            let options = String(pattern[pattern.index(after: dollarIndex)...])
            pattern = String(pattern[..<dollarIndex])

            let parts = options.components(separatedBy: ",")
            for opt in parts {
                switch opt {
                case "third-party", "3p":
                    loadType = ["third-party"]
                case "~third-party", "~3p", "first-party", "1p":
                    loadType = ["first-party"]
                case "script":
                    resourceTypes = (resourceTypes ?? []) + ["script"]
                case "image":
                    resourceTypes = (resourceTypes ?? []) + ["image"]
                case "stylesheet":
                    resourceTypes = (resourceTypes ?? []) + ["style-sheet"]
                case "xmlhttprequest", "fetch":
                    resourceTypes = (resourceTypes ?? []) + ["raw"]
                case "media":
                    resourceTypes = (resourceTypes ?? []) + ["media"]
                case "font":
                    resourceTypes = (resourceTypes ?? []) + ["font"]
                case "popup":
                    resourceTypes = (resourceTypes ?? []) + ["popup"]
                case "subdocument":
                    resourceTypes = (resourceTypes ?? []) + ["document"]
                default:
                    // Skip domain-specific or unsupported options
                    if opt.hasPrefix("domain=") || opt.hasPrefix("csp=") ||
                       opt.hasPrefix("rewrite=") || opt.hasPrefix("redirect=") ||
                       opt == "websocket" || opt == "webrtc" ||
                       opt == "important" || opt == "match-case" {
                        continue
                    }
                    // Skip negated resource types (~script, etc.)
                    if opt.hasPrefix("~") { continue }
                    // Unknown option — skip entire rule to be safe
                    return nil
                }
            }
        }

        guard !pattern.isEmpty else { return nil }

        // Convert to url-filter regex
        guard let urlFilter = convertToURLFilter(pattern) else { return nil }

        trigger["url-filter"] = urlFilter
        if let lt = loadType { trigger["load-type"] = lt }
        if let rt = resourceTypes, !rt.isEmpty { trigger["resource-type"] = rt }

        return [
            "trigger": trigger,
            "action": ["type": "block"]
        ]
    }

    private func parseExceptionRule(_ line: String) -> [String: Any]? {
        var pattern = line

        // Strip options (keep it simple for exceptions)
        if let dollarIndex = pattern.lastIndex(of: "$") {
            pattern = String(pattern[..<dollarIndex])
        }

        guard !pattern.isEmpty else { return nil }
        guard let urlFilter = convertToURLFilter(pattern) else { return nil }

        return [
            "trigger": ["url-filter": urlFilter],
            "action": ["type": "ignore-previous-rules"]
        ]
    }

    private func parseCSSHidingRule(_ line: String) -> [String: Any]? {
        guard let hashRange = line.range(of: "##") else { return nil }

        let domains = String(line[..<hashRange.lowerBound])
        let selector = String(line[hashRange.upperBound...])

        guard !selector.isEmpty else { return nil }

        // Skip procedural/extended selectors
        if selector.contains(":has(") || selector.contains(":contains(") ||
           selector.contains(":-abp-") || selector.contains(":style(") ||
           selector.contains(":matches-css(") || selector.contains(":xpath(") {
            return nil
        }

        var trigger: [String: Any] = ["url-filter": ".*"]

        if !domains.isEmpty {
            let domainList = domains.components(separatedBy: ",")
            let ifDomains = domainList.filter { !$0.hasPrefix("~") }.map { "*\($0)" }
            let unlessDomains = domainList.filter { $0.hasPrefix("~") }.map { "*\(String($0.dropFirst()))" }

            if !ifDomains.isEmpty { trigger["if-domain"] = ifDomains }
            if !unlessDomains.isEmpty { trigger["unless-domain"] = unlessDomains }
        }

        return [
            "trigger": trigger,
            "action": [
                "type": "css-display-none",
                "selector": selector
            ]
        ]
    }

    // MARK: - Pattern Conversion

    /// Convert Adblock Plus pattern to WebKit url-filter regex
    private func convertToURLFilter(_ pattern: String) -> String? {
        var p = pattern

        // Domain anchor: ||domain.com^
        if p.hasPrefix("||") {
            p = String(p.dropFirst(2))
            let escaped = escapeForRegex(p)
            // Match domain and subdomains
            return "^[^:]+:(//)?([^/]*\\.)?" + escaped
        }

        // Start anchor: |http
        if p.hasPrefix("|") {
            p = String(p.dropFirst())
            return "^" + escapeForRegex(p)
        }

        // End anchor: .js|
        if p.hasSuffix("|") {
            p = String(p.dropLast())
            return escapeForRegex(p) + "$"
        }

        let escaped = escapeForRegex(p)

        // Skip overly broad patterns (< 5 chars after escaping)
        if escaped.replacingOccurrences(of: "\\", with: "").replacingOccurrences(of: ".", with: "").count < 4 {
            return nil
        }

        return escaped
    }

    /// Escape regex special characters, convert Adblock Plus wildcards
    private func escapeForRegex(_ pattern: String) -> String {
        var result = ""
        for char in pattern {
            switch char {
            case "^":
                result += "[/:?&=]"
            case "*":
                result += ".*"
            case ".":
                result += "\\."
            case "+":
                result += "\\+"
            case "?":
                result += "\\?"
            case "|":
                result += "\\|"
            case "{", "}", "(", ")", "[", "]", "\\":
                result += "\\\(char)"
            default:
                result.append(char)
            }
        }
        return result
    }

    // MARK: - Compile

    private func compileRules(_ rules: [[String: Any]], identifier: String) async throws -> WKContentRuleList? {
        guard !rules.isEmpty else { return nil }

        let jsonData = try JSONSerialization.data(withJSONObject: rules)
        guard let jsonString = String(data: jsonData, encoding: .utf8) else { return nil }

        return try await WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: identifier,
            encodedContentRuleList: jsonString
        )
    }

    /// Create whitelist rules for OAuth domains so they're never blocked
    private func compileOAuthWhitelist() async throws -> WKContentRuleList? {
        let oauthDomains = PrivacyManager.shared.oauthDomainsList()

        var rules: [[String: Any]] = []
        for domain in oauthDomains {
            rules.append([
                "trigger": [
                    "url-filter": ".*",
                    "if-domain": ["*\(domain)"]
                ],
                "action": ["type": "ignore-previous-rules"]
            ])
        }

        guard !rules.isEmpty else { return nil }

        let jsonData = try JSONSerialization.data(withJSONObject: rules)
        guard let jsonString = String(data: jsonData, encoding: .utf8) else { return nil }

        return try await WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "MAI_OAuthWhitelist",
            encodedContentRuleList: jsonString
        )
    }

    // MARK: - Helpers

    private static func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
