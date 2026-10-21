import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/meeting_model.dart';
import 'api_service.dart' show ApiMessageException;

/// Reuniones virtuales por curso (CU-09): `/courses/:id/meeting`.
///
/// Requieren conexión (no se encolan sin red: una reunión es "ahora"). Los errores
/// del servidor llegan como [ApiMessageException] con el texto listo para mostrar.
class MeetingService {
  const MeetingService();

  static const _timeout = Duration(seconds: 20);

  Uri _uri(int courseId, [String sufijo = '']) =>
      Uri.parse('${ApiConfig.baseUrl}/courses/$courseId/meeting$sufijo');

  Never _fallo(http.Response res) {
    var mensaje = 'No se pudo completar la acción (código ${res.statusCode}).';
    try {
      final d = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
      if (d is Map && d['message'] != null) mensaje = d['message'].toString();
    } catch (_) {
      // Un 404 sin JSON: el servidor aún no tiene el módulo desplegado.
      if (res.statusCode == 404) {
        mensaje = 'El servidor todavía no tiene habilitadas las reuniones virtuales.';
      }
    }
    throw ApiMessageException(res.statusCode, mensaje);
  }

  /// Reunión vigente del curso, o `null`.
  Future<Meeting?> current(int courseId) async {
    final res = await http.get(_uri(courseId)).timeout(_timeout);
    // Servidor sin el módulo: se trata como "sin reunión" para no molestar al estudiante.
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) _fallo(res);
    final d = jsonDecode(res.body);
    final m = d is Map ? d['meeting'] : null;
    return m is Map<String, dynamic> ? Meeting.fromJson(m) : null;
  }

  /// Inicia (o programa con [scheduledAt]) una reunión. Sin [url] se crea una sala
  /// de Jitsi; con [url] se usa el enlace de Meet/Zoom/Teams.
  Future<Meeting> start(int courseId, {String? title, String? url, DateTime? scheduledAt}) async {
    final res = await http
        .post(_uri(courseId),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              if (title != null && title.trim().isNotEmpty) 'title': title.trim(),
              if (url != null && url.trim().isNotEmpty) 'url': url.trim(),
              if (scheduledAt != null) 'scheduledAt': scheduledAt.toUtc().toIso8601String(),
            }))
        .timeout(_timeout);
    if (res.statusCode != 201) _fallo(res);
    return Meeting.fromJson((jsonDecode(res.body) as Map)['meeting'] as Map<String, dynamic>);
  }

  Future<void> end(int courseId) async {
    final res = await http.post(_uri(courseId, '/end')).timeout(_timeout);
    if (res.statusCode != 200) _fallo(res);
  }
}
