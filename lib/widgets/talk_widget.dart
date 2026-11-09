import 'package:flutter/material.dart';
import '../services/settings_service.dart';

/// Marca visual de «lo que el lector está leyendo» (cursor de ayuda y resplandor opcional al pasar).
///
/// La VOZ ya no la da este widget: la da el lector general (`ScreenReader`), que lee todo lo que
/// tiene etiqueta de accesibilidad en cualquier pantalla. Se conserva para no cambiar las pantallas
/// que lo usan y para el realce visual; [label] queda como documentación del texto del elemento.
class TalkWidget extends StatefulWidget {
  final Widget child;
  final String label;
  final int delayMs;
  final bool highlightOnHover;

  const TalkWidget({
    super.key,
    required this.child,
    required this.label,
    this.delayMs = 200, // Reducido para lectura más rápida al explorar
    this.highlightOnHover = false,
  });

  @override
  State<TalkWidget> createState() => _TalkWidgetState();
}

class _TalkWidgetState extends State<TalkWidget> {
  bool _hovering = false;

  /// El cursor entró (solo realce visual).
  void _onEnter(PointerEvent _) {
    if (!AppSettings.talkBackEnabled.value) return;
    if (mounted) setState(() => _hovering = true);
  }

  /// El cursor salió.
  void _onExit(PointerEvent _) {
    if (mounted) setState(() => _hovering = false);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AppSettings.talkBackEnabled,
      builder: (_, activado, child) => MouseRegion(
        onEnter: _onEnter,
        onExit:  _onExit,
        cursor: activado
            ? SystemMouseCursors.help
            : SystemMouseCursors.basic,
        child: child,
      ),
      child: widget.highlightOnHover
          ? AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              decoration: _hovering && AppSettings.talkBackEnabled.value
                  ? BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [BoxShadow(
                        color: Theme.of(context)
                            .colorScheme.primary.withOpacity(0.15),
                        blurRadius: 14, spreadRadius: 2,
                      )],
                    )
                  : null,
              child: widget.child,
            )
          : widget.child,
    );
  }
}
