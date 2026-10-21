import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/app_tokens.dart';
import '../../models/calendar_models.dart';
import '../../services/calendar_service.dart';
import '../../widgets/ui/ui.dart';
import '../notifications/notification_router.dart';

const _dias = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
const _meses = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
  'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
];

String _cap(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

/// "Lunes 20 de mayo · 19:30" (sin depender de datos de idioma).
String fechaLarga(DateTime col, {bool conHora = true}) {
  final base = '${_cap(_dias[col.weekday - 1])} ${col.day} de ${_meses[col.month - 1]}';
  return conHora
      ? '$base · ${col.hour.toString().padLeft(2, '0')}:${col.minute.toString().padLeft(2, '0')}'
      : base;
}

/// "2 d 4 h", "5 h 10 min", "12 min" o "ahora".
String duracionCorta(Duration d) {
  if (d.inMinutes < 1) return 'ahora';
  if (d.inHours < 1) return '${d.inMinutes} min';
  if (d.inDays < 1) {
    final m = d.inMinutes % 60;
    return m == 0 ? '${d.inHours} h' : '${d.inHours} h $m min';
  }
  final h = d.inHours % 24;
  return h == 0 ? '${d.inDays} d' : '${d.inDays} d $h h';
}

/// El número grande y su unidad para el círculo del contador: "3\nd", "2\nh", "45\nmin".
String _numeroYUnidad(Duration d) {
  if (d.inDays >= 1) return '${d.inDays}\nd';
  if (d.inHours >= 1) return '${d.inHours}\nh';
  return '${d.inMinutes < 1 ? 1 : d.inMinutes}\nmin';
}

/// Hora actual de pared en Colombia (UTC-5), como las fechas de [CalEvent.startCol].
DateTime ahoraColombia([DateTime? ahora]) {
  final c = (ahora ?? DateTime.now()).toUtc().subtract(const Duration(hours: 5));
  return DateTime(c.year, c.month, c.day, c.hour, c.minute, c.second);
}

// ═════════════════════════════════════════════════════════════════════════════
// Próximo vencimiento
// ═════════════════════════════════════════════════════════════════════════════
/// Tarjeta con la cuenta regresiva al próximo evento que requiere atención.
/// Se actualiza sola cada medio minuto y cambia de color según la urgencia.
class ProximoVencimientoCard extends StatefulWidget {
  const ProximoVencimientoCard({super.key, required this.eventos, required this.onTap, this.ahora});

  final List<CalEvent> eventos;
  final ValueChanged<CalEvent> onTap;

  /// Para pruebas: reloj fijo (UTC).
  final DateTime Function()? ahora;

  @override
  State<ProximoVencimientoCard> createState() => _ProximoVencimientoCardState();
}

class _ProximoVencimientoCardState extends State<ProximoVencimientoCard> {
  Timer? _timer;

  DateTime get _ahora => (widget.ahora?.call() ?? DateTime.now()).toUtc();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// El siguiente evento que importa: entregas pendientes o abiertas, reuniones y evaluaciones por responder.
  CalEvent? _siguiente() {
    final ahora = _ahora;
    final candidatos = widget.eventos.where((e) {
      if (!e.startUtc.isAfter(ahora)) return e.kind == CalKind.meeting && e.status == 'live';
      return switch (e.kind) {
        CalKind.activity => e.esEntrega && (e.status == 'pending' || e.status == 'open'),
        CalKind.meeting => true,
        CalKind.evaluation => e.status == 'pending' || e.status == 'open',
      };
    }).toList()
      ..sort((a, b) => a.startUtc.compareTo(b.startUtc));
    return candidatos.isEmpty ? null : candidatos.first;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final e = _siguiente();
    if (e == null) {
      return AppCard(
        blur: false,
        child: Row(children: [
          Icon(Icons.verified_rounded, color: t.success),
          const SizedBox(width: 12),
          Expanded(
            child: Text('Estás al día: no hay vencimientos próximos.',
                style: GoogleFonts.poppins(fontSize: 13.5, fontWeight: FontWeight.w600)),
          ),
        ]),
      );
    }
    final falta = e.startUtc.difference(_ahora);
    final enCurso = falta.isNegative;
    final color = enCurso || falta.inHours < 3 ? t.danger : falta.inHours < 24 ? t.warning : t.info;
    final etiqueta = switch (e.kind) {
      CalKind.activity => e.status == 'open' ? 'Próximo cierre' : 'Próxima entrega',
      CalKind.meeting => enCurso ? 'Reunión en curso' : 'Próxima reunión',
      CalKind.evaluation => 'Evaluación docente',
    };
    final texto = enCurso ? 'ahora' : 'en ${duracionCorta(falta)}';

    return Semantics(
      button: true,
      label: '$etiqueta: ${e.title}, $texto. Toca para ver el día.',
      child: ExcludeSemantics(
        child: AppCard(
          blur: false,
          tint: color,
          onTap: () => widget.onTap(e),
          child: Row(children: [
            Container(
              width: 54, height: 54,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.15),
                border: Border.all(color: color.withValues(alpha: 0.5), width: 2),
              ),
              child: Center(
                child: Text(
                  enCurso ? 'YA' : _numeroYUnidad(falta),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(fontSize: 11.5, height: 1.1, fontWeight: FontWeight.w800, color: color),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(etiqueta.toUpperCase(),
                    style: GoogleFonts.poppins(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1, color: color)),
                Text(e.title,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(fontSize: 14.5, fontWeight: FontWeight.w700)),
                Text('${e.courseName != null ? '${e.courseName} · ' : ''}${fechaLarga(e.startCol)}',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(fontSize: 12, color: t.muted)),
              ]),
            ),
            Icon(Icons.chevron_right_rounded, color: t.muted),
          ]),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Carga de la semana
// ═════════════════════════════════════════════════════════════════════════════
/// Siete barras (lunes a domingo) con cuántos eventos hay cada día: de un vistazo se ve
/// qué semana viene pesada. Tocar una barra selecciona ese día.
class CargaSemanalCard extends StatelessWidget {
  const CargaSemanalCard({
    super.key,
    required this.dia,
    required this.conteo,
    required this.seleccionado,
    required this.onDia,
    this.hoy,
  });

  /// Cualquier día de la semana a mostrar.
  final DateTime dia;

  /// Eventos por día (claves a medianoche).
  final Map<DateTime, int> conteo;
  final DateTime seleccionado;
  final ValueChanged<DateTime> onDia;
  final DateTime? hoy;

  static const _letras = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final primario = Theme.of(context).colorScheme.primary;
    final lunes = DateTime(dia.year, dia.month, dia.day - (dia.weekday - 1));
    final dias = [for (var i = 0; i < 7; i++) DateTime(lunes.year, lunes.month, lunes.day + i)];
    final cuentas = [for (final d in dias) conteo[d] ?? 0];
    final maximo = cuentas.fold<int>(1, (a, b) => b > a ? b : a);
    final total = cuentas.fold<int>(0, (a, b) => a + b);
    final hoyDia = hoy == null ? null : DateTime(hoy!.year, hoy!.month, hoy!.day);
    final detalle = [for (var i = 0; i < 7; i++) '${_dias[i]} ${cuentas[i]}'].join(', ');
    final etiqueta = 'Carga de la semana: $total eventos. $detalle';

    return Semantics(
      label: etiqueta,
      child: ExcludeSemantics(
        child: AppCard(
          blur: false,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('Carga de la semana', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700)),
              const Spacer(),
              Text(total == 0 ? 'Semana libre' : '$total ${total == 1 ? 'evento' : 'eventos'}',
                  style: GoogleFonts.poppins(fontSize: 12, color: t.muted)),
            ]),
            const SizedBox(height: 10),
            SizedBox(
              height: 88,
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onDia(dias[i]),
                      child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                        Text(cuentas[i] == 0 ? '' : '${cuentas[i]}',
                            style: GoogleFonts.poppins(fontSize: 10.5, fontWeight: FontWeight.w700, color: t.muted)),
                        const SizedBox(height: 2),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 350),
                          curve: Curves.easeOutCubic,
                          width: 18,
                          height: 4 + 38.0 * cuentas[i] / maximo,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            color: cuentas[i] == 0
                                ? t.muted.withValues(alpha: 0.18)
                                : (cuentas[i] >= 3 ? t.warning : primario)
                                    .withValues(alpha: dias[i] == DateTime(seleccionado.year, seleccionado.month, seleccionado.day) ? 1 : 0.55),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(_letras[i],
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              fontWeight: dias[i] == hoyDia ? FontWeight.w900 : FontWeight.w600,
                              color: dias[i] == hoyDia ? primario : t.muted,
                            )),
                      ]),
                    ),
                  ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Acciones de un evento
// ═════════════════════════════════════════════════════════════════════════════
IconData _iconoDe(CalEvent e) => switch (e.kind) {
      CalKind.meeting => Icons.videocam_rounded,
      CalKind.evaluation => Icons.insights_rounded,
      CalKind.activity => e.activityType == 'midterm'
          ? Icons.quiz_rounded
          : e.activityType == 'resource' ? Icons.menu_book_rounded : Icons.assignment_rounded,
    };

/// Hoja con el detalle de un evento y lo que se puede hacer con él.
Future<void> mostrarAccionesEvento(
  BuildContext context,
  CalEvent e, {
  required int userId,
  required String rol,
  Future<bool> Function(Uri uri)? abrirEnlace,
}) {
  final abrir = abrirEnlace ?? (Uri u) => launchUrl(u, mode: LaunchMode.externalApplication);
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      final t = ctx.tokens;
      final color = e.estadoColor(t.success, t.warning, t.danger, t.info) ?? Theme.of(ctx).colorScheme.primary;
      Future<void> hacer(Future<void> Function() accion) async {
        Navigator.pop(ctx);
        await accion();
      }

      final puedeUnirse = e.kind == CalKind.meeting && e.url != null;
      final puedeAbrir = e.refType != null && (e.kind != CalKind.meeting || rol != 'Admin');

      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
                child: Icon(_iconoDe(e), color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Semantics(
                    header: true,
                    child: Text(e.title, style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700)),
                  ),
                  if (e.courseName != null)
                    Text(e.courseName!, style: GoogleFonts.poppins(fontSize: 12.5, color: t.muted)),
                ]),
              ),
            ]),
            const SizedBox(height: 14),
            _fila(ctx, Icons.event_rounded, fechaLarga(e.startCol)),
            if (e.estadoTexto != null) _fila(ctx, Icons.flag_rounded, e.estadoTexto!, color: color),
            if ((e.weighting ?? 0) > 0)
              _fila(ctx, Icons.percent_rounded, 'Vale ${(e.weighting! * 100).round()} % de la nota'),
            const SizedBox(height: 16),
            if (puedeUnirse)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AppButton(
                  label: e.status == 'live' ? 'Unirse a la reunión' : 'Abrir la sala',
                  icon: Icons.videocam_rounded,
                  reaction: IconReaction.nudge,
                  expand: true,
                  onPressed: () => hacer(() => abrir(Uri.parse(e.url!))),
                ),
              ),
            if (puedeAbrir)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AppButton(
                  label: switch (e.kind) {
                    CalKind.activity => rol == 'Teacher' ? 'Ver entregas del curso' : 'Abrir actividad',
                    CalKind.meeting => 'Ir al curso',
                    CalKind.evaluation => 'Ir a la evaluación',
                  },
                  icon: Icons.open_in_new_rounded,
                  style: puedeUnirse ? AppButtonStyle.tonal : AppButtonStyle.primary,
                  expand: true,
                  onPressed: () => hacer(() async {
                    await abrirReferencia(context,
                        refType: e.refType, refId: e.refId, courseId: e.courseId,
                        courseName: e.courseName, userId: userId, rol: rol);
                  }),
                ),
              ),
            Row(children: [
              Expanded(
                child: AppButton(
                  label: 'Añadir a Google Calendar',
                  icon: Icons.calendar_month_rounded,
                  style: AppButtonStyle.outline,
                  height: 44,
                  onPressed: () => hacer(() => abrir(e.googleCalendarUri())),
                ),
              ),
              if (e.url != null) ...[
                const SizedBox(width: 8),
                AnimatedIconButton(
                  tooltip: 'Copiar enlace de la reunión',
                  icon: Icons.copy_rounded,
                  reaction: IconReaction.pop,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: e.url!));
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      behavior: SnackBarBehavior.floating,
                      content: Text('Enlace copiado.', style: GoogleFonts.poppins(color: Colors.white)),
                    ));
                  },
                ),
              ],
            ]),
          ]),
        ),
      );
    },
  );
}

