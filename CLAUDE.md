# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

GESACAD: Flutter app (Android + Web) for university academic management (Unicomfacauca). Three roles — Admin, Teacher, Student — talk to a separate Node.js/Express + MySQL backend (not in this repo). Code comments, UI strings and docs are in Spanish; match that. `README.md` has the use-case table (CU-01…CU-07), black-box test tables and DB schema.

## Commands

```bash
flutter pub get
flutter run -d chrome        # web
flutter run                  # Android emulator/device
flutter analyze              # lint (flutter_lints, see analysis_options.yaml)
flutter test                 # only test/widget_test.dart exists
flutter test test/widget_test.dart
```

Release APK on Windows: the Flutter SDK path contains spaces, so use the junction instead of plain `flutter build apk`:
`C:\flutter_sdk\bin\flutter.bat build apk --release` (output in `build\app\outputs\flutter-apk\app-release.apk`). `pubspec.yaml` pins `objective_c: 9.3.0` via `dependency_overrides` for the same space-in-path build bug — don't remove it.

## Backend URL

`lib/config/api_config.dart` holds `baseUrl` and every endpoint path. `baseUrl` defaults to Render (`gesacad-backend.onrender.com`) and is overridable **without editing code**: `flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8081` (Android emulator: `http://10.0.2.2:8081`, LAN device: `http://192.168.X.X:8081`). The local backend lives in `Backend/` (`npm start`; `.env` points to local MySQL). Note: README still says Railway — the code is the source of truth. Never commit local-dev URLs.

## Architecture

- **Entry/session**: `main.dart` → `SplashScreen` pings the backend (`ApiService().ping()`, wakes the cold-start dyno), reads `userRol` from SharedPreferences and routes to `LoginScreen` / `AdminHome` / `TeacherHome` / `StudentHome`. There is no named-route table; navigation uses `utils/route_transitions.dart` helpers (`slideRoute`, …).
- **Services** (`lib/services`, no state-management package — plain singletons + `ValueNotifier`):
  - `ApiService` — singleton for all HTTP. 30s timeout; `_conRetry` retries GETs once (never use it on POST/PUT/DELETE — it would duplicate inserts). Two-level cache (in-memory 5-min TTL + SharedPreferences `apicache_*` to show last-session data); cache is invalidated on course/activity add/delete. URL path params must be wrapped in `Uri.encodeComponent` (backend crashes on `/ ? # %`).
  - `AuthService` — session in SharedPreferences (`userId`, `userName`, `userRol`) plus cached `profile_*` keys.
  - `AppSettings` (`settings_service.dart`) — theme/config via `ValueNotifier`s; `main.dart` rebuilds `MaterialApp` from `AppSettings.currentTheme`; themes live in `config/app_themes.dart` (dark mode = `AppThemeType.darkCarbon`).
  - `GeminiService` is misnamed: it is a local keyword→canned-response chatbot (no external API), used by `widgets/chatbot_widget.dart`.
  - `tts_service.dart` / `talk_widget.dart` / `tts_button.dart` — text-to-speech accessibility (CU-07).
- **Platform split**: `utils/platform_utils.dart` with `_mobile` / `_web` variants (conditional imports) for web-vs-mobile behavior; `helpers/file_viewer_helper.dart` opens files via the backend `/files/proxy` endpoint (avoids Cloudinary CORS/401).
- **Screens** are grouped by role (`admin/`, `teacher/`, `student/`) plus shared `calendar/`, `notifications/`, `profile/`, `auth/`.

## Backend contract gotchas

