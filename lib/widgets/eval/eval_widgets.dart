import 'dart:math' as math;
import 'dart:ui' show PathMetric;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../config/app_tokens.dart';
import '../../models/evaluation_models.dart';
import '../ui/ui.dart';

/// Componentes visuales del módulo de evaluación docente: lenguaje "futurista"
/// (hexágonos, órbitas, resplandor neón) construido sobre los tokens de la app,
/// así funciona igual en los temas claros y oscuros.

// ── Paleta y utilidades ──────────────────────────────────────────────────────

/// Colores del módulo: cian → violeta, tomados de la paleta de gráficos.
class EvalColors {
  static List<Color> accent(BuildContext c) {
    final t = c.tokens;
    return [t.chart[1], t.chart[0]];
  }

  /// Color de una valoración de 1 a 5 (rojo → verde).
  static Color score(double v, AppTokens t) {
    final k = ((v - 1) / 4).clamp(0.0, 1.0);
    if (k < 0.5) return Color.lerp(t.danger, t.warning, k * 2)!;
    return Color.lerp(t.warning, t.success, (k - 0.5) * 2)!;
  }
}

final _fmtFecha = DateFormat("d 'de' MMM y, h:mm a", 'es');

/// Fecha y hora de Colombia, legible ("12 de oct 2026, 11:59 p. m.").
String formatFechaHora(DateTime? utc) =>
    utc == null ? 'Sin definir' : _fmtFecha.format(toColombia(utc));

/// "Cierra hoy", "Cierra mañana", "Cierra en 3 días"…
String cierraEn(DateTime? closesUtc, {DateTime? ahora}) {
  if (closesUtc == null) return '';
  final d = closesUtc.difference((ahora ?? DateTime.now()).toUtc());
  if (d.isNegative) return 'Cerrada';
  if (d.inHours < 1) return 'Cierra en ${math.max(1, d.inMinutes)} min';
  if (d.inHours < 24) return 'Cierra en ${d.inHours} h';
  if (d.inDays == 1) return 'Cierra mañana';
  return 'Cierra en ${d.inDays} días';
}

// ── Hexágono con órbita ──────────────────────────────────────────────────────

/// Medallón hexagonal con degradado, resplandor y un anillo de guiones que
/// orbita. Es el "sello" del módulo.
class HexMedallion extends StatefulWidget {
  const HexMedallion(
    this.icon, {
    super.key,
    required this.colors,
    this.size = 60,
    this.motion = IconMotion.float,
    this.orbit = true,
    this.ping = false,
  });

  final IconData icon;
  final List<Color> colors;
  final double size;
  final IconMotion motion;
  final bool orbit;
  final bool ping;

  @override
  State<HexMedallion> createState() => _HexMedallionState();
}

class _HexMedallionState extends State<HexMedallion>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 16));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (widget.orbit && !reduce) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return ExcludeSemantics(
      child: SizedBox(
        width: s * 1.3, height: s * 1.3,
        child: RepaintBoundary(
          child: Stack(alignment: Alignment.center, children: [
            CustomPaint(
              size: Size.square(s * 1.3),
              painter: _HexPainter(_c, widget.colors),
            ),
            MotionIcon(widget.icon,
                color: Colors.white,
                size: s * 0.44,
                motion: widget.motion,
                glow: true,
                halo: widget.ping),
          ]),
        ),
      ),
    );
  }
}

Path _hexPath(Offset c, double r) {
  final p = Path();
  for (var i = 0; i < 6; i++) {
    final a = -math.pi / 2 + i * math.pi / 3;
    final pt = c + Offset(math.cos(a), math.sin(a)) * r;
    i == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
  }
  return p..close();
}

class _HexPainter extends CustomPainter {
  _HexPainter(this.t, this.colors) : super(repaint: t);
  final Animation<double> t;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 / 1.3;
    final body = _hexPath(c, r);

