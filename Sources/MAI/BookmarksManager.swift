import Foundation

/// Favorito guardado
struct Bookmark: Codable, Identifiable, Equatable {
    let id: UUID
    var url: String
    var title: String
    var folder: String?
    let dateAdded: Date

    init(url: String, title: String, folder: String? = nil) {
        self.id = UUID()
        self.url = url
        self.title = title.isEmpty ? url : title
        self.folder = folder
        self.dateAdded = Date()
    }

    static func == (lhs: Bookmark, rhs: Bookmark) -> Bool {
        lhs.id == rhs.id
    }
}

/// Gestor de favoritos - persistencia en JSON local
class BookmarksManager: ObservableObject {
    static let shared = BookmarksManager()

    @Published private(set) var bookmarks: [Bookmark] = []
    @Published private(set) var folders: [String] = []

    private let fileURL: URL

    private init() {
        // Guardar en Application Support/MAI/
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let maiFolder = appSupport.appendingPathComponent("MAI", isDirectory: true)

        // Crear directorio si no existe
        try? FileManager.default.createDirectory(at: maiFolder, withIntermediateDirectories: true)

        self.fileURL = maiFolder.appendingPathComponent("bookmarks.json")

        loadBookmarks()
    }

    // MARK: - Public Methods

    /// Verifica si una URL está en favoritos
    func isBookmarked(url: String) -> Bool {
        bookmarks.contains { $0.url == url }
    }

    /// Obtiene el favorito para una URL
    func bookmark(for url: String) -> Bookmark? {
        bookmarks.first { $0.url == url }
    }

    /// Agrega un favorito
    func addBookmark(url: String, title: String, folder: String? = nil) {
        // Evitar duplicados
        guard !isBookmarked(url: url) else { return }

        let bookmark = Bookmark(url: url, title: title, folder: folder)
        bookmarks.insert(bookmark, at: 0)

        // Agregar carpeta si es nueva
        if let folder = folder, !folders.contains(folder) {
            folders.append(folder)
        }

        saveBookmarks()
    }

    /// Elimina un favorito por URL
    func removeBookmark(url: String) {
        bookmarks.removeAll { $0.url == url }
        saveBookmarks()
    }

    /// Elimina un favorito por ID
    func removeBookmark(_ bookmark: Bookmark) {
        bookmarks.removeAll { $0.id == bookmark.id }
        saveBookmarks()
    }

    /// Toggle: agrega o quita de favoritos
    func toggleBookmark(url: String, title: String) {
        if isBookmarked(url: url) {
            removeBookmark(url: url)
        } else {
            addBookmark(url: url, title: title)
        }
    }

    /// Mueve un favorito a otra carpeta
    func moveBookmark(_ bookmark: Bookmark, to folder: String?) {
        guard let index = bookmarks.firstIndex(of: bookmark) else { return }
        bookmarks[index].folder = folder

        if let folder = folder, !folders.contains(folder) {
            folders.append(folder)
        }

        saveBookmarks()
    }

    /// Crea una nueva carpeta
    func createFolder(_ name: String) {
        guard !folders.contains(name) else { return }
        folders.append(name)
        saveBookmarks()
    }

    /// Elimina una carpeta (mueve favoritos a raíz)
    func deleteFolder(_ name: String) {
        folders.removeAll { $0 == name }
        for i in bookmarks.indices where bookmarks[i].folder == name {
            bookmarks[i].folder = nil
        }
        saveBookmarks()
    }

    /// Favoritos sin carpeta
    func bookmarksInRoot() -> [Bookmark] {
        bookmarks.filter { $0.folder == nil }
    }

    /// Favoritos en una carpeta
    func bookmarks(in folder: String) -> [Bookmark] {
        bookmarks.filter { $0.folder == folder }
    }

    /// Busca en favoritos
    func search(query: String) -> [Bookmark] {
        guard !query.isEmpty else { return bookmarks }
        let lowercaseQuery = query.lowercased()
        return bookmarks.filter {
            $0.title.lowercased().contains(lowercaseQuery) ||
            $0.url.lowercased().contains(lowercaseQuery)
        }
    }

    // MARK: - Private Methods

    private func loadBookmarks() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            // Crear favoritos por defecto
            createDefaultBookmarks()
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode(BookmarksData.self, from: data)
            self.bookmarks = decoded.bookmarks
            self.folders = decoded.folders
        } catch {
            print("Error loading bookmarks: \(error)")
            createDefaultBookmarks()
        }
    }

    private func saveBookmarks() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }
            do {
                let data = BookmarksData(bookmarks: self.bookmarks, folders: self.folders)
                let encoded = try JSONEncoder().encode(data)
                try encoded.write(to: self.fileURL, options: .atomic)
            } catch {
                print("Error saving bookmarks: \(error)")
            }
        }
    }

    private func createDefaultBookmarks() {
        // Favoritos por defecto para nuevos usuarios
        bookmarks = [
            Bookmark(url: "https://www.google.com", title: "Google"),
            Bookmark(url: "https://www.github.com", title: "GitHub"),
            Bookmark(url: "https://www.youtube.com", title: "YouTube")
        ]
        saveBookmarks()
    }
}

/// Estructura para serializar bookmarks y folders juntos
private struct BookmarksData: Codable {
    let bookmarks: [Bookmark]
    let folders: [String]
}
