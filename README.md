# GESACAD — Sistema de Gestión Académica Universitaria

**Corporación Universitaria Unicomfacauca**  
Proyecto de Grado — Ingeniería de Sistemas  
Estudiante: Jorge Tunubala  
Versión: 1.1.2

---

## Descripción

GESACAD es una aplicación multiplataforma (Android + Web) desarrollada en Flutter que
implementa los 7 casos de uso del Sistema de Gestión Académica Universitaria (IEEE 830).
Permite a estudiantes entregar tareas, a profesores crear actividades y calificar
entregas, y al administrador gestionar usuarios y cursos desde cualquier dispositivo.

---

## Arquitectura del Sistema

```
┌─────────────────────────────────────────────────────┐
│              GESACAD Flutter (Android / Web)         │
│  lib/                                               │
│  ├── main.dart              Splash + SplashScreen   │
│  ├── config/api_config.dart URLs del backend        │
│  ├── models/                UserModel, CourseModel  │
│  │                          ActivityModel           │
│  ├── services/                                      │
│  │   ├── api_service.dart   HTTP + caché + retry    │
│  │   ├── auth_service.dart  Sesión SharedPreferences│
│  │   └── settings_service.dart  Temas + config      │
│  ├── screens/                                       │
│  │   ├── login_screen.dart       CU-01              │
│  │   ├── admin/                  CU-02, CU-03, CU-06│
│  │   ├── teacher/                CU-04, CU-06       │
│  │   ├── student/                CU-05, CU-06       │
│  │   ├── calendar/               Calendario         │
│  │   ├── notifications/          Notificaciones     │
│  │   └── profile/                Perfil usuario     │
│  ├── utils/route_transitions.dart  Animaciones nav  │
│  └── widgets/               ActivityCard, CourseCard│
└─────────────────────────────────────────────────────┘
          │ HTTPS (Railway)
┌─────────────────────────────────────────────────────┐
│           Backend Node.js + Express                  │
│           Desplegado en Railway                      │
│           URL: gesacad-backend-production.up.railway.app │
└─────────────────────────────────────────────────────┘
          │
    ┌─────┴──────┐
    │            │
┌───────┐  ┌───────────┐
│ MySQL │  │ Cloudinary│
│Railway│  │  (archivos│
│       │  │   y fotos)│
└───────┘  └───────────┘
```

---

## Stack Técnico

| Componente          | Tecnología                              |
|---------------------|-----------------------------------------|
| Framework móvil     | Flutter 3 / Dart 3                      |
| Lenguaje            | Dart 3                                  |
| HTTP + caché        | `http ^1.2.0` + SharedPreferences       |
| Sesión local        | `shared_preferences ^2.3.2`             |
| Selección archivos  | `file_picker ^8.0.0`                    |
| Gráficas            | `fl_chart ^0.68.0` (libre, sin licencia)|
| Tipografía          | `google_fonts ^6.2.1`                   |
| Calendario          | `table_calendar ^3.2.0`                 |
| Localización        | `flutter_localizations` (SDK)           |
| Backend             | Node.js + Express                       |
| Base de datos       | MySQL (Railway)                         |
| Almacenamiento      | Cloudinary (archivos + fotos de perfil) |
| Despliegue backend  | Railway (auto-deploy desde GitHub)      |

---

## Casos de Uso Implementados (IEEE 830)

| CU    | Nombre                          | Rol          | Pantalla principal                    |
|-------|---------------------------------|--------------|---------------------------------------|
| CU-01 | Inicio de sesión                | Todos        | `login_screen.dart`                   |
| CU-02 | Gestión de usuarios             | Admin        | `admin_users.dart`                    |
| CU-03 | Gestión de cursos               | Admin        | `admin_courses.dart`                  |
| CU-04 | Gestión de actividades          | Teacher      | `add_activity_screen.dart`            |
| CU-05 | Entrega de tareas               | Student      | `activity_detail_screen.dart`         |
| CU-06 | Visualización de calificaciones | Teacher/Std  | `grades_screen.dart`                  |
| CU-07 | Accesibilidad (TalkBack)        | Todos        | Todos los widgets con `Semantics`     |

### Funcionalidades adicionales implementadas

| Funcionalidad              | Descripción                                                  |
|----------------------------|--------------------------------------------------------------|
| Perfil de usuario          | Foto, bio, teléfono, programa, correo — guardados en MySQL   |
| Recuperación de contraseña | Notificación al Admin + WhatsApp directo                     |
| Calendario académico       | Actividades reales + festivos Colombia 2026 + recordatorios  |
| Notificaciones             | Por rol: Admin (sistema), Profesor (entregas), Estudiante    |
| Chatbot                    | Respuestas predefinidas sobre Unicomfacauca                  |
| Múltiples temas            | 5 temas de color seleccionables desde Ajustes                |
| TalkBack / VoiceOver       | Accesibilidad completa con `Semantics` en todos los roles    |

---

## Configuración del Entorno de Desarrollo

### 1. Variables de entorno del Backend (`Backend/.env`)

