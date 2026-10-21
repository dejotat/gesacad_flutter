import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../config/app_tokens.dart';
import '../../models/notification_models.dart';
import '../../services/notification_service.dart';
import '../../widgets/ui/ui.dart';
import '../../services/push_service.dart';
import '../../widgets/push_widgets.dart';
import 'notification_router.dart';

/// Bandeja de notificaciones (CU-11).
///
/// - Las notificaciones viven en el servidor: el estado de leído se sincroniza entre
///   dispositivos y los cambios se aplican al instante (con reversa si falla).
/// - Agrupadas por día, con filtros por tipo y "solo sin leer"; se cargan más al llegar
///   al final de la lista.
/// - Tocar una marca como leída y lleva a lo que la originó (actividad, curso, reunión…).
/// - Deslizar a la derecha marca como leída; a la izquierda la descarta.
/// - Sin conexión muestra la última copia guardada.
class NotificationsPanel extends StatefulWidget {
  /// ID del usuario de la sesión. Si es 0 no se consulta el servidor.
  final int userId;

  /// Rol del usuario: 'Student', 'Teacher' o 'Admin'.
  final String userRol;

  /// Para pruebas; por defecto el servicio global.
  final NotificationService? servicio;

  const NotificationsPanel({
    super.key,
    this.userId = 0,
    this.userRol = 'Student',
    this.servicio,
  });

  @override
  State<NotificationsPanel> createState() => _NotificationsPanelState();
}

class _NotificationsPanelState extends State<NotificationsPanel> {
  late final NotificationService _svc = widget.servicio ?? NotificationService.instance;
  final _scroll = ScrollController();

  final List<AppNotif> _items = [];
  int? _siguiente;
  bool _cargando = true;
  bool _cargandoMas = false;
  bool _sinConexion = false;
  String? _error;
  NotifType? _tipo;
  bool _soloNoLeidas = false;

  StreamSubscription<List<AppNotif>>? _llegadas;
  bool _enganchado = false;

  @override
  void initState() {
    super.initState();
    // Si llega algo nuevo con el panel abierto, la lista se actualiza sola.
    _llegadas = _svc.arrivals.listen((_) { if (mounted && !_cargando) _cargar(silencioso: true); });
    _scroll.addListener(() {
      if (_scroll.hasClients && _scroll.position.extentAfter < 300) _cargarMas();
    });
    if (widget.userId > 0) {
      // Asegura que el servicio sepa quién es (por si se abre el panel de forma aislada);
      // si lo engancha este panel, lo suelta al cerrarse.
      if (_svc.userId != widget.userId) {
        _svc.attach(widget.userId, widget.userRol);
        _enganchado = true;
      }
      _cargar();
    } else {
      _cargando = false;
    }
  }

  @override
  void dispose() {
    _llegadas?.cancel();
    if (_enganchado) _svc.detach();
    _scroll.dispose();
    super.dispose();
  }