- Login is `POST /auth/login` `{username, password}` → `{token, user, …, response: 'LOGIN_SUCCESFULLY'}` (single L — server typo, keep it). The old `GET /users/:username/:password` still exists only as a fallback for servers without the new route and is switched off with `ALLOW_LEGACY_LOGIN=false`.
- Activity dates are stored in UTC; convert for display with `ActivityModel.toCol()` (Colombia, UTC-5).
- Submissions are limited to 5 MB and to pdf/doc/docx/png/jpg/jpeg/zip/xlsx/pptx — enforced in the app AND in the server (`addResource`: 413 `ARCHIVO_MUY_GRANDE`, 415 `TIPO_NO_PERMITIDO`). Teacher attachments: 10 MB, up to 5 files. Profile photo: image only, 5 MB. Limits are overridable with `MAX_SUBMISSION_MB`, `MAX_ATTACHMENT_MB`, `MAX_PHOTO_MB`.
- **Subida de archivos** (`server.js`): multer escribe a disco temporal (`os.tmpdir()/gesacad-uploads`, nombre aleatorio, nunca el del cliente) y se transmite a Cloudinary con `subirACloudinary(RUTA, …)`; `limpiarTemporales` (va ANTES de multer en cada ruta con archivos) borra el temporal al cerrar la respuesta, incluso en salidas anticipadas. Nunca volver a `memoryStorage`. El nombre original se guarda dentro de la URL con `::name::` y `|||`: pasa siempre por `nombreSeguro()`. Pruebas sin Cloudinary: `CLOUDINARY_FAKE=true` (ignorado si `NODE_ENV=production`).
- Activity weightings (ponderado) per course must not exceed 100%; check via `ApiConfig.weightingMax` before creating.

## Modo sin conexión (offline)

- **Detección** (`services/connectivity_service.dart`): mide si el *backend* responde, no solo si hay wifi. `ApiService` informa cada éxito/fallo de red; sin conexión sondea `/health` cada 10 s. `isNetworkError(e)` distingue falla de red de error de aplicación.
- **Lectura**: `ApiService._getCached(key, uri)` guarda cada GET 200 en SharedPreferences (`apicache_*`) y, si no hay red, sirve la copia como un 200 sintético. Con `allowCache: false` (`fresh: true` en `getActivityContent`) exige dato del servidor. Solo para GET: nunca usar con POST/PUT/DELETE.
- **Escritura** (`services/offline_queue.dart`): `OfflineQueue` es un outbox persistente (entregas del estudiante y notas del docente). Envía en orden, se sincroniza sola al volver la conexión, reintenta con espera creciente en 5xx y marca `failed` en 4xx. Los archivos se guardan aparte (`outbox_file_store.dart`: disco en móvil, memoria en web — en web se pierden al recargar).
- **Anti-duplicados**: si un POST de entrega expira (`TimeoutException`) la operación queda `uncertain`; antes de reenviar se consulta `getActivityContent(fresh: true)`. Las notas son PATCH idempotentes y se reemplazan entre sí (gana la última).
- **UI**: `widgets/offline_banner.dart` (`OfflineShell` en el `builder` de `MaterialApp`) muestra el estado y el panel `CentroSync`. `utils/app_keys.dart` tiene las llaves globales de Navigator/ScaffoldMessenger.
- **Cerrar sesión** borra la cola y las copias (`AuthService.clearSession`); las pantallas piden confirmación si hay cambios sin enviar (`confirmarSalidaConPendientes`).
- Tests: `test/offline_test.dart`. Inyectar `OperationExecutor`, `OutboxFileStore` y `ConnectivityService.test(...)` para probar sin red.

## Desarrollo local (backend + app)

