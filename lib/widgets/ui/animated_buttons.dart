import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../config/app_tokens.dart';

/// Reacción del ícono de un [AnimatedIconButton] al pasar el cursor o tocar.
/// Cada tipo de botón usa la que "cuenta" su función.
enum IconReaction {
  /// Campana sonando (notificaciones).
  ring,

  /// Giro completo (actualizar, ajustes).
  spin,

  /// Crece y rebota (perfil, agregar).
  pop,

  /// Lápiz escribiendo (editar).
  write,

  /// Empuje lateral (flechas, siguiente).
  nudge,

  /// Voltea en 3D (calendario).
  flip,

  /// Sacudida rápida (eliminar).
  shake,

  /// Salto (ayuda, chat).
  bounce,
}

/// Aplica la transformación de [reaction] para el instante [t] (0..1).
Matrix4 reactionTransform(IconReaction reaction, double t, double size) {
  final env = math.sin(t * math.pi); // 0 → 1 → 0
  switch (reaction) {
    case IconReaction.ring:
      final a = math.sin(t * 7 * math.pi) * 0.5 * (1 - t);
      return Matrix4.translationValues(0, -size * 0.4, 0)
        ..rotateZ(a)
        ..translateByDouble(0.0, size * 0.4, 0.0, 1.0);
    case IconReaction.spin:
      return Matrix4.rotationZ(Curves.easeInOutCubic.transform(t) * 2 * math.pi);
    case IconReaction.pop:
      final s = 1 + 0.38 * env + 0.10 * math.sin(t * 3 * math.pi) * (1 - t);
      return Matrix4.diagonal3Values(s, s, 1);
    case IconReaction.write:
      return Matrix4.translationValues(math.sin(t * 5 * math.pi) * 2.5 * (1 - t), 0, 0)
        ..rotateZ(math.sin(t * 5 * math.pi) * 0.3 * (1 - t));
    case IconReaction.nudge:
      return Matrix4.translationValues(math.sin(t * 2 * math.pi) * 5, 0, 0);
    case IconReaction.flip:
      return Matrix4.identity()
        ..setEntry(3, 2, 0.003)
        ..rotateX(Curves.easeInOut.transform(t) * 2 * math.pi);
    case IconReaction.shake:
      return Matrix4.translationValues(math.sin(t * 9 * math.pi) * 3.2 * (1 - t), 0, 0)
        ..rotateZ(math.sin(t * 9 * math.pi) * 0.12 * (1 - t));
    case IconReaction.bounce:
      return Matrix4.translationValues(0, -math.sin(t * math.pi) * 8, 0);
  }
}

/// Botón de ícono con vida: halo al pasar el cursor, rebote de resorte al
/// presionar y una reacción propia del ícono ([reaction]).
///
/// Sustituye a `IconButton` en barras y tarjetas. Área táctil mínima de 44 px y
/// etiqueta semántica = [tooltip] (CU-07).
class AnimatedIconButton extends StatefulWidget {
  const AnimatedIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.reaction = IconReaction.pop,
    this.color,
    this.size = 22,
    this.filled = false,
    this.badge,
    this.custom,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final IconReaction reaction;
  final Color? color;
  final double size;

  /// Fondo sólido translúcido (botones sobre portadas de color).
  final bool filled;

  /// Contador opcional que aparece como globo con rebote.
  final int? badge;

  /// Reemplaza el ícono (p. ej. la foto de perfil) conservando las reacciones.
  final Widget? custom;

  @override
  State<AnimatedIconButton> createState() => _AnimatedIconButtonState();
}

