import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gesacad/config/app_tokens.dart';
import 'package:gesacad/models/university_info.dart';
import 'package:gesacad/screens/guest/guest_home.dart';
import 'package:gesacad/services/guest_service.dart';
import 'package:gesacad/widgets/ui/ui.dart';

class _Falso extends GuestService {
  @override
  Future<GuestContent> load() async => const GuestContent(info: UniversityInfo.sample, isSample: true);
  @override
  Future<Set<String>> loadChecklist() async => {};
}

Widget _app(Widget home) => MaterialApp(theme: ThemeData(extensions: const [AppTokens.light]), home: home);

void main() {
  testWidgets('MotionIcon con halo no cambia el tamaño de su contenedor mientras anima', (t) async {
    await t.pumpWidget(_app(const Scaffold(
      body: Center(child: MotionIcon(Icons.star, size: 30, color: Colors.blue, halo: true, motion: IconMotion.pulse)),
    )));
    await t.pump();
    final tamanos = <Size>{};
    for (var i = 0; i < 30; i++) {
      await t.pump(const Duration(milliseconds: 100));
      tamanos.add(t.getSize(find.byType(MotionIcon)));
    }
    expect(tamanos.length, 1, reason: 'el halo solo se dibuja, no ocupa espacio: $tamanos');
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('el dashboard de invitado no se mueve solo: la altura del contenido es constante', (t) async {
    await t.binding.setSurfaceSize(const Size(500, 900));
    await t.pumpWidget(_app(GuestHome(servicio: _Falso())));
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    for (final pestana in ['Inicio', 'Universidad', 'Probar la app']) {
      await t.tap(find.text(pestana).last);
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      final extensiones = <String>{};
      final scroll = find.byType(Scrollable).first;
      for (var i = 0; i < 40; i++) {
        await t.pump(const Duration(milliseconds: 250));
        extensiones.add(t.state<ScrollableState>(scroll).position.maxScrollExtent.toStringAsFixed(1));
      }
      expect(extensiones.length, 1, reason: '$pestana cambia de altura sola: $extensiones');
    }
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
    await t.binding.setSurfaceSize(null);
  });
}
