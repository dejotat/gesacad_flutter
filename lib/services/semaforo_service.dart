import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/semaforo_models.dart';
import 'api_service.dart' show ApiMessageException;

/// Semáforo académico (CU-14): `/estudiantes/:id/semaforo`, `/malla/materias` y rutas de corrección.
///
/// Quién dispara cada cambio de estado:
///  * **Docente** de la materia → [registrarNota] (nota DEFINITIVA; el servidor decide aprobada o
///    reprobada con la nota mínima, 3.0).
///  * **Administración** → [corregir], solo para correcciones excepcionales, con motivo; queda en
///    el historial ([auditoria]).
///  * Estudiante, docente (sus alumnos) y Admin → [semaforo] (solo lectura).
///
/// Requieren conexión. Los errores del servidor llegan como [ApiMessageException] con el texto
/// listo para mostrar.
class SemaforoService {
  const SemaforoService();

  static const _timeout = Duration(seconds: 25);
  static const _json = {'Content-Type': 'application/json'};

  Uri _uri(String ruta) => Uri.parse('${ApiConfig.baseUrl}$ruta');

  Never _fallo(http.Response res) {
    var mensaje = 'No se pudo completar la acción (código ${res.statusCode}).';
    try {
      final d = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
      if (d is Map && d['message'] != null) mensaje = d['message'].toString();
    } catch (_) {
      if (res.statusCode == 404) mensaje = 'El servidor todavía no tiene habilitado el semáforo académico.';
    }
    throw ApiMessageException(res.statusCode, mensaje);
  }

  Map<String, dynamic> _mapa(http.Response res) {
    final d = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
    return (d as Map).cast<String, dynamic>();
  }

  Future<Semaforo> semaforo(int studentId) async {
    final res = await http.get(_uri('/estudiantes/$studentId/semaforo')).timeout(_timeout);
    if (res.statusCode != 200) _fallo(res);
    return Semaforo.fromJson(_mapa(res));
  }

  /// Docente: nota definitiva de [studentId] en la materia [courseId]. Devuelve el estado resultante.
  Future<EstadoMateria> registrarNota(int studentId, int courseId, double nota) async {
    final res = await http
        .put(_uri('/estudiantes/$studentId/semaforo/$courseId/nota'),
            headers: _json, body: jsonEncode({'grade': nota}))
        .timeout(_timeout);
    if (res.statusCode != 200) _fallo(res);
    return EstadoMateria.desde(_mapa(res)['status']?.toString());
  }

  /// Admin: corrección excepcional. [estado] puede ser aprobada, reprobada, cancelada o pendiente
  /// (pendiente = quitar el resultado guardado). [nota] es obligatoria al aprobar o reprobar.
  Future<void> corregir(int studentId, int courseId,
      {required EstadoMateria estado, double? nota, required String motivo}) async {
    final res = await http
        .put(_uri('/admin/estudiantes/$studentId/semaforo/$courseId'),
            headers: _json,
            body: jsonEncode({'status': estado.api, if (nota != null) 'grade': nota, 'reason': motivo}))
        .timeout(_timeout);
    if (res.statusCode != 200) _fallo(res);
  }

  Future<List<EntradaAuditoria>> auditoria(int studentId) async {
    final res = await http.get(_uri('/estudiantes/$studentId/semaforo/auditoria')).timeout(_timeout);
    if (res.statusCode != 200) _fallo(res);
    return [
      for (final e in (_mapa(res)['entries'] as List? ?? const []))
        EntradaAuditoria.fromJson((e as Map).cast<String, dynamic>()),
    ];
  }

  /// Plan de estudios: datos de la malla de todas las materias.
  Future<List<MateriaMalla>> malla() async {
    final res = await http.get(_uri('/malla/materias')).timeout(_timeout);
    if (res.statusCode != 200) _fallo(res);
    return [
      for (final c in (_mapa(res)['courses'] as List? ?? const []))
        MateriaMalla.fromJson((c as Map).cast<String, dynamic>()),
    ];
  }

  /// Admin: ubica la materia en la malla (semestre, créditos, área y pre-requisitos).
  Future<void> guardarMalla(int courseId,
      {int? semestre, int? creditos, String? area, List<int> prerequisitos = const []}) async {
    final res = await http
        .put(_uri('/courses/$courseId/malla'),
            headers: _json,
            body: jsonEncode({
              'semester': semestre,
              'credits': creditos,
              'area': area,
              'prerequisites': prerequisitos,
            }))
        .timeout(_timeout);
    if (res.statusCode != 200) _fallo(res);
  }
}
