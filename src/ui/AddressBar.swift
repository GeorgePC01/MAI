import SwiftUI
import AppKit

/// NSTextField que maneja correctamente el foco cuando hay WKWebView
class FocusableTextField: NSTextField {
    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            // Asegurar que el field editor reciba eventos correctamente
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.window?.makeKey()
                if let editor = self.currentEditor() as? NSTextView {
                    // Seleccionar todo el texto
                    let range = NSRange(location: 0, length: editor.string.count)
                    editor.selectedRanges = [NSValue(range: range)]
                }
            }
        }
        return result
    }

    override func mouseDown(with event: NSEvent) {
        // CRÍTICO: Primero resignar cualquier first responder (especialmente WKWebView)
        if let window = self.window {
            window.makeFirstResponder(nil)
        }

        super.mouseDown(with: event)

        // Forzar foco después del click con delay
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.window?.makeFirstResponder(self)
        }
    }

    // Interceptar key equivalents para asegurar que lleguen correctamente
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) {
            let chars = event.charactersIgnoringModifiers ?? ""
            switch chars.lowercased() {
            case "c":
                if NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self) { return true }
            case "v":
                if NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self) { return true }
            case "x":
                if NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: self) { return true }
            case "a":
                if NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: self) { return true }
            case "z":
                if event.modifierFlags.contains(.shift) {
                    if NSApp.sendAction(Selector(("redo:")), to: nil, from: self) { return true }
                } else {
                    if NSApp.sendAction(Selector(("undo:")), to: nil, from: self) { return true }
                }
            default:
                break
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// Barra de direcciones del navegador
struct AddressBar: View {
    @EnvironmentObject var browserState: BrowserState
    @State private var urlText: String = ""
    @State private var isEditing: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            // Botones de navegación
            NavigationButtons()

            // Campo de URL con fondo
            HStack(spacing: 8) {
                SecurityIndicator(url: urlText)

                URLTextField(
                    text: $urlText,
                    isEditing: $isEditing,
                    onSubmit: navigateToURL
                )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.textBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isEditing ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: isEditing ? 2 : 1)
                    )
            )

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
        isEditing = false
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

/// Campo de URL usando NSTextField nativo
struct URLTextField: NSViewRepresentable {
    @Binding var text: String
    @Binding var isEditing: Bool
    let onSubmit: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let textField = FocusableTextField()
        textField.delegate = context.coordinator
        textField.placeholderString = "Buscar o escribir dirección"
        textField.font = .systemFont(ofSize: 13)
        textField.isBordered = false
        textField.drawsBackground = false
        textField.backgroundColor = .clear
        textField.focusRingType = .none
        textField.isEditable = true
        textField.isSelectable = true
        textField.cell?.isScrollable = true
        textField.cell?.wraps = false
        textField.cell?.usesSingleLineMode = true
        textField.lineBreakMode = .byTruncatingTail

        // Importante: Permitir que el field editor maneje los eventos
        textField.allowsEditingTextAttributes = false

        return textField
    }

    func updateNSView(_ textField: NSTextField, context: Context) {
        if textField.stringValue != text {
            textField.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: URLTextField

        init(_ parent: URLTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let textField = obj.object as? NSTextField else { return }
            DispatchQueue.main.async {
                self.parent.text = textField.stringValue
            }
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            DispatchQueue.main.async {
                self.parent.isEditing = true
            }
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            DispatchQueue.main.async {
                self.parent.isEditing = false
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                // Escape - quitar foco
                control.window?.makeFirstResponder(nil)
                return true
            }
            return false
        }
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

    var body: some View {
        HStack(spacing: 4) {
            Button(action: { /* TODO: Implementar */ }) {
                Image(systemName: "star")
                    .font(.system(size: 14))
            }
            .buttonStyle(NavigationButtonStyle())
            .help("Agregar a favoritos")

            Button(action: { /* TODO: Implementar */ }) {
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
        }
    }
}