Widget _fila(BuildContext ctx, IconData icono, String texto, {Color? color}) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Icon(icono, size: 18, color: color ?? ctx.tokens.muted),
        const SizedBox(width: 10),
        Expanded(
          child: Text(texto,
              style: GoogleFonts.poppins(fontSize: 13.5, fontWeight: FontWeight.w600, color: color)),
        ),
      ]),
    );

// ═════════════════════════════════════════════════════════════════════════════
// Suscripción: ver GESACAD en Google Calendar, Outlook o Apple
// ═════════════════════════════════════════════════════════════════════════════
Future<void> mostrarSincronizacion(
  BuildContext context, {
  required int userId,
  required String rol,
  CalendarService servicio = const CalendarService(),
  Future<bool> Function(Uri uri)? abrirEnlace,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _HojaSincronizacion(userId: userId, rol: rol, servicio: servicio, abrirEnlace: abrirEnlace),
    );

class _HojaSincronizacion extends StatefulWidget {
  const _HojaSincronizacion({required this.userId, required this.rol, required this.servicio, this.abrirEnlace});
  final int userId;
  final String rol;
  final CalendarService servicio;
  final Future<bool> Function(Uri uri)? abrirEnlace;

  @override
  State<_HojaSincronizacion> createState() => _HojaSincronizacionState();
}

class _HojaSincronizacionState extends State<_HojaSincronizacion> {
  FeedInfo? _info;
  bool _ocupado = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final i = await widget.servicio.feedStatus(widget.userId, widget.rol);
      if (mounted) setState(() { _info = i; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _crear() async {
    setState(() { _ocupado = true; _error = null; });
    try {
      final url = await widget.servicio.createFeed(widget.userId, widget.rol);
      if (mounted) setState(() { _info = FeedInfo(active: true, url: url); _ocupado = false; });
    } catch (e) {
      if (mounted) setState(() { _ocupado = false; _error = e.toString(); });
    }
  }

  Future<void> _revocar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('¿Dejar de compartir?', style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        content: const Text('Tu calendario dejará de actualizarse en las aplicaciones donde lo agregaste.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Dejar de compartir')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() { _ocupado = true; _error = null; });
    try {
      await widget.servicio.revokeFeed(widget.userId, widget.rol);
      if (mounted) setState(() { _info = const FeedInfo(active: false); _ocupado = false; });
    } catch (e) {
      if (mounted) setState(() { _ocupado = false; _error = e.toString(); });
    }
  }

  Future<void> _abrir(Uri uri) async {
    final abrir = widget.abrirEnlace ?? (Uri u) => launchUrl(u, mode: LaunchMode.externalApplication);
    var ok = false;
    try { ok = await abrir(uri); } catch (_) {}
    if (!ok && mounted) setState(() => _error = 'No se pudo abrir la aplicación. Copia el enlace y agrégalo manualmente.');
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final i = _info;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(22, 0, 22, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Semantics(
            header: true,
            child: Text('Ver GESACAD en tu calendario', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 6),
          Text(
            'Suscríbete y tus entregas, reuniones y evaluaciones aparecerán en Google Calendar, '
            'Outlook o Apple Calendar, con avisos un día y tres horas antes. Se actualiza solo.',
            style: GoogleFonts.poppins(fontSize: 12.5, color: t.muted, height: 1.45),
          ),
          const SizedBox(height: 14),
          if (i == null && _error == null)
            const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()))
          else if (i != null && !i.active)
            AppButton(
              label: 'Crear mi enlace de suscripción',
              icon: Icons.link_rounded,
              reaction: IconReaction.pop,
              expand: true,
              loading: _ocupado,
              onPressed: _ocupado ? null : _crear,
            )
          else if (i != null && i.url == null)
            ..._sinUrl()
          else if (i != null)
            ..._conUrl(i.url!),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Semantics(
                liveRegion: true,
                child: Text(_error!, style: GoogleFonts.poppins(fontSize: 12.5, color: t.danger, fontWeight: FontWeight.w600)),
              ),
            ),
        ]),
      ),
    );
  }

  List<Widget> _sinUrl() => [
        Text(
          'Ya tienes un enlace activo, creado en otro dispositivo. Por seguridad no se puede volver a mostrar. '
          'Si lo necesitas aquí, genera uno nuevo (el anterior dejará de funcionar).',
          style: GoogleFonts.poppins(fontSize: 12.5, height: 1.45),
        ),
        const SizedBox(height: 12),
        AppButton(label: 'Generar un enlace nuevo', icon: Icons.refresh_rounded, expand: true, loading: _ocupado, onPressed: _ocupado ? null : _crear),
        const SizedBox(height: 8),
        AppButton(label: 'Dejar de compartir', icon: Icons.link_off_rounded, style: AppButtonStyle.danger, expand: true, onPressed: _ocupado ? null : _revocar),
      ];

  List<Widget> _conUrl(String url) {
    final t = context.tokens;
    return [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: t.glass,
          borderRadius: BorderRadius.circular(AppTokens.radiusControl),
          border: Border.all(color: t.glassBorder),
        ),
        child: Row(children: [
          Expanded(child: SelectableText(url, maxLines: 2, style: GoogleFonts.robotoMono(fontSize: 11.5))),
          AnimatedIconButton(
            tooltip: 'Copiar enlace de suscripción',
            icon: Icons.copy_rounded,
            reaction: IconReaction.pop,
            onPressed: () {
              Clipboard.setData(ClipboardData(text: url));
              setState(() => _error = null);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                behavior: SnackBarBehavior.floating,
                content: Text('Enlace copiado.', style: GoogleFonts.poppins(color: Colors.white)),
              ));
            },
          ),
        ]),
      ),
      const SizedBox(height: 6),
      Text('Es personal: quien lo tenga puede ver tu calendario. No lo compartas.',
          style: GoogleFonts.poppins(fontSize: 11.5, color: t.warning, fontWeight: FontWeight.w600)),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        AppButton(label: 'Google Calendar', icon: Icons.calendar_month_rounded, style: AppButtonStyle.tonal, height: 42,
            onPressed: () => _abrir(CalendarService.googleSubscribeUri(url))),
        AppButton(label: 'Outlook', icon: Icons.mail_rounded, style: AppButtonStyle.tonal, height: 42,
            onPressed: () => _abrir(CalendarService.outlookSubscribeUri(url))),
        AppButton(label: 'Apple / otras', icon: Icons.phone_iphone_rounded, style: AppButtonStyle.tonal, height: 42,
            onPressed: () => _abrir(CalendarService.appleSubscribeUri(url))),
      ]),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(
          child: AppButton(label: 'Generar uno nuevo', icon: Icons.refresh_rounded, style: AppButtonStyle.outline, height: 42,
              loading: _ocupado, onPressed: _ocupado ? null : _crear),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: AppButton(label: 'Dejar de compartir', icon: Icons.link_off_rounded, style: AppButtonStyle.danger, height: 42,
              onPressed: _ocupado ? null : _revocar),
        ),
      ]),
    ];
  }
}
