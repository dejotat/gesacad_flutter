import '../../config/app_tokens.dart';
import '../../widgets/ui/ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../utils/activity_type.dart';
import '../../utils/grade_style.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../helpers/file_viewer_helper.dart';
import '../../services/api_service.dart';
import '../../services/connectivity_service.dart';
import '../../services/offline_queue.dart';

/// Pantalla de calificación de entregas de estudiantes (CU-06 / RF09).
///
/// El profesor ve todas las entregas de una actividad, puede abrir el archivo
/// entregado por cada estudiante y asignar o editar su nota (escala 0.0–5.0).
///
/// Validaciones de nota (RF09 — escala colombiana):
/// | ID    | Entrada                   | Resultado                              |
/// |-------|---------------------------|----------------------------------------|
/// | CG-01 | Campo vacío               | "Ingresa una nota"                     |
/// | CG-02 | Texto no numérico         | "Formato inválido (ej: 3.50)"          |
/// | CG-03 | Nota < 0.0                | "Entre 0.00 y 5.00"                    |
/// | CG-04 | Nota > 5.0                | "Entre 0.00 y 5.00"                    |
/// | CG-05 | Más de 2 decimales        | Redondeado a 2 decimales               |
/// | CG-06 | Nota válida               | Nota guardada, snackbar verde          |
/// | CG-07 | Error de red              | Snackbar rojo                          |
class GradeStudentsScreen extends StatefulWidget {
  final int courseId;
  final String courseName;
  final int? activityId;
  final String? activityName;

  const GradeStudentsScreen({
    super.key,
    required this.courseId,
    required this.courseName,
    this.activityId,
    this.activityName,
  });

  @override
  State<GradeStudentsScreen> createState() => _GradeStudentsScreenState();
}

class _GradeStudentsScreenState extends State<GradeStudentsScreen> {
  List<Map<String, dynamic>> _resolutions = [];
  // Vista general: lista de actividades con sus estadísticas de entrega
  List<Map<String, dynamic>> _activitiesStats = [];
  bool _loading = true;

  bool get _esVistaGeneral => widget.activityId == null;

  StreamSubscription<SyncEvent>? _syncSub;

  @override
  void initState() {
    super.initState();
    _load();
    // Al sincronizarse una nota guardada sin conexión, se recarga la lista.
    _syncSub = OfflineQueue.instance.events.listen((e) {
      if (e.completed &&
          e.operation.type == OperationType.grade &&
          e.operation.activityId == widget.activityId &&
          mounted) {
        _load();
      }
    });
    OfflineQueue.instance.operations.addListener(_onQueueChanged);
  }

  void _onQueueChanged() {
    if (mounted) setState(() {}); // actualiza las marcas "pendiente de sincronizar"
  }

