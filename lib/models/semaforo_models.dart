/// Estado de una materia en el semáforo académico (CU-14).
///
/// Los guardados en la base son [approved], [failed] y [cancelled]; el servidor CALCULA
/// [inProgress] (matriculada sin resultado), [pending] y [blocked] (falta un pre-requisito).
enum EstadoMateria {
  approved('Aprobada'),
  inProgress('En curso'),
  failed('Reprobada'),
  cancelled('Cancelada'),
  blocked('Pre-requisito'),
  pending('Pendiente');

  const EstadoMateria(this.etiqueta);
  final String etiqueta;

  static EstadoMateria desde(String? s) => switch (s) {
        'approved' => approved,
        'in_progress' => inProgress,
        'failed' => failed,
        'cancelled' => cancelled,
        'blocked' => blocked,
        _ => pending,
      };

  /// El valor que entiende el servidor.
  String get api => switch (this) {
        approved => 'approved',
        inProgress => 'in_progress',
        failed => 'failed',
        cancelled => 'cancelled',
        blocked => 'blocked',
        pending => 'pending',
      };
}

/// Áreas de la malla, en el orden en que se muestran.
const List<String> areasMalla = ['basica', 'complementaria', 'especifica'];

String nombreDeArea(String? area) => switch (area) {
      'basica' => 'Básica',
      'complementaria' => 'Complementaria',
      'especifica' => 'Específica',
      _ => 'Sin área',
    };

class Prerequisito {
  const Prerequisito(this.id, this.name);
  final int id;
  final String name;
}

class MateriaSemaforo {
  const MateriaSemaforo({
    required this.courseId,
    required this.name,
    required this.code,
    required this.status,
    this.semester,
    this.credits,
    this.area,
    this.prerequisites = const [],
    this.missingPrerequisites = const [],
    this.grade,
    this.suggestedGrade,
    this.updatedAt,
  });

  final int courseId;
  final String name;
  final String code;
  final int? semester;
  final int? credits;
  final String? area;
  final List<Prerequisito> prerequisites;
  final List<int> missingPrerequisites;
  final EstadoMateria status;

  /// Nota definitiva (solo aprobada / reprobada).
  final double? grade;

  /// Promedio parcial de lo ya calificado (solo «en curso»; NO es la nota definitiva).
  final double? suggestedGrade;
  final DateTime? updatedAt;

  factory MateriaSemaforo.fromJson(Map<String, dynamic> j) => MateriaSemaforo(
        courseId: (j['courseId'] as num).toInt(),
        name: j['name']?.toString() ?? '',
        code: j['code']?.toString() ?? '',
        semester: (j['semester'] as num?)?.toInt(),
        credits: (j['credits'] as num?)?.toInt(),
        area: j['area']?.toString(),
        prerequisites: [
          for (final p in (j['prerequisites'] as List? ?? const []))
            Prerequisito((p['id'] as num).toInt(), p['name']?.toString() ?? ''),
        ],
        missingPrerequisites: [
          for (final p in (j['missingPrerequisites'] as List? ?? const [])) (p as num).toInt(),
        ],
        status: EstadoMateria.desde(j['status']?.toString()),
        grade: (j['grade'] as num?)?.toDouble(),
        suggestedGrade: (j['suggestedGrade'] as num?)?.toDouble(),
        updatedAt: j['updatedAt'] == null ? null : DateTime.tryParse(j['updatedAt'].toString())?.toLocal(),
      );
}

class ResumenSemaforo {
  const ResumenSemaforo({
    this.approved = 0,
    this.inProgress = 0,
    this.failed = 0,
    this.cancelled = 0,
    this.pending = 0,
    this.blocked = 0,
    this.total = 0,
    this.approvedCredits = 0,
    this.totalCredits = 0,
    this.average,
  });

  final int approved, inProgress, failed, cancelled, pending, blocked, total;
  final int approvedCredits, totalCredits;

  /// Promedio ponderado por créditos de las materias aprobadas.
  final double? average;

  int cuenta(EstadoMateria e) => switch (e) {
        EstadoMateria.approved => approved,
        EstadoMateria.inProgress => inProgress,
        EstadoMateria.failed => failed,
        EstadoMateria.cancelled => cancelled,
        EstadoMateria.blocked => blocked,
        EstadoMateria.pending => pending,
      };

