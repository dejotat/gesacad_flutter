import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../config/app_tokens.dart';
import '../../models/semaforo_models.dart';
import '../../services/api_service.dart' show ApiMessageException;
import '../../services/connectivity_service.dart' show isNetworkError;
import '../../services/semaforo_service.dart';
import '../../widgets/ui/ui.dart';

/// Naranja del estado «Pre-requisito» (el mismo `EA580C` de las tarjetas de curso).
const Color kColorPrerequisito = Color(0xFFEA580C);

/// Color de cada estado, tomado de los tokens del tema (verde, azul, rojo, ámbar) más el naranja
/// del pre-requisito. El gris es el «pendiente». El color NUNCA va solo: cada tarjeta lleva además
/// un ícono y el nombre del estado.
Color colorDeEstado(EstadoMateria e, AppTokens t) => switch (e) {
      EstadoMateria.approved => t.success,
      EstadoMateria.inProgress => t.info,
      EstadoMateria.failed => t.danger,
      EstadoMateria.cancelled => t.warning,
      EstadoMateria.blocked => kColorPrerequisito,
      EstadoMateria.pending => t.muted,
    };

IconData iconoDeEstado(EstadoMateria e) => switch (e) {
      EstadoMateria.approved => PhosphorIconsFill.checkCircle,
      EstadoMateria.inProgress => PhosphorIconsRegular.hourglassMedium,
      EstadoMateria.failed => PhosphorIconsFill.xCircle,
      EstadoMateria.cancelled => PhosphorIconsRegular.minusCircle,
      EstadoMateria.blocked => PhosphorIconsRegular.lockSimple,
      EstadoMateria.pending => PhosphorIconsRegular.circleDashed,
    };

String _romano(int n) {
  const m = [(10, 'X'), (9, 'IX'), (5, 'V'), (4, 'IV'), (1, 'I')];
  var r = '';
  for (final (v, s) in m) {
    while (n >= v) {
      r += s;
      n -= v;
    }
  }
  return r;
}

String fmtNota(double? n) {
  if (n == null) return '—';
  final s = n.toStringAsFixed(2); // 4.20 → «4.2», 4.00 → «4.0», 3.75 → «3.75»
  return s.endsWith('0') ? s.substring(0, s.length - 1) : s;
}

/// Semáforo académico (CU-14): la malla curricular del estudiante, por semestre y por área, con
/// el estado de cada materia en color (verde aprobada, azul en curso, rojo reprobada, amarillo
/// cancelada, naranja con pre-requisito pendiente, gris pendiente).
///
/// La ven el propio **estudiante**, su **docente** (que además registra la nota definitiva de sus
/// materias) y el **administrador** (que puede hacer correcciones excepcionales con motivo y ver
/// el historial de cambios).
class SemaforoScreen extends StatefulWidget {
  const SemaforoScreen({
    super.key,
    required this.studentId,
    required this.rol,
    this.studentName,
    this.teacherCourseIds = const {},
    this.service = const SemaforoService(),
  });

  final int studentId;

  /// Rol de quien mira: 'Student', 'Teacher' o 'Admin'.
  final String rol;
  final String? studentName;

  /// Materias que dicta el docente que mira (solo en esas puede registrar la nota).
  final Set<int> teacherCourseIds;
  final SemaforoService service;

  @override
  State<SemaforoScreen> createState() => _SemaforoScreenState();
}

class _SemaforoScreenState extends State<SemaforoScreen> {
  Semaforo? _datos;
  String? _error;
  bool _cargando = true;

