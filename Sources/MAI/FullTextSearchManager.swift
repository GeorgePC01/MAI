import Foundation
import SQLite3

/// Gestor de búsqueda full-text del contenido de páginas visitadas
/// Usa SQLite FTS5 para indexar y buscar texto de páginas en el historial
class FullTextSearchManager: ObservableObject {
    static let shared = FullTextSearchManager()

    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "fullTextSearchEnabled") }
    }
    @Published var indexedPages: Int = 0
    @Published var isIndexing: Bool = false

    private var db: OpaquePointer?
    private let dbPath: URL
    private let indexQueue = DispatchQueue(label: "com.mai.fulltext", qos: .background)

    private init() {
        self.isEnabled = UserDefaults.standard.object(forKey: "fullTextSearchEnabled") as? Bool ?? true

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let maiFolder = appSupport.appendingPathComponent("MAI", isDirectory: true)
        try? FileManager.default.createDirectory(at: maiFolder, withIntermediateDirectories: true)
        self.dbPath = maiFolder.appendingPathComponent("fulltext_index.db")

        openDatabase()
        updatePageCount()
    }

    deinit {
        if db != nil {
            sqlite3_close(db)
        }
    }

    // MARK: - Database Setup

    private func openDatabase() {
        guard sqlite3_open(dbPath.path, &db) == SQLITE_OK else {
            print("⚠️ FullTextSearch: Failed to open database")
            return
        }

        // Crear tabla FTS5
        let createSQL = """
            CREATE VIRTUAL TABLE IF NOT EXISTS page_content USING fts5(
                url,
                title,
                content,
                visit_date,
                tokenize='unicode61'
            );
        """
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, createSQL, nil, nil, &errMsg) != SQLITE_OK {
            if let errMsg = errMsg {
                print("⚠️ FullTextSearch: \(String(cString: errMsg))")
                sqlite3_free(errMsg)
            }
        }

        // Crear tabla de URLs indexadas (para evitar re-indexar)
        let indexedSQL = """
            CREATE TABLE IF NOT EXISTS indexed_urls (
                url TEXT PRIMARY KEY,
                last_indexed REAL
            );
        """
        sqlite3_exec(db, indexedSQL, nil, nil, nil)
    }

    // MARK: - Indexing

    /// Indexa el contenido de una página (llamado después de didFinish navigation)
    func indexPage(url: String, title: String, content: String) {
        guard isEnabled, !url.isEmpty, url != "about:blank", !url.hasPrefix("about:") else { return }
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // Limitar contenido a 50KB por página (evitar indexar pages enormes)
        let truncatedContent = String(content.prefix(50_000))
        let now = Date().timeIntervalSince1970

        indexQueue.async { [weak self] in
            guard let self = self, let db = self.db else { return }

            // Verificar si ya indexamos esta URL recientemente (última hora)
            var checkStmt: OpaquePointer?
            let checkSQL = "SELECT last_indexed FROM indexed_urls WHERE url = ?;"
            if sqlite3_prepare_v2(db, checkSQL, -1, &checkStmt, nil) == SQLITE_OK {
                sqlite3_bind_text(checkStmt, 1, (url as NSString).utf8String, -1, nil)
                if sqlite3_step(checkStmt) == SQLITE_ROW {
                    let lastIndexed = sqlite3_column_double(checkStmt, 0)
                    if now - lastIndexed < 3600 { // Ya indexada en la última hora
                        sqlite3_finalize(checkStmt)
                        return
                    }
                }
            }
            sqlite3_finalize(checkStmt)

            // Eliminar entrada anterior de esta URL (actualizar)
            var deleteStmt: OpaquePointer?
            let deleteSQL = "DELETE FROM page_content WHERE url = ?;"
            if sqlite3_prepare_v2(db, deleteSQL, -1, &deleteStmt, nil) == SQLITE_OK {
                sqlite3_bind_text(deleteStmt, 1, (url as NSString).utf8String, -1, nil)
                sqlite3_step(deleteStmt)
            }
            sqlite3_finalize(deleteStmt)

            // Insertar nuevo contenido
            var insertStmt: OpaquePointer?
            let insertSQL = "INSERT INTO page_content (url, title, content, visit_date) VALUES (?, ?, ?, ?);"
            if sqlite3_prepare_v2(db, insertSQL, -1, &insertStmt, nil) == SQLITE_OK {
                sqlite3_bind_text(insertStmt, 1, (url as NSString).utf8String, -1, nil)
                sqlite3_bind_text(insertStmt, 2, (title as NSString).utf8String, -1, nil)
                sqlite3_bind_text(insertStmt, 3, (truncatedContent as NSString).utf8String, -1, nil)
                sqlite3_bind_text(insertStmt, 4, (String(now) as NSString).utf8String, -1, nil)
                sqlite3_step(insertStmt)
            }
            sqlite3_finalize(insertStmt)

            // Actualizar tracking de URL indexada
            var upsertStmt: OpaquePointer?
            let upsertSQL = "INSERT OR REPLACE INTO indexed_urls (url, last_indexed) VALUES (?, ?);"
            if sqlite3_prepare_v2(db, upsertSQL, -1, &upsertStmt, nil) == SQLITE_OK {
                sqlite3_bind_text(upsertStmt, 1, (url as NSString).utf8String, -1, nil)
                sqlite3_bind_double(upsertStmt, 2, now)
                sqlite3_step(upsertStmt)
            }
            sqlite3_finalize(upsertStmt)

            DispatchQueue.main.async {
                self.updatePageCount()
            }
        }
    }

    // MARK: - Searching

    /// Resultado de búsqueda full-text con snippet de contexto
    struct SearchResult: Identifiable {
        let id = UUID()
        let url: String
        let title: String
        let snippet: String
        let visitDate: Date
    }

    /// Busca en el contenido indexado de todas las páginas
    func search(query: String, limit: Int = 20) -> [SearchResult] {
        guard let db = db, !query.isEmpty else { return [] }

        var results: [SearchResult] = []

        // FTS5 query con snippets
        let searchSQL = """
            SELECT url, title, snippet(page_content, 2, '<b>', '</b>', '...', 40), visit_date
            FROM page_content
            WHERE page_content MATCH ?
            ORDER BY rank
            LIMIT ?;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, searchSQL, -1, &stmt, nil) == SQLITE_OK else { return results }

        // Escapar query para FTS5 (añadir * para prefix matching)
        let ftsQuery = query.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .map { "\"\($0)\"*" }
            .joined(separator: " ")

        sqlite3_bind_text(stmt, 1, (ftsQuery as NSString).utf8String, -1, nil)
        sqlite3_bind_int(stmt, 2, Int32(limit))

        while sqlite3_step(stmt) == SQLITE_ROW {
            let url = String(cString: sqlite3_column_text(stmt, 0))
            let title = String(cString: sqlite3_column_text(stmt, 1))
            let snippet = String(cString: sqlite3_column_text(stmt, 2))
            let dateStr = String(cString: sqlite3_column_text(stmt, 3))
            let date = Date(timeIntervalSince1970: Double(dateStr) ?? 0)

            // Limpiar tags HTML del snippet para SwiftUI
            let cleanSnippet = snippet
                .replacingOccurrences(of: "<b>", with: "")
                .replacingOccurrences(of: "</b>", with: "")

            results.append(SearchResult(url: url, title: title, snippet: cleanSnippet, visitDate: date))
        }
        sqlite3_finalize(stmt)

        return results
    }

    // MARK: - Maintenance

    /// Elimina entradas más antiguas que N días
    func pruneOldEntries(olderThanDays: Int = 90) {
        indexQueue.async { [weak self] in
            guard let self = self, let db = self.db else { return }
            let cutoff = Date().timeIntervalSince1970 - Double(olderThanDays * 86400)

            let deleteSQL = "DELETE FROM page_content WHERE CAST(visit_date AS REAL) < ?;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, deleteSQL, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_double(stmt, 1, cutoff)
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)

            let pruneIndexSQL = "DELETE FROM indexed_urls WHERE last_indexed < ?;"
            if sqlite3_prepare_v2(db, pruneIndexSQL, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_double(stmt, 1, cutoff)
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)

            DispatchQueue.main.async {
                self.updatePageCount()
            }
        }
    }

    /// Limpia todo el índice
    func clearIndex() {
        indexQueue.async { [weak self] in
            guard let self = self, let db = self.db else { return }
            sqlite3_exec(db, "DELETE FROM page_content;", nil, nil, nil)
            sqlite3_exec(db, "DELETE FROM indexed_urls;", nil, nil, nil)
            DispatchQueue.main.async {
                self.indexedPages = 0
            }
        }
    }

    private func updatePageCount() {
        guard let db = db else { return }
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM indexed_urls;", -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                let count = Int(sqlite3_column_int(stmt, 0))
                DispatchQueue.main.async {
                    self.indexedPages = count
                }
            }
        }
        sqlite3_finalize(stmt)
    }

    /// Tamaño del índice en disco
    var indexSizeFormatted: String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: dbPath.path),
              let size = attrs[.size] as? Int else { return "0 KB" }
        if size < 1_048_576 {
            return "\(size / 1024) KB"
        } else {
            return String(format: "%.1f MB", Double(size) / 1_048_576.0)
        }
    }
}
