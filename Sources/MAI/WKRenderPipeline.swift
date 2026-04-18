import Foundation
import CommonCrypto
import ObjectiveC
import MachO

final class WKRenderPipeline {
    static let shared = WKRenderPipeline()

    private var _cache: [String: String] = [:]
    private let lock = NSLock()

    private var _safeEnvironment: Bool
    private var _integrityValid: Bool
    private var _hooksClean: Bool
    private var _sipDisabled: Bool
    private var _watchdogTimer: DispatchSourceTimer?

    private var _consecutiveFailures: Int = 0
    private let _failureThreshold: Int = 2

    // MARK: - Decoy state (analyzed but unused — wastes Kong's LLM context)
    private var _auxVerified: Bool = false
    private var _rotationEpoch: UInt32 = 0
    private var _auxCache: [String: Data] = [:]

    @_silgen_name("ptrace")
    private static func _ptrace(_ request: CInt, _ pid: pid_t, _ addr: UnsafeMutableRawPointer?, _ data: CInt) -> CInt

    @inline(never)
    private static func _denyDebuggerAttach() {
        let _: CInt = _ptrace(31, 0, nil, 0)
    }

    @inline(never)
    private static func _checkExceptionPorts() -> Bool {
        let EXC_TYPES_MAX = 14
        var maskCount = mach_msg_type_number_t(EXC_TYPES_MAX)
        var masks = [exception_mask_t](repeating: 0, count: EXC_TYPES_MAX)
        var ports = [mach_port_t](repeating: 0, count: EXC_TYPES_MAX)
        var behaviors = [exception_behavior_t](repeating: 0, count: EXC_TYPES_MAX)
        var flavors = [thread_state_flavor_t](repeating: 0, count: EXC_TYPES_MAX)

        let kr = masks.withUnsafeMutableBufferPointer { masksPtr in
            ports.withUnsafeMutableBufferPointer { portsPtr in
                behaviors.withUnsafeMutableBufferPointer { behaviorsPtr in
                    flavors.withUnsafeMutableBufferPointer { flavorsPtr in
                        task_get_exception_ports(
                            mach_task_self_,
                            exception_mask_t(0x3FFE),
                            masksPtr.baseAddress!,
                            &maskCount,
                            portsPtr.baseAddress!,
                            behaviorsPtr.baseAddress!,
                            flavorsPtr.baseAddress!
                        )
                    }
                }
            }
        }

        if kr == KERN_SUCCESS {
            for i in 0 ..< Int(maskCount) {
                if ports[i] != 0 && ports[i] != mach_port_t(MACH_PORT_NULL) {
                    let behavior = behaviors[i]
                    let rawBehavior = behavior & 0x7FFFFFFF
                    if rawBehavior == 1 {
                        return true
                    }
                }
            }
        }
        return false
    }

    // Key split: actual key = _ka[i] ^ _kb[i]. Neither array alone reveals the key.
    // @_used: prevent -dead_strip from eliminating these arrays under Release build
    // (referenced only inside @inline(never) _deobf, no direct Swift references).
    @_used private static let _ka: [UInt8] = [0x3E, 0x5D, 0x8F, 0xC2, 0x47, 0xAB, 0x19, 0x76]
    @_used private static let _kb: [UInt8] = [0x71, 0x28, 0xE4, 0x56, 0xB3, 0xCF, 0x5A, 0xF1]

    @inline(never)
    private static func _deobf(_ encoded: [UInt8]) -> String {
        return String(encoded.enumerated().map { (i, b) in
            let ki = i % 8
            return Character(UnicodeScalar(b ^ (_ka[ki] ^ _kb[ki])))
        })
    }

