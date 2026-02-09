import SwiftUI
import AppKit

/// Barra de direcciones del navegador
struct AddressBar: View {
    @EnvironmentObject var browserState: BrowserState
    @State private var urlText: String = ""
    @State private var isEditing: Bool = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            // Botones de navegación
            NavigationButtons()

            // Campo de URL nativo SwiftUI
            HStack(spacing: 8) {
                SecurityIndicator(url: urlText)

                TextField("Buscar o escribir dirección", text: $urlText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($isFocused)
                    .onSubmit {
                        navigateToURL()
                    }
                    .onChange(of: isFocused) { focused in
                        isEditing = focused
                    }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.textBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isEditing ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: isEditing ? 2 : 1)
                    )
            )
            .contentShape(Rectangle())
            .onTapGesture {
                // PRIMERO: Activar la aplicación MAI
                NSApplication.shared.activate(ignoringOtherApps: true)

                // Forzar foco al hacer clic en cualquier parte del campo
                resignWebViewFocus()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    isFocused = true
                }
            }

            // Botones de acción
            ActionButtons()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
        .onChange(of: browserState.currentURL) { newURL in
            if !isEditing {
                urlText = newURL
            }
        }
        .onAppear {
            urlText = browserState.currentURL
        }
    }

    private func navigateToURL() {
        browserState.navigate(to: urlText)
        isFocused = false
    }

    private func resignWebViewFocus() {
        // Resignar el foco del WKWebView
        if let window = NSApp.keyWindow {
            window.makeFirstResponder(nil)
        }
    }
}

/// Botones de navegación (atrás, adelante, recargar)
struct NavigationButtons: View {
    @EnvironmentObject var browserState: BrowserState

    var body: some View {
        HStack(spacing: 4) {
            Button(action: { browserState.goBack() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(NavigationButtonStyle())
            .disabled(!(browserState.currentTab?.canGoBack ?? false))
            .help("Atrás (Cmd+[)")

            Button(action: { browserState.goForward() }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(NavigationButtonStyle())
            .disabled(!(browserState.currentTab?.canGoForward ?? false))
            .help("Adelante (Cmd+])")

            Button(action: {
                if browserState.isLoading {
                    browserState.stopLoading()
                } else {
                    browserState.reload()
                }
            }) {
                Image(systemName: browserState.isLoading ? "xmark" : "arrow.clockwise")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(NavigationButtonStyle())
            .help(browserState.isLoading ? "Detener" : "Recargar (Cmd+R)")
        }
    }
}

/// Estilo para botones de navegación
struct NavigationButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 28, height: 28)
            .foregroundColor(isEnabled ? .primary : .secondary.opacity(0.5))
            .background(
                Circle()
                    .fill(configuration.isPressed ? Color.gray.opacity(0.2) : Color.clear)
            )
    }
}

/// Indicador de seguridad (candado)
struct SecurityIndicator: View {
    let url: String

    private var isSecure: Bool {
        url.hasPrefix("https://")
    }

    private var isLocal: Bool {
        url.hasPrefix("about:") || url.hasPrefix("file://") || url.isEmpty
    }

    var body: some View {
        Image(systemName: iconName)
            .font(.system(size: 12))
            .foregroundColor(iconColor)
            .frame(width: 16)
    }

    private var iconName: String {
        if isLocal {
            return "magnifyingglass"
        } else if isSecure {
            return "lock.fill"
        } else {
            return "exclamationmark.triangle.fill"
        }
    }

    private var iconColor: Color {
        if isLocal {
            return .secondary
        } else if isSecure {
            return .green
        } else {
            return .orange
        }
    }
}

/// Botones de acción (compartir, favoritos, etc.)
struct ActionButtons: View {
    @EnvironmentObject var browserState: BrowserState
    @ObservedObject private var bookmarksManager = BookmarksManager.shared

    private var isCurrentPageBookmarked: Bool {
        guard let url = browserState.currentTab?.url, !url.isEmpty, url != "about:blank" else {
            return false
        }
        return bookmarksManager.isBookmarked(url: url)
    }

    var body: some View {
        HStack(spacing: 4) {
            // Botón de favoritos (estrella)
            Button(action: { toggleBookmark() }) {
                Image(systemName: isCurrentPageBookmarked ? "star.fill" : "star")
                    .font(.system(size: 14))
                    .foregroundColor(isCurrentPageBookmarked ? .yellow : .primary)
            }
            .buttonStyle(NavigationButtonStyle())
            .help(isCurrentPageBookmarked ? "Quitar de favoritos" : "Agregar a favoritos")
            .disabled(browserState.currentTab?.url.isEmpty ?? true)

            Button(action: { shareCurrentPage() }) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 14))
            }
            .buttonStyle(NavigationButtonStyle())
            .help("Compartir")

            Button(action: { browserState.showSidebar.toggle() }) {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 14))
            }
            .buttonStyle(NavigationButtonStyle())
            .help("Mostrar/ocultar barra lateral (Cmd+Shift+S)")

            Divider()
                .frame(height: 20)

            Button(action: { openSettingsWindow() }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 14))
            }
            .buttonStyle(NavigationButtonStyle())
            .help("Configuración (Cmd+,)")
        }
    }

    private func toggleBookmark() {
        guard let tab = browserState.currentTab,
              !tab.url.isEmpty,
              tab.url != "about:blank" else { return }

        bookmarksManager.toggleBookmark(url: tab.url, title: tab.title)
    }

    private func shareCurrentPage() {
        guard let tab = browserState.currentTab,
              let url = URL(string: tab.url) else { return }

        let picker = NSSharingServicePicker(items: [url])
        if let window = NSApp.keyWindow,
           let contentView = window.contentView {
            picker.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
        }
    }

    private func openSettingsWindow() {
        // Método compatible con macOS 13+
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}
