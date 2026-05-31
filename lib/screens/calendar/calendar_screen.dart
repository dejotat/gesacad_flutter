import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:table_calendar/table_calendar.dart';
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

  const CalendarEvent({
    required this.title,
    required this.type,
    this.description,
    this.course,
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
    _events   = _buildDefaultEvents();
    _loadActivitiesFromBackend();
    _cardAnim.forward();
  }

  @override
  void dispose() {
    _cardAnim.dispose();
    super.dispose();
  }

  /// Construye eventos predeterminados (demo académico).
  Map<DateTime, List<CalendarEvent>> _buildDefaultEvents() {
    final now = DateTime.now();
    return {
      _norm(now): [
        const CalendarEvent(
            title: 'Clase de Cálculo',
            type: EventType.class_,
            course: 'Cálculo Diferencial'),
      ],
      _norm(now.add(const Duration(days: 2))): [
        const CalendarEvent(
            title: 'Entrega Taller 2',
            type: EventType.assignment,
            description: 'Sección 4.1 a 4.5',
            course: 'Sistemas de Info'),
        const CalendarEvent(
            title: 'Quiz Lógica',
            type: EventType.exam,
            course: 'Lógica de Programación'),
      ],
      _norm(now.add(const Duration(days: 5))): [
        const CalendarEvent(
            title: 'Parcial 1 — Cálculo',
            type: EventType.exam,
            description: 'Capítulos 1, 2 y 3',
            course: 'Cálculo Diferencial'),
      ],
      _norm(now.add(const Duration(days: 7))): [
        const CalendarEvent(
            title: 'Feria de Emprendimiento',
            type: EventType.event,
            description: 'Auditorio principal — 8am a 5pm'),
      ],
      _norm(now.add(const Duration(days: 10))): [
        const CalendarEvent(
            title: 'Proyecto final — BD',
            type: EventType.assignment,
            course: 'Bases de Datos'),
      ],
      _norm(now.add(const Duration(days: 14))): [
        const CalendarEvent(
            title: 'Festivo universitario',
            type: EventType.holiday),
      ],
    };
  }

  /// Inicializa los eventos — por ahora usa datos demo académicos.
  /// En producción se conecta al backend para sincronizar actividades reales.
  Future<void> _loadActivitiesFromBackend() async {
    // Los eventos ya se cargan en _buildDefaultEvents() en initState
    // Esta función puede extenderse para sincronizar con el backend
    if (mounted) setState(() => _loading = false);
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
