import SwiftUI
import CEFWrapper

/// Gestor de ventanas adicionales del navegador
class WindowManager {
    static let shared = WindowManager()
    private var windows: [(window: NSWindow, state: BrowserState)] = []

    func openNewWindow() {
        let browserState = BrowserState()
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
        window.title = "MAI Browser"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
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
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] notification in
            if let closedWindow = notification.object as? NSWindow {
                self?.windows.removeAll { $0.window === closedWindow }
            }
        }

        print("🪟 Nueva ventana abierta (\(windows.count + 1) ventanas activas)")
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

        // Seguir el tema del sistema (claro/oscuro automático)
        // NSApplication.shared.appearance = NSAppearance(named: .darkAqua)  // Descomentar para forzar oscuro

        // Activar la aplicación
        NSApp.activate(ignoringOtherApps: true)

        // Asegurar que la ventana tome foco
        DispatchQueue.main.async {
            if let window = NSApp.windows.first {
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            }
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
        if let window = NSApplication.shared.windows.first {
            window.makeKeyAndOrderFront(nil)
        }
    }
}