- **Un comando**: `.\tool\dev_local.ps1` (PowerShell) inicia MySQL, el backend (puerto **8081**, solo API) y la app en Chrome en el puerto **5000** apuntando al backend local. `-SoloBackend` para no abrir la app.
- **El puerto 8081 NO es la app**: solo responde datos (abrirlo en un navegador muestra una página que lo explica). La app se abre en `http://localhost:5000`.
- **Cada servidor tiene sus propios usuarios**: la base local (`Backend/.env` → MySQL local) no es la de producción. `npm run users` (en `Backend/`) lista los usuarios locales sin contraseñas. En depuración, la pantalla de login muestra un indicador de a qué servidor está conectada la app (`widgets/dev_server_badge.dart`).
- **Datos demo opcionales** para probar la evaluación docente (cursos con suficientes estudiantes): `npm run seed:dev -- --yes` en `Backend/` (solo corre contra MySQL local, idempotente, prefijo `demo_`, contraseña de desarrollo `Demo#2026`).
- **Migraciones al arrancar**: `server.js` agrega por sí solo las columnas que el código necesita y faltan en bases antiguas (perfil de `users`, `comment`/`teacherComment` de `resolutionsactivities`) y crea las tablas `evaluation_*`. Si una base antigua da 500 en entregas/actividades, reinicia el backend.

## Despliegue del backend (Render)

- El backend (`Backend/`, repositorio privado `dejotat/gesacad-backend`, rama `master`) se despliega **solo al hacer push a `master`**: Render ejecuta `npm install` y `npm start` (~45 s). No hay que tocar el panel de Render salvo para variables de entorno.
- **Verificar qué versión está en producción**: `GET https://gesacad-backend.onrender.com/health` devuelve `{status, version, uptimeSeconds}`; `version` es el commit corto desplegado (`RENDER_GIT_COMMIT`). Tras un push, esperar a que coincida con `git rev-parse --short=7 HEAD`.
- **Migraciones**: se aplican al arrancar y son idempotentes/aditivas (`CREATE TABLE IF NOT EXISTS`, `ALTER ... ADD COLUMN` ignorando `ER_DUP_FIELDNAME`). Nunca borran ni modifican datos. Antes de subir: `npm test` (28 pruebas contra una BD aparte).
- **Credenciales**: el `.env` NO se versiona (usa `Backend/.env.example` como plantilla; los valores reales viven en `.env` local y en Environment de Render). El `.gitignore` del backend debe quedar en UTF-8 (en UTF-16 git lo ignora en silencio).
- **Conexiones a MySQL**: `server.js` usa un **pool** (`DB_POOL_SIZE`, por defecto 3, tope 10; se abren bajo demanda) y el módulo de evaluación otro de 2. Antes era UNA conexión: si la base en la nube la cerraba por inactividad el servidor quedaba roto hasta reiniciarlo, y las transacciones de varios usuarios se mezclaban. Las transacciones (`ejecutarTransaccion`) usan una conexión propia y su `q` es la ÚNICA forma válida de consultar dentro de ellas. Las migraciones de arranque van encadenadas en orden. Las bases en la nube limitan las conexiones simultáneas: si el plan es pequeño, baja `DB_POOL_SIZE` antes de subirlo. Render envía SIGTERM al redesplegar: el servidor cierra ordenadamente.
- **Integración continua**: `.github/workflows/pruebas.yml` en cada repositorio. Backend: MySQL 8 de servicio + `npm ci` + `npm test`. App: Flutter 3.41.2 + `flutter analyze` (solo errores rompen) + `flutter test`. Render despliega al hacer push sin esperar las pruebas: mira la pestaña Actions del repositorio después de cada push.

## Seguridad: contraseñas, sesiones y permisos

