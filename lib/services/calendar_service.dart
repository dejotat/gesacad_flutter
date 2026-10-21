import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import '../models/calendar_models.dart';
import 'api_service.dart' show ApiMessageException;

/// Calendario unificado y suscripción .ics (CU-12): `/calendar/*`.
///
/// Los eventos se guardan en SharedPreferences tras cada carga exitosa, así el
/// calendario se ve sin conexión con lo último que se sincronizó.
class CalendarService {
  const CalendarService();

  static const _timeout = Duration(seconds: 20);
  static String _claveEventos(int uid) => 'calendar_cache_v1_$uid';
  static String _claveFeed(int uid) => 'calendar_feed_url_$uid';

  Uri _uri(String path, int uid, String rol, [Map<String, String> q = const {}]) =>
      Uri.parse('${ApiConfig.baseUrl}$path').replace(queryParameters: {'userId': '$uid', 'rol': rol, ...q});

  Never _fallo(http.Response res) {
    var mensaje = 'No se pudo completar la acción (código ${res.statusCode}).';
    try {
      final d = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
      if (d is Map && d['message'] != null) mensaje = d['message'].toString();
    } catch (_) {
      if (res.statusCode == 404) mensaje = 'El servidor todavía no tiene habilitado el calendario unificado.';
    }
    throw ApiMessageException(res.statusCode, mensaje);
  }

  /// Eventos entre [desde] y [hasta] (máximo 400 días). Sin conexión usa la última copia.
  Future<CalLoad> events(int uid, String rol, {required DateTime desde, required DateTime hasta}) async {
    try {
      final res = await http
          .get(_uri('/calendar/events', uid, rol, {
            'from': desde.toUtc().toIso8601String(),
            'to': hasta.toUtc().toIso8601String(),
          }))
          .timeout(_timeout);
      if (res.statusCode != 200) _fallo(res);
      final lista = ((jsonDecode(res.body) as Map)['events'] as List? ?? [])
          .map((e) => CalEvent.fromJson(e as Map<String, dynamic>))
          .toList();
      try {
        (await SharedPreferences.getInstance())
            .setString(_claveEventos(uid), jsonEncode(lista.map((e) => e.toJson()).toList()));
      } catch (_) {}
      return CalLoad(events: lista);
    } on ApiMessageException {
      rethrow;
    } catch (_) {
      try {
        final raw = (await SharedPreferences.getInstance()).getString(_claveEventos(uid));
        if (raw != null) {
          return CalLoad(
            events: (jsonDecode(raw) as List).map((e) => CalEvent.fromJson(e as Map<String, dynamic>)).toList(),
            fromCache: true,
          );
        }
      } catch (_) {}
      rethrow;
    }
  }

  // ── Suscripción .ics ──────────────────────────────────────────────────────
  Future<FeedInfo> feedStatus(int uid, String rol) async {
    final res = await http.get(_uri('/calendar/feed', uid, rol)).timeout(_timeout);
    if (res.statusCode != 200) _fallo(res);
    final activo = (jsonDecode(res.body) as Map)['active'] == true;
    String? url;
    try {
      url = (await SharedPreferences.getInstance()).getString(_claveFeed(uid));
    } catch (_) {}
    return FeedInfo(active: activo, url: activo ? url : null);
  }

  /// Crea (o reemplaza) el enlace secreto. El anterior deja de funcionar.
  Future<String> createFeed(int uid, String rol) async {
    final res = await http
        .post(_uri('/calendar/feed', uid, rol), headers: const {'Content-Type': 'application/json'}, body: '{}')
        .timeout(_timeout);
    if (res.statusCode != 201) _fallo(res);
    final url = (jsonDecode(res.body) as Map)['url'].toString();
    try {
      await (await SharedPreferences.getInstance()).setString(_claveFeed(uid), url);
    } catch (_) {}
    return url;
  }

  Future<void> revokeFeed(int uid, String rol) async {
    final res = await http.delete(_uri('/calendar/feed', uid, rol)).timeout(_timeout);
    if (res.statusCode != 200) _fallo(res);
    try {
      await (await SharedPreferences.getInstance()).remove(_claveFeed(uid));
    } catch (_) {}
  }

  // ── Enlaces para suscribirse en cada aplicación ───────────────────────────
  static String _webcal(String url) => url.replaceFirst(RegExp(r'^https?://'), 'webcal://');

  /// Google Calendar: "Otros calendarios → Desde URL".
  static Uri googleSubscribeUri(String url) =>
      Uri.https('calendar.google.com', '/calendar/r', {'cid': _webcal(url)});

  /// Outlook en la web.
  static Uri outlookSubscribeUri(String url) =>
      Uri.https('outlook.live.com', '/calendar/0/addfromweb', {'url': url, 'name': 'GESACAD'});

  /// Apple Calendar y la mayoría de aplicaciones de escritorio/móvil entienden `webcal://`.
  static Uri appleSubscribeUri(String url) => Uri.parse(_webcal(url));
}
