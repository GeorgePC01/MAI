import Foundation
import SecureMem

/// String seguro respaldado por mlock — la memoria nunca se escribe a disco (swap).
/// Uso: para passwords bancarios y credenciales sensibles durante auto-fill.
///
/// Ciclo de vida:
///   1. `SecureString("password")` → alloc + mlock + copy
///   2. `.utf8String` → acceso de lectura
///   3. `.clear()` o deinit → memset_s + munlock + free
///
/// La memoria está protegida contra:
///   - Swap a disco (mlock)
///   - Optimización del compilador al borrar (memset_s)
///   - Persistencia en memoria después de uso (zero-fill en deinit)
final class SecureString {
    private var buffer: UnsafeMutablePointer<SecureBuffer>?

    /// Crea un SecureString desde un String estándar de Swift.
    /// El String original sigue existiendo en el heap de Swift (ARC),
    /// pero este SecureString garantiza una copia protegida para operaciones sensibles.
    init(_ string: String) {
        let utf8 = Array(string.utf8)
        buffer = secure_buffer_create(utf8.count + 1) // +1 for null terminator
        if let buf = buffer {
            utf8.withUnsafeBufferPointer { ptr in
                if let base = ptr.baseAddress {
                    secure_buffer_write(buf, base, utf8.count)
                }
            }
        }
    }

    /// Accede al contenido como String (copia temporal — usar y descartar rápido)
    var utf8String: String? {
        guard let buf = buffer,
              let data = secure_buffer_data(buf) else { return nil }
        let length = secure_buffer_length(buf)
        return String(bytes: UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self),
                                                  count: length),
                      encoding: .utf8)
    }

    /// Longitud del contenido en bytes
    var length: Int {
        guard let buf = buffer else { return 0 }
        return secure_buffer_length(buf)
    }

    /// Zero-fill manual sin liberar (reusar buffer)
    func clear() {
        guard let buf = buffer else { return }
        secure_buffer_zero(buf)
    }

    deinit {
        if buffer != nil {
            secure_buffer_free(&buffer)
        }
    }
}
