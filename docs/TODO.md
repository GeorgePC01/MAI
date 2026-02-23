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
- [x] Banner de videoconferencia con "Abrir en Chrome" (v0.3.1)

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
- [x] Apertura en navegador externo para videoconferencias (v0.3.1)

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
- [x] Anti-detección reducida para compatibilidad con sitios enterprise (v0.3.1)
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

### Compatibilidad y Bugfixes (v0.3.1)
- [x] Fix: about:blank blocking solo para SafeLinks (antes bloqueaba navegación legítima)
- [x] Fix: Navigator spoofing reducido (causaba redirect loops en sitios enterprise como Broadcom)
- [x] Detección de sitios de videoconferencia (Meet, Zoom, Teams)
- [x] ~~Banner "Abrir en Chrome"~~ → Reemplazado por motor Chromium integrado (v0.4.0)

### Motor Híbrido CEF (v0.4.0) ✅
- [x] Integración de Chromium Embedded Framework (CEF 145.0.23, Chromium 145)
- [x] WebKit para navegación general, Chromium solo para Meet/Zoom/Teams
- [x] Auto-detección de dominios de videoconferencia → cambio automático de motor
- [x] Wrapper Objective-C++ (CEFBridge) con API Swift limpia
- [x] CEFWebView NSViewRepresentable para integración SwiftUI
- [x] Helper subprocess para CEF (MAI Helper.app)
- [x] Permisos de media auto-concedidos para videoconferencias
- [x] Indicador "Chromium" en barra cuando el tab usa CEF
- [x] Build system actualizado (Makefile + SPM mixto)
- [ ] Testing screen sharing con iPad Sidecar
- [ ] Optimización de RAM con motor dual activo

### Screen/Window Picker Nativo (v0.4.1) ✅
- [x] Picker nativo con NSAlert + NSPopUpButton (reemplaza picker de Chrome no funcional en embedded mode)
- [x] Enumeración de pantallas y ventanas via ScreenCaptureKit (SCShareableContent)
- [x] Compartir pantalla completa via auto-select flag + real getDisplayMedia()
- [x] Compartir ventanas individuales via SCStream → canvas relay → Meet
- [x] JSDialog handler intercepta window.prompt('MAI_SCREEN_PICKER')
- [x] JS override de navigator.mediaDevices.getDisplayMedia() en sitios de videoconferencia
- [x] Canvas captureStream(5fps) con displaySurface metadata falsa + audio track silencioso
- [x] Captura nativa SCStream a 640x360, 5fps, JPEG 0.3 quality → base64 → executeJavaScript
- [x] Filtrado de ventanas (excluye MAI, ventanas pequeñas, sin título)
- [x] Frameworks: ScreenCaptureKit, CoreMedia, CoreImage vinculados en Package.swift

### CEF con Codecs Propietarios / Teams Screen Sharing (v0.5.0) ✅
- **Problema**: Teams requiere H.264 para screen sharing (VBSS). CEF estándar no incluye H.264.
- **Referencia**: CEF Issue #3910 (confirmado), CEF Issue #3559 (hardware-only via VideoToolbox)
- **Build machine**: Mac Mini 2018, Intel 64GB RAM, macOS 15.7.4, Xcode 16.3
- [x] Compilar CEF branch 7632 con H.264 (proprietary_codecs=true, ffmpeg_branding=Chrome)
- [x] Cross-compilar para ARM64 en Mac Mini Intel (disco KINGSTON 932GB)
- [x] Framework con H.264: OpenH264 encoder + VideoToolbox decoder (311 MB)
- [x] Reemplazar framework en MAI/Frameworks/
- [x] Eliminar JS codec spoofing (H.264 spoof, SDP H.264 removal, setCodecPreferences injection)
- [x] Fix Microsoft auth cookie: UR_FLAG_ALLOW_STORED_CREDENTIALS en on_before_resource_load
- [x] Fix Keychain prompts: --use-mock-keychain re-habilitado
- [x] Popup handler: on_before_popup navega auth URLs in-place (Microsoft, Google, Apple)
- [x] Screen picker restaurado: getDisplayMedia override → prompt('MAI_SCREEN_PICKER') → NSAlert
- [x] Todas pantallas (MacBook + Sidecar/iPad) y ventanas disponibles en picker
- [x] Dominio teams.cloud.microsoft agregado a detección
- [x] Screen sharing funcional en Teams (H.264 VBSS) y Meet
- [ ] Medir impacto en RAM con nuevo framework
- [ ] Optimizar calidad de canvas relay (VideoFrame API futuro)

## Fase 1.5: Preparación para Lanzamiento (Q2 2026)

### Modelo de Negocio (Freemium)

**Versión Gratuita (Free):**
- Navegación WebKit completa (tabs, favoritos, historial, descargas)
- Privacidad (tracker/ad blocking)
- Find in page, multi-ventana
- Tab suspension manual

**Versión Pro (Pago):**
- [ ] Motor híbrido CEF (videoconferencias Meet/Zoom/Teams)
- [ ] Screen/window sharing HD (VideoFrame API - sin doble compresión)
- [ ] Gestor de contraseñas (macOS Keychain)
- [ ] Tab suspension inteligente (ML)
- [ ] Detección de phishing
- [ ] Soporte prioritario

### Calidad HD de Screen Sharing (Pro)
- [ ] VideoFrame API: eliminar canvas intermediario, inyectar frames directamente
- [ ] WebSocket binario: eliminar overhead base64 (33% menos datos)
- [ ] Calidad nativa: compresión única VP9 (igual que Chrome)
- [ ] Estimación de esfuerzo: 3-5 días

### Lanzamiento
- [ ] Landing page (sitio web con demo/screenshots)
- [ ] Apple Developer Account ($99/año)
- [ ] Notarización de la app
- [ ] Procesador de pagos (Stripe o Paddle)
- [ ] Beta pública (TestFlight o descarga directa)
- [ ] App Store (post-beta)

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
| RAM promedio | ~167 MB WebKit / ~400 MB con CEF |
| Archivos Swift | 14 |
| Archivos ObjC++ | 2 |
| Líneas de código | ~6,300+ |
| CEF Framework | 311 MB (Chromium 145 + H.264) |

---

**Última actualización: 2026-02-23 (v0.5.0)**
