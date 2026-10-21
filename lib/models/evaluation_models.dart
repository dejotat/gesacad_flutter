/// Modelos de la evaluación docente (CU-08).
///
/// Las fechas llegan del backend en UTC (ISO-8601 con 'Z'). Para mostrarlas se
/// convierten a hora de Colombia (UTC-5, sin horario de verano) con
/// [toColombia], igual que las fechas de actividades.
library;

/// Convierte un instante UTC a la hora de reloj de Colombia (UTC-5).
DateTime toColombia(DateTime utc) =>
    utc.toUtc().subtract(const Duration(hours: 5));

/// Interpreta una fecha/hora de reloj de Colombia como instante UTC.
DateTime fromColombia(DateTime col) =>
    DateTime.utc(col.year, col.month, col.day, col.hour, col.minute)
        .add(const Duration(hours: 5));

DateTime? _fecha(dynamic v) =>
    v == null ? null : DateTime.tryParse(v.toString())?.toUtc();

/// Fase de un periodo según el backend.
enum EvalPhase {
  draft('Borrador'),
  scheduled('Programada'),
  open('Abierta'),
  closed('Cerrada');

  const EvalPhase(this.label);
  final String label;

  static EvalPhase parse(String? v) => EvalPhase.values.firstWhere(
        (p) => p.name == v,
        orElse: () => EvalPhase.draft,
      );
}

/// Pregunta del instrumento. [type] es `scale` (1 a 5) o `text` (comentario).
class EvalQuestion {
  const EvalQuestion({
    this.id,
    required this.dimension,
    required this.text,
    this.type = 'scale',
    this.required = true,
  });

  final int? id;
  final String dimension;
  final String text;
  final String type;
  final bool required;

  bool get isScale => type == 'scale';

  factory EvalQuestion.fromJson(Map<String, dynamic> j) => EvalQuestion(
        id: j['id'] as int?,
        dimension: j['dimension']?.toString() ?? '',
        text: j['text']?.toString() ?? '',
        type: j['type']?.toString() ?? 'scale',
        required: j['required'] == true || j['required'] == 1,
      );

  Map<String, dynamic> toJson() => {
        'dimension': dimension,
        'text': text,
        'type': type,
        'required': required,
      };

  EvalQuestion copyWith({String? dimension, String? text, String? type, bool? required}) =>
      EvalQuestion(
        id: id,
        dimension: dimension ?? this.dimension,
        text: text ?? this.text,
        type: type ?? this.type,
        required: required ?? this.required,
      );
}

/// Curso + docente de un periodo (foto tomada al publicar).
class EvalTarget {
  const EvalTarget({
    required this.id,
    required this.courseId,
    required this.courseName,
    required this.teacherId,
    required this.teacherName,
    required this.enrolled,
    required this.responses,
  });

  final int id;
  final int courseId;
  final String courseName;
  final int teacherId;
  final String teacherName;
  final int enrolled;
  final int responses;

  double get participation => enrolled == 0 ? 0 : responses / enrolled;

  factory EvalTarget.fromJson(Map<String, dynamic> j) => EvalTarget(
        id: j['id'] as int,
        courseId: j['courseId'] as int,
        courseName: j['courseName']?.toString() ?? '',
        teacherId: j['teacherId'] as int,
        teacherName: j['teacherName']?.toString() ?? '',
        enrolled: (j['enrolled'] as num?)?.toInt() ?? 0,
        responses: (j['responses'] as num?)?.toInt() ?? 0,
      );
}

/// Periodo de evaluación (p. ej. "2026-2") con su ventana de fechas.
class EvalPeriod {
  const EvalPeriod({
    required this.id,
    required this.name,
    required this.status,
    required this.phase,
    required this.minResponses,
    this.opensAt,
    this.closesAt,
    this.publishedAt,
    this.scopeMode = 'all',
    this.targetCount = 0,
    this.expected = 0,
    this.responses = 0,
    this.questions = const [],
    this.targets = const [],
  });

  final int id;
  final String name;
  final String status;
  final EvalPhase phase;
  final int minResponses;
  final DateTime? opensAt;
  final DateTime? closesAt;
  final DateTime? publishedAt;

