import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../config/app_tokens.dart';
import '../../models/evaluation_models.dart';
import '../../services/api_service.dart';
import '../../widgets/eval/eval_result_card.dart';
import '../../widgets/eval/eval_widgets.dart';
import '../../widgets/ui/ui.dart';
import 'admin_evaluations_screen.dart';
import 'eval_participants_tab.dart';

/// Detalle de un periodo (Admin) con tres pestañas:
/// **Resumen** (estado, avance, publicar/cerrar), **Instrumento** (preguntas,
/// editables mientras sea borrador) y **Resultados** (solo al cerrar).
class AdminEvaluationDetailScreen extends StatefulWidget {
  const AdminEvaluationDetailScreen({super.key, required this.periodId, required this.adminId});
  final int periodId;
  final int adminId;

  @override
  State<AdminEvaluationDetailScreen> createState() => _AdminEvaluationDetailScreenState();
}

class _AdminEvaluationDetailScreenState extends State<AdminEvaluationDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);
  EvalPeriod? _p;
  bool _loading = true;
  String? _error;
  bool _busy = false;
  bool _instrumentDirty = false;
  bool _scopeDirty = false;

  /// Para pedirle a la pestaña de participantes que se actualice (llegó un docente
  /// nuevo, se matriculó alguien, etc.).
  final _participantes = GlobalKey<EvalParticipantsTabState>();

  bool get _hasUnsaved => _instrumentDirty || _scopeDirty;

  @override
  void initState() {
    super.initState();
    _load();
    // Cada vez que se entra a "Participantes" se vuelve a pedir la matrícula actual:
    // así aparece el docente o el estudiante que se agregó mientras tanto.
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging && _tabs.index == 1) _participantes.currentState?.recargar();
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = _p == null; _error = null; });
    try {
      final p = await ApiService().getEvalPeriod(widget.periodId, widget.adminId);
      if (mounted) setState(() { _p = p; _loading = false; });
      unawaited(_participantes.currentState?.recargar());
    } catch (e) {
      if (mounted) setState(() { _error = mensajeError(e); _loading = false; });
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    final t = context.tokens;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? t.danger : t.success,
        content: Text(msg, style: GoogleFonts.poppins(color: Colors.white, fontSize: 13)),
      ));
  }

  /// Ejecuta una acción del Admin con indicador y manejo de errores común.
  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      _snack(mensajeError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirmar({
    required IconData icon,
    required Color color,
    required String titulo,
    required List<String> puntos,
    required String accion,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: MotionIcon(icon, color: color, size: 34, motion: IconMotion.pulse, halo: true),
        title: Text(titulo, textAlign: TextAlign.center),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final p in puntos)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(PhosphorIconsRegular.dotOutline, size: 18, color: color),
                const SizedBox(width: 6),
                Expanded(child: Text(p, style: GoogleFonts.poppins(fontSize: 13, height: 1.4))),
              ]),
            ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(accion, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _publicar() async {
    final p = _p!;
    if (_hasUnsaved) {
      // Lo que se publica es lo GUARDADO: evita publicar una selección o unas
      // preguntas distintas a las que el Admin ve en pantalla.
      _tabs.animateTo(_scopeDirty ? 1 : 2);
      _snack('Guarda tus cambios (participantes o preguntas) antes de publicar.', error: true);
      return;
    }
    final ok = await _confirmar(
      icon: PhosphorIconsFill.rocketLaunch,
      color: EvalColors.accent(context).first,
      titulo: '¿Publicar ${p.name}?',
      puntos: [
        'Las preguntas quedarán congeladas y ya no se podrán editar.',
        p.scopeMode == 'custom'
            ? 'Solo podrán evaluar los docentes, cursos y estudiantes que seleccionaste.'
            : 'Participarán todos los cursos con docente y los estudiantes matriculados.',
        'Los estudiantes podrán evaluar del ${formatFechaHora(p.opensAt)} al ${formatFechaHora(p.closesAt)}.',
      ],
      accion: 'Publicar',
    );
    if (!ok) return;
    await _run(() async {
      final r = await ApiService().publishEvalPeriod(p.id, widget.adminId);
      await ApiService().invalidarCache();
      await _load();
      final sinDocente = (r['skippedWithoutTeacher'] as num?)?.toInt() ?? 0;
      final sinAlumnos = (r['skippedWithoutStudents'] as num?)?.toInt() ?? 0;
      _snack('Publicado: ${r['targets']} cursos incluidos'
          '${sinDocente > 0 ? " · $sinDocente sin docente" : ""}'
          '${sinAlumnos > 0 ? " · $sinAlumnos sin estudiantes" : ""}.');
    });
  }

  Future<void> _cerrar() async {
    final ok = await _confirmar(
      icon: PhosphorIconsFill.lockKey,
      color: context.tokens.warning,
      titulo: '¿Cerrar la evaluación ahora?',
      puntos: const [
        'Los estudiantes ya no podrán responder.',
        'Se publicarán los resultados para el Admin y los docentes.',
        'Esta acción no se puede deshacer.',
      ],
      accion: 'Cerrar evaluación',
    );
    if (!ok) return;
    await _run(() async {
      await ApiService().closeEvalPeriod(widget.periodId, widget.adminId);
      await ApiService().invalidarCache();
      await _load();
      if (mounted) _tabs.animateTo(3);
      _snack('Periodo cerrado. Ya puedes ver los resultados.');
    });
  }

  Future<void> _eliminar() async {
    final ok = await _confirmar(
      icon: PhosphorIconsFill.trash,
      color: context.tokens.danger,
      titulo: '¿Eliminar este borrador?',
      puntos: const ['Se borrarán el periodo y sus preguntas.', 'Solo los borradores se pueden eliminar.'],
      accion: 'Eliminar',
    );
    if (!ok) return;
    await _run(() async {
      await ApiService().deleteEvalPeriod(widget.periodId, widget.adminId);
      await ApiService().invalidarCache();
      if (mounted) Navigator.pop(context);
    });
  }

  Future<void> _editarVentana() async {
    final r = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => PeriodFormSheet(adminId: widget.adminId, period: _p),
    );
    if (r != null) {
      await ApiService().invalidarCache();
      await _load();
      _snack('Periodo actualizado.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    return PopScope(
      canPop: !_hasUnsaved,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final salir = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Cambios sin guardar'),
            content: const Text('Modificaste las preguntas o los participantes y no los guardaste. ¿Salir de todos modos?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Seguir editando')),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('Salir', style: TextStyle(color: ctx.tokens.danger)),
              ),
            ],
          ),
        );
        if (salir == true && context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
        appBar: AppBar(
          leading: AnimatedIconButton(
            tooltip: 'Regresar',
            icon: Icons.arrow_back_rounded,
            reaction: IconReaction.nudge,
            onPressed: () => Navigator.maybePop(context),
          ),
          title: Text(p == null ? 'Periodo' : 'Periodo ${p.name}', overflow: TextOverflow.ellipsis),
          actions: [
            AnimatedIconButton(
              tooltip: 'Actualizar',
              icon: Icons.refresh_rounded,
              reaction: IconReaction.spin,
              onPressed: _load,
            ),
          ],
          bottom: TabBar(
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.center,
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            labelStyle: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w700),
            tabs: const [
              Tab(icon: Icon(PhosphorIconsRegular.squaresFour, size: 20), text: 'Resumen'),
              Tab(icon: Icon(PhosphorIconsRegular.usersThree, size: 20), text: 'Participantes'),
              Tab(icon: Icon(PhosphorIconsRegular.listChecks, size: 20), text: 'Instrumento'),
              Tab(icon: Icon(PhosphorIconsRegular.chartPolar, size: 20), text: 'Resultados'),
            ],
          ),
        ),
        body: LogoBackdrop(child: _body()),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return ListView(
        padding: const EdgeInsets.all(AppTokens.pagePadding),
        children: const [SkeletonBox(height: 140), SizedBox(height: 12), SkeletonBox(height: 90)],
      );
    }
    if (_error != null && _p == null) return ErrorState(message: _error!, onRetry: _load);
    final p = _p!;
    return TabBarView(
      controller: _tabs,
      children: [
        _SummaryTab(
          period: p, busy: _busy,
          onPublish: _publicar, onClose: _cerrar, onDelete: _eliminar, onEditWindow: _editarVentana,
          onSeeResults: () => _tabs.animateTo(3), onRefresh: _load,
          onEditParticipants: () => _tabs.animateTo(1),
        ),
        EvalParticipantsTab(
          key: _participantes,
          period: p, adminId: widget.adminId,
          onDirty: (d) { if (_scopeDirty != d) setState(() => _scopeDirty = d); },
          onSaved: () async { await ApiService().invalidarCache(); await _load(); },
        ),
        _InstrumentTab(
          period: p, adminId: widget.adminId,
          onDirty: (d) { if (_instrumentDirty != d) setState(() => _instrumentDirty = d); },
          onSaved: () async { await ApiService().invalidarCache(); await _load(); },
        ),
        _ResultsTab(period: p, adminId: widget.adminId, onClose: _cerrar),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Resumen
// ═══════════════════════════════════════════════════════════════════════════

class _SummaryTab extends StatelessWidget {
  const _SummaryTab({
    required this.period, required this.busy, required this.onPublish, required this.onClose,
    required this.onDelete, required this.onEditWindow, required this.onSeeResults,
    required this.onRefresh, required this.onEditParticipants,
  });

  final EvalPeriod period;
  final bool busy;
  final VoidCallback onPublish, onClose, onDelete, onEditWindow, onSeeResults, onEditParticipants;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final acc = EvalColors.accent(context);
    final p = period;
    final respuestas = p.targets.fold<int>(0, (a, x) => a + x.responses);
    final esperadas = p.targets.fold<int>(0, (a, x) => a + x.enrolled);
    final pct = esperadas == 0 ? 0 : (respuestas / esperadas * 100).round();

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: RefreshIndicator(
          onRefresh: onRefresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppTokens.pagePadding),
            children: [
              NeonFrame(
                colors: acc,
                padding: const EdgeInsets.all(18),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    HexMedallion(
                      switch (p.phase) {
                        EvalPhase.draft => PhosphorIconsFill.pencilSimpleLine,
                        EvalPhase.scheduled => PhosphorIconsFill.hourglassHigh,
                        EvalPhase.open => PhosphorIconsFill.broadcast,
                        EvalPhase.closed => PhosphorIconsFill.lockKey,
                      },
                      colors: acc, size: 48,
                      motion: p.phase == EvalPhase.open ? IconMotion.pulse : IconMotion.float,
                      ping: p.phase == EvalPhase.open,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(p.name,
                            style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        PhaseChip(p.phase),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 14),
                  _linea(context, PhosphorIconsRegular.playCircle, 'Abre', formatFechaHora(p.opensAt)),
                  _linea(context, PhosphorIconsRegular.stopCircle, 'Cierra', formatFechaHora(p.closesAt)),
                  _linea(context, PhosphorIconsRegular.shieldCheck, 'Mínimo para mostrar resultados',
                      '${p.minResponses} respuestas por curso'),
                ]),
              ),
              if (!p.isDraft) ...[
                const SizedBox(height: AppTokens.sectionGap),
                LayoutBuilder(builder: (context, c) {
                  final cols = c.maxWidth > 600 ? 3 : 1;
                  const gap = 12.0;
                  final w = (c.maxWidth - gap * (cols - 1)) / cols;
                  return Wrap(spacing: gap, runSpacing: gap, children: [
                    SizedBox(width: w, child: StatCard(
                        icon: PhosphorIconsRegular.books, value: '${p.targets.length}',
                        label: 'Cursos evaluados', color: t.chart[0], motion: IconMotion.float)),
                    SizedBox(width: w, child: StatCard(
                        icon: PhosphorIconsRegular.chatCircleText, value: '$respuestas',
                        label: 'Respuestas', hint: 'de $esperadas esperadas', color: t.chart[1],
                        motion: IconMotion.pulse, delay: const Duration(milliseconds: 120))),
                    SizedBox(width: w, child: StatCard(
                        icon: PhosphorIconsRegular.chartDonut, value: '$pct',
                        label: 'Participación (%)', color: t.chart[4],
                        motion: IconMotion.bounce, delay: const Duration(milliseconds: 240))),
                  ]);
                }),
              ],
              const SizedBox(height: AppTokens.sectionGap),
              Wrap(spacing: 12, runSpacing: 12, children: [
                if (p.phase == EvalPhase.draft) ...[
                  AppButton(label: 'Publicar', icon: PhosphorIconsFill.rocketLaunch,
                      reaction: IconReaction.bounce, loading: busy, onPressed: busy ? null : onPublish),
                  AppButton(label: 'Participantes', icon: PhosphorIconsRegular.usersThree,
                      style: AppButtonStyle.tonal, onPressed: busy ? null : onEditParticipants),
                  AppButton(label: 'Editar fechas', icon: PhosphorIconsRegular.calendarBlank,
                      style: AppButtonStyle.tonal, onPressed: busy ? null : onEditWindow),
                  AppButton(label: 'Eliminar', icon: PhosphorIconsRegular.trash,
                      reaction: IconReaction.shake, style: AppButtonStyle.danger,
                      onPressed: busy ? null : onDelete),
                ] else if (p.phase != EvalPhase.closed) ...[
                  AppButton(label: 'Ajustar cierre', icon: PhosphorIconsRegular.calendarBlank,
                      style: AppButtonStyle.tonal, onPressed: busy ? null : onEditWindow),
                  AppButton(label: 'Cerrar ahora', icon: PhosphorIconsFill.lockKey,
                      reaction: IconReaction.shake, style: AppButtonStyle.danger,
                      loading: busy, onPressed: busy ? null : onClose),
                ] else
                  AppButton(label: 'Ver resultados', icon: PhosphorIconsFill.chartPolar,
                      reaction: IconReaction.pop, onPressed: onSeeResults),
              ]),
              const SizedBox(height: AppTokens.sectionGap),
              if (p.isDraft)
                _info(context,
                    p.scopeMode == 'custom'
                        ? 'Participantes: selección personalizada. Revísala en la pestaña "Participantes" '
                          'y las preguntas en "Instrumento" antes de publicar.'
                        : 'Participantes: todos los docentes con curso y sus estudiantes matriculados. '
                          'Puedes elegir quiénes participan en la pestaña "Participantes".')
              else ...[
                SectionTitle('Participación por curso',
                    icon: PhosphorIconsRegular.chartBar,
                    subtitle: 'Solo conteos: las respuestas se ven al cerrar'),
                const SizedBox(height: 12),
                for (final x in p.targets) _target(context, x),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _linea(BuildContext context, IconData icon, String label, String value) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 17, color: t.muted),
        const SizedBox(width: 8),
        Text('$label: ', style: GoogleFonts.poppins(fontSize: 12.5, color: t.muted)),
        Expanded(
          child: Text(value, style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }

  Widget _info(BuildContext context, String texto) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.info.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppTokens.radiusControl),
        border: Border.all(color: t.info.withValues(alpha: 0.35)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        MotionIcon(PhosphorIconsFill.info, color: t.info, size: 20, motion: IconMotion.pulse),
        const SizedBox(width: 10),
        Expanded(child: Text(texto, style: GoogleFonts.poppins(fontSize: 12.5, height: 1.45))),
      ]),
    );
  }

  Widget _target(BuildContext context, EvalTarget x) {
    final t = context.tokens;
    final pct = (x.participation * 100).round();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        label: '${x.courseName}, docente ${x.teacherName}: ${x.responses} de ${x.enrolled} respondieron, $pct por ciento.',
        child: ExcludeSemantics(
          child: AppCard(
            blur: false,
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(x.courseName,
                        style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700)),
                    Text(x.teacherName, style: GoogleFonts.poppins(fontSize: 12, color: t.muted)),
                  ]),
                ),
                Text('${x.responses}/${x.enrolled}',
                    style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 8),
              ScoreBar(value: x.participation * 5, height: 7),
            ]),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Instrumento
