import Foundation
import WebKit

/// Niveles de protección anti-fingerprinting
enum FingerprintProtectionLevel: Int, CaseIterable {
    case off = 0        // Sin protección
    case standard = 1   // Ruido sutil, cero rotura de sitios
    case strong = 2     // + Screen/fonts/WebGL extras, rotura mínima
    case maximum = 3    // + Timezone UTC, locale en-US (puede romper sitios)

    var displayName: String {
        switch self {
        case .off: return "Desactivado"
        case .standard: return "Estándar"
        case .strong: return "Fuerte"
        case .maximum: return "Máximo"
        }
    }

    var description: String {
        switch self {
        case .off: return "Sin protección contra rastreo por huella digital"
        case .standard: return "Protección contra canvas, WebGL, audio y hardware fingerprinting. No rompe sitios."
        case .strong: return "Protección adicional de pantalla, fuentes y extensiones WebGL. Rotura mínima."
        case .maximum: return "Protección máxima: timezone UTC, locale en-US. Puede romper algunos sitios."
        }
    }
}

/// Motor anti-fingerprinting de MAI
/// Genera scripts JS inyectables para proteger contra rastreo por huella digital del navegador.
/// Inspirado en Brave (farbling), Firefox (resistFingerprinting) y Tor Browser.
class AntiFingerprintManager {
    static let shared = AntiFingerprintManager()

