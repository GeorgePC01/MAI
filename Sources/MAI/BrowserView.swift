import SwiftUI
import AppKit

/// Vista principal del navegador
struct BrowserView: View {
    @EnvironmentObject var browserState: BrowserState

    var body: some View {
        VStack(spacing: 0) {
            // Barra de título con tabs
            TabBar()

            // Barra de navegación
            AddressBar()

            // Barra de progreso
            if browserState.isLoading {
                ProgressView(value: browserState.loadingProgress)
                    .progressViewStyle(.linear)
                    .tint(.blue)
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

            // Barra de estado
            StatusBar()
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onTapGesture {
            // Activar la aplicación cuando se hace clic en la ventana
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
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
    var body: some View {
        Section("Favoritos") {
            BookmarkRow(title: "Google", url: "https://google.com")
            BookmarkRow(title: "GitHub", url: "https://github.com")
            BookmarkRow(title: "Stack Overflow", url: "https://stackoverflow.com")
        }
    }
}

struct BookmarkRow: View {
    let title: String
    let url: String
    @EnvironmentObject var browserState: BrowserState

    var body: some View {
        Button(action: { browserState.navigate(to: url) }) {
            HStack {
                Image(systemName: "star.fill")
                    .foregroundColor(.yellow)
                Text(title)
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }
}

struct HistorySection: View {
    @EnvironmentObject var browserState: BrowserState
    @ObservedObject private var historyManager = HistoryManager.shared
    @State private var searchText = ""

    var body: some View {
        // Búsqueda
        TextField("Buscar historial...", text: $searchText)
            .textFieldStyle(.roundedBorder)
            .padding(.horizontal, 4)

        let groupedHistory = historyManager.getGroupedHistory()

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

            Spacer()

            // Estadísticas
            HStack(spacing: 16) {
                Label(String(format: "%.0f MB", browserState.memoryUsage), systemImage: "memorychip")
                Label(String(format: "%.1f%%", browserState.cpuUsage), systemImage: "cpu")
                Label("\(browserState.tabs.count) tabs", systemImage: "square.on.square")
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor))
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

