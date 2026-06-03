import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/api_config.dart';

/// Servicio de autenticación y gestión de sesión de usuario.
///
/// Flujo completo de autenticación en GESACAD:
/// ```
///   login_screen → ApiService().login()       → respuesta backend
///                → AuthService().saveSession() → guarda en SharedPreferences
///                → unawaited(fetchAndCachePhoto()) → foto en background
///                → Navigator → AdminHome / TeacherHome / StudentHome
///
///   SplashScreen → AuthService().getSession() → hay sesión → ir a home
///                                             → sin sesión → ir a login
///
///   logout       → AuthService().clearSession() → borra SharedPreferences
///                → Navigator → LoginScreen
/// ```
///
/// Claves guardadas en SharedPreferences:
/// - `userId`   → ID numérico del usuario en MySQL
/// - `userName` → username para saludos en la interfaz
/// - `userRol`  → rol: 'Admin', 'Teacher' o 'Student' (controla qué home se muestra)
///
/// Claves de perfil extendido (cargadas por [fetchAndCachePhoto]):
/// - `profile_telefono`, `profile_bio`, `profile_email_personal`,
///   `profile_email_inst`, `profile_programa`, `profile_semestre`,
///   `profile_photo` (base64), `profile_photo_url`
class AuthService {
  // Claves privadas para SharedPreferences — centralizadas aquí para evitar
  // strings dispersos en el código que pueden causar errores de tipeo.
  static const _keyId   = 'userId';
  static const _keyName = 'userName';
  static const _keyRol  = 'userRol';

  /// Guarda los datos del usuario en la sesión local tras un login exitoso.
  ///
  /// Parámetros:
  /// - [id]: ID del usuario retornado por el backend (de la respuesta LOGIN_SUCCESFULLY).
  /// - [name]: Nombre de usuario para mostrar en la interfaz.
  /// - [rol]: Rol del usuario que determina qué pantalla se muestra (RF02).
  ///
  /// Uso: llamar inmediatamente después de recibir respuesta exitosa del login.
  Future<void> saveSession(int id, String name, String rol) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyId, id);
    await prefs.setString(_keyName, name);
    await prefs.setString(_keyRol, rol);
  }

  /// Recupera los datos de la sesión activa del usuario.
  ///
  /// Retorna un mapa con `id`, `name` y `rol`, o `null` si no hay sesión activa.
  /// Usado en el [SplashScreen] para decidir si redirigir al login o al home.
  Future<Map<String, dynamic>?> getSession() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getInt(_keyId);
    if (id == null) return null; // Sin sesión guardada → ir a login.
    return {
      'id': id,
      'name': prefs.getString(_keyName) ?? '',
      'rol': prefs.getString(_keyRol) ?? '',
    };
  }

  /// Descarga perfil y foto del backend y los guarda en SharedPreferences.
  ///
  /// Se llama con [unawaited] inmediatamente tras [saveSession] en el login,
  /// de forma que no bloquea la navegación al home. La foto llega ~1-2s después
  /// y los homes la muestran automáticamente mediante [Future.delayed(_reloadPhoto)].
  ///
  /// Estrategia: si Cloudinary o el backend no responden, el error se silencia
  /// y el dashboard muestra el ícono de rol por defecto hasta que el usuario
  /// abra Mi Perfil manualmente (que también descarga la foto).
  Future<void> fetchAndCachePhoto(int userId) async {
    try {
      final res = await http.get(
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.getProfile}/$userId'),
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return;

      final perfil = jsonDecode(res.body) as Map<String, dynamic>;
      final prefs  = await SharedPreferences.getInstance();

      // Guardar campos de perfil en caché para que Mi Perfil cargue rápido
      await prefs.setString('profile_telefono',       perfil['telefono']?.toString()       ?? '');
      await prefs.setString('profile_bio',            perfil['bio']?.toString()            ?? '');
      await prefs.setString('profile_email_personal', perfil['email_personal']?.toString() ?? '');
      await prefs.setString('profile_email_inst',     perfil['email_inst']?.toString()     ?? '');
      await prefs.setString('profile_programa',       perfil['programa']?.toString()       ?? '');
      await prefs.setString('profile_semestre',       perfil['semestre']?.toString()       ?? '');

      // Descargar foto desde Cloudinary y guardar como base64
      final photoUrl = perfil['photo_url']?.toString() ?? '';
      if (photoUrl.isEmpty) return;
      final imgRes = await http.get(Uri.parse(photoUrl))
          .timeout(const Duration(seconds: 10));
      if (imgRes.statusCode != 200) return;
      await prefs.setString('profile_photo',     base64Encode(imgRes.bodyBytes));
      await prefs.setString('profile_photo_url', photoUrl);
    } catch (_) {
      // Sin conexión o Cloudinary no disponible: no es error crítico
    }
  }

  /// Elimina todos los datos de sesión y caché del dispositivo (cierre de sesión).
  ///
  /// Llama a [prefs.clear()] que borra TODAS las claves de SharedPreferences,
  /// incluyendo el perfil extendido y la foto. Esto garantiza que:
  /// 1. El [SplashScreen] redirigirá al login en la próxima apertura.
  /// 2. Si otro usuario inicia sesión, no verá datos del usuario anterior.
  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
