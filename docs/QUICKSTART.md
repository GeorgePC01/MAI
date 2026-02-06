# Guía Rápida - MAI Browser

## Requisitos

- macOS 13+ (Ventura o superior)
- Xcode 15+
- Swift 5.9+

## Instalación

```bash
cd ~/Documents/MAI

# Ver comandos disponibles
make help

# Compilar en modo debug
make build-debug

# Ejecutar
make run
```

## Estructura del Proyecto

```
MAI/
├── src/                    # Código fuente
│   ├── main/              # Punto de entrada
│   ├── core/              # Motor del navegador
│   ├── rendering/         # WebKit integration
│   ├── ui/                # SwiftUI interfaces
│   ├── networking/        # HTTP/DNS
│   ├── ml/                # Machine Learning
│   ├── modules/           # Sistema de módulos
│   ├── security/          # Sandboxing
│   └── storage/           # Cache, DB
├── modules/               # Módulos built-in
│   ├── adblocker/
│   ├── privacy/
│   └── ...
├── docs/                  # Documentación
├── tests/                 # Tests
└── Package.swift          # Swift package config
```

## Primeros Pasos

### 1. Explorar el código

```bash
# Ver el motor principal
cat src/core/BrowserEngine.swift

# Ver el punto de entrada
cat src/main/main.swift
```

### 2. Compilar y ejecutar

```bash
make run
```

Verás:
```
███╗   ███╗ █████╗ ██╗
████╗ ████║██╔══██╗██║
██╔████╔██║███████║██║
██║╚██╔╝██║██╔══██║██║
██║ ╚═╝ ██║██║  ██║██║
╚═╝     ╚═╝╚═╝  ╚═╝╚═╝

🚀 Inicializando MAI Browser Engine...
  ✓ WebKit configurado
  ✓ Módulos core registrados: 3
    → AdBlocker v1.0.0 inicializado
    → PrivacyShield v1.0.0 inicializado
    → ResourceOptimizer v1.0.0 inicializado
  ✓ ML engine inicializado
  ✓ Networking configurado
✅ MAI Browser Engine inicializado
```

### 3. Desarrollar en Xcode

```bash
make xcode
```

Esto genera `MAI.xcodeproj` que puedes abrir en Xcode.

## Crear un Módulo

### Ejemplo: Módulo de Screenshots

```bash
# 1. Crear archivo
touch modules/screenshot/ScreenshotModule.swift
```

```swift
// modules/screenshot/ScreenshotModule.swift
import Foundation

struct ScreenshotModule: MAIModule {
    let name = "Screenshot"
    let version = "1.0.0"

    func initialize(context: BrowserContext) {
        print("    → \(name) v\(version) inicializado")
        // Setup screenshot functionality
    }

    func onKeyboardShortcut(_ shortcut: KeyboardShortcut) {
        if shortcut == .screenshot {
            takeScreenshot()
        }
    }

    private func takeScreenshot() {
        // TODO: Implement screenshot logic
        print("📸 Screenshot taken!")
    }

    func cleanup() {
        // Cleanup resources
    }
}
```

### 2. Registrar el módulo

En `src/core/BrowserEngine.swift`:

```swift
private func registerCoreModules() {
    moduleManager.register(AdBlockerModule())
    moduleManager.register(PrivacyShieldModule())
    moduleManager.register(ResourceOptimizerModule())
    moduleManager.register(ScreenshotModule())  // ← Nuevo
}
```

### 3. Compilar y probar

```bash
make run
```

## Tests

```bash
# Ejecutar todos los tests
make test

# Ejecutar un test específico
swift test --filter BrowserEngineTests
```

## Debugging

### Xcode
1. `make xcode`
2. Abrir `MAI.xcodeproj`
3. Poner breakpoints
4. Run (Cmd+R)

### Console
```bash
# Compilar con símbolos de debug
make build-debug

# Ejecutar con lldb
lldb .build/debug/MAI
(lldb) run
```

## Estructura de un Módulo Completo

```
modules/adblocker/
├── AdBlockerModule.swift    # Implementación principal
├── FilterEngine.swift        # Motor de filtros
├── Rules/                    # Reglas de bloqueo
│   ├── easylist.txt
│   └── custom.txt
└── Tests/
    └── AdBlockerTests.swift
```

## Comandos Útiles

```bash
# Limpiar build
make clean

# Ver estadísticas del proyecto
make stats

# Formatear código
make format

# Generar documentación
swift package generate-documentation
```

## Próximos Pasos

1. **Leer documentación**
   - `docs/ARCHITECTURE.md` - Arquitectura técnica
   - `docs/MANIFESTO.md` - Visión del proyecto

2. **Implementar funcionalidades**
   - [ ] UI básica con SwiftUI
   - [ ] Tab management
   - [ ] Address bar
   - [ ] Bookmarks
   - [ ] History

3. **Optimizar**
   - [ ] Memory profiling
   - [ ] CPU profiling
   - [ ] Startup time

4. **Integrar ML**
   - [ ] Core ML models
   - [ ] Navigation prediction
   - [ ] Resource optimization

## Recursos

- [Swift Documentation](https://swift.org/documentation/)
- [WebKit Documentation](https://webkit.org/documentation/)
- [Core ML Guide](https://developer.apple.com/documentation/coreml)
- [SwiftUI Tutorials](https://developer.apple.com/tutorials/swiftui)

## Contribuir

1. Fork el proyecto
2. Crea una branch (`git checkout -b feature/amazing`)
3. Commit cambios (`git commit -m 'Add amazing feature'`)
4. Push (`git push origin feature/amazing`)
5. Abre un Pull Request

## Problemas Comunes

### Error: "Cannot find 'BrowserEngine'"

**Solución**: Asegúrate de que la estructura de directorios coincida con `Package.swift`

### Error de compilación en Xcode

**Solución**:
```bash
make clean
make xcode
```

### Tests fallan

**Solución**: Verifica que todos los módulos estén correctamente implementados

## Soporte

- GitHub Issues: [Crear issue](https://github.com/tu-usuario/MAI/issues)
- Discussions: [Iniciar discusión](https://github.com/tu-usuario/MAI/discussions)

---

**¡Feliz desarrollo! 🚀**
