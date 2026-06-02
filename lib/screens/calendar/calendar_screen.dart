import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../services/api_service.dart';
import '../../services/settings_service.dart';
import '../../widgets/animated_logo.dart';
import '../../widgets/talk_widget.dart';

/// Tipo de evento del calendario académico.
enum EventType { exam, assignment, class_, holiday, event, notification }

extension EventTypeExt on EventType {
  Color get color {
    switch (this) {
      case EventType.exam:         return const Color(0xFFE53935);
      case EventType.assignment:   return const Color(0xFF1565C0);
      case EventType.class_:       return const Color(0xFF2E7D32);
      case EventType.holiday:      return const Color(0xFF6A1B9A);
      case EventType.event:        return const Color(0xFFE65100);
      case EventType.notification: return const Color(0xFF0097A7);
    }
  }

  List<Color> get gradient {
    switch (this) {
      case EventType.exam:         return [const Color(0xFFE53935), const Color(0xFFFF7043)];
      case EventType.assignment:   return [const Color(0xFF1565C0), const Color(0xFF06B6D4)];
      case EventType.class_:       return [const Color(0xFF2E7D32), const Color(0xFF66BB6A)];
      case EventType.holiday:      return [const Color(0xFF6A1B9A), const Color(0xFFAB47BC)];
      case EventType.event:        return [const Color(0xFFE65100), const Color(0xFFFFB300)];
      case EventType.notification: return [const Color(0xFF0097A7), const Color(0xFF26C6DA)];
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
    }
  }
}

/// Modelo de evento del calendario.
class CalendarEvent {
  final String title;
  final EventType type;
  final String? description;
  final String? course;
  final String? hora;        // HH:mm — solo para recordatorios personales
  final bool isReminder;     // true = recordatorio personal del usuario

