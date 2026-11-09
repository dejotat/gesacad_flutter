import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gesacad/screens/login_screen.dart';
import 'package:gesacad/widgets/ui/cinematic_backdrop.dart';

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('CinematicBackdrop', () {
    testWidgets('dibuja el contenido encima y se anima por defecto', (t) async {
      await t.pumpWidget(_app(const CinematicBackdrop(child: Center(child: Text('contenido')))));
      expect(find.text('contenido'), findsOneWidget);
      await t.pump(const Duration(seconds: 1));
      expect(t.hasRunningAnimations, isTrue, reason: 'la aurora se mueve');
      expect(t.takeException(), isNull);
    });

    testWidgets('con "reducir movimiento" queda un cuadro fijo (sin animaciones)', (t) async {
      t.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);

      await t.pumpWidget(_app(const CinematicBackdrop(child: Text('contenido'))));
      // Si algo siguiera animando, pumpAndSettle agotaría el tiempo y fallaría.
      await t.pumpAndSettle();
      expect(t.hasRunningAnimations, isFalse);
      expect(find.text('contenido'), findsOneWidget);
    });

    testWidgets('es decorativo: no aporta nodos de accesibilidad ni intercepta toques', (t) async {
      var toques = 0;
      await t.pumpWidget(_app(CinematicBackdrop(
        child: Center(child: ElevatedButton(onPressed: () => toques++, child: const Text('ok'))),
      )));
      await t.tap(find.text('ok'));
      expect(toques, 1);
    });

    for (final tam in const [Size(320, 560), Size(800, 1280), Size(1600, 900)]) {
      testWidgets('se pinta sin errores en ${tam.width.toInt()}x${tam.height.toInt()}', (t) async {
        t.view.physicalSize = tam;
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        await t.pumpWidget(_app(const CinematicBackdrop(child: SizedBox.expand())));
        for (var i = 0; i < 4; i++) {
          await t.pump(const Duration(seconds: 2));
        }
        expect(t.takeException(), isNull);
      });
    }
  });

  group('LoginScreen', () {
    testWidgets('usa SIEMPRE el tema oscuro de marca y conserva sus acciones', (t) async {
      t.view.physicalSize = const Size(1000, 1100);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);

      // La app está en tema CLARO: el login igual debe verse oscuro.
      await t.pumpWidget(MaterialApp(theme: ThemeData.light(), home: const LoginScreen()));
      await t.pump(const Duration(seconds: 2));

      expect(find.byType(CinematicBackdrop), findsOneWidget);
      expect(find.text('GESACAD'), findsOneWidget);
      expect(find.text('Explorar como invitado'), findsOneWidget);
      expect(find.text('Iniciar Sesión'), findsWidgets);
      expect(find.byType(TextFormField), findsNWidgets(2));
      expect(Theme.of(t.element(find.byType(TextFormField).first)).brightness, Brightness.dark);
      expect(t.takeException(), isNull);
    });

    testWidgets('muestra el aviso inicial (p. ej. sesión expirada)', (t) async {
      t.view.physicalSize = const Size(1000, 1100);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);

      await t.pumpWidget(const MaterialApp(home: LoginScreen(mensaje: 'Tu sesión expiró')));
      await t.pump(const Duration(seconds: 2));
      expect(find.text('Tu sesión expiró'), findsOneWidget);
    });
  });
}
