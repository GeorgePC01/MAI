import SwiftUI
import AppKit
import WebKit

/// Vista principal del navegador
struct BrowserView: View {
    @EnvironmentObject var browserState: BrowserState
    @AppStorage("showStatusBar") private var showStatusBar = true

    var body: some View {
        VStack(spacing: 0) {
            // Barra de título con tabs
            TabBar()

            // Barra de navegación (zIndex alto para que el dropdown de sugerencias no sea tapado)
            AddressBar()
                .zIndex(50)

            // Barra de progreso
            if browserState.isLoading {
                ProgressView(value: browserState.loadingProgress)
                    .progressViewStyle(.linear)
                    .tint(.blue)
            }

            // Banner de guardar contraseña (auto-dismiss 60s — ISO 27001 A.11.2.8)
            if let credential = browserState.pendingCredential {
                PasswordSaveBanner(credential: credential)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
                            if browserState.pendingCredential != nil {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    browserState.pendingCredential = nil
                                }
                            }
                        }
                    }
            }

            // Banner de restauración de sesión
            if browserState.showSessionRestore {
                SessionRestoreBanner()
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Barra de búsqueda en página (Cmd+F)
            if browserState.showFindInPage {
                FindInPageBar()
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Indicador de modo incógnito
            if browserState.isIncognito {
                HStack(spacing: 6) {
                    Image(systemName: "eye.slash.fill")
                        .font(.system(size: 11))
                    Text("Navegación Incógnita")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.secondary)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
                .background(Color(red: 0.14, green: 0.14, blue: 0.16))
                .colorScheme(.dark)
            }

            // Indicador discreto de reunión activa (CEF tabs)
            if browserState.isCurrentTabChromium {
                MeetingIndicator()
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Indicador de modo Chrome compat (WebKit con identidad Chrome)
            if browserState.currentTab?.chromeCompatMode == true && !browserState.isCurrentTabChromium {
                ChromeCompatIndicator()
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Contenido principal con DevTools dockable
            DevToolsDockLayout {
                HStack(spacing: 0) {
                    // Sidebar opcional
                    if browserState.showSidebar {
                        SidebarView()
                            .frame(width: 250)
                            .transition(.move(edge: .leading))
                    }

                    // WebView
                    WebViewContainer()
                }
            }

            // Banner de suspensión (si hay tab pendiente)
            SuspensionBanner()

            // Barra de estado (configurable en Ajustes → Apariencia)
            if showStatusBar {
                StatusBar()
            }
        }
        .background(browserState.isIncognito
                    ? Color(red: 0.10, green: 0.10, blue: 0.12)
                    : Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $browserState.showPhishingWarning) {
            PhishingWarningView()
                .environmentObject(browserState)
        }
        .onAppear {
            // Registrar ventana principal en WindowManager para soporte de merge tabs
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                WindowManager.shared.registerMainWindow(state: browserState)
            }
        }
    }
}

/// Layout que posiciona DevTools abajo, a la derecha o a la izquierda del contenido principal
struct DevToolsDockLayout<Content: View>: View {
    @EnvironmentObject var browserState: BrowserState
    @ObservedObject private var devToolsState = DevToolsState.shared
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    @State private var containerSize: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            let lateralWidth = devToolsState.devToolsSize
            Group {
                if browserState.showDevTools {
                    switch devToolsState.dockPosition {
                    case .bottom:
                        VStack(spacing: 0) {
                            content()
                            DevToolsResizeHandle(isHorizontal: true, containerSize: containerSize)
                            DevToolsView()
                                .frame(height: devToolsState.devToolsSize)
                                .transition(.move(edge: .bottom))
                        }
                    case .right:
                        HStack(spacing: 0) {
                            content()
                            DevToolsResizeHandle(isHorizontal: false, containerSize: containerSize)
                            DevToolsView()
                                .frame(width: lateralWidth)
                                .transition(.move(edge: .trailing))
                        }
                    case .left:
                        HStack(spacing: 0) {
                            DevToolsView()
                                .frame(width: lateralWidth)
                                .transition(.move(edge: .leading))
                            DevToolsResizeHandle(isHorizontal: false, containerSize: containerSize)
                            content()
                        }
                    }
                } else {
                    content()
                }
            }
            .animation(nil, value: devToolsState.devToolsSize)
            .onChange(of: geometry.size.width) { newWidth in
                containerSize = geometry.size
                devToolsState.windowWidth = newWidth
            }
            .onAppear {
                containerSize = geometry.size
                devToolsState.windowWidth = geometry.size.width
                // Si está en modo lateral, asegurar tamaño inicial de 54%
                if devToolsState.dockPosition != .bottom {
                    let targetSize = geometry.size.width * 0.54
                    if devToolsState.devToolsSize < targetSize {
                        devToolsState.devToolsSize = targetSize
                    }
                }
            }
        }
    }
}

