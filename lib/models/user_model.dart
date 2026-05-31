/// Modelo que representa un usuario del sistema GESACAD.
///
/// Corresponde a la tabla `users` de la base de datos MySQL (bdguepardex).
/// Los tres roles posibles definen las capacidades del usuario según RF03:
/// - `Admin`: Acceso total al sistema.
/// - `Teacher`: Gestión de cursos y actividades.
/// - `Student`: Consulta de cursos, entrega de tareas y visualización de notas.
class UserModel {
  /// Identificador único del usuario en la base de datos.
  final int id;

  /// Nombre de usuario utilizado para el inicio de sesión (RF01).
  final String username;

  /// Rol del usuario: 'Admin', 'Teacher' o 'Student' (RF02 — redirección por rol).
  final String rol;

  /// Contraseña del usuario. Solo se incluye en algunas respuestas del backend.
  /// NOTA: El backend actual almacena contraseñas en texto plano.
  /// Para producción, se recomienda implementar bcrypt (RNF01).
  final String? pass;

  const UserModel({
    required this.id,
    required this.username,
    required this.rol,
    this.pass,
  });

  /// Crea un [UserModel] a partir de un mapa JSON recibido del backend.
  ///
  /// Acepta las claves `id`, `username`, `rol` y opcionalmente `pass`.
  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] ?? 0,
      username: json['username'] ?? '',
      rol: json['rol'] ?? '',
      pass: json['pass'],
    );
  }

  /// Serializa el modelo a JSON para enviar al backend.
  /// La contraseña se excluye del JSON por seguridad.
  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'rol': rol,
      };

  /// Retorna la etiqueta en español del rol para mostrarse en la interfaz.
  ///
  /// - 'Admin' → 'Administrador'
  /// - 'Teacher' → 'Profesor'
  /// - 'Student' → 'Estudiante'
  String get rolLabel {
    switch (rol) {
      case 'Admin':
        return 'Administrador';
      case 'Teacher':
        return 'Profesor';
      default:
        return 'Estudiante';
    }
  }
}
