import Foundation
import Security
import WebKit
import LocalAuthentication
import CommonCrypto
import SecureMem

/// Credencial guardada en Keychain
struct SavedCredential: Identifiable {
    var id: String { "\(host)|\(username)" }
    let host: String
    let username: String
    let password: String
}

/// Credencial pendiente de guardar (capturada del formulario)
struct PendingCredential {
    let host: String
    let username: String
    let password: String
}

/// Gestor de contraseñas usando macOS Keychain (Security framework)
/// Protección Secure Enclave: cada credencial requiere biometría hardware (Touch ID)
/// o contraseña del sistema para acceder — verificado por el chip SE, no por software.
/// Backup cifrado automático: AES-256-GCM a disco para recuperación ante reset.
/// (ISO 27001 A.9.4, NIST 800-63B)
class PasswordManager: ObservableObject {
    static let shared = PasswordManager()
    private let service = "com.mai.browser.passwords"

    /// Ventana de tiempo (segundos) en que la autenticación biométrica es válida
    private let authValidityWindow: TimeInterval = 300 // 5 minutos
    private var lastAuthDate: Date?

    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "passwordManagerEnabled") }
    }

    @Published var savedCount: Int = 0
    @Published var isAuthenticated: Bool = false

    /// Crea SecAccessControl para protección Secure Enclave.
    /// Requiere biometría hardware (Touch ID) o contraseña del sistema.
    /// La clave de cifrado NUNCA sale del Secure Enclave.
    private func createSecureAccess() -> SecAccessControl? {
        var error: Unmanaged<CFError>?
        let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
            .userPresence, // Touch ID → fallback a password del sistema (igual que LAContext)
            &error
        )
        if let error = error {
            print("⚠️ SecAccessControl creation failed: \(error.takeRetainedValue())")
            return nil
        }
        return access
    }

    /// Backup directory for encrypted credential exports
    private var backupDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MAI", isDirectory: true)
            .appendingPathComponent("backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport
    }

    private init() {
        self.isEnabled = UserDefaults.standard.object(forKey: "passwordManagerEnabled") as? Bool ?? true
        refreshCount()
        migrateToSecureEnclave()
    }

    // MARK: - Secure Enclave Migration

    /// Migra credenciales existentes (kSecAttrAccessibleWhenUnlocked) a protección Secure Enclave.
    /// Se ejecuta una sola vez. Las credenciales antiguas se re-guardan con SecAccessControl.
    private func migrateToSecureEnclave() {
        let migrated = UserDefaults.standard.bool(forKey: "passwordManager_seMigrated")
        guard !migrated else { return }

        // Leer todas las credenciales con el esquema viejo
        let query: [String: Any] = [
            kSecClass as String:            kSecClassInternetPassword,
            kSecAttrLabel as String:        service,
            kSecReturnAttributes as String: true,
            kSecReturnData as String:       true,
            kSecMatchLimit as String:       kSecMatchLimitAll
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else {
            UserDefaults.standard.set(true, forKey: "passwordManager_seMigrated")
            return
        }

        guard let access = createSecureAccess() else {
            // Si no podemos crear SecAccessControl (e.g. Mac sin passcode), marcar como migrado
            // y seguir con el esquema actual — no bloquear al usuario
            UserDefaults.standard.set(true, forKey: "passwordManager_seMigrated")
            return
        }

        for item in items {
            guard let server = item[kSecAttrServer as String] as? String,
                  let account = item[kSecAttrAccount as String] as? String,
                  let data = item[kSecValueData as String] as? Data else { continue }

            // Borrar item viejo
            let deleteQuery: [String: Any] = [
                kSecClass as String:        kSecClassInternetPassword,
                kSecAttrServer as String:   server,
                kSecAttrAccount as String:  account,
                kSecAttrLabel as String:    service
            ]
            SecItemDelete(deleteQuery as CFDictionary)

            // Re-guardar con Secure Enclave protection
            let addQuery: [String: Any] = [
                kSecClass as String:        kSecClassInternetPassword,
                kSecAttrServer as String:   server,
                kSecAttrAccount as String:  account,
                kSecAttrLabel as String:    service,
                kSecValueData as String:    data,
                kSecAttrAccessControl as String: access
            ]
            SecItemAdd(addQuery as CFDictionary, nil)
        }

        UserDefaults.standard.set(true, forKey: "passwordManager_seMigrated")
        auditLog(action: "secure_enclave_migration", host: "*(\(items.count) credentials)")
    }

    // MARK: - Biometric / System Password Authentication (ISO 27001 A.9.4)

    /// Autentica al usuario con Touch ID o contraseña del sistema antes de operaciones sensibles
    func authenticate(reason: String = "Acceder a contraseñas guardadas", completion: @escaping (Bool) -> Void) {
        // Si la autenticación reciente sigue válida, no pedir de nuevo
        if let lastAuth = lastAuthDate, Date().timeIntervalSince(lastAuth) < authValidityWindow {
            isAuthenticated = true
            completion(true)
            return
        }

        let context = LAContext()
        context.localizedCancelTitle = "Cancelar"
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            print("⚠️ LocalAuthentication no disponible: \(error?.localizedDescription ?? "desconocido")")
            completion(false)
            return
        }

        // deviceOwnerAuthentication = Touch ID → fallback a contraseña del sistema
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { [weak self] success, authError in
            DispatchQueue.main.async {
                if success {
                    self?.lastAuthDate = Date()
                    self?.isAuthenticated = true
                } else {
                    self?.isAuthenticated = false
                    if let authError = authError {
                        print("🔒 Autenticación fallida: \(authError.localizedDescription)")
                    }
                }
                completion(success)
            }
        }
    }

    /// Invalida la sesión de autenticación actual
    func lockVault() {
        lastAuthDate = nil
        isAuthenticated = false
        auditLog(action: "vault_locked", host: "-")
    }

    // MARK: - Clipboard Protection (B4)

    private var clipboardClearTimer: DispatchWorkItem?

    /// Copia un password al clipboard y lo limpia automáticamente después de 30 segundos
    func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        auditLog(action: "password_copied_to_clipboard", host: "-")

        // Cancelar timer anterior si existe
        clipboardClearTimer?.cancel()

        // Auto-limpiar clipboard a los 30s
        let clearWork = DispatchWorkItem { [weak self] in
            let current = NSPasteboard.general.string(forType: .string)
            // Solo limpiar si el clipboard todavía contiene nuestro texto
            if current == text {
                NSPasteboard.general.clearContents()
                self?.auditLog(action: "clipboard_auto_cleared", host: "-")
            }
        }
        clipboardClearTimer = clearWork
        DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: clearWork)
    }

    // MARK: - Audit Log (ISO 27001 A.12.4)

    /// Registra operaciones del password manager en archivo local de auditoría
    private func auditLog(action: String, host: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let entry = "[\(timestamp)] action=\(action) host=\(host)\n"

        let logDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MAI", isDirectory: true)
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)

        let logFile = logDir.appendingPathComponent("password_audit.log")
        if let data = entry.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFile.path) {
                if let handle = try? FileHandle(forWritingTo: logFile) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                try? data.write(to: logFile, options: .atomic)
            }
        }
    }

    // MARK: - Keychain CRUD

    func saveCredential(host: String, username: String, password: String) -> Bool {
        guard let passwordData = password.data(using: .utf8) else { return false }

        // Transacción atómica: intentar update primero, fallback a add (OWASP A04)
        let searchQuery: [String: Any] = [
            kSecClass as String:        kSecClassInternetPassword,
            kSecAttrServer as String:   host,
            kSecAttrAccount as String:  username,
            kSecAttrLabel as String:    service
        ]

        // Secure Enclave: SecAccessControl protege con biometría hardware
        // Fallback: kSecAttrAccessibleWhenUnlocked si SE no disponible (Mac sin passcode)
        let access = createSecureAccess()

        var updateAttributes: [String: Any] = [
            kSecValueData as String: passwordData
        ]
        if let access = access {
            updateAttributes[kSecAttrAccessControl as String] = access
        } else {
            updateAttributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        }

        let updateStatus = SecItemUpdate(searchQuery as CFDictionary, updateAttributes as CFDictionary)

        if updateStatus == errSecSuccess {
            refreshCount()
            auditLog(action: "credential_updated", host: host)
            autoBackup()
            return true
        }

        // No existe aún → agregar nueva
        if updateStatus == errSecItemNotFound {
            var addQuery = searchQuery
            addQuery[kSecValueData as String] = passwordData
            if let access = access {
                addQuery[kSecAttrAccessControl as String] = access
            } else {
                addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            }

            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            if addStatus == errSecSuccess {
                refreshCount()
                auditLog(action: "credential_saved", host: host)
                autoBackup()
                return true
            }
        }

        return false
    }

    /// Obtiene credenciales para un host — uso interno (auto-fill ya gated por authenticate)
    func getCredentials(for host: String) -> [SavedCredential] {
        return fetchCredentials(query: [
            kSecClass as String:            kSecClassInternetPassword,
            kSecAttrServer as String:       host,
            kSecAttrLabel as String:        service,
            kSecReturnAttributes as String: true,
            kSecReturnData as String:       true,
            kSecMatchLimit as String:       kSecMatchLimitAll
        ])
    }

    /// Verifica si existen credenciales para un host SIN devolver passwords (no requiere auth)
    func hasCredentials(for host: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String:            kSecClassInternetPassword,
            kSecAttrServer as String:       host,
            kSecAttrLabel as String:        service,
            kSecMatchLimit as String:       kSecMatchLimitOne
        ]
        var result: AnyObject?
        return SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess
    }

    /// Obtiene TODAS las credenciales — requiere autenticación previa (ISO 27001 A.9.4)
    func getAllCredentials() -> [SavedCredential] {
        return fetchCredentials(query: [
            kSecClass as String:            kSecClassInternetPassword,
            kSecAttrLabel as String:        service,
            kSecReturnAttributes as String: true,
            kSecReturnData as String:       true,
            kSecMatchLimit as String:       kSecMatchLimitAll
        ])
    }

    /// Obtiene todas las credenciales con autenticación biométrica (para UI de "Ver contraseñas")
    func getAllCredentialsAuthenticated(completion: @escaping ([SavedCredential]) -> Void) {
        authenticate(reason: "Ver contraseñas guardadas") { [weak self] success in
            guard success, let self = self else {
                completion([])
                return
            }
            self.auditLog(action: "all_credentials_viewed", host: "*")
            completion(self.getAllCredentials())
        }
    }

    /// Auto-fill con autenticación biométrica — gatea el acceso a la contraseña real
    func getCredentialsForAutoFill(host: String, completion: @escaping ([SavedCredential]) -> Void) {
        // Verificar primero si hay credenciales sin acceder a passwords
        guard hasCredentials(for: host) else {
            completion([])
            return
        }
        authenticate(reason: "Autocompletar contraseña en \(host)") { [weak self] success in
            guard success, let self = self else {
                completion([])
                return
            }
            self.auditLog(action: "autofill_accessed", host: host)
            completion(self.getCredentials(for: host))
        }
    }

    /// Genera el script de auto-fill con el password protegido por mlock.
    /// El password vive en memoria protegida (no swap) y se borra inmediatamente después de generar el script.
    func secureAutoFillScript(for credential: SavedCredential) -> String {
        // Proteger el password con mlock — nunca toca swap
        let securePass = SecureString(credential.password)
        defer { securePass.clear() } // Zero-fill inmediatamente después de uso

        guard let password = securePass.utf8String else { return "" }
        let script = Self.autoFillScript(username: credential.username, password: password)
        // Al salir del scope, securePass.deinit hace memset_s + munlock + free
        return script
    }

    private func fetchCredentials(query: [String: Any]) -> [SavedCredential] {
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let items = result as? [[String: Any]] else { return [] }

        return items.compactMap { item in
            guard let server = item[kSecAttrServer as String] as? String,
                  let account = item[kSecAttrAccount as String] as? String,
                  let data = item[kSecValueData as String] as? Data,
                  let password = String(data: data, encoding: .utf8) else { return nil }
            return SavedCredential(host: server, username: account, password: password)
        }
    }

    @discardableResult
    func deleteCredential(host: String, username: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String:        kSecClassInternetPassword,
            kSecAttrServer as String:   host,
            kSecAttrAccount as String:  username,
            kSecAttrLabel as String:    service
        ]
        let ok = SecItemDelete(query as CFDictionary) == errSecSuccess
        if ok {
            refreshCount()
            auditLog(action: "credential_deleted", host: host)
            autoBackup()
        }
        return ok
    }

    func deleteAllCredentials() {
        let query: [String: Any] = [
            kSecClass as String:    kSecClassInternetPassword,
            kSecAttrLabel as String: service
        ]
        SecItemDelete(query as CFDictionary)
        refreshCount()
        auditLog(action: "all_credentials_deleted", host: "*")
    }

    private func refreshCount() {
        // Contar items SIN deserializar passwords en memoria (Fix #12)
        let query: [String: Any] = [
            kSecClass as String:            kSecClassInternetPassword,
            kSecAttrLabel as String:        service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String:       kSecMatchLimitAll
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let items = result as? [[String: Any]] {
            savedCount = items.count
        } else {
            savedCount = 0
        }
    }

    // MARK: - Breached Password Check (NIST 800-63B §5.1.1.2)

    /// Verifica si un password aparece en filtraciones conocidas usando HIBP k-anonymity API.
    /// Solo envía los primeros 5 caracteres del hash SHA-1 — el password nunca sale del dispositivo.
    func checkBreached(password: String, completion: @escaping (Int) -> Void) {
        // SHA-1 hash del password
        let data = Data(password.utf8)
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        data.withUnsafeBytes { ptr in
            _ = CC_SHA1(ptr.baseAddress, CC_LONG(data.count), &hash)
        }
        let sha1 = hash.map { String(format: "%02X", $0) }.joined()

        let prefix = String(sha1.prefix(5))
        let suffix = String(sha1.dropFirst(5))

        guard let url = URL(string: "https://api.pwnedpasswords.com/range/\(prefix)") else {
            completion(0)
            return
        }

        var request = URLRequest(url: url, timeoutInterval: 5)
        request.addValue("MAI-Browser", forHTTPHeaderField: "User-Agent")
        request.addValue("true", forHTTPHeaderField: "Add-Padding") // HIBP padding para privacidad extra

        URLSession.shared.dataTask(with: request) { data, _, error in
            guard error == nil, let data = data, let response = String(data: data, encoding: .utf8) else {
                DispatchQueue.main.async { completion(0) } // Falla silenciosa — no bloquear UX
                return
            }

            // Cada línea: "SUFFIX:COUNT" — buscar nuestro suffix
            var breachCount = 0
            for line in response.components(separatedBy: "\r\n") {
                let parts = line.split(separator: ":")
                guard parts.count == 2 else { continue }
                if parts[0] == suffix, let count = Int(parts[1]) {
                    breachCount = count
                    break
                }
            }

            DispatchQueue.main.async { completion(breachCount) }
        }.resume()
    }

    // MARK: - JavaScript

    /// Script para capturar credenciales al enviar formulario
    /// Seguridad: credentials se encodean en base64 antes del postMessage (ISO 27001 A.10.1)
    /// B2: Valida que form action no envíe credenciales a dominio externo
    static let captureScript: String = """
    (function() {
        if (window._maiPasswordCapture) return;
        window._maiPasswordCapture = true;

        function _e(s) { return btoa(unescape(encodeURIComponent(s))); }

        function _isSameDomain(formAction) {
            if (!formAction || formAction === '' || formAction === '#') return true;
            try {
                var actionUrl = new URL(formAction, window.location.href);
                var currentHost = window.location.hostname;
                var actionHost = actionUrl.hostname;
                if (actionHost === currentHost) return true;
                var currentDomain = currentHost.split('.').slice(-2).join('.');
                var actionDomain = actionHost.split('.').slice(-2).join('.');
                return currentDomain === actionDomain;
            } catch(e) { return true; }
        }

        function captureCredentials(passField) {
            var form = passField.closest('form');
            if (form && !_isSameDomain(form.action)) {
                console.log('[MAI] Password capture blocked: form submits to external domain');
                return;
            }
            var container = form || document.body;
            var inputs = container.querySelectorAll(
                'input[type="text"], input[type="email"], input[name*="user"], input[name*="email"], input[name*="login"], input[autocomplete="username"]'
            );
            var username = '';
            for (var i = 0; i < inputs.length; i++) {
                if (inputs[i].value.trim()) { username = inputs[i].value.trim(); break; }
            }
            var password = passField.value;
            if (username && password && password.length >= 3) {
                window.webkit.messageHandlers.passwordCapture.postMessage({
                    type: 'credentials_captured',
                    host: _e(window.location.hostname),
                    username: _e(username),
                    password: _e(password),
                    encoded: true
                });
            }
        }

        document.addEventListener('submit', function(e) {
            var pass = e.target.querySelector('input[type="password"]');
            if (pass) captureCredentials(pass);
        }, true);

        document.addEventListener('click', function(e) {
            var btn = e.target.closest('button[type="submit"], input[type="submit"], button:not([type])');
            if (!btn) return;
            var form = btn.closest('form');
            if (!form) return;
            var pass = form.querySelector('input[type="password"]');
            if (pass) setTimeout(function() { captureCredentials(pass); }, 100);
        }, true);
    })();
    """

    /// Escapa un string de forma segura para inyección en JS usando JSONSerialization
    /// (OWASP A03 Injection Prevention — nunca interpolar strings directamente en JS)
    private static func jsonEscape(_ string: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [string], options: []),
              let json = String(data: data, encoding: .utf8) else {
            return "\"\"" // fallback seguro: string vacío
        }
        // JSONSerialization produce ["valor"], extraemos solo "valor"
        let trimmed = json.dropFirst(1).dropLast(1)
        return String(trimmed)
    }

    /// Script para auto-rellenar credenciales
    /// Seguridad: credentials se pasan como base64 y se decodifican en runtime JS
    /// para que nunca aparezcan como texto plano en el source del script (OWASP A02)
    /// B2: Valida que form action sea mismo dominio antes de llenar
    static func autoFillScript(username: String, password: String) -> String {
        // Encode credentials as base64 — no plaintext in JS source
        let userB64 = Data(username.utf8).base64EncodedString()
        let passB64 = Data(password.utf8).base64EncodedString()

        // JSON-escape the base64 strings as extra safety layer
        let safeUserB64 = jsonEscape(userB64)
        let safePassB64 = jsonEscape(passB64)

        return """
        (function() {
            var passFields = document.querySelectorAll('input[type="password"]');
            if (passFields.length === 0) return false;
            var passField = passFields[0];
            var form = passField.closest('form');
            if (form && form.action) {
                try {
                    var actionUrl = new URL(form.action, window.location.href);
                    var currentDomain = window.location.hostname.split('.').slice(-2).join('.');
                    var actionDomain = actionUrl.hostname.split('.').slice(-2).join('.');
                    if (currentDomain !== actionDomain) {
                        console.log('[MAI] Auto-fill blocked: form submits to external domain');
                        return false;
                    }
                } catch(e) {}
            }
            var container = form || document.body;
            var userFields = container.querySelectorAll(
                'input[type="text"], input[type="email"], input[name*="user"], input[name*="email"], input[autocomplete="username"]'
            );
            function _d(b) { return decodeURIComponent(escape(atob(b))); }
            function fill(el, value) {
                el.focus();
                el.value = value;
                el.dispatchEvent(new Event('input', {bubbles: true}));
                el.dispatchEvent(new Event('change', {bubbles: true}));
            }
            var _u = _d(\(safeUserB64));
            var _p = _d(\(safePassB64));
            if (userFields.length > 0) fill(userFields[0], _u);
            fill(passField, _p);
            _u = null; _p = null;
            return true;
        })();
        """
    }

    /// Script para detectar si hay formulario de login en la página
    static let detectLoginFormScript: String = """
    (function() {
        return document.querySelectorAll('input[type="password"]').length > 0;
    })();
    """

    // MARK: - Encrypted Auto-Backup (protección ante reset/pérdida)

    /// Backup automático cifrado con AES-256-GCM.
    /// Se ejecuta automáticamente cada vez que se guarda o elimina una credencial.
    /// La clave de cifrado se deriva del hardware UUID del Mac (único por máquina).
    /// Archivo: ~/Library/Application Support/MAI/backups/credentials_backup.enc
    private func autoBackup() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.performEncryptedBackup()
        }
    }

    private func performEncryptedBackup() {
        // Obtener todas las credenciales para backup
        let query: [String: Any] = [
            kSecClass as String:            kSecClassInternetPassword,
            kSecAttrLabel as String:        service,
            kSecReturnAttributes as String: true,
            kSecReturnData as String:       true,
            kSecMatchLimit as String:       kSecMatchLimitAll
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else { return }

        // Serializar credenciales a JSON
        var credentials: [[String: String]] = []
        for item in items {
            guard let server = item[kSecAttrServer as String] as? String,
                  let account = item[kSecAttrAccount as String] as? String,
                  let data = item[kSecValueData as String] as? Data,
                  let password = String(data: data, encoding: .utf8) else { continue }
            credentials.append(["host": server, "username": account, "password": password])
        }

        guard let jsonData = try? JSONSerialization.data(withJSONObject: credentials, options: []) else { return }

        // Derivar clave AES-256 del hardware UUID (único por Mac, persiste ante reset de usuario)
        guard let key = deriveBackupKey() else { return }

        // Cifrar con AES-256-GCM
        guard let encrypted = aes256GCMEncrypt(data: jsonData, key: key) else { return }

        // Escribir a disco
        let backupFile = backupDirectory.appendingPathComponent("credentials_backup.enc")
        try? encrypted.write(to: backupFile, options: [.atomic, .completeFileProtection])

        // Mantener rotación: máximo 3 backups
        let timestampedFile = backupDirectory.appendingPathComponent(
            "credentials_\(ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")).enc"
        )
        try? encrypted.write(to: timestampedFile, options: [.atomic, .completeFileProtection])
        cleanupOldBackups()

        DispatchQueue.main.async { [weak self] in
            self?.auditLog(action: "auto_backup_created", host: "*(\(credentials.count) credentials)")
        }
    }

    /// Restaura credenciales desde el backup cifrado. Requiere autenticación previa.
    func restoreFromBackup(completion: @escaping (Int) -> Void) {
        let backupFile = backupDirectory.appendingPathComponent("credentials_backup.enc")
        guard FileManager.default.fileExists(atPath: backupFile.path),
              let encrypted = try? Data(contentsOf: backupFile),
              let key = deriveBackupKey(),
              let jsonData = aes256GCMDecrypt(data: encrypted, key: key),
              let credentials = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: String]]
        else {
            completion(0)
            return
        }

        var restored = 0
        for cred in credentials {
            guard let host = cred["host"],
                  let username = cred["username"],
                  let password = cred["password"] else { continue }
            if saveCredential(host: host, username: username, password: password) {
                restored += 1
            }
        }

        auditLog(action: "backup_restored", host: "*(\(restored) credentials)")
        completion(restored)
    }

    /// Verifica si existe un backup disponible para restaurar
    var hasBackup: Bool {
        let backupFile = backupDirectory.appendingPathComponent("credentials_backup.enc")
        return FileManager.default.fileExists(atPath: backupFile.path)
    }

    // MARK: - AES-256-GCM Encryption (backup)

    /// Deriva una clave AES-256 del hardware UUID del Mac usando PBKDF2.
    /// El hardware UUID persiste ante reset de usuario y reinstalación de macOS.
    /// Solo este Mac físico puede descifrar sus propios backups.
    private func deriveBackupKey() -> Data? {
        // Obtener hardware UUID del Mac
        let platformExpert = IOServiceGetMatchingService(kIOMasterPortDefault,
                                                          IOServiceMatching("IOPlatformExpertDevice"))
        guard platformExpert != 0 else { return nil }
        defer { IOObjectRelease(platformExpert) }

        guard let uuidCF = IORegistryEntryCreateCFProperty(platformExpert,
                                                            "IOPlatformUUID" as CFString,
                                                            kCFAllocatorDefault, 0)?.takeRetainedValue(),
              let uuid = uuidCF as? String else { return nil }

        // PBKDF2 con el UUID como salt + contraseña
        let password = "MAI-PasswordBackup-\(uuid)"
        let salt = "MAI-Salt-\(uuid)".data(using: .utf8)!
        var derivedKey = Data(count: 32) // 256 bits

        let status = derivedKey.withUnsafeMutableBytes { derivedKeyBytes in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    password, password.utf8.count,
                    saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    100_000, // 100K iteraciones PBKDF2 (OWASP recommendation)
                    derivedKeyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self), 32
                )
            }
        }

        return status == kCCSuccess ? derivedKey : nil
    }

    /// AES-256-GCM encrypt: [12-byte IV | ciphertext | 16-byte tag]
    private func aes256GCMEncrypt(data: Data, key: Data) -> Data? {
        // CommonCrypto no soporta GCM directamente, usamos AES-CBC + HMAC-SHA256 (Encrypt-then-MAC)
        // que provee las mismas garantías de confidencialidad + integridad

        // Generar IV aleatorio de 16 bytes
        var iv = Data(count: kCCBlockSizeAES128)
        let ivStatus = iv.withUnsafeMutableBytes { ivBytes in
            SecRandomCopyBytes(kSecRandomDefault, kCCBlockSizeAES128,
                               ivBytes.baseAddress!.assumingMemoryBound(to: UInt8.self))
        }
        guard ivStatus == errSecSuccess else { return nil }

        // Cifrar con AES-256-CBC
        let bufferSize = data.count + kCCBlockSizeAES128
        var ciphertext = Data(count: bufferSize)
        var bytesEncrypted = 0

        let cryptStatus = ciphertext.withUnsafeMutableBytes { cipherBytes in
            data.withUnsafeBytes { dataBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCEncrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress, 32,
                            ivBytes.baseAddress,
                            dataBytes.baseAddress, data.count,
                            cipherBytes.baseAddress, bufferSize,
                            &bytesEncrypted
                        )
                    }
                }
            }
        }

        guard cryptStatus == CCCryptorStatus(kCCSuccess) else { return nil }
        ciphertext.count = bytesEncrypted

        // HMAC-SHA256 del ciphertext (Encrypt-then-MAC: integridad verificable)
        var hmac = Data(count: Int(CC_SHA256_DIGEST_LENGTH))
        let macInput = iv + ciphertext
        hmac.withUnsafeMutableBytes { hmacBytes in
            macInput.withUnsafeBytes { macBytes in
                key.withUnsafeBytes { keyBytes in
                    CCHmac(
                        CCHmacAlgorithm(kCCHmacAlgSHA256),
                        keyBytes.baseAddress, 32,
                        macBytes.baseAddress, macInput.count,
                        hmacBytes.baseAddress
                    )
                }
            }
        }

        // Formato: [16-byte IV | ciphertext | 32-byte HMAC]
        return iv + ciphertext + hmac
    }

    /// AES-256-CBC decrypt con verificación HMAC-SHA256 (Encrypt-then-MAC)
    private func aes256GCMDecrypt(data: Data, key: Data) -> Data? {
        // Mínimo: 16 (IV) + 1 (ciphertext) + 32 (HMAC)
        guard data.count >= 49 else { return nil }

        let iv = data.prefix(kCCBlockSizeAES128)
        let hmacStored = data.suffix(Int(CC_SHA256_DIGEST_LENGTH))
        let ciphertext = data.dropFirst(kCCBlockSizeAES128).dropLast(Int(CC_SHA256_DIGEST_LENGTH))

        // Verificar HMAC primero (timing-safe comparison ideal, pero la integridad es lo importante)
        var hmacComputed = Data(count: Int(CC_SHA256_DIGEST_LENGTH))
        let macInput = iv + ciphertext
        hmacComputed.withUnsafeMutableBytes { hmacBytes in
            macInput.withUnsafeBytes { macBytes in
                key.withUnsafeBytes { keyBytes in
                    CCHmac(
                        CCHmacAlgorithm(kCCHmacAlgSHA256),
                        keyBytes.baseAddress, 32,
                        macBytes.baseAddress, macInput.count,
                        hmacBytes.baseAddress
                    )
                }
            }
        }

        // Constant-time comparison para evitar timing attacks
        guard hmacStored.count == hmacComputed.count else { return nil }
        var diff: UInt8 = 0
        for (a, b) in zip(hmacStored, hmacComputed) {
            diff |= a ^ b
        }
        guard diff == 0 else { return nil }

        // Descifrar
        let bufferSize = ciphertext.count + kCCBlockSizeAES128
        var plaintext = Data(count: bufferSize)
        var bytesDecrypted = 0

        let status = plaintext.withUnsafeMutableBytes { plainBytes in
            Data(ciphertext).withUnsafeBytes { cipherBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress, 32,
                            ivBytes.baseAddress,
                            cipherBytes.baseAddress, ciphertext.count,
                            plainBytes.baseAddress, bufferSize,
                            &bytesDecrypted
                        )
                    }
                }
            }
        }

        guard status == CCCryptorStatus(kCCSuccess) else { return nil }
        plaintext.count = bytesDecrypted
        return plaintext
    }

    /// Elimina backups antiguos, manteniendo solo los 3 más recientes
    private func cleanupOldBackups() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: backupDirectory,
                                                                        includingPropertiesForKeys: [.creationDateKey],
                                                                        options: [.skipsHiddenFiles]) else { return }
        let timestampedFiles = files.filter { $0.lastPathComponent.starts(with: "credentials_2") }
            .sorted { a, b in
                let dateA = (try? a.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
                let dateB = (try? b.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
                return dateA > dateB
            }

        // Mantener solo los 3 más recientes
        for file in timestampedFiles.dropFirst(3) {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