  // ── Datos ───────────────────────────────────────────────────────────────────
  Future<void> _cargar({bool silencioso = false}) async {
    if (!silencioso) setState(() { _cargando = true; _error = null; });
    try {
      final p = await _svc.list(type: _tipo, unreadOnly: _soloNoLeidas);
      if (!mounted) return;
      setState(() {
        _items..clear()..addAll(p.items);
        _siguiente = p.nextBefore;
        _sinConexion = p.fromCache;
        _cargando = false;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() { _cargando = false; _error = e.toString(); });
    }
  }

  Future<void> _cargarMas() async {
    if (_cargandoMas || _siguiente == null || _cargando) return;
    setState(() => _cargandoMas = true);
    try {
      final p = await _svc.list(before: _siguiente, type: _tipo, unreadOnly: _soloNoLeidas);
      if (!mounted) return;
      setState(() {
        final ya = _items.map((n) => n.id).toSet();
        _items.addAll(p.items.where((n) => !ya.contains(n.id)));
        _siguiente = p.nextBefore;
        _cargandoMas = false;
      });
    } catch (_) {
      if (mounted) setState(() => _cargandoMas = false);
    }
  }

  void _aviso(String texto, {bool error = false}) {
    if (!mounted) return;
    final t = context.tokens;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? t.danger : null,
        content: Text(texto, style: GoogleFonts.poppins(color: Colors.white)),
      ));
  }

  /// Marca como leída al instante; si el servidor falla, revierte.
  Future<void> _marcarLeida(AppNotif n) async {
    if (n.read) return;
    setState(() => n.read = true);
    try {
      await _svc.markRead([n.id]);
    } catch (e) {
      if (mounted) setState(() => n.read = false);
      _aviso('No se pudo marcar como leída: $e', error: true);
    }
  }

  Future<void> _marcarTodas() async {
    final previas = _items.where((n) => !n.read).toList();
    if (previas.isEmpty && _svc.unread.value == 0) return;
    setState(() { for (final n in previas) { n.read = true; } });
    try {
      await _svc.markAllRead();
      if (_soloNoLeidas) await _cargar(silencioso: true);
    } catch (e) {
      if (mounted) setState(() { for (final n in previas) { n.read = false; } });
      _aviso('No se pudieron marcar: $e', error: true);
    }
  }

  Future<void> _descartar(AppNotif n) async {
    final i = _items.indexOf(n);
    setState(() => _items.remove(n));
    try {
      await _svc.delete(n.id);
    } catch (e) {
      if (mounted) setState(() => _items.insert(i.clamp(0, _items.length), n));
      _aviso('No se pudo descartar: $e', error: true);
    }
  }

  Future<void> _borrarLeidas() async {
    try {
      final n = await _svc.deleteBulk(soloLeidas: true);
      await _cargar(silencioso: true);
      _aviso(n == 0 ? 'No hay notificaciones leídas para borrar.' : 'Se borraron $n notificaciones leídas.');
    } catch (e) {
      _aviso('No se pudieron borrar: $e', error: true);
    }
  }

  Future<void> _abrir(AppNotif n) async {
    unawaited(_marcarLeida(n));
    final fue = await abrirNotificacion(context, n, userId: widget.userId, rol: widget.userRol);
    if (!fue && mounted) _mostrarDetalle(n);
  }

  void _filtrar({NotifType? tipo, bool? soloNoLeidas}) {
    setState(() {
      if (tipo != null || soloNoLeidas == null) _tipo = tipo == _tipo ? null : tipo;
      if (soloNoLeidas != null) _soloNoLeidas = soloNoLeidas;
    });
    _cargar();
  }

  // ── Interfaz ────────────────────────────────────────────────────────────────
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
          MotionIcon(Icons.notifications_rounded, size: 22, motion: IconMotion.ring),
          SizedBox(width: 8),
          Flexible(child: Text('Notificaciones', overflow: TextOverflow.ellipsis)),
        ]),
        actions: [
          AnimatedIconButton(
            icon: Icons.done_all_rounded,
            tooltip: 'Marcar todas como leídas',
            reaction: IconReaction.pop,
            onPressed: widget.userId > 0 ? _marcarTodas : null,
          ),
          PopupMenuButton<String>(
            tooltip: 'Más opciones',
            icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
            onSelected: (v) {
              if (v == 'leidas') _borrarLeidas();
              if (v == 'prefs') _abrirPreferencias();
              if (v == 'refrescar') _cargar();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'refrescar', child: Text('Actualizar')),
              PopupMenuItem(value: 'leidas', child: Text('Borrar las leídas')),
              PopupMenuItem(value: 'prefs', child: Text('Preferencias')),
            ],
          ),
        ],
      ),
      body: LogoBackdrop(
        child: _cargando
            ? _esqueleto()
            : _error != null && _items.isEmpty
                ? ErrorState(message: _error!, onRetry: _cargar)
                : _lista(),
      ),
    );
  }

  Widget _esqueleto() => Semantics(
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

  Widget _lista() {
    final grupos = _agruparPorDia();
    final filas = <Object>[
      for (final g in grupos.entries) ...[g.key, ...g.value],
    ];
    final vacio = _items.isEmpty;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: RefreshIndicator(
          onRefresh: () => _cargar(silencioso: true),
          child: ListView.builder(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
                AppTokens.pagePadding, AppTokens.pagePadding, AppTokens.pagePadding, 40),
            itemCount: filas.length + 3,
            itemBuilder: (_, i) {
              if (i == 0) return _resumen();
              if (i == 1) return _filtros();
              if (i == 2) {
                return Column(children: [
                  if (_sinConexion) _banner(Icons.wifi_off_rounded,
                      'Sin conexión: mostrando la última copia guardada.', context.tokens.warning),
                  if (vacio) _vacio(),
                ]);
              }
              final fila = filas[i - 3];
              if (fila is String) return _cabeceraDia(fila);
              return _Entrada(
                delay: Duration(milliseconds: 40 * (i - 3).clamp(0, 8)),
                child: _tarjeta(fila as AppNotif),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _banner(IconData icono, String texto, Color color) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Semantics(
          liveRegion: true,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppTokens.radiusControl),
              border: Border.all(color: color.withValues(alpha: 0.4)),
            ),
            child: Row(children: [
              Icon(icono, color: color, size: 18),
              const SizedBox(width: 10),
              Expanded(child: Text(texto, style: GoogleFonts.poppins(fontSize: 12.5))),
            ]),
          ),
        ),
      );

  Widget _vacio() {
    final filtrado = _tipo != null || _soloNoLeidas;
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: EmptyState(
        icon: Icons.notifications_off_rounded,
        message: filtrado
            ? 'Sin notificaciones con este filtro.'
            : 'Sin notificaciones.\nCuando haya actividades, calificaciones o '
                'reuniones nuevas aparecerán aquí.',
      ),
    );
  }

  /// Encabezado de cristal: campana que suena + cuántas hay sin leer.
  Widget _resumen() {
    return ValueListenableBuilder<int>(
      valueListenable: _svc.unread,
      builder: (_, n, __) {
        final porTipo = <NotifType, int>{};
        for (final x in _items.where((x) => !x.read)) {
          porTipo[x.type] = (porTipo[x.type] ?? 0) + 1;
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: PageHeader(
            title: n == 0 ? 'Todo al día' : '$n sin leer',
            subtitle: n == 0
                ? 'No tienes notificaciones pendientes'
                : 'Toca una para abrirla o desliza para marcarla / descartarla',
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
                    color: Colors.white, size: 30, glow: true,
                    motion: n == 0 ? IconMotion.float : IconMotion.ring,
                  ),
                ),
              ),
            ),
            chips: [
              for (final e in porTipo.entries.take(4))
                HeaderChip(e.key.icon, '${e.value} ${e.key.label.toLowerCase()}'),
            ],
          ),
        );
      },
    );
  }

  Widget _filtros() {
    final primario = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SizedBox(
        height: 44,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            _chip(null, 'Todas', Icons.all_inbox_rounded, primario, sel: _tipo == null && !_soloNoLeidas,
                onTap: () { setState(() { _tipo = null; _soloNoLeidas = false; }); _cargar(); }),
            _chip(null, 'Sin leer', Icons.mark_email_unread_rounded, context.tokens.danger,
                sel: _soloNoLeidas, onTap: () => _filtrar(soloNoLeidas: !_soloNoLeidas)),
            for (final t in NotifType.values)
              if (t != NotifType.system || widget.userRol == 'Admin')
                _chip(t, t.label, t.icon, t.color, sel: _tipo == t, onTap: () => _filtrar(tipo: t)),
          ],
        ),
      ),
    );
  }

  Widget _chip(NotifType? tipo, String label, IconData icono, Color color,
      {required bool sel, required VoidCallback onTap}) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Semantics(
        button: true,
        selected: sel,
        label: 'Filtrar: $label',
        excludeSemantics: true,
        onTap: onTap,
        child: Pressable(
          pressedScale: 0.92,
          onTap: onTap,
          child: GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                gradient: sel ? LinearGradient(colors: AppTokens.gradientOf(color)) : null,
                color: sel ? null : t.glass,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: sel ? Colors.transparent : t.glassBorder),
                boxShadow: sel
                    ? [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 12, offset: const Offset(0, 4))]
                    : null,
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icono, size: 16, color: sel ? Colors.white : color),
                const SizedBox(width: 6),
                Text(label,
                    style: GoogleFonts.poppins(
                        fontSize: 12, fontWeight: FontWeight.w600,
                        color: sel ? Colors.white : Theme.of(context).colorScheme.onSurface)),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  /// Hoy / Ayer / Esta semana / Anteriores.
  Map<String, List<AppNotif>> _agruparPorDia() {
    final hoy = DateTime.now();
    final inicioHoy = DateTime(hoy.year, hoy.month, hoy.day);
    final grupos = <String, List<AppNotif>>{};
    for (final n in _items) {
      final dia = DateTime(n.createdAt.year, n.createdAt.month, n.createdAt.day);
      final d = inicioHoy.difference(dia).inDays;
      final clave = d <= 0 ? 'Hoy' : d == 1 ? 'Ayer' : d < 7 ? 'Esta semana' : 'Anteriores';
      grupos.putIfAbsent(clave, () => []).add(n);
    }
    return grupos;
  }

  Widget _cabeceraDia(String texto) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 0, 8),
        child: Semantics(
          header: true,
          child: Row(children: [
            Container(
              width: 4, height: 14,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: AppTokens.gradientOf(Theme.of(context).colorScheme.primary),
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                ),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text(texto.toUpperCase(),
                style: GoogleFonts.poppins(
                    fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.1, color: context.tokens.muted)),
          ]),
        ),
      );

  Widget _tarjeta(AppNotif n) {
    final t = context.tokens;
    final primario = Theme.of(context).colorScheme.primary;
    final color = n.type.color;

    Widget fondo(Alignment al, IconData ic, String txt, Color c) => Container(
          alignment: al,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(AppTokens.radiusCard)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            MotionIcon(ic, color: c, size: 22, motion: IconMotion.pulse),
            const SizedBox(width: 8),
            Text(txt, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700, color: c)),
          ]),
        );

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Dismissible(
        key: ValueKey('notif-${n.id}'),
        background: fondo(Alignment.centerLeft, Icons.done_rounded, 'Leída', t.success),
        secondaryBackground: fondo(Alignment.centerRight, Icons.delete_sweep_rounded, 'Descartar', t.danger),
        confirmDismiss: (dir) async {
          if (dir == DismissDirection.startToEnd) {
            unawaited(_marcarLeida(n));
            return false; // solo se marca; la tarjeta permanece
          }
          return true;
        },
        onDismissed: (_) => _descartar(n),
        child: Semantics(
          button: true,
          label: '${n.type.label}${n.read ? '' : ', sin leer'}. ${n.title}. ${_hace(n.createdAt)}. '
              'Toca para abrir, desliza para marcar como leída o descartar.',
          child: ExcludeSemantics(
            child: AppCard(
              blur: false,
              tint: n.read ? null : color,
              onTap: () => _abrir(n),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                IconMedallion(n.type.icon,
                    size: 46,
                    colors: AppTokens.gradientOf(color),
                    motion: n.read ? IconMotion.none : n.type.motion,
                    orbit: !n.read,
                    ping: !n.read),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(8)),
                        child: Text(n.type.label,
                            style: GoogleFonts.poppins(fontSize: 10, color: color, fontWeight: FontWeight.w700)),
                      ),
                      const Spacer(),
                      Text(_hace(n.createdAt), style: GoogleFonts.poppins(fontSize: 12, color: t.muted)),
                      if (!n.read) ...[const SizedBox(width: 8), _PuntoVivo(color: primario)],
                    ]),
                    const SizedBox(height: 6),
                    Text(n.title,
                        style: GoogleFonts.poppins(
                            fontWeight: n.read ? FontWeight.w500 : FontWeight.w700, fontSize: 14)),
                    const SizedBox(height: 4),
                    Text(n.body,
                        style: GoogleFonts.poppins(fontSize: 12, color: t.muted, height: 1.4),
                        maxLines: 3, overflow: TextOverflow.ellipsis),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  /// Detalle para las notificaciones que no llevan a ninguna pantalla.
  void _mostrarDetalle(AppNotif n) {
    final color = n.type.color;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              IconMedallion(n.type.icon, size: 56, colors: AppTokens.gradientOf(color), motion: n.type.motion),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(n.type.label, style: GoogleFonts.poppins(fontSize: 12, color: color, fontWeight: FontWeight.w700)),
                  Text(_hace(n.createdAt), style: GoogleFonts.poppins(fontSize: 12, color: context.tokens.muted)),
                ]),
              ),
            ]),
            const SizedBox(height: 18),
            Text(n.title, style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 17)),
            const SizedBox(height: 8),
            Text(n.body, style: GoogleFonts.poppins(fontSize: 13.5, color: context.tokens.muted, height: 1.55)),
            const SizedBox(height: 22),
            AppButton(label: 'Entendido', icon: Icons.check_rounded, expand: true, onPressed: () => Navigator.pop(ctx)),
          ]),
        ),
      ),
    );
  }

  // ── Preferencias ────────────────────────────────────────────────────────────
  void _abrirPreferencias() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _HojaPreferencias(servicio: _svc, esAdmin: widget.userRol == 'Admin', rol: widget.userRol),
    );
  }

  String _hace(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inSeconds < 60) return 'Ahora';
    if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Hace ${diff.inHours} h';
    if (diff.inDays == 1) return 'Ayer';
    if (diff.inDays < 7) return 'Hace ${diff.inDays} días';
    if (diff.inDays < 30) return 'Hace ${(diff.inDays / 7).floor()} sem';
    return 'Hace ${(diff.inDays / 30).floor()} mes';
  }
}

