import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import 'notification_service.dart';

/// Configuración de Firebase, inyectada al compilar con `--dart-define` (son valores
/// públicos de tu proyecto, no secretos). Sin ellos las push quedan apagadas y la app
/// funciona igual con su bandeja. Ver `tool/compilar_apk.ps1`.
class PushConfig {
  static const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const senderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  static const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const appVersion = String.fromEnvironment('APP_VERSION');

  /// Solo en celulares: en la web el aviso llega por la bandeja mientras la pestaña está abierta.
  static bool get configurado =>
      !kIsWeb && [apiKey, appId, senderId, projectId].every((v) => v.isNotEmpty);
}

/// Mensaje push recibido (lo que envía `Backend/push.js`).
class PushMensaje {
  const PushMensaje({this.title, this.body, this.data = const {}});
  final String? title;
  final String? body;
  final Map<String, String> data;

  int? get notificationId => int.tryParse(data['notificationId'] ?? '');
  String? get refType => data['refType'];
  int? get refId => int.tryParse(data['refId'] ?? '');
  int? get courseId => int.tryParse(data['courseId'] ?? '');
  String? get courseName => data['courseName'];
  String? get courseCode => data['courseCode'];
  int? get courseImg => int.tryParse(data['courseImg'] ?? '');
}

/// Permiso de notificaciones del sistema.
enum PermisoPush { concedido, denegado, sinDecidir }

/// Lo único que `PushService` necesita de Firebase. Así se prueba con un transporte falso
/// y solo `push_transport_firebase.dart` importa los paquetes de Firebase.
abstract class PushTransport {
  Future<void> init();
  Future<PermisoPush> permiso();
  Future<PermisoPush> solicitarPermiso();
  Future<String?> token();
  Stream<String> get tokenRenovado;

  /// Mensaje que llega con la app ABIERTA (el sistema no muestra aviso en ese caso).
  Stream<PushMensaje> get enPrimerPlano;

  /// El usuario tocó el aviso con la app en segundo plano.
  Stream<PushMensaje> get alAbrir;

  /// El usuario tocó el aviso con la app CERRADA y esa fue la que la abrió.
  Future<PushMensaje?> mensajeInicial();
  Future<void> borrarToken();
}

/// Estado de las notificaciones push en este teléfono.
enum PushEstado {
  /// Sin Firebase en esta compilación, en la web o el servidor no envía push.
  noDisponible,

  /// Todavía no se ha iniciado o el usuario respondió "ahora no".
  inactivo,

  /// Falta pedir el permiso del sistema (se explica antes con un diálogo propio).
  pendientePermiso,

  /// Registrado: los avisos llegan aunque la app esté cerrada.
  activo,

  /// El permiso está bloqueado en los ajustes del teléfono.
  denegado,

  /// El usuario las apagó desde las preferencias de la app.
  desactivadoPorUsuario,
}

/// Notificaciones push (CU-13). Registra el teléfono en el servidor, mantiene el token al día,
/// refresca la bandeja cuando llega un aviso con la app abierta y lleva al usuario a lo que
/// originó el aviso cuando lo toca.
class PushService {
  PushService._({PushTransport? transporte, bool? configurado, NotificationService? notificaciones})
      : _transporte = transporte,
        _configurado = configurado ?? PushConfig.configurado,
        _notificaciones = notificaciones;

  static PushService instance = PushService._();

  @visibleForTesting
  factory PushService.test({
    PushTransport? transporte,
    bool configurado = true,
    NotificationService? notificaciones,
  }) =>
      PushService._(transporte: transporte, configurado: configurado, notificaciones: notificaciones);

  PushTransport? _transporte;
  final bool _configurado;
  final NotificationService? _notificaciones;
  NotificationService get _notifs => _notificaciones ?? NotificationService.instance;

  /// Estado actual (la interfaz lo escucha).
  final ValueNotifier<PushEstado> estado = ValueNotifier(PushEstado.noDisponible);

