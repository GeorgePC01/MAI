//
//  CDPManager.swift
//  MAI Browser - Chrome DevTools Protocol Manager
//
//  Connects to CEF's CDP API for JavaScript debugging (breakpoints, stepping, etc.)
//  Uses CEFBridge's send_dev_tools_message / add_dev_tools_message_observer.
//

import SwiftUI
import CEFWrapper

// MARK: - CDP Data Models

struct CDPScript: Identifiable, Hashable {
    let id: String  // scriptId from CDP
    let url: String
    let startLine: Int
    let endLine: Int
    var source: String?

    var displayName: String {
        if url.isEmpty { return "inline-\(id)" }
        return URL(string: url)?.lastPathComponent ?? url
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: CDPScript, rhs: CDPScript) -> Bool { lhs.id == rhs.id }
}

struct CDPBreakpoint: Identifiable {
    let id: String  // breakpointId from CDP
    let scriptId: String
    let url: String
    let lineNumber: Int
    let condition: String
}

struct CDPCallFrame: Identifiable {
    let id: String  // callFrameId
    let functionName: String
    let scriptId: String
    let lineNumber: Int
    let columnNumber: Int
    let scopeChain: [[String: Any]]

    var displayName: String {
        functionName.isEmpty ? "(anónimo)" : functionName
    }
}

enum CDPPauseState {
    case running
    case paused(reason: String, callFrames: [CDPCallFrame])
}

// MARK: - CDP Manager

class CDPManager: NSObject, ObservableObject, CEFBridgeCDPDelegate {
    static let shared = CDPManager()

    @Published var isAttached = false
    @Published var scripts: [CDPScript] = []
    @Published var breakpoints: [CDPBreakpoint] = []
    @Published var pauseState: CDPPauseState = .running
    @Published var consoleOutput: [(id: UUID, text: String, type: String)] = []
    @Published var watchExpressions: [(id: UUID, expr: String, value: String)] = []
    @Published var selectedScript: CDPScript?
    @Published var scriptSource: String = ""

    private var pendingCallbacks: [Int: (Bool, String) -> Void] = [:]
    private var scriptSourceCallbacks: [Int: (String) -> Void] = [:]

    var isPaused: Bool {
        if case .paused = pauseState { return true }
        return false
    }

    var callFrames: [CDPCallFrame] {
        if case .paused(_, let frames) = pauseState { return frames }
        return []
    }

    // MARK: - Attach / Detach

    func attach() {
        CEFBridge.setCDPDelegate(self)
        let ok = CEFBridge.cdpAttach()
        if ok {
            // Enable Debugger and Runtime domains
            sendCommand("Debugger.enable") { [weak self] success, _ in
                if success {
                    self?.sendCommand("Runtime.enable")
                    DispatchQueue.main.async { self?.isAttached = true }
                }
            }
        }
    }

    func detach() {
        if isAttached {
            sendCommand("Debugger.disable")
            sendCommand("Runtime.disable")
        }
        CEFBridge.cdpDetach()
        DispatchQueue.main.async {
            self.isAttached = false
            self.scripts.removeAll()
            self.breakpoints.removeAll()
            self.pauseState = .running
            self.consoleOutput.removeAll()
        }
    }

    // MARK: - Send Commands

    @discardableResult
    func sendCommand(_ method: String, params: [String: Any]? = nil, callback: ((Bool, String) -> Void)? = nil) -> Int {
        var paramsJson: String? = nil
        if let params = params {
            if let data = try? JSONSerialization.data(withJSONObject: params),
               let str = String(data: data, encoding: .utf8) {
                paramsJson = str
            }
        }

        let msgId = CEFBridge.cdpSendMethod(method, params: paramsJson)
        if msgId > 0, let callback = callback {
            pendingCallbacks[Int(msgId)] = callback
        }
        return Int(msgId)
    }

    // MARK: - Debugger Actions

    func setBreakpoint(url: String, line: Int, condition: String = "") {
        var params: [String: Any] = ["lineNumber": line, "url": url]
        if !condition.isEmpty { params["condition"] = condition }

        sendCommand("Debugger.setBreakpointByUrl", params: params) { [weak self] success, result in
            guard success else { return }
            if let data = result.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let bpId = json["breakpointId"] as? String {
                DispatchQueue.main.async {
                    let bp = CDPBreakpoint(id: bpId, scriptId: "", url: url, lineNumber: line, condition: condition)
                    self?.breakpoints.append(bp)
                }
            }
        }
    }

    func removeBreakpoint(_ breakpointId: String) {
        sendCommand("Debugger.removeBreakpoint", params: ["breakpointId": breakpointId]) { [weak self] success, _ in
            if success {
                DispatchQueue.main.async {
                    self?.breakpoints.removeAll { $0.id == breakpointId }
                }
            }
        }
    }

    func resume() {
        sendCommand("Debugger.resume", params: ["terminateOnResume": false])
    }

    func pause() {
        sendCommand("Debugger.pause")
    }

    func stepOver() {
        sendCommand("Debugger.stepOver")
    }

    func stepInto() {
        sendCommand("Debugger.stepInto")
    }

    func stepOut() {
        sendCommand("Debugger.stepOut")
    }

