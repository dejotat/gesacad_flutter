import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gesacad/config/app_tokens.dart';
import 'package:gesacad/services/api_service.dart';
import 'package:gesacad/services/connectivity_service.dart';
import 'package:gesacad/services/offline_queue.dart';
import 'package:gesacad/services/outbox_file_store.dart';
import 'package:gesacad/widgets/offline_banner.dart';

/// Ejecutor falso: devuelve resultados programados y registra el orden de envío.
class FakeExecutor implements OperationExecutor {
  FakeExecutor(this.script);
  final List<OperationOutcome> script;
  final List<String> sent = [];

  @override
  Future<OperationOutcome> execute(PendingOperation op, Uint8List? file) async {
    sent.add(op.label);
    return script.isEmpty
        ? const OperationOutcome(OutcomeKind.success)
        : script.removeAt(0);
  }
}

const _ok = OperationOutcome(OutcomeKind.success);
OperationOutcome _kind(OutcomeKind k, {bool uncertain = false}) =>
    OperationOutcome(k, message: 'm', uncertain: uncertain);

ConnectivityService _conn({bool online = true}) {
  final c = ConnectivityService.test(
      probe: () async => true, interval: const Duration(hours: 1));
  if (!online) c.reportFailure(TimeoutException('t'));
  return c;
}

OfflineQueue _queue(FakeExecutor ex, ConnectivityService c,
        {MemoryOutboxStore? files, int maxAttempts = 3}) =>
    OfflineQueue(
      executor: ex,
      files: files ?? MemoryOutboxStore(),
      connectivity: c,
      maxAttempts: maxAttempts,
      retryBase: const Duration(hours: 1),
    );

