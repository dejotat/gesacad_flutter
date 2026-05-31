import 'package:flutter/material.dart';
import '../../services/api_service.dart';

/// Pantalla de calificaciones del estudiante en un curso (CU-06 / RF10).
///
/// Muestra:
/// - Promedio ponderado actual (suma(nota × ponderado) / suma(ponderados)).
/// - Indicador visual de estado: aprobando (verde, ≥ 3.0) o en riesgo (rojo, < 3.0).
/// - Lista detallada por actividad con nota y ponderado.
///
/// Escala de calificación colombiana universitaria (0.0 – 5.0):
/// - ≥ 4.0: Excelente (verde).
/// - ≥ 3.0: Aprobado (naranja).
/// -  < 3.0: Reprobado (rojo).
/// - Nota aprobatoria mínima: 3.0 (según Decreto 1295 de 2010).
///
/// Implementa [Semantics] para compatibilidad con TalkBack (CU-07/RNF03).
class GradesScreen extends StatefulWidget {
  /// ID del curso del que se muestran las calificaciones.
  final int courseId;

  /// ID del estudiante autenticado.
  final int userId;

  /// Nombre del curso para mostrar en el contexto de la pantalla.
  final String courseName;

  const GradesScreen({
    super.key,
    required this.courseId,
    required this.userId,
    required this.courseName,
  });

  @override
  State<GradesScreen> createState() => _GradesScreenState();
}

class _GradesScreenState extends State<GradesScreen> {
  List<Map<String, dynamic>> _grades = [];
  bool _loading = true;

  /// Promedio ponderado calculado localmente.
  double _promedio = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Carga las calificaciones del estudiante en el curso y calcula el promedio.
  ///
  /// El promedio se calcula como: Σ(nota × ponderado) / Σ(ponderados calificados).
  /// Solo se incluyen actividades con nota asignada (GPA != null) en el cálculo.
  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _grades =
          await ApiService().getGrades(widget.courseId, widget.userId);
      if (_grades.isNotEmpty) {
        double total = 0;
        double totalWeight = 0;
        for (final g in _grades) {
          final gpa = double.tryParse(g['GPA']?.toString() ?? '');
          final w =
              double.tryParse(g['weighting']?.toString() ?? '0') ?? 0;
          if (gpa != null) {
            // Solo incluir actividades calificadas en el promedio.
            total += gpa * w;
            totalWeight += w;
          }
        }
        _promedio = totalWeight > 0 ? total / totalWeight : 0;
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  /// Retorna el color semántico para una nota según la escala colombiana.
  ///
  /// - null: gris (sin calificar).
  /// - ≥ 4.0: verde (excelente).
  /// - ≥ 3.0: naranja (aprobado).
  /// -  < 3.0: rojo (reprobado).
  Color _gradeColor(double? gpa) {
    if (gpa == null) return Colors.grey;
    if (gpa >= 4.0) return Colors.green;
    if (gpa >= 3.0) return Colors.orange;
    return Colors.red;
  }

  /// Etiqueta de estado de la nota para TalkBack.
  String _gradeLabel(double? gpa) {
    if (gpa == null) return 'Sin calificar';
    if (gpa >= 4.0) return 'Excelente';
    if (gpa >= 3.0) return 'Aprobado';
    return 'Reprobado';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_grades.isEmpty) {
      return const Center(
          child: Text('No hay calificaciones aún',
              style: TextStyle(color: Colors.grey)));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildPromedio(),
        const SizedBox(height: 16),
        const Text('Detalle por actividad',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        ..._grades.map((g) {
          final gpa = double.tryParse(g['GPA']?.toString() ?? '');
          final weight =
              double.tryParse(g['weighting']?.toString() ?? '0') ?? 0;
          final title = g['tittle']?.toString() ?? '';

          return Semantics(
            label:
                'Actividad: $title, ponderado: ${(weight * 100).toStringAsFixed(0)} por ciento, '
                'nota: ${gpa != null ? gpa.toStringAsFixed(1) : 'sin calificar'}, '
                '${_gradeLabel(gpa)}',
            child: Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: _gradeColor(gpa).withOpacity(0.15),
                  child: Text(
                    gpa != null ? gpa.toStringAsFixed(1) : '-',
                    style: TextStyle(
                        color: _gradeColor(gpa),
                        fontWeight: FontWeight.bold,
                        fontSize: 13),
                  ),
                ),
                title: Text(title,
                    style:
                        const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                    'Ponderado: ${(weight * 100).toStringAsFixed(0)}%'),
                trailing: gpa != null
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _gradeColor(gpa).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          gpa.toStringAsFixed(1),
                          style: TextStyle(
                              color: _gradeColor(gpa),
                              fontWeight: FontWeight.bold),
                        ),
                      )
                    : const Text('Sin nota',
                        style:
                            TextStyle(color: Colors.grey, fontSize: 12)),
              ),
            ),
          );
        }),
      ],
    );
  }

  /// Widget del promedio ponderado con indicador visual de aprobación.
  Widget _buildPromedio() {
    final aprobando = _promedio >= 3.0;
    return Semantics(
      label: 'Promedio actual: ${_promedio.toStringAsFixed(2)}, '
          '${aprobando ? 'aprobando' : 'en riesgo académico'}',
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: aprobando
                ? [const Color(0xFF1B5E20), const Color(0xFF388E3C)]
                : [const Color(0xFFB71C1C), const Color(0xFFE53935)],
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            const Icon(Icons.auto_graph, color: Colors.white, size: 40),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Promedio actual',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
                Text(
                  _promedio.toStringAsFixed(2),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.bold),
                ),
                Text(
                  aprobando ? 'Aprobando ✓' : 'En riesgo ✗',
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
