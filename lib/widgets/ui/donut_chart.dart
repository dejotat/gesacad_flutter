import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../config/app_tokens.dart';

/// Segmento de [DonutChart].
class DonutSlice {
  const DonutSlice(this.label, this.value, this.color);
  final String label;
  final int value;
  final Color color;
}

/// Dona premium pintada a medida: arcos con degradado y extremos redondeados,
/// brillo (glow) del color de cada segmento, reflejo de cristal y barrido
/// animado al aparecer. Toca un segmento o su fila de leyenda para resaltarlo.
///
/// La gráfica es decorativa para el lector de pantalla: [summary] ya describe
/// todos los valores.
class DonutChart extends StatefulWidget {
  const DonutChart({
    super.key,
    required this.slices,
    required this.centerValue,
    required this.centerLabel,
    required this.summary,
    this.height = 190,
  });

  final List<DonutSlice> slices;
  final String centerValue;
  final String centerLabel;

  /// Descripción en texto de la gráfica para TalkBack.
  final String summary;
  final double height;

  @override
  State<DonutChart> createState() => _DonutChartState();
}

class _DonutChartState extends State<DonutChart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  int? _touched;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100))
      ..forward();
  }

  @override
  void didUpdateWidget(covariant DonutChart old) {
    super.didUpdateWidget(old);
    final a = old.slices.map((s) => s.value).toList();
    final b = widget.slices.map((s) => s.value).toList();
    if (a.length != b.length || !_same(a, b)) _ctrl.forward(from: 0);
  }

  bool _same(List<int> a, List<int> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  static const double _ringFraction = 0.25;

  /// Índice del segmento bajo el punto [p] (null si cae fuera del anillo).
  int? _hit(Offset p, double side, int total) {
    if (total == 0) return null;
    final c = Offset(side / 2, side / 2);
    final r = side / 2 - 12;
    final sw = r * _ringFraction * 2;
    final d = (p - c).distance;
    if (d < r - sw || d > r + 6) return null;
    var ang = math.atan2(p.dy - c.dy, p.dx - c.dx) + math.pi / 2;
    if (ang < 0) ang += 2 * math.pi;
    const minFrac = 0.045;
    final fracs = [
      for (final s in widget.slices)
        s.value == 0 ? 0.0 : math.max(s.value / total, minFrac),
    ];
    final sum = fracs.fold<double>(0, (a, b) => a + b);
    var acc = 0.0;
    for (var i = 0; i < fracs.length; i++) {
      acc += fracs[i] / sum * 2 * math.pi;
      if (ang <= acc && widget.slices[i].value > 0) return i;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final total = widget.slices.fold<int>(0, (s, e) => s + e.value);
    final side = widget.height;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce && _ctrl.value < 1) _ctrl.value = 1;

    return Semantics(
      label: widget.summary,
      child: Column(children: [
        ExcludeSemantics(
          child: SizedBox(
            width: side,
            height: side,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) {
                final i = _hit(d.localPosition, side, total);
                setState(() => _touched = (i == null || _touched == i) ? null : i);
              },
              child: Stack(alignment: Alignment.center, children: [
                AnimatedBuilder(
                  animation: _ctrl,
                  builder: (_, __) => CustomPaint(
                    size: Size(side, side),
                    painter: _DonutPainter(
                      slices: widget.slices,
                      progress: Curves.easeOutCubic.transform(_ctrl.value),
                      touched: _touched,
                      track: onSurface.withValues(alpha: 0.08),
                      ringFraction: _ringFraction,
                    ),
                  ),
                ),
                AnimatedBuilder(
                  animation: _ctrl,
                  builder: (_, child) => Opacity(
                    opacity: Curves.easeIn.transform(_ctrl.value),
                    child: Transform.scale(
                      scale: 0.85 + 0.15 * Curves.easeOutBack.transform(_ctrl.value.clamp(0.0, 1.0)),
                      child: child,
                    ),
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(widget.centerValue,
                        style: GoogleFonts.poppins(
                            fontSize: side * 0.15,
                            fontWeight: FontWeight.w700,
                            height: 1.05,
                            color: onSurface)),
                    Text(widget.centerLabel,
                        style: GoogleFonts.poppins(
                            fontSize: 12, color: t.muted)),
                  ]),
                ),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 10),
        for (var i = 0; i < widget.slices.length; i++)
          ExcludeSemantics(
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => setState(() => _touched = _touched == i ? null : i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: _touched == i
                      ? widget.slices[i].color.withValues(alpha: 0.14)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(children: [
                  Container(
                    width: 12, height: 12,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                          colors: AppTokens.gradientOf(widget.slices[i].color)),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: widget.slices[i].color.withValues(alpha: 0.55),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(widget.slices[i].label,
                        style: GoogleFonts.poppins(fontSize: 13, color: onSurface)),
                  ),
                  Text('${widget.slices[i].value}',
                      style: GoogleFonts.poppins(
                          fontSize: 14, fontWeight: FontWeight.w700,
                          color: onSurface)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: widget.slices[i].color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      total > 0
                          ? '${(widget.slices[i].value / total * 100).round()}%'
                          : '0%',
                      style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: widget.slices[i].color),
                    ),
                  ),
                ]),
              ),
            ),
          ),
      ]),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.slices,
    required this.progress,
    required this.touched,
    required this.track,
    required this.ringFraction,
  });

  final List<DonutSlice> slices;
  final double progress;
  final int? touched;
  final Color track;
  final double ringFraction;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 12;
    final sw = r * ringFraction * 2;
    final rect = Rect.fromCircle(center: c, radius: r - sw / 2);
    final total = slices.fold<int>(0, (s, e) => s + e.value);

    // Pista de fondo
    canvas.drawArc(
      rect, 0, 2 * math.pi, false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = sw
        ..color = track,
    );
    if (total == 0) return;

    final visible = slices.where((s) => s.value > 0).length;
    final radius = r - sw / 2;
    // Fracción mínima visible: un segmento de 2% sigue siendo legible.
    const minFrac = 0.045;
    final fracs = [
      for (final s in slices) s.value == 0 ? 0.0 : math.max(s.value / total, minFrac),
    ];
    final fracSum = fracs.fold<double>(0, (a, b) => a + b);
    var start = -math.pi / 2;

    for (var i = 0; i < slices.length; i++) {
      final s = slices[i];
      if (s.value == 0) continue;
      final full = fracs[i] / fracSum * 2 * math.pi;
      final isTouched = touched == i;
      final w = sw + (isTouched ? 8 : 0);

      // Extremos redondeados solo si el arco es lo bastante largo; si no, una
      // mancha más ancha que el segmento tapa a sus vecinos.
      final roundCaps = visible > 1 && full * radius > sw * 2.2;
      final capComp = roundCaps ? (sw * 0.5) / radius : 0.0;
      final gap = visible > 1 ? capComp * 2 + 0.035 : 0.0;
      final arcStart = start + gap / 2;
      final sweep = math.max(0.0, (full - gap) * progress);
      start += full * progress;
      if (sweep <= 0.001) continue;

      final cols = AppTokens.gradientOf(s.color);
      final paintColor = sweep > 0.5
          ? null
          : s.color; // arco corto: color sólido, el degradado no se luce
      final shader = SweepGradient(
        startAngle: 0,
        endAngle: sweep,
        colors: [cols[0], cols[1]],
        transform: GradientRotation(arcStart),
      ).createShader(rect);

      final cap = roundCaps ? StrokeCap.round : StrokeCap.butt;

      // Halo de luz
      canvas.drawArc(
        rect, arcStart, sweep, false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w + 4
          ..strokeCap = cap
          ..color = s.color.withValues(alpha: isTouched ? 0.55 : 0.32)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, isTouched ? 12 : 8),
      );
      // Arco principal con degradado
      final main = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w
        ..strokeCap = cap;
      if (paintColor == null) {
        main.shader = shader;
      } else {
        main.color = paintColor;
      }
      canvas.drawArc(rect, arcStart, sweep, false, main);

      // Reflejo de cristal en el borde exterior
      if (sweep > 0.25) {
        final shine = Rect.fromCircle(center: c, radius: radius + w * 0.34);
        canvas.drawArc(
          shine, arcStart + 0.06, math.max(0.0, sweep - 0.12), false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = w * 0.10
            ..strokeCap = StrokeCap.round
            ..color = Colors.white.withValues(alpha: 0.30),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.progress != progress ||
      old.touched != touched ||
      old.track != track ||
      old.slices != slices;
}