class _AnimatedIconButtonState extends State<AnimatedIconButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 650));
  bool _hover = false;
  bool _down = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _play() {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return;
    _c.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ??
        IconTheme.of(context).color ??
        Theme.of(context).colorScheme.onSurface;
    final enabled = widget.onPressed != null;

    Widget icon = AnimatedBuilder(
      animation: _c,
      builder: (_, child) => Transform(
        alignment: Alignment.center,
        transform: reactionTransform(widget.reaction, _c.value, widget.size),
        child: child,
      ),
      child: widget.custom ??
          Icon(widget.icon,
              size: widget.size,
              color: enabled ? color : color.withValues(alpha: 0.4)),
    );

    final bg = widget.filled
        ? Colors.black.withValues(alpha: _hover ? 0.46 : 0.30)
        : color.withValues(alpha: _hover ? 0.16 : 0);

    Widget body = AnimatedScale(
      scale: _down ? 0.84 : (_hover ? 1.08 : 1.0),
      duration: Duration(milliseconds: _down ? 90 : 320),
      curve: _down ? Curves.easeOut : Curves.elasticOut,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 44, height: 44,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: icon,
      ),
    );

    if (widget.badge != null && widget.badge! > 0) {
      body = Stack(clipBehavior: Clip.none, children: [
        body,
        Positioned(
          right: 2, top: 2,
          child: _Badge(count: widget.badge!),
        ),
      ]);
    }

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.badge != null && widget.badge! > 0
          ? '${widget.tooltip}, ${widget.badge} sin leer'
          : widget.tooltip,
      excludeSemantics: true,
      onTap: widget.onPressed,
      child: Tooltip(
        message: widget.tooltip,
        excludeFromSemantics: true,
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
          onEnter: (_) {
            setState(() => _hover = true);
            _play();
          },
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: enabled ? (_) => setState(() => _down = true) : null,
            onTapCancel: () => setState(() => _down = false),
            onTapUp: (_) => setState(() => _down = false),
            onTap: enabled
                ? () {
                    HapticFeedback.selectionClick();
                    _play();
                    widget.onPressed!();
                  }
                : null,
            child: body,
          ),
        ),
      ),
    );
  }
}

/// Globo de contador: entra con rebote elástico cada vez que cambia el número
/// y emite un pulso suave mientras haya pendientes.
class _Badge extends StatefulWidget {
  const _Badge({required this.count});
  final int count;

  @override
  State<_Badge> createState() => _BadgeState();
}

class _BadgeState extends State<_Badge> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1800));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) {
      _pulse.stop();
    } else if (!_pulse.isAnimating) {
      _pulse.repeat();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final danger = context.tokens.danger;
    return TweenAnimationBuilder<double>(
      key: ValueKey(widget.count),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 600),
      curve: Curves.elasticOut,
      builder: (_, v, child) => Transform.scale(scale: v, child: child),
      child: Stack(alignment: Alignment.center, children: [
        AnimatedBuilder(
          animation: _pulse,
          builder: (_, __) => Container(
            width: 18 + 14 * _pulse.value,
            height: 18 + 14 * _pulse.value,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: danger.withValues(alpha: 0.35 * (1 - _pulse.value)),
            ),
          ),
        ),
        Container(
          constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: danger,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: Colors.white, width: 1.5),
            boxShadow: [
              BoxShadow(color: danger.withValues(alpha: 0.5), blurRadius: 6),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            widget.count > 9 ? '9+' : '${widget.count}',
            style: GoogleFonts.poppins(
                color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700,
                height: 1.2),
          ),
        ),
      ]),
    );
  }
}

enum AppButtonStyle { primary, tonal, danger, outline }