    func evaluate(_ expression: String) {
        sendCommand("Runtime.evaluate", params: [
            "expression": expression,
            "returnByValue": true,
            "generatePreview": true
        ]) { [weak self] success, result in
            DispatchQueue.main.async {
                let value = success ? self?.extractValue(from: result) ?? result : "Error: \(result)"
                self?.consoleOutput.append((id: UUID(), text: "› \(expression)\n← \(value)", type: success ? "result" : "error"))
            }
        }
    }

    func loadScriptSource(_ script: CDPScript) {
        sendCommand("Debugger.getScriptSource", params: ["scriptId": script.id]) { [weak self] success, result in
            if success,
               let data = result.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let source = json["scriptSource"] as? String {
                DispatchQueue.main.async {
                    self?.selectedScript = script
                    self?.scriptSource = source
                    if let idx = self?.scripts.firstIndex(where: { $0.id == script.id }) {
                        self?.scripts[idx].source = source
                    }
                }
            }
        }
    }

    func refreshWatchExpressions() {
        for (i, watch) in watchExpressions.enumerated() {
            sendCommand("Runtime.evaluate", params: [
                "expression": watch.expr,
                "returnByValue": true
            ]) { [weak self] success, result in
                DispatchQueue.main.async {
                    let value = success ? self?.extractValue(from: result) ?? "undefined" : "Error"
                    if i < (self?.watchExpressions.count ?? 0) {
                        self?.watchExpressions[i].value = value
                    }
                }
            }
        }
    }

    // MARK: - CEFBridgeCDPDelegate

    func cdpDidReceiveMethodResult(_ messageId: Int32, success: Bool, result: String) {
        let id = Int(messageId)
        if let callback = pendingCallbacks.removeValue(forKey: id) {
            callback(success, result)
        }
    }

    func cdpDidReceiveEvent(_ method: String, params: String) {
        switch method {
        case "Debugger.scriptParsed":
            handleScriptParsed(params)
        case "Debugger.paused":
            handlePaused(params)
        case "Debugger.resumed":
            DispatchQueue.main.async {
                self.pauseState = .running
            }
        case "Runtime.consoleAPICalled":
            handleConsoleAPI(params)
        default:
            break
        }
    }

    func cdpDidAttach() {
        print("✅ CDP agent attached")
    }

    func cdpDidDetach() {
        DispatchQueue.main.async {
            self.isAttached = false
            self.pauseState = .running
        }
    }

    // MARK: - Event Handlers

    private func handleScriptParsed(_ paramsJson: String) {
        guard let data = paramsJson.data(using: .utf8),
              let params = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let scriptId = params["scriptId"] as? String else { return }

        let url = params["url"] as? String ?? ""
        // Skip empty/internal scripts
        if url.isEmpty || url.hasPrefix("extensions://") { return }

        let script = CDPScript(
            id: scriptId,
            url: url,
            startLine: params["startLine"] as? Int ?? 0,
            endLine: params["endLine"] as? Int ?? 0
        )

        DispatchQueue.main.async {
            if !self.scripts.contains(where: { $0.id == scriptId }) {
                self.scripts.append(script)
            }
        }
    }

    private func handlePaused(_ paramsJson: String) {
        guard let data = paramsJson.data(using: .utf8),
              let params = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        let reason = params["reason"] as? String ?? "unknown"
        var frames: [CDPCallFrame] = []

        if let callFrames = params["callFrames"] as? [[String: Any]] {
            frames = callFrames.compactMap { frame in
                guard let frameId = frame["callFrameId"] as? String,
                      let location = frame["location"] as? [String: Any],
                      let scriptId = location["scriptId"] as? String,
                      let line = location["lineNumber"] as? Int else { return nil }

                return CDPCallFrame(
                    id: frameId,
                    functionName: frame["functionName"] as? String ?? "",
                    scriptId: scriptId,
                    lineNumber: line,
                    columnNumber: location["columnNumber"] as? Int ?? 0,
                    scopeChain: frame["scopeChain"] as? [[String: Any]] ?? []
                )
            }
        }

        DispatchQueue.main.async {
            self.pauseState = .paused(reason: reason, callFrames: frames)
            self.refreshWatchExpressions()
        }
    }

    private func handleConsoleAPI(_ paramsJson: String) {
        guard let data = paramsJson.data(using: .utf8),
              let params = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        let type = params["type"] as? String ?? "log"
        var text = ""
        if let args = params["args"] as? [[String: Any]] {
            text = args.compactMap { arg -> String? in
                if let value = arg["value"] { return "\(value)" }
                if let desc = arg["description"] as? String { return desc }
                return arg["type"] as? String
            }.joined(separator: " ")
        }

        DispatchQueue.main.async {
            self.consoleOutput.append((id: UUID(), text: text, type: type))
        }
    }

    // MARK: - Helpers

    private func extractValue(from resultJson: String) -> String? {
        guard let data = resultJson.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any] else { return nil }

        if let value = result["value"] {
            if let strVal = value as? String { return "\"\(strVal)\"" }
            return "\(value)"
        }
        if let desc = result["description"] as? String { return desc }
        if let type = result["type"] as? String {
            if type == "undefined" { return "undefined" }
            if let subtype = result["subtype"] as? String { return "\(type):\(subtype)" }
            return type
        }
        return nil
    }
}
