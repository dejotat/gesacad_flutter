import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../config/app_tokens.dart';

/// Fila de [BarList]: etiqueta completa, valor y etiqueta de valor opcional.
class BarItem {
  const BarItem(this.label, this.value, {this.valueLabel, this.color});
  final String label;
  final double value;

  /// Texto mostrado a la derecha ("12", "4.2"). Por defecto, el valor entero.
  final String? valueLabel;

  /// Color propio de la barra; si es null se rota la paleta de gráficos.
  final Color? color;
}

/// Barras horizontales premium: degradado análogo por barra, brillo del mismo
/// color, reflejo de cristal, extremo redondeado y crecimiento escalonado.
/// El nombre queda completo (sin truncar a 8 caracteres).
class BarList extends StatelessWidget {
  const BarList({
    super.key,
    required this.items,
    required this.color,
    this.max,
    this.rotateColors = false,
  });

  final List<BarItem> items;

  /// Color por defecto de las barras sin color propio.
  final Color color;

  /// Valor que llena la barra completa. Por defecto, el mayor de la lista.
  final double? max;

  /// Si es true, cada barra sin color propio toma uno distinto de la paleta.
  final bool rotateColors;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final top = max ??
        items.fold<double>(0, (m, i) => i.value > m ? i.value : m);
    final denom = top <= 0 ? 1.0 : top;

    return Column(
      children: [
        for (var idx = 0; idx < items.length; idx++)
          Builder(builder: (context) {
            final i = items[idx];
            final base = i.color ??
                (rotateColors ? t.chart[idx % t.chart.length] : color);
            final cols = AppTokens.gradientOf(base);
            final frac = (i.value / denom).clamp(0.0, 1.0);

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(i.label,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                            fontSize: 13, fontWeight: FontWeight.w500,
                            color: onSurface)),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: base.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(i.valueLabel ?? i.value.toStringAsFixed(0),
                        style: GoogleFonts.poppins(
                            fontSize: 12, fontWeight: FontWeight.w700,
                            color: base)),
                  ),
                ]),
                const SizedBox(height: 6),
                LayoutBuilder(builder: (context, c) {
                  return TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: frac),
                    duration: reduce
                        ? Duration.zero
                        : Duration(milliseconds: 700 + idx * 90),
                    curve: Curves.easeOutCubic,
                    builder: (_, v, __) {
                      final w = c.maxWidth * v;
                      return SizedBox(
                        height: 14,
                        child: Stack(children: [
                          // Pista
                          Container(
                            decoration: BoxDecoration(
                              color: onSurface.withValues(alpha: 0.07),
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          if (w > 0)
                            // Barra con degradado, halo y reflejo
                            Container(
                              width: w < 14 ? 14 : w,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(colors: cols),
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: [
                                  BoxShadow(
                                    color: base.withValues(alpha: 0.45),
                                    blurRadius: 10,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Align(
                                alignment: Alignment.topCenter,
                                child: FractionallySizedBox(
                                  widthFactor: 0.92,
                                  heightFactor: 0.36,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.30),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ]),
                      );
                    },
                  );
                }),
              ]),
            );
          }),
      ],
    );
  }
}

/// Columnas verticales con degradado, halo y crecimiento animado: para
/// histogramas y comparaciones con pocas categorías.
class GradientColumns extends StatelessWidget {
  const GradientColumns({
    super.key,
    required this.items,
    this.height = 200,
    this.max,
  });

  final List<BarItem> items;
  final double height;
  final double? max;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final top = max ??
        items.fold<double>(0, (m, i) => i.value > m ? i.value : m);
    final denom = top <= 0 ? 1.0 : top;
    const labelH = 22.0;   // etiqueta inferior
    const valueH = 22.0;   // valor superior
    final plotH = height - labelH - valueH;

    return SizedBox(
      height: height,
      child: Stack(children: [
        // Líneas guía
        Positioned.fill(
          top: valueH,
          bottom: labelH,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var k = 0; k < 4; k++)
                Container(height: 1, color: onSurface.withValues(alpha: 0.06)),
            ],
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var idx = 0; idx < items.length; idx++)
              Expanded(
                child: Builder(builder: (context) {
                  final i = items[idx];
                  final base = i.color ?? t.chart[idx % t.chart.length];
                  final cols = AppTokens.gradientOf(base);
                  final frac = (i.value / denom).clamp(0.0, 1.0);
                  return TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: frac),
                    duration: reduce
                        ? Duration.zero
                        : Duration(milliseconds: 700 + idx * 110),
                    curve: Curves.easeOutBack,
                    builder: (_, v, __) {
                      var h = (plotH * v).clamp(0.0, plotH);
                      // Altura mínima visible para valores pequeños (> 0).
                      if (i.value > 0 && h < 6) h = 6;
                      return Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          SizedBox(
                            height: valueH,
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: Text(
                                i.valueLabel ?? i.value.toStringAsFixed(0),
                                style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: base),
                              ),
                            ),
                          ),
                          SizedBox(height: plotH - h),
                          Container(
                            width: 30,
                            height: h,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [cols[1], cols[0]],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(10)),
                              boxShadow: [
                                BoxShadow(
                                  color: base.withValues(alpha: 0.40),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Align(
                              alignment: Alignment.topCenter,
                              child: FractionallySizedBox(
                                widthFactor: 0.30,
                                heightFactor: 0.8,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.28),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          SizedBox(
                            height: labelH,
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: Text(i.label,
                                  style: GoogleFonts.poppins(
                                      fontSize: 12, color: t.muted)),
                            ),
                          ),
                        ],
                      );
                    },
                  );
                }),
              ),
          ],
        ),
      ]),
    );
  }
}