  /// `all` (todos los matriculados) o `custom` (selección del Admin).
  final String scopeMode;

  /// Resumen de la lista de periodos.
  final int targetCount;
  final int expected;
  final int responses;

  /// Solo en el detalle.
  final List<EvalQuestion> questions;
  final List<EvalTarget> targets;

  bool get isDraft => phase == EvalPhase.draft;
  double get participation => expected == 0 ? 0 : responses / expected;

  factory EvalPeriod.fromJson(Map<String, dynamic> j) {
    final t = j['targets'];
    return EvalPeriod(
      id: j['id'] as int,
      name: j['name']?.toString() ?? '',
      status: j['status']?.toString() ?? 'draft',
      phase: EvalPhase.parse(j['phase']?.toString()),
      minResponses: (j['minResponses'] as num?)?.toInt() ?? 5,
      opensAt: _fecha(j['opensAt']),
      closesAt: _fecha(j['closesAt']),
      publishedAt: _fecha(j['publishedAt']),
      scopeMode: j['scopeMode']?.toString() ?? 'all',
      targetCount: t is int ? t : (t is List ? t.length : 0),
      expected: (j['expected'] as num?)?.toInt() ?? 0,
      responses: (j['responses'] as num?)?.toInt() ?? 0,
      questions: (j['questions'] as List? ?? [])
          .map((q) => EvalQuestion.fromJson(q as Map<String, dynamic>))
          .toList(),
      targets: t is List
          ? t.map((x) => EvalTarget.fromJson(x as Map<String, dynamic>)).toList()
          : const [],
    );
  }
}

/// Evaluación disponible para un estudiante (una por curso).
class EvalPending {
  const EvalPending({
    required this.targetId,
    required this.periodId,
    required this.periodName,
    required this.courseId,
    required this.courseName,
    required this.teacherName,
    required this.answered,
    this.closesAt,
  });

  final int targetId;
  final int periodId;
  final String periodName;
  final int courseId;
  final String courseName;
  final String teacherName;
  final bool answered;
  final DateTime? closesAt;

  factory EvalPending.fromJson(Map<String, dynamic> j) => EvalPending(
        targetId: j['targetId'] as int,
        periodId: j['periodId'] as int,
        periodName: j['periodName']?.toString() ?? '',
        courseId: j['courseId'] as int,
        courseName: j['courseName']?.toString() ?? '',
        teacherName: j['teacherName']?.toString() ?? '',
        answered: j['answered'] == true,
        closesAt: _fecha(j['closesAt']),
      );

  EvalPending copyWith({bool? answered}) => EvalPending(
        targetId: targetId,
        periodId: periodId,
        periodName: periodName,
        courseId: courseId,
        courseName: courseName,
        teacherName: teacherName,
        answered: answered ?? this.answered,
        closesAt: closesAt,
      );
}

/// Formulario que el estudiante responde.
class EvalForm {
  const EvalForm({
    required this.targetId,
    required this.periodName,
    required this.courseName,
    required this.teacherName,
    required this.questions,
    this.closesAt,
    this.scaleMin = 1,
    this.scaleMax = 5,
    this.maxCommentLength = 1000,
  });

  final int targetId;
  final String periodName;
  final String courseName;
  final String teacherName;
  final DateTime? closesAt;
  final int scaleMin;
  final int scaleMax;
  final int maxCommentLength;
  final List<EvalQuestion> questions;

  /// Preguntas de escala agrupadas por dimensión, en orden de aparición.
  Map<String, List<EvalQuestion>> get scaleByDimension {
    final out = <String, List<EvalQuestion>>{};
    for (final q in questions.where((q) => q.isScale)) {
      out.putIfAbsent(q.dimension, () => []).add(q);
    }
    return out;
  }

  List<EvalQuestion> get textQuestions =>
      questions.where((q) => !q.isScale).toList();

