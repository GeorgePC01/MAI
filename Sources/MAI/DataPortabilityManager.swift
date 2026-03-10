import Foundation
import AppKit

/// Exporta datos del navegador en formatos estándar (JSON/HTML)
class DataPortabilityManager {
    static let shared = DataPortabilityManager()
    private init() {}

    // MARK: - Export Bookmarks

    /// Exporta favoritos como JSON
    func exportBookmarksJSON() {
        let bookmarks = BookmarksManager.shared.bookmarks
        guard !bookmarks.isEmpty else {
            showAlert(title: "Sin favoritos", message: "No hay favoritos para exportar.")
            return
        }

        let panel = NSSavePanel()
        panel.title = "Exportar Favoritos"
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "mai_bookmarks_\(dateStamp()).json"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(bookmarks)
            try data.write(to: url)
            print("📤 Favoritos exportados: \(bookmarks.count) items → \(url.lastPathComponent)")
        } catch {
            showAlert(title: "Error", message: "No se pudieron exportar los favoritos: \(error.localizedDescription)")
        }
    }

    /// Exporta favoritos como HTML (compatible con Chrome/Firefox/Safari import)
    func exportBookmarksHTML() {
        let bookmarks = BookmarksManager.shared.bookmarks
        guard !bookmarks.isEmpty else {
            showAlert(title: "Sin favoritos", message: "No hay favoritos para exportar.")
            return
        }

        let panel = NSSavePanel()
        panel.title = "Exportar Favoritos (HTML)"
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = "mai_bookmarks_\(dateStamp()).html"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        var html = """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
        <TITLE>MAI Bookmarks</TITLE>
        <H1>MAI Bookmarks</H1>
        <DL><p>
            <DT><H3>Favoritos MAI</H3>
            <DL><p>
        """
        for bookmark in bookmarks {
            let title = escapeHTML(bookmark.title)
            let urlStr = escapeHTML(bookmark.url)
            html += "        <DT><A HREF=\"\(urlStr)\">\(title)</A>\n"
        }
        html += """
            </DL><p>
        </DL><p>
        """

        do {
            try html.write(to: url, atomically: true, encoding: .utf8)
            print("📤 Favoritos HTML exportados: \(bookmarks.count) items → \(url.lastPathComponent)")
        } catch {
            showAlert(title: "Error", message: "No se pudieron exportar: \(error.localizedDescription)")
        }
    }

    // MARK: - Export History

    /// Exporta historial como JSON
    func exportHistoryJSON() {
        let history = HistoryManager.shared.recentHistory
        guard !history.isEmpty else {
            showAlert(title: "Sin historial", message: "No hay historial para exportar.")
            return
        }

        let panel = NSSavePanel()
        panel.title = "Exportar Historial"
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "mai_history_\(dateStamp()).json"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(history)
            try data.write(to: url)
            print("📤 Historial exportado: \(history.count) entradas → \(url.lastPathComponent)")
        } catch {
            showAlert(title: "Error", message: "No se pudo exportar el historial: \(error.localizedDescription)")
        }
    }

    // MARK: - Export All Data

    /// Exporta todos los datos del navegador en un directorio
    func exportAllData() {
        let panel = NSSavePanel()
        panel.title = "Exportar Todos los Datos MAI"
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "mai_data_\(dateStamp()).json"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let allData: [String: Any] = [
            "exportDate": ISO8601DateFormatter().string(from: Date()),
            "browserVersion": "MAI v0.9.3",
            "bookmarksCount": BookmarksManager.shared.bookmarks.count,
            "historyCount": HistoryManager.shared.recentHistory.count,
            "workspacesCount": WorkspaceManager.shared.workspaces.count
        ]

        // Export individual files alongside the summary
        let dir = url.deletingLastPathComponent()
        let prefix = "mai_\(dateStamp())"

        // Summary JSON
        do {
            let summaryData = try JSONSerialization.data(withJSONObject: allData, options: .prettyPrinted)
            try summaryData.write(to: url)
        } catch {
            print("⚠️ Error exportando resumen: \(error)")
        }

        // Bookmarks
        if let bookmarksData = try? JSONEncoder().encode(BookmarksManager.shared.bookmarks) {
            try? bookmarksData.write(to: dir.appendingPathComponent("\(prefix)_bookmarks.json"))
        }

        // History
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let historyData = try? encoder.encode(HistoryManager.shared.recentHistory) {
            try? historyData.write(to: dir.appendingPathComponent("\(prefix)_history.json"))
        }

        // Workspaces
        if let wsData = try? JSONEncoder().encode(WorkspaceManager.shared.workspaces) {
            try? wsData.write(to: dir.appendingPathComponent("\(prefix)_workspaces.json"))
        }

        print("📤 Todos los datos exportados a: \(dir.path)")
    }

    // MARK: - Import Bookmarks

    /// Importa favoritos desde HTML (formato estándar de Chrome/Firefox/Safari)
    func importBookmarksHTML() {
        let panel = NSOpenPanel()
        panel.title = "Importar Favoritos"
        panel.allowedContentTypes = [.html]
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let html = try String(contentsOf: url, encoding: .utf8)
            let imported = parseBookmarksHTML(html)
            var addedCount = 0
            for (bookmarkURL, title) in imported {
                if !BookmarksManager.shared.bookmarks.contains(where: { $0.url == bookmarkURL }) {
                    BookmarksManager.shared.toggleBookmark(url: bookmarkURL, title: title)
                    addedCount += 1
                }
            }
            print("📥 Favoritos importados: \(addedCount) nuevos de \(imported.count) encontrados")
        } catch {
            showAlert(title: "Error", message: "No se pudo leer el archivo: \(error.localizedDescription)")
        }
    }

    /// Parsea HTML estándar de bookmarks (formato NETSCAPE-Bookmark-file-1)
    private func parseBookmarksHTML(_ html: String) -> [(url: String, title: String)] {
        var results: [(String, String)] = []
        // Regex para <A HREF="url">title</A>
        let pattern = #"<A\s+HREF="([^"]+)"[^>]*>([^<]+)</A>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return results }
        let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
        for match in matches {
            if let urlRange = Range(match.range(at: 1), in: html),
               let titleRange = Range(match.range(at: 2), in: html) {
                results.append((String(html[urlRange]), String(html[titleRange])))
            }
        }
        return results
    }

    // MARK: - Helpers

    private func dateStamp() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: Date())
    }

    private func escapeHTML(_ str: String) -> String {
        str.replacingOccurrences(of: "&", with: "&amp;")
           .replacingOccurrences(of: "<", with: "&lt;")
           .replacingOccurrences(of: ">", with: "&gt;")
           .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
