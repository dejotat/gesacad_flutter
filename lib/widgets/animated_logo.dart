import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Logo animado de GESACAD — versión premium con colores del tema activo.
/// Soporta modo transparente para usar como marca de agua en fondos.
class AnimatedLogo extends StatefulWidget {
  final double size;
  /// Si true, los anillos usan blanco transparente (para fondos oscuros/gradiente).
  /// Si false, usa los colores del tema activo.
  final bool transparent;

  const AnimatedLogo({super.key, this.size = 140, this.transparent = false});

  @override
  State<AnimatedLogo> createState() => _AnimatedLogoState();
}

class _AnimatedLogoState extends State<AnimatedLogo>
    with TickerProviderStateMixin {
  late AnimationController _spin1;  // Anillo exterior CW lento
  late AnimationController _spin2;  // Anillo medio CCW
  late AnimationController _pulse;  // Pulso centro
  late AnimationController _orbit;  // Partículas orbitando
  late AnimationController _shimmer; // Shimmer suave

  @override
  void initState() {
    super.initState();
    _spin1   = AnimationController(vsync: this, duration: const Duration(seconds: 12))..repeat();
    _spin2   = AnimationController(vsync: this, duration: const Duration(seconds: 7))..repeat();
    _pulse   = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat(reverse: true);
    _orbit   = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();
    _shimmer = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();
  }

  @override
  void dispose() {
    _spin1.dispose(); _spin2.dispose(); _pulse.dispose();
    _orbit.dispose(); _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final t = widget.transparent;

    return Semantics(
      label: 'Logo animado de GESACAD',
      child: SizedBox(
        width: s, height: s,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Anillo exterior — guiones girando CW
            AnimatedBuilder(
              animation: _spin1,
              builder: (_, __) => Transform.rotate(
                angle: _spin1.value * 2 * pi,
                child: CustomPaint(
                  size: Size(s, s),
                  painter: _DashedRingPainter(
                    radius: s * 0.48,
                    strokeWidth: 1.5,
                    color: t
                        ? Colors.white.withOpacity(0.35)
                        : Colors.white.withOpacity(0.5),
                    dashCount: 28,
                  ),
                ),
              ),
            ),
            // Anillo medio — gradiente girando CCW
            AnimatedBuilder(
              animation: _spin2,
              builder: (_, __) => Transform.rotate(
                angle: -_spin2.value * 2 * pi,
                child: CustomPaint(
                  size: Size(s, s),
                  painter: _GradientArcPainter(
                    radius: s * 0.37,
                    strokeWidth: 3.5,
                    transparent: t,
                  ),
                ),
              ),
            ),
            // Anillo fino fijo
            CustomPaint(
              size: Size(s, s),
              painter: _DashedRingPainter(
                radius: s * 0.28,
                strokeWidth: 1,
                color: t
                    ? Colors.white.withOpacity(0.2)
                    : Colors.white.withOpacity(0.3),
                dashCount: 14,
              ),
            ),
            // Partículas orbitando
            AnimatedBuilder(
              animation: _orbit,
              builder: (_, __) => _buildOrbits(s, t),
            ),
            // Centro pulsante + G
            AnimatedBuilder(
              animation: _pulse,
              builder: (_, __) {
                final g = _pulse.value;
                return Container(
                  width: s * 0.44, height: s * 0.44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        Colors.white.withOpacity(t ? 0.12 + g * 0.08 : 0.22 + g * 0.1),
                        (t ? Colors.black : const Color(0xFF1A237E)).withOpacity(0.85),
                      ],
                    ),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.3 + g * 0.25),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.white.withOpacity(t ? 0.1 + g * 0.15 : 0.2 + g * 0.2),
                        blurRadius: 20 + g * 24,
                        spreadRadius: 2 + g * 4,
                      ),
                      BoxShadow(
                        color: const Color(0xFF82B1FF).withOpacity(t ? 0.15 : 0.35 + g * 0.1),
                        blurRadius: 40, spreadRadius: 0,
                      ),
                    ],
                  ),
                  child: Center(
                    child: ShaderMask(
                      shaderCallback: (bounds) => LinearGradient(
                        colors: [
                          Colors.white,
                          Color.lerp(const Color(0xFF90CAF9),
                              const Color(0xFF80DEEA), g)!,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ).createShader(bounds),
                      child: Text('G', style: GoogleFonts.poppins(
                        fontSize: s * 0.22,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      )),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrbits(double s, bool t) {
    final r = s * 0.37;
    return SizedBox(
      width: s, height: s,
      child: Stack(
        alignment: Alignment.center,
        children: List.generate(4, (i) {
          final angle = _orbit.value * 2 * pi + i * pi / 2;
          final ox = r * cos(angle);
          final oy = r * sin(angle);
          final big = i % 2 == 0;
          final dotSize = big ? 8.0 : 5.0;
          return Transform.translate(
            offset: Offset(ox, oy),
            child: Container(
              width: dotSize, height: dotSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: big ? Colors.white : Colors.white60,
                boxShadow: [BoxShadow(
                  color: big
                      ? Colors.white.withOpacity(t ? 0.6 : 0.9)
                      : Colors.white.withOpacity(t ? 0.3 : 0.5),
                  blurRadius: big ? 10 : 5,
                  spreadRadius: 1,
                )],
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// Widget de marca de agua del logo — transparente, para usar como fondo decorativo.
class LogoWatermark extends StatelessWidget {
  final double size;
  final double opacity;
  const LogoWatermark({super.key, this.size = 200, this.opacity = 0.05});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: IgnorePointer(
        child: AnimatedLogo(size: size, transparent: true),
      ),
    );
  }
}

class _DashedRingPainter extends CustomPainter {
  final double radius, strokeWidth;
  final Color color;
  final int dashCount;
  const _DashedRingPainter({
    required this.radius, required this.strokeWidth,
    required this.color, required this.dashCount,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final center = Offset(size.width / 2, size.height / 2);
    const gapFraction = 0.28;
    final segmentAngle = 2 * pi / dashCount;
    final dashAngle = segmentAngle * (1 - gapFraction);
    for (int i = 0; i < dashCount; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        i * segmentAngle, dashAngle, false, paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _GradientArcPainter extends CustomPainter {
  final double radius, strokeWidth;
  final bool transparent;
  const _GradientArcPainter({
    required this.radius, required this.strokeWidth,
    this.transparent = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCircle(center: center, radius: radius);
    final paint1 = Paint()
      ..shader = const SweepGradient(
        colors: [
          Color(0x00FFFFFF), Color(0xFF90CAF9),
          Color(0xFF80DEEA), Color(0x00FFFFFF),
        ],
        stops: [0.0, 0.3, 0.7, 1.0],
      ).createShader(rect)
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, 2 * pi, false, paint1);
    final paint2 = Paint()
      ..shader = const SweepGradient(
        colors: [Color(0xFF82B1FF), Color(0x0082B1FF)],
        stops: [0.0, 1.0],
      ).createShader(rect)
      ..strokeWidth = strokeWidth * 0.6
      ..style = PaintingStyle.stroke;
    canvas.drawArc(rect, pi, pi, false, paint2);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
