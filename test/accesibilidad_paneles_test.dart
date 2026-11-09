// Accesibilidad de los tres dashboards (Admin, Docente, Estudiante) con un servidor vacío:
// todo lo que se toca tiene etiqueta y un área táctil de al menos 48 dp.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gesacad/config/app_themes.dart';
import 'package:gesacad/screens/admin/admin_home.dart';
import 'package:gesacad/screens/student/student_home.dart';
import 'package:gesacad/screens/teacher/teacher_home.dart';
import 'package:gesacad/services/settings_service.dart';

Future<http.Response> _vacio(http.Request r) async =>
    http.Response(r.method == 'GET' && !r.url.path.contains('Quantity') ? '[]' : '{}', 200,
        headers: {'content-type': 'application/json'});

void main() {
  setUpAll(() async => initializeDateFormatting('es', null));

  // Ancho (menú lateral fijo) y estrecho (menú en un cajón): ambos deben ser accesibles.
  for (final tam in const [Size(1100, 1300), Size(420, 1000)])
  for (final entrada in {'Admin': () => const AdminHome(), 'Teacher': () => const TeacherHome(), 'Student': () => const StudentHome()}.entries) {
    testWidgets('Panel de ${entrada.key} (${tam.width.toInt()} px): etiquetas y áreas táctiles', (t) async {
      SharedPreferences.setMockInitialValues({'userId': 1, 'userName': 'Jorge', 'userRol': entrada.key});
      t.view.physicalSize = tam;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final h = t.ensureSemantics();
      await http.runWithClient(() async {
        await t.pumpWidget(MaterialApp(theme: AppThemes.of(AppThemeType.aurora), home: entrada.value()));
        await t.pump();
        await t.pump(const Duration(seconds: 2));
        await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(t, meetsGuideline(androidTapTargetGuideline));
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(seconds: 1));
      }, () => MockClient(_vacio));
      h.dispose();
    });
  }
}