// ═══════════════════════════════════════════════════════════════════════════

class _InstrumentTab extends StatefulWidget {
  const _InstrumentTab({
    required this.period, required this.adminId, required this.onDirty, required this.onSaved,
  });
  final EvalPeriod period;
  final int adminId;
  final ValueChanged<bool> onDirty;
  final Future<void> Function() onSaved;

  @override
  State<_InstrumentTab> createState() => _InstrumentTabState();
}

class _InstrumentTabState extends State<_InstrumentTab>
    with AutomaticKeepAliveClientMixin {
  late List<EvalQuestion> _qs;
  bool _dirty = false;
  bool _saving = false;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _qs = List.of(widget.period.questions);
  }

  @override
  void didUpdateWidget(covariant _InstrumentTab old) {
    super.didUpdateWidget(old);
    // Si el servidor trae otra versión y no hay cambios locales, se recarga.
    if (!_dirty && old.period != widget.period) _qs = List.of(widget.period.questions);
  }

  void _marcar() {
    setState(() { _dirty = true; _error = null; });
    widget.onDirty(true);
  }

  Future<void> _editar({int? index}) async {
    final dims = _qs.map((q) => q.dimension).toSet().toList();
    final r = await showDialog<EvalQuestion>(
      context: context,
      builder: (_) => _QuestionDialog(initial: index == null ? null : _qs[index], dimensions: dims),
    );
    if (r == null) return;
    setState(() => index == null ? _qs.add(r) : _qs[index] = r);
    _marcar();
  }

  Future<void> _guardar() async {
    if (!_qs.any((q) => q.isScale)) {
      setState(() => _error = 'Debe haber al menos una pregunta de escala (1 a 5).');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await ApiService().saveEvalQuestions(widget.period.id, widget.adminId, _qs);
      _dirty = false;
      widget.onDirty(false);
      await widget.onSaved();
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: context.tokens.success,
          content: Text('Instrumento guardado.', style: GoogleFonts.poppins(color: Colors.white)),
        ));
      }
    } catch (e) {
      if (mounted) setState(() { _saving = false; _error = mensajeError(e); });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final t = context.tokens;
    final draft = widget.period.isDraft;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: ListView(
          padding: const EdgeInsets.all(AppTokens.pagePadding),
          children: [
            if (!draft)
              Container(
                padding: const EdgeInsets.all(14),
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: t.warning.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(AppTokens.radiusControl),
                  border: Border.all(color: t.warning.withValues(alpha: 0.35)),
                ),
                child: Row(children: [
                  Icon(PhosphorIconsFill.lockKey, color: t.warning, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Instrumento congelado: ya hay respuestas basadas en estas preguntas, por eso no se pueden editar.',
                      style: GoogleFonts.poppins(fontSize: 12.5, height: 1.4),
                    ),
                  ),
                ]),
              )
            else
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SectionTitle('Preguntas del instrumento',
                    icon: PhosphorIconsRegular.listChecks,
                    subtitle: '${_qs.length} preguntas · arrastra para reordenar'),
              ),
            if (draft)
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: _qs.length,
                onReorder: (a, b) {
                  setState(() {
                    if (b > a) b -= 1;
                    _qs.insert(b, _qs.removeAt(a));
                  });
                  _marcar();
                },
                itemBuilder: (_, i) => _fila(i),
              )
            else
              ..._soloLectura(),
            if (draft) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 12, runSpacing: 12, children: [
                AppButton(label: 'Agregar pregunta', icon: PhosphorIconsBold.plus,
                    style: AppButtonStyle.tonal, onPressed: () => _editar()),
                AppButton(label: 'Guardar cambios', icon: PhosphorIconsFill.floppyDisk,
                    reaction: IconReaction.bounce, loading: _saving,
                    onPressed: _dirty && !_saving ? _guardar : null),
              ]),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(_error!,
                        style: GoogleFonts.poppins(fontSize: 12.5, color: t.danger, fontWeight: FontWeight.w600)),
                  ),
                ),
              const SizedBox(height: 40),
            ],
          ],
        ),
      ),
    );
  }

  Widget _fila(int i) {
    final t = context.tokens;
    final q = _qs[i];
    return Padding(
      key: ValueKey('q_${i}_${q.text.hashCode}_${q.dimension.hashCode}'),
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        blur: false,
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
        child: Row(children: [
          ReorderableDragStartListener(
            index: i,
            child: Semantics(
              label: 'Arrastrar para reordenar la pregunta ${i + 1}',
              child: const Padding(
                padding: EdgeInsets.all(10),
                child: Icon(PhosphorIconsRegular.dotsSixVertical, size: 22),
              ),
            ),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: _chip(q.dimension, EvalColors.accent(context).first)),
                const SizedBox(width: 6),
                _chip(q.isScale ? 'Escala 1–5' : 'Comentario', q.isScale ? t.chart[4] : t.chart[3]),
                if (!q.required) ...[const SizedBox(width: 6), _chip('Opcional', t.muted)],
              ]),
              const SizedBox(height: 6),
              Text(q.text, style: GoogleFonts.poppins(fontSize: 13, height: 1.4)),
            ]),
          ),
          AnimatedIconButton(
            tooltip: 'Editar pregunta ${i + 1}',
            icon: PhosphorIconsRegular.pencilSimple,
            reaction: IconReaction.write,
            onPressed: () => _editar(index: i),
          ),
          AnimatedIconButton(
            tooltip: 'Eliminar pregunta ${i + 1}',
            icon: PhosphorIconsRegular.trash,
            reaction: IconReaction.shake,
            color: t.danger,
            onPressed: () {
              setState(() => _qs.removeAt(i));
              _marcar();
            },
          ),
        ]),
      ),
    );
  }

  List<Widget> _soloLectura() {
    final t = context.tokens;
    final grupos = <String, List<EvalQuestion>>{};
    for (final q in _qs) { grupos.putIfAbsent(q.dimension, () => []).add(q); }
    return [
      for (final e in grupos.entries) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 12, 0, 8),
          child: Text(e.key.toUpperCase(),
              style: GoogleFonts.poppins(
                  fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.1, color: t.muted)),
        ),
        for (final q in e.value)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppCard(
              blur: false,
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Icon(q.isScale ? PhosphorIconsRegular.chartBar : PhosphorIconsRegular.chatCircleText,
                    size: 20, color: t.muted),
                const SizedBox(width: 12),
                Expanded(child: Text(q.text, style: GoogleFonts.poppins(fontSize: 13, height: 1.4))),
              ]),
            ),
          ),
      ],
    ];
  }

  Widget _chip(String text, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(fontSize: 10.5, fontWeight: FontWeight.w700, color: c)),
      );
}