    // Resplandor exterior.
    canvas.drawPath(
      body,
      Paint()
        ..color = colors.first.withValues(alpha: 0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );
    // Cuerpo con degradado.
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawPath(
      body,
      Paint()
        ..shader = LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(rect),
    );
    // Brillo de cristal.
    canvas.save();
    canvas.clipPath(body);
    canvas.drawCircle(
      c + Offset(-r * 0.35, -r * 0.5), r * 0.9,
      Paint()
        ..shader = RadialGradient(colors: [
          Colors.white.withValues(alpha: 0.42),
          Colors.white.withValues(alpha: 0),
        ]).createShader(Rect.fromCircle(center: c + Offset(-r * 0.35, -r * 0.5), radius: r * 0.9)),
    );
    canvas.restore();
    canvas.drawPath(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.white.withValues(alpha: 0.55),
    );

    // Hexágono exterior de guiones que gira.
    final outer = _hexPath(c, r * 1.22);
    final dash = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..color = colors.first.withValues(alpha: 0.55);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(t.value * 2 * math.pi);
    canvas.translate(-c.dx, -c.dy);
    for (final PathMetric m in outer.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, math.min(d + 7, m.length)), dash);
        d += 13;
      }
    }
    canvas.restore();

    // Punto de luz que recorre el contorno (sentido contrario).
    final a = -t.value * 2 * math.pi * 2 - math.pi / 2;
    final dot = c + Offset(math.cos(a), math.sin(a)) * (r * 1.22);
    canvas.drawCircle(dot, 3, Paint()..color = colors.last);
    canvas.drawCircle(
      dot, 8,
      Paint()
        ..color = colors.last.withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
  }

  @override
  bool shouldRepaint(covariant _HexPainter old) => old.colors != colors;
}

// ── Selector de valoración ───────────────────────────────────────────────────

/// Cinco orbes luminosos para valorar de 1 a 5. El elegido crece con rebote,
/// se enciende con el color de su nivel y emite un anillo de pulso.
class RatingOrbs extends StatelessWidget {
  const RatingOrbs({
    super.key,
    required this.value,
    required this.onChanged,
    this.questionLabel = '',
  });

  final int? value;
  final ValueChanged<int> onChanged;

  /// Enunciado de la pregunta, para el lector de pantalla.
  final String questionLabel;

  static const labels = ['Muy mal', 'Mal', 'Regular', 'Bien', 'Excelente'];
  static const icons = [
    PhosphorIconsFill.smileyAngry,
    PhosphorIconsFill.smileySad,
    PhosphorIconsFill.smileyMeh,
    PhosphorIconsFill.smileySticker,
    PhosphorIconsFill.smileyWink,
  ];

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return LayoutBuilder(builder: (ctx, c) {
      final orb = math.min(56.0, (c.maxWidth - 4 * 8) / 5);
      return Column(mainAxisSize: MainAxisSize.min, children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 1; i <= 5; i++)
              _Orb(
                size: orb,
                level: i,
                selected: value == i,
                dimmed: value != null && value != i,
                color: EvalColors.score(i.toDouble(), t),
                semantic: '$questionLabel ${labels[i - 1]}, $i de 5',
                onTap: () {
                  HapticFeedback.selectionClick();
                  onChanged(i);
                },
              ),
          ],
        ),
        const SizedBox(height: 8),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: Text(
            value == null ? 'Toca un orbe para valorar' : labels[value! - 1],
            key: ValueKey(value),
            style: GoogleFonts.poppins(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: value == null
                  ? t.muted
                  : EvalColors.score(value!.toDouble(), t),
            ),
          ),
        ),
      ]);
    });
  }
}

class _Orb extends StatefulWidget {
  const _Orb({
    required this.size,
    required this.level,
    required this.selected,
    required this.dimmed,
    required this.color,
    required this.semantic,
    required this.onTap,
  });

  final double size;
  final int level;
  final bool selected;
  final bool dimmed;
  final Color color;
  final String semantic;
  final VoidCallback onTap;

  @override
  State<_Orb> createState() => _OrbState();
}

