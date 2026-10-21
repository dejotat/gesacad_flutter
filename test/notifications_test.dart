import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gesacad/config/app_tokens.dart';
import 'package:gesacad/models/notification_models.dart';
import 'package:gesacad/screens/notifications/notifications_panel.dart';
import 'package:gesacad/services/notification_service.dart';

/// Servidor de notificaciones simulado en memoria.
class _Servidor {
  final List<Map<String, dynamic>> filas = [];
  final Map<String, bool> prefs = {};
  final List<String> llamadas = [];
  bool caido = false;
  int _id = 0;

  Map<String, dynamic> agregar(String tipo, String titulo,
      {String cuerpo = 'cuerpo', bool leida = false, Duration hace = Duration.zero, String? refType, int? refId}) {
    final f = {
      'id': ++_id, 'type': tipo, 'title': titulo, 'body': cuerpo,
      'createdAt': DateTime.now().toUtc().subtract(hace).toIso8601String(),
      'read': leida, 'courseId': 10, 'courseName': 'Cálculo', 'courseCode': 'CAL', 'courseImg': 1,
      'refType': refType, 'refId': refId,
    };
    filas.add(f);
    return f;
  }

  int get noLeidas => filas.where((f) => f['read'] == false).length;

  Future<http.Response> responder(http.Request r) async {
    llamadas.add('${r.method} ${r.url.path}${r.url.query.isEmpty ? '' : '?${r.url.query}'}');
    if (caido) throw http.ClientException('sin red');
    final ruta = r.url.path;
    final q = r.url.queryParameters;
    http.Response ok(Object o) => http.Response(jsonEncode(o), 200, headers: {'content-type': 'application/json'});

    if (r.method == 'GET' && ruta == '/notifications') {
      var l = filas.reversed.toList();
      if (q['type'] != null) l = l.where((f) => f['type'] == q['type']).toList();
      if (q['unread'] == '1') l = l.where((f) => f['read'] == false).toList();
      if (q['before'] != null) l = l.where((f) => (f['id'] as int) < int.parse(q['before']!)).toList();
      final lim = int.parse(q['limit'] ?? '30');
      final hayMas = l.length > lim;
      final items = l.take(lim).toList();
      return ok({'items': items, 'unread': noLeidas, 'nextBefore': hayMas ? items.last['id'] : null});
    }
    if (r.method == 'GET' && ruta == '/notifications/summary') {
      final despues = int.parse(q['after'] ?? '0');
      final nuevas = filas.where((f) => (f['id'] as int) > despues && f['read'] == false).toList().reversed.take(5).toList();
      return ok({'unread': noLeidas, 'latestId': filas.isEmpty ? 0 : filas.last['id'], 'items': despues > 0 ? nuevas : []});
    }
    if (r.method == 'POST' && ruta == '/notifications/read') {
      final b = jsonDecode(r.body) as Map;
      for (final f in filas) {
        if (b['all'] == true || (b['ids'] as List?)?.contains(f['id']) == true) f['read'] = true;
      }
      return ok({'updated': 1, 'unread': noLeidas});
    }
    if (r.method == 'DELETE' && ruta.startsWith('/notifications/')) {
      filas.removeWhere((f) => f['id'] == int.parse(ruta.split('/').last));
      return ok({'deleted': 1, 'unread': noLeidas});
    }
    if (r.method == 'POST' && ruta == '/notifications/clear') {
      final antes = filas.length;
      filas.removeWhere((f) => f['read'] == true);
      return ok({'deleted': antes - filas.length, 'unread': noLeidas});
    }
    if (r.method == 'GET' && ruta == '/notifications/preferences') {
      return ok({'types': {for (final t in NotifType.values) t.name: prefs[t.name] ?? true}});
    }
    if (r.method == 'PUT' && ruta == '/notifications/preferences') {
      final b = jsonDecode(r.body) as Map;
      prefs[b['type'] as String] = b['enabled'] as bool;
      return ok({'type': b['type'], 'enabled': b['enabled']});
    }
    return http.Response('no encontrado', 404);
  }
}

Future<void> espera(WidgetTester t, [int ms = 600]) async {
  await t.pump();
  await t.pump(Duration(milliseconds: ms));
}

Widget _app(Widget home) => MaterialApp(theme: ThemeData(extensions: const [AppTokens.light]), home: home);

NotificationService _servicio() => NotificationService.test(intervalo: const Duration(hours: 1));

