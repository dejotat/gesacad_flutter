import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:gesacad/config/app_themes.dart';
import 'package:gesacad/services/chatbot_service.dart';
import 'package:gesacad/services/settings_service.dart';
import 'package:gesacad/widgets/chatbot_widget.dart';

http.Response _json(int status, Map<String, dynamic> cuerpo) =>
    http.Response(jsonEncode(cuerpo), status, headers: {'content-type': 'application/json; charset=utf-8'});

Future<void> _avanzar(WidgetTester t, [int ms = 600]) async {
  for (var i = 0; i < ms ~/ 100; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _abrir(WidgetTester t) async {
  t.view.physicalSize = const Size(900, 1400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(MaterialApp(
    theme: AppThemes.of(AppThemeType.neon),
    home: const Scaffold(floatingActionButton: ChatbotWidget()),
  ));
  await t.tap(find.byTooltip('Asistente GESACAD'));
  await _avanzar(t);
}

void main() {
  test('el servicio envía mensaje e historial recortado y devuelve la respuesta', () async {
    late Map<String, dynamic> enviado;
    await http.runWithClient(() async {
      final historial = [for (var i = 0; i < 14; i++) TurnoChat(esUsuario: i.isEven, texto: 't$i')];
      final r = await const ChatbotService().preguntar('hola', historial);
      expect(r, 'Hola, ¿en qué te ayudo?');
      expect((enviado['history'] as List).length, ChatbotService.maxHistorial);
      expect(enviado['history'].last, {'role': 'model', 'text': 't13'});
    }, () => MockClient((r) async {
          expect(r.url.path, '/chatbot/ask');
          enviado = jsonDecode(r.body) as Map<String, dynamic>;
          return _json(200, {'reply': 'Hola, ¿en qué te ayudo?', 'model': 'm'});
        }));
    expect(enviado['message'], 'hola');
  });

  test('los errores del servidor se convierten en mensajes claros y sin detalles técnicos', () async {
    Future<ChatbotException> falla(http.Response Function(http.Request) servidor) async {
      late ChatbotException e;
      await http.runWithClient(() async {
        try {
          await const ChatbotService().preguntar('hola', const []);
        } on ChatbotException catch (x) {
          e = x;
        }
      }, () => MockClient((r) async => servidor(r)));
      return e;
    }

    final cuota = await falla((r) => _json(429, {'error': 'CUOTA_AGOTADA', 'message': 'El asistente alcanzó su límite de uso por ahora.'}));
    expect(cuota.tipo, FalloChat.cuota);
    expect(cuota.reintentable, isFalse);

    final sinConfig = await falla((r) => _json(503, {'error': 'CHATBOT_NO_CONFIGURADO', 'message': 'El asistente aún no está configurado.'}));
    expect(sinConfig.tipo, FalloChat.noConfigurado);

    final antiguo = await falla((r) => http.Response('<html>Cannot POST</html>', 404));
    expect(antiguo.tipo, FalloChat.noConfigurado);
    expect(antiguo.mensaje, isNot(contains('html')));

    final red = await falla((r) => throw http.ClientException('Failed host lookup'));
    expect(red.tipo, FalloChat.sinConexion);
    expect(red.reintentable, isTrue);

    final sesion = await falla((r) => _json(401, {'error': 'NO_AUTENTICADO', 'message': 'Inicia sesión para continuar.'}));
    expect(sesion.tipo, FalloChat.sesion);
  });

  testWidgets('una pregunta frecuente se ENVÍA al servidor, muestra «escribiendo» y luego la respuesta', (t) async {
    final pendiente = Completer<http.Response>();
    final cuerpos = <Map<String, dynamic>>[];
    await http.runWithClient(() async {
      await _abrir(t);
      expect(find.text('Preguntas frecuentes:'), findsOneWidget);
      expect(find.textContaining('privacidad'), findsOneWidget);

      await t.tap(find.text('¿Cómo funciona el semáforo académico?'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 200));
      // Mientras llega la respuesta: indicador y el campo bloqueado.
      expect(find.text('Escribiendo'), findsOneWidget);
      expect(cuerpos.single['message'], '¿Cómo funciona el semáforo académico?', reason: 'el atajo pasa por el servidor');
      expect(cuerpos.single['history'], isEmpty);

      pendiente.complete(_json(200, {'reply': 'Cada materia tiene un color según su estado. ¿Quieres un ejemplo?', 'model': 'm'}));
      await _avanzar(t);
      expect(find.text('Escribiendo'), findsNothing);
      expect(find.textContaining('¿Quieres un ejemplo?'), findsOneWidget);

      // La segunda pregunta lleva el contexto de la primera.
      await t.enterText(find.byType(TextField), 'Sí, dame un ejemplo');
      await t.testTextInput.receiveAction(TextInputAction.send);
      await t.pump();
      await t.pump(const Duration(milliseconds: 200));
      expect(cuerpos.length, 2);
      expect(cuerpos[1]['history'], [
        {'role': 'user', 'text': '¿Cómo funciona el semáforo académico?'},
        {'role': 'model', 'text': 'Cada materia tiene un color según su estado. ¿Quieres un ejemplo?'},
      ]);
      await _avanzar(t);
      expect(find.text('Claro, mira este ejemplo.'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    }, () => MockClient((r) async {
          cuerpos.add(jsonDecode(r.body) as Map<String, dynamic>);
          if (cuerpos.length == 1) return pendiente.future;
          return _json(200, {'reply': 'Claro, mira este ejemplo.', 'model': 'm'});
        }));
  });

  testWidgets('un fallo se ve en el chat con un mensaje claro y «Reintentar» vuelve a enviar', (t) async {
    var intentos = 0;
    await http.runWithClient(() async {
      await _abrir(t);
      await t.tap(find.text('¿Cómo voy en mis notas?'));
      await _avanzar(t);
      expect(find.text('El asistente está muy ocupado. Inténtalo de nuevo en un momento.'), findsOneWidget);
      expect(find.textContaining('Error:'), findsNothing, reason: 'nada técnico');
      expect(find.text('Reintentar'), findsOneWidget);

      await t.tap(find.text('Reintentar'));
      await _avanzar(t);
      expect(intentos, 2);
      expect(find.text('Reintentar'), findsNothing);
      expect(find.text('Ve a «Calificaciones» en el menú. ¿Te muestro cómo leerlas?'), findsOneWidget);
      expect(find.text('¿Cómo voy en mis notas?'), findsOneWidget, reason: 'la pregunta no se duplica al reintentar');
      await t.pumpWidget(const SizedBox());
    }, () => MockClient((r) async {
          intentos++;
          return intentos == 1
              ? _json(503, {'error': 'CHATBOT_SATURADO', 'message': 'El asistente está muy ocupado. Inténtalo de nuevo en un momento.'})
              : _json(200, {'reply': 'Ve a «Calificaciones» en el menú. ¿Te muestro cómo leerlas?', 'model': 'm'});
        }));
  });

  testWidgets('cuota agotada: se avisa en el chat y no se ofrece reintentar', (t) async {
    await http.runWithClient(() async {
      await _abrir(t);
      await t.tap(find.text('¿Cómo entrego una tarea en GESACAD?'));
      await _avanzar(t);
      expect(find.textContaining('límite de uso'), findsOneWidget);
      expect(find.text('Reintentar'), findsNothing);
      await t.pumpWidget(const SizedBox());
    }, () => MockClient((r) async => _json(429, {'error': 'CUOTA_AGOTADA', 'message': 'El asistente alcanzó su límite de uso por ahora. Inténtalo de nuevo más tarde.'})));
  });
}