/// Qué tipos de aviso quiere recibir el usuario.
class _HojaPreferencias extends StatefulWidget {
  const _HojaPreferencias({required this.servicio, required this.esAdmin, required this.rol});
  final NotificationService servicio;
  final bool esAdmin;
  final String rol;

  @override
  State<_HojaPreferencias> createState() => _HojaPreferenciasState();
}

class _HojaPreferenciasState extends State<_HojaPreferencias> {
  Map<NotifType, bool>? _prefs;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.servicio.preferences().then((p) {
      if (mounted) setState(() => _prefs = p);
    }).catchError((Object e) {
      if (mounted) setState(() => _error = e.toString());
    });
  }

  /// Tipos que pueden llegarle a este rol.
  Iterable<NotifType> get _visibles => NotifType.values.where((t) => switch (t) {
        NotifType.system => widget.esAdmin,
        NotifType.submission => widget.rol == 'Teacher',
        NotifType.activity || NotifType.grade || NotifType.reminder => widget.rol != 'Admin',
        _ => true,
      });

  Future<void> _cambiar(NotifType t, bool v) async {
    setState(() => _prefs![t] = v);
    try {
      await widget.servicio.setPreference(t, v);
    } catch (e) {
      if (mounted) setState(() { _prefs![t] = !v; _error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Semantics(
            header: true,
            child: Text('Qué avisos quiero recibir', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 4),
          Text('Los que desactives dejarán de llegar a tu bandeja.',
              style: GoogleFonts.poppins(fontSize: 12.5, color: t.muted)),
          const SizedBox(height: 8),
          const AvisosEnTelefono(),
          if (_prefs == null && _error == null)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
          else if (_prefs != null)
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                for (final tipo in _visibles)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: Icon(tipo.icon, color: tipo.color),
                    title: Text(tipo.label, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600)),
                    subtitle: Text(tipo.description, style: GoogleFonts.poppins(fontSize: 12)),
                    value: _prefs![tipo] ?? true,
                    onChanged: (v) => _cambiar(tipo, v),
                  ),
              ]),
            ),
          if (_error != null)
            Semantics(
              liveRegion: true,
              child: Text(_error!, style: GoogleFonts.poppins(fontSize: 12.5, color: t.danger, fontWeight: FontWeight.w600)),
            ),
        ]),
      ),
    );
  }
}

