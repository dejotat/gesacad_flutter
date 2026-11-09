import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../config/app_tokens.dart';

/// Cuadrícula de tarjetas de curso del Estudiante y del Docente.
///
/// * **Tamaño uniforme**: todas miden lo mismo (ancho máximo 260, alto 220); la última fila no se
///   estira.
/// * **Alineada con el panel**: el resumen de arriba está centrado en 1100 px; la cuadrícula usa
///   el mismo margen. Antes quedaba pegada al borde de la pantalla, desalineada con él.
/// * Cada tarjeta aparece con un fundido y una ligera escala, una tras otra.
class SliverCourseGrid extends StatelessWidget {
  const SliverCourseGrid({
    super.key,
    required this.count,
    required this.itemBuilder,
    this.maxWidth = 1100,
    this.bottom = 100,
  });

  final int count;
  final Widget Function(int index) itemBuilder;

  /// Ancho máximo del contenido del panel (el mismo del resto de la pantalla).
  final double maxWidth;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(builder: (context, c) {
      final lado = math.max(0.0, (c.crossAxisExtent - maxWidth) / 2) + AppTokens.pagePadding;
      return SliverPadding(
        padding: EdgeInsets.fromLTRB(lado, 0, lado, bottom),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 260,
            mainAxisExtent: 220,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
          ),
          delegate: SliverChildBuilderDelegate(
            (_, i) => AparecerAlCargar(index: i, child: itemBuilder(i)),
            childCount: count,
          ),
        ),
      );
    });
  }
}

/// Fundido + escala + subida suave al aparecer, escalonado por [index] (máx. 8 pasos).
/// Respeta «reducir movimiento»: entonces no anima.
class AparecerAlCargar extends StatefulWidget {
  const AparecerAlCargar({super.key, required this.child, this.index = 0});
  final Widget child;
  final int index;

  @override
  State<AparecerAlCargar> createState() => _AparecerAlCargarState();
}

class _AparecerAlCargarState extends State<AparecerAlCargar> with SingleTickerProviderStateMixin {
  static const _duracion = 460;
  late final int _retraso = 70 * math.min(widget.index, 8);

  // El retraso va DENTRO de la animación (un tramo inicial quieto): sin temporizadores sueltos.
  late final AnimationController _c =
      AnimationController(vsync: this, duration: Duration(milliseconds: _duracion + _retraso));
  late final Animation<double> _t = CurvedAnimation(
      parent: _c, curve: Interval(_retraso / (_duracion + _retraso), 1, curve: Curves.easeOutCubic));
  bool _iniciada = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_iniciada) return;
    _iniciada = true;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      child: widget.child,
      builder: (_, child) => Opacity(
        opacity: _t.value,
        child: Transform.translate(
          offset: Offset(0, 14 * (1 - _t.value)),
          child: Transform.scale(scale: 0.94 + 0.06 * _t.value, child: child),
        ),
      ),
    );
  }
}
