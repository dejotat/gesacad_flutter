import 'package:shared_preferences/shared_preferences.dart';

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

  /// Elimina todos los datos de sesión del dispositivo (cierre de sesión).
  ///
  /// Debe llamarse antes de navegar al [LoginScreen] para garantizar
  /// que el splash no redirija automáticamente al home anterior.
  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
