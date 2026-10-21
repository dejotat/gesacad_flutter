import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/evaluation_models.dart';
import 'api_service.dart';
import 'connectivity_service.dart';
import 'outbox_file_store.dart';

/// Tipos de acción que se pueden registrar sin conexión.
enum OperationType {
  /// Entrega de un archivo de un estudiante a una actividad.
  submission,

  /// Calificación de un docente a la entrega de un estudiante.
  grade,

  /// Evaluación docente de un estudiante (una por curso y periodo).
  evaluation,
}

/// Estado de una acción en la cola.
enum OperationStatus {
  /// Esperando conexión o turno de envío.
  pending,

  /// El servidor la rechazó o agotó los reintentos: requiere decisión del usuario.
  failed,
}

/// Acción registrada por el usuario que aún no llegó al servidor.
class PendingOperation {
  PendingOperation({
    required this.id,
    required this.type,
    required this.payload,
    required this.label,
    DateTime? createdAt,
    this.status = OperationStatus.pending,
    this.attempts = 0,
    this.lastError,
    this.uncertain = false,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  final OperationType type;

  /// Submission: activityId, userId, fileName, comment, fileRef.
  /// Grade: userId (estudiante calificado), activityId, gpa, teacherComment.
  /// Evaluation: userId (estudiante), targetId, answers [{questionId, value?, comment?}].
  Map<String, dynamic> payload;

  /// Texto legible para la interfaz ("Entrega: Parcial 1 · informe.pdf").
  String label;
  final DateTime createdAt;
  OperationStatus status;
  int attempts;
  String? lastError;

  /// El último envío expiró *después* de salir: el servidor pudo haberlo
  /// recibido. Antes de reenviar se consulta el estado para no duplicar.
  bool uncertain;

  int get activityId => (payload['activityId'] as int?) ?? 0;
  int get userId => payload['userId'] as int;

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'payload': payload,
        'label': label,
        'createdAt': createdAt.toIso8601String(),
        'status': status.name,
        'attempts': attempts,
        'lastError': lastError,
        'uncertain': uncertain,
      };

  factory PendingOperation.fromJson(Map<String, dynamic> j) => PendingOperation(
        id: j['id'] as String,
        type: OperationType.values.byName(j['type'] as String),
        payload: Map<String, dynamic>.from(j['payload'] as Map),
        label: j['label'] as String? ?? '',
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? ''),
        status: OperationStatus.values.byName(j['status'] as String? ?? 'pending'),
        attempts: j['attempts'] as int? ?? 0,
        lastError: j['lastError'] as String?,
        uncertain: j['uncertain'] as bool? ?? false,
      );
}

/// Resultado de intentar enviar una acción.
enum OutcomeKind {
  /// El servidor la aceptó.
  success,

  /// No hay conexión: se detiene la sincronización y se reintenta al volver.
  offline,

  /// Falla temporal del servidor (5xx, 429…): se reintenta más tarde.
  retry,

  /// El servidor la rechazó (4xx): reintentar no sirve.
  permanent,
}

class OperationOutcome {
  const OperationOutcome(this.kind, {this.message, this.uncertain = false});
  final OutcomeKind kind;
  final String? message;
  final bool uncertain;
}

/// Envía una acción al backend. Se inyecta en [OfflineQueue] para poder
/// probar la cola sin red.
abstract class OperationExecutor {
  Future<OperationOutcome> execute(PendingOperation op, Uint8List? file);
}

/// Ejecutor real: usa [ApiService].
class ApiOperationExecutor implements OperationExecutor {
  ApiOperationExecutor([ApiService? api]) : _api = api ?? ApiService();
  final ApiService _api;

  /// Traduce el código HTTP a lo que debe hacer la cola.
  static OperationOutcome fromStatus(int code) {
    if (code >= 200 && code < 300) return const OperationOutcome(OutcomeKind.success);
    if (code == 408 || code == 425 || code == 429 || code >= 500) {
      return OperationOutcome(OutcomeKind.retry,
          message: 'El servidor no está disponible (código $code).');
    }
    if (code == 413) {
      return const OperationOutcome(OutcomeKind.permanent,
          message: 'El archivo supera el tamaño permitido por el servidor.');
    }
    if (code == 401) {
      return const OperationOutcome(OutcomeKind.permanent,
          message: 'Tu sesión expiró. Inicia sesión de nuevo y pulsa "Reintentar".');
    }
    if (code == 403) {
      return const OperationOutcome(OutcomeKind.permanent,
          message: 'No tienes permiso para realizar esta acción.');
    }
    return OperationOutcome(OutcomeKind.permanent,
        message: 'El servidor rechazó la acción (código $code). '
            'Es posible que el plazo haya vencido.');
  }

