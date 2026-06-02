import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/user_model.dart';
import '../models/course_model.dart';
import '../models/activity_model.dart';

/// Servicio centralizado de llamadas HTTP al backend GESACAD (Node.js + MySQL).
///
/// Implementa el patrón Singleton para garantizar una sola instancia en toda
/// la aplicación. Todos los métodos aplican [Uri.encodeComponent] sobre los
/// parámetros enviados por URL para prevenir el crash del servidor cuando el
/// valor contiene caracteres especiales (p.ej. '#', '/', '?', '%').
///
/// **Caso negro documentado (RF01 / bug del servidor):**
/// El backend usa `req.params` sin sanitizar, por lo que contraseñas que
/// contengan '/', '?', '#' o '%' causaban el error 'Failed to decode param'.
/// La solución es encodear siempre con [Uri.encodeComponent] en el cliente.
///
/// Versión: 1.0.0 — Unicomfacauca 2024
class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  /// URL base del backend leída desde [ApiConfig].
  final String _base = ApiConfig.baseUrl;

  /// Timeout estándar para todas las peticiones al backend (10 segundos).
  static const _timeout = Duration(seconds: 10);

  // ---------------------------------------------------------------------------
  // RF01 — Autenticación
  // ---------------------------------------------------------------------------

  /// Autentica un usuario en el backend y retorna el mapa JSON de respuesta.
  ///
  /// Aplica [Uri.encodeComponent] a [username] y [password] para prevenir
  /// el crash 'Failed to decode param' con caracteres especiales.
  ///
  /// La clave de éxito es `'LOGIN_SUCCESFULLY'` (un solo 'L' — typo del
  /// servidor conservado intencionalmente para compatibilidad).
  Future<Map<String, dynamic>> login(String username, String password) async {
    // Encodear ambos parámetros para evitar crash con caracteres especiales.
    final encodedUser = Uri.encodeComponent(username);
    final encodedPass = Uri.encodeComponent(password);
    final uri = Uri.parse('$_base${ApiConfig.login}/$encodedUser/$encodedPass');

    developer.log(
      '[ApiService] login → username=$username',
      name: 'GESACAD.Auth',
    );

    final res = await http.get(uri).timeout(_timeout);

    developer.log(
      '[ApiService] login response → statusCode=${res.statusCode} '
      'body=${res.body.length > 120 ? res.body.substring(0, 120) : res.body}',
      name: 'GESACAD.Auth',
    );

    final decoded = jsonDecode(res.body);
    // El backend retorna lista vacía cuando el usuario no existe — normalizar a Map.
    if (decoded is List) {
      developer.log(
        '[ApiService] login → servidor retornó lista (usuario no encontrado)',
        name: 'GESACAD.Auth',
      );
      return <String, dynamic>{};
    }
    return decoded as Map<String, dynamic>;
  }

  // ---------------------------------------------------------------------------
  // RF03 — Gestión de Usuarios (Admin)
  // ---------------------------------------------------------------------------

  /// Obtiene el listado completo de usuarios del sistema (solo Admin — RF03).
  Future<List<UserModel>> getUsers() async {
    final res = await http
        .get(Uri.parse('$_base${ApiConfig.getUsers}'))
        .timeout(_timeout);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final list = data['users'] as List;
    return list
        .map((u) => UserModel.fromJson(u as Map<String, dynamic>))
        .toList();
  }

  /// Crea un nuevo usuario en el sistema.
  ///
  /// - [username]: nombre único (validado en frontend antes de llamar).
  /// - [password]: contraseña (mínimo 4 caracteres).
  /// - [rol]: 'Student', 'Teacher' o 'Admin'.
  Future<String> addUser(String username, String password, String rol) async {
    final res = await http.post(
      Uri.parse('$_base${ApiConfig.addUser}'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password, 'rol': rol}),
    );
    return jsonDecode(res.body).toString();
  }

  /// Elimina un usuario del sistema por su ID.
  Future<String> deleteUser(int userId) async {
    final res = await http.delete(
      Uri.parse('$_base${ApiConfig.deleteUser}'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'userId': userId}),
    );
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return data['response']?.toString() ?? '';
  }

  /// Actualiza los datos de un usuario existente.
  ///
  /// Si [password] es vacío, el backend conserva la contraseña actual.
  Future<String> editUser(
      int id, String username, String password, String rol) async {
    final res = await http.put(
      Uri.parse('$_base${ApiConfig.editUser}'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(
          {'id': id, 'username': username, 'password': password, 'rol': rol}),
    );
    return jsonDecode(res.body).toString();
  }

  /// Obtiene la cantidad total de usuarios agrupados por rol.
  /// Usado en el dashboard del Administrador (CU-06 / RF05).
  Future<Map<String, dynamic>> getQuantityUsers() async {
    final res = await http
        .get(Uri.parse('$_base${ApiConfig.getQuantityUsers}'))
        .timeout(_timeout);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Obtiene la cantidad total de matriculados por curso.
  /// Usado en el dashboard del Administrador (CU-06 / RF05).
  Future<Map<String, dynamic>> getQuantityRecords() async {
    final res = await http
        .get(Uri.parse('$_base${ApiConfig.getQuantityRecords}'))
        .timeout(_timeout);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ---------------------------------------------------------------------------
  // RF04 — Gestión de Cursos
  // ---------------------------------------------------------------------------

  /// Obtiene los cursos en los que participa el usuario (tabla registration).
  ///
  /// Funciona para los tres roles: Student, Teacher y Admin.
  /// Aplica deduplicación por courseId para evitar cursos repetidos cuando
  /// el backend retorna múltiples filas del mismo curso por un JOIN.
  Future<List<CourseModel>> getMyCourses(int userId) async {
    final res = await http
        .get(Uri.parse('$_base${ApiConfig.getMyCourses}/$userId'))
        .timeout(_timeout);
    final list = jsonDecode(res.body) as List;
    final seen = <int>{};
    final result = <CourseModel>[];
    for (final c in list) {
      final model = CourseModel.fromJson(c as Map<String, dynamic>);
      if (seen.add(model.id)) {
        result.add(model);
      }
    }
    return result;
  }

  /// Obtiene TODOS los cursos del sistema (solo Admin).
  ///
  /// Requiere el endpoint GET /courses/getCourses en el backend.
  /// Si el endpoint no existe, retorna lista vacía sin lanzar excepción.
  Future<List<CourseModel>> getAllCourses() async {
    try {
      final res = await http
          .get(Uri.parse('$_base${ApiConfig.getAllCourses}'))
          .timeout(_timeout);
      if (res.statusCode != 200) return [];
      final decoded = jsonDecode(res.body);
      if (decoded is! List) return [];
      final seen = <int>{};
      final result = <CourseModel>[];
      for (final c in decoded) {
        final model = CourseModel.fromJson(c as Map<String, dynamic>);
        if (seen.add(model.id)) result.add(model);
      }
      return result;
    } catch (_) {
      return [];
    }
  }

  /// Crea un nuevo curso con los participantes ya matriculados.
  ///
  /// - [name]: nombre del curso.
  /// - [courseCode]: código institucional.
  /// - [participants]: lista de IDs de estudiantes a matricular.
  /// - [teacherId]: ID del profesor asignado al curso.
  Future<String> addCourse(
      String name, String courseCode, List<int> participants, int teacherId) async {
    final participantsStr = jsonEncode(participants);
    final uri = Uri.parse(
        '$_base${ApiConfig.addCourse}/${Uri.encodeComponent(name)}/${Uri.encodeComponent(courseCode)}/${Uri.encodeComponent(participantsStr)}/$teacherId');
    final res = await http.get(uri).timeout(_timeout);
    return jsonDecode(res.body).toString();
  }

  /// Elimina un curso por su ID junto con sus actividades y registros.
  Future<String> deleteCourse(int courseId) async {
    final res = await http
        .delete(Uri.parse('$_base${ApiConfig.deleteCourse}/$courseId'))
        .timeout(_timeout);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return data['message']?.toString() ?? data.toString();
  }

  /// Actualiza el nombre y código de un curso existente.
  Future<String> editCourse(int id, String name, String code) async {
    final res = await http.post(
      Uri.parse('$_base${ApiConfig.editCourse}'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'id': id, 'name': name, 'code': code}),
    );
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return data['message']?.toString() ?? data.toString();
  }

  // ---------------------------------------------------------------------------
  // RF06, RF07 — Gestión de Actividades
  // ---------------------------------------------------------------------------

  /// Obtiene todas las actividades de un curso (CU-04 / RF06).
  Future<List<ActivityModel>> getActivities(int courseId) async {
    final res = await http
        .get(Uri.parse('$_base${ApiConfig.getActivities}/$courseId'))
        .timeout(_timeout);
    final list = jsonDecode(res.body) as List;
    return list
        .map((a) => ActivityModel.fromJson(a as Map<String, dynamic>))
        .toList();
  }

  /// Obtiene el detalle de una actividad con el estado de entrega del estudiante.
  ///
  /// - [activityId]: ID de la actividad.
  /// - [userId]: ID del estudiante (null para vista de profesor o admin).
  /// - [userRol]: rol del solicitante para construir la ruta correcta.
  Future<ActivityModel?> getActivityContent(
      int activityId, int? userId, String userRol) async {
    final path = userId != null
        ? '$_base${ApiConfig.getActivityContent}/$activityId/$userId/$userRol'
        : '$_base${ApiConfig.getActivityContent}/$activityId/$userRol';
    final res = await http.get(Uri.parse(path)).timeout(_timeout);
    final list = jsonDecode(res.body) as List;
    if (list.isEmpty) return null;
    return ActivityModel.fromJson(list[0] as Map<String, dynamic>);
  }

  /// Crea una nueva actividad en un curso (CU-04 / RF06, RF07).
  ///
  /// [weighting] debe ser el valor decimal (0.0–1.0), NO el porcentaje.
  /// [archivos] lista de archivos que el profesor adjunta a la actividad.
  /// Solo se envía el primero; el backend lo sube a Cloudinary y guarda
  /// la URL en el campo 'content' de la actividad para que los estudiantes
  /// puedan descargarlo desde el detalle de la actividad.
  Future<void> addActivity({
    required int week,
    required String type,
    required String tittle,
    required String description,
    required double weighting,
    required String startDate,
    required String closingDate,
    required int courseId,
    required int teacherId,
    List<Map<String, dynamic>> archivos = const [],
  }) async {
    final uri     = Uri.parse('$_base${ApiConfig.addActivity}');
    final request = http.MultipartRequest('POST', uri);
    request.fields['week']        = week.toString();
    request.fields['type']        = type;
    request.fields['tittle']      = tittle;
    request.fields['description'] = description;
    request.fields['weighting']   = weighting.toStringAsFixed(4);
    request.fields['startDate']   = startDate;
    request.fields['closingDate'] = closingDate;
    request.fields['courseId']    = courseId.toString();
    request.fields['teacherId']   = teacherId.toString();

    // Si el profesor adjuntó archivos, enviar el primero al backend.
    // El backend lo sube a Cloudinary y guarda la URL en activities.content
    // con formato url::name::nombre_original para que el cliente pueda
    // mostrar el nombre y tipo de archivo correctamente.
    if (archivos.isNotEmpty) {
      final f     = archivos.first;
      final bytes = f['bytes'] as Uint8List;
      final name  = f['name']  as String;
      request.files.add(
        http.MultipartFile.fromBytes('File', bytes.toList(), filename: name),
      );
    }

    final respuesta = await request.send().timeout(_timeout);

    // Si el servidor rechaza la solicitud, lanzar excepción para que la UI
    // muestre el error en lugar de mostrar éxito falso.
    if (respuesta.statusCode < 200 || respuesta.statusCode >= 300) {
      throw Exception(
          'El servidor rechazó la creación de la actividad (código ${respuesta.statusCode})');
    }
  }

  /// Elimina una actividad existente.
  Future<void> deleteActivity(int activityId, int courseId) async {
    await http.delete(
      Uri.parse('$_base${ApiConfig.deleteActivity}'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'activityId': activityId, 'courseId': courseId}),
    );
  }

  // ---------------------------------------------------------------------------
  // RF08 — Entrega de Tareas (CU-05)
  // ---------------------------------------------------------------------------

  /// Registra la entrega de una tarea enviando bytes directamente al backend.
  ///
  /// Usado en Flutter Web (donde no hay ruta local de archivo).
  /// El backend almacena el archivo en Cloudinary y guarda la URL en MySQL.
  ///
  /// - [activityId]: ID de la actividad.
  /// - [userId]: ID del estudiante.
  /// - [bytes]: contenido binario del archivo seleccionado.
  /// - [fileName]: nombre original del archivo.
  /// - [comment]: comentario opcional del estudiante al profesor.
  Future<int> addResourceBytes(
      int activityId, int userId, List<int> bytes, String fileName,
      {String comment = ''}) async {
    developer.log(
      '[ApiService] addResourceBytes → activityId=$activityId userId=$userId '
      'file=$fileName comment=${comment.isNotEmpty ? comment : "(sin comentario)"}',
      name: 'GESACAD.Api',
    );
    final uri = Uri.parse('$_base${ApiConfig.addResource}/$activityId');
    final request = http.MultipartRequest('POST', uri);
    request.files.add(
        http.MultipartFile.fromBytes('File', bytes, filename: fileName));
    request.fields['userId'] = userId.toString();
    // Enviar nombre original del archivo para recuperarlo al visualizar
    // Cloudinary genera IDs sin extensión; guardamos el nombre real aquí.
    request.fields['originalFileName'] = fileName;
    // Enviar comentario al backend (requiere columna 'comment' en la tabla resolutions).
    if (comment.isNotEmpty) request.fields['comment'] = comment;
    final streamed = await request.send().timeout(_timeout);
    developer.log(
      '[ApiService] addResourceBytes response → statusCode=${streamed.statusCode}',
      name: 'GESACAD.Api',
    );
    return streamed.statusCode;
  }

  /// Registra la entrega enviando un archivo desde su ruta local (Android/iOS).
  ///
  /// El backend almacena el archivo en Cloudinary y guarda la URL en MySQL.
  ///
  /// - [activityId]: ID de la actividad.
  /// - [userId]: ID del estudiante.
  /// - [filePath]: ruta local del archivo en el dispositivo.
  Future<int> addResource(int activityId, int userId, String filePath) async {
    developer.log(
      '[ApiService] addResource → activityId=$activityId userId=$userId',
      name: 'GESACAD.Api',
    );
    final uri = Uri.parse('$_base${ApiConfig.addResource}/$activityId');
    final request = http.MultipartRequest('POST', uri);
    request.files.add(await http.MultipartFile.fromPath('File', filePath));
    request.fields['userId'] = userId.toString();
    final streamed = await request.send().timeout(_timeout);
    developer.log(
      '[ApiService] addResource response → statusCode=${streamed.statusCode}',
      name: 'GESACAD.Api',
    );
    return streamed.statusCode;
  }

  // ---------------------------------------------------------------------------
  // RF09, RF10 — Calificaciones (CU-06)
  // ---------------------------------------------------------------------------

  /// Obtiene todas las entregas (resoluciones) de una actividad para calificar.
  Future<List<Map<String, dynamic>>> getResolutions(int activityId) async {
    final res = await http
        .get(Uri.parse('$_base${ApiConfig.getResolutions}/$activityId'))
        .timeout(_timeout);
    return List<Map<String, dynamic>>.from(jsonDecode(res.body) as List);
  }

  /// Registra o actualiza la calificación de un estudiante en una actividad.
  ///
  /// - [gpa]: nota entre 0.0 y 5.0 (escala universitaria colombiana; ≥ 3.0 aprueba).
  /// - [teacherComment]: retroalimentación opcional del docente al estudiante.
  Future<void> gradeActivity(int userId, int activityId, double gpa,
      {String teacherComment = ''}) async {
    final body = <String, dynamic>{'GPA': gpa};
    if (teacherComment.trim().isNotEmpty) {
      body['teacherComment'] = teacherComment.trim();
    }
    await http.patch(
      Uri.parse('$_base${ApiConfig.gradeActivity}/$userId/$activityId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
  }

  // ---------------------------------------------------------------------------
  // CU-03 — Gestión avanzada de miembros de un curso (Admin)
  // ---------------------------------------------------------------------------

  /// Obtiene el profesor y los estudiantes actuales de un curso.
  ///
  /// Retorna un mapa con claves 'teacher' (Map o null) y 'students' (List).
  Future<Map<String, dynamic>> getCourseMembers(int courseId) async {
    try {
      final res = await http
          .get(Uri.parse('$_base${ApiConfig.getCourseMembers}/$courseId/members'))
          .timeout(_timeout);
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return {'teacher': null, 'students': []};
  }

  /// Actualiza el profesor y los estudiantes matriculados en un curso.
  ///
  /// - [teacherId]: ID del nuevo profesor asignado.
  /// - [studentIds]: lista de IDs de estudiantes que deben quedar matriculados.
  Future<bool> updateCourseMembers(
      int courseId, int teacherId, List<int> studentIds) async {
    try {
      final res = await http
          .put(
            Uri.parse(
                '$_base${ApiConfig.updateCourseMembers}/$courseId/updateMembers'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'teacherId': teacherId,
              'studentIds': studentIds,
            }),
          )
          .timeout(_timeout);
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Obtiene el reporte de calificaciones de un estudiante en un curso.
  Future<List<Map<String, dynamic>>> getGrades(
      int courseId, int userId) async {
    final res = await http
        .get(Uri.parse('$_base${ApiConfig.getGrades}/$courseId/$userId'))
        .timeout(_timeout);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['data'] as List? ?? []);
  }

  // ---------------------------------------------------------------------------
  // RF07 — Validación de ponderados
  // ---------------------------------------------------------------------------

  /// Obtiene el total de ponderado ya asignado en un curso (RF07).
  ///
  /// Retorna el porcentaje usado (0–100). El disponible es `100 - retorno`.
  Future<double> getWeightingMax(int courseId) async {
    final res = await http.post(
      Uri.parse('$_base${ApiConfig.weightingMax}'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'courseId': courseId}),
    );
    final data = jsonDecode(res.body);
    if (data is num) return data.toDouble();
    if (data is Map) {
      return double.tryParse(data['total']?.toString() ?? '0') ?? 0.0;
    }
    return double.tryParse(data.toString()) ?? 0.0;
  }

  // ---------------------------------------------------------------------------
  // CU-04 FA-02 — Verificar entregas antes de eliminar actividad
  // ---------------------------------------------------------------------------

  /// Consulta cuántos estudiantes han realizado entregas reales en [activityId].
  ///
  /// Una entrega es "real" cuando el campo `resolution` no es NULL ni vacío.
  /// Retorna el número de entregas existentes (0 si ninguna).
  Future<int> checkSubmissions(int activityId) async {
    try {
      final res = await http
          .get(Uri.parse('$_base${ApiConfig.checkSubmissions}/$activityId'))
          .timeout(_timeout);
      if (res.statusCode != 200) return 0;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return (data['total'] as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  // ---------------------------------------------------------------------------
  // CU-05 FA-04 — Reemplazar entrega existente
  // ---------------------------------------------------------------------------

  /// Limpia la entrega de [userId] en [activityId] para permitir un reenvío
  /// desde cero. Solo funciona si el plazo de entrega no ha vencido.
  ///
  /// Retorna `true` si la operación fue exitosa, `false` en caso de error o
  /// si el backend rechaza la solicitud (p.ej. plazo vencido).
  Future<bool> clearSubmission(int activityId, int userId) async {
    try {
      developer.log(
        '[ApiService] clearSubmission → activityId=$activityId userId=$userId',
        name: 'GESACAD.Api',
      );
      final res = await http.delete(
        Uri.parse('$_base${ApiConfig.clearSubmission}'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'activityId': activityId, 'userId': userId}),
      ).timeout(_timeout);
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // CU-02 — Integridad referencial: cursos de un profesor
  // ---------------------------------------------------------------------------

  /// Devuelve el número de cursos en los que [teacherId] está matriculado.
  ///
  /// Usado antes de eliminar un usuario con rol Teacher para advertir al
  /// administrador que ese profesor tiene cursos activos.
  Future<int> getCursosPorProfesor(int teacherId) async {
    try {
      final res = await http
          .get(Uri.parse('$_base${ApiConfig.cursosPorProfesor}/$teacherId'))
          .timeout(_timeout);
      if (res.statusCode != 200) return 0;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return (data['total'] as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  // ---------------------------------------------------------------------------
  // RF11 — Listado de usuarios para matrícula y asignación
  // ---------------------------------------------------------------------------

  /// Obtiene todos los usuarios con rol 'Student' para matricular en un curso.
  ///
  /// Intenta primero el endpoint dedicado GET /users/getStudents. Si no existe
  /// aún en el backend, hace fallback a getUsers() y filtra por rol 'Student'.
  Future<List<UserModel>> getStudents() async {
    try {
      final res = await http
          .get(Uri.parse('$_base${ApiConfig.getStudents}'))
          .timeout(_timeout);
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        if (body is List && body.isNotEmpty) {
          return body
              .map((u) => UserModel.fromJson(u as Map<String, dynamic>))
              .toList();
        }
      }
    } catch (_) {}
    // Fallback: obtener todos los usuarios y filtrar por rol Student.
    final all = await getUsers();
    return all.where((u) => u.rol == 'Student').toList();
  }

  /// Obtiene todos los usuarios con rol 'Teacher' para asignar cursos.
  ///
  /// Intenta primero el endpoint dedicado GET /users/getTeachers. Si no existe
  /// aún en el backend, hace fallback a getUsers() y filtra por rol 'Teacher'.
  Future<List<UserModel>> getTeachers() async {
    try {
      final res = await http
          .get(Uri.parse('$_base${ApiConfig.getTeachers}'))
          .timeout(_timeout);
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        if (body is List && body.isNotEmpty) {
          return body
              .map((u) => UserModel.fromJson(u as Map<String, dynamic>))
              .toList();
        }
      }
    } catch (_) {}
    // Fallback: obtener todos los usuarios y filtrar por rol Teacher.
    final all = await getUsers();
    return all.where((u) => u.rol == 'Teacher').toList();
  }
  // ---------------------------------------------------------------------------
  // Perfil extendido de usuario
  // ---------------------------------------------------------------------------

  /// Carga el perfil extendido de un usuario desde el backend.
  /// Retorna un mapa con todos los campos opcionales (teléfono, bio, etc.)
  /// o null si ocurre un error de red.
  Future<Map<String, dynamic>?> getUserProfile(int userId) async {
    try {
      final res = await http
          .get(Uri.parse('$_base${ApiConfig.getProfile}/$userId'))
          .timeout(_timeout);
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (e) {
      developer.log('[ApiService] getUserProfile error: $e', name: 'GESACAD');
    }
    return null;
  }

  /// Guarda los datos de perfil extendido en el backend.
  /// Retorna true si el guardado fue exitoso.
  Future<bool> updateUserProfile({
    required int    userId,
    String? telefono,
    String? bio,
    String? emailPersonal,
    String? programa,
    String? semestre,
    String? photoUrl,
  }) async {
    try {
      final res = await http.put(
        Uri.parse('$_base${ApiConfig.updateProfile}/$userId'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'telefono':       telefono       ?? '',
          'bio':            bio            ?? '',
          'email_personal': emailPersonal  ?? '',
          'programa':       programa       ?? '',
          'semestre':       semestre       ?? '',
          'photo_url':      photoUrl       ?? '',
        }),
      ).timeout(_timeout);
      return res.statusCode == 200;
    } catch (e) {
      developer.log('[ApiService] updateUserProfile error: $e', name: 'GESACAD');
      return false;
    }
  }

  /// Obtiene las notificaciones reales del usuario desde el backend.
  /// Combina: actividades nuevas, calificaciones publicadas y logs del sistema.
  Future<List<Map<String, dynamic>>> getNotifications(int userId, String rol) async {
    try {
      final res = await http
          .get(Uri.parse('$_base/users/getNotifications/$userId/$rol'))
          .timeout(_timeout);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return List<Map<String, dynamic>>.from(data['notifications'] ?? []);
      }
    } catch (e) {
      developer.log('[ApiService] getNotifications error: $e', name: 'GESACAD');
    }
    return [];
  }

}