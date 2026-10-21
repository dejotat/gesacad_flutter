import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../config/app_tokens.dart';
import '../models/activity_model.dart';
import '../utils/activity_type.dart';
import 'ui/ui.dart';

/// Tarjeta de actividad en la lista de un curso.
///
/// Muestra tipo, ponderado y estado (entregada, calificada, plazo vencido).
/// Es la misma para estudiantes y profesores; [onDelete] solo lo pasa el profesor.
///
/// Accesibilidad (CU-07): la tarjeta se anuncia como un solo botón con el estado.
class ActivityCard extends StatelessWidget {
  final ActivityModel activity;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const ActivityCard({
    super.key,
    required this.activity,
    required this.onTap,
    this.onDelete,
  });

  /// Descripción accesible del estado actual de la actividad para TalkBack (CU-07).
  String _semanticLabel(String typeLabel) {
    final weightStr =
        '${(activity.weighting * 100).toStringAsFixed(0)} por ciento';
    final base = 'Actividad ${activity.tittle}, tipo $typeLabel, ponderado $weightStr';
    if (activity.gpa != null) {
      return '$base, calificación ${activity.gpa!.toStringAsFixed(1)} de 5.';
    }
    if (activity.isDelivered) return '$base, entregada, pendiente de calificación.';
    if (activity.isPastDue) return '$base, plazo vencido.';
    return '$base, pendiente de entrega.';
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final info = ActivityTypeInfo.of(activity.type);
    final color = ActivityTypeInfo.colorOf(activity.type, t);

    return Semantics(
      label: _semanticLabel(info.label),
      hint: 'Toca dos veces para ver el detalle de la actividad',
      button: true,
      excludeSemantics: onDelete == null,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.pagePadding, vertical: 5),
        child: AppCard(
          blur: false,
          onTap: onTap,
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          child: Row(children: [
            IconMedallion(info.icon,
                size: 46,
                colors: AppTokens.gradientOf(color),
                motion: info.motion,
                orbit: false),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(activity.tittle,
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                          fontSize: 14, fontWeight: FontWeight.w600,
                          color: onSurface)),
                  const SizedBox(height: 6),
                  Wrap(spacing: 8, runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                    _pill(info.label, color),
                    Text('${(activity.weighting * 100).toStringAsFixed(0)}%',
                        style: GoogleFonts.poppins(
                            fontSize: 12, color: t.muted)),
                    if (activity.gpa != null)
                      _pill('Nota ${activity.gpa!.toStringAsFixed(1)} / 5.0',
                          t.success, icon: PhosphorIconsFill.checkCircle)
                    else if (activity.isDelivered)
                      _pill('Entregado', t.info,
                          icon: PhosphorIconsRegular.paperPlaneTilt)
                    else if (activity.isPastDue)
                      _pill('Plazo vencido', t.danger,
                          icon: PhosphorIconsRegular.clock),
                  ]),
                ],
              ),
            ),
            if (onDelete != null)
              AnimatedIconButton(
                icon: PhosphorIconsRegular.trash,
                color: t.danger,
                reaction: IconReaction.shake,
                onPressed: onDelete,
                tooltip: 'Eliminar actividad ${activity.tittle}',
              ),
            ExcludeSemantics(
              child: Icon(PhosphorIconsRegular.caretRight,
                  color: t.muted, size: 18),
            ),
            const SizedBox(width: 6),
          ]),
        ),
      ),
    );
  }

  Widget _pill(String text, Color color, {IconData? icon}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(text,
              style: GoogleFonts.poppins(
                  fontSize: 12, fontWeight: FontWeight.w600, color: color)),
        ]),
      );
}
