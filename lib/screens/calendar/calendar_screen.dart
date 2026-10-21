import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../services/settings_service.dart';
import '../../widgets/talk_widget.dart';
import '../../models/calendar_models.dart';
import '../../services/calendar_service.dart';
import '../../utils/colombia_holidays.dart';
import 'calendar_widgets.dart';

/// Tipo de evento del calendario académico.
import '../../config/app_tokens.dart';
import '../../widgets/ui/ui.dart';

enum EventType { exam, assignment, class_, holiday, event, notification, meeting, evaluation }

extension EventTypeExt on EventType {
  Color get color {
    switch (this) {
      case EventType.exam:         return const Color(0xFFDC2626);
      case EventType.assignment:   return const Color(0xFF2563EB);
      case EventType.class_:       return const Color(0xFF16A34A);
      case EventType.holiday:      return const Color(0xFF7C3AED);
      case EventType.event:        return const Color(0xFFD97706);
      case EventType.notification: return const Color(0xFF0891B2);
      case EventType.meeting:      return const Color(0xFFDB2777);
      case EventType.evaluation:   return const Color(0xFF4F46E5);
    }
  }

  List<Color> get gradient {
    switch (this) {
      case EventType.exam:         return [const Color(0xFFB91C1C), const Color(0xFFEF4444)];
      case EventType.assignment:   return [const Color(0xFF1D4ED8), const Color(0xFF3B82F6)];
      case EventType.class_:       return [const Color(0xFF15803D), const Color(0xFF22C55E)];
      case EventType.holiday:      return [const Color(0xFF6D28D9), const Color(0xFF8B5CF6)];
      case EventType.event:        return [const Color(0xFFB45309), const Color(0xFFF59E0B)];
      case EventType.notification: return [const Color(0xFF0E7490), const Color(0xFF06B6D4)];
      case EventType.meeting:      return [const Color(0xFFBE185D), const Color(0xFFEC4899)];
      case EventType.evaluation:   return [const Color(0xFF4338CA), const Color(0xFF6366F1)];
    }
  }

  IconData get icon {
    switch (this) {
      case EventType.exam:         return Icons.quiz_rounded;
      case EventType.assignment:   return Icons.assignment_rounded;
      case EventType.class_:       return Icons.school_rounded;
      case EventType.holiday:      return Icons.celebration_rounded;
      case EventType.event:        return Icons.event_rounded;
      case EventType.notification: return Icons.notifications_rounded;
      case EventType.meeting:      return Icons.videocam_rounded;
      case EventType.evaluation:   return Icons.insights_rounded;
    }
  }

  /// Cada tipo de evento tiene su propio movimiento de ícono.
  IconMotion get motion {
    switch (this) {
      case EventType.exam:         return IconMotion.heartbeat;
      case EventType.assignment:   return IconMotion.write;
      case EventType.class_:       return IconMotion.bounce;
      case EventType.holiday:      return IconMotion.tada;
      case EventType.event:        return IconMotion.swing;
      case EventType.notification: return IconMotion.ring;
      case EventType.meeting:      return IconMotion.pulse;
      case EventType.evaluation:   return IconMotion.float;
    }
  }

  String get label {
    switch (this) {
      case EventType.exam:         return 'Examen';
      case EventType.assignment:   return 'Entrega';
      case EventType.class_:       return 'Clase';
      case EventType.holiday:      return 'Festivo';
      case EventType.event:        return 'Evento';
      case EventType.notification: return 'Aviso';
      case EventType.meeting:      return 'Reunión';
      case EventType.evaluation:   return 'Evaluación';
    }
  }
}

/// Modelo de evento del calendario.
class CalendarEvent {
  final String title;
  final EventType type;
  final String? description;
  final String? course;
  final String? hora;        // HH:mm
  final bool isReminder;     // true = recordatorio personal del usuario

  /// Evento que viene del servidor (actividad, reunión o evaluación); null en
  /// festivos y recordatorios personales.
  final CalEvent? source;

  const CalendarEvent({
    required this.title,
    required this.type,
    this.description,
    this.course,
    this.hora,
    this.isReminder = false,
    this.source,
  });
}

/// Cómo se muestra el calendario.
enum _Vista { mes, semana, agenda }

