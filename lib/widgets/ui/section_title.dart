import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../config/app_tokens.dart';
import 'motion_icon.dart';

/// Título de sección con ícono animado sobre un azulejo con degradado y
/// subtítulo opcional.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title,
      {super.key, this.icon, this.subtitle, this.motion = IconMotion.pulse});

  final String title;
  final IconData? icon;
  final String? subtitle;
  final IconMotion motion;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cols = AppTokens.gradientOf(cs.primary);
    return Semantics(
      header: true,
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        if (icon != null) ...[
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                  colors: cols,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(11),
              boxShadow: [
                BoxShadow(
                  color: cs.primary.withValues(alpha: 0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Center(
              child: MotionIcon(icon!,
                  color: Colors.white, size: 19, motion: motion),
            ),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: GoogleFonts.poppins(
                    fontSize: 16, fontWeight: FontWeight.w600, color: cs.onSurface)),
            if (subtitle != null)
              Text(subtitle!,
                  style: GoogleFonts.poppins(
                      fontSize: 12, color: context.tokens.muted)),
          ]),
        ),
      ]),
    );
  }
}
