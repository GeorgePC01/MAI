# MAI Browser — Changelog Maestro

Registro completo de cada versión con detalle técnico para continuidad entre sesiones.

---

## Roadmap v1.0 — Features por Implementar

Investigación de mercado (2025-2026): features que usuarios piden y ningún browser resuelve bien.

| # | Feature | Esfuerzo | Impacto | Estado |
|---|---------|----------|---------|--------|
| 1 | **Auto-rechazo cookie banners + GPC** | Medio | Muy Alto | ✅ v0.9.1 |
| 2 | **Búsqueda full-text en historial** | Medio | Muy Alto | ✅ v0.9.1 |
| 3 | **Workspaces con contextos aislados** | Alto | Muy Alto | ✅ v0.9.2 |
| 4 | **Traducción de páginas** | Medio | Alto | ✅ v0.9.2 |
| 5 | **Animación + sonido al cerrar tab ML** | Bajo | Medio | ✅ v0.9.2 |
| 6 | **Sesiones crash-proof** | Bajo | Alto | ✅ v0.9.3 |
| 7 | **Anotaciones web nativas** | Medio | Alto | ⏳ |
| 8 | **Modo Focus** | Bajo | Alto | ⏳ |
| 9 | **Screenshot página completa** | Bajo | Medio | ⏳ |
| 10 | **Smart Bookmarks** (auto-tags, dead links) | Medio | Alto | ⏳ |
| 11 | **Split View** | Medio | Medio | ⏳ |
| 12 | **Anti-fingerprinting real** | Alto | Alto | ✅ v0.9.3 |
| 13 | **Tab intelligence** (duplicados, auto-archive, búsqueda) | Bajo | Medio | ✅ v0.9.3 |
| 14 | **Data portability** (export JSON/SQLite) | Bajo | Medio | ✅ v0.9.3 |
| 15 | **PDFs → Preview.app** (no renderizar in-browser) | Bajo | Medio | ✅ v0.9.2 |

---

## Roadmap v2.0 — MAI Ads: Publicidad Inversa

**Concepto**: Invertir el modelo publicitario de internet. En vez de forzar ads al usuario, las empresas pagan al usuario por ver publicidad relevante.

### El Problema Actual
Las empresas pagan a Google/YouTube → Ads forzados al usuario → Usuario molesto → Instala ad blocker → La empresa pierde dinero → El creador de contenido pierde ingresos → Nadie gana.

### La Solución MAI
Las empresas pagan a MAI → MAI paga al usuario por ver ads → El usuario decide qué tipo de publicidad ver → Ads basados en intereses reales (no espionaje) → Mejor conversión para empresas → Todos ganan.

### Principios Clave

1. **Consentimiento real**: El usuario ELIGE activar MAI Ads y decide qué categorías de interés le gustan. Nunca se impone publicidad.
2. **Targeting ético**: Basado en intereses declarados por el usuario, NO en tracking invasivo, cookies de terceros ni fingerprinting. El usuario controla su perfil.
3. **Publicidad proporcional**: Ads más agresivos (largos, intrusivos) = la empresa paga MÁS al usuario. Esto incentiva ads cortos, creativos y de calidad.
4. **Dinero real**: Pagos en dinero real (PayPal, transferencia bancaria, créditos en tiendas), no criptomonedas confusas.
5. **Transparencia total**: El usuario ve exactamente cuánto paga cada empresa, qué datos se comparten (solo categorías de interés, nunca historial), y puede desactivarlo en cualquier momento.

### Modelo de Negocio

| Participante | Beneficio |
|---|---|
| **Usuario** | Gana dinero por ver ads que le interesan. Controla sus datos. |
| **Empresa/Anunciante** | Mejor ROI: audiencia interesada = mayor conversión. Sin ad blockers. |
| **Creador de contenido** | Ingresos más estables (usuarios no bloquean, las empresas pagan más por targeting real). |
| **MAI** | Comisión del 20-30% por intermediar. Modelo sostenible sin vender datos. |

### Diferenciador vs Brave
Brave usa BAT (crypto tokens): volátil, confuso, difícil de convertir, requiere wallet crypto. MAI usa dinero real, interfaz simple, sin blockchain.

### Features Planificados

| # | Feature | Prioridad |
|---|---------|-----------|
| A1 | **Panel de usuario MAI Ads** — activar/desactivar, elegir categorías de interés, ver ganancias | Alta |
| A2 | **Dashboard de anunciante** — subir ads, elegir audiencia por interés, establecer presupuesto, métricas | Alta |
| A3 | **Sistema de pagos** — acumulación de saldo, retiro via PayPal/transferencia, historial | Alta |
| A4 | **Ad delivery engine** — mostrar ads relevantes en momentos no intrusivos (nueva pestaña, entre videos) | Media |
| A5 | **Scoring de calidad de ads** — usuarios califican ads, los mejores pagan menos, los peores pagan más | Media |
| A6 | **API para anunciantes** — integración programática para campañas a escala | Baja |
| A7 | **Reportes de impacto** — cuánto ganó el usuario, cuánto ahorró la empresa vs Google Ads | Baja |