/// Barra de redimensión arrastrable entre WebView y DevTools
/// Técnica: durante el drag solo mueve una línea visual (overlay), aplica el tamaño real al soltar.
/// Esto evita que WKWebView se redimensione en cada pixel del drag (causa del temblor).
struct DevToolsResizeHandle: View {
    let isHorizontal: Bool
    var containerSize: CGSize = .zero
    @ObservedObject private var devToolsState = DevToolsState.shared
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging: Bool = false

    private var clampedOffset: CGFloat {
        let maxSize = isHorizontal
            ? containerSize.height * 0.85
            : containerSize.width * 0.85
        let newSize = devToolsState.devToolsSize + dragOffset
        let clamped = min(maxSize, max(200, newSize))
        return clamped - devToolsState.devToolsSize
    }

    private var previewSize: CGFloat {
        devToolsState.devToolsSize + clampedOffset
    }

    private var sizeLabel: String {
        let total = isHorizontal ? containerSize.height : containerSize.width
        let pct = total > 0 ? Int(previewSize / total * 100) : 0
        return "\(Int(previewSize))px — \(pct)%"
    }

    var body: some View {
        Rectangle()
            .fill(isDragging ? DT.link : DT.border)
            .frame(
                width: isHorizontal ? nil : 5,
                height: isHorizontal ? 5 : nil
            )
            .contentShape(Rectangle().inset(by: -4))
            .onHover { hovering in
                if hovering {
                    if isHorizontal {
                        NSCursor.resizeUpDown.push()
                    } else {
                        NSCursor.resizeLeftRight.push()
                    }
                } else {
                    NSCursor.pop()
                }
            }
            .overlay(
                Group {
                    if isDragging {
                        Text(sizeLabel)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.85))
                            .cornerRadius(6)
                            .fixedSize()
                            .allowsHitTesting(false)
                    }
                }
            )
            .zIndex(isDragging ? 100 : 0)
            .offset(
                x: !isHorizontal && isDragging ? (devToolsState.dockPosition == .right ? -clampedOffset : clampedOffset) : 0,
                y: isHorizontal && isDragging ? -clampedOffset : 0
            )
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        isDragging = true
                        if isHorizontal {
                            dragOffset = -value.translation.height
                        } else if devToolsState.dockPosition == .right {
                            dragOffset = -value.translation.width
                        } else {
                            dragOffset = value.translation.width
                        }
                    }
                    .onEnded { _ in
                        // Aplicar tamaño final de una sola vez
                        devToolsState.devToolsSize = previewSize
                        dragOffset = 0
                        isDragging = false
                    }
            )
    }
}

/// Diálogo de advertencia cuando se detecta phishing
struct PhishingWarningView: View {
    @EnvironmentObject var browserState: BrowserState

    private var isDangerous: Bool {
        if case .dangerous = browserState.phishingThreatLevel { return true }
        return false
    }

    private var score: Double {
        switch browserState.phishingThreatLevel {
        case .safe: return 0
        case .suspicious(let s, _): return s
        case .dangerous(let s, _): return s
        }
    }

