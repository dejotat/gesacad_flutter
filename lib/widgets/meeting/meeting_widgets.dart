import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/app_tokens.dart';
import '../../models/meeting_model.dart';
import '../../services/meeting_service.dart';
import '../ui/ui.dart';
import '../eval/eval_widgets.dart' show HexMedallion;

String _hora(DateTime d) => DateFormat('dd/MM/yyyy HH:mm').format(d);

/// Tarjeta de reunión virtual del curso (CU-09).
///
/// - **Estudiante** ([puedeGestionar] = false): aparece solo cuando el docente inició o
///   programó una reunión; "Unirse" abre la sala. Se actualiza sola cada [cadaSegundos].
/// - **Docente** ([puedeGestionar] = true): siempre visible. Sin reunión ofrece
///   "Iniciar reunión virtual"; con reunión muestra "Entrar", "Copiar enlace" y "Terminar".
class CourseMeetingCard extends StatefulWidget {
  const CourseMeetingCard({
    super.key,
    required this.courseId,
    required this.puedeGestionar,
    this.servicio = const MeetingService(),
    this.cadaSegundos = 30,
    this.abrirEnlace,
  });

  final int courseId;
  final bool puedeGestionar;
  final MeetingService servicio;
  final int cadaSegundos;

  /// Para pruebas; por defecto abre el enlace en la app/navegador externo.
  final Future<bool> Function(Uri uri)? abrirEnlace;

  @override
  State<CourseMeetingCard> createState() => _CourseMeetingCardState();
}

class _CourseMeetingCardState extends State<CourseMeetingCard> {
  Meeting? _reunion;
  bool _cargando = true;
  bool _ocupado = false;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _cargar();
    _timer = Timer.periodic(Duration(seconds: widget.cadaSegundos), (_) => _cargar(silencioso: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _cargar({bool silencioso = false}) async {
    try {
      final m = await widget.servicio.current(widget.courseId);
      if (mounted) setState(() { _reunion = m; _cargando = false; _error = null; });
    } catch (_) {
      // Sin red: se conserva lo último que se vio, sin molestar.
      if (mounted && !silencioso) setState(() => _cargando = false);
    }
  }

  void _aviso(String texto, {bool error = false}) {
    final t = context.tokens;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: error ? t.danger : t.success,
      content: Text(texto, style: GoogleFonts.poppins(color: Colors.white)),
    ));
  }

  Future<void> _entrar(Meeting m) async {
    final abrir = widget.abrirEnlace ??
        (Uri u) => launchUrl(u, mode: LaunchMode.externalApplication);
    var ok = false;
    try { ok = await abrir(Uri.parse(m.url)); } catch (_) {}
    if (!ok && mounted) {
      unawaited(Clipboard.setData(ClipboardData(text: m.url)));
      _aviso('No se pudo abrir el enlace. Lo copié: pégalo en tu navegador.', error: true);
    }
  }

  void _copiar(Meeting m) {
    unawaited(Clipboard.setData(ClipboardData(text: m.url)));
    _aviso('Enlace copiado. Compártelo por donde prefieras.');
  }

