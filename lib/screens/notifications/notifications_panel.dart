import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/activity_model.dart';
import '../../services/api_service.dart';

import '../../config/app_tokens.dart';
import '../../widgets/ui/ui.dart';

/// Modelo de notificación.
class AppNotification {
  final String id;
  final String title;
  final String body;
  final NotifType type;
  final DateTime time;
  bool isRead;

  AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.time,
    this.isRead = false,
  });
}

enum NotifType { activity, grade, announcement, event, system }

extension NotifTypeExt on NotifType {
  Color get color {
    switch (this) {
      case NotifType.activity:     return const Color(0xFF2563EB);
      case NotifType.grade:        return const Color(0xFF16A34A);
      case NotifType.announcement: return const Color(0xFFD97706);
      case NotifType.event:        return const Color(0xFF7C3AED);
      case NotifType.system:       return const Color(0xFF64748B);
    }
  }

  IconData get icon {
    switch (this) {
      case NotifType.activity:     return Icons.assignment_rounded;
      case NotifType.grade:        return Icons.grade_rounded;
      case NotifType.announcement: return Icons.campaign_rounded;
      case NotifType.event:        return Icons.event_rounded;
      case NotifType.system:       return Icons.info_rounded;
    }
  }

  /// Movimiento propio de cada tipo: el ícono "cuenta" de qué trata.
  IconMotion get motion {
    switch (this) {
      case NotifType.activity:     return IconMotion.write;
      case NotifType.grade:        return IconMotion.tada;
      case NotifType.announcement: return IconMotion.ring;
      case NotifType.event:        return IconMotion.swing;
      case NotifType.system:       return IconMotion.pulse;
    }
  }

  String get label {
    switch (this) {
      case NotifType.activity:     return 'Actividad';
      case NotifType.grade:        return 'Calificación';
      case NotifType.announcement: return 'Anuncio';
      case NotifType.event:        return 'Evento';
      case NotifType.system:       return 'Sistema';
    }
  }
}

/// Panel de notificaciones con datos reales del backend.
///
/// Para estudiantes: muestra actividades recientes de sus cursos y calificaciones recibidas.
/// Para profesores:  muestra actividades recientes en sus cursos.
class NotificationsPanel extends StatefulWidget {
  /// ID del usuario sesión activa. Si es 0 no se cargan datos del servidor.
  final int userId;

  /// Rol del usuario: 'Student', 'Teacher' o 'Admin'.
  final String userRol;

  const NotificationsPanel({
    super.key,
    this.userId = 0,
    this.userRol = 'Student',
  });

  @override
  State<NotificationsPanel> createState() => _NotificationsPanelState();
}

