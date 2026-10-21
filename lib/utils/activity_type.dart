import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../config/app_tokens.dart';
import '../widgets/ui/motion_icon.dart';

/// Tipo de actividad: etiqueta, ícono y color en un solo lugar.
/// Valores del backend: 'midterm', 'project', 'resource'; cualquier otro es "Otro".
class ActivityTypeInfo {
  const ActivityTypeInfo._(this.label, this.icon, this.motion);
  final String label;
  final IconData icon;

  /// Movimiento propio del tipo: el parcial late, el proyecto salta…
  final IconMotion motion;

  static ActivityTypeInfo of(String type) {
    switch (type) {
      case 'midterm':
        return const ActivityTypeInfo._('Parcial', PhosphorIconsRegular.exam, IconMotion.heartbeat);
      case 'project':
        return const ActivityTypeInfo._('Proyecto', PhosphorIconsRegular.folderOpen, IconMotion.bounce);
      case 'resource':
        return const ActivityTypeInfo._('Recurso', PhosphorIconsRegular.fileText, IconMotion.float);
      default:
        return const ActivityTypeInfo._('Otro', PhosphorIconsRegular.clipboardText, IconMotion.write);
    }
  }

  static Color colorOf(String type, AppTokens t) {
    switch (type) {
      case 'midterm':
        return t.typeParcial;
      case 'project':
        return t.typeProyecto;
      case 'resource':
        return t.typeRecurso;
      default:
        return t.typeOtro;
    }
  }
}
