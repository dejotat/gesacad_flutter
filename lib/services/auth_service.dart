import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/api_config.dart';

/// Servicio de autenticación y gestión de sesión de usuario.
///
/// Implementa el requisito RF02 (Redirección por rol) almacenando localmente
/// los datos del usuario autenticado usando [SharedPreferences].
/// La sesión persiste aunque el usuario cierre la aplicación.
///
/// Claves almacenadas:
/// - `userId`: ID numérico del usuario en la base de datos.
/// - `userName`: Nombre de usuario (para saludos en la UI).
/// - `userRol`: Rol del usuario ('Admin', 'Teacher' o 'Student').
class AuthService {
  // Claves privadas para SharedPreferences — no exponer al exterior.
  static const _keyId = 'userId';
  static const _keyName = 'userName';
  static const _keyRol = 'userRol';

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

  /// Descarga el perfil del backend y guarda la foto en caché local.
  /// Se llama al hacer login para que el dashboard la muestre sin abrir el perfil.
  /// No lanza excepciones — si falla, el dashboard muestra el ícono gris.
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

  /// Elimina todos los datos de sesión del dispositivo (cierre de sesión).
  ///
  /// Debe llamarse antes de navegar al [LoginScreen] para garantizar
  /// que el splash no redirija automáticamente al home anterior.
  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
