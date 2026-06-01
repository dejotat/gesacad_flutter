import 'package:gesacad/utils/platform_utils.dart';
import 'package:flutter/material.dart';
import '../config/api_config.dart';

/// Helper centralizado para visualización y descarga de archivos de Cloudinary.
///
/// ESTRATEGIA POR TIPO:
/// - Word (.docx/.doc)     → Google Docs Viewer con URL del proxy
/// - Excel (.xlsx/.xls)    → Google Docs Viewer con URL del proxy
/// - PowerPoint (.pptx)    → Google Docs Viewer con URL del proxy
/// - PDF                   → Abrir directamente via proxy (el navegador lo renderiza)
/// - Imágenes              → Abrir directamente via proxy
/// - ZIP/RAR               → Solo descarga via proxy
/// - Cloudinary raw        → Google Docs Viewer (probablemente Office)
class FileViewerHelper {

  // ── Extraer URL real y nombre original ──────────────────────────────────────

  static String extractUrl(String rawUrl) {
    if (rawUrl.contains('::name::')) return rawUrl.split('::name::').first.trim();
    return rawUrl.trim();
  }

  static String extractName(String rawUrl, {int index = 1}) {
    // Formato estándar actual: url::name::nombre_original.ext
    if (rawUrl.contains('::name::')) {
      return rawUrl.split('::name::').last.trim();
    }
    // Compatibilidad con el formato antiguo del backend (antes de la corrección):
    // url nameFile:nombre_original.ext
    if (rawUrl.contains('nameFile:')) {
      return rawUrl.split('nameFile:').last.trim();
    }
    // Si la URL misma tiene extensión reconocida (ej. imágenes subidas por Cloudinary
    // con use_filename:true), extraerla del segmento final de la ruta.
    final url = rawUrl.trim();
    final segment = url.split('/').last.split('?').first;
    final decoded = Uri.decodeComponent(segment);
    final exts = ['pdf','doc','docx','png','jpg','jpeg','gif','zip','rar','7z',
                  'xlsx','xls','pptx','ppt','txt','csv'];
    if (decoded.contains('.') &&
        exts.any((e) => decoded.toLowerCase().endsWith('.$e'))) {
      return decoded;
    }
    return 'Archivo $index';
  }

  static List<String> parseUrls(String raw) =>
      raw.split('|||').map((u) => u.trim()).where((u) => u.isNotEmpty).toList();

  // ── Detectar extensión ──────────────────────────────────────────────────────

  static String detectExtension(String rawUrl) {
    final name = extractName(rawUrl).toLowerCase();
    final url  = extractUrl(rawUrl).toLowerCase();

    for (final ext in ['pdf','docx','doc','xlsx','xls','pptx','ppt',
                        'png','jpg','jpeg','gif','zip','rar','7z','txt','csv']) {
      if (name.endsWith('.$ext')) return ext;
    }
    for (final ext in ['pdf','docx','doc','xlsx','xls','pptx','ppt',
                        'png','jpg','jpeg','gif','zip','rar','7z','txt','csv']) {
      if (url.contains('.$ext')) return ext;
    }
    if (url.contains('/raw/upload/'))   return 'raw';
    if (url.contains('/image/upload/')) return 'jpg';
    return 'unknown';
  }

  static bool isOffice(String ext) =>
      ['doc','docx','xls','xlsx','ppt','pptx'].contains(ext);
  static bool isPdf(String ext)   => ext == 'pdf';
  static bool isImage(String ext) => ['png','jpg','jpeg','gif','webp'].contains(ext);
  static bool isZip(String ext)   => ['zip','rar','7z'].contains(ext);

  // ── Construir URL del proxy ─────────────────────────────────────────────────
  // El proxy de Railway recibe la URL completa (con ::name:: si existe)
  // y se encarga de setear el Content-Type correcto según el nombre.

