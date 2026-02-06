import Foundation
import WebKit

/// Módulo de rendering - WebKit wrapper
public struct MAIRendering {
    public static let version = "0.1.0"
}

/// Configuración de WebKit para MAI
public struct WebKitConfiguration {
    public var enableJavaScript: Bool = true
    public var enableWebGL: Bool = true
    public var enableMediaPlayback: Bool = true
    public var blockPopups: Bool = true

    public init() {}

    public func createWKConfiguration() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptCanOpenWindowsAutomatically = !blockPopups
        // allowsInlineMediaPlayback is available on iOS, not macOS
        // On macOS, inline media playback is always allowed
        return config
    }
}
