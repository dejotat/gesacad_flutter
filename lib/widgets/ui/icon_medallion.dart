import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'motion_icon.dart';

/// Medallón de ícono: base de degradado con brillo de cristal, una órbita de
/// guiones que gira alrededor y el ícono con movimiento propio.
/// Es el "sello visual" de cursos, notificaciones, eventos y actividades.
class IconMedallion extends StatefulWidget {
  const IconMedallion(
    this.icon, {
    super.key,
    required this.colors,
    this.size = 48,
    this.motion = IconMotion.float,
    this.circle = false,
    this.orbit = true,
    this.delay = Duration.zero,
    this.ping = false,
  });

  final IconData icon;

  /// Par de colores del degradado de fondo.
  final List<Color> colors;
  final double size;
  final IconMotion motion;
  final bool circle;

  /// Órbita de guiones girando alrededor del medallón.
  final bool orbit;
  final Duration delay;

  /// Onda sonar (para elementos sin leer o que requieren atención).
  final bool ping;

  @override
  State<IconMedallion> createState() => _IconMedallionState();
}

class _IconMedallionState extends State<IconMedallion>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin =
      AnimationController(vsync: this, duration: const Duration(seconds: 14));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (widget.orbit && !reduce) {
      if (!_spin.isAnimating) _spin.repeat();
    } else {
      _spin.stop();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final radius = BorderRadius.circular(widget.circle ? s : s * 0.30);

    return ExcludeSemantics(
      child: SizedBox(
        width: s, height: s,
        child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
          Container(
            width: s, height: s,
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: LinearGradient(
                colors: widget.colors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
              boxShadow: [
                BoxShadow(
                  color: widget.colors.first.withValues(alpha: 0.38),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: radius,
              child: Stack(children: [
                // Brillo de cristal en la esquina superior.
                Positioned(
                  top: -s * 0.35, left: -s * 0.15,
                  child: Container(
                    width: s * 0.95, height: s * 0.8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(colors: [
                        Colors.white.withValues(alpha: 0.38),
                        Colors.white.withValues(alpha: 0),
                      ]),
                    ),
                  ),
                ),
              ]),
            ),
          ),
          if (widget.orbit)
            AnimatedBuilder(
              animation: _spin,
              builder: (_, __) => CustomPaint(
                size: Size.square(s * 1.28),
                painter: _OrbitPainter(_spin.value, widget.colors.first),
              ),
            ),
          MotionIcon(
            widget.icon,
            color: Colors.white,
            size: s * 0.5,
            motion: widget.motion,
            delay: widget.delay,
            glow: true,
            halo: widget.ping,
          ),
        ]),
      ),
    );
  }
}

/// Anillo de guiones con un punto de luz que lo recorre, por fuera del medallón.
class _OrbitPainter extends CustomPainter {
  _OrbitPainter(this.v, this.color);
  final double v;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final o = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 1;
    final rect = Rect.fromCircle(center: o, radius: r);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: 0.45);
    const n = 14;
    const seg = 2 * math.pi / n;
    for (var i = 0; i < n; i++) {
      canvas.drawArc(rect, v * 2 * math.pi + i * seg, seg * 0.45, false, p);
    }
    final a = -v * 2 * math.pi * 2;
    final d = o + Offset(math.cos(a), math.sin(a)) * r;
    canvas.drawCircle(d, 2.4, Paint()..color = color.withValues(alpha: 0.9));
  }

  @override
  bool shouldRepaint(covariant _OrbitPainter old) => old.v != v;
}
