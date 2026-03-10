import Foundation

/// Datos serializables de una tab para restaurar sesión
struct SavedTab: Codable {
    let url: String
    let title: String
    let isIncognito: Bool
    let workspaceID: UUID?
    let useChromiumEngine: Bool
    let forceWebKit: Bool
}

/// Datos serializables de una ventana
struct SavedWindow: Codable {
    let tabs: [SavedTab]
    let activeTabIndex: Int
    let isIncognito: Bool
    let workspaceID: UUID?
}

/// Sesión completa del navegador
struct SavedSession: Codable {
    let mainWindow: SavedWindow
    let additionalWindows: [SavedWindow]
    let timestamp: Date
}

/// Gestiona persistencia y restauración de sesiones del navegador
class SessionManager {
    static let shared = SessionManager()

    private let savePath: URL
    private var saveTimer: Timer?

    /// Referencia al BrowserState principal (para guardar al cerrar)
    weak var mainBrowserState: BrowserState?

    /// Controla si se restaura la sesión al iniciar
    var restoreSessionOnLaunch: Bool {
        get { UserDefaults.standard.object(forKey: "restoreSession") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "restoreSession") }
    }

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let maiFolder = appSupport.appendingPathComponent("MAI", isDirectory: true)
        try? FileManager.default.createDirectory(at: maiFolder, withIntermediateDirectories: true)
        self.savePath = maiFolder.appendingPathComponent("session.json")
    }

    // MARK: - Guardar sesión

    /// Inicia guardado automático periódico (cada 30s)
    func startAutoSave(mainState: BrowserState) {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self, weak mainState] _ in
            guard let self = self, let state = mainState else { return }
            self.saveSession(mainState: state)
        }
    }

    func stopAutoSave() {
        saveTimer?.invalidate()
        saveTimer = nil
    }

    /// Guarda la sesión actual a disco
    func saveSession(mainState: BrowserState) {
        // No guardar sesiones incógnito
        let mainWindow = savedWindow(from: mainState)

        let additionalWindows: [SavedWindow] = WindowManager.shared.windows.compactMap { entry in
            // No guardar ventanas incógnito
            guard !entry.state.isIncognito else { return nil }
            return savedWindow(from: entry.state)
        }

        let session = SavedSession(
            mainWindow: mainWindow,
            additionalWindows: additionalWindows,
            timestamp: Date()
        )

        do {
            let data = try JSONEncoder().encode(session)
            try data.write(to: savePath, options: .atomic)
        } catch {
            print("⚠️ Error guardando sesión: \(error.localizedDescription)")
        }
    }

    private func savedWindow(from state: BrowserState) -> SavedWindow {
        let savedTabs = state.tabs.compactMap { tab -> SavedTab? in
            // No guardar tabs incógnito ni about:blank
            guard !tab.isIncognito else { return nil }
            let url = tab.url
            guard !url.isEmpty, url != "about:blank" else { return nil }
            return SavedTab(
                url: url,
                title: tab.title,
                isIncognito: false,
                workspaceID: state.workspaceID,
                useChromiumEngine: tab.useChromiumEngine,
                forceWebKit: tab.forceWebKit
            )
        }
        return SavedWindow(
            tabs: savedTabs,
            activeTabIndex: min(state.currentTabIndex, max(savedTabs.count - 1, 0)),
            isIncognito: state.isIncognito,
            workspaceID: state.workspaceID
        )
    }

    // MARK: - Restaurar sesión

    /// Verifica si hay una sesión guardada
    var hasSavedSession: Bool {
        guard FileManager.default.fileExists(atPath: savePath.path) else { return false }
        // Sesión válida solo si tiene menos de 7 días
        if let attrs = try? FileManager.default.attributesOfItem(atPath: savePath.path),
           let modified = attrs[.modificationDate] as? Date {
            return Date().timeIntervalSince(modified) < 7 * 24 * 3600
        }
        return true
    }

    /// Carga la sesión guardada
    func loadSession() -> SavedSession? {
        guard FileManager.default.fileExists(atPath: savePath.path) else { return nil }
        do {
            let data = try Data(contentsOf: savePath)
            return try JSONDecoder().decode(SavedSession.self, from: data)
        } catch {
            print("⚠️ Error cargando sesión: \(error.localizedDescription)")
            return nil
        }
    }

    /// Restaura la sesión en el BrowserState principal
    func restoreSession(into mainState: BrowserState) -> Bool {
        guard restoreSessionOnLaunch,
              let session = loadSession(),
              !session.mainWindow.tabs.isEmpty else { return false }

        // Restaurar ventana principal
        restoreWindow(session.mainWindow, into: mainState)

        // Restaurar ventanas adicionales
        for windowData in session.additionalWindows {
            guard !windowData.tabs.isEmpty else { continue }
            WindowManager.shared.openNewWindow(
                workspaceID: windowData.workspaceID
            )
            // La última ventana creada es la que acabamos de abrir
            if let lastEntry = WindowManager.shared.windows.last {
                restoreWindow(windowData, into: lastEntry.state)
            }
        }

        print("✅ Sesión restaurada: \(session.mainWindow.tabs.count) tabs principales, \(session.additionalWindows.count) ventanas adicionales")
        return true
    }

    private func restoreWindow(_ windowData: SavedWindow, into state: BrowserState) {
        // Remover tab vacío inicial
        if state.tabs.count == 1 && state.tabs.first?.url == "about:blank" {
            state.tabs.removeAll()
        }

        for savedTab in windowData.tabs {
            let tab = Tab(url: savedTab.url, isIncognito: false)
            tab.title = savedTab.title
            tab.forceWebKit = savedTab.forceWebKit
            state.tabs.append(tab)
        }

        if state.tabs.isEmpty {
            state.tabs.append(Tab(url: "about:blank"))
        }

        state.currentTabIndex = min(windowData.activeTabIndex, max(state.tabs.count - 1, 0))

        // Navegar cada tab a su URL
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            for tab in state.tabs where tab.url != "about:blank" {
                tab.navigate(to: tab.url)
            }
        }
    }

    /// Número total de tabs en la sesión guardada
    var savedTabCount: Int {
        guard let session = loadSession() else { return 0 }
        return session.mainWindow.tabs.count + session.additionalWindows.reduce(0) { $0 + $1.tabs.count }
    }

    /// Elimina la sesión guardada
    func clearSession() {
        try? FileManager.default.removeItem(at: savePath)
    }

    /// Guarda sesión inmediatamente antes de cerrar (llamado desde applicationWillTerminate)
    func saveOnTerminate(mainState: BrowserState) {
        stopAutoSave()
        saveSession(mainState: mainState)
    }
}