/// Calendario académico premium — diseño moderno con eventos sincronizados.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen>
    with TickerProviderStateMixin {
  DateTime _focused  = DateTime.now();
  DateTime _selected = DateTime.now();
  bool _loading = false;
  int _userId = 0;
  String _userRol = 'Student';
  final CalendarService _servicio = const CalendarService();

  /// Eventos del servidor por día (se reemplazan completos en cada carga) y en bruto.
  Map<DateTime, List<CalendarEvent>> _srv = {};
  List<CalEvent> _srvRaw = [];
  bool _sinConexion = false;
  String? _errorCarga;

  _Vista _vista = _Vista.mes;
  bool _buscando = false;
  String _busqueda = '';
  String? _cursoFiltro;
  final _buscadorCtrl = TextEditingController();

  /// Tipo elegido en la leyenda (null = todos).
  EventType? _legendFilter;

  // Mapa de eventos: fecha → lista de eventos
  late Map<DateTime, List<CalendarEvent>> _events;

  // Animación de entrada de las tarjetas de eventos
  late AnimationController _cardAnim;
  late Animation<double>   _cardFade;

  @override
  void initState() {
    super.initState();
    _cardAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _cardFade = CurvedAnimation(parent: _cardAnim, curve: Curves.easeOut);
    _events = _buildDefaultEvents();
    _initCalendar();
    _cardAnim.forward();
  }

  @override
  void dispose() {
    _cardAnim.dispose();
    _buscadorCtrl.dispose();
    super.dispose();
  }

  /// Inicia el calendario: carga userId, recordatorios, festivos y eventos del servidor.
  Future<void> _initCalendar() async {
    final prefs = await SharedPreferences.getInstance();
    _userId = prefs.getInt('userId') ?? 0;
    _userRol = prefs.getString('userRol') ?? 'Student';
    // Festivos siempre visibles (sin red)
    final base = _festivosColombia();
    if (mounted) setState(() => _events = base);
    // Recordatorios del usuario actual
    await _loadRecordatorios();
    // Actividades, reuniones y evaluaciones del servidor
    await _cargarServidor();
  }

  /// Festivos oficiales de Colombia, calculados para cada año del calendario
  /// (2024-2030) con la Ley Emiliani y la Pascua: sin lista fija ni conexión.
  Map<DateTime, List<CalendarEvent>> _festivosColombia() {
    final mapa = <DateTime, List<CalendarEvent>>{};
    for (var anio = 2024; anio <= 2030; anio++) {
      for (final e in festivosColombia(anio).entries) {
        mapa[_norm(e.key)] = [
          CalendarEvent(
            title: e.value,
            type: EventType.holiday,
            description: 'Festivo oficial Colombia $anio',
          ),
        ];
      }
    }
    return mapa;
  }

  // ── Recordatorios personales ──────────────────────────────────────────────

  /// Carga los recordatorios del usuario actual desde SharedPreferences.
  /// Clave aislada por userId → cada usuario ve solo los suyos.
  Future<void> _loadRecordatorios() async {
    if (_userId == 0) return;
    final prefs = await SharedPreferences.getInstance();
    final raw   = prefs.getString('recordatorios_$_userId') ?? '[]';
    final lista = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    for (final r in lista) {
      final fecha = _norm(DateTime.parse(r['fecha'] as String));
      final ev = CalendarEvent(
        title:      r['titulo'] as String,
        type:       EventType.notification,
        description: r['hora'] as String?,
        hora:       r['hora'] as String?,
        isReminder: true,
      );
      if (mounted) {
        setState(() => _events.putIfAbsent(fecha, () => []).add(ev));
      }
    }
  }

  /// Guarda un recordatorio nuevo en SharedPreferences y lo agrega al mapa.
  Future<void> _saveRecordatorio(String titulo, String hora) async {
    if (_userId == 0 || titulo.trim().isEmpty) return;
    final prefs  = await SharedPreferences.getInstance();
    final clave  = 'recordatorios_$_userId';
    final raw    = prefs.getString(clave) ?? '[]';
    final lista  = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    final fechaStr = '${_selected.year}-'
        '${_selected.month.toString().padLeft(2,'0')}-'
        '${_selected.day.toString().padLeft(2,'0')}';
    lista.add({'titulo': titulo.trim(), 'hora': hora, 'fecha': fechaStr});
    await prefs.setString(clave, jsonEncode(lista));

    final ev = CalendarEvent(
      title:      titulo.trim(),
      type:       EventType.notification,
      description: hora,
      hora:       hora,
      isReminder: true,
    );
    if (mounted) {
      setState(() => _events.putIfAbsent(_norm(_selected), () => []).add(ev));
    }
  }

  /// Elimina un recordatorio por título y fecha desde SharedPreferences y el mapa.
  Future<void> _eliminarRecordatorio(CalendarEvent ev) async {
    if (_userId == 0) return;
    final prefs  = await SharedPreferences.getInstance();
    final clave  = 'recordatorios_$_userId';
    final raw    = prefs.getString(clave) ?? '[]';
    final lista  = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    final fechaStr = '${_selected.year}-'
        '${_selected.month.toString().padLeft(2,'0')}-'
        '${_selected.day.toString().padLeft(2,'0')}';
    lista.removeWhere((r) =>
        r['titulo'] == ev.title &&
        r['fecha']  == fechaStr &&
        r['hora']   == ev.hora);
    await prefs.setString(clave, jsonEncode(lista));

    if (mounted) {
      setState(() {
        final key = _norm(_selected);
        _events[key]?.removeWhere((e) =>
            e.isReminder && e.title == ev.title && e.hora == ev.hora);
        if (_events[key]?.isEmpty == true) _events.remove(key);
      });
    }
  }

  /// Modal para agregar un recordatorio personal en la fecha seleccionada.
  void _mostrarModalRecordatorio() {
    final tituloCtrl = TextEditingController();
    String horaSeleccionada = TimeOfDay.now().format(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
            decoration: BoxDecoration(
              color: Theme.of(ctx).bottomSheetTheme.backgroundColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border.all(color: ctx.tokens.glassBorder),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle
                Center(child: Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: ctx.tokens.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                )),
                Text('Nuevo recordatorio',
                    style: GoogleFonts.poppins(
                        fontSize: 17, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                  '${_selected.day.toString().padLeft(2,'0')}/'
                  '${_selected.month.toString().padLeft(2,'0')}/'
                  '${_selected.year}',
                  style: GoogleFonts.poppins(
                      fontSize: 12, color: ctx.tokens.muted)),
                const SizedBox(height: 16),
                TextField(
                  controller: tituloCtrl,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'Ej: Entregar tesis, Reunión, Examen...',
                    hintStyle: GoogleFonts.poppins(fontSize: 13),
                    prefixIcon: const Icon(Icons.notifications_rounded,
                        color: Color(0xFF0891B2)),
                  ),
                ),
                const SizedBox(height: 12),
                // Selector de hora
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: ctx,
                      initialTime: TimeOfDay.now(),
                      helpText: 'Hora del recordatorio',
                    );
                    if (picked != null) {
                      setModal(() {
                        horaSeleccionada =
                            '${picked.hour.toString().padLeft(2,'0')}:'
                            '${picked.minute.toString().padLeft(2,'0')}';
                      });
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: ctx.tokens.border),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(children: [
                      const Icon(Icons.access_time_rounded,
                          color: Color(0xFF0891B2), size: 20),
                      const SizedBox(width: 10),
                      Text('Hora: $horaSeleccionada',
                          style: GoogleFonts.poppins(fontSize: 13)),
                      const Spacer(),
                      Icon(Icons.edit_rounded,
                          size: 16, color: ctx.tokens.muted),
                    ]),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: AppButton(
                    label: 'Guardar recordatorio',
                    icon: Icons.save_rounded,
                    reaction: IconReaction.pop,
                    expand: true,
                    onPressed: () {
                      if (tituloCtrl.text.trim().isEmpty) return;
                      Navigator.pop(ctx);
                      _saveRecordatorio(tituloCtrl.text, horaSeleccionada);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Punto de partida: festivos visibles desde el primer frame.
  Map<DateTime, List<CalendarEvent>> _buildDefaultEvents() =>
      _festivosColombia();

  // ── Mapa de tipo de actividad → EventType del calendario ─────────────────

  /// Convierte el tipo de actividad del backend al tipo de evento del calendario.
  /// - 'midterm'  → exam       (rojo — representa un examen/parcial)
  /// - 'project'  → assignment (azul — representa una entrega de proyecto)
  /// - 'resource' → notification (turquesa — representa un recurso/aviso)
  /// - otro       → event      (naranja — tipo genérico)
  EventType _tipoAEventType(String tipo) {
    switch (tipo) {
      case 'midterm':  return EventType.exam;
      case 'project':  return EventType.assignment;
      case 'resource': return EventType.notification;
      default:         return EventType.event;
    }
  }

  /// Devuelve la etiqueta legible del tipo de actividad para incluir
  /// en la descripción del evento del calendario.
  String _tipoLabel(String tipo) {
    switch (tipo) {
      case 'midterm':  return 'Parcial';
      case 'project':  return 'Proyecto';
      case 'resource': return 'Recurso';
      default:         return 'Actividad';
    }
  }

  /// Carga los eventos del servidor: actividades con SU estado, reuniones y evaluaciones.
  /// Una sola consulta (antes eran una por curso). Sin conexión usa la última copia.
  Future<void> _cargarServidor() async {
    if (_userId == 0) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (mounted) setState(() { _loading = true; _errorCarga = null; });
    try {
      final hoy = DateTime.now().toUtc();
      final r = await _servicio.events(_userId, _userRol,
          desde: hoy.subtract(const Duration(days: 90)),
          hasta: hoy.add(const Duration(days: 270)));
      if (!mounted) return;
      setState(() {
        _srvRaw = r.events;
        _srv = _agrupar(r.events);
        _sinConexion = r.fromCache;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _errorCarga = e.toString(); });
    }
  }

  Map<DateTime, List<CalendarEvent>> _agrupar(List<CalEvent> lista) {
    final mapa = <DateTime, List<CalendarEvent>>{};
    for (final e in lista) {
      mapa.putIfAbsent(e.dia, () => []).add(_aEvento(e));
    }
    return mapa;
  }

  CalendarEvent _aEvento(CalEvent e) {
    final peso = (e.weighting ?? 0) > 0 ? ' · ${(e.weighting! * 100).round()} %' : '';
    switch (e.kind) {
      case CalKind.activity:
        final tipo = e.activityType ?? 'other';
        return CalendarEvent(
          title: e.title,
          type: _tipoAEventType(tipo),
          description: '${_tipoLabel(tipo)} · ${tipo == 'resource' ? 'Disponible' : 'Cierra ${e.hora}'}$peso',
          course: e.courseName,
          hora: e.hora,
          source: e,
        );
      case CalKind.meeting:
        return CalendarEvent(
          title: e.title, type: EventType.meeting,
          description: 'Hora: ${e.hora}', course: e.courseName, hora: e.hora, source: e,
        );
      case CalKind.evaluation:
        return CalendarEvent(
          title: e.title, type: EventType.evaluation,
          description: 'Cierra ${e.hora}', hora: e.hora, source: e,
        );
    }
  }

  DateTime _norm(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Festivos, recordatorios y eventos del servidor de un día, con la búsqueda y el
  /// filtro de curso aplicados, ordenados por hora (lo que no tiene hora va primero).
  List<CalendarEvent> _eventsFor(DateTime day) {
    final k = _norm(day);
    final lista = [...?_events[k], ...?_srv[k]].where(_pasaFiltros).toList()
      ..sort((a, b) => (a.hora ?? '').compareTo(b.hora ?? ''));
    return lista;
  }

  bool _pasaFiltros(CalendarEvent e) {
    // Festivos y recordatorios no pertenecen a un curso: siempre se conservan.
    if (_cursoFiltro != null && e.course != null && e.course != _cursoFiltro) return false;
    if (_busqueda.isNotEmpty) {
      final texto = '${e.title} ${e.course ?? ''} ${e.type.label} ${e.description ?? ''}'.toLowerCase();
      if (!texto.contains(_busqueda)) return false;
    }
    return true;
  }

  /// Al seleccionar un día, animar la entrada de los eventos.
  void _onDaySelected(DateTime sel, DateTime foc) {
    setState(() { _selected = sel; _focused = foc; });
    _cardAnim.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final themeType  = AppSettings.currentTheme.value;
    final primary    = themeType.primaryColor;
    final eventos    = _eventsFor(_selected)
        .where((e) => _legendFilter == null || e.type == _legendFilter)
        .toList();
    final cursos = {for (final e in _srvRaw) if (e.courseName != null) e.courseName!}.toList()..sort();

    return Scaffold(
      appBar: AppBar(
        leading: AnimatedIconButton(
          tooltip: 'Regresar',
          icon: Icons.arrow_back_rounded,
          reaction: IconReaction.nudge,
          onPressed: () => Navigator.pop(context),
        ),
        title: _buscando
            ? TextField(
                controller: _buscadorCtrl,
                autofocus: true,
                cursorColor: Colors.white,
                style: GoogleFonts.poppins(color: Colors.white, fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'Buscar evento, curso o tipo',
                  hintStyle: GoogleFonts.poppins(color: Colors.white70, fontSize: 14),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                ),
                onChanged: (v) => setState(() => _busqueda = v.trim().toLowerCase()),
              )
            : const Row(mainAxisSize: MainAxisSize.min, children: [
                MotionIcon(Icons.calendar_month_rounded,
                    size: 22, motion: IconMotion.swing),
                SizedBox(width: 8),
                Flexible(child: Text('Calendario Académico', overflow: TextOverflow.ellipsis)),
              ]),
        actions: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Center(
                child: SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2)),
              ),
            ),
          AnimatedIconButton(
            tooltip: _buscando ? 'Cerrar búsqueda' : 'Buscar',
            icon: _buscando ? Icons.close_rounded : Icons.search_rounded,
            reaction: IconReaction.pop,
            onPressed: () => setState(() {
              _buscando = !_buscando;
              if (!_buscando) { _busqueda = ''; _buscadorCtrl.clear(); }
            }),
          ),
          if (_userId != 0)
            AnimatedIconButton(
              tooltip: 'Ver en mi calendario (Google, Outlook, Apple)',
              icon: Icons.ios_share_rounded,
              reaction: IconReaction.nudge,
              onPressed: () => mostrarSincronizacion(context, userId: _userId, rol: _userRol),
            ),
          AnimatedIconButton(
            tooltip: 'Ir a hoy',
            icon: Icons.today_rounded,
            reaction: IconReaction.flip,
            onPressed: () {
              final hoy = DateTime.now();
              setState(() { _focused = hoy; _selected = hoy; });
              _cardAnim.forward(from: 0);
            },
          ),
        ],
      ),
      body: LogoBackdrop(child:
        Center(child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(children: [
          // Leyenda premium de tipos de evento
          _buildLegend(primary),
          _buildVistas(cursos),
          if (_sinConexion)
            _aviso(Icons.wifi_off_rounded,
                'Sin conexión: se muestra lo último que se sincronizó.', context.tokens.warning),
          if (_errorCarga != null && _srvRaw.isEmpty)
            _aviso(Icons.error_outline_rounded, _errorCarga!, context.tokens.danger, reintentar: _cargarServidor),

          Expanded(
            child: _vista == _Vista.agenda
                ? _buildAgenda(primary)
                : RefreshIndicator(
                    onRefresh: _cargarServidor,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      child: Column(children: [
                        if (_userId != 0 && _srvRaw.isNotEmpty) ...[
                          ProximoVencimientoCard(
                            eventos: _srvRaw,
                            onTap: (e) {
                              setState(() { _selected = e.dia; _focused = e.dia; });
                              _cardAnim.forward(from: 0);
                            },
                          ),
                          const SizedBox(height: 12),
                          CargaSemanalCard(
                            dia: _selected,
                            seleccionado: _selected,
                            hoy: DateTime.now(),
                            conteo: _conteoSemana(),
                            onDia: (d) => _onDaySelected(d, d),
                          ),
                          const SizedBox(height: 12),
                        ],
                        // Tarjeta del calendario premium
                        _buildCalendar(themeType, primary),
                        const SizedBox(height: 16),

                        // Header del día seleccionado
                        _buildDayHeader(eventos, primary, themeType),
                        const SizedBox(height: 12),

                        // Lista de eventos del día
                        if (eventos.isEmpty)
                          _buildEmptyDay(primary)
                        else
                          FadeTransition(
                            opacity: _cardFade,
                            child: Column(
                              children: eventos.asMap().entries.map((e) =>
                                  _buildEventCard(e.value, e.key)).toList(),
                            ),
                          ),
                      ]),
                    ),
                  ),
          ),
        ]),
        )),
      ),
    );
  }

  /// Eventos del servidor por día de la semana mostrada (para las barras de carga).
  Map<DateTime, int> _conteoSemana() {
    final lunes = _norm(_selected.subtract(Duration(days: _selected.weekday - 1)));
    return {
      for (var i = 0; i < 7; i++)
        DateTime(lunes.year, lunes.month, lunes.day + i): _eventsFor(DateTime(lunes.year, lunes.month, lunes.day + i))
            .where((e) => e.source != null)
            .length,
    };
  }

  Widget _aviso(IconData icono, String texto, Color color, {VoidCallback? reintentar}) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Semantics(
          liveRegion: true,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppTokens.radiusControl),
              border: Border.all(color: color.withValues(alpha: 0.4)),
            ),
            child: Row(children: [
              Icon(icono, color: color, size: 18),
              const SizedBox(width: 10),
              Expanded(child: Text(texto, style: GoogleFonts.poppins(fontSize: 12.5))),
              if (reintentar != null)
                TextButton(onPressed: reintentar, child: const Text('Reintentar')),
            ]),
          ),
        ),
      );

  /// Selector de vista (Mes / Semana / Agenda) y filtro por curso.
  Widget _buildVistas(List<String> cursos) {
    final primary = Theme.of(context).colorScheme.primary;
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(children: [
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<_Vista>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: _Vista.mes, icon: Icon(Icons.calendar_view_month_rounded, size: 18), label: Text('Mes')),
              ButtonSegment(value: _Vista.semana, icon: Icon(Icons.calendar_view_week_rounded, size: 18), label: Text('Semana')),
              ButtonSegment(value: _Vista.agenda, icon: Icon(Icons.view_agenda_rounded, size: 18), label: Text('Agenda')),
            ],
            selected: {_vista},
            onSelectionChanged: (s) {
              setState(() => _vista = s.first);
              _cardAnim.forward(from: 0);
            },
          ),
        ),
        if (cursos.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: SizedBox(
              height: 34,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                for (final c in [null, ...cursos])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(c ?? 'Todos los cursos', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600)),
                      selected: _cursoFiltro == c,
                      selectedColor: primary.withValues(alpha: 0.18),
                      side: BorderSide(color: _cursoFiltro == c ? primary : t.glassBorder),
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => setState(() => _cursoFiltro = c),
                    ),
                  ),
              ]),
            ),
          ),
      ]),
    );
  }

  /// Agenda: lo que viene en los próximos 60 días, agrupado por día.
  Widget _buildAgenda(Color primary) {
    final hoy = _norm(DateTime.now());
    final limite = hoy.add(const Duration(days: 60));
    final dias = {..._events.keys, ..._srv.keys}
        .where((d) => !d.isBefore(hoy) && d.isBefore(limite))
        .toList()
      ..sort();
    final grupos = <DateTime, List<CalendarEvent>>{};
    for (final d in dias) {
      final l = _eventsFor(d).where((e) => _legendFilter == null || e.type == _legendFilter).toList();
      if (l.isNotEmpty) grupos[d] = l;
    }
    if (grupos.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [_buildEmptyDay(primary, mensaje: 'No hay eventos en los próximos 60 días')],
      );
    }
    return RefreshIndicator(
      onRefresh: _cargarServidor,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          for (final g in grupos.entries) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 14, 0, 8),
              child: Semantics(
                header: true,
                child: Text(
                  '${_cuentaRegresiva(g.key)} · ${fechaLarga(g.key, conHora: false)}'.toUpperCase(),
                  style: GoogleFonts.poppins(
                      fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.1, color: context.tokens.muted),
                ),
              ),
            ),
            for (final e in g.value.asMap().entries) _buildEventCard(e.value, e.key, dia: g.key),
          ],
        ],
      ),
    );
  }

  // ── Leyenda ──────────────────────────────────────────────────────────────

  Widget _buildLegend(Color primary) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: EventType.values.map((t) {
            final sel = _legendFilter == t;
            final dim = _legendFilter != null && !sel;
            return Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Semantics(
                button: true,
                selected: sel,
                label: 'Filtrar por ${t.label}',
                excludeSemantics: true,
                onTap: () => setState(() => _legendFilter = sel ? null : t),
                child: Pressable(
                  pressedScale: 0.9,
                  onTap: () => setState(() => _legendFilter = sel ? null : t),
                  child: GestureDetector(
                    onTap: () {
                      setState(() => _legendFilter = sel ? null : t);
                      _cardAnim.forward(from: 0);
                    },
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 220),
                      opacity: dim ? 0.38 : 1,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOutBack,
                        padding: EdgeInsets.symmetric(
                            horizontal: sel ? 14 : 10, vertical: 6),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: t.gradient),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: sel
                              ? [BoxShadow(
                                  color: t.color.withValues(alpha: 0.5),
                                  blurRadius: 14, offset: const Offset(0, 4))]
                              : null,
                        ),
                        child: Row(children: [
                          MotionIcon(t.icon,
                              color: Colors.white, size: 14, motion: t.motion),
                          const SizedBox(width: 5),
                          Text(t.label, style: GoogleFonts.poppins(
                              color: Colors.white, fontSize: 12,
                              fontWeight: FontWeight.w700)),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // ── Calendario premium ────────────────────────────────────────────────────

  Widget _buildCalendar(AppThemeType themeType, Color primary) {
    final tk = context.tokens;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return AppCard(
      radius: 24,
      padding: const EdgeInsets.only(bottom: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Column(children: [
          // Franja de acento del tema
          Container(
            height: 4,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: themeType.gradient,
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
            ),
          ),
          TableCalendar<CalendarEvent>(
            locale: 'es_ES',
            firstDay: DateTime.utc(2024, 1, 1),
            lastDay: DateTime.utc(2030, 12, 31),
            focusedDay: _focused,
            selectedDayPredicate: (d) => isSameDay(d, _selected),
            calendarFormat: _vista == _Vista.semana ? CalendarFormat.week : CalendarFormat.month,
            availableCalendarFormats: const {CalendarFormat.month: 'Mes', CalendarFormat.week: 'Semana'},
            eventLoader: _eventsFor,
            startingDayOfWeek: StartingDayOfWeek.monday,
            onDaySelected: _onDaySelected,
            onPageChanged: (f) => setState(() => _focused = f),
            headerStyle: HeaderStyle(
              titleCentered: true,
              formatButtonVisible: false,
              formatButtonDecoration: BoxDecoration(
                gradient: LinearGradient(colors: themeType.gradient),
                borderRadius: BorderRadius.circular(20),
              ),
              formatButtonTextStyle: GoogleFonts.poppins(
                  color: Colors.white, fontSize: 11,
                  fontWeight: FontWeight.w600),
              formatButtonShowsNext: false,
              titleTextStyle: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700, fontSize: 16,
                  color: onSurface),
              leftChevronIcon: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.chevron_left_rounded,
                    color: primary, size: 20),
              ),
              rightChevronIcon: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.chevron_right_rounded,
                    color: primary, size: 20),
              ),
            ),
            calendarStyle: CalendarStyle(
              // Día de hoy — círculo con gradiente
              todayDecoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: themeType.gradient.map(
                      (c) => c.withOpacity(0.3)).toList()),
                shape: BoxShape.circle,
              ),
              // Día seleccionado — gradiente completo
              selectedDecoration: BoxDecoration(
                gradient: LinearGradient(colors: themeType.gradient),
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(
                  color: primary.withOpacity(0.4),
                  blurRadius: 8, offset: const Offset(0, 3),
                )],
              ),
              // Marcadores de eventos (un punto por tipo diferente)
              markerDecoration: BoxDecoration(
                color: primary, shape: BoxShape.circle),
              markersMaxCount: 3,
              markerSize: 5,
              markerMargin: const EdgeInsets.symmetric(horizontal: 0.5),
              todayTextStyle: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700, color: primary),
              selectedTextStyle: GoogleFonts.poppins(
                  fontWeight: FontWeight.w800, color: Colors.white),
              defaultTextStyle: GoogleFonts.poppins(
                  fontSize: 13, color: onSurface),
              weekendTextStyle: GoogleFonts.poppins(
                  color: tk.danger, fontSize: 13),
              outsideTextStyle: GoogleFonts.poppins(
                  color: tk.muted.withValues(alpha: 0.5), fontSize: 13),
              // Remover bordes del rango
              rangeHighlightColor: primary.withOpacity(0.1),
              cellMargin: const EdgeInsets.all(4),
            ),
            daysOfWeekStyle: DaysOfWeekStyle(
              weekdayStyle: GoogleFonts.poppins(
                  fontSize: 12, fontWeight: FontWeight.w700,
                  color: tk.muted),
              weekendStyle: GoogleFonts.poppins(
                  fontSize: 12, fontWeight: FontWeight.w700,
                  color: tk.danger),
            ),
            // Builder personalizado para los marcadores de eventos por tipo
            calendarBuilders: CalendarBuilders(
              // Mes con transición: el título se desliza al cambiar de página.
              headerTitleBuilder: (ctx, date) => AnimatedSwitcher(
                duration: const Duration(milliseconds: 320),
                transitionBuilder: (c, a) => FadeTransition(
                  opacity: a,
                  child: SlideTransition(
                    position: Tween(
                            begin: const Offset(0, 0.4), end: Offset.zero)
                        .animate(a),
                    child: c,
                  ),
                ),
                child: Text(
                  _mesAnio(date),
                  key: ValueKey('${date.year}-${date.month}'),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700, fontSize: 16,
                      color: onSurface),
                ),
              ),
              selectedBuilder: (ctx, day, focused) => _CeldaDia(
                key: ValueKey('sel-$day'),
                day: day,
                gradient: themeType.gradient,
                glow: primary,
              ),
              todayBuilder: (ctx, day, focused) => _CeldaHoy(
                day: day,
                color: primary,
              ),
              markerBuilder: (ctx, day, events) {
                if (events.isEmpty) return null;
                // Mostrar punto de color por cada tipo de evento único
                final tipos = events.map((e) => e.type).toSet().toList();
                return Positioned(
                  bottom: 2,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < tipos.take(3).length; i++)
                        _MarcadorPop(color: tipos[i].color, delay: i * 70),
                    ],
                  ),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  // ── Header del día seleccionado ───────────────────────────────────────────

  String _mesAnio(DateTime d) {
    const m = ['Enero','Febrero','Marzo','Abril','Mayo','Junio','Julio',
               'Agosto','Septiembre','Octubre','Noviembre','Diciembre'];
    return '${m[d.month - 1]} ${d.year}';
  }

  Widget _buildDayHeader(List<CalendarEvent> eventos, Color primary,
      AppThemeType themeType) {
    final meses = ['enero','febrero','marzo','abril','mayo','junio',
                   'julio','agosto','septiembre','octubre','noviembre','diciembre'];
    final dias  = ['lunes','martes','miércoles','jueves',
                   'viernes','sábado','domingo'];
    final diaNom = dias[_selected.weekday - 1];
    final mesNom = meses[_selected.month - 1];
    final label  = '${diaNom[0].toUpperCase()}${diaNom.substring(1)}, '
        '${_selected.day} de $mesNom';
    final conteo =
        '${eventos.length} evento${eventos.length == 1 ? "" : "s"}';

    return Row(children: [
      // Ficha de fecha: el número gira al cambiar de día.
      ExcludeSemantics(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 420),
          switchInCurve: Curves.easeOutBack,
          transitionBuilder: (c, a) => ScaleTransition(
            scale: a,
            child: RotationTransition(
              turns: Tween(begin: -0.08, end: 0.0).animate(a),
              child: c,
            ),
          ),
          child: Container(
            key: ValueKey(_norm(_selected)),
            width: 52, height: 56,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: themeType.gradient,
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(
                  color: primary.withValues(alpha: 0.38),
                  blurRadius: 12, offset: const Offset(0, 5))],
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(mesNom.substring(0, 3).toUpperCase(),
                  style: GoogleFonts.poppins(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 10, fontWeight: FontWeight.w700,
                      letterSpacing: 1)),
              Text('${_selected.day}',
                  style: GoogleFonts.poppins(
                      color: Colors.white, fontSize: 22,
                      fontWeight: FontWeight.w800, height: 1.05)),
            ]),
          ),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: TalkWidget(
          label: '$label. ${eventos.isEmpty ? "Sin eventos." : "$conteo."}',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: GoogleFonts.poppins(
                fontSize: 15, fontWeight: FontWeight.w700, color: primary)),
            Text(eventos.isEmpty ? 'Día libre' : conteo,
                style: GoogleFonts.poppins(
                    fontSize: 12, color: context.tokens.muted)),
          ]),
        ),
      ),
      // Recordatorio personal en el día seleccionado.
      AnimatedIconButton(
        tooltip: 'Agregar recordatorio',
        icon: Icons.add_alert_rounded,
        reaction: IconReaction.ring,
        color: const Color(0xFF0891B2),
        filled: false,
        onPressed: _mostrarModalRecordatorio,
      ),
    ]);
  }

  /// "Hoy", "Mañana", "En 3 días"… respecto de [dia] (por defecto el día seleccionado).
  String _cuentaRegresiva([DateTime? dia]) {
    final hoy = _norm(DateTime.now());
    final d = _norm(dia ?? _selected).difference(hoy).inDays;
    if (d == 0) return 'Hoy';
    if (d == 1) return 'Mañana';
    if (d == -1) return 'Ayer';
    return d > 0 ? 'En $d días' : 'Hace ${-d} días';
  }

  // ── Tarjeta de evento ─────────────────────────────────────────────────────

  Widget _buildEventCard(CalendarEvent ev, int idx, {DateTime? dia}) {
    final cuenta = _cuentaRegresiva(dia);
    final tk = context.tokens;
    final estado = ev.source?.estadoTexto;
    final estadoColor = ev.source?.estadoColor(tk.success, tk.warning, tk.danger, tk.info);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 300 + idx * 90),
      curve: Curves.easeOutBack,
      builder: (_, v, child) => Transform.translate(
        offset: Offset(0, 22 * (1 - v)),
        child: Opacity(opacity: v.clamp(0.0, 1.0), child: child),
      ),
      child: TalkWidget(
        label: '${ev.type.label}: ${ev.title}.'
            '${ev.course != null ? " Curso: ${ev.course}." : ""}'
            '${ev.description != null ? " ${ev.description}." : ""}',
        highlightOnHover: true,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: AppCard(
            blur: false,
            tint: ev.type.color,
            radius: 18,
            onTap: ev.source == null
                ? null
                : () => mostrarAccionesEvento(context, ev.source!, userId: _userId, rol: _userRol),
            padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
            child: Row(children: [
              IconMedallion(ev.type.icon,
                  size: 48,
                  colors: ev.type.gradient,
                  motion: ev.type.motion,
                  delay: Duration(milliseconds: 120 * idx)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(spacing: 6, runSpacing: 4, children: [
                      _pastilla(ev.type.label, ev.type.color),
                      _pastilla(cuenta, context.tokens.muted, soft: true),
                      if (estado != null) _pastilla(estado, estadoColor ?? context.tokens.muted),
                    ]),
                    const SizedBox(height: 6),
                    Text(ev.title, style: GoogleFonts.poppins(
                        fontSize: 13.5, fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onSurface)),
                    if (ev.course != null)
                      Text(ev.course!, style: GoogleFonts.poppins(
                          fontSize: 12, color: ev.type.color,
                          fontWeight: FontWeight.w500)),
                    if (ev.description != null)
                      Row(children: [
                        Icon(Icons.schedule_rounded,
                            size: 12, color: context.tokens.muted),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(ev.description!,
                              style: GoogleFonts.poppins(
                                  fontSize: 12, color: context.tokens.muted),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                      ]),
                  ],
                ),
              ),
              if (ev.isReminder)
                AnimatedIconButton(
                  tooltip: 'Eliminar recordatorio',
                  icon: Icons.delete_outline_rounded,
                  reaction: IconReaction.shake,
                  color: context.tokens.danger,
                  onPressed: () => _eliminarRecordatorio(ev),
                )
              else
                const SizedBox(width: 8),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _pastilla(String texto, Color c, {bool soft = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: c.withValues(alpha: soft ? 0.10 : 0.14),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(texto,
            style: GoogleFonts.poppins(
                fontSize: 11, color: c, fontWeight: FontWeight.w700)),
      );

  // ── Sin eventos ───────────────────────────────────────────────────────────

  Widget _buildEmptyDay(Color primary, {String mensaje = 'No hay actividades programadas\npara este día'}) {
    return TalkWidget(
      label: 'No hay eventos para este día. Selecciona otro día del calendario.',
      child: AppCard(
        padding: const EdgeInsets.all(28),
        child: Column(children: [
          Container(
            width: 88, height: 88,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                primary.withValues(alpha: 0.20),
                primary.withValues(alpha: 0.03),
              ]),
              border: Border.all(color: primary.withValues(alpha: 0.18)),
            ),
            child: Center(
              child: MotionIcon(Icons.beach_access_rounded,
                  size: 40, color: primary, glow: true, halo: true),
            ),
          ),
          const SizedBox(height: 14),
          Text('Día libre', style: GoogleFonts.poppins(
              fontSize: 15, fontWeight: FontWeight.w700,
              color: context.tokens.muted)),
          const SizedBox(height: 6),
          Text(mensaje,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 12, color: context.tokens.muted, height: 1.5)),
        ]),
      ),
    );
  }
}

