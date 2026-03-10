import SwiftUI
import WebKit
import SceneKit

// MARK: - DevTools Color Theme (Chrome DevTools + VS Code Dark+)

/// Colores centralizados para DevTools — basados en Chrome DevTools dark theme y VS Code Dark+
enum DT {
    private static var theme: DevToolsState.DevToolsTheme {
        DevToolsState.shared.theme
    }

    // Backgrounds
    static var bg: Color {
        switch theme {
        case .chromeDark: return Color(red: 0.125, green: 0.129, blue: 0.141)
        case .chromeLight: return Color(red: 1.000, green: 1.000, blue: 1.000)  // #ffffff
        case .monokai:    return Color(red: 0.153, green: 0.157, blue: 0.133)  // #272822
        case .solarizedDark: return Color(red: 0.000, green: 0.169, blue: 0.212) // #002b36
        case .oneDark:    return Color(red: 0.157, green: 0.173, blue: 0.204)  // #282c34
        case .nord:       return Color(red: 0.180, green: 0.204, blue: 0.251)  // #2e3440
        }
    }
    static var toolbarBg: Color {
        switch theme {
        case .chromeDark: return Color(red: 0.161, green: 0.165, blue: 0.176)
        case .chromeLight: return Color(red: 0.949, green: 0.949, blue: 0.949)  // #f1f3f4
        case .monokai:    return Color(red: 0.204, green: 0.208, blue: 0.176)  // #343530
        case .solarizedDark: return Color(red: 0.027, green: 0.212, blue: 0.259) // #073642
        case .oneDark:    return Color(red: 0.200, green: 0.216, blue: 0.247)  // #333842
        case .nord:       return Color(red: 0.231, green: 0.259, blue: 0.322)  // #3b4252
        }
    }
    static var inputBg: Color {
        switch theme {
        case .chromeDark: return Color(red: 0.102, green: 0.102, blue: 0.118)
        case .chromeLight: return Color(red: 1.000, green: 1.000, blue: 1.000)  // #ffffff
        case .monokai:    return Color(red: 0.118, green: 0.122, blue: 0.098)  // #1e1f19
        case .solarizedDark: return Color(red: 0.000, green: 0.129, blue: 0.165) // #00212b
        case .oneDark:    return Color(red: 0.125, green: 0.137, blue: 0.161)  // #21232a
        case .nord:       return Color(red: 0.145, green: 0.165, blue: 0.208)  // #252a34
        }
    }
    static var hoverBg: Color {
        switch theme {
        case .chromeDark: return Color(red: 0.165, green: 0.176, blue: 0.180)
        case .chromeLight: return Color(red: 0.922, green: 0.933, blue: 0.945)  // #ebeeef
        case .monokai:    return Color(red: 0.220, green: 0.224, blue: 0.192)  // #383930
        case .solarizedDark: return Color(red: 0.027, green: 0.212, blue: 0.259)
        case .oneDark:    return Color(red: 0.220, green: 0.235, blue: 0.267)  // #383e4a
        case .nord:       return Color(red: 0.263, green: 0.298, blue: 0.369)  // #434c5e
        }
    }
    static var selectedBg: Color {
        switch theme {
        case .chromeDark: return Color(red: 0.024, green: 0.180, blue: 0.286)
        case .chromeLight: return Color(red: 0.820, green: 0.902, blue: 1.000)  // #d1e6ff
        case .monokai:    return Color(red: 0.259, green: 0.231, blue: 0.114)  // #423b1d
        case .solarizedDark: return Color(red: 0.027, green: 0.212, blue: 0.259)
        case .oneDark:    return Color(red: 0.173, green: 0.220, blue: 0.310)  // #2c384f
        case .nord:       return Color(red: 0.263, green: 0.298, blue: 0.369)  // #434c5e
        }
    }
    static var errorBg: Color {
        switch theme {
        case .chromeDark: return Color(red: 0.161, green: 0.000, blue: 0.000)
        case .chromeLight: return Color(red: 1.000, green: 0.937, blue: 0.937)  // #ffefef
        case .monokai:    return Color(red: 0.200, green: 0.063, blue: 0.063)
        case .solarizedDark: return Color(red: 0.161, green: 0.035, blue: 0.012)
        case .oneDark:    return Color(red: 0.200, green: 0.067, blue: 0.067)
        case .nord:       return Color(red: 0.192, green: 0.082, blue: 0.082)
        }
    }
    static var warnBg: Color {
        switch theme {
        case .chromeDark: return Color(red: 0.200, green: 0.169, blue: 0.000)
        case .chromeLight: return Color(red: 1.000, green: 0.984, blue: 0.929)  // #fffbed
        case .monokai:    return Color(red: 0.200, green: 0.180, blue: 0.050)
        case .solarizedDark: return Color(red: 0.180, green: 0.160, blue: 0.020)
        case .oneDark:    return Color(red: 0.200, green: 0.180, blue: 0.050)
        case .nord:       return Color(red: 0.200, green: 0.180, blue: 0.060)
        }
    }

    // Text — Chrome Dark usa blanco brillante para máxima legibilidad
    static var text: Color {
        switch theme {
        case .chromeDark: return Color(red: 0.941, green: 0.941, blue: 0.941)  // #f0f0f0 — blanco brillante
        case .chromeLight: return Color(red: 0.125, green: 0.129, blue: 0.141)  // #202124 — negro suave
        case .monokai:    return Color(red: 0.973, green: 0.973, blue: 0.949)  // #f8f8f2
        case .solarizedDark: return Color(red: 0.514, green: 0.580, blue: 0.588) // #839496
        case .oneDark:    return Color(red: 0.671, green: 0.698, blue: 0.749)  // #abb2bf
        case .nord:       return Color(red: 0.847, green: 0.871, blue: 0.914)  // #d8dee9
        }
    }
    static var textSecondary: Color {
        switch theme {
        case .chromeDark: return Color(red: 0.729, green: 0.745, blue: 0.765)  // #babcc3 — más claro
        case .chromeLight: return Color(red: 0.373, green: 0.388, blue: 0.412)  // #5f6368
        case .monokai:    return Color(red: 0.659, green: 0.631, blue: 0.502)  // #a8a180
        case .solarizedDark: return Color(red: 0.396, green: 0.482, blue: 0.514) // #657b83
        case .oneDark:    return Color(red: 0.490, green: 0.522, blue: 0.565)  // #7d8590
        case .nord:       return Color(red: 0.612, green: 0.663, blue: 0.718)  // #9ca9b7
        }
    }
    static var textMuted: Color {
        switch theme {
        case .chromeDark: return Color(red: 0.502, green: 0.518, blue: 0.545)  // #808490 — más visible
        case .chromeLight: return Color(red: 0.600, green: 0.616, blue: 0.639)  // #999da3
        case .monokai:    return Color(red: 0.459, green: 0.443, blue: 0.369)  // #75715e
        case .solarizedDark: return Color(red: 0.345, green: 0.431, blue: 0.459) // #586e75
        case .oneDark:    return Color(red: 0.361, green: 0.388, blue: 0.439)  // #5c6370
        case .nord:       return Color(red: 0.298, green: 0.337, blue: 0.416)  // #4c566a
        }
    }

    // Syntax highlighting
    static var tag: Color {
        switch theme {
        case .chromeDark: return Color(red: 0.365, green: 0.690, blue: 0.843)
        case .chromeLight: return Color(red: 0.533, green: 0.133, blue: 0.533)  // #881388 — púrpura HTML tag
        case .monokai:    return Color(red: 0.400, green: 0.851, blue: 0.937)  // #66d9ef
        case .solarizedDark: return Color(red: 0.149, green: 0.545, blue: 0.824) // #268bd2
        case .oneDark:    return Color(red: 0.380, green: 0.686, blue: 0.937)  // #61afef
        case .nord:       return Color(red: 0.506, green: 0.631, blue: 0.757)  // #81a1c1
        }
    }
    static var attr: Color {
        switch theme {
        case .chromeDark: return Color(red: 0.608, green: 0.733, blue: 0.863)
        case .chromeLight: return Color(red: 0.533, green: 0.333, blue: 0.067)  // #885511 — marrón atributo
        case .monokai:    return Color(red: 0.651, green: 0.886, blue: 0.180)  // #a6e22e
        case .solarizedDark: return Color(red: 0.514, green: 0.580, blue: 0.588)
        case .oneDark:    return Color(red: 0.835, green: 0.537, blue: 0.192)  // #d19a66
        case .nord:       return Color(red: 0.557, green: 0.737, blue: 0.733)  // #8fbcbb
        }
    }
    static var string: Color {
        switch theme {
        case .chromeDark: return Color(red: 0.808, green: 0.569, blue: 0.471)
        case .chromeLight: return Color(red: 0.125, green: 0.306, blue: 0.780)  // #1a4ec5 — azul string
        case .monokai:    return Color(red: 0.902, green: 0.859, blue: 0.455)  // #e6db74
        case .solarizedDark: return Color(red: 0.165, green: 0.631, blue: 0.596) // #2aa198
        case .oneDark:    return Color(red: 0.596, green: 0.765, blue: 0.475)  // #98c379
        case .nord:       return Color(red: 0.639, green: 0.745, blue: 0.549)  // #a3be8c
        }
    }
    static var keyword: Color {
        switch theme {
        case .chromeDark: return Color(red: 0.773, green: 0.525, blue: 0.753)
        case .chromeLight: return Color(red: 0.667, green: 0.067, blue: 0.467)  // #aa1177 — magenta keyword
        case .monokai:    return Color(red: 0.976, green: 0.149, blue: 0.447)  // #f92672
        case .solarizedDark: return Color(red: 0.522, green: 0.600, blue: 0.000) // #859900
        case .oneDark:    return Color(red: 0.776, green: 0.471, blue: 0.867)  // #c678dd
        case .nord:       return Color(red: 0.706, green: 0.557, blue: 0.678)  // #b48ead
        }
    }
    static var number: Color {
        switch theme {
        case .chromeDark: return Color(red: 0.710, green: 0.808, blue: 0.659)
        case .chromeLight: return Color(red: 0.039, green: 0.310, blue: 0.647)  // #094fa3 — azul número
        case .monokai:    return Color(red: 0.682, green: 0.506, blue: 0.843)  // #ae81ff
        case .solarizedDark: return Color(red: 0.165, green: 0.631, blue: 0.596)
        case .oneDark:    return Color(red: 0.827, green: 0.580, blue: 0.376)  // #d19a60
        case .nord:       return Color(red: 0.706, green: 0.557, blue: 0.678)  // #b48ead
        }
    }
    static var fnName: Color {
        switch theme {
        case .chromeDark: return Color(red: 0.863, green: 0.863, blue: 0.667)
        case .chromeLight: return Color(red: 0.533, green: 0.067, blue: 0.067)  // #880011 — rojo función
        case .monokai:    return Color(red: 0.651, green: 0.886, blue: 0.180)  // #a6e22e
        case .solarizedDark: return Color(red: 0.149, green: 0.545, blue: 0.824)
        case .oneDark:    return Color(red: 0.380, green: 0.686, blue: 0.937)  // #61afef
        case .nord:       return Color(red: 0.557, green: 0.737, blue: 0.733)  // #8fbcbb
        }
    }
    static var property: Color {
        switch theme {
        case .chromeDark: return Color(red: 0.612, green: 0.863, blue: 0.996)
        case .chromeLight: return Color(red: 0.533, green: 0.133, blue: 0.533)  // #881388
        case .monokai:    return Color(red: 0.400, green: 0.851, blue: 0.937)
        case .solarizedDark: return Color(red: 0.149, green: 0.545, blue: 0.824)
        case .oneDark:    return Color(red: 0.878, green: 0.400, blue: 0.412)  // #e06c75
        case .nord:       return Color(red: 0.506, green: 0.631, blue: 0.757)
        }
    }
    static var comment: Color {
        switch theme {
        case .chromeDark: return Color(red: 0.416, green: 0.600, blue: 0.333)
        case .chromeLight: return Color(red: 0.420, green: 0.467, blue: 0.400)  // #6b7765 — verde apagado
        case .monokai:    return Color(red: 0.459, green: 0.443, blue: 0.369)  // #75715e
        case .solarizedDark: return Color(red: 0.345, green: 0.431, blue: 0.459) // #586e75
        case .oneDark:    return Color(red: 0.361, green: 0.388, blue: 0.439)  // #5c6370
        case .nord:       return Color(red: 0.298, green: 0.337, blue: 0.416)  // #4c566a
        }
    }
    static var typeName: Color {
        switch theme {
        case .chromeDark: return Color(red: 0.306, green: 0.788, blue: 0.690)
        case .chromeLight: return Color(red: 0.000, green: 0.467, blue: 0.533)  // #007788 — teal tipo
        case .monokai:    return Color(red: 0.400, green: 0.851, blue: 0.937)
        case .solarizedDark: return Color(red: 0.796, green: 0.294, blue: 0.086) // #cb4b16
        case .oneDark:    return Color(red: 0.878, green: 0.749, blue: 0.396)  // #e0bf65
        case .nord:       return Color(red: 0.557, green: 0.737, blue: 0.733)
        }
    }
    static var selector: Color {
        switch theme {
        case .chromeDark: return Color(red: 0.843, green: 0.729, blue: 0.490)
        case .chromeLight: return Color(red: 0.533, green: 0.133, blue: 0.533)  // #881388
        case .monokai:    return Color(red: 0.976, green: 0.149, blue: 0.447)
        case .solarizedDark: return Color(red: 0.522, green: 0.600, blue: 0.000)
        case .oneDark:    return Color(red: 0.776, green: 0.471, blue: 0.867)
        case .nord:       return Color(red: 0.706, green: 0.557, blue: 0.678)
        }
    }

    // Console levels
    static var logText: Color {
        switch theme {
        case .chromeDark: return Color(red: 0.910, green: 0.918, blue: 0.929)
        case .chromeLight: return Color(red: 0.125, green: 0.129, blue: 0.141)  // #202124
        case .monokai:    return Color(red: 0.973, green: 0.973, blue: 0.949)
        case .solarizedDark: return Color(red: 0.514, green: 0.580, blue: 0.588)
        case .oneDark:    return Color(red: 0.671, green: 0.698, blue: 0.749)
        case .nord:       return Color(red: 0.847, green: 0.871, blue: 0.914)
        }
    }
    static var warnText: Color {
        switch theme {
        case .chromeDark: return Color(red: 0.976, green: 0.671, blue: 0.000)
        case .chromeLight: return Color(red: 0.600, green: 0.400, blue: 0.000)  // #996600
        case .monokai:    return Color(red: 0.902, green: 0.859, blue: 0.455)
        case .solarizedDark: return Color(red: 0.710, green: 0.537, blue: 0.000) // #b58900
        case .oneDark:    return Color(red: 0.878, green: 0.749, blue: 0.396)
        case .nord:       return Color(red: 0.922, green: 0.796, blue: 0.545)  // #ebcb8b
        }
    }
    static var errorText: Color {
        switch theme {
        case .chromeDark: return Color(red: 0.949, green: 0.545, blue: 0.510)
        case .chromeLight: return Color(red: 0.800, green: 0.067, blue: 0.067)  // #cc1111
        case .monokai:    return Color(red: 0.976, green: 0.149, blue: 0.447)
        case .solarizedDark: return Color(red: 0.863, green: 0.196, blue: 0.184) // #dc322f
        case .oneDark:    return Color(red: 0.878, green: 0.400, blue: 0.412)
        case .nord:       return Color(red: 0.749, green: 0.380, blue: 0.416)  // #bf616a
        }
    }
    static var infoText: Color {
        switch theme {
        case .chromeDark: return Color(red: 0.541, green: 0.706, blue: 0.973)
        case .chromeLight: return Color(red: 0.133, green: 0.400, blue: 0.733)  // #2266bb
        case .monokai:    return Color(red: 0.400, green: 0.851, blue: 0.937)
        case .solarizedDark: return Color(red: 0.149, green: 0.545, blue: 0.824)
        case .oneDark:    return Color(red: 0.380, green: 0.686, blue: 0.937)
        case .nord:       return Color(red: 0.506, green: 0.631, blue: 0.757)
        }
    }
    static var debugText: Color {
        switch theme {
        case .chromeDark: return Color(red: 0.604, green: 0.627, blue: 0.651)
        case .chromeLight: return Color(red: 0.467, green: 0.467, blue: 0.467)  // #777777
        case .monokai:    return Color(red: 0.459, green: 0.443, blue: 0.369)
        case .solarizedDark: return Color(red: 0.345, green: 0.431, blue: 0.459)
        case .oneDark:    return Color(red: 0.361, green: 0.388, blue: 0.439)
        case .nord:       return Color(red: 0.298, green: 0.337, blue: 0.416)
        }
    }

    // Status/badges
    static var success: Color {
        switch theme {
        case .chromeDark: return Color(red: 0.451, green: 0.788, blue: 0.569)
        case .chromeLight: return Color(red: 0.133, green: 0.545, blue: 0.133)  // #228b22
        case .monokai:    return Color(red: 0.651, green: 0.886, blue: 0.180)
        case .solarizedDark: return Color(red: 0.522, green: 0.600, blue: 0.000)
        case .oneDark:    return Color(red: 0.596, green: 0.765, blue: 0.475)
        case .nord:       return Color(red: 0.639, green: 0.745, blue: 0.549)
        }
    }
    static var error: Color {
        switch theme {
        case .chromeDark: return Color(red: 0.945, green: 0.298, blue: 0.298)
        case .chromeLight: return Color(red: 0.800, green: 0.133, blue: 0.133)  // #cc2222
        case .monokai:    return Color(red: 0.976, green: 0.149, blue: 0.447)
        case .solarizedDark: return Color(red: 0.863, green: 0.196, blue: 0.184)
        case .oneDark:    return Color(red: 0.878, green: 0.400, blue: 0.412)
        case .nord:       return Color(red: 0.749, green: 0.380, blue: 0.416)
        }
    }
    static var warning: Color {
        switch theme {
        case .chromeDark: return Color(red: 0.800, green: 0.655, blue: 0.000)
        case .chromeLight: return Color(red: 0.667, green: 0.467, blue: 0.000)  // #aa7700
        case .monokai:    return Color(red: 0.902, green: 0.859, blue: 0.455)
        case .solarizedDark: return Color(red: 0.710, green: 0.537, blue: 0.000)
        case .oneDark:    return Color(red: 0.878, green: 0.749, blue: 0.396)
        case .nord:       return Color(red: 0.922, green: 0.796, blue: 0.545)
        }
    }
    static var info: Color {
        switch theme {
        case .chromeDark: return Color(red: 0.216, green: 0.580, blue: 1.000)
        case .chromeLight: return Color(red: 0.133, green: 0.400, blue: 0.800)  // #2266cc
        case .monokai:    return Color(red: 0.400, green: 0.851, blue: 0.937)
        case .solarizedDark: return Color(red: 0.149, green: 0.545, blue: 0.824)
        case .oneDark:    return Color(red: 0.380, green: 0.686, blue: 0.937)
        case .nord:       return Color(red: 0.506, green: 0.631, blue: 0.757)
        }
    }

    // Borders
    static var border: Color {
        switch theme {
        case .chromeDark: return Color(red: 0.235, green: 0.251, blue: 0.263)
        case .chromeLight: return Color(red: 0.820, green: 0.835, blue: 0.851)  // #d1d5d9
        case .monokai:    return Color(red: 0.298, green: 0.298, blue: 0.259)  // #4c4c42
        case .solarizedDark: return Color(red: 0.027, green: 0.212, blue: 0.259)
        case .oneDark:    return Color(red: 0.247, green: 0.267, blue: 0.306)  // #3e4451
        case .nord:       return Color(red: 0.263, green: 0.298, blue: 0.369)  // #434c5e
        }
    }
    static var borderLight: Color {
        switch theme {
        case .chromeDark: return Color(red: 0.286, green: 0.298, blue: 0.314)
        case .chromeLight: return Color(red: 0.878, green: 0.890, blue: 0.902)  // #e0e3e7
        case .monokai:    return Color(red: 0.349, green: 0.349, blue: 0.310)
        case .solarizedDark: return Color(red: 0.067, green: 0.259, blue: 0.318)
        case .oneDark:    return Color(red: 0.298, green: 0.318, blue: 0.361)
        case .nord:       return Color(red: 0.298, green: 0.337, blue: 0.416)
        }
    }

    // Links
    static var link: Color {
        switch theme {
        case .chromeDark: return Color(red: 0.541, green: 0.706, blue: 0.973)
        case .chromeLight: return Color(red: 0.063, green: 0.369, blue: 0.733)  // #105ebb
        case .monokai:    return Color(red: 0.400, green: 0.851, blue: 0.937)
        case .solarizedDark: return Color(red: 0.149, green: 0.545, blue: 0.824)
        case .oneDark:    return Color(red: 0.380, green: 0.686, blue: 0.937)
        case .nord:       return Color(red: 0.506, green: 0.631, blue: 0.757)
        }
    }
}

// MARK: - DevTools Panel Principal

struct DevToolsView: View {
    @EnvironmentObject var browserState: BrowserState
    @StateObject private var devToolsState = DevToolsState.shared

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar con tabs
            DevToolsToolbar(selectedTab: $devToolsState.selectedTab)

            Divider()

            // Contenido del panel seleccionado
            switch devToolsState.selectedTab {
            case .console:
                ConsolePanel()
            case .elements:
                ElementsPanel()
            case .network:
                NetworkPanel()
            case .performance:
                PerformancePanel()
            case .memory:
                MemoryPanel()
            case .lighthouse:
                LighthousePanel()
            case .device:
                DeviceEmulationPanel()
            case .storage:
                StoragePanel()
            case .sources:
                SourcesPanel()
            case .cssDebug:
                CSSDebugPanel()
            case .dom3d:
                DOM3DPanel()
            case .accessibility:
                AccessibilityPanel()
            case .debugger:
                CDPDebuggerPanel()
            }
        }
        .background(DT.bg)
        .environment(\.colorScheme, DevToolsState.shared.theme.isDark ? .dark : .light)
        .onAppear {
            injectDevToolsScripts()
        }
    }

    private func injectDevToolsScripts() {
        guard let webView = browserState.currentTab?.webView else { return }
        // Inyectar interceptores de console.log y network
        webView.evaluateJavaScript(DevToolsScripts.consoleInterceptor) { _, _ in }
        webView.evaluateJavaScript(DevToolsScripts.networkInterceptor) { _, _ in }
    }
}

// MARK: - DevTools State

class DevToolsState: ObservableObject {
    static let shared = DevToolsState()

    enum DockPosition: String, CaseIterable {
        case bottom = "Abajo"
        case right = "Derecha"
        case left = "Izquierda"

        var icon: String {
            switch self {
            case .bottom: return "rectangle.bottomhalf.inset.filled"
            case .right: return "rectangle.righthalf.inset.filled"
            case .left: return "rectangle.lefthalf.inset.filled"
            }
        }
    }

    enum DevToolsTheme: String, CaseIterable {
        case chromeDark = "Chrome Dark"
        case chromeLight = "Chrome Light"
        case monokai = "Monokai"
        case solarizedDark = "Solarized Dark"
        case oneDark = "One Dark"
        case nord = "Nord"

        var icon: String { "paintpalette" }
        var isDark: Bool { self != .chromeLight }
    }

    enum Tab: String, CaseIterable {
        case console = "Consola"
        case elements = "Elementos"
        case network = "Red"
        case performance = "Rendimiento"
        case memory = "Memoria"
        case lighthouse = "Lighthouse"
        case device = "Dispositivo"
        case storage = "Almacenamiento"
        case sources = "Fuentes"
        case cssDebug = "CSS"
        case dom3d = "3D"
        case accessibility = "Accesibilidad"
        case debugger = "Debugger"

        var icon: String {
            switch self {
            case .console: return "chevron.left.forwardslash.chevron.right"
            case .elements: return "rectangle.3.group"
            case .network: return "network"
            case .performance: return "gauge.with.dots.needle.33percent"
            case .memory: return "memorychip"
            case .lighthouse: return "speedometer"
            case .device: return "iphone.and.arrow.forward"
            case .storage: return "cylinder"
            case .sources: return "doc.text"
            case .cssDebug: return "paintbrush"
            case .dom3d: return "cube"
            case .accessibility: return "accessibility"
            case .debugger: return "ant"
            }
        }
    }

    @Published var selectedTab: Tab = .console

    /// True cuando DevTools está en dock lateral (derecha/izquierda) — paneles deben adaptarse
    var isCompact: Bool { dockPosition != .bottom }

    @Published var dockPosition: DockPosition {
        didSet {
            UserDefaults.standard.set(dockPosition.rawValue, forKey: "devtools_dock_position")
            // Al cambiar a lateral, ajustar tamaño inicial a ~52% de la ventana
            if dockPosition != .bottom {
                let width = windowWidth > 500 ? windowWidth : (NSScreen.main?.visibleFrame.width ?? 1440)
                devToolsSize = width * 0.54
            } else if devToolsSize > 500 {
                devToolsSize = 300 // Reset a tamaño razonable para bottom
            }
        }
    }
    @Published var devToolsSize: CGFloat = 300 // height for bottom, width for left/right
    var windowWidth: CGFloat = 1200 // se actualiza con GeometryReader (no @Published para evitar loop)

    @Published var theme: DevToolsTheme {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: "devtools_theme"); objectWillChange.send() }
    }

    private init() {
        let savedDock = UserDefaults.standard.string(forKey: "devtools_dock_position") ?? DockPosition.bottom.rawValue
        self.dockPosition = DockPosition(rawValue: savedDock) ?? .bottom
        let savedTheme = UserDefaults.standard.string(forKey: "devtools_theme") ?? DevToolsTheme.chromeLight.rawValue
        self.theme = DevToolsTheme(rawValue: savedTheme) ?? .chromeLight
    }

    // Console state
    @Published var consoleLogs: [ConsoleLogEntry] = []
    @Published var consoleFilter: ConsoleLogLevel? = nil
    @Published var commandHistory: [String] = []
    var commandHistoryIndex: Int = -1
    @Published var preserveLog: Bool = false

    // Elements state
    @Published var domTree: [DOMNode] = []
    @Published var selectedElement: DOMNode?
    @Published var elementStyles: [CSSProperty] = []
    @Published var elementComputedStyles: [CSSProperty] = []

    // Network state
    @Published var networkEntries: [NetworkEntry] = []
    @Published var networkFilter: String = ""

    // Storage state
    @Published var cookies: [StorageItem] = []
    @Published var localStorageItems: [StorageItem] = []
    @Published var sessionStorageItems: [StorageItem] = []

    // CSS Debug state
    @Published var cssIssues: [CSSIssue] = []
    @Published var cssIsLoading: Bool = false

    // 3D DOM state
    @Published var dom3DNodes: [DOM3DNode] = []

    // Accessibility state
    @Published var accessibilityIssues: [AccessibilityIssue] = []
    @Published var accessibilityScore: Int = 0
    @Published var accessibilityIsLoading: Bool = false

    // Performance state
    @Published var perfMetrics: PerformanceMetrics?
    @Published var perfIsRecording: Bool = false
    @Published var perfIsLoading: Bool = false
    @Published var perfEntries: [PerfTimelineEntry] = []

    // Memory state
    @Published var memorySnapshots: [MemorySnapshot] = []
    @Published var memoryIsLoading: Bool = false

    // Lighthouse state
    @Published var lighthouseResult: LighthouseResult?
    @Published var lighthouseIsLoading: Bool = false

    // Device emulation state
    @Published var deviceEmulationActive: Bool = false
    @Published var selectedDevice: DeviceProfile = .none

    func clearConsole() {
        consoleLogs.removeAll()
    }

    func clearNetwork() {
        networkEntries.removeAll()
    }

    func addLog(_ entry: ConsoleLogEntry) {
        DispatchQueue.main.async {
            self.consoleLogs.append(entry)
            // Limitar a 1000 entradas
            if self.consoleLogs.count > 1000 {
                self.consoleLogs.removeFirst(self.consoleLogs.count - 1000)
            }
        }
    }

    func addNetworkEntry(_ entry: NetworkEntry) {
        DispatchQueue.main.async {
            // Deduplicar por URL — PerformanceObserver y fetch/XHR pueden reportar lo mismo
            if !self.networkEntries.contains(where: { $0.url == entry.url && $0.type == entry.type }) {
                self.networkEntries.append(entry)
                if self.networkEntries.count > 1000 {
                    self.networkEntries.removeFirst(self.networkEntries.count - 1000)
                }
            }
        }
    }
}

// MARK: - Data Models

struct ConsoleLogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let level: ConsoleLogLevel
    let message: String
    let source: String?
    let line: Int?

    var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: timestamp)
    }
}

enum ConsoleLogLevel: String, CaseIterable {
    case log, info, warn, error, debug, input, output

    // Solo mostrar filtros para los niveles estándar
    static var filterCases: [ConsoleLogLevel] { [.log, .info, .warn, .error, .debug] }

    var color: Color {
        switch self {
        case .log: return DT.logText
        case .info: return DT.infoText
        case .warn: return DT.warnText
        case .error: return DT.errorText
        case .debug: return DT.debugText
        case .input: return DT.infoText
        case .output: return DT.logText
        }
    }

    var icon: String {
        switch self {
        case .log: return ""
        case .info: return "ℹ️"
        case .warn: return "⚠️"
        case .error: return "❌"
        case .debug: return "🔍"
        case .input: return "›"
        case .output: return "←"
        }
    }
}

struct DOMNode: Identifiable {
    let id = UUID()
    let tag: String
    let attributes: [(String, String)]
    let textContent: String?
    var children: [DOMNode]
    var isExpanded: Bool = false
    let depth: Int
    let path: String // CSS selector path for re-querying

    var hasChildren: Bool { !children.isEmpty }

    var openTag: String {
        var result = "<\(tag)"
        for (key, value) in attributes.prefix(3) {
            let truncated = value.count > 40 ? String(value.prefix(40)) + "…" : value
            result += " \(key)=\"\(truncated)\""
        }
        if attributes.count > 3 {
            result += " …"
        }
        result += ">"
        return result
    }
}