    private var reasons: [String] {
        switch browserState.phishingThreatLevel {
        case .safe: return []
        case .suspicious(_, let r): return r
        case .dangerous(_, let r): return r
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            // Icono
            Image(systemName: isDangerous ? "octagon.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 56))
                .foregroundColor(isDangerous ? .red : .orange)

            // Título
            Text(isDangerous ? "Sitio Peligroso Detectado" : "Sitio Sospechoso Detectado")
                .font(.title2)
                .fontWeight(.bold)

            // URL
            Text(browserState.pendingPhishingURL)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
                .padding(.horizontal)

            // Puntuación de riesgo
            HStack(spacing: 8) {
                Text("Riesgo:")
                    .fontWeight(.medium)
                ProgressView(value: score, total: 1.0)
                    .progressViewStyle(.linear)
                    .tint(isDangerous ? .red : .orange)
                    .frame(width: 100)
                Text("\(Int(score * 100))%")
                    .fontWeight(.bold)
                    .foregroundColor(isDangerous ? .red : .orange)
            }

            // Lista de razones
            if !reasons.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Razones:")
                        .fontWeight(.medium)
                    ForEach(reasons, id: \.self) { reason in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(isDangerous ? .red : .orange)
                                .font(.system(size: 12))
                                .padding(.top, 2)
                            Text(reason)
                                .font(.system(size: 13))
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isDangerous
                              ? Color.red.opacity(0.08)
                              : Color.orange.opacity(0.08))
                )
            }

            // Botones
            HStack(spacing: 16) {
                Button(action: { browserState.cancelPhishingNavigation() }) {
                    HStack {
                        Image(systemName: "arrow.uturn.backward")
                        Text("Volver (Recomendado)")
                    }
                    .frame(minWidth: 180)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)

                Button(action: { browserState.proceedToPhishingURL() }) {
                    Text("Continuar de todos modos")
                        .frame(minWidth: 160)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .foregroundColor(.secondary)
            }
        }
        .padding(32)
        .frame(width: 480)
    }
}

/// Barra lateral con bookmarks e historial
struct SidebarView: View {
    @EnvironmentObject var browserState: BrowserState

