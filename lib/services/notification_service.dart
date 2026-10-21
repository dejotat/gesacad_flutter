import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import '../models/notification_models.dart';
import 'api_service.dart' show ApiMessageException;

/// Bandeja de notificaciones del usuario (CU-11).
///
/// - El estado de leído vive en el **servidor**: se sincroniza entre dispositivos.
/// - **Sondeo adaptativo**: consulta `/notifications/summary` cada [intervalo] mientras la
///   app está en primer plano, se detiene en segundo plano y se pone al día al volver.
///   Es una consulta liviana (un contador y, si hay, las novedades).
/// - Las novedades llegan por [arrivals] para mostrar un aviso en pantalla.
/// - La primera página se guarda para verla sin conexión.
class NotificationService with WidgetsBindingObserver {
  NotificationService._({this.intervalo = const Duration(seconds: 20)});

  static NotificationService instance = NotificationService._();

  /// Instancia aislada para pruebas.
  @visibleForTesting
  factory NotificationService.test({Duration intervalo = const Duration(seconds: 20)}) =>
      NotificationService._(intervalo: intervalo);

  final Duration intervalo;

  /// Cantidad de no leídas (para la insignia de la campana).
  final ValueNotifier<int> unread = ValueNotifier(0);

  final StreamController<List<AppNotif>> _arrivals = StreamController.broadcast();

  /// Notificaciones nuevas detectadas mientras la app estaba abierta.
  Stream<List<AppNotif>> get arrivals => _arrivals.stream;

  int _userId = 0;
  String _rol = 'Student';
  int _latestId = 0;
  bool _baseline = false;
  int _refs = 0;
  Timer? _timer;
  Future<void>? _enCurso;
  bool _observing = false;

  int get userId => _userId;
  String get rol => _rol;

  Map<String, String> get _identidad => {'userId': '$_userId', 'rol': _rol};
  Uri _uri(String path, [Map<String, String> query = const {}]) =>
      Uri.parse('${ApiConfig.baseUrl}$path').replace(queryParameters: {..._identidad, ...query});

  // ── Ciclo de vida ───────────────────────────────────────────────────────────
  /// Empieza a vigilar la bandeja de [userId]. Cada llamada debe equilibrarse con [detach].
  void attach(int userId, String rol) {
    if (userId <= 0) return;
    if (userId != _userId) _reiniciar(userId, rol);
    _rol = rol;
    _refs++;
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    _arrancarTemporizador();
    unawaited(poll());
  }

  void detach() {
    if (_refs > 0) _refs--;
    if (_refs == 0) {
      _timer?.cancel();
      _timer = null;
      if (_observing) {
        WidgetsBinding.instance.removeObserver(this);
        _observing = false;
      }
    }
  }

  /// Olvida la sesión (al cerrar sesión).
  void clear() {
    _timer?.cancel();
    _timer = null;
    _refs = 0;
    _reiniciar(0, 'Student');
    if (_observing) {
      WidgetsBinding.instance.removeObserver(this);
      _observing = false;
    }
  }

  void _reiniciar(int userId, String rol) {
    _userId = userId;
    _rol = rol;
    _latestId = 0;
    _baseline = false;
    unread.value = 0;
  }

