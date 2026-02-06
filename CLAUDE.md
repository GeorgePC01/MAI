# MAI Browser - Contexto para Claude

## Resumen del Proyecto

**Nombre:** MAI (Modern AI-Powered Internet Browser)
**Fecha de Creación:** 2026-01-24
**Ubicación:** ~/Documents/MAI
**Estado:** Fase inicial - Estructura y core engine implementados

## ¿Qué es MAI?

MAI es un navegador web moderno, eficiente y modular que estamos desarrollando desde cero para macOS (después Windows/Linux). Está inspirado en la era dorada de Internet Explorer (integración profunda con el OS, rendimiento nativo) pero construido con tecnologías modernas y filosofía open source.

## Motivación

Los navegadores actuales tienen problemas serios:
- **Chrome**: 5.8 GB RAM para uso normal (24 tabs)
- **Arc**: 4.0-4.8 GB RAM (Chromium disfrazado)
- **Safari**: 2.7 GB (mejor, pero lento con Google Meet/ClickUp)
- **DuckDuckGo**: Bug de memory leak (hasta 13.5 GB)

**Decidimos crear uno mejor.**

## Objetivos de Rendimiento

| Métrica | Objetivo MAI | Safari | Chrome | Arc |
|---------|--------------|--------|--------|-----|
| RAM (10 tabs) | **< 1.5 GB** | 2.7 GB | 5.8 GB | 4.8 GB |
| Startup | **< 500ms** | 1.2s | 2.1s | 1.8s |
| Batería | **+30% vs Chrome** | Excelente | Mala | Regular |
| CPU idle | **< 1%** | 2% | 5% | 3% |

## Arquitectura Técnica

**Motor:** WebKit (nativo macOS) - NO Chromium
**Lenguaje:** Swift 5.9+
**UI:** SwiftUI + AppKit (nativo, no Electron)
**ML:** Core ML (local, sin cloud)
**Build:** Swift Package Manager + Makefile
**Plataforma inicial:** macOS 13+ (Ventura)
**Plataformas futuras:** Windows (Win32/WinUI), Linux (GTK)

### Características Clave

1. **Sistema Modular**
   - Core mínimo (~100 MB)
   - Módulos cargables dinámicamente
   - Hot-reload de plugins
   - API de extensiones estándar

2. **Multi-Proceso**
   - Cada tab en proceso separado (como Chrome)
   - Aislamiento de seguridad
   - Crash de tab no afecta el navegador

3. **ML Integrado**
   - Predicción de navegación
   - Pre-fetch inteligente
   - Optimización automática de memoria
   - Detección de phishing
   - Todo local (sin enviar datos a cloud)

4. **Privacidad por Defecto**
   - Ad-blocking nativo
   - Anti-fingerprinting activo
   - DNS over HTTPS
   - Tracking prevention
   - Sin telemetría

5. **Eficiencia**
   - Suspensión agresiva de tabs inactivos
   - Gestión de memoria por prioridad ML
   - Renderizado lazy
   - Cache inteligente

## Estructura del Proyecto

```
MAI/
├── src/
│   ├── core/               # Motor del navegador
│   │   └── BrowserEngine.swift ✅ IMPLEMENTADO
│   ├── main/              # Punto de entrada
│   │   └── main.swift ✅ IMPLEMENTADO
│   ├── rendering/         # WebKit integration (TODO)
│   ├── ui/                # SwiftUI interfaces (TODO)
│   ├── networking/        # HTTP/DNS (TODO)
│   ├── ml/                # Machine Learning (TODO)
│   ├── modules/           # Sistema de módulos (TODO)
│   ├── security/          # Sandboxing (TODO)
│   └── storage/           # Cache, DB (TODO)
├── modules/               # Módulos built-in
│   ├── adblocker/        # Ad-blocking nativo
│   ├── privacy/          # Privacy features
│   ├── translator/       # Traducción in-page
│   ├── reader-mode/      # Modo lectura
│   ├── screenshot/       # Capturas
│   ├── dev-tools/        # DevTools
│   └── extensions-api/   # API extensiones
├── docs/                  # Documentación ✅
│   ├── README.md
│   ├── ARCHITECTURE.md   # Arquitectura técnica detallada
│   ├── MANIFESTO.md      # Visión y filosofía
│   ├── QUICKSTART.md     # Guía de inicio
│   └── TODO.md           # Lista de tareas
├── tests/                 # Tests unitarios (TODO)
├── .github/workflows/     # CI/CD ✅
│   └── ci.yml
├── Package.swift          # Swift package config ✅
├── Makefile              # Build system ✅
├── .gitignore            # ✅
├── LICENSE (MIT)         # Open source ✅
└── CONTRIBUTING.md       # Guía contribución ✅
```