  static String proxyUrl(String rawUrl, {bool download = false}) {
    final realUrl = extractUrl(rawUrl);
    if (!realUrl.toLowerCase().contains('cloudinary.com')) return realUrl;
    // Pasar la URL completa (incluye ::name::) para que el proxy sepa el nombre
    final encoded = Uri.encodeComponent(rawUrl.trim());
    return '${ApiConfig.baseUrl}${ApiConfig.proxyFile}?url=$encoded'
        '${download ? '&dl=1' : ''}';
  }

  // ── Abrir archivo ───────────────────────────────────────────────────────────

  static void abrirArchivo(String rawUrl) {
    final ext     = detectExtension(rawUrl);
    final realUrl = extractUrl(rawUrl);

    if (isZip(ext)) {
      descargarArchivo(rawUrl);
      return;
    }

    if (isImage(ext)) {
      // Imágenes: abrir directamente, el navegador las renderiza sin problemas.
      PlatformUtils.openUrl(realUrl);
      return;
    }

    if (isPdf(ext)) {
      // PDFs nuevos (subidos con resource_type:"raw" + extensión .pdf en public_id):
      // Cloudinary los sirve con Content-Type: application/pdf y Chrome los
      // renderiza directamente en su visor nativo al abrir la URL.
      // - El proxy de Railway falla con 401 (IP del servidor bloqueada por Cloudinary CDN).
      // - Google Docs Viewer no puede acceder a URLs raw de Cloudinary.
      // La URL directa es la solución correcta para archivos públicos con resource_type:raw.
      PlatformUtils.openUrl(realUrl);
      return;
    }

    if (isOffice(ext) || ext == 'raw') {
      final name = extractName(rawUrl);
      if (name.contains('.')) {
        // Usar Microsoft Office Online Viewer en lugar de Google Docs Viewer.
        // Razones del cambio:
        // 1. Google Docs Viewer tiene restricciones conocidas para acceder a
        //    URLs Cloudinary Raw y devuelve "No hay vista previa disponible".
        // 2. fl_attachment fuerza Content-Disposition: attachment (descarga),
        //    lo que impide que cualquier viewer previsualice el archivo.
        // Se pasa la URL directa de Cloudinary SIN fl_attachment para que
        // Office Online pueda leer el archivo con el Content-Type correcto
        // (determinado por la extensión en el public_id de Cloudinary).
        final encoded = Uri.encodeComponent(realUrl);
        final viewer  = 'https://view.officeapps.live.com/op/view.aspx?src=$encoded';
        PlatformUtils.openUrl(viewer);
      } else {
        // Sin nombre ni extensión (datos subidos antes del fix del backend):
        // abrir directo; el navegador descargará el archivo.
        PlatformUtils.openUrl(realUrl);
      }
      return;
    }

    PlatformUtils.openUrl(realUrl);
  }


  // ── Descargar archivo ───────────────────────────────────────────────────────

  static void descargarArchivo(String rawUrl, {int index = 1}) {
    final name    = extractName(rawUrl, index: index);
    final realUrl = extractUrl(rawUrl);
    // Se usa la URL directa de Cloudinary SIN fl_attachment.
    // fl_attachment insertaba una transformación en la URL que Cloudinary
    // rechazaba con HTTP 400 para raw uploads (pptx, xlsx, etc.).
    // El nombre correcto de descarga lo maneja el atributo 'download'
    // del anchor HTML en PlatformUtils.downloadFile().
    PlatformUtils.downloadFile(realUrl, name);
  }

  // ── Ícono y color ───────────────────────────────────────────────────────────