  /// Quien lo configura (main) decide a dónde ir cuando se toca un aviso.
  Future<void> Function(PushMensaje mensaje)? alTocar;

  static const _clavePreguntado = 'push_preguntado_v1';
  static const _claveToken = 'push_token_v1';

  int _userId = 0;
  String _rol = 'Student';
  bool _escuchando = false;
  final List<StreamSubscription<dynamic>> _subs = [];

  /// Lo que se mostrará cuando el usuario toque un aviso y la app todavía no esté lista.
  PushMensaje? _pendiente;

  bool get disponible => _configurado && _transporte != null;

  /// Registra el transporte real (lo llama `main`). No hace nada sin configuración.
  void usarTransporte(PushTransport t) => _transporte ??= t;

  /// Inicializa Firebase y se suscribe a los eventos. Nunca lanza: un fallo aquí no debe
  /// impedir que la app abra.
  Future<void> init() async {
    final t = _transporte;
    if (!_configurado || t == null) return;
    try {
      await t.init();
      _escuchar(t);
      final inicial = await t.mensajeInicial();
      if (inicial != null) _alTocar(inicial);
    } catch (e) {
      debugPrint('[Push] No se pudo inicializar: $e');
      estado.value = PushEstado.noDisponible;
    }
  }

  void _escuchar(PushTransport t) {
    if (_escuchando) return;
    _escuchando = true;
    _subs
      ..add(t.tokenRenovado.listen((nuevo) {
        if (_userId > 0 && estado.value == PushEstado.activo) unawaited(_registrar(nuevo));
      }))
      // Con la app abierta el sistema no muestra aviso: se trae lo nuevo de inmediato
      // y la bandeja lo muestra con su propio aviso flotante.
      ..add(t.enPrimerPlano.listen((_) => unawaited(_notifs.poll())))
      ..add(t.alAbrir.listen(_alTocar));
  }

  void _alTocar(PushMensaje m) {
    // Marcar como leída la notificación a la que corresponde (si el aviso la identifica).
    final id = m.notificationId;
    if (id != null && _userId > 0) unawaited(_notifs.markRead([id]).catchError((_) {}));
    final accion = alTocar;
    if (accion == null) {
      _pendiente = m;
      return;
    }
    unawaited(accion(m).catchError((Object e) => debugPrint('[Push] No se pudo abrir el aviso: $e')));
  }

  /// Si el usuario tocó un aviso antes de que la app estuviera lista, lo abre ahora.
  Future<void> abrirPendiente() async {
    final m = _pendiente;
    final accion = alTocar;
    if (m == null || accion == null) return;
    _pendiente = null;
    await accion(m);
  }

  Uri _uri(String ruta) => Uri.parse('${ApiConfig.baseUrl}$ruta')
      .replace(queryParameters: {'userId': '$_userId', 'rol': _rol});

