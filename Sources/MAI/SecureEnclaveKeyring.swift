import Foundation
import CryptoKit
import Security

/// Wraps the render pipeline's base seed using a Secure Enclave-backed P256
/// ECDH key + Keychain storage. First launch wraps and stores; subsequent
/// launches retrieve and unwrap via SE. Falls back silently to the raw seed
/// if SE is unavailable or any step fails — decryption never breaks.
///
/// Blob layout: [2B seLen][sePrivateKey.dataRepresentation][2B ephLen][ephPub.rawRepresentation][AES-GCM sealed.combined]
final class SecureEnclaveKeyring {
    static let shared = SecureEnclaveKeyring()
    private init() {}

    private let service = "com.mai.browser.render"
    private let account = "wk.seed.v1"
    private let hkdfInfo = Data("mai.seed.wrap.v1".utf8)

    /// Returns the unwrapped seed. On first call (no Keychain entry), wraps
    /// `freshSeed()` into SE and stores it. Returns nil if SE unavailable or
    /// any step fails — caller should fall back to the raw seed.
    @inline(never)
    func getOrWrapSeed(freshSeed: () -> Data) -> Data? {
        if let unwrapped = _readAndUnwrap() { return unwrapped }
        let seed = freshSeed()
        return _wrapAndStore(seed: seed) ? seed : nil
    }

    @inline(never)
    private func _readAndUnwrap() -> Data? {
        guard let blob = _loadKeychainBlob(), blob.count >= 4 else { return nil }

        var offset = 0
        let seLen = Int(_readU16BE(blob, offset: offset))
        offset += 2
        guard blob.count >= offset + seLen + 2 else { return nil }
        let seData = blob.subdata(in: offset..<offset + seLen)
        offset += seLen

        let ephLen = Int(_readU16BE(blob, offset: offset))
        offset += 2
        guard blob.count >= offset + ephLen else { return nil }
        let ephPubData = blob.subdata(in: offset..<offset + ephLen)
        offset += ephLen

        guard blob.count > offset else { return nil }
        let sealedData = blob.subdata(in: offset..<blob.count)

        guard let sePrivate = try? SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: seData),
              let ephPublic = try? P256.KeyAgreement.PublicKey(rawRepresentation: ephPubData),
              let sharedSecret = try? sePrivate.sharedSecretFromKeyAgreement(with: ephPublic) else {
            return nil
        }

        let wrapKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(),
            sharedInfo: hkdfInfo,
            outputByteCount: 32
        )

        guard let sealedBox = try? AES.GCM.SealedBox(combined: sealedData),
              let unsealed = try? AES.GCM.open(sealedBox, using: wrapKey) else {
            return nil
        }

        return unsealed
    }

    @inline(never)
    private func _wrapAndStore(seed: Data) -> Bool {
        guard SecureEnclave.isAvailable else { return false }

        guard let sePrivate = try? SecureEnclave.P256.KeyAgreement.PrivateKey() else { return false }

        let ephemeral = P256.KeyAgreement.PrivateKey()
        let ephPublic = ephemeral.publicKey

        guard let sharedSecret = try? sePrivate.sharedSecretFromKeyAgreement(with: ephPublic) else { return false }

        let wrapKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(),
            sharedInfo: hkdfInfo,
            outputByteCount: 32
        )

        guard let sealed = try? AES.GCM.seal(seed, using: wrapKey),
              let sealedCombined = sealed.combined else {
            return false
        }

        let seData = sePrivate.dataRepresentation
        let ephPubData = ephPublic.rawRepresentation

        var blob = Data()
        blob.append(_writeU16BE(UInt16(seData.count)))
        blob.append(seData)
        blob.append(_writeU16BE(UInt16(ephPubData.count)))
        blob.append(ephPubData)
        blob.append(sealedCombined)

        return _saveKeychainBlob(blob)
    }

    // MARK: - Keychain

    private func _loadKeychainBlob() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    private func _saveKeychainBlob(_ data: Data) -> Bool {
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        return status == errSecSuccess
    }

    // MARK: - Binary helpers

    @inline(__always)
    private func _readU16BE(_ data: Data, offset: Int) -> UInt16 {
        return (UInt16(data[data.startIndex + offset]) << 8) | UInt16(data[data.startIndex + offset + 1])
    }

    @inline(__always)
    private func _writeU16BE(_ value: UInt16) -> Data {
        return Data([UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)])
    }
}