- **Contraseñas**: se guardan con **scrypt** (`Backend/auth.js`, sin dependencias) en `users.pass_hash`; nunca se devuelven por la API. Al arrancar, el servidor agrega las columnas `pass_hash`/`token_version` y cifra en segundo plano las contraseñas antiguas; **el texto plano de `users.pass` se conserva** hasta el paso explícito de purga (`npm run purge:plain -- --yes`, o `PURGE_PLAINTEXT=true` una vez en Render) para poder volver atrás. Contraseñas nuevas/cambiadas: 8–64 caracteres con mayúscula, minúscula, número, símbolo y sin el usuario (validado también en el servidor).
- **Sesiones**: token JWT HS256 (7 días, `JWT_TTL_HOURS`) en `Authorization: Bearer`. Lleva la versión de sesión del usuario (`tv`): cambiar contraseña/rol, eliminar al usuario o `POST /auth/logout-all` revocan los tokens. `POST /auth/refresh` lo renueva (la app lo hace al abrir/volver si pasaron >12 h). `JWT_SECRET` (≥16 caracteres) en el entorno; si falta se deriva de las credenciales de la BD y se avisa.
- **Permisos por ruta** (`auth.acceso(...)` en `server.js`): Admin gestiona usuarios/cursos; el docente solo sus cursos y actividades; el estudiante solo lo suyo; notificaciones y detalle de actividad usan el rol **de la sesión**, no el de la URL. `/files/proxy` es público a propósito (solo reenvía `https://res.cloudinary.com`, validando el host real).
- **`AUTH_MODE`**: `enforce` (defecto desde el 2026-10-21) bloquea con 401/403; un valor mal escrito también cae en `enforce`. `monitor` NO bloquea y registra en consola `[auth:monitor] bloquearía …`; `off` solo para emergencias. **Volver atrás sin redesplegar**: en Render → Environment → `AUTH_MODE=monitor` (reinicia solo, ~1 min) y se avisa en el registro de arranque. `ALLOW_LEGACY_LOGIN` ahora es `false` por defecto (el login antiguo con la contraseña en la URL responde 410 `UPDATE_REQUIRED`); `true` lo reactiva. Pendiente del plan: definir `JWT_SECRET` en Render y purgar el texto plano (`PURGE_PLAINTEXT=true` una sola vez, irreversible).
- **Fuerza bruta**: 8 fallos por usuario+IP y 60 por IP cada 15 min → 429 con `Retry-After`.
- **App**: `services/auth_client.dart` (`AuthClient`) se instala en `main()` con `http.runWithClient` y añade el token **solo** al origen de `ApiConfig.baseUrl`; ante un 401 de sesión (`TOKEN_EXPIRADO/INVALIDO`, `SESION_REVOCADA`) `SessionGuard` descarta el token (sin borrar datos ni cambios pendientes sin conexión) y lleva al login con el motivo. `AuthService` guarda el token (`authToken`); una sesión abierta contra un servidor antiguo sin tokens se marca `legacySession`. Los errores de gestión de usuarios llegan como `ApiMessageException` con el texto del servidor.
- **Tests**: `npm test` en `Backend/` (92: unitarias de auth, integración con el servidor real en una BD aparte —matriz de permisos, migración, revocación—, purga y evaluación); `test/auth_client_test.dart` en la app.

## Evaluación docente (CU-08)

- **Flujo**: el Admin crea un periodo (borrador) con su instrumento y ventana de fechas, lo publica (se congela y se toma la "foto" de curso+docente) y lo cierra; el estudiante evalúa a cada docente de sus cursos matriculados una sola vez; los resultados (Admin y docente) existen **solo con el periodo cerrado**.
- **Backend** (repo aparte en `Backend/`, módulo `evaluations.js`, rutas `/evaluations/*`, tablas `evaluation_*` creadas al arrancar con `CREATE TABLE IF NOT EXISTS`; `npm test` usa una BD aparte `bdgesacad_test`). Reglas: anonimato (participación y respuestas en tablas sin vínculo; sin hora ni id en las respuestas), una respuesta por estudiante/curso (PK), **participantes elegidos por el Admin** (`evaluation_scope`: docente → curso → estudiantes; `scope_mode` all/custom; solo los habilitados pueden responder; selección congelada al publicar), mínimo de respuestas (3–50, def. 5) para mostrar resultados, nada de promedios parciales. **Identidad**: con `AUTH_MODE=enforce` sale de la sesión (token) y el `adminId/studentId/teacherId` del cliente solo se contrasta (403 `IDENTIDAD_NO_COINCIDE` si no coincide).
- **App**: `models/evaluation_models.dart`; métodos en `ApiService` (sección "CU-08"; lecturas con caché, escrituras del Admin lanzan `EvalApiException`); `screens/evaluation/*` (estudiante: lista + formulario por pasos; Admin: lista, detalle con pestañas Resumen/Instrumento/Resultados; docente: resultados); `widgets/eval/*` (`HexMedallion`, `RatingOrbs`, `ScoreRing`, `NeonFrame`, `DimensionRadar`, `EvalResultCard`, `EvaluationEntryCard` que se inserta en los dashboards).
- **Sin conexión**: el envío del estudiante usa `OfflineQueue` (`OperationType.evaluation`); 409 `YA_EVALUADO` se trata como éxito (idempotente). Las acciones del Admin requieren conexión.
- Tests: `test/evaluation_test.dart` (el primer `pump` de una animación recién iniciada cuenta como tiempo 0: usar el helper `espera`).

