import SwiftUI

/// Barra de pestañas del navegador
struct TabBar: View {
    @EnvironmentObject var browserState: BrowserState
    @State private var hoveredTab: UUID?

    var body: some View {
        HStack(spacing: 0) {
            // Área draggable para mover ventana
            Color.clear
                .frame(width: 70, height: 38)

            // Pestañas
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(Array(browserState.tabs.enumerated()), id: \.element.id) { index, tab in
                        TabItem(
                            tab: tab,
                            isSelected: index == browserState.currentTabIndex,
                            isHovered: hoveredTab == tab.id,
                            onSelect: { browserState.selectTab(at: index) },
                            onClose: { browserState.closeTab(at: index) }
                        )
                        .onHover { isHovered in
                            hoveredTab = isHovered ? tab.id : nil
                        }
                    }

                    // Botón nueva pestaña (junto a las pestañas)
                    Button(action: { browserState.createTab() }) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .medium))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .help("Nueva pestaña (Cmd+T)")
                }
                .padding(.horizontal, 4)
            }
            .frame(height: 38)
        }
        .background(TabBarBackground())
        .colorScheme(browserState.isIncognito ? .dark : .light)
    }
}

/// Item individual de pestaña
struct TabItem: View {
    @ObservedObject var tab: Tab
    @EnvironmentObject var browserState: BrowserState
    let isSelected: Bool
    let isHovered: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // Icono de suspendida, pinned, incógnito, o favicon
            if tab.isSuspended {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.orange)
                    .frame(width: 16, height: 16)
            } else if tab.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.blue)
                    .frame(width: 16, height: 16)
            } else if tab.isIncognito {
                Image(systemName: "eye.slash.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(width: 16, height: 16)
            } else if let favicon = tab.favicon {
                Image(nsImage: favicon)
                    .resizable()
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: tab.isLoading ? "arrow.triangle.2.circlepath" : "globe")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(width: 16, height: 16)
                    .rotationEffect(tab.isLoading ? .degrees(360) : .zero)
                    .animation(tab.isLoading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: tab.isLoading)
            }

            // Título
            Text(tab.title)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 150, alignment: .leading)
                .opacity(tab.isSuspended ? 0.6 : 1.0)

            if tab.isMuted {
                Image(systemName: "speaker.slash.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 0)

            // Botón cerrar
            if isHovered || isSelected {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: 16, height: 16)
                        .background(
                            Circle()
                                .fill(Color.gray.opacity(0.2))
                                .opacity(isHovered ? 1 : 0)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(minWidth: 120, maxWidth: 200, minHeight: 30)
        .background(TabItemBackground(isSelected: isSelected, isHovered: isHovered, isSuspended: tab.isSuspended, isIncognito: tab.isIncognito))
        .cornerRadius(8)
        .onTapGesture {
            // Si está suspendida, restaurar al hacer clic
            if tab.isSuspended {
                browserState.resumeTab(tab)
            }
            onSelect()
        }
        .contextMenu {
            Button(action: { browserState.reloadTab(tab) }) {
                Label("Recargar", systemImage: "arrow.clockwise")
            }
            .disabled(tab.isSuspended)

            Button(action: { browserState.duplicateTab(tab) }) {
                Label("Duplicar", systemImage: "plus.square.on.square")
            }

            Button(action: { browserState.toggleMuteTab(tab) }) {
                Label(tab.isMuted ? "Activar Sonido" : "Silenciar Sitio", systemImage: tab.isMuted ? "speaker.wave.2" : "speaker.slash")
            }
            .disabled(tab.isSuspended)

            Button(action: { browserState.togglePinTab(tab) }) {
                Label(tab.isPinned ? "Desfijar Tab" : "Fijar Tab", systemImage: tab.isPinned ? "pin.slash" : "pin")
            }

            Divider()

            if tab.isSuspended {
                Button(action: { browserState.resumeTab(tab) }) {
                    Label("Restaurar Tab", systemImage: "arrow.uturn.backward")
                }
            } else {
                Button(action: { browserState.suspendTab(tab) }) {
                    Label("Suspender Tab", systemImage: "moon.zzz")
                }
            }

            Button(action: { browserState.suspendInactiveTabs() }) {
                Label("Suspender Otras Tabs", systemImage: "moon.zzz.fill")
            }

            Divider()

            Button(action: { browserState.closeOtherTabs(except: tab) }) {
                Label("Cerrar Otras Tabs", systemImage: "xmark.square")
            }
            .disabled(browserState.tabs.count <= 1)

            Button(action: { browserState.closeTabsToRight(of: tab) }) {
                Label("Cerrar Tabs a la Derecha", systemImage: "xmark.square.fill")
            }
            .disabled(browserState.tabs.last?.id == tab.id)

            Button(action: onClose) {
                Label("Cerrar Tab", systemImage: "xmark")
            }
        }
    }
}

/// Fondo del item de pestaña
struct TabItemBackground: View {
    let isSelected: Bool
    let isHovered: Bool
    var isSuspended: Bool = false
    var isIncognito: Bool = false

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(backgroundColor)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
    }

    private var borderColor: Color {
        if isIncognito { return Color.gray.opacity(0.4) }
        if isSuspended { return Color.orange.opacity(0.5) }
        return Color.clear
    }

    private var backgroundColor: Color {
        if isSelected {
            if isIncognito { return Color(red: 0.20, green: 0.21, blue: 0.24) }
            if isSuspended { return Color.orange.opacity(0.15) }
            return Color(NSColor.controlBackgroundColor)
        } else if isHovered {
            return isIncognito ? Color(red: 0.16, green: 0.17, blue: 0.20) : Color.gray.opacity(0.15)
        } else {
            return Color.clear
        }
    }
}

/// Fondo de la barra de pestañas
struct TabBarBackground: View {
    @EnvironmentObject var browserState: BrowserState

    var body: some View {
        Rectangle()
            .fill(browserState.isIncognito
                  ? Color(red: 0.10, green: 0.10, blue: 0.12)
                  : Color(NSColor.windowBackgroundColor).opacity(0.95))
            .overlay(
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 1),
                alignment: .bottom
            )
    }
}

