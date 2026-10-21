import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../config/app_tokens.dart';
import '../../models/evaluation_models.dart';
import '../../services/api_service.dart';
import '../../services/connectivity_service.dart';
import '../../utils/route_transitions.dart';
import '../../widgets/eval/eval_widgets.dart';
import '../../widgets/ui/ui.dart';
import 'admin_evaluation_detail_screen.dart';

/// Mensaje legible para un error de las acciones del Admin.
String mensajeError(Object e) {
  if (e is EvalApiException) return e.message;
  if (isNetworkError(e)) return 'Esta acción necesita conexión a internet.';
  return 'Ocurrió un error inesperado. Inténtalo de nuevo.';
}

/// Lista de periodos de evaluación docente (Admin): crear, abrir el detalle y
/// ver el avance de participación de cada uno.
class AdminEvaluationsScreen extends StatefulWidget {
  const AdminEvaluationsScreen({super.key, required this.adminId});
  final int adminId;

  @override
  State<AdminEvaluationsScreen> createState() => _AdminEvaluationsScreenState();
}

class _AdminEvaluationsScreenState extends State<AdminEvaluationsScreen> {
  List<EvalPeriod>? _periods;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = _periods == null; _error = null; });
    try {
      final r = await ApiService().getEvalPeriods(widget.adminId);
      if (mounted) setState(() { _periods = r; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = mensajeError(e); _loading = false; });
    }
  }

  Future<void> _crear() async {
    final id = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => PeriodFormSheet(adminId: widget.adminId, existing: _periods ?? const []),
    );
    if (id != null && mounted) {
      await _abrir(id);
    }
  }

  Future<void> _abrir(int id) async {
    await Navigator.push(
        context, slideRoute(AdminEvaluationDetailScreen(periodId: id, adminId: widget.adminId)));
    if (mounted) _load();
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _crear,
        icon: const MotionIcon(PhosphorIconsBold.plus, size: 20, motion: IconMotion.tada),
        label: Text('Nuevo periodo', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
      ),
      body: LogoBackdrop(child: _body()),
    );
  }

  Widget _body() {
    if (_loading) {
      return ListView(
        padding: const EdgeInsets.all(AppTokens.pagePadding),
        children: const [SkeletonBox(height: 130), SizedBox(height: 12), SkeletonBox(height: 110)],
      );
    }
    if (_error != null && _periods == null) return ErrorState(message: _error!, onRetry: _load);
    final list = _periods ?? [];
    final abiertos = list.where((p) => p.phase == EvalPhase.open).length;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
                AppTokens.pagePadding, AppTokens.pagePadding, AppTokens.pagePadding, 110),
            children: [
              PageHeader(
                title: 'Evaluación docente',
                subtitle: 'Define el instrumento, abre el periodo y consulta resultados',
                leading: const ExcludeSemantics(
                  child: HexMedallion(PhosphorIconsFill.chartPolar,
                      colors: [Colors.white, Color(0xFFBFE9FF)], size: 40, motion: IconMotion.float),
                ),
                chips: [
                  HeaderChip(PhosphorIconsRegular.calendarBlank,
                      '${list.length} ${list.length == 1 ? "periodo" : "periodos"}'),
                  if (abiertos > 0)
                    HeaderChip(PhosphorIconsFill.broadcast, '$abiertos abierto${abiertos == 1 ? "" : "s"}'),
                  const HeaderChip(PhosphorIconsFill.shieldCheck, 'Anónima'),
                ],
              ),
              if (list.isEmpty)
                const EmptyState(
                  icon: PhosphorIconsRegular.clipboardText,
                  message: 'Todavía no hay periodos.\nCrea el primero con el botón "Nuevo periodo".',
                ),
              const SizedBox(height: AppTokens.sectionGap),
              for (var i = 0; i < list.length; i++) _card(list[i], i),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card(EvalPeriod p, int i) {
    final t = context.tokens;
    final acc = EvalColors.accent(context);
    final (IconData icon, IconMotion motion) = switch (p.phase) {
      EvalPhase.draft => (PhosphorIconsFill.pencilSimpleLine, IconMotion.write),
      EvalPhase.scheduled => (PhosphorIconsFill.hourglassHigh, IconMotion.swing),
      EvalPhase.open => (PhosphorIconsFill.broadcast, IconMotion.pulse),
      EvalPhase.closed => (PhosphorIconsFill.lockKey, IconMotion.none),
    };
    final colors = p.phase == EvalPhase.closed ? [t.warning, t.chart[0]] : acc;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 350 + i * 80),
      curve: Curves.easeOutCubic,
      builder: (_, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, 18 * (1 - v)), child: child),
      ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Semantics(
          button: true,
          label: 'Periodo ${p.name}, ${p.phase.label}. ${p.responses} de ${p.expected} respuestas.',
          excludeSemantics: true,
          onTap: () => _abrir(p.id),
          child: AppCard(
            blur: false,
            onTap: () => _abrir(p.id),
            padding: const EdgeInsets.fromLTRB(12, 14, 14, 14),
            child: Row(children: [
              HexMedallion(icon, colors: colors, size: 42, motion: motion,
                  orbit: p.phase == EvalPhase.open),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(
                      child: Text(p.name,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 8),
                    PhaseChip(p.phase),
                  ]),
                  const SizedBox(height: 4),
                  Text(
                    p.opensAt == null
                        ? 'Fechas sin definir'
                        : '${formatFechaHora(p.opensAt)}  →  ${formatFechaHora(p.closesAt)}',
                    style: GoogleFonts.poppins(fontSize: 11.5, color: t.muted),
                  ),
                  if (p.phase == EvalPhase.open)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(cierraEn(p.closesAt),
                          style: GoogleFonts.poppins(
                              fontSize: 12, fontWeight: FontWeight.w600, color: t.success)),
                    ),
                ]),
              ),
              if (p.expected > 0)
                ScoreRing(
                  value: p.participation * 100, max: 100, size: 54,
                  decimals: 0, suffix: '%', color: colors.first,
                )
              else
                Icon(PhosphorIconsRegular.caretRight, color: t.muted),
            ]),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Formulario de periodo (crear / editar fechas)
