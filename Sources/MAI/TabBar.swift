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
                }
                .padding(.horizontal, 4)
            }
            .frame(height: 38)

            // Botón nueva pestaña
            Button(action: { browserState.createTab() }) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Color.clear)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Nueva pestaña (Cmd+T)")
            .padding(.trailing, 8)
        }
        .background(TabBarBackground())
    }
}

/// Item individual de pestaña
struct TabItem: View {
    @ObservedObject var tab: Tab
    let isSelected: Bool
    let isHovered: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // Favicon
            if let favicon = tab.favicon {
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
        .background(TabItemBackground(isSelected: isSelected, isHovered: isHovered))
        .cornerRadius(8)
        .onTapGesture {
            onSelect()
        }
    }
}

/// Fondo del item de pestaña
struct TabItemBackground: View {
    let isSelected: Bool
    let isHovered: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(backgroundColor)
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color(NSColor.controlBackgroundColor)
        } else if isHovered {
            return Color.gray.opacity(0.15)
        } else {
            return Color.clear
        }
    }
}

/// Fondo de la barra de pestañas
struct TabBarBackground: View {
    var body: some View {
        Rectangle()
            .fill(Color(NSColor.windowBackgroundColor).opacity(0.95))
            .overlay(
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 1),
                alignment: .bottom
            )
    }
}