class _OrbState extends State<_Orb> with SingleTickerProviderStateMixin {
  late final AnimationController _ring = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1500));
  bool _hover = false;

  @override
  void didUpdateWidget(covariant _Orb old) {
    super.didUpdateWidget(old);
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (widget.selected && !old.selected && !reduce) {
      _ring.repeat();
    } else if (!widget.selected) {
      _ring.stop();
      _ring.value = 0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (widget.selected && !reduce && !_ring.isAnimating) _ring.repeat();
  }

  @override
  void dispose() {
    _ring.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final s = widget.size;
    final sel = widget.selected;
    final col = widget.color;

    return Semantics(
      button: true,
      selected: sel,
      label: widget.semantic,
      excludeSemantics: true,
      onTap: widget.onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: SizedBox(
            width: s, height: s,
            child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
              if (sel)
                AnimatedBuilder(
                  animation: _ring,
                  builder: (_, __) => Container(
                    width: s * (1.0 + 0.55 * _ring.value),
                    height: s * (1.0 + 0.55 * _ring.value),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: col.withValues(alpha: 0.6 * (1 - _ring.value)), width: 2),
                    ),
                  ),
                ),
              AnimatedScale(
                scale: sel ? 1.16 : (_hover ? 1.08 : 1.0),
                duration: const Duration(milliseconds: 420),
                curve: Curves.elasticOut,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 260),
                  width: s, height: s,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: sel
                        ? RadialGradient(
                            center: const Alignment(-0.35, -0.4),
                            colors: [Color.lerp(col, Colors.white, 0.35)!, col],
                          )
                        : null,
                    color: sel ? null : t.glass,
                    border: Border.all(
                      color: sel ? Colors.white.withValues(alpha: 0.7) : t.glassBorder,
                      width: sel ? 1.6 : 1,
                    ),
                    boxShadow: sel
                        ? [BoxShadow(color: col.withValues(alpha: 0.7), blurRadius: 20)]
                        : null,
                  ),
                  child: Center(
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 220),
                      opacity: widget.dimmed ? 0.5 : 1,
                      child: Icon(
                        RatingOrbs.icons[widget.level - 1],
                        size: s * 0.56,
                        color: sel ? Colors.white : col,
                      ),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ── Anillo de puntaje ────────────────────────────────────────────────────────

/// Anillo con arco de degradado y resplandor que se dibuja hasta [value]/[max].
/// El número del centro cuenta desde cero.
class ScoreRing extends StatelessWidget {
  const ScoreRing({
    super.key,
    required this.value,
    this.max = 5,
    this.size = 92,
    this.caption,
    this.color,
    this.decimals = 1,
    this.suffix = '',
  });

  final double value;
  final double max;
  final double size;
  final String? caption;
  final Color? color;
  final int decimals;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final col = color ?? EvalColors.score(value / max * 4 + 1, t);
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Semantics(
      label: '${caption ?? "Puntaje"}: ${value.toStringAsFixed(decimals)}$suffix',
      child: ExcludeSemantics(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: (value / max).clamp(0.0, 1.0)),
          duration: reduce ? Duration.zero : const Duration(milliseconds: 1300),
          curve: Curves.easeOutCubic,
          builder: (_, k, __) => SizedBox(
            width: size, height: size,
            child: CustomPaint(
              painter: _RingPainter(k, col, t.border),
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(
                    '${(k * max).toStringAsFixed(decimals)}$suffix',
                    style: GoogleFonts.poppins(
                        fontSize: size * 0.27,
                        fontWeight: FontWeight.w700,
                        height: 1.05,
                        color: Theme.of(context).colorScheme.onSurface),
                  ),
                  if (caption != null)
                    Text(caption!,
                        style: GoogleFonts.poppins(
                            fontSize: size * 0.115, color: t.muted)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.k, this.color, this.track);
  final double k;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final w = size.width * 0.095;
    final rect = Rect.fromCircle(center: c, radius: size.width / 2 - w);
    canvas.drawArc(rect, 0, 2 * math.pi, false,
        Paint()..style = PaintingStyle.stroke..strokeWidth = w..color = track);
    if (k <= 0) return;
    final sweep = 2 * math.pi * k;
    final shader = SweepGradient(
      startAngle: 0,
      endAngle: 2 * math.pi,
      colors: [color.withValues(alpha: 0.35), color, color],
      stops: const [0, 0.5, 1],
      transform: const GradientRotation(-math.pi / 2),
    ).createShader(rect);
    // Resplandor y arco.
    canvas.drawArc(rect, -math.pi / 2, sweep, false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w
          ..strokeCap = StrokeCap.round
          ..color = color.withValues(alpha: 0.5)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7));
    canvas.drawArc(rect, -math.pi / 2, sweep, false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w
          ..strokeCap = StrokeCap.round
          ..shader = shader);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.k != k || old.color != color || old.track != track;
}

// ── Chip de fase ─────────────────────────────────────────────────────────────

class PhaseChip extends StatelessWidget {
  const PhaseChip(this.phase, {super.key});
  final EvalPhase phase;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final (Color color, IconData icon, IconMotion motion) = switch (phase) {
      EvalPhase.draft => (t.muted, PhosphorIconsRegular.pencilSimpleLine, IconMotion.write),
      EvalPhase.scheduled => (t.info, PhosphorIconsRegular.hourglassHigh, IconMotion.swing),
      EvalPhase.open => (t.success, PhosphorIconsRegular.broadcast, IconMotion.pulse),
      EvalPhase.closed => (t.warning, PhosphorIconsRegular.lockKey, IconMotion.none),
    };
    return Semantics(
      label: 'Estado: ${phase.label}',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            MotionIcon(icon, color: color, size: 14, motion: motion,
                halo: phase == EvalPhase.open),
            const SizedBox(width: 5),
            Text(phase.label,
                style: GoogleFonts.poppins(
                    fontSize: 11.5, fontWeight: FontWeight.w700, color: color)),
          ]),
        ),
      ),
    );
  }
}