  factory EvalForm.fromJson(Map<String, dynamic> j) {
    final scale = j['scale'] as Map<String, dynamic>? ?? const {};
    return EvalForm(
      targetId: j['targetId'] as int,
      periodName: j['periodName']?.toString() ?? '',
      courseName: j['courseName']?.toString() ?? '',
      teacherName: j['teacherName']?.toString() ?? '',
      closesAt: _fecha(j['closesAt']),
      scaleMin: (scale['min'] as num?)?.toInt() ?? 1,
      scaleMax: (scale['max'] as num?)?.toInt() ?? 5,
      maxCommentLength: (j['maxCommentLength'] as num?)?.toInt() ?? 1000,
      questions: (j['questions'] as List? ?? [])
          .map((q) => EvalQuestion.fromJson(q as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Resultado de una pregunta de escala.
class EvalQuestionResult {
  const EvalQuestionResult({
    required this.questionId,
    required this.dimension,
    required this.text,
    required this.n,
    required this.avg,
    required this.distribution,
  });

  final int questionId;
  final String dimension;
  final String text;
  final int n;
  final double? avg;

  /// Cantidad de respuestas con 1, 2, 3, 4 y 5.
  final List<int> distribution;

  factory EvalQuestionResult.fromJson(Map<String, dynamic> j) =>
      EvalQuestionResult(
        questionId: j['questionId'] as int,
        dimension: j['dimension']?.toString() ?? '',
        text: j['text']?.toString() ?? '',
        n: (j['n'] as num?)?.toInt() ?? 0,
        avg: (j['avg'] as num?)?.toDouble(),
        distribution: (j['distribution'] as List? ?? [0, 0, 0, 0, 0])
            .map((e) => (e as num).toInt())
            .toList(),
      );
}

/// Resultado agregado de un curso. Si [hidden], no hay promedios: el curso
/// no alcanzó el mínimo de respuestas y se protege el anonimato.
class EvalResult {
  const EvalResult({
    required this.targetId,
    required this.courseName,
    required this.teacherName,
    required this.enrolled,
    required this.responses,
    required this.participation,
    required this.minResponses,
    required this.hidden,
    this.overall,
    this.questions = const [],
    this.comments = const [],
  });

  final int targetId;
  final String courseName;
  final String teacherName;
  final int enrolled;
  final int responses;
  final double participation;
  final int minResponses;
  final bool hidden;
  final double? overall;
  final List<EvalQuestionResult> questions;
  final List<String> comments;

  /// Promedio por dimensión (promedio de los promedios de sus preguntas).
  Map<String, double> get byDimension {
    final acc = <String, List<double>>{};
    for (final q in questions) {
      if (q.avg != null) acc.putIfAbsent(q.dimension, () => []).add(q.avg!);
    }
    return {
      for (final e in acc.entries)
        e.key: e.value.reduce((a, b) => a + b) / e.value.length,
    };
  }

  factory EvalResult.fromJson(Map<String, dynamic> j) => EvalResult(
        targetId: j['targetId'] as int,
        courseName: j['courseName']?.toString() ?? '',
        teacherName: j['teacherName']?.toString() ?? '',
        enrolled: (j['enrolled'] as num?)?.toInt() ?? 0,
        responses: (j['responses'] as num?)?.toInt() ?? 0,
        participation: (j['participation'] as num?)?.toDouble() ?? 0,
        minResponses: (j['minResponses'] as num?)?.toInt() ?? 5,
        hidden: j['hidden'] == true,
        overall: (j['overall'] as num?)?.toDouble(),
        questions: (j['questions'] as List? ?? [])
            .map((q) => EvalQuestionResult.fromJson(q as Map<String, dynamic>))
            .toList(),
        comments: (j['comments'] as List? ?? []).map((c) => c.toString()).toList(),
      );
}

/// Resultados de un periodo (para Admin y docente).
class EvalPeriodResults {
  const EvalPeriodResults({required this.period, required this.results});
  final EvalPeriod period;
  final List<EvalResult> results;

  factory EvalPeriodResults.fromJson(Map<String, dynamic> j) =>
      EvalPeriodResults(
        period: EvalPeriod.fromJson(j['period'] as Map<String, dynamic>),
        results: (j['results'] as List? ?? [])
            .map((r) => EvalResult.fromJson(r as Map<String, dynamic>))
            .toList(),
      );
}

/// Error devuelto por el módulo de evaluación (con el mensaje del servidor).
class EvalApiException implements Exception {
  const EvalApiException(this.status, this.code, this.message);
  final int status;
  final String code;
  final String message;

  @override
  String toString() => message;
}

/// Resultado del envío de una evaluación (lo usa la cola sin conexión).
class EvalSubmitResult {
  const EvalSubmitResult(this.status, {this.code, this.message});
  final int status;
  final String? code;
  final String? message;
}

/// Estudiante dentro del árbol de participantes. [selected] es estado de la
/// pantalla de selección (mutable).
class EvalStudentNode {
  EvalStudentNode({required this.id, required this.username, required this.selected});
  final int id;
  final String username;
  bool selected;

  factory EvalStudentNode.fromJson(Map<String, dynamic> j) => EvalStudentNode(
        id: j['id'] as int,
        username: j['username']?.toString() ?? '',
        selected: j['selected'] == true,
      );
}

/// Curso (materia) con sus estudiantes matriculados.
class EvalCourseNode {
  EvalCourseNode({required this.courseId, required this.courseName, required this.students});
  final int courseId;
  final String courseName;
  final List<EvalStudentNode> students;

  int get selectedCount => students.where((s) => s.selected).length;

  factory EvalCourseNode.fromJson(Map<String, dynamic> j) => EvalCourseNode(
        courseId: j['courseId'] as int,
        courseName: j['courseName']?.toString() ?? '',
        students: (j['students'] as List? ?? [])
            .map((s) => EvalStudentNode.fromJson(s as Map<String, dynamic>))
            .toList(),
      );
}

/// Docente con los cursos que tiene asignados.
class EvalTeacherNode {
  EvalTeacherNode({required this.id, required this.name, required this.courses});
  final int id;
  final String name;
  final List<EvalCourseNode> courses;

  int get studentCount => courses.fold(0, (a, c) => a + c.students.length);
  int get selectedCount => courses.fold(0, (a, c) => a + c.selectedCount);

  factory EvalTeacherNode.fromJson(Map<String, dynamic> j) => EvalTeacherNode(
        id: j['id'] as int,
        name: j['name']?.toString() ?? '',
        courses: (j['courses'] as List? ?? [])
            .map((c) => EvalCourseNode.fromJson(c as Map<String, dynamic>))
            .toList(),
      );
}

/// Persona que aún no aparece en el árbol (docente sin materia o estudiante sin curso).
class EvalPerson {
  const EvalPerson({required this.id, required this.name});
  final int id;
  final String name;

  factory EvalPerson.fromJson(Map<String, dynamic> j) =>
      EvalPerson(id: j['id'] as int, name: j['name']?.toString() ?? '');
}

/// Árbol docente → curso → estudiante con la matrícula actual y la selección
/// del Admin (todos seleccionados por defecto).
class EvalCandidates {
  EvalCandidates({
    required this.mode,
    required this.coursesWithoutTeacher,
    required this.teachers,
    this.unassignedTeachers = const [],
    this.unassignedStudents = const [],
  });
  final String mode;
  final int coursesWithoutTeacher;
  final List<EvalTeacherNode> teachers;

  /// Docentes sin materia asignada: no aparecen en el árbol hasta tener un curso.
  final List<EvalPerson> unassignedTeachers;

  /// Estudiantes sin matrícula en un curso con docente.
  final List<EvalPerson> unassignedStudents;

  factory EvalCandidates.fromJson(Map<String, dynamic> j) {
    final sin = j['unassigned'] as Map<String, dynamic>? ?? const {};
    List<EvalPerson> personas(dynamic v) => (v as List? ?? [])
        .map((e) => EvalPerson.fromJson(e as Map<String, dynamic>))
        .toList();
    return EvalCandidates(
      mode: j['mode']?.toString() ?? 'all',
      coursesWithoutTeacher: (j['coursesWithoutTeacher'] as num?)?.toInt() ?? 0,
      teachers: (j['teachers'] as List? ?? [])
          .map((t) => EvalTeacherNode.fromJson(t as Map<String, dynamic>))
          .toList(),
      unassignedTeachers: personas(sin['teachers']),
      unassignedStudents: personas(sin['students']),
    );
  }
}
