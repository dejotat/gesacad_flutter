import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gesacad/config/app_tokens.dart';
import 'package:gesacad/models/meeting_model.dart';
import 'package:gesacad/services/api_service.dart' show ApiMessageException;
import 'package:gesacad/services/meeting_service.dart';
import 'package:gesacad/widgets/meeting/meeting_widgets.dart';

/// Servicio simulado: guarda la reunión en memoria.
class _Falso extends MeetingService {
  _Falso([this.reunion]);
  Meeting? reunion;
  int terminadas = 0;
  Object? errorAlTerminar;

  @override
  Future<Meeting?> current(int courseId) async => reunion;

  @override
  Future<void> end(int courseId) async {
    if (errorAlTerminar != null) throw errorAlTerminar!;
    terminadas++;
    reunion = null;
  }
}

Meeting _reunion({bool enVivo = true, String proveedor = 'jitsi'}) => Meeting(
      id: 1,
      courseId: 10,
      teacherName: 'profe_a',
      title: 'Repaso del parcial',
      provider: proveedor,
      url: 'https://meet.jit.si/gesacad-abc',
      scheduledAt: enVivo ? null : DateTime(2030, 5, 20, 14, 30),
      isLive: enVivo,
    );

Future<void> espera(WidgetTester t, [int ms = 400]) async {
  await t.pump();
  await t.pump(Duration(milliseconds: ms));
}

Widget _app(Widget child) => MaterialApp(
      theme: ThemeData(extensions: const [AppTokens.light]),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

Future<void> _desmontar(WidgetTester t) async {
  // Cancela el temporizador de sondeo antes de terminar la prueba.
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 1));
}

