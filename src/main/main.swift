import Foundation

/// Punto de entrada del navegador MAI
@main
struct MAIApp {
    static func main() {
        printBanner()

        // Inicializar motor del navegador
        let engine = BrowserEngine.shared

        // Iniciar navegador
        engine.start()

        // Crear tab de prueba
        let tab = engine.createTab(url: URL(string: "https://www.google.com")!)
        print("📑 Tab creado: \(tab.id)")

        // Mostrar estadísticas
        let stats = engine.getStats()
        print("\n📊 Estadísticas iniciales:")
        print("   RAM: \(String(format: "%.1f", stats.memoryMB)) MB")
        print("   CPU: \(String(format: "%.1f", stats.cpuUsage))%")
        print("   Tabs: \(stats.tabCount)")
        print("   Módulos: \(stats.moduleCount)")

        print("\n✨ MAI Browser listo para desarrollar")
        print("   → Presiona Ctrl+C para salir\n")

        // Keep alive
        dispatchMain()
    }

    static func printBanner() {
        print("""

        ███╗   ███╗ █████╗ ██╗
        ████╗ ████║██╔══██╗██║
        ██╔████╔██║███████║██║
        ██║╚██╔╝██║██╔══██║██║
        ██║ ╚═╝ ██║██║  ██║██║
        ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝

        Modern AI-Powered Internet Browser
        Version 0.1.0-alpha
        Built with ❤️ for efficiency

        """)
    }
}
