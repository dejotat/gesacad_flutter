// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'voice_picker.dart';

/// Implementación WEB de PlatformUtils usando dart:html.
/// Se usa automáticamente cuando se compila para web.
class PlatformUtils {
  PlatformUtils._();

  /// Abre una URL en nueva pestaña del navegador.
  static void openUrl(String url) {
    html.window.open(url, '_blank');
  }

  /// Descarga un archivo con nombre personalizado.
  static void downloadFile(String url, String fileName) {
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', fileName)
      ..setAttribute('target', '_blank');
    html.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
  }

  /// Lee texto en voz alta con Web Speech API.
  /// Nota: Chrome requiere una interacción del usuario antes del primer audio.
  static void speak(String text, {String lang = 'es-CO'}) {
    final synth = html.window.speechSynthesis;
    if (synth == null) return;
    synth.cancel();
    final voz = _vozElegante(synth);
    final masculina = voz != null && esVozMasculina(voz.name ?? '', voz.lang ?? '');
    final utt = html.SpeechSynthesisUtterance(text)
      ..lang   = voz?.lang ?? lang
      // Ritmo pausado y tono grave: suena sereno y elegante. Si no hay voz masculina conocida,
      // el tono más grave la acerca a una.
      ..rate   = 0.95
      ..volume = 1.0
      ..pitch  = masculina ? 0.9 : 0.75;
    if (voz != null) utt.voice = voz;
    synth.speak(utt);
  }

  /// Mejor voz masculina en español que tenga el navegador (las voces cargan de forma asíncrona:
  /// si aún no hay ninguna se usa la predeterminada y la siguiente lectura ya las encuentra).
  static html.SpeechSynthesisVoice? _vozElegante(html.SpeechSynthesis synth) {
    try {
      final voces = synth.getVoices();
      final i = mejorVoz([for (final v in voces) (nombre: v.name ?? '', idioma: v.lang ?? '')]);
      return i == null ? null : voces[i];
    } catch (_) {
      return null;
    }
  }

  /// Detiene la lectura de voz en curso.
  static void stopSpeech() {
    html.window.speechSynthesis?.cancel();
  }

  /// Selecciona una imagen del dispositivo (web: FileUploadInputElement).
  static Future<List<int>?> pickImage() async {
    final upload = html.FileUploadInputElement()
      ..accept = 'image/*'
      ..click();
    await upload.onChange.first;
    final file = upload.files?.first;
    if (file == null) return null;
    final reader = html.FileReader();
    reader.readAsArrayBuffer(file);
    await reader.onLoad.first;
    final result = reader.result;
    if (result is List<int>) return result;
    return null;
  }
}
