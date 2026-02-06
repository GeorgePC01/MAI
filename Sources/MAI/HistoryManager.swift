import Foundation

/// Entrada del historial
struct HistoryEntry: Codable, Identifiable {
    let id: UUID
    let url: String
    let title: String
    let visitDate: Date

    init(url: String, title: String, visitDate: Date = Date()) {
        self.id = UUID()
        self.url = url
        self.title = title
        self.visitDate = visitDate
    }
}

/// Gestor de historial - guarda en disco, carga solo lo necesario
class HistoryManager: ObservableObject {
    static let shared = HistoryManager()

    @Published private(set) var recentHistory: [HistoryEntry] = []

    private let fileURL: URL
    private let maxEntriesInMemory = 100  // Solo mantener 100 en RAM
    private let maxEntriesOnDisk = 10000  // Máximo en disco

    private init() {
        // Guardar en Application Support
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let maiFolder = appSupport.appendingPathComponent("MAI", isDirectory: true)

        // Crear directorio si no existe
        try? FileManager.default.createDirectory(at: maiFolder, withIntermediateDirectories: true)

        self.fileURL = maiFolder.appendingPathComponent("history.json")

        loadRecentHistory()
    }

    // MARK: - Public Methods

    /// Registra una visita al historial
    func recordVisit(url: String, title: String) {
        // Ignorar URLs vacías o about:blank
        guard !url.isEmpty, url != "about:blank", !url.hasPrefix("about:") else { return }

        let entry = HistoryEntry(url: url, title: title.isEmpty ? url : title)

        // Agregar al inicio
        recentHistory.insert(entry, at: 0)

        // Limitar en memoria
        if recentHistory.count > maxEntriesInMemory {
            recentHistory = Array(recentHistory.prefix(maxEntriesInMemory))
        }

        // Guardar en disco (async para no bloquear UI)
        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.saveHistory()
        }
    }

    /// Busca en el historial
    func search(query: String) -> [HistoryEntry] {
        guard !query.isEmpty else { return recentHistory }

        let lowercaseQuery = query.lowercased()
        return recentHistory.filter { entry in
            entry.title.lowercased().contains(lowercaseQuery) ||
            entry.url.lowercased().contains(lowercaseQuery)
        }
    }

    /// Obtiene historial agrupado por día
    func getGroupedHistory() -> [(date: String, entries: [HistoryEntry])] {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: "es_ES")

        let grouped = Dictionary(grouping: recentHistory) { entry in
            formatter.string(from: entry.visitDate)
        }

        // Ordenar por fecha (más reciente primero)
        return grouped.map { (date: $0.key, entries: $0.value) }
            .sorted { first, second in
                guard let firstEntry = first.entries.first,
                      let secondEntry = second.entries.first else { return false }
                return firstEntry.visitDate > secondEntry.visitDate
            }
    }

    /// Elimina una entrada del historial
    func deleteEntry(_ entry: HistoryEntry) {
        recentHistory.removeAll { $0.id == entry.id }
        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.saveHistory()
        }
    }

    /// Limpia todo el historial
    func clearAll() {
        recentHistory.removeAll()
        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.saveHistory()
        }
    }

    // MARK: - Private Methods

    private func loadRecentHistory() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }

        do {
            let data = try Data(contentsOf: fileURL)
            let allHistory = try JSONDecoder().decode([HistoryEntry].self, from: data)
            // Solo cargar los más recientes en memoria
            recentHistory = Array(allHistory.prefix(maxEntriesInMemory))
        } catch {
            print("Error loading history: \(error)")
        }
    }

    private func saveHistory() {
        do {
            // Cargar historial existente para no perder entradas antiguas
            var allHistory = recentHistory

            if FileManager.default.fileExists(atPath: fileURL.path),
               let existingData = try? Data(contentsOf: fileURL),
               let existingHistory = try? JSONDecoder().decode([HistoryEntry].self, from: existingData) {
                // Combinar, evitando duplicados recientes
                let existingIds = Set(recentHistory.map { $0.id })
                let oldEntries = existingHistory.filter { !existingIds.contains($0.id) }
                allHistory.append(contentsOf: oldEntries)
            }

            // Limitar tamaño total
            if allHistory.count > maxEntriesOnDisk {
                allHistory = Array(allHistory.prefix(maxEntriesOnDisk))
            }

            let data = try JSONEncoder().encode(allHistory)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Error saving history: \(error)")
        }
    }
}