    var body: some View {
        VStack(spacing: 0) {
            // Selector de sección
            Picker("", selection: $browserState.sidebarSection) {
                ForEach(BrowserState.SidebarTab.allCases, id: \.self) { section in
                    Text(section.rawValue).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding(8)

            Divider()

            // Contenido
            List {
                switch browserState.sidebarSection {
                case .bookmarks:
                    BookmarksSection()
                case .history:
                    HistorySection()
                case .downloads:
                    DownloadsSection()
                }
            }
            .listStyle(.sidebar)
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
}

struct BookmarksSection: View {
    @EnvironmentObject var browserState: BrowserState
    @ObservedObject private var bookmarksManager = BookmarksManager.shared
    @State private var searchText = ""

    var body: some View {
        // Búsqueda
        TextField("Buscar favoritos...", text: $searchText)
            .textFieldStyle(.roundedBorder)
            .padding(.horizontal, 4)

        let filteredBookmarks = searchText.isEmpty
            ? bookmarksManager.bookmarks
            : bookmarksManager.search(query: searchText)

        if filteredBookmarks.isEmpty {
            Text("Sin favoritos")
                .foregroundColor(.secondary)
                .padding()
        } else {
            // Carpetas
            ForEach(bookmarksManager.folders, id: \.self) { folder in
                Section(folder) {
                    ForEach(bookmarksManager.bookmarks(in: folder)) { bookmark in
                        BookmarkRow(bookmark: bookmark)
                    }
                }
            }

            // Favoritos sin carpeta
            Section("Favoritos") {
                ForEach(filteredBookmarks.filter { $0.folder == nil }) { bookmark in
                    BookmarkRow(bookmark: bookmark)
                }
            }
        }
    }
}

struct BookmarkRow: View {
    let bookmark: Bookmark
    @EnvironmentObject var browserState: BrowserState
    @ObservedObject private var bookmarksManager = BookmarksManager.shared
    @State private var showingDeleteAlert = false

    var body: some View {
        Button(action: { browserState.navigate(to: bookmark.url) }) {
            HStack {
                Image(systemName: "star.fill")
                    .foregroundColor(.yellow)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 2) {
                    Text(bookmark.title)
                        .lineLimit(1)

                    Text(bookmark.url)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Abrir") {
                browserState.navigate(to: bookmark.url)
            }

            Button("Abrir en nueva pestaña") {
                browserState.createTab(url: bookmark.url)
            }

            Divider()

            Button("Copiar URL") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(bookmark.url, forType: .string)
            }

            Divider()

            Button("Eliminar", role: .destructive) {
                bookmarksManager.removeBookmark(bookmark)
            }
        }
    }
}

struct HistorySection: View {
    @EnvironmentObject var browserState: BrowserState
    @ObservedObject private var historyManager = HistoryManager.shared
    @State private var searchText = ""
    @State private var fullTextResults: [FullTextSearchManager.SearchResult] = []
    @State private var isFullTextSearch = false

    var body: some View {
        // Búsqueda con toggle full-text
        VStack(spacing: 4) {
            TextField("Buscar historial...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 4)
                .onChange(of: searchText) { query in
                    if isFullTextSearch && query.count >= 3 {
                        fullTextResults = FullTextSearchManager.shared.search(query: query)
                    } else {
                        fullTextResults = []
                    }
                }

            if FullTextSearchManager.shared.isEnabled {
                Toggle("Buscar en contenido de páginas", isOn: $isFullTextSearch)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .padding(.horizontal, 8)
                    .onChange(of: isFullTextSearch) { enabled in
                        if enabled && searchText.count >= 3 {
                            fullTextResults = FullTextSearchManager.shared.search(query: searchText)
                        } else {
                            fullTextResults = []
                        }
                    }
            }
        }

        // Resultados full-text
        if isFullTextSearch && !fullTextResults.isEmpty {
            Section("Resultados en contenido") {
                ForEach(fullTextResults) { result in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.title.isEmpty ? result.url : result.title)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        Text(result.snippet)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                        Text(result.url)
                            .font(.system(size: 10))
                            .foregroundColor(.blue)
                            .lineLimit(1)
                    }
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        browserState.navigate(to: result.url)
                    }
                }
            }
        } else if isFullTextSearch && searchText.count >= 3 && fullTextResults.isEmpty {
            Text("Sin resultados en contenido")
                .foregroundColor(.secondary)
                .font(.caption)
                .padding(.horizontal, 8)
        }

        // Historial normal
        let groupedHistory = historyManager.getGroupedHistory()

        if !isFullTextSearch {
            if groupedHistory.isEmpty {
                Text("Sin historial")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                ForEach(groupedHistory, id: \.date) { group in
                    Section(group.date) {
                        ForEach(filteredEntries(group.entries)) { entry in
                            HistoryRow(entry: entry)
                        }
                    }
                }
            }
        }

        // Botón para limpiar
        Section {
            Button(action: { historyManager.clearAll() }) {
                HStack {
                    Image(systemName: "trash")
                    Text("Limpiar historial")
                }
                .foregroundColor(.red)
            }
            .buttonStyle(.plain)
        }
    }

    private func filteredEntries(_ entries: [HistoryEntry]) -> [HistoryEntry] {
        guard !searchText.isEmpty else { return entries }
        let query = searchText.lowercased()
        return entries.filter {
            $0.title.lowercased().contains(query) ||
            $0.url.lowercased().contains(query)
        }
    }
}

struct HistoryRow: View {
    let entry: HistoryEntry
    @EnvironmentObject var browserState: BrowserState

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: entry.visitDate)
    }

    var body: some View {
        Button(action: { browserState.navigate(to: entry.url) }) {
            HStack {
                Image(systemName: "clock")
                    .foregroundColor(.secondary)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(entry.url)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Text(timeString)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

struct DownloadsSection: View {
    var body: some View {
        Section("Descargas") {
            Text("Sin descargas")
                .foregroundColor(.secondary)
        }
    }
}

/// Barra de estado inferior
struct StatusBar: View {
    @EnvironmentObject var browserState: BrowserState
    @ObservedObject private var privacyManager = PrivacyManager.shared
    @State private var showBlockedList = false

    var body: some View {
        HStack {
            // Estado de carga
            if browserState.isLoading {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundColor(.secondary)
                Text("Cargando...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Contador de bloqueos (si hay) - clickeable
            if privacyManager.blockedRequestsCount > 0 {
                Button(action: { showBlockedList.toggle() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "shield.checkered")
                            .foregroundColor(.green)
                        Text("\(privacyManager.blockedRequestsCount) bloqueados")
                    }
                    .font(.caption)
                    .foregroundColor(.green)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showBlockedList) {
                    BlockedRequestsPopover()
                }
            }

            // Tabs suspendidas (si hay)
            if browserState.suspendedTabsCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "moon.zzz.fill")
                        .foregroundColor(.orange)
                    if browserState.autoSuspendedCount > 0 {
                        Text("\(browserState.suspendedTabsCount) suspendidas (\(browserState.autoSuspendedCount) auto)")
                    } else {
                        Text("\(browserState.suspendedTabsCount) suspendidas")
                    }
                    Text("(-\(Int(browserState.estimatedRAMSaved)) MB)")
                        .foregroundColor(.green)
                }
                .font(.caption)
            }

            Spacer()

            // Estadísticas
            HStack(spacing: 16) {
                Label(String(format: "%.0f MB", browserState.memoryUsage), systemImage: "memorychip")
                Label(String(format: "%.1f%%", browserState.cpuUsage), systemImage: "cpu")

                // Tabs activas vs total
                let activeTabs = browserState.tabs.count - browserState.suspendedTabsCount
                Label("\(activeTabs)/\(browserState.tabs.count) tabs", systemImage: "square.on.square")
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(browserState.isIncognito
                    ? Color(red: 0.10, green: 0.10, blue: 0.12)
                    : Color(NSColor.controlBackgroundColor))
        .colorScheme(browserState.isIncognito ? .dark : .light)
    }
}

/// Popover que muestra los elementos bloqueados
struct BlockedRequestsPopover: View {
    @ObservedObject private var privacyManager = PrivacyManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "shield.checkered")
                    .foregroundColor(.green)
                Text("Elementos bloqueados")
                    .fontWeight(.semibold)
                Spacer()
                Text("\(privacyManager.blockedRequestsCount)")
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Lista de bloqueados
            if privacyManager.blockedRequests.isEmpty {
                Text("No hay elementos bloqueados")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(privacyManager.blockedRequests) { request in
                            BlockedRequestRow(request: request)
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 300)
            }

            Divider()

            // Footer con botón limpiar
            HStack {
                Button("Limpiar lista") {
                    privacyManager.resetBlockedCount()
                }
                .buttonStyle(.borderless)
                .foregroundColor(.red)

                Spacer()

                Text("Solo trackers y ads")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
        }
        .frame(width: 350)
    }
}

/// Fila individual de request bloqueado
struct BlockedRequestRow: View {
    let request: PrivacyManager.BlockedRequest

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: request.timestamp)
    }

    private var typeColor: Color {
        switch request.type {
        case .tracker: return .orange
        case .ad: return .red
        case .thirdPartyCookie: return .purple
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            // Icono de tipo
            Circle()
                .fill(typeColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(request.domain)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                Text(request.url)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(request.type.rawValue)
                    .font(.system(size: 10))
                    .foregroundColor(typeColor)

                Text(timeString)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

/// Barra de búsqueda en página (Cmd+F)
struct FindInPageBar: View {
    @EnvironmentObject var browserState: BrowserState
    @State private var searchText: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Campo de búsqueda
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)

                TextField("Buscar en página...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($isFocused)
                    .onSubmit {
                        browserState.findNext()
                    }
                    .onChange(of: searchText) { newValue in
                        browserState.findInPage(newValue)
                    }

                // Contador de resultados
                if browserState.findResultCount > 0 {
                    Text("\(browserState.findCurrentIndex)/\(browserState.findResultCount)")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                } else if !searchText.isEmpty {
                    Text("Sin resultados")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(NSColor.textBackgroundColor))
            )
            .frame(maxWidth: 300)

            // Botones de navegación
            HStack(spacing: 4) {
                Button(action: { browserState.findPrevious() }) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(FindButtonStyle())
                .disabled(browserState.findResultCount == 0)
                .help("Anterior (Shift+Enter)")

                Button(action: { browserState.findNext() }) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(FindButtonStyle())
                .disabled(browserState.findResultCount == 0)
                .help("Siguiente (Enter)")
            }

            Spacer()

            // Botón cerrar
            Button(action: { browserState.closeFindInPage() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(FindButtonStyle())
            .keyboardShortcut(.escape, modifiers: [])
            .help("Cerrar (Esc)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
        .onAppear {
            isFocused = true
            searchText = browserState.findQuery
        }
        .onDisappear {
            browserState.clearFindHighlights()
        }
    }
}

/// Estilo para botones de búsqueda
struct FindButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 24, height: 24)
            .foregroundColor(isEnabled ? .primary : .secondary.opacity(0.5))
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(configuration.isPressed ? Color.gray.opacity(0.3) : Color.clear)
            )
    }
}

