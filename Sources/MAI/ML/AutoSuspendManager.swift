import Foundation
import Combine

/// Gestiona la suspensión automática de pestañas inactivas para ahorrar memoria (~70MB por tab).
/// Con modo de aprendizaje: pregunta al usuario y aprende sus preferencias por dominio.
class AutoSuspendManager: ObservableObject {
    static let shared = AutoSuspendManager()

    // MARK: - Configuración (persistida en UserDefaults)

    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "autoSuspendEnabled") }
    }

    @Published var thresholdMinutes: Int {
        didSet { UserDefaults.standard.set(thresholdMinutes, forKey: "autoSuspendThresholdMinutes") }
    }

    @Published var learningModeEnabled: Bool {
        didSet { UserDefaults.standard.set(learningModeEnabled, forKey: "autoSuspendLearningMode") }
    }

    /// Cantidad de tabs auto-suspendidas (no manualmente)
    @Published var autoSuspendedCount: Int = 0

    // MARK: - Banner State

    /// Tab esperando confirmación del usuario (muestra banner)
    @Published var pendingSuspensionTab: Tab?
    /// Dominio del tab pendiente
    @Published var pendingSuspensionDomain: String = ""

    // MARK: - Privado

    private var timer: Timer?
    private var autoDismissTimer: Timer?
    private weak var browserState: BrowserState?
    private var autoSuspendedTabIDs: Set<UUID> = []
    /// Tabs rechazadas esta sesión (no volver a preguntar)
    private var declinedTabIDs: Set<UUID> = []

    private let mlModel = SuspensionMLModel.shared

    private init() {
        self.isEnabled = UserDefaults.standard.object(forKey: "autoSuspendEnabled") as? Bool ?? true
        self.thresholdMinutes = UserDefaults.standard.object(forKey: "autoSuspendThresholdMinutes") as? Int ?? 15
        self.learningModeEnabled = UserDefaults.standard.object(forKey: "autoSuspendLearningMode") as? Bool ?? true
    }

    // MARK: - Público

    /// Inicia el monitoreo de tabs. Se llama desde BrowserState.init().
    func start(browserState: BrowserState) {
        self.browserState = browserState
        startTimer()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        autoDismissTimer?.invalidate()
        autoDismissTimer = nil
    }

    // MARK: - User Actions (from banner)

    /// Usuario aprobó suspender la tab pendiente
    func userApprovedSuspension() {
        guard let tab = pendingSuspensionTab, let browserState = browserState else { return }
        let domain = pendingSuspensionDomain
        let inactivity = tab.timeSinceLastInteraction / 60.0

        mlModel.recordDecision(
            domain: domain,
            inactivityMinutes: inactivity,
            openTabCount: browserState.tabs.count,
            isMuted: tab.isMuted,
            approved: true
        )

        browserState.suspendTab(tab)
        autoSuspendedTabIDs.insert(tab.id)
        updateCount(browserState: browserState)
        print("🤖✅ Usuario aprobó suspender: \(tab.title)")

        dismissBanner()
    }

    /// Usuario rechazó suspender la tab pendiente
    func userDeclinedSuspension() {
        guard let tab = pendingSuspensionTab, let browserState = browserState else { return }
        let domain = pendingSuspensionDomain
        let inactivity = tab.timeSinceLastInteraction / 60.0

        mlModel.recordDecision(
            domain: domain,
            inactivityMinutes: inactivity,
            openTabCount: browserState.tabs.count,
            isMuted: tab.isMuted,
            approved: false
        )

        declinedTabIDs.insert(tab.id)
        print("🤖❌ Usuario rechazó suspender: \(tab.title)")

        dismissBanner()
    }

    /// Usuario eligió "Siempre" para este dominio
    func userApprovedAlways() {
        guard let tab = pendingSuspensionTab, let browserState = browserState else { return }
        let domain = pendingSuspensionDomain

        mlModel.markAlwaysSuspend(domain: domain)

        browserState.suspendTab(tab)
        autoSuspendedTabIDs.insert(tab.id)
        updateCount(browserState: browserState)
        print("🤖⚡ Usuario marcó 'Siempre suspender': \(domain)")

        dismissBanner()
    }

    private func dismissBanner() {
        autoDismissTimer?.invalidate()
        autoDismissTimer = nil
        pendingSuspensionTab = nil
        pendingSuspensionDomain = ""
    }

    // MARK: - Timer

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.checkTabs()
        }
    }

    private func checkTabs() {
        guard isEnabled, let browserState = browserState else { return }

        // Si hay un banner activo, no hacer nada (1 banner a la vez)
        if pendingSuspensionTab != nil { return }

        let thresholdSeconds = TimeInterval(thresholdMinutes * 60)

        for tab in browserState.tabs {
            guard !shouldSkip(tab, browserState: browserState) else { continue }
            guard tab.timeSinceLastInteraction > thresholdSeconds else { continue }

            if learningModeEnabled {
                let domain = Self.extractDomain(from: tab.url)
                let calendar = Calendar.current
                let now = Date()

                let prediction = mlModel.predict(
                    domain: domain,
                    inactivityMinutes: tab.timeSinceLastInteraction / 60.0,
                    hourOfDay: calendar.component(.hour, from: now),
                    dayOfWeek: calendar.component(.weekday, from: now),
                    openTabCount: browserState.tabs.count,
                    isMuted: tab.isMuted
                )

                switch prediction {
                case .autoSuspend:
                    DispatchQueue.main.async {
                        browserState.suspendTab(tab)
                        self.autoSuspendedTabIDs.insert(tab.id)
                        self.updateCount(browserState: browserState)
                        print("🤖🧠 ML auto-suspendida: \(tab.title) (\(domain))")
                    }

                case .ask:
                    DispatchQueue.main.async {
                        self.showBanner(for: tab, domain: domain)
                    }
                    return // Solo 1 banner a la vez

                case .neverSuspend:
                    // ML dice no suspender este dominio
                    continue
                }
            } else {
                // Modo clásico: suspender directamente sin preguntar
                DispatchQueue.main.async {
                    browserState.suspendTab(tab)
                    self.autoSuspendedTabIDs.insert(tab.id)
                    self.updateCount(browserState: browserState)
                    print("🤖 Auto-suspendida: \(tab.title) (inactiva \(Int(tab.timeSinceLastInteraction / 60)) min)")
                }
            }
        }
    }

    private func showBanner(for tab: Tab, domain: String) {
        pendingSuspensionTab = tab
        pendingSuspensionDomain = domain

        // Auto-dismiss después de 45 segundos → descarta sin penalizar
        autoDismissTimer?.invalidate()
        autoDismissTimer = Timer.scheduledTimer(withTimeInterval: 45.0, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.dismissBanner()
            }
        }
    }

    /// Determina si una tab nunca debe ser auto-suspendida
    private func shouldSkip(_ tab: Tab, browserState: BrowserState) -> Bool {
        if tab.isSuspended { return true }
        if tab.id == browserState.currentTab?.id { return true }
        if tab.isPinned { return true }
        if tab.useChromiumEngine { return true }
        if tab.isLoading { return true }
        if tab.url == "about:blank" || tab.url.isEmpty { return true }
        if declinedTabIDs.contains(tab.id) { return true }
        return false
    }

    private func updateCount(browserState: BrowserState) {
        autoSuspendedCount = browserState.tabs.filter { tab in
            tab.isSuspended && autoSuspendedTabIDs.contains(tab.id)
        }.count
    }

    /// Llamar cuando una tab se restaura manualmente para limpiar tracking
    func tabResumed(_ tab: Tab) {
        autoSuspendedTabIDs.remove(tab.id)
        declinedTabIDs.remove(tab.id)
        if let browserState = browserState {
            updateCount(browserState: browserState)
        }
    }

    /// Llamar cuando una tab se cierra para limpiar tracking
    func tabClosed(_ tab: Tab) {
        autoSuspendedTabIDs.remove(tab.id)
        declinedTabIDs.remove(tab.id)
        if tab.id == pendingSuspensionTab?.id {
            dismissBanner()
        }
        if let browserState = browserState {
            updateCount(browserState: browserState)
        }
    }

    // MARK: - Helpers

    static func extractDomain(from urlString: String) -> String {
        guard let url = URL(string: urlString), let host = url.host else {
            return urlString
        }
        // Quitar "www." para agrupar
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
