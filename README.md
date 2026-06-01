# GESACAD — Sistema de Gestión Académica Universitaria

**Corporación Universitaria Unicomfacauca**  
Proyecto de Grado — Ingeniería de Sistemas  
Estudiante: Jorge Tunubala

---

## Descripción

GESACAD es una aplicación móvil Flutter que implementa los 7 casos de uso del
Sistema de Gestión Académica Universitaria (IEEE 830). Reemplaza el frontend
React original manteniendo el backend Node.js + MySQL intacto.

---

## Arquitectura

```
gesacad_flutter/
├── lib/
│   ├── main.dart                   # Punto de entrada
│   ├── config/
│   │   └── api_config.dart         # URLs del backend (cambiar IP para dispositivo físico)
│   ├── models/                     # Modelos de datos (UserModel, CourseModel, ActivityModel)
│   ├── services/
│   │   ├── api_service.dart        # HTTP al backend Node.js (Singleton, URL-encoding)
│   │   ├── auth_service.dart       # Sesión con SharedPreferences
│   │   └── (subida de archivos vía backend) # Cloudinary (servidor) / fallback local
│   ├── screens/
│   │   ├── login_screen.dart       # CU-01
│   │   ├── admin/                  # CU-02, CU-03, CU-06
│   │   ├── teacher/                # CU-04, CU-06
│   │   └── student/                # CU-05, CU-06
│   └── widgets/                    # ActivityCard, CourseCard (con Semantics)
└── android/
  └── app/
    └── (Sin Firebase por defecto — usa backend para uploads)
```

---

## Stack Técnico

| Componente         | Tecnología                        |
|--------------------|-----------------------------------|
| Framework móvil    | Flutter 3 / Dart 3                |
| HTTP               | `http ^1.2.0`                     |
| Sesión local       | `shared_preferences ^2.3.2`       |
| Selección archivos | `file_picker ^8.0.0`              |
| Gráficas           | `fl_chart ^0.68.0`                |
| Almacenamiento     | Cloudinary (vía backend)          |
| Backend            | Node.js + Express + MySQL         |

---

## Casos de Uso Implementados (IEEE 830)

| CU    | Nombre                          | Rol          | Pantalla principal                |
|-------|---------------------------------|--------------|-----------------------------------|
| CU-01 | Inicio de sesión                | Todos        | `login_screen.dart`               |
| CU-02 | Gestión de usuarios             | Admin        | `admin_users.dart`                |
| CU-03 | Gestión de cursos               | Admin        | `admin_courses.dart`              |
| CU-04 | Gestión de actividades          | Teacher      | `add_activity_screen.dart`        |
| CU-05 | Entrega de tareas               | Student      | `activity_detail_screen.dart`     |
| CU-06 | Visualización de calificaciones | Teacher/Std  | `grades_screen.dart`              |
| CU-07 | Accesibilidad (TalkBack)        | Todos        | Todos — widgets `Semantics`       |

---

## Configuración del Entorno

### 1. Backend (Node.js + MySQL)

```bash
cd gesacad-backend
npm install
# Configurar .env con credenciales MySQL
npm start   # Puerto 8081
```

### 2. Subida de archivos (actual)

La aplicación móvil usa el backend Node.js para gestionar la subida de
archivos (storage en Cloudinary) y servir los recursos. Firebase Storage
ya no está habilitado por defecto en este repo; las referencias a
servicios de Firebase fueron eliminadas.

Si en el futuro deseas reactivar Firebase Storage, añade `firebase_core`
y `firebase_storage` a `pubspec.yaml` y proporciona un `google-services.json`.

### 3. IP del Backend (dispositivo físico)

En `lib/config/api_config.dart`, cambiar:

```dart
// Emulador Android (por defecto):
static const String baseUrl = 'http://10.0.2.2:8081';

// Dispositivo físico (reemplazar con tu IP local):
static const String baseUrl = 'http://192.168.X.X:8081';
```

### 4. Ejecutar la app

```bash
flutter pub get
flutter run
```

---

## Tabla de Pruebas de Caja Negra — Login (CU-01 / RF01)

| ID    | Entrada / Condición               | Resultado esperado                                     |
|-------|-----------------------------------|--------------------------------------------------------|
| CP-01 | Usuario vacío                     | "El campo Usuario es obligatorio"                      |
| CP-02 | Contraseña vacía                  | "El campo Contraseña es obligatorio"                   |
| CP-03 | Usuario = "   " (solo espacios)   | "El usuario no puede contener solo espacios"           |
| CP-04 | Usuario = "ab" (< 3 chars)        | "El usuario debe tener al menos 3 caracteres"          |
| CP-05 | Usuario = 51 caracteres           | "Máximo 50 caracteres permitidos"                      |
| CP-06 | Contraseña = "abc" (< 4 chars)    | "La contraseña debe tener al menos 4 caracteres"       |
| CP-07 | Credenciales incorrectas          | "Usuario o contraseña incorrectos. Verifica tus datos" |
| CP-08 | Servidor apagado / timeout        | "El servidor tardó demasiado. Verifica la conexión."   |
| CP-09 | Password = "p@$$#/" (chars esp.)  | Login exitoso (Uri.encodeComponent previene crash)     |
| CP-10 | Credenciales Admin válidas        | Navega a AdminHome (panel administrador)               |
| CP-11 | Credenciales Teacher válidas      | Navega a TeacherHome (cursos del profesor)             |
| CP-12 | Credenciales Student válidas      | Navega a StudentHome (mis cursos)                      |