/// Celda del día seleccionado: entra con rebote elástico y brilla.
class _CeldaDia extends StatelessWidget {
  const _CeldaDia({
    super.key,
    required this.day,
    required this.gradient,
    required this.glow,
  });
  final DateTime day;
  final List<Color> gradient;
  final Color glow;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.3, end: 1),
      duration: const Duration(milliseconds: 560),
      curve: Curves.elasticOut,
      builder: (_, v, child) => Transform.scale(scale: v, child: child),
      child: Container(
        margin: const EdgeInsets.all(4),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: gradient,
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
          boxShadow: [BoxShadow(
              color: glow.withValues(alpha: 0.5),
              blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: Text('${day.day}',
            style: GoogleFonts.poppins(
                fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white)),
      ),
    );
  }
}

/// Celda de hoy: anillo que late suavemente para ubicarse de un vistazo.
class _CeldaHoy extends StatefulWidget {
  const _CeldaHoy({required this.day, required this.color});
  final DateTime day;
  final Color color;

  @override
  State<_CeldaHoy> createState() => _CeldaHoyState();
}

class _CeldaHoyState extends State<_CeldaHoy>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2000));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Container(
        margin: EdgeInsets.all(4 - 2.5 * _c.value),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color.withValues(alpha: 0.12),
          border: Border.all(
            color: widget.color.withValues(alpha: 0.9 - 0.55 * _c.value),
            width: 1.6,
          ),
        ),
        child: Text('${widget.day.day}',
            style: GoogleFonts.poppins(
                fontSize: 13, fontWeight: FontWeight.w800, color: widget.color)),
      ),
    );
  }
}

/// Punto marcador de evento: aparece con un pequeño rebote.
class _MarcadorPop extends StatelessWidget {
  const _MarcadorPop({required this.color, this.delay = 0});
  final Color color;
  final int delay;

  @override
  Widget build(BuildContext context) {
    final total = 420 + delay;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      curve: Interval(delay / total, 1, curve: Curves.elasticOut),
      builder: (_, v, __) => Transform.scale(
        scale: v,
        child: Container(
          width: 6, height: 6,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            color: color, shape: BoxShape.circle,
            boxShadow: [BoxShadow(
                color: color.withValues(alpha: 0.55), blurRadius: 4)],
          ),
        ),
      ),
    );
  }
}