  void _arrancarTemporizador() {
    _timer ??= Timer.periodic(intervalo, (_) => poll());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_refs > 0) {
        _arrancarTemporizador();
        unawaited(poll());
      }
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _timer?.cancel();
      _timer = null;
    }
  }

  // ── Sondeo ──────────────────────────────────────────────────────────────────
  /// Consulta novedades. Nunca lanza: sin red simplemente conserva lo último.
  Future<void> poll() {
    if (_userId <= 0) return Future.value();
    return _enCurso ??= _sondear().whenComplete(() => _enCurso = null);
  }

  Future<void> _sondear() async {
    try {
      final res = await http.get(_uri('/notifications/summary', {'after': '$_latestId'})).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return;
      final d = jsonDecode(res.body) as Map<String, dynamic>;
      unread.value = (d['unread'] as num?)?.toInt() ?? 0;
      final latest = (d['latestId'] as num?)?.toInt() ?? 0;
      final nuevas = (d['items'] as List? ?? [])
          .map((e) => AppNotif.fromJson(e as Map<String, dynamic>))
          .toList();
      // La primera consulta solo fija el punto de partida: lo que ya existía no es "nuevo".
      if (_baseline && nuevas.isNotEmpty) _arrivals.add(nuevas);
      if (latest > _latestId) _latestId = latest;
      _baseline = true;
    } catch (_) {
      // Sin conexión o servidor dormido: se reintenta en el próximo ciclo.
    }
  }

  // ── Bandeja ─────────────────────────────────────────────────────────────────
  static String _claveCache(int uid) => 'notif_cache_v2_$uid';

  Never _fallo(http.Response res) {
    var mensaje = 'No se pudo completar la acción (código ${res.statusCode}).';
    try {
      final d = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
      if (d is Map && d['message'] != null) mensaje = d['message'].toString();
    } catch (_) {
      if (res.statusCode == 404) mensaje = 'El servidor todavía no tiene habilitadas las notificaciones.';
    }
    throw ApiMessageException(res.statusCode, mensaje);
  }

  /// Una página de la bandeja. La primera página sin filtros se guarda para uso sin conexión.
  Future<NotifPage> list({int? before, NotifType? type, bool unreadOnly = false, int limit = 30}) async {
    final sinFiltros = before == null && type == null && !unreadOnly;
    try {
      final res = await http
          .get(_uri('/notifications', {
            'limit': '$limit',
            if (before != null) 'before': '$before',
            if (type != null) 'type': type.name,
            if (unreadOnly) 'unread': '1',
          }))
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) _fallo(res);
      final d = jsonDecode(res.body) as Map<String, dynamic>;
      final page = NotifPage(
        items: (d['items'] as List? ?? []).map((e) => AppNotif.fromJson(e as Map<String, dynamic>)).toList(),
        unread: (d['unread'] as num?)?.toInt() ?? 0,
        nextBefore: (d['nextBefore'] as num?)?.toInt(),
      );
      unread.value = page.unread;
      if (sinFiltros) {
        try {
          (await SharedPreferences.getInstance()).setString(
              _claveCache(_userId), jsonEncode({'items': page.items.map((n) => n.toJson()).toList(), 'unread': page.unread}));
        } catch (_) {}
      }
      return page;
    } on ApiMessageException {
      rethrow;
    } catch (e) {
      // Sin red: la última copia guardada, solo para la vista sin filtros.
      if (sinFiltros) {
        try {
          final raw = (await SharedPreferences.getInstance()).getString(_claveCache(_userId));
          if (raw != null) {
            final d = jsonDecode(raw) as Map<String, dynamic>;
            return NotifPage(
              items: (d['items'] as List).map((x) => AppNotif.fromJson(x as Map<String, dynamic>)).toList(),
              unread: (d['unread'] as num?)?.toInt() ?? 0,
              fromCache: true,
            );
          }
        } catch (_) {}
      }
      rethrow;
    }
  }

  Future<http.Response> _enviar(String metodo, String path, [Map<String, dynamic>? cuerpo]) async {
    final uri = _uri(path);
    const cabeceras = {'Content-Type': 'application/json'};
    final body = jsonEncode({...?cuerpo, 'userId': _userId, 'rol': _rol});
    final Future<http.Response> envio = switch (metodo) {
      'POST' => http.post(uri, headers: cabeceras, body: body),
      'PUT' => http.put(uri, headers: cabeceras, body: body),
      _ => http.delete(uri, headers: cabeceras),
    };
    final res = await envio.timeout(const Duration(seconds: 20));
    if (res.statusCode < 200 || res.statusCode >= 300) _fallo(res);
    return res;
  }

  void _actualizarContador(http.Response res) {
    try {
      final d = jsonDecode(res.body);
      if (d is Map && d['unread'] is num) unread.value = (d['unread'] as num).toInt();
    } catch (_) {}
  }

  Future<void> markRead(List<int> ids) async {
    if (ids.isEmpty) return;
    _actualizarContador(await _enviar('POST', '/notifications/read', {'ids': ids}));
  }

  Future<void> markAllRead() async => _actualizarContador(await _enviar('POST', '/notifications/read', {'all': true}));

  Future<void> delete(int id) async => _actualizarContador(await _enviar('DELETE', '/notifications/$id'));

  /// Borra las leídas (o todas con [soloLeidas] = false).
  Future<int> deleteBulk({bool soloLeidas = true}) async {
    final res = await _enviar('POST', '/notifications/clear', {'onlyRead': soloLeidas});
    _actualizarContador(res);
    return ((jsonDecode(res.body) as Map)['deleted'] as num?)?.toInt() ?? 0;
  }

  // ── Preferencias ────────────────────────────────────────────────────────────
  Future<Map<NotifType, bool>> preferences() async {
    final res = await http.get(_uri('/notifications/preferences')).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) _fallo(res);
    final tipos = (jsonDecode(res.body) as Map)['types'] as Map? ?? {};
    return {for (final t in NotifType.values) t: tipos[t.name] != false};
  }

  Future<void> setPreference(NotifType tipo, bool activo) async {
    await _enviar('PUT', '/notifications/preferences', {'type': tipo.name, 'enabled': activo});
  }
}
