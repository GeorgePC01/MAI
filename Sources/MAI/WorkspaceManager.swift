import Foundation
import WebKit

/// Representa un workspace con contexto de navegación aislado
struct Workspace: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var colorHex: String  // Color del indicador (hex string)
    var icon: String      // SF Symbol name

    /// Colores predefinidos para workspaces
    static let defaultColors: [(name: String, hex: String)] = [
        ("Azul", "007AFF"),
        ("Verde", "34C759"),
        ("Naranja", "FF9500"),
        ("Rojo", "FF3B30"),
        ("Morado", "AF52DE"),
        ("Rosa", "FF2D55"),
        ("Cyan", "5AC8FA"),
        ("Amarillo", "FFCC00")
    ]

    /// Iconos predefinidos
    static let defaultIcons: [String] = [
        "briefcase.fill", "house.fill", "cart.fill", "book.fill",
        "gamecontroller.fill", "graduationcap.fill", "building.2.fill", "airplane",
        "heart.fill", "star.fill", "hammer.fill", "paintbrush.fill"
    ]

    static let defaultWorkspace = Workspace(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
        name: "Personal",
        colorHex: "007AFF",
        icon: "house.fill"
    )
}

/// Gestiona workspaces con contextos de navegación aislados
/// Cada workspace tiene su propio WKWebsiteDataStore (cookies, cache, localStorage separados)
class WorkspaceManager: ObservableObject {
    static let shared = WorkspaceManager()

    @Published var workspaces: [Workspace] = []
    @Published var activeWorkspaceID: UUID

    /// Data stores aislados por workspace (WKWebsiteDataStore con identificador único)
    private var dataStores: [UUID: WKWebsiteDataStore] = [:]

    private let savePath: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let maiFolder = appSupport.appendingPathComponent("MAI", isDirectory: true)
        try? FileManager.default.createDirectory(at: maiFolder, withIntermediateDirectories: true)
        self.savePath = maiFolder.appendingPathComponent("workspaces.json")

        // Cargar o crear workspace por defecto
        self.activeWorkspaceID = Workspace.defaultWorkspace.id
        loadWorkspaces()

        if workspaces.isEmpty {
            workspaces = [Workspace.defaultWorkspace]
            saveWorkspaces()
        }
    }

    // MARK: - Data Store Management

    /// Obtiene el WKWebsiteDataStore aislado para un workspace
    func dataStore(for workspaceID: UUID) -> WKWebsiteDataStore {
        // Workspace por defecto usa el data store estándar
        if workspaceID == Workspace.defaultWorkspace.id {
            return WKWebsiteDataStore.default()
        }

        // Reusar data store existente
        if let existing = dataStores[workspaceID] {
            return existing
        }

        // Crear nuevo data store aislado con identificador único (macOS 14+)
        if #available(macOS 14.0, *) {
            let store = WKWebsiteDataStore(forIdentifier: workspaceID)
            dataStores[workspaceID] = store
            return store
        } else {
            // macOS 13: sin aislamiento real, usar default (solo organización visual)
            return WKWebsiteDataStore.default()
        }
    }

    // MARK: - CRUD

    func createWorkspace(name: String, colorHex: String, icon: String) -> Workspace {
        let workspace = Workspace(id: UUID(), name: name, colorHex: colorHex, icon: icon)
        workspaces.append(workspace)
        saveWorkspaces()
        print("📂 Workspace creado: \(name)")
        return workspace
    }

    func updateWorkspace(_ workspace: Workspace) {
        if let index = workspaces.firstIndex(where: { $0.id == workspace.id }) {
            workspaces[index] = workspace
            saveWorkspaces()
        }
    }

    func deleteWorkspace(_ workspaceID: UUID) {
        // No permitir borrar el workspace por defecto
        guard workspaceID != Workspace.defaultWorkspace.id else { return }

        workspaces.removeAll { $0.id == workspaceID }

        // Limpiar data store
        if dataStores[workspaceID] != nil {
            if #available(macOS 14.0, *) {
                WKWebsiteDataStore.remove(forIdentifier: workspaceID) { error in
                    if let error = error {
                        print("⚠️ Error removing data store: \(error.localizedDescription)")
                    }
                }
            }
            dataStores.removeValue(forKey: workspaceID)
        }

        // Si era el activo, cambiar al default
        if activeWorkspaceID == workspaceID {
            activeWorkspaceID = Workspace.defaultWorkspace.id
        }

        saveWorkspaces()
        print("📂 Workspace eliminado")
    }

    func workspace(for id: UUID) -> Workspace? {
        workspaces.first(where: { $0.id == id })
    }

    var activeWorkspace: Workspace {
        workspace(for: activeWorkspaceID) ?? Workspace.defaultWorkspace
    }

    // MARK: - Persistence

    private func saveWorkspaces() {
        do {
            let data = try JSONEncoder().encode(workspaces)
            try data.write(to: savePath)
        } catch {
            print("⚠️ Error saving workspaces: \(error.localizedDescription)")
        }
    }

    private func loadWorkspaces() {
        guard FileManager.default.fileExists(atPath: savePath.path) else { return }
        do {
            let data = try Data(contentsOf: savePath)
            workspaces = try JSONDecoder().decode([Workspace].self, from: data)
        } catch {
            print("⚠️ Error loading workspaces: \(error.localizedDescription)")
        }
    }
}
