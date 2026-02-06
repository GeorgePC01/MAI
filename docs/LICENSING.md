# MAI Browser - Licenciamiento y Distribución

## Resumen Ejecutivo

Para desarrollar, distribuir y vender MAI Browser, solo se necesita una cuenta de **Apple Developer Program** ($99 USD/año).

---

## Apple Developer Program - $99/año

### ¿Qué incluye?

| Característica | Incluido |
|----------------|----------|
| Publicar en Mac App Store | ✅ |
| Vender apps con precio | ✅ |
| Distribución fuera del App Store (notarizada) | ✅ |
| Passkeys/WebAuthn/Autenticación biométrica | ✅ |
| iCloud, Push Notifications, Sign in with Apple | ✅ |
| TestFlight para distribución de betas | ✅ |
| Acceso a APIs privadas de macOS | ✅ |
| Certificados de firma de código | ✅ |

### ¿Se necesita otra licencia para vender?

**No.** Los $99/año cubren todo lo necesario para:
- Desarrollo
- Testing
- Distribución gratuita
- Venta comercial
- Uso empresarial

---

## Opciones de Distribución

### Opción 1: Mac App Store

**Ventajas:**
- Visibilidad en la tienda de Apple
- Actualizaciones automáticas gestionadas por Apple
- Confianza del usuario (app revisada por Apple)
- Integración con Apple Pay

**Desventajas:**
- Comisión de Apple:
  - **15%** si ingresos < $1M/año (Small Business Program)
  - **30%** si ingresos > $1M/año
- Proceso de revisión (puede tomar días)
- Restricciones de Apple (no se permiten otros motores de navegador que no sean WebKit)

**Nota importante:** Apple requiere que todos los navegadores en el App Store usen WebKit como motor. MAI ya usa WebKit, así que cumplimos este requisito.

### Opción 2: Distribución Directa (fuera del App Store)

**Ventajas:**
- **0% comisión** - te quedas con el 100%
- Sin proceso de revisión de Apple
- Libertad total en funcionalidades
- Actualizaciones instantáneas
- Puedes usar cualquier procesador de pagos (Stripe, Paddle, Gumroad, LemonSqueezy)

**Desventajas:**
- Necesitas manejar tu propia infraestructura de pagos
- Necesitas "notarizar" la app (proceso gratuito pero adicional)
- Los usuarios ven advertencia de "app de desarrollador identificado" la primera vez

**Proceso de notarización:**
1. Compilar la app
2. Firmar con Developer ID
3. Enviar a Apple para notarización (automático, toma ~5 minutos)
4. Apple verifica que no es malware
5. Distribuir

---

## Comparativa de Costos

### Escenario: Vendes MAI a $29.99

| Canal | Precio | Comisión | Recibes |
|-------|--------|----------|---------|
| App Store (< $1M) | $29.99 | 15% ($4.50) | $25.49 |
| App Store (> $1M) | $29.99 | 30% ($9.00) | $20.99 |
| Sitio web propio | $29.99 | ~3% (Stripe) | $29.09 |

### Escenario: 1,000 ventas/año

| Canal | Ingresos Brutos | Comisiones | Neto |
|-------|-----------------|------------|------|
| App Store (< $1M) | $29,990 | $4,499 | $25,491 |
| Sitio web + Stripe | $29,990 | $900 | $29,090 |

**Diferencia: ~$3,600/año más vendiendo directo**

---

## Licencias que NO necesitas

| Licencia | ¿Necesaria? | Notas |
|----------|-------------|-------|
| Apple Developer Enterprise ($299/año) | ❌ | Solo para apps internas de empresas, no para venta pública |
| Licencia de WebKit | ❌ | WebKit es open source (LGPL/BSD) |
| Licencia comercial de Swift | ❌ | Swift es open source (Apache 2.0) |
| Licencia de macOS SDK | ❌ | Incluida en Xcode (gratis) |

---

## Requisitos Técnicos para Distribución

### Para Mac App Store:
1. Cuenta Apple Developer activa ($99/año)
2. App firmada con certificado "Apple Distribution"
3. Sandbox habilitado
4. Cumplir App Store Review Guidelines
5. Privacidad: declarar uso de datos

### Para distribución directa:
1. Cuenta Apple Developer activa ($99/año)
2. App firmada con certificado "Developer ID Application"
3. Notarización (enviar a Apple para verificación)
4. No requiere sandbox (opcional)

---

## Funcionalidades que Requieren Developer Account

Sin una cuenta de Apple Developer, las siguientes funcionalidades **no funcionarán correctamente**:

| Funcionalidad | Sin cuenta | Con cuenta ($99) |
|---------------|------------|------------------|
| Passkeys/WebAuthn | ❌ | ✅ |
| Keychain compartido | ❌ | ✅ |
| Notificaciones Push | ❌ | ✅ |
| Sign in with Apple | ❌ | ✅ |
| iCloud sync | ❌ | ✅ |
| Handoff entre dispositivos | ❌ | ✅ |
| App Store distribution | ❌ | ✅ |

---

## Recomendación para MAI Browser

### Estrategia sugerida:

1. **Fase de desarrollo (ahora)**
   - Obtener cuenta Apple Developer ($99)
   - Firmar app correctamente para passkeys
   - Distribuir betas via TestFlight o directamente

2. **Lanzamiento inicial**
   - Distribución directa desde sitio web
   - Modelo freemium o pago único
   - 0% comisión, máxima ganancia

3. **Expansión**
   - Considerar App Store para visibilidad
   - Evaluar si el 15-30% de comisión vale la exposición

### Modelo de negocio sugerido:

| Opción | Descripción |
|--------|-------------|
| **Pago único** | $29-49 USD, licencia perpetua |
| **Freemium** | Gratis básico, Pro con funciones avanzadas |
| **Suscripción** | $4.99/mes o $39.99/año |

---

## Recursos

- [Apple Developer Program](https://developer.apple.com/programs/)
- [App Store Small Business Program](https://developer.apple.com/app-store/small-business-program/)
- [Notarizing macOS Software](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)
- [App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)

---

## Historial de Decisiones

| Fecha | Decisión |
|-------|----------|
| 2026-02-06 | Documentado análisis de licenciamiento |
| 2026-02-06 | Confirmado: Solo se requiere Apple Developer ($99/año) para todo |

---

*Última actualización: 2026-02-06*