Future<PendingOperation> _entrega(OfflineQueue q, String nombre,
        {int activity = 1}) =>
    q.enqueueSubmission(
      activityId: activity,
      userId: 7,
      fileName: nombre,
      bytes: Uint8List.fromList([1, 2, 3]),
      label: nombre,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('ConnectivityService', () {
    test('un error de red pasa a sin conexión y un éxito vuelve a en línea', () {
      final c = _conn();
      expect(c.online.value, isTrue);
      c.reportFailure(TimeoutException('x'));
      expect(c.online.value, isFalse);
      c.reportSuccess();
      expect(c.online.value, isTrue);
      c.dispose();
    });

    test('un error que no es de red no marca sin conexión', () {
      final c = _conn();
      c.reportFailure(const FormatException('json inválido'));
      expect(c.online.value, isTrue);
      c.dispose();
    });

    test('checkNow usa el sondeo para detectar el regreso del servidor', () async {
      var responde = false;
      final c = ConnectivityService.test(
          probe: () async => responde, interval: const Duration(hours: 1));
      c.reportFailure(http.ClientException('sin red'));
      expect(await c.checkNow(), isFalse);
      expect(c.online.value, isFalse);
      responde = true;
      expect(await c.checkNow(), isTrue);
      expect(c.online.value, isTrue);
      c.dispose();
    });
  });

  group('OfflineQueue', () {
    test('persiste las acciones y las recupera tras reiniciar', () async {
      final c = _conn(online: false);
      final files = MemoryOutboxStore();
      final q1 = _queue(FakeExecutor([]), c, files: files);
      await q1.init();
      await _entrega(q1, 'informe.pdf');
      await q1.enqueueGrade(
          studentId: 3, activityId: 1, gpa: 4.5, label: 'Nota 4.50');

      final q2 = _queue(FakeExecutor([]), c, files: files);
      await q2.init();
      expect(q2.operations.value.map((o) => o.label), ['informe.pdf', 'Nota 4.50']);
      expect(q2.hasPendingGrade(3, 1), isTrue);
      q1.disposeForTest();
      q2.disposeForTest();
      c.dispose();
    });

    test('envía en orden y vacía la cola; emite eventos de éxito', () async {
      final c = _conn();
      final ex = FakeExecutor([]);
      final files = MemoryOutboxStore();
      final q = _queue(ex, c, files: files);
      final eventos = <bool>[];
      q.events.listen((e) => eventos.add(e.completed));
      final a = await _entrega(q, 'a.pdf');
      await _entrega(q, 'b.pdf');

      await q.sync();

      expect(ex.sent, ['a.pdf', 'b.pdf']);
      expect(q.operations.value, isEmpty);
      expect(await files.read(a.payload['fileRef'] as String), isNull,
          reason: 'el archivo local se borra tras enviarse');
      await Future<void>.delayed(Duration.zero);
      expect(eventos, [true, true]);
      q.disposeForTest();
      c.dispose();
    });

    test('sin conexión a mitad: se detiene, conserva el orden y no cuenta intento',
        () async {
      final c = _conn();
      final ex = FakeExecutor([_ok, _kind(OutcomeKind.offline)]);
      final q = _queue(ex, c);
      await _entrega(q, '1');
      await _entrega(q, '2');
      await _entrega(q, '3');

      await q.sync();

      expect(ex.sent, ['1', '2'], reason: 'no intenta el 3 tras perder la red');
      expect(q.operations.value.map((o) => o.label), ['2', '3']);
      expect(q.operations.value.first.attempts, 0);
      expect(q.pendingCount, 2);
      q.disposeForTest();
      c.dispose();
    });

    test('un timeout marca la entrega como dudosa para no duplicarla', () async {
      final c = _conn();
      final q = _queue(FakeExecutor([_kind(OutcomeKind.offline, uncertain: true)]), c);
      final op = await _entrega(q, 'x');
      await q.sync();
      expect(op.uncertain, isTrue);
      q.disposeForTest();
      c.dispose();
    });

    test('rechazo permanente (4xx) pasa a fallida y se puede reintentar', () async {
      final c = _conn();
      final ex = FakeExecutor([_kind(OutcomeKind.permanent)]);
      final q = _queue(ex, c);
      final op = await _entrega(q, 'x');
      final eventos = <bool>[];
      q.events.listen((e) => eventos.add(e.completed));

      await q.sync();
      expect(op.status, OperationStatus.failed);
      expect(q.failedCount, 1);
      expect(q.pendingCount, 0);
      await Future<void>.delayed(Duration.zero);
      expect(eventos, [false]);

      await q.retry(op.id);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(q.operations.value, isEmpty, reason: 'el reintento tuvo éxito');
      q.disposeForTest();
      c.dispose();
    });

    test('falla temporal (5xx) reintenta y tras agotar intentos queda fallida',
        () async {
      final c = _conn();
      final ex = FakeExecutor(List.generate(5, (_) => _kind(OutcomeKind.retry)));
      final q = _queue(ex, c, maxAttempts: 3);
      final op = await _entrega(q, 'x');

      await q.sync();
      expect(op.attempts, 1);
      expect(op.status, OperationStatus.pending);
      await q.sync();
      await q.sync();
      expect(op.attempts, 3);
      expect(op.status, OperationStatus.failed);
      q.disposeForTest();
      c.dispose();
    });

    test('la última calificación reemplaza a la pendiente de la misma entrega',
        () async {
      final c = _conn(online: false);
      final q = _queue(FakeExecutor([]), c);
      await q.enqueueGrade(studentId: 3, activityId: 1, gpa: 2.0, label: 'v1');
      await q.enqueueGrade(
          studentId: 3, activityId: 1, gpa: 4.8, label: 'v2');
      await q.enqueueGrade(studentId: 4, activityId: 1, gpa: 3.0, label: 'otro');

      expect(q.operations.value.length, 2);
      final g = q.operations.value.first;
      expect(g.payload['gpa'], 4.8);
      expect(g.label, 'v2');
      q.disposeForTest();
      c.dispose();
    });

    test('se sincroniza sola al volver la conexión', () async {
      final c = _conn(online: false);
      final ex = FakeExecutor([]);
      final q = _queue(ex, c);
      await q.init();
      await q.enqueueGrade(studentId: 3, activityId: 1, gpa: 4.0, label: 'nota');
      expect(q.pendingCount, 1);

      c.reportSuccess(); // vuelve la conexión
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(ex.sent, ['nota']);
      expect(q.operations.value, isEmpty);
      q.disposeForTest();
      c.dispose();
    });

    test('un archivo local perdido (web tras recargar) falla con mensaje claro',
        () async {
      final c = _conn();
      final files = MemoryOutboxStore();
      final q = _queue(FakeExecutor([]), c, files: files);
      final op = await _entrega(q, 'x');
      await files.delete(op.payload['fileRef'] as String);

      await q.sync();
      expect(op.status, OperationStatus.failed);
      expect(op.lastError, contains('archivo'));
      q.disposeForTest();
      c.dispose();
    });

    test('clearAll (cerrar sesión) borra acciones y archivos', () async {
      final c = _conn(online: false);
      final files = MemoryOutboxStore();
      final q = _queue(FakeExecutor([]), c, files: files);
      final op = await _entrega(q, 'x');
      await q.clearAll();
      expect(q.operations.value, isEmpty);
      expect(await files.read(op.payload['fileRef'] as String), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(jsonDecode(prefs.getString('outbox_v1')!), isEmpty);
      q.disposeForTest();
      c.dispose();
    });
  });

  group('ApiOperationExecutor.fromStatus', () {
    test('clasifica los códigos HTTP', () {
      OutcomeKind k(int c) => ApiOperationExecutor.fromStatus(c).kind;
      expect(k(200), OutcomeKind.success);
      expect(k(201), OutcomeKind.success);
      expect(k(500), OutcomeKind.retry);
      expect(k(503), OutcomeKind.retry);
      expect(k(429), OutcomeKind.retry);
      expect(k(413), OutcomeKind.permanent);
      expect(k(403), OutcomeKind.permanent);
      expect(k(400), OutcomeKind.permanent);
    });
  });

  group('ApiService: caché de respaldo sin conexión', () {
    late ConnectivityService conn;
    setUp(() {
      conn = _conn();
      ConnectivityService.instance = conn;
    });
    tearDown(() => conn.dispose());

    const body = '{"data":[{"tittle":"Parcial 1","GPA":4.5}]}';

    test('sin red devuelve la última respuesta guardada', () async {
      var hayRed = true;
      await http.runWithClient(() async {
        final api = ApiService();
        final online = await api.getGrades(1, 7);
        expect(online.single['GPA'], 4.5);

        hayRed = false;
        final offline = await api.getGrades(1, 7);
        expect(offline.single['tittle'], 'Parcial 1');
        expect(conn.online.value, isFalse,
            reason: 'el fallo de red activa el modo sin conexión');

        // Ya se sabe que no hay red: responde sin intentar la petición.
        final rapida = await api.getGrades(1, 7);
        expect(rapida.length, 1);
      }, () => MockClient((_) async {
            if (!hayRed) throw http.ClientException('Failed host lookup');
            return http.Response(body, 200);
          }));
    });

    test('sin red y sin copia guardada, el error se propaga', () async {
      await http.runWithClient(() async {
        expect(() => ApiService().getGrades(9, 9), throwsA(isA<Exception>()));
      }, () => MockClient((_) async => throw http.ClientException('sin red')));
    });

    test('con fresh=true nunca usa datos guardados', () async {
      var hayRed = true;
      await http.runWithClient(() async {
        final api = ApiService();
        await api.getActivityContent(5, 7, 'Student');
        hayRed = false;
        await expectLater(
            api.getActivityContent(5, 7, 'Student', fresh: true),
            throwsA(isA<Exception>()));
      }, () => MockClient((_) async {
            if (!hayRed) throw http.ClientException('sin red');
            return http.Response('[{"id":5,"tittle":"A","description":"d",'
                '"type":"midterm","weighting":0.2,"startDate":"2026-01-01T00:00:00Z",'
                '"closingDate":"2026-12-01T00:00:00Z"}]', 200);
          }));
    });
  });

  group('Interfaz sin conexión', () {
    Widget app(Widget home) => MaterialApp(
        theme: ThemeData(extensions: const [AppTokens.light]), home: home);

    testWidgets('el banner aparece sin conexión y confirma al sincronizar',
        (t) async {
      final c = _conn();
      final q = _queue(FakeExecutor([]), c);
      await t.pumpWidget(app(OfflineShell(
          connectivity: c, queue: q, child: const Scaffold(body: Text('app')))));
      expect(find.text('Sin conexión'), findsNothing);

      c.reportFailure(TimeoutException('x'));
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('Sin conexión'), findsOneWidget);
      expect(find.text('app'), findsOneWidget);

      c.reportSuccess();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('Todo sincronizado'), findsOneWidget);
      await t.pump(const Duration(seconds: 4));
      expect(find.text('Todo sincronizado'), findsNothing);
      q.disposeForTest();
      c.dispose();
    });

    testWidgets('el panel lista lo pendiente y lo rechazado', (t) async {
      final c = _conn(online: false);
      final q = _queue(FakeExecutor([]), c);
      await q.enqueueGrade(
          studentId: 1, activityId: 1, gpa: 4, label: 'Nota 4.00 · ana');
      final fallida = await q.enqueueGrade(
          studentId: 2, activityId: 1, gpa: 1, label: 'Nota 1.00 · luis');
      fallida
        ..status = OperationStatus.failed
        ..lastError = 'El plazo venció';
      await t.pumpWidget(app(Scaffold(body: CentroSync(queue: q, connectivity: c))));
      await t.pump(const Duration(milliseconds: 300));

      expect(find.text('Nota 4.00 · ana'), findsOneWidget);
      expect(find.text('Nota 1.00 · luis'), findsOneWidget);
      expect(find.text('El plazo venció'), findsOneWidget);
      expect(find.byTooltip('Reintentar'), findsOneWidget);
      q.disposeForTest();
      c.dispose();
    });
  });
}