```env
DB_HOST=...
DB_USER=...
DB_PASS=...
DB_NAME=...
DB_PORT=3306
PORT=8081
CLOUDINARY_CLOUD_NAME=...
CLOUDINARY_API_KEY=...
CLOUDINARY_API_SECRET=...
```

### 2. URL del Backend (`lib/config/api_config.dart`)

```dart
// Producción Railway (por defecto):
static const String baseUrl =
    'https://gesacad-backend-production.up.railway.app';

// Desarrollo local Web (Chrome):
// static const String baseUrl = 'http://localhost:8081';

// Emulador Android:
// static const String baseUrl = 'http://10.0.2.2:8081';

// Dispositivo físico (WiFi local):
// static const String baseUrl = 'http://192.168.X.X:8081';
```

### 3. Instalar dependencias

```bash
flutter pub get
```

### 4. Ejecutar en desarrollo (Web / Chrome)

```bash
flutter run -d chrome
```

### 5. Ejecutar en emulador Android

```bash
flutter run
```

---

## Generar APK Release (Android)

> **IMPORTANTE:** No usar `flutter build apk` directamente en Windows si la ruta
> de Flutter tiene espacios (`C:\Users\JORGE TECHNOLOGY\flutter`). Usar la junction:

```powershell
# Desde PowerShell, en la carpeta del proyecto:
C:\flutter_sdk\bin\flutter.bat build apk --release
```

El APK se genera en:
```
build\app\outputs\flutter-apk\app-release.apk
```

**Tamaño aproximado:** ~57 MB

---

## Estructura de la Base de Datos (MySQL)

| Tabla                   | Descripción                                          |
|-------------------------|------------------------------------------------------|
| `users`                 | Usuarios con rol (Admin/Teacher/Student) + perfil    |
| `courses`               | Cursos académicos                                    |
| `registration`          | Matrícula: qué usuario pertenece a qué curso         |
| `activities`            | Actividades evaluables de cada curso                 |
| `resolutionsactivities` | Entregas y calificaciones de cada estudiante         |
| `system_logs`           | Auditoría de acciones críticas (login, creación, etc)|

---

## Rendimiento y Optimizaciones

### Caché en dos niveles (ApiService)
- **Memoria (TTL 5 min):** respuesta en < 1ms para datos recientes
- **SharedPreferences:** muestra datos de sesión anterior mientras carga del backend
- **Invalidación automática:** al crear/editar/eliminar cursos o actividades

### Tolerancia a Railway (cold start)
- **Timeout:** 30 segundos (Railway puede tardar hasta 30s en despertar un dyno)
- **Retry automático:** reintenta 1 vez tras 2s en caso de timeout
- **Ping al arrancar:** `ApiService().ping()` en el SplashScreen despierta Railway
  antes de que el usuario llegue a la pantalla con datos

### Zona horaria
- Todas las fechas de actividades se almacenan en UTC en MySQL
- Flutter convierte a hora Colombia (UTC-5) usando `ActivityModel.toCol()`

---

## Tablas de Pruebas de Caja Negra

### CU-01 — Inicio de Sesión (RF01)

| ID    | Condición de prueba               | Resultado esperado                                      |
|-------|-----------------------------------|---------------------------------------------------------|
| CP-01 | Usuario vacío                     | "El campo Usuario es obligatorio"                       |
| CP-02 | Contraseña vacía                  | "El campo Contraseña es obligatorio"                    |
| CP-03 | Usuario = "   " (solo espacios)   | "El usuario no puede contener solo espacios"            |
| CP-04 | Usuario = "ab" (< 3 chars)        | "El usuario debe tener al menos 3 caracteres"           |
| CP-05 | Usuario = 51 caracteres           | "Máximo 50 caracteres permitidos"                       |
| CP-06 | Contraseña = "abc" (< 4 chars)    | "La contraseña debe tener al menos 4 caracteres"        |
| CP-07 | Credenciales incorrectas          | "Usuario o contraseña incorrectos. Verifica tus datos." |
| CP-08 | Servidor apagado / timeout        | "El servidor tardó demasiado. Verifica tu conexión."    |
| CP-09 | Password = "p@$$#/" (chars esp.)  | Login exitoso (Uri.encodeComponent previene crash)      |
| CP-10 | Credenciales Admin válidas        | Navega a AdminHome                                      |
| CP-11 | Credenciales Teacher válidas      | Navega a TeacherHome                                    |
| CP-12 | Credenciales Student válidas      | Navega a StudentHome                                    |

### CU-04 — Crear Actividad (RF06, RF07)

| ID    | Condición de prueba                   | Resultado esperado                                      |
|-------|---------------------------------------|---------------------------------------------------------|
| CA-01 | Título vacío                          | "Campo requerido"                                       |
| CA-02 | Descripción vacía                     | "Campo requerido"                                       |
| CA-03 | Ponderado vacío                       | "Requerido"                                             |
| CA-04 | Ponderado = 0 o > 100                 | "Entre 1 y 100"                                         |
| CA-05 | Ponderado > disponible en curso       | SnackBar rojo con el máximo disponible                  |
| CA-06 | Fecha/hora cierre ≤ fecha/hora inicio | "La fecha y hora de cierre deben ser posteriores"       |
| CA-07 | Ponderado disponible = 0%             | Banner rojo, botón deshabilitado                        |

