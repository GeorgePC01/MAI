# MAI Browser - Compatibilidad con Sitios Web

## Resumen

MAI Browser implementa técnicas de anti-detección para ser reconocido como Safari por sitios web que bloquean navegadores "no soportados" (como Google, Microsoft, etc.).

---

## El Problema

Sitios como Google, Gmail, Office 365 detectan navegadores usando múltiples técnicas:

| Método de Detección | Qué detectan |
|---------------------|--------------|
| User-Agent | String de identificación del navegador |
| navigator.webdriver | `true` en WKWebView (delata automatización) |
| navigator.vendor | Vacío en WKWebView (Safari dice "Apple Computer, Inc.") |
| navigator.userAgentData | API de Chrome (no existe en Safari) |
| window.chrome | Objeto de Chrome |
| navigator.plugins | Lista de plugins del navegador |
| Canvas fingerprinting | Diferencias en renderizado |

**Resultado sin anti-detección:** "Ya no se admite esta versión del navegador"

---

## Solución Implementada

### 1. User-Agent de Safari 18.2

```swift
webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.2 Safari/605.1.15"
```

- Safari 18.2 es la versión actual (macOS Sequoia)
- `10_15_7` es la convención estándar de Safari
- WebKit 605.1.15 es el motor actual

### 2. Configuración de WKWebView

```swift
// En WKWebViewConfiguration
config.applicationNameForUserAgent = "Version/18.2 Safari/605.1.15"
config.suppressesIncrementalRendering = false

// Preferencias de contenido
preferences.preferredContentMode = .desktop  // macOS 12.3+
```

### 3. Script de Anti-Detección (JavaScript)

Inyectado al inicio de cada página (`atDocumentStart`):

```javascript
// Ocultar WebDriver (WKWebView lo expone como true)
Object.defineProperty(navigator, 'webdriver', {
    get: () => false
});

// Vendor correcto de Safari
Object.defineProperty(navigator, 'vendor', {
    get: () => 'Apple Computer, Inc.'
});

// Plataforma correcta
Object.defineProperty(navigator, 'platform', {
    get: () => 'MacIntel'
});

// Ocultar userAgentData (Chrome-specific)
Object.defineProperty(navigator, 'userAgentData', {
    get: () => undefined
});

// Eliminar rastros de Chrome
delete window.chrome;

// Plugins simulados
Object.defineProperty(navigator, 'plugins', {
    get: () => ({ length: 5, item: () => null })
});
```

### 4. Whitelist de OAuth

Dominios esenciales que nunca se bloquean (PrivacyManager.swift):

**Google:**
- accounts.google.com
- oauth2.googleapis.com
- apis.google.com
- mail.google.com
- myaccount.google.com
- *.gstatic.com
- *.googleapis.com

**Microsoft:**
- login.microsoftonline.com
- login.live.com
- *.msauth.net

**Otros:**
- appleid.apple.com
- github.com
- recaptcha.net
- hcaptcha.com

---

## Archivos Modificados

| Archivo | Cambios |
|---------|---------|
| `Sources/MAI/WebViewContainer.swift` | User-Agent, script anti-detección, configuración WKWebView |
| `Sources/MAI/PrivacyManager.swift` | Whitelist expandida de OAuth |

---

## Compatibilidad Verificada

| Sitio | Estado | Notas |
|-------|--------|-------|
| Gmail | ✅ Funciona | Login completo |
| Google Drive | ✅ Funciona | |
| Google Calendar | ✅ Funciona | |
| YouTube | ✅ Funciona | Fullscreen habilitado |
| Office 365 | ✅ Funciona | |
| Outlook.com | ✅ Funciona | |
| GitHub | ✅ Funciona | OAuth completo |
| Twitter/X | ✅ Funciona | |
| Facebook | ✅ Funciona | |

---

## Limitaciones Conocidas

### Passkeys/WebAuthn
- Requiere cuenta de Apple Developer ($99/año)
- Sin firma válida, passkeys no funcionan
- **Workaround:** Usar contraseña tradicional en lugar de passkey

### Google Meet/Hangouts
- WebRTC tiene limitaciones en WKWebView
- Videollamadas pueden no funcionar correctamente
- **Recomendación:** Usar Safari o Chrome para videollamadas

### Algunos CAPTCHAs
- reCAPTCHA v3 puede fallar ocasionalmente
- hCaptcha generalmente funciona

---

## Debugging

Para verificar qué ve un sitio web:

```javascript
// Ejecutar en consola del navegador
console.log({
    userAgent: navigator.userAgent,
    vendor: navigator.vendor,
    platform: navigator.platform,
    webdriver: navigator.webdriver,
    chrome: window.chrome,
    userAgentData: navigator.userAgentData
});
```

**Resultado esperado:**
```json
{
    "userAgent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15...",
    "vendor": "Apple Computer, Inc.",
    "platform": "MacIntel",
    "webdriver": false,
    "chrome": undefined,
    "userAgentData": undefined
}
```

---

## Referencias

- [WebKit User-Agent Policy](https://webkit.org/blog/8042/release-notes-for-safari-technology-preview-62/)
- [Google Browser Support](https://support.google.com/a/answer/33864)
- [WKWebView Documentation](https://developer.apple.com/documentation/webkit/wkwebview)

---

*Última actualización: 2026-02-06*