/// Banner que pregunta al usuario si quiere suspender una tab (modo aprendizaje)
struct SuspensionBanner: View {
    @ObservedObject private var autoSuspend = AutoSuspendManager.shared
    @State private var iconScale: CGFloat = 1.0
    @State private var glowOpacity: Double = 0.0

    var body: some View {
        if let tab = autoSuspend.pendingSuspensionTab {
            HStack(spacing: 10) {
                Image(systemName: "brain.head.profile")
                    .foregroundColor(.orange)
                    .font(.system(size: 12))
                    .scaleEffect(iconScale)

                Text("Suspender '\(tab.title)'?")
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                Text("(\(autoSuspend.pendingSuspensionDomain))")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Spacer()

                // "Sí" — botón prominente
                Button(action: { autoSuspend.userApprovedSuspension() }) {
                    Text("Sí")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.mini)

                // "No" — botón bordered
                Button(action: { autoSuspend.userDeclinedSuspension() }) {
                    Text("No")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                // "Siempre" — link morado
                Button(action: { autoSuspend.userApprovedAlways() }) {
                    Text("Siempre")
                        .font(.system(size: 11))
                        .foregroundColor(.purple)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.orange.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.orange.opacity(glowOpacity * 0.4), lineWidth: 1)
                    )
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .onAppear {
                // Sonido sutil del sistema al aparecer
                NSSound.beep()

                // Animación pulse en el ícono (3 pulsos)
                withAnimation(.easeInOut(duration: 0.3).repeatCount(3, autoreverses: true)) {
                    iconScale = 1.3
                }
                // Glow del borde naranja
                withAnimation(.easeInOut(duration: 0.6).repeatCount(2, autoreverses: true)) {
                    glowOpacity = 1.0
                }
                // Reset después de las animaciones
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        iconScale = 1.0
                        glowOpacity = 0.0
                    }
                }
            }
        }
    }
}

