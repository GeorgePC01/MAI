import Foundation
import WebKit

/// Niveles de ahorro de RAM
enum RAMSaverLevel: String, CaseIterable, Codable {
    case off = "Desactivado"
    case standard = "Estándar"      // ~25-35% ahorro - lazy loading, sin fonts web, sin autoplay
    case aggressive = "Agresivo"    // ~50-65% ahorro - sin imágenes, sin third-party, suppress rendering
    case windows98 = "Windows 98"   // ~70-80% ahorro - sin JS, sin CSS, solo texto

    var icon: String {
        switch self {
        case .off: return "memorychip"
        case .standard: return "leaf"
        case .aggressive: return "bolt.shield"
        case .windows98: return "desktopcomputer"
        }
    }

    var description: String {
        switch self {
        case .off: return "Sin restricciones de RAM"
        case .standard: return "Ahorro ~25-35% — Lazy loading, sin fonts web, sin autoplay"
        case .aggressive: return "Ahorro ~50-65% — Sin imágenes, sin third-party, sin fonts"
        case .windows98: return "Ahorro ~70-80% — Solo texto, sin JS/CSS/imágenes ⚠️"
        }
    }

    var compatibilityWarning: String? {
        switch self {
        case .off, .standard: return nil
        case .aggressive: return "Sitios sin imágenes. Formularios y login funcionan."
        case .windows98: return "⚠️ Muchos sitios no funcionarán (Gmail, YouTube, apps web). Solo útil para leer artículos y documentación."
        }
    }
}

/// Manager singleton para modo de ahorro de RAM
class RAMSaverManager: ObservableObject {
    static let shared = RAMSaverManager()

    /// Nivel global (aplica a tabs nuevas y existentes sin nivel propio)
    @Published var globalLevel: RAMSaverLevel = .off {
        didSet { saveSettings() }
    }

    /// Niveles por tab (override del global)
    @Published var tabLevels: [UUID: RAMSaverLevel] = [:]

    // Compiled WKContentRuleLists por nivel
    private var standardRuleList: WKContentRuleList?
    private var aggressiveRuleList: WKContentRuleList?

