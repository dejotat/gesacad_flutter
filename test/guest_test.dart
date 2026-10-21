import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gesacad/config/app_tokens.dart';
import 'package:gesacad/models/university_info.dart';
import 'package:gesacad/screens/admin/admin_university_info.dart';
import 'package:gesacad/screens/guest/guest_home.dart';
import 'package:gesacad/services/api_service.dart' show ApiMessageException;
import 'package:gesacad/services/guest_service.dart';

const _info = UniversityInfo(
  name: 'Unicomfacauca',
  tagline: 'Educación que transforma',
  about: 'Somos una institución de ejemplo para las pruebas.',
  programs: [UniProgram(name: 'Ingeniería de Sistemas', level: 'Pregrado', description: 'Programa de prueba')],
  steps: [UniStep(title: 'Inscríbete', text: 'En línea'), UniStep(title: 'Paga', text: 'En el banco')],
  requirements: ['Documento de identidad', 'Diploma de bachiller'],
  dates: [UniDate(label: 'Inicio de clases', value: '1 de febrero')],
  contact: UniContact(phone: '+57 602 123 4567', email: 'info@ejemplo.edu.co'),
);

class _Falso extends GuestService {
  _Falso({this.contenido = const GuestContent(info: _info, isSample: false)});
  GuestContent contenido;
  Object? falla;
  Set<String> lista = {};
  UniversityInfo? guardado;
  int reinicios = 0;

  @override
  Future<GuestContent> load() async => contenido;

  @override
  Future<Set<String>> loadChecklist() async => {...lista};

  @override
  Future<void> saveChecklist(Set<String> hechos) async => lista = {...hechos};

  @override
  Future<void> save(UniversityInfo info) async {
    if (falla != null) throw falla!;
    guardado = info;
  }

  @override
  Future<void> reset() async => reinicios++;
}

Future<void> espera(WidgetTester t, [int ms = 500]) async {
  await t.pump();
  await t.pump(Duration(milliseconds: ms));
}

Widget _app(Widget home) => MaterialApp(theme: ThemeData(extensions: const [AppTokens.light]), home: home);

Future<void> _salir(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 1));
}

