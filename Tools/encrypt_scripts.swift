#!/usr/bin/env swift
/// Herramienta de build: cifra scripts JS (fragmentados) y genera código Swift.
/// Cada script se divide en N fragmentos, cada uno cifrado con salt diferente.
/// Uso: swift Tools/encrypt_scripts.swift
/// Output: genera EncryptedScripts.swift con fragmentos cifrados + orden shuffled

import Foundation
import CommonCrypto

// MARK: - Key derivation (DEBE ser idéntica a ScriptProtection.swift)

let renderConfig: UInt64  = 0x2620_A4A1_3937_BBBA &+ 0x2720_A4A1_3937_BBB9
let layoutEngine: UInt64  = 0x32B9_2839_37BA_32B2 &+ 0x32B9_2839_37BA_32B1
let sessionToken: UInt64  = 0x3A34_B7B7_25B2_BC99 &+ 0x3A34_B7B7_25B2_BC99
let frameVersion: UInt64  = 0x1819_1B20_A2A9_991B &+ 0x1819_1B20_A2A9_991A

func deriveKey(salt: String) -> Data {
    var seed = Data()
    withUnsafeBytes(of: renderConfig.bigEndian) { seed.append(contentsOf: $0) }
    withUnsafeBytes(of: layoutEngine.bigEndian) { seed.append(contentsOf: $0) }
    withUnsafeBytes(of: sessionToken.bigEndian) { seed.append(contentsOf: $0) }
    withUnsafeBytes(of: frameVersion.bigEndian) { seed.append(contentsOf: $0) }

    let saltData = salt.data(using: .utf8)!

    var derivedKey = Data(count: 32)
    let _ = derivedKey.withUnsafeMutableBytes { keyPtr in
        saltData.withUnsafeBytes { saltPtr in
            seed.withUnsafeBytes { seedPtr in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    seedPtr.baseAddress?.assumingMemoryBound(to: Int8.self),
                    seed.count,
                    saltPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                    saltData.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    50_000,
                    keyPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                    32
                )
            }
        }
    }
    return derivedKey
}

func encrypt(plaintext: String, salt: String) -> Data {
    let key = deriveKey(salt: salt)
    let plaintextData = plaintext.data(using: .utf8)!

    var iv = Data(count: 16)
    iv.withUnsafeMutableBytes { ptr in
        _ = SecRandomCopyBytes(kSecRandomDefault, 16, ptr.baseAddress!)
    }

    let ctSize = plaintextData.count + 16
    var ciphertext = Data(count: ctSize)
    var encryptedCount = 0

    let _ = ciphertext.withUnsafeMutableBytes { ctPtr in
        plaintextData.withUnsafeBytes { ptPtr in
            iv.withUnsafeBytes { ivPtr in
                key.withUnsafeBytes { keyPtr in
                    CCCrypt(
                        CCOperation(kCCEncrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionPKCS7Padding),
                        keyPtr.baseAddress, 32,
                        ivPtr.baseAddress,
                        ptPtr.baseAddress, plaintextData.count,
                        ctPtr.baseAddress, ctSize,
                        &encryptedCount
                    )
                }
            }
        }
    }
    ciphertext.count = encryptedCount

    let macInput = iv + ciphertext
    var hmac = Data(count: Int(CC_SHA256_DIGEST_LENGTH))
    let _ = hmac.withUnsafeMutableBytes { hmacPtr in
        macInput.withUnsafeBytes { macPtr in
            key.withUnsafeBytes { keyPtr in
                CCHmac(
                    CCHmacAlgorithm(kCCHmacAlgSHA256),
                    keyPtr.baseAddress, 32,
                    macPtr.baseAddress, macInput.count,
                    hmacPtr.baseAddress
                )
            }
        }
    }

    return iv + ciphertext + hmac
}

func generateSwiftLiteral(data: Data, name: String) -> String {
    let bytes = data.map { String($0) }
    let chunkSize = 20
    var lines: [String] = []
    lines.append("    static let \(name): Data = Data([")
    for i in stride(from: 0, to: bytes.count, by: chunkSize) {
        let end = min(i + chunkSize, bytes.count)
        let chunk = bytes[i..<end].joined(separator: ", ")
        let suffix = end < bytes.count ? "," : ""
        lines.append("        \(chunk)\(suffix)")
    }
    lines.append("    ])")
    return lines.joined(separator: "\n")
}

// MARK: - Fragment a script into N pieces with shuffled order

let FRAGMENT_COUNT = 8

func sha256(data: Data) -> Data {
    var hash = Data(count: Int(CC_SHA256_DIGEST_LENGTH))
    _ = hash.withUnsafeMutableBytes { hashPtr in
        data.withUnsafeBytes { dataPtr in
            CC_SHA256(dataPtr.baseAddress, CC_LONG(data.count), hashPtr.baseAddress?.assumingMemoryBound(to: UInt8.self))
        }
    }
    return hash
}

