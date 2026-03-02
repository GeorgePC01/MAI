import SwiftUI
import WebKit

/// Vista de configuración del navegador
struct SettingsView: View {
    @EnvironmentObject var browserState: BrowserState

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            PrivacySettingsView()
                .tabItem {
                    Label("Privacidad", systemImage: "hand.raised")
                }

            AppearanceSettingsView()
                .tabItem {
                    Label("Apariencia", systemImage: "paintbrush")
                }

            AdvancedSettingsView()
                .tabItem {
                    Label("Avanzado", systemImage: "slider.horizontal.3")
                }
        }
        .frame(width: 500, height: 400)
    }
}

/// Configuración general
struct GeneralSettingsView: View {
    @AppStorage("homepage") private var homepage = "https://www.google.com"
    @AppStorage("searchEngine") private var searchEngine = "Google"
    @AppStorage("downloadLocation") private var downloadLocation = "~/Downloads"

    let searchEngines = ["Google", "DuckDuckGo", "Bing", "Ecosia"]

    var body: some View {
        Form {
            Section("Inicio") {
                TextField("Página de inicio", text: $homepage)

                Picker("Motor de búsqueda", selection: $searchEngine) {
                    ForEach(searchEngines, id: \.self) { engine in
                        Text(engine).tag(engine)
                    }
                }
            }

            Section("Descargas") {
                HStack {
                    TextField("Ubicación de descargas", text: $downloadLocation)
                    Button("Elegir...") {
                        selectDownloadFolder()
                    }
                }
            }

            Section("Pestañas") {
                Toggle("Abrir links en nueva pestaña", isOn: .constant(true))
                Toggle("Confirmar al cerrar múltiples pestañas", isOn: .constant(true))
            }
        }
        .padding()
    }

    private func selectDownloadFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK {
            downloadLocation = panel.url?.path ?? downloadLocation
        }
    }
}

/// Configuración de privacidad
struct PrivacySettingsView: View {
    @ObservedObject private var privacyManager = PrivacyManager.shared
    @ObservedObject private var easyListManager = EasyListManager.shared
    @ObservedObject private var phishingDetector = PhishingDetector.shared
    @AppStorage("dnsOverHTTPS") private var dnsOverHTTPS = true
    @AppStorage("clearDataOnExit") private var clearDataOnExit = false

