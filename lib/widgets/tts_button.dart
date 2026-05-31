import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/tts_service.dart';
import '../services/settings_service.dart';

/// Botón flotante TalkBack premium con animaciones y tema dinámico.
class TtsButton extends StatefulWidget {
  final String text;
  const TtsButton({super.key, required this.text});

  @override
  State<TtsButton> createState() => _TtsButtonState();
}

class _TtsButtonState extends State<TtsButton>
    with SingleTickerProviderStateMixin {
  bool _leyendo = false;
  late AnimationController _pulse;
  late Animation<double> _scale;
  late Animation<double> _glow;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1000))
      ..repeat(reverse: true);
    _scale = Tween<double>(begin: 1.0, end: 1.10)
        .animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));
    _glow  = Tween<double>(begin: 0.4, end: 0.8)
        .animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _pulse.dispose();
    TtsService.instance.stop();
    super.dispose();
  }

  Future<void> _toggle(BuildContext ctx) async {
    if (_leyendo) {
      await TtsService.instance.stop();
      if (!mounted) return;
      setState(() => _leyendo = false);
      ScaffoldMessenger.of(ctx).clearSnackBars();
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        content: Row(children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.volume_off_rounded, color: Colors.white, size: 16),
          ),
          const SizedBox(width: 10),
          Text('TalkBack detenido', style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600, color: Colors.white, fontSize: 13)),
        ]),
        backgroundColor: const Color(0xFFB71C1C),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      ));
    } else {
      setState(() => _leyendo = true);
      ScaffoldMessenger.of(ctx).clearSnackBars();
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        content: Row(children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.volume_up_rounded, color: Colors.white, size: 16),
          ),
          const SizedBox(width: 10),
          Text('Leyendo pantalla en voz alta...', style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600, color: Colors.white, fontSize: 13)),
        ]),
        backgroundColor: const Color(0xFF1B5E20),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      ));
      await TtsService.instance.speak(widget.text);
      if (mounted) setState(() => _leyendo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AppSettings.talkBackEnabled,
      builder: (_, enabled, __) {
        if (!enabled) {
          if (_leyendo) {
            Future.microtask(() async {
              await TtsService.instance.stop();
              if (mounted) setState(() => _leyendo = false);
            });
          }
          return const SizedBox.shrink();
        }

        final themeType = AppSettings.currentTheme.value;
        final activeColors  = [const Color(0xFFD32F2F), const Color(0xFF7B1111)];
        final idleColors    = themeType.gradient;

        return Semantics(
          label: _leyendo ? 'Detener lectura' : 'Leer pantalla en voz alta',
          button: true,
          child: AnimatedBuilder(
            animation: _pulse,
            builder: (_, child) => Transform.scale(
              scale: _leyendo ? _scale.value : 1.0,
              child: child,
            ),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(32),
                gradient: LinearGradient(
                  colors: _leyendo ? activeColors : idleColors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: (_leyendo
                        ? const Color(0xFFD32F2F)
                        : themeType.primaryColor)
                        .withOpacity(_leyendo ? _glow.value : 0.45),
                    blurRadius: _leyendo ? 24 : 14,
                    offset: const Offset(0, 5),
                  ),
                  BoxShadow(
                    color: Colors.white.withOpacity(0.15),
                    blurRadius: 3,
                    offset: const Offset(0, -1),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _toggle(context),
                  borderRadius: BorderRadius.circular(32),
                  splashColor: Colors.white24,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      // Ícono animado
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        transitionBuilder: (child, anim) => ScaleTransition(
                            scale: anim, child: child),
                        child: Icon(
                          _leyendo
                              ? Icons.stop_circle_rounded
                              : Icons.volume_up_rounded,
                          key: ValueKey(_leyendo),
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Texto animado
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: Text(
                          _leyendo ? 'Detener' : 'TalkBack',
                          key: ValueKey(_leyendo),
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
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