struct CSSProperty: Identifiable {
    let id = UUID()
    let name: String
    let value: String
    let source: String?
}

struct NetworkEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let method: String
    let url: String
    let status: Int
    let type: String
    let size: String
    let duration: String
    let initiator: String

    // Waterfall timing (ms desde navigation start)
    let startTime: Int
    let connectEnd: Int
    let requestStart: Int
    let responseStart: Int
    let responseEnd: Int

    var statusColor: Color {
        switch status {
        case 200..<300: return DT.success
        case 300..<400: return DT.infoText
        case 400..<500: return DT.warning
        case 500..<600: return DT.error
        default: return DT.textMuted
        }
    }

    var shortURL: String {
        guard let urlObj = URL(string: url) else { return url }
        let path = urlObj.path
        return path.isEmpty ? urlObj.host ?? url : (urlObj.host ?? "") + path
    }

    /// Nombre corto del recurso (última parte del path, como Chrome)
    var shortName: String {
        guard let urlObj = URL(string: url) else { return url }
        let last = urlObj.lastPathComponent
        if last.isEmpty || last == "/" {
            // Para document: mostrar el path o query
            if let query = urlObj.query, !query.isEmpty {
                let path = urlObj.path
                let pathPart = path.isEmpty ? "" : path
                let full = pathPart + "?" + query
                return String(full.prefix(60))
            }
            return urlObj.host ?? url
        }
        // Incluir query params si existen (truncado)
        if let query = urlObj.query, !query.isEmpty {
            return last + "?" + String(query.prefix(30)) + (query.count > 30 ? "…" : "")
        }
        return last
    }

    /// Tipo formateado para mostrar
    var typeLabel: String {
        switch type.lowercased() {
        case "document", "navigation": return "document"
        case "stylesheet", "css": return "stylesheet"
        case "script": return "script"
        case "xhr", "xmlhttprequest": return "xhr"
        case "fetch": return "fetch"
        case "image", "img": return "image"
        case "font": return "font"
        case "media", "video", "audio": return "media"
        case "websocket": return "websocket"
        case "manifest": return "manifest"
        case "wasm": return "wasm"
        default: return type
        }
    }

    /// Color del tipo
    var typeColor: Color {
        switch type.lowercased() {
        case "document", "navigation": return Color(red: 0.380, green: 0.533, blue: 0.867)
        case "stylesheet", "css": return Color(red: 0.561, green: 0.349, blue: 0.757)
        case "script": return Color(red: 0.933, green: 0.706, blue: 0.275)
        case "xhr", "fetch", "xmlhttprequest": return Color(red: 0.380, green: 0.749, blue: 0.380)
        case "image", "img": return Color(red: 0.216, green: 0.718, blue: 0.718)
        case "font": return Color(red: 0.769, green: 0.467, blue: 0.659)
        case "media", "video", "audio": return Color(red: 0.400, green: 0.773, blue: 0.961)
        default: return DT.textSecondary
        }
    }

    var durationMs: Int {
        return responseEnd - startTime
    }
}

struct StorageItem: Identifiable {
    let id = UUID()
    let key: String
    let value: String
    let domain: String?
    let path: String?
    let expires: String?
}

// MARK: - Toolbar

struct DevToolsToolbar: View {
    @Binding var selectedTab: DevToolsState.Tab
    @EnvironmentObject var browserState: BrowserState
    @ObservedObject private var devToolsState = DevToolsState.shared

    /// Tabs visibles directamente vs en overflow — depende del modo compacto
    var isCompact: Bool { devToolsState.dockPosition != .bottom }

    /// En modo compacto mostramos solo 4 tabs + overflow, en ancho completo mostramos todos
    var visibleTabs: [DevToolsState.Tab] {
        if isCompact {
            // Mostrar las 4 principales + si la seleccionada no está, reemplazar la última
            let primary: [DevToolsState.Tab] = [.console, .elements, .network, .storage]
            if primary.contains(selectedTab) { return primary }
            // Reemplazar storage con la tab seleccionada para que siempre sea visible
            return [.console, .elements, .network, selectedTab]
        }
        return DevToolsState.Tab.allCases.map { $0 }
    }

    var overflowTabs: [DevToolsState.Tab] {
        if !isCompact { return [] }
        return DevToolsState.Tab.allCases.filter { !visibleTabs.contains($0) }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Tabs visibles
            ForEach(visibleTabs, id: \.self) { tab in
                Button(action: { selectedTab = tab }) {
                    HStack(spacing: 3) {
                        Image(systemName: tab.icon)
                            .font(.system(size: isCompact ? 9 : 10))
                        if !isCompact {
                            Text(tab.rawValue)
                                .font(.system(size: 14, weight: selectedTab == tab ? .semibold : .regular))
                        }
                    }
                    .foregroundColor(selectedTab == tab ? DT.text : DT.textSecondary)
                    .padding(.horizontal, isCompact ? 6 : 10)
                    .padding(.vertical, 5)
                    .background(selectedTab == tab ? DT.selectedBg : Color.clear)
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .help(tab.rawValue)
            }

            // Menú overflow (chevron >>) cuando hay tabs ocultas
            if !overflowTabs.isEmpty {
                Menu {
                    ForEach(overflowTabs, id: \.self) { tab in
                        Button(action: { selectedTab = tab }) {
                            Label(tab.rawValue, systemImage: tab.icon)
                        }
                    }
                } label: {
                    Image(systemName: "chevron.right.2")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DT.textSecondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 5)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 24)
                .help("Más paneles")
            }

            Spacer()

            // Selector de tema
            Menu {
                ForEach(DevToolsState.DevToolsTheme.allCases, id: \.self) { theme in
                    Button(action: { devToolsState.theme = theme }) {
                        HStack {
                            Text(theme.rawValue)
                            if devToolsState.theme == theme {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "paintpalette")
                    .font(.system(size: 13))
                    .foregroundColor(DT.textSecondary)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 22)
            .help("Tema de DevTools")

            // Botones de posición de dock
            HStack(spacing: 2) {
                ForEach(DevToolsState.DockPosition.allCases, id: \.self) { position in
                    Button(action: { devToolsState.dockPosition = position }) {
                        Image(systemName: position.icon)
                            .font(.system(size: 13))
                            .foregroundColor(devToolsState.dockPosition == position ? DT.text : DT.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .help(position.rawValue)
                }
            }
            .padding(.horizontal, 4)

            // Botón cerrar
            Button(action: { browserState.showDevTools = false }) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(DT.textSecondary)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 8)
        }
        .padding(.horizontal, isCompact ? 4 : 8)
        .padding(.vertical, 3)
        .background(DT.toolbarBg)
    }
}

// MARK: - Console Panel

struct ConsolePanel: View {
    @EnvironmentObject var browserState: BrowserState
    @StateObject private var devTools = DevToolsState.shared
    @State private var command: String = ""
    @State private var scrollProxy: ScrollViewProxy?

    var filteredLogs: [ConsoleLogEntry] {
        if let filter = devTools.consoleFilter {
            return devTools.consoleLogs.filter { $0.level == filter }
        }
        return devTools.consoleLogs
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filter bar
            HStack(spacing: 6) {
                // Log level filters
                ForEach(ConsoleLogLevel.filterCases, id: \.self) { level in
                    Button(action: {
                        devTools.consoleFilter = devTools.consoleFilter == level ? nil : level
                    }) {
                        Text(level.rawValue.capitalized)
                            .font(.system(size: 13))
                            .foregroundColor(devTools.consoleFilter == level ? level.color : DT.textSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(devTools.consoleFilter == level ? level.color.opacity(0.15) : Color.clear)
                            .cornerRadius(3)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                let errorCount = devTools.consoleLogs.filter { $0.level == .error }.count
                let warnCount = devTools.consoleLogs.filter { $0.level == .warn }.count

                if errorCount > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(DT.error)
                        Text("\(errorCount)")
                            .font(.system(size: 13))
                            .foregroundColor(DT.error)
                    }
                }
                if warnCount > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(DT.warning)
                        Text("\(warnCount)")
                            .font(.system(size: 13))
                            .foregroundColor(DT.warning)
                    }
                }

                Toggle("Preservar", isOn: $devTools.preserveLog)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 13))
                    .controlSize(.mini)

                Button(action: { devTools.clearConsole() }) {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundColor(DT.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Limpiar consola")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(DT.toolbarBg)

            Divider().overlay(DT.border)

            // Log output
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(filteredLogs) { entry in
                            ConsoleLogRow(entry: entry)
                                .id(entry.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(DT.bg)
                .onChange(of: devTools.consoleLogs.count) { _ in
                    if let last = filteredLogs.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            Divider().overlay(DT.border)

            // Input
            ConsoleInput(command: $command) { cmd in
                executeCommand(cmd)
            }
        }
    }

    private func executeCommand(_ cmd: String) {
        devTools.commandHistory.insert(cmd, at: 0)
        if devTools.commandHistory.count > 100 {
            devTools.commandHistory.removeLast()
        }
        devTools.commandHistoryIndex = -1

        // Mostrar el comando del usuario con nivel .input
        devTools.addLog(ConsoleLogEntry(
            timestamp: Date(), level: .input,
            message: cmd, source: nil, line: nil
        ))

        // Script wrapper: serializa el resultado como JSON rico con tipo
        let wrappedJS = """
        (function() {
            try {
                var __r = eval(\(Self.escapeForJS(cmd)));
                if (__r instanceof Promise) {
                    __r.then(function(v) {
                        window.webkit.messageHandlers.maiDevToolsConsole.postMessage(
                            JSON.stringify({level:'log', message:'← ' + __maiStringify(v), source:'Promise'})
                        );
                    }).catch(function(e) {
                        window.webkit.messageHandlers.maiDevToolsConsole.postMessage(
                            JSON.stringify({level:'error', message:'← Promise rejected: ' + (e.message || String(e)), source:'Promise'})
                        );
                    });
                    return '⏳ Promise {<pending>}';
                }
                if (__r instanceof HTMLElement) {
                    return '<' + __r.tagName.toLowerCase() + (__r.id ? '#'+__r.id : '') + (__r.className ? '.'+__r.className.split(' ').join('.') : '') + '>';
                }
                if (__r instanceof NodeList || __r instanceof HTMLCollection) {
                    return __r.constructor.name + '(' + __r.length + ') [' + Array.from(__r).slice(0,5).map(function(n){return '<'+n.tagName.toLowerCase()+'>'}).join(', ') + (__r.length > 5 ? ', …' : '') + ']';
                }
                if (typeof __r === 'function') {
                    return 'ƒ ' + (__r.name || 'anonymous') + '()';
                }
                return __maiStringify(__r);
            } catch(e) {
                throw e;
            }
            function __maiStringify(v, d) {
                d = d || 0;
                if (d > 4) return '…';
                if (v === null) return 'null';
                if (v === undefined) return 'undefined';
                if (typeof v === 'string') return '"' + v + '"';
                if (typeof v === 'number' || typeof v === 'boolean') return String(v);
                if (typeof v === 'symbol') return v.toString();
                if (Array.isArray(v)) {
                    if (v.length === 0) return '[]';
                    var items = v.slice(0,20).map(function(x){return __maiStringify(x,d+1)});
                    return '[' + items.join(', ') + (v.length > 20 ? ', …(+'+(v.length-20)+')' : '') + ']';
                }
                if (typeof v === 'object') {
                    var keys = Object.keys(v);
                    if (keys.length === 0) return '{}';
                    var pairs = keys.slice(0,15).map(function(k){return k+': '+__maiStringify(v[k],d+1)});
                    return '{' + pairs.join(', ') + (keys.length > 15 ? ', …(+'+(keys.length-15)+')' : '') + '}';
                }
                return String(v);
            }
        })()
        """

        browserState.currentTab?.webView?.evaluateJavaScript(wrappedJS) { result, error in
            if let error = error {
                let msg = error.localizedDescription
                    .replacingOccurrences(of: "A JavaScript exception occurred", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                devTools.addLog(ConsoleLogEntry(
                    timestamp: Date(), level: .error,
                    message: "✗ \(msg)", source: "eval", line: nil
                ))
            } else {
                let output: String
                if let result = result {
                    output = Self.formatJSValue(result)
                } else {
                    output = "undefined"
                }
                devTools.addLog(ConsoleLogEntry(
                    timestamp: Date(), level: .output,
                    message: "← \(output)", source: nil, line: nil
                ))
            }
        }
    }

    private static func escapeForJS(_ str: String) -> String {
        let escaped = str
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
        return "`\(escaped)`"
    }

    static func formatJSValue(_ value: Any, depth: Int = 0) -> String {
        if depth > 4 { return "…" }
        if let dict = value as? [String: Any] {
            if dict.isEmpty { return "{}" }
            let entries = dict.prefix(15).map { key, val in
                "\(key): \(formatJSValue(val, depth: depth + 1))"
            }
            let suffix = dict.count > 15 ? ", …(\(dict.count - 15) more)" : ""
            return "{ \(entries.joined(separator: ", "))\(suffix) }"
        }
        if let arr = value as? [Any] {
            if arr.isEmpty { return "[]" }
            let items = arr.prefix(20).map { formatJSValue($0, depth: depth + 1) }
            let suffix = arr.count > 20 ? ", …(\(arr.count - 20) more)" : ""
            return "[\(items.joined(separator: ", "))\(suffix)]"
        }
        if let str = value as? String { return str }
        if let num = value as? NSNumber { return "\(num)" }
        if value is NSNull { return "null" }
        return "\(value)"
    }
}

struct ConsoleLogRow: View {
    let entry: ConsoleLogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            if entry.level == .input {
                // REPL input: prompt azul + código
                Text("›")
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundColor(DT.infoText)
                    .frame(width: 16, alignment: .center)
                Text(entry.message)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundColor(DT.infoText)
                    .textSelection(.enabled)
                    .lineLimit(nil)
            } else if entry.level == .output {
                // REPL output: flecha + resultado
                Text("←")
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundColor(DT.textSecondary)
                    .frame(width: 16, alignment: .center)
                Text(entry.message.hasPrefix("← ") ? String(entry.message.dropFirst(2)) : entry.message)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundColor(DT.logText)
                    .textSelection(.enabled)
                    .lineLimit(nil)
            } else {
                // Log estándar
                Text(entry.timeString)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(DT.textMuted)
                    .frame(width: 75, alignment: .leading)

                if !entry.level.icon.isEmpty {
                    Text(entry.level.icon)
                        .font(.system(size: 13))
                }

                Text(entry.message)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundColor(entry.level.color)
                    .textSelection(.enabled)
                    .lineLimit(nil)
            }

            Spacer()

            if let source = entry.source {
                Text(source + (entry.line != nil ? ":\(entry.line!)" : ""))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(DT.textMuted)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            entry.level == .error ? DT.errorBg :
            entry.level == .warn ? DT.warnBg :
            entry.level == .input ? DT.inputBg :
            entry.level == .output ? DT.inputBg.opacity(0.5) :
            Color.clear
        )
    }
}

struct ConsoleInput: View {
    @Binding var command: String
    let onExecute: (String) -> Void
    @StateObject private var devTools = DevToolsState.shared

    var body: some View {
        HStack(spacing: 4) {
            Text("›")
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundColor(DT.infoText)
            ConsoleTextField(
                text: $command,
                onSubmit: {
                    guard !command.isEmpty else { return }
                    let cmd = command
                    command = ""
                    onExecute(cmd)
                },
                onArrowUp: {
                    let history = devTools.commandHistory
                    if !history.isEmpty {
                        devTools.commandHistoryIndex = min(devTools.commandHistoryIndex + 1, history.count - 1)
                        command = history[devTools.commandHistoryIndex]
                    }
                },
                onArrowDown: {
                    if devTools.commandHistoryIndex > 0 {
                        devTools.commandHistoryIndex -= 1
                        command = devTools.commandHistory[devTools.commandHistoryIndex]
                    } else {
                        devTools.commandHistoryIndex = -1
                        command = ""
                    }
                }
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(DT.inputBg)
    }
}

/// NSTextField con intercepción de flechas para historial de comandos
struct ConsoleTextField: NSViewRepresentable {
    @Binding var text: String
    let onSubmit: () -> Void
    let onArrowUp: () -> Void
    let onArrowDown: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let tf = NSTextField()
        tf.isBordered = false
        tf.drawsBackground = false
        tf.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        tf.focusRingType = .none
        tf.delegate = context.coordinator
        // Colores se aplican en updateNSView para respetar cambios de tema
        return tf
    }

    func updateNSView(_ tf: NSTextField, context: Context) {
        if tf.stringValue != text {
            tf.stringValue = text
        }
        // Actualizar colores según tema activo
        tf.textColor = NSColor(DT.text)
        tf.placeholderAttributedString = NSAttributedString(
            string: "Ejecutar JavaScript…",
            attributes: [
                .foregroundColor: NSColor(DT.textMuted),
                .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
            ]
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        let parent: ConsoleTextField
        init(parent: ConsoleTextField) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            guard let tf = obj.object as? NSTextField else { return }
            parent.text = tf.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            if commandSelector == #selector(NSResponder.moveUp(_:)) {
                parent.onArrowUp()
                return true
            }
            if commandSelector == #selector(NSResponder.moveDown(_:)) {
                parent.onArrowDown()
                return true
            }
            return false
        }
    }
}

// MARK: - Elements Panel

struct ElementsPanel: View {
    @EnvironmentObject var browserState: BrowserState
    @StateObject private var devTools = DevToolsState.shared
    @State private var searchQuery: String = ""
    @State private var isLoading: Bool = false

    /// Panel del DOM tree
    var domTreeView: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundColor(DT.textSecondary)
                TextField("Buscar en DOM…", text: $searchQuery, onCommit: searchDOM)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundColor(DT.text)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(DT.toolbarBg)

            Divider().overlay(DT.border)

            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(DT.bg)
            } else if devTools.domTree.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "rectangle.3.group")
                        .font(.system(size: 24))
                        .foregroundColor(DT.textSecondary)
                    Text("Presiona el botón para inspeccionar el DOM")
                        .font(.system(size: 14))
                        .foregroundColor(DT.textSecondary)
                    Button("Inspeccionar") { loadDOM() }
                        .controlSize(.small)
                        .foregroundColor(DT.link)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DT.bg)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(flattenedNodes()) { node in
                            DOMNodeRow(node: node, onToggle: { toggleNode(node) }, onSelect: { selectNode(node) })
                        }
                    }
                    .padding(4)
                }
                .background(DT.bg)
            }
        }
    }

    /// Panel de estilos CSS
    var stylesView: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Estilos")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DT.text)
                Spacer()
                if devTools.selectedElement != nil {
                    Button(action: loadComputedStyles) {
                        Text("Computed")
                            .font(.system(size: 13))
                            .foregroundColor(DT.link)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(DT.toolbarBg)

            Divider()

            if let element = devTools.selectedElement {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(element.openTag)
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundColor(DT.infoText)
                            .padding(6)

                        Divider()

                        if !devTools.elementStyles.isEmpty {
                            Text("Estilos aplicados")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(DT.textSecondary)
                                .padding(.horizontal, 8)
                                .padding(.top, 4)

                            ForEach(devTools.elementStyles) { prop in
                                CSSPropertyRow(property: prop)
                            }
                        }

                        if !devTools.elementComputedStyles.isEmpty {
                            Text("Estilos computados")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(DT.textSecondary)
                                .padding(.horizontal, 8)
                                .padding(.top, 8)

                            ForEach(devTools.elementComputedStyles) { prop in
                                CSSPropertyRow(property: prop)
                            }
                        }
                    }
                }
                .background(DT.bg)
            } else {
                Text("Selecciona un elemento")
                    .font(.system(size: 14))
                    .foregroundColor(DT.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(DT.bg)
            }
        }
        .background(DT.bg)
    }

    var body: some View {
        if devTools.isCompact {
            // Modo compacto (dock lateral): DOM arriba, Estilos abajo (stacked)
            VSplitView {
                domTreeView
                stylesView
            }
        } else {
            // Modo ancho (dock bottom): DOM izquierda, Estilos derecha (side-by-side)
            HSplitView {
                domTreeView
                    .frame(minWidth: 300)
                stylesView
                    .frame(minWidth: 200)
            }
        }
    }

    private func loadDOM() {
        guard let webView = browserState.currentTab?.webView else { return }
        isLoading = true

        webView.evaluateJavaScript(DevToolsScripts.domTreeScript) { result, error in
            DispatchQueue.main.async {
                isLoading = false
                if let jsonString = result as? String,
                   let data = jsonString.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                    devTools.domTree = Self.parseDOMNodes(json, depth: 0, parentPath: "")
                }
            }
        }
    }

    private func searchDOM() {
        guard !searchQuery.isEmpty, let webView = browserState.currentTab?.webView else { return }
        let escaped = searchQuery.replacingOccurrences(of: "'", with: "\\'")
        let script = """
        (function() {
            var el = document.querySelector('\(escaped)');
            if (!el) { el = document.querySelector('[id*="\(escaped)"], [class*="\(escaped)"]'); }
            if (el) {
                el.scrollIntoView({behavior:'smooth',block:'center'});
                el.style.outline = '2px solid #4A90D9';
                setTimeout(function() { el.style.outline = ''; }, 2000);
                return JSON.stringify({tag: el.tagName.toLowerCase(), id: el.id, class: el.className});
            }
            return null;
        })()
        """
        webView.evaluateJavaScript(script) { result, _ in
            if let jsonStr = result as? String {
                devTools.addLog(ConsoleLogEntry(
                    timestamp: Date(), level: .info,
                    message: "Elemento encontrado: \(jsonStr)", source: nil, line: nil
                ))
            }
        }
    }

    static func parseDOMNodes(_ nodes: [[String: Any]], depth: Int, parentPath: String) -> [DOMNode] {
        return nodes.compactMap { node -> DOMNode? in
            guard let tag = node["tag"] as? String else { return nil }
            let attrs = (node["attrs"] as? [[String: String]])?.compactMap { dict -> (String, String)? in
                guard let k = dict["name"], let v = dict["value"] else { return nil }
                return (k, v)
            } ?? []
            let text = node["text"] as? String
            let childrenData = node["children"] as? [[String: Any]] ?? []
            let index = node["index"] as? Int ?? 0
            let path = parentPath.isEmpty ? "\(tag):nth-child(\(index + 1))" : "\(parentPath) > \(tag):nth-child(\(index + 1))"
            let children = parseDOMNodes(childrenData, depth: depth + 1, parentPath: path)
            return DOMNode(tag: tag, attributes: attrs, textContent: text, children: children, depth: depth, path: path)
        }
    }

    private func flattenedNodes() -> [DOMNode] {
        var result: [DOMNode] = []
        func flatten(_ nodes: [DOMNode]) {
            for node in nodes {
                result.append(node)
                if node.isExpanded {
                    flatten(node.children)
                }
            }
        }
        flatten(devTools.domTree)
        return result
    }

    private func toggleNode(_ node: DOMNode) {
        func toggle(in nodes: inout [DOMNode]) {
            for i in nodes.indices {
                if nodes[i].id == node.id {
                    nodes[i].isExpanded.toggle()
                    return
                }
                toggle(in: &nodes[i].children)
            }
        }
        toggle(in: &devTools.domTree)
    }

    private func selectNode(_ node: DOMNode) {
        devTools.selectedElement = node
        loadStyles(for: node)
        highlightElement(node)
    }

    private func loadStyles(for node: DOMNode) {
        guard let webView = browserState.currentTab?.webView else { return }
        let escaped = node.path.replacingOccurrences(of: "'", with: "\\'")
        let script = """
        (function() {
            try {
                var el = document.querySelector('\(escaped)');
                if (!el) return '[]';
                var styles = [];
                if (el.style) {
                    for (var i = 0; i < el.style.length; i++) {
                        var name = el.style[i];
                        styles.push({name: name, value: el.style.getPropertyValue(name), source: 'inline'});
                    }
                }
                var computed = window.getComputedStyle(el);
                var important = ['display','position','width','height','margin','padding','color','background','font-size','font-family','border','flex','grid','overflow','z-index','opacity','transform','box-sizing'];
                important.forEach(function(p) {
                    var v = computed.getPropertyValue(p);
                    if (v && v !== '' && v !== 'none' && v !== 'normal' && v !== 'auto' && v !== '0px' && v !== 'rgba(0, 0, 0, 0)') {
                        styles.push({name: p, value: v, source: 'computed'});
                    }
                });
                return JSON.stringify(styles);
            } catch(e) { return '[]'; }
        })()
        """
        webView.evaluateJavaScript(script) { result, _ in
            if let jsonStr = result as? String,
               let data = jsonStr.data(using: .utf8),
               let items = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] {
                DispatchQueue.main.async {
                    devTools.elementStyles = items.filter { $0["source"] == "inline" }.map {
                        CSSProperty(name: $0["name"] ?? "", value: $0["value"] ?? "", source: $0["source"])
                    }
                    devTools.elementComputedStyles = items.filter { $0["source"] == "computed" }.map {
                        CSSProperty(name: $0["name"] ?? "", value: $0["value"] ?? "", source: $0["source"])
                    }
                }
            }
        }
    }

    private func loadComputedStyles() {
        guard let node = devTools.selectedElement,
              let webView = browserState.currentTab?.webView else { return }
        let escaped = node.path.replacingOccurrences(of: "'", with: "\\'")
        let script = """
        (function() {
            try {
                var el = document.querySelector('\(escaped)');
                if (!el) return '[]';
                var computed = window.getComputedStyle(el);
                var styles = [];
                for (var i = 0; i < computed.length; i++) {
                    var name = computed[i];
                    styles.push({name: name, value: computed.getPropertyValue(name), source: 'computed'});
                }
                return JSON.stringify(styles);
            } catch(e) { return '[]'; }
        })()
        """
        webView.evaluateJavaScript(script) { result, _ in
            if let jsonStr = result as? String,
               let data = jsonStr.data(using: .utf8),
               let items = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] {
                DispatchQueue.main.async {
                    devTools.elementComputedStyles = items.map {
                        CSSProperty(name: $0["name"] ?? "", value: $0["value"] ?? "", source: $0["source"])
                    }
                }
            }
        }
    }

    private func highlightElement(_ node: DOMNode) {
        guard let webView = browserState.currentTab?.webView else { return }
        let escaped = node.path.replacingOccurrences(of: "'", with: "\\'")
        let script = """
        (function() {
            document.querySelectorAll('.__mai_highlight').forEach(function(el) {
                el.style.outline = '';
                el.classList.remove('__mai_highlight');
            });
            var el = document.querySelector('\(escaped)');
            if (el) {
                el.style.outline = '2px solid #4A90D9';
                el.classList.add('__mai_highlight');
                el.scrollIntoView({behavior:'smooth',block:'center'});
            }
        })()
        """
        webView.evaluateJavaScript(script) { _, _ in }
    }
}

struct DOMNodeRow: View {
    let node: DOMNode
    let onToggle: () -> Void
    let onSelect: () -> Void
    @StateObject private var devTools = DevToolsState.shared

    var body: some View {
        HStack(spacing: 2) {
            // Indentación
            ForEach(0..<node.depth, id: \.self) { _ in
                Color.clear.frame(width: 16)
            }

            // Expand/collapse
            if node.hasChildren {
                Button(action: onToggle) {
                    Image(systemName: node.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12))
                        .foregroundColor(DT.textMuted)
                        .frame(width: 12)
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: 12)
            }

            // Tag content
            Button(action: onSelect) {
                HStack(spacing: 0) {
                    Text("<")
                        .foregroundColor(DT.textMuted)
                    Text(node.tag)
                        .foregroundColor(DT.keyword)

                    ForEach(Array(node.attributes.prefix(2).enumerated()), id: \.offset) { _, attr in
                        Text(" \(attr.0)")
                            .foregroundColor(DT.string)
                        Text("=")
                            .foregroundColor(DT.textMuted)
                        Text("\"\(attr.1.prefix(30))\(attr.1.count > 30 ? "…" : "")\"")
                            .foregroundColor(DT.success)
                    }

                    if node.attributes.count > 2 {
                        Text(" …")
                            .foregroundColor(DT.textMuted)
                    }

                    Text(">")
                        .foregroundColor(DT.textMuted)

                    if let text = node.textContent, !text.isEmpty {
                        Text(text.prefix(40) + (text.count > 40 ? "…" : ""))
                            .foregroundColor(DT.text.opacity(0.7))
                    }

                    if !node.hasChildren || !node.isExpanded {
                        Text("</\(node.tag)>")
                            .foregroundColor(DT.textMuted)
                    }
                }
                .font(.system(size: 14, design: .monospaced))
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.vertical, 1)
        .padding(.horizontal, 4)
        .background(devTools.selectedElement?.id == node.id ? DT.selectedBg : Color.clear)
    }
}

struct CSSPropertyRow: View {
    let property: CSSProperty

    var body: some View {
        HStack(spacing: 4) {
            Text(property.name)
                .font(.system(size: 14, design: .monospaced))
                .foregroundColor(DT.keyword)
            Text(":")
                .font(.system(size: 14, design: .monospaced))
                .foregroundColor(DT.textMuted)
            Text(property.value)
                .font(.system(size: 14, design: .monospaced))
                .foregroundColor(DT.infoText)
                .lineLimit(1)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 1)
    }
}

// MARK: - Network Panel (Chrome DevTools style)

enum NetworkThrottleProfile: String, CaseIterable {
    case none = "Sin límite"
    case fast3g = "Fast 3G"
    case slow3g = "Slow 3G"
    case offline = "Offline"
    case custom = "Custom"

    var latencyMs: Int {
        switch self {
        case .none: return 0
        case .fast3g: return 563
        case .slow3g: return 2000
        case .offline: return 0
        case .custom: return 0
        }
    }

    var downloadKbps: Int {
        switch self {
        case .none: return 0
        case .fast3g: return 1500   // 1.5 Mbps
        case .slow3g: return 400    // 400 Kbps
        case .offline: return 0
        case .custom: return 0
        }
    }

    var uploadKbps: Int {
        switch self {
        case .none: return 0
        case .fast3g: return 750
        case .slow3g: return 400
        case .offline: return 0
        case .custom: return 0
        }
    }

