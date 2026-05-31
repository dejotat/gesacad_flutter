import 'package:gesacad/utils/platform_utils.dart';
import 'dart:developer' as developer;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import '../../config/api_config.dart';
import '../../models/activity_model.dart';
import '../../services/api_service.dart';
import '../../widgets/animated_logo.dart';
import '../../helpers/file_viewer_helper.dart';

/// Pantalla de detalle de actividad para el estudiante — estilo Google Classroom.
///
/// Flujo de entrega en 2 pasos:
/// 1. [Agregar entrega] → selecciona archivo(s); se muestran en vista previa.
/// 2. [Enviar entrega] → sube cada archivo al backend; pantalla NO se cierra.
///
/// También soporta "+ Agregar otro archivo" para entregas con múltiples archivos.
///
/// Al abrir, re-consulta el estado actual de la entrega para reflejar
/// si la actividad ya fue enviada en una sesión anterior (evita que muestre
/// "Sin enviar" cuando el backend ya tiene la entrega registrada).
class ActivityDetailScreen extends StatefulWidget {
  final ActivityModel activity;
  final int userId;

  const ActivityDetailScreen({
    super.key,
    required this.activity,
    required this.userId,
  });

  @override
  State<ActivityDetailScreen> createState() => _ActivityDetailScreenState();
}

class _ActivityDetailScreenState extends State<ActivityDetailScreen> {
  // ── Estado del servidor (re-fetch al abrir) ────────────────────────────────
  ActivityModel? _serverActivity;

  /// Actividad actual: prefiere el dato fresco del servidor.
  ActivityModel get _act => _serverActivity ?? widget.activity;

  bool _refreshing = true;

  // ── Estado de subida ───────────────────────────────────────────────────────
  bool _uploading = false;
  bool _uploadSuccess = false;
  bool _clearingSubmission = false; // CU-05 FA-04: true mientras se limpia una entrega anterior
  int _uploadedCount = 0;

  // ── Archivos pendientes (seleccionados, aún NO enviados) ──────────────────
  final List<PlatformFile> _pendingFiles = [];
  final List<Uint8List> _pendingBytes = [];

  // ── Comentario opcional ───────────────────────────────────────────────────
  final TextEditingController _commentCtrl = TextEditingController();

  static const List<String> _allowedExtensions = [
    'pdf', 'doc', 'docx', 'png', 'jpg', 'jpeg', 'zip', 'xlsx', 'pptx',
  ];
  static const int _maxFileSizeBytes = 5 * 1024 * 1024; // 5 MB