  const CalendarEvent({
    required this.title,
    required this.type,
    this.description,
    this.course,
    this.hora,
    this.isReminder = false,
  });
}

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
  CalendarFormat _format = CalendarFormat.month;
  bool _loading = false;
  int _userId = 0;

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
    super.dispose();
  }

  /// Inicia el calendario: carga userId, recordatorios, festivos y actividades.
  Future<void> _initCalendar() async {
    final prefs = await SharedPreferences.getInstance();
    _userId = prefs.getInt('userId') ?? 0;
    // Festivos siempre visibles (sin red)
    final base = _festivosColombia();
    if (mounted) setState(() => _events = base);
    // Recordatorios del usuario actual
    await _loadRecordatorios();
    // Actividades del backend
    await _loadActivitiesFromBackend();
  }

  /// Festivos oficiales de Colombia 2026 — hardcoded, no requieren conexión.
  Map<DateTime, List<CalendarEvent>> _festivosColombia() {
    final lista = {
      DateTime(2026,  1,  1): 'Año Nuevo',
      DateTime(2026,  1, 12): 'Reyes Magos',
      DateTime(2026,  3, 23): 'Día de San José',
      DateTime(2026,  4,  2): 'Jueves Santo',
      DateTime(2026,  4,  3): 'Viernes Santo',
      DateTime(2026,  5,  1): 'Día del Trabajo',
      DateTime(2026,  5, 18): 'Ascensión del Señor',
      DateTime(2026,  6,  8): 'Corpus Christi',
      DateTime(2026,  6, 29): 'San Pedro y San Pablo',
      DateTime(2026,  7, 20): 'Independencia de Colombia',
      DateTime(2026,  8,  7): 'Batalla de Boyacá',
      DateTime(2026,  8, 17): 'Asunción de la Virgen',
      DateTime(2026, 10, 12): 'Día de la Raza',
      DateTime(2026, 11,  2): 'Todos los Santos',
      DateTime(2026, 11, 16): 'Independencia de Cartagena',
      DateTime(2026, 12,  8): 'Inmaculada Concepción',
      DateTime(2026, 12, 25): 'Navidad',
    };
    return {
      for (final e in lista.entries)
        _norm(e.key): [CalendarEvent(
          title: e.value,
          type: EventType.holiday,
          description: 'Festivo oficial Colombia 2026',
        )],
    };
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
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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
                    color: Colors.grey.shade300,
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
                      fontSize: 12, color: Colors.grey.shade500)),
                const SizedBox(height: 16),
                TextField(
                  controller: tituloCtrl,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'Ej: Entregar tesis, Reunión, Examen...',
                    hintStyle: GoogleFonts.poppins(fontSize: 13),
                    prefixIcon: const Icon(Icons.notifications_rounded,
                        color: Color(0xFF0097A7)),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                          color: Color(0xFF0097A7), width: 2),
                    ),
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
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(children: [
                      const Icon(Icons.access_time_rounded,
                          color: Color(0xFF0097A7), size: 20),
                      const SizedBox(width: 10),
                      Text('Hora: $horaSeleccionada',
                          style: GoogleFonts.poppins(fontSize: 13)),
                      const Spacer(),
                      Icon(Icons.edit_rounded,
                          size: 16, color: Colors.grey.shade400),
                    ]),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      if (tituloCtrl.text.trim().isEmpty) return;
                      Navigator.pop(ctx);
                      _saveRecordatorio(tituloCtrl.text, horaSeleccionada);
                    },
                    icon: const Icon(Icons.save_rounded),
                    label: Text('Guardar recordatorio',
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0097A7),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
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

  /// Carga las actividades reales de todos los cursos del usuario
  /// y las inserta en el mapa [_events] del calendario.
  ///
  /// Flujo:
  /// 1. Leer userId y rol desde SharedPreferences.
  /// 2. Obtener cursos del usuario con [ApiService.getMyCourses].
  /// 3. Por cada curso obtener actividades con [ApiService.getActivities].
  /// 4. Mapear cada actividad a un [CalendarEvent] usando la fecha de cierre.
  Future<void> _loadActivitiesFromBackend() async {
    try {
      // Leer datos de sesión para obtener los cursos correctos del usuario
      final prefs  = await SharedPreferences.getInstance();
      final userId = prefs.getInt('userId') ?? 0;

      if (userId == 0) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      // Obtener los cursos en los que está matriculado el usuario
      final cursos = await ApiService().getMyCourses(userId);

      // Mapa temporal para acumular eventos antes de llamar a setState
      final nuevosMapa = <DateTime, List<CalendarEvent>>{};

      for (final curso in cursos) {
        // Obtener todas las actividades del curso
        final actividades = await ApiService().getActivities(curso.id);

        for (final act in actividades) {
          // Parsear la fecha de cierre para colocar el evento en el día correcto
          DateTime? fechaCierre;
          try {
            fechaCierre = DateTime.parse(act.closingDate);
          } catch (_) {
            continue; // Ignorar actividades con fecha inválida
          }

          // Extraer la hora de cierre para mostrarla en la descripción
          final horaCierre =
              '${fechaCierre.hour.toString().padLeft(2, '0')}:'
              '${fechaCierre.minute.toString().padLeft(2, '0')}';

          // Construir la descripción con tipo y hora de cierre
          final descripcion =
              '${_tipoLabel(act.type)} · Cierre: $horaCierre';

          // Crear el evento del calendario a partir de la actividad
          final evento = CalendarEvent(
            title:       act.tittle,
            type:        _tipoAEventType(act.type),
            description: descripcion,
            course:      curso.name,
          );

          // Agregar el evento al día de cierre (normalizando a medianoche)
          final diaCierre = _norm(fechaCierre);
          nuevosMapa.putIfAbsent(diaCierre, () => []).add(evento);
        }
      }

      // Mezclar actividades con festivos y recordatorios ya cargados
      // (no reemplazar _events entero para no perder festivos ni recordatorios)
      if (mounted) {
        setState(() {
          for (final entry in nuevosMapa.entries) {
            _events.putIfAbsent(entry.key, () => []).addAll(entry.value);
          }
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  DateTime _norm(DateTime d) => DateTime(d.year, d.month, d.day);

  List<CalendarEvent> _eventsFor(DateTime day) =>
      _events[_norm(day)] ?? [];

  /// Al seleccionar un día, animar la entrada de los eventos.
  void _onDaySelected(DateTime sel, DateTime foc) {
    setState(() { _selected = sel; _focused = foc; });
    _cardAnim.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final themeType  = AppSettings.currentTheme.value;
    final primary    = themeType.primaryColor;
    final eventos    = _eventsFor(_selected);

    return Scaffold(
      backgroundColor: themeType.backgroundColor,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: themeType.gradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        leading: IconButton(
          tooltip: 'Regresar',
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(children: [
          const LogoWatermark(size: 26, opacity: 0.35),
          const SizedBox(width: 8),
          Text('Calendario Académico',
              style: GoogleFonts.poppins(
                  color: Colors.white, fontWeight: FontWeight.w700)),
        ]),
        centerTitle: true,
        actions: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2)),
              ),
            ),
        ],
      ),
      body: Stack(children: [
        // Logo de fondo decorativo
        Positioned(bottom: -30, right: -30,
            child: LogoWatermark(size: 240, opacity: 0.04)),

        Column(children: [
          // Leyenda premium de tipos de evento
          _buildLegend(primary),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: Column(children: [
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
        ]),
      ]),
    );
  }

  // ── Leyenda ──────────────────────────────────────────────────────────────

  Widget _buildLegend(Color primary) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: EventType.values.map((t) => TalkWidget(
            label: 'Tipo de evento: ${t.label}',
            child: Container(
              margin: const EdgeInsets.only(right: 10),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: t.gradient),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(
                    color: t.color.withOpacity(0.3),
                    blurRadius: 6, offset: const Offset(0, 2))],
              ),
              child: Row(children: [
                Icon(t.icon, color: Colors.white, size: 12),
                const SizedBox(width: 5),
                Text(t.label, style: GoogleFonts.poppins(
                    color: Colors.white, fontSize: 10,
                    fontWeight: FontWeight.w700)),
              ]),
            ),
          )).toList(),
        ),
      ),
    );
  }

  // ── Calendario premium ────────────────────────────────────────────────────

  Widget _buildCalendar(AppThemeType themeType, Color primary) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: primary.withOpacity(0.12),
              blurRadius: 20, offset: const Offset(0, 6)),
          BoxShadow(color: Colors.black.withOpacity(0.05),
              blurRadius: 10, offset: const Offset(0, 2)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Column(children: [
          // Header del calendario con gradiente
          Container(
            padding: const EdgeInsets.symmetric(vertical: 6),
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
            lastDay: DateTime.utc(2027, 12, 31),
            focusedDay: _focused,
            selectedDayPredicate: (d) => isSameDay(d, _selected),
            calendarFormat: _format,
            eventLoader: _eventsFor,
            startingDayOfWeek: StartingDayOfWeek.monday,
            onDaySelected: _onDaySelected,
            onFormatChanged: (f) => setState(() => _format = f),
            onPageChanged: (f) => setState(() => _focused = f),
            headerStyle: HeaderStyle(
              titleCentered: true,
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
                  color: const Color(0xFF1A1A2E)),
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
                  fontSize: 13, color: const Color(0xFF1A1A2E)),
              weekendTextStyle: GoogleFonts.poppins(
                  color: Colors.red.shade400, fontSize: 13),
              outsideTextStyle: GoogleFonts.poppins(
                  color: Colors.grey.shade300, fontSize: 13),
              // Remover bordes del rango
              rangeHighlightColor: primary.withOpacity(0.1),
              cellMargin: const EdgeInsets.all(4),
            ),
            daysOfWeekStyle: DaysOfWeekStyle(
              weekdayStyle: GoogleFonts.poppins(
                  fontSize: 12, fontWeight: FontWeight.w700,
                  color: Colors.grey.shade500),
              weekendStyle: GoogleFonts.poppins(
                  fontSize: 12, fontWeight: FontWeight.w700,
                  color: Colors.red.shade300),
            ),
            // Builder personalizado para los marcadores de eventos por tipo
            calendarBuilders: CalendarBuilders(
              markerBuilder: (ctx, day, events) {
                if (events.isEmpty) return null;
                // Mostrar punto de color por cada tipo de evento único
                final tipos = events.map((e) => e.type).toSet().toList();
                return Positioned(
                  bottom: 2,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: tipos.take(3).map((t) => Container(
                      width: 5, height: 5,
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(
                        color: t.color, shape: BoxShape.circle,
                        boxShadow: [BoxShadow(
                          color: t.color.withOpacity(0.5), blurRadius: 3)],
                      ),
                    )).toList(),
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

    return Row(children: [
      Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: themeType.gradient),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [BoxShadow(
              color: primary.withOpacity(0.3),
              blurRadius: 8, offset: const Offset(0, 3))],
        ),
        child: const Icon(Icons.calendar_today_rounded,
            color: Colors.white, size: 16),
      ),
      const SizedBox(width: 10),
      TalkWidget(
        label: '$label. ${ eventos.isEmpty ? "Sin eventos." : "${eventos.length} evento${eventos.length == 1 ? "" : "s"}." }',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: GoogleFonts.poppins(
              fontSize: 15, fontWeight: FontWeight.w700,
              color: primary)),
          if (eventos.isNotEmpty)
            Text('${eventos.length} evento${eventos.length == 1 ? "" : "s"}',
                style: GoogleFonts.poppins(
                    fontSize: 11, color: Colors.grey.shade400)),
        ]),
      ),
      const Spacer(),
      if (eventos.isNotEmpty)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: themeType.gradient),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(
                color: primary.withOpacity(0.3), blurRadius: 6)],
          ),
          child: Text('${eventos.length} evento${eventos.length == 1 ? "" : "s"}',
              style: GoogleFonts.poppins(
                  color: Colors.white, fontSize: 10,
                  fontWeight: FontWeight.w700)),
        ),
      const SizedBox(width: 8),
      // Botón para agregar recordatorio personal en el día seleccionado
      Tooltip(
        message: 'Agregar recordatorio',
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: _mostrarModalRecordatorio,
          child: Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: const Color(0xFF0097A7).withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.add_alert_rounded,
                color: Color(0xFF0097A7), size: 20),
          ),
        ),
      ),
    ]);
  }

  // ── Tarjeta de evento ─────────────────────────────────────────────────────

  Widget _buildEventCard(CalendarEvent ev, int idx) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 250 + idx * 80),
      curve: Curves.easeOutBack,
      builder: (_, v, child) => Transform.translate(
        offset: Offset(0, 16 * (1 - v)),
        child: Opacity(opacity: v.clamp(0.0, 1.0), child: child),
      ),
      child: TalkWidget(
        label: '${ev.type.label}: ${ev.title}.'
            '${ev.course != null ? " Curso: ${ev.course}." : ""}'
            '${ev.description != null ? " ${ev.description}." : ""}',
        highlightOnHover: true,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: ev.type.color.withOpacity(0.2), width: 1.5),
            boxShadow: [BoxShadow(
                color: ev.type.color.withOpacity(0.08),
                blurRadius: 12, offset: const Offset(0, 4))],
          ),
          child: Row(children: [
            // Barra lateral de color
            Container(
              width: 5,
              height: 80,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: ev.type.gradient,
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(18),
                    bottomLeft: Radius.circular(18)),
              ),
            ),
            const SizedBox(width: 14),
            // Ícono con gradiente
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: ev.type.gradient),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(
                    color: ev.type.color.withOpacity(0.3),
                    blurRadius: 8, offset: const Offset(0, 3))],
              ),
              child: Icon(ev.type.icon, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            // Contenido
            Expanded(child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: ev.type.color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(ev.type.label,
                          style: GoogleFonts.poppins(
                              fontSize: 9, color: ev.type.color,
                              fontWeight: FontWeight.w700)),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Text(ev.title, style: GoogleFonts.poppins(
                      fontSize: 13, fontWeight: FontWeight.w700,
                      color: const Color(0xFF1A1A2E))),
                  if (ev.course != null)
                    Text(ev.course!, style: GoogleFonts.poppins(
                        fontSize: 11, color: ev.type.color,
                        fontWeight: FontWeight.w500)),
                  if (ev.description != null)
                    Text(ev.description!, style: GoogleFonts.poppins(
                        fontSize: 10, color: Colors.grey.shade400),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            )),
            // Botón eliminar — solo visible en recordatorios personales
            if (ev.isReminder)
              IconButton(
                tooltip: 'Eliminar recordatorio',
                icon: Icon(Icons.delete_outline_rounded,
                    color: Colors.red.shade300, size: 20),
                onPressed: () => _eliminarRecordatorio(ev),
              )
            else
              const SizedBox(width: 14),
          ]),
        ),
      ),
    );
  }

  // ── Sin eventos ───────────────────────────────────────────────────────────

  Widget _buildEmptyDay(Color primary) {
    return TalkWidget(
      label: 'No hay eventos para este día. Selecciona otro día del calendario.',
      child: Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.shade100),
        ),
        child: Column(children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: primary.withOpacity(0.07),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.event_busy_rounded,
                size: 40, color: primary.withOpacity(0.4)),
          ),
          const SizedBox(height: 14),
          Text('Sin eventos', style: GoogleFonts.poppins(
              fontSize: 15, fontWeight: FontWeight.w700,
              color: Colors.grey.shade500)),
          const SizedBox(height: 6),
          Text('No hay actividades programadas\npara este día',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 12, color: Colors.grey.shade400, height: 1.5)),
        ]),
      ),
    );
  }
}