  @override
  void dispose() {
    _syncSub?.cancel();
    OfflineQueue.instance.operations.removeListener(_onQueueChanged);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      if (!_esVistaGeneral) {
        // ── Vista por actividad ──────────────────────────────────────────
        final raw = await ApiService().getResolutions(widget.activityId!);
        final seen   = <dynamic>{};
        final deduped = <Map<String, dynamic>>[];
        for (final r in raw) {
          final uid = r['id'] ?? r['userId'] ?? r['username'];
          if (seen.add(uid)) {
            final rol = r['rol']?.toString() ?? r['role']?.toString() ?? '';
            if (rol.isEmpty || rol == 'Student') deduped.add(r);
          }
        }
        _resolutions = deduped;
      } else {
        // ── Vista general: carga todas las actividades del curso ─────────
        final acts = await ApiService().getActivities(widget.courseId);
        final stats = <Map<String, dynamic>>[];
        for (final act in acts) {
          try {
            final resols = await ApiService().getResolutions(act.id);
            final entregados = resols.where((r) =>
                r['resolution'] != null &&
                r['resolution'].toString().isNotEmpty).length;
            final calificados =
                resols.where((r) => r['GPA'] != null).length;
            final gpas = resols
                .where((r) => r['GPA'] != null)
                .map((r) => double.tryParse(r['GPA'].toString()) ?? 0.0)
                .toList();
            final promedio = gpas.isEmpty
                ? null
                : gpas.reduce((a, b) => a + b) / gpas.length;
            stats.add({
              'activityId':  act.id,
              'name':        act.tittle,
              'type':        act.type,
              'weighting':   act.weighting,
              'total':       resols.length,
              'entregados':  entregados,
              'calificados': calificados,
              'promedio':    promedio,
            });
          } catch (_) {}
        }
        _activitiesStats = stats;
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  /// Separa una cadena de URLs múltiples (separadas por `|||`) en lista.
  List<String> _parsearUrls(String raw) {
    return raw
        .split('|||')
        .map((u) => u.trim())
        .where((u) => u.isNotEmpty)
        .toList();
  }

  /// Valida la nota y retorna el [double] o null si hay error.
  double? _validateAndParseGrade(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      _showSnack('Ingresa una nota antes de guardar', Colors.red);
      return null;
    }
    final parsed = double.tryParse(trimmed);
    if (parsed == null) {
      _showSnack('Nota inválida. Usa formato numérico: 3.5 ó 4.00', Colors.red);
      return null;
    }
    if (parsed < 0.0 || parsed > 5.0) {
      _showSnack('La nota debe estar entre 0.00 y 5.00', Colors.red);
      return null;
    }
    return double.parse(parsed.toStringAsFixed(2));
  }

  /// Retorna el color semántico de la nota según la escala colombiana.
  Color _gradeColor(double gpa) => GradeStyle.color(gpa, context.tokens);

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  /// Muestra el diálogo de calificación mejorado.
  ///
  /// Mejoras sobre la versión anterior:
  /// - Soporte de múltiples archivos entregados (separados por `|||`).
  /// - Cada archivo tiene su propio botón "Abrir".
  /// - PDF de Cloudinary se abre correctamente vía Google Docs Viewer.
  /// - Campo de retroalimentación del docente (se guarda en BD).
  /// - Indicador de nota anterior si ya fue calificado.
  void _showGradeDialog(Map<String, dynamic> res) {
    final existingGpa = res['GPA'];
    final existingStr = existingGpa != null
        ? (double.tryParse(existingGpa.toString())?.toStringAsFixed(2) ??
            existingGpa.toString())
        : '';
    final gradeCtrl = TextEditingController(text: existingStr);
    final commentCtrl = TextEditingController(
        text: res['teacherComment']?.toString() ?? '');
    final formKey = GlobalKey<FormState>();

    final String username = res['username']?.toString() ?? '';
    final String rawResolution = res['resolution']?.toString() ?? '';
    // Separar múltiples archivos entregados
    final List<String> archivos = rawResolution.isNotEmpty
        ? _parsearUrls(rawResolution)
        : [];
    final String? fechaEntrega = res['dateResolution']?.toString();
    final String comentarioEstudiante = res['comment']?.toString() ?? '';

    final primary = Theme.of(context).colorScheme.primary;
    final t = context.tokens;

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Encabezado ─────────────────────────────────────────────
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: primary.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.grading_rounded,
                          color: primary, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Calificar a $username',
                            style: GoogleFonts.poppins(
                                fontSize: 17, fontWeight: FontWeight.w600),
                          ),
                          if (existingGpa != null)
                            Text(
                              'Nota actual: $existingStr / 5.00',
                              style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  color: _gradeColor(
                                      double.tryParse(existingStr) ?? 0)),
                            ),
                        ],
                      ),
                    ),
                  ]),
                  const SizedBox(height: 20),

                  // ── Archivos entregados ────────────────────────────────────
                  if (archivos.isNotEmpty) ...[
                    Row(children: [
                      Icon(Icons.folder_open_rounded,
                          color: t.info, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        'Entrega${archivos.length > 1 ? 's' : ''} del estudiante '
                        '(${archivos.length} archivo${archivos.length > 1 ? 's' : ''}):',
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: t.info.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: t.info.withValues(alpha: 0.30)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Fecha de entrega
                          if (fechaEntrega != null) ...[
                            Row(children: [
                              Icon(Icons.schedule_rounded,
                                  color: t.muted, size: 14),
                              const SizedBox(width: 4),
                              Text(
                                'Enviado: ${fechaEntrega.split('T')[0]}',
                                style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    color: t.muted),
                              ),
                            ]),
                            const SizedBox(height: 8),
                          ],
                          // Tarjetas de archivos con ícono y tipo correcto
                          ...archivos.asMap().entries.map((e) =>
                            FileViewerHelper.buildFileCard(
                              e.value,
                              index: e.key + 1,
                              primaryColor: t.info,
                            ),
                          ),
                          // Comentario del estudiante
                          if (comentarioEstudiante.isNotEmpty) ...[
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: t.warning.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: t.warning.withValues(alpha: 0.35)),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.comment_rounded,
                                      color: t.warning, size: 16),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text('Comentario del estudiante:',
                                            style: GoogleFonts.poppins(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: t.warning)),
                                        const SizedBox(height: 2),
                                        Text(comentarioEstudiante,
                                            style: GoogleFonts.poppins(
                                                fontSize: 12,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurface)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ] else ...[
                    // Sin entrega
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: t.warning.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: t.warning.withValues(alpha: 0.35)),
                      ),
                      child: Row(children: [
                        Icon(Icons.info_outline_rounded,
                            color: t.warning, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Este estudiante no ha realizado entrega.',
                            style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: t.warning),
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ── Campo de nota ──────────────────────────────────────────
                  TextFormField(
                    controller: gradeCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'^\d*\.?\d{0,2}')),
                    ],
                    decoration: InputDecoration(
                      labelText: 'Nota (0.00 – 5.00)',
                      helperText:
                          'Máx. 2 decimales.  Mínima aprobatoria: 3.00',
                      prefixIcon: const Icon(Icons.star_rounded),
                      suffixText: '/ 5.00',
                    ),
                    validator: (v) {
                      final t = v?.trim() ?? '';
                      if (t.isEmpty) return 'Ingresa una nota';
                      final n = double.tryParse(t);
                      if (n == null) return 'Formato inválido (ej: 3.50)';
                      if (n < 0.0 || n > 5.0) return 'Entre 0.00 y 5.00';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),

                  // ── Escala visual colombiana ───────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _scaleChip('< 3.0', 'En riesgo', t.danger),
                      _scaleChip('3.0–3.9', 'Aprobando', t.warning),
                      _scaleChip('≥ 4.0', 'Sobresaliente', t.success),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ── Retroalimentación del docente ──────────────────────────
                  TextFormField(
                    controller: commentCtrl,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: 'Retroalimentación para el estudiante',
                      hintText: 'Opcional: escribe comentarios sobre la entrega...',
                      prefixIcon: const Icon(Icons.rate_review_rounded),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Acciones ───────────────────────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text('Cancelar', style: GoogleFonts.poppins()),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.save_rounded, size: 18),
                        label: Text('Guardar Nota',
                            style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w600)),
                        onPressed: () async {
                          if (!formKey.currentState!.validate()) return;
                          final grade = _validateAndParseGrade(gradeCtrl.text);
                          if (grade == null) return;
                          Navigator.pop(ctx);
                          await _guardarNota(
                              res, grade, commentCtrl.text, username);
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Guarda la nota en el servidor; sin conexión la deja en la cola y la
  /// refleja de inmediato en pantalla (se sincroniza sola al reconectar).
  Future<void> _guardarNota(Map<String, dynamic> res, double grade,
      String comentario, String username) async {
    Future<void> encolar() async {
      await OfflineQueue.instance.enqueueGrade(
        studentId: res['id'] as int,
        activityId: widget.activityId!,
        gpa: grade,
        teacherComment: comentario,
        label: 'Nota ${grade.toStringAsFixed(2)} · $username',
      );
      if (!mounted) return;
      setState(() {
        res['GPA'] = grade; // vista optimista hasta confirmar con el servidor
        res['teacherComment'] = comentario;
      });
      _showSnack(
          'Sin conexión: la nota de $username quedó guardada y se enviará '
          'automáticamente.',
          context.tokens.warning);
    }

    if (!ConnectivityService.instance.online.value) {
      await encolar();
      return;
    }
    try {
      final code = await ApiService().gradeActivity(
        res['id'] as int,
        widget.activityId!,
        grade,
        teacherComment: comentario,
      );
      if (code < 200 || code >= 300) {
        if (mounted) {
          _showSnack('El servidor rechazó la nota (código $code).',
              context.tokens.danger);
        }
        return;
      }
      await _load();
      if (mounted) {
        _showSnack(
          'Nota ${grade.toStringAsFixed(2)} asignada a $username '
          '(${grade >= 3.0 ? 'Aprobado' : 'En riesgo'})',
          _gradeColor(grade),
        );
      }
    } catch (e) {
      if (isNetworkError(e)) {
        await encolar();
      } else if (mounted) {
        _showSnack('Error al guardar la nota. Intenta de nuevo.',
            context.tokens.danger);
      }
    }
  }

  /// Chip de referencia de la escala de calificación colombiana.
  Widget _scaleChip(String range, String label, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Text(range,
              style: GoogleFonts.poppins(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ),
        const SizedBox(height: 3),
        Text(label,
            style: GoogleFonts.poppins(
                fontSize: 12, color: context.tokens.muted)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _esVistaGeneral
                  ? 'Calificaciones generales'
                  : (widget.activityName ?? 'Calificaciones'),
              style: GoogleFonts.poppins(
                  color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
            ),
            Text(widget.courseName,
                style: GoogleFonts.poppins(color: Colors.white70, fontSize: 12)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Actualizar',
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? Semantics(
              label: 'Cargando calificaciones',
              child: ExcludeSemantics(
                child: ListView(
                  padding: const EdgeInsets.all(AppTokens.pagePadding),
                  children: const [
                    SkeletonBox(height: 70), SizedBox(height: 10),
                    SkeletonBox(height: 90), SizedBox(height: 10),
                    SkeletonBox(height: 90),
                  ],
                ),
              ),
            )
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: _esVistaGeneral
                    ? _buildGeneralView(primary)
                    : _buildActivityView(primary),
              ),
            ),
    );
  }

  // ── Vista por actividad específica ───────────────────────────────────────

  Widget _buildActivityView(Color primary) {
    final total      = _resolutions.length;
    final entregados = _resolutions.where((r) => r['resolution']?.toString().isNotEmpty == true).length;
    final calificados = _resolutions.where((r) => r['GPA'] != null).length;

    if (_resolutions.isEmpty) return _buildEmpty();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(
            AppTokens.pagePadding, AppTokens.pagePadding, AppTokens.pagePadding, 4),
        child: _buildSummaryBar(total, entregados, calificados, primary),
      ),
      Expanded(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: _resolutions.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) => _buildStudentCard(_resolutions[i]),
          ),
        ),
      ),
    ]);
  }

  // ── Vista general: todas las actividades del curso ────────────────────────

  Widget _buildGeneralView(Color primary) {
    if (_activitiesStats.isEmpty) {
      return const EmptyState(
        icon: PhosphorIconsRegular.chartBar,
        message: 'Sin actividades en este curso.\n'
            'Crea actividades para ver las calificaciones aquí.',
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        itemCount: _activitiesStats.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) => _buildActivityStatCard(_activitiesStats[i], primary),
      ),
    );
  }

  Widget _buildActivityStatCard(Map<String, dynamic> stat, Color primary) {
    final t = context.tokens;
    final name       = stat['name'] as String;
    final type       = stat['type'] as String;
    final weighting  = (stat['weighting'] as double) * 100;
    final total      = stat['total'] as int;
    final entregados = stat['entregados'] as int;
    final calificados = stat['calificados'] as int;
    final promedio   = stat['promedio'] as double?;
    final actId      = stat['activityId'] as int;

    final info = ActivityTypeInfo.of(type);
    final typeColor = ActivityTypeInfo.colorOf(type, t);
    final double progress = total > 0 ? entregados / total : 0.0;

    return Semantics(
      button: true,
      label: '$name, ${info.label}, ponderado ${weighting.toStringAsFixed(0)} por ciento. '
          '$entregados de $total entregaron, $calificados calificados'
          '${promedio != null ? ', promedio ${promedio.toStringAsFixed(2)}' : ''}.',
      child: ExcludeSemantics(
        child: AppCard(
          blur: false,
          onTap: () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => GradeStudentsScreen(
              courseId: widget.courseId,
              courseName: widget.courseName,
              activityId: actId,
              activityName: name,
            ),
          )).then((_) => _load()),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: typeColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppTokens.radiusControl),
                ),
                child: Icon(info.icon, color: typeColor, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name,
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                Text('${info.label} · ${weighting.toStringAsFixed(0)}%',
                    style: GoogleFonts.poppins(fontSize: 12, color: t.muted)),
              ])),
              if (promedio != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _gradeColor(promedio).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(AppTokens.radiusControl),
                  ),
                  child: Column(children: [
                    Text(promedio.toStringAsFixed(2),
                        style: GoogleFonts.poppins(
                            fontSize: 16, fontWeight: FontWeight.w700,
                            color: _gradeColor(promedio))),
                    Text('promedio',
                        style: GoogleFonts.poppins(fontSize: 12, color: t.muted)),
                  ]),
                ),
            ]),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: t.border,
                color: entregados == total && total > 0 ? t.success : primary,
              ),
            ),
            const SizedBox(height: 10),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              _miniStat('$total', 'Total', t.muted),
              _miniStat('$entregados', 'Entregaron', t.success),
              _miniStat('$calificados', 'Calificados', t.info),
              _miniStat('${total - entregados}', 'Sin entrega', t.warning),
            ]),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('Ver entregas',
                    style: GoogleFonts.poppins(
                        fontSize: 13, color: primary, fontWeight: FontWeight.w600)),
                const SizedBox(width: 4),
                Icon(PhosphorIconsRegular.arrowRight, size: 14, color: primary),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _miniStat(String value, String label, Color color) {
    return Column(children: [
      Text(value,
          style: GoogleFonts.poppins(
              fontSize: 16, fontWeight: FontWeight.w700, color: color)),
      Text(label,
          style: GoogleFonts.poppins(fontSize: 12, color: context.tokens.muted)),
    ]);
  }

  /// Barra superior con contadores de total, entregados y calificados.
  Widget _buildSummaryBar(
      int total, int entregados, int calificados, Color primary) {
    final t = context.tokens;
    return Semantics(
      label: '$total estudiantes, $entregados entregaron, '
          '$calificados calificados, ${total - entregados} sin entrega.',
      child: ExcludeSemantics(
        child: AppCard(
          blur: false,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _summaryItem(total.toString(), 'Total',
                  PhosphorIconsRegular.users, primary),
              _divider(),
              _summaryItem(entregados.toString(), 'Entregaron',
                  PhosphorIconsRegular.uploadSimple, t.success),
              _divider(),
              _summaryItem(calificados.toString(), 'Calificados',
                  PhosphorIconsRegular.checkCircle, t.info),
              _divider(),
              _summaryItem('${total - entregados}', 'Sin entrega',
                  PhosphorIconsRegular.hourglass, t.warning),
            ],
          ),
        ),
      ),
    );
  }

  Widget _summaryItem(
      String value, String label, IconData icon, Color color) {
    return Column(children: [
      Icon(icon, color: color, size: 22),
      const SizedBox(height: 4),
      Text(value,
          style: GoogleFonts.poppins(
              fontWeight: FontWeight.w700, fontSize: 18, color: color)),
      Text(label,
          style: GoogleFonts.poppins(fontSize: 12, color: context.tokens.muted)),
    ]);
  }

  Widget _divider() =>
      Container(width: 1, height: 40, color: context.tokens.border);

  /// Tarjeta de estudiante con estado de entrega y nota.
  Widget _buildStudentCard(Map<String, dynamic> r) {
    final t = context.tokens;
    final hasDelivery =
        r['resolution'] != null && r['resolution'].toString().isNotEmpty;
    final gpaParsed = r['GPA'] != null
        ? double.tryParse(r['GPA'].toString())
        : null;
    final String username = r['username']?.toString() ?? '—';
    final String? fechaEntrega = r['dateResolution']?.toString();

    // Color del avatar según estado
    final Color avatarColor;
    final IconData avatarIcon;
    if (gpaParsed != null) {
      avatarColor = _gradeColor(gpaParsed);
      avatarIcon = PhosphorIconsFill.checkCircle;
    } else if (hasDelivery) {
      avatarColor = t.info;
      avatarIcon = PhosphorIconsRegular.paperPlaneTilt;
    } else {
      avatarColor = t.muted;
      avatarIcon = PhosphorIconsRegular.hourglass;
    }

    return Semantics(
      label: 'Estudiante $username, '
          '${hasDelivery ? 'entrega realizada' : 'sin entrega'}, '
          'nota: ${gpaParsed != null ? gpaParsed.toStringAsFixed(2) : 'sin calificar'}',
      child: AppCard(
        blur: false,
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            ExcludeSemantics(
              child: Container(
                width: 46, height: 46,
                decoration: BoxDecoration(
                  color: avatarColor.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(avatarIcon, color: avatarColor, size: 24),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(username,
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(
                    hasDelivery ? 'Entrega realizada' : 'Sin entrega',
                    style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: hasDelivery ? t.success : t.warning,
                        fontWeight: FontWeight.w500),
                  ),
                  if (hasDelivery && fechaEntrega != null)
                    Text('Enviado: ${fechaEntrega.split('T')[0]}',
                        style: GoogleFonts.poppins(fontSize: 12, color: t.muted)),
                  if (gpaParsed != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '${gpaParsed.toStringAsFixed(2)} / 5.00 · '
                        '${GradeStyle.label(gpaParsed)}',
                        style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _gradeColor(gpaParsed)),
                      ),
                    ),
                  if (r['id'] is int &&
                      OfflineQueue.instance.hasPendingGrade(
                          r['id'] as int, widget.activityId ?? 0))
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        MotionIcon(Icons.cloud_upload_rounded,
                            size: 14, color: t.warning, motion: IconMotion.float),
                        const SizedBox(width: 4),
                        Text('Pendiente de sincronizar',
                            style: GoogleFonts.poppins(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: t.warning)),
                      ]),
                    ),
                ],
              ),
            ),
            // Botón de calificar / editar nota
            gpaParsed != null
                ? OutlinedButton(
                    style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8)),
                    onPressed: () => _showGradeDialog(r),
                    child: Text('Editar',
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600, fontSize: 13)),
                  )
                : ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8)),
                    onPressed: () => _showGradeDialog(r),
                    child: Text('Calificar',
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600, fontSize: 13)),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() => const EmptyState(
        icon: PhosphorIconsRegular.tray,
        message: 'Sin entregas aún.\n'
            'Los estudiantes no han enviado archivos para esta actividad.',
      );
}