    var icon: String {
        switch self {
        case .none: return "bolt.fill"
        case .fast3g: return "antenna.radiowaves.left.and.right"
        case .slow3g: return "antenna.radiowaves.left.and.right.slash"
        case .offline: return "wifi.slash"
        case .custom: return "slider.horizontal.3"
        }
    }
}

struct NetworkPanel: View {
    @EnvironmentObject var browserState: BrowserState
    @StateObject private var devTools = DevToolsState.shared
    @State private var filterText: String = ""
    @State private var selectedType: String = "All"
    @State private var selectedEntry: NetworkEntry?
    @State private var preserveLog: Bool = false
    @State private var disableCache: Bool = false
    @State private var isRecording: Bool = true
    @State private var throttleProfile: NetworkThrottleProfile = .none
    @State private var customLatency: String = "200"
    @State private var customDownload: String = "1000"

    let types = ["All", "Fetch/XHR", "Doc", "CSS", "JS", "Font", "Img", "Media", "Manifest", "WS", "WASM", "Other"]

    /// Tiempo máximo en ms para escalar el waterfall
    var waterfallMaxTime: Int {
        let maxEnd = filteredEntries.map { $0.responseEnd }.max() ?? 1000
        if maxEnd <= 500 { return 500 }
        if maxEnd <= 1000 { return 1000 }
        if maxEnd <= 2000 { return 2000 }
        if maxEnd <= 5000 { return 5000 }
        if maxEnd <= 10000 { return 10000 }
        if maxEnd <= 20000 { return 20000 }
        if maxEnd <= 50000 { return 50000 }
        return ((maxEnd / 10000) + 1) * 10000
    }

    /// Total bytes transferidos
    var totalTransferred: Int {
        filteredEntries.compactMap { entry -> Int? in
            let s = entry.size.replacingOccurrences(of: " ", with: "")
            if s.hasSuffix("KB") { return Int((Double(s.dropLast(2)) ?? 0) * 1024) }
            if s.hasSuffix("MB") { return Int((Double(s.dropLast(2)) ?? 0) * 1024 * 1024) }
            if s.hasSuffix("B") { return Int(Double(s.dropLast(1)) ?? 0) }
            return Int(s)
        }.reduce(0, +)
    }

    /// Tiempo de finalización (max responseEnd)
    var finishTime: String {
        let maxMs = filteredEntries.map { $0.responseEnd }.max() ?? 0
        if maxMs < 1000 { return "\(maxMs) ms" }
        return String(format: "%.2f s", Double(maxMs) / 1000.0)
    }

    var filteredEntries: [NetworkEntry] {
        devTools.networkEntries.filter { entry in
            let typeLower = entry.type.lowercased()
            let methodUpper = entry.method.uppercased()
            let typeMatch: Bool
            switch selectedType {
            case "All": typeMatch = true
            case "Fetch/XHR": typeMatch = typeLower.contains("fetch") || typeLower.contains("xhr") || typeLower.contains("xmlhttprequest")
            case "Doc": typeMatch = typeLower.contains("document") || typeLower.contains("navigation")
            case "CSS": typeMatch = typeLower.contains("stylesheet") || typeLower.contains("css")
            case "JS": typeMatch = typeLower.contains("script")
            case "Font": typeMatch = typeLower.contains("font")
            case "Img": typeMatch = typeLower.contains("image") || typeLower.contains("img")
            case "Media": typeMatch = typeLower.contains("media") || typeLower.contains("video") || typeLower.contains("audio")
            case "Manifest": typeMatch = typeLower.contains("manifest")
            case "WS": typeMatch = typeLower.contains("websocket") || methodUpper == "WS"
            case "WASM": typeMatch = typeLower.contains("wasm")
            default: typeMatch = true
            }
            let textMatch = filterText.isEmpty ||
                entry.url.localizedCaseInsensitiveContains(filterText) ||
                entry.shortName.localizedCaseInsensitiveContains(filterText)
            return typeMatch && textMatch
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // === Fila 1: Record, Clear, Preserve log, Disable cache ===
            HStack(spacing: 6) {
                // Record button (rojo cuando activo)
                Button(action: { isRecording.toggle() }) {
                    Circle()
                        .fill(isRecording ? Color.red : DT.textMuted)
                        .frame(width: 9, height: 9)
                }
                .buttonStyle(.plain)
                .help(isRecording ? "Detener grabación" : "Grabar red")

                // Clear
                Button(action: { devTools.clearNetwork() }) {
                    Image(systemName: "nosign")
                        .font(.system(size: 13))
                        .foregroundColor(DT.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Limpiar")

                Divider().frame(height: 14)

                // Filtro texto
                HStack(spacing: 3) {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 12))
                        .foregroundColor(DT.textSecondary)
                    TextField("Filter", text: $filterText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundColor(DT.text)
                        .frame(minWidth: 60, maxWidth: devTools.isCompact ? .infinity : 150)
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(DT.inputBg)
                .cornerRadius(4)

                if !devTools.isCompact {
                    Divider().frame(height: 14)

                    Toggle("Preserve log", isOn: $preserveLog)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 13))
                        .controlSize(.mini)

                    Toggle("Disable cache", isOn: $disableCache)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 13))
                        .controlSize(.mini)
                }

                Spacer()

                Divider().frame(height: 14)

                // Throttling
                Menu {
                    ForEach(NetworkThrottleProfile.allCases, id: \.self) { profile in
                        if profile == .custom {
                            // Custom handled separately
                        } else {
                            Button(action: {
                                throttleProfile = profile
                                applyThrottling(profile)
                            }) {
                                HStack {
                                    Image(systemName: profile.icon)
                                    Text(profile.rawValue)
                                    if profile == throttleProfile {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: throttleProfile.icon)
                            .font(.system(size: 11))
                        Text(throttleProfile == .none ? "⚡" : throttleProfile.rawValue)
                            .font(.system(size: 11))
                    }
                    .foregroundColor(throttleProfile == .none ? DT.textSecondary : DT.warning)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(throttleProfile == .none ? Color.clear : DT.warnBg)
                    .cornerRadius(3)
                }

                // Refrescar
                Button(action: { loadNetworkEntries() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13))
                        .foregroundColor(DT.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Recargar datos de red")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(DT.toolbarBg)

            // Throttle warning banner
            if throttleProfile != .none {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                    if throttleProfile == .offline {
                        Text("Modo Offline — Las peticiones fetch/XHR serán bloqueadas")
                    } else {
                        Text("Throttling activo: \(throttleProfile.rawValue) — Latencia: \(throttleProfile.latencyMs)ms, Descarga: \(throttleProfile.downloadKbps) Kbps")
                    }
                    Spacer()
                    Button("Desactivar") {
                        throttleProfile = .none
                        applyThrottling(.none)
                    }
                    .font(.system(size: 11))
                    .buttonStyle(.plain)
                    .foregroundColor(DT.link)
                }
                .font(.system(size: 11))
                .foregroundColor(DT.warnText)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(DT.warnBg)
            }

            // === Fila 2: Type filters (scroll horizontal en compacto) ===
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 1) {
                    ForEach(types, id: \.self) { type in
                        Button(action: { selectedType = type }) {
                            Text(type)
                                .font(.system(size: devTools.isCompact ? 11 : 12))
                                .foregroundColor(selectedType == type ? DT.text : DT.textSecondary)
                                .padding(.horizontal, devTools.isCompact ? 4 : 6)
                                .padding(.vertical, 2)
                                .background(selectedType == type ? DT.selectedBg : Color.clear)
                                .cornerRadius(3)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
            }
            .padding(.vertical, 2)
            .background(DT.toolbarBg.opacity(0.85))

            Divider().overlay(DT.border)

            // === Timeline ruler (marcadores de tiempo como Chrome) ===
            if !filteredEntries.isEmpty && !devTools.isCompact {
                NetworkTimelineRuler(maxTime: waterfallMaxTime)
                    .frame(height: 18)
                    .background(DT.bg)
                Divider().overlay(DT.border)
            }

            // === Column headers ===
            if devTools.isCompact {
                HStack(spacing: 0) {
                    Text("Name").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Status").frame(width: 50, alignment: .trailing)
                    Text("Time").frame(width: 50, alignment: .trailing)
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(DT.textSecondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(DT.toolbarBg)
            } else {
                HStack(spacing: 0) {
                    Text("Name").frame(minWidth: 150, alignment: .leading)
                    Text("Status").frame(width: 45, alignment: .center)
                    Text("Type").frame(width: 55, alignment: .leading)
                    Text("Initiator").frame(width: 80, alignment: .leading)
                    Text("Size").frame(width: 55, alignment: .trailing)
                    Text("Time").frame(width: 55, alignment: .trailing)
                    Text("Waterfall").frame(minWidth: 120, alignment: .leading).padding(.leading, 6)
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(DT.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(DT.toolbarBg)
            }

            Divider().overlay(DT.border)

            // === Entries ===
            if filteredEntries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "network")
                        .font(.system(size: 24))
                        .foregroundColor(DT.textSecondary)
                    Text(devTools.networkEntries.isEmpty ? "Recording network activity…" : "No matching requests")
                        .font(.system(size: 14))
                        .foregroundColor(DT.textSecondary)
                    if devTools.networkEntries.isEmpty {
                        Text("Perform a request or hit \(Image(systemName: "arrow.clockwise")) to capture")
                            .font(.system(size: 13))
                            .foregroundColor(DT.textMuted)
                    }
                    Button("Capturar peticiones") { loadNetworkEntries() }
                        .controlSize(.small)
                        .foregroundColor(DT.link)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DT.bg)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredEntries) { entry in
                            NetworkEntryRow(entry: entry, isSelected: selectedEntry?.id == entry.id, maxTime: waterfallMaxTime)
                                .onTapGesture { selectedEntry = entry }
                        }
                    }
                }
                .background(DT.bg)
            }

            // === Status bar (como Chrome) ===
            if !filteredEntries.isEmpty {
                Divider().overlay(DT.border)
                HStack(spacing: 0) {
                    let total = devTools.networkEntries.count
                    let showing = filteredEntries.count
                    if selectedType != "All" || !filterText.isEmpty {
                        Text("\(showing) / \(total) requests")
                    } else {
                        Text("\(total) requests")
                    }
                    Text("  |  ")
                        .foregroundColor(DT.textMuted)
                    Text("\(Self.formatBytes(totalTransferred)) transferred")
                    Text("  |  ")
                        .foregroundColor(DT.textMuted)
                    Text("Finish: \(finishTime)")

                    Spacer()
                }
                .font(.system(size: 13))
                .foregroundColor(DT.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(DT.toolbarBg)
            }

            // === Detail panel for selected entry ===
            if let entry = selectedEntry {
                Divider().overlay(DT.border)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.url)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(DT.infoText)
                        .textSelection(.enabled)
                        .lineLimit(2)
                    HStack(spacing: 12) {
                        Text("Method: \(entry.method)")
                        Text("Status: \(entry.status)")
                        Text("Type: \(entry.type)")
                        Text("Size: \(entry.size)")
                        Text("Time: \(entry.duration)")
                        if !entry.initiator.isEmpty {
                            Text("Initiator: \(entry.initiator)")
                        }
                    }
                    .font(.system(size: 13))
                    .foregroundColor(DT.textSecondary)
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DT.toolbarBg)
            }
        }
        .onAppear { loadNetworkEntries() }
    }

    private func loadNetworkEntries() {
        guard let webView = browserState.currentTab?.webView else { return }
        webView.evaluateJavaScript(DevToolsScripts.networkCaptureScript) { result, _ in
            if let jsonStr = result as? String,
               let data = jsonStr.data(using: .utf8),
               let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                let parsed = entries.compactMap { entry -> NetworkEntry? in
                    guard let name = entry["name"] as? String else { return nil }
                    return NetworkEntry(
                        timestamp: Date(),
                        method: entry["method"] as? String ?? "GET",
                        url: name,
                        status: entry["status"] as? Int ?? 0,
                        type: entry["type"] as? String ?? "other",
                        size: Self.formatBytes(entry["size"] as? Int ?? 0),
                        duration: String(format: "%.0fms", entry["duration"] as? Double ?? 0),
                        initiator: entry["initiator"] as? String ?? "",
                        startTime: entry["startTime"] as? Int ?? 0,
                        connectEnd: entry["connectEnd"] as? Int ?? 0,
                        requestStart: entry["requestStart"] as? Int ?? 0,
                        responseStart: entry["responseStart"] as? Int ?? 0,
                        responseEnd: entry["responseEnd"] as? Int ?? 0
                    )
                }
                DispatchQueue.main.async {
                    if preserveLog {
                        devTools.networkEntries.append(contentsOf: parsed)
                    } else {
                        devTools.networkEntries = parsed
                    }
                }
            }
        }
    }

    static func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }

    private func applyThrottling(_ profile: NetworkThrottleProfile) {
        guard let webView = browserState.currentTab?.webView else { return }

        if profile == .none {
            // Remover throttling
            webView.evaluateJavaScript("""
            (function() {
                if (window.__maiOriginalFetch) {
                    window.fetch = window.__maiOriginalFetch;
                    delete window.__maiOriginalFetch;
                }
                if (window.__maiOriginalXHROpen) {
                    XMLHttpRequest.prototype.open = window.__maiOriginalXHROpen;
                    delete window.__maiOriginalXHROpen;
                }
                window.__maiThrottleLatency = 0;
                window.__maiThrottleOffline = false;
                console.log('[MAI] Network throttling desactivado');
            })();
            """) { _, _ in }
            return
        }

        let latency = profile.latencyMs
        let isOffline = profile == .offline

        webView.evaluateJavaScript("""
        (function() {
            var latency = \(latency);
            var offline = \(isOffline ? "true" : "false");
            window.__maiThrottleLatency = latency;
            window.__maiThrottleOffline = offline;

            // Intercept fetch
            if (!window.__maiOriginalFetch) {
                window.__maiOriginalFetch = window.fetch;
            }
            window.fetch = function() {
                if (offline) {
                    return Promise.reject(new TypeError('Failed to fetch — Modo offline (MAI DevTools)'));
                }
                var args = arguments;
                var origFetch = window.__maiOriginalFetch;
                if (latency > 0) {
                    return new Promise(function(resolve) {
                        setTimeout(function() { resolve(origFetch.apply(window, args)); }, latency);
                    });
                }
                return origFetch.apply(window, args);
            };

            // Intercept XMLHttpRequest
            if (!window.__maiOriginalXHROpen) {
                window.__maiOriginalXHROpen = XMLHttpRequest.prototype.open;
                window.__maiOriginalXHRSend = XMLHttpRequest.prototype.send;
            }
            XMLHttpRequest.prototype.send = function() {
                var xhr = this;
                var args = arguments;
                var origSend = window.__maiOriginalXHRSend;
                if (offline) {
                    setTimeout(function() {
                        xhr.dispatchEvent(new Event('error'));
                        if (xhr.onerror) xhr.onerror(new Error('Modo offline (MAI DevTools)'));
                    }, 50);
                    return;
                }
                if (latency > 0) {
                    setTimeout(function() { origSend.apply(xhr, args); }, latency);
                } else {
                    origSend.apply(xhr, args);
                }
            };

            console.log('[MAI] Network throttling: ' + (offline ? 'OFFLINE' : latency + 'ms latency'));
        })();
        """) { _, _ in }
    }
}

struct NetworkEntryRow: View {
    let entry: NetworkEntry
    let isSelected: Bool
    var maxTime: Int = 1000
    @ObservedObject private var devTools = DevToolsState.shared

    var body: some View {
        if devTools.isCompact {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.shortName)
                        .font(.system(size: 12))
                        .foregroundColor(DT.text)
                        .lineLimit(1)
                    Text(entry.shortURL)
                        .font(.system(size: 12))
                        .foregroundColor(DT.textMuted)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text("\(entry.status)")
                    .frame(width: 50, alignment: .trailing)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(entry.statusColor)

                Text(entry.duration)
                    .frame(width: 50, alignment: .trailing)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(DT.textSecondary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(isSelected ? DT.selectedBg : Color.clear)
        } else {
            HStack(spacing: 0) {
                // Name (shows resource name, full URL as tooltip)
                Text(entry.shortName)
                    .frame(minWidth: 150, alignment: .leading)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundColor(DT.text)
                    .help(entry.url)

                // Status
                Text("\(entry.status)")
                    .frame(width: 45, alignment: .center)
                    .foregroundColor(entry.statusColor)

                // Type
                Text(entry.typeLabel)
                    .frame(width: 55, alignment: .leading)
                    .foregroundColor(entry.typeColor)

                // Initiator
                Text(entry.initiator)
                    .frame(width: 80, alignment: .leading)
                    .foregroundColor(DT.textMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)

                // Size
                Text(entry.size)
                    .frame(width: 55, alignment: .trailing)
                    .foregroundColor(DT.textSecondary)

                // Time
                Text(entry.duration)
                    .frame(width: 55, alignment: .trailing)
                    .foregroundColor(DT.textSecondary)

                // Waterfall bar
                WaterfallBar(entry: entry, maxTime: maxTime)
                    .frame(height: 10)
                    .frame(minWidth: 120)
                    .padding(.leading, 6)
            }
            .font(.system(size: 13, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(isSelected ? DT.selectedBg : Color.clear)
        }
    }
}

// MARK: - Network Timeline Ruler

/// Regla de tiempo horizontal encima de las entradas (como Chrome: 10,000ms | 20,000ms | ...)
struct NetworkTimelineRuler: View {
    let maxTime: Int

    var markers: [Int] {
        let step: Int
        if maxTime <= 500 { step = 100 }
        else if maxTime <= 1000 { step = 200 }
        else if maxTime <= 2000 { step = 500 }
        else if maxTime <= 5000 { step = 1000 }
        else if maxTime <= 10000 { step = 2000 }
        else if maxTime <= 20000 { step = 5000 }
        else if maxTime <= 50000 { step = 10000 }
        else { step = 20000 }
        var marks: [Int] = []
        var t = step
        while t <= maxTime {
            marks.append(t)
            t += step
        }
        return marks
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Background line
                Rectangle()
                    .fill(DT.border.opacity(0.3))
                    .frame(height: 0.5)
                    .offset(y: geo.size.height - 1)

                // Marker ticks and labels
                ForEach(markers, id: \.self) { ms in
                    let x = geo.size.width * CGFloat(ms) / CGFloat(max(maxTime, 1))
                    VStack(spacing: 0) {
                        Spacer()
                        Text(Self.formatTime(ms))
                            .font(.system(size: 12))
                            .foregroundColor(DT.textMuted)
                        Rectangle()
                            .fill(DT.border.opacity(0.5))
                            .frame(width: 0.5, height: 5)
                    }
                    .offset(x: x - 15)
                    .frame(width: 30)
                }
            }
            .padding(.horizontal, 8)
        }
    }

    static func formatTime(_ ms: Int) -> String {
        if ms < 1000 { return "\(ms) ms" }
        let s = Double(ms) / 1000.0
        if s == s.rounded() { return String(format: "%.0f s", s) }
        return String(format: "%.1f s", s)
    }
}

// MARK: - Waterfall Bar

/// Barra visual de waterfall para cada petición de red (colores por tipo como Chrome)
struct WaterfallBar: View {
    let entry: NetworkEntry
    let maxTime: Int

    var barColor: Color {
        switch entry.type.lowercased() {
        case "document", "navigation": return Color(red: 0.380, green: 0.533, blue: 0.867) // azul
        case "stylesheet", "css": return Color(red: 0.561, green: 0.349, blue: 0.757) // morado
        case "script": return Color(red: 0.933, green: 0.706, blue: 0.275) // amarillo
        case "xhr", "fetch", "xmlhttprequest": return Color(red: 0.380, green: 0.749, blue: 0.380) // verde
        case "image", "img": return Color(red: 0.216, green: 0.718, blue: 0.718) // teal
        case "font": return Color(red: 0.769, green: 0.467, blue: 0.659) // rosa
        case "media", "video", "audio": return Color(red: 0.400, green: 0.773, blue: 0.961) // celeste
        case "websocket": return Color(red: 0.933, green: 0.490, blue: 0.302) // naranja
        case "manifest": return Color(red: 0.600, green: 0.600, blue: 0.600) // gris
        case "wasm": return Color(red: 0.600, green: 0.400, blue: 0.800) // morado claro
        default: return DT.textSecondary
        }
    }

    var body: some View {
        GeometryReader { geo in
            let scale = geo.size.width / CGFloat(max(maxTime, 1))
            let xStart = CGFloat(entry.startTime) * scale
            let barWidth = max(CGFloat(max(entry.responseEnd - entry.startTime, 1)) * scale, 2)
            let clampedWidth = min(barWidth, geo.size.width - max(xStart, 0))

            // Light bar: waiting (startTime → responseStart)
            if entry.responseStart > entry.startTime {
                let waitWidth = CGFloat(entry.responseStart - entry.startTime) * scale
                RoundedRectangle(cornerRadius: 1)
                    .fill(barColor.opacity(0.35))
                    .frame(width: min(waitWidth, clampedWidth), height: 8)
                    .offset(x: max(xStart, 0), y: 1)
            }

            // Solid bar: downloading (responseStart → responseEnd)
            let dlStart = CGFloat(max(entry.responseStart, entry.startTime)) * scale
            let dlWidth = max(CGFloat(entry.responseEnd - max(entry.responseStart, entry.startTime)) * scale, 2)
            RoundedRectangle(cornerRadius: 1)
                .fill(barColor)
                .frame(width: min(dlWidth, geo.size.width - max(dlStart, 0)), height: 8)
                .offset(x: max(dlStart, 0), y: 1)
        }
    }
}

// MARK: - Storage Panel

struct StoragePanel: View {
    @EnvironmentObject var browserState: BrowserState
    @StateObject private var devTools = DevToolsState.shared
    @State private var selectedStorage: StorageType = .localStorage

    enum StorageType: String, CaseIterable {
        case localStorage = "Local Storage"
        case sessionStorage = "Session Storage"
        case cookies = "Cookies"
    }

    var currentItems: [StorageItem] {
        switch selectedStorage {
        case .localStorage: return devTools.localStorageItems
        case .sessionStorage: return devTools.sessionStorageItems
        case .cookies: return devTools.cookies
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Storage type selector
            HStack(spacing: 6) {
                ForEach(StorageType.allCases, id: \.self) { type in
                    Button(action: {
                        selectedStorage = type
                        loadStorage(type)
                    }) {
                        Text(type.rawValue)
                            .font(.system(size: 13))
                            .foregroundColor(selectedStorage == type ? DT.text : DT.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(selectedStorage == type ? DT.selectedBg : Color.clear)
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Text("\(currentItems.count) entradas")
                    .font(.system(size: 13))
                    .foregroundColor(DT.textSecondary)

                Button(action: { loadStorage(selectedStorage) }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13))
                        .foregroundColor(DT.textSecondary)
                }
                .buttonStyle(.plain)

                Button(action: { clearStorage() }) {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundColor(DT.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Limpiar almacenamiento")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(DT.toolbarBg)

            Divider()

            // Table headers
            HStack(spacing: 0) {
                Text("Clave").frame(width: 200, alignment: .leading)
                Text("Valor").frame(minWidth: 200, alignment: .leading)
                if selectedStorage == .cookies {
                    Text("Dominio").frame(width: 120, alignment: .leading)
                    Text("Expira").frame(width: 100, alignment: .leading)
                }
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(DT.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(DT.toolbarBg)

            Divider()

            // Items
            if currentItems.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "cylinder")
                        .font(.system(size: 24))
                        .foregroundColor(DT.textSecondary)
                    Text("Sin datos almacenados")
                        .font(.system(size: 14))
                        .foregroundColor(DT.textSecondary)
                    Button("Cargar") { loadStorage(selectedStorage) }
                        .controlSize(.small)
                        .foregroundColor(DT.link)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DT.bg)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(currentItems) { item in
                            HStack(spacing: 0) {
                                Text(item.key)
                                    .frame(width: 200, alignment: .leading)
                                    .lineLimit(1)
                                    .foregroundColor(DT.keyword)

                                Text(item.value.prefix(200))
                                    .frame(minWidth: 200, alignment: .leading)
                                    .lineLimit(2)
                                    .textSelection(.enabled)
                                    .foregroundColor(DT.string)

                                if selectedStorage == .cookies {
                                    Text(item.domain ?? "")
                                        .frame(width: 120, alignment: .leading)
                                        .lineLimit(1)
                                        .foregroundColor(DT.textSecondary)

                                    Text(item.expires ?? "Sesión")
                                        .frame(width: 100, alignment: .leading)
                                        .lineLimit(1)
                                        .foregroundColor(DT.textSecondary)
                                }
                            }
                            .font(.system(size: 13, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.clear)
                        }
                    }
                }
                .background(DT.bg)
            }
        }
        .onAppear { loadStorage(selectedStorage) }
    }

    private func loadStorage(_ type: StorageType) {
        guard let webView = browserState.currentTab?.webView else { return }

        switch type {
        case .localStorage:
            webView.evaluateJavaScript(DevToolsScripts.localStorageScript) { result, _ in
                parseStorageResult(result, target: .localStorage)
            }
        case .sessionStorage:
            webView.evaluateJavaScript(DevToolsScripts.sessionStorageScript) { result, _ in
                parseStorageResult(result, target: .sessionStorage)
            }
        case .cookies:
            webView.evaluateJavaScript("document.cookie") { result, _ in
                if let cookieStr = result as? String {
                    let items = cookieStr.split(separator: ";").map { pair -> StorageItem in
                        let parts = pair.trimmingCharacters(in: .whitespaces).split(separator: "=", maxSplits: 1)
                        return StorageItem(
                            key: String(parts.first ?? ""),
                            value: parts.count > 1 ? String(parts[1]) : "",
                            domain: nil, path: nil, expires: nil
                        )
                    }
                    DispatchQueue.main.async { devTools.cookies = items }
                }
            }
            // Also get HTTP-only cookies from WKHTTPCookieStore
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                let items = cookies.map { cookie in
                    StorageItem(
                        key: cookie.name,
                        value: cookie.value,
                        domain: cookie.domain,
                        path: cookie.path,
                        expires: cookie.expiresDate?.description ?? "Sesión"
                    )
                }
                DispatchQueue.main.async { devTools.cookies = items }
            }
        }
    }

    private func parseStorageResult(_ result: Any?, target: StorageType) {
        if let jsonStr = result as? String,
           let data = jsonStr.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] {
            let items = dict.map { StorageItem(key: $0["key"] ?? "", value: $0["value"] ?? "", domain: nil, path: nil, expires: nil) }
            DispatchQueue.main.async {
                switch target {
                case .localStorage: devTools.localStorageItems = items
                case .sessionStorage: devTools.sessionStorageItems = items
                default: break
                }
            }
        }
    }

    private func clearStorage() {
        guard let webView = browserState.currentTab?.webView else { return }
        switch selectedStorage {
        case .localStorage:
            webView.evaluateJavaScript("localStorage.clear()") { _, _ in
                DispatchQueue.main.async { devTools.localStorageItems.removeAll() }
            }
        case .sessionStorage:
            webView.evaluateJavaScript("sessionStorage.clear()") { _, _ in
                DispatchQueue.main.async { devTools.sessionStorageItems.removeAll() }
            }
        case .cookies:
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                for cookie in cookies {
                    webView.configuration.websiteDataStore.httpCookieStore.delete(cookie)
                }
                DispatchQueue.main.async { devTools.cookies.removeAll() }
            }
        }
    }
}

// MARK: - Sources Panel

struct SourcesPanel: View {
    @EnvironmentObject var browserState: BrowserState
    @State private var sourceHTML: String = ""
    @State private var isLoading: Bool = false
    @State private var searchText: String = ""
    @State private var lineCount: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Button(action: loadSource) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13))
                        Text("Cargar fuente")
                            .font(.system(size: 13))
                    }
                    .foregroundColor(DT.textSecondary)
                }
                .buttonStyle(.plain)

                if lineCount > 0 {
                    Text("\(lineCount) líneas")
                        .font(.system(size: 13))
                        .foregroundColor(DT.textSecondary)
                }

                Spacer()

                HStack {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundColor(DT.textSecondary)
                    TextField("Buscar en fuente…", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundColor(DT.text)
                        .frame(width: 150)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(DT.inputBg)
                .cornerRadius(4)

                Button(action: copySource) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 13))
                        Text("Copiar")
                            .font(.system(size: 13))
                    }
                    .foregroundColor(DT.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(DT.toolbarBg)

            Divider()

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(DT.bg)
            } else if sourceHTML.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 24))
                        .foregroundColor(DT.textSecondary)
                    Text("Presiona \"Cargar fuente\" para ver el HTML")
                        .font(.system(size: 14))
                        .foregroundColor(DT.textSecondary)
                    Button("Cargar fuente") { loadSource() }
                        .controlSize(.small)
                        .foregroundColor(DT.link)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DT.bg)
            } else {
                ScrollView([.horizontal, .vertical]) {
                    SourceCodeView(source: sourceHTML, searchText: searchText)
                        .padding(8)
                }
                .background(DT.bg)
            }
        }
        .onAppear { loadSource() }
    }

    private func loadSource() {
        guard let webView = browserState.currentTab?.webView else { return }
        isLoading = true
        webView.evaluateJavaScript("""
        (function() {
            var dt = document.doctype;
            var doctype = dt ? '<!DOCTYPE ' + dt.name + '>' : '';
            return doctype + '\\n' + document.documentElement.outerHTML;
        })()
        """) { result, _ in
            DispatchQueue.main.async {
                isLoading = false
                if let html = result as? String {
                    sourceHTML = html
                    lineCount = html.components(separatedBy: "\n").count
                }
            }
        }
    }

    private func copySource() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(sourceHTML, forType: .string)
    }
}

struct SourceCodeView: View {
    let source: String
    let searchText: String

    var lines: [(Int, String)] {
        source.components(separatedBy: "\n").enumerated().map { ($0.offset + 1, $0.element) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(lines.prefix(5000), id: \.0) { lineNum, content in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(lineNum)")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(DT.textMuted)
                        .frame(width: 40, alignment: .trailing)

                    HighlightedSourceLine(content: content, searchText: searchText)
                }
            }
            if lines.count > 5000 {
                Text("… (\(lines.count - 5000) líneas más)")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(DT.textMuted)
                    .padding(.leading, 48)
            }
        }
    }
}

