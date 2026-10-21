import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../config/app_tokens.dart';
import '../models/course_model.dart';
import 'talk_widget.dart';
import 'ui/animated_buttons.dart';
import 'ui/motion_icon.dart';

/// Tarjeta de curso: portada de color sobrio con ícono, nombre y código.
/// Toda la tarjeta es un único destino táctil.
class CourseCard extends StatefulWidget {
  final CourseModel course;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  final VoidCallback? onEdit;
  final int index;

  /// Si true, oculta la indicación "Abrir curso" (vista Admin de gestión).
  final bool hideOpenButton;

  const CourseCard({
    super.key,
    required this.course,
    required this.onTap,
    this.onDelete,
    this.onEdit,
    this.index = 0,
    this.hideOpenButton = false,
  });

  /// Pares de degradado vivos (texto blanco encima con buen contraste).
  static const List<List<Color>> _gradients = [
    [Color(0xFF2563EB), Color(0xFF06B6D4)], // azul → cian
    [Color(0xFF7C3AED), Color(0xFFEC4899)], // violeta → rosa
    [Color(0xFF059669), Color(0xFF22D3EE)], // esmeralda → turquesa
    [Color(0xFFE11D48), Color(0xFFF59E0B)], // carmín → ámbar
    [Color(0xFF0D9488), Color(0xFF84CC16)], // teal → lima
    [Color(0xFFEA580C), Color(0xFFEF4444)], // naranja → rojo
    [Color(0xFF4F46E5), Color(0xFF0EA5E9)], // índigo → cielo
    [Color(0xFFC026D3), Color(0xFF6366F1)], // fucsia → índigo
  ];

  static const List<IconData> _icons = [
    PhosphorIconsRegular.code,
    PhosphorIconsRegular.flask,
    PhosphorIconsRegular.calculator,
    PhosphorIconsRegular.dna,
    PhosphorIconsRegular.compass,
    PhosphorIconsRegular.brain,
    PhosphorIconsRegular.bookOpen,
    PhosphorIconsRegular.graph,
  ];

  /// Cada materia mueve su ícono a su manera (código teclea, el matraz burbujea…).
  static const List<IconMotion> _motions = [
    IconMotion.write,      // code
    IconMotion.wiggle,     // flask
    IconMotion.pulse,      // calculator
    IconMotion.spin,       // dna
    IconMotion.swing,      // compass
    IconMotion.heartbeat,  // brain
    IconMotion.float,      // book
    IconMotion.bounce,     // graph
  ];

  static IconMotion motionFor(int imgCourse) =>
      _motions[(imgCourse - 1).clamp(0, _motions.length - 1)];

  static List<Color> gradientFor(int imgCourse) {
    final idx = (imgCourse - 1).clamp(0, _gradients.length - 1);
    return _gradients[idx];
  }

  static IconData iconFor(int imgCourse) {
    final idx = (imgCourse - 1).clamp(0, _icons.length - 1);
    return _icons[idx];
  }

  @override
  State<CourseCard> createState() => _CourseCardState();
}

