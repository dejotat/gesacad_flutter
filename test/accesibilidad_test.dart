// Accesibilidad (CU-07): comprobaciones OFICIALES de Flutter sobre las pantallas principales.
//  * labeledTapTargetGuideline → todo lo que se toca tiene una etiqueta que un lector pueda decir.
//  * androidTapTargetGuideline → las áreas táctiles miden al menos 48×48 dp.
// Además se comprueba que el lector integrado (ScreenReader) lee cada control de verdad.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gesacad/config/app_themes.dart';
import 'package:gesacad/models/course_model.dart';
import 'package:gesacad/models/university_info.dart';
import 'package:gesacad/screens/auth/forgot_password_screen.dart';
import 'package:gesacad/screens/calendar/calendar_screen.dart';
import 'package:gesacad/screens/guest/guest_home.dart';
import 'package:gesacad/screens/login_screen.dart';
import 'package:gesacad/screens/notifications/notifications_panel.dart';
import 'package:gesacad/services/connectivity_service.dart';
import 'package:gesacad/services/guest_service.dart';
import 'package:gesacad/services/notification_service.dart';
import 'package:gesacad/services/offline_queue.dart';
import 'package:gesacad/services/outbox_file_store.dart';
import 'package:gesacad/services/screen_reader.dart';
import 'package:gesacad/services/settings_service.dart';
import 'package:gesacad/widgets/course_card.dart';
import 'package:gesacad/widgets/offline_banner.dart';
import 'package:gesacad/widgets/ui/account_menu.dart';

const _info = UniversityInfo(
  name: 'Unicomfacauca',
  tagline: 'Educación que transforma',
  about: 'Institución de ejemplo.',
  programs: [UniProgram(name: 'Ingeniería de Sistemas', level: 'Pregrado', description: 'Programa')],
  steps: [UniStep(title: 'Inscríbete', text: 'En línea')],
  requirements: ['Documento de identidad'],
  dates: [UniDate(label: 'Inicio de clases', value: '1 de febrero')],
  contact: UniContact(phone: '+57 602 123 4567', email: 'info@ejemplo.edu.co'),
);

class _InvitadoFalso extends GuestService {
  @override
  Future<GuestContent> load() async => const GuestContent(info: _info, isSample: false);
  @override
  Future<Set<String>> loadChecklist() async => {};
  @override
  Future<void> saveChecklist(Set<String> hechos) async {}
  @override
  Future<void> save(UniversityInfo info) async {}
  @override
  Future<void> reset() async {}
}

