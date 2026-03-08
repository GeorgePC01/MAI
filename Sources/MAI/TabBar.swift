import SwiftUI
import AppKit
import WebKit

/// Ventana flotante que muestra preview de tab durante tear-off drag
class TabDragPreviewWindow: NSPanel {
    static let shared = TabDragPreviewWindow()

    private let imageView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let faviconView = NSImageView()

    private init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        level = .floating
        hasShadow = true
        ignoresMouseEvents = true

        // Container con esquinas redondeadas
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 200))
        container.wantsLayer = true
        container.layer?.cornerRadius = 10
        container.layer?.masksToBounds = true
        container.layer?.borderColor = NSColor.separatorColor.cgColor
        container.layer?.borderWidth = 1

        // Fondo
        let bg = NSView(frame: container.bounds)
        bg.wantsLayer = true
        bg.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        bg.autoresizingMask = [.width, .height]
        container.addSubview(bg)

        // Header con favicon + título
        let header = NSView(frame: NSRect(x: 0, y: 170, width: 280, height: 30))
        header.wantsLayer = true
        header.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        faviconView.frame = NSRect(x: 8, y: 7, width: 16, height: 16)
        faviconView.imageScaling = .scaleProportionallyUpOrDown
        header.addSubview(faviconView)

        titleLabel.frame = NSRect(x: 30, y: 5, width: 240, height: 20)
        titleLabel.font = .systemFont(ofSize: 11)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        header.addSubview(titleLabel)
        container.addSubview(header)

        // Preview image
        imageView.frame = NSRect(x: 0, y: 0, width: 280, height: 170)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.autoresizingMask = [.width, .height]
        container.addSubview(imageView)

        contentView = container
    }

    func show(tab: Tab, at point: NSPoint) {
        titleLabel.stringValue = tab.title
        faviconView.image = tab.favicon ?? NSImage(systemSymbolName: "globe", accessibilityDescription: nil)

        // Capturar snapshot del webView si existe
        if let webView = tab.webView {
            let config = WKSnapshotConfiguration()
            webView.takeSnapshot(with: config) { [weak self] image, _ in
                DispatchQueue.main.async {
                    self?.imageView.image = image
                }
            }
        } else {
            imageView.image = nil
        }

        updatePosition(at: point)
        alphaValue = 0
        orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            animator().alphaValue = 0.95
        }
    }

    func updatePosition(at point: NSPoint) {
        // Centrar horizontalmente bajo el cursor, offset vertical
        setFrameOrigin(NSPoint(x: point.x - 140, y: point.y - 220))
    }

    func dismiss() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            animator().alphaValue = 0
        }, completionHandler: {
            self.orderOut(nil)
            self.imageView.image = nil
        })
    }
}