## Estado Actual (2026-01-24)

### ✅ Completado

1. **Estructura del proyecto completa**
   - Directorios organizados
   - Build system (Makefile)
   - Swift Package Manager config
   - Git setup

2. **Core Engine implementado**
   - `BrowserEngine.swift` - Motor principal
   - ModuleManager - Gestión de módulos
   - ResourceManager - Gestión de recursos (stub)
   - ProcessManager - Multi-proceso (stub)
   - 3 módulos stub: AdBlocker, PrivacyShield, ResourceOptimizer

3. **Entry point funcional**
   - `main.swift` con banner ASCII
   - Inicialización del engine
   - Creación de tabs
   - Estadísticas básicas

4. **Documentación completa**
   - README con visión general
   - ARCHITECTURE con diseño técnico
   - MANIFESTO con filosofía
   - QUICKSTART para comenzar
   - TODO con roadmap
   - CONTRIBUTING para colaboradores

5. **Infraestructura**
   - GitHub Actions CI/CD
   - MIT License
   - .gitignore configurado

### ⏳ Por Implementar (Prioridad Alta)

1. **UI SwiftUI**
   - MainWindow
   - TabBar
   - AddressBar
   - WebView wrapper
   - Settings panel

2. **WebKit Integration**
   - WKWebView wrapper
   - Process-per-tab
   - Navigation (forward/back/refresh)
   - Downloads

3. **Módulos Core Funcionales**
   - AdBlocker con filter engine
   - PrivacyShield completo
   - ReaderMode

4. **Navegación Básica**
   - History
   - Bookmarks
   - Downloads manager

## Filosofía del Proyecto

### 1. Eficiencia es Respeto
Consumir menos recursos es respetar el hardware del usuario, su batería, su tiempo y el medio ambiente.

### 2. Privacidad por Defecto
La privacidad no es opcional. Todo tracking/telemetría deshabilitado por defecto.

### 3. Inteligencia, no Complejidad
ML debe simplificar la experiencia, no complicarla. Predicción transparente.

### 4. Nativo es Mejor
No Electron, no web tech. Swift puro para integración profunda con macOS.

### 5. Modular y Extensible
Core mínimo + módulos que el usuario elija. No cargar lo que no se usa.

### 6. Open Source Siempre
MIT License. Transparencia total. Auditable. Sin sorpresas.

## Comandos Principales

```bash
cd ~/Documents/MAI

# Ver ayuda
make help

# Compilar y ejecutar
make run

# Abrir en Xcode
make xcode

# Tests
make test

# Limpiar
make clean

# Estadísticas
make stats
```

## Roadmap

### Fase 1: MVP (Q1-Q2 2026)
- ✅ Estructura del proyecto
- ✅ Core engine básico
- ⏳ UI SwiftUI completa
- ⏳ WebKit integration
- ⏳ 3-5 módulos funcionales
- ⏳ Navegación básica

### Fase 2: Funcionalidades Core (Q3 2026)
- ML integration (Core ML)
- Sistema de módulos completo
- Optimizaciones de performance
- Extension API
- Memory/CPU profiling

### Fase 3: Multiplataforma (Q4 2026)
- Windows port (Win32/WinUI)
- Linux port (GTK/WebKitGTK)
- Sync service
- Extension marketplace

## Contexto de Desarrollo

### Sesión de Creación (2026-01-24)

**Problema inicial:** Usuario tenía problemas de RAM con navegadores
- Chrome: 5.8 GB (24 tabs)
- Investigamos Arc: resultó ser Chromium (4.8 GB)
- Investigamos DuckDuckGo: tiene memory leak (13.5 GB)
- Safari: eficiente (2.7 GB) pero lento con Google Meet/ClickUp

**Decisión:** Crear navegador propio, eficiente, nativo y modular