### Fases de Implementación
- **Fase 1**: Backend + panel de usuario + integración básica en el navegador
- **Fase 2**: Dashboard de anunciante + sistema de pagos + primeros anunciantes beta
- **Fase 3**: API pública + scoring + escala

---

### Decisiones
- **PDFs**: No renderizar en browser. Detectar → descargar a /tmp → abrir con Preview.app (NSWorkspace). Cero overhead.
- **v1.0**: Features 1-6 + landing page + notarización = listo para público
- **v2.0**: MAI Ads — modelo de publicidad inversa (requiere backend, pagos, panel anunciantes)
- **Versioning**: +0.0.1 por sesión/feature, v1.0 para release público, v2.0 para MAI Ads

---

## v0.9.4 (2026-03-10) — DevTools Profesional Completo + CEF Crash Fix + CDP Debugger

### CEF Crash Fix (macOS 26.3.1)
- **Root cause**: `SwiftUI.AppKitApplication` (subclase de NSApplication) no implementa `-isHandlingSendEvent` que Chromium llama internamente
- **Fix**: `class_addMethod` inyecta `isHandlingSendEvent` → `NO` en runtime antes de crear cualquier browser CEF
- **Safety net**: Signal handler `setjmp/longjmp` para SIGTRAP/SIGABRT dentro de `cef_do_message_loop_work()` — si CEF crashea internamente, la app sobrevive
- **Browser generation counter**: `g_browserGeneration` previene que bloques `dispatch_async` de sesiones antiguas ejecuten con estado nuevo
- **Exception logger**: `NSSetUncaughtExceptionHandler` escribe detalles a `/tmp/mai_exception.log`

### CDP JS Debugger (Chrome DevTools Protocol)
- **CDPManager.swift**: Singleton que usa `send_dev_tools_message` + `add_dev_tools_message_observer` de CEF C API
- **Breakpoints reales**: `Debugger.setBreakpointByUrl` con línea y columna
- **Step debugging**: stepOver, stepInto, stepOut, resume via CDP
- **Scope inspection**: Variables locales y de closure en cada paused frame
- **Solo CEF tabs**: Funciona exclusivamente en tabs Chromium (Meet, Zoom, Teams)

### Chrome Light Theme
- Nuevo theme `.chromeLight` con ~30 propiedades de color (fondo blanco, texto oscuro, syntax highlighting apropiado)
- Theme por defecto cambiado a Chrome Light
- `var isDark: Bool { self != .chromeLight }` controla colorScheme condicional

### Dock Lateral + Drag Handle
- DevTools dockable lateral ocupa 54% del ancho de ventana (igual que Chrome)
- GeometryReader con `@State containerSize` (no `@Published` — evita render loop infinito)
- Drag handle offset-based: durante arrastre solo mueve línea visual via `.offset()`, aplica tamaño real en `.onEnded`
- `clampedOffset` + `.zIndex(100)` evitan que el handle desaparezca o se pierda
- Indicador de tamaño en px y % durante arrastre

### Console REPL (ejecutar JavaScript)
- `eval()` wrapper completo: maneja Promises, DOM nodes, NodeList, functions con serialización
- Niveles `.input` (› azul) y `.output` (← gris) diferenciados visualmente
- `escapeForJS()` helper para strings seguros

### Performance Panel (NUEVO)
- Summary: score circle, Core Web Vitals (FCP, LCP, Load), timing breakdown bars
- Timeline: resource bars coloreados por tipo (script, style, image, font, etc.)
- Resources: conteo por tipo + top 10 más lentos
- DOM stats: nodos, profundidad, listeners, memoria
- Recomendaciones automáticas

### Memory Panel (NUEVO)
- Heap snapshots: captura DOM nodes, detached nodes, event listeners, timers, iframes
- IDs duplicados, nodos más grandes, leak warnings automáticos
- Comparación de snapshots con delta cards (verde/rojo)
- Health score visual

### Network Throttling
- `NetworkThrottleProfile` enum: None, Fast 3G, Slow 3G, Offline, Custom
- Intercepta fetch/XHR con setTimeout para simular latencia
- Banner de advertencia cuando throttling activo

