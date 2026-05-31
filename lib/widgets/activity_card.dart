import 'package:flutter/material.dart';
import '../models/activity_model.dart';

/// Widget de tarjeta para mostrar una actividad evaluable en la lista del curso.
///
/// Muestra el título, tipo, ponderado, estado de entrega y calificación.
/// Soporta acción opcional de eliminación (solo 'Teacher' propietario).
/// Implementa [Semantics] para compatibilidad con TalkBack (CU-07/RNF03).
class ActivityCard extends StatelessWidget {
  /// Modelo de la actividad a mostrar.
  final ActivityModel activity;

  /// Callback ejecutado al tocar la tarjeta (navega al detalle de la actividad).
  final VoidCallback onTap;

  /// Callback de eliminación. Si es null, no se muestra el botón de eliminar.
  final VoidCallback? onDelete;

  const ActivityCard({
    super.key,
    required this.activity,
    required this.onTap,
    this.onDelete,
  });

  /// Color identificador del tipo de actividad.
  Color get _typeColor {
    switch (activity.type) {
      case 'midterm':
        return Colors.orange;
      case 'project':
        return Colors.blue;
      case 'resource':
        return Colors.green;
      default:
        return Colors.purple;
    }
  }

  /// Etiqueta en español del tipo de actividad.
  String get _typeLabel {
    switch (activity.type) {
      case 'midterm':
        return 'Parcial';
      case 'project':
        return 'Proyecto';
      case 'resource':
        return 'Recurso';
      default:
        return 'Otro';
    }
  }

  /// Ícono representativo del tipo de actividad.
  IconData get _typeIcon {
    switch (activity.type) {
      case 'midterm':
        return Icons.quiz_outlined;
      case 'project':
        return Icons.folder_outlined;
      case 'resource':
        return Icons.description_outlined;
      default:
        return Icons.assignment_outlined;
    }
  }

  /// Descripción accesible del estado actual de la actividad para TalkBack (CU-07).
  String get _semanticLabel {
    final weightStr =
        '${(activity.weighting * 100).toStringAsFixed(0)} por ciento';
    if (activity.gpa != null) {
      return 'Actividad ${activity.tittle}, tipo $_typeLabel, ponderado $weightStr, calificación ${activity.gpa!.toStringAsFixed(1)} de 5.';
    }
    if (activity.isDelivered) {
      return 'Actividad ${activity.tittle}, tipo $_typeLabel, ponderado $weightStr, entregada, pendiente de calificación.';
    }
    if (activity.isPastDue) {
      return 'Actividad ${activity.tittle}, tipo $_typeLabel, ponderado $weightStr, plazo vencido.';
    }
    return 'Actividad ${activity.tittle}, tipo $_typeLabel, ponderado $weightStr, pendiente de entrega.';
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: _semanticLabel,
      hint: 'Toca dos veces para ver el detalle de la actividad',
      button: true,
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 2,
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: CircleAvatar(
            backgroundColor: _typeColor.withOpacity(0.15),
            child: Icon(_typeIcon, color: _typeColor, size: 22),
          ),
          title: Text(
            activity.tittle,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: _typeColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(_typeLabel,
                        style: TextStyle(color: _typeColor, fontSize: 11)),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${(activity.weighting * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
              if (activity.isPastDue) ...[
                const SizedBox(height: 4),
                const Text('⏰ Plazo vencido',
                    style: TextStyle(color: Colors.red, fontSize: 11)),
              ],
              if (activity.isDelivered) ...[
                const SizedBox(height: 4),
                const Text('✅ Entregado',
                    style: TextStyle(color: Colors.green, fontSize: 11)),
              ],
              if (activity.gpa != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Nota: ${activity.gpa!.toStringAsFixed(1)}',
                  style: const TextStyle(
                      color: Colors.indigo,
                      fontSize: 12,
                      fontWeight: FontWeight.bold),
                ),
              ],
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onDelete != null)
                Semantics(
                  label: 'Eliminar actividad ${activity.tittle}',
                  button: true,
                  child: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: onDelete,
                    tooltip: 'Eliminar actividad',
                  ),
                ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
          onTap: onTap,
        ),
      ),
    );
  }
}
