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

/// Evento de un aviso de sistema (ver [AppNotif.evento]).
enum EventoSistema { usuarioCreado, usuarioEliminado, restablecerClave, otro }

const _rolEs = {'Admin': 'administrador', 'Teacher': 'docente', 'Student': 'estudiante'};

// El nombre puede llevar espacios ("carlos zuñiga"): se lee hasta « rol=». Sin distinguir mayúsculas
// (el texto técnico llega como «userId=…» o «userid=…»).
final _detalleTecnico = RegExp(r'username=(.*?)\s+rol=(\S+)', caseSensitive: false);

/// Convierte el texto técnico de auditoría de un aviso de sistema («userId=38 username=juan
/// rol=Student») en una frase clara («Se eliminó la cuenta «juan» (estudiante).»). Cualquier otro
/// texto se devuelve igual. Es la misma regla que aplica el servidor (`Backend/eventosAdmin.js`):
/// se repite aquí para que la app se vea bien con servidores antiguos y con copias guardadas.
String cuerpoLegible(NotifType tipo, String titulo, String cuerpo) {
  if (tipo != NotifType.system) return cuerpo;
  final m = _detalleTecnico.firstMatch(cuerpo);
  if (m == null) return cuerpo;
  final verbo = switch (titulo) {
    'Nuevo usuario registrado' => 'creó',
    'Usuario eliminado del sistema' => 'eliminó',
    _ => null,
  };
  if (verbo == null) return cuerpo;
  final nombre = m.group(1)!.trim();
  final rolCrudo = m.group(2)!;
  final rol = rolCrudo == '?' ? null : (_rolEs[rolCrudo] ?? rolCrudo.toLowerCase());
  final cuenta = nombre.isEmpty || nombre == '?'
      ? 'una cuenta'
      : 'la cuenta «$nombre»${rol != null ? ' ($rol)' : ''}';
  return 'Se $verbo $cuenta.';
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

  factory AppNotif.fromJson(Map<String, dynamic> j) {
    final tipo = NotifType.parse(j['type']?.toString());
    final titulo = j['title']?.toString() ?? '';
    return AppNotif(
        id: (j['id'] as num).toInt(),
        type: tipo,
        title: titulo,
        // El servidor (o una copia guardada) puede traer el texto técnico de auditoría.
        body: cuerpoLegible(tipo, titulo, j['body']?.toString() ?? ''),
        createdAt: DateTime.tryParse(j['createdAt']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
        read: j['read'] == true,
        courseId: (j['courseId'] as num?)?.toInt(),
        courseName: j['courseName']?.toString(),
        courseCode: j['courseCode']?.toString(),
        courseImg: (j['courseImg'] as num?)?.toInt(),
        refType: j['refType']?.toString(),
        refId: (j['refId'] as num?)?.toInt(),
    );
  }

  // ── Presentación: los avisos de sistema se distinguen por su EVENTO ─────────

  /// Evento concreto de un aviso de sistema (el servidor manda `type: system` para todos).
  EventoSistema get evento => type != NotifType.system
      ? EventoSistema.otro
      : switch (title) {
          'Nuevo usuario registrado' => EventoSistema.usuarioCreado,
          'Usuario eliminado del sistema' => EventoSistema.usuarioEliminado,
          'Solicitud de recuperación de contraseña' => EventoSistema.restablecerClave,
          _ => EventoSistema.otro,
        };

  /// Etiqueta de la tarjeta («Usuarios», «Seguridad» o la del tipo).
  String get etiqueta => switch (evento) {
        EventoSistema.usuarioCreado || EventoSistema.usuarioEliminado => 'Usuarios',
        EventoSistema.restablecerClave => 'Seguridad',
        EventoSistema.otro => type.label,
      };

  IconData get icono => switch (evento) {
        EventoSistema.usuarioCreado => Icons.person_add_alt_1_rounded,
        EventoSistema.usuarioEliminado => Icons.person_remove_alt_1_rounded,
        EventoSistema.restablecerClave => Icons.lock_reset_rounded,
        EventoSistema.otro => type.icon,
      };

  Color get colorAviso => switch (evento) {
        EventoSistema.usuarioCreado => const Color(0xFF169365),
        EventoSistema.usuarioEliminado => const Color(0xFFE5484D),
        EventoSistema.restablecerClave => const Color(0xFFCB7A12),
        EventoSistema.otro => type.color,
      };

  IconMotion get movimiento => switch (evento) {
        EventoSistema.usuarioCreado => IconMotion.bounce,
        EventoSistema.usuarioEliminado => IconMotion.pulse,
        EventoSistema.restablecerClave => IconMotion.ring,
        EventoSistema.otro => type.motion,
      };

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
