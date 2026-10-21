import 'package:flutter/material.dart';

/// Tipo de evento que entrega el servidor (`/calendar/events`).
enum CalKind { activity, meeting, evaluation }

/// Un evento del calendario unificado (CU-12): actividad, reunión o evaluación.
///
/// El servidor entrega la hora en UTC. [startUtc] sirve para exportar a otros
/// calendarios; [startCol] es la hora de pared de Colombia (UTC-5), que es la que ve
/// el usuario y la que decide en qué día cae el evento.
class CalEvent {
  const CalEvent({
    required this.id,
    required this.kind,
    required this.title,
    required this.startUtc,
    this.courseId,
    this.courseName,
    this.activityType,
    this.weighting,
    this.status,
    this.grade,
    this.submitted,
    this.total,
    this.toGrade,
    this.url,
    this.provider,
    this.refType,
    this.refId,
  });

  final String id;
  final CalKind kind;
  final String title;
  final DateTime startUtc;
  final int? courseId;
  final String? courseName;

  /// `midterm`, `project`, `resource` u `other` (solo actividades).
  final String? activityType;
  final double? weighting;

  /// Estudiante: `pending`, `submitted`, `graded`, `overdue`, `resource`.
  /// Docente: `open`, `closed`. Reunión: `live`, `scheduled`. Evaluación: `pending`, `done`, `open`.
  final String? status;
  final double? grade;

  /// Solo docente: entregas recibidas, matriculados y entregas sin calificar.
  final int? submitted;
  final int? total;
  final int? toGrade;

  /// Enlace de la videollamada (reuniones).
  final String? url;
  final String? provider;
  final String? refType;
  final int? refId;

  factory CalEvent.fromJson(Map<String, dynamic> j) => CalEvent(
        id: j['id']?.toString() ?? '',
        kind: CalKind.values.firstWhere((k) => k.name == j['kind'], orElse: () => CalKind.activity),
        title: j['title']?.toString() ?? '',
        startUtc: DateTime.tryParse(j['start']?.toString() ?? '')?.toUtc() ?? DateTime.now().toUtc(),
        courseId: (j['courseId'] as num?)?.toInt(),
        courseName: j['courseName']?.toString(),
        activityType: j['activityType']?.toString(),
        weighting: (j['weighting'] as num?)?.toDouble(),
        status: j['status']?.toString(),
        grade: (j['grade'] as num?)?.toDouble(),
        submitted: (j['submitted'] as num?)?.toInt(),
        total: (j['total'] as num?)?.toInt(),
        toGrade: (j['toGrade'] as num?)?.toInt(),
        url: j['url']?.toString(),
        provider: j['provider']?.toString(),
        refType: j['refType']?.toString(),
        refId: (j['refId'] as num?)?.toInt(),
      );

  Map<String, dynamic> toJson() => {
        'id': id, 'kind': kind.name, 'title': title, 'start': startUtc.toIso8601String(),
        'courseId': courseId, 'courseName': courseName, 'activityType': activityType,
        'weighting': weighting, 'status': status, 'grade': grade, 'submitted': submitted,
        'total': total, 'toGrade': toGrade, 'url': url, 'provider': provider,
        'refType': refType, 'refId': refId,
      };

  /// Hora de pared de Colombia (UTC-5), sin zona horaria.
  DateTime get startCol {
    final c = startUtc.subtract(const Duration(hours: 5));
    return DateTime(c.year, c.month, c.day, c.hour, c.minute);
  }

  /// Día (a medianoche) en que cae el evento, en hora de Colombia.
  DateTime get dia => DateTime(startCol.year, startCol.month, startCol.day);

  String get hora =>
      '${startCol.hour.toString().padLeft(2, '0')}:${startCol.minute.toString().padLeft(2, '0')}';

  bool get esEntrega => kind == CalKind.activity && activityType != 'resource';

  /// ¿Sigue pendiente de hacer algo el estudiante? (para el contador de "próximo vencimiento").
  bool get pendiente => status == 'pending';

  /// Texto corto del estado para la tarjeta.
  String? get estadoTexto {
    switch (kind) {
      case CalKind.activity:
        switch (status) {
          case 'pending': return 'Pendiente';
          case 'submitted': return 'Entregada';
          case 'graded': return grade == null ? 'Calificada' : 'Calificada · ${grade!.toStringAsFixed(1)}';
          case 'overdue': return 'Vencida sin entrega';
          case 'resource': return 'Recurso';
          case 'open':
            final por = toGrade ?? 0;
            return '${submitted ?? 0}/${total ?? 0} entregas${por > 0 ? ' · $por por calificar' : ''}';
          case 'closed':
            final por = toGrade ?? 0;
            return por > 0 ? 'Cerrada · $por por calificar' : 'Cerrada';
        }
      case CalKind.meeting:
        return status == 'live' ? 'En curso' : 'Programada';
      case CalKind.evaluation:
        return switch (status) { 'pending' => 'Pendiente', 'done' => 'Respondida', _ => 'Abierta' };
    }
    return null;
  }

  /// Color semántico del estado (rojo = urgente, verde = listo…).
  Color? estadoColor(Color ok, Color aviso, Color peligro, Color info) {
    switch (status) {
      case 'graded':
      case 'submitted':
      case 'done':
      case 'live':
        return ok;
      case 'pending':
        return aviso;
      case 'overdue':
        return peligro;
      case 'open':
      case 'closed':
        return (toGrade ?? 0) > 0 ? aviso : info;
      case 'scheduled':
        return info;
    }
    return null;
  }

  /// Enlace para añadir ESTE evento a Google Calendar (se abre en el navegador).
  Uri googleCalendarUri() {
    String f(DateTime d) => d.toUtc().toIso8601String().replaceAll(RegExp(r'[-:]'), '').replaceAll(RegExp(r'\.\d+'), '');
    final fin = startUtc.add(Duration(minutes: kind == CalKind.meeting ? 60 : 30));
    final detalle = [
      if (courseName != null) 'Curso: $courseName',
      if (url != null) 'Enlace: $url',
      'Desde GESACAD',
    ].join('\n');
    return Uri.https('calendar.google.com', '/calendar/render', {
      'action': 'TEMPLATE',
      'text': title,
      'dates': '${f(startUtc)}/${f(fin)}',
      'details': detalle,
      if (url != null) 'location': url!,
    });
  }
}

/// Resultado de cargar el calendario.
class CalLoad {
  const CalLoad({required this.events, this.fromCache = false});
  final List<CalEvent> events;

  /// Sin conexión: son los eventos de la última carga exitosa.
  final bool fromCache;
}

/// Estado del enlace de suscripción (.ics) del usuario.
class FeedInfo {
  const FeedInfo({required this.active, this.url});
  final bool active;

  /// Solo se conoce en este equipo si el enlace se creó aquí (el servidor guarda solo un hash).
  final String? url;
}
