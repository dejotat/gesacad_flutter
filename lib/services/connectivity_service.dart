import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';

/// ¿El error corresponde a una falla de red (sin conexión, DNS, timeout)?
///
/// Se distingue de un error de la aplicación (JSON inválido, bug) para no
/// confundir "sin internet" con "el servidor respondió algo inesperado".
/// No usa `dart:io` para funcionar igual en web (`http.ClientException`).
bool isNetworkError(Object e) =>
    e is TimeoutException ||
    e is http.ClientException ||
    e.runtimeType.toString() == 'SocketException' ||
    e.runtimeType.toString() == '_ClientSocketException' ||
    e.runtimeType.toString() == 'HandshakeException';

/// Estado de conexión **con el backend de GESACAD**.
///
/// No se limita a preguntar si hay wifi o datos móviles (eso no garantiza que
/// el servidor responda): aprende de las peticiones reales. Cada llamada de
/// [ApiService] informa su resultado con [reportSuccess] / [reportFailure] y,
/// mientras se está sin conexión, un sondeo periódico a `/health` detecta
/// cuándo vuelve el servicio.
///
/// Es optimista: arranca "en línea" para no mostrar avisos falsos al abrir.
class ConnectivityService with WidgetsBindingObserver {
  ConnectivityService._({Future<bool> Function()? probe, Duration? interval})
      : _probe = probe ?? _defaultProbe,
        _interval = interval ?? const Duration(seconds: 10);

  static ConnectivityService instance = ConnectivityService._();

  /// Instancia aislada para pruebas (sondeo e intervalo inyectables).
  @visibleForTesting
  factory ConnectivityService.test(
          {required Future<bool> Function() probe, Duration? interval}) =>
      ConnectivityService._(probe: probe, interval: interval);

  final Future<bool> Function() _probe;
  final Duration _interval;
  Timer? _timer;
  bool _checking = false;

  /// `true` cuando el backend es alcanzable.
  final ValueNotifier<bool> online = ValueNotifier<bool>(true);

  static Future<bool> _defaultProbe() async {
    try {
      final r = await http
          .get(Uri.parse('${ApiConfig.baseUrl}/health'))
          .timeout(const Duration(seconds: 6));
      return r.statusCode < 500;
    } catch (_) {
      return false;
    }
  }

  /// Activa la detección al volver a primer plano (llamar una vez al inicio).
  void start() => WidgetsBinding.instance.addObserver(this);

  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Al volver a la app tras un rato, comprobar de inmediato.
    if (state == AppLifecycleState.resumed && !online.value) checkNow();
  }

  /// Una petición al backend funcionó: estamos en línea.
  void reportSuccess() {
    if (!online.value) {
      online.value = true;
    }
    _timer?.cancel();
    _timer = null;
  }

  /// Una petición falló: si es de red, pasamos a modo sin conexión y
  /// empezamos a sondear para detectar el regreso del servicio.
  void reportFailure(Object error) {
    if (!isNetworkError(error)) return;
    if (online.value) online.value = false;
    _timer ??= Timer.periodic(_interval, (_) => checkNow());
  }

  /// Comprueba ahora mismo si el backend responde (botón "Reintentar").
  Future<bool> checkNow() async {
    if (_checking) return online.value;
    _checking = true;
    try {
      final ok = await _probe();
      if (ok) {
        reportSuccess();
      } else if (online.value) {
        online.value = false;
        _timer ??= Timer.periodic(_interval, (_) => checkNow());
      }
      return ok;
    } finally {
      _checking = false;
    }
  }
}
