import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../config/app_tokens.dart';
import '../../models/evaluation_models.dart';
import '../../services/api_service.dart';
import '../../services/connectivity_service.dart';
import '../../services/offline_queue.dart';
import '../../widgets/eval/eval_widgets.dart';
import '../../widgets/ui/ui.dart';

enum _Resultado { enviada, enCola }

/// Formulario de evaluación de un docente, por pasos:
/// introducción (anonimato) → una página por dimensión → comentarios y envío.
///
/// - Una valoración de 1 a 5 por pregunta con [RatingOrbs].
/// - Si no hay conexión (o falla la red al enviar) la evaluación queda en la
///   cola sin conexión y se envía sola; el servidor evita duplicados.
/// - Al salir con respuestas sin enviar pide confirmación.
///
/// Devuelve `true` al cerrarse si la evaluación se envió o quedó en cola.
class EvaluationFormScreen extends StatefulWidget {
  const EvaluationFormScreen({super.key, required this.pending, required this.studentId});
  final EvalPending pending;
  final int studentId;

  @override
  State<EvaluationFormScreen> createState() => _EvaluationFormScreenState();
}

class _EvaluationFormScreenState extends State<EvaluationFormScreen> {
  EvalForm? _form;
  bool _loading = true;
  String? _error;

  final Map<int, int> _values = {};
  final Map<int, TextEditingController> _comments = {};
  final PageController _pages = PageController();
  int _step = 0;
  bool _showMissing = false;
  bool _sending = false;
  String? _sendError;
  _Resultado? _done;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pages.dispose();
    for (final c in _comments.values) { c.dispose(); }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final f = await ApiService().getEvaluationForm(widget.pending.targetId, widget.studentId);
      for (final q in f.textQuestions) {
        _comments.putIfAbsent(q.id!, () => TextEditingController());
      }
      if (mounted) setState(() { _form = f; _loading = false; });
    } on EvalApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'YA_EVALUADO') {
        Navigator.pop(context, true);
        return;
      }
      setState(() { _error = e.message; _loading = false; });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'No se pudo cargar el formulario. Revisa tu conexión e inténtalo de nuevo.';
          _loading = false;
        });
      }
    }
  }

  // ── Pasos ─────────────────────────────────────────────────────────────────
  List<String> get _dimensions => _form?.scaleByDimension.keys.toList() ?? [];
  int get _totalSteps => _dimensions.length + 2; // intro + dimensiones + final
  bool get _dirty => _values.isNotEmpty || _comments.values.any((c) => c.text.trim().isNotEmpty);

  /// Preguntas obligatorias sin responder en el paso [step].
  List<EvalQuestion> _faltantes(int step) {
    if (step == 0 || step > _dimensions.length) return const [];
    final qs = _form!.scaleByDimension[_dimensions[step - 1]]!;
    return qs.where((q) => q.required && !_values.containsKey(q.id)).toList();
  }

  void _go(int step) {
    _pages.animateToPage(step,
        duration: const Duration(milliseconds: 420), curve: Curves.easeOutCubic);
    setState(() { _step = step; _showMissing = false; });
  }

  void _next() {
    if (_faltantes(_step).isNotEmpty) {
      HapticFeedback.mediumImpact();
      setState(() => _showMissing = true);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: context.tokens.warning,
          content: Text('Responde todas las preguntas de esta sección para continuar.',
              style: GoogleFonts.poppins(color: Colors.white, fontSize: 13)),
        ));
      return;
    }
    if (_step < _totalSteps - 1) _go(_step + 1);
  }

  // ── Envío ─────────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _answers() {
    final out = <Map<String, dynamic>>[];
    for (final q in _form!.questions) {
      if (q.isScale) {
        final v = _values[q.id];
        if (v != null) out.add({'questionId': q.id, 'value': v});
      } else {
        final t = _comments[q.id]?.text.trim() ?? '';
        if (t.isNotEmpty) out.add({'questionId': q.id, 'comment': t});
      }
    }
    return out;
  }

  Future<void> _enviar() async {
    // Última comprobación de obligatorias en todas las secciones.
    for (var s = 1; s <= _dimensions.length; s++) {
      if (_faltantes(s).isNotEmpty) {
        HapticFeedback.mediumImpact();
        _go(s);
        setState(() => _showMissing = true);
        return;
      }
    }
    setState(() { _sending = true; _sendError = null; });
    final answers = _answers();
    final label = 'Evaluación docente · ${_form!.courseName}';

    Future<void> encolar() async {
      await OfflineQueue.instance.enqueueEvaluation(
        studentId: widget.studentId,
        targetId: widget.pending.targetId,
        answers: answers,
        label: label,
      );
      if (mounted) setState(() { _sending = false; _done = _Resultado.enCola; });
    }

    if (!ConnectivityService.instance.online.value) {
      await encolar();
      return;
    }
    try {
      final r = await ApiService().submitEvaluation(widget.pending.targetId, widget.studentId, answers);
      if (!mounted) return;
      final c = r.status;
      if ((c >= 200 && c < 300) || c == 409) {
        setState(() { _sending = false; _done = _Resultado.enviada; });
      } else if (c >= 500 || c == 408 || c == 429) {
        await encolar(); // falla temporal: la cola reintenta sola
      } else {
        setState(() {
          _sending = false;
          _sendError = r.message ?? 'El servidor rechazó la evaluación (código $c).';
        });
      }
    } catch (e) {
      if (isNetworkError(e)) {
        // Si la petición llegó pero se perdió la respuesta, el reenvío recibe
        // 409 y la cola lo da por bueno: no hay duplicados.
        await encolar();
      } else if (mounted) {
        setState(() { _sending = false; _sendError = 'Ocurrió un error inesperado. Inténtalo de nuevo.'; });
      }
    }
  }

  Future<bool> _confirmarSalida() async {
    if (_done != null || !_dirty) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Salir sin enviar?'),
        content: const Text('Tus respuestas de esta evaluación se perderán.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Seguir evaluando')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Salir', style: TextStyle(color: ctx.tokens.danger)),
          ),
        ],
      ),
    );
    return ok == true;
  }

  /// Cierra la pantalla (pidiendo confirmación si hay respuestas sin enviar).
  Future<void> _salir(bool resultado) async {
    if (!await _confirmarSalida()) return;
    if (mounted) Navigator.pop(context, resultado);
  }

  // ── Interfaz ──────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _done != null || !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _salir(false);
      },
      child: Scaffold(
        appBar: AppBar(
          leading: AnimatedIconButton(
            tooltip: 'Cerrar',
            icon: Icons.close_rounded,
            reaction: IconReaction.spin,
            onPressed: () => _salir(_done != null),
          ),
          title: Text(widget.pending.courseName, overflow: TextOverflow.ellipsis),
        ),
        body: LogoBackdrop(child: _body()),
        // En bottomNavigationBar los avisos (SnackBar) flotan POR ENCIMA de los
        // botones en lugar de taparlos.
        bottomNavigationBar:
            (_form != null && !_loading && _error == null && _done == null) ? _navBar() : null,
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(AppTokens.pagePadding),
        child: Column(children: [SkeletonBox(height: 160), SizedBox(height: 12), SkeletonBox(height: 120)]),
      );
    }
    if (_error != null) return ErrorState(message: _error!, onRetry: _load);
    if (_done != null) return _success();

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Column(children: [
          _progress(),
          Expanded(
            child: PageView(
              controller: _pages,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _intro(),
                for (final d in _dimensions) _dimensionPage(d),
                _finalPage(),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _progress() {
    final t = context.tokens;
    final acc = EvalColors.accent(context);
    final label = _step == 0
        ? 'Introducción'
        : _step <= _dimensions.length
            ? _dimensions[_step - 1]
            : 'Comentarios y envío';
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppTokens.pagePadding, 8, AppTokens.pagePadding, 4),
      child: Semantics(
        label: 'Paso ${_step + 1} de $_totalSteps: $label',
        child: ExcludeSemantics(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('Paso ${_step + 1} de $_totalSteps',
                  style: GoogleFonts.poppins(fontSize: 11.5, color: t.muted, fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: Text(label,
                      key: ValueKey(label),
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(fontSize: 11.5, color: acc.first, fontWeight: FontWeight.w700)),
                ),
              ),
            ]),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Container(
                height: 6,
                color: t.border,
                alignment: Alignment.centerLeft,
                child: AnimatedFractionallySizedBox(
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.easeOutCubic,
                  widthFactor: (_step + 1) / _totalSteps,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: acc),
                      boxShadow: [BoxShadow(color: acc.first.withValues(alpha: 0.7), blurRadius: 8)],
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _navBar() {
    final last = _step == _totalSteps - 1;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppTokens.pagePadding, 8, AppTokens.pagePadding, 12),
        child: Row(children: [
          if (_step > 0) ...[
            AppButton(
              label: 'Atrás',
              icon: PhosphorIconsBold.arrowLeft,
              reaction: IconReaction.nudge,
              style: AppButtonStyle.outline,
              onPressed: _sending ? null : () => _go(_step - 1),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: AppButton(
              label: last ? 'Enviar evaluación' : (_step == 0 ? 'Comenzar' : 'Siguiente'),
              icon: last ? PhosphorIconsFill.paperPlaneTilt : PhosphorIconsBold.arrowRight,
              reaction: last ? IconReaction.bounce : IconReaction.nudge,
              expand: true,
              loading: _sending,
              onPressed: last ? _enviar : _next,
            ),
          ),
        ]),
      ),
    );
  }

  // ── Páginas ───────────────────────────────────────────────────────────────
  Widget _intro() {
    final t = context.tokens;
    final acc = EvalColors.accent(context);
    final f = _form!;
    Widget punto(IconData icon, String titulo, String texto) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: acc.first.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(child: MotionIcon(icon, color: acc.first, size: 20, motion: IconMotion.pulse)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(titulo, style: GoogleFonts.poppins(fontSize: 13.5, fontWeight: FontWeight.w700)),
                Text(texto, style: GoogleFonts.poppins(fontSize: 12.5, color: t.muted, height: 1.4)),
              ]),
            ),
          ]),
        );

    return ListView(
      padding: const EdgeInsets.all(AppTokens.pagePadding),
      children: [
        const SizedBox(height: 8),
        Center(
          child: HexMedallion(PhosphorIconsFill.shieldCheck,
              colors: acc, size: 84, motion: IconMotion.float, ping: true),
        ),
        const SizedBox(height: 12),
        Semantics(
          header: true,
          child: Text('Evaluación docente',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: 4),
        Text('${f.courseName} · ${f.teacherName}',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(fontSize: 13.5, color: t.muted)),
        const SizedBox(height: 22),
        NeonFrame(
          colors: acc,
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
          child: Column(children: [
            punto(PhosphorIconsFill.eyeSlash, 'Es completamente anónima',
                'Tu nombre nunca se guarda junto a tus respuestas. Nadie, ni el docente ni la administración, puede saber qué respondiste.'),
            punto(PhosphorIconsFill.fingerprint, 'Una sola vez por curso',
                'Cuando la envíes no podrás modificarla, así que responde con calma.'),
            punto(PhosphorIconsFill.clockCountdown, cierraEn(f.closesAt).isEmpty ? 'Tiempo limitado' : cierraEn(f.closesAt),
                'Son ${f.questions.length} preguntas cortas, toma unos 3 minutos.'),
          ]),
        ),
      ],
    );
  }

  Widget _dimensionPage(String dimension) {
    final qs = _form!.scaleByDimension[dimension]!;
    final faltan = _showMissing ? _faltantes(_step).map((q) => q.id).toSet() : <int?>{};
    final t = context.tokens;
    return ListView(
      padding: const EdgeInsets.all(AppTokens.pagePadding),
      children: [
        SectionTitle(dimension,
            icon: PhosphorIconsRegular.target,
            subtitle: '${qs.where((q) => _values.containsKey(q.id)).length} de ${qs.length} respondidas'),
        const SizedBox(height: 14),
        for (var i = 0; i < qs.length; i++)
          TweenAnimationBuilder<double>(
            key: ValueKey('${dimension}_${qs[i].id}'),
            tween: Tween(begin: 0, end: 1),
            duration: Duration(milliseconds: 350 + i * 100),
            curve: Curves.easeOutCubic,
            builder: (_, v, child) => Opacity(
              opacity: v,
              child: Transform.translate(offset: Offset(0, 16 * (1 - v)), child: child),
            ),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: AppCard(
                blur: false,
                tint: faltan.contains(qs[i].id) ? t.danger : null,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(qs[i].text,
                      style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, height: 1.4)),
                  if (faltan.contains(qs[i].id))
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Semantics(
                        liveRegion: true,
                        child: Text('Falta responder',
                            style: GoogleFonts.poppins(fontSize: 12, color: t.danger, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  const SizedBox(height: 14),
                  RatingOrbs(
                    value: _values[qs[i].id],
                    questionLabel: qs[i].text,
                    onChanged: (v) => setState(() => _values[qs[i].id!] = v),
                  ),
                ]),
              ),
            ),
          ),
      ],
    );
  }

  Widget _finalPage() {
    final t = context.tokens;
    final f = _form!;
    final dados = _values.values.toList();
    final promedio = dados.isEmpty ? null : dados.reduce((a, b) => a + b) / dados.length;
    final porDim = <String, double>{};
    for (final e in f.scaleByDimension.entries) {
      final vs = e.value.map((q) => _values[q.id]).whereType<int>().toList();
      if (vs.isNotEmpty) porDim[e.key] = vs.reduce((a, b) => a + b) / vs.length;
    }

    return ListView(
      padding: const EdgeInsets.all(AppTokens.pagePadding),
      children: [
        const SectionTitle('Casi listo',
            icon: PhosphorIconsRegular.flagCheckered,
            subtitle: 'Revisa tu valoración y, si quieres, déjanos un comentario'),
        const SizedBox(height: 14),
        AppCard(
          blur: false,
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (promedio != null) ScoreRing(value: promedio, size: 84, caption: 'tu promedio'),
              if (promedio != null) const SizedBox(width: 16),
              Expanded(
                child: Wrap(spacing: 8, runSpacing: 6, children: [
                  for (final e in porDim.entries)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: EvalColors.score(e.value, t).withValues(alpha: 0.13),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text('${e.key} · ${e.value.toStringAsFixed(1)}',
                          style: GoogleFonts.poppins(
                              fontSize: 11, fontWeight: FontWeight.w600,
                              color: EvalColors.score(e.value, t))),
                    ),
                ]),
              ),
            ]),
          ]),
        ),
        for (final q in f.textQuestions) ...[
          const SizedBox(height: 14),
          AppCard(
            blur: false,
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const MotionIcon(PhosphorIconsRegular.chatCircleText, size: 20, motion: IconMotion.float),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(q.text,
                      style: GoogleFonts.poppins(fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.35)),
                ),
              ]),
              const SizedBox(height: 10),
              TextField(
                controller: _comments[q.id],
                maxLines: 4,
                maxLength: f.maxCommentLength,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Escribe aquí (opcional). Sé respetuoso y concreto.',
                  hintStyle: GoogleFonts.poppins(fontSize: 13),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ]),
          ),
        ],
        const SizedBox(height: 14),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(PhosphorIconsFill.shieldCheck, size: 18, color: t.success),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Al enviar, tu evaluación queda registrada de forma anónima. No podrás editarla.',
              style: GoogleFonts.poppins(fontSize: 12, color: t.muted, height: 1.4),
            ),
          ),
        ]),
        if (_sendError != null) ...[
          const SizedBox(height: 12),
          Semantics(
            liveRegion: true,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: t.danger.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(AppTokens.radiusControl),
                border: Border.all(color: t.danger.withValues(alpha: 0.4)),
              ),
              child: Text(_sendError!,
                  style: GoogleFonts.poppins(fontSize: 12.5, color: t.danger, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ],
    );
  }

  Widget _success() {
    final t = context.tokens;
    final acc = EvalColors.accent(context);
    final enCola = _done == _Resultado.enCola;
    final col = enCola ? [t.warning, acc.last] : [t.success, acc.first];
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.pagePadding + 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              height: 220,
              child: Stack(alignment: Alignment.center, children: [
                if (!enCola) SparkBurst(colors: [...col, acc.last, Colors.white], size: 260),
                HexMedallion(
                  enCola ? PhosphorIconsFill.cloudArrowUp : PhosphorIconsFill.sealCheck,
                  colors: col, size: 96, motion: IconMotion.tada, ping: true,
                ),
              ]),
            ),
            Semantics(
              liveRegion: true,
              header: true,
              child: Text(enCola ? 'Evaluación guardada' : '¡Gracias por evaluar!',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 8),
            Text(
              enCola
                  ? 'No hay conexión en este momento. Tu evaluación está guardada en el dispositivo y se enviará sola cuando vuelva internet.'
                  : 'Tu evaluación se registró de forma anónima. Tu opinión ayuda a mejorar la calidad de las clases.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(fontSize: 13.5, color: t.muted, height: 1.5),
            ),
            const SizedBox(height: 28),
            AppButton(
              label: 'Volver a mis evaluaciones',
              icon: PhosphorIconsBold.arrowLeft,
              reaction: IconReaction.nudge,
              expand: true,
              onPressed: () => Navigator.pop(context, true),
            ),
          ]),
        ),
      ),
    );
  }
}
