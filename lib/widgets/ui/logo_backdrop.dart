import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Isotipo de GESACAD dibujado en vectores: núcleo con la "G", tres órbitas
/// (dos de guiones y una de degradado) y puntos de luz que las recorren.
///
/// Se pinta con un solo [CustomPainter] y un único controlador: es mucho más
/// barato que apilar widgets animados. Todas las velocidades son múltiplos
/// enteros del ciclo, así el bucle no tiene saltos.
class GesacadMark extends StatefulWidget {
  const GesacadMark({
    super.key,
    this.size = 160,
    this.color,
    this.opacity = 1,
    this.animate = true,
  });

  final double size;

  /// Color base; por defecto el primario del tema.
  final Color? color;

  /// Opacidad global (el logo de fondo usa valores muy bajos).
  final double opacity;
  final bool animate;

  @override
  State<GesacadMark> createState() => _GesacadMarkState();
}

class _GesacadMarkState extends State<GesacadMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 24));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (widget.animate && !reduce) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c.stop();
      _c.value = 0.12;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    var base = widget.color ?? Theme.of(context).colorScheme.primary;
    // En oscuro se aclara para que el trazo se lea sobre el fondo negro.
    if (dark) base = Color.lerp(base, Colors.white, 0.35)!;

    return ExcludeSemantics(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.square(widget.size),
          painter: _MarkPainter(_c, base, widget.opacity),
        ),
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.t, this.color, this.opacity) : super(repaint: t);

  final Animation<double> t;
  final Color color;
  final double opacity;

  static const _tau = 2 * math.pi;

  Color _c(double a) => color.withValues(alpha: (a * opacity).clamp(0.0, 1.0));

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final o = Offset(s / 2, s / 2);
    final v = t.value;

    // ── Órbita exterior: guiones que giran lento en sentido horario.
    _dashedRing(canvas, o, s * 0.47, 36, s * 0.006, _c(0.55), v * _tau);

    // ── Órbita media: arco con degradado, contrarreloj (2 vueltas por ciclo).
    final rMid = s * 0.37;
    final rectMid = Rect.fromCircle(center: o, radius: rMid);
    final angMid = -v * _tau * 2;
    canvas.save();
    canvas.translate(o.dx, o.dy);
    canvas.rotate(angMid);
    canvas.translate(-o.dx, -o.dy);
    canvas.drawArc(
      rectMid, 0, _tau, false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.016
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          colors: [_c(0), _c(0.95), _c(0.35), _c(0)],
          stops: const [0.0, 0.45, 0.8, 1.0],
        ).createShader(rectMid),
    );
    canvas.restore();

    // ── Órbita interior de guiones finos (contraria a la exterior).
    _dashedRing(canvas, o, s * 0.29, 18, s * 0.005, _c(0.45), -v * _tau * 3);

    // ── Puntos de luz recorriendo las órbitas.
    _dot(canvas, o, rMid, v * _tau * 3 + 0.6, s * 0.022, _c(1));
    _dot(canvas, o, rMid, v * _tau * 3 + 0.6 + math.pi, s * 0.014, _c(0.8));
    _dot(canvas, o, s * 0.47, -v * _tau * 2 + 2.2, s * 0.016, _c(0.9));

    // ── Núcleo: esfera con pulso (periodo 2 s) y la "G".
    final pulse = 0.5 + 0.5 * math.sin(v * _tau * 12);
    final rc = s * (0.205 + 0.008 * pulse);
    canvas.drawCircle(
      o, rc * 1.55,
      Paint()
        ..shader = RadialGradient(
          colors: [_c(0.32 + 0.14 * pulse), _c(0)],
        ).createShader(Rect.fromCircle(center: o, radius: rc * 1.55)),
    );
    canvas.drawCircle(
      o, rc,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.35),
          colors: [_c(0.55), _c(0.95)],
        ).createShader(Rect.fromCircle(center: o, radius: rc)),
    );
    canvas.drawCircle(
      o, rc,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.012
        ..color = _c(0.9),
    );

    final tp = TextPainter(
      text: TextSpan(
        text: 'G',
        style: GoogleFonts.poppins(
          fontSize: s * 0.21,
          fontWeight: FontWeight.w800,
          color: Colors.white.withValues(alpha: (0.95 * opacity).clamp(0.0, 1.0)),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, o - Offset(tp.width / 2, tp.height / 2));
  }

  void _dashedRing(Canvas canvas, Offset o, double r, int count, double w,
      Color c, double rot) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..color = c;
    final seg = _tau / count;
    final rect = Rect.fromCircle(center: o, radius: r);
    for (var i = 0; i < count; i++) {
      canvas.drawArc(rect, rot + i * seg, seg * 0.62, false, p);
    }
  }

  void _dot(Canvas canvas, Offset o, double r, double a, double radius, Color c) {
    final p = o + Offset(math.cos(a), math.sin(a)) * r;
    canvas.drawCircle(
      p, radius * 3,
      Paint()
        ..shader = RadialGradient(colors: [c.withValues(alpha: c.a * 0.5), c.withValues(alpha: 0)])
            .createShader(Rect.fromCircle(center: p, radius: radius * 3)),
    );
    canvas.drawCircle(p, radius, Paint()..color = c);
  }

  @override
  bool shouldRepaint(covariant _MarkPainter old) =>
      old.color != color || old.opacity != opacity;
}

/// Fondo de dashboard: el isotipo de GESACAD grande, translúcido y en
/// movimiento (órbitas girando, flotación suave) detrás del contenido.
/// No intercepta toques ni aparece para lectores de pantalla.
class LogoBackdrop extends StatefulWidget {
  const LogoBackdrop({
    super.key,
    required this.child,
    this.opacity = 0.11,
    this.alignment = const Alignment(0.55, -0.15),
  });

  final Widget child;
  final double opacity;
  final Alignment alignment;

  @override
  State<LogoBackdrop> createState() => _LogoBackdropState();
}

class _LogoBackdropState extends State<LogoBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _float =
      AnimationController(vsync: this, duration: const Duration(seconds: 9));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) {
      _float.stop();
    } else if (!_float.isAnimating) {
      _float.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _float.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: LayoutBuilder(builder: (_, c) {
              final side = (math.max(c.maxWidth, c.maxHeight) * 0.78)
                  .clamp(280.0, 760.0);
              return AnimatedBuilder(
                animation: _float,
                builder: (_, child) {
                  final k = Curves.easeInOut.transform(_float.value);
                  return Align(
                    alignment: widget.alignment,
                    child: Transform.translate(
                      offset: Offset(0, (k - 0.5) * 22),
                      child: Transform.scale(
                        scale: 1 + 0.025 * k,
                        child: child,
                      ),
                    ),
                  );
                },
                child: GesacadMark(size: side, opacity: widget.opacity),
              );
            }),
          ),
        ),
        widget.child,
      ],
    );
  }
}