class _NotificationsPanelState extends State<NotificationsPanel>
    with SingleTickerProviderStateMixin {
  late AnimationController _anim;
  late Animation<double> _fade;

  List<AppNotification> _notifs = [];
  NotifType? _filter;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 350));
    _fade = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
    _anim.forward();
    _cargarNotificaciones();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  // ── Carga de notificaciones desde el backend ──────────────────────────────

  Future<void> _cargarNotificaciones() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });

    try {
      final notifs = <AppNotification>[];

      if (widget.userId > 0) {
        // El Admin obtiene todos los cursos del sistema para tener una
        // vista global. Student y Teacher solo ven sus propios cursos.
        final cursos = widget.userRol == 'Admin'
            ? await ApiService().getAllCourses()
            : await ApiService().getMyCourses(widget.userId);

        for (final curso in cursos) {
          try {
            final actividades = await ApiService().getActivities(curso.id);
            final ahora = DateTime.now();

            // ── Estudiante: actividades recientes + calificaciones ─────────
            if (widget.userRol == 'Student') {
              for (final act in actividades) {
                // Notificar actividades publicadas en los últimos 14 días
                DateTime? startDate;
                try { startDate = DateTime.parse(act.startDate); } catch (_) {}
                if (startDate != null) {
                  final diff = ahora.difference(startDate);
                  if (diff.inDays >= -1 && diff.inDays <= 14) {
                    notifs.add(AppNotification(
                      id: 'act_${act.id}',
                      title: 'Nueva actividad disponible',
                      body: '${_tipoLabel(act.type)} "${act.tittle}" en ${curso.name}. '
                          'Fecha límite: ${act.closingDate.split("T")[0]}',
                      type: NotifType.activity,
                      // Usar startDate para mostrar cuándo fue publicada la actividad.
                      // Así _timeAgo calcula el tiempo relativo real: '5 min', '2 h', '3 d', etc.
                      time: startDate,
                    ));
                  }
                }
              }
              // Calificaciones recibidas por el estudiante en este curso
              try {
                final notas = await ApiService().getGrades(curso.id, widget.userId);
                for (int i = 0; i < notas.length; i++) {
                  final nota = notas[i];
                  final gpa  = nota['GPA'];
                  if (gpa != null) {
                    final gpaParsed = double.tryParse(gpa.toString()) ?? 0.0;
                    // Usar dateResolution real para tiempo relativo correcto (Bug 2)
                    final drStr = nota['dateResolution']?.toString() ?? '';
                    final drTime = drStr.isNotEmpty
                        ? (ActivityModel.toCol(drStr))
                        : DateTime.now();
                    notifs.add(AppNotification(
                      id: 'grade_${curso.id}_$i',
                      title: 'Calificación publicada',
                      body: 'Tu entrega de "${nota['tittle'] ?? 'actividad'}" '
                          'en ${curso.name} fue calificada: '
                          '${gpaParsed.toStringAsFixed(2)} / 5.0 — '
                          '${gpaParsed >= 3.0 ? "Aprobado ✓" : "Reprobado"}',
                      type: NotifType.grade,
                      time: drTime,
                    ));
                  }
                }
              } catch (_) {}
            }

            // ── Profesor: entregas pendientes de calificar ────────────────
            if (widget.userRol == 'Teacher') {
              for (final act in actividades) {
                try {
                  final entregas = await ApiService().getResolutions(act.id);
                  final pendientes = entregas.where((e) =>
                      e['resolution'] != null &&
                      (e['resolution'] as String).isNotEmpty &&
                      e['GPA'] == null).toList();
                  if (pendientes.isNotEmpty) {
                    // Usar la dateResolution más reciente como timestamp (Bug 2)
                    DateTime notifTime = DateTime(2000);
                    for (final p in pendientes) {
                      final drStr = p['dateResolution']?.toString() ?? '';
                      if (drStr.isNotEmpty) {
                        final t = ActivityModel.toCol(drStr);
                        if (t.isAfter(notifTime)) notifTime = t;
                      }
                    }
                    if (notifTime.year == 2000) notifTime = DateTime.now();
                    notifs.add(AppNotification(
                      id: 'pending_${act.id}',
                      title: 'Entregas pendientes de calificar',
                      body: '${pendientes.length} '
                          '${pendientes.length == 1 ? "estudiante entregó" : "estudiantes entregaron"} '
                          '"${act.tittle}" en ${curso.name}.',
                      type: NotifType.activity,
                      time: notifTime,
                    ));
                  }
                } catch (_) {}
              }
            }

            // Admin no ve notificaciones académicas — solo eventos del sistema.
            // Sus notificaciones se cargan por separado fuera del loop de cursos.
          } catch (_) {}
        }

        // Admin: cargar eventos globales del sistema desde el backend
        if (widget.userRol == 'Admin') {
          try {
            final adminNotifs = await ApiService()
                .getNotifications(widget.userId, 'Admin');
            for (final n in adminNotifs) {
              notifs.add(AppNotification(
                id:    'admin_${n['id'] ?? notifs.length}',
                title: _tituloAdminLog(n['title'] as String? ?? ''),
                body:  n['body']  as String? ?? '',
                type:  NotifType.system,
                time:  DateTime.tryParse(n['time'] as String? ?? '') ?? DateTime.now(),
              ));
            }
          } catch (_) {}
        }

        // Ordenar de más reciente a más antiguo
        notifs.sort((a, b) => b.time.compareTo(a.time));
      }

      if (mounted) setState(() { _notifs = notifs; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  /// Etiqueta de grupo según qué tan reciente es la notificación.
  String _grupo(DateTime t) {
    final hoy = DateTime.now();
    final d0 = DateTime(hoy.year, hoy.month, hoy.day);
    final dias = d0.difference(DateTime(t.year, t.month, t.day)).inDays;
    if (dias <= 0) return 'Hoy';
    if (dias == 1) return 'Ayer';
    if (dias < 7) return 'Esta semana';
    return 'Anteriores';
  }

  /// Lista plana: cadenas (encabezados de grupo) y notificaciones.
  List<Object> _itemsAgrupados() {
    final lista = _filter == null
        ? _notifs
        : _notifs.where((n) => n.type == _filter).toList();
    final out = <Object>[];
    String? actual;
    for (final n in lista) {
      final g = _grupo(n.time);
      if (g != actual) {
        out.add(g);
        actual = g;
      }
      out.add(n);
    }
    return out;
  }

  int get _sinLeer => _notifs.where((n) => !n.isRead).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: AnimatedIconButton(
          tooltip: 'Regresar',
          icon: Icons.arrow_back_rounded,
          reaction: IconReaction.nudge,
          onPressed: () => Navigator.pop(context),
        ),
        title: const Row(mainAxisSize: MainAxisSize.min, children: [
          MotionIcon(Icons.notifications_rounded,
              size: 22, motion: IconMotion.ring),
          SizedBox(width: 8),
          Flexible(child: Text('Notificaciones', overflow: TextOverflow.ellipsis)),
        ]),
        actions: [
          AnimatedIconButton(
            icon: Icons.refresh_rounded,
            tooltip: 'Actualizar',
            reaction: IconReaction.spin,
            onPressed: _cargarNotificaciones,
          ),
          AnimatedIconButton(
            icon: Icons.done_all_rounded,
            tooltip: 'Marcar todas como leídas',
            reaction: IconReaction.pop,
            onPressed: () {
              for (final n in _notifs) { n.isRead = true; }
              setState(() {});
            },
          ),
        ],
      ),
      body: LogoBackdrop(
        child: FadeTransition(
          opacity: _fade,
          child: _loading
              ? _buildShimmer()
              : _error != null
                  ? _buildError()
                  : _notifs.isEmpty
                      ? _buildEmpty()
                      : _buildLista(),
        ),
      ),
    );
  }

  Widget _buildLista() {
    final items = _itemsAgrupados();
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: RefreshIndicator(
          onRefresh: _cargarNotificaciones,
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
                AppTokens.pagePadding, AppTokens.pagePadding,
                AppTokens.pagePadding, 40),
            itemCount: items.length + 2,
            itemBuilder: (_, i) {
              if (i == 0) return _buildResumen();
              if (i == 1) return _buildFiltros();
              final it = items[i - 2];
              if (it is String) return _buildGrupo(it);
              return _Entrada(
                // Escalonado: cada tarjeta entra un poco después de la anterior.
                delay: Duration(milliseconds: 50 * (i - 2).clamp(0, 8)),
                child: _buildNotifTile(it as AppNotification),
              );
            },
          ),
        ),
      ),
    );
  }

  /// Encabezado de cristal: campana que suena + cuántas hay sin leer.
  Widget _buildResumen() {
    final n = _sinLeer;
    final porTipo = <NotifType, int>{};
    for (final x in _notifs) {
      porTipo[x.type] = (porTipo[x.type] ?? 0) + 1;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: PageHeader(
        title: n == 0 ? 'Todo al día' : '$n sin leer',
        subtitle: n == 0
            ? 'No tienes notificaciones pendientes'
            : 'Toca una para ver el detalle o desliza para descartar',
        leading: ExcludeSemantics(
          child: Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.22),
              border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
            ),
            child: Center(
              child: MotionIcon(
                n == 0 ? Icons.notifications_active_outlined : Icons.notifications_active_rounded,
                color: Colors.white,
                size: 30,
                glow: true,
                halo: n > 0,
                motion: n == 0 ? IconMotion.float : IconMotion.ring,
              ),
            ),
          ),
        ),
        chips: [
          for (final e in porTipo.entries)
            HeaderChip(e.key.icon, '${e.value} ${e.key.label.toLowerCase()}'),
        ],
      ),
    );
  }

  /// Filtros por tipo: la selección se anima y lleva el color del tipo.
  Widget _buildFiltros() {
    final tipos = NotifType.values
        .where((t) => _notifs.any((n) => n.type == t))
        .toList();
    if (tipos.length < 2) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: SizedBox(
        height: 44,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            _chipFiltro(null, 'Todas', Icons.all_inbox_rounded,
                Theme.of(context).colorScheme.primary),
            for (final t in tipos) _chipFiltro(t, t.label, t.icon, t.color),
          ],
        ),
      ),
    );
  }

  Widget _chipFiltro(NotifType? tipo, String label, IconData icon, Color color) {
    final sel = _filter == tipo;
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Semantics(
        button: true,
        selected: sel,
        label: 'Filtrar: $label',
        excludeSemantics: true,
        onTap: () => setState(() => _filter = tipo),
        child: Pressable(
          pressedScale: 0.92,
          onTap: () => setState(() => _filter = tipo),
          child: GestureDetector(
            onTap: () => setState(() => _filter = tipo),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                gradient: sel
                    ? LinearGradient(colors: AppTokens.gradientOf(color))
                    : null,
                color: sel ? null : t.glass,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: sel ? Colors.transparent : t.glassBorder),
                boxShadow: sel
                    ? [BoxShadow(
                        color: color.withValues(alpha: 0.4),
                        blurRadius: 12, offset: const Offset(0, 4))]
                    : null,
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  transitionBuilder: (c, a) =>
                      ScaleTransition(scale: a, child: c),
                  child: Icon(icon,
                      key: ValueKey(sel),
                      size: 16,
                      color: sel ? Colors.white : color),
                ),
                const SizedBox(width: 6),
                Text(label,
                    style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: sel
                            ? Colors.white
                            : Theme.of(context).colorScheme.onSurface)),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGrupo(String texto) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 0, 8),
        child: Semantics(
          header: true,
          child: Row(children: [
            Container(
              width: 4, height: 14,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: AppTokens.gradientOf(
                      Theme.of(context).colorScheme.primary),
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                ),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text(texto.toUpperCase(),
                style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                    color: context.tokens.muted)),
          ]),
        ),
      );

  /// Panel deslizable con el detalle completo de la notificación.
  void _mostrarDetalle(AppNotification notif) {
    setState(() => notif.isRead = true);
    final color = notif.type.color;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                IconMedallion(notif.type.icon,
                    size: 56,
                    colors: AppTokens.gradientOf(color),
                    motion: notif.type.motion),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(notif.type.label,
                          style: GoogleFonts.poppins(
                              fontSize: 11, color: color,
                              fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(height: 4),
                    Text(_timeAgo(notif.time),
                        style: GoogleFonts.poppins(
                            fontSize: 12, color: context.tokens.muted)),
                  ]),
                ),
              ]),
              const SizedBox(height: 18),
              Text(notif.title,
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700, fontSize: 17)),
              const SizedBox(height: 8),
              Text(notif.body,
                  style: GoogleFonts.poppins(
                      fontSize: 13.5, color: context.tokens.muted, height: 1.55)),
              const SizedBox(height: 22),
              AppButton(
                label: 'Entendido',
                icon: Icons.check_rounded,
                expand: true,
                onPressed: () => Navigator.pop(ctx),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNotifTile(AppNotification notif) {
    final primary = Theme.of(context).colorScheme.primary;
    final t = context.tokens;
    final color = notif.type.color;

    Widget fondoSwipe(Alignment al, IconData ic, String txt, Color c) =>
        Container(
          alignment: al,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(AppTokens.radiusCard),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              MotionIcon(ic, color: c, size: 22, motion: IconMotion.pulse),
              const SizedBox(width: 8),
              Text(txt,
                  style: GoogleFonts.poppins(
                      fontSize: 12, fontWeight: FontWeight.w700, color: c)),
            ],
          ),
        );

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Dismissible(
        key: ValueKey(notif.id),
        background: fondoSwipe(Alignment.centerLeft, Icons.done_rounded,
            'Leída', t.success),
        secondaryBackground: fondoSwipe(Alignment.centerRight,
            Icons.delete_sweep_rounded, 'Descartar', t.danger),
        confirmDismiss: (dir) async {
          if (dir == DismissDirection.startToEnd) {
            setState(() => notif.isRead = true);
            return false; // solo se marca; la tarjeta permanece
          }
          return true;
        },
        onDismissed: (_) => setState(() => _notifs.remove(notif)),
        child: Semantics(
          button: true,
          label: '${notif.type.label}${notif.isRead ? '' : ', sin leer'}. '
              '${notif.title}. ${_timeAgo(notif.time)}. '
              'Desliza para marcar como leída o descartar.',
          child: ExcludeSemantics(
            child: AppCard(
              blur: false,
              tint: notif.isRead ? null : color,
              onTap: () => _mostrarDetalle(notif),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconMedallion(notif.type.icon,
                      size: 46,
                      colors: AppTokens.gradientOf(color),
                      motion: notif.isRead ? IconMotion.none : notif.type.motion,
                      orbit: !notif.isRead,
                      ping: !notif.isRead),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(notif.type.label,
                                style: GoogleFonts.poppins(
                                    fontSize: 10,
                                    color: color,
                                    fontWeight: FontWeight.w700)),
                          ),
                          const Spacer(),
                          Text(_timeAgo(notif.time),
                              style: GoogleFonts.poppins(
                                  fontSize: 12, color: t.muted)),
                          if (!notif.isRead) ...[
                            const SizedBox(width: 8),
                            _PuntoVivo(color: primary),
                          ],
                        ]),
                        const SizedBox(height: 6),
                        Text(notif.title,
                            style: GoogleFonts.poppins(
                                fontWeight: notif.isRead
                                    ? FontWeight.w500
                                    : FontWeight.w700,
                                fontSize: 14)),
                        const SizedBox(height: 4),
                        Text(notif.body,
                            style: GoogleFonts.poppins(
                                fontSize: 12, color: t.muted, height: 1.4),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildShimmer() {
    return Semantics(
      label: 'Cargando notificaciones',
      child: ExcludeSemantics(
        child: ListView.separated(
          padding: const EdgeInsets.all(AppTokens.pagePadding),
          itemCount: 5,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, __) => const SkeletonBox(height: 84),
        ),
      ),
    );
  }

  Widget _buildEmpty() => const EmptyState(
        icon: Icons.notifications_off_rounded,
        message: 'Sin notificaciones.\nCuando haya actividades o calificaciones '
            'nuevas aparecerán aquí.',
      );

  Widget _buildError() => ErrorState(
        message: 'No se pudieron cargar las notificaciones.',
        onRetry: _cargarNotificaciones,
      );

  String _timeAgo(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inSeconds < 60)  return 'Ahora';
    if (diff.inMinutes < 60)  return 'Hace ${diff.inMinutes} min';
    if (diff.inHours < 24)    return 'Hace ${diff.inHours} h';
    if (diff.inDays == 1)     return 'Ayer';
    if (diff.inDays < 7)      return 'Hace ${diff.inDays} días';
    if (diff.inDays < 30)     return 'Hace ${(diff.inDays / 7).floor()} sem';
    return 'Hace ${(diff.inDays / 30).floor()} mes';
  }

  String _tipoLabel(String tipo) {
    switch (tipo) {
      case 'midterm':  return 'Parcial';
      case 'project':  return 'Proyecto';
      case 'resource': return 'Recurso';
      default:         return 'Actividad';
    }
  }

  String _tituloAdminLog(String titulo) {
    if (titulo.contains('Nuevo usuario'))    return 'Nuevo usuario registrado';
    if (titulo.contains('eliminado'))        return 'Usuario eliminado del sistema';
    if (titulo.contains('recuperaci'))       return 'Solicitud de recuperación de contraseña';
    return titulo.isNotEmpty ? titulo : 'Evento del sistema';
  }
}

