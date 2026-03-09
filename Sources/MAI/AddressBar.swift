import SwiftUI
import AppKit

/// Sugerencia de autocompletado
struct URLSuggestion: Identifiable, Equatable {
    let id = UUID()
    let url: String
    let title: String
    let source: SuggestionSource

    enum SuggestionSource: Equatable {
        case history
        case bookmark
        case search
    }

    var displayIcon: String {
        switch source {
        case .history: return "clock.arrow.circlepath"
        case .bookmark: return "star.fill"
        case .search: return "magnifyingglass"
        }
    }

    var iconColor: Color {
        switch source {
        case .history: return .secondary
        case .bookmark: return .yellow
        case .search: return .blue
        }
    }
}

/// Barra de direcciones del navegador
struct AddressBar: View {
    @EnvironmentObject var browserState: BrowserState
    @State private var urlText: String = ""
    @State private var isEditing: Bool = false
    @FocusState private var isFocused: Bool
    @State private var suggestions: [URLSuggestion] = []
    @State private var showSuggestions: Bool = false
    @State private var selectedSuggestionIndex: Int = -1
    @State private var suggestDebounceTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 8) {
            // Botones de navegación
            NavigationButtons()

            // Campo de URL con sugerencias
            HStack(spacing: 8) {
                SecurityIndicator(url: urlText)

                AddressTextField(
                    text: $urlText,
                    isFocused: $isFocused,
                    onSubmit: {
                        if selectedSuggestionIndex >= 0 && selectedSuggestionIndex < suggestions.count {
                            selectSuggestion(suggestions[selectedSuggestionIndex])
                        } else {
                            navigateToURL()
                        }
                    },
                    onArrowDown: {
                        if showSuggestions && !suggestions.isEmpty {
                            selectedSuggestionIndex = min(selectedSuggestionIndex + 1, suggestions.count - 1)
                        }
                    },
                    onArrowUp: {
                        if showSuggestions {
                            selectedSuggestionIndex = max(selectedSuggestionIndex - 1, -1)
                        }
                    },
                    onEscape: {
                        if showSuggestions {
                            showSuggestions = false
                            selectedSuggestionIndex = -1
                        } else {
                            if let window = NSApp.keyWindow {
                                window.makeFirstResponder(nil)
                            }
                        }
                    },
                    onFocusChange: { focused in
                        isEditing = focused
                        if !focused {
                            suggestDebounceTask?.cancel()
                            // Delay para permitir click en sugerencia antes de cerrar
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                showSuggestions = false
                                suggestions = []
                                selectedSuggestionIndex = -1
                            }
                        }
                    }
                )
                    .onChange(of: urlText) { newText in
                        if isEditing {
                            updateSuggestions(for: newText)
                        }
                    }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(browserState.isIncognito
                          ? Color(red: 0.20, green: 0.21, blue: 0.24)
                          : Color(NSColor.textBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isEditing ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: isEditing ? 2 : 1)
                    )
            )
            .contentShape(Rectangle())
            .onTapGesture {
                NSApplication.shared.activate(ignoringOtherApps: true)
                resignWebViewFocus()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    isFocused = true
                }
            }
            .overlay(alignment: .top) {
                // Dropdown de sugerencias — overlay para que no sea recortado por el layout padre
                if showSuggestions && !suggestions.isEmpty {
                    SuggestionsDropdown(
                        suggestions: suggestions,
                        selectedIndex: selectedSuggestionIndex,
                        isIncognito: browserState.isIncognito,
                        onSelect: { suggestion in
                            selectSuggestion(suggestion)
                        }
                    )
                    .offset(y: 38)
                    .zIndex(100)
                }
            }

            // Botones de acción
            ActionButtons()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(browserState.isIncognito
                    ? Color(red: 0.10, green: 0.10, blue: 0.12)
                    : Color(NSColor.windowBackgroundColor))
        .colorScheme(browserState.isIncognito ? .dark : .light)
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
        suggestDebounceTask?.cancel()
        showSuggestions = false
        suggestions = []
        selectedSuggestionIndex = -1
        browserState.navigate(to: urlText)
        isEditing = false
        if let window = NSApp.keyWindow {
            window.makeFirstResponder(nil)
        }
    }

    private func selectSuggestion(_ suggestion: URLSuggestion) {
        suggestDebounceTask?.cancel()
        urlText = suggestion.url
        showSuggestions = false
        suggestions = []
        selectedSuggestionIndex = -1
        browserState.navigate(to: suggestion.url)
        isEditing = false
        if let window = NSApp.keyWindow {
            window.makeFirstResponder(nil)
        }
    }

    private func updateSuggestions(for query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            suggestions = []
            showSuggestions = false
            selectedSuggestionIndex = -1
            suggestDebounceTask?.cancel()
            return
        }

        // Resultados locales inmediatos
        var results: [URLSuggestion] = []
        var seenKeys = Set<String>()

        // Bookmarks (mayor prioridad)
        let bookmarkResults = BookmarksManager.shared.search(query: trimmed)
        for bm in bookmarkResults.prefix(3) {
            let key = bm.url.lowercased()
            if !seenKeys.contains(key) {
                seenKeys.insert(key)
                results.append(URLSuggestion(url: bm.url, title: bm.title, source: .bookmark))
            }
        }

        // Historial
        let historyResults = HistoryManager.shared.search(query: trimmed)
        for entry in historyResults.prefix(5) {
            let key = entry.url.lowercased()
            if !seenKeys.contains(key) {
                seenKeys.insert(key)
                results.append(URLSuggestion(url: entry.url, title: entry.title, source: .history))
            }
        }

        // Mostrar locales inmediatamente
        suggestions = Array(results.prefix(10))
        showSuggestions = !suggestions.isEmpty
        selectedSuggestionIndex = -1

        // Google Suggest con debounce de 200ms (no en incógnito)
        suggestDebounceTask?.cancel()
        if !browserState.isIncognito {
            let currentQuery = trimmed
            let localResults = results
            let localKeys = seenKeys
            suggestDebounceTask = Task {
                try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
                guard !Task.isCancelled else { return }
                // Verificar que el query actual sigue siendo relevante
                let currentText = urlText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard currentText.hasPrefix(currentQuery.lowercased()) || currentQuery.lowercased().hasPrefix(currentText) else { return }
                await fetchGoogleSuggestions(query: currentQuery, localResults: localResults, seenKeys: localKeys)
            }
        }
    }

    @MainActor
    private func fetchGoogleSuggestions(query: String, localResults: [URLSuggestion], seenKeys: Set<String>) async {
        // Chrome Suggest endpoint — client=chrome returns 15 results (vs 8 for chrome-omni)
        let lang = Locale.current.language.languageCode?.identifier ?? "es"
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.google.com/complete/search?client=chrome&q=\(encoded)&hl=\(lang)") else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)

            // Google puede responder en Latin-1 (ej: ñ = 0xF1) — normalizar a UTF-8
            let jsonString: String
            if let utf8 = String(data: data, encoding: .utf8) {
                jsonString = utf8
            } else if let latin1 = String(data: data, encoding: .isoLatin1) {
                jsonString = latin1
            } else {
                return
            }

            guard let jsonData = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [Any],
                  json.count >= 2,
                  let suggestStrings = json[1] as? [String] else { return }

            // Verificar que seguimos editando
            guard isEditing else { return }

            // Parsear tipos (NAVIGATION/QUERY/CALCULATOR) y descripciones
            let descriptions = (json.count >= 3 ? json[2] as? [String] : nil) ?? []
            var suggestTypes: [String] = []
            var relevanceScores: [Int] = []
            if json.count >= 5, let metadata = json[4] as? [String: Any] {
                suggestTypes = metadata["google:suggesttype"] as? [String] ?? []
                relevanceScores = metadata["google:suggestrelevance"] as? [Int] ?? []
            }

            var googleResults: [(suggestion: URLSuggestion, relevance: Int)] = []
            var keys = seenKeys

            for (i, s) in suggestStrings.enumerated() {
                let type = i < suggestTypes.count ? suggestTypes[i] : "QUERY"
                let description = i < descriptions.count ? descriptions[i] : ""
                let relevance = i < relevanceScores.count ? relevanceScores[i] : 500
                let key = s.lowercased()

                guard !keys.contains(key) else { continue }
                keys.insert(key)

                switch type {
                case "NAVIGATION":
                    // URL directa (ej: https://linkedin.com) — mostrar dominio limpio como título
                    let title: String
                    if !description.isEmpty {
                        title = description
                    } else {
                        // Extraer dominio limpio como título
                        var domain = s
                        domain = domain.replacingOccurrences(of: "https://", with: "")
                        domain = domain.replacingOccurrences(of: "http://", with: "")
                        if domain.hasSuffix("/") { domain = String(domain.dropLast()) }
                        title = domain
                    }
                    googleResults.append((
                        URLSuggestion(url: s, title: title, source: .history),
                        relevance
                    ))
                case "CALCULATOR":
                    // Resultado de calculadora (ej: "= 12")
                    googleResults.append((
                        URLSuggestion(url: "https://www.google.com/search?q=\(encoded)", title: "\(query) \(s)", source: .search),
                        relevance + 100 // Priorizar calculadora
                    ))
                default:
                    // QUERY: sugerencia de búsqueda
                    let searchURL = "https://www.google.com/search?q=\(s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s)"
                    googleResults.append((
                        URLSuggestion(url: searchURL, title: s, source: .search),
                        relevance
                    ))
                }
            }

            // Ordenar por relevancia (Google ya los ordena, pero CALCULATOR tiene boost)
            googleResults.sort { $0.relevance > $1.relevance }

            // Combinar: locales primero (máx 3), luego Google por relevancia
            var combined = Array(localResults.prefix(3))
            let remainingSlots = 10 - combined.count
            combined.append(contentsOf: googleResults.prefix(remainingSlots).map(\.suggestion))

            suggestions = combined
            showSuggestions = !suggestions.isEmpty
        } catch {
            // Fallo silencioso — las sugerencias locales ya están mostrándose
        }
    }

    private func resignWebViewFocus() {
        if let window = NSApp.keyWindow {
            window.makeFirstResponder(nil)
        }
    }
}

