import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../config/app_tokens.dart';
import 'motion_icon.dart';

/// Estado vacío (no hay datos): ícono flotante sobre un halo de color.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final primary = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 96, height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                primary.withValues(alpha: 0.22),
                primary.withValues(alpha: 0.04),
              ]),
              border: Border.all(color: primary.withValues(alpha: 0.18)),
            ),
            child: Center(
              child: MotionIcon(icon, color: primary, size: 44, glow: true),
            ),
          ),
          const SizedBox(height: 16),
          Text(message,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(fontSize: 14, color: t.muted, height: 1.5)),
        ]),
      ),
    );
  }
}

/// Estado de error con reintento (distinto de "sin datos"). Se anuncia al aparecer.
class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 96, height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                t.danger.withValues(alpha: 0.22),
                t.danger.withValues(alpha: 0.04),
              ]),
              border: Border.all(color: t.danger.withValues(alpha: 0.18)),
            ),
            child: Center(
              child: MotionIcon(Icons.cloud_off_rounded,
                  color: t.danger, size: 44, motion: IconMotion.wiggle, glow: true),
            ),
          ),
          const SizedBox(height: 16),
          Semantics(
            liveRegion: true,
            child: Text(message,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(fontSize: 14, color: t.muted, height: 1.5)),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Reintentar'),
          ),
        ]),
      ),
    );
  }
}

/// Bloque para esqueletos de carga: vidrio con destello que recorre la tarjeta.
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({super.key, this.height = 80, this.width});
  final double height;
  final double? width;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1500))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final base = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.07);
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final x = reduce ? 0.0 : -1.0 + 3.0 * _c.value;
        return Container(
          height: widget.height,
          width: widget.width,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTokens.radiusCard),
            border: Border.all(color: t.border),
            gradient: LinearGradient(
              colors: [base, t.glassHighlight, base],
              stops: const [0.0, 0.5, 1.0],
              begin: Alignment(x - 1, 0),
              end: Alignment(x + 1, 0),
            ),
          ),
        );
      },
    );
  }
}