// ── Marco neón ───────────────────────────────────────────────────────────────

/// Contenedor de vidrio con un borde de degradado que gira lentamente.
class NeonFrame extends StatefulWidget {
  const NeonFrame({
    super.key,
    required this.child,
    required this.colors,
    this.radius = 22,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
  });

  final Widget child;
  final List<Color> colors;
  final double radius;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  State<NeonFrame> createState() => _NeonFrameState();
}

class _NeonFrameState extends State<NeonFrame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 7));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) {
      _c.stop();
      _c.value = 0.1;
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final r = BorderRadius.circular(widget.radius);
    final card = CustomPaint(
      foregroundPainter: _FramePainter(_c, widget.colors, widget.radius),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: r,
          gradient: LinearGradient(
            colors: [
              widget.colors.first.withValues(alpha: 0.12),
              widget.colors.last.withValues(alpha: 0.07),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          color: t.glass,
          boxShadow: [
            BoxShadow(
                color: widget.colors.first.withValues(alpha: 0.22),
                blurRadius: 24, offset: const Offset(0, 8)),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: r,
            onTap: widget.onTap,
            child: Padding(padding: widget.padding, child: widget.child),
          ),
        ),
      ),
    );
    return RepaintBoundary(
      child: widget.onTap == null ? card : Pressable(onTap: widget.onTap, child: card),
    );
  }
}

class _FramePainter extends CustomPainter {
  _FramePainter(this.t, this.colors, this.radius) : super(repaint: t);
  final Animation<double> t;
  final List<Color> colors;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
        (Offset.zero & size).deflate(0.8), Radius.circular(radius));
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..shader = SweepGradient(
          colors: [
            colors.first,
            colors.last,
            colors.first.withValues(alpha: 0.05),
            colors.first.withValues(alpha: 0.05),
            colors.first,
          ],
          stops: const [0, 0.3, 0.55, 0.8, 1],
          transform: GradientRotation(t.value * 2 * math.pi),
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(covariant _FramePainter old) => old.colors != colors;
}

// ── Chispas de celebración ───────────────────────────────────────────────────

/// Ráfaga de partículas de un solo disparo (al enviar la evaluación).
class SparkBurst extends StatefulWidget {
  const SparkBurst({super.key, required this.colors, this.size = 260});
  final List<Color> colors;
  final double size;

  @override
  State<SparkBurst> createState() => _SparkBurstState();
}

class _SparkBurstState extends State<SparkBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1700));
  final _rng = math.Random(7);
  late final List<_Spark> _sparks = List.generate(
      40,
      (i) => _Spark(
            angle: _rng.nextDouble() * 2 * math.pi,
            speed: 0.45 + _rng.nextDouble() * 0.55,
            size: 2 + _rng.nextDouble() * 3.2,
            colorIndex: i % widget.colors.length,
          ));

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted && !(MediaQuery.maybeDisableAnimationsOf(context) ?? false)) {
        _c.forward();
      }
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: ExcludeSemantics(
          child: SizedBox.square(
            dimension: widget.size,
            child: CustomPaint(painter: _SparkPainter(_c, _sparks, widget.colors)),
          ),
        ),
      );
}

