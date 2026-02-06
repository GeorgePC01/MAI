import SwiftUI
import AppKit

/// Barra de direcciones del navegador
struct AddressBar: View {
    @EnvironmentObject var browserState: BrowserState
    @State private var urlText: String = ""
    @State private var isEditing: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            // Botones de navegación
            NavigationButtons()

            // Campo de URL
            URLTextField(
                text: $urlText,
                isEditing: $isEditing,
                onSubmit: navigateToURL
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
            // Atrás
            Button(action: { browserState.goBack() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(NavigationButtonStyle())
            .disabled(!(browserState.currentTab?.canGoBack ?? false))
            .help("Atrás (Cmd+[)")

            // Adelante
            Button(action: { browserState.goForward() }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(NavigationButtonStyle())
            .disabled(!(browserState.currentTab?.canGoForward ?? false))
            .help("Adelante (Cmd+])")

            // Recargar / Detener
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

/// Campo de URL usando NSTextField nativo para mejor input handling
struct URLTextField: NSViewRepresentable {
    @Binding var text: String
    @Binding var isEditing: Bool
    let onSubmit: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.delegate = context.coordinator
        textField.placeholderString = "Buscar o escribir dirección"
        textField.font = .systemFont(ofSize: 13)
        textField.isBordered = false
        textField.backgroundColor = .clear
        textField.focusRingType = .none
        textField.cell?.isScrollable = true
        textField.cell?.wraps = false
        textField.lineBreakMode = .byTruncatingTail
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
            parent.text = textField.stringValue
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            parent.isEditing = true
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            parent.isEditing = false
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
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
        url.hasPrefix("about:") || url.hasPrefix("file://")
    }

    var body: some View {
        Image(systemName: iconName)
            .font(.system(size: 12))
            .foregroundColor(iconColor)
    }

    private var iconName: String {
        if isLocal {
            return "doc"
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
            // Agregar a favoritos
            Button(action: { /* TODO: Implementar */ }) {
                Image(systemName: "star")
                    .font(.system(size: 14))
            }
            .buttonStyle(NavigationButtonStyle())
            .help("Agregar a favoritos")

            // Compartir
            Button(action: { /* TODO: Implementar */ }) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 14))
            }
            .buttonStyle(NavigationButtonStyle())
            .help("Compartir")

            // Sidebar toggle
            Button(action: { browserState.showSidebar.toggle() }) {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 14))
            }
            .buttonStyle(NavigationButtonStyle())
            .help("Mostrar/ocultar barra lateral (Cmd+Shift+S)")
        }
    }
}
