# GESACAD — Sistema de Gestión Académica Universitaria

[![Pruebas de la app](https://github.com/dejotat/gesacad_flutter/actions/workflows/pruebas.yml/badge.svg)](https://github.com/dejotat/gesacad_flutter/actions/workflows/pruebas.yml)
![Flutter](https://img.shields.io/badge/Flutter-3.41-02569B?logo=flutter&logoColor=white)
![Node.js](https://img.shields.io/badge/Node.js-22-339933?logo=node.js&logoColor=white)
![MySQL](https://img.shields.io/badge/MySQL-8.4-4479A1?logo=mysql&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white)

Aplicación multiplataforma (**Android y Web**) para la gestión académica de la
**Corporación Universitaria Unicomfacauca**. Tres roles —Administrador, Docente y
Estudiante— trabajan sobre una API propia (Node.js + MySQL): cursos, actividades,
entregas, calificaciones, evaluación docente, reuniones virtuales, calendario y notificaciones.

Proyecto de grado — Ingeniería de Sistemas · Autor: **Jorge Tunubala**

---

## Contenido

- [Características](#características)
- [Arquitectura](#arquitectura)
- [Inicio rápido](#inicio-rápido)
- [Docker en detalle](#docker-en-detalle)
- [Configuración](#configuración)
- [Seguridad](#seguridad)
- [Pruebas e integración continua](#pruebas-e-integración-continua)
- [Despliegue](#despliegue)
- [Generar el APK](#generar-el-apk-android)
- [Estructura del proyecto](#estructura-del-proyecto)
- [Base de datos](#base-de-datos)
- [Rendimiento y modo sin conexión](#rendimiento-y-modo-sin-conexión)
- [Accesibilidad](#accesibilidad)
- [Roles y permisos](#roles-y-permisos)
- [Notas técnicas](#notas-técnicas)
- [Documentación adicional](#documentación-adicional)

---

## Características

| CU | Funcionalidad | Rol | Descripción |
|----|---------------|-----|-------------|
| 01 | Inicio de sesión | Todos | Pantalla oscura con fondo animado (aurora y partículas, respeta «reducir movimiento»), sesión con token (JWT), indicador de seguridad de contraseña y renovación automática |
| 02 | Gestión de usuarios | Admin | Alta, edición, baja y cambio de rol; política de contraseñas |
| 03 | Gestión de cursos | Admin | Cursos, docentes y matrícula de estudiantes |
| 04 | Gestión de actividades | Docente | Actividades con ponderado (≤ 100 % por curso), adjuntos y fechas de cierre |
| 05 | Entrega de tareas | Estudiante | Archivos de hasta 5 MB (pdf, doc/docx, xlsx, pptx, imágenes, zip) |
| 06 | Calificaciones | Docente / Estudiante | Notas y comentarios, vista de progreso con gráficas |
| 07 | Accesibilidad | Todos | `Semantics` en toda la interfaz (TalkBack/VoiceOver) y lectura en voz alta |
| 08 | Evaluación docente | Admin / Estudiante / Docente | Periodos, participantes elegidos por el Admin, respuestas anónimas y resultados al cierre |
| 09 | Reuniones virtuales | Docente / Estudiante | Sala de Jitsi o enlace de Google Meet, Zoom o Teams (solo https) por curso |
| 10 | Modo invitado | Público | Presentación de la universidad, ruta de matrícula y demo interactiva con datos de ejemplo |
| 11 | Notificaciones | Todos | Bandeja persistente sincronizada entre dispositivos, filtros y preferencias por tipo |
| 12 | Calendario unificado | Todos | Vistas mes/semana/agenda, festivos de Colombia, suscripción `.ics` (Google/Outlook/Apple) |
| 13 | Notificaciones push | Android | Avisos con la app cerrada vía Firebase Cloud Messaging (requiere configuración) |

También: **modo sin conexión** (lectura en caché y cola de escritura que se sincroniza sola),
perfil con foto, recuperación de contraseña asistida por el Admin, chatbot de preguntas
frecuentes y cinco temas de color (incluido modo oscuro).

---

## Arquitectura

```
        ┌──────────────────────────────────────────────┐
        │  App Flutter (Android · Web)                 │
        │  screens · widgets · services · models       │
        └───────────────────────┬──────────────────────┘
                                │ HTTPS · JWT (Bearer)
        ┌───────────────────────▼──────────────────────┐
        │  API Node.js + Express  (Backend/)           │
        │  auth · permisos por rol · evaluaciones      │
        │  reuniones · notificaciones · calendario     │
        └──────┬───────────────┬───────────────┬───────┘
               │               │               │
        ┌──────▼─────┐  ┌──────▼──────┐  ┌─────▼──────────┐
        │  MySQL 8.4 │  │ Cloudinary  │  │ Firebase (FCM) │
        │  (datos)   │  │ (archivos)  │  │ (push, opcional)│
        └────────────┘  └─────────────┘  └────────────────┘
```

- **Producción:** API en Render (despliegue automático al hacer push a `master`).
- **Local o entrega:** todo el sistema (base, API y web) con **Docker Compose**.
- El backend vive en `Backend/`, que es un **repositorio aparte** (`dejotat/gesacad-backend`,
  privado); en este repositorio solo se registra su versión.

### Stack

| Capa | Tecnología |
|------|------------|
| App | Flutter 3.41 / Dart 3 · `http` · `shared_preferences` · `fl_chart` · `table_calendar` · `google_fonts` · `phosphor_flutter` · `flutter_tts` · `url_launcher` · `firebase_messaging` |
| API | Node.js 22 · Express · `mysql2` (pool de conexiones) · `multer` · Cloudinary |
| Seguridad | scrypt (contraseñas) · JWT HS256 · permisos por ruta · límite de intentos |
| Datos | MySQL 8.4 |
| Contenedores | Docker Compose · nginx sin privilegios para la web |
| Calidad | GitHub Actions (análisis estático + pruebas de app y de API) |

---

## Inicio rápido

### Opción A — Docker (recomendada)

Requiere [Docker Desktop](https://www.docker.com/products/docker-desktop). Levanta MySQL, la API y la web.

```powershell
.\docker\iniciar.ps1          # Windows (PowerShell)
./docker/iniciar.sh           # Linux / macOS
```

El script crea el `.env` con **contraseñas aleatorias** (si no existe), construye, arranca y abre el navegador.
Al terminar muestra el usuario administrador y su contraseña **una sola vez** (también queda en `.env`).

| Servicio | Dirección |
|----------|-----------|
| **Aplicación web** | http://localhost:5000 |
| API (solo datos) | http://localhost:8081 — abrirla en un navegador te lleva a la app |
| MySQL (para Workbench/DBeaver) | `127.0.0.1:3307` |

> Con internet lenta, `.\docker\iniciar.ps1 -WebLocal` compila la web en tu equipo en lugar de
> descargar la imagen de Flutter (varios GB).

### Opción B — Desarrollo local (sin Docker)

```bash
flutter pub get
flutter run -d chrome         # web
flutter run                   # emulador o dispositivo Android
flutter analyze               # análisis estático
```

La app apunta por defecto a la API de producción. Para usar un backend local no hace falta editar código:

```bash
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8081
# Emulador Android:   http://10.0.2.2:8081
# Dispositivo físico: http://192.168.X.X:8081
```

El backend local (`Backend/`, repositorio aparte): copia `Backend/.env.example` como `Backend/.env`,
apúntalo a un MySQL local y ejecuta `npm install` y `npm start`.
En Windows, `.\tool\dev_local.ps1` inicia MySQL, el backend y la app juntos.

---

## Docker en detalle

### Qué se levanta

| Servicio | Imagen | Notas |
|----------|--------|-------|
| `db` | `mysql:8.4` | Volumen persistente; carga el esquema base solo la primera vez |
| `backend` | `Backend/Dockerfile` (Node 22, dos etapas) | Usuario sin privilegios, `HEALTHCHECK` a `/health` |
| `web` | `Dockerfile` (Flutter compilado + nginx) | nginx sin privilegios, cabeceras de seguridad, caché adecuada |

Los puertos solo escuchan en `localhost`. `docker compose ps` muestra el estado y la salud;
`docker compose logs -f backend` los registros; `docker compose down` detiene **conservando** los datos
(`down -v` los borra).

### La base de datos nace vacía

MySQL carga `Backend/db/01-esquema.sql` (estructura, sin datos ni cuentas); el servidor crea el
resto de tablas al arrancar. El primer administrador sale de `ADMIN_BOOTSTRAP_USER` y
`ADMIN_BOOTSTRAP_PASSWORD`, y **solo se crea si no existe ningún Admin**. Desde ahí se crean los demás
usuarios en la app.

> Los volcados históricos `gesacad_db4free.sql` y `bdgesacad.sql.sql` ya no están en el repositorio, pero siguen en su historial y contienen cuentas con
> contraseñas reales: **no los uses** para Docker ni los publiques.

### Scripts de `docker/`

| Script | Para qué sirve |
|--------|----------------|
| `iniciar.ps1` / `iniciar.sh` | Crea el `.env`, construye y arranca; abre la app (`-NoAbrir` lo evita) |
| `datos-demo.ps1` | Carga docentes, estudiantes y cursos de prueba (`demo_*`, contraseña `Demo#2026`, guardadas cifradas) |
| `respaldo.ps1` | Copia de seguridad en `respaldos\`; `-Restaurar archivo.sql` la restaura |
| `migrar-desde-nube.ps1` | Copia una base MySQL de la nube a Docker (solo lectura en el origen) |
| `publicar.ps1` | Construye y etiqueta las imágenes para Docker Hub; solo con `-Subir` las publica |
| `entrega/` | Compose, script y guía para ejecutar el sistema **sin el código fuente** |

**Conectar una herramienta a la base:** host `127.0.0.1`, puerto **3307** (no el 3306, que suele estar
ocupado por un MySQL local), y `DB_USER`, `DB_PASS` y `DB_NAME` de tu `.env`.

### Migrar la base de la nube a Docker

`.\docker\migrar-desde-nube.ps1` pide servidor, puerto, usuario, contraseña (oculta, no se guarda)
y base —o los lee de `.env.nube`, copia de `.env.nube.example`, que git ignora—. Hace un respaldo de
lo actual, descarga la copia de la nube (**solo lectura: el origen no se modifica**), pide confirmar con
`SI`, restaura, muestra las filas por tabla y los usuarios por rol, y reinicia la API.
Después la base de Docker es una **copia independiente**: lo que se agregue allí no llega a la nube.
Si algo sale mal: `.\docker\respaldo.ps1 -Restaurar respaldos\antes-de-migrar-FECHA.sql`.

### Ejecutar en otro equipo (sin el código)

La carpeta `docker/entrega/` contiene `compose.yaml`, `iniciar.ps1` y `LEEME.md`. En el otro equipo basta
Docker Desktop: `.\iniciar.ps1` crea el `.env`, carga o descarga las imágenes y arranca todo; luego se
abre http://localhost:5000. Las imágenes se generan con `docker\publicar.ps1`, que las etiqueta como
`<usuario>/gesacad-{db,backend,web}`; también pueden entregarse en un archivo con `docker save`.

---

## Configuración

### Variables de Docker (`.env`, plantilla `.env.docker.example`)

| Variable | Obligatoria | Descripción |
|----------|:-----------:|-------------|
| `DB_USER`, `DB_PASS`, `MYSQL_ROOT_PASSWORD` | Sí | Credenciales de MySQL |
| `JWT_SECRET` | Sí | Secreto de las sesiones (aleatorio, mínimo 16 caracteres) |
| `ADMIN_BOOTSTRAP_USER`, `ADMIN_BOOTSTRAP_PASSWORD` | Primer arranque | Primer administrador de una base nueva |
| `DB_NAME`, `DB_HOST_PORT` | No | Nombre de la base (`bdgesacad`) y puerto local de MySQL (`3307`) |
| `CLOUDINARY_*` | No | Sin ellas todo funciona menos subir archivos |
| `FIREBASE_SERVICE_ACCOUNT` | No | Activa las notificaciones push |
| `API_BASE_URL` | No | Dirección de la API **para el navegador**; se graba al compilar la web |

Si cambias `API_BASE_URL`: `docker compose up -d --build web`.

### Variables del backend (`Backend/.env`, plantilla `Backend/.env.example`)

`DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASS`, `DB_NAME`, `PORT` (8081), `JWT_SECRET`, `AUTH_MODE`
(`enforce` por defecto), `DB_POOL_SIZE`, `CLOUDINARY_*`, `FIREBASE_SERVICE_ACCOUNT`. El `.env` **no se versiona**.

### URL de la API en la app

`lib/config/api_config.dart` define `baseUrl` y todas las rutas. Se sobrescribe sin tocar código con
`--dart-define=API_BASE_URL=...`. No se deben versionar URLs de desarrollo local.

### Notificaciones push (opcional)

Firebase se configura con `--dart-define` (`FIREBASE_API_KEY`, `FIREBASE_APP_ID`,
`FIREBASE_MESSAGING_SENDER_ID`, `FIREBASE_PROJECT_ID`), sin `google-services.json`. Copia
`firebase.env.example` como `firebase.env` (git lo ignora) y compila con `.\tool\compilar_apk.ps1`.
En el servidor hace falta `FIREBASE_SERVICE_ACCOUNT`. Solo Android; sin esta configuración la bandeja
de notificaciones funciona igual. El envío contra FCM real **requiere validarse con un teléfono**.

---

## Seguridad

- **Contraseñas** con **scrypt** (`pass_hash`); nunca se devuelven por la API. Política: 8–64 caracteres con
  mayúscula, minúscula, número y símbolo, y sin el nombre de usuario (validada en app y servidor). La app muestra
  una **barra de seguridad** de colores mientras se escribe.
- **Sesiones** con JWT HS256 (7 días) en `Authorization: Bearer`. Cambiar contraseña o rol, eliminar al usuario o
  `POST /auth/logout-all` revocan los tokens. La app renueva el token al abrir si pasaron más de 12 horas.
- **Permisos por ruta:** el Admin gestiona usuarios y cursos; el docente solo sus cursos y actividades; el
  estudiante solo lo suyo. La identidad sale de la sesión, no de lo que envía el cliente.
- **Fuerza bruta:** 8 fallos por usuario+IP y 60 por IP cada 15 min → `429` con `Retry-After`.
- **Archivos:** límites y tipos validados en app y servidor; se escriben a disco temporal con nombre aleatorio y se
  borran al terminar; el endpoint `/files/proxy` (conservado para versiones antiguas) solo reenvía `https://res.cloudinary.com`.
- **Anonimato en la evaluación docente:** participación y respuestas viven en tablas sin vínculo entre sí.
- **Contenedores:** la API y la web corren sin privilegios; los puertos solo escuchan en `localhost`;
  las imágenes no contienen secretos ni datos.
- **Secretos:** `.env`, `.env.nube`, `firebase.env` y `respaldos/` están fuera de git.

---

## Pruebas e integración continua

```bash
flutter analyze
flutter test                          # pruebas de la app (widgets, lógica, modo sin conexión)
cd Backend && npm test                # pruebas de la API contra una base MySQL aparte
```

GitHub Actions (`.github/workflows/pruebas.yml`) ejecuta en cada push: **app** → análisis y pruebas;
**backend** → MySQL 8 de servicio, `npm ci` y `npm test`. Render despliega al hacer push sin esperar las
pruebas, así que conviene revisar la pestaña *Actions* después de cada push.
Casos de caja negra por caso de uso: [`docs/pruebas-caja-negra.md`](docs/pruebas-caja-negra.md).

---

## Despliegue

**Backend en Render:** el repositorio `gesacad-backend` se despliega al hacer push a `master` (`npm install` y
`npm start`, ~45 s). Las migraciones se aplican al arrancar y son aditivas e idempotentes: nunca borran datos.

```
GET /health  →  { status, version, uptimeSeconds, auth, push }
```

`version` es el commit corto desplegado: tras un push, debe coincidir con `git rev-parse --short=7 HEAD`.
Las bases en la nube limitan las conexiones simultáneas; si el plan es pequeño, baja `DB_POOL_SIZE`.

**Todo en Docker:** ver [Docker en detalle](#docker-en-detalle).

---

## Generar el APK (Android)

En Windows, si la ruta de Flutter tiene espacios, **no uses `flutter build apk` directamente**: usa el acceso
directo sin espacios.

```powershell
C:\flutter_sdk\bin\flutter.bat build apk --release
# Con notificaciones push: .\tool\compilar_apk.ps1   (lee firebase.env)
```

Salida: `build\app\outputs\flutter-apk\app-release.apk`. El `dependency_overrides` de `objective_c` en
`pubspec.yaml` corrige el mismo problema de rutas con espacios: **no lo quites**.

> La compilación *release* usa hoy la firma de depuración; para publicar en una tienda hace falta una clave
> de lanzamiento propia.

---

## Estructura del proyecto

```
gesacad_flutter/
├── lib/
│   ├── main.dart              Entrada: splash, sesión y rol
│   ├── config/                api_config, temas, tokens de diseño
│   ├── models/                Usuario, curso, actividad, evaluación, calendario…
│   ├── services/              ApiService (HTTP + caché), Auth, cola sin conexión, push…
│   ├── screens/               admin · teacher · student · evaluation · calendar ·
│   │                          notifications · profile · guest · auth
│   ├── widgets/               Componentes reutilizables (tarjetas, menú de cuenta, barras…)
│   └── utils/ · helpers/      Transiciones, plataforma web/móvil, visor de archivos
├── test/                      Pruebas de la app
├── Backend/                   API Node.js (repositorio aparte)
├── docker/                    Scripts, nginx y paquete de entrega
├── docs/                      Documentación adicional
├── tool/                      Scripts de desarrollo y compilación del APK
├── compose.yaml · Dockerfile  Orquestación y compilación de la web
└── .github/workflows/         Integración continua
```

---

## Base de datos

18 tablas (MySQL 8.4). Las cinco primeras vienen en el esquema base; el servidor crea el resto al arrancar.

| Grupo | Tablas |
|-------|--------|
| Núcleo académico | `users`, `courses`, `registration`, `activities`, `resolutionsactivities` |
| Auditoría | `system_logs` |
| Evaluación docente | `evaluation_periods`, `evaluation_questions`, `evaluation_targets`, `evaluation_scope`, `evaluation_participation`, `evaluation_answers` |
| Reuniones | `course_meetings` |
| Notificaciones | `notifications`, `notification_prefs`, `push_devices` |
| Calendario | `calendar_feeds` |
| Invitados | `public_content` |

---

## Rendimiento y modo sin conexión

- **Caché de dos niveles** en `ApiService`: memoria (5 min) y `SharedPreferences` (muestra datos de la sesión anterior
  mientras carga). Se invalida al crear, editar o eliminar cursos y actividades.
- **Tolerancia a arranques en frío:** timeout de 30 s y un reintento de las lecturas; `ping()` al abrir despierta el servidor.
- **Modo sin conexión:** la app mide si el *servidor* responde (no solo el wifi). Las lecturas se sirven desde la copia
  local; las entregas del estudiante y las notas del docente van a una **cola persistente** que se sincroniza sola, reintenta
  con espera creciente y evita duplicados.
- **Zona horaria:** las fechas se guardan en UTC y se muestran en hora de Colombia (UTC-5) con `ActivityModel.toCol()`.

---

## Accesibilidad

Cumple CU-07 con `Semantics` de Flutter (TalkBack/VoiceOver): etiquetas en todos los botones solo con icono,
`ExcludeSemantics` en imágenes decorativas y contadores animados (con la etiqueta en el padre), descripciones completas
en tarjetas y gráficas, y errores como `liveRegion` que se anuncian al aparecer. Incluye lectura en voz alta del contenido.

---

## Roles y permisos

| Rol | Permisos principales |
|-----|----------------------|
| **Admin** | Gestiona usuarios, cursos y matrícula; crea y cierra periodos de evaluación; ve los resultados; edita la información para invitados |
| **Docente** | Crea actividades en sus cursos, califica entregas, convoca reuniones, ve los resultados de su evaluación |
| **Estudiante** | Ve actividades, entrega tareas, consulta calificaciones, evalúa a sus docentes y se une a reuniones |

---

## Notas técnicas

- **`LOGIN_SUCCESFULLY`** (una sola «L»): es la clave de respuesta del login en el servidor original; se conserva a propósito.
- **Cloudinary con `resource_type: "raw"`:** hace que el tipo MIME se determine por la extensión; con `"auto"`, los PDF quedarían
  como imágenes.
- **Visualización de archivos:** la app abre los archivos con la URL directa de Cloudinary (PDF e imágenes directamente;
  Word, Excel y PowerPoint con el visor de Office Online). `GET /files/proxy?url=…` sigue disponible en el servidor para
  versiones antiguas de la app, pero la versión actual no lo usa.
- **Parámetros en la URL:** deben pasar por `Uri.encodeComponent` (el servidor falla con `/ ? # %`).
- **Singleton:** `ApiService` es una única instancia que comparte el caché entre pantallas.
- **Sin gestor de estado externo:** se usan singletons y `ValueNotifier`.

---

## Documentación adicional

- [`docs/pruebas-caja-negra.md`](docs/pruebas-caja-negra.md) — casos de prueba funcionales.
- [`docker/entrega/LEEME.md`](docker/entrega/LEEME.md) — ejecutar el sistema en otro equipo.
- `Backend/.env.example`, `.env.docker.example`, `firebase.env.example` — plantillas de configuración.

---

## Créditos

- **Autor:** Jorge Tunubala — Corporación Universitaria Unicomfacauca
- **Tecnologías:** Flutter / Dart, Node.js / Express, MySQL, Docker, Cloudinary, Firebase
- **Gráficas:** [fl_chart](https://pub.dev/packages/fl_chart) (licencia BSD)
