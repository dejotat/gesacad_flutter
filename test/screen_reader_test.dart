import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gesacad/services/screen_reader.dart';
import 'package:gesacad/services/settings_service.dart';

Widget _pantalla() => MaterialApp(
      navigatorObservers: [ScreenReaderObserver()],
      home: Scaffold(
        appBar: AppBar(title: const Text('Panel de prueba')),
        body: Column(children: [
          ElevatedButton(onPressed: () {}, child: const Text('Guardar')),
          IconButton(onPressed: () {}, icon: const Icon(Icons.delete), tooltip: 'Eliminar usuario'),
          const TextField(decoration: InputDecoration(labelText: 'Usuario')),
          Semantics(header: true, child: const Text('Resumen del sistema')),
          Semantics(label: 'Notificaciones', toggled: true, onTap: () {}, child: const SizedBox(width: 60, height: 40)),
          const SizedBox(height: 120),
        ]),
      ),
    );

void main() {
  late List<String> dicho;
  final sr = ScreenReader.instance;

  // El lector abre su propio manejador de accesibilidad: hay que cerrarlo dentro de la prueba.
  void fin(SemanticsHandle sem) {
    sr.reiniciar();
    sem.dispose();
  }

  setUpAll(() {
    // El lector real usa el motor de voz del dispositivo; en pruebas no existe.
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'), (c) async => 1);
  });

  setUp(() {
    AppSettings.talkBackEnabled.value = false;
    sr.reiniciar();
    dicho = [];
    sr.decir = dicho.add;
    sr.espera = const Duration(milliseconds: 50);
  });

  tearDown(() {
    sr.reiniciar();
    AppSettings.talkBackEnabled.value = false;
  });

  testWidgets('frasePara lee etiqueta y rol: botón, botón con tooltip, campo, encabezado e interruptor', (t) async {
    final sem = t.ensureSemantics();
    await t.pumpWidget(_pantalla());

    // Sin la palabra «botón» al final: solo el nombre.
    expect(sr.frasePara(t.getCenter(find.text('Guardar'))), 'Guardar');
    expect(sr.frasePara(t.getCenter(find.byIcon(Icons.delete))), 'Eliminar usuario');
    expect(sr.frasePara(t.getCenter(find.byType(TextField))), allOf(contains('Usuario'), isNot(contains('campo de texto'))));
    expect(sr.frasePara(t.getCenter(find.text('Resumen del sistema'))), 'Resumen del sistema');
    expect(sr.frasePara(t.getCenter(find.byWidgetPredicate((w) => w is SizedBox && w.width == 60))), allOf(contains('Notificaciones'), contains('activado')));
    fin(sem);
  });

  testWidgets('al entrar a un panel saluda una sola vez y la pantalla no lo tapa', (t) async {
    final sem = t.ensureSemantics();
    await t.pumpWidget(_pantalla());
    AppSettings.talkBackEnabled.value = true;
    sr.iniciar();

    sr.bienvenida('administrador');
    sr.pantallaCambio(); // la transición de la ruta llega justo después
    await t.pump(const Duration(milliseconds: 1500));
    expect(dicho, ['Bienvenido al panel de administrador']);
    fin(sem);
  });

  testWidgets('donde no hay nada con etiqueta no lee nada', (t) async {
    final sem = t.ensureSemantics();
    await t.pumpWidget(_pantalla());
    expect(sr.frasePara(const Offset(2, 590)), isNull);
    fin(sem);
  });

  testWidgets('con el lector activo, el cursor lee al detenerse y no repite el mismo elemento', (t) async {
    final sem = t.ensureSemantics();
    await t.pumpWidget(_pantalla());
    AppSettings.talkBackEnabled.value = true;
    sr.iniciar();

    final cursor = await t.createGesture(kind: PointerDeviceKind.mouse);
    await cursor.addPointer(location: Offset.zero);
    await cursor.moveTo(t.getCenter(find.text('Guardar')));
    await t.pump(const Duration(milliseconds: 120));
    expect(dicho, ['Guardar']);

    // Moverse dentro del mismo botón no vuelve a leerlo.
    await cursor.moveBy(const Offset(3, 2));
    await t.pump(const Duration(milliseconds: 120));
    expect(dicho.length, 1);

    // Pasar a otro elemento sí lo lee.
    await cursor.moveTo(t.getCenter(find.byIcon(Icons.delete)));
    await t.pump(const Duration(milliseconds: 120));
    expect(dicho.last, 'Eliminar usuario');

    // Un cruce rápido (sin detenerse) no lee lo que se atraviesa.
    final antes = dicho.length;
    await cursor.moveTo(t.getCenter(find.text('Guardar')));
    await cursor.moveTo(t.getCenter(find.byType(TextField)));
    await t.pump(const Duration(milliseconds: 120));
    expect(dicho.length, antes + 1, reason: 'solo lee donde se detiene');
    expect(dicho.last, contains('Usuario'));
    await cursor.removePointer();
    fin(sem);
  });

  testWidgets('apagado no habla', (t) async {
    final sem = t.ensureSemantics();
    await t.pumpWidget(_pantalla());
    sr.iniciar(); // lector desactivado
    final cursor = await t.createGesture(kind: PointerDeviceKind.mouse);
    await cursor.addPointer(location: Offset.zero);
    await cursor.moveTo(t.getCenter(find.text('Guardar')));
    await t.pump(const Duration(milliseconds: 200));
    expect(dicho, isEmpty);
    await cursor.removePointer();
    fin(sem);
  });

  testWidgets('activarlo desde los ajustes lo anuncia; arrancar con él ya activo no habla', (t) async {
    final sem = t.ensureSemantics();
    await t.pumpWidget(_pantalla());
    AppSettings.talkBackEnabled.value = true; // preferencia guardada de la sesión anterior
    sr.iniciar();
    expect(dicho, isEmpty, reason: 'el navegador bloquea la voz sin gesto del usuario');

    sr.reiniciar();
    AppSettings.talkBackEnabled.value = false;
    dicho = [];
    sr.decir = dicho.add;
    sr.iniciar();
    AppSettings.talkBackEnabled.value = true; // el usuario lo enciende
    expect(dicho.single, contains('Lector de pantalla activado'));
    fin(sem);
  });

  testWidgets('el teclado: al enfocar con Tab lee el elemento', (t) async {
    final sem = t.ensureSemantics();
    await t.pumpWidget(_pantalla());
    AppSettings.talkBackEnabled.value = true;
    sr.iniciar();

    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump(const Duration(milliseconds: 300));
    expect(dicho, isNotEmpty);
    expect(dicho.join(' | '), anyOf(contains('Guardar'), contains('Eliminar usuario')));
    fin(sem);
  });

  testWidgets('al abrir una pantalla o un diálogo anuncia su título', (t) async {
    final sem = t.ensureSemantics();
    await t.pumpWidget(_pantalla());
    AppSettings.talkBackEnabled.value = true;
    sr.iniciar();

    // Nueva pantalla con su AppBar.
    final nav = t.state<NavigatorState>(find.byType(Navigator));
    nav.push(MaterialPageRoute<void>(builder: (_) => Scaffold(appBar: AppBar(title: const Text('Detalle del curso')))));
    await t.pumpAndSettle();
    await t.pump(const Duration(milliseconds: 800));
    expect(dicho, contains('Detalle del curso'));

    // Diálogo: anuncia su título.
    dicho.clear();
    showDialog<void>(
      context: nav.context,
      builder: (_) => const AlertDialog(title: Text('Eliminar usuario'), content: Text('¿Seguro?')),
    );
    await t.pumpAndSettle();
    await t.pump(const Duration(milliseconds: 800));
    expect(dicho.join(' | '), allOf(contains('Eliminar usuario'), contains('¿Seguro?')));
    fin(sem);
  });
}
