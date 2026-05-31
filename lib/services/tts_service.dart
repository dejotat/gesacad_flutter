import 'package:gesacad/utils/platform_utils.dart';

/// Servicio singleton de Text-to-Speech — funciona en web y Android.
///
/// En WEB usa Web Speech API vía PlatformUtils.
/// En Android usa flutter_tts vía PlatformUtils.
///
/// El [TalkWidget] consulta [textoActual] para saber si ya está leyendo
/// el mismo texto y no interrumpirlo innecesariamente.
class TtsService {
  TtsService._();
  static final TtsService instance = TtsService._();

  /// Indica si actualmente se está leyendo texto.
  bool _leyendo = false;
  bool get leyendo => _leyendo;

  /// Texto que se está leyendo — expuesto para exploración táctil continua.
  String _textoActual = '';
  String get textoActual => _textoActual;

  /// Marca interacción del usuario (Chrome la requiere para audio).
  static void marcarInteraccion() {}

  /// Lee [texto] en voz alta.
  /// Si ya está leyendo el mismo texto → no interrumpe.
  /// Si está leyendo otro texto → cancela y empieza el nuevo.
  Future<void> speak(String texto) async {
    if (texto.isEmpty) return;

    // Mismo texto → no interrumpir
    if (_leyendo && _textoActual == texto) return;

    // Cancelar lectura anterior
    PlatformUtils.stopSpeech();

    _leyendo     = true;
    _textoActual = texto;

    // Delegar a PlatformUtils (web: speechSynthesis, Android: flutter_tts)
    PlatformUtils.speak(texto, lang: 'es-CO');

    // Estimar duración para resetear estado cuando termine
    final ms = 800 + texto.length * 50;
    Future.delayed(Duration(milliseconds: ms), () {
      if (_textoActual == texto && _leyendo) {
        _leyendo     = false;
        _textoActual = '';
      }
    });
  }

  /// Detiene la lectura inmediatamente.
  Future<void> stop() async {
    PlatformUtils.stopSpeech();
    _leyendo     = false;
    _textoActual = '';
  }
}
