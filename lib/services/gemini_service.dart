/// Asistente virtual de GESACAD con respuestas predefinidas por palabras clave.
///
/// No usa ninguna API externa. Las respuestas se generan localmente en Flutter
/// comparando el mensaje del usuario con palabras clave definidas.
class GeminiService {
  GeminiService._();

  /// Mapa de palabras clave → respuesta correspondiente.
  /// Se evalúan en orden; la primera coincidencia gana.
  static const List<_Regla> _reglas = [
    _Regla(
      palabras: ['matrícula', 'matricula', 'inscripción', 'inscripcion'],
      respuesta:
          'El proceso de matrícula en Unicomfacauca se realiza en las fechas '
          'establecidas en el calendario académico. '
          'Visita unicomfacauca.edu.co para más información.',
    ),
    _Regla(
      palabras: ['programas', 'carreras', 'programa', 'carrera'],
      respuesta:
          'Unicomfacauca ofrece programas en Ingeniería, Ciencias Sociales, '
          'Ciencias de la Salud y más. '
          'Visita unicomfacauca.edu.co/programas',
    ),
    _Regla(
      palabras: ['reglamento', 'normas', 'norma', 'regla', 'reglas'],
      respuesta:
          'El reglamento estudiantil está disponible en unicomfacauca.edu.co. '
          'Regula derechos, deberes y procesos académicos.',
    ),
    _Regla(
      palabras: ['calificaciones', 'notas', 'nota', 'calificación', 'calificacion'],
      respuesta:
          'Puedes ver tus calificaciones en GESACAD en la sección de cada curso.',
    ),
    _Regla(
      palabras: ['actividad', 'tarea', 'entrega', 'entregar', 'actividades'],
      respuesta:
          'Para entregar una actividad entra al curso, selecciona la actividad '
          'y usa el botón Agregar entrega.',
    ),
    _Regla(
      palabras: ['contacto', 'teléfono', 'telefono', 'dirección', 'direccion'],
      respuesta:
          'Unicomfacauca: unicomfacauca.edu.co | Popayán, Cauca, Colombia.',
    ),
  ];

  static const String _respuestaDefault =
      'Puedo ayudarte con información sobre Unicomfacauca y GESACAD. '
      'Intenta preguntar sobre matrículas, programas, reglamento o calificaciones.';

  /// Genera una respuesta basada en palabras clave del mensaje del usuario.
  /// El parámetro [historial] se mantiene por compatibilidad con la firma
  /// anterior pero no se usa en la lógica local.
  static Future<String> generarRespuesta(
    List<Map<String, dynamic>> historial,
  ) async {
    // Extraer el último mensaje del usuario del historial
    if (historial.isEmpty) return _respuestaDefault;

    final ultimoTurno = historial.last;
    final partes      = ultimoTurno['parts'] as List? ?? [];
    final texto       = partes.isNotEmpty
        ? (partes.last['text'] as String? ?? '').toLowerCase()
        : '';

    // Buscar la primera regla cuyas palabras clave aparezcan en el texto
    for (final regla in _reglas) {
      if (regla.palabras.any((p) => texto.contains(p))) {
        // Simular un pequeño retardo para que la UI "escribiendo" sea visible
        await Future.delayed(const Duration(milliseconds: 600));
        return regla.respuesta;
      }
    }

    await Future.delayed(const Duration(milliseconds: 600));
    return _respuestaDefault;
  }
}

/// Modelo interno de una regla: palabras clave → respuesta.
class _Regla {
  final List<String> palabras;
  final String       respuesta;

  const _Regla({required this.palabras, required this.respuesta});
}
