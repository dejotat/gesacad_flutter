import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gesacad/config/app_themes.dart';
import 'package:gesacad/models/semaforo_models.dart';
import 'package:gesacad/screens/academic/semaforo_screen.dart';
import 'package:gesacad/screens/login_screen.dart';
import 'package:gesacad/services/settings_service.dart';

Map<String, dynamic> _materia(int id, String nombre, int sem, String area, String estado,
        {int cred = 3, double? nota, double? parcial, List<Map<String, dynamic>> req = const [], List<int> faltan = const []}) =>
    {
      'courseId': id, 'name': nombre, 'code': 'C$id', 'semester': sem, 'credits': cred, 'area': area,
      'prerequisites': req, 'missingPrerequisites': faltan, 'status': estado, 'grade': nota,
      'suggestedGrade': parcial, 'updatedAt': null,
    };

final _datos = {
  'student': {'id': 7, 'name': 'ana', 'program': 'Ingeniería de Sistemas'},
  'minApprove': 3.0,
  'summary': {
    'approved': 1, 'inProgress': 1, 'failed': 1, 'cancelled': 1, 'pending': 1, 'blocked': 1, 'total': 6,
    'approvedCredits': 4, 'totalCredits': 18, 'average': 4.2,
  },
  'courses': [
    _materia(1, 'Cálculo Diferencial', 1, 'basica', 'approved', cred: 4, nota: 4.2),
    _materia(2, 'Álgebra Lineal', 2, 'basica', 'in_progress', parcial: 3.8),
    _materia(3, 'Física I', 1, 'basica', 'failed', nota: 2.1),
    _materia(4, 'Inglés I', 1, 'complementaria', 'cancelled'),
    _materia(5, 'Cálculo Integral', 2, 'basica', 'blocked', req: [{'id': 3, 'name': 'Física I'}], faltan: [3]),
    _materia(6, 'Electiva', 3, 'especifica', 'pending'),
  ],
};

Future<http.Response> _servidor(http.Request r) async {
  if (r.url.path.endsWith('/semaforo') && r.method == 'GET') {
    return http.Response(jsonEncode(_datos), 200, headers: {'content-type': 'application/json'});
  }
  if (r.method == 'PUT') {
    return http.Response(jsonEncode({'status': 'approved', 'grade': 4.0}), 200, headers: {'content-type': 'application/json'});
  }
  return http.Response('{}', 404);
}

Future<void> _grande(WidgetTester t, {Size tam = const Size(1100, 1300)}) async {
  t.view.physicalSize = tam;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

/// Avanza el reloj de pruebas (no se usa pumpAndSettle: el fondo de la app anima sin parar).
Future<void> _esperar(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 150));
  }
}

Widget _pantalla(String rol, {Set<int> suyas = const {}}) => MaterialApp(
    theme: AppThemes.of(AppThemeType.neon),
    home: SemaforoScreen(studentId: 7, rol: rol, teacherCourseIds: suyas));

