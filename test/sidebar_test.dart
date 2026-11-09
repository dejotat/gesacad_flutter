import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:gesacad/config/app_themes.dart';
import 'package:gesacad/services/settings_service.dart';
import 'package:gesacad/widgets/ui/app_sidebar.dart';
import 'package:gesacad/widgets/course_grid.dart';

SidebarNav _nav({VoidCallback? salir}) => SidebarNav(
      rol: 'Student',
      nombre: 'Ana María',
      onSalir: salir ?? () {},
      items: [
        const NavItem(id: 'inicio', icon: PhosphorIconsRegular.house, label: 'Inicio'),
        NavItem(
            id: 'perfil',
            icon: PhosphorIconsRegular.userCircle,
            label: 'Mi perfil',
            destination: () => const Scaffold(body: Text('PANTALLA PERFIL'))),
      ],
    );

Widget _app(SidebarNav nav, {String activo = 'inicio'}) => MaterialApp(
      theme: AppThemes.of(AppThemeType.neon),
      home: Builder(
        builder: (c) => AppShell(
          nav: nav,
          activo: activo,
          child: Scaffold(
            drawer: nav.cajon(c, activo),
            appBar: AppBar(title: const Text('Panel')),
            body: const Text('PANTALLA INICIO'),
          ),
        ),
      ),
    );

void main() {
  testWidgets('pantalla ancha: menú fijo con la entrada activa; al abrir otra sección el menú sigue y «Inicio» vuelve',
      (t) async {
    t.view.physicalSize = const Size(1200, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final h = t.ensureSemantics();
    await t.pumpWidget(_app(_nav()));
    await t.pump(const Duration(milliseconds: 300));

    expect(find.byType(AppSidebar), findsOneWidget);
    expect(find.text('Mi perfil'), findsOneWidget);
    expect(find.text('Cerrar sesión'), findsOneWidget);
    expect(find.byType(Drawer), findsNothing, reason: 'en pantalla ancha no hay cajón');
    expect(t.getSemantics(find.text('Inicio')).flagsCollection.isSelected.name, 'isTrue');

    await t.tap(find.text('Mi perfil'));
    await t.pumpAndSettle();
    expect(find.text('PANTALLA PERFIL'), findsOneWidget);
    expect(find.byType(AppSidebar), findsOneWidget, reason: 'el menú sigue visible en la otra sección');
    expect(t.getSemantics(find.text('Mi perfil')).flagsCollection.isSelected.name, 'isTrue');

    await t.tap(find.text('Inicio'));
    await t.pumpAndSettle();
    expect(find.text('PANTALLA INICIO'), findsOneWidget);
    h.dispose();
  });

  testWidgets('pantalla estrecha: el mismo menú vive en un cajón y «Cerrar sesión» funciona', (t) async {
    t.view.physicalSize = const Size(420, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    var salio = false;
    await t.pumpWidget(_app(_nav(salir: () => salio = true)));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byType(AppSidebar), findsNothing);

    await t.tap(find.byTooltip('Open navigation menu').evaluate().isNotEmpty
        ? find.byTooltip('Open navigation menu')
        : find.byType(DrawerButton));
    await t.pumpAndSettle();
    expect(find.byType(AppSidebar), findsOneWidget);
    expect(find.text('Mi perfil'), findsOneWidget);

    await t.tap(find.text('Cerrar sesión'));
    await t.pumpAndSettle();
    expect(salio, isTrue);
  });

  testWidgets('cuadrícula de cursos: todas las tarjetas del mismo tamaño y alineadas con el panel', (t) async {
    t.view.physicalSize = const Size(1400, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CustomScrollView(slivers: [
          SliverCourseGrid(count: 5, itemBuilder: (i) => Container(key: ValueKey('c$i'), color: Colors.teal)),
        ]),
      ),
    ));
    await t.pump(const Duration(seconds: 2));
    final tam = {for (var i = 0; i < 5; i++) t.getSize(find.byKey(ValueKey('c$i')))};
    expect(tam.length, 1, reason: 'todas del mismo tamaño');
    // Mismo margen izquierdo que un panel centrado en 1100 px con 16 de relleno.
    expect(t.getTopLeft(find.byKey(const ValueKey('c0'))).dx, (1400 - 1100) / 2 + 16);
  });
}
