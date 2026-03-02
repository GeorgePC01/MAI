import Foundation

/// Modelo de aprendizaje para suspensión de tabs.
/// Aprende las preferencias del usuario por dominio y contexto.
class SuspensionMLModel: ObservableObject {
    static let shared = SuspensionMLModel()

    // MARK: - Types

    enum Prediction {
        case autoSuspend
        case ask
        case neverSuspend
    }

    struct SuspensionDecision: Codable {
        let domain: String
        let timeSinceLastInteraction: Double // minutos
        let hourOfDay: Int
        let dayOfWeek: Int
        let openTabCount: Int
        let isMuted: Bool
        let userApproved: Bool
        let timestamp: Date
    }

    struct DomainStat: Codable {
        var approvedCount: Int = 0
        var rejectedCount: Int = 0
        var averageInactivityMinutes: Double = 0
        var alwaysSuspend: Bool = false

        var totalDecisions: Int { approvedCount + rejectedCount }

        var approvalRate: Double {
            guard totalDecisions > 0 else { return 0 }
            return Double(approvedCount) / Double(totalDecisions)
        }

        mutating func recordDecision(approved: Bool, inactivityMinutes: Double) {
            if approved {
                approvedCount += 1
            } else {
                rejectedCount += 1
            }
            // Media móvil exponencial
            let alpha = 0.3
            averageInactivityMinutes = averageInactivityMinutes == 0
                ? inactivityMinutes
                : averageInactivityMinutes * (1 - alpha) + inactivityMinutes * alpha
        }
    }

    // MARK: - Stored Data

    @Published private(set) var decisions: [SuspensionDecision] = []
    @Published private(set) var domainStats: [String: DomainStat] = [:]

    var totalDecisions: Int { decisions.count }
    var learnedDomains: Int { domainStats.count }

    // MARK: - Persistence

    private static var dataDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("MAI", isDirectory: true)
    }

    private static var decisionsFile: URL {
        dataDirectory.appendingPathComponent("suspension_decisions.json")
    }

    private static var domainStatsFile: URL {
        dataDirectory.appendingPathComponent("suspension_domain_stats.json")
    }

    // MARK: - Init

    private init() {
        load()
    }

    // MARK: - Prediction

    /// Predice si una tab debe ser suspendida automáticamente, preguntada al usuario, o nunca suspendida.
    func predict(domain: String, inactivityMinutes: Double, hourOfDay: Int, dayOfWeek: Int,
                 openTabCount: Int, isMuted: Bool) -> Prediction {
        let stat = domainStats[domain]

        // Si el usuario marcó "Siempre" para este dominio
        if let stat = stat, stat.alwaysSuspend {
            return .autoSuspend
        }

        // Pocas decisiones globales → preguntar
        if totalDecisions < 20 {
            return .ask
        }

        // Pocas decisiones para este dominio → preguntar
        guard let stat = stat, stat.totalDecisions >= 5 else {
            return .ask
        }

        // Alta tasa de aprobación con suficientes datos → auto-suspender
        if stat.approvalRate > 0.80 && stat.totalDecisions >= 10 {
            return .autoSuspend
        }

        // Baja tasa de aprobación con suficientes datos → nunca suspender
        if stat.approvalRate < 0.20 && stat.totalDecisions >= 10 {
            return .neverSuspend
        }

        return .ask
    }

    // MARK: - Recording

    /// Registra una decisión del usuario
    func recordDecision(domain: String, inactivityMinutes: Double, openTabCount: Int,
                        isMuted: Bool, approved: Bool) {
        let now = Date()
        let calendar = Calendar.current
        let decision = SuspensionDecision(
            domain: domain,
            timeSinceLastInteraction: inactivityMinutes,
            hourOfDay: calendar.component(.hour, from: now),
            dayOfWeek: calendar.component(.weekday, from: now),
            openTabCount: openTabCount,
            isMuted: isMuted,
            userApproved: approved,
            timestamp: now
        )
        decisions.append(decision)

        // Actualizar stats del dominio
        var stat = domainStats[domain] ?? DomainStat()
        stat.recordDecision(approved: approved, inactivityMinutes: inactivityMinutes)
        domainStats[domain] = stat

        save()
    }

    /// Marca un dominio para suspender siempre sin preguntar
    func markAlwaysSuspend(domain: String) {
        var stat = domainStats[domain] ?? DomainStat()
        stat.alwaysSuspend = true
        domainStats[domain] = stat
        save()
    }

    /// Resetea todo el aprendizaje
    func resetAll() {
        decisions = []
        domainStats = [:]
        save()
    }

    // MARK: - Persistence

    private func save() {
        let dir = Self.dataDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        if let data = try? encoder.encode(decisions) {
            try? data.write(to: Self.decisionsFile)
        }
        if let data = try? encoder.encode(domainStats) {
            try? data.write(to: Self.domainStatsFile)
        }
    }

    private func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let data = try? Data(contentsOf: Self.decisionsFile),
           let loaded = try? decoder.decode([SuspensionDecision].self, from: data) {
            decisions = loaded
        }
        if let data = try? Data(contentsOf: Self.domainStatsFile),
           let loaded = try? decoder.decode([String: DomainStat].self, from: data) {
            domainStats = loaded
        }
    }
}