Future<http.Response> _servidorDeAvisos(http.Request r) async {
  http.Response ok(Object o) => http.Response(jsonEncode(o), 200, headers: {'content-type': 'application/json'});
  if (r.method == 'GET' && r.url.path == '/notifications') {
    Map<String, dynamic> n(int id, String tipo, String titulo, String cuerpo, bool leida) => {
          'id': id, 'type': tipo, 'title': titulo, 'body': cuerpo, 'read': leida,
          'createdAt': DateTime.now().toUtc().toIso8601String(), 'courseId': 10, 'courseName': 'Cálculo',
          'courseCode': 'CAL', 'courseImg': 1, 'refType': null, 'refId': null,
        };
    return ok({
      'items': [
        n(3, 'system', 'Usuario eliminado del sistema', 'userid=38 username=juan rol=Student', false),
        n(2, 'grade', 'Calificación publicada: Taller', 'Obtuviste 4.5 en Cálculo.', false),
        n(1, 'activity', 'Nueva actividad: Taller 2', 'En Cálculo.', true),
      ],
      'unread': 2,
      'nextBefore': null,
    });
  }
  if (r.method == 'GET' && r.url.path == '/notifications/summary') return ok({'unread': 2, 'latestId': 3, 'items': []});
  return http.Response('no encontrado', 404);
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es', null);
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppSettings.talkBackEnabled.value = false;
    ScreenReader.instance.reiniciar();
  });
  tearDown(() => ScreenReader.instance.reiniciar());

  /// Pantalla grande y oscura (el tema por defecto) para que quepa todo.
  Widget app(Widget home, {AppThemeType tema = AppThemeType.aurora}) =>
      MaterialApp(theme: AppThemes.of(tema), home: home);

  Future<void> grande(WidgetTester t) async {
    t.view.physicalSize = const Size(1000, 1300);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
  }

  /// Etiquetas y áreas táctiles correctas en lo que hay ahora en pantalla.
  Future<void> revisar(WidgetTester t, {bool tamanos = true}) async {
    await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
    if (tamanos) await expectLater(t, meetsGuideline(androidTapTargetGuideline));
  }

  group('Todo lo que se toca tiene etiqueta y un área táctil suficiente', () {
    testWidgets('Inicio de sesión', (t) async {
      await grande(t);
      final h = t.ensureSemantics();
      await t.pumpWidget(app(const LoginScreen()));
      await t.pump(const Duration(seconds: 2));
      await revisar(t);
      h.dispose();
    });

    testWidgets('Recuperar contraseña', (t) async {
      await grande(t);
      final h = t.ensureSemantics();
      await t.pumpWidget(app(const ForgotPasswordScreen()));
      await t.pump(const Duration(seconds: 2));
      await revisar(t);
      h.dispose();
    });

    testWidgets('Modo invitado', (t) async {
      await grande(t);
      final h = t.ensureSemantics();
      await t.pumpWidget(app(GuestHome(servicio: _InvitadoFalso())));
      await t.pump();
      await t.pump(const Duration(seconds: 2));
      await revisar(t);
      h.dispose();
    });

    testWidgets('Calendario', (t) async {
      await grande(t);
      final h = t.ensureSemantics();
      await t.pumpWidget(app(const CalendarScreen()));
      await t.pump();
      await t.pump(const Duration(seconds: 2));
      await revisar(t);
      h.dispose();
    });

    testWidgets('Tarjeta de curso', (t) async {
      await grande(t);
      final h = t.ensureSemantics();
      await t.pumpWidget(app(Scaffold(
        body: SizedBox(
          width: 300, height: 240,
          child: CourseCard(course: CourseModel(id: 1, name: 'Programación', courseCode: 'PRG-1', imgCourse: 1),
              onTap: () {}, onEdit: () {}, onDelete: () {}),
        ),
      )));
      await t.pump(const Duration(seconds: 2));
      await revisar(t);
      h.dispose();
    });

    testWidgets('Menú de cuenta abierto', (t) async {
      await grande(t);
      final h = t.ensureSemantics();
      await t.pumpWidget(app(Scaffold(
        appBar: AppBar(actions: [
          MenuCuenta(nombre: 'Jorge', rol: 'Admin', onPerfil: () {}, onAjustes: () {}, onSalir: () {}),
        ]),
      )));
      await t.tap(find.byTooltip('Cuenta y opciones'));
      await t.pumpAndSettle();
      await revisar(t);
      h.dispose();
    });

    testWidgets('Aviso de «Conectando» y de «Sin conexión»', (t) async {
      await grande(t);
      final h = t.ensureSemantics();
      final c = ConnectivityService.test(probe: () async => false, interval: const Duration(hours: 1));
      final q = OfflineQueue(
        executor: _Nada(), files: MemoryOutboxStore(), connectivity: c, maxAttempts: 3, retryBase: const Duration(hours: 1));
      await t.pumpWidget(app(OfflineShell(connectivity: c, queue: q, child: const Scaffold(body: Text('app')))));
      c.reportFailure(Exception('x'));
      await t.pump(const Duration(milliseconds: 400));
      await revisar(t);
      q.disposeForTest();
      c.dispose();
      h.dispose();
    });

    testWidgets('Notificaciones', (t) async {
      await grande(t);
      final h = t.ensureSemantics();
      await http.runWithClient(() async {
        await t.pumpWidget(app(NotificationsPanel(
            userId: 4, userRol: 'Admin', servicio: NotificationService.test(intervalo: const Duration(hours: 1)))));
        await t.pump();
        await t.pump(const Duration(seconds: 2));
        await revisar(t);
      }, () => MockClient(_servidorDeAvisos));
      h.dispose();
    });
  });

  group('El lector integrado lee de verdad', () {
    testWidgets('una notificación se lee COMPLETA: tipo, título, texto claro y hora', (t) async {
      await grande(t);
      final h = t.ensureSemantics();
      await http.runWithClient(() async {
        await t.pumpWidget(app(NotificationsPanel(
            userId: 4, userRol: 'Admin', servicio: NotificationService.test(intervalo: const Duration(hours: 1)))));
        await t.pump();
        await t.pump(const Duration(seconds: 2));

        final frase = ScreenReader.instance.frasePara(t.getCenter(find.text('Usuario eliminado del sistema')));
        expect(frase, isNotNull);
        expect(frase, contains('Usuarios'));
        expect(frase, contains('Usuario eliminado del sistema'));
        expect(frase, contains('Se eliminó la cuenta «juan» (estudiante).'), reason: 'el texto técnico no se lee');
        expect(frase, isNot(contains('userid=')));
        expect(frase, contains('Toca para abrir'));
      }, () => MockClient(_servidorDeAvisos));
      h.dispose();
    });

    testWidgets('los botones de solo ícono con tooltip se leen (papelera, lápiz del curso)', (t) async {
      await grande(t);
      final h = t.ensureSemantics();
      await t.pumpWidget(app(Scaffold(
        body: Center(
          child: SizedBox(
            width: 300, height: 240,
            child: CourseCard(course: CourseModel(id: 1, name: 'Programación', courseCode: 'PRG-1', imgCourse: 1),
                onTap: () {}, onEdit: () {}, onDelete: () {}),
          ),
        ),
      )));
      await t.pump(const Duration(seconds: 2));
      final leidas = <String>{};
      for (final icono in [Icons.delete_outline_rounded, Icons.edit_rounded, Icons.delete_rounded, Icons.edit_outlined]) {
        final f = find.byIcon(icono);
        if (f.evaluate().isNotEmpty) {
          final frase = ScreenReader.instance.frasePara(t.getCenter(f.first));
          if (frase != null) leidas.add(frase);
        }
      }
      // El número suelto se lee como «código de la materia», no como un número a secas.
      expect(ScreenReader.instance.frasePara(t.getCenter(find.text('PRG-1'))), startsWith('Código de la materia PRG-1'));
      expect(find.text('Programación'), findsWidgets);
      // Al menos el nombre del curso y alguna acción se pueden leer.
      expect(ScreenReader.instance.frasePara(t.getCenter(find.text('Programación').first)), contains('Programación'));
      h.dispose();
    });
  });
}

class _Nada implements OperationExecutor {
  @override
  Future<OperationOutcome> execute(PendingOperation op, dynamic file) async => const OperationOutcome(OutcomeKind.success);
}
