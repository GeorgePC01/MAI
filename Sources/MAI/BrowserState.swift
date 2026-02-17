import SwiftUI
import WebKit
import Combine
import CEFWrapper

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

        // If closing a Chromium tab, release CEF browser
        let closingTab = tabs[index]
        if closingTab.useChromiumEngine {
            CEFBridge.closeBrowser()
            print("🔄 CEF browser closed for tab: \(closingTab.title)")
        }

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

        // Detectar y extraer URL real de Microsoft SafeLinks
        if let extractedURL = extractSafeLinksURL(from: finalURL) {
            print("🔗 SafeLinks detectado, redirigiendo a: \(extractedURL)")
            finalURL = extractedURL
        }

        // Auto-detect video conferencing domains → use Chromium engine
        let shouldUseChromium = Self.shouldUseChromiumEngine(for: finalURL)
        if shouldUseChromium != tab.useChromiumEngine {
            tab.useChromiumEngine = shouldUseChromium
            if shouldUseChromium {
                print("🔄 Switching to Chromium engine for: \(finalURL)")
            } else {
                print("🔄 Switching back to WebKit engine")
            }
        }

        tab.navigate(to: finalURL)
    }

    /// Extrae la URL real de un enlace de Microsoft SafeLinks
    private func extractSafeLinksURL(from urlString: String) -> String? {
        // Detectar si es un SafeLinks URL
        guard urlString.contains("safelinks.protection.outlook.com") else {
            return nil
        }

        // Extraer el parámetro "url=" de la query string
        guard let url = URL(string: urlString),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems,
              let urlParam = queryItems.first(where: { $0.name == "url" })?.value else {
            return nil
        }

        // La URL viene codificada, decodificarla
        guard let decodedURL = urlParam.removingPercentEncoding else {
            return urlParam
        }

        return decodedURL
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

    // MARK: - Tab Suspension

    /// Suspende una tab para liberar memoria
    func suspendTab(_ tab: Tab) {
        guard !tab.isSuspended, let webView = tab.webView else { return }

        // 1. Capturar screenshot
        let config = WKSnapshotConfiguration()
        webView.takeSnapshot(with: config) { [weak tab] image, _ in
            DispatchQueue.main.async {
                tab?.suspendedSnapshot = image
            }
        }

        // 2. Guardar scroll position
        webView.evaluateJavaScript("JSON.stringify({x: window.scrollX, y: window.scrollY})") { [weak tab] result, _ in
            if let json = result as? String,
               let data = json.data(using: .utf8),
               let pos = try? JSONDecoder().decode([String: CGFloat].self, from: data) {
                tab?.scrollPosition = CGPoint(x: pos["x"] ?? 0, y: pos["y"] ?? 0)
            }
        }

        // 3. Marcar como suspendida (la WebView se liberará)
        tab.isSuspended = true

        print("💤 Tab suspendida: \(tab.title) - RAM liberada")
    }

    /// Restaura una tab suspendida
    func resumeTab(_ tab: Tab) {
        guard tab.isSuspended else { return }

        tab.isSuspended = false
        tab.suspendedSnapshot = nil

        // La WebView se recreará automáticamente en WebViewContainer
        // y cargará la URL guardada

        print("⏰ Tab restaurada: \(tab.title)")
    }

    /// Suspende todas las tabs excepto la actual
    func suspendInactiveTabs() {
        for tab in tabs where tab.id != currentTab?.id && !tab.isSuspended {
            suspendTab(tab)
        }
    }

    /// Cuenta tabs suspendidas
    var suspendedTabsCount: Int {
        tabs.filter { $0.isSuspended }.count
    }

    /// RAM estimada ahorrada por suspensión
    var estimatedRAMSaved: Double {
        // ~70 MB promedio por tab suspendida
        Double(suspendedTabsCount) * 70.0
    }

    // MARK: - Find in Page

    @Published var findQuery: String = ""
    @Published var findResultCount: Int = 0
    @Published var findCurrentIndex: Int = 0

    func findInPage(_ query: String) {
        findQuery = query
        guard !query.isEmpty, let webView = currentTab?.webView else {
            clearFindHighlights()
            return
        }

        // JavaScript para buscar y resaltar todas las coincidencias
        let script = """
        (function() {
            // Limpiar highlights anteriores
            const existingHighlights = document.querySelectorAll('.mai-find-highlight');
            existingHighlights.forEach(el => {
                const parent = el.parentNode;
                parent.replaceChild(document.createTextNode(el.textContent), el);
                parent.normalize();
            });

            const query = '\(query.replacingOccurrences(of: "'", with: "\\'").replacingOccurrences(of: "\\", with: "\\\\"))';
            if (!query) return JSON.stringify({count: 0, current: 0});

            const marks = [];
            const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, null, false);

            while (walker.nextNode()) {
                const node = walker.currentNode;
                const text = node.nodeValue;
                const lowerText = text.toLowerCase();
                const lowerQuery = query.toLowerCase();
                let index = lowerText.indexOf(lowerQuery);

                if (index >= 0) {
                    const span = document.createElement('span');
                    span.className = 'mai-find-highlight';
                    span.style.backgroundColor = '#ffff00';
                    span.style.color = '#000';
                    span.textContent = text.substring(index, index + query.length);

                    const before = document.createTextNode(text.substring(0, index));
                    const after = document.createTextNode(text.substring(index + query.length));

                    const parent = node.parentNode;
                    parent.insertBefore(before, node);
                    parent.insertBefore(span, node);
                    parent.insertBefore(after, node);
                    parent.removeChild(node);

                    marks.push(span);
                }
            }

            // Resaltar el primero como actual
            if (marks.length > 0) {
                marks[0].style.backgroundColor = '#ff9500';
                marks[0].scrollIntoView({behavior: 'smooth', block: 'center'});
            }

            window.maiFindMarks = marks;
            window.maiFindIndex = 0;

            return JSON.stringify({count: marks.length, current: marks.length > 0 ? 1 : 0});
        })();
        """

        webView.evaluateJavaScript(script) { [weak self] result, _ in
            if let json = result as? String,
               let data = json.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Int] {
                DispatchQueue.main.async {
                    self?.findResultCount = dict["count"] ?? 0
                    self?.findCurrentIndex = dict["current"] ?? 0
                }
            }
        }
    }

    func findNext() {
        guard !findQuery.isEmpty, let webView = currentTab?.webView else { return }

        let script = """
        (function() {
            const marks = window.maiFindMarks || [];
            if (marks.length === 0) return JSON.stringify({count: 0, current: 0});

            let index = window.maiFindIndex || 0;

            // Quitar highlight actual
            marks[index].style.backgroundColor = '#ffff00';

            // Siguiente
            index = (index + 1) % marks.length;
            window.maiFindIndex = index;

            // Resaltar nuevo
            marks[index].style.backgroundColor = '#ff9500';
            marks[index].scrollIntoView({behavior: 'smooth', block: 'center'});

            return JSON.stringify({count: marks.length, current: index + 1});
        })();
        """

        webView.evaluateJavaScript(script) { [weak self] result, _ in
            if let json = result as? String,
               let data = json.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Int] {
                DispatchQueue.main.async {
                    self?.findResultCount = dict["count"] ?? 0
                    self?.findCurrentIndex = dict["current"] ?? 0
                }
            }
        }
    }

    func findPrevious() {
        guard !findQuery.isEmpty, let webView = currentTab?.webView else { return }

        let script = """
        (function() {
            const marks = window.maiFindMarks || [];
            if (marks.length === 0) return JSON.stringify({count: 0, current: 0});

            let index = window.maiFindIndex || 0;

            // Quitar highlight actual
            marks[index].style.backgroundColor = '#ffff00';

            // Anterior
            index = (index - 1 + marks.length) % marks.length;
            window.maiFindIndex = index;

            // Resaltar nuevo
            marks[index].style.backgroundColor = '#ff9500';
            marks[index].scrollIntoView({behavior: 'smooth', block: 'center'});

            return JSON.stringify({count: marks.length, current: index + 1});
        })();
        """

        webView.evaluateJavaScript(script) { [weak self] result, _ in
            if let json = result as? String,
               let data = json.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Int] {
                DispatchQueue.main.async {
                    self?.findResultCount = dict["count"] ?? 0
                    self?.findCurrentIndex = dict["current"] ?? 0
                }
            }
        }
    }

    func clearFindHighlights() {
        guard let webView = currentTab?.webView else { return }

        let script = """
        (function() {
            const highlights = document.querySelectorAll('.mai-find-highlight');
            highlights.forEach(el => {
                const parent = el.parentNode;
                parent.replaceChild(document.createTextNode(el.textContent), el);
                parent.normalize();
            });
            window.maiFindMarks = [];
            window.maiFindIndex = 0;
        })();
        """

        webView.evaluateJavaScript(script, completionHandler: nil)
        findResultCount = 0
        findCurrentIndex = 0
        findQuery = ""
    }

    func closeFindInPage() {
        clearFindHighlights()
        showFindInPage = false
    }

    // MARK: - CEF Hybrid Engine (Video Conferencing)

    /// Dominios de videoconferencia que usan Chromium engine
    private static let videoConferenceDomains: Set<String> = [
        "meet.google.com",
        "zoom.us",
        "app.zoom.us",
        "teams.microsoft.com",
        "teams.live.com"
    ]

    /// Determina si una URL debería usar Chromium engine
    static func shouldUseChromiumEngine(for urlString: String) -> Bool {
        guard let url = URL(string: urlString),
              let host = url.host?.lowercased() else { return false }
        return videoConferenceDomains.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// Verifica si la URL actual es un sitio de videoconferencia
    var isVideoConferenceSite: Bool {
        guard let url = currentTab?.url else { return false }
        return Self.shouldUseChromiumEngine(for: url)
    }

    /// Verifica si el tab actual usa Chromium engine
    var isCurrentTabChromium: Bool {
        currentTab?.useChromiumEngine ?? false
    }

    /// Nombre del servicio de videoconferencia actual
    var videoConferenceServiceName: String {
        guard let url = currentTab?.url,
              let host = URL(string: url)?.host?.lowercased() else { return "" }
        if host.contains("meet.google") { return "Google Meet" }
        if host.contains("zoom") { return "Zoom" }
        if host.contains("teams") { return "Microsoft Teams" }
        return "Videoconferencia"
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

    // Tab Suspension
    @Published var isSuspended: Bool = false
    @Published var suspendedSnapshot: NSImage?
    @Published var lastInteraction: Date = Date()
    var scrollPosition: CGPoint = .zero

    // CEF Hybrid Engine - true when tab uses Chromium (video conferencing)
    @Published var useChromiumEngine: Bool = false

    weak var webView: WKWebView?

    init(url: String = "about:blank") {
        self.url = url
    }

    /// Registra interacción del usuario (para ML futuro)
    func recordInteraction() {
        lastInteraction = Date()
    }

    /// Tiempo desde última interacción
    var timeSinceLastInteraction: TimeInterval {
        Date().timeIntervalSince(lastInteraction)
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