  static const double _anchoColumna = 172;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final d = await widget.service.semaforo(widget.studentId);
      if (!mounted) return;
      setState(() {
        _datos = d;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = e is ApiMessageException
            ? e.message
            : isNetworkError(e)
                ? 'Sin conexión. El semáforo necesita conexión con el servidor.'
                : 'No se pudo cargar el semáforo académico.';
      });
    }
  }

  Future<void> _verHistorial() async {
    try {
      final lista = await widget.service.auditoria(widget.studentId);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _HistorialSheet(entradas: lista),
      );
    } catch (e) {
      if (mounted) _aviso(e is ApiMessageException ? e.message : 'No se pudo cargar el historial.');
    }
  }

  void _aviso(String texto) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(texto)));

  Future<void> _abrirDetalle(MateriaSemaforo m) async {
    final d = _datos!;
    final cambio = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _DetalleMateria(
        materia: m,
        minApprove: d.minApprove,
        studentId: widget.studentId,
        rol: widget.rol,
        puedeCalificar: widget.rol == 'Teacher' &&
            widget.teacherCourseIds.contains(m.courseId) &&
            (m.status == EstadoMateria.inProgress ||
                m.status == EstadoMateria.approved ||
                m.status == EstadoMateria.failed),
        service: widget.service,
      ),
    );
    if (cambio == true) {
      _aviso('Cambio guardado.');
      _cargar();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Semáforo académico'),
        actions: [
          if (widget.rol == 'Admin')
            IconButton(
              tooltip: 'Historial de cambios',
              icon: const Icon(PhosphorIconsRegular.clockCounterClockwise),
              onPressed: _datos == null ? null : _verHistorial,
            ),
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(PhosphorIconsRegular.arrowsClockwise),
            onPressed: _cargando ? null : _cargar,
          ),
        ],
      ),
      body: _cargando && _datos == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _datos == null
              ? ErrorState(message: _error!, onRetry: _cargar)
              : RefreshIndicator(onRefresh: _cargar, child: _contenido(_datos!)),
    );
  }

  Widget _contenido(Semaforo d) {
    final t = context.tokens;
    final s = d.summary;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppTokens.pagePadding),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              PageHeader(
                title: widget.studentName ?? (d.studentName.isEmpty ? 'Semáforo académico' : d.studentName),
                subtitle: d.program?.isNotEmpty == true ? d.program! : 'Malla curricular por semestre',
                leading: const Icon(PhosphorIconsRegular.trafficSignal, color: Colors.white, size: 30),
                chips: [
                  HeaderChip(PhosphorIconsRegular.checkCircle, '${s.approved} de ${s.total} aprobadas'),
                  if (s.totalCredits > 0)
                    HeaderChip(PhosphorIconsRegular.stack, '${s.approvedCredits}/${s.totalCredits} créditos'),
                  if (s.average != null) HeaderChip(PhosphorIconsRegular.trophy, 'Promedio ${fmtNota(s.average)}'),
                ],
              ),
              const SizedBox(height: 16),
              _Leyenda(resumen: s),
              const SizedBox(height: 16),
            ]),
          ),
        ),
        if (d.courses.isEmpty)
          const EmptyState(
            icon: PhosphorIconsRegular.graduationCap,
            message: 'Aún no hay materias en el plan de estudios.\n'
                'El administrador debe ubicarlas en la malla.',
          )
        else
          _malla(d, t),
        const SizedBox(height: 80),
      ],
    );
  }

  /// La malla: columnas por semestre y filas por área, con desplazamiento horizontal si no cabe.
  Widget _malla(Semaforo d, AppTokens t) {
    final semestres = d.semestres;
    final sinSemestre = d.courses.where((c) => c.semester == null).toList();
    final onSurface = Theme.of(context).colorScheme.onSurface;

    Widget banda(String texto, double ancho) => Container(
          width: ancho,
          margin: const EdgeInsets.only(top: 10, bottom: 8),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
          decoration: BoxDecoration(
            color: onSurface.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: t.border),
          ),
          child: Text(texto.toUpperCase(),
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.4, color: onSurface)),
        );

    final anchoTotal = semestres.length * _anchoColumna;
    final secciones = <Widget>[];
    if (semestres.isNotEmpty) {
      secciones.add(Row(children: [
        for (final n in semestres)
          SizedBox(
            width: _anchoColumna,
            child: Center(
              child: Semantics(
                header: true,
                label: 'Semestre $n',
                child: ExcludeSemantics(
                  child: Text(_romano(n),
                      style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: onSurface.withValues(alpha: 0.85))),
                ),
              ),
            ),
          ),
      ]));
      for (final area in [...areasMalla, null]) {
        final deArea = d.courses.where((c) => c.semester != null && c.area == area).toList();
        if (deArea.isEmpty) continue;
        secciones.add(banda(nombreDeArea(area), anchoTotal));
        secciones.add(Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final n in semestres)
            SizedBox(
              width: _anchoColumna,
              child: Column(children: [
                for (final m in deArea.where((c) => c.semester == n))
                  Padding(
                    padding: const EdgeInsets.only(right: 10, bottom: 10),
                    child: _TarjetaMateria(materia: m, onTap: () => _abrirDetalle(m)),
                  ),
              ]),
            ),
        ]));
      }
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        // stretch: la malla ocupa todo el ancho disponible y arranca a la izquierda, alineada con
        // el encabezado (sin esto se centraba y las columnas quedaban desalineadas).
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (semestres.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: secciones),
            ),
          if (sinSemestre.isNotEmpty) ...[
            banda('Sin semestre asignado', 1100),
            Wrap(spacing: 10, runSpacing: 10, children: [
              for (final m in sinSemestre) _TarjetaMateria(materia: m, onTap: () => _abrirDetalle(m)),
            ]),
          ],
        ]),
      ),
    );
  }
}

