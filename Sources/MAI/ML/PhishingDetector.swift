import Foundation

/// Nivel de amenaza devuelto por el análisis de phishing
enum PhishingThreatLevel {
    case safe
    case suspicious(score: Double, reasons: [String])
    case dangerous(score: Double, reasons: [String])
}

/// Detector heurístico de URLs de phishing.
/// Puntúa URLs de 0.0 (seguro) a 1.0 (phishing definitivo) usando 8 verificaciones.
/// Arquitectura preparada para futura integración con modelos Core ML.
class PhishingDetector: ObservableObject {
    static let shared = PhishingDetector()

    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "phishingDetectionEnabled") }
    }

    /// Umbral de puntuación para advertencia sospechosa (naranja)
    let suspiciousThreshold: Double = 0.3
    /// Umbral de puntuación para advertencia peligrosa (rojo)
    let dangerousThreshold: Double = 0.6

    // MARK: - Marcas objetivo para detección de homoglifos

    private let targetBrands: [String: [String]] = [
        "paypal": ["paypa1", "paypai", "paypaI", "pаypal", "раypal", "payp4l"],
        "google": ["g00gle", "googie", "goog1e", "googlе", "g0ogle"],
        "apple": ["app1e", "appie", "аpple", "appl3"],
        "microsoft": ["rnicrosoft", "micr0soft", "micrоsoft", "microsof1"],
        "amazon": ["amaz0n", "аmazon", "amazоn", "amаzon"],
        "facebook": ["faceb00k", "fаcebook", "facеbook"],
        "netflix": ["netf1ix", "netfiix", "nеtflix"],
        "instagram": ["1nstagram", "instagran", "instаgram"],
        "twitter": ["tw1tter", "tvvitter", "twittеr"],
        "linkedin": ["1inkedin", "linkedln", "linkеdin"],
        "chase": ["chas3", "chаse"],
        "wellsfargo": ["we11sfargo", "wellsfarg0"],
        "bankofamerica": ["bankofamer1ca", "bankоfamerica"],
        "dropbox": ["dr0pbox", "dropb0x"],
        "icloud": ["ic1oud", "iclоud"],
        "outlook": ["0utlook", "outl00k", "outlоok"],
    ]

    /// TLDs sospechosos frecuentemente usados en phishing
    private let suspiciousTLDs: Set<String> = [
        "tk", "ml", "ga", "cf", "gq", "xyz", "top", "pw",
        "cc", "club", "work", "date", "racing", "win",
        "bid", "stream", "download", "loan", "trade"
    ]

    /// Palabras clave de login en rutas de URL
    private let loginKeywords: Set<String> = [
        "login", "signin", "sign-in", "log-in", "verify",
        "account", "secure", "update", "confirm", "password",
        "credential", "authenticate", "auth", "banking"
    ]

    private init() {
        self.isEnabled = UserDefaults.standard.object(forKey: "phishingDetectionEnabled") as? Bool ?? true
    }

    // MARK: - API Pública

    /// Analiza una URL buscando indicadores de phishing. Devuelve nivel de amenaza con puntuación y razones.
    func analyze(url: URL) -> PhishingThreatLevel {
        guard isEnabled else { return .safe }
        guard let host = url.host?.lowercased() else { return .safe }

        // Dominios OAuth en whitelist siempre son seguros
        if PrivacyManager.shared.isOAuthDomain(host) {
            return .safe
        }

        var score: Double = 0.0
        var reasons: [String] = []

        // Verificación 1: Dirección IP como hostname (+0.4)
        if isIPAddress(host) {
            score += 0.4
            reasons.append("Dirección IP como hostname")
        }

        // Verificación 2: Homoglifos / suplantación de marca (+0.5)
        if let brand = detectHomoglyph(in: host) {
            score += 0.5
            reasons.append("Posible suplantación de \(brand)")
        }

        // Verificación 3: Nombre de marca en subdominio (+0.35)
        if let brand = detectBrandInSubdomain(host: host) {
            score += 0.35
            reasons.append("Marca \"\(brand)\" en subdominio sospechoso")
        }

        // Verificación 4: TLD sospechoso (+0.2)
        if hasSuspiciousTLD(host) {
            score += 0.2
            reasons.append("TLD sospechoso frecuente en phishing")
        }

        // Verificación 5: HTTP + palabras clave de login (+0.25)
        if url.scheme == "http" && hasLoginKeywords(url: url) {
            score += 0.25
            reasons.append("Login en conexión HTTP no segura")
        }

        // Verificación 6: Dominio Punycode/IDN (+0.2)
        if isPunycodeDomain(host) {
            score += 0.2
            reasons.append("Dominio internacionalizado (Punycode)")
        }

        // Verificación 7: Exceso de subdominios (+0.15 por nivel extra después de 3)
        let excessSubdomains = countExcessiveSubdomains(host)
        if excessSubdomains > 0 {
            score += 0.15 * Double(excessSubdomains)
            reasons.append("Exceso de subdominios (\(excessSubdomains) extra)")
        }

        // Verificación 8: URL mayor a 200 caracteres (+0.1)
        if url.absoluteString.count > 200 {
            score += 0.1
            reasons.append("URL excesivamente larga (\(url.absoluteString.count) caracteres)")
        }

        // Limitar a 1.0
        score = min(score, 1.0)

        if score >= dangerousThreshold {
            return .dangerous(score: score, reasons: reasons)
        } else if score >= suspiciousThreshold {
            return .suspicious(score: score, reasons: reasons)
        }
        return .safe
    }

    // MARK: - Verificaciones Heurísticas

    private func isIPAddress(_ host: String) -> Bool {
        // IPv4: solo dígitos y puntos
        let ipv4Pattern = #"^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$"#
        if host.range(of: ipv4Pattern, options: .regularExpression) != nil {
            return true
        }
        // IPv6: contiene dos puntos (verificación simplificada)
        if host.contains(":") && host.contains("[") {
            return true
        }
        return false
    }

    private func detectHomoglyph(in host: String) -> String? {
        // Remover TLD y puntos para comparación
        let domainParts = host.split(separator: ".")
        let domainWithoutTLD = domainParts.dropLast().joined(separator: ".")

        for (brand, variants) in targetBrands {
            // Verificar si el dominio contiene una variante homoglifa conocida
            for variant in variants {
                if domainWithoutTLD.contains(variant) {
                    return brand
                }
            }
        }
        return nil
    }

    private func detectBrandInSubdomain(host: String) -> String? {
        let parts = host.split(separator: ".").map(String.init)
        guard parts.count >= 3 else { return nil }

        // El dominio real es la penúltima parte
        // Verificar si nombres de marca aparecen en subdominios (no en el dominio real)
        let subdomains = parts.dropLast(2).joined(separator: ".")

        for brand in targetBrands.keys {
            if subdomains.contains(brand) {
                // Verificar que el dominio real NO sea la marca legítima
                let mainDomain = parts.suffix(2).first ?? ""
                if mainDomain != brand {
                    return brand
                }
            }
        }
        return nil
    }

    private func hasSuspiciousTLD(_ host: String) -> Bool {
        guard let tld = host.split(separator: ".").last.map(String.init) else { return false }
        return suspiciousTLDs.contains(tld)
    }

    private func hasLoginKeywords(url: URL) -> Bool {
        let path = url.path.lowercased()
        let query = url.query?.lowercased() ?? ""
        let combined = path + query

        for keyword in loginKeywords {
            if combined.contains(keyword) {
                return true
            }
        }
        return false
    }

    private func isPunycodeDomain(_ host: String) -> Bool {
        return host.contains("xn--")
    }

    private func countExcessiveSubdomains(_ host: String) -> Int {
        let parts = host.split(separator: ".")
        // Normal: subdominio.dominio.tld (3 partes)
        // Excesivo: cualquier cosa más allá de 3 partes
        let excess = parts.count - 3
        return max(0, excess)
    }
}
