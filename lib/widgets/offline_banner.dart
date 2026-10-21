import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../config/app_tokens.dart';
import '../services/connectivity_service.dart';
import '../services/offline_queue.dart';
import '../utils/app_keys.dart';
import 'ui/ui.dart';

enum _Estado { oculto, sinConexion, sincronizando, revisar, listo }

/// Envuelve toda la app y muestra, arriba, el estado de conexión y de la cola
/// de cambios pendientes:
///
/// - **Sin conexión**: datos guardados + cuántos cambios esperan.
/// - **Sincronizando**: envío en curso.
/// - **Por revisar**: alguna acción fue rechazada y necesita decisión.
/// - **Todo sincronizado**: confirmación breve al terminar.
///
/// Al tocarlo abre el panel de sincronización ([mostrarCentroSync]).
class OfflineShell extends StatefulWidget {
  const OfflineShell({
    super.key,
    required this.child,
    ConnectivityService? connectivity,
    OfflineQueue? queue,
  })  : _connectivity = connectivity,
        _queue = queue;

  final Widget child;
  final ConnectivityService? _connectivity;
  final OfflineQueue? _queue;

  @override
  State<OfflineShell> createState() => _OfflineShellState();
}

class _OfflineShellState extends State<OfflineShell> {
  late final ConnectivityService _conn =
      widget._connectivity ?? ConnectivityService.instance;
  late final OfflineQueue _queue = widget._queue ?? OfflineQueue.instance;
  late final Listenable _merged =
      Listenable.merge([_conn.online, _queue.operations, _queue.syncing]);
  StreamSubscription<SyncEvent>? _sub;
  Timer? _doneTimer;
  bool _showDone = false;
  bool _hadWork = false;

  @override
  void initState() {
    super.initState();
    _merged.addListener(_onChange);
    _sub = _queue.events.listen(_onEvent);
  }

  @override
  void dispose() {
    _merged.removeListener(_onChange);
    _sub?.cancel();
    _doneTimer?.cancel();
    super.dispose();
  }

