import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Movimiento continuo de un [MotionIcon] tras su entrada.
enum IconMotion {
  /// Sin movimiento continuo (solo la entrada).
  none,

  /// Flota suavemente arriba y abajo.
  float,

  /// Late: escala sube y baja.
  pulse,

  /// Se agita brevemente cada pocos segundos (campana, avisos).
  wiggle,

  /// Gira lento.
  spin,

  /// Salta de vez en cuando.
  bounce,

  /// Campana: oscila con el pivote arriba, como si sonara.
  ring,

  /// Tada: crece y se sacude como celebrando (calificaciones, logros).
  tada,

  /// Latido doble, como un corazón.
  heartbeat,

  /// Péndulo continuo (relojes, calendarios colgantes).
  swing,

  /// Trazo de escritura: se inclina y avanza (lápiz, formularios).
  write,
}

/// Ícono con vida: entra con un rebote elástico y luego se mueve de forma sutil
/// según [motion]. Al pasar el cursor (web/escritorio) crece un poco.
///
/// Respeta "reducir movimiento" del sistema (`MediaQuery.disableAnimations`):
/// en ese caso se muestra estático. Es decorativo: se excluye de la semántica
/// salvo que se pase [semanticLabel].
class MotionIcon extends StatefulWidget {
  const MotionIcon(
    this.icon, {
    super.key,
    this.color,
    this.size = 24,
    this.motion = IconMotion.float,
    this.delay = Duration.zero,
    this.glow = false,
    this.halo = false,
    this.semanticLabel,
  });

  final IconData icon;
  final Color? color;
  final double size;
  final IconMotion motion;

  /// Retraso de la entrada (para escalonar varios íconos).
  final Duration delay;

  /// Halo de luz del color del ícono.
  final bool glow;

  /// Onda expansiva tipo sonar detrás del ícono (llama la atención sin ruido).
  final bool halo;
  final String? semanticLabel;

  @override
  State<MotionIcon> createState() => _MotionIconState();
}

class _MotionIconState extends State<MotionIcon> with TickerProviderStateMixin {
  late final AnimationController _enter;
  AnimationController? _loop;
  Timer? _delayTimer;
  bool _hover = false;

  Duration get _period {
    switch (widget.motion) {
      case IconMotion.float:  return const Duration(milliseconds: 3200);
      case IconMotion.pulse:  return const Duration(milliseconds: 2200);
      case IconMotion.wiggle: return const Duration(milliseconds: 4200);
      case IconMotion.spin:   return const Duration(seconds: 9);
      case IconMotion.bounce: return const Duration(milliseconds: 3400);
      case IconMotion.ring:   return const Duration(milliseconds: 3600);
      case IconMotion.tada:   return const Duration(milliseconds: 4600);
      case IconMotion.heartbeat: return const Duration(milliseconds: 1500);
      case IconMotion.swing:  return const Duration(milliseconds: 2800);
      case IconMotion.write:  return const Duration(milliseconds: 3000);
      case IconMotion.none:   return const Duration(seconds: 1);
    }
  }