struct HighlightedSourceLine: View {
    let content: String
    let searchText: String

    var body: some View {
        if !searchText.isEmpty && content.localizedCaseInsensitiveContains(searchText) {
            Text(highlightedText)
                .font(.system(size: 14, design: .monospaced))
                .textSelection(.enabled)
        } else {
            Text(syntaxHighlighted(content))
                .font(.system(size: 14, design: .monospaced))
                .textSelection(.enabled)
        }
    }

    private var highlightedText: AttributedString {
        var attr = AttributedString(content)
        attr.foregroundColor = Color(red: 0.910, green: 0.918, blue: 0.929) // DT.text
        // Highlight search matches
        if let range = content.range(of: searchText, options: .caseInsensitive) {
            let start = content.distance(from: content.startIndex, to: range.lowerBound)
            let length = content.distance(from: range.lowerBound, to: range.upperBound)
            let attrStart = attr.index(attr.startIndex, offsetByCharacters: start)
            let attrEnd = attr.index(attrStart, offsetByCharacters: length)
            attr[attrStart..<attrEnd].backgroundColor = Color(red: 0.318, green: 0.357, blue: 0.416) // #515c6a find match
            attr[attrStart..<attrEnd].foregroundColor = Color(red: 0.910, green: 0.918, blue: 0.929) // DT.text for match
        }
        return attr
    }

    private func syntaxHighlighted(_ text: String) -> AttributedString {
        var attr = AttributedString(text)
        attr.foregroundColor = Color(red: 0.831, green: 0.831, blue: 0.831) // DT.text dimmed
        // Basic HTML syntax coloring
        let tagPattern = try? NSRegularExpression(pattern: "</?[a-zA-Z][^>]*>")
        if let matches = tagPattern?.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            for match in matches {
                if let range = Range(match.range, in: text) {
                    let start = text.distance(from: text.startIndex, to: range.lowerBound)
                    let length = text.distance(from: range.lowerBound, to: range.upperBound)
                    let attrStart = attr.index(attr.startIndex, offsetByCharacters: start)
                    let attrEnd = attr.index(attrStart, offsetByCharacters: length)
                    attr[attrStart..<attrEnd].foregroundColor = Color(red: 0.365, green: 0.690, blue: 0.843) // DT.tag
                }
            }
        }
        return attr
    }
}

// MARK: - Performance Data Models

struct PerformanceMetrics {
    // Navigation Timing
    var dnsLookup: Double = 0        // domainLookupEnd - domainLookupStart
    var tcpConnect: Double = 0       // connectEnd - connectStart
    var tlsHandshake: Double = 0     // connectEnd - secureConnectionStart (if > 0)
    var ttfb: Double = 0             // responseStart - requestStart
    var contentDownload: Double = 0  // responseEnd - responseStart
    var domParsing: Double = 0       // domInteractive - responseEnd
    var domContentLoaded: Double = 0 // domContentLoadedEventEnd - navigationStart
    var pageLoad: Double = 0         // loadEventEnd - navigationStart
    var domInteractive: Double = 0   // domInteractive - navigationStart
    var firstPaint: Double = 0       // from PerformanceObserver paint entries
    var firstContentfulPaint: Double = 0
    var largestContentfulPaint: Double = 0

    // Resource summary
    var totalResources: Int = 0
    var totalTransferSize: Int = 0
    var scriptCount: Int = 0
    var styleCount: Int = 0
    var imageCount: Int = 0
    var fontCount: Int = 0
    var xhrCount: Int = 0
    var otherCount: Int = 0

    // DOM stats
    var domNodeCount: Int = 0
    var domDepth: Int = 0
    var eventListenerCount: Int = 0

    // Memory (if available)
    var jsHeapSize: Int = 0
    var jsHeapLimit: Int = 0
}

struct PerfTimelineEntry: Identifiable {
    let id = UUID()
    let name: String
    let type: String       // script, css, img, font, xhr, etc.
    let startTime: Double  // ms from navigationStart
    let duration: Double   // ms
    let size: Int          // bytes

    var typeColor: Color {
        switch type.lowercased() {
        case "script": return DT.keyword
        case "css", "stylesheet": return DT.success
        case "img", "image": return DT.string
        case "font": return DT.typeName
        case "xhr", "fetch": return DT.infoText
        case "document", "navigation": return DT.tag
        default: return DT.textSecondary
        }
    }

    var shortName: String {
        if let lastSlash = name.lastIndex(of: "/") {
            return String(name[name.index(after: lastSlash)...]).prefix(40).description
        }
        return String(name.prefix(40))
    }
}

// MARK: - Performance Panel

struct PerformancePanel: View {
    @EnvironmentObject var browserState: BrowserState
    @StateObject private var devTools = DevToolsState.shared
    @State private var selectedSection: String = "Resumen"

    let sections = ["Resumen", "Timeline", "Recursos", "DOM"]

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 8) {
                // Record button
                Button(action: { capturePerformance() }) {
                    HStack(spacing: 4) {
                        Image(systemName: devTools.perfIsLoading ? "stop.fill" : "record.circle")
                            .font(.system(size: 13))
                            .foregroundColor(devTools.perfIsLoading ? .red : DT.textSecondary)
                        Text(devTools.perfIsLoading ? "Capturando…" : "Capturar")
                            .font(.system(size: 13))
                            .foregroundColor(DT.text)
                    }
                }
                .buttonStyle(.plain)

                Button(action: { devTools.perfMetrics = nil; devTools.perfEntries.removeAll() }) {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundColor(DT.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Limpiar")

                Divider().frame(height: 14)

                // Section selector
                ForEach(sections, id: \.self) { section in
                    Button(action: { selectedSection = section }) {
                        Text(section)
                            .font(.system(size: 12))
                            .foregroundColor(selectedSection == section ? DT.text : DT.textSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(selectedSection == section ? DT.selectedBg : Color.clear)
                            .cornerRadius(3)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(DT.toolbarBg)

            Divider().overlay(DT.border)

            // Content
            if let metrics = devTools.perfMetrics {
                switch selectedSection {
                case "Resumen":
                    perfSummaryView(metrics)
                case "Timeline":
                    perfTimelineView()
                case "Recursos":
                    perfResourcesView(metrics)
                case "DOM":
                    perfDOMView(metrics)
                default:
                    perfSummaryView(metrics)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "gauge.with.dots.needle.33percent")
                        .font(.system(size: 36))
                        .foregroundColor(DT.textSecondary)
                    Text("Capturar datos de rendimiento")
                        .font(.system(size: 15))
                        .foregroundColor(DT.text)
                    Text("Presiona \"Capturar\" para analizar el rendimiento de la página actual")
                        .font(.system(size: 13))
                        .foregroundColor(DT.textSecondary)
                        .multilineTextAlignment(.center)
                    Button("Capturar ahora") { capturePerformance() }
                        .controlSize(.regular)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DT.bg)
            }
        }
    }

    // MARK: - Summary View
    @ViewBuilder
    private func perfSummaryView(_ m: PerformanceMetrics) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Page Load Score
                let score = Self.loadScore(m)
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .stroke(DT.border, lineWidth: 6)
                            .frame(width: 70, height: 70)
                        Circle()
                            .trim(from: 0, to: CGFloat(score) / 100.0)
                            .stroke(
                                score >= 90 ? DT.success : score >= 50 ? DT.warning : DT.error,
                                style: StrokeStyle(lineWidth: 6, lineCap: .round)
                            )
                            .frame(width: 70, height: 70)
                            .rotationEffect(.degrees(-90))
                        Text("\(score)")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(DT.text)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Puntuación de Rendimiento")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(DT.text)
                        Text(score >= 90 ? "Excelente" : score >= 50 ? "Necesita mejoras" : "Rendimiento pobre")
                            .font(.system(size: 13))
                            .foregroundColor(score >= 90 ? DT.success : score >= 50 ? DT.warning : DT.error)
                    }
                }
                .padding(.bottom, 4)

                // Core Web Vitals
                Text("Core Web Vitals")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(DT.text)

                HStack(spacing: 12) {
                    metricCard("FCP", value: m.firstContentfulPaint, unit: "ms",
                               good: 1800, poor: 3000, description: "First Contentful Paint")
                    metricCard("LCP", value: m.largestContentfulPaint, unit: "ms",
                               good: 2500, poor: 4000, description: "Largest Contentful Paint")
                    metricCard("Carga", value: m.pageLoad, unit: "ms",
                               good: 3000, poor: 6000, description: "Page Load Total")
                }

                Divider().overlay(DT.border)

                // Timing breakdown
                Text("Desglose de Tiempos")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(DT.text)

                timingBar("DNS Lookup", value: m.dnsLookup, max: m.pageLoad, color: DT.tag)
                timingBar("TCP Connect", value: m.tcpConnect, max: m.pageLoad, color: DT.typeName)
                if m.tlsHandshake > 0 {
                    timingBar("TLS Handshake", value: m.tlsHandshake, max: m.pageLoad, color: DT.keyword)
                }
                timingBar("TTFB (Time to First Byte)", value: m.ttfb, max: m.pageLoad, color: DT.string)
                timingBar("Descarga contenido", value: m.contentDownload, max: m.pageLoad, color: DT.success)
                timingBar("Parseo DOM", value: m.domParsing, max: m.pageLoad, color: DT.warning)
                timingBar("DOMContentLoaded", value: m.domContentLoaded, max: m.pageLoad, color: DT.info)
                timingBar("Page Load", value: m.pageLoad, max: m.pageLoad, color: DT.error)

                if m.firstPaint > 0 {
                    Divider().overlay(DT.border)
                    Text("Paint Timings")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(DT.text)
                    timingBar("First Paint", value: m.firstPaint, max: m.pageLoad, color: DT.fnName)
                    timingBar("First Contentful Paint", value: m.firstContentfulPaint, max: m.pageLoad, color: DT.selector)
                    if m.largestContentfulPaint > 0 {
                        timingBar("Largest Contentful Paint", value: m.largestContentfulPaint, max: m.pageLoad, color: DT.property)
                    }
                }
            }
            .padding(12)
        }
        .background(DT.bg)
    }

    // MARK: - Timeline View
    @ViewBuilder
    private func perfTimelineView() -> some View {
        if devTools.perfEntries.isEmpty {
            VStack {
                Text("Sin datos de timeline")
                    .foregroundColor(DT.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DT.bg)
        } else {
            let maxTime = devTools.perfEntries.map { $0.startTime + $0.duration }.max() ?? 1000
            VStack(spacing: 0) {
                // Timeline ruler
                HStack(spacing: 0) {
                    ForEach(0..<5) { i in
                        Text(Self.formatMs(maxTime * Double(i) / 4.0))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(DT.textMuted)
                        if i < 4 { Spacer() }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(DT.toolbarBg)

                Divider().overlay(DT.border)

                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(devTools.perfEntries) { entry in
                            HStack(spacing: 0) {
                                // Name
                                Text(entry.shortName)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(DT.text)
                                    .lineLimit(1)
                                    .frame(width: 160, alignment: .leading)

                                // Bar
                                GeometryReader { geo in
                                    let barStart = CGFloat(entry.startTime / maxTime) * geo.size.width
                                    let barWidth = max(2, CGFloat(entry.duration / maxTime) * geo.size.width)
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(entry.typeColor)
                                        .frame(width: barWidth, height: 14)
                                        .offset(x: barStart)
                                }
                                .frame(height: 18)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 1)
                        }
                    }
                }
                .background(DT.bg)
            }
        }
    }

    // MARK: - Resources View
    @ViewBuilder
    private func perfResourcesView(_ m: PerformanceMetrics) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Resumen de Recursos")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(DT.text)

                // Resource pie chart (text-based)
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        resourceRow("Scripts", count: m.scriptCount, color: DT.keyword)
                        resourceRow("Estilos", count: m.styleCount, color: DT.success)
                        resourceRow("Imágenes", count: m.imageCount, color: DT.string)
                        resourceRow("Fuentes", count: m.fontCount, color: DT.typeName)
                        resourceRow("XHR/Fetch", count: m.xhrCount, color: DT.infoText)
                        resourceRow("Otros", count: m.otherCount, color: DT.textMuted)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text("\(m.totalResources)")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(DT.text)
                        Text("recursos totales")
                            .font(.system(size: 12))
                            .foregroundColor(DT.textSecondary)

                        Divider().frame(width: 80).overlay(DT.border)

                        Text(Self.formatBytes(m.totalTransferSize))
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundColor(DT.text)
                        Text("transferidos")
                            .font(.system(size: 12))
                            .foregroundColor(DT.textSecondary)
                    }
                }

                if !devTools.perfEntries.isEmpty {
                    Divider().overlay(DT.border)
                    Text("Top 10 recursos más lentos")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(DT.text)

                    let slowest = devTools.perfEntries.sorted { $0.duration > $1.duration }.prefix(10)
                    ForEach(Array(slowest)) { entry in
                        HStack {
                            Circle().fill(entry.typeColor).frame(width: 8, height: 8)
                            Text(entry.shortName)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(DT.text)
                                .lineLimit(1)
                            Spacer()
                            Text(Self.formatMs(entry.duration))
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundColor(entry.duration > 1000 ? DT.error : entry.duration > 500 ? DT.warning : DT.textSecondary)
                        }
                    }
                }
            }
            .padding(12)
        }
        .background(DT.bg)
    }

    // MARK: - DOM View
    @ViewBuilder
    private func perfDOMView(_ m: PerformanceMetrics) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Estadísticas del DOM")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(DT.text)

                HStack(spacing: 20) {
                    domStat("Nodos", value: m.domNodeCount,
                            threshold: m.domNodeCount > 1500 ? "Alto" : m.domNodeCount > 800 ? "Medio" : "Bajo",
                            color: m.domNodeCount > 1500 ? DT.error : m.domNodeCount > 800 ? DT.warning : DT.success)
                    domStat("Profundidad", value: m.domDepth,
                            threshold: m.domDepth > 15 ? "Muy profundo" : m.domDepth > 10 ? "Profundo" : "OK",
                            color: m.domDepth > 15 ? DT.error : m.domDepth > 10 ? DT.warning : DT.success)
                    domStat("Event Listeners", value: m.eventListenerCount,
                            threshold: m.eventListenerCount > 200 ? "Excesivo" : m.eventListenerCount > 100 ? "Alto" : "Normal",
                            color: m.eventListenerCount > 200 ? DT.error : m.eventListenerCount > 100 ? DT.warning : DT.success)
                }

                if m.jsHeapSize > 0 {
                    Divider().overlay(DT.border)
                    Text("Memoria JavaScript")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(DT.text)

                    HStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Self.formatBytes(m.jsHeapSize))
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundColor(DT.text)
                            Text("Heap usado")
                                .font(.system(size: 11))
                                .foregroundColor(DT.textSecondary)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Self.formatBytes(m.jsHeapLimit))
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundColor(DT.textSecondary)
                            Text("Heap límite")
                                .font(.system(size: 11))
                                .foregroundColor(DT.textSecondary)
                        }
                    }
                }

                Divider().overlay(DT.border)

                // Recommendations
                Text("Recomendaciones")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(DT.text)

                if let metrics = devTools.perfMetrics {
                    if metrics.domNodeCount > 1500 {
                        recommendationRow("⚠️", "Reducir nodos DOM (\(metrics.domNodeCount)) — páginas con >1500 nodos son más lentas")
                    }
                    if metrics.domDepth > 15 {
                        recommendationRow("⚠️", "DOM demasiado profundo (\(metrics.domDepth) niveles) — aplanar la jerarquía")
                    }
                    if metrics.ttfb > 600 {
                        recommendationRow("🔴", "TTFB alto (\(Int(metrics.ttfb))ms) — optimizar servidor o usar CDN")
                    }
                    if metrics.firstContentfulPaint > 2500 {
                        recommendationRow("🔴", "FCP lento (\(Int(metrics.firstContentfulPaint))ms) — reducir CSS/JS bloqueante")
                    }
                    if metrics.scriptCount > 15 {
                        recommendationRow("⚠️", "Demasiados scripts (\(metrics.scriptCount)) — considerar bundling")
                    }
                    if metrics.imageCount > 20 {
                        recommendationRow("⚠️", "Muchas imágenes (\(metrics.imageCount)) — usar lazy loading")
                    }
                    if metrics.totalTransferSize > 3_000_000 {
                        recommendationRow("🔴", "Página pesada (\(Self.formatBytes(metrics.totalTransferSize))) — optimizar recursos")
                    }
                    if metrics.pageLoad < 3000 && metrics.domNodeCount < 1000 && metrics.scriptCount < 10 {
                        recommendationRow("✅", "¡Buen rendimiento! La página carga rápido y el DOM es ligero")
                    }
                }
            }
            .padding(12)
        }
        .background(DT.bg)
    }

    // MARK: - Helpers

    private func metricCard(_ label: String, value: Double, unit: String, good: Double, poor: Double, description: String) -> some View {
        VStack(spacing: 4) {
            Text(Self.formatMs(value))
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(value <= good ? DT.success : value <= poor ? DT.warning : DT.error)
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(DT.text)
            Text(value <= good ? "Bueno" : value <= poor ? "Mejorable" : "Pobre")
                .font(.system(size: 10))
                .foregroundColor(value <= good ? DT.success : value <= poor ? DT.warning : DT.error)
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(DT.inputBg)
        .cornerRadius(6)
        .help(description)
    }

    private func timingBar(_ label: String, value: Double, max: Double, color: Color) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(DT.textSecondary)
                .frame(width: 180, alignment: .trailing)
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 3)
                    .fill(color)
                    .frame(width: max > 0 ? CGFloat(value / max) * geo.size.width : 0, height: 14)
            }
            .frame(height: 16)
            Text(Self.formatMs(value))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(DT.text)
                .frame(width: 60, alignment: .trailing)
        }
    }

    private func resourceRow(_ label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(DT.text)
            Spacer()
            Text("\(count)")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(DT.text)
        }
    }

    private func domStat(_ label: String, value: Int, threshold: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(DT.text)
            Text(threshold)
                .font(.system(size: 10))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(DT.inputBg)
        .cornerRadius(6)
    }

    private func recommendationRow(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(icon)
                .font(.system(size: 13))
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(DT.text)
        }
        .padding(.vertical, 2)
    }

    static func formatMs(_ ms: Double) -> String {
        if ms < 1 { return "0 ms" }
        if ms < 1000 { return "\(Int(ms)) ms" }
        return String(format: "%.2f s", ms / 1000.0)
    }

    static func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024.0) }
        return String(format: "%.1f MB", Double(bytes) / (1024.0 * 1024.0))
    }

    static func loadScore(_ m: PerformanceMetrics) -> Int {
        var score = 100
        // FCP penalty
        if m.firstContentfulPaint > 3000 { score -= 25 }
        else if m.firstContentfulPaint > 1800 { score -= 10 }
        // LCP penalty
        if m.largestContentfulPaint > 4000 { score -= 25 }
        else if m.largestContentfulPaint > 2500 { score -= 10 }
        // Page load penalty
        if m.pageLoad > 6000 { score -= 20 }
        else if m.pageLoad > 3000 { score -= 10 }
        // TTFB penalty
        if m.ttfb > 600 { score -= 10 }
        // DOM complexity
        if m.domNodeCount > 1500 { score -= 10 }
        return max(0, min(100, score))
    }

    // MARK: - Capture

    private func capturePerformance() {
        guard let webView = browserState.currentTab?.webView else { return }
        devTools.perfIsLoading = true

        webView.evaluateJavaScript(DevToolsScripts.performanceScript) { result, error in
            devTools.perfIsLoading = false
            guard let dict = result as? [String: Any] else { return }

            var m = PerformanceMetrics()

            // Navigation timing
            if let nav = dict["navigation"] as? [String: Any] {
                m.dnsLookup = nav["dnsLookup"] as? Double ?? 0
                m.tcpConnect = nav["tcpConnect"] as? Double ?? 0
                m.tlsHandshake = nav["tlsHandshake"] as? Double ?? 0
                m.ttfb = nav["ttfb"] as? Double ?? 0
                m.contentDownload = nav["contentDownload"] as? Double ?? 0
                m.domParsing = nav["domParsing"] as? Double ?? 0
                m.domContentLoaded = nav["domContentLoaded"] as? Double ?? 0
                m.pageLoad = nav["pageLoad"] as? Double ?? 0
                m.domInteractive = nav["domInteractive"] as? Double ?? 0
            }

            // Paint timing
            if let paint = dict["paint"] as? [String: Any] {
                m.firstPaint = paint["firstPaint"] as? Double ?? 0
                m.firstContentfulPaint = paint["firstContentfulPaint"] as? Double ?? 0
                m.largestContentfulPaint = paint["lcp"] as? Double ?? 0
            }

            // Resources summary
            if let res = dict["resources"] as? [String: Any] {
                m.totalResources = res["total"] as? Int ?? 0
                m.totalTransferSize = res["transferSize"] as? Int ?? 0
                m.scriptCount = res["scripts"] as? Int ?? 0
                m.styleCount = res["styles"] as? Int ?? 0
                m.imageCount = res["images"] as? Int ?? 0
                m.fontCount = res["fonts"] as? Int ?? 0
                m.xhrCount = res["xhr"] as? Int ?? 0
                m.otherCount = res["other"] as? Int ?? 0
            }

            // DOM stats
            if let dom = dict["dom"] as? [String: Any] {
                m.domNodeCount = dom["nodeCount"] as? Int ?? 0
                m.domDepth = dom["maxDepth"] as? Int ?? 0
                m.eventListenerCount = dom["listenerCount"] as? Int ?? 0
            }

            // Memory
            if let mem = dict["memory"] as? [String: Any] {
                m.jsHeapSize = mem["usedJSHeapSize"] as? Int ?? 0
                m.jsHeapLimit = mem["jsHeapSizeLimit"] as? Int ?? 0
            }

            devTools.perfMetrics = m

            // Timeline entries
            if let entries = dict["timeline"] as? [[String: Any]] {
                devTools.perfEntries = entries.compactMap { e in
                    guard let name = e["name"] as? String,
                          let type = e["type"] as? String,
                          let start = e["startTime"] as? Double,
                          let dur = e["duration"] as? Double else { return nil }
                    return PerfTimelineEntry(name: name, type: type, startTime: start, duration: dur, size: e["size"] as? Int ?? 0)
                }
            }
        }
    }
}

// MARK: - Memory Data Models

struct MemorySnapshot: Identifiable {
    let id = UUID()
    let timestamp: Date
    let domNodeCount: Int
    let detachedNodes: Int
    let eventListenerCount: Int
    let iframeCount: Int
    let scriptCount: Int
    let styleSheetCount: Int
    let imageCount: Int
    let canvasCount: Int
    let videoCount: Int
    let audioContextCount: Int
    let webSocketCount: Int
    let observerCount: Int  // MutationObserver, IntersectionObserver, etc.
    let timerCount: Int     // setInterval count
    let domSize: Int        // outerHTML.length (approximate memory)
    let duplicateIds: [String]
    let largestNodes: [LargeNode]
    let leakWarnings: [String]

    var timeString: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"
        return fmt.string(from: timestamp)
    }

    var healthScore: Int {
        var score = 100
        if detachedNodes > 50 { score -= 25 } else if detachedNodes > 10 { score -= 10 }
        if eventListenerCount > 500 { score -= 20 } else if eventListenerCount > 200 { score -= 10 }
        if domNodeCount > 3000 { score -= 20 } else if domNodeCount > 1500 { score -= 10 }
        if timerCount > 10 { score -= 10 } else if timerCount > 5 { score -= 5 }
        if !duplicateIds.isEmpty { score -= 5 }
        return max(0, min(100, score))
    }
}

struct LargeNode: Identifiable {
    let id = UUID()
    let selector: String
    let childCount: Int
    let estimatedSize: Int // bytes
}

// MARK: - Memory Panel