Future<T> _con<T>(_Servidor s, Future<T> Function() cuerpo) =>
    http.runWithClient(cuerpo, () => MockClient(s.responder));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Modelo', () {
    test('lee el JSON del servidor y convierte la hora a local', () {
      final n = AppNotif.fromJson({
        'id': 7, 'type': 'meeting', 'title': 'Reunión', 'body': 'b', 'createdAt': '2030-05-20T19:30:00Z',
        'read': false, 'courseId': 3, 'courseName': 'Física', 'refType': 'meeting', 'refId': 3,
      });
      expect(n.type, NotifType.meeting);
      expect(n.createdAt.toUtc(), DateTime.utc(2030, 5, 20, 19, 30));
      expect(n.courseName, 'Física');
      expect(n.read, isFalse);
    });

    test('un tipo desconocido cae en "sistema" y todos los tipos tienen texto', () {
      expect(NotifType.parse('inventado'), NotifType.system);
      for (final t in NotifType.values) {
        expect(t.label, isNotEmpty);
        expect(t.description, isNotEmpty);
      }
    });
  });

  group('Servicio', () {
    test('el primer sondeo fija la base; después avisa solo de lo realmente nuevo', () async {
      final s = _Servidor()..agregar('activity', 'Antigua');
      final svc = _servicio();
      final llegadas = <List<AppNotif>>[];
      svc.arrivals.listen(llegadas.add);
      await _con(s, () async {
        svc.attach(4, 'Student');
        await svc.poll();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(svc.unread.value, 1);
        expect(llegadas, isEmpty, reason: 'lo que ya existía no es una novedad');

        s.agregar('grade', 'Nota nueva');
        await svc.poll();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(llegadas, hasLength(1));
        expect(llegadas.single.single.title, 'Nota nueva');
        expect(svc.unread.value, 2);

        await svc.poll();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(llegadas, hasLength(1), reason: 'no repite la misma novedad');
        svc.detach();
      });
    });

    test('envía la identidad del usuario y no lanza si el servidor no responde', () async {
      final s = _Servidor()..caido = true;
      final svc = _servicio();
      await _con(s, () async {
        svc.attach(9, 'Teacher');
        await svc.poll();
        svc.detach();
      });
      expect(s.llamadas.any((l) => l.contains('/notifications/summary')), isTrue);
      expect(svc.unread.value, 0);
    });

    test('marcar leídas, borrar y limpiar actualizan el contador con lo que dice el servidor', () async {
      final s = _Servidor()
        ..agregar('activity', 'A')
        ..agregar('activity', 'B')
        ..agregar('grade', 'C', leida: true);
      final svc = _servicio();
      await _con(s, () async {
        svc.attach(4, 'Student');
        final p = await svc.list();
        expect(p.items, hasLength(3));
        expect(svc.unread.value, 2);

        final sinLeer = p.items.firstWhere((n) => !n.read);
        await svc.markRead([sinLeer.id]);
        expect(svc.unread.value, 1);
        await svc.delete(p.items.last.id);
        await svc.markAllRead();
        expect(svc.unread.value, 0);
        expect(await svc.deleteBulk(), greaterThan(0));
        svc.detach();
      });
    });

    test('pagina con cursor', () async {
      final s = _Servidor();
      for (var i = 1; i <= 7; i++) {
        s.agregar('activity', 'N$i');
      }
      final svc = _servicio();
      await _con(s, () async {
        svc.attach(4, 'Student');
        final p1 = await svc.list(limit: 3);
        expect(p1.items.map((n) => n.title), ['N7', 'N6', 'N5']);
        expect(p1.nextBefore, isNotNull);
        final p2 = await svc.list(limit: 3, before: p1.nextBefore);
        expect(p2.items.map((n) => n.title), ['N4', 'N3', 'N2']);
        final p3 = await svc.list(limit: 3, before: p2.nextBefore);
        expect(p3.items.map((n) => n.title), ['N1']);
        expect(p3.nextBefore, isNull);
        svc.detach();
      });
    });

    test('sin conexión devuelve la última copia guardada', () async {
      final s = _Servidor()..agregar('activity', 'Guardada');
      final svc = _servicio();
      await _con(s, () async {
        svc.attach(4, 'Student');
        await svc.list();
        s.caido = true;
        final p = await svc.list();
        expect(p.fromCache, isTrue);
        expect(p.items.single.title, 'Guardada');
        svc.detach();
      });
    });

    test('sin conexión y sin copia propaga el error', () async {
      final s = _Servidor()..caido = true;
      final svc = _servicio();
      await _con(s, () async {
        svc.attach(5, 'Student');
        await expectLater(svc.list(), throwsA(isA<Object>()));
        svc.detach();
      });
    });

    test('preferencias: lee y cambia por tipo', () async {
      final s = _Servidor();
      final svc = _servicio();
      await _con(s, () async {
        svc.attach(4, 'Student');
        expect((await svc.preferences())[NotifType.grade], isTrue);
        await svc.setPreference(NotifType.grade, false);
        expect((await svc.preferences())[NotifType.grade], isFalse);
        expect((await svc.preferences())[NotifType.activity], isTrue);
        svc.detach();
      });
    });
  });

  group('Panel', () {
    testWidgets('agrupa por día, cuenta las no leídas y muestra el tipo', (t) async {
      await t.binding.setSurfaceSize(const Size(500, 1400));
      final s = _Servidor()
        ..agregar('activity', 'Hace días', hace: const Duration(days: 3), leida: true)
        ..agregar('grade', 'Ayer sin leer', hace: const Duration(hours: 24))
        ..agregar('meeting', 'Reunión de hoy');
      await _con(s, () async {
        await t.pumpWidget(_app(NotificationsPanel(userId: 4, userRol: 'Student', servicio: _servicio())));
        await espera(t, 900);
        expect(find.text('2 sin leer'), findsOneWidget);
        expect(find.text('HOY'), findsOneWidget);
        expect(find.text('AYER'), findsOneWidget);
        expect(find.text('ESTA SEMANA'), findsOneWidget);
        expect(find.text('Reunión de hoy'), findsOneWidget);
        expect(find.text('Calificación'), findsWidgets);
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(seconds: 1));
      });
      await t.binding.setSurfaceSize(null);
    });

    testWidgets('tocar una la marca como leída en el servidor y baja el contador', (t) async {
      await t.binding.setSurfaceSize(const Size(500, 1400));
      final s = _Servidor()..agregar('system', 'Aviso del sistema');
      await _con(s, () async {
        final svc = _servicio();
        await t.pumpWidget(_app(NotificationsPanel(userId: 4, userRol: 'Student', servicio: svc)));
        await espera(t, 900);
        expect(find.text('1 sin leer'), findsOneWidget);
        await t.tap(find.text('Aviso del sistema'));
        await espera(t, 900);
        expect(s.filas.single['read'], isTrue, reason: 'el estado de leído vive en el servidor');
        expect(svc.unread.value, 0);
        // Sin pantalla de destino: muestra el detalle.
        expect(find.text('Entendido'), findsOneWidget);
        await t.tap(find.text('Entendido'));
        await espera(t);
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(seconds: 1));
      });
      await t.binding.setSurfaceSize(null);
    });

    testWidgets('"Marcar todas" y deslizar para descartar', (t) async {
      await t.binding.setSurfaceSize(const Size(500, 1400));
      final s = _Servidor()
        ..agregar('activity', 'Primera')
        ..agregar('activity', 'Segunda');
      await _con(s, () async {
        final svc = _servicio();
        await t.pumpWidget(_app(NotificationsPanel(userId: 4, userRol: 'Student', servicio: svc)));
        await espera(t, 900);

        await t.drag(find.text('Segunda'), const Offset(-600, 0));
        await espera(t, 900);
        expect(find.text('Segunda'), findsNothing);
        expect(s.filas.map((f) => f['title']), ['Primera'], reason: 'se borró en el servidor');

        await t.tap(find.byTooltip('Marcar todas como leídas'));
        await espera(t, 900);
        expect(s.noLeidas, 0);
        expect(find.text('Todo al día'), findsOneWidget);
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(seconds: 1));
      });
      await t.binding.setSurfaceSize(null);
    });

    testWidgets('el filtro por tipo pide al servidor solo ese tipo', (t) async {
      await t.binding.setSurfaceSize(const Size(800, 1400));
      final s = _Servidor()
        ..agregar('activity', 'Una actividad')
        ..agregar('grade', 'Una nota');
      await _con(s, () async {
        await t.pumpWidget(_app(NotificationsPanel(userId: 4, userRol: 'Student', servicio: _servicio())));
        await espera(t, 900);
        await t.tap(find.bySemanticsLabel('Filtrar: Calificación'));
        await espera(t, 900);
        expect(s.llamadas.any((l) => l.contains('type=grade')), isTrue);
        expect(find.text('Una nota'), findsOneWidget);
        expect(find.text('Una actividad'), findsNothing);

        await t.ensureVisible(find.text('Sin leer'));
        await espera(t, 300);
        await t.tap(find.text('Sin leer'));
        await espera(t, 900);
        expect(s.llamadas.last.contains('unread=1'), isTrue, reason: s.llamadas.join(' | '));
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(seconds: 1));
      });
      await t.binding.setSurfaceSize(null);
    });

    testWidgets('sin conexión muestra la última copia con un aviso', (t) async {
      await t.binding.setSurfaceSize(const Size(500, 1400));
      final s = _Servidor()..agregar('activity', 'En caché');
      await _con(s, () async {
        final svc = _servicio();
        svc.attach(4, 'Student');
        await svc.list(); // guarda la copia
        s.caido = true;
        await t.pumpWidget(_app(NotificationsPanel(userId: 4, userRol: 'Student', servicio: svc)));
        await espera(t, 900);
        expect(find.textContaining('Sin conexión'), findsOneWidget);
        expect(find.text('En caché'), findsOneWidget);
        svc.detach();
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(seconds: 1));
      });
      await t.binding.setSurfaceSize(null);
    });

    testWidgets('si el servidor falla y no hay copia, ofrece reintentar', (t) async {
      await t.binding.setSurfaceSize(const Size(500, 1400));
      final s = _Servidor()..caido = true;
      await _con(s, () async {
        await t.pumpWidget(_app(NotificationsPanel(userId: 77, userRol: 'Student', servicio: _servicio())));
        await espera(t, 900);
        expect(find.byType(ErrorWidget), findsNothing);
        expect(find.text('Reintentar'), findsOneWidget);
        s.caido = false;
        s.agregar('activity', 'Ya hay');
        await t.tap(find.text('Reintentar'));
        await espera(t, 900);
        expect(find.text('Ya hay'), findsOneWidget);
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(seconds: 1));
      });
      await t.binding.setSurfaceSize(null);
    });

    testWidgets('preferencias: cada interruptor se guarda en el servidor', (t) async {
      await t.binding.setSurfaceSize(const Size(500, 1600));
      final s = _Servidor()..agregar('activity', 'x');
      await _con(s, () async {
        await t.pumpWidget(_app(NotificationsPanel(userId: 4, userRol: 'Student', servicio: _servicio())));
        await espera(t, 900);
        await t.tap(find.byTooltip('Más opciones'));
        await espera(t);
        await t.tap(find.text('Preferencias'));
        await espera(t, 900);
        expect(find.text('Qué avisos quiero recibir'), findsOneWidget);
        expect(find.text('Sistema'), findsNothing, reason: 'un estudiante no recibe eventos del sistema');
        await t.tap(find.text('Calificación').last);
        await espera(t, 900);
        expect(s.prefs['grade'], isFalse);
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(seconds: 1));
      });
      await t.binding.setSurfaceSize(null);
    });

    testWidgets('sin sesión no consulta nada y muestra el estado vacío', (t) async {
      final s = _Servidor();
      await _con(s, () async {
        await t.pumpWidget(_app(NotificationsPanel(servicio: _servicio())));
        await espera(t, 900);
        expect(find.textContaining('Sin notificaciones'), findsOneWidget);
        expect(s.llamadas, isEmpty);
      });
    });
  });

  group('Campana', () {
    testWidgets('muestra la insignia con las no leídas y se actualiza sola', (t) async {
      final s = _Servidor()
        ..agregar('activity', 'A')
        ..agregar('activity', 'B');
      await _con(s, () async {
        final svc = _servicio();
        await t.pumpWidget(_app(Scaffold(
          appBar: AppBar(actions: [NotificationBell(userId: 4, userRol: 'Student', servicio: svc)]),
        )));
        await espera(t, 700);
        expect(find.text('2'), findsOneWidget);
        expect(find.byTooltip('Notificaciones, 2 sin leer'), findsOneWidget);

        s.agregar('grade', 'C');
        await svc.poll();
        await espera(t, 700);
        expect(find.text('3'), findsOneWidget);
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(seconds: 1));
      });
    });
  });
}
