import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../config/app_tokens.dart';
import '../../models/evaluation_models.dart';
import '../../screens/evaluation/admin_evaluations_screen.dart';
import '../../screens/evaluation/student_evaluations_screen.dart';
import '../../screens/evaluation/teacher_evaluation_screen.dart';
import '../../services/api_service.dart';
import '../../services/offline_queue.dart';
import '../../utils/route_transitions.dart';
import '../ui/ui.dart';
import 'eval_widgets.dart';

enum EvalRole { student, teacher, admin }

/// Tarjeta del dashboard que lleva a la evaluación docente. Según el rol:
///
/// - **Estudiante**: cuántos cursos faltan por evaluar y cuándo cierra.
/// - **Docente**: resultados disponibles de periodos cerrados.
/// - **Admin**: avance del periodo abierto, o invitación a crear el del semestre.
///
/// Se oculta sola cuando no hay nada que mostrar, y funciona sin conexión con
/// los últimos datos guardados.
class EvaluationEntryCard extends StatefulWidget {
  const EvaluationEntryCard({super.key, required this.role, required this.userId});

  final EvalRole role;
  final int userId;

  @override
  State<EvaluationEntryCard> createState() => _EvaluationEntryCardState();
}

class _EvaluationEntryCardState extends State<EvaluationEntryCard> {
  List<EvalPending>? _pending;
  List<EvalPeriodResults>? _teacher;
  List<EvalPeriod>? _periods;
  StreamSubscription<SyncEvent>? _sub;

  @override
  void initState() {
    super.initState();
    _load();
    OfflineQueue.instance.operations.addListener(_rebuild);
    // Al sincronizarse una evaluación guardada sin conexión, se actualiza.
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
    if (widget.userId <= 0) return;
    try {
      switch (widget.role) {
        case EvalRole.student:
          final r = await ApiService().getPendingEvaluations(widget.userId);
          if (mounted) setState(() => _pending = r);
        case EvalRole.teacher:
          final r = await ApiService().getTeacherEvalResults(widget.userId);
          if (mounted) setState(() => _teacher = r);
        case EvalRole.admin:
          final r = await ApiService().getEvalPeriods(widget.userId);
          if (mounted) setState(() => _periods = r);
      }
    } catch (_) {
      // Sin datos (o el servidor aún no tiene el módulo): la tarjeta no aparece.
    }
  }

  Future<void> _open(Widget screen) async {
    await Navigator.push(context, slideRoute(screen));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final card = switch (widget.role) {
      EvalRole.student => _student(context),
      EvalRole.teacher => _teacherCard(context),
      EvalRole.admin => _admin(context),
    };
    return AnimatedSize(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: card ?? const SizedBox(width: double.infinity),
    );
  }

  // ── Estudiante ────────────────────────────────────────────────────────────
  Widget? _student(BuildContext context) {
    final list = _pending;
    if (list == null || list.isEmpty) return null;
    final q = OfflineQueue.instance;
    final faltan = list
        .where((p) => !p.answered && !q.hasPendingEvaluation(widget.userId, p.targetId))
        .toList();
    final acc = EvalColors.accent(context);
    final t = context.tokens;
    final screen = StudentEvaluationsScreen(studentId: widget.userId);

    if (faltan.isEmpty) {
      return _wrap(NeonFrame(
        colors: [t.success, acc.first],
        onTap: () => _open(screen),
        child: _row(
          icon: PhosphorIconsFill.sealCheck,
          colors: [t.success, acc.first],
          motion: IconMotion.tada,
          title: 'Evaluación docente completada',
          subtitle: '¡Gracias! Tu opinión es anónima y ayuda a mejorar.',
          semantic: 'Evaluación docente completada. Gracias.',
        ),
      ));
    }
    final cierra = faltan
        .map((p) => p.closesAt)
        .whereType<DateTime>()
        .fold<DateTime?>(null, (a, b) => a == null || b.isBefore(a) ? b : a);
    return _wrap(NeonFrame(
      colors: acc,
      onTap: () => _open(screen),
      child: _row(
        icon: PhosphorIconsFill.chalkboardTeacher,
        colors: acc,
        motion: IconMotion.tada,
        ping: true,
        title: 'Evalúa a tus docentes',
        subtitle: '${faltan.length} ${faltan.length == 1 ? "curso por evaluar" : "cursos por evaluar"}'
            '${cierra != null ? " · ${cierraEn(cierra)}" : ""}',
        chip: 'Anónima',
        semantic: 'Evaluación docente abierta. ${faltan.length} cursos por evaluar. Toca para empezar.',
      ),
    ));
  }

