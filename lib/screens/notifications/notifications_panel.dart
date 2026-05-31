import 'dart:async';
// ignore: avoid_web_libraries_in_flutter
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/activity_model.dart';
import '../../services/api_service.dart';
import '../../services/settings_service.dart';

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
      case NotifType.activity:     return const Color(0xFF1565C0);
      case NotifType.grade:        return const Color(0xFF2E7D32);
      case NotifType.announcement: return const Color(0xFFE65100);
      case NotifType.event:        return const Color(0xFF6A1B9A);
      case NotifType.system:       return const Color(0xFF37474F);
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
                      time: DateTime.now(),
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
                    notifs.add(AppNotification(
                      id: 'grade_${curso.id}_$i',
                      title: 'Calificación publicada',
                      body: 'Tu entrega de "${nota['tittle'] ?? 'actividad'}" '
                          'en ${curso.name} fue calificada: '
                          '${gpaParsed.toStringAsFixed(2)} / 5.0 — '
                          '${gpaParsed >= 3.0 ? "Aprobado ✓" : "Reprobado"}',
                      type: NotifType.grade,
                      time: DateTime.now(),
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
                  final sinCalificar = entregas.where((e) =>
                      e['resolution'] != null &&
                      (e['resolution'] as String).isNotEmpty &&
                      e['GPA'] == null).length;
                  if (sinCalificar > 0) {
                    notifs.add(AppNotification(
                      id: 'pending_${act.id}',
                      title: 'Entregas pendientes de calificar',
                      body: '$sinCalificar '
                          '${sinCalificar == 1 ? "estudiante entregó" : "estudiantes entregaron"} '
                          '"${act.tittle}" en ${curso.name}.',
                      type: NotifType.activity,
                      time: DateTime.now(),
                    ));
                  }
                } catch (_) {}
              }
            }

            // ── Admin: vista global de entregas sin calificar en todo el sistema
            // El Admin actúa como super-supervisor: ve todos los cursos y puede
            // detectar actividades con entregas que ningún profesor ha calificado.
            if (widget.userRol == 'Admin') {
              for (final act in actividades) {
                try {
                  final entregas = await ApiService().getResolutions(act.id);
                  final sinCalificar = entregas.where((e) =>
                      e['resolution'] != null &&
                      (e['resolution'] as String).isNotEmpty &&
                      e['GPA'] == null).length;
                  if (sinCalificar > 0) {
                    notifs.add(AppNotification(
                      id: 'admin_pending_${act.id}',
                      title: 'Entregas sin calificar',
                      body: '$sinCalificar '
                          '${sinCalificar == 1 ? "entrega pendiente" : "entregas pendientes"} '
                          'en "${act.tittle}" — ${curso.name}.',
                      type: NotifType.activity,
                      time: DateTime.now(),
                    ));
                  }
                } catch (_) {}
              }
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

  @override
  Widget build(BuildContext context) {
    final themeType = AppSettings.currentTheme.value;
    final primary = Theme.of(context).colorScheme.primary;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Regresar',
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Notificaciones',
            style: GoogleFonts.poppins(
                color: Colors.white, fontWeight: FontWeight.w700)),
        centerTitle: true,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
                colors: themeType.gradient,
                begin: Alignment.centerLeft,
                end: Alignment.centerRight),
          ),
        ),
        backgroundColor: Colors.transparent,
        actions: [
          // Recargar notificaciones desde el backend
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            tooltip: 'Actualizar',
            onPressed: _cargarNotificaciones,
          ),
          // Marcar todas como leídas
          IconButton(
            icon: const Icon(Icons.done_all_rounded, color: Colors.white),
            tooltip: 'Marcar todas como leídas',
            onPressed: () {
              for (final n in _notifs) { n.isRead = true; }
              setState(() {});
            },
          ),
        ],
      ),
      body: FadeTransition(
        opacity: _fade,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _buildError()
                : _notifs.isEmpty
                    ? _buildEmpty()
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        itemCount: _notifs.length,
                        separatorBuilder: (_, __) => Divider(
                            height: 1,
                            color: isDark
                                ? Colors.white10
                                : Colors.grey.shade100),
                        itemBuilder: (_, i) =>
                            _buildNotifTile(_notifs[i], isDark, primary),
                      ),
      ),
    );
  }

  /// Muestra un panel deslizable con el detalle completo de la notificación.
  void _mostrarDetalle(AppNotification notif) {
    setState(() => notif.isRead = true);
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Indicador visual de arrastre
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Tipo de notificación
            Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: notif.type.color.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(notif.type.icon, color: notif.type.color, size: 22),
              ),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  decoration: BoxDecoration(
                    color: notif.type.color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(notif.type.label,
                      style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: notif.type.color,
                          fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 4),
                Text(_timeAgo(notif.time),
                    style: GoogleFonts.poppins(
                        fontSize: 11, color: Colors.grey.shade500)),
              ]),
            ]),
            const SizedBox(height: 16),
            // Título
            Text(notif.title,
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 8),
            // Cuerpo completo (sin truncar)
            Text(notif.body,
                style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                    height: 1.5)),
            const SizedBox(height: 24),
            // Botón cerrar
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: Text('Cerrar',
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildNotifTile(AppNotification notif, bool isDark, Color primary) {
    return InkWell(
      onTap: () => _mostrarDetalle(notif),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        color: notif.isRead
            ? Colors.transparent
            : (isDark
                ? Colors.white.withOpacity(0.04)
                : notif.type.color.withOpacity(0.04)),
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Ícono del tipo de notificación
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: notif.type.color.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(notif.type.icon,
                  color: notif.type.color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    // Badge del tipo
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: notif.type.color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(notif.type.label,
                          style: GoogleFonts.poppins(
                              fontSize: 10,
                              color: notif.type.color,
                              fontWeight: FontWeight.w600)),
                    ),
                    const Spacer(),
                    // Tiempo transcurrido
                    Text(_timeAgo(notif.time),
                        style: GoogleFonts.poppins(
                            fontSize: 11, color: Colors.grey.shade500)),
                    // Punto azul de no leído
                    if (!notif.isRead) ...[
                      const SizedBox(width: 6),
                      Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                              color: primary, shape: BoxShape.circle)),
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
                          fontSize: 12,
                          color: Colors.grey.shade500,
                          height: 1.4),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.notifications_off_rounded,
            size: 64, color: Colors.grey.shade300),
        const SizedBox(height: 14),
        Text('Sin notificaciones',
            style: GoogleFonts.poppins(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade400)),
        const SizedBox(height: 8),
        Text('Cuando haya actividades o calificaciones\nnuevas aparecerán aquí.',
            style: GoogleFonts.poppins(
                fontSize: 13, color: Colors.grey.shade400),
            textAlign: TextAlign.center),
      ]),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.cloud_off_rounded, size: 56, color: Colors.red.shade300),
        const SizedBox(height: 14),
        Text('No se pudieron cargar las notificaciones',
            style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600)),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: _cargarNotificaciones,
          icon: const Icon(Icons.refresh_rounded),
          label: Text('Reintentar',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }

  String _timeAgo(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1)  return 'Ahora';
    if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes} min';
    if (diff.inHours < 24)   return 'Hace ${diff.inHours} h';
    return 'Hace ${diff.inDays} d';
  }

  String _tipoLabel(String tipo) {
    switch (tipo) {
      case 'midterm':  return 'Parcial';
      case 'project':  return 'Proyecto';
      case 'resource': return 'Recurso';
      default:         return 'Actividad';
    }
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

class _NotificationBellState extends State<NotificationBell> {
  /// Número de notificaciones no leídas (se actualiza al volver del panel).
  int _count = 0;

  @override
  void initState() {
    super.initState();
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

  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
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

      // Profesor y Admin comparten la misma lógica de badge:
      // contar entregas que tienen archivo pero no tienen nota asignada.
      if (widget.userRol == 'Teacher' || widget.userRol == 'Admin') {
        final listaActividades = await Future.wait(
          cursos.map((c) => ApiService().getActivities(c.id)
              .catchError((_) => <ActivityModel>[])),
        );
        final todasActs = listaActividades.expand((l) => l).toList();

        // Limitar a las primeras 10 actividades para no saturar el backend
        final actsAVerificar = todasActs.take(10).toList();
        final resoluciones = await Future.wait(
          actsAVerificar.map((a) => ApiService().getResolutions(a.id)
              .catchError((_) => <Map<String, dynamic>>[])),
        );
        int conteo = 0;
        for (final entregasList in resoluciones) {
          conteo += entregasList.where((e) =>
              e['resolution'] != null &&
              (e['resolution'] as String).isNotEmpty &&
              e['GPA'] == null).length;
        }
        if (mounted) setState(() { _count = conteo; });

      } else {
        // Estudiante: actividades recientes + calificaciones recibidas
        final listaActividades = await Future.wait(
          cursos.map((c) => ApiService().getActivities(c.id)
              .catchError((_) => <ActivityModel>[])),
        );
        int conteo = 0;
        final ahora = DateTime.now();
        for (final actividades in listaActividades) {
          for (final act in actividades) {
            try {
              final startDate = DateTime.parse(act.startDate);
              final dias = ahora.difference(startDate).inDays;
              if (dias >= 0 && dias <= 7) conteo++;
            } catch (_) {}
          }
        }
        // Sumar calificaciones que el estudiante ya recibió
        final notas = await Future.wait(
          cursos.map((c) => ApiService().getGrades(c.id, widget.userId)
              .catchError((_) => <Map<String, dynamic>>[])),
        );
        for (final lista in notas) {
          conteo += lista.where((n) => n['GPA'] != null).length;
        }
        if (mounted) setState(() { _count = conteo; });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        IconButton(
          tooltip: 'Notificaciones',
          icon: const Icon(Icons.notifications_rounded, color: Colors.white),
          onPressed: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => NotificationsPanel(
                  userId: widget.userId,
                  userRol: widget.userRol,
                ),
              ),
            );
            // Recalcular conteo al volver
            if (mounted) _calcularConteo();
          },
        ),
        if (_count > 0)
          Positioned(
            right: 6,
            top: 6,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(
                color: Color(0xFFE53935),
                shape: BoxShape.circle,
              ),
              constraints:
                  const BoxConstraints(minWidth: 18, minHeight: 18),
              child: Text(
                _count > 9 ? '9+' : '$_count',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w800),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}