void main() {
  setUpAll(() async => initializeDateFormatting('es', null));

  test('el modelo interpreta los estados del servidor', () {
    final s = Semaforo.fromJson(_datos);
    expect(s.courses.map((c) => c.status), [
      EstadoMateria.approved, EstadoMateria.inProgress, EstadoMateria.failed,
      EstadoMateria.cancelled, EstadoMateria.blocked, EstadoMateria.pending,
    ]);
    expect(s.semestres, [1, 2, 3]);
    expect(s.summary.average, 4.2);
    expect(s.courses[4].missingPrerequisites, [3]);
  });

  testWidgets('muestra la leyenda, las áreas y una tarjeta por materia con su estado', (t) async {
    SharedPreferences.setMockInitialValues({});
    await _grande(t);
    await http.runWithClient(() async {
      await t.pumpWidget(_pantalla('Student'));
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      for (final e in ['En curso', 'Aprobada', 'Reprobada', 'Cancelada', 'Pre-requisito', 'Pendiente']) {
        expect(find.text(e), findsWidgets, reason: 'leyenda: $e');
      }
      for (final a in ['BÁSICA', 'COMPLEMENTARIA', 'ESPECÍFICA']) {
        expect(find.text(a), findsOneWidget);
      }
      expect(find.text('Cálculo Diferencial'), findsOneWidget);
      expect(find.text('Definitiva: 4.2'), findsOneWidget);
      expect(find.text('En curso · parcial 3.8'), findsOneWidget);
      expect(find.text('Falta pre-requisito'), findsOneWidget);
      expect(find.text('4 Cr.'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    }, () => MockClient(_servidor));
  });

  testWidgets('el estudiante solo mira: la ficha de la materia no ofrece registrar ni corregir', (t) async {
    SharedPreferences.setMockInitialValues({});
    await _grande(t);
    await http.runWithClient(() async {
      await t.pumpWidget(_pantalla('Student'));
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      await t.tap(find.text('Álgebra Lineal'));
      await _esperar(t);
      expect(find.text('Código C2'), findsOneWidget);
      expect(find.textContaining('Promedio parcial'), findsOneWidget);
      expect(find.text('Registrar nota definitiva'), findsNothing);
      expect(find.text('Corrección excepcional'), findsNothing);
      await t.pumpWidget(const SizedBox());
    }, () => MockClient(_servidor));
  });

  testWidgets('el docente registra la nota solo en SUS materias', (t) async {
    SharedPreferences.setMockInitialValues({});
    await _grande(t);
    var enviada = false;
    await http.runWithClient(() async {
      await t.pumpWidget(_pantalla('Teacher', suyas: {2}));
      await t.pump();
      await t.pump(const Duration(seconds: 1));

      await t.tap(find.text('Cálculo Diferencial')); // no es suya
      await _esperar(t);
      expect(find.text('Registrar nota definitiva'), findsNothing);
      await t.tapAt(const Offset(10, 10)); // cierra la hoja
      await _esperar(t);

      await t.tap(find.text('Álgebra Lineal')); // sí es suya
      await _esperar(t);
      expect(find.text('Registrar nota definitiva'), findsOneWidget);
      await t.enterText(find.byType(TextField).first, '9');
      await t.tap(find.text('Registrar nota'));
      await _esperar(t);
      expect(find.text('Escribe una nota entre 0 y 5.'), findsOneWidget, reason: 'se valida antes de enviar');
      await t.enterText(find.byType(TextField).first, '4,0');
      await t.tap(find.text('Registrar nota'));
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      await t.pumpWidget(const SizedBox());
    }, () => MockClient((r) {
          if (r.method == 'PUT') {
            enviada = true;
            expect(r.url.path, '/estudiantes/7/semaforo/2/nota');
            expect(jsonDecode(r.body), {'grade': 4.0});
          }
          return _servidor(r);
        }));
    expect(enviada, isTrue);
  });

  testWidgets('el admin necesita nota y motivo, y tiene el historial a mano', (t) async {
    SharedPreferences.setMockInitialValues({});
    await _grande(t);
    await http.runWithClient(() async {
      await t.pumpWidget(_pantalla('Admin'));
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      expect(find.byTooltip('Historial de cambios'), findsOneWidget);
      await t.tap(find.text('Física I'));
      await _esperar(t);
      expect(find.text('Corrección excepcional'), findsOneWidget);
      await t.ensureVisible(find.text('Guardar corrección'));
      await t.tap(find.text('Guardar corrección'));
      await _esperar(t);
      expect(find.textContaining('Escribe el motivo'), findsOneWidget, reason: 'la nota ya viene rellena; falta el motivo');
      await t.pumpWidget(const SizedBox());
    }, () => MockClient(_servidor));
  });

  for (final tam in const [Size(1100, 1300), Size(420, 900)]) {
    testWidgets('accesibilidad del semáforo (${tam.width.toInt()} px): etiquetas y áreas táctiles', (t) async {
      SharedPreferences.setMockInitialValues({});
      await _grande(t, tam: tam);
      final h = t.ensureSemantics();
      await http.runWithClient(() async {
        await t.pumpWidget(_pantalla('Admin'));
        await t.pump();
        await t.pump(const Duration(seconds: 1));
        await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(t, meetsGuideline(androidTapTargetGuideline));
        await t.pumpWidget(const SizedBox());
      }, () => MockClient(_servidor));
      h.dispose();
    });
  }

  group('Mensaje de error del inicio de sesión', () {
    Future<void> intentar(WidgetTester t, http.Response Function(http.Request) servidor) async {
      SharedPreferences.setMockInitialValues({});
      await _grande(t, tam: const Size(1000, 1400));
      await http.runWithClient(() async {
        await t.pumpWidget(MaterialApp(theme: ThemeData.light(), home: const LoginScreen()));
        await t.pump(const Duration(seconds: 2));
        await t.enterText(find.byType(TextFormField).first, 'ana');
        await t.enterText(find.byType(TextFormField).last, 'ClaveMala1\$');
        // Enviar con «Intro» desde el campo de contraseña (igual que el botón).
        await t.testTextInput.receiveAction(TextInputAction.done);
        for (var i = 0; i < 15; i++) {
          await t.pump(const Duration(milliseconds: 200));
        }
      }, () => MockClient((r) async => r.url.path == '/health' ? http.Response('{"status":"ok"}', 200) : servidor(r)));
    }

    testWidgets('credenciales incorrectas: UNA frase clara, sin servidor ni detalles internos', (t) async {
      await intentar(t, (r) => http.Response(
          jsonEncode({'error': 'CREDENCIALES_INVALIDAS', 'response': 'USER_OR_PASS_INVALID', 'message': 'Usuario o contraseña incorrectos.'}),
          401, headers: {'content-type': 'application/json'}));
      expect(find.text('Usuario o contraseña incorrectos.'), findsOneWidget);
      expect(find.textContaining('Servidor'), findsNothing);
      expect(find.textContaining('onrender'), findsNothing);
      expect(find.textContaining('http'), findsNothing);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('un servidor que sí distingue «no existe» muestra el mensaje de cuenta inexistente', (t) async {
      await intentar(t, (r) => http.Response(jsonEncode({'response': 'USER_NOT_FOUND'}), 401, headers: {'content-type': 'application/json'}));
      expect(find.text('No encontramos una cuenta con ese usuario.'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });
  });
}