class _Spark {
  const _Spark({required this.angle, required this.speed, required this.size, required this.colorIndex});
  final double angle, speed, size;
  final int colorIndex;
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.t, this.sparks, this.colors) : super(repaint: t);
  final Animation<double> t;
  final List<_Spark> sparks;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final k = Curves.easeOutCubic.transform(t.value);
    for (final s in sparks) {
      final d = s.speed * k * size.width / 2;
      final p = c + Offset(math.cos(s.angle), math.sin(s.angle)) * d;
      final a = (1 - t.value).clamp(0.0, 1.0);
      final col = colors[s.colorIndex].withValues(alpha: a);
      canvas.drawCircle(p, s.size * (1 - t.value * 0.5), Paint()..color = col);
      canvas.drawCircle(p, s.size * 2.4,
          Paint()..color = col.withValues(alpha: a * 0.3)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    }
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) => false;
}

// ── Radar de dimensiones ─────────────────────────────────────────────────────

/// Radar (telaraña) con el promedio por dimensión. Con menos de 3 dimensiones
/// no tiene forma de polígono: se usan barras.
class DimensionRadar extends StatelessWidget {
  const DimensionRadar({super.key, required this.values, this.height = 230});
  final Map<String, double> values;
  final double height;

  String _corto(String s) => s.length > 15 ? '${s.substring(0, 14)}…' : s;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final acc = EvalColors.accent(context);
    final names = values.keys.toList();
    final summary = names
        .map((n) => '$n ${values[n]!.toStringAsFixed(1)}')
        .join(', ');

    if (names.length < 3) {
      return Column(children: [
        for (final n in names) _barra(context, n, values[n]!),
      ]);
    }
    return Semantics(
      label: 'Gráfico de radar por dimensión: $summary',
      child: ExcludeSemantics(
        child: SizedBox(
          height: height,
          child: RadarChart(
            RadarChartData(
              radarShape: RadarShape.polygon,
              tickCount: 5,
              ticksTextStyle: const TextStyle(color: Colors.transparent, fontSize: 0),
              tickBorderData: BorderSide(color: t.border, width: 1),
              gridBorderData: BorderSide(color: t.border, width: 1),
              radarBorderData: BorderSide(color: t.border, width: 1),
              radarBackgroundColor: Colors.transparent,
              titlePositionPercentageOffset: 0.16,
              titleTextStyle: GoogleFonts.poppins(
                  fontSize: 10.5, color: t.muted, fontWeight: FontWeight.w500),
              getTitle: (i, _) => RadarChartTitle(text: _corto(names[i])),
              dataSets: [
                // Fija la escala 0–5 (invisible).
                RadarDataSet(
                  fillColor: Colors.transparent,
                  borderColor: Colors.transparent,
                  entryRadius: 0,
                  borderWidth: 0,
                  dataEntries: [for (final _ in names) const RadarEntry(value: 5)],
                ),
                RadarDataSet(
                  fillColor: acc.first.withValues(alpha: 0.28),
                  borderColor: acc.first,
                  entryRadius: 3.5,
                  borderWidth: 2.4,
                  dataEntries: [for (final n in names) RadarEntry(value: values[n]!)],
                ),
              ],
            ),
            swapAnimationDuration: const Duration(milliseconds: 700),
          ),
        ),
      ),
    );
  }

  Widget _barra(BuildContext context, String name, double v) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(
          flex: 3,
          child: Text(name,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(fontSize: 12, color: t.muted)),
        ),
        Expanded(flex: 5, child: ScoreBar(value: v)),
        const SizedBox(width: 8),
        Text(v.toStringAsFixed(1),
            style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

/// Barra horizontal 0–5 con degradado y resplandor, de ancho animado.
class ScoreBar extends StatelessWidget {
  const ScoreBar({super.key, required this.value, this.height = 8});
  final double value;
  final double height;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final col = EvalColors.score(value, t);
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: Container(
          height: height,
          color: t.border,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: (value / 5).clamp(0.0, 1.0)),
            duration: reduce ? Duration.zero : const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (_, k, __) => FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: k,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [col.withValues(alpha: 0.6), col]),
                  boxShadow: [BoxShadow(color: col.withValues(alpha: 0.6), blurRadius: 6)],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