func fragmentAndEncrypt(js: String, baseName: String) -> (fragments: String, orderArray: String, saltArray: String, hashLiteral: String) {
    let chars = Array(js)
    let chunkSize = (chars.count + FRAGMENT_COUNT - 1) / FRAGMENT_COUNT
    var fragments: [String] = []

    for i in 0 ..< FRAGMENT_COUNT {
        let start = i * chunkSize
        let end = min(start + chunkSize, chars.count)
        if start < chars.count {
            fragments.append(String(chars[start..<end]))
        } else {
            fragments.append("")
        }
    }

    // Generar orden shuffled: [0,1,2,...,N-1] → shuffle
    var order = Array(0 ..< fragments.count)
    for i in stride(from: order.count - 1, through: 1, by: -1) {
        let j = Int.random(in: 0...i)
        order.swapAt(i, j)
    }

    // Cifrar cada fragmento con un salt diferente derivado de su índice shuffled
    var swiftCode = ""
    var salts: [String] = []
    for shuffledIdx in 0 ..< order.count {
        let originalIdx = order[shuffledIdx]
        let salt = "\(UUID().uuidString.prefix(8)).r\(shuffledIdx).\(UUID().uuidString.suffix(4))"
        salts.append(salt)
        let encrypted = encrypt(plaintext: fragments[originalIdx], salt: salt)
        let literal = generateSwiftLiteral(data: encrypted, name: "\(baseName)_f\(shuffledIdx)")
        swiftCode += "\(literal)\n\n"
    }

    // Generar el array de orden para re-ensamblar
    // order[shuffledIdx] = originalIdx → necesitamos el inverso:
    // reassembly[originalIdx] = shuffledIdx
    var reassembly = Array(repeating: 0, count: order.count)
    for shuffledIdx in 0 ..< order.count {
        reassembly[order[shuffledIdx]] = shuffledIdx
    }

    let orderStr = "    static let \(baseName)_order: [Int] = [\(reassembly.map { String($0) }.joined(separator: ", "))]"
    let saltStr = "    static let \(baseName)_salts: [String] = [\(salts.map { "\"\($0)\"" }.joined(separator: ", "))]"

    // Capa 9d: SHA-256 del script original (pre-fragmentación) para verificación post-ensamblado
    let scriptData = js.data(using: .utf8)!
    let hash = sha256(data: scriptData)
    let hashLiteral = generateSwiftLiteral(data: hash, name: "\(baseName)_hash")

    return (swiftCode, orderStr, saltStr, hashLiteral)
}

// MARK: - Read scripts

let obfuscatedDir = "Tools/scripts_obfuscated"
let scriptsDir = FileManager.default.fileExists(atPath: obfuscatedDir) ? obfuscatedDir : "Tools/scripts"
let outputFile = "Sources/MAI/EncryptedScripts.swift"

let fm = FileManager.default
if !fm.fileExists(atPath: scriptsDir) {
    print("❌ Directorio \(scriptsDir) no existe.")
    exit(1)
}

let contents = try fm.contentsOfDirectory(atPath: scriptsDir)
    .filter { $0.hasSuffix(".js") }
    .sorted()

if contents.isEmpty {
    print("❌ No hay archivos .js en \(scriptsDir)")
    exit(1)
}

var output = """
/// Auto-generated by Tools/encrypt_scripts.swift
/// NO EDITAR MANUALMENTE — regenerar con: make encrypt-scripts
/// Scripts fragmentados en \(FRAGMENT_COUNT) partes, cada una cifrada con salt diferente.
/// El orden de fragmentos está shuffled — se re-ensambla en runtime.
import Foundation

struct EncryptedScripts {

"""

for file in contents {
    let path = "\(scriptsDir)/\(file)"
    let js = try String(contentsOfFile: path, encoding: .utf8)
    let varName = file.replacingOccurrences(of: ".js", with: "")
        .replacingOccurrences(of: "-", with: "_")
        .replacingOccurrences(of: ".", with: "_")

    let result = fragmentAndEncrypt(js: js, baseName: varName)
    output += "    // --- \(varName): \(FRAGMENT_COUNT) fragments (shuffled) + integrity hash ---\n\n"
    output += result.fragments
    output += "\(result.orderArray)\n\n"
    output += "\(result.saltArray)\n\n"
    output += "\(result.hashLiteral)\n\n"

    let totalBytes = js.count
    print("✅ \(file) → \(varName) (\(totalBytes) chars → \(FRAGMENT_COUNT) fragments cifrados)")
}

output += "}\n"

try output.write(toFile: outputFile, atomically: true, encoding: .utf8)
print("\n📦 Generado: \(outputFile)")
print("   Fragmentos shuffled — hookear CCCrypt solo captura 1/\(FRAGMENT_COUNT) del script")