## Reuniones virtuales (CU-09)

- **Backend** (`Backend/meetings.js`, tabla `course_meetings` creada al arrancar): `GET /courses/:id/meeting` (miembros del curso), `POST /courses/:id/meeting` y `POST /courses/:id/meeting/end` (solo el docente del curso). Una reunión vigente por curso; las olvidadas dejan de verse a las 6 h. Sin `url` crea una sala de Jitsi (`JITSI_BASE_URL`, por defecto `https://meet.jit.si`) con nombre aleatorio; con `url` solo acepta **https** de Google Meet, Zoom o Teams (anti-phishing). Pruebas en `test/auth.server.test.js`.
- **App**: `models/meeting_model.dart`, `services/meeting_service.dart`, `widgets/meeting/meeting_widgets.dart` (`CourseMeetingCard`, se inserta sobre las pestañas de `student_course_content` y `teacher_course_content`; sondea cada 30 s). "Unirse" usa `url_launcher` (sin dependencias nuevas). Tests: `test/meeting_test.dart`.

## Modo invitado (CU-10)

- **Entrada**: botón "Explorar como invitado" en `LoginScreen` → `screens/guest/guest_home.dart`. No hay sesión ni token (no se llama a `saveSession`); solo se usa `GET /public/university`, público.
- **Pestañas**: Inicio (perfiles y funciones), Universidad (presentación, programas, "Mi ruta de matrícula" con requisitos que el visitante marca —se guardan solo en su equipo— y contacto) y Probar la app (`guest_demo.dart`: demo de Estudiante/Docente/Admin con **datos de ejemplo**, reutilizando `CourseCard`, `ActivityCard`, `RatingOrbs`, `CourseMeetingCard` con un `MeetingService` simulado en memoria; nada toca el servidor).
- **Contenido editable**: el Admin lo edita en `screens/admin/admin_university_info.dart` (menú lateral "Información para invitados"). Backend `Backend/publicinfo.js`: `GET/PUT /public/university` (tabla `public_content`); el PUT es solo Admin, valida longitudes, exige `https://` en el sitio web y descarta campos desconocidos. Mientras no se edite se sirve contenido de EJEMPLO con `isSample: true` y la app lo avisa. **No inventar datos reales de la universidad.**
- Sin conexión se muestra la última copia (`guest_university_v1` en SharedPreferences). Tests: `test/guest_test.dart` y la sección "Información pública" de `Backend/test/auth.server.test.js`.

## Notificaciones (CU-11)