### Lighthouse Auditorías (NUEVO)
- 4 categorías × 8 audits = 32 auditorías totales
- **Performance**: FCP, load time, TTFB, DOM ready, recursos, render-blocking, DOM size, imágenes sin dimensiones
- **Accesibilidad**: alt text, labels, lang, headings, H1 único, contraste, landmarks ARIA, tabindex
- **Best Practices**: HTTPS, errores consola, doctype, charset, HTML deprecado, viewport, mixed content, noopener
- **SEO**: título, meta description, canonical, H1, link text, Open Graph, robots, mobile-friendly
- Score circles por categoría con colores (verde/naranja/rojo)

### Device Emulation (NUEVO)
- 7 perfiles: iPhone 14, iPhone 14 Pro Max, iPad Air, iPad Pro, Pixel 7, Galaxy S23, Responsive
- Inyección JS: viewport meta + CSS override + `Object.defineProperty` screen/window + UA spoofing + touch events
- Toggle landscape/portrait

### Pendiente (requiere CDP)
- **JS Debugger con breakpoints**: único feature del gap analysis que requiere Chrome DevTools Protocol real, no simulable con JavaScript injection

---

## v0.9.3 (2026-03-09) — Sesiones Crash-Proof, Anti-Fingerprinting, Password Manager, DevTools, Data Portability

### Sesiones Crash-Proof (SessionManager.swift — NUEVO)
- **Guardado automático**: Cada 30s + al completar cada navegación (`didFinish`) + al cerrar la app (`applicationWillTerminate`)
- **Banner de restauración**: Al iniciar, banner azul "¿Restaurar N pestañas?" con botones "Restaurar" / "Descartar" (estilo Chrome)
- **Multi-ventana**: Guarda y restaura tabs de ventana principal + ventanas adicionales de WindowManager
- **Privacidad**: Excluye tabs y ventanas incógnito del guardado
- **Expiración**: Sesión válida máximo 7 días
- **Setting**: Preferencias → Sesión → "Restaurar pestañas al iniciar" (activado por defecto)
- **Archivo**: `~/Library/Application Support/MAI/session.json`

### Diálogo CEF de Reuniones Simultáneas (BrowserState.swift)
- **Problema**: Al abrir Teams mientras Meet estaba activo, se reemplazaba silenciosamente el tab
- **Solución**: Diálogo con 3 opciones claras sin jerga técnica:
  - "Reemplazar reunión" — cierra la actual, abre nueva con experiencia completa
  - "Abrir en modo nativo" — mantiene reunión actual, abre nueva con audio/video (WebKit)
  - "Cancelar"
- **Fix loop infinito**: Flag `forceWebKit` en Tab evita re-detección en BrowserState.navigate() y WebViewContainer.decidePolicyFor()
- **Investigación**: Usuarios sí necesitan múltiples reuniones (monitoreo pasivo, solapamiento). Google Meet y Zoom lo permiten nativamente.

### Navegación con Teclado en Sugerencias (AddressBar.swift)
- **Problema**: Flechas arriba/abajo no funcionaban para navegar sugerencias en URL bar
- **Causa raíz**: NSTextField en modo edición delega al field editor (NSTextView interno) que captura las flechas para mover el cursor de texto. `keyDown` del NSTextField nunca se ejecutaba.
- **Fix**: Interceptar en `control(_:textView:doCommandBy:)` del delegate — captura `moveDown:`, `moveUp:`, `cancelOperation:` (escape)

### Phishing Detector — Whitelist Dominios Seguros (PhishingDetector.swift)
- **Problema**: `statics.teams.cdn.live.net` marcado como sospechoso (falso positivo por "exceso de subdominios")
- **Fix**: Lista de ~25 dominios legítimos (Microsoft CDNs, Google, Zoom, Apple, Cloudflare) que usan muchos subdominios por diseño
- **Método**: `isKnownSafeDomain()` verifica suffix match, bypass completo del análisis heurístico

### MeetingIndicator Sutil (BrowserView.swift)
- **Antes**: `ChromiumEngineIndicator` — barra grande con texto técnico "Motor Chromium activo"
- **Ahora**: `MeetingIndicator` — punto verde + "Reunión activa — [servicio]" + botón "Cerrar al terminar"
- **Método estático**: `BrowserState.videoConferenceServiceName(for:)` para resolución de nombres sin instancia

### Anti-Fingerprinting Real (AntiFingerprintManager.swift — NUEVO)
- **3 niveles de protección**: Standard, Strong, Maximum
- **12 vectores protegidos**: Canvas, WebGL, Audio, Navigator, Screen, Fonts, MediaDevices, Speech, WebGPU, ClientRects, Connection API, Battery
- **Farbling determinístico**: Seed de sesión (UInt32.random) + PRNG Mulberry32 por dominio — misma huella por sesión+dominio, diferente entre sesiones
- **Anti-detección**: Function.prototype.toString spoofing para que los overrides parezcan nativos
- **Integración**: WKUserScript inyectado en `documentStart`, allFrames, via `WebViewContainer.createConfiguration()`
- **Settings**: Picker con 4 opciones (Desactivado/Estándar/Fuerte/Máximo) + descripción del nivel

