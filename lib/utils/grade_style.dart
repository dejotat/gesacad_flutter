import 'package:flutter/material.dart';
import '../config/app_tokens.dart';

/// Umbrales y colores de nota en un solo lugar (escala 0–5, aprueba con 3.0).
/// ≥ 4.0 sobresaliente · ≥ 3.0 aprobado · < 3.0 en riesgo · null sin nota.
class GradeStyle {
  GradeStyle._();

  static const double pass = 3.0;
  static const double high = 4.0;

  static Color color(double? g, AppTokens t) {
    if (g == null) return t.muted;
    if (g >= high) return t.success;
    if (g >= pass) return t.warning;
    return t.danger;
  }

  static String label(double? g) {
    if (g == null) return 'Sin notas';
    if (g >= high) return 'Sobresaliente';
    if (g >= pass) return 'Aprobando';
    return 'En riesgo';
  }
}