// ═══════════════════════════════════════════════════════════════════════════

/// Hoja inferior para crear un periodo o editar su ventana.
///
/// - **Crear** ([period] nulo): nombre, apertura, cierre, mínimo de respuestas y
///   opción de copiar las preguntas de otro periodo. Devuelve el id creado.
/// - **Editar** ([period] dado): en borrador cambia nombre, apertura y cierre;
///   publicado, solo el cierre y el mínimo. Devuelve `-1` si se guardó.
class PeriodFormSheet extends StatefulWidget {
  const PeriodFormSheet({super.key, required this.adminId, this.period, this.existing = const []});
  final int adminId;
  final EvalPeriod? period;
  final List<EvalPeriod> existing;

  @override
  State<PeriodFormSheet> createState() => _PeriodFormSheetState();
}

class _PeriodFormSheetState extends State<PeriodFormSheet> {
  late final TextEditingController _name;
  late DateTime _opens; // hora de reloj de Colombia
  late DateTime _closes;
  late double _min;
  int? _copyFrom;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.period != null;
  bool get _draft => !_editing || widget.period!.isDraft;

  @override
  void initState() {
    super.initState();
    final p = widget.period;
    final now = toColombia(DateTime.now());
    final y = now.year;
    _name = TextEditingController(text: p?.name ?? (now.month <= 6 ? '$y-1' : '$y-2'));
    _opens = p?.opensAt != null
        ? toColombia(p!.opensAt!)
        : DateTime(now.year, now.month, now.day, 8).add(const Duration(days: 1));
    _closes = p?.closesAt != null
        ? toColombia(p!.closesAt!)
        : DateTime(_opens.year, _opens.month, _opens.day, 23, 59).add(const Duration(days: 14));
    _min = (p?.minResponses ?? 5).toDouble();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<DateTime?> _pick(DateTime initial) async {
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(initial.year - 1),
      lastDate: DateTime(initial.year + 3),
      helpText: 'Selecciona la fecha',
    );
    if (d == null || !mounted) return null;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      helpText: 'Hora (Colombia)',
    );
    if (t == null) return null;
    return DateTime(d.year, d.month, d.day, t.hour, t.minute);
  }

  Future<void> _guardar() async {
    final name = _name.text.trim();
    if (_draft && name.isEmpty) {
      setState(() => _error = 'Escribe un nombre para el periodo (ej: 2026-2).');
      return;
    }
    if (!_closes.isAfter(_opens)) {
      setState(() => _error = 'El cierre debe ser posterior a la apertura.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      final api = ApiService();
      if (_editing) {
        await api.updateEvalPeriod(
          widget.period!.id, widget.adminId,
          name: _draft ? name : null,
          opensAt: _draft ? fromColombia(_opens) : null,
          closesAt: fromColombia(_closes),
          minResponses: _min.round(),
        );
        if (mounted) Navigator.pop(context, -1);
      } else {
        final id = await api.createEvalPeriod(
          widget.adminId, name,
          opensAt: fromColombia(_opens),
          closesAt: fromColombia(_closes),
          minResponses: _min.round(),
          copyFromPeriodId: _copyFrom,
        );
        if (mounted) Navigator.pop(context, id);
      }
    } catch (e) {
      if (mounted) setState(() { _saving = false; _error = mensajeError(e); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              HexMedallion(
                _editing ? PhosphorIconsFill.calendarCheck : PhosphorIconsFill.plusCircle,
                colors: EvalColors.accent(context), size: 36, motion: IconMotion.pulse,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(_editing ? 'Editar periodo' : 'Nuevo periodo de evaluación',
                      style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700)),
                ),
              ),
            ]),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              enabled: _draft,
              maxLength: 60,
              decoration: const InputDecoration(
                labelText: 'Nombre del periodo',
                hintText: 'Ej: 2026-2',
                prefixIcon: Icon(PhosphorIconsRegular.tag),
              ),
            ),
            const SizedBox(height: 4),
            _fecha('Apertura', _opens, _draft, (d) => setState(() => _opens = d)),
            const SizedBox(height: 10),
            _fecha('Cierre', _closes, true, (d) => setState(() => _closes = d)),
            const SizedBox(height: 18),
            Row(children: [
              Icon(PhosphorIconsRegular.shieldCheck, size: 18, color: t.success),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Mínimo de respuestas para mostrar resultados: ${_min.round()}',
                    style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ]),
            Slider(
              value: _min, min: 3, max: 20, divisions: 17,
              label: '${_min.round()}',
              onChanged: (v) => setState(() => _min = v),
            ),
            Text(
              'Si un curso recibe menos respuestas, sus resultados quedan ocultos para que nadie pueda identificar a un estudiante.',
              style: GoogleFonts.poppins(fontSize: 11.5, color: t.muted, height: 1.4),
            ),
            if (!_editing && widget.existing.isNotEmpty) ...[
              const SizedBox(height: 16),
              DropdownButtonFormField<int?>(
                initialValue: _copyFrom,
                decoration: const InputDecoration(
                  labelText: 'Preguntas',
                  prefixIcon: Icon(PhosphorIconsRegular.copy),
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Usar el instrumento por defecto')),
                  for (final p in widget.existing)
                    DropdownMenuItem(value: p.id, child: Text('Copiar de ${p.name}')),
                ],
                onChanged: (v) => setState(() => _copyFrom = v),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Text(_error!,
                    style: GoogleFonts.poppins(fontSize: 12.5, color: t.danger, fontWeight: FontWeight.w600)),
              ),
            ],
            const SizedBox(height: 20),
            AppButton(
              label: _editing ? 'Guardar cambios' : 'Crear borrador',
              icon: PhosphorIconsBold.check,
              reaction: IconReaction.pop,
              expand: true,
              loading: _saving,
              onPressed: _guardar,
            ),
          ]),
        ),
      ),
    );
  }

  Widget _fecha(String label, DateTime value, bool enabled, ValueChanged<DateTime> onPick) {
    final t = context.tokens;
    return Semantics(
      button: true,
      enabled: enabled,
      label: '$label: ${formatFechaHora(fromColombia(value))}. Toca para cambiar.',
      excludeSemantics: true,
      onTap: enabled ? () async { final d = await _pick(value); if (d != null) onPick(d); } : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTokens.radiusControl),
        onTap: enabled
            ? () async {
                final d = await _pick(value);
                if (d != null) onPick(d);
              }
            : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(color: t.border),
            borderRadius: BorderRadius.circular(AppTokens.radiusControl),
          ),
          child: Row(children: [
            Icon(PhosphorIconsRegular.calendarBlank, size: 20,
                color: enabled ? Theme.of(context).colorScheme.primary : t.muted),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: GoogleFonts.poppins(fontSize: 11.5, color: t.muted)),
                Text(formatFechaHora(fromColombia(value)),
                    style: GoogleFonts.poppins(fontSize: 13.5, fontWeight: FontWeight.w600)),
              ]),
            ),
            if (enabled) Icon(PhosphorIconsRegular.pencilSimple, size: 16, color: t.muted),
          ]),
        ),
      ),
    );
  }
}
