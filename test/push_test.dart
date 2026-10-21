import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gesacad/config/app_tokens.dart';
import 'package:gesacad/services/notification_service.dart';
import 'package:gesacad/services/push_service.dart';
import 'package:gesacad/widgets/push_widgets.dart';

/// Firebase simulado: el permiso y el token se controlan desde la prueba.
class _Transporte implements PushTransport {
  PermisoPush permisoActual = PermisoPush.concedido;
  PermisoPush alPedir = PermisoPush.concedido;
  String? tokenActual = 'token-del-telefono-'.padLeft(40, 'x');
  int inits = 0, borrados = 0, pedidos = 0;
  Object? errorAlIniciar;
  PushMensaje? inicial;
  final tokens = StreamController<String>.broadcast(sync: true);
  final primerPlano = StreamController<PushMensaje>.broadcast(sync: true);
  final abiertos = StreamController<PushMensaje>.broadcast(sync: true);

  @override
  Future<void> init() async {
    inits++;
    if (errorAlIniciar != null) throw errorAlIniciar!;
  }

  @override
  Future<PermisoPush> permiso() async => permisoActual;

  @override
  Future<PermisoPush> solicitarPermiso() async {
    pedidos++;
    permisoActual = alPedir;
    return alPedir;
  }

  @override
  Future<String?> token() async => tokenActual;
  @override
  Stream<String> get tokenRenovado => tokens.stream;
  @override
  Stream<PushMensaje> get enPrimerPlano => primerPlano.stream;
  @override
  Stream<PushMensaje> get alAbrir => abiertos.stream;
  @override
  Future<PushMensaje?> mensajeInicial() async => inicial;
  @override
  Future<void> borrarToken() async => borrados++;
}

/// Servidor simulado de /push y /notifications.
class _Servidor {
  bool habilitado = true;
  bool usuarioActivo = true;
  bool caido = false;
  final llamadas = <String>[];
  final registrados = <String>[];
  final borrados = <String>[];
  final leidas = <int>[];

  Future<http.Response> responder(http.Request r) async {
    llamadas.add('${r.method} ${r.url.path}');
    if (caido) throw http.ClientException('sin red');
    http.Response ok(Object o, [int code = 200]) =>
        http.Response(jsonEncode(o), code, headers: {'content-type': 'application/json; charset=utf-8'});
    switch ('${r.method} ${r.url.path}') {
      case 'GET /push/status':
        return ok({'enabled': habilitado, 'devices': registrados.length, 'userEnabled': usuarioActivo});
      case 'POST /push/devices':
        registrados.add((jsonDecode(r.body) as Map)['token'] as String);
        return ok({'registered': true}, 201);
      case 'DELETE /push/devices':
        borrados.add((jsonDecode(r.body) as Map)['token'] as String);
        return ok({'removed': 1});
      case 'PUT /push/settings':
        usuarioActivo = (jsonDecode(r.body) as Map)['enabled'] as bool;
        return ok({'userEnabled': usuarioActivo});
      case 'GET /notifications/summary':
        return ok({'unread': 0, 'latestId': 0, 'items': []});
      case 'POST /notifications/read':
        leidas.addAll(((jsonDecode(r.body) as Map)['ids'] as List).cast<int>());
        return ok({'updated': 1, 'unread': 0});
    }
    return http.Response('no encontrado', 404);
  }
}

Future<T> _con<T>(_Servidor s, Future<T> Function() f) => http.runWithClient(f, () => MockClient(s.responder));
Future<void> _micro() => Future<void>.delayed(const Duration(milliseconds: 30));