    private let settingsURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("MAI/ram_saver_settings.json")
    }()

    private init() {
        loadSettings()
        compileRuleLists()
    }

    // MARK: - Public API

    /// Obtener nivel efectivo para un tab (tab override > global)
    func effectiveLevel(for tabId: UUID) -> RAMSaverLevel {
        return tabLevels[tabId] ?? globalLevel
    }

    /// Establecer nivel por tab
    func setLevel(_ level: RAMSaverLevel, for tabId: UUID) {
        if level == globalLevel {
            tabLevels.removeValue(forKey: tabId)
        } else {
            tabLevels[tabId] = level
        }
    }

    /// Limpiar nivel de tab (vuelve al global)
    func clearTabLevel(for tabId: UUID) {
        tabLevels.removeValue(forKey: tabId)
    }

    /// Aplicar modo ahorro a un WKWebView existente (inyección JS)
    func apply(to webView: WKWebView, tabId: UUID) {
        let level = effectiveLevel(for: tabId)
        guard level != .off else { return }

        // Remover reglas previas de RAM saver
        removeRuleLists(from: webView)

        // Agregar reglas de contenido según nivel
        switch level {
        case .off:
            break
        case .standard:
            if let rules = standardRuleList {
                webView.configuration.userContentController.add(rules)
            }
            webView.evaluateJavaScript(Self.standardScript, completionHandler: nil)
        case .aggressive:
            if let rules = standardRuleList {
                webView.configuration.userContentController.add(rules)
            }
            if let rules = aggressiveRuleList {
                webView.configuration.userContentController.add(rules)
            }
            webView.evaluateJavaScript(Self.aggressiveScript, completionHandler: nil)
        case .windows98:
            if let rules = standardRuleList {
                webView.configuration.userContentController.add(rules)
            }
            if let rules = aggressiveRuleList {
                webView.configuration.userContentController.add(rules)
            }
            webView.evaluateJavaScript(Self.windows98Script, completionHandler: nil)
        }
    }

    /// Remover modo ahorro de un WKWebView
    func removeRuleLists(from webView: WKWebView) {
        if let rules = standardRuleList {
            webView.configuration.userContentController.remove(rules)
        }
        if let rules = aggressiveRuleList {
            webView.configuration.userContentController.remove(rules)
        }
    }

    /// Configurar WKWebViewConfiguration según nivel (para tabs nuevas)
    func configure(_ config: WKWebViewConfiguration, level: RAMSaverLevel) {
        switch level {
        case .off:
            break
        case .standard:
            config.mediaTypesRequiringUserActionForPlayback = [.video, .audio]
            if let rules = standardRuleList {
                config.userContentController.add(rules)
            }
            config.userContentController.addUserScript(WKUserScript(
                source: Self.standardScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: false
            ))
        case .aggressive:
            config.mediaTypesRequiringUserActionForPlayback = [.video, .audio]
            config.suppressesIncrementalRendering = true
            if let rules = standardRuleList {
                config.userContentController.add(rules)
            }
            if let rules = aggressiveRuleList {
                config.userContentController.add(rules)
            }
            config.userContentController.addUserScript(WKUserScript(
                source: Self.aggressiveScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: false
            ))
        case .windows98:
            config.mediaTypesRequiringUserActionForPlayback = [.video, .audio]
            config.suppressesIncrementalRendering = true
            let prefs = WKWebpagePreferences()
            prefs.allowsContentJavaScript = false
            config.defaultWebpagePreferences = prefs
            if let rules = standardRuleList {
                config.userContentController.add(rules)
            }
            if let rules = aggressiveRuleList {
                config.userContentController.add(rules)
            }
            config.userContentController.addUserScript(WKUserScript(
                source: Self.windows98Script,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            ))
        }
    }

    // MARK: - WKContentRuleList Compilation

    private func compileRuleLists() {
        let store = WKContentRuleListStore.default()!

        // Standard: bloquear fonts web y autoplay media
        let standardRules: [[String: Any]] = [
            [
                "trigger": ["url-filter": ".*", "resource-type": ["font"]],
                "action": ["type": "block"]
            ]
        ]
        if let json = try? JSONSerialization.data(withJSONObject: standardRules),
           let jsonStr = String(data: json, encoding: .utf8) {
            store.compileContentRuleList(forIdentifier: "mai-ramsaver-standard", encodedContentRuleList: jsonStr) { [weak self] list, _ in
                self?.standardRuleList = list
            }
        }

        // Aggressive: bloquear imágenes, fonts, media, third-party
        let aggressiveRules: [[String: Any]] = [
            [
                "trigger": ["url-filter": ".*", "resource-type": ["image"]],
                "action": ["type": "block"]
            ],
            [
                "trigger": ["url-filter": ".*", "resource-type": ["media"]],
                "action": ["type": "block"]
            ],
            [
                "trigger": ["url-filter": ".*", "resource-type": ["popup"]],
                "action": ["type": "block"]
            ]
        ]
        if let json = try? JSONSerialization.data(withJSONObject: aggressiveRules),
           let jsonStr = String(data: json, encoding: .utf8) {
            store.compileContentRuleList(forIdentifier: "mai-ramsaver-aggressive", encodedContentRuleList: jsonStr) { [weak self] list, _ in
                self?.aggressiveRuleList = list
            }
        }
    }

    // MARK: - JavaScript Scripts

    /// Estándar: lazy loading forzado + limpieza de iframes innecesarios
    static let standardScript = """
    (function() {
        if (window._maiRAMSaver) return;
        window._maiRAMSaver = 'standard';

        // Forzar lazy loading en todas las imágenes
        document.querySelectorAll('img').forEach(function(img) {
            img.loading = 'lazy';
            img.decoding = 'async';
        });

        // Observar imágenes nuevas y forzar lazy loading
        var observer = new MutationObserver(function(mutations) {
            mutations.forEach(function(m) {
                m.addedNodes.forEach(function(node) {
                    if (node.tagName === 'IMG') {
                        node.loading = 'lazy';
                        node.decoding = 'async';
                    }
                    if (node.querySelectorAll) {
                        node.querySelectorAll('img').forEach(function(img) {
                            img.loading = 'lazy';
                            img.decoding = 'async';
                        });
                    }
                });
            });
        });
        observer.observe(document.body || document.documentElement, { childList: true, subtree: true });

        // Remover iframes no visibles (ads, trackers)
        document.querySelectorAll('iframe').forEach(function(iframe) {
            var rect = iframe.getBoundingClientRect();
            if (rect.width < 5 || rect.height < 5) {
                iframe.remove();
            }
        });

        // Pausar videos/audio que no estén en viewport
        document.querySelectorAll('video, audio').forEach(function(media) {
            media.preload = 'none';
            media.autoplay = false;
            media.pause();
        });
    })();
    """

    /// Agresivo: remover imágenes pesadas + deshabilitar animaciones CSS
    static let aggressiveScript = """
    (function() {
        if (window._maiRAMSaver) return;
        window._maiRAMSaver = 'aggressive';

        // Remover todas las imágenes de fondo CSS
        document.querySelectorAll('*').forEach(function(el) {
            var style = getComputedStyle(el);
            if (style.backgroundImage && style.backgroundImage !== 'none') {
                el.style.backgroundImage = 'none';
            }
        });

        // Remover SVGs pesados (>5KB inline)
        document.querySelectorAll('svg').forEach(function(svg) {
            if (svg.outerHTML.length > 5000) {
                svg.remove();
            }
        });

        // Remover iframes
        document.querySelectorAll('iframe').forEach(function(iframe) { iframe.remove(); });

        // Remover videos y canvas
        document.querySelectorAll('video, canvas').forEach(function(el) { el.remove(); });

        // Deshabilitar animaciones CSS
        var style = document.createElement('style');
        style.textContent = '*, *::before, *::after { animation: none !important; transition: none !important; }';
        document.head.appendChild(style);

        // Lazy load agresivo: descargar imágenes solo cuando estén en viewport
        document.querySelectorAll('img').forEach(function(img) {
            img.loading = 'lazy';
            img.decoding = 'async';
        });

        // Pausar todos los medios
        document.querySelectorAll('video, audio').forEach(function(media) {
            media.pause();
            media.src = '';
            media.load();
        });

        // Limpiar Service Workers (liberan memoria)
        if (navigator.serviceWorker) {
            navigator.serviceWorker.getRegistrations().then(function(registrations) {
                registrations.forEach(function(reg) { reg.unregister(); });
            });
        }
    })();
    """

    /// Windows 98: modo texto puro, solo contenido esencial
    static let windows98Script = """
    (function() {
        if (window._maiRAMSaver) return;
        window._maiRAMSaver = 'windows98';

        // Remover todos los scripts (ya no ejecutarán con JS deshabilitado en config, pero por si acaso)
        document.querySelectorAll('script, noscript').forEach(function(el) { el.remove(); });

        // Remover medios
        document.querySelectorAll('img, video, audio, iframe, canvas, svg, picture, source, object, embed')
            .forEach(function(el) { el.remove(); });

        // Remover todos los estilos existentes
        document.querySelectorAll('style, link[rel="stylesheet"]').forEach(function(el) { el.remove(); });

        // Remover elementos decorativos
        document.querySelectorAll('[role="banner"], [role="complementary"], [role="contentinfo"], footer, aside, nav')
            .forEach(function(el) {
                // Mantener nav principal si tiene links importantes
                if (el.tagName === 'NAV' && el.querySelectorAll('a').length > 10) return;
                el.style.display = 'none';
            });

        // Aplicar estilo Windows 98 minimalista
        var w98style = document.createElement('style');
        w98style.textContent = [
            '* { font-family: "Lucida Grande", "Tahoma", "MS Sans Serif", sans-serif !important; ',
            '    font-size: 13px !important; line-height: 1.5 !important; ',
            '    color: #000 !important; background: #c0c0c0 !important; ',
            '    border-radius: 0 !important; box-shadow: none !important; ',
            '    animation: none !important; transition: none !important; }',
            'body { max-width: 800px !important; margin: 8px auto !important; padding: 8px !important; background: #fff !important; }',
            'a { color: #00f !important; text-decoration: underline !important; }',
            'a:visited { color: #800080 !important; }',
            'h1, h2, h3, h4, h5, h6 { color: #000080 !important; font-weight: bold !important; }',
            'h1 { font-size: 18px !important; }',
            'h2 { font-size: 16px !important; }',
            'h3 { font-size: 14px !important; }',
            'input, textarea, select { background: #fff !important; border: 2px inset #c0c0c0 !important; padding: 2px !important; }',
            'button, input[type="submit"] { background: #c0c0c0 !important; border: 2px outset #c0c0c0 !important; padding: 2px 8px !important; cursor: pointer !important; }',
            'button:active, input[type="submit"]:active { border-style: inset !important; }',
            'table { border-collapse: collapse !important; }',
            'td, th { border: 1px solid #808080 !important; padding: 4px !important; }',
            'pre, code { background: #e0e0e0 !important; font-family: "Courier New", monospace !important; padding: 4px !important; }',
            'hr { border: 1px inset #c0c0c0 !important; }'
        ].join('\\n');
        document.head.appendChild(w98style);

        // Limpiar Service Workers
        if (navigator.serviceWorker) {
            navigator.serviceWorker.getRegistrations().then(function(registrations) {
                registrations.forEach(function(reg) { reg.unregister(); });
            });
        }
    })();
    """

    // MARK: - Persistence

    private func saveSettings() {
        let data: [String: String] = ["globalLevel": globalLevel.rawValue]
        if let json = try? JSONEncoder().encode(data) {
            try? json.write(to: settingsURL)
        }
    }

    private func loadSettings() {
        guard let data = try? Data(contentsOf: settingsURL),
              let dict = try? JSONDecoder().decode([String: String].self, from: data),
              let levelStr = dict["globalLevel"],
              let level = RAMSaverLevel(rawValue: levelStr) else { return }
        globalLevel = level
    }
}
