/// Asistente virtual de GESACAD con respuestas predefinidas por palabras clave.
///
/// No usa ninguna API externa. Las respuestas se generan localmente en Flutter
/// comparando el mensaje del usuario con palabras clave definidas.
class GeminiService {
  GeminiService._();

  /// Reglas ordenadas: se evalúa la primera coincidencia.
  static const List<_Regla> _reglas = [
    _Regla(
      palabras: ['matrícula', 'matricula', 'inscripción', 'inscripcion'],
      respuesta:
          'El régimen de matrícula está disponible en:\n'
          'https://www.unicomfacauca.edu.co/estudiantes/',
    ),
    _Regla(
      palabras: ['programas', 'carreras', 'programa', 'carrera'],
      respuesta:
          'Unicomfacauca ofrece: Ingeniería de Sistemas, Ingeniería Industrial, '
          'Ingeniería Mecatrónica, Contaduría Pública, Derecho, Comunicación Social, '
          'Administración de Empresas y más. Ver todos en:\n'
          'https://www.unicomfacauca.edu.co',
    ),
    _Regla(
      palabras: ['reglamento', 'normas', 'norma'],
      respuesta:
          'Reglamento Estudiantil Acuerdo 019 de 2018. Descárgalo aquí:\n'
          'https://www.unicomfacauca.edu.co/wp-content/uploads/2020/11/Reglamento-estudiantil-Unicomfacauca.pdf',
    ),
    _Regla(
      palabras: ['normatividad', 'acuerdos', 'acuerdo'],
      respuesta:
          'Toda la normatividad en:\n'
          'https://www.unicomfacauca.edu.co/nuestra-u/normatividad/',
    ),
    _Regla(
      palabras: ['calendario', 'fechas', 'fecha'],
      respuesta:
          'Calendario Académico 2026 en:\n'
          'https://www.unicomfacauca.edu.co/estudiantes/',
    ),
    _Regla(
      palabras: ['bienestar', 'salud', 'deporte', 'cultura', 'recreación', 'recreacion'],
      respuesta:
          'Bienestar Universitario: salud, recreación, cultura y desarrollo humano:\n'
          'https://www.unicomfacauca.edu.co/estudiantes/',
    ),
    _Regla(
      palabras: ['calificaciones', 'notas', 'nota', 'calificación', 'calificacion'],
      respuesta:
          'Consulta tus calificaciones en GESACAD entrando a cada curso.',
    ),
    _Regla(
      palabras: ['actividad', 'tarea', 'entrega', 'entregar', 'actividades'],
      respuesta:
          'Para entregar: entra al curso, selecciona la actividad y toca Agregar entrega.',
    ),
    _Regla(
      palabras: ['contacto', 'teléfono', 'telefono', 'dirección', 'direccion'],
      respuesta:
          'Unicomfacauca | Popayán, Cauca | www.unicomfacauca.edu.co',
    ),
  ];

  static const String _respuestaDefault =
      'Puedo ayudarte con información sobre Unicomfacauca y GESACAD. '
      'Intenta preguntar sobre matrículas, programas, reglamento o calificaciones.';

  /// Genera una respuesta basada en palabras clave del último mensaje del usuario.
  /// [historial] se mantiene por compatibilidad de firma.
  static Future<String> generarRespuesta(
    List<Map<String, dynamic>> historial,
  ) async {
    if (historial.isEmpty) return _respuestaDefault;

    final ultimoTurno = historial.last;
    final partes      = ultimoTurno['parts'] as List? ?? [];
    final texto       = partes.isNotEmpty
        ? (partes.last['text'] as String? ?? '').toLowerCase()
        : '';

    for (final regla in _reglas) {
      if (regla.palabras.any((p) => texto.contains(p))) {
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