  // ── Docente ───────────────────────────────────────────────────────────────
  Widget? _teacherCard(BuildContext context) {
    final list = _teacher;
    if (list == null || list.isEmpty) return null;
    final acc = EvalColors.accent(context);
    return _wrap(NeonFrame(
      colors: acc,
      onTap: () => _open(TeacherEvaluationScreen(teacherId: widget.userId)),
      child: _row(
        icon: PhosphorIconsFill.chartPolar,
        colors: acc,
        motion: IconMotion.float,
        title: 'Resultados de evaluación docente',
        subtitle: '${list.length} ${list.length == 1 ? "periodo disponible" : "periodos disponibles"}'
            ' · último: ${list.first.period.name}',
        semantic: 'Resultados de evaluación docente disponibles. Toca para verlos.',
      ),
    ));
  }

  // ── Admin ─────────────────────────────────────────────────────────────────
  Widget? _admin(BuildContext context) {
    final list = _periods;
    if (list == null) return null;
    final acc = EvalColors.accent(context);
    final open = list.where((p) => p.phase == EvalPhase.open).firstOrNull;
    final screen = AdminEvaluationsScreen(adminId: widget.userId);

    if (open != null) {
      final pct = (open.participation * 100).round();
      return _wrap(NeonFrame(
        colors: acc,
        onTap: () => _open(screen),
        child: Row(children: [
          ScoreRing(
            value: open.participation * 100, max: 100, size: 66,
            decimals: 0, suffix: '%', color: acc.first,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Evaluación ${open.name} abierta',
                  style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700)),
              Text('${open.responses} de ${open.expected} respuestas · $pct% · ${cierraEn(open.closesAt)}',
                  style: GoogleFonts.poppins(fontSize: 12, color: context.tokens.muted)),
            ]),
          ),
          const Icon(PhosphorIconsRegular.caretRight, size: 18),
        ]),
      ));
    }
    return _wrap(NeonFrame(
      colors: acc,
      onTap: () => _open(screen),
      child: _row(
        icon: PhosphorIconsFill.chartPolar,
        colors: acc,
        motion: IconMotion.float,
        title: 'Evaluación docente',
        subtitle: list.isEmpty
            ? 'Crea la evaluación del semestre para que los estudiantes califiquen a sus docentes.'
            : '${list.length} ${list.length == 1 ? "periodo" : "periodos"} · toca para administrar',
        semantic: 'Evaluación docente. Toca para administrar los periodos.',
      ),
    ));
  }

  // ── Piezas ────────────────────────────────────────────────────────────────
  Widget _wrap(Widget child) => Padding(
        padding: const EdgeInsets.only(top: AppTokens.sectionGap),
        child: child,
      );

  Widget _row({
    required IconData icon,
    required List<Color> colors,
    required IconMotion motion,
    required String title,
    required String subtitle,
    required String semantic,
    bool ping = false,
    String? chip,
  }) {
    final t = context.tokens;
    return Semantics(
      button: true,
      label: semantic,
      excludeSemantics: true,
      child: Row(children: [
        HexMedallion(icon, colors: colors, size: 46, motion: motion, ping: ping),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(subtitle,
                style: GoogleFonts.poppins(fontSize: 12, color: t.muted, height: 1.35)),
            if (chip != null) ...[
              const SizedBox(height: 6),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(PhosphorIconsFill.shieldCheck, size: 13, color: t.success),
                const SizedBox(width: 4),
                Text(chip,
                    style: GoogleFonts.poppins(
                        fontSize: 11.5, fontWeight: FontWeight.w600, color: t.success)),
              ]),
            ],
          ]),
        ),
        const MotionIcon(PhosphorIconsRegular.caretRight,
            size: 18, motion: IconMotion.none),
      ]),
    );
  }
}
