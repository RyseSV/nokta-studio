# Nokta Studio

One backend, three clients. The user speaks Spanish — reply in Spanish, plain language.

## Cómo trabajar con el usuario

- Es el dueño de Nokta Studio (estudio de foto/video). No es muy técnico: explicaciones simples, pasos cortos, sin jerga.
- Él prueba en su Mac y manda capturas. Antes de decir "listo": compilar Mac e iPhone y pedirle que confirme lo visual.
- Si pregunta "¿ya lo aplicaste?" o "¿ya revisaste todo?", volver a verificar en el código; no repetir lo dicho antes.
- Nunca pedir, ver ni escribir su contraseña: él hace las pruebas de login.
- Plan Pro: cuida el uso. Sonnet para arreglos chicos, Opus para trabajo grande.

## Estado del proyecto (2026-09-24)

- La app de Mac/iPhone es 100% nativa, con su propio login/logout.
- **Quitado a pedido del usuario (2026-09-22, commit 994f88d):** login con Touch ID/Face ID y cierre de sesión por inactividad (AFK, 10 min). Cerraba sesión a los ~20-30 s en vez de 10 min. No volver a agregarlo salvo que lo pida; si lo pide, encontrar primero por qué se disparaba antes (sospechosos sin confirmar: notificaciones de pantalla dormida / sesión inactiva).
- **Arreglado (commit edaf922):** `CookieSync` pisaba la sesión antes de cada llamada a la API (datos vacíos, sin nombre). Se eliminó. El avatar del sidebar ahora muestra la foto subida del usuario; el nombre ya se confirmó, la foto falta confirmarla.
- **Rediseño premium (en curso, 2026-09-24):** diseño en Figma "Nokta Studio – Rediseño Dashboard" (https://www.figma.com/design/U2QhD4yiJTbjQV68lHs40L, una sola página; plan Starter con límite de llamadas MCP — ya se agotó una vez, no pagar). En la app: colores adaptables `NoktaTheme` + `.noktaCard()` + selector Claro/Oscuro/Automático (`NoktaApariencia`) en `Core/DesignSystem.swift`; Dashboard y menú lateral ya rediseñados; las demás pantallas y el login siguen con `NoktaPalette` y fijas en oscuro hasta rediseñarlas una por una. El menú agrupa por tipo (General, Trabajos, Finanzas, Clientes, Estudio, Administración): **nunca quitar secciones**, solo reordenar.
- **Pendiente de seguridad:** 2FA para el login de admin y respaldos de la base de datos.

- `server/` — Express + Mongoose API on Render (`app.js`), web panel in `server/views/admin.html`. Auto-deploys from `main` on GitHub (RyseSV/nokta-studio).
- `native/` — SwiftUI app for macOS + iOS, 100% native, calls the same REST API via `NoktaStudio/Assistant/NoktaAPI.swift`. Keep behavior 1:1 with admin.html.

## Commands

- Node is not on PATH: `export PATH="/Users/gabrielcerritos/dev-tools/node/bin:$PATH"`
- Server tests: `node server/tests/<file>.cjs` (one file per area).
- After adding/removing any `.swift` file: `cd native && python3 gen_pbxproj.py` (the .xcodeproj is generated; there is no Info.plist — use `INFOPLIST_KEY_*` in gen_pbxproj.py).
- Build both before calling a change done:
  - `xcodebuild -project native/NoktaStudio.xcodeproj -scheme NoktaStudio-macOS -destination 'platform=macOS' build`
  - `xcodebuild -project native/NoktaStudio.xcodeproj -scheme NoktaStudio-iOS -destination 'generic/platform=iOS Simulator' build`

## Gotchas

- Relaunch the Mac app with `open <.app>` — running the binary directly starts it with no window.
- Swift `print()` is invisible when launched via `open`; use `NSLog` and `log stream --predicate 'process == "NoktaStudio"'`.
- Mongo schemas are `strict:false`: numbers may arrive as strings — decode with `@Flex` / `@FlexInt` / `@FlexString`.
- The session cookie lives only in URLSession's shared cookie storage (set by LoginView). Nothing should copy cookies from WKWebView.
- The server talks to the real production DB. Never leave test data there; never handle the user's password.
