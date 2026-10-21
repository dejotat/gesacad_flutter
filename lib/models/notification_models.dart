import 'package:flutter/material.dart';
import '../widgets/ui/motion_icon.dart' show IconMotion;

/// Tipo de notificación (CU-11). El nombre coincide con el `type` del servidor.
enum NotifType {
  activity('Actividad', Icons.assignment_rounded, Color(0xFF2563EB), IconMotion.write),
  grade('Calificación', Icons.grade_rounded, Color(0xFF16A34A), IconMotion.tada),
  submission('Entrega', Icons.upload_file_rounded, Color(0xFF0891B2), IconMotion.bounce),
  meeting('Reunión', Icons.videocam_rounded, Color(0xFFDB2777), IconMotion.pulse),
  evaluation('Evaluación', Icons.insights_rounded, Color(0xFF7C3AED), IconMotion.swing),
  enrollment('Matrícula', Icons.school_rounded, Color(0xFF0D9488), IconMotion.float),
  reminder('Recordatorio', Icons.alarm_rounded, Color(0xFFDC2626), IconMotion.ring),
  system('Sistema', Icons.info_rounded, Color(0xFF64748B), IconMotion.pulse);

  const NotifType(this.label, this.icon, this.color, this.motion);
  final String label;
  final IconData icon;
  final Color color;
  final IconMotion motion;

  /// Descripción para la pantalla de preferencias.
  String get description => switch (this) {
        NotifType.activity => 'Actividades y recursos nuevos en tus cursos',
        NotifType.grade => 'Cuando un docente califica tu entrega',
        NotifType.submission => 'Entregas de tus estudiantes',
        NotifType.meeting => 'Reuniones virtuales iniciadas o programadas',
        NotifType.evaluation => 'Apertura y cierre de la evaluación docente',
        NotifType.enrollment => 'Cuando te matriculan en un curso',
        NotifType.reminder => 'Avisos de entregas que están por vencer',
        NotifType.system => 'Eventos del sistema para administradores',
      };

  static NotifType parse(String? s) =>
      NotifType.values.firstWhere((t) => t.name == s, orElse: () => NotifType.system);
}

/// Una notificación de la bandeja del usuario.
class AppNotif {
  AppNotif({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    this.read = false,
    this.courseId,
    this.courseName,
    this.courseCode,
    this.courseImg,
    this.refType,
    this.refId,
  });

  final int id;
  final NotifType type;
  final String title;
  final String body;

  /// Hora local (el servidor la entrega en UTC).
  final DateTime createdAt;
  bool read;
  final int? courseId;
  final String? courseName;
  final String? courseCode;
  final int? courseImg;

  /// Qué la originó: `activity`, `course`, `meeting`, `evaluation`…
  final String? refType;
  final int? refId;

  factory AppNotif.fromJson(Map<String, dynamic> j) => AppNotif(
        id: (j['id'] as num).toInt(),
        type: NotifType.parse(j['type']?.toString()),
        title: j['title']?.toString() ?? '',
        body: j['body']?.toString() ?? '',
        createdAt: DateTime.tryParse(j['createdAt']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
        read: j['read'] == true,
        courseId: (j['courseId'] as num?)?.toInt(),
        courseName: j['courseName']?.toString(),
        courseCode: j['courseCode']?.toString(),
        courseImg: (j['courseImg'] as num?)?.toInt(),
        refType: j['refType']?.toString(),
        refId: (j['refId'] as num?)?.toInt(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'title': title,
        'body': body,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'read': read,
        'courseId': courseId,
        'courseName': courseName,
        'courseCode': courseCode,
        'courseImg': courseImg,
        'refType': refType,
        'refId': refId,
      };
}

/// Una página de la bandeja.
class NotifPage {
  const NotifPage({required this.items, required this.unread, this.nextBefore, this.fromCache = false});
  final List<AppNotif> items;
  final int unread;

  /// Cursor para pedir la página siguiente, o `null` si no hay más.
  final int? nextBefore;

  /// Se muestra la última copia guardada porque no hubo conexión.
  final bool fromCache;
}
