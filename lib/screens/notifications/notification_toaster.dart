import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/notification_models.dart';
import '../../services/notification_service.dart';
import '../../utils/app_keys.dart';
import 'notifications_panel.dart';

StreamSubscription<List<AppNotif>>? _suscripcion;

/// Muestra un aviso flotante cuando llega una notificación nueva con la app abierta
/// (CU-11). Se instala una sola vez desde `main()`; funciona sobre cualquier pantalla.
///
/// Aspecto: tarjeta flotante y centrada (no una franja pegada al borde), de vidrio oscuro con el
/// color del tipo de aviso, ícono tonal y el texto en hasta dos líneas. Se ve igual de bien sobre
/// cualquier tema.
void instalarAvisosDeNotificaciones([NotificationService? servicio]) {
  final svc = servicio ?? NotificationService.instance;
  _suscripcion?.cancel();
  _suscripcion = svc.arrivals.listen((items) {
    final messenger = appMessengerKey.currentState;
    if (messenger == null || items.isEmpty) return;
    final primera = items.first;
    final extra = items.length - 1;
    final color = primera.colorAviso;

    // Ancho: cómodo de leer en pantallas grandes y con margen en teléfonos.
    final ctx = appNavigatorKey.currentContext;
    final ancho = ctx != null ? MediaQuery.sizeOf(ctx).width : 600.0;

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        width: math.max(280.0, math.min(520.0, ancho - 32)),
        duration: const Duration(seconds: 6),
        elevation: 10,
        backgroundColor: const Color(0xF2111830),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: color.withValues(alpha: 0.55)),
        ),
        content: Semantics(
          liveRegion: true,
          child: Row(children: [
            // Ícono tonal del tipo de aviso.
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.20),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: color.withValues(alpha: 0.40)),
              ),
              child: Icon(primera.icono, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(primera.title,
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13, height: 1.25)),
                if (extra > 0 || primera.body.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(extra > 0 ? 'y $extra más' : primera.body,
                        maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(color: Colors.white.withValues(alpha: 0.78), fontSize: 12, height: 1.3)),
                  ),
              ]),
            ),
          ]),
        ),
        action: SnackBarAction(
          label: 'Ver',
          textColor: Colors.white,
          onPressed: () => appNavigatorKey.currentState?.push(MaterialPageRoute(
            builder: (_) => NotificationsPanel(userId: svc.userId, userRol: svc.rol, servicio: svc),
          )),
        ),
      ));
  });
}