struct MemoryPanel: View {
    @EnvironmentObject var browserState: BrowserState
    @StateObject private var devTools = DevToolsState.shared

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 8) {
                Button(action: { takeSnapshot() }) {
                    HStack(spacing: 4) {
                        Image(systemName: devTools.memoryIsLoading ? "hourglass" : "camera")
                            .font(.system(size: 13))
                            .foregroundColor(devTools.memoryIsLoading ? DT.warning : DT.textSecondary)
                        Text(devTools.memoryIsLoading ? "Capturando…" : "Tomar Snapshot")
                            .font(.system(size: 13))
                            .foregroundColor(DT.text)
                    }
                }
                .buttonStyle(.plain)
                .disabled(devTools.memoryIsLoading)

                if devTools.memorySnapshots.count >= 2 {
                    Divider().frame(height: 14)
                    Button(action: {}) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.left.arrow.right")
                                .font(.system(size: 12))
                            Text("Comparar")
                                .font(.system(size: 13))
                        }
                        .foregroundColor(DT.link)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                if !devTools.memorySnapshots.isEmpty {
                    Text("\(devTools.memorySnapshots.count) snapshot\(devTools.memorySnapshots.count > 1 ? "s" : "")")
                        .font(.system(size: 12))
                        .foregroundColor(DT.textSecondary)

                    Button(action: { devTools.memorySnapshots.removeAll() }) {
                        Image(systemName: "trash")
                            .font(.system(size: 13))
                            .foregroundColor(DT.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .help("Limpiar snapshots")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(DT.toolbarBg)

            Divider().overlay(DT.border)

            if devTools.memorySnapshots.isEmpty {
                // Empty state
                VStack(spacing: 12) {
                    Image(systemName: "memorychip")
                        .font(.system(size: 36))
                        .foregroundColor(DT.textSecondary)
                    Text("Analizar uso de memoria")
                        .font(.system(size: 15))
                        .foregroundColor(DT.text)
                    Text("Toma snapshots para detectar memory leaks, nodos DOM detached,\nevent listeners excesivos y otros problemas de memoria")
                        .font(.system(size: 13))
                        .foregroundColor(DT.textSecondary)
                        .multilineTextAlignment(.center)
                    Button("Tomar Snapshot") { takeSnapshot() }
                        .controlSize(.regular)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DT.bg)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Comparison if multiple snapshots
                        if devTools.memorySnapshots.count >= 2 {
                            comparisonView
                            Divider().overlay(DT.border)
                        }

                        // Latest snapshot detail
                        if let latest = devTools.memorySnapshots.last {
                            snapshotDetailView(latest, index: devTools.memorySnapshots.count)
                        }

                        // Previous snapshots summary
                        if devTools.memorySnapshots.count > 1 {
                            Divider().overlay(DT.border)
                            Text("Historial de Snapshots")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(DT.text)

                            ForEach(Array(devTools.memorySnapshots.dropLast().reversed().enumerated()), id: \.element.id) { idx, snap in
                                let snapNum = devTools.memorySnapshots.count - 1 - idx
                                snapshotSummaryRow(snap, number: snapNum)
                            }
                        }
                    }
                    .padding(12)
                }
                .background(DT.bg)
            }
        }
    }

    // MARK: - Comparison View
    @ViewBuilder
    private var comparisonView: some View {
        let prev = devTools.memorySnapshots[devTools.memorySnapshots.count - 2]
        let curr = devTools.memorySnapshots.last!

        VStack(alignment: .leading, spacing: 8) {
            Text("Comparación: Snapshot \(devTools.memorySnapshots.count - 1) → \(devTools.memorySnapshots.count)")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(DT.text)

            HStack(spacing: 16) {
                deltaCard("Nodos DOM", prev: prev.domNodeCount, curr: curr.domNodeCount)
                deltaCard("Detached", prev: prev.detachedNodes, curr: curr.detachedNodes)
                deltaCard("Listeners", prev: prev.eventListenerCount, curr: curr.eventListenerCount)
                deltaCard("Timers", prev: prev.timerCount, curr: curr.timerCount)
            }
        }
    }

    private func deltaCard(_ label: String, prev: Int, curr: Int) -> some View {
        let delta = curr - prev
        return VStack(spacing: 2) {
            HStack(spacing: 2) {
                Text("\(curr)")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(DT.text)
                if delta != 0 {
                    Text(delta > 0 ? "+\(delta)" : "\(delta)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(delta > 0 ? DT.error : DT.success)
                }
            }
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(DT.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(6)
        .background(DT.inputBg)
        .cornerRadius(6)
    }

    // MARK: - Snapshot Detail
    @ViewBuilder
    private func snapshotDetailView(_ snap: MemorySnapshot, index: Int) -> some View {
        // Health score
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(DT.border, lineWidth: 5)
                    .frame(width: 60, height: 60)
                Circle()
                    .trim(from: 0, to: CGFloat(snap.healthScore) / 100.0)
                    .stroke(
                        snap.healthScore >= 80 ? DT.success : snap.healthScore >= 50 ? DT.warning : DT.error,
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .frame(width: 60, height: 60)
                    .rotationEffect(.degrees(-90))
                Text("\(snap.healthScore)")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(DT.text)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Snapshot #\(index) — \(snap.timeString)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DT.text)
                Text(snap.healthScore >= 80 ? "Memoria saludable" : snap.healthScore >= 50 ? "Posibles problemas" : "Problemas detectados")
                    .font(.system(size: 13))
                    .foregroundColor(snap.healthScore >= 80 ? DT.success : snap.healthScore >= 50 ? DT.warning : DT.error)
            }
        }

        // Stats grid
        Text("Estadísticas DOM")
            .font(.system(size: 14, weight: .bold))
            .foregroundColor(DT.text)

        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            statCell("Nodos DOM", value: snap.domNodeCount,
                     status: snap.domNodeCount > 1500 ? .bad : snap.domNodeCount > 800 ? .warn : .ok)
            statCell("Nodos Detached", value: snap.detachedNodes,
                     status: snap.detachedNodes > 10 ? .bad : snap.detachedNodes > 0 ? .warn : .ok)
            statCell("Event Listeners", value: snap.eventListenerCount,
                     status: snap.eventListenerCount > 500 ? .bad : snap.eventListenerCount > 200 ? .warn : .ok)
            statCell("Iframes", value: snap.iframeCount, status: snap.iframeCount > 5 ? .warn : .ok)
            statCell("Scripts", value: snap.scriptCount, status: snap.scriptCount > 30 ? .warn : .ok)
            statCell("StyleSheets", value: snap.styleSheetCount, status: snap.styleSheetCount > 20 ? .warn : .ok)
            statCell("Imágenes", value: snap.imageCount, status: snap.imageCount > 50 ? .warn : .ok)
            statCell("Canvas", value: snap.canvasCount, status: .ok)
            statCell("Timers activos", value: snap.timerCount,
                     status: snap.timerCount > 10 ? .bad : snap.timerCount > 5 ? .warn : .ok)
        }

        if snap.webSocketCount > 0 || snap.audioContextCount > 0 || snap.observerCount > 0 {
            Text("Recursos Activos")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(DT.text)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                if snap.webSocketCount > 0 { statCell("WebSockets", value: snap.webSocketCount, status: .ok) }
                if snap.audioContextCount > 0 { statCell("AudioContext", value: snap.audioContextCount, status: snap.audioContextCount > 2 ? .warn : .ok) }
                if snap.observerCount > 0 { statCell("Observers", value: snap.observerCount, status: snap.observerCount > 20 ? .warn : .ok) }
            }
        }

        // Duplicate IDs
        if !snap.duplicateIds.isEmpty {
            Divider().overlay(DT.border)
            Text("⚠️ IDs Duplicados (\(snap.duplicateIds.count))")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(DT.warning)
            Text("IDs duplicados causan comportamiento impredecible en JS y accessibility")
                .font(.system(size: 12))
                .foregroundColor(DT.textSecondary)
            ForEach(snap.duplicateIds.prefix(10), id: \.self) { dupId in
                Text("#\(dupId)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(DT.string)
            }
            if snap.duplicateIds.count > 10 {
                Text("… y \(snap.duplicateIds.count - 10) más")
                    .font(.system(size: 11))
                    .foregroundColor(DT.textMuted)
            }
        }

        // Largest nodes
        if !snap.largestNodes.isEmpty {
            Divider().overlay(DT.border)
            Text("Nodos más grandes")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(DT.text)

            ForEach(snap.largestNodes.prefix(5)) { node in
                HStack {
                    Text(node.selector)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(DT.tag)
                        .lineLimit(1)
                    Spacer()
                    Text("\(node.childCount) hijos")
                        .font(.system(size: 11))
                        .foregroundColor(DT.textSecondary)
                    Text(PerformancePanel.formatBytes(node.estimatedSize))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(DT.text)
                }
            }
        }

        // Leak warnings
        if !snap.leakWarnings.isEmpty {
            Divider().overlay(DT.border)
            Text("🔴 Posibles Memory Leaks")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(DT.error)

            ForEach(snap.leakWarnings, id: \.self) { warning in
                HStack(alignment: .top, spacing: 6) {
                    Text("•")
                        .foregroundColor(DT.error)
                    Text(warning)
                        .font(.system(size: 13))
                        .foregroundColor(DT.text)
                }
            }
        }

        // DOM estimated size
        Divider().overlay(DT.border)
        HStack {
            Text("Tamaño DOM estimado:")
                .font(.system(size: 13))
                .foregroundColor(DT.textSecondary)
            Text(PerformancePanel.formatBytes(snap.domSize))
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(snap.domSize > 5_000_000 ? DT.error : snap.domSize > 2_000_000 ? DT.warning : DT.text)
        }
    }

    private enum StatStatus { case ok, warn, bad }

    private func statCell(_ label: String, value: Int, status: StatStatus) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(status == .bad ? DT.error : status == .warn ? DT.warning : DT.text)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(DT.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(6)
        .background(DT.inputBg)
        .cornerRadius(5)
    }

    // MARK: - Snapshot Summary Row
    private func snapshotSummaryRow(_ snap: MemorySnapshot, number: Int) -> some View {
        HStack(spacing: 8) {
            Text("#\(number)")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(DT.textSecondary)
                .frame(width: 25)
            Text(snap.timeString)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(DT.textMuted)
            Text("\(snap.domNodeCount) nodos")
                .font(.system(size: 12))
                .foregroundColor(DT.text)
            if snap.detachedNodes > 0 {
                Text("\(snap.detachedNodes) detached")
                    .font(.system(size: 11))
                    .foregroundColor(DT.warning)
            }
            Spacer()
            Circle()
                .fill(snap.healthScore >= 80 ? DT.success : snap.healthScore >= 50 ? DT.warning : DT.error)
                .frame(width: 8, height: 8)
            Text("\(snap.healthScore)")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(DT.textSecondary)
        }
        .padding(.vertical, 3)
    }

    // MARK: - Capture
    private func takeSnapshot() {
        guard let webView = browserState.currentTab?.webView else { return }
        devTools.memoryIsLoading = true

        webView.evaluateJavaScript(DevToolsScripts.memorySnapshotScript) { result, error in
            devTools.memoryIsLoading = false
            guard let dict = result as? [String: Any] else { return }

            let dupIds = dict["duplicateIds"] as? [String] ?? []
            let largeNodesRaw = dict["largestNodes"] as? [[String: Any]] ?? []
            let largeNodes = largeNodesRaw.compactMap { n -> LargeNode? in
                guard let sel = n["selector"] as? String else { return nil }
                return LargeNode(selector: sel,
                                 childCount: n["childCount"] as? Int ?? 0,
                                 estimatedSize: n["estimatedSize"] as? Int ?? 0)
            }
            let warnings = dict["leakWarnings"] as? [String] ?? []

            let snap = MemorySnapshot(
                timestamp: Date(),
                domNodeCount: dict["domNodeCount"] as? Int ?? 0,
                detachedNodes: dict["detachedNodes"] as? Int ?? 0,
                eventListenerCount: dict["eventListenerCount"] as? Int ?? 0,
                iframeCount: dict["iframeCount"] as? Int ?? 0,
                scriptCount: dict["scriptCount"] as? Int ?? 0,
                styleSheetCount: dict["styleSheetCount"] as? Int ?? 0,
                imageCount: dict["imageCount"] as? Int ?? 0,
                canvasCount: dict["canvasCount"] as? Int ?? 0,
                videoCount: dict["videoCount"] as? Int ?? 0,
                audioContextCount: dict["audioContextCount"] as? Int ?? 0,
                webSocketCount: dict["webSocketCount"] as? Int ?? 0,
                observerCount: dict["observerCount"] as? Int ?? 0,
                timerCount: dict["timerCount"] as? Int ?? 0,
                domSize: dict["domSize"] as? Int ?? 0,
                duplicateIds: dupIds,
                largestNodes: largeNodes,
                leakWarnings: warnings
            )

            devTools.memorySnapshots.append(snap)
        }
    }
}

// MARK: - Lighthouse Data Models

struct LighthouseResult {
    var performanceScore: Int = 0
    var accessibilityScore: Int = 0
    var bestPracticesScore: Int = 0
    var seoScore: Int = 0
    var audits: [LighthouseAudit] = []
    var timestamp: Date = Date()
}

struct LighthouseAudit: Identifiable {
    let id = UUID()
    let category: String     // Performance, Accessibility, Best Practices, SEO
    let title: String
    let description: String
    let score: Double        // 0.0 - 1.0
    let impact: String       // high, medium, low
    let details: String

    var status: String {
        if score >= 0.9 { return "pass" }
        if score >= 0.5 { return "average" }
        return "fail"
    }

    var statusColor: Color {
        if score >= 0.9 { return DT.success }
        if score >= 0.5 { return DT.warning }
        return DT.error
    }

    var statusIcon: String {
        if score >= 0.9 { return "checkmark.circle.fill" }
        if score >= 0.5 { return "exclamationmark.triangle.fill" }
        return "xmark.circle.fill"
    }
}

// MARK: - Lighthouse Panel

struct LighthousePanel: View {
    @EnvironmentObject var browserState: BrowserState
    @StateObject private var devTools = DevToolsState.shared
    @State private var selectedCategory: String = "Todos"

    let categories = ["Todos", "Performance", "Accessibility", "Best Practices", "SEO"]

    var filteredAudits: [LighthouseAudit] {
        guard let result = devTools.lighthouseResult else { return [] }
        if selectedCategory == "Todos" { return result.audits }
        return result.audits.filter { $0.category == selectedCategory }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 8) {
                Button(action: { runAudit() }) {
                    HStack(spacing: 4) {
                        Image(systemName: devTools.lighthouseIsLoading ? "hourglass" : "speedometer")
                            .font(.system(size: 13))
                            .foregroundColor(devTools.lighthouseIsLoading ? DT.warning : DT.textSecondary)
                        Text(devTools.lighthouseIsLoading ? "Analizando…" : "Ejecutar Auditoría")
                            .font(.system(size: 13))
                            .foregroundColor(DT.text)
                    }
                }
                .buttonStyle(.plain)
                .disabled(devTools.lighthouseIsLoading)

                if devTools.lighthouseResult != nil {
                    Divider().frame(height: 14)
                    ForEach(categories, id: \.self) { cat in
                        Button(action: { selectedCategory = cat }) {
                            Text(cat == "Todos" ? "Todos" : cat)
                                .font(.system(size: 11))
                                .foregroundColor(selectedCategory == cat ? DT.text : DT.textSecondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(selectedCategory == cat ? DT.selectedBg : Color.clear)
                                .cornerRadius(3)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer()

                if devTools.lighthouseResult != nil {
                    Button(action: { devTools.lighthouseResult = nil }) {
                        Image(systemName: "trash")
                            .font(.system(size: 13))
                            .foregroundColor(DT.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(DT.toolbarBg)

            Divider().overlay(DT.border)

            if let result = devTools.lighthouseResult {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Score circles
                        HStack(spacing: 20) {
                            scoreCircle("Performance", score: result.performanceScore)
                            scoreCircle("Accessibility", score: result.accessibilityScore)
                            scoreCircle("Best Practices", score: result.bestPracticesScore)
                            scoreCircle("SEO", score: result.seoScore)
                        }
                        .padding(.vertical, 8)

                        Divider().overlay(DT.border)

                        // Audit results
                        let failed = filteredAudits.filter { $0.score < 0.5 }
                        let warnings = filteredAudits.filter { $0.score >= 0.5 && $0.score < 0.9 }
                        let passed = filteredAudits.filter { $0.score >= 0.9 }

                        if !failed.isEmpty {
                            Text("🔴 Problemas (\(failed.count))")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(DT.error)
                            ForEach(failed) { audit in auditRow(audit) }
                        }

                        if !warnings.isEmpty {
                            Text("🟡 Mejorables (\(warnings.count))")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(DT.warning)
                            ForEach(warnings) { audit in auditRow(audit) }
                        }

                        if !passed.isEmpty {
                            Text("✅ Aprobados (\(passed.count))")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(DT.success)
                            ForEach(passed) { audit in auditRow(audit) }
                        }
                    }
                    .padding(12)
                }
                .background(DT.bg)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "speedometer")
                        .font(.system(size: 36))
                        .foregroundColor(DT.textSecondary)
                    Text("Auditoría tipo Lighthouse")
                        .font(.system(size: 15))
                        .foregroundColor(DT.text)
                    Text("Analiza Performance, Accessibility, Best Practices y SEO\nde la página actual con un solo click")
                        .font(.system(size: 13))
                        .foregroundColor(DT.textSecondary)
                        .multilineTextAlignment(.center)
                    Button("Ejecutar Auditoría") { runAudit() }
                        .controlSize(.regular)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DT.bg)
            }
        }
    }

    private func scoreCircle(_ label: String, score: Int) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(DT.border, lineWidth: 5)
                    .frame(width: 56, height: 56)
                Circle()
                    .trim(from: 0, to: CGFloat(score) / 100.0)
                    .stroke(
                        score >= 90 ? DT.success : score >= 50 ? DT.warning : DT.error,
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .frame(width: 56, height: 56)
                    .rotationEffect(.degrees(-90))
                Text("\(score)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(score >= 90 ? DT.success : score >= 50 ? DT.warning : DT.error)
            }
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(DT.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private func auditRow(_ audit: LighthouseAudit) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: audit.statusIcon)
                    .font(.system(size: 12))
                    .foregroundColor(audit.statusColor)
                Text(audit.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(DT.text)
                Spacer()
                Text(audit.category)
                    .font(.system(size: 10))
                    .foregroundColor(DT.textMuted)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(DT.inputBg)
                    .cornerRadius(3)
            }
            Text(audit.description)
                .font(.system(size: 12))
                .foregroundColor(DT.textSecondary)
            if !audit.details.isEmpty {
                Text(audit.details)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(DT.textMuted)
                    .lineLimit(2)
            }
        }
        .padding(8)
        .background(DT.inputBg.opacity(0.5))
        .cornerRadius(6)
    }

    private func runAudit() {
        guard let webView = browserState.currentTab?.webView else { return }
        devTools.lighthouseIsLoading = true

        webView.evaluateJavaScript(DevToolsScripts.lighthouseScript) { result, error in
            devTools.lighthouseIsLoading = false
            if let error = error {
                print("❌ Lighthouse error: \(error.localizedDescription)")
                return
            }
            guard let dict = result as? [String: Any] else {
                print("❌ Lighthouse: resultado no es diccionario")
                return
            }

            var lr = LighthouseResult()
            lr.timestamp = Date()

            func parseCategory(_ key: String, _ categoryName: String) -> (Int, [LighthouseAudit]) {
                guard let cat = dict[key] as? [String: Any] else { return (0, []) }
                let score = cat["score"] as? Int ?? 0
                var audits: [LighthouseAudit] = []
                if let items = cat["audits"] as? [[String: Any]] {
                    audits = items.compactMap { a in
                        guard let title = a["title"] as? String else { return nil }
                        let passed = a["passed"] as? Bool ?? false
                        return LighthouseAudit(
                            category: categoryName,
                            title: title,
                            description: a["description"] as? String ?? "",
                            score: passed ? 1.0 : 0.0,
                            impact: a["impact"] as? String ?? "low",
                            details: ""
                        )
                    }
                }
                return (score, audits)
            }

            let (perfScore, perfAudits) = parseCategory("performance", "Performance")
            let (a11yScore, a11yAudits) = parseCategory("accessibility", "Accessibility")
            let (bpScore, bpAudits) = parseCategory("bestPractices", "Best Practices")
            let (seoScore, seoAudits) = parseCategory("seo", "SEO")

            lr.performanceScore = perfScore
            lr.accessibilityScore = a11yScore
            lr.bestPracticesScore = bpScore
            lr.seoScore = seoScore
            lr.audits = perfAudits + a11yAudits + bpAudits + seoAudits

            devTools.lighthouseResult = lr
        }
    }
}

// MARK: - Device Emulation

enum DeviceProfile: String, CaseIterable {
    case none = "Sin emulación"
    case iphone14 = "iPhone 14"
    case iphone14pro = "iPhone 14 Pro Max"
    case ipadAir = "iPad Air"
    case ipadPro = "iPad Pro 12.9\""
    case pixel7 = "Pixel 7"
    case galaxyS23 = "Galaxy S23"
    case responsive = "Responsive"

    var width: Int {
        switch self {
        case .none: return 0
        case .iphone14: return 390
        case .iphone14pro: return 430
        case .ipadAir: return 820
        case .ipadPro: return 1024
        case .pixel7: return 412
        case .galaxyS23: return 360
        case .responsive: return 0
        }
    }

    var height: Int {
        switch self {
        case .none: return 0
        case .iphone14: return 844
        case .iphone14pro: return 932
        case .ipadAir: return 1180
        case .ipadPro: return 1366
        case .pixel7: return 915
        case .galaxyS23: return 800
        case .responsive: return 0
        }
    }

    var userAgent: String {
        switch self {
        case .none: return ""
        case .iphone14, .iphone14pro:
            return "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        case .ipadAir, .ipadPro:
            return "Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        case .pixel7:
            return "Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"
        case .galaxyS23:
            return "Mozilla/5.0 (Linux; Android 14; SM-S911B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"
        case .responsive: return ""
        }
    }

    var devicePixelRatio: Double {
        switch self {
        case .none: return 0
        case .iphone14: return 3
        case .iphone14pro: return 3
        case .ipadAir: return 2
        case .ipadPro: return 2
        case .pixel7: return 2.625
        case .galaxyS23: return 3
        case .responsive: return 2
        }
    }

    var icon: String {
        switch self {
        case .none: return "desktopcomputer"
        case .iphone14, .iphone14pro: return "iphone"
        case .ipadAir, .ipadPro: return "ipad"
        case .pixel7, .galaxyS23: return "smartphone"
        case .responsive: return "arrow.left.and.right"
        }
    }
}

struct DeviceEmulationPanel: View {
    @EnvironmentObject var browserState: BrowserState
    @StateObject private var devTools = DevToolsState.shared
    @State private var customWidth: String = "375"
    @State private var customHeight: String = "812"
    @State private var isLandscape: Bool = false

    var activeWidth: Int {
        if devTools.selectedDevice == .responsive {
            return Int(customWidth) ?? 375
        }
        let w = devTools.selectedDevice.width
        let h = devTools.selectedDevice.height
        return isLandscape ? h : w
    }