### Bug documentado RF01 (prueba CP-09):

El backend recibe el password como parámetro de URL (`GET /users/:username/:pass`)
sin sanitizar. Contraseñas con `/`, `?`, `#` o `%` causaban error HTTP 400:
`"Failed to decode param"`.

**Corrección en cliente:** `Uri.encodeComponent(username)` y
`Uri.encodeComponent(password)` en `api_service.dart` antes de construir la URI.

---

## Tabla de Pruebas de Caja Negra — Entrega de Tareas (CU-05 / RF08)

| ID    | Condición de prueba               | Resultado esperado                                    |
|-------|-----------------------------------|-------------------------------------------------------|
| CE-01 | Plazo de la actividad vencido     | Botón deshabilitado, banner rojo visible              |
| CE-02 | Actividad ya entregada            | Sección "Tu entrega" visible, sin botón de subir      |
| CE-03 | Archivo de 6 MB (> 5 MB)          | "El archivo (6.0 MB) no puede superar 5 MB"           |
| CE-04 | Seleccionar .exe (no permitido)   | FilePicker solo muestra extensiones válidas           |
| CE-05 | Archivo válido + servidor OK      | Barra de progreso animada + snackbar verde + regreso  |
| CE-06 | Archivo válido + servidor caído   | Snackbar rojo: "Error de conexión..."                 |
| CE-07 | Cancelar el selector de archivos  | No ocurre ninguna acción                              |

---

## Tabla de Pruebas de Caja Negra — Crear Actividad (CU-04 / RF07)

| ID    | Condición de prueba               | Resultado esperado                                     |
|-------|-----------------------------------|--------------------------------------------------------|
| CA-01 | Título vacío                      | "Campo requerido"                                      |
| CA-02 | Descripción vacía                 | "Campo requerido"                                      |
| CA-03 | Ponderado vacío                   | "Requerido"                                            |
| CA-04 | Ponderado = 0 o > 100             | "Entre 1 y 100"                                        |
| CA-05 | Ponderado > disponible en curso   | SnackBar rojo con el máximo disponible                 |
| CA-06 | Fecha cierre < fecha inicio       | SnackBar rojo: "La fecha de cierre debe ser posterior" |
| CA-07 | Ponderado disponible = 0%         | Banner rojo, feedback en tiempo real del exceso        |

---

## Tabla de Pruebas de Caja Negra — Gestión de Usuarios (CU-02 / RF03)

| ID    | Condición de prueba               | Resultado esperado                                    |
|-------|-----------------------------------|-------------------------------------------------------|
| CU-01 | Nombre de usuario vacío           | "Requerido"                                           |
| CU-02 | Nombre < 3 caracteres             | "Mínimo 3 caracteres"                                 |
| CU-03 | Nombre > 50 caracteres            | "Máximo 50 caracteres"                                |
| CU-04 | Nombre duplicado                  | SnackBar rojo: "Ya existe un usuario con ese nombre"  |
| CU-05 | Contraseña vacía al crear         | "Requerido"                                           |
| CU-06 | Contraseña < 4 chars al crear     | "Mínimo 4 caracteres"                                 |
| CU-07 | Editar sin cambiar contraseña     | Se conserva la contraseña original                    |

---

## Accesibilidad (CU-07 — RNF03)

Todos los elementos interactivos implementan `Semantics` de Flutter para
compatibilidad con **TalkBack** (Android) y **VoiceOver** (iOS):

- **Campos de texto**: `label` descriptivo + `hint` con instrucciones.
- **Botones de acción**: `label`, `hint` y `button: true`.
- **Tarjetas de actividad**: descripción completa del estado (nota, plazo, entrega).
- **Indicadores de progreso**: `liveRegion: true` — TalkBack anuncia el porcentaje.
- **Mensajes de error**: `liveRegion: true` — se anuncian automáticamente.

---

## Notas Técnicas

### Escala de calificación (Colombia — Decreto 1295/2010, art. 47)

| Rango | Estado     | Color    |
|-------|------------|----------|
| < 3.0 | Reprobado  | Rojo     |
| 3.0–3.9 | Aprobado | Naranja  |
| ≥ 4.0 | Excelente  | Verde    |

Nota mínima aprobatoria: **3.0**

### Typo del backend (RF01)

La clave de respuesta exitosa del login es `'LOGIN_SUCCESFULLY'` (una 'L', no dos).
Es un error tipográfico del servidor original. **No corregir en el cliente** — cambiarlo
rompería la autenticación.

### Patrón Singleton (ApiService)

`ApiService` usa el patrón Factory Singleton para garantizar una única instancia del
cliente HTTP en toda la app y mantener coherencia en las peticiones concurrentes.

### Degradación elegante de Firebase

Si `google-services.json` no está configurado, `main.dart` captura la excepción de
inicialización y la app continúa funcionando usando el endpoint `/addResource` del
backend local para subir archivos. Firebase Storage es opcional pero recomendado
para producción.
