import Foundation
import WebKit

/// Gestiona la traducción de páginas web usando Google Translate (endpoint gratuito gtx)
/// Flujo: detecta idioma → muestra banner → usuario acepta → traduce texto DOM in-place
class TranslationManager: ObservableObject {
    static let shared = TranslationManager()

    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "translationEnabled") }
    }
    @Published var targetLanguage: String {
        didSet { UserDefaults.standard.set(targetLanguage, forKey: "translationTargetLang") }
    }
    @Published var pagesTranslated: Int {
        didSet { UserDefaults.standard.set(pagesTranslated, forKey: "pagesTranslated") }
    }

    /// Estado actual de traducción para la tab activa
    @Published var showTranslationBanner: Bool = false
    @Published var detectedLanguage: String = ""
    @Published var isTranslating: Bool = false
    @Published var currentTabTranslated: Bool = false

    /// Idiomas soportados con nombres legibles
    static let supportedLanguages: [(code: String, name: String)] = [
        ("es", "Español"), ("en", "English"), ("fr", "Français"),
        ("de", "Deutsch"), ("it", "Italiano"), ("pt", "Português"),
        ("ja", "日本語"), ("ko", "한국어"), ("zh", "中文"),
        ("ru", "Русский"), ("ar", "العربية"), ("hi", "हिन्दी"),
        ("nl", "Nederlands"), ("pl", "Polski"), ("tr", "Türkçe"),
        ("sv", "Svenska"), ("da", "Dansk"), ("no", "Norsk"),
        ("fi", "Suomi"), ("el", "Ελληνικά"), ("he", "עברית"),
        ("th", "ไทย"), ("vi", "Tiếng Việt"), ("id", "Bahasa Indonesia"),
        ("ms", "Bahasa Melayu"), ("uk", "Українська"), ("cs", "Čeština"),
        ("ro", "Română"), ("hu", "Magyar"), ("ca", "Català")
    ]

    private init() {
        self.isEnabled = UserDefaults.standard.object(forKey: "translationEnabled") as? Bool ?? true
        self.targetLanguage = UserDefaults.standard.string(forKey: "translationTargetLang")
            ?? Locale.current.language.languageCode?.identifier ?? "es"
        self.pagesTranslated = UserDefaults.standard.integer(forKey: "pagesTranslated")
    }

    func resetCount() {
        pagesTranslated = 0
    }

    static func languageName(for code: String) -> String {
        supportedLanguages.first(where: { $0.code == code })?.name ?? code
    }

    // MARK: - Language Detection

    /// Script JS que detecta idioma de la página.
    /// Prioridad: 1) atributo lang del HTML, 2) meta content-language, 3) texto visible para API
    static let detectLanguageScript: String = """
    (function() {
        // 1. Atributo lang del <html> — la fuente más confiable
        var htmlLang = document.documentElement.lang || '';
        if (htmlLang) {
            // Normalizar: "es-MX" → "es", "pt-BR" → "pt", "en-US" → "en"
            htmlLang = htmlLang.split('-')[0].toLowerCase().trim();
            if (htmlLang.length >= 2 && htmlLang.length <= 3) {
                return 'LANG:' + htmlLang;
            }
        }
        // 2. Meta tag content-language
        var meta = document.querySelector('meta[http-equiv="content-language"]');
        if (meta && meta.content) {
            var metaLang = meta.content.split('-')[0].toLowerCase().trim();
            if (metaLang.length >= 2 && metaLang.length <= 3) {
                return 'LANG:' + metaLang;
            }
        }
        // 3. Fallback: extraer texto visible para detección por API (más texto = mejor precisión)
        const walker = document.createTreeWalker(
            document.body, NodeFilter.SHOW_TEXT, null
        );
        let text = '';
        let node;
        while ((node = walker.nextNode()) && text.length < 1000) {
            const parent = node.parentElement;
            if (parent && !['SCRIPT','STYLE','NOSCRIPT','CODE','PRE'].includes(parent.tagName)) {
                const t = node.textContent.trim();
                if (t.length > 3) text += t + ' ';
            }
        }
        return text.substring(0, 1000);
    })();
    """

    /// Detecta el idioma: si el script devolvió "LANG:xx", usa eso directamente.
    /// Si no, envía el texto a Google Translate API para detección.
    func detectLanguage(sampleText: String) async -> String? {
        // Si el script ya resolvió el idioma via html lang / meta tag
        if sampleText.hasPrefix("LANG:") {
            let lang = String(sampleText.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
            return lang.isEmpty ? nil : lang
        }

        // Fallback: detección por API con texto de la página
        guard !sampleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let sample = String(sampleText.prefix(500))
        guard let encoded = sample.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=en&dt=t&q=\(encoded)") else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            // Respuesta: [[["translation","original",null,null,10]],null,"detected_lang"]
            if let json = try? JSONSerialization.jsonObject(with: data) as? [Any],
               json.count > 2, let lang = json[2] as? String {
                return lang
            }
        } catch {
            print("⚠️ Translation detect error: \(error.localizedDescription)")
        }
        return nil
    }

    // MARK: - Translation

    /// Script JS que traduce todos los nodos de texto visibles en la página
    /// Recibe un diccionario JSON de traducciones {original: traducción}
    static func translatePageScript(translations: String) -> String {
        return """
        (function() {
            const translations = \(translations);
            const walker = document.createTreeWalker(
                document.body, NodeFilter.SHOW_TEXT, null
            );
            let node;
            const nodes = [];
            while ((node = walker.nextNode())) {
                const parent = node.parentElement;
                if (parent && !['SCRIPT','STYLE','NOSCRIPT','CODE','PRE','TEXTAREA','INPUT'].includes(parent.tagName)) {
                    const text = node.textContent.trim();
                    if (text.length > 1) nodes.push(node);
                }
            }
            let replaced = 0;
            for (const n of nodes) {
                const key = n.textContent.trim();
                // Match exacto primero, luego normalizado (colapsar whitespace)
                var translation = translations[key];
                if (!translation) {
                    const normalized = key.replace(/\\s+/g, ' ');
                    translation = translations[normalized];
                }
                if (translation) {
                    n.textContent = translation;
                    replaced++;
                }
            }
            return replaced;
        })();
        """
    }

    /// Script JS que recolecta todos los textos visibles de la página para traducción batch
    static let collectTextsScript: String = """
    (function() {
        const walker = document.createTreeWalker(
            document.body, NodeFilter.SHOW_TEXT, null
        );
        let node;
        const texts = [];
        const seen = new Set();
        while ((node = walker.nextNode())) {
            const parent = node.parentElement;
            if (parent && !['SCRIPT','STYLE','NOSCRIPT','CODE','PRE','TEXTAREA','INPUT'].includes(parent.tagName)) {
                const text = node.textContent.trim();
                if (text.length > 1 && text.length < 5000 && !seen.has(text)) {
                    seen.add(text);
                    texts.push(text);
                }
            }
        }
        return JSON.stringify(texts);
    })();
    """

    /// Separador para concatenar textos en un solo request (Google lo respeta como límite de frase)
    private static let batchSeparator = "\n\n"

    /// Traduce un array de textos usando Google Translate.
    /// Concatena múltiples textos en un solo POST para velocidad (como Chrome).
    /// Cada batch junta textos hasta ~4KB, enviados como un solo request.
    func translateTexts(_ texts: [String], from sourceLang: String, to targetLang: String) async -> [String: String] {
        var translations: [String: String] = [:]

        // Agrupar textos en batches por tamaño (~4KB cada uno para no exceder límites)
        var batches: [[(index: Int, text: String)]] = []
        var currentBatch: [(index: Int, text: String)] = []
        var currentSize = 0
        let maxBatchSize = 4000

        for (i, text) in texts.enumerated() {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let textSize = trimmed.utf8.count
            if currentSize + textSize > maxBatchSize && !currentBatch.isEmpty {
                batches.append(currentBatch)
                currentBatch = []
                currentSize = 0
            }
            currentBatch.append((index: i, text: trimmed))
            currentSize += textSize + Self.batchSeparator.utf8.count
        }
        if !currentBatch.isEmpty { batches.append(currentBatch) }

        // Traducir cada batch con un solo POST request
        for batch in batches {
            let combined = batch.map(\.text).joined(separator: Self.batchSeparator)

            let urlString = "https://translate.googleapis.com/translate_a/single?client=gtx&sl=\(sourceLang)&tl=\(targetLang)&dt=t"
            guard let url = URL(string: urlString) else { continue }

            var request = URLRequest(url: url, timeoutInterval: 15)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            let bodyString = "q=\(combined.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
            request.httpBody = bodyString.data(using: .utf8)

            do {
                let (data, _) = try await URLSession.shared.data(for: request)
                if let json = try? JSONSerialization.jsonObject(with: data) as? [Any],
                   let sentences = json.first as? [Any] {
                    // Google devuelve segmentos traducidos — reconstruir y separar por nuestro separador
                    var fullTranslation = ""
                    for sentence in sentences {
                        if let parts = sentence as? [Any], let t = parts.first as? String {
                            fullTranslation += t
                        }
                    }
                    // Dividir la respuesta concatenada de vuelta a textos individuales
                    let translatedParts = fullTranslation.components(separatedBy: Self.batchSeparator)
                    for (i, part) in translatedParts.enumerated() where i < batch.count {
                        let trimmedPart = part.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmedPart.isEmpty {
                            translations[batch[i].text] = trimmedPart
                        }
                    }
                }
            } catch {
                print("⚠️ Translation batch error: \(error.localizedDescription)")
            }

            // Pequeño delay entre batches
            if batches.count > 1 {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }
        }

        return translations
    }

    /// Traduce la página completa en un WKWebView
    @MainActor
    func translatePage(webView: WKWebView, from sourceLang: String) async {
        guard !isTranslating else { return }
        isTranslating = true

        do {
            // 0. Guardar textos originales para "Ver original"
            let _ = try await webView.evaluateJavaScript(Self.saveOriginalsScript)

            // 1. Recolectar textos de la página
            let result = try await webView.evaluateJavaScript(Self.collectTextsScript)
            guard let jsonString = result as? String,
                  let jsonData = jsonString.data(using: .utf8),
                  let texts = try? JSONSerialization.jsonObject(with: jsonData) as? [String],
                  !texts.isEmpty else {
                isTranslating = false
                return
            }

            print("🌐 Traduciendo \(texts.count) fragmentos de \(sourceLang) → \(targetLanguage)")

            // 2. Traducir todos los textos
            let translations = await translateTexts(texts, from: sourceLang, to: targetLanguage)

            guard !translations.isEmpty else {
                isTranslating = false
                return
            }

            // 3. Inyectar traducciones en la página
            let translationsJSON = try JSONSerialization.data(withJSONObject: translations)
            let translationsStr = String(data: translationsJSON, encoding: .utf8) ?? "{}"
            let script = Self.translatePageScript(translations: translationsStr)

            let replaced = try await webView.evaluateJavaScript(script)
            let count = replaced as? Int ?? 0

            print("🌐 ✅ \(count) fragmentos reemplazados")

            currentTabTranslated = true
            showTranslationBanner = false
            pagesTranslated += 1
            isTranslating = false
        } catch {
            print("⚠️ Translation error: \(error.localizedDescription)")
            isTranslating = false
        }
    }

    /// Script JS que guarda los textos originales antes de traducir (para "Ver original")
    static let saveOriginalsScript: String = """
    (function() {
        if (window._maiOriginalTexts) return; // Ya guardados
        window._maiOriginalTexts = [];
        const walker = document.createTreeWalker(
            document.body, NodeFilter.SHOW_TEXT, null
        );
        let node;
        while ((node = walker.nextNode())) {
            const parent = node.parentElement;
            if (parent && !['SCRIPT','STYLE','NOSCRIPT','CODE','PRE','TEXTAREA','INPUT'].includes(parent.tagName)) {
                const text = node.textContent.trim();
                if (text.length > 1) {
                    window._maiOriginalTexts.push({node: node, text: node.textContent});
                }
            }
        }
        return window._maiOriginalTexts.length;
    })();
    """

    /// Script JS que restaura los textos originales
    static let restoreOriginalsScript: String = """
    (function() {
        if (!window._maiOriginalTexts) return 0;
        let restored = 0;
        for (const item of window._maiOriginalTexts) {
            try {
                if (item.node && item.node.parentNode) {
                    item.node.textContent = item.text;
                    restored++;
                }
            } catch(e) {}
        }
        window._maiOriginalTexts = null;
        return restored;
    })();
    """

    /// Restaura la página al idioma original
    @MainActor
    func restoreOriginal(webView: WKWebView) async {
        do {
            let result = try await webView.evaluateJavaScript(Self.restoreOriginalsScript)
            let count = result as? Int ?? 0
            print("🌐 Restaurados \(count) textos originales")
            currentTabTranslated = false
            showTranslationBanner = true // Mostrar banner de nuevo por si quiere re-traducir
        } catch {
            print("⚠️ Restore error: \(error.localizedDescription)")
        }
    }

    /// Resetea estado al cambiar de tab o navegar
    func resetState() {
        showTranslationBanner = false
        detectedLanguage = ""
        isTranslating = false
        currentTabTranslated = false
    }
}
