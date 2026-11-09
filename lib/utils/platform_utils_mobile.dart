import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:image_picker/image_picker.dart';

import 'voice_picker.dart';

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
    // Voz masculina en español si el teléfono tiene alguna; si no, un tono más grave.
    var masculina = false;
    try {
      final todas = await _tts.getVoices;
      if (todas is List) {
        final voces = <({String nombre, String idioma})>[];
        final mapas = <Map<Object?, Object?>>[];
        for (final v in todas) {
          if (v is Map) {
            voces.add((nombre: '${v['name']}', idioma: '${v['locale']}'));
            mapas.add(v);
          }
        }
        final i = mejorVoz(voces);
        if (i != null) {
          await _tts.setVoice({'name': '${mapas[i]['name']}', 'locale': '${mapas[i]['locale']}'});
          masculina = esVozMasculina(voces[i].nombre, voces[i].idioma);
        }
      }
    } catch (_) {
      // Sin lista de voces: se queda la predeterminada.
    }
    await _tts.setPitch(masculina ? 0.9 : 0.75);
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
