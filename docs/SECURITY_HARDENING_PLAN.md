# MAI — Plan de Hardening Anti-Ingeniería-Inversa

**Última actualización:** 2026-04-14
**Objetivo:** cerrar v0.9.7.7 y preparar v1.0 con protección suficiente para release pagado ($1 USD).

---

## Hito clave

**Viernes 2026-04-18 — Apple Developer ID ($99/año)**

Sin este cert, MAI depende de firmas ad-hoc con Team IDs distintos por binario, lo que obliga a mantener `com.apple.security.cs.disable-library-validation = true` en el entitlements. Ese flag abre la puerta a inyección de dylibs arbitrarios (el ataque más eficiente contra las 10 capas anti-RE actuales).

Con Developer ID → todos los binarios firmados con el **mismo Team ID** → `disable-library-validation` se puede eliminar → cierra la vulnerabilidad crítica.

---

## Estado actual de protección (v0.9.7.6)

### 10 capas implementadas
1. `PT_DENY_ATTACH` — bloquea debuggers (lldb)
2. Exception port monitoring — detecta debuggers vía Mach
3. Dylib enumeration — detecta 12 frameworks de hooking (Frida, Cycript, etc.)
4. Environment variable checks — `DYLD_INSERT_LIBRARIES`, `MALLOC_*`, etc.
5. Code signature verification en runtime
6. Hook detection — `dladdr()` verifica `CCCrypt`, `WKUserScript`
7. Hardened runtime — bloquea unsigned memory, DYLD env vars
8. AES-128-CBC encryption de scripts JS (8 fragmentos + HMAC-SHA256 + PBKDF2 50K iter)
9. XOR rolling key + permutation array + opaque predicates para string tables JS
10. Anti-Kong class rename (`WKRenderPipeline` genérico) + bracket notation

### Vulnerabilidad crítica abierta
`com.apple.security.cs.disable-library-validation = true` permite cargar dylibs con cualquier firma. Atacante inyecta dylib que hookea `decrypt()` y extrae scripts en plaintext en ~30 minutos.

**Bloqueador**: falta Apple Developer ID para firmar CEF + MAI con mismo Team ID.

---

## Plan de implementación de esta semana

### Lunes-Jueves (fixes gratuitos, sin Developer ID)

| # | Fix | Tiempo | Riesgo | Descripción |
|---|-----|--------|--------|-------------|
| 1 | Release build + `-O` + strip + `-dead_strip` | 15 min | Cero | Pasar de Debug a Release en Makefile, eliminar símbolos Swift |
| 2 | SwiftShield con exclusiones | 2h + QA | Bajo-medio | Renombrar clases/métodos Swift a hashes en Release |
| 3 | Watchdog 8-15s → 1-2s | 30 min | Cero | Cerrar ventana temporal de inyección de hooks |
| 4 | Secure Enclave para clave AES | 2-3h | Bajo | Guardar clave maestra en T2/Secure Enclave en vez de derivarla en código |

### Viernes 2026-04-18

1. Pagar Apple Developer ID ($99/año)
2. Editar `MAI.entitlements` → **remover** `com.apple.security.cs.disable-library-validation`
3. Re-firmar MAI.app + CEF + 5 helper bundles con Team ID del nuevo cert
4. Habilitar notarización en el Makefile (`xcrun notarytool submit`)
5. Validar que Gatekeeper acepta el bundle sin warnings

---

## Exclusiones obligatorias para SwiftShield

SwiftShield renombra símbolos Swift. Los siguientes patrones **no se deben renombrar** o se rompen en runtime:

### Selectores por string (fallan si se renombra el método)
- `Selector(("showSettingsWindow:"))` — `Sources/MAI/AddressBar.swift`, `Sources/MAI/MAIApp.swift`
- `NSApp.sendAction(..., to: nil, from: nil)` — si envía a selectores que pueden estar ofuscados

### Notification names custom
- `Notification.Name("maiCreateWorkspace")` y el extension en `Sources/MAI/MAIApp.swift`
- Cualquier otra notificación custom con nombre string

### Bridging Swift ↔ ObjC
- Clases con `@objc` expuestas al CEFWrapper (verificar en `Sources/MAI/CEF/`)
- Métodos `@objc` llamados desde `CEFBridge.mm`

### Antes de ejecutar SwiftShield

```bash
# Generar lista exhaustiva de patrones que requieren exclusión
grep -rn "Selector(\|NSSelectorFromString\|performSelector\|#selector\|@objc" Sources/MAI/
grep -rn "NotificationCenter.*post\|NotificationCenter.*addObserver" Sources/MAI/
```

### Suite de humo post-SwiftShield (obligatoria)

- [ ] Abrir 2 ventanas, Cmd+Opt+I en ambas (regresión del fix v0.9.7.7)
- [ ] Google Meet, Zoom, Teams → CEF bridge recibe callbacks
- [ ] Traducir página → popover estilo Chrome funciona
- [ ] Cmd+, → Settings abre
- [ ] Cmd+Shift+P → "Nuevo Perfil…" → notification custom dispara
- [ ] Screen sharing picker se abre correctamente
- [ ] Password manager: guardar/autofill una credencial

---

## Hikari — por qué queda diferido

**Técnicamente viable** — la Mac Mini 2018 (64GB RAM, 174GB libres, T2) ya compiló Chromium completo cross-compile Intel→ARM64 con H.264 propietario. Hikari es mucho menos pesado.

**Por qué no es prioridad:**

| Aspecto | Realidad en MAI |
|---------|-----------------|
| Cobertura Swift | Parcial — metadata y runtime de Swift resisten sus transformaciones |
| Cobertura ObjC/C++ (CEFBridge.mm) | Alta — ahí sí brilla |
| Overhead build | +8h primer build (luego incremental) |
| Overhead runtime | 10-30% más lento, binario 2-5x más grande |
| Madurez | Fork mantenido por 1 persona con commits esporádicos → riesgo de miscompilación silenciosa |
| Alternativa Swift | SwiftShield + Release + strip dan ~80% del resultado en 30 min |

**Trigger para revisitarlo:** si después del viernes aparecen cracks circulando en foros específicamente atacando `CEFBridge.mm`, reconsiderar. Hasta entonces, el ROI no justifica la complejidad.

---

## Infraestructura de build

### Máquina primaria de desarrollo
- Apple Silicon (M-series) con macOS 26.3.1
- Donde corren los 4 fixes de esta semana
- Donde se valida funcionalidad

### Build machine dedicada
- **Mac Mini 2018**: Intel i5 6-core, 64 GB RAM, T2 Security Chip
- macOS 15.7.4 Sequoia (última versión soportada)
- ~174 GB libres al cierre del último build de CEF
- Ya validada con Chromium completo (20M LOC C++) cross-compile Intel → ARM64 con H.264
- Disponible para Hikari si se decide hacerlo

### Target
- `arm64-apple-macosx` (Apple Silicon únicamente por ahora)
- macOS 13+ (Ventura mínimo)

---

## Referencias cruzadas

- `CHANGELOG.md` — historial de cada release
- `docs/CEF_BUILD_H264.md` — proceso de build de CEF en la Mac Mini (experiencia previa de cross-compile)
- `docs/ARCHITECTURE.md` — arquitectura técnica general
- `MAI.entitlements` — archivo a editar post-Developer ID
- `Sources/CEFWrapper/CEFBridge.mm` — objetivo principal de Hikari (si se ejecuta)
- `Sources/MAI/` — objetivo de SwiftShield (con exclusiones)
