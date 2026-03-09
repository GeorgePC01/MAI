import SwiftUI
import CEFWrapper

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

    func openNewWindow(url: String? = nil, isIncognito: Bool = false) {
        let browserState = BrowserState(isIncognito: isIncognito)
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
        window.title = isIncognito ? "MAI Browser — Incógnito" : "MAI Browser"
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

        // Activar la aplicación
        NSApp.activate(ignoringOtherApps: true)

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
