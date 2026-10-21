import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import '../../config/app_tokens.dart';
import 'animated_buttons.dart';

/// Panel de vidrio: relleno translúcido con brillo en la esquina superior,
/// desenfoque del fondo, borde de luz y sombra suave. Usa `blur: false` en
/// listas largas (mantiene la translucidez sin el costo del desenfoque).
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.blur = true,
    this.radius = AppTokens.radiusCard,
    this.tint,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final bool blur;
  final double radius;

  /// Color que se mezcla sobre el vidrio (p. ej. un estado de color suave).
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final r = BorderRadius.circular(radius);

    Widget panel = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [t.glassHighlight, t.glass],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: r,
        border: Border.all(color: t.glassBorder),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: tint == null
              ? null
              : LinearGradient(
                  colors: [
                    tint!.withValues(alpha: 0.16),
                    tint!.withValues(alpha: 0.04),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
          borderRadius: r,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: r,
            onTap: onTap,
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );

    if (blur) {
      panel = ClipRRect(
        borderRadius: r,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: panel,
        ),
      );
    }

    final card = DecoratedBox(
      decoration: BoxDecoration(borderRadius: r, boxShadow: t.cardShadow),
      child: panel,
    );
    // Las tarjetas tocables responden con resorte y elevación al cursor.
    return onTap == null ? card : Pressable(onTap: onTap, child: card);
  }
}
