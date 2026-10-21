import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import 'auth_service.dart';

/// Avisa a la interfaz cuando el servidor dice que la sesión ya no vale.
///
/// La navegación la registra `main.dart` ([alInvalidarse]) para que los servicios
/// no dependan de las pantallas. Se ignoran avisos repetidos: una ráfaga de
/// peticiones fallidas a la vez debe llevar al login una sola vez.
class SessionGuard {
  SessionGuard._();
  static final SessionGuard instance = SessionGuard._();

  /// Recibe el mensaje a mostrar en el login.
  void Function(String mensaje)? alInvalidarse;
  bool _activo = false;

  static const _mensajes = {
    'TOKEN_EXPIRADO': 'Tu sesión expiró. Inicia sesión de nuevo.',
    'TOKEN_INVALIDO': 'Tu sesión ya no es válida. Inicia sesión de nuevo.',
    'SESION_REVOCADA': 'Tu sesión se cerró (cambió tu contraseña o tu rol). Inicia sesión de nuevo.',
    'NO_AUTENTICADO': 'Inicia sesión para continuar.',
  };

  static bool esCodigoDeSesion(String? c) => _mensajes.containsKey(c);

  Future<void> sesionInvalida(String codigo) async {
    if (_activo) return;
    _activo = true;
    try {
      // Solo se quita el token: los datos guardados y los cambios pendientes de
      // enviar se conservan; se retoman al volver a iniciar sesión.
      await AuthService().expireSession();
      alInvalidarse?.call(_mensajes[codigo] ?? _mensajes['TOKEN_INVALIDO']!);
    } finally {
      Future.delayed(const Duration(seconds: 3), () => _activo = false);
    }
  }
}

/// Cliente HTTP de toda la app: añade `Authorization: Bearer <token>` y detecta
/// sesiones vencidas (401).
///
/// Se instala con `http.runWithClient(..., () => AuthClient())` en `main()`, así
/// TODAS las llamadas (`http.get`, `http.post`, subidas multipart…) pasan por aquí
/// sin tocar cada sitio de llamada.
///
/// Seguridad: el token se envía **únicamente** al servidor de GESACAD
/// ([ApiConfig.baseUrl]). Nunca a Cloudinary, ni a ningún otro dominio.
class AuthClient extends http.BaseClient {
  AuthClient({http.Client? inner, String? baseUrl, SessionGuard? guard})
      : _inner = inner ?? http.Client(),
        _origen = Uri.parse(baseUrl ?? ApiConfig.baseUrl).origin,
        _guard = guard ?? SessionGuard.instance;

  final http.Client _inner;
  final String _origen;
  final SessionGuard _guard;

  bool _esApi(Uri u) => u.origin == _origen;

  /// Rutas donde un 401 significa "credenciales incorrectas", no "sesión vencida".
  bool _esLogin(Uri u) => u.path.endsWith('/auth/login') || RegExp(r'^/users/[^/]+/[^/]+$').hasMatch(u.path);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final token = AuthService.currentToken;
    final api = _esApi(request.url);
    if (api && token != null && !request.headers.containsKey('Authorization')) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    final res = await _inner.send(request);

    if (api && token != null && res.statusCode == 401 && !_esLogin(request.url)) {
      // El cuerpo de un 401 es pequeño: se lee para distinguir la causa y se
      // devuelve intacto a quien hizo la llamada.
      final bytes = await res.stream.toBytes();
      String? codigo;
      try {
        // allowMalformed: aunque el texto del mensaje venga mal codificado, el código de
        // error (ASCII) debe poder leerse para reconocer una sesión vencida.
        final d = jsonDecode(utf8.decode(bytes, allowMalformed: true));
        if (d is Map) codigo = d['error']?.toString();
      } catch (_) {}
      if (SessionGuard.esCodigoDeSesion(codigo)) unawaited(_guard.sesionInvalida(codigo!));
      return http.StreamedResponse(
        http.ByteStream.fromBytes(bytes),
        res.statusCode,
        contentLength: bytes.length,
        request: res.request,
        headers: res.headers,
        isRedirect: res.isRedirect,
        persistentConnection: res.persistentConnection,
        reasonPhrase: res.reasonPhrase,
      );
    }
    return res;
  }

  @override
  void close() => _inner.close();
}