  Future<void> _iniciar() async {
    final m = await showModalBottomSheet<Meeting>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _HojaNuevaReunion(courseId: widget.courseId, servicio: widget.servicio),
    );
    if (m != null && mounted) {
      setState(() => _reunion = m);
      _aviso(m.isLive ? 'Reunión iniciada. Los estudiantes ya la ven en su curso.' : 'Reunión programada.');
    }
  }

  Future<void> _terminar() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('¿Terminar la reunión?', style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        content: const Text('Dejará de aparecer a los estudiantes. Quienes ya estén dentro pueden seguir en la sala.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Terminar')),
        ],
      ),
    );
    if (confirmar != true) return;
    setState(() { _ocupado = true; _error = null; });
    try {
      await widget.servicio.end(widget.courseId);
      if (mounted) setState(() { _reunion = null; _ocupado = false; });
    } catch (e) {
      if (mounted) setState(() { _ocupado = false; _error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = _reunion;
    if (_cargando && m == null) return const SizedBox.shrink();
    if (m == null && !widget.puedeGestionar) return const SizedBox.shrink();
    final t = context.tokens;
    final acento = [t.success, t.info];

    if (m == null) {
      // Docente sin reunión: invitación a iniciar una.
      return Padding(
        padding: const EdgeInsets.fromLTRB(AppTokens.pagePadding, 12, AppTokens.pagePadding, 0),
        child: AppCard(
          blur: false,
          child: Row(children: [
            HexMedallion(PhosphorIconsFill.videoCamera, colors: acento, size: 40, orbit: false, motion: IconMotion.float),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Reunión virtual', style: GoogleFonts.poppins(fontSize: 14.5, fontWeight: FontWeight.w700)),
                Text('Habla con tu curso por videollamada',
                    style: GoogleFonts.poppins(fontSize: 12, color: t.muted)),
              ]),
            ),
            AppButton(
              label: 'Iniciar',
              icon: PhosphorIconsFill.videoCamera,
              reaction: IconReaction.pop,
              height: 40,
              onPressed: _iniciar,
            ),
          ]),
        ),
      );
    }

    final enVivo = m.isLive;
    final color = enVivo ? t.success : t.warning;
    final puedeEntrar = enVivo || widget.puedeGestionar;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppTokens.pagePadding, 12, AppTokens.pagePadding, 0),
      child: Semantics(
        container: true,
        label: '${enVivo ? "Reunión en curso" : "Reunión programada"}: ${m.title}, con ${m.teacherName}',
        child: AppCard(
          blur: false,
          tint: color,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              HexMedallion(PhosphorIconsFill.videoCamera, colors: [color, t.info], size: 40, orbit: false,
                  motion: enVivo ? IconMotion.pulse : IconMotion.none),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(10)),
                      child: Text(enVivo ? 'EN CURSO' : 'PROGRAMADA',
                          style: GoogleFonts.poppins(
                              fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: color)),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(m.providerName,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(fontSize: 11, color: t.muted)),
                    ),
                  ]),
                  const SizedBox(height: 3),
                  Text(m.title,
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700)),
                  Text(
                    m.scheduledAt != null && !enVivo
                        ? '${_hora(m.scheduledAt!)} · ${m.teacherName}'
                        : 'Docente: ${m.teacherName}',
                    style: GoogleFonts.poppins(fontSize: 12, color: t.muted),
                  ),
                ]),
              ),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: AppButton(
                  label: puedeEntrar ? 'Unirse a la reunión' : 'Aún no empieza',
                  icon: PhosphorIconsFill.signIn,
                  reaction: IconReaction.nudge,
                  height: 44,
                  expand: true,
                  onPressed: puedeEntrar ? () => _entrar(m) : null,
                ),
              ),
              if (widget.puedeGestionar) ...[
                const SizedBox(width: 8),
                AnimatedIconButton(
                  tooltip: 'Copiar enlace de la reunión',
                  icon: PhosphorIconsRegular.copy,
                  reaction: IconReaction.pop,
                  onPressed: () => _copiar(m),
                ),
                AnimatedIconButton(
                  tooltip: 'Terminar la reunión',
                  icon: PhosphorIconsRegular.stopCircle,
                  reaction: IconReaction.shake,
                  onPressed: _ocupado ? null : _terminar,
                ),
              ],
            ]),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Semantics(
                  liveRegion: true,
                  child: Text(_error!,
                      style: GoogleFonts.poppins(fontSize: 12.5, color: t.danger, fontWeight: FontWeight.w600)),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

/// Hoja para iniciar o programar una reunión: sala automática o enlace propio.
class _HojaNuevaReunion extends StatefulWidget {
  const _HojaNuevaReunion({required this.courseId, required this.servicio});
  final int courseId;
  final MeetingService servicio;

  @override
  State<_HojaNuevaReunion> createState() => _HojaNuevaReunionState();
}

class _HojaNuevaReunionState extends State<_HojaNuevaReunion> {
  final _titulo = TextEditingController(text: 'Reunión de clase');
  final _enlace = TextEditingController();
  bool _propio = false;
  bool _programar = false;
  DateTime? _fecha;
  bool _enviando = false;
  String? _error;

  @override
  void dispose() {
    _titulo.dispose();
    _enlace.dispose();
    super.dispose();
  }

  Future<void> _elegirFecha() async {
    final ahora = DateTime.now();
    final dia = await showDatePicker(
      context: context,
      initialDate: _fecha ?? ahora,
      firstDate: ahora,
      lastDate: ahora.add(const Duration(days: 90)),
    );
    if (dia == null || !mounted) return;
    final hora = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_fecha ?? ahora.add(const Duration(hours: 1))),
    );
    if (hora == null || !mounted) return;
    setState(() => _fecha = DateTime(dia.year, dia.month, dia.day, hora.hour, hora.minute));
  }

  Future<void> _enviar() async {
    if (_propio && _enlace.text.trim().isEmpty) {
      setState(() => _error = 'Pega el enlace de Google Meet, Zoom o Teams.');
      return;
    }
    if (_programar && (_fecha == null || _fecha!.isBefore(DateTime.now()))) {
      setState(() => _error = 'Elige una fecha y hora futuras.');
      return;
    }
    setState(() { _enviando = true; _error = null; });
    try {
      final m = await widget.servicio.start(
        widget.courseId,
        title: _titulo.text,
        url: _propio ? _enlace.text : null,
        scheduledAt: _programar ? _fecha : null,
      );
      if (mounted) Navigator.pop(context, m);
    } catch (e) {
      if (mounted) setState(() { _enviando = false; _error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Semantics(
            header: true,
            child: Text('Nueva reunión virtual',
                style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _titulo,
            maxLength: 80,
            decoration: const InputDecoration(labelText: 'Título', counterText: ''),
          ),
          const SizedBox(height: 12),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, icon: Icon(PhosphorIconsRegular.magicWand), label: Text('Sala automática')),
              ButtonSegment(value: true, icon: Icon(PhosphorIconsRegular.link), label: Text('Mi enlace')),
            ],
            selected: {_propio},
            onSelectionChanged: (s) => setState(() { _propio = s.first; _error = null; }),
          ),
          const SizedBox(height: 8),
          if (_propio)
            TextField(
              controller: _enlace,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Enlace de Google Meet, Zoom o Teams',
                hintText: 'https://meet.google.com/abc-defg-hij',
              ),
            )
          else
            Text('Se crea una sala privada de Jitsi Meet: sin cuentas ni instalación. '
                'Funciona en el navegador y en el celular.',
                style: GoogleFonts.poppins(fontSize: 12, color: t.muted, height: 1.4)),
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _programar,
            title: Text('Programar para más tarde', style: GoogleFonts.poppins(fontSize: 14)),
            onChanged: (v) => setState(() { _programar = v; _error = null; }),
          ),
          if (_programar)
            Align(
              alignment: Alignment.centerLeft,
              child: AppButton(
                label: _fecha == null ? 'Elegir fecha y hora' : _hora(_fecha!),
                icon: PhosphorIconsRegular.calendarPlus,
                style: AppButtonStyle.tonal,
                height: 42,
                onPressed: _elegirFecha,
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Semantics(
                liveRegion: true,
                child: Text(_error!,
                    style: GoogleFonts.poppins(fontSize: 12.5, color: t.danger, fontWeight: FontWeight.w600)),
              ),
            ),
          const SizedBox(height: 16),
          AppButton(
            label: _programar ? 'Programar reunión' : 'Iniciar ahora',
            icon: _programar ? PhosphorIconsFill.calendarCheck : PhosphorIconsFill.videoCamera,
            reaction: IconReaction.pop,
            expand: true,
            loading: _enviando,
            onPressed: _enviando ? null : _enviar,
          ),
        ]),
      ),
    );
  }
}
