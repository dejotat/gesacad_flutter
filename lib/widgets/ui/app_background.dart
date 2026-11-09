import 'package:flutter/material.dart';
import '../../config/app_scenes.dart';
import '../../services/settings_service.dart';
import 'logo_backdrop.dart';

/// Fondo de toda la app, con la escena de cada tema:
///
/// * **Temas oscuros**: tinta de color (violeta, grafito cálido, verde azulado; nunca negro) con
///   tres luces difusas y una cuadrícula casi invisible que se desvanece hacia los bordes.
/// * **Temas claros**: malla de color (degradado base + tres halos) derivada del tema.
///
/// En todos, el isotipo de GESACAD gira lento y translúcido detrás del contenido ([LogoFlotante]):
/// vive AQUÍ, una sola vez, y por eso aparece en TODAS las pantallas (antes solo en algunas).
/// Los paneles de vidrio (`AppCard`) dejan ver todo a través.
class AppBackground extends StatelessWidget {
  const AppBackground({super.key, required this.type, required this.child});

  final AppThemeType type;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = type.isDark;
    final capas = dark ? _oscuro(type.scene) : _claro(type.gradient);
    return Stack(
      fit: StackFit.expand,
      children: [
        ...capas,
        LogoFlotante(
          opacity: dark ? 0.2 : 0.11,
          color: dark ? (type.scene.logo ?? type.secondaryColor) : null,
        ),
        child,
      ],
    );
  }

  List<Widget> _claro(List<Color> g) {
    final base = [
      Color.lerp(const Color(0xFFFAF9FF), g[0], 0.10)!,
      Color.lerp(const Color(0xFFF1F5FF), g[1], 0.16)!,
    ];
    return [
      DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: base,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      ),
      Positioned(top: -160, right: -140, child: _halo(g[0].withValues(alpha: 0.30), 520)),
      Positioned(bottom: -200, left: -160, child: _halo(g[1].withValues(alpha: 0.28), 560)),
      Positioned(top: 220, left: -120, child: _halo(type.secondaryColor.withValues(alpha: 0.16), 340)),
    ];
  }

  List<Widget> _oscuro(DarkScene e) {
    return [
      DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: e.base,
            stops: const [0, 0.5, 1],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
      ),
      // Cuadrícula (una sola vez: queda en caché, no se repinta).
      const RepaintBoundary(child: IgnorePointer(child: CustomPaint(painter: _GridPainter()))),
      // Luces difusas (radial-gradient: baratas de pintar).
      Positioned(top: -190, right: -150, child: _halo(e.halos[0], 620)),
      Positioned(bottom: -220, left: -170, child: _halo(e.halos[1], 640)),
      Positioned(top: 240, left: -150, child: _halo(e.halos[2], 420)),
    ];
  }

  Widget _halo(Color c, double size) => IgnorePointer(
        child: ExcludeSemantics(
          child: Container(
            width: size, height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [c, c.withValues(alpha: 0)]),
            ),
          ),
        ),
      );
}

/// Cuadrícula fina enmascarada con un degradado radial (más visible al centro).
class _GridPainter extends CustomPainter {
  const _GridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.saveLayer(rect, Paint());
    final linea = Paint()
      ..color = const Color(0x12FFFFFF)
      ..strokeWidth = 1;
    const paso = 56.0;
    for (double x = 0; x <= size.width; x += paso) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), linea);
    }
    for (double y = 0; y <= size.height; y += paso) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linea);
    }
    canvas.drawRect(
      rect,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = const RadialGradient(
          center: Alignment(0, -0.3),
          radius: 0.9,
          colors: [Colors.white, Color(0x00FFFFFF)],
        ).createShader(rect),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