void main() {
  group('Modelo', () {
    test('lee la respuesta del servidor y convierte la hora a local', () {
      final m = Meeting.fromJson({
        'id': 3, 'courseId': 10, 'teacherName': 'ana', 'title': 'Clase', 'provider': 'zoom',
        'url': 'https://zoom.us/j/1', 'scheduledAt': '2030-05-20T19:30:00Z', 'status': 'scheduled',
      });
      expect(m.providerName, 'Zoom');
      expect(m.isLive, isFalse);
      expect(m.scheduledAt!.toUtc(), DateTime.utc(2030, 5, 20, 19, 30));
    });

    test('sin hora programada está en vivo', () {
      final m = Meeting.fromJson({
        'id': 1, 'courseId': 1, 'teacherName': 'x', 'title': 't', 'provider': 'jitsi',
        'url': 'https://meet.jit.si/a', 'scheduledAt': null, 'status': 'live',
      });
      expect(m.isLive, isTrue);
      expect(m.scheduledAt, isNull);
      expect(m.providerName, 'Jitsi Meet');
    });
  });

  group('Estudiante', () {
    testWidgets('sin reunión no ve nada', (t) async {
      await t.pumpWidget(_app(CourseMeetingCard(courseId: 10, puedeGestionar: false, servicio: _Falso())));
      await espera(t);
      expect(find.text('Iniciar'), findsNothing);
      expect(find.text('Unirse a la reunión'), findsNothing);
      await _desmontar(t);
    });

    testWidgets('con reunión en curso ve "Unirse" y abre el enlace', (t) async {
      Uri? abierta;
      await t.pumpWidget(_app(CourseMeetingCard(
        courseId: 10, puedeGestionar: false, servicio: _Falso(_reunion()),
        abrirEnlace: (u) async { abierta = u; return true; },
      )));
      await espera(t);
      expect(find.text('EN CURSO'), findsOneWidget);
      expect(find.text('Repaso del parcial'), findsOneWidget);
      expect(find.text('Docente: profe_a'), findsOneWidget);
      expect(find.byTooltip('Terminar la reunión'), findsNothing, reason: 'el estudiante no gestiona');

      await t.tap(find.text('Unirse a la reunión'));
      await espera(t);
      expect(abierta.toString(), 'https://meet.jit.si/gesacad-abc');
      await _desmontar(t);
    });

    testWidgets('reunión programada: no puede entrar todavía y ve la hora', (t) async {
      await t.pumpWidget(_app(CourseMeetingCard(
        courseId: 10, puedeGestionar: false, servicio: _Falso(_reunion(enVivo: false)))));
      await espera(t);
      expect(find.text('PROGRAMADA'), findsOneWidget);
      expect(find.text('Aún no empieza'), findsOneWidget);
      expect(find.textContaining('20/05/2030 14:30'), findsOneWidget);
      await _desmontar(t);
    });

    testWidgets('aparece sola cuando el docente la inicia (sondeo periódico)', (t) async {
      final servicio = _Falso();
      await t.pumpWidget(_app(CourseMeetingCard(
        courseId: 10, puedeGestionar: false, servicio: servicio, cadaSegundos: 1)));
      await espera(t);
      expect(find.text('Unirse a la reunión'), findsNothing);

      servicio.reunion = _reunion();
      await t.pump(const Duration(seconds: 2));
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('Unirse a la reunión'), findsOneWidget);
      await _desmontar(t);
    });

    testWidgets('si el enlace no abre, avisa y lo copia', (t) async {
      await t.pumpWidget(_app(CourseMeetingCard(
        courseId: 10, puedeGestionar: false, servicio: _Falso(_reunion()),
        abrirEnlace: (u) async => false,
      )));
      await espera(t);
      await t.tap(find.text('Unirse a la reunión'));
      await espera(t);
      expect(find.textContaining('No se pudo abrir el enlace'), findsOneWidget);
      await t.pump(const Duration(seconds: 5));
      await _desmontar(t);
    });
  });

  group('Docente', () {
    testWidgets('sin reunión ofrece iniciarla y abre la hoja con las dos opciones', (t) async {
      await t.pumpWidget(_app(CourseMeetingCard(courseId: 10, puedeGestionar: true, servicio: _Falso())));
      await espera(t);
      expect(find.text('Reunión virtual'), findsOneWidget);

      await t.tap(find.text('Iniciar'));
      await espera(t, 600);
      expect(find.text('Nueva reunión virtual'), findsOneWidget);
      expect(find.text('Sala automática'), findsOneWidget);
      expect(find.text('Mi enlace'), findsOneWidget);
      expect(find.text('Iniciar ahora'), findsOneWidget);

      await t.tap(find.text('Mi enlace'));
      await espera(t);
      expect(find.text('Enlace de Google Meet, Zoom o Teams'), findsOneWidget);

      // Sin pegar el enlace no envía y lo explica.
      await t.tap(find.text('Iniciar ahora'));
      await espera(t);
      expect(find.text('Pega el enlace de Google Meet, Zoom o Teams.'), findsOneWidget);
      await _desmontar(t);
    });

    testWidgets('con reunión: puede entrar, copiar el enlace y terminarla', (t) async {
      final servicio = _Falso(_reunion());
      await t.pumpWidget(_app(CourseMeetingCard(
        courseId: 10, puedeGestionar: true, servicio: servicio,
        abrirEnlace: (u) async => true,
      )));
      await espera(t);
      expect(find.byTooltip('Copiar enlace de la reunión'), findsOneWidget);
      expect(find.byTooltip('Terminar la reunión'), findsOneWidget);

      await t.tap(find.byTooltip('Terminar la reunión'));
      await espera(t, 600);
      expect(find.text('¿Terminar la reunión?'), findsOneWidget);
      await t.tap(find.text('Terminar'));
      await espera(t, 600);

      expect(servicio.terminadas, 1);
      expect(find.text('EN CURSO'), findsNothing);
      expect(find.text('Iniciar'), findsOneWidget, reason: 'vuelve a ofrecer iniciar otra');
      await _desmontar(t);
    });

    testWidgets('si el servidor rechaza terminar, muestra el motivo y conserva la reunión', (t) async {
      final servicio = _Falso(_reunion())
        ..errorAlTerminar = const ApiMessageException(403, 'No eres docente de este curso.');
      await t.pumpWidget(_app(CourseMeetingCard(courseId: 10, puedeGestionar: true, servicio: servicio)));
      await espera(t);
      await t.tap(find.byTooltip('Terminar la reunión'));
      await espera(t, 600);
      await t.tap(find.text('Terminar'));
      await espera(t, 600);
      expect(find.text('No eres docente de este curso.'), findsOneWidget);
      expect(find.text('EN CURSO'), findsOneWidget);
      await _desmontar(t);
    });

    testWidgets('una reunión programada sí le permite entrar al docente', (t) async {
      await t.pumpWidget(_app(CourseMeetingCard(
        courseId: 10, puedeGestionar: true, servicio: _Falso(_reunion(enVivo: false)))));
      await espera(t);
      expect(find.text('Unirse a la reunión'), findsOneWidget);
      await _desmontar(t);
    });
  });
}
