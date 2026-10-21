import 'package:flutter/material.dart';
import '../../services/settings_service.dart';

/// Fondo de toda la app: malla de color (degradado base + tres halos difusos)
/// derivada del tema. Los paneles de vidrio (`AppCard`) lo dejan ver a través,
/// por eso los colores son vivos pero con baja opacidad.
/// Es estático (sin animación) para no gastar batería ni distraer.
class AppBackground extends StatelessWidget {
  const AppBackground({super.key, required this.type, required this.child});

  final AppThemeType type;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = type.isDark;
    final g = type.gradient;

    final base = dark
        ? [const Color(0xFF0B0B1A), const Color(0xFF14102B)]
        : [
            Color.lerp(const Color(0xFFFAF9FF), g[0], 0.10)!,
            Color.lerp(const Color(0xFFF1F5FF), g[1], 0.16)!,
          ];

    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: base,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        // Halos difusos (radial-gradient: baratos de pintar).
        Positioned(
          top: -160, right: -140,
          child: _halo(g[0].withValues(alpha: dark ? 0.34 : 0.30), 520),
        ),
        Positioned(
          bottom: -200, left: -160,
          child: _halo(g[1].withValues(alpha: dark ? 0.26 : 0.28), 560),
        ),
        Positioned(
          top: 220, left: -120,
          child: _halo(
              type.secondaryColor.withValues(alpha: dark ? 0.14 : 0.16), 340),
        ),
        child,
      ],
    );
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
