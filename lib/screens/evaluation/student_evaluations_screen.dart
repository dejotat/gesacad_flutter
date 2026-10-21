import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../config/app_tokens.dart';
import '../../models/evaluation_models.dart';
import '../../services/api_service.dart';
import '../../services/offline_queue.dart';
import '../../utils/route_transitions.dart';
import '../../widgets/eval/eval_widgets.dart';
import '../../widgets/ui/ui.dart';
import 'evaluation_form_screen.dart';

/// Evaluaciones docentes abiertas para el estudiante: una por curso en el que
/// está matriculado. Funciona sin conexión con los últimos datos guardados.
class StudentEvaluationsScreen extends StatefulWidget {
  const StudentEvaluationsScreen({super.key, required this.studentId});
  final int studentId;

  @override
  State<StudentEvaluationsScreen> createState() => _StudentEvaluationsScreenState();
}

class _StudentEvaluationsScreenState extends State<StudentEvaluationsScreen> {
  List<EvalPending>? _items;
  bool _loading = true;
  String? _error;
  StreamSubscription<SyncEvent>? _sub;

  @override
  void initState() {
    super.initState();
    _load();
    OfflineQueue.instance.operations.addListener(_rebuild);
    _sub = OfflineQueue.instance.events.listen((e) {
      if (e.completed && e.operation.type == OperationType.evaluation) _load();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    OfflineQueue.instance.operations.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    setState(() { _loading = _items == null; _error = null; });
    try {
      final r = await ApiService().getPendingEvaluations(widget.studentId);
      if (mounted) setState(() { _items = r; _loading = false; });
    } on EvalApiException catch (e) {
      if (mounted) setState(() { _error = e.message; _loading = false; });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'No se pudieron cargar las evaluaciones. Revisa tu conexión.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _abrir(EvalPending p) async {
    final enviada = await Navigator.push<bool>(
        context, slideRoute(EvaluationFormScreen(pending: p, studentId: widget.studentId)));
    if (enviada == true && mounted) {
      // Refleja de inmediato; el servidor confirma al recargar.
      setState(() => _items = _items
          ?.map((x) => x.targetId == p.targetId ? x.copyWith(answered: true) : x)
          .toList());
      _load();
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
          MotionIcon(PhosphorIconsFill.chalkboardTeacher,
              size: 22, motion: IconMotion.swing),
          SizedBox(width: 8),
          Flexible(child: Text('Evaluación docente', overflow: TextOverflow.ellipsis)),
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
        children: const [SkeletonBox(height: 130), SizedBox(height: 12), SkeletonBox(height: 96), SizedBox(height: 12), SkeletonBox(height: 96)],
      );
    }
    if (_error != null && _items == null) {
      return ErrorState(message: _error!, onRetry: _load);
    }
    final items = _items ?? [];
    final q = OfflineQueue.instance;
    bool hecha(EvalPending p) =>
        p.answered || q.hasPendingEvaluation(widget.studentId, p.targetId);
    final faltan = items.where((p) => !hecha(p)).length;

    // Agrupa por periodo conservando el orden.
    final porPeriodo = <int, List<EvalPending>>{};
    for (final p in items) {
      porPeriodo.putIfAbsent(p.periodId, () => []).add(p);
    }

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
                title: faltan == 0 && items.isNotEmpty ? '¡Todo evaluado!' : 'Tu opinión cuenta',
                subtitle: items.isEmpty
                    ? 'Aún no hay evaluaciones abiertas'
                    : 'Evalúa a tus docentes de forma anónima',
                leading: ExcludeSemantics(
                  child: HexMedallion(
                    faltan == 0 && items.isNotEmpty
                        ? PhosphorIconsFill.sealCheck
                        : PhosphorIconsFill.sparkle,
                    colors: const [Colors.white, Color(0xFFBFE9FF)],
                    size: 40,
                    motion: IconMotion.tada,
                  ),
                ),
                chips: [
                  const HeaderChip(PhosphorIconsFill.shieldCheck, '100% anónima'),
                  if (items.isNotEmpty)
                    HeaderChip(PhosphorIconsRegular.listChecks, '$faltan por evaluar'),
                ],
              ),
              if (items.isEmpty)
                const EmptyState(
                  icon: PhosphorIconsRegular.clipboardText,
                  message: 'No hay evaluaciones abiertas.\nCuando el administrador abra '
                      'el periodo, aparecerán aquí tus cursos.',
                ),
              for (final e in porPeriodo.entries) ...[
                const SizedBox(height: AppTokens.sectionGap),
                SectionTitle('Periodo ${e.value.first.periodName}',
                    icon: PhosphorIconsRegular.calendarCheck,
                    subtitle: cierraEn(e.value.first.closesAt)),
                const SizedBox(height: 12),
                for (var i = 0; i < e.value.length; i++)
                  _card(e.value[i], i, hecha(e.value[i])),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _card(EvalPending p, int i, bool hecha) {
    final t = context.tokens;
    final acc = EvalColors.accent(context);
    final enCola = !p.answered && OfflineQueue.instance.hasPendingEvaluation(widget.studentId, p.targetId);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 380 + i * 90),
      curve: Curves.easeOutCubic,
      builder: (_, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, 18 * (1 - v)), child: child),
      ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Semantics(
          button: !hecha,
          label: '${p.courseName}, docente ${p.teacherName}. '
              '${p.answered ? "Ya evaluaste." : enCola ? "Guardada, se enviará al recuperar la conexión." : "Pendiente. Toca para evaluar."}',
          excludeSemantics: true,
          onTap: hecha ? null : () => _abrir(p),
          child: AppCard(
            blur: false,
            tint: hecha ? t.success : acc.first,
            onTap: hecha ? null : () => _abrir(p),
            padding: const EdgeInsets.fromLTRB(12, 14, 14, 14),
            child: Row(children: [
              HexMedallion(
                hecha ? PhosphorIconsFill.sealCheck : PhosphorIconsFill.chalkboardTeacher,
                colors: hecha ? [t.success, acc.first] : acc,
                size: 42,
                orbit: !hecha,
                motion: hecha ? IconMotion.none : IconMotion.float,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p.courseName,
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(fontSize: 14.5, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Row(children: [
                    Icon(PhosphorIconsRegular.user, size: 14, color: t.muted),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(p.teacherName,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(fontSize: 12.5, color: t.muted)),
                    ),
                  ]),
                ]),
              ),
              const SizedBox(width: 8),
              if (p.answered)
                _status(PhosphorIconsFill.checkCircle, 'Respondida', t.success)
              else if (enCola)
                _status(PhosphorIconsFill.cloudArrowUp, 'En cola', t.warning)
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: acc),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [BoxShadow(color: acc.first.withValues(alpha: 0.4), blurRadius: 10)],
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('Evaluar',
                        style: GoogleFonts.poppins(
                            fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.white)),
                    const SizedBox(width: 4),
                    const Icon(PhosphorIconsBold.arrowRight, size: 14, color: Colors.white),
                  ]),
                ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _status(IconData icon, String label, Color c) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          MotionIcon(icon, color: c, size: 18, motion: IconMotion.none),
          const SizedBox(width: 4),
          Text(label,
              style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700, color: c)),
        ],
      );
}
