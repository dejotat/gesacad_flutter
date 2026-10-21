import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/notification_models.dart';
import '../../services/notification_service.dart';
import '../../utils/app_keys.dart';
import 'notifications_panel.dart';

StreamSubscription<List<AppNotif>>? _suscripcion;

/// Muestra un aviso flotante cuando llega una notificación nueva con la app abierta
/// (CU-11). Se instala una sola vez desde `main()`; funciona sobre cualquier pantalla.
void instalarAvisosDeNotificaciones([NotificationService? servicio]) {
  final svc = servicio ?? NotificationService.instance;
  _suscripcion?.cancel();
  _suscripcion = svc.arrivals.listen((items) {
    final messenger = appMessengerKey.currentState;
    if (messenger == null || items.isEmpty) return;
    final primera = items.first;
    final extra = items.length - 1;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
        content: Semantics(
          liveRegion: true,
          child: Row(children: [
            Icon(primera.type.icon, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(primera.title,
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                Text(extra > 0 ? 'y $extra más' : primera.body,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(color: Colors.white70, fontSize: 12)),
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