- **Bandeja persistente en el servidor** (`Backend/notifications.js`, tablas `notifications` y `notification_prefs`, creadas al arrancar): una fila por destinatario, con `read_at` (el leído se sincroniza entre dispositivos), `dedupe_key` único por usuario (un hecho no avisa dos veces) y retención de 90 días. Rutas: `GET /notifications` (paginada por cursor, filtros `type`/`unread`), `GET /notifications/summary?after=` (sondeo ligero: contador + novedades), `POST /notifications/read`, `DELETE /notifications/:id`, `POST /notifications/clear`, `GET/PUT /notifications/preferences`. La identidad sale del token (en modo `monitor` sin token se acepta `userId`/`rol` del cliente, igual que el resto de rutas).
- **Quién avisa a quién** (emisores en `server.js`, nunca lanzan: una notificación fallida no rompe la acción): actividad creada/eliminada → estudiantes del curso; entrega (`addResource`) → docentes del curso (un aviso por estudiante y hora); nota (`gradeActivity`) → el estudiante (no repite la misma nota); reunión → estudiantes; evaluación publicada → estudiantes habilitados, cerrada → Admin y docentes; matrícula (`updateMembers`/`addCourse`) → solo quien entra; `USUARIO_CREADO/ELIMINADO/SOLICITUD_RESET_CONTRASENA` (en `registrarLog`) → Admins. Recordatorios de cierre (24 h y 3 h) solo a quien NO ha entregado, cada 15 min (`NOTIF_SCHEDULER=off` lo desactiva; las pruebas lo apagan). La primera vez que se abre la bandeja se siembra con lo de los últimos 7 días.
- **App**: `models/notification_models.dart`, `services/notification_service.dart` (singleton: `unread` para la insignia, `arrivals` para avisos en pantalla; sondeo cada 20 s en primer plano, se pausa en segundo plano y se pone al día al volver; copia sin conexión de la primera página), `screens/notifications/{notifications_panel,notification_router,notification_toaster}.dart`. El panel agrupa por día, filtra por tipo/sin leer, desliza para leer o descartar (con reversa si falla), pagina al llegar al final y tiene preferencias por tipo. `abrirReferencia` lleva a la actividad/curso/reunión/evaluación según el rol y la usa también el calendario. La ruta antigua `/users/getNotifications` se conserva para apps desactualizadas. Push con la app cerrada requeriría Firebase (no implementado).
- Tests: `test/notifications_test.dart` y la sección "Notificaciones persistentes" de `Backend/test/auth.server.test.js`.

## Calendario unificado (CU-12)

- **Backend** (`Backend/calendar.js`): `GET /calendar/events?from&to` (máx. 400 días) reúne por rol actividades con SU estado (estudiante: pendiente/entregada/calificada/vencida; docente: entregas y por calificar), reuniones y ventanas de evaluación. Cada fuente falla por separado. **Suscripción**: `POST/GET/DELETE /calendar/feed` administran un enlace secreto (token de 192 bits; solo se guarda su SHA-256) y `GET /calendar/feed/:token.ics` entrega un iCalendar (RFC 5545: escapes, líneas de 75 octetos sin partir UTF-8, alarmas 1 día y 3 h antes) para Google Calendar/Outlook/Apple. Regenerar invalida el anterior.
- **App**: `models/calendar_models.dart` (`CalEvent`: la hora de Colombia UTC-5 decide el día), `services/calendar_service.dart` (copia sin conexión; enlaces de suscripción), `utils/colombia_holidays.dart` (festivos de CUALQUIER año: Ley Emiliani + Pascua; antes era una lista fija de 2026 sin Sagrado Corazón), `screens/calendar/calendar_widgets.dart` (próximo vencimiento con cuenta regresiva, carga semanal, acciones por evento, hoja de sincronización) y `calendar_screen.dart` (vistas Mes/Semana/Agenda, búsqueda, filtro por curso, leyenda por tipo, recordatorios personales locales). "Añadir a Google Calendar" por evento y suscripción completa.
- Tests: `test/calendar_logic_test.dart`, `test/calendar_ui_test.dart` y la sección "Calendario unificado" de `Backend/test/auth.server.test.js`.

## Accessibility

CU-07 requires `Semantics` labels on all icon-only buttons, `ExcludeSemantics` on decorative images/animated counters (with a `Semantics(label)` on the parent), and `liveRegion: true` on error messages. Keep this when adding widgets.
