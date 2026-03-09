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

    /// Script JS que extrae texto de la página para detectar idioma
    static let detectLanguageScript: String = """
    (function() {
        // Extraer texto visible (máx 500 chars para detección rápida)
        const walker = document.createTreeWalker(
            document.body, NodeFilter.SHOW_TEXT, null
        );
        let text = '';
        let node;
        while ((node = walker.nextNode()) && text.length < 500) {
            const parent = node.parentElement;
            if (parent && !['SCRIPT','STYLE','NOSCRIPT','CODE','PRE'].includes(parent.tagName)) {
                const t = node.textContent.trim();
                if (t.length > 3) text += t + ' ';
            }
        }
        return text.substring(0, 500);
    })();
    """

    /// Detecta el idioma de un texto usando Google Translate API
    func detectLanguage(sampleText: String) async -> String? {
        guard !sampleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let sample = String(sampleText.prefix(200))
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
                if (translations[key]) {
                    n.textContent = n.textContent.replace(key, translations[key]);
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

    /// Traduce un array de textos usando Google Translate (en batches)
    func translateTexts(_ texts: [String], from sourceLang: String, to targetLang: String) async -> [String: String] {
        var translations: [String: String] = [:]
        let batchSize = 20 // Google acepta múltiples `q` params

        for batchStart in stride(from: 0, to: texts.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, texts.count)
            let batch = Array(texts[batchStart..<batchEnd])

            // Construir URL con múltiples q= params
            var components = URLComponents(string: "https://translate.googleapis.com/translate_a/t")!
            components.queryItems = [
                URLQueryItem(name: "client", value: "gtx"),
                URLQueryItem(name: "sl", value: sourceLang),
                URLQueryItem(name: "tl", value: targetLang),
                URLQueryItem(name: "dt", value: "t")
            ]
            for text in batch {
                components.queryItems?.append(URLQueryItem(name: "q", value: text))
            }

            guard let url = components.url else { continue }

            do {
                let (data, _) = try await URLSession.shared.data(from: url)

                // Respuesta para múltiples q: [["traducción1"], ["traducción2"], ...]
                // O para un solo q: [["traducción"]]
                if let json = try? JSONSerialization.jsonObject(with: data) as? [Any] {
                    if batch.count == 1 {
                        // Single: [["traducción"]]  o  [[["traducción","original"]]]
                        if let first = json.first {
                            if let arr = first as? [Any], let text = arr.first as? String {
                                translations[batch[0]] = text
                            } else if let text = first as? String {
                                translations[batch[0]] = text
                            }
                        }
                    } else {
                        // Multiple: [["trad1"], ["trad2"], ...]
                        for (i, item) in json.enumerated() where i < batch.count {
                            if let arr = item as? [String], let translated = arr.first {
                                translations[batch[i]] = translated
                            } else if let arr = item as? [Any], let translated = arr.first as? String {
                                translations[batch[i]] = translated
                            }
                        }
                    }
                }
            } catch {
                print("⚠️ Translation batch error: \(error.localizedDescription)")
            }

            // Pequeño delay entre batches para no saturar API
            if batchEnd < texts.count {
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

    /// Resetea estado al cambiar de tab o navegar
    func resetState() {
        showTranslationBanner = false
        detectedLanguage = ""
        isTranslating = false
        currentTabTranslated = false
    }
}
