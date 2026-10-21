import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gesacad/config/app_tokens.dart';
import 'package:gesacad/models/evaluation_models.dart';
import 'package:gesacad/screens/evaluation/eval_participants_tab.dart';
import 'package:gesacad/screens/evaluation/evaluation_form_screen.dart';
import 'package:gesacad/services/api_service.dart';
import 'package:gesacad/services/connectivity_service.dart';
import 'package:gesacad/services/offline_queue.dart';
import 'package:gesacad/services/outbox_file_store.dart';
import 'package:gesacad/widgets/eval/eval_result_card.dart';
import 'package:gesacad/widgets/eval/eval_widgets.dart';
import 'package:gesacad/widgets/eval/evaluation_entry_card.dart';

class _NoopExecutor implements OperationExecutor {
  @override
  Future<OperationOutcome> execute(PendingOperation op, Uint8List? file) async =>
      const OperationOutcome(OutcomeKind.success);
}

const Map<String, dynamic> _formJson = {
  'targetId': 5, 'periodId': 1, 'periodName': '2026-2',
  'courseName': 'Cálculo', 'teacherName': 'Profe A',
  'closesAt': '2030-01-01T00:00:00Z',
  'scale': {'min': 1, 'max': 5}, 'maxCommentLength': 1000,
  'questions': [
    {'id': 1, 'position': 1, 'dimension': 'Metodología', 'text': 'Explica con claridad', 'type': 'scale', 'required': 1},
    {'id': 2, 'position': 2, 'dimension': 'Metodología', 'text': 'Usa buenos recursos', 'type': 'scale', 'required': 1},
    {'id': 3, 'position': 3, 'dimension': 'Evaluación', 'text': 'Califica a tiempo', 'type': 'scale', 'required': 1},
    {'id': 4, 'position': 4, 'dimension': 'Evaluación', 'text': 'Comentarios', 'type': 'text', 'required': 0},
  ],
};

/// Avanza el reloj de pruebas. El primer fotograma de una animación recién
/// iniciada cuenta como tiempo cero, así que se bombea dos veces.
Future<void> espera(WidgetTester t, [int ms = 700]) async {
  await t.pump();
  await t.pump(Duration(milliseconds: ms));
}