// ── Leyenda de colores ────────────────────────────────────────────────────────

class _Leyenda extends StatelessWidget {
  const _Leyenda({required this.resumen});
  final ResumenSemaforo resumen;

  // El orden de la referencia (SIU): En curso, Aprobada, Reprobada, Cancelada, Pre-requisito, Pendiente.
  static const _orden = [
    EstadoMateria.inProgress,
    EstadoMateria.approved,
    EstadoMateria.failed,
    EstadoMateria.cancelled,
    EstadoMateria.blocked,
    EstadoMateria.pending,
  ];

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Semantics(
      container: true,
      label: 'Leyenda de colores: ${_orden.map((e) => '${e.etiqueta} ${resumen.cuenta(e)}').join(', ')}.',
      child: ExcludeSemantics(
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          for (final e in _orden)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              decoration: BoxDecoration(
                color: colorDeEstado(e, t).withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: colorDeEstado(e, t).withValues(alpha: 0.7)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(iconoDeEstado(e), size: 15, color: colorDeEstado(e, t)),
                const SizedBox(width: 6),
                Text(e.etiqueta, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: onSurface)),
                const SizedBox(width: 6),
                Text('${resumen.cuenta(e)}', style: GoogleFonts.poppins(fontSize: 12, color: onSurface.withValues(alpha: 0.65))),
              ]),
            ),
        ]),
      ),
    );
  }
}

// ── Tarjeta de una materia ────────────────────────────────────────────────────

class _TarjetaMateria extends StatefulWidget {
  const _TarjetaMateria({required this.materia, required this.onTap});
  final MateriaSemaforo materia;
  final VoidCallback onTap;

  @override
  State<_TarjetaMateria> createState() => _TarjetaMateriaState();
}

class _TarjetaMateriaState extends State<_TarjetaMateria> {
  bool _encima = false;

