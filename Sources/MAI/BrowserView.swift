import SwiftUI
import AppKit

/// Vista principal del navegador
struct BrowserView: View {
    @EnvironmentObject var browserState: BrowserState

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

            // Indicador de motor Chromium (cuando el tab usa CEF)
            if browserState.isCurrentTabChromium {
                ChromiumEngineIndicator()
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Indicador de modo Chrome compat (WebKit con identidad Chrome)
            if browserState.currentTab?.chromeCompatMode == true && !browserState.isCurrentTabChromium {
                ChromeCompatIndicator()
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Contenido principal
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

            // Banner de suspensión (si hay tab pendiente)
            SuspensionBanner()

            // Barra de estado
            StatusBar()
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

    var body: some View {
        if let tab = autoSuspend.pendingSuspensionTab {
            HStack(spacing: 10) {
                Image(systemName: "brain.head.profile")
                    .foregroundColor(.orange)
                    .font(.system(size: 12))

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
            .background(Color.orange.opacity(0.08))
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
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

struct ChromiumEngineIndicator: View {
    @EnvironmentObject var browserState: BrowserState

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "gearshape.2.fill")
                .foregroundColor(.orange)
                .font(.system(size: 11))

            Text("Chromium")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.orange)

            Text("- \(browserState.videoConferenceServiceName) (screen sharing habilitado)")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color.orange.opacity(0.08))
    }
}

