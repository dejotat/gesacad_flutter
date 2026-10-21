import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../config/app_tokens.dart';
import '../../models/evaluation_models.dart';
import '../../services/api_service.dart';
import '../../widgets/eval/eval_widgets.dart';
import '../../widgets/ui/ui.dart';
import 'admin_evaluations_screen.dart' show mensajeError;

/// Cómo se comporta la pestaña según el estado del periodo.
enum ModoParticipantes {
  /// Borrador: se elige libremente quién participa.
  editar,

  /// Publicado y vigente: lo ya habilitado queda bloqueado; se pueden INCORPORAR
  /// los estudiantes o cursos que se sumaron después.
  incorporar,

  /// Cerrado: solo lectura.
  lectura,
}

/// Pestaña "Participantes" del periodo: el Admin elige **qué docentes, cursos y
/// estudiantes** intervienen en la evaluación.
///
/// Muestra el árbol docente → curso (materia) → estudiantes con la matrícula
/// **actual**. Marcar un docente marca todos sus cursos; marcar un curso, todos sus
/// estudiantes; los estados parciales se ven con casillas de tres estados.
///
/// - **Borrador**: editable; "Guardar selección" la envía al servidor.
/// - **Publicado y vigente**: lo habilitado queda bloqueado y se pueden incorporar los
///   nuevos ("Incorporar N participantes"). Con la opción "todos", los nuevos entran solos.
/// - **Cerrado**: solo lectura.
///
/// Se actualiza al mostrarse la pestaña ([EvalParticipantsTabState.recargar]) y explica
/// quién NO aparece: los docentes sin materia y los estudiantes sin matrícula.
class EvalParticipantsTab extends StatefulWidget {
  const EvalParticipantsTab({
    super.key,
    required this.period,
    required this.adminId,
    required this.onDirty,
    required this.onSaved,
  });

  final EvalPeriod period;
  final int adminId;
  final ValueChanged<bool> onDirty;
  final Future<void> Function() onSaved;

  @override
  State<EvalParticipantsTab> createState() => EvalParticipantsTabState();
}

