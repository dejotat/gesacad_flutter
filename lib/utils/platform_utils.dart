/// Utilidades multiplataforma para GESACAD.
///
/// Flutter selecciona automáticamente la implementación correcta:
/// - En WEB  → usa dart:html (window.open, speechSynthesis, etc.)
/// - En Android/iOS → usa url_launcher, flutter_tts, image_picker
///
/// USO en cualquier archivo:
///   import 'package:gesacad/utils/platform_utils.dart';
///   PlatformUtils.openUrl('https://...');
///   PlatformUtils.speak('Hola mundo');

export 'platform_utils_web.dart'
    if (dart.library.io) 'platform_utils_mobile.dart';
