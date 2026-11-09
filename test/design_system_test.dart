import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gesacad/config/app_themes.dart';
import 'package:gesacad/config/app_tokens.dart';
import 'package:gesacad/services/settings_service.dart';
import 'package:gesacad/widgets/ui/ui.dart';

double _hue(Color c) => HSLColor.fromColor(c).hue;

/// Distancia angular entre dos matices (0–180).
double _dHue(double a, double b) {
  final d = (a - b).abs() % 360;
  return d > 180 ? 360 - d : d;
}

Widget _app(Widget child, {AppThemeType tema = AppThemeType.aurora}) =>
    MaterialApp(theme: AppThemes.of(tema), home: Scaffold(body: SingleChildScrollView(child: child)));

void main() {
  group('Tema por defecto: Futurista', () {
    test('es oscuro, se llama «Futurista» y usa violeta + cian', () {
      const t = AppThemeType.aurora;
      expect(t.isDark, isTrue);
      expect(t.label, 'Futurista');
      expect(AppThemes.of(t).brightness, Brightness.dark);
      expect(_dHue(_hue(t.primaryColor), 262), lessThan(15), reason: 'primario violeta');
      expect(_dHue(_hue(t.secondaryColor), 188), lessThan(15), reason: 'secundario cian');
    });

    test('el encabezado NO pasa por azul (violeta → magenta)', () {
      final g = AppThemeType.aurora.gradient;
      for (var i = 0; i <= 10; i++) {
        final c = Color.lerp(g[0], g[1], i / 10)!;
        final h = _hue(c);
        // 200–250° es el azul: el degradado violeta-turquesa anterior caía justo ahí.
        expect(h < 200 || h > 250, isTrue, reason: 'paso $i: matiz ${h.toStringAsFixed(0)}° (azul)');
      }
    });

    test('las tarjetas de curso no tienen azul y los degradados automáticos casi no cambian de matiz', () {
      for (final base in [...AppTokens.dark.chart, AppThemeType.aurora.primaryColor]) {
        final g = AppTokens.gradientOf(base);
        expect(_dHue(_hue(g[0]), _hue(base)), lessThan(8));
        expect(_dHue(_hue(g[1]), _hue(base)), lessThan(8));
      }
    });
  });

  group('Paleta de gráficos (oscura, validada)', () {
    test('6 tonos distintos, con color real, en el orden cian · rosa · ámbar · violeta · verde · coral', () {
      final c = AppTokens.dark.chart;
      expect(c.length, 6);
      expect(c.toSet().length, 6);
      const esperados = [190, 340, 38, 262, 158, 10];
      for (var i = 0; i < 6; i++) {
        expect(_dHue(_hue(c[i]), esperados[i].toDouble()), lessThan(20), reason: 'slot ${i + 1}');
        expect(HSLColor.fromColor(c[i]).saturation, greaterThan(0.45));
      }
    });

    test('los tipos de actividad reutilizan la paleta', () {
      final t = AppTokens.dark;
      expect(t.typeProyecto, t.chart[0]);
      expect(t.typeParcial, t.chart[2]);
      expect(t.typeRecurso, t.chart[4]);
      expect(t.typeOtro, t.chart[3]);
    });
  });

  group('Roles', () {
    test('cada rol tiene su gesto, ícono y color fijo (cian · violeta · rosa)', () {
      expect(roleStyleOf(RoleKind.student).motion, IconMotion.nod);
      expect(roleStyleOf(RoleKind.teacher).motion, IconMotion.float);
      expect(roleStyleOf(RoleKind.admin).motion, IconMotion.breathe);
      expect({for (final k in RoleKind.values) roleStyleOf(k).icon}.length, 3);
      expect(_dHue(_hue(roleStyleOf(RoleKind.student).color), 190), lessThan(15));
      expect(_dHue(_hue(roleStyleOf(RoleKind.teacher).color), 262), lessThan(15));
      expect(_dHue(_hue(roleStyleOf(RoleKind.admin).color), 340), lessThan(15));
    });

    test('los degradados de rol son del mismo matiz que el color del rol', () {
      for (final k in RoleKind.values) {
        final r = roleStyleOf(k);
        for (final c in r.gradient) {
          expect(_dHue(_hue(c), _hue(r.color)), lessThan(15), reason: r.label);
        }
      }
    });

    test('roleKindFromName entiende los nombres del servidor', () {
      expect(roleKindFromName('Admin'), RoleKind.admin);
      expect(roleKindFromName('Teacher'), RoleKind.teacher);
      expect(roleKindFromName('Student'), RoleKind.student);
      expect(roleKindFromName('otro'), isNull);
      expect(roleKindFromName(null), isNull);
      expect(roleGradientFromName('desconocido'), roleStyleOf(RoleKind.student).gradient);
    });

    testWidgets('RoleBadge muestra el ícono del rol, se anima y no lanza errores', (t) async {
      await t.pumpWidget(_app(const RoleBadge(role: RoleKind.admin)));
      await t.pump(const Duration(milliseconds: 500));
      await t.pump(const Duration(seconds: 2));
      expect(find.byType(MotionIcon), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('RoleBadge con foto muestra la foto en lugar del ícono', (t) async {
      final png = base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');
      await t.pumpWidget(_app(RoleBadge(role: RoleKind.teacher, photo: png)));
      await t.pump();
      expect(find.byType(Image), findsOneWidget);
      expect(find.byType(MotionIcon), findsNothing);
    });
  });

  group('Componentes sobre el tema Futurista', () {
    for (final tema in [AppThemeType.aurora, AppThemeType.medianoche, AppThemeType.oceano]) {
      testWidgets('indicadores, dona, barras y fondo se dibujan sin errores (${tema.name})', (t) async {
        final tk = tema.isDark ? AppTokens.dark : AppTokens.light;
        await t.pumpWidget(MaterialApp(
          theme: AppThemes.of(tema),
          home: AppBackground(
            type: tema,
            child: Scaffold(
              body: SingleChildScrollView(
                child: Column(children: [
                  PageHeader(title: 'Hola', subtitle: 'Resumen', leading: const RoleBadge(role: RoleKind.admin), chips: const []),
                  StatCard(icon: Icons.school, value: '6', label: 'Estudiantes', color: roleStyleOf(RoleKind.student).color, hint: '1.0 por materia'),
                  DonutChart(
                    slices: [
                      DonutSlice('A', 6, roleStyleOf(RoleKind.student).color),
                      DonutSlice('B', 3, roleStyleOf(RoleKind.teacher).color),
                      DonutSlice('C', 1, roleStyleOf(RoleKind.admin).color),
                    ],
                    centerValue: '10', centerLabel: 'usuarios', summary: 'x'),
                  BarList(color: tk.chart[0], items: const [BarItem('uno', 3), BarItem('dos', 1)]),
                  const SectionTitle('Título', icon: Icons.bar_chart, subtitle: 'sub'),
                ]),
              ),
            ),
          ),
        ));
        await t.pump(const Duration(milliseconds: 300));
        await t.pump(const Duration(seconds: 3));
        expect(t.takeException(), isNull);
        expect(find.text('Estudiantes'), findsOneWidget);
        expect(find.text('1.0 por materia'), findsOneWidget);
      });
    }

    testWidgets('la dona con una sola categoría o con valor 0 no falla', (t) async {
      await t.pumpWidget(_app(DonutChart(
        slices: [DonutSlice('Solo', 4, AppTokens.dark.chart[0])],
        centerValue: '4', centerLabel: 'x', summary: 'x')));
      await t.pump(const Duration(seconds: 2));
      await t.pumpWidget(_app(DonutChart(
        slices: [DonutSlice('Nada', 0, AppTokens.dark.chart[0])],
        centerValue: '0', centerLabel: 'x', summary: 'x')));
      await t.pump(const Duration(seconds: 2));
      expect(t.takeException(), isNull);
    });
  });

  group('Movimiento de íconos', () {
    test('los gestos nuevos tienen ciclo propio y respetan la velocidad', () {
      expect(MotionIcon.periodo(IconMotion.breathe), const Duration(milliseconds: 3800));
      expect(MotionIcon.periodo(IconMotion.nod), const Duration(milliseconds: 3600));
      expect(MotionIcon.periodo(IconMotion.nod, 2), const Duration(milliseconds: 1800));
    });

    testWidgets('breathe y nod se animan sin excepciones', (t) async {
      await t.pumpWidget(_app(const Wrap(children: [
        MotionIcon(Icons.shield, motion: IconMotion.breathe, halo: true),
        MotionIcon(Icons.school, motion: IconMotion.nod, speed: 1.7),
      ])));
      await t.pump(const Duration(milliseconds: 500));
      for (var i = 0; i < 8; i++) {
        await t.pump(const Duration(milliseconds: 600));
      }
      expect(t.takeException(), isNull);
    });
  });
}