class EvalParticipantsTabState extends State<EvalParticipantsTab>
    with AutomaticKeepAliveClientMixin {
  EvalCandidates? _data;
  bool _loading = true;
  String? _error;
  Set<String> _original = {};
  String _query = '';
  bool _saving = false;
  String? _saveError;

  @override
  bool get wantKeepAlive => true;

  ModoParticipantes get _modo {
    final p = widget.period;
    if (p.isDraft) return ModoParticipantes.editar;
    if (p.phase == EvalPhase.closed) return ModoParticipantes.lectura;
    return ModoParticipantes.incorporar;
  }

  bool get _puedeTocar => _modo != ModoParticipantes.lectura;

  @override
  void initState() {
    super.initState();
    _load(inicial: true);
  }

  @override
  void didUpdateWidget(covariant EvalParticipantsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Al publicar o cerrar cambian las reglas y qué está habilitado: se vuelve a pedir.
    if (oldWidget.period.status != widget.period.status || oldWidget.period.phase != widget.period.phase) {
      _load(forzar: true);
    }
  }

  /// Vuelve a pedir el árbol (p. ej. al volver a la pestaña tras crear un docente o
  /// matricular un estudiante). No pisa una selección sin guardar.
  /// Devuelve `false` si no actualizó por haber cambios locales sin guardar.
  Future<bool> recargar() => _load();

  Future<bool> _load({bool inicial = false, bool forzar = false}) async {
    if (!forzar && !inicial && _dirty) return false;
    setState(() { _loading = _data == null; _error = null; });
    try {
      final d = await ApiService().getEvalCandidates(widget.period.id, widget.adminId);
      if (!mounted) return true;
      setState(() {
        _data = d;
        _original = _keys(d);
        _loading = false;
      });
      widget.onDirty(false);
    } catch (e) {
      if (mounted) setState(() { _error = mensajeError(e); _loading = false; });
    }
    return true;
  }

  // ── Selección ─────────────────────────────────────────────────────────────
  Set<String> _keys(EvalCandidates d) => {
        for (final t in d.teachers)
          for (final c in t.courses)
            for (final s in c.students)
              if (s.selected) _k(c, s),
      };

  String _k(EvalCourseNode c, EvalStudentNode s) => '${c.courseId}:${s.id}';

  bool get _dirty => _data != null && !_sameSet(_keys(_data!), _original);

  bool _sameSet(Set<String> a, Set<String> b) => a.length == b.length && a.containsAll(b);

  /// En el modo incorporar, quien ya estaba habilitado no se puede quitar.
  bool _bloqueado(EvalCourseNode c, EvalStudentNode s) =>
      _modo == ModoParticipantes.incorporar && _original.contains(_k(c, s));

  /// Estudiantes de [c] que se pueden marcar o desmarcar.
  Iterable<EvalStudentNode> _tocables(EvalCourseNode c) => c.students.where((s) => !_bloqueado(c, s));

  void _changed() {
    setState(() => _saveError = null);
    widget.onDirty(_dirty);
  }

  void _setCourse(EvalCourseNode c, bool v) {
    for (final s in _tocables(c)) { s.selected = v; }
    _changed();
  }

  void _setTeacher(EvalTeacherNode t, bool v) {
    for (final c in t.courses) {
      for (final s in _tocables(c)) { s.selected = v; }
    }
    _changed();
  }

  void _setAll(bool v) {
    for (final t in _data!.teachers) {
      for (final c in t.courses) {
        for (final s in _tocables(c)) { s.selected = v; }
      }
    }
    _changed();
  }

  /// Casilla de tres estados: nada / parcial / todo.
  bool? _tri(int selected, int total) =>
      total == 0 || selected == 0 ? false : (selected == total ? true : null);

  /// ¿Marcar o desmarcar al pulsar? Si todo lo tocable ya está marcado, se desmarca.
  bool _alternar(Iterable<EvalStudentNode> tocables) =>
      tocables.isNotEmpty && !tocables.every((s) => s.selected);

  Future<void> _guardar() async {
    final d = _data!;
    setState(() { _saving = true; _saveError = null; });
    try {
      if (_modo == ModoParticipantes.incorporar) {
        // Solo lo NUEVO: lo que ya estaba habilitado no se vuelve a enviar.
        final seleccion = <Map<String, dynamic>>[
          for (final t in d.teachers)
            for (final c in t.courses)
              if (_tocables(c).any((s) => s.selected))
                {
                  'courseId': c.courseId,
                  'studentIds': [for (final s in _tocables(c)) if (s.selected) s.id],
                },
        ];
        final r = await ApiService().addEvalParticipants(widget.period.id, widget.adminId, seleccion);
        if (!mounted) return;
        setState(() => _saving = false);
        widget.onDirty(false);
        await widget.onSaved();
        await _load(forzar: true);
        if (!mounted) return;
        _aviso('Se incorporaron ${r['added']} participantes'
            '${(r['newCourses'] as num? ?? 0) > 0 ? " y ${r['newCourses']} curso(s) nuevo(s)" : ""}.');
        return;
      }

      final todos = d.teachers.every((t) => t.selectedCount == t.studentCount);
      final seleccion = <Map<String, dynamic>>[
        for (final t in d.teachers)
          for (final c in t.courses)
            if (c.selectedCount > 0)
              {
                'courseId': c.courseId,
                'studentIds': [for (final s in c.students) if (s.selected) s.id],
              },
      ];
      // Todos seleccionados = modo "todos": sigue la matrícula hasta publicar.
      await ApiService().saveEvalScope(widget.period.id, widget.adminId,
          selection: todos ? null : seleccion);
      if (!mounted) return;
      _original = _keys(d);
      setState(() => _saving = false);
      widget.onDirty(false);
      await widget.onSaved();
      if (mounted) _aviso('Participantes guardados.');
    } catch (e) {
      if (mounted) setState(() { _saving = false; _saveError = mensajeError(e); });
    }
  }

  void _aviso(String texto) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: context.tokens.success,
      content: Text(texto, style: GoogleFonts.poppins(color: Colors.white)),
    ));
  }

  // ── Filtro ────────────────────────────────────────────────────────────────
  bool _coincide(String s) => _query.isEmpty || s.toLowerCase().contains(_query);

  /// Estudiantes visibles de un curso según el buscador (si coincide el docente
  /// o el curso, se muestran todos sus estudiantes).
  List<EvalStudentNode> _visibles(EvalTeacherNode t, EvalCourseNode c) {
    var lista = c.students;
    if (_modo == ModoParticipantes.lectura) lista = lista.where((s) => s.selected).toList();
    if (_query.isEmpty || _coincide(t.name) || _coincide(c.courseName)) return lista;
    return lista.where((s) => _coincide(s.username)).toList();
  }

  bool _cursoVisible(EvalTeacherNode t, EvalCourseNode c) {
    if (_modo == ModoParticipantes.lectura && c.selectedCount == 0) return false;
    if (_query.isEmpty) return true;
    return _coincide(t.name) || _coincide(c.courseName) || _visibles(t, c).isNotEmpty;
  }

  // ── Interfaz ──────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) {
      return ListView(
        padding: const EdgeInsets.all(AppTokens.pagePadding),
        children: const [SkeletonBox(height: 120), SizedBox(height: 12), SkeletonBox(height: 160)],
      );
    }
    if (_error != null) return ErrorState(message: _error!, onRetry: _load);
    final d = _data!;
    final t = context.tokens;

    final docentes = d.teachers.where((x) => x.courses.any((c) => _cursoVisible(x, c))).toList();
    final totalAlumnos = d.teachers.fold<int>(0, (a, x) => a + x.studentCount);
    final selAlumnos = d.teachers.fold<int>(0, (a, x) => a + x.selectedCount);
    final selCursos = d.teachers.fold<int>(
        0, (a, x) => a + x.courses.where((c) => c.selectedCount > 0).length);
    final selDocentes = d.teachers.where((x) => x.selectedCount > 0).length;
    final nuevos = _modo == ModoParticipantes.incorporar
        ? d.teachers.fold<int>(0, (a, x) => a + x.courses.fold<int>(
            0, (b, c) => b + _tocables(c).where((s) => s.selected).length))
        : 0;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: RefreshIndicator(
          onRefresh: () => _load(forzar: true),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
                AppTokens.pagePadding, AppTokens.pagePadding, AppTokens.pagePadding, 40),
            children: [
              _resumen(context, selDocentes, selCursos, selAlumnos, totalAlumnos),
              const SizedBox(height: 12),
              if (_puedeTocar) _buscador(context),
              if (_modo == ModoParticipantes.incorporar && widget.period.scopeMode == 'all')
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: _info(context, PhosphorIconsFill.arrowsClockwise, t.success,
                      'Este periodo incluye a todos: los estudiantes y cursos que se sumen '
                      'entran solos. Actualiza esta pestaña para verlos.'),
                ),
              if (_modo == ModoParticipantes.incorporar && widget.period.scopeMode != 'all' && nuevos == 0)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: _info(context, PhosphorIconsFill.info, t.info,
                      'Este periodo tiene una selección personalizada. Si se matricula alguien '
                      'después, aparecerá aquí sin marcar para que lo incorpores.'),
                ),
              if (_puedeTocar) ..._sinAsignar(context, d),
              if (d.coursesWithoutTeacher > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: _info(context, PhosphorIconsFill.info, t.info,
                      '${d.coursesWithoutTeacher} ${d.coursesWithoutTeacher == 1 ? "curso no aparece" : "cursos no aparecen"} '
                      'porque no tienen un docente asignado.'),
                ),
              const SizedBox(height: 14),
              if (d.teachers.isEmpty)
                const EmptyState(
                  icon: PhosphorIconsRegular.chalkboardTeacher,
                  message: 'No hay docentes con cursos asignados.\nAsigna un docente a una materia '
                      'en "Gestionar Materias".',
                )
              else if (docentes.isEmpty)
                const EmptyState(
                  icon: PhosphorIconsRegular.magnifyingGlass,
                  message: 'Sin coincidencias.\nPrueba con otro nombre.',
                ),
              for (final docente in docentes) _docente(context, docente),
              if (_puedeTocar && d.teachers.isNotEmpty) ...[
                const SizedBox(height: 8),
                if (_modo == ModoParticipantes.editar && selAlumnos == 0)
                  _info(context, PhosphorIconsFill.warning, t.warning,
                      'Selecciona al menos un estudiante para poder publicar la evaluación.'),
                if (_saveError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(_saveError!,
                          style: GoogleFonts.poppins(
                              fontSize: 12.5, color: t.danger, fontWeight: FontWeight.w600)),
                    ),
                  ),
                const SizedBox(height: 12),
                if (_modo == ModoParticipantes.editar)
                  AppButton(
                    label: _dirty ? 'Guardar selección' : 'Selección guardada',
                    icon: _dirty ? PhosphorIconsFill.floppyDisk : PhosphorIconsFill.checkCircle,
                    reaction: IconReaction.bounce,
                    expand: true,
                    loading: _saving,
                    onPressed: _dirty && selAlumnos > 0 && !_saving ? _guardar : null,
                  )
                else
                  AppButton(
                    label: nuevos > 0
                        ? 'Incorporar $nuevos ${nuevos == 1 ? "participante" : "participantes"}'
                        : 'Marca a quienes quieras incorporar',
                    icon: PhosphorIconsFill.userPlus,
                    reaction: IconReaction.pop,
                    expand: true,
                    loading: _saving,
                    onPressed: nuevos > 0 && !_saving ? _guardar : null,
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Quién NO aparece en el árbol y cómo arreglarlo.
  List<Widget> _sinAsignar(BuildContext context, EvalCandidates d) {
    final t = context.tokens;
    final docs = d.unassignedTeachers;
    final ests = d.unassignedStudents;
    if (docs.isEmpty && ests.isEmpty) return const [];

    Widget bloque(IconData icon, String titulo, String ayuda, List<EvalPerson> gente) => Container(
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: t.warning.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppTokens.radiusControl),
            border: Border.all(color: t.warning.withValues(alpha: 0.35)),
          ),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              key: PageStorageKey('sin_${titulo.hashCode}'),
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(top: 4),
              leading: Icon(icon, color: t.warning, size: 22),
              title: Text('$titulo (${gente.length})',
                  style: GoogleFonts.poppins(fontSize: 13.5, fontWeight: FontWeight.w700)),
              subtitle: Text(ayuda,
                  style: GoogleFonts.poppins(fontSize: 11.5, color: t.muted, height: 1.35)),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(spacing: 8, runSpacing: 4, children: [
                    for (final p in gente)
                      Chip(
                        label: Text(p.name, style: GoogleFonts.poppins(fontSize: 12)),
                        visualDensity: VisualDensity.compact,
                      ),
                  ]),
                ),
              ],
            ),
          ),
        );

    return [
      if (docs.isNotEmpty)
        bloque(PhosphorIconsFill.chalkboardTeacher, 'Docentes sin materia asignada',
            'No aparecen en el árbol hasta tener un curso. Asígnalo en "Gestionar Materias" y '
            'vuelve aquí: aparecerá solo.', docs),
      if (ests.isNotEmpty)
        bloque(PhosphorIconsFill.student, 'Estudiantes sin curso con docente',
            'Matricúlalos en una materia que tenga docente y aparecerán solos.', ests),
    ];
  }

  Widget _resumen(BuildContext context, int docentes, int cursos, int alumnos, int total) {
    final t = context.tokens;
    final acc = EvalColors.accent(context);
    final (String titulo, String sub) = switch (_modo) {
      ModoParticipantes.editar => (
          'Participantes de la evaluación',
          'Elige qué docentes, cursos y estudiantes participan'
        ),
      ModoParticipantes.incorporar => (
          'Participantes habilitados',
          'Los ya habilitados quedan bloqueados; puedes incorporar a los nuevos'
        ),
      ModoParticipantes.lectura => ('Participantes habilitados', 'Periodo cerrado: solo lectura'),
    };
    return NeonFrame(
      colors: acc,
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          HexMedallion(PhosphorIconsFill.usersThree, colors: acc, size: 42, motion: IconMotion.float),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Semantics(
                header: true,
                child: Text(titulo, style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              Text(sub, style: GoogleFonts.poppins(fontSize: 12, color: t.muted)),
            ]),
          ),
          if (_puedeTocar)
            AnimatedIconButton(
              tooltip: 'Actualizar participantes',
              icon: PhosphorIconsRegular.arrowsClockwise,
              reaction: IconReaction.spin,
              onPressed: () async {
                final mensajero = ScaffoldMessenger.of(context);
                final aviso = context.tokens.warning;
                final ok = await _load(forzar: false);
                if (!ok) {
                  mensajero.showSnackBar(SnackBar(
                    behavior: SnackBarBehavior.floating,
                    backgroundColor: aviso,
                    content: Text('Tienes cambios sin guardar: guárdalos para actualizar.',
                        style: GoogleFonts.poppins(color: Colors.white)),
                  ));
                }
              },
            ),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _chip(PhosphorIconsRegular.chalkboardTeacher, '$docentes ${docentes == 1 ? "docente" : "docentes"}', acc.first),
          _chip(PhosphorIconsRegular.books, '$cursos ${cursos == 1 ? "curso" : "cursos"}', t.chart[0]),
          _chip(PhosphorIconsRegular.student, '$alumnos de $total estudiantes', t.chart[4]),
        ]),
        if (_modo != ModoParticipantes.lectura) ...[
          const SizedBox(height: 12),
          Row(children: [
            AppButton(
              label: _modo == ModoParticipantes.editar ? 'Seleccionar todos' : 'Marcar nuevos',
              icon: PhosphorIconsBold.checks, height: 40,
              style: AppButtonStyle.tonal, onPressed: () => _setAll(true),
            ),
            const SizedBox(width: 10),
            AppButton(
              label: _modo == ModoParticipantes.editar ? 'Ninguno' : 'Desmarcar',
              icon: PhosphorIconsBold.x, height: 40,
              style: AppButtonStyle.outline, onPressed: () => _setAll(false),
            ),
          ]),
        ],
      ]),
    );
  }

  Widget _chip(IconData icon, String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 5),
          Text(text, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
        ]),
      );

  Widget _buscador(BuildContext context) => TextField(
        onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
        decoration: InputDecoration(
          hintText: 'Buscar docente, curso o estudiante',
          hintStyle: GoogleFonts.poppins(fontSize: 13),
          prefixIcon: const Icon(PhosphorIconsRegular.magnifyingGlass),
        ),
      );

  Widget _info(BuildContext context, IconData icon, Color color, String texto) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(AppTokens.radiusControl),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(texto, style: GoogleFonts.poppins(fontSize: 12.5, height: 1.4))),
        ]),
      );

  Widget _casilla(String etiqueta, bool? valor, bool habilitada, VoidCallback onTap) => Semantics(
        label: etiqueta,
        child: Checkbox(
          tristate: true,
          value: valor,
          onChanged: habilitada ? (_) => onTap() : null,
        ),
      );

  Widget _docente(BuildContext context, EvalTeacherNode docente) {
    final t = context.tokens;
    final cursos = docente.courses.where((c) => _cursoVisible(docente, c)).toList();
    final sel = docente.selectedCount;
    final total = docente.studentCount;
    final tocables = [for (final c in docente.courses) ..._tocables(c)];

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        blur: false,
        padding: EdgeInsets.zero,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: PageStorageKey('doc_${docente.id}'),
            initiallyExpanded: _data!.teachers.length <= 3 || _query.isNotEmpty,
            tilePadding: const EdgeInsets.symmetric(horizontal: 12),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            leading: Row(mainAxisSize: MainAxisSize.min, children: [
              if (_puedeTocar)
                _casilla('Seleccionar todos los cursos de ${docente.name}',
                    _tri(sel, total), tocables.isNotEmpty,
                    () => _setTeacher(docente, _alternar(tocables))),
              HexMedallion(PhosphorIconsFill.chalkboardTeacher,
                  colors: EvalColors.accent(context), size: 26, orbit: false, motion: IconMotion.none),
            ]),
            title: Text(docente.name,
                style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700)),
            subtitle: Text(
              '${docente.courses.length} ${docente.courses.length == 1 ? "curso" : "cursos"} · '
              '$sel de $total estudiantes',
              style: GoogleFonts.poppins(fontSize: 12, color: t.muted),
            ),
            children: [for (final c in cursos) _curso(context, docente, c)],
          ),
        ),
      ),
    );
  }

  Widget _curso(BuildContext context, EvalTeacherNode docente, EvalCourseNode curso) {
    final t = context.tokens;
    final alumnos = _visibles(docente, curso);
    final sel = curso.selectedCount;
    final tocables = _tocables(curso).toList();

    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: t.glass,
        borderRadius: BorderRadius.circular(AppTokens.radiusControl),
        border: Border.all(color: t.glassBorder),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: PageStorageKey('cur_${curso.courseId}'),
          initiallyExpanded: _query.isNotEmpty,
          tilePadding: const EdgeInsets.symmetric(horizontal: 8),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          leading: _puedeTocar
              ? _casilla('Seleccionar todos los estudiantes de ${curso.courseName}',
                  _tri(sel, curso.students.length), tocables.isNotEmpty,
                  () => _setCourse(curso, _alternar(tocables)))
              : const Icon(PhosphorIconsRegular.bookOpen, size: 20),
          title: Text(curso.courseName,
              style: GoogleFonts.poppins(fontSize: 13.5, fontWeight: FontWeight.w600)),
          subtitle: Text('$sel de ${curso.students.length} estudiantes',
              style: GoogleFonts.poppins(fontSize: 11.5, color: t.muted)),
          children: [
            if (alumnos.isEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Sin estudiantes que mostrar.',
                    style: GoogleFonts.poppins(fontSize: 12, color: t.muted)),
              )
            else
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(spacing: 8, runSpacing: 4, children: [
                  for (final s in alumnos)
                    FilterChip(
                      label: Text(s.username, style: GoogleFonts.poppins(fontSize: 12)),
                      avatar: Icon(
                          s.selected ? PhosphorIconsFill.student : PhosphorIconsRegular.student,
                          size: 16),
                      selected: s.selected,
                      visualDensity: VisualDensity.compact,
                      // Bloqueado: ya estaba habilitado (solo se pueden sumar, no quitar).
                      onSelected: _puedeTocar && !_bloqueado(curso, s)
                          ? (v) { s.selected = v; _changed(); }
                          : null,
                    ),
                ]),
              ),
          ],
        ),
      ),
    );
  }
}