class _CourseCardState extends State<CourseCard>
    with SingleTickerProviderStateMixin {
  bool _hovered = false;

  /// Reloj de la portada: mueve las luces de fondo (ciclo de 14 s sin saltos).
  late final AnimationController _aurora =
      AnimationController(vsync: this, duration: const Duration(seconds: 14));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) {
      _aurora.stop();
    } else if (!_aurora.isAnimating) {
      _aurora.repeat();
    }
  }

  @override
  void dispose() {
    _aurora.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = CourseCard.gradientFor(widget.course.imgCourse);
    final icon = CourseCard.iconFor(widget.course.imgCourse);
    final t = context.tokens;
    final cs = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(AppTokens.radiusCard);

    return Semantics(
      label: 'Curso: ${widget.course.name}, código ${widget.course.courseCode}',
      button: true,
      // Con botones de administración (editar/eliminar) deben seguir accesibles.
      excludeSemantics: widget.onEdit == null && widget.onDelete == null,
      onTap: widget.onTap,
      child: TalkWidget(
        label: 'Curso ${widget.course.name}, código ${widget.course.courseCode}',
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: Pressable(
            hoverScale: 1.03,
            pressedScale: 0.97,
            child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: radius,
              border: Border.all(color: _hovered ? colors[1] : t.border),
              boxShadow: _hovered
                  ? [BoxShadow(
                      color: colors[0].withValues(alpha: 0.18),
                      blurRadius: 16,
                      offset: const Offset(0, 6))]
                  : t.cardShadow,
            ),
            child: ClipRRect(
              borderRadius: radius,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: widget.onTap,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildCover(colors, icon),
                      _buildInfo(colors, cs, t),
                    ],
                  ),
                ),
              ),
            ),
          ),
          ),
        ),
      ),
    );
  }

  Widget _buildCover(List<Color> colors, IconData icon) {
    final hasActions = widget.onEdit != null || widget.onDelete != null;
    final delay = Duration(milliseconds: 80 * widget.index.clamp(0, 10));
    return Container(
      height: 96,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(children: [
        // Aurora: tres luces que derivan lentamente (decorativo).
        Positioned.fill(
          child: ExcludeSemantics(
            child: AnimatedBuilder(
              animation: _aurora,
              builder: (_, __) => CustomPaint(painter: _AuroraPainter(_aurora.value)),
            ),
          ),
        ),
        // Medallón de cristal con el ícono animado de la materia.
        Center(
          child: ExcludeSemantics(
            child: Container(
              width: 62, height: 62,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.18),
                border: Border.all(color: Colors.white.withValues(alpha: 0.55)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.white.withValues(alpha: _hovered ? 0.45 : 0.18),
                    blurRadius: _hovered ? 26 : 14,
                  ),
                ],
              ),
              child: Center(
                child: MotionIcon(icon,
                    color: Colors.white,
                    size: 32,
                    glow: true,
                    halo: _hovered,
                    motion: CourseCard.motionFor(widget.course.imgCourse),
                    delay: delay),
              ),
            ),
          ),
        ),
        Positioned(
          top: 8, left: 10,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              widget.course.courseCode,
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
        if (hasActions)
          Positioned(
            top: 2, right: 2,
            child: Row(children: [
              if (widget.onEdit != null)
                _actionBtn(PhosphorIconsRegular.pencilSimple, 'Editar',
                    IconReaction.write, widget.onEdit!),
              if (widget.onDelete != null)
                _actionBtn(PhosphorIconsRegular.trash, 'Eliminar',
                    IconReaction.shake, widget.onDelete!),
            ]),
          ),
      ]),
    );
  }

  Widget _buildInfo(List<Color> colors, ColorScheme cs, AppTokens t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.course.name,
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
              height: 1.25,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (!widget.hideOpenButton) ...[
            const SizedBox(height: 8),
            Row(children: [
              Text('Abrir curso',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: cs.brightness == Brightness.dark
                        ? colors[1]
                        : colors[0],
                  )),
              const SizedBox(width: 4),
              AnimatedSlide(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutBack,
                offset: Offset(_hovered ? 0.7 : 0, 0),
                child: Icon(PhosphorIconsRegular.arrowRight,
                    size: 14,
                    color: cs.brightness == Brightness.dark
                        ? colors[1]
                        : colors[0]),
              ),
            ]),
          ],
        ],
      ),
    );
  }

  /// Botón de administración sobre la portada: reacciona según su función.
  Widget _actionBtn(IconData icon, String tooltip, IconReaction reaction,
      VoidCallback onPressed) {
    return AnimatedIconButton(
      tooltip: tooltip,
      icon: icon,
      reaction: reaction,
      size: 18,
      color: Colors.white,
      filled: true,
      onPressed: onPressed,
    );
  }
}

/// Luces difusas que derivan en trayectorias de Lissajous (bucle sin saltos).
class _AuroraPainter extends CustomPainter {
  _AuroraPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final tau = 2 * math.pi;
    void luz(double fx, double fy, double ph, double r, double a) {
      final c = Offset(
        size.width * (0.5 + 0.42 * math.sin(t * tau * fx + ph)),
        size.height * (0.5 + 0.40 * math.cos(t * tau * fy + ph * 1.7)),
      );
      canvas.drawCircle(
        c, r,
        Paint()
          ..shader = RadialGradient(colors: [
            Colors.white.withValues(alpha: a),
            Colors.white.withValues(alpha: 0),
          ]).createShader(Rect.fromCircle(center: c, radius: r)),
      );
    }

    luz(1, 1, 0.0, size.height * 0.95, 0.30);
    luz(2, 1, 2.1, size.height * 0.70, 0.20);
    luz(1, 2, 4.2, size.height * 0.80, 0.16);
  }

  @override
  bool shouldRepaint(covariant _AuroraPainter old) => old.t != t;
}
