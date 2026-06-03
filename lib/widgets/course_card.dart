import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'talk_widget.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/course_model.dart';

/// Tarjeta de curso con diseño moderno glassmorphism + gradientes vibrantes.
class CourseCard extends StatefulWidget {
  final CourseModel course;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  final VoidCallback? onEdit;
  final int index;
  /// Si true, oculta el botón "Abrir curso" (usado en la vista Admin de gestión)
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

  static const List<List<Color>> _gradients = [
    [Color(0xFF0052D4), Color(0xFF4364F7), Color(0xFF6FB1FC)],
    [Color(0xFF8E2DE2), Color(0xFF4A00E0), Color(0xFFB721FF)],
    [Color(0xFF11998E), Color(0xFF38EF7D), Color(0xFF00B09B)],
    [Color(0xFFEB3349), Color(0xFFF45C43), Color(0xFFFF6B6B)],
    [Color(0xFF1D976C), Color(0xFF93F9B9), Color(0xFF1D976C)],
    [Color(0xFFFF6B35), Color(0xFFF7C59F), Color(0xFFFF8E53)],
    [Color(0xFF373B44), Color(0xFF4286F4), Color(0xFF373B44)],
    [Color(0xFFDA22FF), Color(0xFF9733EE), Color(0xFFDA22FF)],
  ];

  static const List<IconData> _icons = [
    Icons.computer_rounded,
    Icons.science_rounded,
    Icons.calculate_rounded,
    Icons.biotech_rounded,
    Icons.architecture_rounded,
    Icons.psychology_rounded,
    Icons.menu_book_rounded,
    Icons.hub_rounded,
  ];

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
  late AnimationController _ctrl;
  late Animation<double> _entry;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _entry = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack);
    Future.delayed(
      Duration(milliseconds: 70 * widget.index.clamp(0, 12)),
      () { if (mounted) _ctrl.forward(); },
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = CourseCard.gradientFor(widget.course.imgCourse);
    final icon = CourseCard.iconFor(widget.course.imgCourse);
    final hasActions = widget.onEdit != null || widget.onDelete != null;

    return AnimatedBuilder(
      animation: _entry,
      builder: (_, child) => Transform.translate(
        offset: Offset(0, 28 * (1 - _entry.value)),
        child: Opacity(opacity: _entry.value.clamp(0.0, 1.0), child: child),
      ),
      child: Semantics(
        label: 'Curso: ${widget.course.name}, código ${widget.course.courseCode}',
        button: true,
        child: TalkWidget(
          label: 'Curso ${widget.course.name}, código ${widget.course.courseCode}',
          child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: AnimatedScale(
            scale: _hovered ? 1.03 : 1.0,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: colors[0].withOpacity(_hovered ? 0.45 : 0.18),
                    blurRadius: _hovered ? 28 : 10,
                    spreadRadius: _hovered ? 2 : 0,
                    offset: Offset(0, _hovered ? 10 : 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Material(
                  color: Colors.white,
                  child: InkWell(
                    onTap: widget.onTap,
                    splashColor: colors[0].withOpacity(0.12),
                    highlightColor: Colors.transparent,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildCover(colors, icon, hasActions),
                        _buildInfo(colors),
                      ],
                    ),
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

  Widget _buildCover(List<Color> colors, IconData icon, bool hasActions) {
    return Stack(
      children: [
        // Fondo gradiente animado
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          height: 90,
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: _hovered
                  ? [colors[1], colors[0], colors[2]]
                  : [colors[0], colors[1], colors[2]],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: CustomPaint(painter: _ModernPatternPainter(colors)),
        ),
        // Shimmer overlay al hacer hover
        if (_hovered)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withOpacity(0.0),
                    Colors.white.withOpacity(0.08),
                    Colors.white.withOpacity(0.0),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          ),
        // Botones admin
        if (hasActions)
          Positioned(
            top: 8, right: 8,
            child: Row(children: [
              if (widget.onEdit != null)
                _actionBtn(Icons.edit_rounded, 'Editar', widget.onEdit!,
                    Colors.white),
              if (widget.onDelete != null)
                _actionBtn(Icons.delete_rounded, 'Eliminar', widget.onDelete!,
                    Colors.red.shade200),
            ]),
          ),
        // Ícono central con efecto glass
        Positioned.fill(
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: EdgeInsets.all(_hovered ? 14 : 12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(_hovered ? 0.25 : 0.18),
                shape: BoxShape.circle,
                border: Border.all(
                    color: Colors.white.withOpacity(0.5),
                    width: _hovered ? 2.0 : 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white,
                  size: _hovered ? 28 : 24),
            ),
          ),
        ),
        // Número de código pequeño arriba izquierda
        Positioned(
          top: 8, left: 10,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.25),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              widget.course.courseCode,
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 8,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfo(List<Color> colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Nombre del curso
          Text(
            widget.course.name,
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1A1A2E),
              height: 1.25,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 10),
          // Botón Abrir — oculto cuando hideOpenButton = true (Admin)
          if (!widget.hideOpenButton) SizedBox(
            width: double.infinity,
            height: 34,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [colors[0], colors[1]],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(10),
                boxShadow: _hovered
                    ? [BoxShadow(
                        color: colors[0].withOpacity(0.40),
                        blurRadius: 10,
                        offset: const Offset(0, 4))]
                    : [],
              ),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  onTap: widget.onTap,
                  borderRadius: BorderRadius.circular(10),
                  splashColor: Colors.white24,
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.rocket_launch_rounded,
                            color: Colors.white, size: 13),
                        const SizedBox(width: 6),
                        Text('Abrir curso',
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.3,
                            )),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionBtn(IconData icon, String tooltip, VoidCallback onPressed,
      Color iconColor) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.all(3),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.30),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
          ),
          child: Icon(icon, color: iconColor, size: 14),
        ),
      ),
    );
  }
}