    /// Nivel de protección actual
    var protectionLevel: FingerprintProtectionLevel {
        get {
            let raw = UserDefaults.standard.integer(forKey: "fingerprintProtectionLevel")
            return FingerprintProtectionLevel(rawValue: raw) ?? .standard
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "fingerprintProtectionLevel") }
    }

    /// Semilla de sesión (cambia cada vez que se inicia el navegador)
    private let sessionSeed: UInt32 = UInt32.random(in: 0...UInt32.max)

    private init() {}

    /// Genera el script anti-fingerprinting para el nivel actual
    func generateScript(level: FingerprintProtectionLevel? = nil) -> String {
        let effectiveLevel = level ?? protectionLevel
        guard effectiveLevel != .off else { return "" }

        var script = scriptHeader()

        // Nivel 1 — Estándar (siempre)
        script += canvasNoiseScript()
        script += webGLBasicScript()
        script += audioNoiseScript()
        script += navigatorSpoofScript()
        script += mediaDevicesSpoofScript()
        script += speechVoicesScript()
        script += webGPUBlockScript()
        script += clientRectsScript()
        script += connectionAPIScript()

        // Nivel 2 — Fuerte
        if effectiveLevel.rawValue >= FingerprintProtectionLevel.strong.rawValue {
            script += screenSpoofScript()
            script += fontEnumerationScript()
            script += webGLExtendedScript()
        }

        // Nivel 3 — Máximo
        if effectiveLevel == .maximum {
            script += timezoneScript()
        }

        script += antiDetectionScript()
        script += scriptFooter()

        return script
    }

    /// Crea el WKUserScript listo para inyectar
    func userScript(level: FingerprintProtectionLevel? = nil) -> WKUserScript? {
        let source = generateScript(level: level)
        guard !source.isEmpty else { return nil }
        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false)
    }

    // MARK: - Script Components

    /// Dominios donde el anti-fingerprinting se desactiva completamente.
    /// Sitios de medición de red usan canvas/WebGL de forma funcional (no de tracking).
    private static let fingerprintBypassDomains: [String] = [
        "speedtest.net",
        "ookla.com",
        "fast.com",
        "nperf.com",
        "speed.cloudflare.com",
        "speedof.me",
        "testmy.net"
    ]

    private func scriptHeader() -> String {
        let bypassList = Self.fingerprintBypassDomains
            .map { "\"\($0)\"" }
            .joined(separator: ", ")

        return """
        (function() {
            'use strict';
            if (window._maiAntiFingerprint) return;

            // Bypass completo en sitios de medición de red
            const _maiFpBypass = [\(bypassList)];
            const _maiHost = location.hostname.replace(/^www\\./, '');
            if (_maiFpBypass.some(d => _maiHost === d || _maiHost.endsWith('.' + d))) return;

            window._maiAntiFingerprint = true;

            const SESSION_SEED = \(sessionSeed);

            function mulberry32(seed) {
                return function() {
                    seed |= 0; seed = seed + 0x6D2B79F5 | 0;
                    var t = Math.imul(seed ^ seed >>> 15, 1 | seed);
                    t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t;
                    return ((t ^ t >>> 14) >>> 0) / 4294967296;
                };
            }

            function hashDomain(domain) {
                let h = SESSION_SEED;
                for (let i = 0; i < domain.length; i++) {
                    h = ((h << 5) - h + domain.charCodeAt(i)) | 0;
                }
                return h >>> 0;
            }

            const domainSeed = hashDomain(location.hostname);
            const rng = mulberry32(domainSeed);

        """
    }

    private func canvasNoiseScript() -> String {
        return """
            // CANVAS 2D — Ruido sutil en 5% de píxeles (±2 valores, imperceptible)
            const origGetImageData = CanvasRenderingContext2D.prototype.getImageData;
            const origToDataURL = HTMLCanvasElement.prototype.toDataURL;
            const origToBlob = HTMLCanvasElement.prototype.toBlob;

            function addCanvasNoise(imageData) {
                const data = imageData.data;
                const localRng = mulberry32(domainSeed ^ data.length);
                for (let i = 0; i < data.length; i += 4) {
                    if (localRng() < 0.05) {
                        const channel = (localRng() < 0.5) ? 2 : 0;
                        const delta = (localRng() < 0.5) ? 1 : -1;
                        data[i + channel] = Math.max(0, Math.min(255, data[i + channel] + delta));
                    }
                }
                return imageData;
            }

            CanvasRenderingContext2D.prototype.getImageData = function() {
                const imageData = origGetImageData.apply(this, arguments);
                return addCanvasNoise(imageData);
            };

            HTMLCanvasElement.prototype.toDataURL = function() {
                const ctx = this.getContext('2d');
                if (ctx) {
                    const imageData = origGetImageData.call(ctx, 0, 0, this.width, this.height);
                    addCanvasNoise(imageData);
                    const tempCanvas = document.createElement('canvas');
                    tempCanvas.width = this.width;
                    tempCanvas.height = this.height;
                    tempCanvas.getContext('2d').putImageData(imageData, 0, 0);
                    return origToDataURL.apply(tempCanvas, arguments);
                }
                return origToDataURL.apply(this, arguments);
            };

            HTMLCanvasElement.prototype.toBlob = function(callback) {
                const ctx = this.getContext('2d');
                if (ctx && callback) {
                    const imageData = origGetImageData.call(ctx, 0, 0, this.width, this.height);
                    addCanvasNoise(imageData);
                    const tempCanvas = document.createElement('canvas');
                    tempCanvas.width = this.width;
                    tempCanvas.height = this.height;
                    tempCanvas.getContext('2d').putImageData(imageData, 0, 0);
                    return origToBlob.apply(tempCanvas, arguments);
                }
                return origToBlob.apply(this, arguments);
            };

        """
    }

    private func webGLBasicScript() -> String {
        return """
            // WEBGL — Spoofear renderer/vendor a valores genéricos
            const origGetParameter = WebGLRenderingContext.prototype.getParameter;
            const origGetParameter2 = WebGL2RenderingContext.prototype.getParameter;

            function spoofWebGLParam(original, gl, pname) {
                const result = original.call(gl, pname);
                if (pname === 0x9245) return 'Apple Inc.';
                if (pname === 0x9246) return 'Apple GPU';
                if (pname === 0x0D33) return 4096;
                if (pname === 0x84E8) return 4096;
                if (pname === 0x0D3A) return new Int32Array([4096, 4096]);
                return result;
            }

            WebGLRenderingContext.prototype.getParameter = function(pname) {
                return spoofWebGLParam(origGetParameter, this, pname);
            };
            WebGL2RenderingContext.prototype.getParameter = function(pname) {
                return spoofWebGLParam(origGetParameter2, this, pname);
            };

        """
    }

    private func audioNoiseScript() -> String {
        return """
            // AUDIO — Ruido inaudible (0.0002 amplitud) en AudioBuffer/AnalyserNode
            const origGetChannelData = AudioBuffer.prototype.getChannelData;
            AudioBuffer.prototype.getChannelData = function(channel) {
                const data = origGetChannelData.call(this, channel);
                const localRng = mulberry32(domainSeed ^ data.length ^ channel);
                for (let i = 0; i < data.length; i++) {
                    data[i] += (localRng() - 0.5) * 0.0002;
                }
                return data;
            };

            const origGetFloatFreq = AnalyserNode.prototype.getFloatFrequencyData;
            AnalyserNode.prototype.getFloatFrequencyData = function(array) {
                origGetFloatFreq.call(this, array);
                const localRng = mulberry32(domainSeed ^ array.length);
                for (let i = 0; i < array.length; i++) {
                    array[i] += (localRng() - 0.5) * 0.1;
                }
            };

            const origGetByteFreq = AnalyserNode.prototype.getByteFrequencyData;
            AnalyserNode.prototype.getByteFrequencyData = function(array) {
                origGetByteFreq.call(this, array);
                const localRng = mulberry32(domainSeed ^ array.length);
                for (let i = 0; i < array.length; i++) {
                    if (localRng() < 0.1) {
                        array[i] = Math.max(0, Math.min(255, array[i] + ((localRng() < 0.5) ? 1 : -1)));
                    }
                }
            };

        """
    }

    private func navigatorSpoofScript() -> String {
        return """
            // NAVIGATOR — Valores fijos genéricos (estilo Firefox RFP)
            try {
                Object.defineProperty(Navigator.prototype, 'hardwareConcurrency', { value: 4, writable: false, configurable: true, enumerable: true });
                Object.defineProperty(Navigator.prototype, 'deviceMemory', { value: 8, writable: false, configurable: true, enumerable: true });
                Object.defineProperty(Navigator.prototype, 'platform', { value: 'MacIntel', writable: false, configurable: true, enumerable: true });
            } catch(e) {}

        """
    }

    private func mediaDevicesSpoofScript() -> String {
        return """
            // MEDIADEVICES — Sin permiso: reportar 1 cámara + 1 mic genéricos
            const origEnumerateDevices = navigator.mediaDevices?.enumerateDevices?.bind(navigator.mediaDevices);
            if (origEnumerateDevices) {
                navigator.mediaDevices.enumerateDevices = async function() {
                    const devices = await origEnumerateDevices();
                    const hasLabels = devices.some(d => d.label && d.label.length > 0);
                    if (!hasLabels) {
                        return [
                            { deviceId: '', kind: 'audioinput', label: '', groupId: '' },
                            { deviceId: '', kind: 'videoinput', label: '', groupId: '' },
                            { deviceId: '', kind: 'audiooutput', label: '', groupId: '' }
                        ];
                    }
                    return devices;
                };
            }

        """
    }

    private func speechVoicesScript() -> String {
        return """
            // SPEECH SYNTHESIS — Lista vacía
            if (window.speechSynthesis) {
                window.speechSynthesis.getVoices = function() { return []; };
            }

        """
    }

    private func webGPUBlockScript() -> String {
        return """
            // WEBGPU — Remover API (pocos sitios lo usan, alto riesgo fingerprint)
            if (navigator.gpu) {
                try {
                    Object.defineProperty(Navigator.prototype, 'gpu', { get: () => undefined, configurable: true });
                } catch(e) {}
            }

        """
    }

    private func clientRectsScript() -> String {
        return """
            // CLIENT RECTS — Redondear a enteros (elimina diferencias subpíxel)
            const origGetBCR = Element.prototype.getBoundingClientRect;
            Element.prototype.getBoundingClientRect = function() {
                const rect = origGetBCR.call(this);
                return new DOMRect(Math.round(rect.x), Math.round(rect.y), Math.round(rect.width), Math.round(rect.height));
            };

            const origGetCR = Element.prototype.getClientRects;
            Element.prototype.getClientRects = function() {
                const rects = origGetCR.call(this);
                const result = [];
                for (let i = 0; i < rects.length; i++) {
                    result.push(new DOMRect(Math.round(rects[i].x), Math.round(rects[i].y), Math.round(rects[i].width), Math.round(rects[i].height)));
                }
                result.item = function(i) { return this[i]; };
                return result;
            };

        """
    }

    private func connectionAPIScript() -> String {
        return """
            // CONNECTION API — Valores genéricos
            if (navigator.connection) {
                try {
                    Object.defineProperty(Navigator.prototype, 'connection', {
                        get: () => ({ effectiveType: '4g', downlink: 10, rtt: 50, saveData: false, type: 'wifi', addEventListener: () => {}, removeEventListener: () => {} }),
                        configurable: true
                    });
                } catch(e) {}
            }

        """
    }

    // MARK: - Nivel 2 (Fuerte)

    private func screenSpoofScript() -> String {
        return """
            // SCREEN — Redondear a resoluciones comunes de Mac
            const commonWidths = [1280, 1440, 1680, 1920, 2560];
            const commonHeights = [800, 900, 1050, 1080, 1440];
            function roundToNearest(val, options) {
                return options.reduce((prev, curr) => Math.abs(curr - val) < Math.abs(prev - val) ? curr : prev);
            }
            const spoofedWidth = roundToNearest(screen.width, commonWidths);
            const spoofedHeight = roundToNearest(screen.height, commonHeights);
            try {
                Object.defineProperty(Screen.prototype, 'width', { get: () => spoofedWidth, configurable: true, enumerable: true });
                Object.defineProperty(Screen.prototype, 'height', { get: () => spoofedHeight, configurable: true, enumerable: true });
                Object.defineProperty(Screen.prototype, 'availWidth', { get: () => spoofedWidth, configurable: true, enumerable: true });
                Object.defineProperty(Screen.prototype, 'availHeight', { get: () => spoofedHeight - 25, configurable: true, enumerable: true });
                Object.defineProperty(Screen.prototype, 'colorDepth', { get: () => 24, configurable: true, enumerable: true });
                Object.defineProperty(Screen.prototype, 'pixelDepth', { get: () => 24, configurable: true, enumerable: true });
                Object.defineProperty(window, 'devicePixelRatio', { get: () => 2, configurable: true, enumerable: true });
            } catch(e) {}

        """
    }

    private func fontEnumerationScript() -> String {
        return """
            // FUENTES — measureText retorna medidas de Arial para fuentes no-sistema
            const systemFonts = new Set([
                'Arial', 'Helvetica', 'Helvetica Neue', 'Times New Roman', 'Times',
                'Courier New', 'Courier', 'Verdana', 'Georgia', 'Palatino',
                'Garamond', 'Comic Sans MS', 'Trebuchet MS', 'Arial Black',
                'Impact', 'Lucida Sans', 'Tahoma', 'Geneva', 'Menlo', 'Monaco',
                'San Francisco', 'SF Pro', 'SF Mono', '-apple-system',
                'system-ui', 'BlinkMacSystemFont'
            ]);
            const origMeasureText = CanvasRenderingContext2D.prototype.measureText;
            CanvasRenderingContext2D.prototype.measureText = function(text) {
                const result = origMeasureText.call(this, text);
                const font = this.font || '';
                const fontFamily = font.split(',').map(f => f.trim().replace(/['"]/g, ''));
                const isSystemFont = fontFamily.some(f => systemFonts.has(f));
                if (!isSystemFont) {
                    const savedFont = this.font;
                    this.font = font.replace(/(['"]?)[\\w\\s-]+\\1(\\s*,|$)/g, 'Arial$2');
                    const fallback = origMeasureText.call(this, text);
                    this.font = savedFont;
                    return fallback;
                }
                return result;
            };

        """
    }

    private func webGLExtendedScript() -> String {
        return """
            // WEBGL EXTENDED — Extensiones limitadas + readPixels con ruido
            const safeExtensions = [
                'ANGLE_instanced_arrays', 'EXT_blend_minmax', 'EXT_color_buffer_half_float',
                'EXT_shader_texture_lod', 'EXT_texture_filter_anisotropic',
                'OES_element_index_uint', 'OES_standard_derivatives',
                'OES_texture_float', 'OES_texture_half_float',
                'OES_vertex_array_object', 'WEBGL_compressed_texture_s3tc',
                'WEBGL_depth_texture', 'WEBGL_lose_context'
            ];
            const origGetExtensions = WebGLRenderingContext.prototype.getSupportedExtensions;
            WebGLRenderingContext.prototype.getSupportedExtensions = function() {
                const real = origGetExtensions.call(this);
                if (!real) return real;
                return real.filter(e => safeExtensions.includes(e));
            };

            const origReadPixels = WebGLRenderingContext.prototype.readPixels;
            WebGLRenderingContext.prototype.readPixels = function() {
                origReadPixels.apply(this, arguments);
                const pixels = arguments[6];
                if (pixels && pixels.length) {
                    const localRng = mulberry32(domainSeed ^ pixels.length);
                    for (let i = 0; i < pixels.length; i += 4) {
                        if (localRng() < 0.03) {
                            pixels[i] = Math.max(0, Math.min(255, pixels[i] + ((localRng() < 0.5) ? 1 : -1)));
                        }
                    }
                }
            };

        """
    }

    // MARK: - Nivel 3 (Máximo)

    private func timezoneScript() -> String {
        return """
            // TIMEZONE — Forzar UTC (PUEDE ROMPER sitios: calendarios, banca, email)
            const origDateTimeFormat = Intl.DateTimeFormat;
            Intl.DateTimeFormat = function(locale, options) {
                options = Object.assign({}, options, { timeZone: 'UTC' });
                return new origDateTimeFormat(locale, options);
            };
            Intl.DateTimeFormat.prototype = origDateTimeFormat.prototype;
            try {
                Object.defineProperty(Intl.DateTimeFormat, 'name', { value: 'DateTimeFormat' });
            } catch(e) {}

            const origResolvedOptions = Intl.DateTimeFormat.prototype.resolvedOptions;
            Intl.DateTimeFormat.prototype.resolvedOptions = function() {
                const opts = origResolvedOptions.call(this);
                opts.timeZone = 'UTC';
                return opts;
            };

        """
    }

    // MARK: - Anti-detección

    private func antiDetectionScript() -> String {
        return """
            // ANTI-DETECCIÓN — Ocultar que los métodos fueron modificados
            const nativeToString = Function.prototype.toString;
            const spoofedFunctions = new Map();

            function hideOverride(obj, prop, name) {
                const fn = obj[prop];
                if (typeof fn === 'function') {
                    spoofedFunctions.set(fn, 'function ' + (name || prop) + '() { [native code] }');
                }
            }

            Function.prototype.toString = function() {
                if (spoofedFunctions.has(this)) return spoofedFunctions.get(this);
                return nativeToString.call(this);
            };
            spoofedFunctions.set(Function.prototype.toString, 'function toString() { [native code] }');

            hideOverride(CanvasRenderingContext2D.prototype, 'getImageData', 'getImageData');
            hideOverride(HTMLCanvasElement.prototype, 'toDataURL', 'toDataURL');
            hideOverride(HTMLCanvasElement.prototype, 'toBlob', 'toBlob');
            hideOverride(WebGLRenderingContext.prototype, 'getParameter', 'getParameter');
            hideOverride(WebGL2RenderingContext.prototype, 'getParameter', 'getParameter');
            hideOverride(AudioBuffer.prototype, 'getChannelData', 'getChannelData');
            hideOverride(AnalyserNode.prototype, 'getFloatFrequencyData', 'getFloatFrequencyData');
            hideOverride(AnalyserNode.prototype, 'getByteFrequencyData', 'getByteFrequencyData');
            hideOverride(Element.prototype, 'getBoundingClientRect', 'getBoundingClientRect');
            hideOverride(Element.prototype, 'getClientRects', 'getClientRects');

        """
    }

    private func scriptFooter() -> String {
        return """
        })();
        """
    }
}
