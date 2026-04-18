import SwiftUI
import CEFWrapper
import ObjectiveC

extension Notification.Name {
    static let maiCreateWorkspace = Notification.Name("maiCreateWorkspace")
}

// MARK: - CEF + macOS 26 Compatibility Fix
//
// ROOT CAUSE: CEF 145 (Chromium) internally calls -[NSApplication isHandlingSendEvent]
// during cef_do_message_loop_work(). In standard AppKit, NSApplication implements this.
// But SwiftUI uses SwiftUI.AppKitApplication (a subclass) which does NOT implement it.
// On macOS 26.3.1, this causes NSInvalidArgumentException → SIGTRAP → crash.
//
// FIX: Dynamically add -isHandlingSendEvent to SwiftUI.AppKitApplication at runtime.
// The method returns NO (we're not in a sendEvent: call from CEF's perspective).

func installCEFCompatibilityFix() {
    guard let app = NSApp else { return }

    let actualClass: AnyClass = type(of: app)
    let selector = NSSelectorFromString("isHandlingSendEvent")

    // Check if the method already exists
    if class_getInstanceMethod(actualClass, selector) != nil {
        NSLog("[CEF] isHandlingSendEvent already exists on %@", NSStringFromClass(actualClass))
        return
    }

    // Add -isHandlingSendEvent → returns NO (BOOL/ObjCBool)
    // Method signature: "c@:" = returns char (BOOL), takes self + _cmd
    let imp = imp_implementationWithBlock({ (_: AnyObject) -> ObjCBool in
        return ObjCBool(false)
    } as @convention(block) (AnyObject) -> ObjCBool)

    let typeEncoding = "c@:" // BOOL return, id self, SEL _cmd
    let added = class_addMethod(actualClass, selector, imp, typeEncoding)
    if added {
        NSLog("[CEF] ✅ Added isHandlingSendEvent to %@ — CEF compatibility fix applied",
              NSStringFromClass(actualClass))
    } else {
        NSLog("[CEF] ⚠️ Failed to add isHandlingSendEvent to %@", NSStringFromClass(actualClass))
    }
}

/// Gestor de ventanas adicionales del navegador
class WindowManager {
    static let shared = WindowManager()
    var windows: [(window: NSWindow, state: BrowserState)] = []

    /// Registra la ventana principal (llamado desde BrowserView.onAppear)
    func registerMainWindow(state: BrowserState) {
        guard let window = NSApp.windows.first(where: { w in
            !(w is NSPanel) && !windows.contains(where: { $0.window === w })
        }) else { return }
        if !windows.contains(where: { $0.state === state }) {
            windows.append((window: window, state: state))
        }
    }

    /// Resuelve el BrowserState asociado a una NSWindow específica
    func browserState(for window: NSWindow) -> BrowserState? {
        return windows.first(where: { $0.window === window })?.state
    }

    /// BrowserState de la ventana con foco (fallback al primero registrado)
    func focusedBrowserState() -> BrowserState? {
        if let key = NSApp.keyWindow, let state = browserState(for: key) {
            return state
        }
        if let main = NSApp.mainWindow, let state = browserState(for: main) {
            return state
        }
        return windows.first?.state
    }

    /// Busca el BrowserState de otra ventana cuyo tab bar contiene el punto en pantalla
    func browserState(at screenPoint: NSPoint, excluding: BrowserState) -> BrowserState? {
        for entry in windows {
            guard entry.state !== excluding, entry.window.isVisible else { continue }
            let windowFrame = entry.window.frame
            // Zona del tab bar: los 50px superiores de la ventana (margen generoso)
            let tabBarRect = NSRect(x: windowFrame.minX, y: windowFrame.maxY - 50, width: windowFrame.width, height: 50)
            if tabBarRect.contains(screenPoint) {
                return entry.state
            }
        }
        return nil
    }