class _ModernPatternPainter extends CustomPainter {
  final List<Color> colors;
  const _ModernPatternPainter(this.colors);

  @override
  void paint(Canvas canvas, Size size) {
    final p1 = Paint()
      ..color = Colors.white.withOpacity(0.05)
      ..style = PaintingStyle.fill;
    final p2 = Paint()
      ..color = Colors.white.withOpacity(0.07)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Círculos decorativos
    final positions = [
      Offset(size.width * 0.80, size.height * 0.15),
      Offset(size.width * 0.90, size.height * 0.70),
      Offset(size.width * 0.10, size.height * 0.80),
      Offset(size.width * 0.15, size.height * 0.15),
    ];
    final radii = [40.0, 32.0, 28.0, 22.0];
    for (var i = 0; i < positions.length; i++) {
      canvas.drawCircle(positions[i], radii[i], p1);
      canvas.drawCircle(positions[i], radii[i], p2);
    }

    // Líneas diagonales sutiles
    final lp = Paint()
      ..color = Colors.white.withOpacity(0.04)
      ..strokeWidth = 12.0
      ..style = PaintingStyle.stroke;
    for (var i = -1; i < 4; i++) {
      final x = size.width * 0.25 * i;
      canvas.drawLine(Offset(x, 0), Offset(x + size.height, size.height), lp);
    }

    // Hexágono decorativo
    _drawHex(canvas, Offset(size.width * 0.62, size.height * 0.25), 16, p2);
    _drawHex(canvas, Offset(size.width * 0.92, size.height * 0.45), 12, p2);
  }

  void _drawHex(Canvas canvas, Offset center, double r, Paint paint) {
    final path = Path();
    for (var i = 0; i < 6; i++) {
      final angle = math.pi / 3 * i - math.pi / 6;
      final x = center.dx + r * math.cos(angle);
      final y = center.dy + r * math.sin(angle);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ModernPatternPainter old) => false;
}
