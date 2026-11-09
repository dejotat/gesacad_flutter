import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Fondo cinematográfico para pantallas de entrada (login): verde azulado profundo (el color del
/// tema Neón; el negro se rechazó) con una aurora de luz que deriva lentamente, partículas que titilan unidas por líneas tenues, una cuadrícula
/// apenas visible y un viñeteado que enfoca el contenido.
///
/// Diseño pensado para rendimiento y accesibilidad:
/// * Las capas estáticas (base, cuadrícula, viñeta) están en su propio `RepaintBoundary`: se
///   dibujan UNA vez; solo la capa de movimiento se repinta, con un único `AnimationController`.
/// * Todo el movimiento es periódico (ciclos enteros por minuto): el bucle no tiene saltos.
/// * Es puramente decorativo: no entra en el árbol de accesibilidad ni recibe toques.
/// * Respeta "reducir movimiento" del sistema (`MediaQuery.disableAnimations`): queda un
///   cuadro fijo, sin animación. `TickerMode` la pausa sola cuando otra pantalla la tapa.
class CinematicBackdrop extends StatefulWidget {
  const CinematicBackdrop({super.key, required this.child});

  /// Contenido que se dibuja encima del fondo.
  final Widget child;

  @override
  State<CinematicBackdrop> createState() => _CinematicBackdropState();
}

class _CinematicBackdropState extends State<CinematicBackdrop>
    with SingleTickerProviderStateMixin {
  /// Duración del ciclo completo. Todo el movimiento da vueltas enteras en este lapso.
  static const _ciclo = Duration(seconds: 60);

  late final AnimationController _c =
      AnimationController(vsync: this, duration: _ciclo);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reducir = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reducir) {
      // Un cuadro fijo y agradable: sin movimiento.
      _c
        ..stop()
        ..value = 0.18;
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Decorativo: fuera del árbol de accesibilidad y sin interceptar toques.
        ExcludeSemantics(
          child: IgnorePointer(
            child: Stack(
              fit: StackFit.expand,
              children: [
                const RepaintBoundary(child: CustomPaint(painter: _BasePainter())),
                RepaintBoundary(child: CustomPaint(painter: _MotionPainter(_c))),
                const RepaintBoundary(child: CustomPaint(painter: _VignettePainter())),
              ],
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

// ── Capa 1 (estática): verde azulado profundo + cuadrícula que se desvanece hacia los bordes ──────────

class _BasePainter extends CustomPainter {
  const _BasePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF07302C), Color(0xFF0A3C37), Color(0xFF05221F)],
          stops: [0, 0.55, 1],
        ).createShader(rect),
    );

    // Cuadrícula muy tenue, enmascarada con un degradado radial (más visible al centro).
    canvas.saveLayer(rect, Paint());
    final linea = Paint()
      ..color = const Color(0x14FFFFFF)
      ..strokeWidth = 1;
    const paso = 56.0;
    for (double x = 0; x <= size.width; x += paso) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), linea);
    }
    for (double y = 0; y <= size.height; y += paso) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linea);
    }
    canvas.drawRect(
      rect,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = const RadialGradient(
          center: Alignment(0, -0.2),
          radius: 0.85,
          colors: [Colors.white, Color(0x00FFFFFF)],
        ).createShader(rect),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Capa 2 (animada): aurora aditiva + partículas con constelación ────────────────────────────

class _Blob {
  const _Blob(this.color, this.x, this.y, this.ax, this.ay, this.kx, this.ky, this.fase,
      this.radio, this.alfa);
  final Color color;
  final double x, y; // centro base (0..1)
  final double ax, ay; // amplitud del desplazamiento (fracción del ancho/alto)
  final int kx, ky; // ciclos por minuto (enteros → bucle sin saltos)
  final double fase; // 0..1
  final double radio; // fracción de la dimensión mayor
  final double alfa;
}

class _Particula {
  const _Particula(this.x, this.y, this.sube, this.oscila, this.kOscila, this.fase, this.radio,
      this.kBrillo, this.cian);
  final double x, y;
  final int sube; // vueltas verticales por minuto
  final double oscila; // amplitud lateral
  final int kOscila, kBrillo;
  final double fase, radio;
  final bool cian;
}

class _MotionPainter extends CustomPainter {
  _MotionPainter(this.t) : super(repaint: t);

  final Animation<double> t;

  static const _blobs = <_Blob>[
    _Blob(Color(0xFF2DD4BF), 0.18, 0.22, 0.14, 0.10, 1, 2, 0.00, 0.58, 0.22), // turquesa
    _Blob(Color(0xFF22D3EE), 0.84, 0.28, 0.12, 0.14, 2, 1, 0.31, 0.54, 0.14), // cian
    _Blob(Color(0xFF65A30D), 0.55, 0.88, 0.18, 0.08, 1, 1, 0.57, 0.60, 0.20), // verde lima
    _Blob(Color(0xFFA3E635), 0.92, 0.82, 0.10, 0.12, 2, 3, 0.74, 0.32, 0.10), // lima viva
    _Blob(Color(0xFF10B981), 0.06, 0.80, 0.10, 0.10, 3, 2, 0.12, 0.28, 0.12), // esmeralda
  ];

  static final List<_Particula> _particulas = () {
    final r = math.Random(20261104);
    return List.generate(
      46,
      (_) => _Particula(
        r.nextDouble(),
        r.nextDouble(),
        1 + r.nextInt(3),
        0.01 + r.nextDouble() * 0.025,
        1 + r.nextInt(3),
        r.nextDouble(),
        0.8 + r.nextDouble() * 1.5,
        2 + r.nextInt(4),
        r.nextBool(),
      ),
    );
  }();

  static const _dosPi = math.pi * 2;

  @override
  void paint(Canvas canvas, Size size) {
    final v = t.value; // 0..1 sobre un ciclo de 60 s
    final mayor = math.max(size.width, size.height);

    // Aurora: manchas de luz en mezcla ADITIVA sobre el negro (se suman, no se tapan).
    for (final b in _blobs) {
      final cx = size.width * (b.x + b.ax * math.sin(_dosPi * (b.kx * v + b.fase)));
      final cy = size.height * (b.y + b.ay * math.cos(_dosPi * (b.ky * v + b.fase)));
      final r = mayor * b.radio * (1 + 0.07 * math.sin(_dosPi * (2 * v + b.fase)));
      final centro = Offset(cx, cy);
      canvas.drawCircle(
        centro,
        r,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = RadialGradient(
            colors: [b.color.withValues(alpha: b.alfa), b.color.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: centro, radius: r)),
      );
    }

    // Partículas: menos en pantallas pequeñas.
    final n = size.width < 520 ? 28 : _particulas.length;
    final pos = List<Offset>.filled(n, Offset.zero);
    final brillo = List<double>.filled(n, 0);
    for (var i = 0; i < n; i++) {
      final p = _particulas[i];
      final y = ((p.y - p.sube * v) % 1.0 + 1.0) % 1.0; // sube y reaparece abajo
      final x = p.x + p.oscila * math.sin(_dosPi * (p.kOscila * v + p.fase));
      pos[i] = Offset(x * size.width, y * size.height);
      brillo[i] = 0.30 + 0.70 * (0.5 + 0.5 * math.sin(_dosPi * (p.kBrillo * v + p.fase)));
    }

    // Constelación: líneas entre partículas cercanas, más tenues cuanto más lejos.
    final enlace = math.min(150.0, mayor * 0.16);
    final lapiz = Paint()
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < n; i++) {
      for (var j = i + 1; j < n; j++) {
        final d = (pos[i] - pos[j]).distance;
        if (d < enlace) {
          lapiz.color = const Color(0xFF99F6E4)
              .withValues(alpha: (1 - d / enlace) * 0.16 * math.min(brillo[i], brillo[j]));
          canvas.drawLine(pos[i], pos[j], lapiz);
        }
      }
    }

    final punto = Paint();
    for (var i = 0; i < n; i++) {
      final p = _particulas[i];
      final c = p.cian ? const Color(0xFF67E8F9) : const Color(0xFFD9F99D);
      punto.color = c.withValues(alpha: 0.10 * brillo[i]);
      canvas.drawCircle(pos[i], p.radio * 3.6, punto); // halo
      punto.color = c.withValues(alpha: 0.85 * brillo[i]);
      canvas.drawCircle(pos[i], p.radio, punto); // núcleo
    }
  }

  @override
  bool shouldRepaint(covariant _MotionPainter old) => old.t != t;
}

// ── Capa 3 (estática): viñeteado que oscurece los bordes y enfoca el centro ───────────────────

class _VignettePainter extends CustomPainter {
  const _VignettePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0, -0.1),
          radius: 1.05,
          colors: [Color(0x00000000), Color(0xB3021410)],
          stops: [0.38, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