    var body: some View {
        Form {
            Section("Bloqueo") {
                Toggle("Bloquear rastreadores", isOn: $privacyManager.blockTrackers)
                Toggle("Bloquear anuncios", isOn: $privacyManager.blockAds)

                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Bloquear cookies de terceros", isOn: $privacyManager.blockThirdPartyCookies)
                    Text("Los dominios de OAuth (Google, Microsoft, etc.) están en whitelist")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section("EasyList (Listas de filtros)") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Usar EasyList + EasyPrivacy", isOn: $privacyManager.useEasyList)
                    Text("~80,000 reglas de bloqueo de ads y trackers (mismas que uBlock Origin)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if privacyManager.useEasyList {
                    HStack {
                        if easyListManager.isLoading {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 16, height: 16)
                        } else {
                            Image(systemName: easyListManager.isLoaded ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(easyListManager.isLoaded ? .green : .secondary)
                        }
                        Text(easyListManager.statusMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        if let date = easyListManager.lastUpdateDate {
                            Text(date, style: .relative)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    Button("Actualizar listas ahora") {
                        Task { await easyListManager.forceUpdate() }
                    }
                    .buttonStyle(.borderless)
                    .disabled(easyListManager.isLoading)
                }
            }

            Section("Detección de Phishing") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Detectar URLs de phishing", isOn: $phishingDetector.isEnabled)
                    Text("Analiza URLs con heurísticas para detectar suplantación de identidad y sitios fraudulentos")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section("Protección") {
                Toggle("DNS sobre HTTPS", isOn: $dnsOverHTTPS)
                Toggle("Protección contra fingerprinting", isOn: $privacyManager.fingerprintProtection)
            }

            Section("Estadísticas") {
                HStack {
                    Label("\(privacyManager.blockedRequestsCount) requests bloqueadas", systemImage: "shield.checkered")
                    Spacer()
                    Button("Reiniciar") {
                        privacyManager.resetBlockedCount()
                    }
                    .buttonStyle(.borderless)
                }
            }

            Section("Datos") {
                Toggle("Borrar datos al salir", isOn: $clearDataOnExit)

                Button("Borrar todos los datos ahora...") {
                    clearAllData()
                }
                .foregroundColor(.red)
            }
        }
        .padding()
    }

    private func clearAllData() {
        let alert = NSAlert()
        alert.messageText = "Borrar todos los datos"
        alert.informativeText = "Esto eliminará historial, cookies, cache y datos de sitios (incluyendo preferencias de tema de Google). Esta acción no se puede deshacer."
        alert.addButton(withTitle: "Borrar")
        alert.addButton(withTitle: "Cancelar")
        alert.alertStyle = .warning

        if alert.runModal() == .alertFirstButtonReturn {
            // Borrar datos de WebKit
            let dataStore = WKWebsiteDataStore.default()
            let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
            dataStore.removeData(ofTypes: dataTypes, modifiedSince: .distantPast) {
                DispatchQueue.main.async {
                    // Mostrar confirmación
                    let confirmAlert = NSAlert()
                    confirmAlert.messageText = "Datos borrados"
                    confirmAlert.informativeText = "Se han eliminado todas las cookies, cache y datos de sitios. Recarga la página para ver los cambios."
                    confirmAlert.addButton(withTitle: "OK")
                    confirmAlert.alertStyle = .informational
                    confirmAlert.runModal()
                }
            }

            // También limpiar historial local
            HistoryManager.shared.clearAll()
        }
    }
}

/// Configuración de apariencia
struct AppearanceSettingsView: View {
    @AppStorage("theme") private var theme = "System"
    @AppStorage("fontSize") private var fontSize = 16.0
    @AppStorage("showStatusBar") private var showStatusBar = true
    @AppStorage("tabBarPosition") private var tabBarPosition = "Top"

    let themes = ["System", "Light", "Dark"]
    let tabPositions = ["Top", "Bottom"]

    var body: some View {
        Form {
            Section("Tema") {
                Picker("Apariencia", selection: $theme) {
                    ForEach(themes, id: \.self) { t in
                        Text(t).tag(t)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Texto") {
                HStack {
                    Text("Tamaño de fuente: \(Int(fontSize))")
                    Slider(value: $fontSize, in: 10...24, step: 1)
                }
            }

            Section("Interfaz") {
                Toggle("Mostrar barra de estado", isOn: $showStatusBar)

                Picker("Posición de pestañas", selection: $tabBarPosition) {
                    ForEach(tabPositions, id: \.self) { pos in
                        Text(pos).tag(pos)
                    }
                }
            }
        }
        .padding()
    }
}

/// Configuración avanzada
struct AdvancedSettingsView: View {
    @ObservedObject private var autoSuspend = AutoSuspendManager.shared
    @ObservedObject private var mlModel = SuspensionMLModel.shared
    @AppStorage("enableHardwareAcceleration") private var enableHardwareAcceleration = true
    @AppStorage("maxMemoryPerTab") private var maxMemoryPerTab = 200.0
    @AppStorage("enableDeveloperTools") private var enableDeveloperTools = false
    @State private var showResetAlert = false

    var body: some View {
        Form {
            Section("Auto-Suspensión de Pestañas") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Suspender pestañas inactivas automáticamente", isOn: $autoSuspend.isEnabled)
                    Text("Suspende pestañas no usadas para liberar ~70 MB de RAM por pestaña")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if autoSuspend.isEnabled {
                    HStack {
                        Text("Umbral de inactividad: \(autoSuspend.thresholdMinutes) min")
                        Slider(value: Binding(
                            get: { Double(autoSuspend.thresholdMinutes) },
                            set: { autoSuspend.thresholdMinutes = Int($0) }
                        ), in: 5...60, step: 5)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Modo de aprendizaje", isOn: $autoSuspend.learningModeEnabled)
                        Text("Pregunta antes de suspender y aprende tus preferencias por dominio")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if autoSuspend.learningModeEnabled {
                        LabeledContent("Decisiones registradas", value: "\(mlModel.totalDecisions)")
                        LabeledContent("Dominios aprendidos", value: "\(mlModel.learnedDomains)")

                        Button("Reiniciar aprendizaje") {
                            showResetAlert = true
                        }
                        .foregroundColor(.red)
                        .alert("Reiniciar aprendizaje", isPresented: $showResetAlert) {
                            Button("Cancelar", role: .cancel) { }
                            Button("Reiniciar", role: .destructive) {
                                mlModel.resetAll()
                            }
                        } message: {
                            Text("Se borrarán todas las decisiones y estadísticas de suspensión. El modelo empezará a aprender de cero.")
                        }
                    }

                    if autoSuspend.autoSuspendedCount > 0 {
                        LabeledContent("Pestañas auto-suspendidas", value: "\(autoSuspend.autoSuspendedCount)")
                    }
                }
            }

            Section("Rendimiento") {
                Toggle("Aceleración por hardware", isOn: $enableHardwareAcceleration)

                HStack {
                    Text("Memoria máxima por pestaña: \(Int(maxMemoryPerTab)) MB")
                    Slider(value: $maxMemoryPerTab, in: 100...500, step: 50)
                }
            }

            Section("Desarrollo") {
                Toggle("Habilitar herramientas de desarrollador", isOn: $enableDeveloperTools)
            }

            Section("Información") {
                LabeledContent("Versión", value: "0.7.0-alpha")
                LabeledContent("Motor", value: "WebKit + CEF")
                LabeledContent("Build", value: "2026.02.28")
            }
        }
        .padding()
    }
}