/// Botón principal de la app: degradado del tema, brillo que recorre el botón
/// al pasar el cursor (y una vez al aparecer), resorte al presionar y un
/// ícono con reacción. Muestra un indicador mientras [loading].
class AppButton extends StatefulWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.reaction = IconReaction.pop,
    this.style = AppButtonStyle.primary,
    this.loading = false,
    this.expand = false,
    this.height = 48,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final IconReaction reaction;
  final AppButtonStyle style;
  final bool loading;
  final bool expand;
  final double height;

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> with TickerProviderStateMixin {
  late final AnimationController _shine = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1100));
  late final AnimationController _icon = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 650));
  Timer? _welcome;
  bool _hover = false;
  bool _down = false;

  @override
  void initState() {
    super.initState();
    // Un destello de bienvenida: invita a tocar sin repetirse.
    _welcome = Timer(const Duration(milliseconds: 500), () {
      if (mounted && !(MediaQuery.maybeDisableAnimationsOf(context) ?? false)) {
        _shine.forward(from: 0);
      }
    });
  }

  @override
  void dispose() {
    _welcome?.cancel();
    _shine.dispose();
    _icon.dispose();
    super.dispose();
  }

  void _celebrate() {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return;
    _shine.forward(from: 0);
    _icon.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final cs = Theme.of(context).colorScheme;
    final enabled = widget.onPressed != null && !widget.loading;

    late final List<Color> bg;
    late final Color fg;
    BorderSide? border;
    switch (widget.style) {
      case AppButtonStyle.primary:
        bg = AppTokens.gradientOf(cs.primary);
        fg = Colors.white;
      case AppButtonStyle.danger:
        bg = [t.danger, Color.lerp(t.danger, Colors.orange, 0.35)!];
        fg = Colors.white;
      case AppButtonStyle.tonal:
        bg = [cs.primary.withValues(alpha: 0.16), cs.primary.withValues(alpha: 0.10)];
        fg = cs.primary;
      case AppButtonStyle.outline:
        bg = [Colors.transparent, Colors.transparent];
        fg = cs.primary;
        border = BorderSide(color: cs.primary.withValues(alpha: 0.55), width: 1.4);
    }
    final solid = widget.style == AppButtonStyle.primary ||
        widget.style == AppButtonStyle.danger;
    final radius = BorderRadius.circular(AppTokens.radiusControl + 4);

    final content = Row(
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.loading)
          SizedBox(
            width: 18, height: 18,
            child: CircularProgressIndicator(strokeWidth: 2.2, color: fg),
          )
        else if (widget.icon != null)
          AnimatedBuilder(
            animation: _icon,
            builder: (_, child) => Transform(
              alignment: Alignment.center,
              transform: reactionTransform(widget.reaction, _icon.value, 20),
              child: child,
            ),
            child: Icon(widget.icon, size: 20, color: fg),
          ),
        if (widget.loading || widget.icon != null) const SizedBox(width: 8),
        Flexible(
          child: Text(widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                  fontSize: 14, fontWeight: FontWeight.w600, color: fg)),
        ),
      ],
    );

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.loading ? '${widget.label}, cargando' : widget.label,
      excludeSemantics: true,
      onTap: enabled ? widget.onPressed : null,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) {
          setState(() => _hover = true);
          if (enabled && !_shine.isAnimating) _shine.forward(from: 0);
        },
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: enabled ? (_) => setState(() => _down = true) : null,
          onTapCancel: () => setState(() => _down = false),
          onTapUp: (_) => setState(() => _down = false),
          onTap: enabled
              ? () {
                  HapticFeedback.lightImpact();
                  _celebrate();
                  widget.onPressed!();
                }
              : null,
          child: AnimatedScale(
            scale: _down ? 0.95 : (_hover ? 1.025 : 1.0),
            duration: Duration(milliseconds: _down ? 90 : 300),
            curve: _down ? Curves.easeOut : Curves.elasticOut,
            child: Opacity(
              opacity: enabled || widget.loading ? 1 : 0.5,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: widget.height,
                constraints: const BoxConstraints(minWidth: 96),
                padding: const EdgeInsets.symmetric(horizontal: 22),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: bg),
                  borderRadius: radius,
                  border: border != null ? Border.fromBorderSide(border) : null,
                  boxShadow: solid
                      ? [
                          BoxShadow(
                            color: bg[0].withValues(alpha: _hover ? 0.55 : 0.34),
                            blurRadius: _hover ? 22 : 14,
                            offset: Offset(0, _hover ? 10 : 6),
                          ),
                        ]
                      : null,
                ),
                child: ClipRRect(
                  borderRadius: radius,
                  child: Stack(alignment: Alignment.center, children: [
                    Positioned.fill(
                      child: IgnorePointer(
                        child: AnimatedBuilder(
                          animation: _shine,
                          builder: (_, __) {
                            if (_shine.value == 0 || _shine.value == 1) {
                              return const SizedBox();
                            }
                            // Banda diagonal de luz que cruza el botón.
                            final x = -1.4 + 2.8 * Curves.easeInOut.transform(_shine.value);
                            return DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment(x - 0.5, -0.4),
                                  end: Alignment(x + 0.5, 0.4),
                                  colors: [
                                    Colors.white.withValues(alpha: 0),
                                    Colors.white.withValues(alpha: solid ? 0.42 : 0.22),
                                    Colors.white.withValues(alpha: 0),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    content,
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Envuelve cualquier widget con resorte al presionar y elevación al pasar el
/// cursor. Para tarjetas y celdas propias que no usan [AppCard].
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.pressedScale = 0.96,
    this.hoverScale = 1.02,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double pressedScale;
  final double hoverScale;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Listener(
        onPointerDown: (_) => setState(() => _down = true),
        onPointerUp: (_) => setState(() => _down = false),
        onPointerCancel: (_) => setState(() => _down = false),
        child: AnimatedScale(
          scale: _down ? widget.pressedScale : (_hover ? widget.hoverScale : 1),
          duration: Duration(milliseconds: _down ? 90 : 320),
          curve: _down ? Curves.easeOut : Curves.elasticOut,
          child: widget.child,
        ),
      ),
    );
  }
}