/// Ícono de campana con badge de no leídas.
///
/// Recibe [userId] y [userRol] para cargar notificaciones reales al abrir el panel.
class NotificationBell extends StatefulWidget {
  final int userId;
  final String userRol;

  const NotificationBell({
    super.key,
    this.userId = 0,
    this.userRol = 'Student',
  });

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell>
    with SingleTickerProviderStateMixin {
  int _count = 0;
  Timer? _timer;

  // Bug 5 — animación shake cuando llega una notificación nueva
  late AnimationController _shakeCtrl;
  late Animation<double> _shakeAnim;

  // Clave SharedPreferences para persistir el conteo leído
  String get _readKey => 'notif_last_read_count_${widget.userId}';

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _shakeAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end:  0.12), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 0.12, end: -0.12), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -0.12, end: 0.09), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 0.09, end: -0.09), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -0.09, end: 0.0), weight: 1),
    ]).animate(CurvedAnimation(parent: _shakeCtrl, curve: Curves.easeOut));

    if (widget.userId > 0) _calcularConteo();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (widget.userId > 0 && mounted) _calcularConteo();
    });
  }

  @override
  void didUpdateWidget(NotificationBell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId && widget.userId > 0) {
      _calcularConteo();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _shakeCtrl.dispose();
    super.dispose();
  }

  /// Marca las notificaciones como leídas guardando el conteo actual.
  Future<void> _marcarLeidas() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_readKey, _count);
    if (mounted) setState(() => _count = 0);
  }

  /// Calcula el número de notificaciones para el badge del ícono de campana.
  ///
  /// La lógica varía según el rol:
  /// - **Docente**: entregas de estudiantes con archivo enviado pero sin nota.
  /// - **Estudiante**: actividades recientes (últimos 7 días) + calificaciones recibidas.
  /// - **Admin**: igual que Docente pero sobre todos los cursos del sistema,
  ///   ya que el Admin supervisa el estado global de calificaciones.
  Future<void> _calcularConteo() async {
    try {
      // Admin consulta todos los cursos; los demás roles solo sus propios cursos.
      final cursos = widget.userRol == 'Admin'
          ? await ApiService().getAllCourses()
          : await ApiService().getMyCourses(widget.userId);
      if (cursos.isEmpty) {
        if (mounted) setState(() { _count = 0; });
        return;
      }

      // Calcular el conteo bruto según el rol
      int conteoNuevo = 0;

      if (widget.userRol == 'Admin') {
        try {
          final adminNotifs = await ApiService()
              .getNotifications(widget.userId, 'Admin');
          conteoNuevo = adminNotifs.length;
        } catch (_) {}

      } else if (widget.userRol == 'Teacher') {
        final listaActividades = await Future.wait(
          cursos.map((c) => ApiService().getActivities(c.id)
              .catchError((_) => <ActivityModel>[])),
        );
        final todasActs = listaActividades.expand((l) => l).toList();
        final resoluciones = await Future.wait(
          todasActs.map((a) => ApiService().getResolutions(a.id)
              .catchError((_) => <Map<String, dynamic>>[])),
        );
        for (final entregasList in resoluciones) {
          conteoNuevo += entregasList.where((e) =>
              e['resolution'] != null &&
              (e['resolution'] as String).isNotEmpty &&
              e['GPA'] == null).length;
        }

      } else {
        final listaActividades = await Future.wait(
          cursos.map((c) => ApiService().getActivities(c.id)
              .catchError((_) => <ActivityModel>[])),
        );
        final ahora = DateTime.now();
        for (final actividades in listaActividades) {
          for (final act in actividades) {
            try {
              final startDate = DateTime.parse(act.startDate);
              final dias = ahora.difference(startDate).inDays;
              if (dias >= 0 && dias <= 7) conteoNuevo++;
            } catch (_) {}
          }
        }
        final notas = await Future.wait(
          cursos.map((c) => ApiService().getGrades(c.id, widget.userId)
              .catchError((_) => <Map<String, dynamic>>[])),
        );
        for (final lista in notas) {
          conteoNuevo += lista.where((n) => n['GPA'] != null).length;
        }
      }

      // Bug 3: restar lo que ya leyó el usuario (persistido en SharedPreferences)
      final prefs    = await SharedPreferences.getInstance();
      final leido    = prefs.getInt(_readKey) ?? 0;
      final noLeidas = (conteoNuevo - leido).clamp(0, 999);

      if (!mounted) return;

      // Bug 5: shake si hay notificaciones nuevas que antes no había
      if (noLeidas > _count && noLeidas > 0) {
        _shakeCtrl.forward(from: 0);
      }
      setState(() => _count = noLeidas);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    // La campana suena sola al llegar una notificación y también al tocarla.
    return AnimatedBuilder(
      animation: _shakeAnim,
      builder: (_, child) => Transform.rotate(
        angle: _shakeAnim.value,
        alignment: Alignment.topCenter,
        child: child,
      ),
      child: AnimatedIconButton(
        tooltip: 'Notificaciones',
        icon: Icons.notifications_rounded,
        reaction: IconReaction.ring,
        color: Colors.white,
        badge: _count,
        onPressed: () async {
          // Capturar navigator antes de cualquier await
          final nav = Navigator.of(context);
          await _marcarLeidas();
          await nav.push(
            MaterialPageRoute(
              builder: (_) => NotificationsPanel(
                userId: widget.userId,
                userRol: widget.userRol,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Entrada con deslizamiento y fundido; [delay] escalona listas.
class _Entrada extends StatelessWidget {
  const _Entrada({required this.child, this.delay = Duration.zero});
  final Widget child;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return child;
    final total = 420 + delay.inMilliseconds;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      curve: Interval(delay.inMilliseconds / total, 1, curve: Curves.easeOutCubic),
      builder: (_, v, c) => Opacity(
        opacity: v.clamp(0.0, 1.0),
        child: Transform.translate(offset: Offset(24 * (1 - v), 0), child: c),
      ),
      child: child,
    );
  }
}

/// Punto de "sin leer" con latido y onda.
class _PuntoVivo extends StatefulWidget {
  const _PuntoVivo({required this.color});
  final Color color;

  @override
  State<_PuntoVivo> createState() => _PuntoVivoState();
}

class _PuntoVivoState extends State<_PuntoVivo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1600))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 16, height: 16,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => Stack(alignment: Alignment.center, children: [
          Container(
            width: 8 + 8 * _c.value, height: 8 + 8 * _c.value,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color.withValues(alpha: 0.4 * (1 - _c.value)),
            ),
          ),
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
          ),
        ]),
      ),
    );
  }
}