  @override
  void initState() {
    super.initState();
    _enter = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 750));
    _delayTimer = Timer(widget.delay, () {
      if (mounted) _enter.forward();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce || widget.motion == IconMotion.none) {
      _loop?.dispose();
      _loop = null;
      if (reduce) _enter.value = 1;
    } else if (_loop == null) {
      // Desfase aleatorio para que varios íconos no se muevan al unísono.
      _loop = AnimationController(vsync: this, duration: _period)
        ..value = math.Random().nextDouble()
        ..repeat();
    }
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _enter.dispose();
    _loop?.dispose();
    super.dispose();
  }

  /// Transformación continua según [t] (0..1 del ciclo).
  Matrix4 _loopTransform(double t) {
    switch (widget.motion) {
      case IconMotion.float:
        return Matrix4.translationValues(0, math.sin(t * 2 * math.pi) * -3.5, 0);
      case IconMotion.pulse:
        final s = 1 + 0.10 * (0.5 - 0.5 * math.cos(t * 2 * math.pi));
        return Matrix4.diagonal3Values(s, s, 1);
      case IconMotion.wiggle:
        // Agitación solo en el primer 18% del ciclo, el resto en reposo.
        if (t > 0.18) return Matrix4.identity();
        final k = t / 0.18;
        final a = math.sin(k * 6 * math.pi) * 0.30 * (1 - k);
        return Matrix4.rotationZ(a);
      case IconMotion.spin:
        return Matrix4.rotationZ(t * 2 * math.pi);
      case IconMotion.bounce:
        if (t > 0.30) return Matrix4.identity();
        final k = t / 0.30;
        return Matrix4.translationValues(0, -math.sin(k * math.pi) * 7, 0);
      case IconMotion.ring:
        // Campana: pivote en la parte alta, amortiguada, en el 30% del ciclo.
        if (t > 0.30) return Matrix4.identity();
        final k = t / 0.30;
        final a = math.sin(k * 8 * math.pi) * 0.42 * (1 - k);
        return _rotateAround(a, 0, -widget.size * 0.4);
      case IconMotion.tada:
        if (t > 0.26) return Matrix4.identity();
        final k = t / 0.26;
        final sc = 1 + 0.22 * math.sin(k * math.pi);
        final a = math.sin(k * 6 * math.pi) * 0.14 * math.sin(k * math.pi);
        return Matrix4.diagonal3Values(sc, sc, 1)..rotateZ(a);
      case IconMotion.heartbeat:
        // Dos latidos seguidos y un descanso.
        double b(double x, double c) =>
            math.exp(-math.pow((x - c) / 0.07, 2).toDouble());
        final s = 1 + 0.16 * b(t, 0.12) + 0.11 * b(t, 0.32);
        return Matrix4.diagonal3Values(s, s, 1);
      case IconMotion.swing:
        return _rotateAround(
            math.sin(t * 2 * math.pi) * 0.22, 0, -widget.size * 0.45);
      case IconMotion.write:
        if (t > 0.5) return Matrix4.identity();
        final k = t / 0.5;
        return Matrix4.translationValues(
            math.sin(k * 4 * math.pi) * 2.5 * (1 - k), 0, 0)
          ..rotateZ(math.sin(k * 4 * math.pi) * 0.22 * (1 - k));
      case IconMotion.none:
        return Matrix4.identity();
    }
  }

  /// Rota [angle] alrededor de un pivote desplazado (dx, dy) del centro.
  Matrix4 _rotateAround(double angle, double dx, double dy) =>
      Matrix4.translationValues(dx, dy, 0)
        ..rotateZ(angle)
        ..translateByDouble(-dx, -dy, 0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? IconTheme.of(context).color;
    final icon = Icon(
      widget.icon,
      size: widget.size,
      color: color,
      shadows: widget.glow && color != null
          ? [Shadow(color: color.withValues(alpha: 0.55), blurRadius: 14)]
          : null,
    );

    Widget body = AnimatedBuilder(
      animation: Listenable.merge([_enter, if (_loop != null) _loop!]),
      child: icon,
      builder: (_, child) {
        final e = Curves.elasticOut.transform(_enter.value.clamp(0.0, 1.0));
        final fade = Curves.easeOut.transform(_enter.value.clamp(0.0, 1.0));
        final loop = _loop == null
            ? Matrix4.identity()
            : _loopTransform(_loop!.value);
        return Opacity(
          opacity: fade,
          child: Transform.scale(
            scale: (0.3 + 0.7 * e) * (_hover ? 1.15 : 1.0),
            child: Transform(
              alignment: Alignment.center,
              transform: loop,
              child: child,
            ),
          ),
        );
      },
    );

    if (widget.halo && _loop != null && color != null) {
      final sz = widget.size;
      // El halo solo se DIBUJA más grande (Transform): si crecieran sus medidas, el
      // contenedor cambiaría de tamaño en cada cuadro y movería todo lo de alrededor.
      body = Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
        AnimatedBuilder(
          animation: _loop!,
          builder: (_, __) {
            // Número entero de ondas por ciclo: el bucle no tiene saltos.
            final waves = math.max(1, (_period.inMilliseconds / 2000).round());
            final k = (_loop!.value * waves) % 1.0;
            return IgnorePointer(
              child: Transform.scale(
                scale: 1.0 + 0.9 * k,
                child: Container(
                  width: sz,
                  height: sz,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: color.withValues(alpha: 0.38 * (1 - k)),
                      width: 2 / (1.0 + 0.9 * k),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        body,
      ]);
    }

    body = MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: RepaintBoundary(child: body),
    );

    if (widget.semanticLabel != null) {
      return Semantics(label: widget.semanticLabel, image: true, child: ExcludeSemantics(child: body));
    }
    return ExcludeSemantics(child: body);
  }
}
