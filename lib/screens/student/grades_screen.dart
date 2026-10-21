import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../config/app_tokens.dart';
import '../../services/api_service.dart';
import '../../utils/grade_style.dart';
import '../../widgets/ui/ui.dart';

/// Pantalla de calificaciones del estudiante en un curso (CU-06 / RF10).
///
/// Muestra:
/// - Promedio ponderado actual (suma(nota × ponderado) / suma(ponderados)).
/// - Indicador de estado: sobresaliente (≥ 4.0), aprobando (≥ 3.0) o en riesgo (< 3.0).
/// - Lista detallada por actividad con nota y ponderado.
///
/// Escala de calificación colombiana universitaria (0.0 – 5.0); la nota
/// aprobatoria mínima es 3.0 (Decreto 1295 de 2010). Umbrales y colores en
/// [GradeStyle].
///
/// Implementa [Semantics] para compatibilidad con TalkBack (CU-07/RNF03).
class GradesScreen extends StatefulWidget {
  /// ID del curso del que se muestran las calificaciones.
  final int courseId;

  /// ID del estudiante autenticado.
  final int userId;

  /// Nombre del curso para mostrar en el contexto de la pantalla.
  final String courseName;

  const GradesScreen({
    super.key,
    required this.courseId,
    required this.userId,
    required this.courseName,
  });

  @override
  State<GradesScreen> createState() => _GradesScreenState();
}

class _GradesScreenState extends State<GradesScreen> {
  List<Map<String, dynamic>> _grades = [];
  bool _loading = true;
  bool _error = false;

  /// Promedio ponderado; null mientras no haya ninguna actividad calificada.
  double? _promedio;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Carga las calificaciones del estudiante en el curso y calcula el promedio.
  ///
  /// El promedio se calcula como: Σ(nota × ponderado) / Σ(ponderados calificados).
  /// Solo se incluyen actividades con nota asignada (GPA != null) en el cálculo.
  Future<void> _load() async {
    setState(() { _loading = true; _error = false; });
    try {
      _grades =
          await ApiService().getGrades(widget.courseId, widget.userId);
      double total = 0;
      double totalWeight = 0;
      for (final g in _grades) {
        final gpa = double.tryParse(g['GPA']?.toString() ?? '');
        final w = double.tryParse(g['weighting']?.toString() ?? '0') ?? 0;
        if (gpa != null) {
          total += gpa * w;
          totalWeight += w;
        }
      }
      _promedio = totalWeight > 0 ? total / totalWeight : null;
    } catch (_) {
      if (_grades.isEmpty) _error = true;
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Semantics(
        label: 'Cargando calificaciones',
        child: ExcludeSemantics(
          child: ListView(
            padding: const EdgeInsets.all(AppTokens.pagePadding),
            children: const [
              SkeletonBox(height: 120), SizedBox(height: 12),
              SkeletonBox(height: 64), SizedBox(height: 8),
              SkeletonBox(height: 64),
            ],
          ),
        ),
      );
    }
    if (_error) {
      return ErrorState(
        message: 'No se pudieron cargar las calificaciones.',
        onRetry: _load,
      );
    }
    if (_grades.isEmpty) {
      return const EmptyState(
        icon: PhosphorIconsRegular.trophy,
        message: 'No hay calificaciones aún',
      );
    }

    final t = context.tokens;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          padding: const EdgeInsets.all(AppTokens.pagePadding),
          children: [
            _buildPromedio(),
            const SizedBox(height: AppTokens.sectionGap),
            const SectionTitle('Detalle por actividad',
                icon: PhosphorIconsRegular.listChecks),
            const SizedBox(height: 12),
            ..._grades.map((g) {
              final gpa = double.tryParse(g['GPA']?.toString() ?? '');
              final weight =
                  double.tryParse(g['weighting']?.toString() ?? '0') ?? 0;
              final title = g['tittle']?.toString() ?? '';
              final color = GradeStyle.color(gpa, t);

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Semantics(
                  label:
                      'Actividad: $title, ponderado: ${(weight * 100).toStringAsFixed(0)} por ciento, '
                      'nota: ${gpa != null ? gpa.toStringAsFixed(1) : 'sin calificar'}, '
                      '${GradeStyle.label(gpa)}',
                  child: ExcludeSemantics(
                    child: AppCard(
                      blur: false,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      child: Row(children: [
                        Container(
                          width: 46, height: 46,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.14),
                            borderRadius:
                                BorderRadius.circular(AppTokens.radiusControl),
                          ),
                          child: Center(
                            child: Text(
                              gpa != null ? gpa.toStringAsFixed(1) : '—',
                              style: GoogleFonts.poppins(
                                  color: color,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.poppins(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600)),
                                Text(
                                    'Ponderado: ${(weight * 100).toStringAsFixed(0)}%',
                                    style: GoogleFonts.poppins(
                                        fontSize: 12, color: t.muted)),
                              ]),
                        ),
                        Text(GradeStyle.label(gpa),
                            style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: color)),
                      ]),
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  /// Promedio ponderado con indicador de estado. Sin notas muestra "Sin notas",
  /// no "En riesgo".
  Widget _buildPromedio() {
    final t = context.tokens;
    final p = _promedio;
    final color = GradeStyle.color(p, t);
    final estado = GradeStyle.label(p);
    return Semantics(
      label: p == null
          ? 'Promedio actual: aún sin notas'
          : 'Promedio actual: ${p.toStringAsFixed(2)}, $estado',
      child: ExcludeSemantics(
        child: AppCard(
          tint: color,
          padding: const EdgeInsets.all(20),
          child: Row(children: [
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
              child: Icon(PhosphorIconsRegular.chartLineUp,
                  color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Promedio actual',
                    style: GoogleFonts.poppins(fontSize: 13, color: t.muted)),
                Text(
                  p?.toStringAsFixed(2) ?? '—',
                  style: GoogleFonts.poppins(
                      fontSize: 34,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                      color: Theme.of(context).colorScheme.onSurface),
                ),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(estado,
                  style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: color)),
            ),
          ]),
        ),
      ),
    );
  }
}