PushService _push(_Transporte t, {bool configurado = true}) =>
    PushService.test(transporte: t, configurado: configurado, notificaciones: NotificationService.test());

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Disponibilidad', () {
    test('sin configuración de Firebase no hace nada ni llama al servidor', () async {
      final s = _Servidor();
      final p = _push(_Transporte(), configurado: false);
      await _con(s, () async {
        await p.init();
        await p.start(4, 'Student');
      });
      expect(p.estado.value, PushEstado.noDisponible);
      expect(s.llamadas, isEmpty);
    });

    test('si el servidor no tiene push, queda no disponible y no registra', () async {
      final s = _Servidor()..habilitado = false;
      final p = _push(_Transporte());
      await _con(s, () => p.start(4, 'Student'));
      expect(p.estado.value, PushEstado.noDisponible);
      expect(s.registrados, isEmpty);
    });

    test('si el usuario los apagó, no registra el teléfono', () async {
      final s = _Servidor()..usuarioActivo = false;
      final p = _push(_Transporte());
      await _con(s, () => p.start(4, 'Student'));
      expect(p.estado.value, PushEstado.desactivadoPorUsuario);
      expect(s.registrados, isEmpty);
    });

    test('sin conexión no lanza ni cambia el estado', () async {
      final s = _Servidor()..caido = true;
      final p = _push(_Transporte());
      await _con(s, () => p.start(4, 'Student'));
      expect(p.estado.value, PushEstado.noDisponible);
    });

    test('un fallo al iniciar Firebase no lanza (la app debe abrir igual)', () async {
      final t = _Transporte()..errorAlIniciar = StateError('Firebase roto');
      final p = _push(t);
      await p.init();
      expect(p.estado.value, PushEstado.noDisponible);
    });

    test('un userId inválido se ignora', () async {
      final s = _Servidor();
      final p = _push(_Transporte());
      await _con(s, () => p.start(0, 'Student'));
      expect(s.llamadas, isEmpty);
    });
  });

  group('Permiso y registro', () {
    test('con permiso concedido registra el teléfono UNA sola vez', () async {
      final s = _Servidor();
      final t = _Transporte();
      final p = _push(t);
      await _con(s, () async {
        await p.start(4, 'Student');
        await p.start(4, 'Student');
      });
      expect(p.estado.value, PushEstado.activo);
      expect(s.registrados, [t.tokenActual], reason: 'el mismo token no se envía dos veces');
    });

    test('sin decidir: pide explicar primero; al aceptar pide el permiso y registra', () async {
      final s = _Servidor();
      final t = _Transporte()..permisoActual = PermisoPush.sinDecidir;
      final p = _push(t);
      await _con(s, () async {
        await p.start(4, 'Student');
        expect(p.estado.value, PushEstado.pendientePermiso);
        expect(p.debePreguntar, isTrue);
        expect(t.pedidos, 0, reason: 'el permiso del sistema NO se pide antes de explicarlo');

        expect(await p.solicitarPermiso(), isTrue);
      });
      expect(t.pedidos, 1);
      expect(p.estado.value, PushEstado.activo);
      expect(s.registrados, hasLength(1));
    });

    test('si el sistema deniega el permiso, queda denegado y no registra', () async {
      final s = _Servidor();
      final t = _Transporte()
        ..permisoActual = PermisoPush.sinDecidir
        ..alPedir = PermisoPush.denegado;
      final p = _push(t);
      await _con(s, () async {
        await p.start(4, 'Student');
        expect(await p.solicitarPermiso(), isFalse);
      });
      expect(p.estado.value, PushEstado.denegado);
      expect(s.registrados, isEmpty);
    });

    test('permiso ya bloqueado en el teléfono: estado denegado sin preguntar', () async {
      final t = _Transporte()..permisoActual = PermisoPush.denegado;
      final p = _push(t);
      await _con(_Servidor(), () => p.start(4, 'Student'));
      expect(p.estado.value, PushEstado.denegado);
      expect(p.debePreguntar, isFalse);
    });

    test('"Ahora no": no se vuelve a preguntar en los siguientes inicios', () async {
      final t = _Transporte()..permisoActual = PermisoPush.sinDecidir;
      final p = _push(t);
      await _con(_Servidor(), () async {
        await p.start(4, 'Student');
        await p.posponer();
        expect(p.estado.value, PushEstado.inactivo);
        await p.start(4, 'Student');
      });
      expect(p.estado.value, PushEstado.inactivo);
      expect(p.debePreguntar, isFalse);
      expect(t.pedidos, 0);
    });

    test('cuando Firebase renueva el token, se vuelve a registrar el nuevo', () async {
      final s = _Servidor();
      final t = _Transporte();
      final p = _push(t);
      await _con(s, () async {
        await p.init();
        await p.start(4, 'Student');
        t.tokens.add('token-renovado-'.padLeft(40, 'n'));
        await _micro();
      });
      expect(s.registrados, hasLength(2));
      expect(s.registrados.last, startsWith('nnnn'), reason: 'se registró el token NUEVO');
      await p.cerrar();
    });

    test('el teléfono compartido: otro usuario con el mismo token se registra de nuevo', () async {
      final s = _Servidor();
      final t = _Transporte();
      final p = _push(t);
      await _con(s, () async {
        await p.start(4, 'Student');
        await p.stop();
        await p.start(5, 'Teacher');
      });
      expect(s.registrados, hasLength(2));
      expect(s.borrados, hasLength(1));
    });
  });

  group('Cerrar sesión', () {
    test('avisa al servidor, borra el token y deja el estado inactivo', () async {
      final s = _Servidor();
      final t = _Transporte();
      final p = _push(t);
      await _con(s, () async {
        await p.start(4, 'Student');
        await p.stop();
      });
      expect(s.borrados, [t.tokenActual]);
      expect(t.borrados, 1);
      expect(p.estado.value, PushEstado.inactivo);
    });

    test('sin sesión ni registro no lanza', () async {
      final p = _push(_Transporte());
      await _con(_Servidor(), () => p.stop());
    });

    test('si el servidor no responde igual borra el token local', () async {
      final s = _Servidor();
      final t = _Transporte();
      final p = _push(t);
      await _con(s, () => p.start(4, 'Student'));
      s.caido = true;
      await _con(s, () => p.stop());
      expect(t.borrados, 1);
    });
  });

  group('Mensajes', () {
    test('con la app abierta, un aviso trae las novedades al instante', () async {
      final s = _Servidor();
      final t = _Transporte();
      final svc = NotificationService.test();
      final p = PushService.test(transporte: t, notificaciones: svc);
      await _con(s, () async {
        await p.init();
        svc.attach(4, 'Student');
        await p.start(4, 'Student');
        s.llamadas.clear();
        t.primerPlano.add(const PushMensaje(title: 'x', body: 'y'));
        await _micro();
        svc.detach();
      });
      expect(s.llamadas, contains('GET /notifications/summary'));
      await p.cerrar();
    });

    test('tocar un aviso (app en segundo plano) lo abre y marca la notificación como leída', () async {
      final s = _Servidor();
      final t = _Transporte();
      final p = _push(t);
      final abiertos = <PushMensaje>[];
      p.alTocar = (m) async => abiertos.add(m);
      await _con(s, () async {
        await p.init();
        await p.start(4, 'Student');
        t.abiertos.add(const PushMensaje(data: {'notificationId': '55', 'refType': 'activity', 'refId': '7', 'courseId': '10'}));
        await _micro();
      });
      expect(abiertos.single.refId, 7);
      expect(abiertos.single.courseId, 10);
      expect(s.leidas, [55]);
      await p.cerrar();
    });

    test('la app abierta POR el aviso (estaba cerrada) también lo procesa', () async {
      final t = _Transporte()..inicial = const PushMensaje(data: {'refType': 'meeting', 'courseId': '3'});
      final p = _push(t);
      final abiertos = <PushMensaje>[];
      p.alTocar = (m) async => abiertos.add(m);
      await _con(_Servidor(), () => p.init());
      await _micro();
      expect(abiertos.single.refType, 'meeting');
      await p.cerrar();
    });

    test('si el aviso se toca antes de que la app esté lista, queda pendiente y se abre después', () async {
      final t = _Transporte()..inicial = const PushMensaje(data: {'refType': 'evaluation'});
      final p = _push(t);
      await _con(_Servidor(), () => p.init());
      final abiertos = <PushMensaje>[];
      p.alTocar = (m) async => abiertos.add(m);
      await p.abrirPendiente();
      expect(abiertos.single.refType, 'evaluation');
      await p.abrirPendiente();
      expect(abiertos, hasLength(1), reason: 'se abre una sola vez');
      await p.cerrar();
    });

    test('lee los datos del mensaje y tolera valores raros', () {
      const m = PushMensaje(data: {'notificationId': 'abc', 'refId': '', 'courseId': '9', 'courseImg': '2'});
      expect(m.notificationId, isNull);
      expect(m.refId, isNull);
      expect(m.courseId, 9);
      expect(m.courseImg, 2);
    });
  });

  group('Preferencia del usuario', () {
    test('apagarlo guarda la preferencia sin tocar la bandeja; encenderlo registra el teléfono', () async {
      final s = _Servidor();
      final t = _Transporte();
      final p = _push(t);
      await _con(s, () async {
        await p.start(4, 'Student');
        await p.setUserEnabled(false);
        expect(p.estado.value, PushEstado.desactivadoPorUsuario);
        expect(s.usuarioActivo, isFalse);
        s.registrados.clear();
        await SharedPreferences.getInstance().then((x) => x.clear());
        await p.setUserEnabled(true);
      });
      expect(p.estado.value, PushEstado.activo);
      expect(s.registrados, hasLength(1));
    });

    test('si el servidor falla, lanza para que la pantalla lo explique', () async {
      final s = _Servidor()..caido = true;
      final p = _push(_Transporte());
      await _con(s, () async {
        await expectLater(p.setUserEnabled(false), throwsA(isA<Object>()));
      });
    });
  });

  group('Pantallas', () {
    Widget app(Widget hijo) => MaterialApp(theme: ThemeData(extensions: const [AppTokens.light]), home: Scaffold(body: Center(child: hijo)));

    testWidgets('el diálogo explica para qué sirve y "Activar avisos" pide el permiso', (t) async {
      final tr = _Transporte()..permisoActual = PermisoPush.sinDecidir;
      final p = _push(tr);
      await _con(_Servidor(), () async {
        await p.start(4, 'Student');
        await t.pumpWidget(app(Builder(builder: (ctx) => ElevatedButton(onPressed: () => preguntarPorPush(ctx, servicio: p), child: const Text('abrir')))));
        await t.tap(find.text('abrir'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
        expect(find.text('¿Activar avisos en tu teléfono?'), findsOneWidget);
        expect(find.text('Entregas que están por vencer'), findsOneWidget);
        expect(tr.pedidos, 0);

        await t.tap(find.text('Activar avisos'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
        expect(tr.pedidos, 1);
        expect(p.estado.value, PushEstado.activo);
      });
    });

    testWidgets('"Ahora no" no vuelve a preguntar', (t) async {
      final tr = _Transporte()..permisoActual = PermisoPush.sinDecidir;
      final p = _push(tr);
      await _con(_Servidor(), () async {
        await p.start(4, 'Student');
        await t.pumpWidget(app(Builder(builder: (ctx) => ElevatedButton(onPressed: () => preguntarPorPush(ctx, servicio: p), child: const Text('abrir')))));
        await t.tap(find.text('abrir'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
        await t.tap(find.text('Ahora no'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
        expect(tr.pedidos, 0);
        expect(p.debePreguntar, isFalse);

        await t.tap(find.text('abrir'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 400));
        expect(find.text('¿Activar avisos en tu teléfono?'), findsNothing);
      });
    });

    testWidgets('el interruptor no aparece si las push no están disponibles', (t) async {
      final p = _push(_Transporte(), configurado: false);
      await t.pumpWidget(app(AvisosEnTelefono(servicio: p)));
      expect(find.text('Avisos en el teléfono'), findsNothing);
    });

    testWidgets('el interruptor refleja el estado y guarda el cambio', (t) async {
      final s = _Servidor();
      final p = _push(_Transporte());
      await _con(s, () async {
        await p.start(4, 'Student');
        await t.pumpWidget(app(AvisosEnTelefono(servicio: p)));
        expect(find.text('Avisos en el teléfono'), findsOneWidget);
        expect(tester(t).value, isTrue);

        await t.tap(find.byType(Switch));
        await t.pump();
        await t.pump(const Duration(milliseconds: 300));
        expect(s.usuarioActivo, isFalse);
        expect(tester(t).value, isFalse);
      });
    });

    testWidgets('si el permiso está bloqueado lo explica y deshabilita el interruptor', (t) async {
      final tr = _Transporte()..permisoActual = PermisoPush.denegado;
      final p = _push(tr);
      await _con(_Servidor(), () async {
        await p.start(4, 'Student');
        await t.pumpWidget(app(AvisosEnTelefono(servicio: p)));
        expect(find.textContaining('Bloqueados en los ajustes'), findsOneWidget);
        expect(tester(t).onChanged, isNull);
      });
    });
  });
}

/// El Switch del interruptor (única instancia en estas pantallas).
Switch tester(WidgetTester t) => t.widget<Switch>(find.byType(Switch));