    var activeHeight: Int {
        if devTools.selectedDevice == .responsive {
            return Int(customHeight) ?? 812
        }
        let w = devTools.selectedDevice.width
        let h = devTools.selectedDevice.height
        return isLandscape ? w : h
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 8) {
                // Device selector
                Menu {
                    ForEach(DeviceProfile.allCases, id: \.self) { device in
                        Button(action: {
                            devTools.selectedDevice = device
                            if device == .none {
                                removeEmulation()
                            } else {
                                applyEmulation(device)
                            }
                        }) {
                            HStack {
                                Image(systemName: device.icon)
                                Text(device.rawValue)
                                if device.width > 0 {
                                    Text("(\(device.width)×\(device.height))")
                                        .foregroundColor(.secondary)
                                }
                                if device == devTools.selectedDevice {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: devTools.selectedDevice.icon)
                            .font(.system(size: 12))
                        Text(devTools.selectedDevice.rawValue)
                            .font(.system(size: 12))
                    }
                    .foregroundColor(devTools.selectedDevice == .none ? DT.textSecondary : DT.infoText)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(devTools.selectedDevice == .none ? Color.clear : DT.selectedBg)
                    .cornerRadius(4)
                }

                if devTools.selectedDevice != .none {
                    Divider().frame(height: 14)

                    // Landscape toggle
                    Button(action: {
                        isLandscape.toggle()
                        applyEmulation(devTools.selectedDevice)
                    }) {
                        Image(systemName: isLandscape ? "rectangle.landscape.rotate" : "rectangle.portrait.rotate")
                            .font(.system(size: 13))
                            .foregroundColor(DT.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .help(isLandscape ? "Modo vertical" : "Modo horizontal")

                    // Dimensions display
                    Text("\(activeWidth) × \(activeHeight)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(DT.text)
                }

                if devTools.selectedDevice == .responsive {
                    Divider().frame(height: 14)
                    HStack(spacing: 4) {
                        TextField("W", text: $customWidth)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(DT.text)
                            .frame(width: 40)
                            .padding(2)
                            .background(DT.inputBg)
                            .cornerRadius(3)
                        Text("×")
                            .foregroundColor(DT.textMuted)
                        TextField("H", text: $customHeight)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(DT.text)
                            .frame(width: 40)
                            .padding(2)
                            .background(DT.inputBg)
                            .cornerRadius(3)
                        Button("Aplicar") {
                            applyEmulation(.responsive)
                        }
                        .font(.system(size: 11))
                        .buttonStyle(.plain)
                        .foregroundColor(DT.link)
                    }
                }

                Spacer()

                if devTools.selectedDevice != .none {
                    Button("Resetear") {
                        devTools.selectedDevice = .none
                        isLandscape = false
                        removeEmulation()
                    }
                    .font(.system(size: 12))
                    .buttonStyle(.plain)
                    .foregroundColor(DT.link)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(DT.toolbarBg)

            Divider().overlay(DT.border)

            // Emulation status banner
            if devTools.selectedDevice != .none {
                HStack(spacing: 6) {
                    Image(systemName: devTools.selectedDevice.icon)
                        .font(.system(size: 12))
                    Text("Emulando: \(devTools.selectedDevice.rawValue) — \(activeWidth)×\(activeHeight) @\(String(format: "%.1f", devTools.selectedDevice.devicePixelRatio))x")
                        .font(.system(size: 12))
                    if !devTools.selectedDevice.userAgent.isEmpty {
                        Text("• UA móvil activo")
                            .font(.system(size: 11))
                            .foregroundColor(DT.textMuted)
                    }
                    Spacer()
                }
                .foregroundColor(DT.infoText)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(DT.selectedBg.opacity(0.5))
            }

            // Device grid
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Dispositivos")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(DT.text)

                    // Mobile
                    Text("Móviles")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DT.textSecondary)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        deviceCard(.iphone14)
                        deviceCard(.iphone14pro)
                        deviceCard(.pixel7)
                        deviceCard(.galaxyS23)
                    }

                    // Tablets
                    Text("Tablets")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DT.textSecondary)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        deviceCard(.ipadAir)
                        deviceCard(.ipadPro)
                    }

                    // Responsive
                    Text("Personalizado")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DT.textSecondary)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        deviceCard(.responsive)
                    }

                    Divider().overlay(DT.border)

                    // Info
                    VStack(alignment: .leading, spacing: 6) {
                        Text("¿Qué hace la emulación?")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(DT.text)
                        infoRow("📐", "Cambia el viewport CSS al tamaño del dispositivo")
                        infoRow("📱", "Inyecta User-Agent móvil (sitios responden diferente)")
                        infoRow("👆", "Simula touch events en vez de mouse events")
                        infoRow("🔍", "Ajusta devicePixelRatio para DPI correcto")
                        infoRow("⚠️", "No es un emulador real — es CSS viewport + UA spoofing")
                    }
                }
                .padding(12)
            }
            .background(DT.bg)
        }
    }

    private func deviceCard(_ device: DeviceProfile) -> some View {
        Button(action: {
            devTools.selectedDevice = device
            applyEmulation(device)
        }) {
            VStack(spacing: 6) {
                Image(systemName: device.icon)
                    .font(.system(size: 20))
                    .foregroundColor(devTools.selectedDevice == device ? DT.infoText : DT.textSecondary)
                Text(device.rawValue)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DT.text)
                    .lineLimit(1)
                if device.width > 0 {
                    Text("\(device.width)×\(device.height)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(DT.textMuted)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(8)
            .background(devTools.selectedDevice == device ? DT.selectedBg : DT.inputBg)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(devTools.selectedDevice == device ? DT.info : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func infoRow(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(icon).font(.system(size: 12))
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(DT.textSecondary)
        }
    }

    private func applyEmulation(_ device: DeviceProfile) {
        guard let webView = browserState.currentTab?.webView else { return }
        let w = activeWidth
        let h = activeHeight
        let ua = device.userAgent
        let dpr = device.devicePixelRatio

        // Set custom user agent
        if !ua.isEmpty {
            webView.customUserAgent = ua
        }

        // Inject viewport meta + CSS override + touch simulation
        webView.evaluateJavaScript("""
        (function() {
            // Viewport meta tag
            var meta = document.querySelector('meta[name="viewport"]');
            if (!meta) {
                meta = document.createElement('meta');
                meta.name = 'viewport';
                document.head.appendChild(meta);
            }
            meta.content = 'width=\(w), initial-scale=1, maximum-scale=1';

            // CSS viewport override
            var style = document.getElementById('mai-device-emulation');
            if (!style) {
                style = document.createElement('style');
                style.id = 'mai-device-emulation';
                document.head.appendChild(style);
            }
            style.textContent = `
                html {
                    width: \(w)px !important;
                    max-width: \(w)px !important;
                    overflow-x: hidden !important;
                }
                body {
                    width: \(w)px !important;
                    max-width: \(w)px !important;
                    overflow-x: hidden !important;
                }
            `;

            // Override screen properties
            try {
                Object.defineProperty(window, 'innerWidth', {value: \(w), writable: true, configurable: true});
                Object.defineProperty(window, 'innerHeight', {value: \(h), writable: true, configurable: true});
                Object.defineProperty(screen, 'width', {value: \(w), writable: true, configurable: true});
                Object.defineProperty(screen, 'height', {value: \(h), writable: true, configurable: true});
                Object.defineProperty(screen, 'availWidth', {value: \(w), writable: true, configurable: true});
                Object.defineProperty(screen, 'availHeight', {value: \(h), writable: true, configurable: true});
                Object.defineProperty(window, 'devicePixelRatio', {value: \(dpr), writable: true, configurable: true});
            } catch(e) {}

            // Simulate touch capability
            if (!('ontouchstart' in window)) {
                Object.defineProperty(window, 'ontouchstart', {value: null, writable: true, configurable: true});
                Object.defineProperty(navigator, 'maxTouchPoints', {value: 5, writable: true, configurable: true});
            }

            // Trigger resize event so responsive CSS/JS reacts
            window.dispatchEvent(new Event('resize'));

            // Trigger media query check
            if (window.matchMedia) {
                window.dispatchEvent(new MediaQueryListEvent('change', {media: '(max-width: \(w)px)', matches: true}));
            }

            console.log('[MAI] Device emulation: \(device.rawValue) (\(w)×\(h) @\(dpr)x)');
        })();
        """) { _, _ in }

        devTools.deviceEmulationActive = true
    }

    private func removeEmulation() {
        guard let webView = browserState.currentTab?.webView else { return }

        // Reset user agent
        webView.customUserAgent = nil

        // Remove CSS and overrides
        webView.evaluateJavaScript("""
        (function() {
            var style = document.getElementById('mai-device-emulation');
            if (style) style.remove();

            // Remove viewport override — restore original or remove
            var meta = document.querySelector('meta[name="viewport"]');
            if (meta && meta.content.includes('\(DeviceProfile.iphone14.width)')) {
                meta.content = 'width=device-width, initial-scale=1';
            }

            // Can't easily undo defineProperty but resize event will help
            window.dispatchEvent(new Event('resize'));
            console.log('[MAI] Device emulation desactivada');
        })();
        """) { _, _ in }

        devTools.deviceEmulationActive = false
    }
}

// MARK: - JavaScript Scripts for DevTools

enum DevToolsScripts {
    /// Intercepta console.log/warn/error/info/debug y los envía al DevTools nativo
    static let consoleInterceptor = """
    (function() {
        if (window.__maiDevToolsConsole) return;
        window.__maiDevToolsConsole = true;

        var levels = ['log', 'info', 'warn', 'error', 'debug'];
        levels.forEach(function(level) {
            var original = console[level];
            console[level] = function() {
                // Llamar al original
                original.apply(console, arguments);
                // Enviar al DevTools de MAI
                try {
                    var args = Array.from(arguments).map(function(arg) {
                        if (typeof arg === 'object') {
                            try { return JSON.stringify(arg, null, 2); } catch(e) { return String(arg); }
                        }
                        return String(arg);
                    });
                    var msg = args.join(' ');
                    var error = new Error();
                    var stack = error.stack ? error.stack.split('\\n') : [];
                    var source = stack.length > 2 ? stack[2].trim() : '';
                    window.webkit.messageHandlers.maiDevToolsConsole.postMessage({
                        level: level,
                        message: msg,
                        source: source,
                        timestamp: Date.now()
                    });
                } catch(e) {}
            };
        });

        // Interceptar errores no capturados
        window.addEventListener('error', function(e) {
            try {
                window.webkit.messageHandlers.maiDevToolsConsole.postMessage({
                    level: 'error',
                    message: e.message + (e.filename ? ' at ' + e.filename + ':' + e.lineno : ''),
                    source: e.filename || '',
                    timestamp: Date.now()
                });
            } catch(ex) {}
        });

        // Interceptar promise rejections
        window.addEventListener('unhandledrejection', function(e) {
            try {
                window.webkit.messageHandlers.maiDevToolsConsole.postMessage({
                    level: 'error',
                    message: 'Unhandled Promise Rejection: ' + (e.reason ? (e.reason.message || String(e.reason)) : 'unknown'),
                    source: '',
                    timestamp: Date.now()
                });
            } catch(ex) {}
        });
    })();
    """

    /// Intercepta fetch/XHR para monitoreo de red
    static let networkInterceptor = """
    (function() {
        if (window.__maiDevToolsNetwork) return;
        window.__maiDevToolsNetwork = true;
        window.__maiNetworkLog = [];
        window.__maiSentURLs = new Set();

        var navStart = performance.timeOrigin || 0;

        function classifyEntry(e) {
            var init = (e.initiatorType || '').toLowerCase();
            var url = e.name.toLowerCase();
            if (e.entryType === 'navigation') return 'document';
            if (init === 'xmlhttprequest') return 'xhr';
            if (init === 'fetch') return 'fetch';
            if (init === 'beacon') return 'xhr';
            if (url.match(/\\.js(\\?|#|$)/i) || init === 'script') return 'script';
            if (url.match(/\\.css(\\?|#|$)/i) || init === 'link' || init === 'css') return 'stylesheet';
            if (url.match(/\\.(png|jpg|jpeg|gif|svg|webp|ico|avif|bmp)(\\?|#|$)/i) || init === 'img' || init === 'image') return 'image';
            if (url.match(/\\.(woff|woff2|ttf|eot|otf)(\\?|#|$)/i)) return 'font';
            if (url.match(/\\.(mp4|webm|ogg|mp3|wav|m3u8|mpd|flac|aac)(\\?|#|$)/i) || init === 'video' || init === 'audio') return 'media';
            if (url.match(/\\.(html|htm)(\\?|#|$)/i)) return 'document';
            if (url.match(/manifest\\.json|site\\.webmanifest/i)) return 'manifest';
            if (url.match(/\\.wasm(\\?|#|$)/i)) return 'wasm';
            if (init === 'iframe') return 'document';
            return 'other';
        }

        function postEntry(e) {
            if (window.__maiSentURLs.has(e.name)) return;
            window.__maiSentURLs.add(e.name);
            var navBase = performance.getEntriesByType('navigation');
            var t0 = navBase.length > 0 ? navBase[0].startTime : 0;
            var entry = {
                method: 'GET',
                url: e.name,
                status: e.responseStatus || 200,
                type: classifyEntry(e),
                duration: Math.round(e.responseEnd - e.startTime),
                size: Math.round(e.transferSize || e.encodedBodySize || 0),
                initiator: e.initiatorType || (e.entryType === 'navigation' ? 'navigation' : ''),
                startTime: Math.round(e.startTime - t0),
                connectEnd: Math.round((e.connectEnd || 0) - t0),
                requestStart: Math.round((e.requestStart || 0) - t0),
                responseStart: Math.round((e.responseStart || 0) - t0),
                responseEnd: Math.round((e.responseEnd || 0) - t0)
            };
            try {
                window.webkit.messageHandlers.maiDevToolsNetwork.postMessage(entry);
            } catch(ex) {}
        }

        // 1. PerformanceObserver — captura TODOS los recursos en tiempo real
        try {
            var obs = new PerformanceObserver(function(list) {
                list.getEntries().forEach(postEntry);
            });
            obs.observe({ type: 'resource', buffered: true });
            // También observar navigation
            try {
                var navObs = new PerformanceObserver(function(list) {
                    list.getEntries().forEach(postEntry);
                });
                navObs.observe({ type: 'navigation', buffered: true });
            } catch(ne) {}
        } catch(oe) {
            // Fallback: enviar las que ya existen
            performance.getEntriesByType('navigation').forEach(postEntry);
            performance.getEntriesByType('resource').forEach(postEntry);
        }

        // 2. Interceptar fetch — captura método, headers, status real
        var originalFetch = window.fetch;
        window.fetch = function() {
            var url = arguments[0];
            if (typeof url === 'object' && url.url) url = url.url;
            else if (typeof url === 'object' && url instanceof Request) url = url.url;
            var method = (arguments[1] && arguments[1].method) || 'GET';
            var start = performance.now();

            return originalFetch.apply(this, arguments).then(function(response) {
                var key = String(url);
                if (!window.__maiSentURLs.has(key)) {
                    window.__maiSentURLs.add(key);
                    try {
                        window.webkit.messageHandlers.maiDevToolsNetwork.postMessage({
                            method: method,
                            url: key,
                            status: response.status,
                            type: 'fetch',
                            duration: Math.round(performance.now() - start),
                            size: parseInt(response.headers.get('content-length') || '0'),
                            initiator: 'fetch',
                            startTime: Math.round(start), connectEnd: 0, requestStart: Math.round(start),
                            responseStart: Math.round(performance.now()), responseEnd: Math.round(performance.now())
                        });
                    } catch(ex) {}
                }
                return response;
            }).catch(function(err) {
                try {
                    window.webkit.messageHandlers.maiDevToolsNetwork.postMessage({
                        method: method, url: String(url), status: 0, type: 'fetch',
                        duration: Math.round(performance.now() - start), size: 0,
                        initiator: 'fetch (error)', startTime: Math.round(start),
                        connectEnd: 0, requestStart: 0, responseStart: 0, responseEnd: Math.round(performance.now())
                    });
                } catch(ex) {}
                throw err;
            });
        };

        // 3. Interceptar XMLHttpRequest
        var XHR = XMLHttpRequest.prototype;
        var originalOpen = XHR.open;
        var originalSend = XHR.send;
        XHR.open = function(method, url) {
            this.__maiMethod = method;
            this.__maiURL = url;
            return originalOpen.apply(this, arguments);
        };
        XHR.send = function() {
            var xhr = this;
            var start = performance.now();
            xhr.addEventListener('loadend', function() {
                var key = String(xhr.__maiURL || '');
                if (!window.__maiSentURLs.has(key)) {
                    window.__maiSentURLs.add(key);
                    try {
                        window.webkit.messageHandlers.maiDevToolsNetwork.postMessage({
                            method: xhr.__maiMethod || 'GET', url: key,
                            status: xhr.status, type: 'xhr',
                            duration: Math.round(performance.now() - start),
                            size: parseInt(xhr.getResponseHeader('content-length') || '0'),
                            initiator: 'XMLHttpRequest',
                            startTime: Math.round(start), connectEnd: 0, requestStart: Math.round(start),
                            responseStart: Math.round(performance.now()), responseEnd: Math.round(performance.now())
                        });
                    } catch(ex) {}
                }
            });
            return originalSend.apply(this, arguments);
        };

        // 4. Interceptar WebSocket
        var OrigWebSocket = window.WebSocket;
        window.WebSocket = function(url, protocols) {
            var ws = protocols ? new OrigWebSocket(url, protocols) : new OrigWebSocket(url);
            try {
                window.webkit.messageHandlers.maiDevToolsNetwork.postMessage({
                    method: 'WS', url: String(url), status: 101, type: 'websocket',
                    size: 0, duration: 0, initiator: 'WebSocket',
                    startTime: Math.round(performance.now()), connectEnd: 0,
                    requestStart: 0, responseStart: 0, responseEnd: 0
                });
            } catch(ex) {}
            return ws;
        };
        window.WebSocket.prototype = OrigWebSocket.prototype;

        // 5. Interceptar EventSource (SSE)
        if (window.EventSource) {
            var OrigES = window.EventSource;
            window.EventSource = function(url, config) {
                var es = config ? new OrigES(url, config) : new OrigES(url);
                try {
                    window.webkit.messageHandlers.maiDevToolsNetwork.postMessage({
                        method: 'GET', url: String(url), status: 200, type: 'xhr',
                        size: 0, duration: 0, initiator: 'EventSource',
                        startTime: Math.round(performance.now()), connectEnd: 0,
                        requestStart: 0, responseStart: 0, responseEnd: 0
                    });
                } catch(ex) {}
                return es;
            };
            window.EventSource.prototype = OrigES.prototype;
        }

        // 6. Hook History API para SPA navigations (Google, YouTube, etc.)
        var origPushState = history.pushState;
        var origReplaceState = history.replaceState;
        function onSPANavigate(url) {
            try {
                window.webkit.messageHandlers.maiDevToolsNetwork.postMessage({
                    method: 'GET', url: String(url), status: 200, type: 'document',
                    size: 0, duration: 0, initiator: 'pushState',
                    startTime: Math.round(performance.now()), connectEnd: 0,
                    requestStart: Math.round(performance.now()), responseStart: Math.round(performance.now()),
                    responseEnd: Math.round(performance.now())
                });
            } catch(ex) {}
            window.__maiSentURLs.clear();
        }
        history.pushState = function() {
            var result = origPushState.apply(this, arguments);
            onSPANavigate(arguments[2] || location.href);
            return result;
        };
        history.replaceState = function() {
            var result = origReplaceState.apply(this, arguments);
            onSPANavigate(arguments[2] || location.href);
            return result;
        };
        window.addEventListener('popstate', function() {
            onSPANavigate(location.href);
        });
    })();
    """

    /// Captura datos de red del Performance API (navigation + resource + fetch/XHR interceptados)
    static let networkCaptureScript = """
    (function() {
        // 1. Capturar la navegación principal (document)
        var navEntries = performance.getEntriesByType('navigation');
        var resourceEntries = performance.getEntriesByType('resource');
        var intercepted = window.__maiNetworkLog || [];
        var allPerf = navEntries.concat(resourceEntries);

        // Timestamp base para waterfall (startTime de la navegación)
        var navStart = navEntries.length > 0 ? navEntries[0].startTime : 0;

        function classifyType(e) {
            // Navigation entries son siempre document
            if (e.entryType === 'navigation') return 'document';
            var init = (e.initiatorType || '').toLowerCase();
            var url = e.name.toLowerCase();
            if (init === 'xmlhttprequest' || init === 'fetch') return init;
            if (init === 'beacon') return 'xhr';
            // Por extensión
            if (url.match(/\\.js(\\?|#|$)/i)) return 'script';
            if (url.match(/\\.css(\\?|#|$)/i)) return 'stylesheet';
            if (url.match(/\\.(png|jpg|jpeg|gif|svg|webp|ico|avif|bmp)(\\?|#|$)/i)) return 'image';
            if (url.match(/\\.(woff|woff2|ttf|eot|otf)(\\?|#|$)/i)) return 'font';
            if (url.match(/\\.(mp4|webm|ogg|mp3|wav|m3u8|mpd|flac|aac)(\\?|#|$)/i)) return 'media';
            if (url.match(/\\.(html|htm)(\\?|#|$)/i)) return 'document';
            if (url.match(/manifest\\.json|site\\.webmanifest/i)) return 'manifest';
            if (url.match(/\\.wasm(\\?|#|$)/i)) return 'wasm';
            // Por initiatorType
            if (init === 'img' || init === 'image') return 'image';
            if (init === 'script') return 'script';
            if (init === 'link' || init === 'css') return 'stylesheet';
            if (init === 'video' || init === 'audio') return 'media';
            return 'other';
        }

        var result = allPerf.map(function(e) {
            var startMs = Math.round(e.startTime - navStart);
            var durationMs = Math.round(e.responseEnd - e.startTime);
            return {
                name: e.name,
                method: e.entryType === 'navigation' ? (performance.navigation ? ['GET','GET','GET','GET'][performance.navigation.type] || 'GET' : 'GET') : 'GET',
                status: e.responseStatus || (e.entryType === 'navigation' ? 200 : 200),
                type: classifyType(e),
                size: Math.round(e.transferSize || e.encodedBodySize || 0),
                duration: durationMs,
                initiator: e.initiatorType || (e.entryType === 'navigation' ? 'navigation' : ''),
                startTime: startMs,
                connectEnd: Math.round((e.connectEnd || 0) - navStart),
                requestStart: Math.round((e.requestStart || 0) - navStart),
                responseStart: Math.round((e.responseStart || 0) - navStart),
                responseEnd: Math.round((e.responseEnd || 0) - navStart)
            };
        });

        // Agregar fetch/XHR interceptados que no estén en Performance API
        intercepted.forEach(function(entry) {
            if (!result.find(function(r) { return r.name === entry.url; })) {
                result.push({
                    name: entry.url,
                    method: entry.method,
                    status: entry.status,
                    type: entry.type,
                    size: entry.size || 0,
                    duration: entry.duration || 0,
                    initiator: entry.initiator || '',
                    startTime: 0, connectEnd: 0, requestStart: 0, responseStart: 0, responseEnd: entry.duration || 0
                });
            }
        });

        // Ordenar por startTime
        result.sort(function(a, b) { return a.startTime - b.startTime; });

        return JSON.stringify(result);
    })();
    """

    /// Obtiene el árbol DOM simplificado
    static let domTreeScript = """
    (function() {
        function serializeNode(node, depth, index) {
            if (depth > 6) return null;
            if (node.nodeType !== 1) return null;

            var tag = node.tagName.toLowerCase();
            // Skip script/style/svg content
            if (tag === 'script' || tag === 'style' || tag === 'noscript') {
                return {tag: tag, attrs: [], text: null, children: [], index: index};
            }

            var attrs = [];
            for (var i = 0; i < Math.min(node.attributes.length, 5); i++) {
                attrs.push({name: node.attributes[i].name, value: node.attributes[i].value});
            }

            var text = null;
            if (node.childNodes.length === 1 && node.childNodes[0].nodeType === 3) {
                var t = node.childNodes[0].textContent.trim();
                if (t.length > 0) text = t.substring(0, 80);
            }

            var children = [];
            var childIndex = 0;
            for (var j = 0; j < node.children.length && children.length < 50; j++) {
                var child = serializeNode(node.children[j], depth + 1, childIndex);
                if (child) {
                    children.push(child);
                    childIndex++;
                }
            }

            return {tag: tag, attrs: attrs, text: text, children: children, index: index};
        }

        var html = serializeNode(document.documentElement, 0, 0);
        return JSON.stringify(html ? [html] : []);
    })();
    """

    /// Lee localStorage
    static let localStorageScript = """
    (function() {
        try {
            var items = [];
            for (var i = 0; i < localStorage.length; i++) {
                var key = localStorage.key(i);
                items.push({key: key, value: localStorage.getItem(key).substring(0, 500)});
            }
            return JSON.stringify(items);
        } catch(e) { return '[]'; }
    })();
    """

    /// Lee sessionStorage
    static let sessionStorageScript = """
    (function() {
        try {
            var items = [];
            for (var i = 0; i < sessionStorage.length; i++) {
                var key = sessionStorage.key(i);
                items.push({key: key, value: sessionStorage.getItem(key).substring(0, 500)});
            }
            return JSON.stringify(items);
        } catch(e) { return '[]'; }
    })();
    """

    /// Analiza CSS y detecta declaraciones sin efecto con explicación
    static let cssDebugScript = """
    (function() {
        var issues = [];
        var checked = 0;
        var allElements = document.querySelectorAll('*');
        var maxElements = Math.min(allElements.length, 500);

        for (var i = 0; i < maxElements; i++) {
            var el = allElements[i];
            if (!el.style || el.style.length === 0) continue;

            var computed = window.getComputedStyle(el);
            var display = computed.display;
            var position = computed.position;
            var parentDisplay = el.parentElement ? window.getComputedStyle(el.parentElement).display : '';
            var tag = el.tagName.toLowerCase();
            var selector = tag;
            if (el.id) selector += '#' + el.id;
            else if (el.className && typeof el.className === 'string') selector += '.' + el.className.split(' ')[0];

            for (var j = 0; j < el.style.length; j++) {
                var prop = el.style[j];
                var val = el.style.getPropertyValue(prop);
                var issue = null;

                // display:inline ignora width/height/margin-top/margin-bottom
                if (display === 'inline') {
                    if (prop === 'width' || prop === 'height') {
                        issue = {prop: prop, value: val, selector: selector, reason: 'Los elementos inline ignoran width/height. Usa display:inline-block o display:block.', severity: 'error'};
                    }
                    if (prop === 'margin-top' || prop === 'margin-bottom') {
                        issue = {prop: prop, value: val, selector: selector, reason: 'Los elementos inline ignoran margin-top/bottom. Usa display:inline-block.', severity: 'warn'};
                    }
                    if (prop === 'padding-top' || prop === 'padding-bottom') {
                        issue = {prop: prop, value: val, selector: selector, reason: 'padding-top/bottom en inline no afecta el layout (no empuja elementos). Usa inline-block.', severity: 'warn'};
                    }
                }

                // flex/grid properties sin parent flex/grid
                if ((prop === 'flex' || prop === 'flex-grow' || prop === 'flex-shrink' || prop === 'flex-basis' || prop === 'align-self' || prop === 'order') && parentDisplay !== 'flex' && parentDisplay !== 'inline-flex') {
                    issue = {prop: prop, value: val, selector: selector, reason: 'Propiedad flex sin efecto: el padre no tiene display:flex.', severity: 'error'};
                }
                if ((prop === 'grid-column' || prop === 'grid-row' || prop === 'grid-area' || prop === 'justify-self') && parentDisplay !== 'grid' && parentDisplay !== 'inline-grid') {
                    issue = {prop: prop, value: val, selector: selector, reason: 'Propiedad grid sin efecto: el padre no tiene display:grid.', severity: 'error'};
                }

                // gap sin flex/grid
                if (prop === 'gap' || prop === 'row-gap' || prop === 'column-gap') {
                    if (display !== 'flex' && display !== 'inline-flex' && display !== 'grid' && display !== 'inline-grid') {
                        issue = {prop: prop, value: val, selector: selector, reason: 'gap solo funciona con display:flex o display:grid.', severity: 'error'};
                    }
                }

                // position properties sin position
                if ((prop === 'top' || prop === 'right' || prop === 'bottom' || prop === 'left') && position === 'static') {
                    issue = {prop: prop, value: val, selector: selector, reason: prop + ' no tiene efecto con position:static. Usa relative, absolute, fixed o sticky.', severity: 'error'};
                }
                if (prop === 'z-index' && position === 'static' && display !== 'flex' && display !== 'grid') {
                    issue = {prop: prop, value: val, selector: selector, reason: 'z-index no tiene efecto con position:static (excepto en flex/grid items).', severity: 'error'};
                }

                // overflow en inline
                if ((prop === 'overflow' || prop === 'overflow-x' || prop === 'overflow-y') && display === 'inline') {
                    issue = {prop: prop, value: val, selector: selector, reason: 'overflow no funciona en elementos inline. Necesita block o inline-block.', severity: 'warn'};
                }

                // vertical-align en block
                if (prop === 'vertical-align' && (display === 'block' || display === 'flex' || display === 'grid')) {
                    issue = {prop: prop, value: val, selector: selector, reason: 'vertical-align no funciona en elementos block. Solo aplica a inline y table-cell.', severity: 'error'};
                }

                // float en flex/grid child
                if (prop === 'float' && (parentDisplay === 'flex' || parentDisplay === 'grid')) {
                    issue = {prop: prop, value: val, selector: selector, reason: 'float es ignorado en hijos de flex/grid. Usa propiedades de alineación.', severity: 'warn'};
                }

                // clear sin float context
                if (prop === 'clear' && (parentDisplay === 'flex' || parentDisplay === 'grid')) {
                    issue = {prop: prop, value: val, selector: selector, reason: 'clear es ignorado dentro de contenedores flex/grid.', severity: 'warn'};
                }

                // margin:auto centering issues
                if ((prop === 'margin-left' || prop === 'margin-right') && val === 'auto' && display === 'inline') {
                    issue = {prop: prop, value: val, selector: selector, reason: 'margin:auto no centra elementos inline. Usa text-align:center en el padre o cambia a block/inline-block.', severity: 'warn'};
                }

                // text-overflow sin overflow:hidden
                if (prop === 'text-overflow' && val === 'ellipsis') {
                    var ov = computed.overflow;
                    var ws = computed.whiteSpace;
                    if (ov !== 'hidden' && ov !== 'clip') {
                        issue = {prop: prop, value: val, selector: selector, reason: 'text-overflow:ellipsis necesita overflow:hidden y white-space:nowrap para funcionar.', severity: 'error'};
                    }
                }

                // transform en inline
                if (prop === 'transform' && display === 'inline') {
                    issue = {prop: prop, value: val, selector: selector, reason: 'transform no funciona en elementos inline. Usa inline-block o block.', severity: 'error'};
                }

                // justify-content/align-items sin flex/grid
                if ((prop === 'justify-content' || prop === 'align-items' || prop === 'align-content' || prop === 'flex-direction' || prop === 'flex-wrap') && display !== 'flex' && display !== 'inline-flex' && display !== 'grid' && display !== 'inline-grid') {
                    issue = {prop: prop, value: val, selector: selector, reason: prop + ' solo funciona con display:flex o display:grid.', severity: 'error'};
                }

                // opacity/visibility redundancy check
                if (prop === 'opacity' && val === '0' && computed.visibility === 'hidden') {
                    issue = {prop: prop, value: val, selector: selector, reason: 'Redundante: opacity:0 y visibility:hidden juntos. Uno es suficiente.', severity: 'info'};
                }

                // width/height en flex con flex-basis
                if ((prop === 'width' || prop === 'height') && parentDisplay === 'flex') {
                    var basis = el.style.getPropertyValue('flex-basis');
                    if (basis && basis !== '' && basis !== 'auto') {
                        var dir = window.getComputedStyle(el.parentElement).flexDirection;
                        if ((dir === 'row' && prop === 'width') || (dir === 'column' && prop === 'height')) {
                            issue = {prop: prop, value: val, selector: selector, reason: prop + ' es sobreescrito por flex-basis:' + basis + ' en dirección ' + dir + '.', severity: 'warn'};
                        }
                    }
                }

                if (issue) {
                    issues.push(issue);
                    if (issues.length >= 200) break;
                }
            }
            checked++;
            if (issues.length >= 200) break;
        }

        // También verificar hojas de estilo
        try {
            for (var s = 0; s < document.styleSheets.length && issues.length < 200; s++) {
                try {
                    var sheet = document.styleSheets[s];
                    if (!sheet.cssRules) continue;
                    for (var r = 0; r < sheet.cssRules.length && issues.length < 200; r++) {
                        var rule = sheet.cssRules[r];
                        if (rule.type !== 1) continue; // Solo style rules
                        var sel = rule.selectorText;
                        if (!sel) continue;

                        try {
                            var matched = document.querySelectorAll(sel);
                            if (matched.length === 0 && !sel.includes(':hover') && !sel.includes(':focus') && !sel.includes(':active') && !sel.includes('::') && !sel.includes(':nth') && !sel.includes(':not') && !sel.includes('@')) {
                                issues.push({prop: '(selector)', value: sel, selector: sel, reason: 'Selector sin match: ningún elemento en la página coincide con este selector. Posible código CSS muerto.', severity: 'info'});
                            }
                        } catch(e) {}
                    }
                } catch(e) {} // CORS blocks cross-origin stylesheets
            }
        } catch(e) {}

        return JSON.stringify({issues: issues, elementsChecked: checked, totalElements: allElements.length});
    })();
    """

    /// Obtiene datos del DOM para visualización 3D
    static let dom3DScript = """
    (function() {
        var nodes = [];
        var maxNodes = 300;

        function walkDOM(el, depth) {
            if (nodes.length >= maxNodes) return;
            if (el.nodeType !== 1) return;
            var tag = el.tagName.toLowerCase();
            if (tag === 'script' || tag === 'style' || tag === 'noscript' || tag === 'link' || tag === 'meta') return;

            var rect = el.getBoundingClientRect();
            if (rect.width === 0 && rect.height === 0) return;

            var computed = window.getComputedStyle(el);
            if (computed.display === 'none' || computed.visibility === 'hidden') return;

            nodes.push({
                tag: tag,
                id: el.id || '',
                cls: (typeof el.className === 'string') ? el.className.split(' ')[0] : '',
                x: Math.round(rect.left),
                y: Math.round(rect.top),
                w: Math.round(rect.width),
                h: Math.round(rect.height),
                d: depth,
                bg: computed.backgroundColor,
                children: el.children.length
            });

            for (var i = 0; i < el.children.length; i++) {
                walkDOM(el.children[i], depth + 1);
            }
        }

        walkDOM(document.body, 0);
        return JSON.stringify({
            nodes: nodes,
            pageWidth: document.documentElement.scrollWidth,
            pageHeight: document.documentElement.scrollHeight,
            viewportWidth: window.innerWidth,
            viewportHeight: window.innerHeight
        });
    })();
    """

    /// Auditoría de accesibilidad completa
    static let accessibilityAuditScript = """
    (function() {
        var issues = [];
        var passed = 0;

        // 1. Imágenes sin alt
        document.querySelectorAll('img').forEach(function(img) {
            if (!img.hasAttribute('alt')) {
                issues.push({type: 'error', category: 'Imágenes', message: 'Imagen sin atributo alt', selector: describeElement(img), fix: 'Agrega alt="descripción" a la imagen'});
            } else if (img.alt.trim() === '' && !img.getAttribute('role')) {
                issues.push({type: 'warn', category: 'Imágenes', message: 'Imagen con alt vacío sin role="presentation"', selector: describeElement(img), fix: 'Si es decorativa, agrega role="presentation". Si no, describe la imagen.'});
            } else { passed++; }
        });

        // 2. Formularios sin labels
        document.querySelectorAll('input, select, textarea').forEach(function(input) {
            if (input.type === 'hidden' || input.type === 'submit' || input.type === 'button') return;
            var hasLabel = input.id && document.querySelector('label[for="' + input.id + '"]');
            var hasAriaLabel = input.getAttribute('aria-label') || input.getAttribute('aria-labelledby');
            var hasTitle = input.title;
            var wrappedInLabel = input.closest('label');
            if (!hasLabel && !hasAriaLabel && !hasTitle && !wrappedInLabel) {
                issues.push({type: 'error', category: 'Formularios', message: 'Campo de formulario sin label asociado', selector: describeElement(input), fix: 'Agrega <label for="' + (input.id || 'id') + '"> o aria-label'});
            } else { passed++; }
        });

        // 3. Jerarquía de headings
        var headings = document.querySelectorAll('h1, h2, h3, h4, h5, h6');
        var prevLevel = 0;
        var h1Count = 0;
        headings.forEach(function(h) {
            var level = parseInt(h.tagName[1]);
            if (level === 1) h1Count++;
            if (prevLevel > 0 && level > prevLevel + 1) {
                issues.push({type: 'warn', category: 'Encabezados', message: 'Salto en jerarquía: h' + prevLevel + ' → h' + level + ' (falta h' + (prevLevel + 1) + ')', selector: describeElement(h), fix: 'Usa h' + (prevLevel + 1) + ' para mantener la jerarquía'});
            } else { passed++; }
            prevLevel = level;
        });
        if (h1Count === 0) {
            issues.push({type: 'warn', category: 'Encabezados', message: 'La página no tiene ningún h1', selector: 'document', fix: 'Agrega un <h1> como título principal de la página'});
        } else if (h1Count > 1) {
            issues.push({type: 'info', category: 'Encabezados', message: 'La página tiene ' + h1Count + ' elementos h1 (recomendado: solo 1)', selector: 'document', fix: 'Usa solo un <h1> como título principal'});
        }

        // 4. Links sin texto
        document.querySelectorAll('a').forEach(function(a) {
            var text = (a.textContent || '').trim();
            var ariaLabel = a.getAttribute('aria-label');
            var img = a.querySelector('img[alt]');
            if (!text && !ariaLabel && !img) {
                issues.push({type: 'error', category: 'Enlaces', message: 'Enlace sin texto accesible', selector: describeElement(a), fix: 'Agrega texto al enlace o aria-label'});
            } else if (text === 'click aquí' || text === 'aquí' || text === 'leer más' || text === 'more' || text === 'click here' || text === 'here' || text === 'read more') {
                issues.push({type: 'warn', category: 'Enlaces', message: 'Texto de enlace genérico: "' + text + '"', selector: describeElement(a), fix: 'Usa texto descriptivo que indique el destino del enlace'});
            } else { passed++; }
        });

        // 5. Contraste de color (verificación básica)
        var textElements = document.querySelectorAll('p, span, a, li, td, th, h1, h2, h3, h4, h5, h6, label, button');
        var contrastChecked = 0;
        textElements.forEach(function(el) {
            if (contrastChecked >= 50) return;
            var computed = window.getComputedStyle(el);
            var color = computed.color;
            var bg = getEffectiveBackground(el);
            if (color && bg) {
                var ratio = getContrastRatio(parseColor(color), parseColor(bg));
                if (ratio > 0 && ratio < 3) {
                    issues.push({type: 'error', category: 'Contraste', message: 'Contraste muy bajo (' + ratio.toFixed(1) + ':1). Mínimo WCAG AA: 4.5:1', selector: describeElement(el), fix: 'Aumenta el contraste entre texto (' + color + ') y fondo (' + bg + ')'});
                } else if (ratio >= 3 && ratio < 4.5) {
                    issues.push({type: 'warn', category: 'Contraste', message: 'Contraste insuficiente (' + ratio.toFixed(1) + ':1). WCAG AA requiere 4.5:1', selector: describeElement(el), fix: 'Ajusta los colores para alcanzar ratio 4.5:1'});
                } else { passed++; }
                contrastChecked++;
            }
        });

        // 6. Landmarks ARIA
        var hasMain = document.querySelector('main, [role="main"]');
        var hasNav = document.querySelector('nav, [role="navigation"]');
        var hasBanner = document.querySelector('header, [role="banner"]');
        if (!hasMain) issues.push({type: 'warn', category: 'Landmarks', message: 'Falta landmark <main> o role="main"', selector: 'document', fix: 'Envuelve el contenido principal en <main>'});
        else passed++;
        if (!hasNav) issues.push({type: 'info', category: 'Landmarks', message: 'No se detectó <nav> o role="navigation"', selector: 'document', fix: 'Envuelve la navegación en <nav>'});
        else passed++;

        // 7. Lang attribute
        var htmlLang = document.documentElement.getAttribute('lang');
        if (!htmlLang) {
            issues.push({type: 'error', category: 'Documento', message: 'Falta atributo lang en <html>', selector: 'html', fix: 'Agrega lang="es" (o el idioma correspondiente) a <html>'});
        } else { passed++; }

        // 8. Tabindex positivo (anti-pattern)
        document.querySelectorAll('[tabindex]').forEach(function(el) {
            var val = parseInt(el.getAttribute('tabindex'));
            if (val > 0) {
                issues.push({type: 'warn', category: 'Teclado', message: 'tabindex positivo (' + val + ') altera el orden natural de tabulación', selector: describeElement(el), fix: 'Usa tabindex="0" para orden natural o tabindex="-1" para programático'});
            }
        });

        // 9. Autoplay videos
        document.querySelectorAll('video[autoplay], audio[autoplay]').forEach(function(el) {
            if (!el.muted) {
                issues.push({type: 'error', category: 'Multimedia', message: 'Video/audio con autoplay sin mute', selector: describeElement(el), fix: 'Agrega muted o elimina autoplay'});
            }
        });

        // 10. Botones sin texto
        document.querySelectorAll('button').forEach(function(btn) {
            var text = (btn.textContent || '').trim();
            var ariaLabel = btn.getAttribute('aria-label');
            var title = btn.title;
            if (!text && !ariaLabel && !title && !btn.querySelector('img[alt]')) {
                issues.push({type: 'error', category: 'Botones', message: 'Botón sin texto accesible', selector: describeElement(btn), fix: 'Agrega texto, aria-label o title al botón'});
            } else { passed++; }
        });

        // 11. Skip navigation link
        var firstLink = document.querySelector('a');
        var hasSkipLink = false;
        if (firstLink) {
            var href = firstLink.getAttribute('href') || '';
            var text = (firstLink.textContent || '').toLowerCase();
            hasSkipLink = href.startsWith('#') && (text.includes('skip') || text.includes('saltar') || text.includes('ir al contenido'));
        }
        if (!hasSkipLink && document.querySelectorAll('a').length > 10) {
            issues.push({type: 'info', category: 'Navegación', message: 'No se detectó "skip to content" link', selector: 'document', fix: 'Agrega un enlace al inicio que salte al contenido principal'});
        }

        // Helper functions
        function describeElement(el) {
            var desc = el.tagName.toLowerCase();
            if (el.id) desc += '#' + el.id;
            else if (el.className && typeof el.className === 'string') desc += '.' + el.className.split(' ')[0];
            var text = (el.textContent || '').trim().substring(0, 30);
            if (text) desc += ' "' + text + (el.textContent.trim().length > 30 ? '...' : '') + '"';
            return desc;
        }

        function getEffectiveBackground(el) {
            var current = el;
            while (current) {
                var bg = window.getComputedStyle(current).backgroundColor;
                if (bg && bg !== 'rgba(0, 0, 0, 0)' && bg !== 'transparent') return bg;
                current = current.parentElement;
            }
            return 'rgb(255, 255, 255)';
        }

        function parseColor(str) {
            var m = str.match(/rgba?\\((\\d+),\\s*(\\d+),\\s*(\\d+)/);
            return m ? {r: parseInt(m[1]), g: parseInt(m[2]), b: parseInt(m[3])} : null;
        }

        function getContrastRatio(c1, c2) {
            if (!c1 || !c2) return -1;
            var l1 = luminance(c1.r, c1.g, c1.b);
            var l2 = luminance(c2.r, c2.g, c2.b);
            var lighter = Math.max(l1, l2);
            var darker = Math.min(l1, l2);
            return (lighter + 0.05) / (darker + 0.05);
        }

        function luminance(r, g, b) {
            var a = [r, g, b].map(function(v) {
                v /= 255;
                return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
            });
            return a[0] * 0.2126 + a[1] * 0.7152 + a[2] * 0.0722;
        }

        var score = Math.round((passed / Math.max(passed + issues.length, 1)) * 100);
        return JSON.stringify({issues: issues, passed: passed, score: score});
    })();
    """

    /// Captura métricas de rendimiento: Navigation Timing, Paint, Resources, DOM, Memory
    static let performanceScript = """
    (function() {
        var result = {navigation: {}, paint: {}, resources: {}, dom: {}, memory: {}, timeline: []};

        // Navigation Timing API
        var nav = performance.getEntriesByType('navigation')[0];
        if (nav) {
            result.navigation = {
                dnsLookup: Math.round(nav.domainLookupEnd - nav.domainLookupStart),
                tcpConnect: Math.round(nav.connectEnd - nav.connectStart),
                tlsHandshake: nav.secureConnectionStart > 0 ? Math.round(nav.connectEnd - nav.secureConnectionStart) : 0,
                ttfb: Math.round(nav.responseStart - nav.requestStart),
                contentDownload: Math.round(nav.responseEnd - nav.responseStart),
                domParsing: Math.round(nav.domInteractive - nav.responseEnd),
                domContentLoaded: Math.round(nav.domContentLoadedEventEnd - nav.startTime),
                pageLoad: Math.round(nav.loadEventEnd - nav.startTime),
                domInteractive: Math.round(nav.domInteractive - nav.startTime)
            };
        }

        // Paint Timing
        var paintEntries = performance.getEntriesByType('paint');
        var fp = 0, fcp = 0;
        paintEntries.forEach(function(e) {
            if (e.name === 'first-paint') fp = Math.round(e.startTime);
            if (e.name === 'first-contentful-paint') fcp = Math.round(e.startTime);
        });
        result.paint = {firstPaint: fp, firstContentfulPaint: fcp, lcp: 0};

        // LCP via PerformanceObserver (captura el último valor)
        try {
            var lcpEntries = performance.getEntriesByType('largest-contentful-paint');
            if (lcpEntries && lcpEntries.length > 0) {
                result.paint.lcp = Math.round(lcpEntries[lcpEntries.length - 1].startTime);
            }
        } catch(e) {}

        // Resource timing
        var resources = performance.getEntriesByType('resource');
        var scripts = 0, styles = 0, images = 0, fonts = 0, xhr = 0, other = 0;
        var totalTransfer = 0;
        var timeline = [];

        resources.forEach(function(r) {
            totalTransfer += r.transferSize || 0;
            var type = 'other';
            var it = r.initiatorType || '';
            if (it === 'script' || r.name.match(/\\.js(\\?|$)/i)) { scripts++; type = 'script'; }
            else if (it === 'css' || it === 'link' || r.name.match(/\\.css(\\?|$)/i)) { styles++; type = 'css'; }
            else if (it === 'img' || r.name.match(/\\.(png|jpg|jpeg|gif|svg|webp|avif|ico)(\\?|$)/i)) { images++; type = 'img'; }
            else if (r.name.match(/\\.(woff2?|ttf|otf|eot)(\\?|$)/i)) { fonts++; type = 'font'; }
            else if (it === 'xmlhttprequest' || it === 'fetch') { xhr++; type = 'xhr'; }
            else { other++; }

            timeline.push({
                name: r.name,
                type: type,
                startTime: Math.round(r.startTime),
                duration: Math.round(r.duration),
                size: r.transferSize || 0
            });
        });

        result.resources = {
            total: resources.length,
            transferSize: totalTransfer,
            scripts: scripts,
            styles: styles,
            images: images,
            fonts: fonts,
            xhr: xhr,
            other: other
        };

        // Timeline sorted by startTime
        timeline.sort(function(a, b) { return a.startTime - b.startTime; });
        result.timeline = timeline;

        // DOM stats
        var allNodes = document.querySelectorAll('*');
        var maxDepth = 0;
        function getDepth(el) {
            var d = 0;
            var node = el;
            while (node.parentElement) { d++; node = node.parentElement; }
            return d;
        }
        // Sample depth from first 200 nodes for performance
        var sampleSize = Math.min(allNodes.length, 200);
        for (var i = 0; i < sampleSize; i++) {
            var d = getDepth(allNodes[Math.floor(i * allNodes.length / sampleSize)]);
            if (d > maxDepth) maxDepth = d;
        }

        // Count event listeners (approximate via getEventListeners if available, else estimate)
        var listenerCount = 0;
        try {
            // In WebKit, we can count elements with on* attributes
            allNodes.forEach(function(el) {
                var attrs = el.attributes;
                for (var j = 0; j < attrs.length; j++) {
                    if (attrs[j].name.startsWith('on')) listenerCount++;
                }
            });
        } catch(e) {}

        result.dom = {
            nodeCount: allNodes.length,
            maxDepth: maxDepth,
            listenerCount: listenerCount
        };

        // Memory (Chromium only, not available in WebKit)
        if (performance.memory) {
            result.memory = {
                usedJSHeapSize: performance.memory.usedJSHeapSize || 0,
                jsHeapSizeLimit: performance.memory.jsHeapSizeLimit || 0
            };
        }

        return result;
    })();
    """

    /// Captura snapshot de memoria: nodos DOM, detached, listeners, timers, leaks
    static let memorySnapshotScript = """
    (function() {
        var result = {};
        var allNodes = document.querySelectorAll('*');
        result.domNodeCount = allNodes.length;

        // Detached nodes: elements that were created but not in DOM
        // We can detect orphaned references by checking iframes with removed src
        var detached = 0;
        try {
            // Check for elements with stale references (common leak pattern)
            var iframes = document.querySelectorAll('iframe');
            iframes.forEach(function(f) {
                try {
                    if (!f.contentDocument && !f.src) detached++;
                } catch(e) {}
            });
            // Count hidden elements that might be detached
            allNodes.forEach(function(el) {
                if (el.offsetParent === null && el.tagName !== 'HTML' && el.tagName !== 'HEAD' &&
                    el.tagName !== 'BODY' && el.tagName !== 'SCRIPT' && el.tagName !== 'LINK' &&
                    el.tagName !== 'META' && el.tagName !== 'STYLE' && el.tagName !== 'TITLE' &&
                    getComputedStyle(el).display === 'none' && el.innerHTML.length > 500) {
                    detached++;
                }
            });
        } catch(e) {}
        result.detachedNodes = detached;

        // Event listeners (count on* attributes + tracked via monkey-patch)
        var listenerCount = 0;
        allNodes.forEach(function(el) {
            var attrs = el.attributes;
            for (var i = 0; i < attrs.length; i++) {
                if (attrs[i].name.startsWith('on')) listenerCount++;
            }
        });
        // Add window-level listeners if we tracked them
        if (window.__maiListenerCount) listenerCount += window.__maiListenerCount;
        result.eventListenerCount = listenerCount;

        // Resource counts
        result.iframeCount = document.querySelectorAll('iframe').length;
        result.scriptCount = document.querySelectorAll('script').length;
        result.styleSheetCount = document.styleSheets.length;
        result.imageCount = document.querySelectorAll('img, picture, svg').length;
        result.canvasCount = document.querySelectorAll('canvas').length;
        result.videoCount = document.querySelectorAll('video, audio').length;

        // Audio contexts
        result.audioContextCount = window.__maiAudioContexts ? window.__maiAudioContexts : 0;

        // WebSockets
        result.webSocketCount = window.__maiWebSocketCount || 0;

        // Observers (MutationObserver, IntersectionObserver, ResizeObserver)
        result.observerCount = window.__maiObserverCount || 0;

        // Active timers (setInterval)
        var timerCount = 0;
        try {
            // Detect active intervals by testing high timer IDs
            var testId = setInterval(function(){}, 99999);
            clearInterval(testId);
            timerCount = Math.min(testId, 100); // approximate
        } catch(e) {}
        result.timerCount = timerCount;

        // DOM size (approximate memory)
        try {
            result.domSize = document.documentElement.outerHTML.length * 2; // UTF-16
        } catch(e) {
            result.domSize = 0;
        }

        // Duplicate IDs
        var idMap = {};
        var dupIds = [];
        allNodes.forEach(function(el) {
            if (el.id) {
                if (idMap[el.id]) {
                    if (!dupIds.includes(el.id)) dupIds.push(el.id);
                }
                idMap[el.id] = true;
            }
        });
        result.duplicateIds = dupIds;

        // Largest nodes (by child count)
        var largeNodes = [];
        allNodes.forEach(function(el) {
            if (el.children.length > 20) {
                var sel = el.tagName.toLowerCase();
                if (el.id) sel += '#' + el.id;
                else if (el.className && typeof el.className === 'string') sel += '.' + el.className.split(' ')[0];
                largeNodes.push({
                    selector: sel,
                    childCount: el.children.length,
                    estimatedSize: el.innerHTML.length * 2
                });
            }
        });
        largeNodes.sort(function(a, b) { return b.childCount - a.childCount; });
        result.largestNodes = largeNodes.slice(0, 10);

        // Leak warnings
        var warnings = [];
        if (result.domNodeCount > 3000) {
            warnings.push('DOM excesivamente grande (' + result.domNodeCount + ' nodos). Considerar virtualización o lazy rendering.');
        }
        if (detached > 20) {
            warnings.push(detached + ' nodos potencialmente detached. Posible leak de referencias DOM.');
        }
        if (listenerCount > 500) {
            warnings.push('Demasiados event listeners (' + listenerCount + '). Usar delegación de eventos.');
        }
        if (timerCount > 10) {
            warnings.push(timerCount + ' timers activos (setInterval). Asegurar que se limpian con clearInterval.');
        }
        if (result.iframeCount > 5) {
            warnings.push(result.iframeCount + ' iframes — cada uno consume memoria separada.');
        }
        if (dupIds.length > 0) {
            warnings.push(dupIds.length + ' IDs duplicados encontrados — puede causar leaks en querySelector/getElementById.');
        }
        if (result.domSize > 5000000) {
            warnings.push('DOM muy pesado (' + Math.round(result.domSize / 1048576) + ' MB). Considerar paginación o carga diferida.');
        }
        result.leakWarnings = warnings;

        return result;
    })();
    """

    /// Auditoría tipo Lighthouse: Performance, Accesibilidad, Best Practices, SEO
    static let lighthouseScript = """
    (function() {
        var r = { performance: { score: 0, audits: [] }, accessibility: { score: 0, audits: [] }, bestPractices: { score: 0, audits: [] }, seo: { score: 0, audits: [] } };

        // === PERFORMANCE ===
        var perfAudits = [];
        var perfPass = 0, perfTotal = 0;
        try {
            var nav = performance.getEntriesByType('navigation')[0] || {};
            var fcp = 0;
            try {
                var paintEntries = performance.getEntriesByType('paint');
                for (var i = 0; i < paintEntries.length; i++) {
                    if (paintEntries[i].name === 'first-contentful-paint') fcp = Math.round(paintEntries[i].startTime);
                }
            } catch(e) {}
            var loadTime = Math.round(nav.loadEventEnd - nav.startTime) || 0;
            var ttfb = Math.round(nav.responseStart - nav.requestStart) || 0;
            var domReady = Math.round(nav.domContentLoadedEventEnd - nav.startTime) || 0;

            // FCP
            perfTotal++;
            var fcpOk = fcp > 0 && fcp < 2500;
            if (fcpOk) perfPass++;
            perfAudits.push({ title: 'First Contentful Paint', description: fcp + 'ms' + (fcp === 0 ? ' (no disponible)' : ''), passed: fcpOk, impact: fcp > 4000 ? 'high' : (fcp > 2500 ? 'medium' : 'low') });

            // Load time
            perfTotal++;
            var loadOk = loadTime < 3000;
            if (loadOk) perfPass++;
            perfAudits.push({ title: 'Tiempo de carga total', description: loadTime + 'ms', passed: loadOk, impact: loadTime > 5000 ? 'high' : (loadTime > 3000 ? 'medium' : 'low') });

            // TTFB
            perfTotal++;
            var ttfbOk = ttfb < 600;
            if (ttfbOk) perfPass++;
            perfAudits.push({ title: 'Time to First Byte (TTFB)', description: ttfb + 'ms', passed: ttfbOk, impact: ttfb > 1000 ? 'high' : (ttfb > 600 ? 'medium' : 'low') });

            // DOM ready
            perfTotal++;
            var domOk = domReady < 2000;
            if (domOk) perfPass++;
            perfAudits.push({ title: 'DOM Content Loaded', description: domReady + 'ms', passed: domOk, impact: domReady > 4000 ? 'high' : 'medium' });

            // Resources count
            var resources = performance.getEntriesByType('resource');
            perfTotal++;
            var resOk = resources.length < 80;
            if (resOk) perfPass++;
            perfAudits.push({ title: 'Cantidad de recursos', description: resources.length + ' recursos cargados', passed: resOk, impact: resources.length > 150 ? 'high' : 'medium' });

            // Render-blocking resources
            var blocking = 0;
            resources.forEach(function(res) {
                if ((res.initiatorType === 'link' || res.initiatorType === 'script') && res.renderBlockingStatus === 'blocking') blocking++;
            });
            perfTotal++;
            var blockOk = blocking < 5;
            if (blockOk) perfPass++;
            perfAudits.push({ title: 'Recursos que bloquean renderizado', description: blocking + ' recursos bloqueantes', passed: blockOk, impact: blocking > 10 ? 'high' : 'medium' });

            // DOM size
            var domNodes = document.querySelectorAll('*').length;
            perfTotal++;
            var domSizeOk = domNodes < 1500;
            if (domSizeOk) perfPass++;
            perfAudits.push({ title: 'Tamaño del DOM', description: domNodes + ' nodos', passed: domSizeOk, impact: domNodes > 3000 ? 'high' : 'medium' });

            // Images without dimensions
            var imgsNoDim = 0;
            document.querySelectorAll('img').forEach(function(img) {
                if (!img.hasAttribute('width') && !img.hasAttribute('height') && !img.style.width && !img.style.height) imgsNoDim++;
            });
            perfTotal++;
            var imgDimOk = imgsNoDim === 0;
            if (imgDimOk) perfPass++;
            perfAudits.push({ title: 'Imágenes sin dimensiones', description: imgsNoDim + ' imágenes sin width/height (causan layout shift)', passed: imgDimOk, impact: imgsNoDim > 5 ? 'high' : 'medium' });

        } catch(e) { perfAudits.push({ title: 'Error al auditar performance', description: e.message, passed: false, impact: 'low' }); }
        r.performance.score = perfTotal > 0 ? Math.round((perfPass / perfTotal) * 100) : 0;
        r.performance.audits = perfAudits;

        // === ACCESSIBILITY ===
        var a11yAudits = [];
        var a11yPass = 0, a11yTotal = 0;
        try {
            // Images without alt
            var imgsNoAlt = document.querySelectorAll('img:not([alt])').length;
            a11yTotal++;
            if (imgsNoAlt === 0) a11yPass++;
            a11yAudits.push({ title: 'Imágenes sin atributo alt', description: imgsNoAlt + ' imágenes sin texto alternativo', passed: imgsNoAlt === 0, impact: imgsNoAlt > 5 ? 'high' : 'medium' });

            // Form inputs without labels
            var inputsNoLabel = 0;
            document.querySelectorAll('input, select, textarea').forEach(function(el) {
                if (el.type === 'hidden' || el.type === 'submit' || el.type === 'button') return;
                var hasLabel = el.hasAttribute('aria-label') || el.hasAttribute('aria-labelledby') || el.hasAttribute('title') || el.id && document.querySelector('label[for="' + el.id + '"]');
                if (!hasLabel) inputsNoLabel++;
            });
            a11yTotal++;
            if (inputsNoLabel === 0) a11yPass++;
            a11yAudits.push({ title: 'Campos de formulario sin label', description: inputsNoLabel + ' inputs sin label asociado', passed: inputsNoLabel === 0, impact: 'high' });

            // Document language
            a11yTotal++;
            var hasLang = document.documentElement.hasAttribute('lang');
            if (hasLang) a11yPass++;
            a11yAudits.push({ title: 'Atributo lang en <html>', description: hasLang ? 'Presente: ' + document.documentElement.lang : 'No definido', passed: hasLang, impact: 'high' });

            // Heading hierarchy
            var headings = document.querySelectorAll('h1, h2, h3, h4, h5, h6');
            var headingOrder = true;
            var prevLevel = 0;
            var h1Count = 0;
            headings.forEach(function(h) {
                var level = parseInt(h.tagName[1]);
                if (level === 1) h1Count++;
                if (prevLevel > 0 && level > prevLevel + 1) headingOrder = false;
                prevLevel = level;
            });
            a11yTotal++;
            if (headingOrder) a11yPass++;
            a11yAudits.push({ title: 'Jerarquía de encabezados', description: headingOrder ? 'Correcta (' + headings.length + ' headings)' : 'Saltos en la jerarquía detectados', passed: headingOrder, impact: 'medium' });

            // Multiple H1
            a11yTotal++;
            var h1Ok = h1Count <= 1;
            if (h1Ok) a11yPass++;
            a11yAudits.push({ title: 'Un solo <h1> por página', description: h1Count + ' elementos <h1>', passed: h1Ok, impact: 'medium' });

            // Color contrast (basic check - buttons/links with low contrast)
            a11yTotal++;
            var contrastIssues = 0;
            try {
                document.querySelectorAll('a, button').forEach(function(el) {
                    var style = getComputedStyle(el);
                    var color = style.color;
                    var bg = style.backgroundColor;
                    if (color === bg && color !== 'rgba(0, 0, 0, 0)') contrastIssues++;
                });
            } catch(e) {}
            if (contrastIssues === 0) a11yPass++;
            a11yAudits.push({ title: 'Contraste de color básico', description: contrastIssues + ' elementos con posible contraste insuficiente', passed: contrastIssues === 0, impact: 'high' });

            // ARIA roles
            a11yTotal++;
            var landmarks = document.querySelectorAll('[role="main"], main, [role="navigation"], nav, [role="banner"], header, [role="contentinfo"], footer');
            var hasLandmarks = landmarks.length > 0;
            if (hasLandmarks) a11yPass++;
            a11yAudits.push({ title: 'Landmarks ARIA / HTML5', description: hasLandmarks ? landmarks.length + ' landmarks encontrados' : 'Sin landmarks semánticos', passed: hasLandmarks, impact: 'medium' });

            // Tab index
            var negativeTabindex = document.querySelectorAll('[tabindex]:not([tabindex="0"]):not([tabindex="-1"])').length;
            a11yTotal++;
            if (negativeTabindex === 0) a11yPass++;
            a11yAudits.push({ title: 'Valores de tabindex válidos', description: negativeTabindex + ' elementos con tabindex positivo (altera orden de navegación)', passed: negativeTabindex === 0, impact: 'medium' });

        } catch(e) { a11yAudits.push({ title: 'Error al auditar accesibilidad', description: e.message, passed: false, impact: 'low' }); }
        r.accessibility.score = a11yTotal > 0 ? Math.round((a11yPass / a11yTotal) * 100) : 0;
        r.accessibility.audits = a11yAudits;

        // === BEST PRACTICES ===
        var bpAudits = [];
        var bpPass = 0, bpTotal = 0;
        try {
            // HTTPS
            bpTotal++;
            var isHTTPS = location.protocol === 'https:';
            if (isHTTPS) bpPass++;
            bpAudits.push({ title: 'Usa HTTPS', description: isHTTPS ? 'Sí' : 'No — contenido no seguro', passed: isHTTPS, impact: 'high' });

            // Console errors
            bpTotal++;
            var consoleErrors = window.__maiConsoleErrors || 0;
            var noErrors = consoleErrors === 0;
            if (noErrors) bpPass++;
            bpAudits.push({ title: 'Sin errores en consola', description: consoleErrors + ' errores detectados', passed: noErrors, impact: 'medium' });

            // Doctype
            bpTotal++;
            var hasDoctype = document.doctype !== null;
            if (hasDoctype) bpPass++;
            bpAudits.push({ title: 'Doctype declarado', description: hasDoctype ? 'HTML5 doctype presente' : 'Sin doctype', passed: hasDoctype, impact: 'medium' });

            // Character encoding
            bpTotal++;
            var charset = document.characterSet || document.charset;
            var charsetOk = charset && charset.toLowerCase() === 'utf-8';
            if (charsetOk) bpPass++;
            bpAudits.push({ title: 'Codificación UTF-8', description: 'Charset: ' + (charset || 'no definido'), passed: charsetOk, impact: 'medium' });

            // Deprecated APIs
            bpTotal++;
            var deprecated = [];
            if (document.querySelectorAll('marquee').length > 0) deprecated.push('marquee');
            if (document.querySelectorAll('blink').length > 0) deprecated.push('blink');
            if (document.querySelectorAll('center').length > 0) deprecated.push('center');
            if (document.querySelectorAll('font').length > 0) deprecated.push('font');
            var noDeprecated = deprecated.length === 0;
            if (noDeprecated) bpPass++;
            bpAudits.push({ title: 'Sin elementos HTML deprecados', description: noDeprecated ? 'Ninguno encontrado' : 'Encontrados: ' + deprecated.join(', '), passed: noDeprecated, impact: 'low' });

            // Viewport meta
            bpTotal++;
            var viewport = document.querySelector('meta[name="viewport"]');
            var hasViewport = viewport !== null;
            if (hasViewport) bpPass++;
            bpAudits.push({ title: 'Meta viewport configurado', description: hasViewport ? viewport.getAttribute('content') : 'No presente', passed: hasViewport, impact: 'high' });

            // Mixed content
            bpTotal++;
            var mixedContent = 0;
            if (isHTTPS) {
                document.querySelectorAll('img[src^="http:"], script[src^="http:"], link[href^="http:"]').forEach(function() { mixedContent++; });
            }
            var noMixed = mixedContent === 0;
            if (noMixed) bpPass++;
            bpAudits.push({ title: 'Sin contenido mixto (HTTP en HTTPS)', description: noMixed ? 'Todo el contenido es seguro' : mixedContent + ' recursos HTTP en página HTTPS', passed: noMixed, impact: 'high' });

            // Target _blank without rel=noopener
            bpTotal++;
            var unsafeLinks = 0;
            document.querySelectorAll('a[target="_blank"]').forEach(function(a) {
                var rel = (a.getAttribute('rel') || '').toLowerCase();
                if (!rel.includes('noopener') && !rel.includes('noreferrer')) unsafeLinks++;
            });
            var safeLinks = unsafeLinks === 0;
            if (safeLinks) bpPass++;
            bpAudits.push({ title: 'Links _blank con rel="noopener"', description: safeLinks ? 'Todos seguros' : unsafeLinks + ' links sin noopener/noreferrer', passed: safeLinks, impact: 'medium' });

        } catch(e) { bpAudits.push({ title: 'Error al auditar best practices', description: e.message, passed: false, impact: 'low' }); }
        r.bestPractices.score = bpTotal > 0 ? Math.round((bpPass / bpTotal) * 100) : 0;
        r.bestPractices.audits = bpAudits;

        // === SEO ===
        var seoAudits = [];
        var seoPass = 0, seoTotal = 0;
        try {
            // Title
            seoTotal++;
            var title = document.title;
            var hasTitle = title && title.length > 0;
            if (hasTitle) seoPass++;
            seoAudits.push({ title: 'Título de página', description: hasTitle ? '"' + title.substring(0, 60) + '"' + (title.length > 60 ? ' (' + title.length + ' chars — ideal < 60)' : '') : 'Sin título', passed: hasTitle, impact: 'high' });

            // Meta description
            seoTotal++;
            var metaDesc = document.querySelector('meta[name="description"]');
            var hasDesc = metaDesc && metaDesc.content && metaDesc.content.length > 0;
            if (hasDesc) seoPass++;
            seoAudits.push({ title: 'Meta description', description: hasDesc ? metaDesc.content.substring(0, 80) + '...' : 'No presente', passed: hasDesc, impact: 'high' });

            // Canonical
            seoTotal++;
            var canonical = document.querySelector('link[rel="canonical"]');
            var hasCanonical = canonical !== null;
            if (hasCanonical) seoPass++;
            seoAudits.push({ title: 'Link canonical', description: hasCanonical ? canonical.href : 'No definido', passed: hasCanonical, impact: 'medium' });

            // Heading structure
            seoTotal++;
            var h1s = document.querySelectorAll('h1');
            var hasH1 = h1s.length > 0;
            if (hasH1) seoPass++;
            seoAudits.push({ title: 'Encabezado H1 presente', description: hasH1 ? h1s.length + ' H1: "' + h1s[0].textContent.substring(0, 50) + '"' : 'Sin H1', passed: hasH1, impact: 'high' });

            // Links with text
            seoTotal++;
            var emptyLinks = 0;
            document.querySelectorAll('a[href]').forEach(function(a) {
                var text = (a.textContent || '').trim();
                var ariaLabel = a.getAttribute('aria-label') || '';
                var img = a.querySelector('img[alt]');
                if (!text && !ariaLabel && !img) emptyLinks++;
            });
            var linksOk = emptyLinks < 3;
            if (linksOk) seoPass++;
            seoAudits.push({ title: 'Links con texto descriptivo', description: emptyLinks + ' links sin texto accesible', passed: linksOk, impact: 'medium' });

            // Open Graph
            seoTotal++;
            var ogTitle = document.querySelector('meta[property="og:title"]');
            var ogDesc = document.querySelector('meta[property="og:description"]');
            var hasOG = ogTitle !== null || ogDesc !== null;
            if (hasOG) seoPass++;
            seoAudits.push({ title: 'Open Graph meta tags', description: hasOG ? 'Presente' : 'No encontrados (og:title, og:description)', passed: hasOG, impact: 'low' });

            // Robots meta
            seoTotal++;
            var robots = document.querySelector('meta[name="robots"]');
            var robotsContent = robots ? robots.content : '';
            var indexable = !robotsContent.includes('noindex');
            if (indexable) seoPass++;
            seoAudits.push({ title: 'Página indexable', description: robots ? 'robots: ' + robotsContent : 'Sin meta robots (indexable por defecto)', passed: indexable, impact: 'high' });

            // Mobile friendly
            seoTotal++;
            var vpMeta = document.querySelector('meta[name="viewport"]');
            var mobileFriendly = vpMeta && vpMeta.content && vpMeta.content.includes('width=device-width');
            if (mobileFriendly) seoPass++;
            seoAudits.push({ title: 'Mobile-friendly', description: mobileFriendly ? 'Viewport responsive configurado' : 'Sin viewport responsive', passed: mobileFriendly, impact: 'high' });

        } catch(e) { seoAudits.push({ title: 'Error al auditar SEO', description: e.message, passed: false, impact: 'low' }); }
        r.seo.score = seoTotal > 0 ? Math.round((seoPass / seoTotal) * 100) : 0;
        r.seo.audits = seoAudits;

        return r;
    })();
    """
}

// MARK: - Data Models for New Panels

struct CSSIssue: Identifiable {
    let id = UUID()
    let property: String
    let value: String
    let selector: String
    let reason: String
    let severity: CSSIssueSeverity
}

enum CSSIssueSeverity: String {
    case error, warn, info

    var color: Color {
        switch self {
        case .error: return DT.error
        case .warn: return DT.warning
        case .info: return DT.info
        }
    }

    var icon: String {
        switch self {
        case .error: return "xmark.circle.fill"
        case .warn: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }

    var label: String {
        switch self {
        case .error: return "Error"
        case .warn: return "Advertencia"
        case .info: return "Info"
        }
    }
}

struct DOM3DNode {
    let tag: String
    let id: String
    let cls: String
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
    let depth: Int
    let bgColor: NSColor
    let childCount: Int

    var label: String {
        if !id.isEmpty { return "\(tag)#\(id)" }
        if !cls.isEmpty { return "\(tag).\(cls)" }
        return tag
    }
}

struct AccessibilityIssue: Identifiable {
    let id = UUID()
    let type: AccessibilityIssueSeverity
    let category: String
    let message: String
    let selector: String
    let fix: String
}

enum AccessibilityIssueSeverity: String {
    case error, warn, info

    var color: Color {
        switch self {
        case .error: return DT.error
        case .warn: return DT.warning
        case .info: return DT.info
        }
    }

    var icon: String {
        switch self {
        case .error: return "xmark.circle.fill"
        case .warn: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }
}

// MARK: - CSS Debug Panel ("¿Por qué no funciona?")

struct CSSDebugPanel: View {
    @EnvironmentObject var browserState: BrowserState
    @StateObject private var devTools = DevToolsState.shared
    @State private var filterSeverity: CSSIssueSeverity? = nil

    var filteredIssues: [CSSIssue] {
        if let filter = filterSeverity {
            return devTools.cssIssues.filter { $0.severity == filter }
        }
        return devTools.cssIssues
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 8) {
                Button(action: runCSSAudit) {
                    HStack(spacing: 4) {
                        Image(systemName: "paintbrush")
                            .font(.system(size: 13))
                        Text("Analizar CSS")
                            .font(.system(size: 13))
                    }
                    .foregroundColor(DT.textSecondary)
                }
                .buttonStyle(.plain)

                Divider().frame(height: 14).overlay(DT.border)

                ForEach([CSSIssueSeverity.error, .warn, .info], id: \.self) { sev in
                    let count = devTools.cssIssues.filter { $0.severity == sev }.count
                    Button(action: { filterSeverity = filterSeverity == sev ? nil : sev }) {
                        HStack(spacing: 3) {
                            Image(systemName: sev.icon)
                                .font(.system(size: 12))
                                .foregroundColor(sev.color)
                            Text("\(count)")
                                .font(.system(size: 13))
                                .foregroundColor(filterSeverity == sev ? sev.color : DT.textSecondary)
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(filterSeverity == sev ? sev.color.opacity(0.15) : Color.clear)
                        .cornerRadius(3)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                if !devTools.cssIssues.isEmpty {
                    Text("\(devTools.cssIssues.count) problemas detectados")
                        .font(.system(size: 13))
                        .foregroundColor(DT.textSecondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(DT.toolbarBg)

            Divider()

            if devTools.cssIsLoading {
                ProgressView("Analizando CSS…")
                    .controlSize(.small)
                    .foregroundColor(DT.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(DT.bg)
            } else if devTools.cssIssues.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "paintbrush")
                        .font(.system(size: 32))
                        .foregroundColor(DT.textSecondary)
                    Text("CSS Debug — ¿Por qué no funciona?")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(DT.text)
                    Text("Analiza el CSS de la página y detecta declaraciones\nsin efecto con explicaciones claras.")
                        .font(.system(size: 14))
                        .foregroundColor(DT.textSecondary)
                        .multilineTextAlignment(.center)
                    Button("Analizar CSS") { runCSSAudit() }
                        .controlSize(.small)
                        .foregroundColor(DT.link)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DT.bg)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredIssues) { issue in
                            CSSIssueRow(issue: issue)
                        }
                    }
                }
                .background(DT.bg)
            }
        }
    }

    private func runCSSAudit() {
        guard let webView = browserState.currentTab?.webView else { return }
        devTools.cssIsLoading = true
        devTools.cssIssues.removeAll()

        webView.evaluateJavaScript(DevToolsScripts.cssDebugScript) { result, error in
            DispatchQueue.main.async {
                devTools.cssIsLoading = false
                guard let jsonStr = result as? String,
                      let data = jsonStr.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let issuesData = json["issues"] as? [[String: String]] else { return }

                devTools.cssIssues = issuesData.compactMap { dict in
                    guard let prop = dict["prop"],
                          let value = dict["value"],
                          let selector = dict["selector"],
                          let reason = dict["reason"],
                          let sevStr = dict["severity"] else { return nil }
                    let severity: CSSIssueSeverity
                    switch sevStr {
                    case "error": severity = .error
                    case "warn": severity = .warn
                    default: severity = .info
                    }
                    return CSSIssue(property: prop, value: value, selector: selector, reason: reason, severity: severity)
                }
            }
        }
    }
}

struct CSSIssueRow: View {
    let issue: CSSIssue

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: issue.severity.icon)
                    .font(.system(size: 14))
                    .foregroundColor(issue.severity.color)

                Text(issue.selector)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundColor(DT.keyword)

                Spacer()

                HStack(spacing: 2) {
                    Text(issue.property)
                        .foregroundColor(DT.property)
                    Text(":")
                        .foregroundColor(DT.textMuted)
                    Text(issue.value)
                        .foregroundColor(DT.success)
                }
                .font(.system(size: 13, design: .monospaced))
            }

            Text(issue.reason)
                .font(.system(size: 14))
                .foregroundColor(DT.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(issue.severity == .error ? DT.errorBg.opacity(0.5) : issue.severity == .warn ? DT.warnBg.opacity(0.5) : Color.clear)
        .overlay(
            Rectangle()
                .fill(issue.severity.color)
                .frame(width: 3),
            alignment: .leading
        )
    }
}

// MARK: - 3D DOM Panel

struct DOM3DPanel: View {
    @EnvironmentObject var browserState: BrowserState
    @StateObject private var devTools = DevToolsState.shared
    @State private var isLoading: Bool = false
    @State private var pageWidth: CGFloat = 1920
    @State private var pageHeight: CGFloat = 1080
    @State private var selectedNodeLabel: String = ""
    @State private var showWireframe: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 8) {
                Button(action: loadDOM3D) {
                    HStack(spacing: 4) {
                        Image(systemName: "cube")
                            .font(.system(size: 13))
                        Text("Renderizar 3D")
                            .font(.system(size: 13))
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(DT.link)

                Divider().frame(height: 14)

                Toggle("Wireframe", isOn: $showWireframe)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 13))
                    .controlSize(.mini)
                    .foregroundColor(DT.textSecondary)

                Spacer()

                if !selectedNodeLabel.isEmpty {
                    Text(selectedNodeLabel)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(DT.property)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(DT.inputBg)
                        .cornerRadius(3)
                }

                Text("\(devTools.dom3DNodes.count) elementos")
                    .font(.system(size: 13))
                    .foregroundColor(DT.textSecondary)

                Text("Rotar: arrastrar | Zoom: scroll | Pan: shift+arrastrar")
                    .font(.system(size: 12))
                    .foregroundColor(DT.textMuted)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(DT.toolbarBg)

            Divider()

            if isLoading {
                ProgressView("Construyendo vista 3D…")
                    .controlSize(.small)
                    .foregroundColor(DT.text)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(DT.bg)
            } else if devTools.dom3DNodes.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "cube.transparent")
                        .font(.system(size: 32))
                        .foregroundColor(DT.textSecondary)
                    Text("Vista 3D del DOM")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(DT.text)
                    Text("Visualiza la estructura de la página como bloques 3D.\nCada elemento es un bloque apilado según su profundidad en el DOM.\nDetecta visualmente z-index wars, divitis y elementos ocultos.")
                        .font(.system(size: 14))
                        .foregroundColor(DT.textSecondary)
                        .multilineTextAlignment(.center)
                    Button("Renderizar 3D") { loadDOM3D() }
                        .controlSize(.small)
                        .foregroundColor(DT.link)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DT.bg)
            } else {
                SceneView3D(
                    nodes: devTools.dom3DNodes,
                    pageWidth: pageWidth,
                    pageHeight: pageHeight,
                    showWireframe: showWireframe,
                    onNodeSelected: { label in
                        selectedNodeLabel = label
                    }
                )
            }
        }
    }

    private func loadDOM3D() {
        guard let webView = browserState.currentTab?.webView else { return }
        isLoading = true
        devTools.dom3DNodes.removeAll()

        webView.evaluateJavaScript(DevToolsScripts.dom3DScript) { result, error in
            DispatchQueue.main.async {
                isLoading = false
                guard let jsonStr = result as? String,
                      let data = jsonStr.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

                pageWidth = json["pageWidth"] as? CGFloat ?? 1920
                pageHeight = json["pageHeight"] as? CGFloat ?? 1080

                guard let nodesData = json["nodes"] as? [[String: Any]] else { return }

                devTools.dom3DNodes = nodesData.compactMap { node -> DOM3DNode? in
                    guard let tag = node["tag"] as? String,
                          let x = node["x"] as? CGFloat,
                          let y = node["y"] as? CGFloat,
                          let w = node["w"] as? CGFloat,
                          let h = node["h"] as? CGFloat,
                          let d = node["d"] as? Int else { return nil }

                    let bgStr = node["bg"] as? String ?? ""
                    let bgColor = Self.parseColorString(bgStr) ?? Self.colorForDepth(d)

                    return DOM3DNode(
                        tag: tag,
                        id: node["id"] as? String ?? "",
                        cls: node["cls"] as? String ?? "",
                        x: x, y: y, width: w, height: h,
                        depth: d,
                        bgColor: bgColor,
                        childCount: node["children"] as? Int ?? 0
                    )
                }
            }
        }
    }

    static func parseColorString(_ str: String) -> NSColor? {
        guard !str.isEmpty, str != "rgba(0, 0, 0, 0)", str != "transparent" else { return nil }
        let pattern = try? NSRegularExpression(pattern: "rgba?\\((\\d+),\\s*(\\d+),\\s*(\\d+)")
        guard let match = pattern?.firstMatch(in: str, range: NSRange(str.startIndex..., in: str)),
              let rRange = Range(match.range(at: 1), in: str),
              let gRange = Range(match.range(at: 2), in: str),
              let bRange = Range(match.range(at: 3), in: str),
              let r = Double(str[rRange]),
              let g = Double(str[gRange]),
              let b = Double(str[bRange]) else { return nil }
        return NSColor(red: r / 255, green: g / 255, blue: b / 255, alpha: 1.0)
    }

    static func colorForDepth(_ depth: Int) -> NSColor {
        let colors: [NSColor] = [
            NSColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 0.8),  // Azul (body)
            NSColor(red: 0.3, green: 0.7, blue: 0.4, alpha: 0.8),  // Verde
            NSColor(red: 0.9, green: 0.6, blue: 0.2, alpha: 0.8),  // Naranja
            NSColor(red: 0.8, green: 0.3, blue: 0.5, alpha: 0.8),  // Rosa
            NSColor(red: 0.5, green: 0.3, blue: 0.8, alpha: 0.8),  // Morado
            NSColor(red: 0.2, green: 0.7, blue: 0.7, alpha: 0.8),  // Teal
            NSColor(red: 0.9, green: 0.4, blue: 0.4, alpha: 0.8),  // Rojo
        ]
        return colors[depth % colors.count]
    }
}

