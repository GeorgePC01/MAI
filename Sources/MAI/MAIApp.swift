import SwiftUI

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
                    // TODO: Implementar nueva ventana
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

        // Configurar apariencia
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)

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