Widget _app(Widget child) => MaterialApp(
      theme: ThemeData(extensions: const [AppTokens.light]),
      home: child,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() => initializeDateFormatting('es'));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Modelos', () {
    test('conversión de hora Colombia (UTC-5) es reversible', () {
      final utc = DateTime.utc(2026, 10, 20, 3, 30);
      final col = toColombia(utc);
      expect(col, DateTime.utc(2026, 10, 19, 22, 30));
      expect(fromColombia(DateTime(2026, 10, 19, 22, 30)), utc);
    });

    test('un periodo de la lista trae conteos y el detalle trae objetivos', () {
      final lista = EvalPeriod.fromJson({
        'id': 1, 'name': '2026-2', 'status': 'published', 'phase': 'open',
        'minResponses': 5, 'opensAt': '2026-10-01T13:00:00Z', 'closesAt': '2026-10-30T04:59:00Z',
        'targets': 4, 'expected': 40, 'responses': 10,
      });
      expect(lista.phase, EvalPhase.open);
      expect(lista.targetCount, 4);
      expect(lista.participation, 0.25);

      final detalle = EvalPeriod.fromJson({
        'id': 1, 'name': 'x', 'status': 'draft', 'phase': 'draft', 'minResponses': 5,
        'questions': [(_formJson['questions'] as List)[0]],
        'targets': [
          {'id': 9, 'courseId': 2, 'courseName': 'Física', 'teacherId': 3, 'teacherName': 'B', 'enrolled': 10, 'responses': 4},
        ],
      });
      expect(detalle.isDraft, isTrue);
      expect(detalle.questions.single.isScale, isTrue);
      expect(detalle.targets.single.participation, 0.4);
    });

    test('el formulario agrupa las preguntas de escala por dimensión', () {
      final f = EvalForm.fromJson(_formJson);
      expect(f.scaleByDimension.keys, ['Metodología', 'Evaluación']);
      expect(f.scaleByDimension['Metodología']!.length, 2);
      expect(f.textQuestions.single.text, 'Comentarios');
    });

    test('un resultado protegido no trae promedios y uno visible sí', () {
      final oculto = EvalResult.fromJson({
        'targetId': 1, 'courseName': 'A', 'teacherName': 'T', 'enrolled': 10,
        'responses': 2, 'participation': 0.2, 'minResponses': 5, 'hidden': true,
      });
      expect(oculto.hidden, isTrue);
      expect(oculto.overall, isNull);
      expect(oculto.byDimension, isEmpty);

      final visible = EvalResult.fromJson({
        'targetId': 1, 'courseName': 'A', 'teacherName': 'T', 'enrolled': 6,
        'responses': 6, 'participation': 1, 'minResponses': 5, 'hidden': false, 'overall': 4.0,
        'questions': [
          {'questionId': 1, 'dimension': 'M', 'text': 'q1', 'n': 6, 'avg': 4.0, 'distribution': [0, 0, 1, 4, 1]},
          {'questionId': 2, 'dimension': 'M', 'text': 'q2', 'n': 6, 'avg': 5.0, 'distribution': [0, 0, 0, 0, 6]},
          {'questionId': 3, 'dimension': 'E', 'text': 'q3', 'n': 6, 'avg': 3.0, 'distribution': [0, 0, 6, 0, 0]},
        ],
      });
      expect(visible.byDimension['M'], 4.5);
      expect(visible.byDimension['E'], 3.0);
    });

    test('cierraEn describe el tiempo restante', () {
      final ahora = DateTime.utc(2026, 1, 1, 12);
      expect(cierraEn(ahora.add(const Duration(minutes: 20)), ahora: ahora), 'Cierra en 20 min');
      expect(cierraEn(ahora.add(const Duration(hours: 5)), ahora: ahora), 'Cierra en 5 h');
      expect(cierraEn(ahora.add(const Duration(days: 1, hours: 2)), ahora: ahora), 'Cierra mañana');
      expect(cierraEn(ahora.add(const Duration(days: 6)), ahora: ahora), 'Cierra en 6 días');
      expect(cierraEn(ahora.subtract(const Duration(hours: 1)), ahora: ahora), 'Cerrada');
    });
  });

  group('Cola sin conexión: evaluaciones', () {
    OfflineQueue cola(ConnectivityService c) => OfflineQueue(
        executor: _NoopExecutor(), files: MemoryOutboxStore(), connectivity: c,
        retryBase: const Duration(hours: 1));

    ConnectivityService sinRed() {
      final c = ConnectivityService.test(
          probe: () async => true, interval: const Duration(hours: 1));
      c.reportFailure(TimeoutException('x'));
      return c;
    }

    test('guarda las respuestas, sobreviven a un reinicio y se reemplazan por curso', () async {
      final c = sinRed();
      final q = cola(c);
      await q.init();
      await q.enqueueEvaluation(studentId: 7, targetId: 5,
          answers: [{'questionId': 1, 'value': 3}], label: 'v1');
      await q.enqueueEvaluation(studentId: 7, targetId: 5,
          answers: [{'questionId': 1, 'value': 5}, {'questionId': 4, 'comment': 'bien'}], label: 'v2');
      await q.enqueueEvaluation(studentId: 7, targetId: 6,
          answers: [{'questionId': 9, 'value': 4}], label: 'otro curso');

      expect(q.operations.value.length, 2, reason: 'misma evaluación se reemplaza');
      expect(q.hasPendingEvaluation(7, 5), isTrue);
      expect(q.hasPendingEvaluation(8, 5), isFalse);

      final q2 = cola(c);
      await q2.init();
      final op = q2.operations.value.firstWhere((o) => o.payload['targetId'] == 5);
      expect(op.type, OperationType.evaluation);
      expect((op.payload['answers'] as List).length, 2);
      q.disposeForTest();
      q2.disposeForTest();
      c.dispose();
    });

    test('409 YA_EVALUADO cuenta como éxito; 4xx es rechazo; 5xx reintenta', () {
      OutcomeKind k(int s, [String? m]) =>
          ApiOperationExecutor.fromEvalResult(EvalSubmitResult(s, message: m)).kind;
      expect(k(201), OutcomeKind.success);
      expect(k(409), OutcomeKind.success);
      expect(k(500), OutcomeKind.retry);
      expect(k(429), OutcomeKind.retry);
      expect(k(403, 'La evaluación ya cerró.'), OutcomeKind.permanent);
      expect(k(400), OutcomeKind.permanent);
      expect(ApiOperationExecutor.fromEvalResult(
              const EvalSubmitResult(403, message: 'La evaluación ya cerró.')).message,
          'La evaluación ya cerró.');
    });
  });

  group('ApiService: evaluación docente', () {
    late ConnectivityService conn;
    setUp(() {
      conn = ConnectivityService.test(
          probe: () async => true, interval: const Duration(hours: 1));
      ConnectivityService.instance = conn;
    });
    tearDown(() => conn.dispose());

    test('submitEvaluation devuelve código y mensaje sin lanzar por 4xx', () async {
      await http.runWithClient(() async {
        final r = await ApiService().submitEvaluation(5, 7, [{'questionId': 1, 'value': 4}]);
        expect(r.status, 403);
        expect(r.code, 'EVALUACION_CERRADA');
        expect(r.message, 'La evaluación ya cerró.');
      }, () => MockClient((_) async => http.Response(
          jsonEncode({'error': 'EVALUACION_CERRADA', 'message': 'La evaluación ya cerró.'}), 403)));
    });

    test('las acciones del Admin lanzan EvalApiException con el mensaje del servidor', () async {
      await http.runWithClient(() async {
        await expectLater(
          ApiService().publishEvalPeriod(1, 6),
          throwsA(isA<EvalApiException>()
              .having((e) => e.code, 'code', 'VENTANA_REQUERIDA')
              .having((e) => e.message, 'message', contains('fechas'))),
        );
      }, () => MockClient((_) async => http.Response(
          jsonEncode({'error': 'VENTANA_REQUERIDA', 'message': 'Define las fechas de apertura y cierre.'}), 400)));
    });

    test('las evaluaciones pendientes se leen sin conexión desde el caché', () async {
      var hayRed = true;
      await http.runWithClient(() async {
        final api = ApiService();
        final a = await api.getPendingEvaluations(7);
        expect(a.single.courseName, 'Cálculo');
        hayRed = false;
        final b = await api.getPendingEvaluations(7);
        expect(b.single.courseName, 'Cálculo');
      }, () => MockClient((_) async {
            if (!hayRed) throw http.ClientException('sin red');
            return http.Response(jsonEncode([
              {'targetId': 5, 'periodId': 1, 'periodName': '2026-2', 'closesAt': '2030-01-01T00:00:00Z',
               'courseId': 2, 'courseName': 'Cálculo', 'teacherName': 'Profe A', 'answered': false},
            ]), 200);
          }));
    });
  });

  group('Componentes', () {
    testWidgets('RatingOrbs notifica el valor y se anuncia con etiquetas', (t) async {
      final handle = t.ensureSemantics();
      int? elegido;
      await t.pumpWidget(_app(Scaffold(
        body: Center(
          child: StatefulBuilder(builder: (_, set) => RatingOrbs(
                value: elegido, questionLabel: 'Explica con claridad',
                onChanged: (v) => set(() => elegido = v))),
        ),
      )));
      expect(find.bySemanticsLabel(RegExp('Excelente, 5 de 5')), findsOneWidget);
      await t.tap(find.byIcon(PhosphorIconsFill.smileyWink));
      await espera(t, 500);
      expect(elegido, 5);
      expect(find.text('Excelente'), findsOneWidget);
      await t.pump(const Duration(seconds: 2));
      handle.dispose();
    });

    testWidgets('EvalResultCard protege los cursos bajo el umbral', (t) async {
      await t.pumpWidget(_app(Scaffold(
        body: SingleChildScrollView(
          child: Column(children: [
            EvalResultCard(result: EvalResult.fromJson({
              'targetId': 1, 'courseName': 'Física', 'teacherName': 'B', 'enrolled': 10,
              'responses': 2, 'participation': 0.2, 'minResponses': 5, 'hidden': true})),
          ]),
        ),
      )));
      await t.pump(const Duration(seconds: 1));
      expect(find.textContaining('Resultados protegidos'), findsOneWidget);
      expect(find.textContaining('al menos 5'), findsOneWidget);
      expect(find.text('Ver detalle por pregunta'), findsNothing);
    });

    testWidgets('EvalResultCard muestra puntaje y comentarios solo si se pide', (t) async {
      final r = EvalResult.fromJson({
        'targetId': 1, 'courseName': 'Cálculo', 'teacherName': 'A', 'enrolled': 6,
        'responses': 6, 'participation': 1, 'minResponses': 5, 'hidden': false, 'overall': 4.2,
        'comments': ['Muy buen curso'],
        'questions': [
          {'questionId': 1, 'dimension': 'M', 'text': 'q1', 'n': 6, 'avg': 4.0, 'distribution': [0, 0, 1, 4, 1]},
        ],
      });
      await t.binding.setSurfaceSize(const Size(500, 1400));
      await t.pumpWidget(_app(Scaffold(body: SingleChildScrollView(child: EvalResultCard(result: r)))));
      await t.pump(const Duration(seconds: 2));
      expect(find.text('Ver detalle por pregunta'), findsOneWidget);
      expect(find.textContaining('Comentarios ('), findsNothing, reason: 'el docente no ve comentarios');

      await t.pumpWidget(_app(Scaffold(body: SingleChildScrollView(
          child: EvalResultCard(result: r, showComments: true)))));
      await t.pump(const Duration(seconds: 2));
      expect(find.text('Comentarios (1)'), findsOneWidget);
      await t.binding.setSurfaceSize(null);
    });
  });

  group('Formulario del estudiante (flujo completo)', () {
    late ConnectivityService conn;
    late OfflineQueue queue;

    setUp(() {
      conn = ConnectivityService.test(
          probe: () async => true, interval: const Duration(hours: 1));
      ConnectivityService.instance = conn;
      queue = OfflineQueue(
          executor: _NoopExecutor(), files: MemoryOutboxStore(), connectivity: conn,
          retryBase: const Duration(hours: 1));
      OfflineQueue.instance = queue;
    });
    tearDown(() {
      queue.disposeForTest();
      conn.dispose();
    });

    const pending = EvalPending(
      targetId: 5, periodId: 1, periodName: '2026-2', courseId: 2,
      courseName: 'Cálculo', teacherName: 'Profe A', answered: false,
    );

    Future<void> responderTodo(WidgetTester t) async {
      await t.tap(find.text('Comenzar'));
      await espera(t, 700);
      // Dimensión 1: dos preguntas
      await t.tap(find.byIcon(PhosphorIconsFill.smileyWink).at(0));
      await t.tap(find.byIcon(PhosphorIconsFill.smileySticker).at(1));
      await espera(t, 400);
      await t.tap(find.text('Siguiente'));
      await espera(t, 700);
      // Dimensión 2: una pregunta
      await t.tap(find.byIcon(PhosphorIconsFill.smileyMeh).first);
      await espera(t, 400);
      await t.tap(find.text('Siguiente'));
      await espera(t, 700);
    }

    testWidgets('exige responder, envía las respuestas y agradece', (t) async {
      await t.binding.setSurfaceSize(const Size(500, 1000));
      final enviados = <http.Request>[];
      await http.runWithClient(() async {
        await t.pumpWidget(_app(const EvaluationFormScreen(pending: pending, studentId: 7)));
        await espera(t, 600);
        expect(find.text('Es completamente anónima'), findsOneWidget);

        // Avanza a la primera dimensión y prueba la validación
        await t.tap(find.text('Comenzar'));
        await espera(t, 700);
        await t.tap(find.text('Siguiente'));
        await espera(t, 300);
        expect(find.text('Falta responder'), findsNWidgets(2));
        expect(find.textContaining('Paso 2 de 4'), findsOneWidget, reason: 'no avanzó');

        // Ahora responde todo y llega al final
        await t.tap(find.byIcon(PhosphorIconsFill.smileyWink).at(0));
        await t.tap(find.byIcon(PhosphorIconsFill.smileySticker).at(1));
        await espera(t, 400);
        await t.tap(find.text('Siguiente'));
        await espera(t, 700);
        await t.tap(find.byIcon(PhosphorIconsFill.smileyMeh).first);
        await espera(t, 400);
        await t.tap(find.text('Siguiente'));
        await espera(t, 700);
        expect(find.text('Enviar evaluación'), findsOneWidget);

        await t.enterText(find.byType(TextField), 'Excelente docente');
        await t.tap(find.text('Enviar evaluación'));
        await espera(t, 600);
        await espera(t, 600);

        expect(find.text('¡Gracias por evaluar!'), findsOneWidget);
        expect(enviados.length, 1);
        final body = jsonDecode(enviados.single.body) as Map<String, dynamic>;
        expect(body['studentId'], 7);
        final answers = (body['answers'] as List).cast<Map<String, dynamic>>();
        expect(answers.firstWhere((a) => a['questionId'] == 1)['value'], 5);
        expect(answers.firstWhere((a) => a['questionId'] == 2)['value'], 4);
        expect(answers.firstWhere((a) => a['questionId'] == 3)['value'], 3);
        expect(answers.firstWhere((a) => a['questionId'] == 4)['comment'], 'Excelente docente');
        expect(queue.operations.value, isEmpty, reason: 'enviada directo, sin cola');
        await t.pump(const Duration(seconds: 3));
      }, () => MockClient((req) async {
            if (req.method == 'GET') return http.Response(jsonEncode(_formJson), 200);
            enviados.add(req);
            return http.Response(jsonEncode({'message': 'EVALUACION_REGISTRADA'}), 201);
          }));
      await t.binding.setSurfaceSize(null);
    });

    testWidgets('sin conexión al enviar, la evaluación queda en la cola', (t) async {
      await t.binding.setSurfaceSize(const Size(500, 1000));
      var cae = false;
      await http.runWithClient(() async {
        await t.pumpWidget(_app(const EvaluationFormScreen(pending: pending, studentId: 7)));
        await espera(t, 600);
        await responderTodo(t);
        cae = true; // se pierde la red justo antes de enviar
        await t.tap(find.text('Enviar evaluación'));
        await espera(t, 600);
        await espera(t, 600);

        expect(find.text('Evaluación guardada'), findsOneWidget);
        expect(queue.operations.value.length, 1);
        expect(queue.hasPendingEvaluation(7, 5), isTrue);
        expect(conn.online.value, isFalse);
        conn.dispose(); // cancela el sondeo periódico antes de que termine la prueba
        await t.pump(const Duration(seconds: 3));
      }, () => MockClient((req) async {
            if (req.method == 'GET') return http.Response(jsonEncode(_formJson), 200);
            if (cae) throw http.ClientException('sin red');
            return http.Response('{}', 201);
          }));
      await t.binding.setSurfaceSize(null);
    });

    testWidgets('si el servidor rechaza el envío, muestra su mensaje y no encola', (t) async {
      await t.binding.setSurfaceSize(const Size(500, 1000));
      await http.runWithClient(() async {
        await t.pumpWidget(_app(const EvaluationFormScreen(pending: pending, studentId: 7)));
        await espera(t, 600);
        await responderTodo(t);
        await t.tap(find.text('Enviar evaluación'));
        await espera(t, 600);
        await espera(t, 600);

        expect(find.text('La evaluación ya cerró.'), findsOneWidget);
        expect(queue.operations.value, isEmpty);
        await t.pump(const Duration(seconds: 3));
      }, () => MockClient((req) async {
            if (req.method == 'GET') return http.Response(jsonEncode(_formJson), 200);
            return http.Response(
                jsonEncode({'error': 'EVALUACION_CERRADA', 'message': 'La evaluación ya cerró.'}), 403);
          }));
      await t.binding.setSurfaceSize(null);
    });
  });

  group('Tarjeta de entrada', () {
    testWidgets('el estudiante ve cuántos cursos faltan; se oculta si no hay nada', (t) async {
      final conn = ConnectivityService.test(
          probe: () async => true, interval: const Duration(hours: 1));
      ConnectivityService.instance = conn;
      OfflineQueue.instance = OfflineQueue(
          executor: _NoopExecutor(), files: MemoryOutboxStore(), connectivity: conn);
      await http.runWithClient(() async {
        await t.pumpWidget(_app(const Scaffold(
            body: EvaluationEntryCard(role: EvalRole.student, userId: 7))));
        await espera(t, 800);
        expect(find.text('Evalúa a tus docentes'), findsOneWidget);
        expect(find.textContaining('2 cursos por evaluar'), findsOneWidget);
        await t.pump(const Duration(seconds: 1));
      }, () => MockClient((_) async => http.Response(jsonEncode([
            for (final i in [1, 2])
              {'targetId': i, 'periodId': 1, 'periodName': '2026-2', 'closesAt': '2030-01-01T00:00:00Z',
               'courseId': i, 'courseName': 'Curso $i', 'teacherName': 'P', 'answered': false},
          ]), 200)));

      await http.runWithClient(() async {
        await t.pumpWidget(_app(const Scaffold(
            body: EvaluationEntryCard(role: EvalRole.teacher, userId: 3))));
        await espera(t, 800);
        expect(find.textContaining('Resultados de evaluación'), findsNothing);
      }, () => MockClient((_) async => http.Response('[]', 200)));
      conn.dispose();
    });
  });

  group('Pestaña de participantes (Admin)', () {
    Map<String, dynamic> arbol({bool bSelected = true}) => {
          'mode': 'all', 'coursesWithoutTeacher': 1,
          'teachers': [
            {'id': 2, 'name': 'profe_a', 'courses': [
              {'courseId': 10, 'courseName': 'Cálculo', 'students': [
                {'id': 4, 'username': 'ana', 'selected': true},
                {'id': 5, 'username': 'luis', 'selected': true},
              ]},
            ]},
            {'id': 3, 'name': 'profe_b', 'courses': [
              {'courseId': 11, 'courseName': 'Física', 'students': [
                {'id': 4, 'username': 'ana', 'selected': bSelected},
              ]},
            ]},
          ],
        };

    const borrador = EvalPeriod(
        id: 1, name: '2026-2', status: 'draft', phase: EvalPhase.draft, minResponses: 5);

    Widget tab(EvalPeriod p, List<bool> dirty) => _app(Scaffold(
          body: EvalParticipantsTab(
            period: p, adminId: 1,
            onDirty: dirty.add,
            onSaved: () async {},
          ),
        ));

    test('el árbol se interpreta y cuenta lo seleccionado', () {
      final c = EvalCandidates.fromJson(arbol(bSelected: false));
      expect(c.teachers.length, 2);
      expect(c.coursesWithoutTeacher, 1);
      expect(c.teachers[0].studentCount, 2);
      expect(c.teachers[0].selectedCount, 2);
      expect(c.teachers[1].selectedCount, 0);
      expect(c.teachers[0].courses.single.selectedCount, 2);
    });

    testWidgets('elegir docentes cambia lo que se envía; todos seleccionados = modo "todos"', (t) async {
      final handle = t.ensureSemantics();
      await t.binding.setSurfaceSize(const Size(600, 1200));
      final cuerpos = <Map<String, dynamic>>[];
      final dirty = <bool>[];
      await http.runWithClient(() async {
        await t.pumpWidget(tab(borrador, dirty));
        await espera(t, 600);
        expect(find.text('Participantes de la evaluación'), findsOneWidget);
        expect(find.text('2 docentes'), findsOneWidget);
        expect(find.text('3 de 3 estudiantes'), findsOneWidget);
        expect(find.textContaining('1 curso no aparece'), findsOneWidget);
        expect(find.text('Selección guardada'), findsOneWidget, reason: 'aún sin cambios');

        // Desmarca al docente B → quedan 2 de 3
        await t.tap(find.bySemanticsLabel('Seleccionar todos los cursos de profe_b'));
        await t.pump();
        expect(find.text('2 de 3 estudiantes'), findsOneWidget);
        expect(find.text('1 docente'), findsOneWidget);
        expect(dirty.last, isTrue);

        await t.tap(find.text('Guardar selección'));
        await espera(t, 400);
        expect(cuerpos.length, 1);
        expect(cuerpos.single['selection'], [
          {'courseId': 10, 'studentIds': [4, 5]},
        ]);
        expect(cuerpos.single.containsKey('mode'), isFalse);
        expect(dirty.last, isFalse);

        // Vuelve a marcar todo y guarda → modo "todos"
        await t.tap(find.text('Seleccionar todos'));
        await t.pump();
        await t.tap(find.text('Guardar selección'));
        await espera(t, 400);
        expect(cuerpos.length, 2);
        expect(cuerpos.last['mode'], 'all');
        expect(cuerpos.last.containsKey('selection'), isFalse);
        await t.pump(const Duration(seconds: 1));
      }, () => MockClient((req) async {
            if (req.method == 'GET') return http.Response(jsonEncode(arbol()), 200);
            cuerpos.add(jsonDecode(req.body) as Map<String, dynamic>);
            return http.Response(jsonEncode({'message': 'PARTICIPANTES_ACTUALIZADOS'}), 200);
          }));
      await t.binding.setSurfaceSize(null);
      handle.dispose();
    });

    testWidgets('sin estudiantes seleccionados avisa y no deja guardar', (t) async {
      await t.binding.setSurfaceSize(const Size(600, 1200));
      var puts = 0;
      await http.runWithClient(() async {
        await t.pumpWidget(tab(borrador, []));
        await espera(t, 600);
        await t.tap(find.text('Ninguno'));
        await t.pump();
        expect(find.textContaining('Selecciona al menos un estudiante'), findsOneWidget);
        await t.tap(find.text('Guardar selección'), warnIfMissed: false);
        await espera(t, 300);
        expect(puts, 0);
        await t.pump(const Duration(seconds: 1));
      }, () => MockClient((req) async {
            if (req.method == 'GET') return http.Response(jsonEncode(arbol()), 200);
            puts++;
            return http.Response('{}', 200);
          }));
      await t.binding.setSurfaceSize(null);
    });

    testWidgets('el buscador filtra por docente, curso o estudiante', (t) async {
      await t.binding.setSurfaceSize(const Size(600, 1200));
      await http.runWithClient(() async {
        await t.pumpWidget(tab(borrador, []));
        await espera(t, 600);
        expect(find.text('profe_b'), findsOneWidget);
        await t.enterText(find.byType(TextField), 'cálculo');
        await t.pump();
        expect(find.text('profe_b'), findsNothing);
        expect(find.text('profe_a'), findsOneWidget);
        await t.enterText(find.byType(TextField), 'zzz');
        await t.pump();
        expect(find.textContaining('Sin coincidencias'), findsOneWidget);
        await t.pump(const Duration(seconds: 1));
      }, () => MockClient((_) async => http.Response(jsonEncode(arbol()), 200)));
      await t.binding.setSurfaceSize(null);
    });

    testWidgets('publicado vigente: lo habilitado se bloquea y se puede incorporar a otros', (t) async {
      await t.binding.setSurfaceSize(const Size(600, 1200));
      const publicado = EvalPeriod(
          id: 1, name: '2026-2', status: 'published', phase: EvalPhase.open, minResponses: 5);
      await http.runWithClient(() async {
        await t.pumpWidget(tab(publicado, []));
        await espera(t, 600);
        expect(find.text('Participantes habilitados'), findsOneWidget);
        expect(find.text('Guardar selección'), findsNothing);
        expect(find.text('Marca a quienes quieras incorporar'), findsOneWidget);
        await t.pump(const Duration(seconds: 1));
      }, () => MockClient((_) async => http.Response(jsonEncode(arbol(bSelected: false)), 200)));
      await t.binding.setSurfaceSize(null);
    });

    testWidgets('cerrado: solo lectura y solo los estudiantes habilitados', (t) async {
      await t.binding.setSurfaceSize(const Size(600, 1200));
      const publicado = EvalPeriod(
          id: 1, name: '2026-2', status: 'published', phase: EvalPhase.closed, minResponses: 5);
      await http.runWithClient(() async {
        await t.pumpWidget(tab(publicado, []));
        await espera(t, 600);
        expect(find.text('Participantes habilitados'), findsOneWidget);
        expect(find.byType(Checkbox), findsNothing);
        expect(find.text('Guardar selección'), findsNothing);
        expect(find.text('profe_a'), findsOneWidget);
        expect(find.text('profe_b'), findsNothing, reason: 'sin estudiantes habilitados');
        await t.pump(const Duration(seconds: 1));
      }, () => MockClient((_) async => http.Response(jsonEncode(arbol(bSelected: false)), 200)));
      await t.binding.setSurfaceSize(null);
    });
  });

  group('Mensajes de error del módulo', () {
    test('un 404 sin JSON (ruta inexistente) se explica como módulo no desplegado', () async {
      final conn = ConnectivityService.test(
          probe: () async => true, interval: const Duration(hours: 1));
      ConnectivityService.instance = conn;
      await http.runWithClient(() async {
        await expectLater(
          ApiService().getEvalPeriods(1),
          throwsA(isA<EvalApiException>()
              .having((e) => e.code, 'code', 'MODULO_NO_DISPONIBLE')
              .having((e) => e.message, 'message', contains('desplegar'))),
        );
      }, () => MockClient((_) async => http.Response('<html>Cannot GET /evaluations</html>', 404)));
      conn.dispose();
    });

    test('un 404 con JSON del módulo conserva su mensaje', () async {
      final conn = ConnectivityService.test(
          probe: () async => true, interval: const Duration(hours: 1));
      ConnectivityService.instance = conn;
      await http.runWithClient(() async {
        await expectLater(
          ApiService().getEvalPeriod(99, 1),
          throwsA(isA<EvalApiException>()
              .having((e) => e.code, 'code', 'PERIODO_NO_ENCONTRADO')),
        );
      }, () => MockClient((_) async => http.Response(
          jsonEncode({'error': 'PERIODO_NO_ENCONTRADO', 'message': 'El periodo no existe.'}), 404)));
      conn.dispose();
    });
  });
}
