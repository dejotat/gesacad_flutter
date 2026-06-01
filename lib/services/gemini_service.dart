import 'dart:convert';
import 'package:http/http.dart' as http;

/// Servicio para comunicarse con la API de Gemini de Google.
///
/// Modelo: gemini-1.5-flash (capa gratuita de Google AI).
/// La clave API se usa directamente desde el cliente porque esta es una
/// aplicación académica. En producción se recomienda llamar a Gemini
/// desde el backend para no exponer la clave en el código fuente.
class GeminiService {
  GeminiService._();

  // Clave API de Google AI Studio (Gemini)
  static const String _apiKey =
      'AQ.Ab8RN6I73JVgI1_7Rn2BBY7IpL01uVilzJY4crY6YFTmmZ6uMQ';

  static const String _modelo = 'gemini-1.5-flash';

  static const String _urlBase =
      'https://generativelanguage.googleapis.com/v1beta/models/$_modelo:generateContent';

  /// Prompt del sistema que define el comportamiento del asistente.
  static const String _promptSistema =
      'Eres el asistente virtual de la Universidad Unicomfacauca y la plataforma GESACAD. '
      'Responde preguntas sobre la universidad, programas académicos, reglamento estudiantil, '
      'procesos de matrícula y uso de GESACAD. Si te preguntan algo fuera de estos temas, '
      'redirige amablemente. La página oficial es unicomfacauca.edu.co';

  /// Genera una respuesta del modelo dado el historial completo de la conversación.
  ///
  /// [historial] contiene todos los turnos anteriores (usuario y modelo) en
  /// formato de la API de Gemini: lista de mapas con claves 'role' y 'parts'.
  ///
  /// Lanza [Exception] si la API devuelve un error o la respuesta está vacía.
  static Future<String> generarRespuesta(
    List<Map<String, dynamic>> historial,
  ) async {
    final uri = Uri.parse('$_urlBase?key=$_apiKey');

    final cuerpo = jsonEncode({
      'contents': historial,
      'systemInstruction': {
        'parts': [
          {'text': _promptSistema},
        ],
      },
      'generationConfig': {
        'temperature':     0.7,
        'maxOutputTokens': 1024,
      },
    });

    final respuesta = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: cuerpo,
        )
        .timeout(const Duration(seconds: 30));

    if (respuesta.statusCode != 200) {
      throw Exception(
          'Error ${respuesta.statusCode}: ${respuesta.body}');
    }

    final datos      = jsonDecode(respuesta.body) as Map<String, dynamic>;
    final candidatos = datos['candidates'] as List?;
    if (candidatos == null || candidatos.isEmpty) {
      throw Exception('La API no devolvió candidatos');
    }

    final contenido = candidatos[0]['content'] as Map<String, dynamic>;
    final partes    = contenido['parts'] as List;
    return (partes[0]['text'] as String).trim();
  }
}