/// Barra de selección de workspace
struct WorkspaceBar: View {
    @ObservedObject private var workspaceManager = WorkspaceManager.shared
    @EnvironmentObject var browserState: BrowserState
    @State private var showCreateSheet = false
    @State private var newName = ""
    @State private var newColorHex = "007AFF"
    @State private var newIcon = "briefcase.fill"

    var body: some View {
        HStack(spacing: 6) {
            ForEach(workspaceManager.workspaces) { workspace in
                WorkspaceChip(
                    workspace: workspace,
                    isActive: workspace.id == browserState.workspaceID
                )
                .onTapGesture {
                    if workspace.id != browserState.workspaceID {
                        // Abrir nueva ventana con este workspace
                        WindowManager.shared.openNewWindow(workspaceID: workspace.id)
                    }
                }
                .contextMenu {
                    if workspace.id != Workspace.defaultWorkspace.id {
                        Button("Editar nombre...") {
                            renameWorkspace(workspace)
                        }
                        Divider()
                        Button("Eliminar workspace", role: .destructive) {
                            workspaceManager.deleteWorkspace(workspace.id)
                        }
                    }
                }
            }

            // Botón para crear workspace
            Button(action: { showCreateSheet = true }) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Crear nuevo workspace")

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.95))
        .sheet(isPresented: $showCreateSheet) {
            CreateWorkspaceSheet(
                name: $newName,
                colorHex: $newColorHex,
                icon: $newIcon,
                onCreate: {
                    let ws = workspaceManager.createWorkspace(name: newName, colorHex: newColorHex, icon: newIcon)
                    newName = ""
                    showCreateSheet = false
                    // Abrir nueva ventana con el workspace recién creado
                    WindowManager.shared.openNewWindow(workspaceID: ws.id)
                },
                onCancel: {
                    newName = ""
                    showCreateSheet = false
                }
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .maiCreateWorkspace)) { _ in
            showCreateSheet = true
        }
    }

    private func renameWorkspace(_ workspace: Workspace) {
        let alert = NSAlert()
        alert.messageText = "Renombrar workspace"
        alert.addButton(withTitle: "Guardar")
        alert.addButton(withTitle: "Cancelar")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 250, height: 24))
        input.stringValue = workspace.name
        alert.accessoryView = input

        if alert.runModal() == .alertFirstButtonReturn {
            var updated = workspace
            updated.name = input.stringValue
            workspaceManager.updateWorkspace(updated)
        }
    }
}

/// Chip visual de un workspace
struct WorkspaceChip: View {
    let workspace: Workspace
    let isActive: Bool

    var color: Color {
        Color(hex: workspace.colorHex) ?? .blue
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: workspace.icon)
                .font(.system(size: 9))
            Text(workspace.name)
                .font(.system(size: 10, weight: isActive ? .semibold : .regular))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isActive ? color.opacity(0.15) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(isActive ? color : Color.gray.opacity(0.3), lineWidth: isActive ? 1.5 : 0.5)
                )
        )
        .foregroundColor(isActive ? color : .secondary)
    }
}

