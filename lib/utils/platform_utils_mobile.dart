import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:image_picker/image_picker.dart';

/// Implementación ANDROID/iOS de PlatformUtils.
class PlatformUtils {
  PlatformUtils._();

  static final _tts     = FlutterTts();
  static bool  _ttsInit = false;

  static Future<void> _initTts() async {
    if (_ttsInit) return;
    await _tts.setLanguage('es-CO');
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.05);
    _ttsInit = true;
  }

  /// Abre una URL en el navegador del dispositivo.
  static void openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// Descarga un archivo (en Android abre la URL en el navegador).
  static void downloadFile(String url, String fileName) => openUrl(url);

  /// Lee texto en voz alta con flutter_tts.
  static void speak(String text, {String lang = 'es-CO'}) async {
    await _initTts();
    await _tts.speak(text);
  }

  /// Detiene la lectura de voz.
  static void stopSpeech() async {
    await _tts.stop();
  }

  /// Selecciona una imagen de la galería del dispositivo.
  static Future<List<int>?> pickImage() async {
    final picker = ImagePicker();
    final file   = await picker.pickImage(source: ImageSource.gallery);
    if (file == null) return null;
    return (await file.readAsBytes()).toList();
  }
}
