# TODO List - MAI Browser

## Fase 1: MVP (Q1-Q2 2026)

### Core Engine ✅
- [x] Estructura del proyecto
- [x] BrowserEngine básico
- [x] ProcessManager (WKWebView maneja esto)
- [x] ResourceManager con mediciones reales (memoria/CPU)
- [ ] Event bus para comunicación

### UI ✅ (Completado)
- [x] MainWindow SwiftUI
- [x] TabBar con gestión de pestañas
- [x] AddressBar con navegación
- [x] WebView integration (WKWebView)
- [x] Context menus (JavaScript alerts/confirms)
- [x] Settings panel completo
- [x] Sidebar (Favoritos/Historial/Descargas)
- [x] Barra de estado con estadísticas
- [x] Multi-ventana (Cmd+N) con WindowManager (v0.3.0)

### Navegación ✅
- [x] Navegación básica (forward/back)
- [x] Refresh/Stop
- [x] Zoom (in/out/reset)
- [x] Historial funcional con persistencia
- [x] Keyboard shortcuts (Cmd+Y, Cmd+J, Cmd+B, Cmd+D, etc.)
- [x] Bookmarks manager con persistencia (v0.2.0)
- [x] Downloads manager funcional (v0.2.1)
- [x] Buscar en página (Cmd+F) (v0.2.1)
- [x] File upload / Open Panel para subir archivos (v0.3.0)

### Seguridad y OAuth ✅
- [x] Cookies persistentes entre sesiones
- [x] Soporte OAuth (Google, Microsoft, etc.)
- [x] Whitelist de dominios OAuth
- [x] Autenticación HTTP básica
- [x] Manejo de certificados HTTPS
- [x] JavaScript prompts (alert, confirm, prompt)
- [x] OAuth popup windows (Claude, Google, etc.) (v0.2.1)
- [x] Permisos cámara/micrófono (v0.2.1)
- [x] Microsoft SafeLinks support (v0.2.1)
- [ ] Passkeys/WebAuthn (requiere Apple Developer)

### Privacidad ✅
- [x] PrivacyManager con configuración
- [x] Bloqueo de trackers (40+ dominios)
- [x] Bloqueo de ads
- [x] Whitelist OAuth (no bloquea login)
- [x] Contador de requests bloqueadas
- [x] Toggles en Settings
- [ ] Fingerprinting protection (diseñado, no implementado)
- [ ] DNS over HTTPS (configuración existe)

### Módulos Core
- [x] AdBlocker básico (integrado en PrivacyManager)
  - [x] Lista de dominios bloqueados
  - [x] Whitelist para OAuth
  - [ ] EasyList integration
  - [ ] Custom rules UI
- [x] PrivacyShield básico
  - [ ] Anti-fingerprinting activo
  - [x] Cookie management
  - [x] Tracking prevention
- [ ] ReaderMode
  - [ ] Article detection
  - [ ] Clean layout
  - [ ] Font/size controls
- [x] Buscar en página (Cmd+F) (v0.2.1)

## Fase 2: Funcionalidades Core (Q3 2026)

### ML Integration
- [ ] Core ML model setup
- [ ] Navigation prediction
- [ ] Resource optimization
- [ ] Phishing detection
- [ ] Auto-categorization

### Performance
- [x] Memory profiling básico
- [x] CPU monitoring básico
- [ ] Startup optimization
- [ ] Lazy loading de tabs
- [x] Tab suspension manual (v0.2.1)
- [ ] Tab suspension automática (ML)

### Networking
- [ ] HTTP/3 support
- [ ] DNS over HTTPS implementation
- [ ] Smart caching
- [ ] Offline mode

### Extensions
- [ ] Extension API design
- [ ] Manifest parsing
- [ ] Permission system
- [ ] Extension store (basic)

## Fase 3: Multiplataforma (Q4 2026)

### Windows Port
- [ ] Win32/WinUI implementation
- [ ] WebView2 integration
- [ ] Windows-specific optimizations

### Linux Port
- [ ] GTK interface
- [ ] WebKitGTK integration
- [ ] Package distribution (deb/rpm)

### Cross-Platform
- [ ] Shared core logic
- [ ] Platform abstraction layer
- [ ] Unified build system

## Distribución y Negocio

### Licenciamiento ✅
- [x] Análisis de costos (ver docs/LICENSING.md)
- [x] Apple Developer Program ($99/año = suficiente)
- [ ] Obtener cuenta Apple Developer
- [ ] Configurar firma de código
- [ ] Notarización para distribución

### Lanzamiento
- [ ] Sitio web
- [ ] Modelo de precios
- [ ] Procesador de pagos (Stripe/Paddle)
- [ ] Beta pública

## Futuro

### Advanced Features
- [ ] Tab groups
- [ ] Profiles
- [ ] Sync service
- [ ] PWA support
- [ ] Dark mode themes
- [ ] Accessibility improvements

### Community
- [ ] Public beta
- [ ] Extension marketplace
- [ ] Documentation site
- [ ] Video tutorials
- [ ] Community forum

---

## Estadísticas del Proyecto

| Métrica | Valor |
|---------|-------|
| RAM promedio | ~167 MB (vs Chrome 2.5+ GB) |
| Archivos Swift | 12 |
| Líneas de código | ~2,500 |

---

**Última actualización: 2026-02-15**
