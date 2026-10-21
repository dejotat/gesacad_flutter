import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../config/app_tokens.dart';
import '../../models/evaluation_models.dart';
import '../../services/api_service.dart';
import '../../widgets/eval/eval_result_card.dart';
import '../../widgets/eval/eval_widgets.dart';
import '../../widgets/ui/ui.dart';

/// Resultados de la evaluación docente para el docente: solo sus cursos, de
/// periodos ya cerrados y sin comentarios abiertos (solo valoraciones).
class TeacherEvaluationScreen extends StatefulWidget {
  const TeacherEvaluationScreen({super.key, required this.teacherId});
  final int teacherId;

  @override
  State<TeacherEvaluationScreen> createState() => _TeacherEvaluationScreenState();
}

class _TeacherEvaluationScreenState extends State<TeacherEvaluationScreen> {
  List<EvalPeriodResults>? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = _data == null; _error = null; });
    try {
      final r = await ApiService().getTeacherEvalResults(widget.teacherId);
      if (mounted) setState(() { _data = r; _loading = false; });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e is EvalApiException
              ? e.message
              : 'No se pudieron cargar los resultados. Revisa tu conexión.';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: AnimatedIconButton(
          tooltip: 'Regresar',
          icon: Icons.arrow_back_rounded,
          reaction: IconReaction.nudge,
          onPressed: () => Navigator.pop(context),
        ),
        title: const Row(mainAxisSize: MainAxisSize.min, children: [
          MotionIcon(PhosphorIconsFill.chartPolar, size: 22, motion: IconMotion.float),
          SizedBox(width: 8),
          Flexible(child: Text('Mi evaluación docente', overflow: TextOverflow.ellipsis)),
        ]),
        actions: [
          AnimatedIconButton(
            tooltip: 'Actualizar',
            icon: Icons.refresh_rounded,
            reaction: IconReaction.spin,
            onPressed: _load,
          ),
        ],
      ),
      body: LogoBackdrop(child: _body()),
    );
  }

  Widget _body() {
    if (_loading) {
      return ListView(
        padding: const EdgeInsets.all(AppTokens.pagePadding),
        children: const [SkeletonBox(height: 120), SizedBox(height: 12), SkeletonBox(height: 260)],
      );
    }
    if (_error != null && _data == null) return ErrorState(message: _error!, onRetry: _load);
    final data = _data ?? [];

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
                AppTokens.pagePadding, AppTokens.pagePadding, AppTokens.pagePadding, 40),
            children: [
              PageHeader(
                title: 'Lo que opinan tus estudiantes',
                subtitle: 'Resultados anónimos de cada periodo cerrado',
                leading: const ExcludeSemantics(
                  child: HexMedallion(PhosphorIconsFill.chartPolar,
                      colors: [Colors.white, Color(0xFFBFE9FF)], size: 40, motion: IconMotion.float),
                ),
                chips: const [
                  HeaderChip(PhosphorIconsFill.shieldCheck, 'Respuestas anónimas'),
                ],
              ),
              if (data.isEmpty)
                const EmptyState(
                  icon: PhosphorIconsRegular.hourglassHigh,
                  message: 'Aún no hay resultados.\nSe publican cuando el administrador cierra '
                      'el periodo de evaluación.',
                ),
              for (final p in data) ...[
                const SizedBox(height: AppTokens.sectionGap),
                SectionTitle('Periodo ${p.period.name}',
                    icon: PhosphorIconsRegular.calendarCheck,
                    subtitle: 'Cerró el ${formatFechaHora(p.period.closesAt)}'),
                const SizedBox(height: 12),
                for (final r in p.results)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: EvalResultCard(result: r),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
