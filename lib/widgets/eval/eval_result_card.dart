import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../config/app_tokens.dart';
import '../../models/evaluation_models.dart';
import '../ui/ui.dart';
import 'eval_widgets.dart';

/// Resultado de un curso: puntaje global, radar por dimensión, detalle por
/// pregunta y (solo si [showComments]) comentarios abiertos.
///
/// Si el curso no alcanzó el mínimo de respuestas ([EvalResult.hidden]) solo se
/// muestra la participación: es la protección del anonimato.
class EvalResultCard extends StatefulWidget {
  const EvalResultCard({super.key, required this.result, this.showComments = false});

  final EvalResult result;
  final bool showComments;

  @override
  State<EvalResultCard> createState() => _EvalResultCardState();
}

class _EvalResultCardState extends State<EvalResultCard> {
  bool _detail = false;
  bool _comments = false;

  EvalResult get r => widget.result;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final acc = EvalColors.accent(context);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final pct = (r.participation * 100).round();

    return Semantics(
      container: true,
      label: 'Resultados de ${r.courseName}, docente ${r.teacherName}. '
          '${r.hidden ? "Protegido: ${r.responses} respuestas, mínimo ${r.minResponses}." : "Puntaje ${r.overall?.toStringAsFixed(1) ?? "sin datos"} de 5."} '
          '${r.responses} de ${r.enrolled} estudiantes respondieron.',
      child: AppCard(
        blur: false,
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            HexMedallion(
              r.hidden ? PhosphorIconsFill.lockKey : PhosphorIconsFill.chalkboardTeacher,
              colors: r.hidden ? [t.muted, t.border] : acc,
              size: 44,
              orbit: !r.hidden,
              motion: r.hidden ? IconMotion.none : IconMotion.float,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.courseName,
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                        fontSize: 15, fontWeight: FontWeight.w700, color: onSurface)),
                Text(r.teacherName,
                    style: GoogleFonts.poppins(fontSize: 12.5, color: t.muted)),
              ]),
            ),
            if (!r.hidden && r.overall != null)
              ScoreRing(value: r.overall!, size: 78, caption: 'de 5'),
          ]),
          const SizedBox(height: 14),
          // Participación
          Row(children: [
            Icon(PhosphorIconsRegular.usersThree, size: 16, color: t.muted),
            const SizedBox(width: 6),
            Expanded(
              child: Text('${r.responses} de ${r.enrolled} estudiantes respondieron · $pct%',
                  style: GoogleFonts.poppins(fontSize: 12, color: t.muted)),
            ),
          ]),
          const SizedBox(height: 6),
          ScoreBar(value: r.participation * 5, height: 6),
          const SizedBox(height: 14),
          if (r.hidden) _privacyPanel(context) else ..._content(context),
        ]),
      ),
    );
  }

  Widget _privacyPanel(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppTokens.radiusControl),
        border: Border.all(color: t.warning.withValues(alpha: 0.35)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        MotionIcon(PhosphorIconsRegular.shieldCheck,
            color: t.warning, size: 22, motion: IconMotion.pulse),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Resultados protegidos. Solo hay ${r.responses} '
            '${r.responses == 1 ? "respuesta" : "respuestas"} y se necesitan al menos '
            '${r.minResponses} para mostrar datos sin poder identificar a nadie.',
            style: GoogleFonts.poppins(fontSize: 12.5, height: 1.45),
          ),
        ),
      ]),
    );
  }

  List<Widget> _content(BuildContext context) {
    final t = context.tokens;
    final dims = r.byDimension;
    return [
      Text('Por dimensión',
          style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: t.muted)),
      const SizedBox(height: 4),
      DimensionRadar(values: dims),
      if (dims.length >= 3) ...[
        const SizedBox(height: 4),
        Wrap(spacing: 8, runSpacing: 6, children: [
          for (final e in dims.entries)
            _dimChip(context, e.key, e.value),
        ]),
      ],
      const SizedBox(height: 10),
      _toggle(
        icon: PhosphorIconsRegular.listChecks,
        label: _detail ? 'Ocultar detalle por pregunta' : 'Ver detalle por pregunta',
        open: _detail,
        onTap: () => setState(() => _detail = !_detail),
      ),
      AnimatedSize(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: _detail
            ? Column(children: [
                const SizedBox(height: 6),
                for (final q in r.questions) _questionRow(context, q),
              ])
            : const SizedBox(width: double.infinity),
      ),
      if (widget.showComments && r.comments.isNotEmpty) ...[
        const SizedBox(height: 4),
        _toggle(
          icon: PhosphorIconsRegular.chatCircleText,
          label: 'Comentarios (${r.comments.length})',
          open: _comments,
          onTap: () => setState(() => _comments = !_comments),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _comments
              ? Column(children: [
                  const SizedBox(height: 6),
                  for (final c in r.comments) _comment(context, c),
                ])
              : const SizedBox(width: double.infinity),
        ),
      ],
    ];
  }

  Widget _dimChip(BuildContext context, String name, double v) {
    final col = EvalColors.score(v, context.tokens);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: col.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text('$name · ${v.toStringAsFixed(1)}',
          style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: col)),
    );
  }

  Widget _toggle({
    required IconData icon,
    required String label,
    required bool open,
    required VoidCallback onTap,
  }) {
    final primary = Theme.of(context).colorScheme.primary;
    return Semantics(
      button: true,
      expanded: open,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            Icon(icon, size: 18, color: primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(label,
                  style: GoogleFonts.poppins(
                      fontSize: 13, fontWeight: FontWeight.w600, color: primary)),
            ),
            AnimatedRotation(
              turns: open ? 0.5 : 0,
              duration: const Duration(milliseconds: 250),
              child: Icon(PhosphorIconsRegular.caretDown, size: 16, color: primary),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _questionRow(BuildContext context, EvalQuestionResult q) {
    final t = context.tokens;
    final total = q.distribution.fold<int>(0, (a, b) => a + b);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(q.text, style: GoogleFonts.poppins(fontSize: 12.5, height: 1.35)),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(child: ScoreBar(value: q.avg ?? 0)),
          const SizedBox(width: 8),
          Text(q.avg?.toStringAsFixed(2) ?? '—',
              style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 6),
        // Distribución 1..5
        Row(children: [
          for (var i = 0; i < 5; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Semantics(
                  label: '${q.distribution[i]} respuestas con ${i + 1}',
                  child: ExcludeSemantics(
                    child: Column(children: [
                      Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: EvalColors.score((i + 1).toDouble(), t).withValues(
                              alpha: total == 0 ? 0.15 : 0.25 + 0.75 * (q.distribution[i] / total)),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text('${i + 1}: ${q.distribution[i]}',
                          style: GoogleFonts.poppins(fontSize: 10, color: t.muted)),
                    ]),
                  ),
                ),
              ),
            ),
        ]),
      ]),
    );
  }

  Widget _comment(BuildContext context, String text) {
    final t = context.tokens;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.glass,
        borderRadius: BorderRadius.circular(AppTokens.radiusControl),
        border: Border.all(color: t.glassBorder),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(PhosphorIconsFill.quotes, size: 16, color: t.muted),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: GoogleFonts.poppins(fontSize: 12.5, height: 1.45))),
      ]),
    );
  }
}