/// Vista SceneKit 3D para el DOM
struct SceneView3D: NSViewRepresentable {
    let nodes: [DOM3DNode]
    let pageWidth: CGFloat
    let pageHeight: CGFloat
    let showWireframe: Bool
    let onNodeSelected: (String) -> Void

    func makeNSView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = true
        scnView.backgroundColor = NSColor(red: 0.125, green: 0.129, blue: 0.141, alpha: 1) // DT.bg

        let scene = buildScene()
        scnView.scene = scene

        // Click handler
        let clickGesture = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleClick(_:)))
        scnView.addGestureRecognizer(clickGesture)
        context.coordinator.scnView = scnView

        return scnView
    }

    func updateNSView(_ scnView: SCNView, context: Context) {
        scnView.scene = buildScene()
        context.coordinator.onNodeSelected = onNodeSelected
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onNodeSelected: onNodeSelected)
    }

    class Coordinator: NSObject {
        weak var scnView: SCNView?
        var onNodeSelected: (String) -> Void

        init(onNodeSelected: @escaping (String) -> Void) {
            self.onNodeSelected = onNodeSelected
        }

        @objc func handleClick(_ gesture: NSClickGestureRecognizer) {
            guard let scnView = scnView else { return }
            let point = gesture.location(in: scnView)
            let hits = scnView.hitTest(point, options: [:])
            if let hit = hits.first, let name = hit.node.name {
                onNodeSelected(name)
            }
        }
    }

    private func buildScene() -> SCNScene {
        let scene = SCNScene()

        // Normalize coordinates
        let scale: CGFloat = 10.0 / max(pageWidth, pageHeight)
        let layerHeight: CGFloat = 0.15

        for node in nodes {
            let w = max(node.width * scale, 0.02)
            let h = max(node.height * scale, 0.02)
            let x = (node.x + node.width / 2) * scale - (pageWidth * scale / 2)
            let y = -((node.y + node.height / 2) * scale - (pageHeight * scale / 2))
            let z = CGFloat(node.depth) * layerHeight

            let box = SCNBox(width: w, height: h, length: layerHeight * 0.9, chamferRadius: 0.005)

            let material = SCNMaterial()
            material.diffuse.contents = node.bgColor
            material.transparency = 0.75
            if showWireframe {
                material.fillMode = .lines
                material.transparency = 1.0
            }
            box.materials = [material]

            let scnNode = SCNNode(geometry: box)
            scnNode.position = SCNVector3(Float(x), Float(y), Float(z))
            scnNode.name = node.label

            scene.rootNode.addChildNode(scnNode)
        }

        // Camera
        let camera = SCNCamera()
        camera.usesOrthographicProjection = false
        camera.fieldOfView = 45
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, 8)
        cameraNode.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(cameraNode)

        // Ambient light
        let ambientLight = SCNLight()
        ambientLight.type = .ambient
        ambientLight.intensity = 600
        ambientLight.color = NSColor.white
        let ambientNode = SCNNode()
        ambientNode.light = ambientLight
        scene.rootNode.addChildNode(ambientNode)

        // Directional light
        let directionalLight = SCNLight()
        directionalLight.type = .directional
        directionalLight.intensity = 800
        let directionalNode = SCNNode()
        directionalNode.light = directionalLight
        directionalNode.position = SCNVector3(5, 5, 10)
        directionalNode.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(directionalNode)

        // Grid floor
        let gridPlane = SCNPlane(width: 12, height: 12)
        let gridMaterial = SCNMaterial()
        gridMaterial.diffuse.contents = NSColor(white: 0.15, alpha: 1)
        gridMaterial.transparency = 0.3
        gridPlane.materials = [gridMaterial]
        let gridNode = SCNNode(geometry: gridPlane)
        gridNode.position = SCNVector3(0, 0, -0.1)
        scene.rootNode.addChildNode(gridNode)

        return scene
    }
}