class _QuestionDialog extends StatefulWidget {
  const _QuestionDialog({this.initial, required this.dimensions});
  final EvalQuestion? initial;
  final List<String> dimensions;

  @override
  State<_QuestionDialog> createState() => _QuestionDialogState();
}

class _QuestionDialogState extends State<_QuestionDialog> {
  late final TextEditingController _dim =
      TextEditingController(text: widget.initial?.dimension ?? '');
  late final TextEditingController _text =
      TextEditingController(text: widget.initial?.text ?? '');
  late String _type = widget.initial?.type ?? 'scale';
  late bool _required = widget.initial?.required ?? true;
  String? _error;

  @override
  void dispose() {
    _dim.dispose();
    _text.dispose();
    super.dispose();
  }

  void _ok() {
    final d = _dim.text.trim();
    final x = _text.text.trim();
    if (d.isEmpty || d.length > 60) {
      setState(() => _error = 'La dimensión debe tener entre 1 y 60 caracteres.');
      return;
    }
    if (x.isEmpty || x.length > 300) {
      setState(() => _error = 'El enunciado debe tener entre 1 y 300 caracteres.');
      return;
    }
    Navigator.pop(context, EvalQuestion(
      id: widget.initial?.id, dimension: d, text: x, type: _type,
      required: _type == 'scale' ? _required : false,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return AlertDialog(
      title: Text(widget.initial == null ? 'Nueva pregunta' : 'Editar pregunta'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
              controller: _dim,
              maxLength: 60,
              decoration: const InputDecoration(
                labelText: 'Dimensión', hintText: 'Ej: Metodología',
                prefixIcon: Icon(PhosphorIconsRegular.target),
              ),
            ),
            if (widget.dimensions.isNotEmpty)
              Wrap(spacing: 6, runSpacing: 4, children: [
                for (final d in widget.dimensions)
                  ActionChip(
                    label: Text(d, style: GoogleFonts.poppins(fontSize: 11)),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() => _dim.text = d),
                  ),
              ]),
            const SizedBox(height: 12),
            TextField(
              controller: _text,
              maxLength: 300,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Enunciado',
                hintText: 'Ej: El docente explica con claridad.',
              ),
            ),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'scale', label: Text('Escala 1–5'), icon: Icon(PhosphorIconsRegular.chartBar)),
                ButtonSegment(value: 'text', label: Text('Comentario'), icon: Icon(PhosphorIconsRegular.chatCircleText)),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
            if (_type == 'scale')
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Obligatoria', style: GoogleFonts.poppins(fontSize: 13)),
                value: _required,
                onChanged: (v) => setState(() => _required = v),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!,
                    style: GoogleFonts.poppins(fontSize: 12.5, color: t.danger, fontWeight: FontWeight.w600)),
              ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        TextButton(onPressed: _ok, child: const Text('Aceptar')),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Resultados
// ═══════════════════════════════════════════════════════════════════════════

class _ResultsTab extends StatefulWidget {
  const _ResultsTab({required this.period, required this.adminId, required this.onClose});
  final EvalPeriod period;
  final int adminId;
  final VoidCallback onClose;

