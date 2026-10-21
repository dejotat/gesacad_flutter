import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gesacad/models/calendar_models.dart';
import 'package:gesacad/services/calendar_service.dart';
import 'package:gesacad/utils/colombia_holidays.dart';

CalEvent _ev(Map<String, dynamic> extra) => CalEvent.fromJson({
      'id': 'act-1', 'kind': 'activity', 'title': 'Taller', 'start': '2030-05-20T19:30:00Z',
      'courseName': 'Cálculo', 'activityType': 'project', ...extra,
    });

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Festivos de Colombia', () {
    test('2026: las 18 fechas oficiales (incluido Sagrado Corazón)', () {
      final f = festivosColombia(2026);
      final fechas = f.keys.map((d) => '${d.month}-${d.day}').toSet();
      expect(fechas, {
        '1-1', '1-12', '3-23', '4-2', '4-3', '5-1', '5-18', '6-8', '6-15', '6-29',
        '7-20', '8-7', '8-17', '10-12', '11-2', '11-16', '12-8', '12-25',
      });
      expect(f[DateTime(2026, 6, 15)], 'Sagrado Corazón');
      expect(f[DateTime(2026, 11, 16)], 'Independencia de Cartagena');
    });

    test('la Pascua es correcta en varios años', () {
      expect(domingoDePascua(2024), DateTime(2024, 3, 31));
      expect(domingoDePascua(2025), DateTime(2025, 4, 20));
      expect(domingoDePascua(2026), DateTime(2026, 4, 5));
      expect(domingoDePascua(2027), DateTime(2027, 3, 28));
      expect(domingoDePascua(2030), DateTime(2030, 4, 21));
    });

    test('los festivos trasladables siempre caen en lunes; Semana Santa en jueves y viernes', () {
      const trasladables = [
        'Reyes Magos', 'San José', 'San Pedro', 'Asunción', 'Raza', 'Todos los Santos',
        'Cartagena', 'Ascensión', 'Corpus', 'Sagrado',
      ];
      for (var anio = 2024; anio <= 2035; anio++) {
        final f = festivosColombia(anio);
        for (final e in f.entries) {
          final nombre = e.value;
          if (nombre.contains('Jueves Santo')) {
            expect(e.key.weekday, DateTime.thursday, reason: '$anio $nombre');
          } else if (nombre.contains('Viernes Santo')) {
            expect(e.key.weekday, DateTime.friday, reason: '$anio $nombre');
          } else if (trasladables.any(nombre.contains)) {
            expect(e.key.weekday, DateTime.monday, reason: '$anio $nombre');
          }
        }
        expect(f.length, inInclusiveRange(17, 18), reason: '$anio');
      }
    });

    test('dos festivos en el mismo lunes se unen en un nombre (30 de junio de 2025)', () {
      final f = festivosColombia(2025);
      expect(f[DateTime(2025, 6, 30)], contains('Sagrado Corazón'));
      expect(f[DateTime(2025, 6, 30)], contains('San Pedro y San Pablo'));
    });

    test('2025 coincide con el calendario oficial', () {
      final f = festivosColombia(2025);
      for (final fecha in [
        DateTime(2025, 1, 1), DateTime(2025, 1, 6), DateTime(2025, 3, 24), DateTime(2025, 4, 17),
        DateTime(2025, 4, 18), DateTime(2025, 6, 2), DateTime(2025, 6, 23), DateTime(2025, 8, 18),
        DateTime(2025, 10, 13), DateTime(2025, 11, 3), DateTime(2025, 11, 17),
      ]) {
        expect(f.containsKey(fecha), isTrue, reason: '$fecha');
      }
    });
  });

  group('CalEvent', () {
    test('la hora de Colombia (UTC-5) decide el día', () {
      final e = _ev({'start': '2030-05-21T03:00:00Z'}); // 22:00 del 20 en Colombia
      expect(e.startCol, DateTime(2030, 5, 20, 22, 0));
      expect(e.dia, DateTime(2030, 5, 20));
      expect(e.hora, '22:00');
      expect(_ev({'start': '2030-05-21T05:00:00Z'}).dia, DateTime(2030, 5, 21), reason: '00:00 Colombia ya es el 21');
    });

    test('ida y vuelta por JSON conserva todo', () {
      final e = _ev({'status': 'graded', 'grade': 4.5, 'weighting': 0.2, 'courseId': 3, 'refId': 9, 'refType': 'activity'});
      final otro = CalEvent.fromJson(jsonDecode(jsonEncode(e.toJson())) as Map<String, dynamic>);
      expect(otro.toJson(), e.toJson());
    });

    test('textos de estado por rol y tipo', () {
      expect(_ev({'status': 'pending'}).estadoTexto, 'Pendiente');
      expect(_ev({'status': 'graded', 'grade': 4.25}).estadoTexto, 'Calificada · 4.3');
      expect(_ev({'status': 'overdue'}).estadoTexto, 'Vencida sin entrega');
      expect(_ev({'status': 'open', 'submitted': 5, 'total': 12, 'toGrade': 3}).estadoTexto, '5/12 entregas · 3 por calificar');
      expect(_ev({'status': 'closed', 'toGrade': 0}).estadoTexto, 'Cerrada');
      expect(_ev({'kind': 'meeting', 'status': 'live'}).estadoTexto, 'En curso');
      expect(_ev({'kind': 'meeting', 'status': 'scheduled'}).estadoTexto, 'Programada');
      expect(_ev({'kind': 'evaluation', 'status': 'done'}).estadoTexto, 'Respondida');
    });

    test('esEntrega excluye los recursos', () {
      expect(_ev({}).esEntrega, isTrue);
      expect(_ev({'activityType': 'resource'}).esEntrega, isFalse);
      expect(_ev({'kind': 'meeting'}).esEntrega, isFalse);
    });

    test('enlace para añadir a Google Calendar', () {
      final u = _ev({'kind': 'meeting', 'url': 'https://meet.jit.si/x', 'title': 'Repaso, final'}).googleCalendarUri();
      expect(u.host, 'calendar.google.com');
      expect(u.queryParameters['action'], 'TEMPLATE');
      expect(u.queryParameters['text'], 'Repaso, final');
      expect(u.queryParameters['dates'], '20300520T193000Z/20300520T203000Z', reason: 'una reunión dura 1 h');
      expect(u.queryParameters['location'], 'https://meet.jit.si/x');
      expect(_ev({}).googleCalendarUri().queryParameters['dates'], '20300520T193000Z/20300520T200000Z');
    });
  });

  group('CalendarService', () {
    final desde = DateTime.utc(2030, 1, 1);
    final hasta = DateTime.utc(2030, 12, 31);

    test('carga eventos con la identidad y el rango', () async {
      Uri? pedida;
      final r = await http.runWithClient(
        () => const CalendarService().events(4, 'Student', desde: desde, hasta: hasta),
        () => MockClient((req) async {
          pedida = req.url;
          return http.Response(jsonEncode({'events': [
            {'id': 'act-1', 'kind': 'activity', 'title': 'Taller', 'start': '2030-05-20T19:30:00Z', 'status': 'pending'},
          ]}), 200);
        }),
      );
      expect(r.events.single.title, 'Taller');
      expect(r.fromCache, isFalse);
      expect(pedida!.path, '/calendar/events');
      expect(pedida!.queryParameters['userId'], '4');
      expect(pedida!.queryParameters['from'], '2030-01-01T00:00:00.000Z');
    });

    test('sin conexión usa la última copia; sin copia propaga el error', () async {
      var caido = true;
      Future<T> con<T>(Future<T> Function() f) => http.runWithClient(f, () => MockClient((req) async {
            if (caido) throw http.ClientException('sin red');
            return http.Response(jsonEncode({'events': [
              {'id': 'act-1', 'kind': 'activity', 'title': 'Guardado', 'start': '2030-05-20T19:30:00Z'},
            ]}), 200);
          }));

      await expectLater(
        con(() => const CalendarService().events(8, 'Student', desde: desde, hasta: hasta)),
        throwsA(isA<Object>()),
      );
      caido = false;
      await con(() => const CalendarService().events(4, 'Student', desde: desde, hasta: hasta));
      caido = true;
      final r = await con(() => const CalendarService().events(4, 'Student', desde: desde, hasta: hasta));
      expect(r.fromCache, isTrue);
      expect(r.events.single.title, 'Guardado');
    });

    test('un error del servidor llega con su mensaje', () async {
      await expectLater(
        http.runWithClient(
          () => const CalendarService().events(4, 'Student', desde: desde, hasta: hasta),
          () => MockClient((_) async => http.Response(jsonEncode({'error': 'RANGO_INVALIDO', 'message': 'Rango inválido'}), 400,
              headers: {'content-type': 'application/json; charset=utf-8'})),
        ),
        throwsA(predicate((e) => e.toString() == 'Rango inválido')),
      );
    });

    test('suscripción: crea el enlace, lo recuerda y lo revoca', () async {
      var activo = false;
      Future<T> con<T>(Future<T> Function() f) => http.runWithClient(f, () => MockClient((req) async {
            if (req.method == 'POST') {
              activo = true;
              return http.Response(jsonEncode({'url': 'https://api.test/calendar/feed/abc.ics'}), 201);
            }
            if (req.method == 'DELETE') {
              activo = false;
              return http.Response(jsonEncode({'revoked': 1}), 200);
            }
            return http.Response(jsonEncode({'active': activo}), 200);
          }));
      const s = CalendarService();
      expect((await con(() => s.feedStatus(4, 'Student'))).active, isFalse);
      expect(await con(() => s.createFeed(4, 'Student')), 'https://api.test/calendar/feed/abc.ics');
      final info = await con(() => s.feedStatus(4, 'Student'));
      expect(info.active, isTrue);
      expect(info.url, 'https://api.test/calendar/feed/abc.ics', reason: 'se recuerda en este equipo');
      await con(() => s.revokeFeed(4, 'Student'));
      final fin = await con(() => s.feedStatus(4, 'Student'));
      expect(fin.active, isFalse);
      expect(fin.url, isNull);
    });

    test('enlaces para suscribirse en Google, Outlook y Apple', () {
      const url = 'https://api.test/calendar/feed/abc.ics';
      expect(CalendarService.googleSubscribeUri(url).queryParameters['cid'], 'webcal://api.test/calendar/feed/abc.ics');
      expect(CalendarService.outlookSubscribeUri(url).queryParameters['url'], url);
      expect(CalendarService.appleSubscribeUri(url).scheme, 'webcal');
    });
  });
}