  /// Detecta el paso de "había trabajo pendiente" a "todo al día".
  void _onChange() {
    final trabajo = !_conn.online.value ||
        _queue.operations.value.isNotEmpty ||
        _queue.syncing.value;
    if (_hadWork && !trabajo) {
      setState(() => _showDone = true);
      _doneTimer?.cancel();
      _doneTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _showDone = false);
      });
    }
    _hadWork = trabajo;
  }

  void _onEvent(SyncEvent e) {
    final m = appMessengerKey.currentState;
    if (m == null) return;
    final ctx = appNavigatorKey.currentContext;
    final t = ctx != null ? ctx.tokens : AppTokens.light;
    m.hideCurrentSnackBar();
    m.showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: e.completed ? t.success : t.danger,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
      content: Text(
        e.completed
            ? 'Enviado: ${e.operation.label}'
            : 'No se pudo enviar: ${e.operation.label}. ${e.operation.lastError ?? ''}',
        style: GoogleFonts.poppins(color: Colors.white, fontSize: 13),
      ),
      action: e.completed
          ? null
          : SnackBarAction(
              label: 'Ver',
              textColor: Colors.white,
              onPressed: mostrarCentroSync),
    ));
  }

  _Estado get _estado {
    if (!_conn.online.value) return _Estado.sinConexion;
    if (_queue.syncing.value) return _Estado.sincronizando;
    if (_queue.failedCount > 0) return _Estado.revisar;
    if (_queue.pendingCount > 0) return _Estado.sincronizando;
    return _showDone ? _Estado.listo : _Estado.oculto;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _merged,
      builder: (context, _) {
        final estado = _estado;
        final visible = estado != _Estado.oculto;
        return Column(children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: visible
                ? _Banner(
                    key: ValueKey(estado),
                    estado: estado,
                    pendientes: _queue.pendingCount,
                    fallidas: _queue.failedCount,
                    onReintentar: () async {
                      if (await _conn.checkNow()) unawaited(_queue.sync());
                    },
                    onTap: mostrarCentroSync,
                  )
                : const SizedBox(width: double.infinity),
          ),
          Expanded(
            // El banner ya cubre la zona de la barra de estado: quitarla aquí
            // evita que el AppBar de abajo la reserve por segunda vez.
            child: MediaQuery.removePadding(
              context: context,
              removeTop: visible,
              child: widget.child,
            ),
          ),
        ]);
      },
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    super.key,
    required this.estado,
    required this.pendientes,
    required this.fallidas,
    required this.onReintentar,
    required this.onTap,
  });

  final _Estado estado;
  final int pendientes;
  final int fallidas;
  final VoidCallback onReintentar;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final top = MediaQuery.paddingOf(context).top;

    late final Color color;
    late final IconData icon;
    late final IconMotion motion;
    late final String titulo;
    String? detalle;
    switch (estado) {
      case _Estado.sinConexion:
        color = const Color(0xFF475569);
        icon = Icons.cloud_off_rounded;
        motion = IconMotion.wiggle;
        titulo = 'Sin conexión';
        detalle = pendientes > 0
            ? 'Mostrando datos guardados · $pendientes ${pendientes == 1 ? "cambio espera" : "cambios esperan"} para enviarse'
            : 'Mostrando datos guardados en tu dispositivo';
      case _Estado.sincronizando:
        color = t.info;
        icon = Icons.cloud_sync_rounded;
        motion = IconMotion.spin;
        titulo = 'Sincronizando';
        detalle = pendientes > 0
            ? 'Enviando $pendientes ${pendientes == 1 ? "cambio" : "cambios"}…'
            : null;
      case _Estado.revisar:
        color = t.danger;
        icon = Icons.error_outline_rounded;
        motion = IconMotion.pulse;
        titulo = 'Requiere tu atención';
        detalle = '$fallidas ${fallidas == 1 ? "cambio no se pudo enviar" : "cambios no se pudieron enviar"}';
      case _Estado.listo:
        color = t.success;
        icon = Icons.cloud_done_rounded;
        motion = IconMotion.tada;
        titulo = 'Todo sincronizado';
        detalle = null;
      case _Estado.oculto:
        return const SizedBox.shrink();
    }

    return Semantics(
      liveRegion: true,
      button: true,
      label: '$titulo.${detalle != null ? " $detalle." : ""} Toca para ver los detalles.',
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(16, top + 8, 8, 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [color, Color.lerp(color, Colors.black, 0.18)!],
              ),
              boxShadow: [
                BoxShadow(
                    color: color.withValues(alpha: 0.35),
                    blurRadius: 12, offset: const Offset(0, 3)),
              ],
            ),
            child: Row(children: [
              MotionIcon(icon,
                  color: Colors.white,
                  size: 22,
                  motion: motion,
                  halo: estado == _Estado.sinConexion),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(titulo,
                        style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700)),
                    if (detalle != null)
                      Text(detalle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 11.5,
                              height: 1.3)),
                  ],
                ),
              ),
              if (estado == _Estado.sinConexion)
                TextButton(
                  onPressed: onReintentar,
                  style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      minimumSize: const Size(44, 44)),
                  child: Text('Reintentar',
                      style: GoogleFonts.poppins(
                          fontSize: 12, fontWeight: FontWeight.w700)),
                )
              else if (estado == _Estado.sincronizando)
                const Padding(
                  padding: EdgeInsets.only(right: 12),
                  child: SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  ),
                )
              else
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Icon(Icons.chevron_right_rounded, color: Colors.white),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ── Centro de sincronización ─────────────────────────────────────────────────

/// Abre el panel con las acciones pendientes o rechazadas.
void mostrarCentroSync() {
  final ctx = appNavigatorKey.currentContext;
  if (ctx == null) return;
  showModalBottomSheet(
    context: ctx,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const CentroSync(),
  );
}

class CentroSync extends StatelessWidget {
  const CentroSync({super.key, this.queue, this.connectivity});

  final OfflineQueue? queue;
  final ConnectivityService? connectivity;

  String _hace(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'hace un momento';
    if (d.inHours < 1) return 'hace ${d.inMinutes} min';
    if (d.inDays < 1) return 'hace ${d.inHours} h';
    return 'hace ${d.inDays} d';
  }

