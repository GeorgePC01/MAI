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

                // WebView - expandir para llenar todo el espacio
                WebViewContainer()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

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
    @State private var selectedSection: SidebarSection = .bookmarks

    enum SidebarSection: String, CaseIterable {
        case bookmarks = "Favoritos"
        case history = "Historial"
        case downloads = "Descargas"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Selector de sección
            Picker("", selection: $selectedSection) {
                ForEach(SidebarSection.allCases, id: \.self) { section in
                    Text(section.rawValue).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding(8)

            Divider()

            // Contenido
            List {
                switch selectedSection {
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
    var body: some View {
        Section("Hoy") {
            Text("Sin historial")
                .foregroundColor(.secondary)
        }
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