/// Campana con insignia de no leídas, conectada al servicio global.
///
/// Mientras está en pantalla mantiene el sondeo de novedades; suena cuando llega una
/// notificación nueva y al tocarla abre la bandeja.
class NotificationBell extends StatefulWidget {
  final int userId;
  final String userRol;
  final NotificationService? servicio;

  const NotificationBell({super.key, this.userId = 0, this.userRol = 'Student', this.servicio});

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> with SingleTickerProviderStateMixin {
  late final NotificationService _svc = widget.servicio ?? NotificationService.instance;
  late final AnimationController _shake =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
  late final Animation<double> _shakeAnim = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.12), weight: 1),
    TweenSequenceItem(tween: Tween(begin: 0.12, end: -0.12), weight: 2),
    TweenSequenceItem(tween: Tween(begin: -0.12, end: 0.09), weight: 2),
    TweenSequenceItem(tween: Tween(begin: 0.09, end: -0.09), weight: 2),
    TweenSequenceItem(tween: Tween(begin: -0.09, end: 0.0), weight: 1),
  ]).animate(CurvedAnimation(parent: _shake, curve: Curves.easeOut));
  StreamSubscription<List<AppNotif>>? _sub;
  bool _enlazada = false;

  @override
  void initState() {
    super.initState();
    if (widget.userId > 0) {
      _svc.attach(widget.userId, widget.userRol);
      _enlazada = true;
      _iniciarPush();
    }
    _sub = _svc.arrivals.listen((_) {
      if (mounted && !(MediaQuery.maybeDisableAnimationsOf(context) ?? false)) _shake.forward(from: 0);
    });
  }

  /// Registra este teléfono para recibir push y, si falta, pregunta con contexto (una sola vez).
  Future<void> _iniciarPush() async {
    await PushService.instance.start(widget.userId, widget.userRol);
    if (!mounted) return;
    await preguntarPorPush(context);
    // Si el usuario tocó un aviso antes de que la app estuviera lista, se abre ahora.
    await PushService.instance.abrirPendiente();
  }

  @override
  void didUpdateWidget(NotificationBell old) {
    super.didUpdateWidget(old);
    if (old.userId != widget.userId && widget.userId > 0) {
      if (_enlazada) _svc.detach();
      _svc.attach(widget.userId, widget.userRol);
      _enlazada = true;
      _iniciarPush();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    if (_enlazada) _svc.detach();
    _shake.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: _svc.unread,
      builder: (_, cuenta, __) => AnimatedBuilder(
        animation: _shakeAnim,
        builder: (_, child) => Transform.rotate(angle: _shakeAnim.value, alignment: Alignment.topCenter, child: child),
        child: AnimatedIconButton(
          tooltip: cuenta > 0 ? 'Notificaciones, $cuenta sin leer' : 'Notificaciones',
          icon: Icons.notifications_rounded,
          reaction: IconReaction.ring,
          color: Colors.white,
          badge: cuenta,
          onPressed: () async {
            final nav = Navigator.of(context);
            await nav.push(MaterialPageRoute(
              builder: (_) => NotificationsPanel(userId: widget.userId, userRol: widget.userRol, servicio: widget.servicio),
            ));
            // Al volver, la insignia se pone al día con lo que se leyó.
            unawaited(_svc.poll());
          },
        ),
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

class _PuntoVivoState extends State<_PuntoVivo> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();

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
        builder: (_, __) => Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
          Transform.scale(
            scale: 1 + _c.value,
            child: Container(
              width: 8, height: 8,
              decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color.withValues(alpha: 0.4 * (1 - _c.value))),
            ),
          ),
          Container(width: 8, height: 8, decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle)),
        ]),
      ),
    );
  }
}