    private static let _s_frida: [UInt8] = [0x29, 0x07, 0x02, 0xF0, 0x95]
    private static let _s_cycript: [UInt8] = [0x2C, 0x0C, 0x08, 0xE6, 0x9D, 0x14, 0x37]
    private static let _s_substrate: [UInt8] = [0x3C, 0x00, 0x09, 0xE7, 0x80, 0x16, 0x22, 0xF3, 0x2A]
    private static let _s_substitute: [UInt8] = [0x3C, 0x00, 0x09, 0xE7, 0x80, 0x0D, 0x37, 0xF2, 0x3B, 0x10]
    private static let _s_libhooker: [UInt8] = [0x23, 0x1C, 0x09, 0xFC, 0x9B, 0x0B, 0x28, 0xE2, 0x3D]
    private static let _s_ellekit: [UInt8] = [0x2A, 0x19, 0x07, 0xF1, 0x9F, 0x0D, 0x37]
    private static let _s_mobileloader: [UInt8] = [0x22, 0x1A, 0x09, 0xFD, 0x98, 0x01, 0x2F, 0xE8, 0x2E, 0x11, 0x0E, 0xE6]
    private static let _s_sslkillswitch: [UInt8] = [0x3C, 0x06, 0x07, 0xFF, 0x9D, 0x08, 0x2F, 0xF4, 0x38, 0x1C, 0x1F, 0xF7, 0x9C]
    private static let _s_flexloader: [UInt8] = [0x29, 0x19, 0x0E, 0xEC, 0x98, 0x0B, 0x22, 0xE3, 0x2A, 0x07]
    private static let _s_flexdylib: [UInt8] = [0x29, 0x19, 0x0E, 0xEC, 0x90, 0x1D, 0x2F, 0xEE, 0x2D]
    private static let _s_revealdylib: [UInt8] = [0x3D, 0x10, 0x1D, 0xF1, 0x95, 0x08, 0x27, 0xFE, 0x23, 0x1C, 0x09]
    private static let _s_introspy: [UInt8] = [0x26, 0x1B, 0x1F, 0xE6, 0x9B, 0x17, 0x33, 0xFE]
    private static let _s_libcommonCrypto: [UInt8] = [0x23, 0x1C, 0x09, 0xF7, 0x9B, 0x09, 0x2E, 0xE8, 0x21, 0x36, 0x19, 0xED, 0x84, 0x10, 0x2C]
    private static let _s_Security: [UInt8] = [0x1C, 0x10, 0x08, 0xE1, 0x86, 0x0D, 0x37, 0xFE]
    private static let _s_WebKit: [UInt8] = [0x18, 0x10, 0x09, 0xDF, 0x9D, 0x10]
    private static let _s_CCCrypt: [UInt8] = [0x0C, 0x36, 0x28, 0xE6, 0x8D, 0x14, 0x37]
    private static let _s_env_dyld_insert: [UInt8] = [0x0B, 0x2C, 0x27, 0xD0, 0xAB, 0x2D, 0x0D, 0xD4, 0x0A, 0x27, 0x3F, 0xCB, 0xB8, 0x2D, 0x01, 0xD5, 0x0E, 0x27, 0x22, 0xD1, 0xA7]
    private static let _s_env_malloc: [UInt8] = [0x02, 0x14, 0x07, 0xF8, 0x9B, 0x07, 0x10, 0xF3, 0x2E, 0x16, 0x00, 0xD8, 0x9B, 0x03, 0x24, 0xEE, 0x21, 0x12]
    private static let _s_env_mssafe: [UInt8] = [0x10, 0x38, 0x38, 0xC7, 0x95, 0x02, 0x26, 0xCA, 0x20, 0x11, 0x0E]
    private static let _s_env_dyld_lib: [UInt8] = [0x0B, 0x2C, 0x27, 0xD0, 0xAB, 0x28, 0x0A, 0xC5, 0x1D, 0x34, 0x39, 0xCD, 0xAB, 0x34, 0x02, 0xD3, 0x07]
    private static let _s_env_dyld_fw: [UInt8] = [0x0B, 0x2C, 0x27, 0xD0, 0xAB, 0x22, 0x11, 0xC6, 0x02, 0x30, 0x3C, 0xDB, 0xA6, 0x2F, 0x1C, 0xD7, 0x0E, 0x21, 0x23]

    // MARK: - Decoy encoded arrays (Kong wastes time analyzing these)
    private static let _s_aux_token: [UInt8] = [0x3A, 0x15, 0x1E, 0xFF, 0x8C, 0x04, 0x27, 0xF1, 0x31]
    private static let _s_aux_session: [UInt8] = [0x1C, 0x10, 0x16, 0xE7, 0x9D, 0x0B, 0x2A, 0xC7, 0x30, 0x02]
    private static let _s_aux_channel: [UInt8] = [0x2C, 0x1D, 0x08, 0xF5, 0x9B, 0x01, 0x2F, 0xDE, 0x23, 0x07]