**Lo que se implementó:**
1. Estructura completa del proyecto
2. Core engine funcional en Swift
3. Sistema de módulos básico
4. Documentación exhaustiva
5. Build system + CI/CD

### Por qué MAI es diferente

**vs Chrome/Arc:**
- NO Chromium (WebKit nativo)
- Objetivo: 74% menos RAM (1.5 GB vs 5.8 GB)
- No telemetría, no tracking

**vs Safari:**
- Más rápido con web apps modernas
- Sistema de módulos extensible
- ML integrado para optimización

**vs DuckDuckGo:**
- Sin memory leaks
- Más maduro (Swift vs fork de WebKit)
- Mejor compatibilidad

**vs Firefox:**
- Nativo (no cross-platform compromises)
- ML local integrado
- Más eficiente en macOS

## Inspiración: Internet Explorer (lo bueno)

MAI toma las mejores ideas de IE sin los errores:

✅ **Tomamos:**
- Integración profunda con el OS
- Rendimiento nativo
- Extensibilidad para desarrolladores
- Simplicidad en UX

❌ **Evitamos:**
- Código propietario
- Vendor lock-in
- Vulnerabilidades por legacy code
- Monopolio

## Notas Técnicas Importantes

### WebKit vs Chromium
- **WebKit**: Más eficiente en macOS, integración nativa
- **Chromium**: Más pesado, pero compatible con todo
- **Decisión**: WebKit primero, mantener arquitectura modular para swap futuro

### ML Local vs Cloud
- **Local (Core ML)**: Privacidad, offline, sin latencia
- **Cloud**: Más potente pero requiere datos
- **Decisión**: 100% local

### Multi-Proceso
- Como Chrome: cada tab es proceso separado
- Ventaja: aislamiento de seguridad
- Desventaja: overhead de memoria
- Mitigación: suspensión agresiva + ML para predicción

## Próximos Pasos Inmediatos

1. **Desarrollar UI en SwiftUI**
   - Crear `src/ui/MainWindow.swift`
   - TabBar con gestión visual
   - AddressBar con auto-completado

2. **Integrar WebKit**
   - Wrapper de WKWebView en `src/rendering/`
   - Gestión de procesos por tab
   - Navigation stack

3. **Implementar AdBlocker**
   - Filter engine con EasyList
   - WKContentRuleList integration
   - Custom rules

4. **Performance Testing**
   - Memory profiling con Instruments
   - Startup time measurement
   - Comparar con Safari/Chrome

## Recursos de Referencia

- Swift Documentation: https://swift.org/documentation/
- WebKit Documentation: https://webkit.org/documentation/
- Core ML Guide: https://developer.apple.com/documentation/coreml
- SwiftUI Tutorials: https://developer.apple.com/tutorials/swiftui

## Lecciones de la Investigación de Navegadores

Durante el desarrollo investigamos todos los navegadores principales:

**Safari:** 2.7 GB RAM, excelente batería, pero problemas con Google Meet/ClickUp (WebRTC limitado, tracking prevention rompe funcionalidad)

**Chrome:** 5.8 GB RAM, 24 procesos renderer, buen rendimiento pero excesivo consumo

**Arc:** 4.0 GB RAM (no 30% menos como dicen), Chromium base, desarrollo discontinuado (equipo se movió a Dia), buena UX pero mismo problema de recursos

**DuckDuckGo:** Memory leak serio (puede llegar a 13.5 GB), Brave usa 31% menos RAM que DuckDuckGo, incompatibilidades con web apps modernas

**Conclusión:** Todos tienen trade-offs. MAI busca lo mejor de cada uno sin los problemas.

---

## Para Claude en futuras sesiones:

**Este es un proyecto activo de desarrollo de navegador web.**

Cuando el usuario mencione "MAI" o navegador:
- Revisa este archivo para contexto completo
- El código está en ~/Documents/MAI/
- Prioriza eficiencia y arquitectura modular
- Sigue los principios de la filosofía MAI
- Consulta ARCHITECTURE.md para decisiones técnicas
- Consulta TODO.md para próximas tareas

**Estado actual:** Core engine funcional, falta UI y WebKit integration.

**Siguiente objetivo:** Implementar MainWindow en SwiftUI.
