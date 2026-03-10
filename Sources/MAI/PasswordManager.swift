import Foundation
import Security
import WebKit

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
class PasswordManager: ObservableObject {
    static let shared = PasswordManager()
    private let service = "com.mai.browser.passwords"

    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "passwordManagerEnabled") }
    }

    @Published var savedCount: Int = 0

    private init() {
        self.isEnabled = UserDefaults.standard.object(forKey: "passwordManagerEnabled") as? Bool ?? true
        refreshCount()
    }

    // MARK: - Keychain CRUD

    func saveCredential(host: String, username: String, password: String) -> Bool {
        guard let passwordData = password.data(using: .utf8) else { return false }

        // Eliminar existente primero (patrón update)
        deleteCredential(host: host, username: username)

        let query: [String: Any] = [
            kSecClass as String:            kSecClassInternetPassword,
            kSecAttrServer as String:       host,
            kSecAttrAccount as String:      username,
            kSecAttrLabel as String:        service,
            kSecValueData as String:        passwordData,
            kSecAttrAccessible as String:   kSecAttrAccessibleWhenUnlocked
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecSuccess {
            refreshCount()
            print("🔑 Contraseña guardada para \(host)")
        }
        return status == errSecSuccess
    }

    func getCredentials(for host: String) -> [SavedCredential] {
        let query: [String: Any] = [
            kSecClass as String:            kSecClassInternetPassword,
            kSecAttrServer as String:       host,
            kSecAttrLabel as String:        service,
            kSecReturnAttributes as String: true,
            kSecReturnData as String:       true,
            kSecMatchLimit as String:       kSecMatchLimitAll
        ]

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

    func getAllCredentials() -> [SavedCredential] {
        let query: [String: Any] = [
            kSecClass as String:            kSecClassInternetPassword,
            kSecAttrLabel as String:        service,
            kSecReturnAttributes as String: true,
            kSecReturnData as String:       true,
            kSecMatchLimit as String:       kSecMatchLimitAll
        ]

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
        if ok { refreshCount() }
        return ok
    }

    func deleteAllCredentials() {
        let query: [String: Any] = [
            kSecClass as String:    kSecClassInternetPassword,
            kSecAttrLabel as String: service
        ]
        SecItemDelete(query as CFDictionary)
        refreshCount()
        print("🔑 Todas las contraseñas eliminadas")
    }

    private func refreshCount() {
        savedCount = getAllCredentials().count
    }

    // MARK: - JavaScript

    /// Script para capturar credenciales al enviar formulario
    static let captureScript: String = """
    (function() {
        if (window._maiPasswordCapture) return;
        window._maiPasswordCapture = true;

        function captureCredentials(passField) {
            var form = passField.closest('form');
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
                    host: window.location.hostname,
                    username: username,
                    password: password
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

    /// Script para auto-rellenar credenciales
    static func autoFillScript(username: String, password: String) -> String {
        let escapedUser = username.replacingOccurrences(of: "'", with: "\\'").replacingOccurrences(of: "\\", with: "\\\\")
        let escapedPass = password.replacingOccurrences(of: "'", with: "\\'").replacingOccurrences(of: "\\", with: "\\\\")
        return """
        (function() {
            var passFields = document.querySelectorAll('input[type="password"]');
            if (passFields.length === 0) return false;
            var passField = passFields[0];
            var form = passField.closest('form') || document.body;
            var userFields = form.querySelectorAll(
                'input[type="text"], input[type="email"], input[name*="user"], input[name*="email"], input[autocomplete="username"]'
            );
            function fill(el, value) {
                el.focus();
                el.value = value;
                el.dispatchEvent(new Event('input', {bubbles: true}));
                el.dispatchEvent(new Event('change', {bubbles: true}));
            }
            if (userFields.length > 0) fill(userFields[0], '\(escapedUser)');
            fill(passField, '\(escapedPass)');
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
}