    private init() {
        _safeEnvironment = true
        _integrityValid = true
        _hooksClean = true
        _sipDisabled = false

        _sipDisabled = WKRenderPipeline._isSIPDisabled()

        #if !DEBUG
        WKRenderPipeline._denyDebuggerAttach()
        #endif

        WKRenderPipeline._installCrashLogger()

        _safeEnvironment = !WKRenderPipeline._checkInstrumentation()
        _integrityValid = WKRenderPipeline._verifyCodeSignature()
        _hooksClean = WKRenderPipeline._verifyNoHooks()

        // Decoy init (never affects real flow)
        _auxVerified = _integrityValid
        _rotationEpoch = UInt32(Date().timeIntervalSince1970) & 0xFFFF

        _startWatchdog()
    }

    private func _startWatchdog() {
        let queue = DispatchQueue(label: "com.mai.sp.wd", qos: .utility)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        let baseInterval = 8.0
        let jitter = Double.random(in: 0...7)
        timer.schedule(deadline: .now() + baseInterval + jitter, repeating: baseInterval + jitter)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }

            if !WKRenderPipeline._verifyCodeSignature() {
                self.lock.lock()
                self._integrityValid = false
                self._cache.removeAll()
                self.lock.unlock()
                return
            }
            if !WKRenderPipeline._verifyNoHooks() {
                self.lock.lock()
                self._hooksClean = false
                self._cache.removeAll()
                self.lock.unlock()
                return
            }

            let instrumentDetected = WKRenderPipeline._checkInstrumentation()
            let exceptionPortDetected = WKRenderPipeline._checkExceptionPorts()

