/// Modelo que representa un curso académico en GESACAD.
///
/// Corresponde a la tabla `courses` de la base de datos MySQL (bdguepardex).
/// Los cursos son creados por el Administrador (CU-03/RF04) y asignados a
/// un profesor. Los estudiantes se matriculan a través de la tabla `registration`.
class CourseModel {
  /// Identificador único del curso en la base de datos.
  final int id;

  /// Nombre completo del curso (p.ej. "Programación Orientada a Objetos").
  final String name;

  /// Código identificador del curso (p.ej. "POO-2024-A").
  final String courseCode;

  /// Índice de imagen de portada del curso (1–4), determina el color del card.
  final int imgCourse;

  const CourseModel({
    required this.id,
    required this.name,
    required this.courseCode,
    required this.imgCourse,
  });

  /// Crea un [CourseModel] a partir de un mapa JSON.
  ///
  /// Maneja dos formatos de respuesta del backend:
  /// - Endpoint `/registration/:id` retorna `course_id`, `course_name`, `course_code`.
  /// - Endpoint `/courses` retorna `id`, `name`, `courseCode`.
  factory CourseModel.fromJson(Map<String, dynamic> json) {
    return CourseModel(
      id: json['course_id'] ?? json['id'] ?? 0,
      name: json['course_name'] ?? json['name'] ?? '',
      courseCode: json['course_code'] ?? json['courseCode'] ?? '',
      imgCourse: json['img_course'] ?? json['imgCourse'] ?? 1,
    );
  }
}