/// Sheet para crear un nuevo workspace
struct CreateWorkspaceSheet: View {
    @Binding var name: String
    @Binding var colorHex: String
    @Binding var icon: String
    var onCreate: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Nuevo Workspace")
                .font(.headline)

            TextField("Nombre", text: $name)
                .textFieldStyle(.roundedBorder)

            // Selector de color
            HStack(spacing: 8) {
                Text("Color:")
                    .font(.caption)
                ForEach(Workspace.defaultColors, id: \.hex) { c in
                    Circle()
                        .fill(Color(hex: c.hex) ?? .blue)
                        .frame(width: 20, height: 20)
                        .overlay(
                            Circle()
                                .stroke(Color.primary, lineWidth: colorHex == c.hex ? 2 : 0)
                        )
                        .onTapGesture { colorHex = c.hex }
                }
            }

            // Selector de ícono
            HStack(spacing: 8) {
                Text("Ícono:")
                    .font(.caption)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(28)), count: 6), spacing: 4) {
                    ForEach(Workspace.defaultIcons, id: \.self) { ic in
                        Image(systemName: ic)
                            .font(.system(size: 12))
                            .frame(width: 28, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(icon == ic ? Color.accentColor.opacity(0.2) : Color.clear)
                            )
                            .onTapGesture { icon = ic }
                    }
                }
            }

            HStack {
                Button("Cancelar", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Crear", action: onCreate)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}

/// Extensión para crear Color desde hex string
extension Color {
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard hex.count == 6,
              let int = UInt64(hex, radix: 16) else { return nil }
        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >> 8) & 0xFF) / 255.0
        let b = Double(int & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

/// Banner que ofrece traducir la página cuando detecta un idioma diferente al target
struct TranslationBanner: View {
    @ObservedObject private var translation = TranslationManager.shared
    @EnvironmentObject var browserState: BrowserState

    var body: some View {
        if translation.currentTabTranslated {
            // Banner post-traducción: "Traducida de X" + botón "Ver original"
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 12))

                Text("Traducida de \(TranslationManager.languageName(for: translation.detectedLanguage))")
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                Spacer()

                Button(action: { restoreOriginalPage() }) {
                    Text("Ver original")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                Button(action: { translation.currentTabTranslated = false }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Color.green.opacity(0.06))
            .transition(.move(edge: .top).combined(with: .opacity))
        } else if translation.showTranslationBanner && !translation.detectedLanguage.isEmpty {
            HStack(spacing: 10) {
                Image(systemName: "globe")
                    .foregroundColor(.blue)
                    .font(.system(size: 12))

                Text("Página en \(TranslationManager.languageName(for: translation.detectedLanguage))")
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                Spacer()

                if translation.isTranslating {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 16, height: 16)
                    Text("Traduciendo...")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                } else {
                    // Traducir
                    Button(action: { translateCurrentPage() }) {
                        Text("Traducir a \(TranslationManager.languageName(for: translation.targetLanguage))")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .controlSize(.mini)

                    // Descartar
                    Button(action: { translation.showTranslationBanner = false }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Color.blue.opacity(0.06))
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func translateCurrentPage() {
        // Buscar el WKWebView activo para inyectar la traducción
        guard let window = NSApp.keyWindow,
              let contentView = window.contentView else { return }

        // Encontrar el WKWebView en la jerarquía
        if let webView = findWebView(in: contentView) {
            let sourceLang = translation.detectedLanguage
            Task {
                await translation.translatePage(webView: webView, from: sourceLang)
            }
        }
    }

    private func restoreOriginalPage() {
        guard let window = NSApp.keyWindow,
              let contentView = window.contentView,
              let webView = findWebView(in: contentView) else { return }
        Task {
            await translation.restoreOriginal(webView: webView)
        }
    }

    /// Busca recursivamente un WKWebView en la jerarquía de vistas
    private func findWebView(in view: NSView) -> WKWebView? {
        if let webView = view as? WKWebView {
            return webView
        }
        for subview in view.subviews {
            if let found = findWebView(in: subview) {
                return found
            }
        }
        return nil
    }
}

/// Indicador sutil cuando un tab usa Chromium engine (CEF) para videoconferencias
struct ChromeCompatIndicator: View {
    @EnvironmentObject var browserState: BrowserState

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "globe.americas")
                .foregroundColor(.blue)
                .font(.system(size: 11))

            Text("Modo Chrome")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.blue)

            Text("- Identidad Chrome en WebKit")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(1)

            Spacer()

            Button(action: {
                if let tab = browserState.currentTab {
                    browserState.toggleChromeCompatMode(tab)
                }
            }) {
                Text("Desactivar")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.blue)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color.blue.opacity(0.08))
    }
}

/// Indicador discreto de reunión activa — reemplaza el viejo "Chromium Engine Indicator"

struct PasswordSaveBanner: View {
    @EnvironmentObject var browserState: BrowserState
    let credential: PendingCredential
    @State private var breachCount: Int = 0
    @State private var breachChecked: Bool = false

    /// NIST 800-63B: evalúa fortaleza de la contraseña
    private var passwordStrength: (label: String, color: Color) {
        let p = credential.password
        if p.count < 8 { return ("Contraseña débil", .red) }
        var score = 0
        if p.count >= 12 { score += 1 }
        if p.range(of: "[A-Z]", options: .regularExpression) != nil { score += 1 }
        if p.range(of: "[0-9]", options: .regularExpression) != nil { score += 1 }
        if p.range(of: "[^a-zA-Z0-9]", options: .regularExpression) != nil { score += 1 }
        if score >= 3 { return ("Contraseña fuerte", .green) }
        return ("Contraseña aceptable", .orange)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "key.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.orange)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text("¿Guardar contraseña?")
                            .font(.system(size: 12, weight: .medium))
                        // NIST 800-63B: indicador de fortaleza
                        Text(passwordStrength.label)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(passwordStrength.color)
                    }
                    Text("\(credential.username) en \(credential.host)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button(action: {
                    let _ = PasswordManager.shared.saveCredential(
                        host: credential.host,
                        username: credential.username,
                        password: credential.password
                    )
                    withAnimation(.easeOut(duration: 0.2)) {
                        browserState.pendingCredential = nil
                    }
                }) {
                    Text("Guardar")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Color.orange)
                        .cornerRadius(5)
                }
                .buttonStyle(.plain)

                Button(action: {
                    withAnimation(.easeOut(duration: 0.2)) {
                        browserState.pendingCredential = nil
                    }
                }) {
                    Text("No")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            // NIST 800-63B §5.1.1.2: Advertencia de contraseña filtrada
            if breachChecked && breachCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                    Text("Esta contraseña apareció en \(breachCount.formatted()) filtraciones conocidas")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(.red)
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(breachCount > 0 ? Color.red.opacity(0.08) : Color.orange.opacity(0.08))
        .onAppear {
            PasswordManager.shared.checkBreached(password: credential.password) { count in
                breachCount = count
                breachChecked = true
            }
        }
    }
}

