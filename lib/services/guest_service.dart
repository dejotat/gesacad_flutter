import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import '../models/university_info.dart';
import 'api_service.dart' show ApiMessageException;

/// Modo invitado (CU-10): información pública de la universidad.
///
/// El invitado NO tiene sesión ni token: solo usa `/public/university`, que no
/// requiere autenticación. La última copia se guarda para verla sin conexión.
class GuestService {
  const GuestService();

  static const _timeout = Duration(seconds: 20);
  static const _claveCache = 'guest_university_v1';
  static const _claveRequisitos = 'guest_requisitos_v1';

  Uri get _uri => Uri.parse('${ApiConfig.baseUrl}/public/university');

  GuestContent? _leer(String cuerpo, {bool offline = false}) {
    try {
      final d = jsonDecode(cuerpo);
      if (d is! Map<String, dynamic> || d['content'] is! Map<String, dynamic>) return null;
      return GuestContent(
        info: UniversityInfo.fromJson(d['content'] as Map<String, dynamic>),
        isSample: d['isSample'] == true,
        offline: offline,
      );
    } catch (_) {
      return null;
    }
  }

  /// Carga la información; sin conexión usa la última copia y, si no hay, un ejemplo local.
  Future<GuestContent> load() async {
    SharedPreferences? prefs;
    try { prefs = await SharedPreferences.getInstance(); } catch (_) {}
    try {
      final res = await http.get(_uri).timeout(_timeout);
      if (res.statusCode == 200) {
        final c = _leer(utf8.decode(res.bodyBytes, allowMalformed: true));
        if (c != null) {
          await prefs?.setString(_claveCache, utf8.decode(res.bodyBytes, allowMalformed: true));
          return c;
        }
      }
    } catch (_) {
      // Sin red o servidor dormido: se cae a la copia guardada.
    }
    final guardado = prefs?.getString(_claveCache);
    final c = guardado == null ? null : _leer(guardado, offline: true);
    return c ?? const GuestContent(info: UniversityInfo.sample, isSample: true, offline: true);
  }

  Never _fallo(http.Response res) {
    var mensaje = 'No se pudo guardar (código ${res.statusCode}).';
    try {
      final d = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
      if (d is Map && d['message'] != null) mensaje = d['message'].toString();
    } catch (_) {
      if (res.statusCode == 404) mensaje = 'El servidor todavía no tiene habilitada esta función.';
    }
    throw ApiMessageException(res.statusCode, mensaje);
  }

  /// Admin: guarda el contenido público.
  Future<void> save(UniversityInfo info) async {
    final res = await http
        .put(_uri, headers: const {'Content-Type': 'application/json'}, body: jsonEncode({'content': info.toJson()}))
        .timeout(_timeout);
    if (res.statusCode != 200) _fallo(res);
    await _guardarCopia(res.body);
  }

  /// Admin: vuelve al contenido de ejemplo.
  Future<void> reset() async {
    final res = await http
        .put(_uri, headers: const {'Content-Type': 'application/json'}, body: jsonEncode({'reset': true}))
        .timeout(_timeout);
    if (res.statusCode != 200) _fallo(res);
    await _guardarCopia(res.body);
  }

  Future<void> _guardarCopia(String cuerpo) async {
    try {
      (await SharedPreferences.getInstance()).setString(_claveCache, cuerpo);
    } catch (_) {}
  }

  // ── "Mi ruta de matrícula": requisitos que el visitante ya reunió (solo en su equipo) ──
  Future<Set<String>> loadChecklist() async {
    try {
      return ((await SharedPreferences.getInstance()).getStringList(_claveRequisitos) ?? []).toSet();
    } catch (_) {
      return {};
    }
  }

  Future<void> saveChecklist(Set<String> hechos) async {
    try {
      await (await SharedPreferences.getInstance()).setStringList(_claveRequisitos, hechos.toList());
    } catch (_) {}
  }
}