### Tab Intelligence (BrowserState.swift)
- **Detectar duplicados**: `findDuplicateTabs()` — normaliza URLs (quita trailing slash, fragmentos, www) y agrupa por URL
- **Cerrar duplicados**: `closeDuplicateTabs()` — mantiene el tab más reciente, cierra los demás
- **Búsqueda de tabs**: `searchTabs(query:)` — busca en título y URL, case-insensitive
- **Normalización**: `normalizeURL()` — quita esquema, www, trailing slash, fragmentos para comparación
- **UI**: Click derecho en tab → "Cerrar Tabs Duplicadas" con ícono `doc.on.doc`

### Data Portability (DataPortabilityManager.swift — NUEVO)
- **Export bookmarks JSON**: Array de `BookmarkEntry` con título, URL, fecha
- **Export bookmarks HTML**: Formato Netscape (compatible Chrome/Firefox/Safari import)
- **Import bookmarks HTML**: Parsea `<DT><A HREF="...">` del formato Netscape estándar
- **Export historial JSON**: Array de `HistoryEntry` con URL, título, fecha, frecuencia
- **Export todo**: JSON combinado con bookmarks + historial + workspaces
- **Settings**: Sección "Portabilidad de Datos" con botones de export/import y NSSavePanel/NSOpenPanel

### Password Manager (PasswordManager.swift — NUEVO)
- **Almacenamiento**: macOS Keychain (Security framework) con `kSecClassInternetPassword`
- **Captura automática**: JS intercepta `submit` en forms con campos de password → `window.webkit.messageHandlers`
- **Banner "¿Guardar contraseña?"**: Barra naranja con botones Guardar/No, se muestra tras detectar credenciales
- **Auto-fill**: JS inyecta username/password en campos de login con `dispatchEvent(new Event('input'))` para React/Vue
- **Detección de login**: Script detecta si la página tiene formulario de login para trigger auto-fill
- **CRUD**: save, get (por host), getAll, delete, deleteAll via SecItem* APIs
- **Privacidad**: Skip completo en modo incógnito
- **Settings**: Toggle + contador de contraseñas guardadas

### DevTools (MAIApp.swift + BrowserView.swift + WebViewContainer.swift)
- **Menú "Desarrollo"**: Nuevo menú en barra de la app con 3 opciones
- **Consola JavaScript (Cmd+Option+J)**: `JSConsoleView` — panel interactivo para ejecutar JS en el tab actual
  - Input con campo de texto + botón Ejecutar
  - Historial de comandos y resultados con scroll
  - Ejecuta vía `webView.evaluateJavaScript()` en el WKWebView activo
- **Inspeccionar Elemento (Cmd+Option+I)**: Abre la Consola JavaScript (WKWebView no expone Inspector programáticamente)
- **Ver Código Fuente (Cmd+Option+U)**: Obtiene HTML con `document.documentElement.outerHTML`, genera página con tema oscuro y syntax highlighting, abre en nuevo tab MAI (no en app externa)
- **isInspectable**: `webView.isInspectable = true` (macOS 13.3+) permite conexión de Safari Web Inspector

### Doble Click para Maximizar (MAIApp.swift)
- **Problema**: Con `titlebarAppearsTransparent` y contenido fullSize, doble click en titlebar no maximizaba
- **Fix**: Monitor local de eventos `NSEvent.addLocalMonitorForEvents` detecta doble click en zona superior (38px)
- **Respeta preferencia del sistema**: `AppleActionOnDoubleClick` — zoom o minimize según configuración del usuario

---

## v0.9.2 (2026-03-09) — Google Suggest, Translation, ML Banner Animation, PDFs → Preview

### Google Suggest Mejorado (AddressBar.swift)
- **Endpoint**: Cambiado de `client=chrome-omni` (8 resultados) a `client=chrome` (15 resultados) — mismo que Chrome real
- **Más sugerencias**: Dropdown muestra hasta 10 resultados (antes 8)
- **NAVIGATION display**: URLs directas (linkedin.com, yahoo.com) muestran dominio limpio como título

### Animación + Sonido en Banner ML (BrowserView.swift)
- **Sonido**: `NSSound.beep()` al aparecer el banner de suspensión
- **Pulse ícono**: 3 pulsos de escala (1.0 → 1.3) en el ícono del cerebro
- **Glow borde**: Borde naranja que pulsa 2 veces y se desvanece
- **Reset**: Animaciones se resetean después de 1.8s

