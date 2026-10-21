import 'dart:async';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../config/api_config.dart';
import '../config/app_tokens.dart';

/// Indicador de **a qué servidor está conectada la app** y si responde.
///
/// Solo existe en compilaciones de depuración (en producción no ocupa espacio) y
/// **permanece oculto mientras el servidor responde**: solo aparece cuando NO hay
/// conexión, para explicar cómo arrancar el backend. Para verlo siempre (útil al
/// alternar entre servidor local y de producción):
/// `flutter run --dart-define=SHOW_SERVER_BADGE=true`.
class DevServerBadge extends StatefulWidget {
  const DevServerBadge({super.key, this.baseUrl, this.client, this.siempreVisible});

  /// Para pruebas; por defecto [ApiConfig.baseUrl].
  final String? baseUrl;
  final http.Client? client;

  /// Mostrarlo aunque el servidor responda. Por defecto lo decide `SHOW_SERVER_BADGE`.
  final bool? siempreVisible;

  static const _mostrarSiempre = bool.fromEnvironment('SHOW_SERVER_BADGE');

  @override
  State<DevServerBadge> createState() => _DevServerBadgeState();
}

enum _Estado { comprobando, activo, sinRespuesta }

class _DevServerBadgeState extends State<DevServerBadge> {
  _Estado _estado = _Estado.comprobando;

  String get _url => widget.baseUrl ?? ApiConfig.baseUrl;
  bool get _esLocal =>
      _url.contains('localhost') || _url.contains('127.0.0.1') || _url.contains('10.0.2.2') ||
      RegExp(r'//(192\.168|10\.)').hasMatch(_url);

  @override
  void initState() {
    super.initState();
    _comprobar();
  }

  Future<void> _comprobar() async {
    if (mounted) setState(() => _estado = _Estado.comprobando);
    try {
      final c = widget.client;
      final res = await (c != null ? c.get(Uri.parse('$_url/health')) : http.get(Uri.parse('$_url/health')))
          .timeout(const Duration(seconds: 5));
      if (mounted) setState(() => _estado = res.statusCode < 500 ? _Estado.activo : _Estado.sinRespuesta);
    } catch (_) {
      if (mounted) setState(() => _estado = _Estado.sinRespuesta);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode && widget.baseUrl == null) return const SizedBox.shrink();
    // Oculto mientras todo va bien: solo estorbaría en el login.
    final siempre = widget.siempreVisible ?? DevServerBadge._mostrarSiempre;
    if (!siempre && _estado != _Estado.sinRespuesta) return const SizedBox.shrink();
    final t = context.tokens;
    final (Color color, String texto) = switch (_estado) {
      _Estado.comprobando => (t.muted, 'Comprobando servidor…'),
      _Estado.activo => (t.success, 'Servidor activo'),
      _Estado.sinRespuesta => (t.danger, 'Sin respuesta del servidor'),
    };

    return Semantics(
      container: true,
      liveRegion: true,
      label: '$texto. Dirección: $_url.',
      child: Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppTokens.radiusControl),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 9, height: 9,
              decoration: BoxDecoration(
                color: color, shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 6)],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(texto,
                  style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w700, color: color)),
            ),
            Text(_esLocal ? 'LOCAL' : 'PRODUCCIÓN',
                style: GoogleFonts.poppins(
                    fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1, color: t.muted)),
            if (_estado == _Estado.sinRespuesta)
              IconButton(
                tooltip: 'Reintentar conexión',
                visualDensity: VisualDensity.compact,
                onPressed: _comprobar,
                icon: Icon(PhosphorIconsBold.arrowClockwise, size: 16, color: color),
              ),
          ]),
          const SizedBox(height: 4),
          SelectableText(_url, style: GoogleFonts.robotoMono(fontSize: 11.5, color: t.muted)),
          if (_estado == _Estado.sinRespuesta) ...[
            const SizedBox(height: 6),
            Text(
              _esLocal
                  ? 'El backend local no está corriendo. Ábrelo con "npm start" en la carpeta Backend '
                    '(o usa tool\\dev_local.ps1).'
                  : 'No se pudo contactar al servidor. Revisa tu conexión a internet.',
              style: GoogleFonts.poppins(fontSize: 11.5, height: 1.4),
            ),
          ] else if (_estado == _Estado.activo) ...[
            const SizedBox(height: 4),
            Text('Cada servidor tiene sus propios usuarios: los de producción pueden no existir aquí.',
                style: GoogleFonts.poppins(fontSize: 11, color: t.muted, height: 1.35)),
          ],
        ]),
      ),
    );
  }
}