  factory ResumenSemaforo.fromJson(Map<String, dynamic> j) => ResumenSemaforo(
        approved: (j['approved'] as num?)?.toInt() ?? 0,
        inProgress: (j['inProgress'] as num?)?.toInt() ?? 0,
        failed: (j['failed'] as num?)?.toInt() ?? 0,
        cancelled: (j['cancelled'] as num?)?.toInt() ?? 0,
        pending: (j['pending'] as num?)?.toInt() ?? 0,
        blocked: (j['blocked'] as num?)?.toInt() ?? 0,
        total: (j['total'] as num?)?.toInt() ?? 0,
        approvedCredits: (j['approvedCredits'] as num?)?.toInt() ?? 0,
        totalCredits: (j['totalCredits'] as num?)?.toInt() ?? 0,
        average: (j['average'] as num?)?.toDouble(),
      );
}

class Semaforo {
  const Semaforo({
    required this.studentId,
    required this.studentName,
    required this.minApprove,
    required this.summary,
    required this.courses,
    this.program,
  });

  final int studentId;
  final String studentName;
  final String? program;
  final double minApprove;
  final ResumenSemaforo summary;
  final List<MateriaSemaforo> courses;

  factory Semaforo.fromJson(Map<String, dynamic> j) {
    final st = (j['student'] as Map?) ?? const {};
    return Semaforo(
      studentId: (st['id'] as num?)?.toInt() ?? 0,
      studentName: st['name']?.toString() ?? '',
      program: st['program']?.toString(),
      minApprove: (j['minApprove'] as num?)?.toDouble() ?? 3.0,
      summary: ResumenSemaforo.fromJson((j['summary'] as Map?)?.cast<String, dynamic>() ?? const {}),
      courses: [
        for (final c in (j['courses'] as List? ?? const [])) MateriaSemaforo.fromJson((c as Map).cast<String, dynamic>()),
      ],
    );
  }

  /// Semestres presentes en la malla, en orden.
  List<int> get semestres =>
      (courses.map((c) => c.semester).whereType<int>().toSet().toList()..sort());
}

/// Una línea del historial de cambios (quién, cuándo y por qué).
class EntradaAuditoria {
  const EntradaAuditoria({
    required this.courseName,
    required this.newStatus,
    required this.changedByRole,
    required this.changedByName,
    this.previousStatus,
    this.previousGrade,
    this.newGrade,
    this.reason,
    this.changedAt,
  });

  final String courseName;
  final String? previousStatus;
  final double? previousGrade;
  final String newStatus;
  final double? newGrade;
  final String changedByRole;
  final String changedByName;
  final String? reason;
  final DateTime? changedAt;

  factory EntradaAuditoria.fromJson(Map<String, dynamic> j) => EntradaAuditoria(
        courseName: j['courseName']?.toString() ?? '',
        previousStatus: j['previousStatus']?.toString(),
        previousGrade: (j['previousGrade'] as num?)?.toDouble(),
        newStatus: j['newStatus']?.toString() ?? '',
        newGrade: (j['newGrade'] as num?)?.toDouble(),
        changedByRole: j['changedByRole']?.toString() ?? '',
        changedByName: j['changedByName']?.toString() ?? '',
        reason: j['reason']?.toString(),
        changedAt: j['changedAt'] == null ? null : DateTime.tryParse(j['changedAt'].toString())?.toLocal(),
      );
}

/// Datos de una materia en el plan de estudios (pantalla de configuración del Admin).
class MateriaMalla {
  const MateriaMalla({
    required this.courseId,
    required this.name,
    required this.code,
    this.semester,
    this.credits,
    this.area,
    this.prerequisiteIds = const [],
  });

  final int courseId;
  final String name;
  final String code;
  final int? semester;
  final int? credits;
  final String? area;
  final List<int> prerequisiteIds;

  factory MateriaMalla.fromJson(Map<String, dynamic> j) => MateriaMalla(
        courseId: (j['courseId'] as num).toInt(),
        name: j['name']?.toString() ?? '',
        code: j['code']?.toString() ?? '',
        semester: (j['semester'] as num?)?.toInt(),
        credits: (j['credits'] as num?)?.toInt(),
        area: j['area']?.toString(),
        prerequisiteIds: [for (final p in (j['prerequisiteIds'] as List? ?? const [])) (p as num).toInt()],
      );
}
