import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../helpers/file_viewer_helper.dart';
import '../../services/api_service.dart';

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

  @override
  void initState() {
    super.initState();
    _load();
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
  Color _gradeColor(double gpa) {
    if (gpa >= 4.0) return const Color(0xFF2E7D32);
    if (gpa >= 3.0) return const Color(0xFFE65100);
    return const Color(0xFFC62828);
  }

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

    const primary = Color(0xFF1A237E);

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
                        color: primary.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.grading_rounded,
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
                                fontSize: 17, fontWeight: FontWeight.w700),
                          ),
                          if (existingGpa != null)
                            Text(
                              'Nota actual: $existingStr / 5.00',
                              style: GoogleFonts.poppins(
                                  fontSize: 11,
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
                          color: Colors.blue.shade700, size: 16),
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
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Fecha de entrega
                          if (fechaEntrega != null) ...[
                            Row(children: [
                              Icon(Icons.schedule_rounded,
                                  color: Colors.grey.shade500, size: 14),
                              const SizedBox(width: 4),
                              Text(
                                'Enviado: ${fechaEntrega.split('T')[0]}',
                                style: GoogleFonts.poppins(
                                    fontSize: 11,
                                    color: Colors.grey.shade600),
                              ),
                            ]),
                            const SizedBox(height: 8),
                          ],
                          // Tarjetas de archivos con ícono y tipo correcto
                          ...archivos.asMap().entries.map((e) =>
                            FileViewerHelper.buildFileCard(
                              e.value,
                              index: e.key + 1,
                              primaryColor: Colors.blue.shade700,
                            ),
                          ),
                          // Comentario del estudiante
                          if (comentarioEstudiante.isNotEmpty) ...[
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border:
                                    Border.all(color: Colors.amber.shade300),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.comment_rounded,
                                      color: Colors.amber.shade800, size: 16),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text('Comentario del estudiante:',
                                            style: GoogleFonts.poppins(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w700,
                                                color:
                                                    Colors.amber.shade900)),
                                        const SizedBox(height: 2),
                                        Text(comentarioEstudiante,
                                            style: GoogleFonts.poppins(
                                                fontSize: 12,
                                                color:
                                                    Colors.grey.shade800)),
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
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Row(children: [
                        Icon(Icons.info_outline_rounded,
                            color: Colors.orange.shade700, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Este estudiante no ha realizado entrega.',
                            style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: Colors.orange.shade800),
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
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                      prefixIcon: const Icon(Icons.star_rounded),
                      suffixText: '/ 5.00',
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide:
                            const BorderSide(color: primary, width: 2),
                      ),
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
                      _scaleChip('< 3.0', 'Reprobado',
                          const Color(0xFFC62828)),
                      _scaleChip('3.0–3.9', 'Aprobado',
                          const Color(0xFFE65100)),
                      _scaleChip('≥ 4.0', 'Excelente',
                          const Color(0xFF2E7D32)),
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
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                      prefixIcon: const Icon(Icons.rate_review_rounded),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide:
                            const BorderSide(color: primary, width: 2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Acciones ───────────────────────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text('Cancelar',
                            style: GoogleFonts.poppins(
                                color: Colors.grey.shade600)),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 12),
                        ),
                        icon: const Icon(Icons.save_rounded, size: 18),
                        label: Text('Guardar Nota',
                            style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w600)),
                        onPressed: () async {
                          if (!formKey.currentState!.validate()) return;
                          final grade = _validateAndParseGrade(gradeCtrl.text);
                          if (grade == null) return;
                          Navigator.pop(ctx);
                          try {
                            await ApiService().gradeActivity(
                              res['id'] as int,
                              widget.activityId!,
                              grade,
                              teacherComment: commentCtrl.text,
                            );
                            await _load();
                            if (mounted) {
                              _showSnack(
                                'Nota ${grade.toStringAsFixed(2)} asignada a $username '
                                '(${grade >= 3.0 ? 'Aprobado' : 'Reprobado'})',
                                _gradeColor(grade),
                              );
                            }
                          } catch (_) {
                            if (mounted) {
                              _showSnack(
                                  'Error al guardar la nota. Verifica la conexión.',
                                  Colors.red);
                            }
                          }
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

  /// Chip de referencia de la escala de calificación colombiana.
  Widget _scaleChip(String range, String label, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.4)),
          ),
          child: Text(range,
              style: GoogleFonts.poppins(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 3),
        Text(label,
            style: GoogleFonts.poppins(
                fontSize: 9, color: Colors.grey.shade600)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF1A237E);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1A237E), Color(0xFF3949AB)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
        ),
        backgroundColor: Colors.transparent,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _esVistaGeneral
                  ? 'Calificaciones generales'
                  : (widget.activityName ?? 'Calificaciones'),
              style: GoogleFonts.poppins(
                  color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
            ),
            Text(widget.courseName,
                style: GoogleFonts.poppins(color: Colors.white70, fontSize: 11)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            tooltip: 'Actualizar',
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _esVistaGeneral
              ? _buildGeneralView(primary)
              : _buildActivityView(primary),
    );
  }

  // ── Vista por actividad específica ───────────────────────────────────────

  Widget _buildActivityView(Color primary) {
    final total      = _resolutions.length;
    final entregados = _resolutions.where((r) => r['resolution']?.toString().isNotEmpty == true).length;
    final calificados = _resolutions.where((r) => r['GPA'] != null).length;

    if (_resolutions.isEmpty) return _buildEmpty();
    return Column(children: [
      _buildSummaryBar(total, entregados, calificados, primary),
      Expanded(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: _resolutions.length,
            itemBuilder: (_, i) => _buildStudentCard(_resolutions[i]),
          ),
        ),
      ),
    ]);
  }

  // ── Vista general: todas las actividades del curso ────────────────────────

  Widget _buildGeneralView(Color primary) {
    if (_activitiesStats.isEmpty) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.bar_chart_rounded, size: 64, color: Colors.grey.shade300),
        const SizedBox(height: 14),
        Text('Sin actividades en este curso',
            style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600,
                color: Colors.grey.shade500)),
        const SizedBox(height: 8),
        Text('Crea actividades para ver las calificaciones aquí.',
            style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade400),
            textAlign: TextAlign.center),
      ]));
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        itemCount: _activitiesStats.length,
        itemBuilder: (_, i) => _buildActivityStatCard(_activitiesStats[i], primary),
      ),
    );
  }

  Widget _buildActivityStatCard(Map<String, dynamic> stat, Color primary) {
    final name       = stat['name'] as String;
    final type       = stat['type'] as String;
    final weighting  = (stat['weighting'] as double) * 100;
    final total      = stat['total'] as int;
    final entregados = stat['entregados'] as int;
    final calificados = stat['calificados'] as int;
    final promedio   = stat['promedio'] as double?;
    final actId      = stat['activityId'] as int;

    final String typeLabel;
    final Color typeColor;
    switch (type) {
      case 'midterm':  typeLabel = 'Parcial';   typeColor = Colors.orange; break;
      case 'project':  typeLabel = 'Proyecto';  typeColor = Colors.blue;   break;
      case 'resource': typeLabel = 'Recurso';   typeColor = Colors.green;  break;
      default:         typeLabel = 'Otro';       typeColor = Colors.purple;
    }

    final double progress = total > 0 ? entregados / total : 0.0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => GradeStudentsScreen(
            courseId: widget.courseId,
            courseName: widget.courseName,
            activityId: actId,
            activityName: name,
          ),
        )).then((_) => _load()),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Encabezado
            Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: typeColor.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.assignment_rounded, color: typeColor, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 14),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                Row(children: [
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                    decoration: BoxDecoration(
                      color: typeColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(typeLabel,
                        style: GoogleFonts.poppins(fontSize: 10, color: typeColor, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 6),
                  Text('${weighting.toStringAsFixed(0)}%',
                      style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade500)),
                ]),
              ])),
              // Promedio
              if (promedio != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _gradeColor(promedio).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _gradeColor(promedio).withOpacity(0.3)),
                  ),
                  child: Column(children: [
                    Text(promedio.toStringAsFixed(2),
                        style: GoogleFonts.poppins(
                            fontSize: 16, fontWeight: FontWeight.w800, color: _gradeColor(promedio))),
                    Text('prom.', style: GoogleFonts.poppins(fontSize: 9, color: Colors.grey.shade500)),
                  ]),
                ),
            ]),
            const SizedBox(height: 12),

            // Barra de progreso de entregas
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: Colors.grey.shade200,
                color: entregados == total && total > 0 ? Colors.green : primary,
              ),
            ),
            const SizedBox(height: 8),

            // Contadores
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              _miniStat('$total', 'Total', Colors.grey.shade600),
              _miniStat('$entregados', 'Entregaron', Colors.green.shade700),
              _miniStat('$calificados', 'Calificados', Colors.indigo),
              _miniStat('${total - entregados}', 'Sin entrega', Colors.orange.shade700),
            ]),
            const SizedBox(height: 8),

            // Botón ver detalle
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              Text('Ver entregas →',
                  style: GoogleFonts.poppins(
                      fontSize: 12, color: primary, fontWeight: FontWeight.w600)),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _miniStat(String value, String label, Color color) {
    return Column(children: [
      Text(value, style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w800, color: color)),
      Text(label, style: GoogleFonts.poppins(fontSize: 9, color: Colors.grey.shade500)),
    ]);
  }

  /// Barra superior con contadores de total, entregados y calificados.
  Widget _buildSummaryBar(
      int total, int entregados, int calificados, Color primary) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _summaryItem(
              total.toString(), 'Total', Icons.people_rounded, primary),
          _divider(),
          _summaryItem(entregados.toString(), 'Entregaron',
              Icons.upload_file_rounded, Colors.green.shade700),
          _divider(),
          _summaryItem(calificados.toString(), 'Calificados',
              Icons.grading_rounded, Colors.indigo),
          _divider(),
          _summaryItem(
            '${total - entregados}',
            'Sin entrega',
            Icons.pending_rounded,
            Colors.orange.shade700,
          ),
        ],
      ),
    );
  }

  Widget _summaryItem(
      String value, String label, IconData icon, Color color) {
    return Column(children: [
      Icon(icon, color: color, size: 20),
      const SizedBox(height: 4),
      Text(value,
          style: GoogleFonts.poppins(
              fontWeight: FontWeight.w800,
              fontSize: 18,
              color: color)),
      Text(label,
          style: GoogleFonts.poppins(
              fontSize: 10, color: Colors.grey.shade600)),
    ]);
  }

  Widget _divider() => Container(
      width: 1, height: 40, color: Colors.grey.shade200);

  /// Tarjeta de estudiante con estado de entrega y nota.
  Widget _buildStudentCard(Map<String, dynamic> r) {
    final hasDelivery =
        r['resolution'] != null && r['resolution'].toString().isNotEmpty;
    final gpaParsed = r['GPA'] != null
        ? double.tryParse(r['GPA'].toString())
        : null;
    final String username = r['username']?.toString() ?? '—';
    final String? fechaEntrega = r['dateResolution']?.toString();

    // Color del avatar según estado
    Color avatarColor;
    IconData avatarIcon;
    if (gpaParsed != null) {
      avatarColor = _gradeColor(gpaParsed);
      avatarIcon = Icons.check_circle_rounded;
    } else if (hasDelivery) {
      avatarColor = Colors.green;
      avatarIcon = Icons.check_circle_outline_rounded;
    } else {
      avatarColor = Colors.grey.shade400;
      avatarIcon = Icons.radio_button_unchecked_rounded;
    }

    return Semantics(
      label: 'Estudiante $username, '
          '${hasDelivery ? 'entrega realizada' : 'sin entrega'}, '
          'nota: ${gpaParsed != null ? gpaParsed.toStringAsFixed(2) : 'sin calificar'}',
      child: Card(
        margin: const EdgeInsets.only(bottom: 10),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Ícono de estado
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: avatarColor.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(avatarIcon, color: avatarColor, size: 24),
              ),
              const SizedBox(width: 14),

              // Información del estudiante
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(username,
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w700,
                            fontSize: 15)),
                    const SizedBox(height: 4),

                    // Estado de entrega
                    _estadoChip(
                      hasDelivery
                          ? '✅ Entrega realizada'
                          : '⏳ Sin entrega',
                      hasDelivery
                          ? Colors.green.shade700
                          : Colors.orange.shade700,
                    ),

                    // Fecha de entrega
                    if (hasDelivery && fechaEntrega != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Enviado: ${fechaEntrega.split('T')[0]}',
                          style: GoogleFonts.poppins(
                              fontSize: 11,
                              color: Colors.grey.shade500),
                        ),
                      ),

                    // Nota asignada
                    if (gpaParsed != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(children: [
                          Icon(Icons.star_rounded,
                              color: _gradeColor(gpaParsed),
                              size: 14),
                          const SizedBox(width: 4),
                          Text(
                            '${gpaParsed.toStringAsFixed(2)} / 5.00  •  '
                            '${gpaParsed >= 4.0 ? 'Excelente' : gpaParsed >= 3.0 ? 'Aprobado' : 'Reprobado'}',
                            style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _gradeColor(gpaParsed)),
                          ),
                        ]),
                      ),
                  ],
                ),
              ),

              // Botón de calificar / editar nota
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: gpaParsed != null
                      ? Colors.grey.shade100
                      : const Color(0xFF1A237E),
                  foregroundColor: gpaParsed != null
                      ? const Color(0xFF1A237E)
                      : Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  elevation: gpaParsed != null ? 0 : 2,
                ),
                onPressed: () => _showGradeDialog(r),
                child: Text(
                  gpaParsed != null ? 'Editar' : 'Calificar',
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _estadoChip(String text, Color color) {
    return Text(
      text,
      style: GoogleFonts.poppins(
          fontSize: 12,
          color: color,
          fontWeight: FontWeight.w500),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.inbox_outlined,
              size: 64, color: Colors.grey.shade400),
        ),
        const SizedBox(height: 18),
        Text(
          'Sin entregas aún',
          style: GoogleFonts.poppins(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade600),
        ),
        const SizedBox(height: 6),
        Text(
          'Los estudiantes no han enviado archivos para esta actividad.',
          style: GoogleFonts.poppins(
              fontSize: 13, color: Colors.grey.shade400),
          textAlign: TextAlign.center,
        ),
      ]),
    );
  }
}