// MARK: - Accessibility Panel

struct AccessibilityPanel: View {
    @EnvironmentObject var browserState: BrowserState
    @StateObject private var devTools = DevToolsState.shared
    @State private var filterCategory: String = "Todos"

    var categories: [String] {
        var cats = Set(devTools.accessibilityIssues.map { $0.category })
        cats.insert("Todos")
        return ["Todos"] + Array(cats).filter { $0 != "Todos" }.sorted()
    }

    var filteredIssues: [AccessibilityIssue] {
        if filterCategory == "Todos" { return devTools.accessibilityIssues }
        return devTools.accessibilityIssues.filter { $0.category == filterCategory }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 8) {
                Button(action: runAudit) {
                    HStack(spacing: 4) {
                        Image(systemName: "accessibility")
                            .font(.system(size: 13))
                        Text("Auditar accesibilidad")
                            .font(.system(size: 13))
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(DT.link)

                Divider().frame(height: 14)

                // Score badge
                if devTools.accessibilityScore > 0 {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(scoreColor)
                            .frame(width: 8, height: 8)
                        Text("\(devTools.accessibilityScore)/100")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(scoreColor)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(scoreColor.opacity(0.1))
                    .cornerRadius(4)
                }

                // Severity counts
                let errors = devTools.accessibilityIssues.filter { $0.type == .error }.count
                let warns = devTools.accessibilityIssues.filter { $0.type == .warn }.count
                let infos = devTools.accessibilityIssues.filter { $0.type == .info }.count

                if errors > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundColor(DT.error)
                        Text("\(errors)").font(.system(size: 13)).foregroundColor(DT.error)
                    }
                }
                if warns > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 12)).foregroundColor(DT.string)
                        Text("\(warns)").font(.system(size: 13)).foregroundColor(DT.string)
                    }
                }
                if infos > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "info.circle.fill").font(.system(size: 12)).foregroundColor(DT.infoText)
                        Text("\(infos)").font(.system(size: 13)).foregroundColor(DT.infoText)
                    }
                }

                Spacer()

                // Category filter
                if !devTools.accessibilityIssues.isEmpty {
                    Picker("", selection: $filterCategory) {
                        ForEach(categories, id: \.self) { cat in
                            Text(cat).tag(cat)
                        }
                    }
                    .frame(width: 130)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(DT.toolbarBg)

            Divider()

            if devTools.accessibilityIsLoading {
                ProgressView("Auditando accesibilidad…")
                    .controlSize(.small)
                    .foregroundColor(DT.text)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(DT.bg)
            } else if devTools.accessibilityIssues.isEmpty && devTools.accessibilityScore == 0 {
                VStack(spacing: 12) {
                    Image(systemName: "accessibility")
                        .font(.system(size: 32))
                        .foregroundColor(DT.textSecondary)
                    Text("Auditoría de Accesibilidad")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(DT.text)
                    Text("Verifica 11 categorías WCAG:\nimágenes, formularios, encabezados, enlaces, contraste,\nlandmarks, idioma, teclado, multimedia, botones, navegación.")
                        .font(.system(size: 14))
                        .foregroundColor(DT.textSecondary)
                        .multilineTextAlignment(.center)
                    Button("Auditar") { runAudit() }
                        .controlSize(.small)
                        .foregroundColor(DT.link)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DT.bg)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredIssues) { issue in
                            AccessibilityIssueRow(issue: issue)
                        }
                    }
                }
                .background(DT.bg)
            }
        }
    }

    var scoreColor: Color {
        if devTools.accessibilityScore >= 90 { return DT.success }
        if devTools.accessibilityScore >= 70 { return DT.warning }
        return DT.error
    }

    private func runAudit() {
        guard let webView = browserState.currentTab?.webView else { return }
        devTools.accessibilityIsLoading = true
        devTools.accessibilityIssues.removeAll()

        webView.evaluateJavaScript(DevToolsScripts.accessibilityAuditScript) { result, error in
            DispatchQueue.main.async {
                devTools.accessibilityIsLoading = false
                guard let jsonStr = result as? String,
                      let data = jsonStr.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

                devTools.accessibilityScore = json["score"] as? Int ?? 0

                guard let issuesData = json["issues"] as? [[String: String]] else { return }

                devTools.accessibilityIssues = issuesData.compactMap { dict in
                    guard let typeStr = dict["type"],
                          let category = dict["category"],
                          let message = dict["message"],
                          let selector = dict["selector"],
                          let fix = dict["fix"] else { return nil }
                    let type: AccessibilityIssueSeverity
                    switch typeStr {
                    case "error": type = .error
                    case "warn": type = .warn
                    default: type = .info
                    }
                    return AccessibilityIssue(type: type, category: category, message: message, selector: selector, fix: fix)
                }
            }
        }
    }
}

struct AccessibilityIssueRow: View {
    let issue: AccessibilityIssue

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: issue.type.icon)
                    .font(.system(size: 14))
                    .foregroundColor(issue.type.color)

                Text(issue.category)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DT.textSecondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(DT.border)
                    .cornerRadius(3)

                Text(issue.message)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(DT.text)
                    .lineLimit(2)

                Spacer()
            }

            HStack(spacing: 8) {
                Text(issue.selector)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(DT.keyword)
                    .lineLimit(1)
            }

            HStack(spacing: 4) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 12))
                    .foregroundColor(DT.success)
                Text(issue.fix)
                    .font(.system(size: 13))
                    .foregroundColor(DT.success)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(issue.type == .error ? DT.errorBg.opacity(0.5) : issue.type == .warn ? DT.warnBg.opacity(0.5) : Color.clear)
        .overlay(
            Rectangle()
                .fill(issue.type.color)
                .frame(width: 3),
            alignment: .leading
        )
    }
}

// MARK: - CDP Debugger Panel

struct CDPDebuggerPanel: View {
    @ObservedObject var cdp = CDPManager.shared
    @EnvironmentObject var browserState: BrowserState
    @State private var breakpointURL = ""
    @State private var breakpointLine = ""
    @State private var breakpointCondition = ""
    @State private var evalExpression = ""
    @State private var newWatchExpr = ""
    @State private var selectedFrameId: String?

    var isCEFTab: Bool {
        browserState.currentTab?.useChromiumEngine == true
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            debuggerToolbar

            Divider().background(DT.border)

            if !isCEFTab {
                // No CEF tab — show message
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 32))
                        .foregroundColor(DT.warning)
                    Text("Debugger solo disponible en tabs Chromium (CEF)")
                        .font(.system(size: 13))
                        .foregroundColor(DT.textSecondary)
                    Text("Navega a Meet, Zoom o Teams, o activa Modo Chrome para usar el debugger CDP.")
                        .font(.system(size: 11))
                        .foregroundColor(DT.textMuted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DT.bg)
            } else if !cdp.isAttached {
                // CEF tab but not attached
                VStack(spacing: 12) {
                    Image(systemName: "ant")
                        .font(.system(size: 32))
                        .foregroundColor(DT.link)
                    Text("Debugger CDP")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DT.text)
                    Text("Conecta al protocolo Chrome DevTools para depurar JavaScript con breakpoints, stepping y call stack.")
                        .font(.system(size: 11))
                        .foregroundColor(DT.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                    Button("Conectar Debugger") { cdp.attach() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DT.bg)
            } else {
                // Attached — show debugger UI
                HSplitView {
                    // Left: Scripts + Source
                    VStack(spacing: 0) {
                        scriptsPanel
                        Divider().background(DT.border)
                        sourcePanel
                    }
                    .frame(minWidth: 300)

                    // Right: Breakpoints + Call Stack + Watch + Console
                    VStack(spacing: 0) {
                        breakpointsPanel
                        Divider().background(DT.border)
                        callStackPanel
                        Divider().background(DT.border)
                        watchPanel
                        Divider().background(DT.border)
                        debugConsole
                    }
                    .frame(minWidth: 200, idealWidth: 280)
                }
                .background(DT.bg)
            }
        }
        .background(DT.bg)
    }

    // MARK: - Toolbar

    var debuggerToolbar: some View {
        HStack(spacing: 6) {
            if cdp.isAttached {
                // Pause/Resume
                Button(action: { cdp.isPaused ? cdp.resume() : cdp.pause() }) {
                    Image(systemName: cdp.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .foregroundColor(cdp.isPaused ? DT.success : DT.text)
                .help(cdp.isPaused ? "Continuar (F8)" : "Pausar (F8)")

                // Step Over
                Button(action: { cdp.stepOver() }) {
                    Image(systemName: "arrow.right.to.line")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .disabled(!cdp.isPaused)
                .help("Step Over (F10)")

                // Step Into
                Button(action: { cdp.stepInto() }) {
                    Image(systemName: "arrow.down.to.line")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .disabled(!cdp.isPaused)
                .help("Step Into (F11)")

                // Step Out
                Button(action: { cdp.stepOut() }) {
                    Image(systemName: "arrow.up.to.line")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .disabled(!cdp.isPaused)
                .help("Step Out (Shift+F11)")

                Spacer()

                // Status
                if cdp.isPaused {
                    HStack(spacing: 4) {
                        Circle().fill(DT.warning).frame(width: 6, height: 6)
                        Text("Pausado")
                            .font(.system(size: 10))
                            .foregroundColor(DT.warning)
                    }
                } else {
                    HStack(spacing: 4) {
                        Circle().fill(DT.success).frame(width: 6, height: 6)
                        Text("Ejecutando")
                            .font(.system(size: 10))
                            .foregroundColor(DT.success)
                    }
                }

                Button(action: { cdp.detach() }) {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .foregroundColor(DT.error)
                .help("Desconectar")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(DT.toolbarBg)
    }

    // MARK: - Scripts Panel

    var scriptsPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Scripts (\(cdp.scripts.count))")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(DT.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DT.toolbarBg)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(cdp.scripts) { script in
                        HStack(spacing: 4) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 9))
                                .foregroundColor(DT.textMuted)
                            Text(script.displayName)
                                .font(.system(size: 11))
                                .foregroundColor(cdp.selectedScript?.id == script.id ? DT.link : DT.text)
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(cdp.selectedScript?.id == script.id ? DT.selectedBg : Color.clear)
                        .contentShape(Rectangle())
                        .onTapGesture { cdp.loadScriptSource(script) }
                    }
                }
            }
            .frame(maxHeight: 120)
        }
    }

    // MARK: - Source Panel

    var sourcePanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let script = cdp.selectedScript {
                HStack {
                    Text(script.displayName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(DT.text)
                    Spacer()
                    Text(script.url)
                        .font(.system(size: 9))
                        .foregroundColor(DT.textMuted)
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(DT.toolbarBg)

                ScrollView([.horizontal, .vertical]) {
                    sourceCodeView
                }
            } else {
                VStack {
                    Text("Selecciona un script para ver su código fuente")
                        .font(.system(size: 11))
                        .foregroundColor(DT.textMuted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var sourceCodeView: some View {
        let lines = cdp.scriptSource.components(separatedBy: "\n")
        let pausedLine = currentPausedLine

        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                sourceLineRow(idx: idx, line: line, pausedLine: pausedLine)
            }
        }
        .padding(.horizontal, 4)
    }

    private func sourceLineRow(idx: Int, line: String, pausedLine: Int?) -> some View {
        let lineNum = idx + 1
        let hasBreakpoint = cdp.breakpoints.contains { bp in
            bp.lineNumber == idx && (bp.url == cdp.selectedScript?.url || bp.scriptId == cdp.selectedScript?.id)
        }
        let isPausedHere = pausedLine == idx

        return HStack(spacing: 0) {
            ZStack {
                if hasBreakpoint {
                    Circle().fill(DT.error).frame(width: 10, height: 10)
                }
                if isPausedHere {
                    Image(systemName: "arrowtriangle.right.fill")
                        .font(.system(size: 8))
                        .foregroundColor(DT.warning)
                }
            }
            .frame(width: 16)

            Text("\(lineNum)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(DT.textMuted)
                .frame(width: 35, alignment: .trailing)
                .padding(.trailing, 6)

            Text(line)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(DT.text)
                .textSelection(.enabled)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 1)
        .background(isPausedHere ? DT.warning.opacity(0.15) :
                   hasBreakpoint ? DT.error.opacity(0.08) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            if let script = cdp.selectedScript {
                if let existing = cdp.breakpoints.first(where: { $0.lineNumber == idx && ($0.url == script.url || $0.scriptId == script.id) }) {
                    cdp.removeBreakpoint(existing.id)
                } else {
                    cdp.setBreakpoint(url: script.url, line: idx)
                }
            }
        }
    }

    var currentPausedLine: Int? {
        guard case .paused(_, let frames) = cdp.pauseState,
              let frame = frames.first,
              frame.scriptId == cdp.selectedScript?.id else { return nil }
        return frame.lineNumber
    }

    // MARK: - Breakpoints Panel

    var breakpointsPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Breakpoints (\(cdp.breakpoints.count))")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(DT.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DT.toolbarBg)

            // Add breakpoint form
            HStack(spacing: 4) {
                TextField("URL o archivo", text: $breakpointURL)
                    .font(.system(size: 10))
                    .textFieldStyle(.roundedBorder)
                TextField("Línea", text: $breakpointLine)
                    .font(.system(size: 10))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 45)
                Button(action: {
                    if let line = Int(breakpointLine), !breakpointURL.isEmpty {
                        cdp.setBreakpoint(url: breakpointURL, line: line - 1, condition: breakpointCondition)
                        breakpointLine = ""
                    }
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .foregroundColor(DT.link)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(cdp.breakpoints) { bp in
                        HStack(spacing: 4) {
                            Circle().fill(DT.error).frame(width: 8, height: 8)
                            Text(URL(string: bp.url)?.lastPathComponent ?? bp.url)
                                .font(.system(size: 10))
                                .foregroundColor(DT.text)
                                .lineLimit(1)
                            Text(":\(bp.lineNumber + 1)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(DT.textSecondary)
                            Spacer()
                            Button(action: { cdp.removeBreakpoint(bp.id) }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8))
                            }
                            .buttonStyle(.borderless)
                            .foregroundColor(DT.textMuted)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                    }
                }
            }
            .frame(maxHeight: 100)
        }
    }

    // MARK: - Call Stack Panel

    var callStackPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Call Stack")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(DT.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DT.toolbarBg)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(cdp.callFrames) { frame in
                        HStack(spacing: 4) {
                            Text(frame.displayName)
                                .font(.system(size: 10, weight: selectedFrameId == frame.id ? .semibold : .regular))
                                .foregroundColor(selectedFrameId == frame.id ? DT.link : DT.text)
                                .lineLimit(1)
                            Spacer()
                            Text("L\(frame.lineNumber + 1)")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(DT.textMuted)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(selectedFrameId == frame.id ? DT.selectedBg : Color.clear)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedFrameId = frame.id
                            // Navigate to the script/line of this frame
                            if let script = cdp.scripts.first(where: { $0.id == frame.scriptId }) {
                                cdp.loadScriptSource(script)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 100)
        }
    }

    // MARK: - Watch Panel

    var watchPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Watch")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(DT.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DT.toolbarBg)

            HStack(spacing: 4) {
                TextField("Expresión…", text: $newWatchExpr, onCommit: {
                    if !newWatchExpr.isEmpty {
                        cdp.watchExpressions.append((id: UUID(), expr: newWatchExpr, value: "…"))
                        newWatchExpr = ""
                        cdp.refreshWatchExpressions()
                    }
                })
                .font(.system(size: 10))
                .textFieldStyle(.roundedBorder)

                Button(action: { cdp.refreshWatchExpressions() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(cdp.watchExpressions, id: \.id) { watch in
                        HStack(spacing: 4) {
                            Text(watch.expr)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(DT.property)
                                .lineLimit(1)
                            Text("=")
                                .font(.system(size: 10))
                                .foregroundColor(DT.textMuted)
                            Text(watch.value)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(DT.string)
                                .lineLimit(1)
                            Spacer()
                            Button(action: {
                                cdp.watchExpressions.removeAll { $0.id == watch.id }
                            }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8))
                            }
                            .buttonStyle(.borderless)
                            .foregroundColor(DT.textMuted)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                    }
                }
            }
            .frame(maxHeight: 80)
        }
    }

    // MARK: - Debug Console

    var debugConsole: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Consola CDP")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(DT.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DT.toolbarBg)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(cdp.consoleOutput, id: \.id) { entry in
                        Text(entry.text)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(entry.type == "error" ? DT.error : DT.text)
                            .textSelection(.enabled)
                            .padding(.horizontal, 8)
                    }
                }
            }
            .frame(maxHeight: .infinity)

            HStack(spacing: 4) {
                Text("›")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(DT.link)
                TextField("Evaluar expresión…", text: $evalExpression, onCommit: {
                    if !evalExpression.isEmpty {
                        cdp.evaluate(evalExpression)
                        evalExpression = ""
                    }
                })
                .font(.system(size: 11, design: .monospaced))
                .textFieldStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(DT.inputBg)
        }
    }
}
