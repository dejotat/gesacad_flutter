import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gesacad/config/app_tokens.dart';
import 'package:gesacad/models/calendar_models.dart';
import 'package:gesacad/screens/calendar/calendar_screen.dart';
import 'package:gesacad/screens/calendar/calendar_widgets.dart';

Map<String, dynamic> _ev(String id, String titulo, Duration desde, Map<String, dynamic> extra) => {
      'id': id, 'kind': 'activity', 'title': titulo, 'courseId': 10, 'courseName': 'Cálculo',
      'activityType': 'project', 'weighting': 0.2, 'refType': 'activity', 'refId': 1,
      'start': DateTime.now().toUtc().add(desde).toIso8601String(), ...extra,
    };

class _Servidor {
  bool caido = false;
  bool feedActivo = false;
  final llamadas = <String>[];

  final eventos = <Map<String, dynamic>>[
    _ev('act-1', 'Taller de límites', const Duration(hours: 30), {'status': 'pending'}),
    _ev('act-2', 'Parcial final', const Duration(days: 5), {'status': 'pending', 'activityType': 'midterm', 'courseName': 'Física', 'courseId': 11}),
    _ev('act-3', 'Proyecto entregado', const Duration(days: 8), {'status': 'submitted'}),
    _ev('meet-1', 'Tutoría', const Duration(days: 2), {'kind': 'meeting', 'status': 'scheduled', 'url': 'https://meet.jit.si/gesacad-x', 'refType': 'meeting', 'refId': 10}),
  ];

  Future<http.Response> responder(http.Request r) async {
    llamadas.add('${r.method} ${r.url.path}');
    if (caido) throw http.ClientException('sin red');
    http.Response ok(Object o, [int code = 200]) =>
        http.Response(jsonEncode(o), code, headers: {'content-type': 'application/json; charset=utf-8'});
    if (r.url.path == '/calendar/events') return ok({'events': eventos});
    if (r.url.path == '/calendar/feed') {
      if (r.method == 'POST') {
        feedActivo = true;
        return ok({'url': 'https://api.test/calendar/feed/${'a' * 48}.ics'}, 201);
      }
      if (r.method == 'DELETE') {
        feedActivo = false;
        return ok({'revoked': 1});
      }
      return ok({'active': feedActivo});
    }
    return http.Response('no encontrado', 404);
  }
}

Future<void> espera(WidgetTester t, [int ms = 600]) async {
  await t.pump();
  await t.pump(Duration(milliseconds: ms));
}

Widget _app(Widget home) => MaterialApp(theme: ThemeData(extensions: const [AppTokens.light]), home: home);

Future<T> _con<T>(_Servidor s, Future<T> Function() f) => http.runWithClient(f, () => MockClient(s.responder));

Future<void> _salir(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 1));
}

