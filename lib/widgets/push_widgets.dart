import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../config/app_tokens.dart';
import '../services/push_service.dart';
import 'ui/ui.dart';

/// Pregunta una sola vez, con contexto, si el usuario quiere recibir avisos en el teléfono
/// (CU-13). Se explica ANTES de que salga el permiso del sistema: así la gente lo acepta
/// sabiendo para qué sirve, y si dice "ahora no" no se le vuelve a insistir (puede
/// activarlo en Notificaciones → Preferencias).
Future<void> preguntarPorPush(BuildContext context, {PushService? servicio}) async {
  final push = servicio ?? PushService.instance;
  if (!push.debePreguntar) return;
  final acepta = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      final t = ctx.tokens;
      return AlertDialog(
        icon: Icon(Icons.notifications_active_rounded, size: 40, color: Theme.of(ctx).colorScheme.primary),
        title: Text('¿Activar avisos en tu teléfono?',
            textAlign: TextAlign.center, style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 18)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Te avisamos aunque la app esté cerrada de:', style: GoogleFonts.poppins(fontSize: 13.5)),
          const SizedBox(height: 10),
          for (final f in const [
            (Icons.assignment_rounded, 'Actividades nuevas y notas'),
            (Icons.alarm_rounded, 'Entregas que están por vencer'),
            (Icons.videocam_rounded, 'Reuniones que empiezan'),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                Icon(f.$1, size: 18, color: t.muted),
                const SizedBox(width: 10),
                Expanded(child: Text(f.$2, style: GoogleFonts.poppins(fontSize: 13))),
              ]),
            ),
          const SizedBox(height: 6),
          Text('Puedes cambiarlo cuando quieras en Notificaciones → Preferencias.',
              style: GoogleFonts.poppins(fontSize: 11.5, color: t.muted, height: 1.4)),
        ]),
        actionsAlignment: MainAxisAlignment.center,
        actionsOverflowDirection: VerticalDirection.down,
        actions: [
          AppButton(label: 'Activar avisos', icon: Icons.check_rounded, expand: true, onPressed: () => Navigator.pop(ctx, true)),
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Ahora no')),
        ],
      );
    },
  );
  if (acepta == true) {
    await push.solicitarPermiso();
  } else {
    await push.posponer();
  }
}

/// Interruptor "Avisos en el teléfono" para la hoja de preferencias de notificaciones.
/// No aparece si las push no están disponibles (sin Firebase, web o servidor sin configurar).
class AvisosEnTelefono extends StatefulWidget {
  const AvisosEnTelefono({super.key, this.servicio});
  final PushService? servicio;

  @override
  State<AvisosEnTelefono> createState() => _AvisosEnTelefonoState();
}

class _AvisosEnTelefonoState extends State<AvisosEnTelefono> {
  late final PushService _push = widget.servicio ?? PushService.instance;
  bool _ocupado = false;
  String? _error;

  Future<void> _cambiar(bool v) async {
    setState(() { _ocupado = true; _error = null; });
    try {
      await _push.setUserEnabled(v);
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudo guardar el cambio. Revisa tu conexión.');
    }
    if (mounted) setState(() => _ocupado = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ValueListenableBuilder<PushEstado>(
      valueListenable: _push.estado,
      builder: (_, estado, __) {
        if (estado == PushEstado.noDisponible) return const SizedBox.shrink();
        final bloqueado = estado == PushEstado.denegado;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: Icon(Icons.phone_android_rounded, color: bloqueado ? t.muted : Theme.of(context).colorScheme.primary),
            title: Text('Avisos en el teléfono', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700)),
            subtitle: Text(
              bloqueado
                  ? 'Bloqueados en los ajustes del teléfono. Actívalos allí: Ajustes → Aplicaciones → GESACAD → Notificaciones.'
                  : 'Te avisamos aunque la app esté cerrada.',
              style: GoogleFonts.poppins(fontSize: 12, height: 1.35),
            ),
            value: estado == PushEstado.activo,
            onChanged: bloqueado || _ocupado ? null : _cambiar,
          ),
          if (_error != null)
            Semantics(
              liveRegion: true,
              child: Text(_error!, style: GoogleFonts.poppins(fontSize: 12.5, color: t.danger, fontWeight: FontWeight.w600)),
            ),
          const Divider(height: 20),
        ]);
      },
    );
  }
}