            self.lock.lock()
            if instrumentDetected || exceptionPortDetected {
                self._consecutiveFailures += 1
                if self._consecutiveFailures >= self._failureThreshold {
                    self._safeEnvironment = false
                    self._cache.removeAll()
                }
            } else {
                self._consecutiveFailures = 0
                if self._integrityValid && self._hooksClean {
                    self._safeEnvironment = true
                }
            }
            // Decoy: update rotation state (no effect on real logic)
            self._rotationEpoch = self._rotationEpoch &+ 1
            self._auxVerified = self._integrityValid && self._hooksClean
            self.lock.unlock()
        }
        timer.resume()
        _watchdogTimer = timer
    }

    @inline(never)
    private static func _verifyNoHooks() -> Bool {
        let ccName = _deobf(_s_CCCrypt)
        let libCC = _deobf(_s_libcommonCrypto)
        let secFw = _deobf(_s_Security)
        let wkFw = _deobf(_s_WebKit)

        let ccCryptPtr = dlsym(dlopen(nil, RTLD_NOW), ccName)
        if let ptr = ccCryptPtr {
            var info = Dl_info()
            if dladdr(ptr, &info) != 0 {
                if let fname = info.dli_fname {
                    let path = String(cString: fname)
                    if !path.contains(libCC) && !path.contains(secFw) {
                        return false
                    }
                }
            } else {
                return false
            }
        }

        if let wkClass = NSClassFromString("WK" + "UserScript") {
            let selector = NSSelectorFromString("initWithSource:injectionTime:forMainFrameOnly:")
            if let method = class_getInstanceMethod(wkClass, selector) {
                let imp = method_getImplementation(method)
                var info = Dl_info()
                if dladdr(unsafeBitCast(imp, to: UnsafeRawPointer.self), &info) != 0 {
                    if let fname = info.dli_fname {
                        let path = String(cString: fname)
                        if !path.contains(wkFw) {
                            return false
                        }
                    }
                }
            }
        }

        if let wkcClass = NSClassFromString("WK" + "UserContentController") {
            let selector = NSSelectorFromString("addUserScript:")
            if let method = class_getInstanceMethod(wkcClass, selector) {
                let imp = method_getImplementation(method)
                var info = Dl_info()
                if dladdr(unsafeBitCast(imp, to: UnsafeRawPointer.self), &info) != 0 {
                    if let fname = info.dli_fname {
                        let path = String(cString: fname)
                        if !path.contains(wkFw) {
                            return false
                        }
                    }
                }
            }
        }

        return true
    }

    @inline(never)
    private static func _checkInstrumentation() -> Bool {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        let r = sysctl(&mib, 4, &info, &size, nil, 0)
        if r == 0 && (info.kp_proc.p_flag & P_TRACED) != 0 {
            return true
        }

        let imageCount = _dyld_image_count()
        let dangerousLibs = [
            _deobf(_s_frida), _deobf(_s_cycript), _deobf(_s_substrate),
            _deobf(_s_substitute), _deobf(_s_libhooker), _deobf(_s_ellekit),
            _deobf(_s_mobileloader), _deobf(_s_sslkillswitch),
            _deobf(_s_flexloader), _deobf(_s_flexdylib),
            _deobf(_s_revealdylib), _deobf(_s_introspy)
        ]
        for i: UInt32 in 0 ..< imageCount {
            if let name = _dyld_get_image_name(i) {
                let s = String(cString: name).lowercased()
                for lib in dangerousLibs {
                    if s.contains(lib) { return true }
                }
            }
        }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        let _fp: UInt16 = 13521 &* 2
        addr.sin_port = CFSwapInt16HostToBig(_fp)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        if sock >= 0 {
            var flags = fcntl(sock, F_GETFL, 0)
            flags |= O_NONBLOCK
            fcntl(sock, F_SETFL, flags)
            let result = withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    connect(sock, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            if result == 0 {
                close(sock)
                return true
            }
            var pollFd = pollfd(fd: sock, events: Int16(POLLOUT), revents: 0)
            let pollResult = poll(&pollFd, 1, 50)
            if pollResult > 0 && (pollFd.revents & Int16(POLLOUT)) != 0 {
                var errVal: Int32 = 0
                var errLen = socklen_t(MemoryLayout<Int32>.size)
                getsockopt(sock, SOL_SOCKET, SO_ERROR, &errVal, &errLen)
                if errVal == 0 {
                    close(sock)
                    return true
                }
            }
            close(sock)
        }

        let envChecks = [
            _deobf(_s_env_dyld_insert),
            _deobf(_s_env_malloc),
            _deobf(_s_env_mssafe),
            _deobf(_s_env_dyld_lib),
            _deobf(_s_env_dyld_fw)
        ]
        for env in envChecks {
            if getenv(env) != nil { return true }
        }

        return false
    }

    @inline(never)
    private static func _isSIPDisabled() -> Bool {
        let fm = FileManager.default
        return fm.isWritableFile(atPath: "/System/Library/Extensions")
    }

    private static func _installCrashLogger() {
        let signals: [Int32] = [SIGABRT, SIGSEGV, SIGBUS, SIGFPE, SIGILL, SIGTRAP]
        for sig in signals {
            signal(sig) { sigNum in
                let timestamp = Int(Date().timeIntervalSince1970)
                let logDir = NSHomeDirectory() + "/Library/Logs/MAI"
                mkdir(logDir, 0o755)
                let path = "\(logDir)/crash_\(timestamp).log"

                var info = ""
                info += "MAI Crash Report\n"
                info += "Signal: \(sigNum)\n"
                info += "Time: \(timestamp)\n"
                info += "PID: \(getpid())\n"

                var callstack = [UnsafeMutableRawPointer?](repeating: nil, count: 128)
                let frames = backtrace(&callstack, 128)
                if let symbols = backtrace_symbols(&callstack, frames) {
                    for i in 0 ..< Int(frames) {
                        if let sym = symbols[i] {
                            info += String(cString: sym) + "\n"
                        }
                    }
                    free(symbols)
                }

                let fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
                if fd >= 0 {
                    info.withCString { ptr in
                        _ = write(fd, ptr, strlen(ptr))
                    }
                    close(fd)
                }

                signal(sigNum, SIG_DFL)
                raise(sigNum)
            }
        }
    }

    @inline(never)
    private static func _verifyCodeSignature() -> Bool {
        guard let execURL = Bundle.main.executableURL else { return false }

        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(execURL as CFURL, [], &staticCode)
        guard createStatus == errSecSuccess, let code = staticCode else { return false }

        let checkStatus = SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSDoNotValidateResources), nil)
        return checkStatus == errSecSuccess
    }

    // MARK: - Key derivation with intermediate noise (same final result, harder to trace)

    @inline(never)
    private func deriveKey(salt: String) -> Data {
        let c1 = _computeC1()
        let c2 = _computeC2()
        let c3 = _computeC3()
        let c4 = _computeC4()

        var seed = Data()
        withUnsafeBytes(of: c1.bigEndian) { seed.append(contentsOf: $0) }
        withUnsafeBytes(of: c2.bigEndian) { seed.append(contentsOf: $0) }
        withUnsafeBytes(of: c3.bigEndian) { seed.append(contentsOf: $0) }
        withUnsafeBytes(of: c4.bigEndian) { seed.append(contentsOf: $0) }

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

    @inline(never)
    private func deriveKey() -> Data {
        let bundleId = Bundle.main.bundleIdentifier ?? "com.mai.browser"
        return deriveKey(salt: "wk.\(bundleId).render")
    }

    // Key components: intermediate add/subtract noise that cancels out.
    // Prevents compiler constant-folding and confuses LLM data-flow analysis.
    // Final value: identical to original (a &+ b).

    @inline(never) private func _computeC1() -> UInt64 {
        let a: UInt64 = 0x2620_A4A1_3937_BBBA
        let b: UInt64 = 0x2720_A4A1_3937_BBB9
        let n: UInt64 = 0x3141_5926_5358_9793
        var r = a &+ n
        r = r &+ b
        r = r &- n
        return r
    }
    @inline(never) private func _computeC2() -> UInt64 {
        let a: UInt64 = 0x32B9_2839_37BA_32B2
        let b: UInt64 = 0x32B9_2839_37BA_32B1
        let n: UInt64 = 0x7F23_4A91_B2C8_E617
        var r = a &+ n
        r = r &+ b
        r = r &- n
        return r
    }
    @inline(never) private func _computeC3() -> UInt64 {
        let a: UInt64 = 0x3A34_B7B7_25B2_BC99
        let b: UInt64 = 0x3A34_B7B7_25B2_BC99
        let n: UInt64 = 0xA8B3_C2D1_E4F5_0617
        var r = a &+ n
        r = r &+ b
        r = r &- n
        return r
    }
    @inline(never) private func _computeC4() -> UInt64 {
        let a: UInt64 = 0x1819_1B20_A2A9_991B
        let b: UInt64 = 0x1819_1B20_A2A9_991A
        let n: UInt64 = 0x5C6D_7E8F_9A0B_1C2D
        var r = a &+ n
        r = r &+ b
        r = r &- n
        return r
    }

    // MARK: - Decoy key schedule (Kong analyzes this but it's never used for real decryption)

    @inline(never) private func _computeC5() -> UInt64 {
        let a: UInt64 = 0x4A29_BB13_CC82_1FA3
        let b: UInt64 = 0x1E72_93A4_DD51_8B67
        return a &* b &+ 0x7F
    }
    @inline(never) private func _computeC6() -> UInt64 {
        let a: UInt64 = 0x8817_2B3C_4D5E_6F70
        let b: UInt64 = 0x1928_3A4B_5C6D_7E8F
        return (a ^ b) &+ 0x1337
    }

    @inline(never)
    private func _deriveAuxKey(salt: String, epoch: UInt32) -> Data {
        let c5 = _computeC5()
        let c6 = _computeC6()
        var seed = Data()
        withUnsafeBytes(of: c5.bigEndian) { seed.append(contentsOf: $0) }
        withUnsafeBytes(of: c6.bigEndian) { seed.append(contentsOf: $0) }
        withUnsafeBytes(of: epoch.bigEndian) { seed.append(contentsOf: $0) }
        let saltData = salt.data(using: .utf8)!
        var dk = Data(count: 32)
        let _ = dk.withUnsafeMutableBytes { kp in
            saltData.withUnsafeBytes { sp in
                seed.withUnsafeBytes { sdp in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        sdp.baseAddress?.assumingMemoryBound(to: Int8.self),
                        seed.count,
                        sp.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        saltData.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        25_000,
                        kp.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        32
                    )
                }
            }
        }
        return dk
    }

    @inline(never)
    private func _decryptAuxPayload(_ data: Data, token: UInt32) -> String? {
        guard data.count >= 64 else { return nil }
        let iv = data.prefix(16)
        let ct = data[16 ..< (data.count - 32)]
        let tag = data.suffix(32)
        let key = _deriveAuxKey(salt: "aux.\(token)", epoch: _rotationEpoch)
        _ = iv; _ = ct; _ = tag; _ = key
        return nil
    }

    // MARK: - Decrypt (single blob)

    func decrypt(identifier: String, data: Data) -> String {
        #if !DEBUG
        if !_safeEnvironment || !_integrityValid || !_hooksClean { return "" }
        #endif

        lock.lock()
        defer { lock.unlock() }

        if let cached = _cache[identifier] { return cached }

        guard data.count >= 49 else { return "" }

        let key = deriveKey()
        guard let result = _decryptWithKey(key: key, data: data) else { return "" }

        _cache[identifier] = result
        return result
    }

    // MARK: - Decrypt Fragmented

    var isSIPDegraded: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _sipDisabled
    }

    func decryptFragmented(identifier: String, fragments: [Data], order: [Int], salts: [String], expectedHash: Data? = nil) -> String {
        #if !DEBUG
        if !_safeEnvironment || !_integrityValid || !_hooksClean { return "" }
        if _sipDisabled { return "" }
        #endif

        lock.lock()
        defer { lock.unlock() }

        if let cached = _cache[identifier] { return cached }

        guard fragments.count == order.count, fragments.count == salts.count else { return "" }

        var decryptedFragments = Array(repeating: "", count: fragments.count)
        for i in 0 ..< fragments.count {
            let key = deriveKey(salt: salts[i])
            guard let text = _decryptWithKey(key: key, data: fragments[i]) else { return "" }
            decryptedFragments[i] = text
        }

        var assembled = ""
        for originalIdx in 0 ..< order.count {
            let shuffledIdx = order[originalIdx]
            if shuffledIdx < decryptedFragments.count {
                assembled += decryptedFragments[shuffledIdx]
            }
        }

        if let expected = expectedHash {
            if !_verifyScriptHash(assembled, expected: expected) {
                #if DEBUG
                print("⚠️ WKRenderPipeline: hash mismatch para '\(identifier)' — permitido en DEBUG")
                #else
                _safeEnvironment = false
                _cache.removeAll()
                return ""
                #endif
            }
        }

        _cache[identifier] = assembled
        return assembled
    }

    @inline(never)
    private func _verifyScriptHash(_ script: String, expected: Data) -> Bool {
        guard let scriptData = script.data(using: .utf8) else { return false }
        var hash = Data(count: Int(CC_SHA256_DIGEST_LENGTH))
        _ = hash.withUnsafeMutableBytes { hashPtr in
            scriptData.withUnsafeBytes { dataPtr in
                CC_SHA256(dataPtr.baseAddress, CC_LONG(scriptData.count), hashPtr.baseAddress?.assumingMemoryBound(to: UInt8.self))
            }
        }
        guard hash.count == expected.count else { return false }
        var result: UInt8 = 0
        for i in 0 ..< hash.count {
            result |= hash[i] ^ expected[i]
        }
        return result == 0
    }

    private func _decryptWithKey(key: Data, data: Data) -> String? {
        guard data.count >= 49 else { return nil }

        let iv = data.prefix(kCCBlockSizeAES128)
        let hmacStored = data.suffix(Int(CC_SHA256_DIGEST_LENGTH))
        let ciphertext = data[kCCBlockSizeAES128 ..< (data.count - Int(CC_SHA256_DIGEST_LENGTH))]

        let macInput = Data(iv + ciphertext)
        var hmacComputed = Data(count: Int(CC_SHA256_DIGEST_LENGTH))
        let _ = hmacComputed.withUnsafeMutableBytes { hmacPtr in
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

        guard hmacComputed == hmacStored else { return nil }

        let ctCount = ciphertext.count
        let ptSize = ctCount + kCCBlockSizeAES128
        var plaintext = Data(count: ptSize)
        var decryptedCount = 0

        let status = plaintext.withUnsafeMutableBytes { ptPtr in
            ciphertext.withUnsafeBytes { ctPtr in
                iv.withUnsafeBytes { ivPtr in
                    key.withUnsafeBytes { keyPtr in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyPtr.baseAddress, 32,
                            ivPtr.baseAddress,
                            ctPtr.baseAddress, ctCount,
                            ptPtr.baseAddress, ptSize,
                            &decryptedCount
                        )
                    }
                }
            }
        }

        guard status == CCCryptorStatus(kCCSuccess) else { return nil }

        plaintext.count = decryptedCount
        return String(data: plaintext, encoding: .utf8)
    }

    func evict(identifier: String) {
        lock.lock()
        _cache.removeValue(forKey: identifier)
        lock.unlock()
    }

    func clearCache() {
        lock.lock()
        _cache.removeAll()
        lock.unlock()
    }
}