void main() {
  setUpAll(() async => initializeDateFormatting('es_ES'));
  setUp(() => SharedPreferences.setMockInitialValues({'userId': 4, 'userRol': 'Student'}));

  group('Pantalla del calendario', () {
    testWidgets('muestra el próximo vencimiento y la carga de la semana', (t) async {
      await t.binding.setSurfaceSize(const Size(500, 1600));
      await _con(_Servidor(), () async {
        await t.pumpWidget(_app(const CalendarScreen()));
        await espera(t, 900);
        expect(find.text('PRÓXIMA ENTREGA'), findsOneWidget);
        expect(find.text('Taller de límites'), findsOneWidget);
        expect(find.text('Carga de la semana'), findsOneWidget);
        expect(find.byTooltip('Ver en mi calendario (Google, Outlook, Apple)'), findsOneWidget);
        await _salir(t);
      });
      await t.binding.setSurfaceSize(null);
    });

    testWidgets('la vista Agenda agrupa por día, muestra el estado y la búsqueda filtra', (t) async {
      await t.binding.setSurfaceSize(const Size(500, 1600));
      await _con(_Servidor(), () async {
        await t.pumpWidget(_app(const CalendarScreen()));
        await espera(t, 900);
        await t.tap(find.text('Agenda'));
        await espera(t, 900);
        expect(find.text('Taller de límites'), findsOneWidget);
        expect(find.text('Parcial final'), findsOneWidget);
        expect(find.text('Tutoría'), findsOneWidget);
        expect(find.text('Pendiente'), findsWidgets);
        expect(find.text('Entregada'), findsOneWidget);
        expect(find.text('Programada'), findsOneWidget);

        await t.tap(find.byTooltip('Buscar'));
        await espera(t);
        await t.enterText(find.byType(TextField), 'parcial');
        await espera(t, 700);
        expect(find.text('Parcial final'), findsOneWidget);
        expect(find.text('Taller de límites'), findsNothing);
        expect(find.text('Tutoría'), findsNothing);

        await t.tap(find.byTooltip('Cerrar búsqueda'));
        await espera(t, 700);
        expect(find.text('Taller de límites'), findsOneWidget);
        await _salir(t);
      });
      await t.binding.setSurfaceSize(null);
    });

    testWidgets('filtrar por curso deja solo sus eventos', (t) async {
      await t.binding.setSurfaceSize(const Size(500, 1600));
      await _con(_Servidor(), () async {
        await t.pumpWidget(_app(const CalendarScreen()));
        await espera(t, 900);
        await t.tap(find.text('Agenda'));
        await espera(t, 900);
        await t.tap(find.widgetWithText(ChoiceChip, 'Física'));
        await espera(t, 700);
        expect(find.text('Parcial final'), findsOneWidget);
        expect(find.text('Taller de límites'), findsNothing);
        await t.tap(find.widgetWithText(ChoiceChip, 'Todos los cursos'));
        await espera(t, 700);
        expect(find.text('Taller de límites'), findsOneWidget);
        await _salir(t);
      });
      await t.binding.setSurfaceSize(null);
    });

    testWidgets('tocar un evento abre sus acciones', (t) async {
      await t.binding.setSurfaceSize(const Size(500, 1600));
      await _con(_Servidor(), () async {
        await t.pumpWidget(_app(const CalendarScreen()));
        await espera(t, 900);
        await t.tap(find.text('Agenda'));
        await espera(t, 900);
        await t.tap(find.text('Taller de límites'));
        await espera(t, 900);
        expect(find.text('Abrir actividad'), findsOneWidget);
        expect(find.text('Añadir a Google Calendar'), findsOneWidget);
        expect(find.text('Vale 20 % de la nota'), findsOneWidget);
        await t.tapAt(const Offset(10, 10)); // cierra la hoja
        await espera(t);
        await _salir(t);
      });
      await t.binding.setSurfaceSize(null);
    });

    testWidgets('sin conexión muestra la última copia con un aviso, y los festivos siguen', (t) async {
      await t.binding.setSurfaceSize(const Size(500, 1600));
      final s = _Servidor();
      await _con(s, () async {
        await t.pumpWidget(_app(const CalendarScreen()));
        await espera(t, 900);
        await _salir(t);
        s.caido = true;
        await t.pumpWidget(_app(const CalendarScreen()));
        await espera(t, 900);
        expect(find.textContaining('Sin conexión'), findsOneWidget);
        expect(find.text('PRÓXIMA ENTREGA'), findsOneWidget, reason: 'usa la copia guardada');
        await _salir(t);
      });
      await t.binding.setSurfaceSize(null);
    });

    testWidgets('sin sesión no consulta el servidor ni muestra la sincronización', (t) async {
      SharedPreferences.setMockInitialValues({});
      await t.binding.setSurfaceSize(const Size(500, 1600));
      final s = _Servidor();
      await _con(s, () async {
        await t.pumpWidget(_app(const CalendarScreen()));
        await espera(t, 900);
        expect(s.llamadas, isEmpty);
        expect(find.byTooltip('Ver en mi calendario (Google, Outlook, Apple)'), findsNothing);
        await _salir(t);
      });
      await t.binding.setSurfaceSize(null);
    });

    testWidgets('suscripción: crear el enlace, verlo y dejar de compartir', (t) async {
      await t.binding.setSurfaceSize(const Size(500, 1600));
      final s = _Servidor();
      await _con(s, () async {
        await t.pumpWidget(_app(const CalendarScreen()));
        await espera(t, 900);
        await t.tap(find.byTooltip('Ver en mi calendario (Google, Outlook, Apple)'));
        await espera(t, 900);
        expect(find.text('Ver GESACAD en tu calendario'), findsOneWidget);
        await t.tap(find.text('Crear mi enlace de suscripción'));
        await espera(t, 900);
        expect(find.textContaining('/calendar/feed/'), findsOneWidget);
        expect(find.text('Google Calendar'), findsOneWidget);
        expect(find.text('Outlook'), findsOneWidget);
        expect(find.textContaining('Es personal'), findsOneWidget);
        expect(s.feedActivo, isTrue);

        await t.tap(find.text('Dejar de compartir'));
        await espera(t, 700);
        await t.tap(find.text('Dejar de compartir').last);
        await espera(t, 900);
        expect(s.feedActivo, isFalse);
        expect(find.text('Crear mi enlace de suscripción'), findsOneWidget);
        await _salir(t);
      });
      await t.binding.setSurfaceSize(null);
    });
  });

  group('Componentes', () {
    CalEvent ev(String id, Duration desde, Map<String, dynamic> extra) =>
        CalEvent.fromJson(_ev(id, 'Evento $id', desde, extra));

    testWidgets('próximo vencimiento: cuenta regresiva y color según urgencia', (t) async {
      final ahora = DateTime.utc(2030, 5, 20, 12);
      CalEvent en(Duration d) => CalEvent.fromJson({
            'id': 'a', 'kind': 'activity', 'title': 'Entrega', 'start': ahora.add(d).toIso8601String(),
            'activityType': 'project', 'status': 'pending', 'courseName': 'Cálculo',
          });
      Future<void> montar(List<CalEvent> l) async {
        await t.pumpWidget(_app(Scaffold(body: ProximoVencimientoCard(eventos: l, onTap: (_) {}, ahora: () => ahora))));
        await t.pump();
      }

      await montar([en(const Duration(hours: 2, minutes: 5))]);
      expect(find.text('2\nh'), findsOneWidget);
      expect(find.text('PRÓXIMA ENTREGA'), findsOneWidget);

      await montar([en(const Duration(days: 3, hours: 4))]);
      expect(find.text('3\nd'), findsOneWidget);

      await montar([]);
      expect(find.text('Estás al día: no hay vencimientos próximos.'), findsOneWidget);

      // Lo ya entregado o calificado no cuenta como pendiente.
      await montar([CalEvent.fromJson({'id': 'b', 'kind': 'activity', 'title': 'x', 'start': ahora.add(const Duration(hours: 1)).toIso8601String(), 'activityType': 'project', 'status': 'submitted'})]);
      expect(find.text('Estás al día: no hay vencimientos próximos.'), findsOneWidget);

      // Una reunión en curso se muestra como "YA".
      await montar([CalEvent.fromJson({'id': 'm', 'kind': 'meeting', 'title': 'Tutoría', 'start': ahora.subtract(const Duration(minutes: 10)).toIso8601String(), 'status': 'live'})]);
      expect(find.text('REUNIÓN EN CURSO'), findsOneWidget);
      expect(find.text('YA'), findsOneWidget);
      await _salir(t);
    });

    testWidgets('carga semanal: una barra por día y tocar selecciona', (t) async {
      DateTime? elegido;
      final lunes = DateTime(2030, 5, 20);
      await t.pumpWidget(_app(Scaffold(
        body: CargaSemanalCard(
          dia: DateTime(2030, 5, 22),
          seleccionado: DateTime(2030, 5, 22),
          hoy: lunes,
          conteo: {lunes: 1, DateTime(2030, 5, 22): 4},
          onDia: (d) => elegido = d,
        ),
      )));
      await espera(t, 500);
      expect(find.text('5 eventos'), findsOneWidget);
      for (final l in ['L', 'M', 'X', 'J', 'V', 'S', 'D']) {
        expect(find.text(l), findsOneWidget);
      }
      await t.tap(find.text('X'));
      expect(elegido, DateTime(2030, 5, 22));
      await t.tap(find.text('V'));
      expect(elegido, DateTime(2030, 5, 24));
    });

    testWidgets('acciones de una reunión: unirse y añadir a Google Calendar', (t) async {
      final abiertos = <Uri>[];
      final e = ev('meet-1', const Duration(hours: 1), {
        'kind': 'meeting', 'status': 'live', 'url': 'https://meet.jit.si/gesacad-x', 'refType': 'meeting', 'refId': 10,
      });
      await t.pumpWidget(_app(Builder(builder: (ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => mostrarAccionesEvento(ctx, e, userId: 4, rol: 'Student', abrirEnlace: (u) async { abiertos.add(u); return true; }),
                child: const Text('abrir'),
              ),
            ),
          ))));
      await t.tap(find.text('abrir'));
      await espera(t, 900);
      expect(find.text('Unirse a la reunión'), findsOneWidget);
      expect(find.text('Ir al curso'), findsOneWidget);
      await t.tap(find.text('Unirse a la reunión'));
      await espera(t, 700);
      expect(abiertos.single.toString(), 'https://meet.jit.si/gesacad-x');

      await t.tap(find.text('abrir'));
      await espera(t, 900);
      await t.tap(find.text('Añadir a Google Calendar'));
      await espera(t, 700);
      expect(abiertos.last.host, 'calendar.google.com');
      expect(abiertos.last.queryParameters['action'], 'TEMPLATE');
      await _salir(t);
    });

    test('formatos de fecha y duración', () {
      expect(fechaLarga(DateTime(2030, 5, 20, 19, 30)), 'Lunes 20 de mayo · 19:30');
      expect(fechaLarga(DateTime(2030, 5, 20, 19, 30), conHora: false), 'Lunes 20 de mayo');
      expect(duracionCorta(const Duration(seconds: 20)), 'ahora');
      expect(duracionCorta(const Duration(minutes: 45)), '45 min');
      expect(duracionCorta(const Duration(hours: 3)), '3 h');
      expect(duracionCorta(const Duration(hours: 5, minutes: 10)), '5 h 10 min');
      expect(duracionCorta(const Duration(days: 2)), '2 d');
      expect(duracionCorta(const Duration(days: 2, hours: 7, minutes: 3)), '2 d 7 h');
      expect(ahoraColombia(DateTime.utc(2030, 5, 20, 3)), DateTime(2030, 5, 19, 22));
    });
  });
}
