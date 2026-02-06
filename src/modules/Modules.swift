import Foundation

/// Sistema de módulos de MAI
public struct MAIModules {
    public static let version = "0.1.0"
}

/// Protocolo base para todos los módulos de MAI
public protocol MAIModuleProtocol: AnyObject {
    var identifier: String { get }
    var name: String { get }
    var version: String { get }
    var isEnabled: Bool { get set }

    func onLoad()
    func onUnload()
    func onPageLoad(url: URL)
    func onPageUnload(url: URL)
}

/// Extensión con implementaciones por defecto
public extension MAIModuleProtocol {
    func onPageLoad(url: URL) {}
    func onPageUnload(url: URL) {}
}

/// Registry central de módulos
public class ModuleRegistry {
    public static let shared = ModuleRegistry()

    private var modules: [String: MAIModuleProtocol] = [:]

    private init() {}

    public func register(_ module: MAIModuleProtocol) {
        modules[module.identifier] = module
        if module.isEnabled {
            module.onLoad()
        }
    }

    public func unregister(identifier: String) {
        if let module = modules[identifier] {
            module.onUnload()
            modules.removeValue(forKey: identifier)
        }
    }

    public func getModule(identifier: String) -> MAIModuleProtocol? {
        return modules[identifier]
    }

    public var allModules: [MAIModuleProtocol] {
        Array(modules.values)
    }

    public func notifyPageLoad(url: URL) {
        modules.values.filter { $0.isEnabled }.forEach { $0.onPageLoad(url: url) }
    }

    public func notifyPageUnload(url: URL) {
        modules.values.filter { $0.isEnabled }.forEach { $0.onPageUnload(url: url) }
    }
}