/// Dropdown de sugerencias de autocompletado
struct SuggestionsDropdown: View {
    let suggestions: [URLSuggestion]
    let selectedIndex: Int
    let isIncognito: Bool
    let onSelect: (URLSuggestion) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                SuggestionRow(
                    suggestion: suggestion,
                    isSelected: index == selectedIndex,
                    isIncognito: isIncognito
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    onSelect(suggestion)
                }

                if index < suggestions.count - 1 {
                    Divider()
                        .padding(.horizontal, 8)
                }
            }
        }
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isIncognito
                      ? Color(red: 0.18, green: 0.19, blue: 0.22)
                      : Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
}

/// Fila individual de sugerencia
struct SuggestionRow: View {
    let suggestion: URLSuggestion
    let isSelected: Bool
    let isIncognito: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: suggestion.displayIcon)
                .font(.system(size: 12))
                .foregroundColor(suggestion.iconColor)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(suggestion.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .foregroundColor(.primary)

                Text(cleanURL(suggestion.url))
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
                .padding(.horizontal, 4)
        )
    }

    /// Limpia URL para mostrar sin protocolo
    private func cleanURL(_ url: String) -> String {
        var clean = url
        clean = clean.replacingOccurrences(of: "https://", with: "")
        clean = clean.replacingOccurrences(of: "http://", with: "")
        if clean.hasSuffix("/") { clean = String(clean.dropLast()) }
        return clean
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

/// NSTextField wrapper que intercepta flechas arriba/abajo y escape para el autocompletado
struct AddressTextField: NSViewRepresentable {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    var onSubmit: () -> Void
    var onArrowDown: () -> Void
    var onArrowUp: () -> Void
    var onEscape: () -> Void
    var onFocusChange: ((Bool) -> Void)?

    func makeNSView(context: Context) -> KeyInterceptingTextField {
        let textField = KeyInterceptingTextField()
        textField.delegate = context.coordinator
        textField.font = NSFont.systemFont(ofSize: 13)
        textField.isBordered = false
        textField.backgroundColor = .clear
        textField.focusRingType = .none
        textField.placeholderString = "Buscar o escribir dirección"
        textField.cell?.lineBreakMode = .byTruncatingTail
        textField.onArrowDown = onArrowDown
        textField.onArrowUp = onArrowUp
        textField.onEscape = onEscape
        return textField
    }

    func updateNSView(_ textField: KeyInterceptingTextField, context: Context) {
        if textField.stringValue != text {
            textField.stringValue = text
        }
        textField.onArrowDown = onArrowDown
        textField.onArrowUp = onArrowUp
        textField.onEscape = onEscape
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: AddressTextField

        init(_ parent: AddressTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            if let textField = notification.object as? NSTextField {
                parent.text = textField.stringValue
            }
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            parent.onFocusChange?(true)
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            parent.onFocusChange?(false)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            if commandSelector == #selector(NSResponder.moveDown(_:)) {
                parent.onArrowDown()
                return true
            }
            if commandSelector == #selector(NSResponder.moveUp(_:)) {
                parent.onArrowUp()
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onEscape()
                return true
            }
            return false
        }
    }
}

/// NSTextField que intercepta teclas de flecha y escape
class KeyInterceptingTextField: NSTextField {
    var onArrowDown: (() -> Void)?
    var onArrowUp: (() -> Void)?
    var onEscape: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 125: // Flecha abajo
            onArrowDown?()
        case 126: // Flecha arriba
            onArrowUp?()
        case 53: // Escape
            onEscape?()
        default:
            super.keyDown(with: event)
        }
    }
}
