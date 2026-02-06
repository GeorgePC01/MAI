import Foundation

/// Módulo de networking para MAI
public struct MAINetworking {
    public static let version = "0.1.0"
}

/// Configuración de red
public struct NetworkConfiguration {
    public var enableDNSOverHTTPS: Bool = true
    public var dnsServer: String = "1.1.1.1"  // Cloudflare
    public var timeout: TimeInterval = 30
    public var enableHTTP3: Bool = true

    public init() {}
}

/// Custom URL Session para MAI
public class MAIURLSession {
    private let config: NetworkConfiguration
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = self.config.timeout
        config.httpAdditionalHeaders = [
            "User-Agent": "MAI/0.1.0 (macOS)"
        ]
        return URLSession(configuration: config)
    }()

    public init(config: NetworkConfiguration = NetworkConfiguration()) {
        self.config = config
    }

    public func fetch(url: URL) async throws -> Data {
        let (data, _) = try await session.data(from: url)
        return data
    }
}