### Traducción de Páginas (TranslationManager.swift — NUEVO)
- **API**: Google Translate endpoint gratuito (`translate.googleapis.com/translate_a/single?client=gtx`, sin API key)
- **Detección automática**: Extrae 500 chars de texto visible → detecta idioma → muestra banner azul si es diferente al target
- **Traducción batch**: Recolecta nodos de texto DOM → traduce en batches de 20 → reemplaza in-place preservando HTML
- **30 idiomas**: es, en, fr, de, it, pt, ja, ko, zh, ru, ar, hi, nl, pl, tr, sv, da, no, fi, el, he, th, vi, id, ms, uk, cs, ro, hu, ca
- **Banner**: Barra azul "Página en [idioma] — Traducir a [target]" con ProgressView durante traducción
- **Settings**: Toggle habilitar, selector idioma target, contador páginas traducidas
- **Atajo**: Cmd+Shift+T para traducir manualmente
- **Reset**: Estado se resetea al cambiar de tab (BrowserState.selectTab)
- **Archivos**: TranslationManager.swift (nuevo), WebViewContainer.swift, BrowserView.swift, SettingsView.swift, MAIApp.swift, BrowserState.swift

### PDFs → Preview.app (WebViewContainer.swift)
- **Intercepta** `application/pdf` en `decidePolicyFor navigationResponse`
- **Descarga** a `/tmp` con `URLSession` (no renderiza in-browser)
- **Abre** con `NSWorkspace.shared.open()` → Preview.app por defecto
- **Cancela** navegación en browser (cero overhead de memoria)

### Workspaces con Contextos Aislados (WorkspaceManager.swift — NUEVO)
- **Data store**: `WKWebsiteDataStore(forIdentifier: uuid)` (macOS 14+) — cookies, cache, localStorage completamente aislados por workspace
- **Modelo**: `Workspace` (Codable) con id, name, colorHex, icon (SF Symbol)
- **Persistencia**: JSON en `~/Library/Application Support/MAI/workspaces.json`
- **UI**: `WorkspaceBar` con chips de color encima del TabBar, click abre ventana con ese workspace
- **Crear**: Sheet con nombre, selector 8 colores, selector 12 íconos
- **Editar/Eliminar**: Click derecho en chip, workspace "Personal" no eliminable
- **Título ventana**: "MAI Browser — [Workspace Name]"
- **Integración**: BrowserState.workspaceID → WebViewConfigurationManager.createConfiguration(workspaceID:)
- **Fallback macOS 13**: Organización visual sin aislamiento real
- **Archivos**: WorkspaceManager.swift (nuevo), BrowserState.swift, WebViewContainer.swift, BrowserView.swift, MAIApp.swift

### Archivos modificados
- `AddressBar.swift`: client=chrome, 10 resultados, NAVIGATION display
- `BrowserView.swift`: SuspensionBanner con animación pulse + glow + sonido
- `WebViewContainer.swift`: PDF intercept + openPDFInPreview()

---

## v0.9.0 (2026-03-08) — URL Suggestions, Tab Tear-off/Merge, Crash Recovery

### URL Autocomplete (AddressBar.swift)
- **Dropdown de sugerencias** con 3 fuentes: bookmarks (estrella amarilla), historial (reloj gris), Google Suggest (lupa azul)
- **Endpoint Chrome real**: `www.google.com/complete/search?client=chrome-omni` (mismo que Chrome Omnibox)
- **Encoding fix**: Fallback Latin-1 → UTF-8 (Google devuelve ñ como 0xF1 con hl=es, rompía JSONSerialization)
- **Idioma dinámico**: `Locale.current.language.languageCode` en vez de hardcoded `hl=es`
- **Relevance sorting**: Usa `google:suggestrelevance` scores de Google para ordenar
- **CALCULATOR support**: Detecta tipo CALCULATOR (ej: `sqrt(144)` → `= 12`)
- **Staleness fix**: Guard original (`urlText == query`) rechazaba resultados al escribir rápido; relajado a prefix match + Task cancellation
- **Dropdown clipping fix**: Cambiado de ZStack a `.overlay(alignment: .top)` + `AddressBar.zIndex(50)` en BrowserView para que el dropdown se dibuje encima del contenido web sin recortarse
- **Google Suggest API**: `suggestqueries.google.com/complete/search?client=chrome&q=...&hl=es`
  - Debounce 200ms con Task cancellation
  - Parsea `google:suggesttype` para distinguir NAVIGATION (URLs directas) vs QUERY (búsquedas)
  - Deshabilitado en modo incógnito por privacidad
  - **Bug fix**: Guard de staleness original (`urlText == query`) rechazaba resultados cuando el usuario escribía más rápido que el debounce. Relajado a prefix match + confianza en Task cancellation.