  String get _detalle {
    final m = widget.materia;
    switch (m.status) {
      case EstadoMateria.approved:
      case EstadoMateria.failed:
        return 'Definitiva: ${fmtNota(m.grade)}';
      case EstadoMateria.inProgress:
        return m.suggestedGrade != null ? 'En curso · parcial ${fmtNota(m.suggestedGrade)}' : 'En curso';
      case EstadoMateria.blocked:
        return 'Falta pre-requisito';
      case EstadoMateria.cancelled:
        return 'Cancelada';
      case EstadoMateria.pending:
        return 'Pendiente';
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final m = widget.materia;
    final c = colorDeEstado(m.status, t);
    final vacio = m.status == EstadoMateria.pending;

    return Semantics(
      button: true,
      label: '${m.name}. ${m.status.etiqueta}.'
          '${m.status == EstadoMateria.approved || m.status == EstadoMateria.failed ? ' Nota definitiva ${fmtNota(m.grade)}.' : ''}'
          '${m.credits != null ? ' ${m.credits} créditos.' : ''}',
      excludeSemantics: true,
      onTap: widget.onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _encima = true),
        onExit: (_) => setState(() => _encima = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 162,
            height: 108,
            transform: Matrix4.translationValues(0, _encima ? -2 : 0, 0),
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            decoration: BoxDecoration(
              gradient: vacio
                  ? null
                  : LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [c.withValues(alpha: 0.34), c.withValues(alpha: 0.14)]),
              color: vacio ? onSurface.withValues(alpha: 0.05) : null,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: c.withValues(alpha: vacio ? 0.45 : 0.85), width: _encima ? 2 : 1.2),
              boxShadow: vacio || !_encima ? null : [BoxShadow(color: c.withValues(alpha: 0.35), blurRadius: 14)],
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Text(m.name,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(fontSize: 11.5, height: 1.2, fontWeight: FontWeight.w600, color: onSurface)),
                ),
                if (m.credits != null) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(color: c.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(6)),
                    child: Text('${m.credits} Cr.',
                        style: GoogleFonts.poppins(fontSize: 9.5, fontWeight: FontWeight.w700, color: onSurface)),
                  ),
                ],
              ]),
              const Spacer(),
              Row(children: [
                Icon(iconoDeEstado(m.status), size: 14, color: c),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(_detalle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(fontSize: 10.5, fontWeight: FontWeight.w600, color: onSurface.withValues(alpha: 0.9))),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

// ── Detalle de una materia (y acciones según el rol) ──────────────────────────

class _DetalleMateria extends StatefulWidget {
  const _DetalleMateria({
    required this.materia,
    required this.minApprove,
    required this.studentId,
    required this.rol,
    required this.puedeCalificar,
    required this.service,
  });

  final MateriaSemaforo materia;
  final double minApprove;
  final int studentId;
  final String rol;
  final bool puedeCalificar;
  final SemaforoService service;

  @override
  State<_DetalleMateria> createState() => _DetalleMateriaState();
}

class _DetalleMateriaState extends State<_DetalleMateria> {
  final _nota = TextEditingController();
  final _motivo = TextEditingController();
  EstadoMateria _estado = EstadoMateria.approved;
  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final g = widget.materia.grade;
    if (g != null) _nota.text = g.toString();
  }

  @override
  void dispose() {
    _nota.dispose();
    _motivo.dispose();
    super.dispose();
  }

  double? _leerNota() {
    final n = double.tryParse(_nota.text.trim().replaceAll(',', '.'));
    if (n == null || n < 0 || n > 5) return null;
    return n;
  }

  Future<void> _ejecutar(Future<void> Function() accion) async {
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await accion();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _guardando = false;
          _error = e is ApiMessageException ? e.message : 'No se pudo guardar. Revisa tu conexión.';
        });
      }
    }
  }

  void _registrarNota() {
    final n = _leerNota();
    if (n == null) {
      setState(() => _error = 'Escribe una nota entre 0 y 5.');
      return;
    }
    _ejecutar(() => widget.service.registrarNota(widget.studentId, widget.materia.courseId, n));
  }

  void _corregir() {
    final conNota = _estado == EstadoMateria.approved || _estado == EstadoMateria.failed;
    double? n;
    if (conNota) {
      n = _leerNota();
      if (n == null) {
        setState(() => _error = 'Escribe la nota (0 a 5).');
        return;
      }
    }
    if (_motivo.text.trim().length < 5) {
      setState(() => _error = 'Escribe el motivo de la corrección (mínimo 5 caracteres).');
      return;
    }
    _ejecutar(() => widget.service.corregir(widget.studentId, widget.materia.courseId,
        estado: _estado, nota: n, motivo: _motivo.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final m = widget.materia;
    final c = colorDeEstado(m.status, t);
    final fecha = m.updatedAt == null ? null : DateFormat("d MMM y · h:mm a", 'es').format(m.updatedAt!);

    Widget dato(IconData icono, String texto) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            Icon(icono, size: 16, color: t.muted),
            const SizedBox(width: 8),
            Expanded(child: Text(texto, style: GoogleFonts.poppins(fontSize: 13, color: onSurface))),
          ]),
        );

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(m.name, style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: onSurface)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: c.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: c.withValues(alpha: 0.8)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(iconoDeEstado(m.status), size: 16, color: c),
              const SizedBox(width: 6),
              Text(m.status.etiqueta, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: onSurface)),
            ]),
          ),
          const SizedBox(height: 14),
          dato(PhosphorIconsRegular.hash, 'Código ${m.code}'),
          dato(PhosphorIconsRegular.squaresFour,
              '${nombreDeArea(m.area)}${m.semester != null ? ' · Semestre ${m.semester}' : ''}${m.credits != null ? ' · ${m.credits} créditos' : ''}'),
          if (m.grade != null) dato(PhosphorIconsRegular.trophy, 'Nota definitiva: ${fmtNota(m.grade)}'),
          if (m.suggestedGrade != null)
            dato(PhosphorIconsRegular.chartLine, 'Promedio parcial de lo calificado: ${fmtNota(m.suggestedGrade)} (no es la nota definitiva)'),
          if (m.prerequisites.isNotEmpty)
            dato(PhosphorIconsRegular.lockSimple,
                'Pre-requisitos: ${m.prerequisites.map((p) => m.missingPrerequisites.contains(p.id) ? '${p.name} (pendiente)' : p.name).join(', ')}'),
          if (fecha != null) dato(PhosphorIconsRegular.clock, 'Actualizado $fecha'),

          // ── DOCENTE: nota definitiva ──
          if (widget.puedeCalificar) ...[
            const Divider(height: 28),
            Text('Registrar nota definitiva', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: onSurface)),
            const SizedBox(height: 4),
            Text('Con ${fmtNota(widget.minApprove)} o más la materia queda aprobada; con menos, reprobada. '
                'El sistema decide el color.',
                style: GoogleFonts.poppins(fontSize: 12, color: t.muted)),
            const SizedBox(height: 10),
            TextField(
              controller: _nota,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Nota definitiva (0 a 5)',
                prefixIcon: const Icon(PhosphorIconsRegular.trophy),
                suffix: m.suggestedGrade == null
                    ? null
                    : TextButton(
                        onPressed: () => setState(() => _nota.text = m.suggestedGrade!.toStringAsFixed(1)),
                        child: const Text('Usar parcial')),
              ),
            ),
            const SizedBox(height: 12),
            _boton('Registrar nota', _registrarNota),
          ],

          // ── ADMIN: corrección excepcional ──
          if (widget.rol == 'Admin') ...[
            const Divider(height: 28),
            Text('Corrección excepcional', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: onSurface)),
            const SizedBox(height: 4),
            Text('Solo para homologaciones, errores o retiros. Queda registrado quién, cuándo y por qué.',
                style: GoogleFonts.poppins(fontSize: 12, color: t.muted)),
            const SizedBox(height: 10),
            DropdownButtonFormField<EstadoMateria>(
              initialValue: _estado,
              decoration: const InputDecoration(labelText: 'Nuevo estado', prefixIcon: Icon(PhosphorIconsRegular.trafficSignal)),
              items: const [
                DropdownMenuItem(value: EstadoMateria.approved, child: Text('Aprobada')),
                DropdownMenuItem(value: EstadoMateria.failed, child: Text('Reprobada')),
                DropdownMenuItem(value: EstadoMateria.cancelled, child: Text('Cancelada')),
                DropdownMenuItem(value: EstadoMateria.pending, child: Text('Quitar resultado (vuelve a pendiente / en curso)')),
              ],
              onChanged: (v) => setState(() => _estado = v ?? _estado),
            ),
            if (_estado == EstadoMateria.approved || _estado == EstadoMateria.failed) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _nota,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Nota (${_estado == EstadoMateria.approved ? '${fmtNota(widget.minApprove)} o más' : 'menos de ${fmtNota(widget.minApprove)}'})',
                  prefixIcon: const Icon(PhosphorIconsRegular.trophy),
                ),
              ),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: _motivo,
              maxLength: 300,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Motivo (obligatorio)', prefixIcon: Icon(PhosphorIconsRegular.note)),
            ),
            _boton('Guardar corrección', _corregir),
          ],

          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Semantics(
                liveRegion: true,
                child: Text(_error!, style: GoogleFonts.poppins(fontSize: 12.5, color: t.danger)),
              ),
            ),
        ]),
      ),
    );
  }


  Widget _boton(String texto, VoidCallback onPressed) => SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _guardando ? null : onPressed,
          child: _guardando
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(texto),
        ),
      );
}

