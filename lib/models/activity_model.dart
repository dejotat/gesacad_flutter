/// Modelo que representa una actividad evaluable dentro de un curso en GESACAD.
///
/// Corresponde a la tabla `activities` de la base de datos MySQL (railway).
/// Implementa los requisitos RF06 (Gestión de actividades) y RF07
/// (Configuración de porcentajes de evaluación) del IEEE 830.
///
/// Tipos de actividad posibles:
/// - `midterm`  : Parcial
/// - `project`  : Proyecto
/// - `resource` : Recurso o material de clase
/// - `other`    : Otro tipo de evaluación
class ActivityModel {
  /// Identificador único de la actividad.
  final int id;

  /// Título descriptivo de la actividad (campo 'tittle' en BD — nombre original conservado).
  final String tittle;

  /// Semana del semestre a la que pertenece la actividad (1–16).
  final int week;

  /// Tipo de actividad: 'midterm', 'project', 'resource' u 'other'.
  final String type;

  /// Descripción detallada e instrucciones para los estudiantes.
  final String description;

  /// Contenido adicional o URL del material adjunto por el profesor.
  final String? content;

  /// Peso de la actividad en la nota final del curso (valor entre 0.0 y 1.0).
  ///
  /// La suma de ponderados de todas las actividades del curso no debe exceder 1.0 (100%).
  /// Esta restricción es validada en CU-04 / RF07.
  final double weighting;

  /// Fecha de inicio de la actividad en formato ISO 8601 (p.ej. '2024-03-01T00:00').
  final String startDate;

  /// Fecha límite de entrega en formato ISO 8601 (p.ej. '2024-03-15T23:59').
  ///
  /// Después de esta fecha el sistema bloquea automáticamente las entregas (CU-05 / RF06).
  final String closingDate;

  /// ID del curso al que pertenece esta actividad.
  final int courseId;

  /// Nota obtenida por el estudiante (escala 0.0–5.0). Null si no ha sido calificada.
  final double? gpa;

  /// URL del archivo entregado por el estudiante, almacenado en Cloudinary.
  /// Si es null o vacío, el estudiante aún no ha realizado la entrega.
  final String? resolution;

  /// Fecha y hora en que el estudiante realizó la entrega.
  final String? dateResolution;

  /// Retroalimentación escrita por el docente al calificar la entrega.
  /// Null si el docente no ha dejado comentarios aún.
  final String? teacherComment;

  const ActivityModel({
    required this.id,
    required this.tittle,
    required this.week,
    required this.type,
    required this.description,
    this.content,
    required this.weighting,
    required this.startDate,
    required this.closingDate,
    required this.courseId,
    this.gpa,
    this.resolution,
    this.dateResolution,
    this.teacherComment,
  });

  /// Construye un [ActivityModel] a partir del JSON retornado por el backend.
  factory ActivityModel.fromJson(Map<String, dynamic> json) {
    return ActivityModel(
      id: json['id'] ?? 0,
      tittle: json['tittle'] ?? '',
      week: json['week'] ?? 1,
      type: json['type'] ?? 'other',
      description: json['description'] ?? '',
      content: json['content'],
      weighting:
          double.tryParse(json['weighting']?.toString() ?? '0') ?? 0.0,
      startDate: json['startDate'] ?? '',
      closingDate: json['closingDate'] ?? '',
      courseId: json['courseId'] ?? 0,
      // El campo GPA viene en mayúsculas desde el backend.
      gpa: json['GPA'] != null
          ? double.tryParse(json['GPA'].toString())
          : null,
      resolution: json['resolution'],
      dateResolution: json['dateResolution'],
      teacherComment: json['teacherComment']?.toString().isNotEmpty == true
          ? json['teacherComment'].toString()
          : null,
    );
  }

  /// Convierte una fecha del backend (UTC con sufijo Z o sin él) a hora Colombia (UTC-5).
  /// El backend guarda en UTC; para mostrar en Colombia restamos 5 horas.
  static DateTime parseFecha(String s) {
    final limpia = s.trim();
    // Si tiene sufijo Z o +00:00 → es UTC explícito
    if (limpia.endsWith('Z') || limpia.contains('+')) {
      return DateTime.parse(limpia).toLocal().subtract(
        DateTime.parse(limpia).toLocal().timeZoneOffset -
        const Duration(hours: -5),  // UTC-5 Colombia
      );
    }
    // Sin sufijo → Railway lo guardó en UTC sin indicarlo; tratarlo igual
    return DateTime.parse('${limpia}Z').subtract(const Duration(hours: 0))
        .toUtc().add(const Duration(hours: 0));
  }

  /// Convierte fecha del backend a Colombia restando offset del dispositivo y ajustando a UTC-5.
  static DateTime toCol(String s) {
    try {
      final raw = s.trim();
      // Parsear como UTC (con o sin Z)
      final utc = raw.endsWith('Z') ? DateTime.parse(raw) : DateTime.parse('${raw}Z');
      // Colombia es UTC-5
      return utc.subtract(const Duration(hours: 5));
    } catch (_) {
      return DateTime.now();
    }
  }

  /// Indica si el plazo de entrega ya venció (comparado en hora Colombia).
  bool get isPastDue {
    try {
      final closing = toCol(closingDate);
      final nowCol  = DateTime.now().toUtc().subtract(const Duration(hours: 5));
      return nowCol.isAfter(closing);
    } catch (_) {
      return false;
    }
  }

  /// Indica si el estudiante ya realizó la entrega de esta actividad.
  ///
  /// Una actividad se considera entregada cuando [resolution] no es null ni vacía.
  bool get isDelivered => resolution != null && resolution!.isNotEmpty;

  /// Ponderado de la actividad expresado como porcentaje (0–100).
  double get weightingPercent => weighting * 100;
}