  @override
  Widget build(BuildContext context) {
    final q = queue ?? OfflineQueue.instance;
    final conn = connectivity ?? ConnectivityService.instance;
    final t = context.tokens;
    final primary = Theme.of(context).colorScheme.primary;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.85, maxWidth: 560),
        child: ListenableBuilder(
          listenable: Listenable.merge([q.operations, q.syncing, conn.online]),
          builder: (context, _) {
            final ops = q.operations.value;
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  MotionIcon(
                    conn.online.value
                        ? Icons.cloud_done_rounded
                        : Icons.cloud_off_rounded,
                    color: conn.online.value ? t.success : t.muted,
                    size: 28,
                    motion: conn.online.value
                        ? IconMotion.float
                        : IconMotion.wiggle,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Semantics(
                        header: true,
                        child: Text('Sincronización',
                            style: GoogleFonts.poppins(
                                fontSize: 17, fontWeight: FontWeight.w700)),
                      ),
                      Text(
                        conn.online.value
                            ? 'Conectado al servidor'
                            : 'Sin conexión: tus cambios se guardan aquí',
                        style: GoogleFonts.poppins(
                            fontSize: 12, color: t.muted),
                      ),
                    ]),
                  ),
                ]),
                const SizedBox(height: 14),
                if (ops.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    child: Text('No hay cambios pendientes.',
                        style: GoogleFonts.poppins(color: t.muted)),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: ops.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) =>
                          _fila(context, q, ops[i], t, primary),
                    ),
                  ),
                const SizedBox(height: 16),
                AppButton(
                  label: q.syncing.value ? 'Sincronizando…' : 'Sincronizar ahora',
                  icon: Icons.sync_rounded,
                  reaction: IconReaction.spin,
                  expand: true,
                  loading: q.syncing.value,
                  onPressed: ops.isEmpty
                      ? null
                      : () async {
                          if (await conn.checkNow()) unawaited(q.sync());
                        },
                ),
              ]),
            );
          },
        ),
      ),
    );
  }

  Widget _fila(BuildContext context, OfflineQueue q, PendingOperation op,
      AppTokens t, Color primary) {
    final falla = op.status == OperationStatus.failed;
    final color = falla ? t.danger : primary;
    return AppCard(
      blur: false,
      tint: falla ? t.danger : null,
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      child: Row(children: [
        IconMedallion(
          switch (op.type) {
            OperationType.submission => Icons.upload_file_rounded,
            OperationType.grade => Icons.grading_rounded,
            OperationType.evaluation => Icons.rate_review_rounded,
          },
          size: 40,
          orbit: false,
          motion: falla ? IconMotion.none : IconMotion.float,
          colors: AppTokens.gradientOf(color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(op.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                    fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(
              falla
                  ? (op.lastError ?? 'No se pudo enviar')
                  : 'Pendiente · ${_hace(op.createdAt)}',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                  fontSize: 11.5, color: falla ? t.danger : t.muted),
            ),
          ]),
        ),
        if (falla)
          AnimatedIconButton(
            tooltip: 'Reintentar',
            icon: Icons.refresh_rounded,
            reaction: IconReaction.spin,
            color: primary,
            onPressed: () => q.retry(op.id),
          ),
        AnimatedIconButton(
          tooltip: 'Descartar',
          icon: Icons.delete_outline_rounded,
          reaction: IconReaction.shake,
          color: t.danger,
          onPressed: () => _confirmarDescarte(context, q, op),
        ),
      ]),
    );
  }

  Future<void> _confirmarDescarte(
      BuildContext context, OfflineQueue q, PendingOperation op) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Descartar este cambio?'),
        content: Text(
            '"${op.label}" no se enviará al servidor y se perderá de este dispositivo.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Conservar')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Descartar',
                  style: TextStyle(color: ctx.tokens.danger))),
        ],
      ),
    );
    if (ok == true) await q.discard(op.id);
  }
}

/// Antes de cerrar sesión: si hay cambios sin enviar se perderían, así que se
/// pide confirmación. Devuelve `true` si se puede continuar.
Future<bool> confirmarSalidaConPendientes(BuildContext context) async {
  final n = OfflineQueue.instance.operations.value.length;
  if (n == 0) return true;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Tienes cambios sin enviar'),
      content: Text(
          '$n ${n == 1 ? "cambio todavía no llegó" : "cambios todavía no llegaron"} '
          'al servidor. Si cierras sesión ahora se perderán.\n\n'
          'Conéctate a internet y espera a que se sincronicen.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Esperar')),
        TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Cerrar sesión y perderlos',
                style: TextStyle(color: ctx.tokens.danger))),
      ],
    ),
  );
  return ok == true;
}