struct SessionRestoreBanner: View {
    @EnvironmentObject var browserState: BrowserState
    private let tabCount = SessionManager.shared.savedTabCount

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.counterclockwise.circle.fill")
                .font(.system(size: 14))
                .foregroundColor(.blue)

            Text("Se cerró inesperadamente. ¿Restaurar \(tabCount) pestaña\(tabCount == 1 ? "" : "s")?")
                .font(.system(size: 12))
                .lineLimit(1)

            Spacer()

            Button(action: {
                withAnimation(.easeOut(duration: 0.2)) {
                    browserState.showSessionRestore = false
                }
                let _ = SessionManager.shared.restoreSession(into: browserState)
            }) {
                Text("Restaurar")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.blue)
                    .cornerRadius(5)
            }
            .buttonStyle(.plain)

            Button(action: {
                withAnimation(.easeOut(duration: 0.2)) {
                    browserState.showSessionRestore = false
                }
                SessionManager.shared.clearSession()
            }) {
                Text("Descartar")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.blue.opacity(0.08))
    }
}

struct MeetingIndicator: View {
    @EnvironmentObject var browserState: BrowserState

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.green)
                .frame(width: 7, height: 7)

            Text("Reunión activa — \(browserState.videoConferenceServiceName)")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(1)

            Spacer()

            Button(action: {
                if let window = NSApp.keyWindow {
                    window.close()
                }
            }) {
                Text("Cerrar al terminar")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
        .background(Color.green.opacity(0.05))
    }
}

