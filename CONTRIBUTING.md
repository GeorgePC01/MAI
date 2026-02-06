# Guía de Contribución - MAI Browser

## Bienvenido

Gracias por tu interés en contribuir a MAI Browser. Este documento te guiará en el proceso.

## Código de Conducta

- Se respetuoso con todos los contribuidores
- Acepta críticas constructivas
- Enfócate en lo mejor para el proyecto
- Muestra empatía hacia otros miembros de la comunidad

## Cómo Contribuir

### Reportar Bugs

1. Verifica que el bug no esté ya reportado
2. Abre un issue con:
   - Descripción clara del problema
   - Pasos para reproducir
   - Comportamiento esperado vs actual
   - Screenshots si aplica
   - Versión de macOS y MAI

### Proponer Features

1. Abre un issue de "Feature Request"
2. Explica:
   - El problema que resuelve
   - Tu solución propuesta
   - Alternativas consideradas
   - Screenshots/mockups si aplica

### Pull Requests

1. Fork el repositorio
2. Crea una branch descriptiva:
   ```bash
   git checkout -b feature/awesome-feature
   # o
   git checkout -b fix/nasty-bug
   ```

3. Haz tus cambios siguiendo las guías de estilo

4. Agrega tests si aplica

5. Asegúrate de que los tests pasen:
   ```bash
   make test
   ```

6. Commit con mensajes claros:
   ```bash
   git commit -m "Add awesome feature

   - Implemented X
   - Fixed Y
   - Updated Z
   "
   ```

7. Push a tu fork:
   ```bash
   git push origin feature/awesome-feature
   ```

8. Abre un Pull Request

## Guías de Estilo

### Swift Code Style

- Usar Swift style guide oficial
- Indentación: 4 espacios
- Máximo 100 caracteres por línea
- Comentarios en español o inglés (consistente)

```swift
// ✅ Bueno
func fetchUserData(userId: String) async throws -> UserData {
    let url = buildURL(for: userId)
    return try await networkManager.fetch(url)
}

// ❌ Malo
func fetch(id:String)->UserData{
let url=buildURL(id)
return networkManager.fetch(url)
}
```

### Commits

- Presente imperativo: "Add feature" no "Added feature"
- Primera línea: máximo 50 caracteres
- Descripción detallada si es necesario

```bash
# ✅ Bueno
git commit -m "Add ML-based tab prediction

Implemented Core ML model to predict which tabs
the user is likely to open next based on browsing
patterns.

Closes #123
"

# ❌ Malo
git commit -m "fixed stuff"
```

### Documentación

- Comentarios para código complejo
- Documentación en archivos `.md`
- Ejemplos de uso cuando sea útil

```swift
/// Optimiza el uso de memoria suspendiendo tabs inactivos
///
/// Este método usa ML para determinar qué tabs tienen menor
/// probabilidad de ser usados y los suspende para liberar RAM.
///
/// - Parameter maxTabsToSuspend: Número máximo de tabs a suspender
/// - Returns: Número de tabs efectivamente suspendidos
func optimizeMemory(maxTabsToSuspend: Int = 5) -> Int {
    // Implementation
}
```

## Estructura de Branches

- `main` - Código estable, listo para release
- `develop` - Desarrollo activo
- `feature/*` - Nuevas características
- `fix/*` - Bug fixes
- `docs/*` - Cambios en documentación

## Tests

Todos los PRs con código nuevo deben incluir tests:

```swift
import XCTest
@testable import MAICore

final class BrowserEngineTests: XCTestCase {
    func testEngineInitialization() {
        let engine = BrowserEngine.shared
        XCTAssertEqual(engine.state, .idle)
    }

    func testTabCreation() {
        let engine = BrowserEngine.shared
        let tab = engine.createTab(url: URL(string: "https://test.com")!)
        XCTAssertNotNil(tab)
    }
}
```

## Áreas que Necesitan Ayuda

### Alta Prioridad
- [ ] UI SwiftUI implementation
- [ ] Tab management
- [ ] History/Bookmarks
- [ ] Settings interface

### Media Prioridad
- [ ] ML models training
- [ ] Extension API
- [ ] Sync service
- [ ] Performance optimization

### Baja Prioridad
- [ ] Themes
- [ ] Advanced features
- [ ] Windows/Linux ports

## Proceso de Review

1. Automated tests run on PR
2. Code review por maintainer
3. Changes solicitados si es necesario
4. Merge una vez aprobado

## Licencia

Al contribuir, aceptas que tu código será licenciado bajo MIT License.

---

**Gracias por contribuir a MAI Browser! 🎉**
