import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../config/app_tokens.dart';
import 'app_card.dart';
import 'motion_icon.dart';

/// Indicador (KPI): ícono animado sobre un azulejo con degradado, valor grande
/// que "cuenta" hasta su valor final y etiqueta.
/// Se anuncia como un solo elemento ("Estudiantes: 120").
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
    this.hint,
    this.motion = IconMotion.float,
    this.delay = Duration.zero,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;

  /// Línea de contexto opcional ("de 12 cursos").
  final String? hint;

  /// Movimiento del ícono y retraso de su entrada (para escalonar tarjetas).
  final IconMotion motion;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final cols = AppTokens.gradientOf(color);
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final target = int.tryParse(value);

    final valueStyle = GoogleFonts.poppins(
        fontSize: 26, fontWeight: FontWeight.w700, color: onSurface, height: 1.1);

    return Semantics(
      label: '$label: $value${hint != null ? ', $hint' : ''}',
      child: ExcludeSemantics(
        child: AppCard(
          tint: color,
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(
              width: 46, height: 46,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: cols,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(AppTokens.radiusControl),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.45),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Center(
                child: MotionIcon(icon,
                    color: Colors.white, size: 24, motion: motion, delay: delay),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (target != null && !reduce)
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: target.toDouble()),
                    duration: const Duration(milliseconds: 1100),
                    curve: Curves.easeOutCubic,
                    builder: (_, v, __) => Text('${v.round()}', style: valueStyle),
                  )
                else
                  Text(value, style: valueStyle),
                Text(label,
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(fontSize: 12, color: t.muted, height: 1.25)),
                if (hint != null)
                  Text(hint!,
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                          fontSize: 12, fontWeight: FontWeight.w600, color: color)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
