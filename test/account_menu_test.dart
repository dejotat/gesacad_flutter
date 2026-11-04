import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gesacad/config/app_tokens.dart';
import 'package:gesacad/widgets/ui/account_menu.dart';

// PNG de 1×1 píxel (foto de prueba).
final _foto = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');

class _Llamadas {
  int perfil = 0, ajustes = 0, salir = 0;
}

Widget _app(_Llamadas l, {String nombre = 'Ana María Gómez', String rol = 'Student', bool oscuro = false, bool conFoto = false}) =>
    MaterialApp(
      theme: ThemeData(
        brightness: oscuro ? Brightness.dark : Brightness.light,
        extensions: [oscuro ? AppTokens.dark : AppTokens.light],
      ),
      home: Scaffold(
        appBar: AppBar(actions: [
          MenuCuenta(
            nombre: nombre,
            rol: rol,
            foto: conFoto ? _foto : null,
            onPerfil: () => l.perfil++,
            onAjustes: () => l.ajustes++,
            onSalir: () => l.salir++,
          ),
        ]),
      ),
    );

Future<void> _abrir(WidgetTester t) async {
  await t.tap(find.byTooltip('Cuenta y opciones'));
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

void main() {
  group('Utilidades', () {
    test('iniciales', () {
      expect(MenuCuenta.iniciales('Ana María Gómez'), 'AM');
      expect(MenuCuenta.iniciales('  juan   pérez  '), 'JP');
      expect(MenuCuenta.iniciales('Carlos'), 'CA');
      expect(MenuCuenta.iniciales('X'), 'X');
      expect(MenuCuenta.iniciales(''), '?');
      expect(MenuCuenta.iniciales('   '), '?');
    });

    test('nombre del rol', () {
      expect(MenuCuenta.nombreDelRol('Admin'), 'Administrador');
      expect(MenuCuenta.nombreDelRol('Teacher'), 'Docente');
      expect(MenuCuenta.nombreDelRol('Student'), 'Estudiante');
      expect(MenuCuenta.nombreDelRol('Otro'), 'Otro');
    });
  });

  group('Menú de cuenta', () {
    testWidgets('muestra quién tiene la sesión y las opciones con su descripción', (t) async {
      await t.pumpWidget(_app(_Llamadas()));
      expect(find.text('Ana María Gómez'), findsNothing, reason: 'cerrado: no se ve nada');
      await _abrir(t);
      expect(find.text('Ana María Gómez'), findsOneWidget);
      expect(find.text('AM'), findsOneWidget, reason: 'iniciales mientras no haya foto');
      expect(find.text('Estudiante'), findsOneWidget);
      expect(find.text('Mi perfil'), findsOneWidget);
      expect(find.text('Tus datos y tu foto'), findsOneWidget);
      expect(find.text('Ajustes'), findsOneWidget);
      expect(find.text('Tema, voz y accesibilidad'), findsOneWidget);
      expect(find.text('Cerrar sesión'), findsOneWidget);
      expect(find.text('Salir de esta cuenta'), findsOneWidget);
    });

    testWidgets('cada opción ejecuta SU acción y cierra el menú', (t) async {
      final l = _Llamadas();
      await t.pumpWidget(_app(l));

      await _abrir(t);
      await t.tap(find.text('Mi perfil'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect([l.perfil, l.ajustes, l.salir], [1, 0, 0]);
      expect(find.text('Mi perfil'), findsNothing, reason: 'el menú se cerró');

      await _abrir(t);
      await t.tap(find.text('Ajustes'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect([l.perfil, l.ajustes, l.salir], [1, 1, 0]);

      await _abrir(t);
      await t.tap(find.text('Cerrar sesión'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect([l.perfil, l.ajustes, l.salir], [1, 1, 1]);
    });

    testWidgets('tocar la cabecera NO hace nada ni cierra el menú', (t) async {
      final l = _Llamadas();
      await t.pumpWidget(_app(l));
      await _abrir(t);
      await t.tap(find.text('Ana María Gómez'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect([l.perfil, l.ajustes, l.salir], [0, 0, 0]);
      expect(find.text('Mi perfil'), findsOneWidget, reason: 'sigue abierto');
    });

    testWidgets('con foto muestra la imagen y no las iniciales', (t) async {
      await t.pumpWidget(_app(_Llamadas(), conFoto: true));
      await _abrir(t);
      expect(find.text('AM'), findsNothing);
      final conImagen = find.byWidgetPredicate((w) =>
          w is Container && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).image != null);
      expect(conImagen, findsOneWidget);
    });

    testWidgets('muestra el rol correcto de cada perfil', (t) async {
      for (final (rol, texto) in [('Admin', 'Administrador'), ('Teacher', 'Docente'), ('Student', 'Estudiante')]) {
        await t.pumpWidget(_app(_Llamadas(), rol: rol));
        await _abrir(t);
        expect(find.text(texto), findsOneWidget, reason: rol);
        await t.tapAt(const Offset(5, 5)); // cierra el menú
        await t.pump();
        await t.pump(const Duration(milliseconds: 300));
      }
    });

    testWidgets('sin nombre muestra "Tu cuenta" y "?" en el avatar', (t) async {
      await t.pumpWidget(_app(_Llamadas(), nombre: '   '));
      await _abrir(t);
      expect(find.text('Tu cuenta'), findsOneWidget);
      expect(find.text('?'), findsOneWidget);
    });

    testWidgets('un nombre larguísimo en pantalla angosta no desborda', (t) async {
      await t.binding.setSurfaceSize(const Size(320, 640));
      await t.pumpWidget(_app(_Llamadas(), nombre: 'Maria de los Angeles Fernanda del Pilar Rodriguez de la Cruz y Montenegro'));
      await _abrir(t);
      expect(find.text('Mi perfil'), findsOneWidget);
      expect(t.takeException(), isNull, reason: 'sin RenderFlex overflow');
      await t.binding.setSurfaceSize(null);
    });

    testWidgets('se ve bien en tema oscuro', (t) async {
      await t.pumpWidget(_app(_Llamadas(), oscuro: true));
      await _abrir(t);
      expect(find.text('Cerrar sesión'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('accesibilidad: cabecera y opciones tienen etiqueta para el lector de pantalla', (t) async {
      final h = t.ensureSemantics();
      await t.pumpWidget(_app(_Llamadas()));
      await _abrir(t);
      expect(find.bySemanticsLabel('Sesión de Ana María Gómez, Estudiante'), findsOneWidget);
      expect(find.bySemanticsLabel('Mi perfil. Tus datos y tu foto'), findsOneWidget);
      expect(find.bySemanticsLabel('Cerrar sesión. Salir de esta cuenta'), findsOneWidget);
      h.dispose();
    });
  });
}
