import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../services/settings_service.dart';

/// Indicador flotante «Lector de voz activo» (abajo a la izquierda). Solo aparece mientras el
/// lector está encendido: deja claro por qué la app está hablando y permite apagarlo con un toque.
/// Va en el `builder` de `MaterialApp`, por encima de todas las pantallas.
class IndicadorLectorVoz extends StatelessWidget {
  const IndicadorLectorVoz({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AppSettings.talkBackEnabled,
      builder: (context, activo, _) {
        if (!activo) return const SizedBox.shrink();
        final acento = Theme.of(context).colorScheme.secondary;
        return Positioned(
          left: 12,
          bottom: 12,
          child: SafeArea(
            // Solo visual: el lector NO debe leerlo (repetía «lector de voz activo, toca para
            // desactivar» cada vez que se volvía a una pantalla). Se apaga desde Ajustes, el menú
            // de cuenta o el botón del lector.
            child: ExcludeSemantics(
              child: Material(
                color: const Color(0xE6101630),
                shape: StadiumBorder(side: BorderSide(color: acento.withValues(alpha: 0.6))),
                elevation: 8,
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: () => AppSettings.setTalkBack(false),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 14, 8),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(PhosphorIconsFill.speakerHigh, size: 18, color: acento),
                      const SizedBox(width: 8),
                      Text('Lector de voz activo',
                          style: GoogleFonts.poppins(
                              color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                      const SizedBox(width: 8),
                      Icon(PhosphorIconsRegular.x, size: 14, color: Colors.white70),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Botón para encender o apagar el lector de voz (login, menús). Se anuncia como interruptor.
class BotonLectorVoz extends StatelessWidget {
  const BotonLectorVoz({super.key, this.color});

  /// Color del ícono (por defecto, el del tema).
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AppSettings.talkBackEnabled,
      builder: (context, activo, _) {
        final c = color ?? Theme.of(context).colorScheme.onSurface;
        return Semantics(
          button: true,
          toggled: activo,
          label: activo ? 'Lector de voz activado. Toca para desactivarlo.' : 'Activar lector de voz',
          excludeSemantics: true,
          onTap: () => AppSettings.setTalkBack(!activo),
          child: Tooltip(
            message: activo ? 'Desactivar lector de voz' : 'Activar lector de voz',
            child: IconButton(
              onPressed: () => AppSettings.setTalkBack(!activo),
              style: IconButton.styleFrom(
                backgroundColor: activo ? c.withValues(alpha: 0.18) : Colors.transparent,
                side: BorderSide(color: c.withValues(alpha: activo ? 0.6 : 0.25)),
              ),
              icon: Icon(
                activo ? PhosphorIconsFill.speakerHigh : PhosphorIconsRegular.speakerHigh,
                color: c,
                size: 22,
              ),
            ),
          ),
        );
      },
    );
  }
}
