/// Configuración central de URLs del backend GESACAD (Node.js + MySQL en Railway).
///
/// Todos los endpoints corresponden al servidor Express desplegado en Railway.
/// Para desarrollo local, cambiar [baseUrl] según el entorno indicado en los comentarios.
class ApiConfig {
  /// URL base del servidor backend.
  ///
  /// Opciones según entorno:
  ///  - Producción Railway : https://gesacad-backend-production.up.railway.app
  ///  - WEB local (PC)     : http://localhost:8081
  ///  - Emulador Android   : http://10.0.2.2:8081
  ///  - Celular (WiFi)     : http://192.168.X.X:8081
  static const String baseUrl =
      'https://gesacad-backend-production.up.railway.app';

  // ---------------------------------------------------------------------------
  // RF01 — Autenticación (CU-01)
  // Ruta: GET /users/:username/:password
  // IMPORTANTE: los parámetros van URL-encodeados (Uri.encodeComponent).
  // La respuesta de éxito usa 'LOGIN_SUCCESFULLY' (una sola 'L') — typo del
  // servidor que se conserva intencionalmente para compatibilidad.
  // ---------------------------------------------------------------------------
  static const String login = '/users';

  // ---------------------------------------------------------------------------
  // RF03 — Gestión de Usuarios (CU-02, Admin)
  // ---------------------------------------------------------------------------

  /// Retorna todos los usuarios del sistema (solo Admin).
  static const String getUsers = '/users/getUsers';

  /// Crea un nuevo usuario.
  static const String addUser = '/users/addUser';

  /// Elimina un usuario por su ID.
  static const String deleteUser = '/users/deleteUser';

  /// Actualiza los datos de un usuario.
  static const String editUser = '/users/editUser';

  /// Cantidad de usuarios agrupados por rol (dashboard Admin).
  static const String getQuantityUsers = '/users/getQuantityUsers';

  /// Cantidad total de matriculados por curso (dashboard Admin).
  static const String getQuantityRecords = '/users/getQuantityRecords';

  /// Lista únicamente los usuarios con rol 'Student' (para matricular en cursos).
  /// Requiere el endpoint GET /users/getStudents en el backend.
  static const String getStudents = '/users/getStudents';

  /// Lista únicamente los usuarios con rol 'Teacher' (para asignar cursos).
  /// Requiere el endpoint GET /users/getTeachers en el backend.
  static const String getTeachers = '/users/getTeachers';

  // ---------------------------------------------------------------------------
  // RF04 — Gestión de Cursos (CU-03, Admin/Teacher/Student)
  // ---------------------------------------------------------------------------

  /// Cursos en los que participa un usuario (tabla registration).
  static const String getMyCourses = '/registration';

  /// Retorna TODOS los cursos del sistema (solo Admin — requiere endpoint en backend).
  static const String getAllCourses = '/courses/getCourses';

  /// Crea un curso con estudiantes y profesor asignados.
  static const String addCourse = '/courses/addCourse';

  /// Elimina un curso por su ID.
  static const String deleteCourse = '/courses/deleteCourse';

  /// Edita nombre y código de un curso.
  static const String editCourse = '/courses/editCourse';

  // ---------------------------------------------------------------------------
  // RF06, RF07 — Gestión de Actividades (CU-04, Teacher)
  // ---------------------------------------------------------------------------

  /// Lista todas las actividades de un curso.
  static const String getActivities = '/courses/activities/getActivities';

  /// Crea una nueva actividad en un curso.
  static const String addActivity = '/courses/activities/addActivity';

  /// Elimina una actividad existente.
  static const String deleteActivity = '/courses/activities/deleteActivity';

  /// Detalle de una actividad con estado de entrega del estudiante.
  static const String getActivityContent =
      '/courses/activities/getActivityContent';

  /// Total de ponderado ya asignado en un curso (validación RF07).
  static const String weightingMax = '/courses/activities/weightingMax';

  // ---------------------------------------------------------------------------
  // RF08 — Entrega de Tareas (CU-05, Student)
  // ---------------------------------------------------------------------------

  /// Sube el archivo de entrega al backend (almacenado en Cloudinary).
  static const String addResource = '/courses/activities/addResource';

  // ---------------------------------------------------------------------------
  // RF09, RF10 — Calificaciones (CU-06, Teacher/Student)
  // ---------------------------------------------------------------------------

  /// Lista las entregas de una actividad para calificar.
  static const String getResolutions = '/courses/activities/getResolutions';

  /// Registra o actualiza la nota de un estudiante.
  static const String gradeActivity = '/courses/activities/gradeActivity';

  /// Reporte de notas de un estudiante en un curso.
  static const String getGrades = '/courses/activities/getActivitiesGrades';

  // ---------------------------------------------------------------------------
  // Archivos — proxy y descarga
  // ---------------------------------------------------------------------------

  /// Proxy real de Cloudinary: Railway busca el archivo server-to-server y lo
  /// retorna al cliente evitando errores CORS/401 del navegador.
  /// Query params: url=<cloudinary_url_encodeada> [&dl=1 para descargar]
  static const String proxyFile = '/files/proxy';

  /// Obtiene la URL de un archivo desde la base de datos (no es proxy real).
  static const String downloadFile = '/files/download';

  // ---------------------------------------------------------------------------
  // CU-04 FA-02 — Verificar entregas antes de eliminar actividad
  // CU-05 FA-04 — Reemplazar entrega existente del estudiante
  // ---------------------------------------------------------------------------

  /// Cuenta cuántos estudiantes han realizado entregas reales en una actividad.
  /// Retorna JSON {total: N}. Usado para advertir al profesor antes de eliminar.
  static const String checkSubmissions = '/courses/activities/tieneEntregas';

  /// Limpia la entrega de un estudiante para permitir un reenvío desde cero.
  /// Solo se permite si el plazo de entrega aún no ha vencido (CU-05 FA-04).
  static const String clearSubmission = '/courses/activities/clearSubmission';

  // ---------------------------------------------------------------------------
  // Integridad referencial — CU-02 (eliminar profesor con cursos activos)
  // ---------------------------------------------------------------------------

  /// Cuenta los cursos asociados a un profesor (por matrícula en registration).
  /// Usado para advertir antes de eliminar un usuario con rol Teacher.
  static const String cursosPorProfesor = '/users/cursosPorProfesor';

  // ---------------------------------------------------------------------------
  // Gestión de miembros de un curso (CU-03 / Edición avanzada)
  // ---------------------------------------------------------------------------

  /// Retorna el profesor y los estudiantes actuales de un curso.
  /// Ruta: GET /courses/:id/members
  static const String getCourseMembers = '/courses';

  /// Actualiza el profesor y los estudiantes de un curso existente.
  /// Ruta: PUT /courses/:id/updateMembers
  /// Body: { teacherId: int, studentIds: [int] }
  static const String updateCourseMembers = '/courses';
}
