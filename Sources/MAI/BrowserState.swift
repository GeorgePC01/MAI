import SwiftUI
import WebKit
import Combine

/// Estado global del navegador
class BrowserState: ObservableObject {
    // MARK: - Published Properties

    @Published var tabs: [Tab] = []
    @Published var currentTabIndex: Int = 0
    @Published var showSidebar: Bool = false
    @Published var sidebarSection: SidebarTab = .bookmarks
    @Published var showFindInPage: Bool = false
    @Published var isLoading: Bool = false
    @Published var loadingProgress: Double = 0

    enum SidebarTab: String, CaseIterable {
        case bookmarks = "Favoritos"
        case history = "Historial"
        case downloads = "Descargas"
    }

    func showHistory() {
        sidebarSection = .history
        showSidebar = true
    }

    func showDownloads() {
        sidebarSection = .downloads
        showSidebar = true
    }

    func showBookmarks() {
        sidebarSection = .bookmarks
        showSidebar = true
    }

    // MARK: - Computed Properties

    var currentTab: Tab? {
        guard tabs.indices.contains(currentTabIndex) else { return nil }
        return tabs[currentTabIndex]
    }

    var currentURL: String {
        currentTab?.url ?? ""
    }

    var currentTitle: String {
        currentTab?.title ?? "Nueva Pestaña"
    }

    // MARK: - Statistics

    @Published var memoryUsage: Double = 0
    @Published var cpuUsage: Double = 0

    private var statsTimer: Timer?

    // MARK: - Initialization

    init() {
        // Crear pestaña inicial
        createTab(url: "about:blank")

        // Iniciar monitoreo de stats
        startStatsMonitoring()
    }

    deinit {
        statsTimer?.invalidate()
    }

    // MARK: - Tab Management

    func createTab(url: String = "about:blank") {
        let tab = Tab(url: url)
        tabs.append(tab)
        currentTabIndex = tabs.count - 1
    }

    func closeTab(at index: Int) {
        guard tabs.count > 1 else { return }  // Mantener al menos 1 tab
        tabs.remove(at: index)

        if currentTabIndex >= tabs.count {
            currentTabIndex = tabs.count - 1
        }
    }

    func closeCurrentTab() {
        closeTab(at: currentTabIndex)
    }

    func selectTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        currentTabIndex = index
    }

    func moveTab(from source: IndexSet, to destination: Int) {
        tabs.move(fromOffsets: source, toOffset: destination)
    }

    // MARK: - Navigation

    func navigate(to urlString: String) {
        guard let tab = currentTab else { return }

        var finalURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)

        // Auto-completar protocolo
        if !finalURL.hasPrefix("http://") && !finalURL.hasPrefix("https://") {
            // Si parece un dominio, agregar https
            if finalURL.contains(".") && !finalURL.contains(" ") {
                finalURL = "https://" + finalURL
            } else {
                // Si no, buscar en Google
                let query = finalURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? finalURL
                finalURL = "https://www.google.com/search?q=\(query)"
            }
        }

        tab.navigate(to: finalURL)
    }

    func goBack() {
        currentTab?.webView?.goBack()
    }

    func goForward() {
        currentTab?.webView?.goForward()
    }

    func reload() {
        currentTab?.webView?.reload()
    }

    func stopLoading() {
        currentTab?.webView?.stopLoading()
    }

    func goHome() {
        navigate(to: "https://www.google.com")
    }

    // MARK: - Zoom

    func zoomIn() {
        currentTab?.zoomLevel = min((currentTab?.zoomLevel ?? 1.0) + 0.1, 3.0)
        applyZoom()
    }

    func zoomOut() {
        currentTab?.zoomLevel = max((currentTab?.zoomLevel ?? 1.0) - 0.1, 0.5)
        applyZoom()
    }

    func resetZoom() {
        currentTab?.zoomLevel = 1.0
        applyZoom()
    }

    private func applyZoom() {
        guard let webView = currentTab?.webView,
              let zoomLevel = currentTab?.zoomLevel else { return }
        webView.pageZoom = zoomLevel
    }

    // MARK: - Stats Monitoring

    private func startStatsMonitoring() {
        statsTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updateStats()
        }
    }

    private func updateStats() {
        // Obtener uso de memoria del proceso
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        if result == KERN_SUCCESS {
            memoryUsage = Double(info.resident_size) / 1024 / 1024  // MB
        }

        // CPU usage aproximado
        cpuUsage = Double.random(in: 0.5...2.0)  // TODO: Implementar real
    }
}

/// Representa una pestaña del navegador
class Tab: ObservableObject, Identifiable {
    let id = UUID()
    @Published var url: String
    @Published var title: String = "Nueva Pestaña"
    @Published var favicon: NSImage?
    @Published var isLoading: Bool = false
    @Published var loadProgress: Double = 0
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    @Published var zoomLevel: Double = 1.0

    weak var webView: WKWebView?

    init(url: String = "about:blank") {
        self.url = url
    }

    func navigate(to urlString: String) {
        self.url = urlString
        guard let url = URL(string: urlString) else { return }
        webView?.load(URLRequest(url: url))
    }

    func updateFromWebView(_ webView: WKWebView) {
        self.url = webView.url?.absoluteString ?? ""
        self.title = webView.title ?? "Sin título"
        self.canGoBack = webView.canGoBack
        self.canGoForward = webView.canGoForward
        self.isLoading = webView.isLoading
        self.loadProgress = webView.estimatedProgress
    }
}