/// Barra de pestañas del navegador
struct TabBar: View {
    @EnvironmentObject var browserState: BrowserState
    @State private var hoveredTab: UUID?
    @State private var draggedTabId: UUID?
    @State private var dragOffset: CGFloat = 0
    @State private var dragVerticalOffset: CGFloat = 0
    @State private var tabFrames: [UUID: CGRect] = [:]
    @State private var isTearingOff: Bool = false

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
                            onSelect: {
                                if tab.isSuspended {
                                    browserState.resumeTab(tab)
                                }
                                browserState.selectTab(at: index)
                            },
                            onClose: { browserState.closeTab(at: index) }
                        )
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(
                                    key: TabFramePreference.self,
                                    value: [tab.id: geo.frame(in: .named("tabbar"))]
                                )
                            }
                        )
                        .offset(x: draggedTabId == tab.id ? dragOffset : 0,
                                y: draggedTabId == tab.id ? dragVerticalOffset : 0)
                        .zIndex(draggedTabId == tab.id ? 1 : 0)
                        .opacity(draggedTabId == tab.id ? 0.85 : 1.0)
                        .scaleEffect(draggedTabId == tab.id ? 1.05 : 1.0)
                        .animation(.easeInOut(duration: 0.15), value: draggedTabId)
                        .onHover { isHovered in
                            hoveredTab = isHovered ? tab.id : nil
                        }
                        .gesture(
                            DragGesture(minimumDistance: 8, coordinateSpace: .global)
                                .onChanged { value in
                                    if draggedTabId == nil {
                                        draggedTabId = tab.id
                                    }
                                    dragOffset = value.translation.width
                                    dragVerticalOffset = value.translation.height

                                    let inTearZone = abs(dragVerticalOffset) > 40

                                    if inTearZone && !isTearingOff {
                                        // Entró en zona de tear-off/merge: mostrar preview
                                        isTearingOff = true
                                        TabDragPreviewWindow.shared.show(tab: tab, at: NSEvent.mouseLocation)
                                    } else if inTearZone && isTearingOff {
                                        // Mover preview con el cursor
                                        TabDragPreviewWindow.shared.updatePosition(at: NSEvent.mouseLocation)
                                    } else if !inTearZone && isTearingOff {
                                        // Volvió al tab bar: ocultar preview
                                        isTearingOff = false
                                        TabDragPreviewWindow.shared.dismiss()
                                    }

                                    // Solo reordenar si no está en zona de tear-off
                                    if !inTearZone {
                                        checkSwap(draggedId: tab.id)
                                    }
                                }
                                .onEnded { value in
                                    TabDragPreviewWindow.shared.dismiss()
                                    let verticalDistance = value.translation.height
                                    let screenPoint = NSEvent.mouseLocation

                                    if abs(verticalDistance) > 60 {
                                        // Primero intentar merge: ¿soltó sobre el tab bar de otra ventana?
                                        if let targetState = WindowManager.shared.browserState(at: screenPoint, excluding: browserState) {
                                            WindowManager.shared.mergeTab(tab, into: targetState, from: browserState)
                                        } else if browserState.tabs.count > 1 {
                                            // Tear off: nueva ventana
                                            WindowManager.shared.openNewWindow(
                                                withTab: tab,
                                                from: browserState,
                                                at: screenPoint
                                            )
                                        }
                                    }
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        dragOffset = 0
                                        dragVerticalOffset = 0
                                        draggedTabId = nil
                                        isTearingOff = false
                                    }
                                }
                        )
                        .simultaneousGesture(
                            TapGesture().onEnded {
                                if tab.isSuspended {
                                    browserState.resumeTab(tab)
                                }
                                if let idx = browserState.tabs.firstIndex(where: { $0.id == tab.id }) {
                                    browserState.selectTab(at: idx)
                                }
                            }
                        )
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
            .coordinateSpace(name: "tabbar")
            .onPreferenceChange(TabFramePreference.self) { frames in
                tabFrames = frames
            }
            .frame(height: 38)
        }
        .background(TabBarBackground())
        .colorScheme(browserState.isIncognito ? .dark : .light)
    }

    /// Detecta si la tab arrastrada cruzó sobre otra y las intercambia
    private func checkSwap(draggedId: UUID) {
        guard let draggedFrame = tabFrames[draggedId] else { return }
        let draggedCenter = draggedFrame.midX + dragOffset

        guard let fromIndex = browserState.tabs.firstIndex(where: { $0.id == draggedId }) else { return }

        for (id, frame) in tabFrames {
            if id == draggedId { continue }
            guard let toIndex = browserState.tabs.firstIndex(where: { $0.id == id }) else { continue }

            // Si el centro de la tab arrastrada cruza el centro de otra tab
            if draggedCenter > frame.midX - frame.width * 0.3 && draggedCenter < frame.midX + frame.width * 0.3 {
                if fromIndex != toIndex {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        browserState.tabs.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
                        if let newIndex = browserState.tabs.firstIndex(where: { $0.id == draggedId }) {
                            browserState.currentTabIndex = newIndex
                        }
                    }
                    // Ajustar offset para compensar el movimiento del array
                    let direction: CGFloat = toIndex > fromIndex ? -1 : 1
                    dragOffset += direction * draggedFrame.width
                    break
                }
            }
        }
    }
}

/// PreferenceKey para trackear posiciones de tabs
struct TabFramePreference: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
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

            Button(action: { browserState.toggleChromeCompatMode(tab) }) {
                Label(tab.chromeCompatMode ? "Desactivar Modo Chrome" : "Modo Chrome",
                      systemImage: tab.chromeCompatMode ? "globe.badge.chevron.backward" : "globe.americas")
            }
            .disabled(tab.isSuspended || tab.useChromiumEngine)

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