  /// Traduce la respuesta del módulo de evaluación.
  ///
  /// 409 (YA_EVALUADO) cuenta como éxito: el envío es idempotente. Así, si una
  /// petición llegó pero se perdió la respuesta, el reintento no genera error.
  static OperationOutcome fromEvalResult(EvalSubmitResult r) {
    final c = r.status;
    if ((c >= 200 && c < 300) || c == 409) {
      return const OperationOutcome(OutcomeKind.success);
    }
    if (c == 408 || c == 425 || c == 429 || c >= 500) {
      return OperationOutcome(OutcomeKind.retry,
          message: 'El servidor no está disponible (código $c).');
    }
    return OperationOutcome(OutcomeKind.permanent,
        message: r.message ?? 'El servidor rechazó la evaluación (código $c).');
  }

  @override
  Future<OperationOutcome> execute(PendingOperation op, Uint8List? file) async {
    try {
      switch (op.type) {
        case OperationType.evaluation:
          final r = await _api.submitEvaluation(
            op.payload['targetId'] as int,
            op.userId,
            List<Map<String, dynamic>>.from(
                (op.payload['answers'] as List).map((a) => Map<String, dynamic>.from(a as Map))),
          );
          return fromEvalResult(r);
        case OperationType.submission:
          // Si el intento anterior pudo haber llegado al servidor, confirmar
          // antes de reenviar: un POST repetido duplicaría la entrega.
          if (op.uncertain) {
            final act = await _api.getActivityContent(
                op.activityId, op.userId, 'Student', fresh: true);
            if (act?.isDelivered == true) {
              return const OperationOutcome(OutcomeKind.success);
            }
          }
          final code = await _api.addResourceBytes(
            op.activityId,
            op.userId,
            file!,
            op.payload['fileName'] as String,
            comment: op.payload['comment'] as String? ?? '',
          );
          return fromStatus(code);
        case OperationType.grade:
          // PATCH idempotente: reenviar la misma nota es seguro.
          final code = await _api.gradeActivity(
            op.userId,
            op.activityId,
            (op.payload['gpa'] as num).toDouble(),
            teacherComment: op.payload['teacherComment'] as String? ?? '',
          );
          return fromStatus(code);
      }
    } catch (e) {
      if (isNetworkError(e)) {
        // Solo un timeout deja dudas: la petición pudo salir antes de cortarse.
        return OperationOutcome(OutcomeKind.offline,
            uncertain: e is TimeoutException &&
                op.type == OperationType.submission);
      }
      return OperationOutcome(OutcomeKind.permanent, message: 'Error inesperado: $e');
    }
  }
}

/// Evento de la cola para mostrar avisos al usuario.
class SyncEvent {
  const SyncEvent(this.operation, {required this.completed});
  final PendingOperation operation;
  final bool completed;
}

/// Cola de acciones sin conexión ("outbox").
///
/// - **Persistente**: sobrevive al cierre de la app (JSON en `SharedPreferences`
///   y archivos en el directorio privado).
/// - **Ordenada**: se envía en el orden en que el usuario actuó. Si se pierde
///   la conexión a mitad, se detiene y conserva el orden.
/// - **Segura ante duplicados**: ver [PendingOperation.uncertain].
/// - **Autónoma**: se sincroniza sola al volver la conexión y reintenta con
///   espera creciente ante fallas del servidor.
class OfflineQueue {
  OfflineQueue({
    OperationExecutor? executor,
    OutboxFileStore? files,
    ConnectivityService? connectivity,
    this.maxAttempts = 5,
    this.retryBase = const Duration(seconds: 30),
  })  : _executor = executor ?? ApiOperationExecutor(),
        _files = files ?? OutboxFileStore.platform(),
        _connectivity = connectivity ?? ConnectivityService.instance;

  static OfflineQueue instance = OfflineQueue();

  static const _prefsKey = 'outbox_v1';

  final OperationExecutor _executor;
  final OutboxFileStore _files;
  final ConnectivityService _connectivity;
  final int maxAttempts;
  final Duration retryBase;

