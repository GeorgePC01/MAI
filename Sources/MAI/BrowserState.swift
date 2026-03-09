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

    // Estado de detección de phishing
    @Published var showPhishingWarning: Bool = false
    @Published var pendingPhishingURL: String = ""
    @Published var phishingThreatLevel: PhishingThreatLevel = .safe
    var phishingBypassURL: String?

    // Incognito window — all tabs inherit this mode
    let isIncognito: Bool

    // Workspace — contexto aislado de navegación (cookies, cache, localStorage)
    let workspaceID: UUID

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

    init(isIncognito: Bool = false, workspaceID: UUID? = nil) {
        self.isIncognito = isIncognito
        self.workspaceID = workspaceID ?? WorkspaceManager.shared.activeWorkspaceID
        // Crear pestaña inicial (hereda modo incógnito de la ventana)
        let tab = Tab(url: "about:blank", isIncognito: isIncognito)
        tabs.append(tab)
        currentTabIndex = 0

        // Iniciar monitoreo de stats
        startStatsMonitoring()

        // Iniciar gestor de auto-suspensión
        AutoSuspendManager.shared.start(browserState: self)
    }

    deinit {
        statsTimer?.invalidate()
    }

    // MARK: - Tab Management

    func createTab(url: String = "about:blank") {
        let tab = Tab(url: url, isIncognito: self.isIncognito)
        tabs.append(tab)
        currentTabIndex = tabs.count - 1
    }

    func closeTab(at index: Int, force: Bool = false) {
        guard force || tabs.count > 1 else { return }  // Mantener al menos 1 tab

        let closingTab = tabs[index]
        AutoSuspendManager.shared.tabClosed(closingTab)
        // Limpiar snapshot de disco
        if let path = closingTab.snapshotPath {
            try? FileManager.default.removeItem(at: path)
        }
        if closingTab.useChromiumEngine {
            // CEF browser will be closed by CEFWebView.dismantleNSView (async)
            // when SwiftUI removes the view from the hierarchy
            print("🔄 Closing CEF tab: \(closingTab.title)")
        }

        tabs.remove(at: index)

        // If all tabs closed, create a blank one
        if tabs.isEmpty {
            tabs.append(Tab(isIncognito: self.isIncognito))
            currentTabIndex = 0
        } else if currentTabIndex >= tabs.count {
            currentTabIndex = tabs.count - 1
        }
    }

    func closeCurrentTab() {
        closeTab(at: currentTabIndex)
    }

    func selectTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        currentTab?.recordInteraction() // Marca actividad en el tab que dejamos
        currentTabIndex = index
        tabs[index].recordInteraction()
        TranslationManager.shared.resetState()
    }

    func moveTab(from source: IndexSet, to destination: Int) {
        tabs.move(fromOffsets: source, toOffset: destination)
    }

    func duplicateTab(_ tab: Tab) {
        let newTab = Tab(url: tab.url, isIncognito: tab.isIncognito)
        newTab.title = tab.title
        newTab.favicon = tab.favicon
        if let index = tabs.firstIndex(where: { $0.id == tab.id }) {
            tabs.insert(newTab, at: index + 1)
            currentTabIndex = index + 1
        } else {
            tabs.append(newTab)
            currentTabIndex = tabs.count - 1
        }
    }

    func togglePinTab(_ tab: Tab) {
        tab.isPinned.toggle()
        // Mover pinned tabs al inicio
        let pinned = tabs.filter { $0.isPinned }
        let unpinned = tabs.filter { !$0.isPinned }
        tabs = pinned + unpinned
        if let newIndex = tabs.firstIndex(where: { $0.id == tab.id }) {
            currentTabIndex = newIndex
        }
    }

    func toggleMuteTab(_ tab: Tab) {
        tab.isMuted.toggle()
        applyMuteState(tab)
    }

    /// Aplica el estado de mute al webview (WebKit o CEF)
    func applyMuteState(_ tab: Tab) {
        let muteJS = "document.querySelectorAll('video, audio').forEach(el => el.muted = \(tab.isMuted));"

        if tab.useChromiumEngine {
            CEFBridge.executeJavaScript(muteJS)
        } else if let webView = tab.webView {
            webView.evaluateJavaScript(muteJS) { _, error in
                if let error = error {
                    print("⚠️ Mute failed for '\(tab.title)': \(error.localizedDescription)")
                }
            }
        } else {
            print("⚠️ Cannot mute tab '\(tab.title)': no webView available")
        }
    }

    // MARK: - Navegación Phishing

    /// Proceder a la URL marcada como phishing (usuario clickeó "Continuar de todos modos")
    func proceedToPhishingURL() {
        guard !pendingPhishingURL.isEmpty else { return }
        phishingBypassURL = pendingPhishingURL
        showPhishingWarning = false
        navigate(to: pendingPhishingURL)
        // Limpiar bypass después de un breve retraso para permitir que la navegación complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.phishingBypassURL = nil
        }
        pendingPhishingURL = ""
        phishingThreatLevel = .safe
    }

    /// Cancelar navegación a URL de phishing (usuario clickeó "Volver")
    func cancelPhishingNavigation() {
        showPhishingWarning = false
        pendingPhishingURL = ""
        phishingThreatLevel = .safe
    }

    func closeOtherTabs(except tab: Tab) {
        for t in tabs where t.id != tab.id {
            if let path = t.snapshotPath { try? FileManager.default.removeItem(at: path) }
        }
        tabs.removeAll { $0.id != tab.id }
        currentTabIndex = 0
    }

    func closeTabsToRight(of tab: Tab) {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        for t in tabs[(index + 1)...] {
            if let path = t.snapshotPath { try? FileManager.default.removeItem(at: path) }
        }
        tabs.removeSubrange((index + 1)...)
        if currentTabIndex >= tabs.count {
            currentTabIndex = tabs.count - 1
        }
    }

    func reloadTab(_ tab: Tab) {
        tab.webView?.reload()
    }

    // MARK: - Navigation

    func navigate(to urlString: String) {
        guard let tab = currentTab else { return }
        tab.recordInteraction()

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

        if tab.useChromiumEngine {
            // Tab already in Chromium — all navigation goes through CEF.
            // CEF close/release always crashes, so we never switch back to WebKit.
            print("🔄 Navigating in Chromium: \(finalURL)")
            CEFBridge.loadURL(finalURL)
            return
        }

        if shouldUseChromium && !tab.forceWebKit {
            // CEF es singleton — solo un browser Chromium a la vez.
            // Si ya hay una reunión activa, avisar al usuario en vez de reemplazar silenciosamente.
            if let existingCEFTab = tabs.first(where: { $0.useChromiumEngine }),
               let cefIndex = tabs.firstIndex(where: { $0.id == existingCEFTab.id }) {

                let existingService = Self.videoConferenceServiceName(for: existingCEFTab.url)
                let newService = Self.videoConferenceServiceName(for: finalURL)

                let alert = NSAlert()
                alert.messageText = "Reunión activa en \(existingService)"
                alert.informativeText = "¿Qué deseas hacer con la reunión de \(newService)?\n\n• Reemplazar: Cierra \(existingService) y abre \(newService) con experiencia completa.\n\n• Modo nativo: Mantiene tu reunión actual y abre \(newService). Algunas funciones avanzadas podrían tener limitaciones."
                alert.addButton(withTitle: "Reemplazar reunión")
                alert.addButton(withTitle: "Abrir en modo nativo")
                alert.addButton(withTitle: "Cancelar")
                alert.alertStyle = .informational

                let response = alert.runModal()
                if response == .alertFirstButtonReturn {
                    // Reemplazar: navegar en el tab CEF existente
                    print("🔄 Usuario reemplazó reunión: \(existingService) → \(newService)")
                    CEFBridge.loadURL(finalURL)
                    existingCEFTab.url = finalURL
                    existingCEFTab.title = "Cargando..."
                    currentTabIndex = cefIndex
                    return
                } else if response == .alertSecondButtonReturn {
                    // Abrir en WebKit: audio/video funciona, sin compartir pantalla HD
                    print("🌐 Abriendo \(newService) en modo nativo (reunión activa en \(existingService))")
                    tab.forceWebKit = true
                    tab.navigate(to: finalURL)
                    return
                } else {
                    // Cancelar
                    return
                }
            }
            // No hay reunión activa — abrir normalmente en Chromium
            tab.useChromiumEngine = true
            tab.useStandaloneChromium = false
            print("🔄 Switching to Chromium engine for: \(finalURL)")
            tab.navigate(to: finalURL)
            return
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

        // 1. Capturar screenshot → comprimir JPEG → escribir a disco
        let config = WKSnapshotConfiguration()
        let tabID = tab.id
        webView.takeSnapshot(with: config) { [weak tab] image, _ in
            guard let image = image, let tab = tab else { return }
            DispatchQueue.global(qos: .utility).async {
                let dir = Tab.snapshotsDirectory
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let filePath = dir.appendingPathComponent("\(tabID.uuidString).jpg")

                if let tiffData = image.tiffRepresentation,
                   let bitmap = NSBitmapImageRep(data: tiffData),
                   let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) {
                    try? jpegData.write(to: filePath)
                    DispatchQueue.main.async {
                        tab.snapshotPath = filePath
                    }
                }
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

        print("💤 Tab suspendida: \(tab.title) - RAM liberada (snapshot a disco)")
    }

    /// Restaura una tab suspendida
    func resumeTab(_ tab: Tab) {
        guard tab.isSuspended else { return }

        tab.isSuspended = false
        // Eliminar snapshot de disco
        if let path = tab.snapshotPath {
            try? FileManager.default.removeItem(at: path)
        }
        tab.snapshotPath = nil
        tab.recordInteraction()
        AutoSuspendManager.shared.tabResumed(tab)

        // La WebView se recreará automáticamente en WebViewContainer
        // y cargará la URL guardada.
        // El mute state se re-aplica en webView(_:didFinish:) del Coordinator.

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

    /// Cantidad de tabs auto-suspendidas por AutoSuspendManager
    var autoSuspendedCount: Int {
        AutoSuspendManager.shared.autoSuspendedCount
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

    // MARK: - Chrome Compatibility Mode

    /// Toggle Chrome compatibility mode for a tab and persist preference per domain
    func toggleChromeCompatMode(_ tab: Tab) {
        tab.chromeCompatMode.toggle()

        // Persist preference for this domain
        let domain = AutoSuspendManager.extractDomain(from: tab.url)
        if !domain.isEmpty {
            ChromeCompatManager.shared.setPreference(domain: domain, enabled: tab.chromeCompatMode)
        }

        // Reload the tab to apply new UA + scripts
        if let webView = tab.webView {
            webView.customUserAgent = tab.chromeCompatMode
                ? ChromeCompatManager.chromeUserAgent
                : ChromeCompatManager.safariUserAgent
            webView.reload()
        }
    }

    /// Check if a domain has Chrome compat mode saved
    static func shouldUseChromeCompat(for urlString: String) -> Bool {
        let domain = AutoSuspendManager.extractDomain(from: urlString)
        return ChromeCompatManager.shared.isEnabled(domain: domain)
    }

    // MARK: - CEF Hybrid Engine (Video Conferencing)

    /// Dominios de videoconferencia que usan Chromium engine
    private static let videoConferenceDomains: Set<String> = [
        "meet.google.com",
        "zoom.us",
        "app.zoom.us",
        "teams.microsoft.com",
        "teams.live.com",
        "teams.cloud.microsoft"
    ]

    /// Teams domains that need standalone Chrome-style window for screen sharing
    private static let teamsDomains: Set<String> = [
        "teams.microsoft.com",
        "teams.live.com",
        "teams.cloud.microsoft"
    ]

    /// Determina si una URL debería usar Chromium engine
    static func shouldUseChromiumEngine(for urlString: String) -> Bool {
        guard let url = URL(string: urlString),
              let host = url.host?.lowercased() else { return false }
        return videoConferenceDomains.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// Determina si una URL es Teams (necesita Chrome-style standalone)
    static func isTeamsDomain(for urlString: String) -> Bool {
        guard let url = URL(string: urlString),
              let host = url.host?.lowercased() else { return false }
        return teamsDomains.contains { host == $0 || host.hasSuffix("." + $0) }
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

    /// Nombre del servicio de videoconferencia para una URL dada
    static func videoConferenceServiceName(for urlString: String) -> String {
        guard let host = URL(string: urlString)?.host?.lowercased() else { return "Videoconferencia" }
        if host.contains("meet.google") { return "Google Meet" }
        if host.contains("zoom") { return "Zoom" }
        if host.contains("teams") { return "Microsoft Teams" }
        return "Videoconferencia"
    }

    /// Nombre del servicio de videoconferencia actual
    var videoConferenceServiceName: String {
        guard let url = currentTab?.url else { return "" }
        return Self.videoConferenceServiceName(for: url)
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

    // Pending close: tab will be removed after CEF browser fully closes
    var pendingClose: Bool = false

    // Tab Suspension
    @Published var isSuspended: Bool = false
    @Published var snapshotPath: URL?
    @Published var lastInteraction: Date = Date()
    var scrollPosition: CGPoint = .zero

    /// Directorio donde se guardan los snapshots de tabs suspendidas (JPEG)
    static var snapshotsDirectory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return caches.appendingPathComponent("MAI/snapshots", isDirectory: true)
    }

    // CEF Hybrid Engine - true when tab uses Chromium (video conferencing)
    @Published var useChromiumEngine: Bool = false
    // True when Teams uses standalone Chrome-style window (for screen sharing)
    @Published var useStandaloneChromium: Bool = false
    // User chose to open video conference in WebKit (skip CEF auto-detection)
    var forceWebKit: Bool = false

    // Incognito mode - no history, non-persistent cookies/cache
    let isIncognito: Bool

    // Tab pinning and muting
    @Published var isPinned: Bool = false
    @Published var isMuted: Bool = false

    // Chrome compatibility mode (spoof Chrome identity on WebKit)
    @Published var chromeCompatMode: Bool = false

    weak var webView: WKWebView?
    /// Referencia strong temporal durante transferencia entre ventanas (tear-off/merge)
    var retainedWebView: WKWebView?

    init(url: String = "about:blank", isIncognito: Bool = false) {
        self.url = url
        self.isIncognito = isIncognito
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