void main() {
  group('Modelo', () {
    test('lee el contenido del servidor y descarta lo que no entiende', () {
      final i = UniversityInfo.fromJson({
        'name': 'Uni', 'programs': [{'name': 'A', 'level': 'Pregrado'}, 'basura', 7],
        'enrollment': {'steps': [{'title': 'P1'}], 'requirements': ['R1', 2], 'dates': [{'label': 'L', 'value': 'V'}]},
        'contact': {'phone': '123'},
      });
      expect(i.name, 'Uni');
      expect(i.programs.map((p) => p.name), ['A']);
      expect(i.steps.single.title, 'P1');
      expect(i.requirements, ['R1', '2']);
      expect(i.contact.phone, '123');
      expect(i.contact.isEmpty, isFalse);
    });

    test('ida y vuelta por JSON', () {
      final otra = UniversityInfo.fromJson(_info.toJson());
      expect(otra.toJson(), _info.toJson());
    });

    test('un JSON vacío no rompe', () {
      final i = UniversityInfo.fromJson({});
      expect(i.name, 'Universidad');
      expect(i.programs, isEmpty);
      expect(i.contact.isEmpty, isTrue);
    });
  });

  group('Modo invitado', () {
    testWidgets('Inicio: muestra la universidad, los perfiles y la ayuda de matrícula', (t) async {
      await t.binding.setSurfaceSize(const Size(500, 1400));
      await t.pumpWidget(_app(GuestHome(servicio: _Falso())));
      await espera(t, 700);
      expect(find.text('Modo invitado'), findsOneWidget);
      expect(find.text('Unicomfacauca'), findsOneWidget);
      expect(find.text('Educación que transforma'), findsOneWidget);
      expect(find.text('Estás explorando como invitado'), findsOneWidget);
      for (final r in ['Estudiante', 'Docente', 'Admin']) {
        expect(find.text(r), findsWidgets);
      }
      expect(find.text('Iniciar sesión'), findsOneWidget);
      await _salir(t);
      await t.binding.setSurfaceSize(null);
    });

    testWidgets('Universidad: programas, pasos, fechas y contacto', (t) async {
      await t.binding.setSurfaceSize(const Size(500, 2400));
      await t.pumpWidget(_app(GuestHome(servicio: _Falso())));
      await espera(t, 700);
      await t.tap(find.text('Universidad').last);
      await espera(t, 700);
      expect(find.text('Ingeniería de Sistemas'), findsOneWidget);
      expect(find.text('Paso 1: Inscríbete'), findsOneWidget);
      expect(find.text('Paso 2: Paga'), findsOneWidget);
      expect(find.text('Inicio de clases'), findsOneWidget);
      expect(find.text('+57 602 123 4567'), findsOneWidget);
      expect(find.text('info@ejemplo.edu.co'), findsOneWidget);
      expect(find.textContaining('de ejemplo: la universidad'), findsNothing, reason: 'el contenido es real');
      await _salir(t);
      await t.binding.setSurfaceSize(null);
    });

    testWidgets('marcar requisitos actualiza el avance y se guarda', (t) async {
      await t.binding.setSurfaceSize(const Size(500, 2400));
      final servicio = _Falso();
      await t.pumpWidget(_app(GuestHome(servicio: servicio)));
      await espera(t, 700);
      await t.tap(find.text('Universidad').last);
      await espera(t, 700);
      expect(find.text('0/2'), findsOneWidget);

      await t.tap(find.text('Documento de identidad'));
      await espera(t);
      expect(find.text('1/2'), findsOneWidget);
      expect(servicio.lista, {'Documento de identidad'});

      await t.tap(find.text('Diploma de bachiller'));
      await espera(t);
      expect(find.text('¡Tienes todos los requisitos listos!'), findsOneWidget);

      await t.tap(find.text('Documento de identidad'));
      await espera(t);
      expect(find.text('1/2'), findsOneWidget);
      await _salir(t);
      await t.binding.setSurfaceSize(null);
    });

    testWidgets('recuerda los requisitos marcados de una visita anterior', (t) async {
      await t.binding.setSurfaceSize(const Size(500, 2400));
      final servicio = _Falso()..lista = {'Diploma de bachiller'};
      await t.pumpWidget(_app(GuestHome(servicio: servicio)));
      await espera(t, 700);
      await t.tap(find.text('Universidad').last);
      await espera(t, 700);
      expect(find.text('1/2'), findsOneWidget);
      await _salir(t);
      await t.binding.setSurfaceSize(null);
    });

    testWidgets('avisa cuando la información es de ejemplo o está sin conexión', (t) async {
      await t.binding.setSurfaceSize(const Size(500, 2400));
      final ejemplo = _Falso(contenido: const GuestContent(info: _info, isSample: true));
      await t.pumpWidget(_app(GuestHome(servicio: ejemplo)));
      await espera(t, 700);
      await t.tap(find.text('Universidad').last);
      await espera(t, 700);
      expect(find.textContaining('es de ejemplo'), findsOneWidget);
      await _salir(t);

      final sinRed = _Falso(contenido: const GuestContent(info: _info, isSample: false, offline: true));
      await t.pumpWidget(_app(GuestHome(servicio: sinRed)));
      await espera(t, 700);
      await t.tap(find.text('Universidad').last);
      await espera(t, 700);
      expect(find.textContaining('Sin conexión'), findsOneWidget);
      await _salir(t);
      await t.binding.setSurfaceSize(null);
    });

    testWidgets('sin datos de contacto lo dice en vez de mostrar una tarjeta vacía', (t) async {
      await t.binding.setSurfaceSize(const Size(500, 2400));
      const sinContacto = UniversityInfo(name: 'Uni');
      await t.pumpWidget(_app(GuestHome(servicio: _Falso(contenido: const GuestContent(info: sinContacto, isSample: false)))));
      await espera(t, 700);
      await t.tap(find.text('Universidad').last);
      await espera(t, 700);
      expect(find.textContaining('aún no ha publicado sus datos de contacto'), findsOneWidget);
      await _salir(t);
      await t.binding.setSurfaceSize(null);
    });

    testWidgets('Probar la app: cada perfil muestra su demostración con datos de ejemplo', (t) async {
      await t.binding.setSurfaceSize(const Size(500, 2600));
      await t.pumpWidget(_app(GuestHome(servicio: _Falso())));
      await espera(t, 700);
      await t.tap(find.text('Probar la app').last);
      await espera(t, 800);
      expect(find.textContaining('Modo demostración'), findsOneWidget);
      expect(find.text('Hola, Ana (ejemplo)'), findsOneWidget);
      expect(find.text('Matemáticas Aplicadas'), findsOneWidget);
      expect(find.text('Repaso del parcial'), findsOneWidget, reason: 'reunión de ejemplo');

      await t.tap(find.text('Docente').last);
      await espera(t, 800);
      expect(find.text('Hola, Profe Demo'), findsOneWidget);
      expect(find.text('Libreta de calificaciones'), findsOneWidget);

      await t.tap(find.text('Admin').last);
      await espera(t, 800);
      expect(find.text('Panel Administrador'), findsOneWidget);
      expect(find.text('Estudiantes por materia'), findsOneWidget);
      await _salir(t);
      await t.binding.setSurfaceSize(null);
    });

    testWidgets('demo de estudiante: calificar al docente es interactivo', (t) async {
      await t.binding.setSurfaceSize(const Size(500, 3000));
      await t.pumpWidget(_app(GuestHome(servicio: _Falso())));
      await espera(t, 700);
      await t.tap(find.text('Probar la app').last);
      await espera(t, 800);
      expect(find.textContaining('respuesta es anónima'), findsNothing);
      await t.tap(find.bySemanticsLabel(RegExp('Excelente')).first);
      await espera(t);
      expect(find.textContaining('respuesta es anónima'), findsOneWidget);
      await _salir(t);
      await t.binding.setSurfaceSize(null);
    });

    testWidgets('demo de docente: iniciar una reunión funciona sin servidor', (t) async {
      await t.binding.setSurfaceSize(const Size(500, 3000));
      await t.pumpWidget(_app(GuestHome(servicio: _Falso())));
      await espera(t, 700);
      await t.tap(find.text('Probar la app').last);
      await espera(t, 800);
      await t.tap(find.text('Docente').last);
      await espera(t, 800);
      await t.tap(find.text('Iniciar'));
      await espera(t, 700);
      await t.tap(find.text('Iniciar ahora'));
      await espera(t, 800);
      expect(find.text('EN CURSO'), findsOneWidget);
      await _salir(t);
      await t.binding.setSurfaceSize(null);
    });
  });

  group('Admin: editar la información para invitados', () {
    testWidgets('carga lo publicado, permite editar y guarda', (t) async {
      await t.binding.setSurfaceSize(const Size(600, 4000));
      final servicio = _Falso();
      await t.pumpWidget(_app(AdminUniversityInfo(servicio: servicio)));
      await espera(t, 700);
      expect(find.text('Información para invitados'), findsOneWidget);
      expect(find.text('Unicomfacauca'), findsOneWidget);

      await t.enterText(find.widgetWithText(TextField, 'Nombre de la universidad *'), 'Nueva Universidad');
      await t.tap(find.text('Agregar requisito'));
      await espera(t);
      await t.tap(find.text('Guardar y publicar'));
      await espera(t, 800);

      expect(servicio.guardado, isNotNull);
      expect(servicio.guardado!.name, 'Nueva Universidad');
      expect(servicio.guardado!.programs.single.name, 'Ingeniería de Sistemas');
      expect(servicio.guardado!.requirements, ['Documento de identidad', 'Diploma de bachiller'],
          reason: 'el renglón vacío no se guarda');
      expect(find.textContaining('Guardado'), findsOneWidget);
      await t.pump(const Duration(seconds: 5));
      await _salir(t);
      await t.binding.setSurfaceSize(null);
    });

    testWidgets('exige el nombre y muestra el error del servidor', (t) async {
      await t.binding.setSurfaceSize(const Size(600, 4000));
      final servicio = _Falso()..falla = const ApiMessageException(400, 'El sitio web debe empezar con https://');
      await t.pumpWidget(_app(AdminUniversityInfo(servicio: servicio)));
      await espera(t, 700);

      await t.enterText(find.widgetWithText(TextField, 'Nombre de la universidad *'), '');
      await t.tap(find.text('Guardar y publicar'));
      await espera(t);
      expect(find.text('El nombre de la universidad es obligatorio.'), findsOneWidget);
      expect(servicio.guardado, isNull);

      await t.enterText(find.widgetWithText(TextField, 'Nombre de la universidad *'), 'Uni');
      await t.tap(find.text('Guardar y publicar'));
      await espera(t, 800);
      expect(find.text('El sitio web debe empezar con https://'), findsOneWidget);
      await _salir(t);
      await t.binding.setSurfaceSize(null);
    });

    testWidgets('restablecer pide confirmación y vuelve al ejemplo', (t) async {
      await t.binding.setSurfaceSize(const Size(600, 4000));
      final servicio = _Falso();
      await t.pumpWidget(_app(AdminUniversityInfo(servicio: servicio)));
      await espera(t, 700);
      await t.tap(find.byTooltip('Restablecer contenido de ejemplo'));
      await espera(t, 600);
      expect(find.text('¿Restablecer el ejemplo?'), findsOneWidget);
      await t.tap(find.text('Restablecer'));
      await espera(t, 800);
      expect(servicio.reinicios, 1);
      await _salir(t);
      await t.binding.setSurfaceSize(null);
    });
  });
}
