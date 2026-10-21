import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../config/app_tokens.dart';
import '../../services/settings_service.dart';
import 'motion_icon.dart';

/// Encabezado de dashboard: degradado vivo del tema con destellos de luz
/// translúcidos, saludo, rol y etiquetas. Estático (el movimiento vive en los
/// íconos), con bordes de cristal.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.leading,
    this.chips = const [],
  });

  final String title;
  final String subtitle;
  final Widget? leading;
  final List<Widget> chips;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppThemeType>(
      valueListenable: AppSettings.currentTheme,
      builder: (_, theme, __) {
        final g = theme.gradient;
        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: g,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(AppTokens.radiusCard + 6),
            border: Border.all(color: Colors.white.withValues(alpha: 0.30)),
            boxShadow: [
              BoxShadow(
                color: g[0].withValues(alpha: 0.38),
                blurRadius: 30,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppTokens.radiusCard + 6),
            child: Stack(children: [
              // Destellos de luz translúcidos (decorativos)
              Positioned(
                top: -50, right: -30,
                child: ExcludeSemantics(child: _glow(150, 0.20)),
              ),
              Positioned(
                bottom: -70, left: 60,
                child: ExcludeSemantics(child: _glow(170, 0.12)),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(children: [
                  if (leading != null) ...[leading!, const SizedBox(width: 16)],
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Semantics(
                        header: true,
                        child: Text(title,
                            style: GoogleFonts.poppins(
                                fontSize: 21, fontWeight: FontWeight.w600,
                                color: Colors.white)),
                      ),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style: GoogleFonts.poppins(
                              fontSize: 13,
                              color: Colors.white.withValues(alpha: 0.92))),
                      if (chips.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Wrap(spacing: 8, runSpacing: 8, children: chips),
                      ],
                    ]),
                  ),
                ]),
              ),
            ]),
          ),
        );
      },
    );
  }

  Widget _glow(double size, double alpha) => Container(
        width: size, height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [
            Colors.white.withValues(alpha: alpha),
            Colors.white.withValues(alpha: 0),
          ]),
        ),
      );
}

/// Etiqueta de cristal para el encabezado (rol, total de cursos…).
class HeaderChip extends StatelessWidget {
  const HeaderChip(this.icon, this.label, {super.key});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.20),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        MotionIcon(icon, color: Colors.white, size: 14, motion: IconMotion.pulse),
        const SizedBox(width: 6),
        Text(label,
            style: GoogleFonts.poppins(
                fontSize: 12, fontWeight: FontWeight.w500, color: Colors.white)),
      ]),
    );
  }
}