  @override
  State<_ResultsTab> createState() => _ResultsTabState();
}

class _ResultsTabState extends State<_ResultsTab> {
  EvalPeriodResults? _data;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.period.phase == EvalPhase.closed) _load();
  }

  @override
  void didUpdateWidget(covariant _ResultsTab old) {
    super.didUpdateWidget(old);
    if (old.period.phase != EvalPhase.closed && widget.period.phase == EvalPhase.closed) _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final r = await ApiService().getEvalResults(widget.period.id, widget.adminId);
      if (mounted) setState(() { _data = r; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = mensajeError(e); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final p = widget.period;

    if (p.phase != EvalPhase.closed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            HexMedallion(PhosphorIconsFill.lockKey,
                colors: [t.warning, t.chart[0]], size: 72, motion: IconMotion.swing),
            const SizedBox(height: 8),
            Text('Resultados protegidos',
                style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              p.isDraft
                  ? 'Publica el periodo para que los estudiantes empiecen a responder.'
                  : 'Los resultados se publican cuando el periodo cierra. Verlos antes permitiría deducir respuestas individuales y rompería el anonimato.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(fontSize: 13, color: t.muted, height: 1.5),
            ),
            if (!p.isDraft) ...[
              const SizedBox(height: 18),
              AppButton(label: 'Cerrar ahora', icon: PhosphorIconsFill.lockKey,
                  reaction: IconReaction.shake, style: AppButtonStyle.danger,
                  onPressed: widget.onClose),
            ],
          ]),
        ),
      );
    }
    if (_loading) {
      return ListView(
        padding: const EdgeInsets.all(AppTokens.pagePadding),
        children: const [SkeletonBox(height: 280), SizedBox(height: 12), SkeletonBox(height: 280)],
      );
    }
    if (_error != null) return ErrorState(message: _error!, onRetry: _load);
    final data = _data;
    if (data == null) return const SizedBox.shrink();

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppTokens.pagePadding),
            children: [
              SectionTitle('Resultados por curso',
                  icon: PhosphorIconsRegular.chartPolar,
                  subtitle: 'Incluye comentarios · solo visibles para el Admin'),
              const SizedBox(height: 12),
              if (data.results.isEmpty)
                const EmptyState(
                    icon: PhosphorIconsRegular.clipboardText,
                    message: 'Este periodo no tuvo cursos evaluados.'),
              for (final r in data.results)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: EvalResultCard(result: r, showComments: true),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