// ── Historial de cambios (Admin) ──────────────────────────────────────────────

class _HistorialSheet extends StatelessWidget {
  const _HistorialSheet({required this.entradas});
  final List<EntradaAuditoria> entradas;

  static String _estado(String? s) => s == null ? 'sin resultado' : EstadoMateria.desde(s).etiqueta.toLowerCase();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final fmt = DateFormat("d MMM y · h:mm a", 'es');
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.7,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
          child: Text('Historial de cambios', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: onSurface)),
        ),
        Expanded(
          child: entradas.isEmpty
              ? const EmptyState(icon: PhosphorIconsRegular.clockCounterClockwise, message: 'Aún no hay cambios registrados.')
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  itemCount: entradas.length,
                  separatorBuilder: (_, __) => Divider(color: t.border),
                  itemBuilder: (_, i) {
                    final e = entradas[i];
                    final quien = e.changedByRole == 'Admin' ? 'Administración' : 'Docente';
                    return Semantics(
                      container: true,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(e.courseName, style: GoogleFonts.poppins(fontSize: 13.5, fontWeight: FontWeight.w600, color: onSurface)),
                        Text(
                            'De ${_estado(e.previousStatus)} a ${_estado(e.newStatus)}'
                            '${e.newGrade != null ? ' · nota ${fmtNota(e.newGrade)}' : ''}',
                            style: GoogleFonts.poppins(fontSize: 12.5, color: onSurface)),
                        Text('$quien: ${e.changedByName}${e.changedAt != null ? ' · ${fmt.format(e.changedAt!)}' : ''}',
                            style: GoogleFonts.poppins(fontSize: 11.5, color: t.muted)),
                        if (e.reason != null && e.reason!.isNotEmpty)
                          Text('Motivo: ${e.reason}', style: GoogleFonts.poppins(fontSize: 11.5, color: t.muted)),
                      ]),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}