- **Keyboard navigation**: Flechas arriba/abajo navegan sugerencias, Enter selecciona, Escape cierra
- **AddressTextField** (NSViewRepresentable): `KeyInterceptingTextField` subclase NSTextField que intercepta keyCode 125/126/53
- **Deduplicación**: Set<String> por URL lowercased, máximo 8 sugerencias
- **Focus**: Click en barra activa app + resigna foco de WKWebView + delay 150ms para isFocused

### Tab Drag & Drop / Tear-off / Merge (TabBar.swift + MAIApp.swift)
- **Reordenar**: DragGesture horizontal, `checkSwap()` compara centros de tabs (30% threshold)
- **Tear-off** (>60px vertical): `WindowManager.openNewWindow(withTab:from:at:)` crea NSWindow nueva
- **Merge**: Soltar tab sobre tab bar de otra ventana → `WindowManager.mergeTab(_:into:from:)`
- **TabDragPreviewWindow**: NSPanel singleton, 280x200, snapshot + favicon + título, animación fade
- **WebView transfer**: `tab.retainedWebView` (strong ref) evita dealloc durante transferencia. `WebViewRepresentable.makeNSView` reutiliza webView existente sin recargar página.
- **TabFramePreference**: PreferenceKey que trackea posiciones de tabs para hit-testing
- **WindowManager.registerMainWindow**: Llamado desde BrowserView.onAppear (delay 0.5s)
- **WindowManager.browserState(at:excluding:)**: Detecta tab bar de otras ventanas (top 50px)

### Chrome Compatibility Mode (BrowserState + BrowserView + TabBar)
- **Toggle**: Click derecho en tab → "Modo Chrome" / "Desactivar Modo Chrome"
- **Indicador**: Barra azul `ChromeCompatIndicator` con botón "Desactivar"
- **UA spoofing**: Safari 18.2 ↔ Chrome 145.0.7632.68
- **JS injection**: `window.chrome`, `navigator.userAgentData` (brands/platform), `navigator.vendor`
- **Persistencia**: JSON por dominio vía `ChromeCompatManager.shared`
- **Auto-aplica**: `WebViewRepresentable.makeNSView` checa preferencia por dominio al crear tab
- **Deshabilitado para**: Tabs suspendidos y tabs CEF (ya son Chromium real)

### CEF Crash Recovery (CEFBridge.mm)
- **`on_render_process_terminated`**: Detecta abnormal/killed/crashed/OOM
- **Auto-reload**: Captura URL del main frame, `load_url` después de 1s dispatch_after
- **Delegate**: `cefBrowserRendererCrashedWithStatus:` notifica a Swift para UI state
- **Swift side** (CEFWebView.swift): Coordinator actualiza loading state del tab

### WebKit Crash Recovery (WebViewContainer.swift)
- **`webViewWebContentProcessDidTerminate`**: Auto-reload inmediato con `webView.reload()`
- Logs título del tab afectado

### CEF Stability Fixes
- **Disabled `FontationsFontBackend`**: Rust fontations crasheaba con EXC_BREAKPOINT en bitmap glyph rendering → fallback a CoreText nativo
- **Disabled `RustPngDecoder`**: Rust PNG decoder crasheaba durante compositing → fallback a C libpng
- Ambos crashes observados en MAI Helper (Renderer) 2026-03-02
- **Removed silent audio track**: AudioContext+OscillatorNode track causaba que Meet reemplazara el sender del micrófono real, matándolo (state=ended) y generando errores SDP BUNDLE codec collision [111:audio/opus] x2

### Archivos modificados
- `AddressBar.swift` (+462 líneas): URL suggestions completo
- `TabBar.swift` (+250 líneas): Drag/drop, tear-off, merge, preview window
- `MAIApp.swift` (+117 líneas): WindowManager tear-off/merge/register
- `BrowserState.swift` (+32 líneas): Chrome compat toggle, Tab.retainedWebView
- `BrowserView.swift` (+49 líneas): ChromeCompatIndicator, WindowManager register
- `CEFBridge.mm` (+88/-13 líneas): Crash recovery, disabled features, removed audio track
- `CEFBridge.h` (+1 línea): cefBrowserRendererCrashedWithStatus delegate
- `CEFWebView.swift` (+17 líneas): Crash UI state handling
- `WebViewContainer.swift` (+18 líneas): WebKit crash recovery, WebView reuse

---

## v0.8.0 (2026-02-28) — YouTube Ad Blocking