  static IconData fileIcon(String rawUrl) {
    final ext = detectExtension(rawUrl);
    switch (ext) {
      case 'pdf':  return Icons.picture_as_pdf_rounded;
      case 'doc':  case 'docx': return Icons.description_rounded;
      case 'xls':  case 'xlsx': return Icons.table_chart_rounded;
      case 'ppt':  case 'pptx': return Icons.slideshow_rounded;
      case 'png':  case 'jpg': case 'jpeg': case 'gif': return Icons.image_rounded;
      case 'zip':  case 'rar': case '7z': return Icons.folder_zip_rounded;
      case 'txt':  case 'csv': return Icons.article_rounded;
      case 'raw':  return Icons.description_rounded;
      default:     return Icons.attach_file_rounded;
    }
  }

  static Color fileColor(String rawUrl) {
    final ext = detectExtension(rawUrl);
    switch (ext) {
      case 'pdf':  return const Color(0xFFD32F2F);
      case 'doc':  case 'docx': return const Color(0xFF1565C0);
      case 'xls':  case 'xlsx': return const Color(0xFF2E7D32);
      case 'ppt':  case 'pptx': return const Color(0xFFE65100);
      case 'png':  case 'jpg': case 'jpeg': case 'gif': return const Color(0xFF00695C);
      case 'zip':  case 'rar': case '7z': return const Color(0xFF6A1B9A);
      case 'raw':  return const Color(0xFF1565C0);
      default:     return const Color(0xFF455A64);
    }
  }

  static String fileLabel(String rawUrl) {
    final ext = detectExtension(rawUrl);
    switch (ext) {
      case 'pdf':  return 'PDF';
      case 'doc':  case 'docx': return 'Word';
      case 'xls':  case 'xlsx': return 'Excel';
      case 'ppt':  case 'pptx': return 'PowerPoint';
      case 'png':  case 'jpg': case 'jpeg': case 'gif': return 'Imagen';
      case 'zip':  return 'ZIP';
      case 'rar':  return 'RAR';
      case '7z':   return '7-Zip';
      case 'raw':  return 'Documento';
      default:     return 'Archivo';
    }
  }

  // ── Widget tarjeta de archivo ───────────────────────────────────────────────

  static Widget buildFileCard(
    String rawUrl, {
    int index = 1,
    bool showDownload = true,
    bool isLocal = false,
    Color primaryColor = const Color(0xFF1A237E),
  }) {
    final name     = isLocal ? rawUrl : extractName(rawUrl, index: index);
    final icon     = fileIcon(rawUrl);
    final color    = fileColor(rawUrl);
    final label    = fileLabel(rawUrl);
    final ext      = detectExtension(rawUrl);
    final isZipFile = isZip(ext);
    final canOpen  = !isLocal && !isZipFile;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.25), width: 1.5),
        boxShadow: [
          BoxShadow(
              color: color.withOpacity(0.08),
              blurRadius: 8,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: canOpen ? () => abrirArchivo(rawUrl) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              // Ícono del tipo
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 12),
              // Nombre y tipo
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isLocal
                            ? Colors.grey.shade600
                            : const Color(0xFF1A1A2E),
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    const SizedBox(height: 3),
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(label,
                            style: TextStyle(
                                fontSize: 9,
                                color: color,
                                fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isLocal
                            ? 'Listo para enviar'
                            : isZipFile
                                ? 'Descargar para ver'
                                : 'Toca para abrir',
                        style: TextStyle(
                            fontSize: 10, color: Colors.grey.shade400),
                      ),
                    ]),
                  ],
                ),
              ),
              // Botones
              if (!isLocal) ...[
                if (canOpen)
                  Tooltip(
                    message: 'Abrir',
                    child: IconButton(
                      icon: Icon(Icons.open_in_new_rounded,
                          color: color, size: 20),
                      onPressed: () => abrirArchivo(rawUrl),
                    ),
                  ),
                if (showDownload)
                  Tooltip(
                    message: 'Descargar',
                    child: IconButton(
                      icon: Icon(Icons.download_rounded,
                          color: Colors.grey.shade400, size: 20),
                      onPressed: () =>
                          descargarArchivo(rawUrl, index: index),
                    ),
                  ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}