  @override
  void initState() {
    super.initState();
    // Re-consultar estado actual: evita "Sin enviar" cuando ya hay entrega
    // en el servidor pero el padre pasó un modelo desactualizado.
    _refreshActivityState();
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  // ── Re-fetch del estado de la actividad ────────────────────────────────────

  Future<void> _refreshActivityState() async {
    setState(() => _refreshing = true);
    try {
      final latest = await ApiService()
          .getActivityContent(_act.id, widget.userId, 'Student');
      if (mounted && latest != null) {
        setState(() => _serverActivity = latest);
      }
    } catch (_) {}
    if (mounted) setState(() => _refreshing = false);
  }

  // ── Proxy de archivos Cloudinary ──────────────────────────────────────────

  /// Proxy delegado al FileViewerHelper centralizado.
  String _cloudinaryProxy(String url, {bool download = false}) =>
      FileViewerHelper.proxyUrl(url, download: download);

  // ── Abrir / descargar archivos ─────────────────────────────────────────────

  /// Abre el archivo en una nueva pestaña del navegador.
  ///
  /// - Cloudinary (PDF/imagen): enruta por el proxy Railway para evitar CORS.
  /// - Office (.doc, .pptx, .xlsx): pasa el proxy por Google Docs Viewer.
  /// - Otros: abre directamente.
  void _abrirArchivo(String url) => FileViewerHelper.abrirArchivo(url);

  void _descargarArchivo(String url) => FileViewerHelper.descargarArchivo(url);

  // ── Paso 1: Agregar archivo(s) ─────────────────────────────────────────────

  Future<void> _pickFile() async {
    if (_act.isPastDue) {
      _showSnack('El plazo de entrega ha vencido', Colors.red);
      return;
    }
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _allowedExtensions,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final Uint8List? bytes = file.bytes;
    if (bytes == null) {
      _showSnack('No se pudo leer el archivo seleccionado', Colors.red);
      return;
    }
    if (file.size > _maxFileSizeBytes) {
      final mb = (file.size / 1024 / 1024).toStringAsFixed(1);
      _showSnack('El archivo ($mb MB) supera el límite de 5 MB', Colors.red);
      return;
    }
    // Verificar si ya existe el mismo archivo en la lista pendiente.
    final yaExiste = _pendingFiles.any((f) => f.name == file.name);
    if (yaExiste) {
      _showSnack('Ya agregaste ese archivo', Colors.orange);
      return;
    }
    setState(() {
      _pendingFiles.add(file);
      _pendingBytes.add(bytes);
    });
  }

  void _removePendingFile(int index) {
    setState(() {
      _pendingFiles.removeAt(index);
      _pendingBytes.removeAt(index);
    });
  }

  // ── Paso 2: Enviar todos los archivos ─────────────────────────────────────

  Future<void> _enviarEntrega() async {
    if (_pendingFiles.isEmpty) {
      _showSnack('Selecciona al menos un archivo antes de enviar', Colors.orange);
      return;
    }
    setState(() { _uploading = true; _uploadedCount = 0; });

    developer.log(
      '[ActivityDetailScreen] Enviando entrega: '
      'actividadId=${_act.id} userId=${widget.userId} '
      'archivos=${_pendingFiles.map((f) => f.name).join(", ")}',
      name: 'GESACAD.Upload',
    );

    int exitosos = 0;
    final comment = _commentCtrl.text.trim();

    for (int i = 0; i < _pendingFiles.length; i++) {
      try {
        final statusCode = await ApiService().addResourceBytes(
          _act.id,
          widget.userId,
          _pendingBytes[i],
          _pendingFiles[i].name,
          comment: (i == 0) ? comment : '', // comentario solo en el primer archivo
        );
        developer.log(
          '[ActivityDetailScreen] Archivo ${_pendingFiles[i].name} → '
          'statusCode=$statusCode',
          name: 'GESACAD.Upload',
        );
        if (statusCode == 200) {
          exitosos++;
          if (mounted) setState(() => _uploadedCount = exitosos);
        }
      } catch (e) {
        developer.log(
          '[ActivityDetailScreen] Error en archivo ${_pendingFiles[i].name}: $e',
          name: 'GESACAD.Upload',
          error: e,
        );
      }
    }

    if (!mounted) return;

    if (exitosos > 0) {
      setState(() {
        _uploading = false;
        _uploadSuccess = true;
      });
      final txt = exitosos == _pendingFiles.length
          ? '¡${exitosos == 1 ? "Archivo enviado" : "$exitosos archivos enviados"} exitosamente! 🎉'
          : '$exitosos de ${_pendingFiles.length} archivos enviados. Verifica tu conexión.';
      _showSnack(txt,
          exitosos == _pendingFiles.length ? const Color(0xFF2E7D32) : Colors.orange);
      // Actualizar el estado desde el servidor.
      _refreshActivityState();
    } else {
      setState(() => _uploading = false);
      _showSnack('Error al enviar. Verifica tu conexión e intenta de nuevo.', Colors.red);
    }
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg,
            style: GoogleFonts.poppins(color: Colors.white, fontSize: 13)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final a = _act;
    const primary = Color(0xFF1A237E);

    // Determinar estado compuesto: entregado si servidor dice sí, o si acabamos
    // de enviar exitosamente en esta sesión.
    final yaEntrego = a.isDelivered || _uploadSuccess;
    final puedeEntregar = !a.isPastDue && !yaEntrego;

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
        title: Semantics(
          label: 'Detalle de actividad: ${a.tittle}',
          child: Text(a.tittle,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15)),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (!_refreshing)
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: Colors.white),
              tooltip: 'Actualizar estado',
              onPressed: _refreshActivityState,
            ),
        ],
      ),
      body: Stack(
        children: [
          _refreshing
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Encabezado ─────────────────────────────────────────
                      _buildHeader(a, primary),
                      const SizedBox(height: 16),

                      // ── Descripción ────────────────────────────────────────
                      _buildCard(
                        title: 'Descripción',
                        icon: Icons.description_rounded,
                        iconColor: Colors.blue.shade700,
                        child: Text(
                          a.description.isEmpty
                              ? 'Sin descripción adicional.'
                              : a.description,
                          style: GoogleFonts.poppins(fontSize: 13, height: 1.6),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // ── Tabla estado Moodle ────────────────────────────────
                      _buildCard(
                        title: 'Estado de la entrega',
                        icon: Icons.assignment_turned_in_rounded,
                        iconColor: Colors.teal,
                        child: _buildMoodleTable(a, yaEntrego),
                      ),
                      const SizedBox(height: 12),

                      // ── Panel "Tu trabajo" estilo Google Classroom ─────────
                      _buildCard(
                        title: 'Tu trabajo',
                        icon: Icons.work_rounded,
                        iconColor: primary,
                        titleTrailing: _buildEstadoBadge(a, yaEntrego),
                        child: _buildWorkPanel(a, yaEntrego, puedeEntregar, primary),
                      ),
                      const SizedBox(height: 80),
                    ],
                  ),
                ),
          // Nota: marca de agua eliminada — los elementos blancos del
          // AnimatedLogo son invisibles sobre fondo claro. IEEE 830 §3.3.2.
        ],
      ),
    );
  }

  // ── Panel "Tu trabajo" ─────────────────────────────────────────────────────

  Widget _buildWorkPanel(
      ActivityModel a, bool yaEntrego, bool puedeEntregar, Color primary) {
    // ── Mientras se está subiendo ─────────────────────────────────────────
    if (_uploading) {
      return _buildUploadingIndicator();
    }

    // ── Éxito reciente (archivos enviados en esta sesión) ─────────────────
    if (_uploadSuccess) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSuccessCard(),
          const SizedBox(height: 12),
          if (a.resolution != null) ...[
            _buildDeliveredFiles(a, primary),
            const SizedBox(height: 8),
          ],
          // Panel de retroalimentación del docente (si ya fue calificado)
          _buildFeedbackPanel(a, primary),
          // Si aún está en plazo y sin calificar, mostrar opciones para anular
          if (!a.isPastDue && a.gpa == null) ...[
            const SizedBox(height: 8),
            Semantics(
              label: 'Botón anular entrega recién enviada',
              button: true,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                    foregroundColor: Colors.red.shade600),
                icon: const Icon(Icons.undo_rounded, size: 16),
                label: Text('Anular entrega',
                    style: GoogleFonts.poppins(fontSize: 12)),
                onPressed: () => _confirmarAnularEntrega(primary),
              ),
            ),
          ],
        ],
      );
    }

    // ── Archivo(s) ya entregados previamente (desde servidor) ────────────
    if (yaEntrego) {
      // CU-05 FA-04: mostrar indicador de carga mientras se limpia la entrega
      if (_clearingSubmission) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.orange.shade200),
          ),
          child: Row(children: [
            const SizedBox(
              width: 22, height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5,
                  color: Color(0xFF1A237E)),
            ),
            const SizedBox(width: 14),
            Text('Procesando solicitud...',
                style: GoogleFonts.poppins(
                    fontSize: 13, color: Colors.grey.shade700)),
          ]),
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildDeliveredFiles(a, primary),
          // Panel de retroalimentación del docente (si ya fue calificado)
          _buildFeedbackPanel(a, primary),
          const SizedBox(height: 12),
          // Solo mostrar opciones de edición si: plazo vigente Y sin calificar.
          // Una vez que el docente calificó (gpa != null) la entrega queda bloqueada.
          if (!a.isPastDue && a.gpa == null) ...[
            // CU-05 FA-04: botón principal para reemplazar la entrega existente.
            Semantics(
              label: 'Botón reemplazar entrega existente',
              button: true,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  elevation: 2,
                ),
                icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                label: Text('Reemplazar entrega',
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w700, fontSize: 13)),
                onPressed: () => _confirmarReemplazarEntrega(a, primary),
              ),
            ),
            const SizedBox(height: 6),
            // Botón secundario para anular sin reemplazar
            Semantics(
              label: 'Botón anular entrega sin reemplazar',
              button: true,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: Colors.red.shade600,
                ),
                icon: const Icon(Icons.undo_rounded, size: 16),
                label: Text('Anular entrega',
                    style: GoogleFonts.poppins(fontSize: 12)),
                onPressed: () => _confirmarAnularEntrega(primary),
              ),
            ),
          ],
          // Mensaje cuando el docente ya calificó (bloquea edición)
          if (a.gpa != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(children: [
                Icon(Icons.lock_rounded,
                    size: 13, color: Colors.grey.shade500),
                const SizedBox(width: 6),
                Text(
                  'El docente ya calificó esta entrega.',
                  style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: Colors.grey.shade500,
                      fontStyle: FontStyle.italic),
                ),
              ]),
            ),
          if (a.isPastDue && a.gpa == null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'No se pueden editar entregas después de la fecha límite.',
                style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: Colors.red.shade600,
                    fontStyle: FontStyle.italic),
              ),
            ),
        ],
      );
    }

    // ── Sin entrega (puede entregar) ─────────────────────────────────────
    if (puedeEntregar) {
      return _buildUploadSection(primary);
    }

    // ── Plazo vencido sin entrega ─────────────────────────────────────────
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(children: [
        Icon(Icons.lock_clock_rounded, color: Colors.red.shade700, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'El plazo de entrega ha vencido. Ya no es posible enviar archivos.',
            style: GoogleFonts.poppins(
                fontSize: 13, color: Colors.red.shade800),
          ),
        ),
      ]),
    );
  }

  // ── Sección de carga (2 pasos, múltiples archivos) ────────────────────────

  Widget _buildUploadSection(Color primary) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Lista de archivos pendientes
        if (_pendingFiles.isNotEmpty) ...[
          ...List.generate(_pendingFiles.length, (i) {
            final f = _pendingFiles[i];
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _fileColor(f.name).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(_fileIcon(f.name),
                      color: _fileColor(f.name), size: 22),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(f.name,
                          style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: Colors.blue.shade900),
                          overflow: TextOverflow.ellipsis),
                      Text(
                        '${(f.size / 1024).toStringAsFixed(0)} KB  •  '
                        '${f.extension?.toUpperCase() ?? 'FILE'}',
                        style: GoogleFonts.poppins(
                            fontSize: 11, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Quitar archivo',
                  icon: Icon(Icons.close_rounded, color: Colors.red.shade400, size: 18),
                  onPressed: () => _removePendingFile(i),
                ),
              ]),
            );
          }),
          const SizedBox(height: 4),

          // Botón "+ Agregar otro archivo"
          TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: primary,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: Text('Agregar otro archivo',
                style: GoogleFonts.poppins(
                    fontSize: 13, fontWeight: FontWeight.w600)),
            onPressed: _pickFile,
          ),
          const SizedBox(height: 12),

          // Cuadro de comentario
          TextField(
            controller: _commentCtrl,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'Comentario para el profesor (opcional)',
              labelStyle: GoogleFonts.poppins(
                  fontSize: 13, color: Colors.grey.shade600),
              hintText: 'Ej: Este es mi avance del proyecto final...',
              hintStyle: GoogleFonts.poppins(
                  fontSize: 12, color: Colors.grey.shade400),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                      color: Color(0xFF1A237E), width: 2)),
              contentPadding: const EdgeInsets.all(14),
              prefixIcon: const Icon(Icons.comment_rounded, size: 20),
            ),
          ),
          const SizedBox(height: 14),

          // Botón "Enviar entrega"
          SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 4,
                shadowColor: primary.withOpacity(0.4),
              ),
              icon: const Icon(Icons.send_rounded),
              label: Text('Enviar entrega',
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700, fontSize: 15)),
              onPressed: _enviarEntrega,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'El archivo se enviará al profesor para su calificación.',
            style:
                GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade500),
            textAlign: TextAlign.center,
          ),
        ] else ...[
          // Estado inicial: solo el botón "Agregar entrega"
          SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 4,
                shadowColor: primary.withOpacity(0.4),
              ),
              icon: const Icon(Icons.attach_file_rounded),
              label: Text('Agregar entrega',
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700, fontSize: 15)),
              onPressed: _pickFile,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Formatos: PDF, DOC, DOCX, PNG, JPG, ZIP, XLSX, PPTX  •  Máx. 5 MB',
            style: GoogleFonts.poppins(
                fontSize: 11, color: Colors.grey.shade500),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  Widget _buildUploadingIndicator() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A237E).withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: const Color(0xFF1A237E).withOpacity(0.15)),
      ),
      child: Column(children: [
        const CircularProgressIndicator(
            strokeWidth: 3, color: Color(0xFF1A237E)),
        const SizedBox(height: 14),
        Text(
          _pendingFiles.length > 1
              ? 'Enviando archivo ${_uploadedCount + 1} de ${_pendingFiles.length}...'
              : 'Enviando "${_pendingFiles.isNotEmpty ? _pendingFiles[0].name : "archivo"}"...',
          style: GoogleFonts.poppins(
              fontSize: 13,
              color: const Color(0xFF1A237E),
              fontWeight: FontWeight.w600),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text('Por favor espera, no cierres esta pantalla',
            style: GoogleFonts.poppins(
                fontSize: 11, color: Colors.grey.shade500)),
      ]),
    );
  }

  Widget _buildSuccessCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.green.shade600, Colors.green.shade400],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.green.withOpacity(0.3),
              blurRadius: 14,
              offset: const Offset(0, 5)),
        ],
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.25),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_circle_rounded,
              color: Colors.white, size: 28),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _uploadedCount == 1
                    ? '¡Entrega enviada exitosamente!'
                    : '¡$_uploadedCount archivos enviados exitosamente!',
                style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14)),
              Text('El profesor recibirá tu trabajo para calificarlo.',
                  style: GoogleFonts.poppins(
                      color: Colors.white.withOpacity(0.8), fontSize: 11)),
            ],
          ),
        ),
      ]),
    );
  }

  /// Muestra los archivos ya entregados con opciones de abrir y descargar.
  Widget _buildDeliveredFiles(ActivityModel a, Color primary) {
    if (a.resolution == null || a.resolution!.isEmpty) return const SizedBox();
    final urls = FileViewerHelper.parseUrls(a.resolution!);
    if (urls.isEmpty) return const SizedBox();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: urls.asMap().entries.map((e) =>
        FileViewerHelper.buildFileCard(e.value, index: e.key + 1, primaryColor: primary)
      ).toList(),
    );
  }

  /// Panel de retroalimentación del docente (calificación + comentario).
  ///
  /// Se muestra cuando la actividad ya fue calificada (gpa != null) en la
  /// sección "Tu trabajo". Incluye la nota y el comentario del docente si
  /// está disponible.
  Widget _buildFeedbackPanel(ActivityModel a, Color primary) {
    if (a.gpa == null) return const SizedBox();
    final aprobado = a.gpa! >= 3.0;
    final colorEstado =
        aprobado ? Colors.green.shade700 : Colors.red.shade700;
    final bgEstado =
        aprobado ? Colors.green.shade50 : Colors.red.shade50;
    final iconEstado =
        aprobado ? Icons.check_circle_rounded : Icons.cancel_rounded;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgEstado,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorEstado.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Encabezado con estado calificado
          Row(
            children: [
              Icon(iconEstado, color: colorEstado, size: 20),
              const SizedBox(width: 8),
              Text(
                aprobado ? 'Calificado — Aprobado' : 'Calificado — Reprobado',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: colorEstado,
                ),
              ),
              const Spacer(),
              // Badge con la nota final
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: colorEstado,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  a.gpa!.toStringAsFixed(1),
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          // Comentario del docente (sólo si existe)
          if (a.teacherComment != null) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.comment_outlined,
                    color: colorEstado.withOpacity(0.7), size: 16),
                const SizedBox(width: 6),
                Text(
                  'Retroalimentación:',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: colorEstado,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 22),
              child: Text(
                a.teacherComment!,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  color: Colors.grey.shade800,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Diálogo de confirmación para REEMPLAZAR la entrega actual (CU-05 FA-04).
  ///
  /// Llama al backend para borrar la resolución existente, luego muestra el
  /// formulario de carga para que el estudiante suba el nuevo archivo.
  void _confirmarReemplazarEntrega(ActivityModel a, Color primary) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Icon(Icons.swap_horiz_rounded, color: primary, size: 22),
          const SizedBox(width: 8),
          Text('Reemplazar entrega',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        ]),
        content: Text(
          'Se eliminará tu entrega actual para que puedas subir una nueva '
          'antes del plazo. Esta acción no se puede deshacer.\n\n¿Continuar?',
          style: GoogleFonts.poppins(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancelar',
                style: GoogleFonts.poppins(color: Colors.grey.shade600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              // Llamar al backend para limpiar la entrega existente (CU-05 FA-04)
              setState(() => _clearingSubmission = true);
              final ok = await ApiService()
                  .clearSubmission(widget.activity.id, widget.userId);
              if (!mounted) return;
              if (ok) {
                // Limpiar estado local de archivos pendientes
                setState(() {
                  _uploadSuccess = false;
                  _pendingFiles.clear();
                  _pendingBytes.clear();
                  _commentCtrl.clear();
                });
                _showSnack(
                    'Entrega eliminada. Ahora puedes subir un nuevo archivo.',
                    Colors.blue.shade700);
                // Recargar datos del servidor para que el formulario de subida
                // aparezca (sin recarga, _act sigue mostrando la entrega vieja)
                await _refreshActivityState();
              } else {
                setState(() => _clearingSubmission = false);
                _showSnack(
                    'No se pudo reemplazar la entrega. '
                    'Verifica que el plazo no haya vencido.',
                    Colors.red);
              }
            },
            child: Text('Reemplazar',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  /// Diálogo de confirmación para ANULAR la entrega sin reemplazarla.
  ///
  /// También llama al backend para limpiar la resolución, pero el mensaje
  /// indica al estudiante que puede volver a enviar (sin forzar el reenvío).
  void _confirmarAnularEntrega(Color primary) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Anular entrega',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        content: Text(
          'Si anulas la entrega podrás volver a enviar antes del plazo. '
          '¿Continuar?',
          style: GoogleFonts.poppins(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancelar',
                style: GoogleFonts.poppins(color: Colors.grey.shade600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              // Limpiar entrega en el backend antes de actualizar el estado local
              setState(() => _clearingSubmission = true);
              final ok = await ApiService()
                  .clearSubmission(widget.activity.id, widget.userId);
              if (!mounted) return;
              setState(() {
                _uploadSuccess = false;
                _pendingFiles.clear();
                _pendingBytes.clear();
                _commentCtrl.clear();
              });
              _showSnack(
                ok
                    ? 'Entrega anulada. Puedes volver a enviar tu trabajo.'
                    : 'Entrega anulada localmente. Verifica tu conexión.',
                ok ? Colors.orange : Colors.orange.shade300);
              // Recargar del servidor para reflejar el estado limpio en la UI
              await _refreshActivityState();
            },
            child: Text('Anular',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  // ── Widgets de estado ──────────────────────────────────────────────────────

  Widget _buildEstadoBadge(ActivityModel a, bool yaEntrego) {
    if (yaEntrego) {
      return Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.green.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green.shade300),
        ),
        child: Text('Entregado',
            style: GoogleFonts.poppins(
                fontSize: 11,
                color: Colors.green.shade800,
                fontWeight: FontWeight.w700)),
      );
    }
    if (a.isPastDue) {
      return Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Text('Plazo vencido',
            style: GoogleFonts.poppins(
                fontSize: 11,
                color: Colors.red.shade700,
                fontWeight: FontWeight.w700)),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Text('Asignado',
          style: GoogleFonts.poppins(
              fontSize: 11,
              color: Colors.orange.shade800,
              fontWeight: FontWeight.w700)),
    );
  }

  // ── Tabla estado Moodle ────────────────────────────────────────────────────

  Widget _buildMoodleTable(ActivityModel a, bool yaEntrego) {
    String tiempoRestante;
    Color tiempoColor;
    if (a.isPastDue) {
      tiempoRestante = 'El plazo de entrega ha vencido';
      tiempoColor = Colors.red.shade700;
    } else if (yaEntrego) {
      try {
        final cierre = DateTime.parse(a.closingDate);
        final entrega = a.dateResolution != null
            ? DateTime.parse(a.dateResolution!)
            : DateTime.now();
        final diff = cierre.difference(entrega);
        final h = diff.inHours;
        final m = diff.inMinutes % 60;
        tiempoRestante =
            'Enviado $h hora${h == 1 ? '' : 's'} y '
            '$m minuto${m == 1 ? '' : 's'} antes del cierre';
        tiempoColor = Colors.green.shade700;
      } catch (_) {
        tiempoRestante = 'Entregado a tiempo';
        tiempoColor = Colors.green.shade700;
      }
    } else {
      try {
        final cierre = DateTime.parse(a.closingDate);
        final diff = cierre.difference(DateTime.now());
        final dias = diff.inDays;
        final horas = diff.inHours % 24;
        tiempoRestante = dias > 0
            ? '$dias día${dias == 1 ? '' : 's'} y $horas hora${horas == 1 ? '' : 's'}'
            : '$horas hora${horas == 1 ? '' : 's'} restantes';
        tiempoColor = dias < 1 ? Colors.orange.shade700 : Colors.teal;
      } catch (_) {
        tiempoRestante = a.closingDate.split('T')[0];
        tiempoColor = Colors.grey.shade700;
      }
    }

    return Table(
      columnWidths: const {
        0: IntrinsicColumnWidth(),
        1: FlexColumnWidth(),
      },
      border: TableBorder.all(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(8)),
      children: [
        _tableRow('Estado de la entrega',
            yaEntrego
                ? _tableValue('Enviado para calificar', Colors.green.shade700,
                    bg: Colors.green.shade50)
                : a.isPastDue
                    ? _tableValue('No entregado (plazo vencido)',
                        Colors.red.shade700, bg: Colors.red.shade50)
                    : _tableValue('Sin enviar', Colors.orange.shade700,
                        bg: Colors.orange.shade50)),
        _tableRow('Estado de la calificación',
            a.gpa != null
                ? _tableValue(
                    '${a.gpa!.toStringAsFixed(2)} / 5.00  •  '
                    '${a.gpa! >= 4.0 ? 'Excelente' : a.gpa! >= 3.0 ? 'Aprobado' : 'Reprobado'}',
                    a.gpa! >= 3.0
                        ? Colors.green.shade700
                        : Colors.red.shade700,
                    bg: a.gpa! >= 3.0
                        ? Colors.green.shade50
                        : Colors.red.shade50)
                : Text('Sin calificar',
                    style: GoogleFonts.poppins(
                        fontSize: 13, color: Colors.grey.shade600))),
        _tableRow('Tiempo restante',
            Text(tiempoRestante,
                style: GoogleFonts.poppins(fontSize: 13, color: tiempoColor))),
        _tableRow('Apertura',
            Text(a.startDate.split('T')[0],
                style: GoogleFonts.poppins(
                    fontSize: 13, color: Colors.grey.shade700))),
        _tableRow('Cierre',
            Text(a.closingDate.split('T')[0],
                style: GoogleFonts.poppins(
                    fontSize: 13, color: Colors.grey.shade700))),
        if (yaEntrego && a.dateResolution != null)
          _tableRow('Última modificación',
              Text(a.dateResolution!.split('T')[0],
                  style: GoogleFonts.poppins(
                      fontSize: 13, color: Colors.grey.shade700))),
        _tableRow('Archivos enviados',
            yaEntrego && (a.resolution ?? '').isNotEmpty
                ? (() {
                    // Soporta múltiples archivos separados por '|||'
                    final urls = a.resolution!
                        .split('|||')
                        .map((u) => u.trim())
                        .where((u) => u.isNotEmpty)
                        .toList();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: urls
                          .map((u) => Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: _buildFileLink(u),
                              ))
                          .toList(),
                    );
                  })()
                : (_uploadSuccess && _pendingFiles.isNotEmpty
                    ? _buildFileLink(_pendingFiles[0].name, isLocal: true)
                    : Text('—',
                        style: GoogleFonts.poppins(
                            fontSize: 13, color: Colors.grey.shade400)))),
      ],
    );
  }

  // ── Encabezado ─────────────────────────────────────────────────────────────

  Widget _buildHeader(ActivityModel a, Color primary) {
    final typeColor = _tipoColor(a.type);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, 4))
        ],
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: typeColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(_tipoIcono(a.type), color: typeColor, size: 30),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(a.tittle,
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700, fontSize: 17)),
              const SizedBox(height: 4),
              Row(children: [
                _chip(_tipoLabel(a.type), typeColor),
                const SizedBox(width: 8),
                _chip('${(a.weighting * 100).toStringAsFixed(0)}%',
                    Colors.indigo),
                const SizedBox(width: 8),
                _chip('Semana ${a.week}', Colors.grey.shade600),
              ]),
            ],
          ),
        ),
      ]),
    );
  }

  // ── Helpers UI ─────────────────────────────────────────────────────────────

  /// Chip visual para un archivo.
  ///
  /// Si [label] se suministra se usa ese texto en lugar del nombre del archivo.
  /// Si [isLocal] es true el chip es no interactivo (archivo pendiente de subir).
  Widget _buildFileLink(String url, {bool isLocal = false, String? label}) {
    if (isLocal) {
      return FileViewerHelper.buildFileCard(url, isLocal: true, showDownload: false);
    }
    final name = label ?? FileViewerHelper.extractName(url);
    return GestureDetector(
      onTap: () => FileViewerHelper.abrirArchivo(url),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blue.shade200),
        ),
        child: Row(children: [
          Icon(FileViewerHelper.fileIcon(url), color: FileViewerHelper.fileColor(url), size: 22),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: GoogleFonts.poppins(fontSize: 13, color: Colors.blue.shade800,
                fontWeight: FontWeight.w600, decoration: TextDecoration.underline,
                decorationColor: Colors.blue.shade300), overflow: TextOverflow.ellipsis),
            Text('Toca para visualizar', style: GoogleFonts.poppins(fontSize: 10, color: Colors.blue.shade300)),
          ])),
          Icon(Icons.open_in_new_rounded, color: Colors.blue.shade400, size: 16),
        ]),
      ),
    );
  }

    Widget _buildCard({
    required String title,
    required IconData icon,
    required Color iconColor,
    required Widget child,
    Widget? titleTrailing,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 3))
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
              border: Border(
                  bottom:
                      BorderSide(color: Colors.grey.shade100, width: 1))),
          child: Row(children: [
            Icon(icon, color: iconColor, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(title,
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: Colors.grey.shade800)),
            ),
            if (titleTrailing != null) titleTrailing,
          ]),
        ),
        Padding(padding: const EdgeInsets.all(16), child: child),
      ]),
    );
  }

  TableRow _tableRow(String label, Widget value) {
    return TableRow(children: [
      Container(
        color: Colors.grey.shade50,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Text(label,
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                fontSize: 12,
                color: Colors.grey.shade700)),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: value,
      ),
    ]);
  }

  Widget _tableValue(String text, Color textColor, {Color? bg}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg ?? textColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text,
          style: GoogleFonts.poppins(
              fontSize: 12,
              color: textColor,
              fontWeight: FontWeight.w600)),
    );
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text,
          style: GoogleFonts.poppins(
              fontSize: 10, color: color, fontWeight: FontWeight.w600)),
    );
  }

  // ── Iconos y colores de archivo ────────────────────────────────────────────

  IconData _fileIcon(String name) {
    final ext = name.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf': return Icons.picture_as_pdf_rounded;
      case 'doc': case 'docx': return Icons.description_rounded;
      case 'zip': return Icons.folder_zip_rounded;
      case 'png': case 'jpg': case 'jpeg': return Icons.image_rounded;
      case 'xlsx': case 'xls': return Icons.table_chart_rounded;
      case 'pptx': case 'ppt': return Icons.slideshow_rounded;
      default: return Icons.attach_file_rounded;
    }
  }

  Color _fileColor(String name) {
    final ext = name.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf': return Colors.red.shade700;
      case 'doc': case 'docx': return Colors.blue.shade700;
      case 'zip': return Colors.orange.shade700;
      case 'png': case 'jpg': case 'jpeg': return Colors.teal.shade700;
      case 'xlsx': case 'xls': return Colors.green.shade700;
      case 'pptx': case 'ppt': return Colors.deepOrange.shade700;
      default: return Colors.blueGrey.shade700;
    }
  }

  // ── Tipos de actividad ─────────────────────────────────────────────────────

  Color _tipoColor(String tipo) {
    switch (tipo) {
      case 'midterm': return Colors.orange;
      case 'project': return Colors.blue;
      case 'resource': return Colors.green;
      default: return Colors.purple;
    }
  }

  IconData _tipoIcono(String tipo) {
    switch (tipo) {
      case 'midterm': return Icons.quiz_rounded;
      case 'project': return Icons.folder_rounded;
      case 'resource': return Icons.description_rounded;
      default: return Icons.assignment_rounded;
    }
  }

  String _tipoLabel(String tipo) {
    switch (tipo) {
      case 'midterm': return 'Parcial';
      case 'project': return 'Proyecto';
      case 'resource': return 'Recurso';
      default: return 'Otro';
    }
  }
}