### YouTubeAdBlockManager.swift (761 líneas)
- **5 capas de defensa**:
  - Capa 0: ServiceWorker cleanup
  - Capa 1: Data interception — JSON.parse override, property traps (ytInitialPlayerResponse, ytInitialData, ytPlayerConfig), ytcfg.set trap, fetch/XHR/Response.json intercept, adSignalsInfo removal from POST body, 20+ claves de ads removidas, recursión 15 niveles
  - Capa 2: CSS cosmético — 30+ selectores ocultos
  - Capa 3: Monitoreo activo — Polling 250ms + MutationObserver + video events, triple detección (CSS .ad-showing + overlay + player API), skip forzado (mute+16x+jump), 10+ selectores de skip buttons, player API patching
  - Capa 4: WKContentRuleList — 13 reglas de red (doubleclick, pagead, etc.)
  - Capa 5: Post-load cleanup (atDocumentEnd) + re-inyección en didFinish
- **SPA navigation**: Hooks en pushState, popstate, yt-navigate-finish, yt-page-data-updated
- **Settings**: Toggle + contador de ads bloqueados
- **Guard**: `_maiYTAdBlock` previene doble inyección
- **Tags**: `v0.7.1-pre-youtube-adblock` (backup), `v0.8.0`

---

## v0.7.1 (2026-02-28) — Chrome Compatibility Mode

- Spoofea identidad Chrome en tabs WebKit sin CEF
- `ChromeCompatManager.swift`: Singleton, persistencia JSON por dominio
- Script inteligente en atDocumentStart: detecta UA → inyecta/oculta Chrome properties
- Auto-aplica al crear tab si dominio tiene preferencia guardada
- **Limitación**: Sitios que requieren Chrome Extensions API real no funcionan

---

## v0.7.0 (2026-02-28) — ML Auto-Suspensión + Snapshots a Disco

### Snapshot a Disco
- `Tab.snapshotPath: URL?` reemplaza `NSImage?` en RAM
- JPEG 0.7 quality en `~/Library/Caches/MAI/snapshots/{uuid}.jpg`
- `SuspendedTabView` carga onAppear, libera onDisappear → zero RAM
- Orphan cleanup en applicationDidFinishLaunching

### ML Auto-Suspensión
- **SuspensionMLModel**: `DomainStat` con approval rate + exponential moving average inactivity + `alwaysSuspend` flag
- **Predict**: alwaysSuspend→auto, <20 global o <5 domain→ask, >0.80 rate→auto, <0.20→never, else ask
- **Persistencia**: `suspension_decisions.json` + `suspension_domain_stats.json`
- **AutoSuspendManager**: learningModeEnabled, pendingSuspensionTab, declinedTabIDs (session)
- **Banner**: 45s timeout (era 15s), auto-dismiss sin penalización, [Sí]/[No]/[Siempre]
- **Tab interaction**: selectTab() registra interacción al salir de tab

### PhishingDetector
- Heurísticas de URL: homoglyphs, IP addresses, excesivos subdominos, dominios sospechosos
- Modal sheet con nivel de riesgo, razones, Volver/Continuar

---

## v0.6.1 (2026-02-27) — Bugfixes

- **Drag & drop fix**: Removido `onTapGesture` de BrowserView VStack que bloqueaba drag events
- **Tab mute fix**: Nuevo `applyMuteState()` soporta WebKit y CEF. Antes fallaba silenciosamente en CEF.
- **Mute persistence**: Re-aplica mute en `webView(_:didFinish:)`
- **Visual screen picker**: Thumbnails de pantallas/ventanas en grid 3 columnas con nombres reales

---

## v0.6.0 (2026-02-23) — VideoFrame API + Crash Fixes

### Screen Sharing HD
- **VideoFrame path**: fetch→createImageBitmap→VideoFrame→MediaStreamTrackGenerator→WritableStream (15fps, no canvas)
- **Canvas fallback**: captureStream(5) si MediaStreamTrackGenerator no disponible
- **Feature flag**: `--enable-blink-features=MediaStreamInsertableStreams`
- **Adaptive quality**: 0.92 default, 0.95 max, 0.80 min, step ±0.03/0.01, sRGB

### Crash Fixes
- **KEY INSIGHT**: `forceReleaseBrowser` siempre más seguro que `closeBrowser` (sync vs async)
- Shutdown crash: forceReleaseBrowser sync en vez de message pump loop
- Dual-window crash: comparación de browser IDs en on_before_close
- Motor switch crash: release sincrónico antes de crear nuevo browser
- **Google login**: `UR_FLAG_ALLOW_STORED_CREDENTIALS` forzado en ALL requests (Chromium 145 ponía DO_NOT_SEND_COOKIES en type=19)

---

## v0.5.1 (2026-02-16) — Incognito Mode

