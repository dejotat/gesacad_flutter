import 'dart:async';
import 'package:flutter/material.dart';
import '../services/tts_service.dart';
import '../services/settings_service.dart';

/// Widget de TalkBack con lectura continua al arrastrar el cursor.
///
/// Implementa "Touch Exploration" — al pasar o arrastrar el cursor/dedo
/// sobre el elemento, lo lee en voz alta inmediatamente.
///
/// Comportamiento:
/// - Si TalkBack está desactivado → no hace nada
/// - Al entrar el cursor → espera [delayMs] ms → lee el texto
/// - Al salir el cursor → detiene la lectura
/// - Al arrastrar (hover move) → si cambia de widget, lee el nuevo
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
  Timer? _timer;
  bool _hovering = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// El cursor entró — iniciar lectura tras el delay.
  void _onEnter(PointerEvent _) {
    if (!AppSettings.talkBackEnabled.value) return;
    if (mounted) setState(() => _hovering = true);
    _timer?.cancel();
    _timer = Timer(Duration(milliseconds: widget.delayMs), () {
      if (!mounted || !_hovering) return;
      if (!AppSettings.talkBackEnabled.value) return;
      TtsService.instance.speak(widget.label);
    });
  }

  /// El cursor se movió dentro del widget — releer si ya está leyendo
  /// otro texto (exploración táctil continua).
  void _onHover(PointerEvent _) {
    if (!AppSettings.talkBackEnabled.value) return;
    // Si ya está leyendo ESTE texto no interrumpir
    if (TtsService.instance.textoActual == widget.label) return;
    // Si está leyendo otro texto, actualizar al nuevo (exploración continua)
    if (TtsService.instance.leyendo) {
      _timer?.cancel();
      _timer = Timer(Duration(milliseconds: widget.delayMs), () {
        if (!mounted || !_hovering) return;
        TtsService.instance.speak(widget.label);
      });
    }
  }

  /// El cursor salió — detener lectura.
  void _onExit(PointerEvent _) {
    if (mounted) setState(() => _hovering = false);
    _timer?.cancel();
    TtsService.instance.stop();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AppSettings.talkBackEnabled,
      builder: (_, activado, child) => MouseRegion(
        onEnter: _onEnter,
        onHover: _onHover, // Captura movimiento del cursor dentro del widget
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
