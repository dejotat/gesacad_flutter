import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:gesacad/config/app_tokens.dart';
import 'package:gesacad/widgets/dev_server_badge.dart';

Widget _app(Widget child) => MaterialApp(
      theme: ThemeData(extensions: const [AppTokens.light]),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  testWidgets('servidor local activo: lo indica y avisa que los usuarios son distintos', (t) async {
    Uri? pedida;
    await t.pumpWidget(_app(DevServerBadge(
      siempreVisible: true,
      baseUrl: 'http://localhost:8081',
      client: MockClient((req) async {
        pedida = req.url;
        return http.Response('{"status":"ok"}', 200);
      }),
    )));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));

    expect(pedida.toString(), 'http://localhost:8081/health');
    expect(find.text('Servidor activo'), findsOneWidget);
    expect(find.text('LOCAL'), findsOneWidget);
    expect(find.text('http://localhost:8081'), findsOneWidget);
    expect(find.textContaining('sus propios usuarios'), findsOneWidget);
  });

  testWidgets('backend local apagado: explica cómo iniciarlo y permite reintentar', (t) async {
    var intentos = 0;
    var vivo = false;
    await t.pumpWidget(_app(DevServerBadge(
      siempreVisible: true,
      baseUrl: 'http://localhost:8081',
      client: MockClient((_) async {
        intentos++;
        if (!vivo) throw http.ClientException('Connection refused');
        return http.Response('{"status":"ok"}', 200);
      }),
    )));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));

    expect(find.text('Sin respuesta del servidor'), findsOneWidget);
    expect(find.textContaining('npm start'), findsOneWidget);

    vivo = true; // el usuario levanta el backend y toca "Reintentar"
    await t.tap(find.byTooltip('Reintentar conexión'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(intentos, 2);
    expect(find.text('Servidor activo'), findsOneWidget);
  });

  testWidgets('servidor de producción: se etiqueta como PRODUCCIÓN', (t) async {
    await t.pumpWidget(_app(DevServerBadge(
      siempreVisible: true,
      baseUrl: 'https://gesacad-backend.onrender.com',
      client: MockClient((_) async => http.Response('{}', 200)),
    )));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('PRODUCCIÓN'), findsOneWidget);
    expect(find.text('LOCAL'), findsNothing);
  });
}