    /// Incorpora una tab a un BrowserState existente (merge), cerrando la ventana origen si queda vacía
    func mergeTab(_ tab: Tab, into targetState: BrowserState, from sourceState: BrowserState) {
        // Retener webView
        tab.retainedWebView = tab.webView

        // Remover de origen
        if let index = sourceState.tabs.firstIndex(where: { $0.id == tab.id }) {
            sourceState.tabs.remove(at: index)
            sourceState.currentTabIndex = min(sourceState.currentTabIndex, max(sourceState.tabs.count - 1, 0))
        }

        // Agregar al destino
        targetState.tabs.append(tab)
        targetState.currentTabIndex = targetState.tabs.count - 1

        // Si la ventana origen quedó sin tabs, cerrarla
        if sourceState.tabs.isEmpty {
            if let entry = windows.first(where: { $0.state === sourceState }) {
                entry.window.close()
            }
        }

        print("🔗 Tab merged into window (\(targetState.tabs.count) tabs)")
    }

    /// Separa una tab existente en una nueva ventana (tear off)
    func openNewWindow(withTab tab: Tab, from sourceBrowserState: BrowserState, at screenPoint: NSPoint? = nil) {
        guard sourceBrowserState.tabs.count > 1 else { return } // No separar si es la única tab

        // Retener webView antes de remover la tab (evita que weak ref se pierda)
        tab.retainedWebView = tab.webView

        // Remover tab del estado original
        if let index = sourceBrowserState.tabs.firstIndex(where: { $0.id == tab.id }) {
            sourceBrowserState.tabs.remove(at: index)
            sourceBrowserState.currentTabIndex = min(sourceBrowserState.currentTabIndex, sourceBrowserState.tabs.count - 1)
        }

        // Crear nueva ventana con la tab (webView se transfiere sin recargar)
        let newBrowserState = BrowserState(isIncognito: tab.isIncognito)
        newBrowserState.tabs = [tab]
        newBrowserState.currentTabIndex = 0

        let contentView = BrowserView()
            .environmentObject(newBrowserState)
            .frame(minWidth: 800, minHeight: 600)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentView = NSHostingView(rootView: contentView)
        window.title = tab.isIncognito ? "MAI Browser — Incógnito" : "MAI Browser"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        if tab.isIncognito {
            window.backgroundColor = NSColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1.0)
        }

        // Posicionar donde el usuario soltó la tab
        if let point = screenPoint {
            window.setFrameOrigin(NSPoint(x: point.x - 600, y: point.y - 400))
        } else {
            window.center()
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        windows.append((window: window, state: newBrowserState))

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] notification in
            if let closedWindow = notification.object as? NSWindow {
                closedWindow.contentView = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self?.windows.removeAll { $0.window === closedWindow }
                }
            }
        }

        print("🪟 Tab separada en nueva ventana (\(windows.count + 1) ventanas activas)")
    }

    func openNewWindow(url: String? = nil, isIncognito: Bool = false, workspaceID: UUID? = nil) {
        let browserState = BrowserState(isIncognito: isIncognito, workspaceID: workspaceID)
        if let url = url {
            browserState.navigate(to: url)
        }
        let contentView = BrowserView()
            .environmentObject(browserState)
            .frame(minWidth: 800, minHeight: 600)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentView = NSHostingView(rootView: contentView)
        let wsName = workspaceID.flatMap({ WorkspaceManager.shared.workspace(for: $0)?.name })
        if isIncognito {
            window.title = "MAI Browser — Incógnito"
        } else if let name = wsName, workspaceID != Workspace.defaultWorkspace.id {
            window.title = "MAI Browser — \(name)"
        } else {
            window.title = "MAI Browser"
        }
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        // Prevenir crash en _NSWindowTransformAnimation dealloc:
        // NSWindow por defecto se auto-libera al cerrar, causando use-after-free
        // en animaciones internas de AppKit (CoreAnimation transactions)
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        if isIncognito {
            window.backgroundColor = NSColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1.0)
        }
        window.center()

        // Offset ligeramente de la ventana actual
        if let keyWindow = NSApp.keyWindow {
            let offset: CGFloat = 30
            window.setFrameOrigin(NSPoint(
                x: keyWindow.frame.origin.x + offset,
                y: keyWindow.frame.origin.y - offset
            ))
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        windows.append((window: window, state: browserState))

        // Limpiar referencia cuando se cierre la ventana
        // Delay de 1s para que CoreAnimation termine todas las transacciones pendientes
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] notification in
            if let closedWindow = notification.object as? NSWindow {
                // Limpiar contenido inmediatamente para evitar referencias colgantes
                closedWindow.contentView = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self?.windows.removeAll { $0.window === closedWindow }
                }
            }
        }

        let modeLabel = isIncognito ? "incógnito" : "normal"
        print("🪟 Nueva ventana \(modeLabel) abierta (\(windows.count + 1) ventanas activas)")
    }

    var windowCount: Int {
        windows.count
    }
}