- **Window-level** (no tab-level): BrowserState.isIncognito, todos los tabs heredan
- WKWebsiteDataStore.nonPersistent() compartido, descartado al cerrar
- Skip HistoryManager.recordVisit() para incognito
- Full dark theme: .colorScheme(.dark) en TabBar, AddressBar, StatusBar
- IncognitoLandingPage para about:blank
- WindowManager.openNewWindow(isIncognito:)

---

## v0.5.0 (2026-02-21) — CEF H.264 Build

- CEF 145.0.26 con proprietary codecs (OpenH264 + VideoToolbox)
- Framework 311 MB (era 292 sin H.264)
- Build: Mac Mini 2018 Intel 64GB, disco KINGSTON 932GB
- args.gn: `proprietary_codecs=true ffmpeg_branding="Chrome"`
- Teams screen sharing + login funcional

---

## v0.4.x (2026-02) — CEF Integration

### v0.4.3
- Teams standalone window REMOVIDO (parent_view forza Alloy, cookie contextID mismatch)
- Todos los sitios (Meet/Zoom/Teams) usan mismo embedded Alloy mode

### v0.4.2
- Adaptive JPEG quality para window capture
- sRGB color space
- Auto-cleanup cuando video track termina

### v0.4.1
- Screen/window picker nativo con ScreenCaptureKit
- Native picker → SCStream → JPEG → base64 → canvas.captureStream

### v0.4.0
- CEF C API → CEFBridge.mm (ObjC++) → CEFWebView.swift → SwiftUI
- Auto-detección Meet/Zoom/Teams
- 5 helper bundles, message pump, permission handler
- on_before_popup para auth URLs in-place

---

## v0.3.1 — Bugfixes

- about:blank fix: solo bloquear desde SafeLinks, no todas las navegaciones
- Navigator spoofing reducido: 3 propiedades mínimas (webdriver, userAgentData, window.chrome)

---

## v0.3.0 — Core Browser

- UI SwiftUI completa: TabBar, AddressBar, BrowserView, StatusBar, Sidebar
- WebKit navigation, historial, bookmarks, descargas
- OAuth popups (OAuthWindowController con .floating level)
- SafeLinks URL extraction
- Multi-window (Cmd+N), Find in Page (Cmd+F)
- File upload (NSOpenPanel), camera/microphone permissions
- Tracker/ad blocking (PrivacyManager), anti-fingerprinting

---

## Arquitectura de Archivos

| Archivo | Responsabilidad |
|---------|----------------|
| `MAIApp.swift` | Entry point, WindowManager, CEF shutdown, keyboard shortcuts |
| `BrowserState.swift` | State management, tab CRUD, navigation, suspension, find, CEF detection |
| `BrowserView.swift` | Main view hierarchy, indicators, sidebar, status bar |
| `AddressBar.swift` | URL field, suggestions, navigation buttons, security indicator, bookmarks |
| `TabBar.swift` | Tab UI, drag/drop, tear-off/merge, context menus |
| `WebViewContainer.swift` | WKWebView setup, delegates, OAuth, downloads, privacy blocking |
| `CEFBridge.mm` | CEF C API wrapper, screen sharing, permissions, crash recovery |
| `CEFBridge.h` | ObjC header for Swift bridge |
| `CEFWebView.swift` | NSViewRepresentable for CEF, coordinator delegates |
| `ChromeCompatManager.swift` | Chrome UA/JS spoofing, domain persistence |
| `YouTubeAdBlockManager.swift` | 5-layer YouTube ad defense |
| `PrivacyManager.swift` | Tracker/ad blocking, OAuth whitelist |
| `ML/AutoSuspendManager.swift` | Auto-suspension with ML, banner state |
| `ML/SuspensionMLModel.swift` | Decision tracking, domain stats, prediction |
| `ML/PhishingDetector.swift` | URL phishing heuristics |
| `SettingsView.swift` | App settings UI |

## Build & Run

```bash
cd ~/Documents/MAI
make app     # build + helpers + bundle + codesign
make run     # build and launch
make clean   # clean build artifacts
```

## Decisiones Técnicas Clave

1. **WebKit + CEF híbrido** — WebKit para navegación general (eficiente), CEF solo para videoconferencias (compatibilidad)
2. **forceReleaseBrowser > closeBrowser** — Sync siempre más seguro que async para CEF lifecycle
3. **parent_view forza Alloy en macOS** — Chrome style imposible con parent_view (cef_types_mac.h:152)
4. **UR_FLAG_ALLOW_STORED_CREDENTIALS universal** — Chromium 145 rompe cookies, forzamos en ALL requests
5. **Tab.retainedWebView** — Strong ref temporal para transferir WKWebView entre ventanas sin recargar
6. **Snapshots a disco** — JPEG en ~/Library/Caches vs NSImage en RAM, zero RAM cuando no visible
7. **getDisplayMedia video-only** — Silent audio track mata micrófono real en Meet