  final ValueNotifier<List<PendingOperation>> operations = ValueNotifier(const []);
  final ValueNotifier<bool> syncing = ValueNotifier(false);
  final StreamController<SyncEvent> _events = StreamController.broadcast();
  Stream<SyncEvent> get events => _events.stream;

  Timer? _retryTimer;
  bool _started = false;

  List<PendingOperation> get _ops => List.of(operations.value);

  int get pendingCount =>
      operations.value.where((o) => o.status == OperationStatus.pending).length;
  int get failedCount =>
      operations.value.where((o) => o.status == OperationStatus.failed).length;

  /// Carga lo guardado y empieza a escuchar la conexión. Llamar al iniciar la app.
  Future<void> init() async {
    if (_started) return;
    _started = true;
    await _load();
    _connectivity.online.addListener(_onConnectivityChanged);
    if (_connectivity.online.value && pendingCount > 0) unawaited(sync());
  }

  void _onConnectivityChanged() {
    if (_connectivity.online.value && pendingCount > 0) unawaited(sync());
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return;
      final list = (jsonDecode(raw) as List)
          .map((e) => PendingOperation.fromJson(e as Map<String, dynamic>))
          .toList();
      operations.value = list;
    } catch (_) {
      // Datos corruptos: se descartan en lugar de bloquear el arranque.
      operations.value = const [];
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _prefsKey, jsonEncode(operations.value.map((o) => o.toJson()).toList()));
    } catch (_) {}
  }

  void _publish(List<PendingOperation> list) =>
      operations.value = List.unmodifiable(list);

  String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
      '${math.Random().nextInt(1 << 20).toRadixString(36)}';

  // ── Registro de acciones ────────────────────────────────────────────────

  /// Guarda una entrega para enviarla cuando haya conexión.
  Future<PendingOperation> enqueueSubmission({
    required int activityId,
    required int userId,
    required String fileName,
    required Uint8List bytes,
    String comment = '',
    required String label,
    bool uncertain = false,
  }) async {
    final id = _newId();
    final ref = await _files.save(id, fileName, bytes);
    final op = PendingOperation(
      id: id,
      type: OperationType.submission,
      label: label,
      uncertain: uncertain,
      payload: {
        'activityId': activityId,
        'userId': userId,
        'fileName': fileName,
        'comment': comment,
        'fileRef': ref,
      },
    );
    _publish([..._ops, op]);
    await _persist();
    return op;
  }

  /// Guarda una calificación. Si ya hay una pendiente para la misma entrega,
  /// la reemplaza: solo importa la última nota.
  Future<PendingOperation> enqueueGrade({
    required int studentId,
    required int activityId,
    required double gpa,
    String teacherComment = '',
    required String label,
  }) async {
    final payload = {
      'userId': studentId,
      'activityId': activityId,
      'gpa': gpa,
      'teacherComment': teacherComment,
    };
    final list = _ops;
    final i = list.indexWhere((o) =>
        o.type == OperationType.grade &&
        o.userId == studentId &&
        o.activityId == activityId);
    late PendingOperation op;
    if (i >= 0) {
      op = list[i]
        ..payload = payload
        ..label = label
        ..status = OperationStatus.pending
        ..attempts = 0
        ..lastError = null;
    } else {
      op = PendingOperation(
          id: _newId(), type: OperationType.grade, label: label, payload: payload);
      list.add(op);
    }
    _publish(list);
    await _persist();
    return op;
  }

  /// Guarda una evaluación docente para enviarla al volver la conexión.
  /// Si ya hay una pendiente para el mismo curso, la reemplaza.
  Future<PendingOperation> enqueueEvaluation({
    required int studentId,
    required int targetId,
    required List<Map<String, dynamic>> answers,
    required String label,
  }) async {
    final payload = {'userId': studentId, 'targetId': targetId, 'answers': answers};
    final list = _ops;
    final i = list.indexWhere((o) =>
        o.type == OperationType.evaluation &&
        o.userId == studentId &&
        o.payload['targetId'] == targetId);
    late PendingOperation op;
    if (i >= 0) {
      op = list[i]
        ..payload = payload
        ..label = label
        ..status = OperationStatus.pending
        ..attempts = 0
        ..lastError = null;
    } else {
      op = PendingOperation(
          id: _newId(), type: OperationType.evaluation, label: label, payload: payload);
      list.add(op);
    }
    _publish(list);
    await _persist();
    return op;
  }

  bool hasPendingEvaluation(int studentId, int targetId) =>
      operations.value.any((o) =>
          o.type == OperationType.evaluation &&
          o.userId == studentId &&
          o.payload['targetId'] == targetId);

  // ── Consultas para la interfaz ─────────────────────────────────────────

  bool hasPendingGrade(int studentId, int activityId) =>
      operations.value.any((o) =>
          o.type == OperationType.grade &&
          o.userId == studentId &&
          o.activityId == activityId);

  List<PendingOperation> submissionsFor(int activityId, int userId) =>
      operations.value
          .where((o) =>
              o.type == OperationType.submission &&
              o.activityId == activityId &&
              o.userId == userId)
          .toList();

  // ── Sincronización ────────────────────────────────────────────────────

  /// Envía las acciones pendientes en orden. Segura de llamar varias veces:
  /// si ya hay una sincronización en curso, no hace nada.
  Future<void> sync() async {
    if (syncing.value || pendingCount == 0) return;
    syncing.value = true;
    _retryTimer?.cancel();
    var needsRetry = false;
    try {
      for (final op in _ops.where((o) => o.status == OperationStatus.pending)) {
        Uint8List? file;
        if (op.type == OperationType.submission) {
          file = await _files.read(op.payload['fileRef'] as String);
          if (file == null) {
            // Típico en web tras recargar: el archivo ya no existe.
            _fail(op, 'El archivo guardado ya no está disponible. '
                'Vuelve a adjuntarlo.');
            continue;
          }
        }

        final outcome = await _executor.execute(op, file);
        switch (outcome.kind) {
          case OutcomeKind.success:
            await _remove(op);
            _events.add(SyncEvent(op, completed: true));
          case OutcomeKind.offline:
            if (outcome.uncertain) op.uncertain = true;
            _publish(_ops);
            await _persist();
            return; // se conserva el orden; reintenta al volver la conexión
          case OutcomeKind.retry:
            op.attempts++;
            op.lastError = outcome.message;
            if (op.attempts >= maxAttempts) {
              _fail(op, outcome.message ?? 'El servidor no respondió.');
            } else {
              needsRetry = true;
            }
          case OutcomeKind.permanent:
            _fail(op, outcome.message ?? 'El servidor rechazó la acción.');
        }
        _publish(_ops);
        await _persist();
      }
    } finally {
      syncing.value = false;
      if (needsRetry) _scheduleRetry();
    }
  }

  void _fail(PendingOperation op, String message) {
    op.status = OperationStatus.failed;
    op.lastError = message;
    _events.add(SyncEvent(op, completed: false));
  }

  Future<void> _remove(PendingOperation op) async {
    if (op.type == OperationType.submission) {
      await _files.delete(op.payload['fileRef'] as String);
    }
    _publish(_ops..removeWhere((o) => o.id == op.id));
    await _persist();
  }

  /// Espera creciente (30 s, 60 s, 120 s… hasta 10 min) tras una falla temporal.
  void _scheduleRetry() {
    final worst = operations.value
        .where((o) => o.status == OperationStatus.pending)
        .fold<int>(0, (m, o) => math.max(m, o.attempts));
    final seconds = math.min(retryBase.inSeconds * (1 << math.max(0, worst - 1)), 600);
    _retryTimer?.cancel();
    _retryTimer = Timer(Duration(seconds: seconds), () {
      if (_connectivity.online.value) unawaited(sync());
    });
  }

  /// Vuelve a intentar una acción rechazada.
  Future<void> retry(String id) async {
    final list = _ops;
    final i = list.indexWhere((o) => o.id == id);
    if (i < 0) return;
    list[i]
      ..status = OperationStatus.pending
      ..attempts = 0
      ..lastError = null;
    _publish(list);
    await _persist();
    if (_connectivity.online.value) unawaited(sync());
  }

  /// Descarta una acción (y su archivo) por decisión del usuario.
  Future<void> discard(String id) async {
    final op = operations.value.where((o) => o.id == id).firstOrNull;
    if (op != null) await _remove(op);
  }

  /// Borra todo (cierre de sesión): ninguna acción debe ejecutarse a nombre
  /// del usuario siguiente en un dispositivo compartido.
  Future<void> clearAll() async {
    _retryTimer?.cancel();
    for (final op in _ops) {
      if (op.type == OperationType.submission) {
        await _files.delete(op.payload['fileRef'] as String);
      }
    }
    _publish(const []);
    await _persist();
  }

  @visibleForTesting
  void disposeForTest() {
    _retryTimer?.cancel();
    _connectivity.online.removeListener(_onConnectivityChanged);
  }
}