### CU-05 — Entrega de Tareas (RF08)

| ID    | Condición de prueba               | Resultado esperado                                     |
|-------|-----------------------------------|--------------------------------------------------------|
| CE-01 | Plazo de la actividad vencido     | Botón deshabilitado, banner rojo visible               |
| CE-02 | Actividad ya entregada            | Sección "Tu entrega" visible, estado "Entregado"       |
| CE-03 | Archivo de 6 MB (> 5 MB)          | "El archivo no puede superar 5 MB"                     |
| CE-04 | Seleccionar tipo no permitido     | FilePicker solo muestra extensiones válidas            |
| CE-05 | Archivo válido + servidor OK      | Snackbar verde + estado actualizado                    |
| CE-06 | Archivo válido + servidor caído   | Snackbar rojo: "Error de conexión"                     |
| CE-07 | Cancelar el selector de archivos  | No ocurre ninguna acción                               |

### CU-02 — Gestión de Usuarios (RF03)

| ID    | Condición de prueba               | Resultado esperado                                    |
|-------|-----------------------------------|-------------------------------------------------------|
| CU-01 | Nombre de usuario vacío           | "Requerido"                                           |
| CU-02 | Nombre < 3 caracteres             | "Mínimo 3 caracteres"                                 |
| CU-03 | Nombre > 50 caracteres            | "Máximo 50 caracteres"                                |
| CU-04 | Nombre duplicado                  | SnackBar: "Ya existe un usuario con ese nombre"       |
| CU-05 | Contraseña vacía al crear         | "Requerido"                                           |
| CU-06 | Contraseña < 4 chars al crear     | "Mínimo 4 caracteres"                                 |
| CU-07 | Eliminar profesor con cursos      | Diálogo de advertencia antes de eliminar              |

---

## Accesibilidad (CU-07 — RNF03)

Implementa `Semantics` de Flutter para compatibilidad con **TalkBack** (Android):

- **Campos de texto:** `labelText` en `InputDecoration` → leídos automáticamente
- **Botones de acción:** `Semantics(label, button: true)` en todos los botones sin texto visible
- **Imágenes decorativas:** `ExcludeSemantics` para que TalkBack las ignore
- **Animaciones count-up:** `ExcludeSemantics` en número animado + `Semantics(label)` con valor final en el padre
- **Gráficas:** `Semantics(label: 'descripción de datos...')` en el wrapper, leyenda interactiva accesible
- **Tarjetas de actividad:** descripción completa del estado (nota, plazo, entrega)
- **Errores:** `liveRegion: true` — se anuncian automáticamente al aparecer

---

## Notas Técnicas Importantes

### Typo del backend (RF01)
La clave de respuesta exitosa del login es `'LOGIN_SUCCESFULLY'` (una sola 'L').
Es un error tipográfico del servidor original conservado intencionalmente para compatibilidad.

### BINARY en MySQL (contraseñas)
El query de login usa `BINARY pass = ?` para comparación case-sensitive.
Sin `BINARY`, MySQL ignora mayúsculas en la contraseña.

### resource_type: "raw" en Cloudinary
Todos los archivos se suben con `resource_type: "raw"` para que el MIME type
se determine por la extensión del nombre de archivo. Con `"auto"`, los PDFs
quedarían como imágenes y los archivos Office sin extensión.

### Proxy de archivos
El endpoint `GET /files/proxy?url=...` de Railway descarga el archivo de Cloudinary
server-to-server y lo reenvía al cliente, evitando errores CORS/401 que ocurrirían
si el navegador intentara acceder directamente a Cloudinary.

### Patrón Singleton (ApiService)
`ApiService` usa Factory Singleton para una única instancia del cliente HTTP
en toda la app, compartiendo el caché en memoria entre todas las pantallas.

### Zona horaria Colombia (UTC-5)
Las fechas de actividades se guardan en MySQL en UTC (+5h al recibir hora Colombia).
Flutter convierte a hora Colombia restando 5h usando `ActivityModel.toCol(String)`.

---

## Roles del Sistema

| Rol         | Permisos principales                                                    |
|-------------|-------------------------------------------------------------------------|
| **Admin**   | Gestionar usuarios, cursos y miembros. Ver estadísticas globales.       |
| **Teacher** | Crear/editar actividades en sus cursos. Calificar entregas.             |
| **Student** | Ver actividades, entregar tareas, consultar calificaciones.             |

---

## Créditos

- **Desarrollador:** Jorge Tunubala
- **Institución:** Corporación Universitaria Unicomfacauca
- **Framework:** Flutter / Dart — Google
- **Backend:** Node.js + Express + MySQL en Railway
- **Almacenamiento:** Cloudinary
- **Gráficas:** fl_chart (BSD License)