  Future<Map<String, dynamic>?> _estadoServidor() async {
    try {
      final res = await http.get(_uri('/push/status')).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Empieza para el usuario con sesión. Se puede llamar muchas veces.
  Future<void> start(int userId, String rol) async {
    final t = _transporte;
    if (userId <= 0) return;
    _userId = userId;
    _rol = rol;
    if (!_configurado || t == null) {
      estado.value = PushEstado.noDisponible;
      return;
    }
    final srv = await _estadoServidor();
    if (srv == null) return; // sin conexión: se reintenta en la próxima apertura
    if (srv['enabled'] != true) {
      estado.value = PushEstado.noDisponible;
      return;
    }
    if (srv['userEnabled'] == false) {
      estado.value = PushEstado.desactivadoPorUsuario;
      return;
    }
    switch (await t.permiso()) {
      case PermisoPush.concedido:
        estado.value = PushEstado.activo;
        await _registrar(await t.token());
      case PermisoPush.denegado:
        estado.value = PushEstado.denegado;
      case PermisoPush.sinDecidir:
        final yaPreguntado = (await SharedPreferences.getInstance()).getBool(_clavePreguntado) ?? false;
        estado.value = yaPreguntado ? PushEstado.inactivo : PushEstado.pendientePermiso;
    }
  }

  /// ¿Conviene mostrar el diálogo que explica para qué sirven los avisos?
  bool get debePreguntar => estado.value == PushEstado.pendientePermiso;

  /// El usuario dijo "ahora no": no se le vuelve a insistir (puede activarlo en Preferencias).
  Future<void> posponer() async {
    (await SharedPreferences.getInstance()).setBool(_clavePreguntado, true);
    if (estado.value == PushEstado.pendientePermiso) estado.value = PushEstado.inactivo;
  }

  /// Pide el permiso del sistema y, si lo dan, registra el teléfono. Devuelve si quedó activo.
  Future<bool> solicitarPermiso() async {
    final t = _transporte;
    if (t == null || !_configurado) return false;
    (await SharedPreferences.getInstance()).setBool(_clavePreguntado, true);
    final r = await t.solicitarPermiso();
    if (r == PermisoPush.concedido) {
      estado.value = PushEstado.activo;
      await _registrar(await t.token());
      return true;
    }
    estado.value = r == PermisoPush.denegado ? PushEstado.denegado : PushEstado.inactivo;
    return false;
  }

  /// Registra (o actualiza) el dispositivo. No repite la petición si el token no cambió.
  Future<void> _registrar(String? token) async {
    if (token == null || token.isEmpty || _userId <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    final clave = '$_claveToken:$_userId';
    if (prefs.getString(clave) == token) return;
    try {
      final res = await http
          .post(_uri('/push/devices'),
              headers: const {'Content-Type': 'application/json'},
              body: jsonEncode({
                'token': token,
                'platform': defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
                if (PushConfig.appVersion.isNotEmpty) 'appVersion': PushConfig.appVersion,
              }))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 201) await prefs.setString(clave, token);
    } catch (e) {
      debugPrint('[Push] No se pudo registrar el dispositivo: $e');
    }
  }

  /// Activa o desactiva los avisos en el teléfono (la bandeja no se toca).
  Future<void> setUserEnabled(bool activo) async {
    final res = await http
        .put(_uri('/push/settings'),
            headers: const {'Content-Type': 'application/json'}, body: jsonEncode({'enabled': activo}))
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) throw StateError('No se pudo guardar la preferencia (${res.statusCode}).');
    if (!activo) {
      estado.value = PushEstado.desactivadoPorUsuario;
      return;
    }
    await start(_userId, _rol);
    if (estado.value == PushEstado.pendientePermiso || estado.value == PushEstado.inactivo) {
      await solicitarPermiso();
    }
  }

  /// Al cerrar sesión: el teléfono deja de recibir los avisos de este usuario. Debe llamarse
  /// ANTES de borrar la sesión (necesita el token para avisar al servidor). Nunca lanza.
  Future<void> stop() async {
    final t = _transporte;
    final uid = _userId;
    // 1) Avisar al servidor. Si no hay red, se sigue igual: el servidor limpia solo los
    //    tokens que FCM declare muertos, pero el del teléfono NO puede quedarse.
    try {
      if (uid > 0) {
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString('$_claveToken:$uid');
        if (token != null) {
          await prefs.remove('$_claveToken:$uid');
          await http
              .delete(_uri('/push/devices'),
                  headers: const {'Content-Type': 'application/json'}, body: jsonEncode({'token': token}))
              .timeout(const Duration(seconds: 8));
        }
      }
    } catch (e) {
      debugPrint('[Push] No se pudo avisar al servidor al cerrar sesión: $e');
    }
    // 2) Token nuevo para el siguiente usuario de este teléfono (siempre, haya o no red).
    try {
      if (t != null && _configurado) await t.borrarToken();
    } catch (e) {
      debugPrint('[Push] No se pudo borrar el token local: $e');
    }
    _userId = 0;
    _pendiente = null;
    if (_configurado && t != null) estado.value = PushEstado.inactivo;
  }

  @visibleForTesting
  Future<void> cerrar() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    _escuchando = false;
  }
}
