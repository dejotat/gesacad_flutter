import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import 'connectivity_service.dart' show isNetworkError;

/// Un turno de la conversación con el asistente.
class TurnoChat {
  const TurnoChat({required this.esUsuario, required this.texto});
  final bool esUsuario;
  final String texto;

  Map<String, String> toJson() => {'role': esUsuario ? 'user' : 'model', 'text': texto};
}

/// Por qué falló una pregunta (decide el texto y si se ofrece «Reintentar»).
enum FalloChat { sinConexion, tiempo, cuota, saturado, noConfigurado, sesion, otro }

/// Error del asistente con un mensaje LISTO para mostrar en el chat (nunca detalles técnicos).
class ChatbotException implements Exception {
  const ChatbotException(this.tipo, this.mensaje);
  final FalloChat tipo;
  final String mensaje;

  /// Tiene sentido volver a intentar la misma pregunta.
  bool get reintentable =>
      tipo == FalloChat.sinConexion || tipo == FalloChat.tiempo || tipo == FalloChat.saturado || tipo == FalloChat.otro;

  @override
  String toString() => mensaje;
}

/// Asistente GESACAD (CU-15): habla con `POST /chatbot/ask` del servidor, que es el único que
/// conoce la clave de Gemini. Las preguntas frecuentes del chat también pasan por aquí (no hay
/// respuestas fijas en la app), así el modelo puede explicar y hacer su pregunta de seguimiento.
class ChatbotService {
  const ChatbotService();

  /// El servidor puede probar con un modelo de respaldo (hasta ~25 s cada uno).
  static const _timeout = Duration(seconds: 60);

  /// Cuántos turnos previos se envían como contexto.
  static const maxHistorial = 10;

  Future<String> preguntar(String mensaje, List<TurnoChat> historial) async {
    final reciente = historial.length > maxHistorial ? historial.sublist(historial.length - maxHistorial) : historial;
    final http.Response res;
    try {
      res = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/chatbot/ask'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'message': mensaje, 'history': [for (final t in reciente) t.toJson()]}),
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw const ChatbotException(FalloChat.tiempo, 'El asistente tardó demasiado en responder. Inténtalo de nuevo.');
    } catch (e) {
      throw ChatbotException(
          FalloChat.sinConexion,
          isNetworkError(e)
              ? 'Sin conexión con el servidor. Revisa tu internet e inténtalo de nuevo.'
              : 'No se pudo conectar con el asistente. Inténtalo de nuevo.');
    }

    Map<String, dynamic> cuerpo = const {};
    try {
      final d = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
      if (d is Map<String, dynamic>) cuerpo = d;
    } catch (_) {
      // Respuesta sin JSON (p. ej. un servidor antiguo sin la ruta): se trata abajo por el código HTTP.
    }

    if (res.statusCode == 200) {
      final r = cuerpo['reply']?.toString().trim() ?? '';
      if (r.isNotEmpty) return r;
      throw const ChatbotException(FalloChat.otro, 'No recibí una respuesta del asistente. Inténtalo de nuevo.');
    }

    // El servidor ya manda el mensaje en lenguaje claro; se usa tal cual.
    final msg = cuerpo['message']?.toString();
    switch (res.statusCode) {
      case 401:
        throw ChatbotException(FalloChat.sesion, msg ?? 'Tu sesión expiró. Inicia sesión de nuevo para usar el asistente.');
      case 404:
        throw const ChatbotException(FalloChat.noConfigurado, 'El asistente todavía no está disponible en el servidor.');
      case 429:
        throw ChatbotException(FalloChat.cuota, msg ?? 'El asistente alcanzó su límite de uso por ahora. Inténtalo más tarde.');
      case 503:
        final nc = cuerpo['error'] == 'CHATBOT_NO_CONFIGURADO';
        throw ChatbotException(nc ? FalloChat.noConfigurado : FalloChat.saturado,
            msg ?? 'El asistente no está disponible en este momento.');
      case 504:
        throw ChatbotException(FalloChat.tiempo, msg ?? 'El asistente tardó demasiado en responder. Inténtalo de nuevo.');
      default:
        throw ChatbotException(FalloChat.otro, msg ?? 'No pude responder esta vez. Inténtalo de nuevo.');
    }
  }
}