/// Aplicación principal MAI Browser
@main
struct MAIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var browserState = BrowserState()

    var body: some Scene {
        WindowGroup {
            BrowserView()
                .environmentObject(browserState)
                .frame(minWidth: 800, minHeight: 600)
                .onAppear {
                    // Registrar estado principal para guardado de sesión
                    SessionManager.shared.mainBrowserState = browserState
                    SessionManager.shared.startAutoSave(mainState: browserState)
                    // Si hay sesión guardada, mostrar banner (no restaurar automáticamente)
                    if SessionManager.shared.restoreSessionOnLaunch && SessionManager.shared.hasSavedSession {
                        browserState.showSessionRestore = true
                    }
                }
        }
        .windowStyle(.automatic)
        .commands {
            // Comandos de menú personalizados
            CommandGroup(replacing: .newItem) {
                Button("Nueva Pestaña") {
                    browserState.createTab()
                }
                .keyboardShortcut("t", modifiers: .command)

                Button("Nueva Ventana") {
                    WindowManager.shared.openNewWindow()
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("Nueva Ventana Incógnito") {
                    WindowManager.shared.openNewWindow(isIncognito: true)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Divider()

                Button("Cerrar Pestaña") {
                    browserState.closeCurrentTab()
                }
                .keyboardShortcut("w", modifiers: .command)
            }

            CommandGroup(after: .textEditing) {
                Button("Buscar en Página") {
                    browserState.showFindInPage = true
                }
                .keyboardShortcut("f", modifiers: .command)
            }

            CommandMenu("Navegación") {
                Button("Atrás") {
                    browserState.goBack()
                }
                .keyboardShortcut("[", modifiers: .command)

                Button("Adelante") {
                    browserState.goForward()
                }
                .keyboardShortcut("]", modifiers: .command)

                Button("Recargar") {
                    browserState.reload()
                }
                .keyboardShortcut("r", modifiers: .command)

                Divider()

                Button("Página de Inicio") {
                    browserState.goHome()
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])

                Divider()

                // Ahorro de RAM — menú global
                Menu("Ahorro de RAM") {
                    ForEach(RAMSaverLevel.allCases, id: \.self) { level in
                        Button(action: {
                            RAMSaverManager.shared.globalLevel = level
                            // Aplicar a todas las tabs abiertas que no tengan nivel propio
                            for tab in browserState.tabs {
                                if tab.ramSaverLevel == nil, let webView = tab.webView {
                                    if level == .off {
                                        RAMSaverManager.shared.removeRuleLists(from: webView)
                                        browserState.reloadTab(tab)
                                    } else {
                                        RAMSaverManager.shared.apply(to: webView, tabId: tab.id)
                                    }
                                }
                            }
                        }) {
                            HStack {
                                Image(systemName: level.icon)
                                Text(level.rawValue)
                                if RAMSaverManager.shared.globalLevel == level {
                                    Text("✓")
                                }
                            }
                        }
                    }

                    if let warning = RAMSaverManager.shared.globalLevel.compatibilityWarning {
                        Divider()
                        Text(warning).font(.caption)
                    }
                }
            }

            CommandMenu("Ver") {
                Button("Zoom In") {
                    browserState.zoomIn()
                }
                .keyboardShortcut("+", modifiers: .command)

                Button("Zoom Out") {
                    browserState.zoomOut()
                }
                .keyboardShortcut("-", modifiers: .command)

                Button("Tamaño Real") {
                    browserState.resetZoom()
                }
                .keyboardShortcut("0", modifiers: .command)

                Divider()

                Toggle("Barra Lateral", isOn: $browserState.showSidebar)
                    .keyboardShortcut("s", modifiers: [.command, .shift])

                Divider()

                Button("Historial") {
                    browserState.showHistory()
                }
                .keyboardShortcut("y", modifiers: .command)

                Button("Descargas") {
                    browserState.showDownloads()
                }
                .keyboardShortcut("j", modifiers: .command)

                Button("Favoritos") {
                    browserState.showBookmarks()
                }
                .keyboardShortcut("b", modifiers: .command)

                Divider()

                Button("Agregar a Favoritos") {
                    if let tab = browserState.currentTab,
                       !tab.url.isEmpty,
                       tab.url != "about:blank" {
                        BookmarksManager.shared.toggleBookmark(url: tab.url, title: tab.title)
                    }
                }
                .keyboardShortcut("d", modifiers: .command)

                Divider()

                Button("Traducir Página") {
                    let translation = TranslationManager.shared
                    if translation.showTranslationBanner {
                        // Si ya hay banner, simular click en traducir
                        // El banner se encarga de buscar el webView
                    } else {
                        // Mostrar banner forzando detección
                        translation.showTranslationBanner = true
                        if translation.detectedLanguage.isEmpty {
                            translation.detectedLanguage = "auto"
                        }
                    }
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            }

            CommandMenu("Perfiles") {
                // Lista de workspaces/perfiles disponibles
                let wsManager = WorkspaceManager.shared
                ForEach(wsManager.workspaces) { workspace in
                    Button(action: {
                        if workspace.id != browserState.workspaceID {
                            WindowManager.shared.openNewWindow(workspaceID: workspace.id)
                        }
                    }) {
                        let isActive = workspace.id == browserState.workspaceID
                        Label(workspace.name + (isActive ? " ✓" : ""),
                              systemImage: workspace.icon)
                    }
                }

                Divider()

                Button("Nuevo Perfil...") {
                    NotificationCenter.default.post(name: .maiCreateWorkspace, object: nil)
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])

                Divider()

                Button("Configuración...") {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            CommandMenu("Desarrollo") {
                Button("DevTools") {
                    let state = WindowManager.shared.focusedBrowserState() ?? browserState
                    state.showDevTools.toggle()
                }
                .keyboardShortcut("i", modifiers: [.command, .option])

                Button("Consola JavaScript") {
                    let state = WindowManager.shared.focusedBrowserState() ?? browserState
                    DevToolsState.shared.selectedTab = .console
                    state.showDevTools = true
                }
                .keyboardShortcut("j", modifiers: [.command, .option])

                Button("Inspeccionar Elementos") {
                    let state = WindowManager.shared.focusedBrowserState() ?? browserState
                    DevToolsState.shared.selectedTab = .elements
                    state.showDevTools = true
                }

                Button("Monitor de Red") {
                    let state = WindowManager.shared.focusedBrowserState() ?? browserState
                    DevToolsState.shared.selectedTab = .network
                    state.showDevTools = true
                }

                Divider()

                Button("CSS Debug") {
                    let state = WindowManager.shared.focusedBrowserState() ?? browserState
                    DevToolsState.shared.selectedTab = .cssDebug
                    state.showDevTools = true
                }

                Button("Vista 3D del DOM") {
                    let state = WindowManager.shared.focusedBrowserState() ?? browserState
                    DevToolsState.shared.selectedTab = .dom3d
                    state.showDevTools = true
                }

                Button("Auditoría de Accesibilidad") {
                    let state = WindowManager.shared.focusedBrowserState() ?? browserState
                    DevToolsState.shared.selectedTab = .accessibility
                    state.showDevTools = true
                }

                Divider()

                Button("Ver Código Fuente") {
                    let state = WindowManager.shared.focusedBrowserState() ?? browserState
                    DevToolsState.shared.selectedTab = .sources
                    state.showDevTools = true
                }
                .keyboardShortcut("u", modifiers: [.command, .option])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(browserState)
        }
    }
}

/// App Delegate para configuración adicional
class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationWillFinishLaunching(_ notification: Notification) {
        // CRÍTICO: Establecer política de activación ANTES de que termine el lanzamiento
        // Esto permite que la app tome el foco incluso sin bundle
        NSApp.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("MAI Browser iniciado")

        // Add missing isHandlingSendEvent method to SwiftUI.AppKitApplication.
        // CEF 145 calls this on NSApp during message pump, but SwiftUI's subclass
        // doesn't implement it → crash on macOS 26.3.1. This adds it dynamically.
        installCEFCompatibilityFix()

        // Activar la aplicación
        NSApp.activate(ignoringOtherApps: true)

        // Doble click en titlebar para maximizar/restaurar ventana
        // SwiftUI con fullSizeContentView impide que el titlebar reciba el doble click nativo
        NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { event in
            if event.clickCount == 2, let window = event.window {
                // Zona del titlebar: los 38px superiores (altura de la tab bar)
                let locationInWindow = event.locationInWindow
                let titlebarHeight: CGFloat = 38
                if locationInWindow.y >= window.frame.height - titlebarHeight {
                    // Respetar preferencia del sistema: zoom o minimize
                    let action = UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") ?? "Maximize"
                    if action == "Minimize" {
                        window.miniaturize(nil)
                    } else {
                        window.zoom(nil)
                    }
                }
            }
            return event
        }

        // Limpiar snapshots huérfanos de sesión anterior
        let snapshotsDir = Tab.snapshotsDirectory
        if FileManager.default.fileExists(atPath: snapshotsDir.path) {
            try? FileManager.default.removeItem(at: snapshotsDir)
            print("🧹 Snapshots huérfanos limpiados")
        }

        // Load EasyList filter lists in background
        if PrivacyManager.shared.useEasyList {
            Task {
                await EasyListManager.shared.loadFilterLists()
            }
        }

        // Pre-compile YouTube ad block rules
        if YouTubeAdBlockManager.shared.blockYouTubeAds {
            Task {
                await YouTubeAdBlockManager.shared.compileNetworkRules()
            }
        }

        // Pre-compile cookie banner CSS hiding rules
        if CookieBannerManager.shared.autoDismissCookieBanners {
            CookieBannerManager.shared.compileRules()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Guardar sesión antes de cerrar
        if let mainState = SessionManager.shared.mainBrowserState {
            SessionManager.shared.saveOnTerminate(mainState: mainState)
            print("💾 Sesión guardada antes de cerrar")
        }
        // Shutdown CEF if it was initialized
        if CEFBridge.isInitialized {
            CEFBridge.shutdownCEF()
        }
        print("MAI Browser terminando...")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // SwiftUI ya maneja el foco de ventanas automáticamente
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()

        let newWindowItem = NSMenuItem(title: "Nueva Ventana", action: #selector(dockNewWindow), keyEquivalent: "")
        newWindowItem.target = self
        menu.addItem(newWindowItem)

        let incognitoItem = NSMenuItem(title: "Nueva Ventana Incógnito", action: #selector(dockNewIncognitoWindow), keyEquivalent: "")
        incognitoItem.target = self
        menu.addItem(incognitoItem)

        return menu
    }

    @objc private func dockNewWindow() {
        WindowManager.shared.openNewWindow()
    }

    @objc private func dockNewIncognitoWindow() {
        WindowManager.shared.openNewWindow(isIncognito: true)
    }
}
