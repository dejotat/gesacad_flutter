import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gesacad/config/app_tokens.dart';
import 'package:gesacad/models/course_model.dart';
import 'package:gesacad/screens/calendar/calendar_screen.dart';
import 'package:gesacad/screens/notifications/notifications_panel.dart';
import 'package:gesacad/widgets/course_card.dart';
import 'package:gesacad/widgets/ui/ui.dart';

/// Pruebas de render de los widgets con movimiento: que construyan, animen
/// varios fotogramas y respondan al toque sin excepciones ni desbordes.
Widget _app(Widget child) => MaterialApp(
      theme: ThemeData(extensions: const [AppTokens.light]),
      home: Scaffold(body: child),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('AppButton responde al toque y muestra el brillo', (t) async {
    var n = 0;
    await t.pumpWidget(_app(Center(
      child: AppButton(label: 'Guardar', icon: Icons.save, onPressed: () => n++),
    )));
    await t.pump(const Duration(milliseconds: 600));
    await t.tap(find.text('Guardar'));
    await t.pump(const Duration(milliseconds: 300));
    expect(n, 1);
    await t.pump(const Duration(seconds: 2));
  });

  testWidgets('AnimatedIconButton: todas las reacciones renderizan', (t) async {
    await t.pumpWidget(_app(Wrap(children: [
      for (final r in IconReaction.values)
        AnimatedIconButton(
            icon: Icons.star, tooltip: r.name, reaction: r, badge: 3,
            onPressed: () {}),
    ])));
    for (final r in IconReaction.values) {
      await t.tap(find.byTooltip(r.name));
      await t.pump(const Duration(milliseconds: 200));
    }
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('MotionIcon e IconMedallion: todos los movimientos', (t) async {
    await t.pumpWidget(_app(Wrap(children: [
      for (final m in IconMotion.values)
        IconMedallion(Icons.school,
            colors: const [Colors.blue, Colors.cyan], motion: m, ping: true),
    ])));
    await t.pump(const Duration(milliseconds: 500));
    await t.pump(const Duration(seconds: 3));
  });

  testWidgets('LogoBackdrop anima sin excepciones', (t) async {
    await t.pumpWidget(_app(const LogoBackdrop(child: Text('contenido'))));
    await t.pump(const Duration(seconds: 2));
    expect(find.text('contenido'), findsOneWidget);
  });

  testWidgets('CourseCard con acciones', (t) async {
    await t.pumpWidget(_app(SizedBox(
      width: 260, height: 220,
      child: CourseCard(
        course: CourseModel(id: 1, name: 'Programación', courseCode: 'PRG-1', imgCourse: 1),
        onTap: () {}, onEdit: () {}, onDelete: () {},
      ),
    )));
    await t.pump(const Duration(seconds: 2));
    expect(find.text('Programación'), findsOneWidget);
  });

  testWidgets('NotificationsPanel sin sesión muestra estado vacío', (t) async {
    await t.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: const [AppTokens.light]),
      home: const NotificationsPanel(),
    ));
    await t.pump(const Duration(seconds: 1));
    expect(find.textContaining('Sin notificaciones'), findsOneWidget);
  });

  testWidgets('CalendarScreen renderiza festivos y cambia de día', (t) async {
    await initializeDateFormatting('es_ES');
    await t.binding.setSurfaceSize(const Size(420, 900));
    await t.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: const [AppTokens.light]),
      home: const CalendarScreen(),
    ));
    await t.pump(const Duration(seconds: 1));
    await t.tap(find.byTooltip('Ir a hoy'));
    await t.pump(const Duration(seconds: 1));
    await t.tap(find.text('Examen'));
    await t.pump(const Duration(seconds: 1));
    await t.binding.setSurfaceSize(null);
  });
}
