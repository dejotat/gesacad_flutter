import 'package:flutter/material.dart';

/// Tokens de diseño de GESACAD (colores semánticos, gráficos, vidrio, radios,
/// espaciado). Se leen con `context.tokens`; así las pantallas no hardcodean
/// colores y funcionan igual en tema claro y oscuro.
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
    required this.chart,
    required this.typeParcial,
    required this.typeProyecto,
    required this.typeRecurso,
    required this.typeOtro,
    required this.border,
    required this.muted,
    required this.cardShadow,
    required this.glass,
    required this.glassBorder,
    required this.glassHighlight,
  });

  final Color success;
  final Color warning;
  final Color danger;
  final Color info;

  /// Paleta categórica de gráficos: 6 tonos vivos y bien separados.
  final List<Color> chart;

  final Color typeParcial;
  final Color typeProyecto;
  final Color typeRecurso;
  final Color typeOtro;

  /// Borde de 1 px de cards y contenedores.
  final Color border;

  /// Texto secundario (etiquetas, subtítulos). Contraste ≥ 4.5:1 sobre surface.
  final Color muted;

  final List<BoxShadow> cardShadow;

  /// Relleno translúcido de paneles de vidrio, su borde de luz y el brillo
  /// superior (esquina iluminada del cristal).
  final Color glass;
  final Color glassBorder;
  final Color glassHighlight;

  // Radios y espaciado (múltiplos de 4).
  static const double radiusControl = 14;
  static const double radiusCard = 20;
  static const double gap = 8;
  static const double pagePadding = 16;
  static const double sectionGap = 24;

  static const light = AppTokens(
    success: Color(0xFF059669),
    warning: Color(0xFFD97706),
    danger: Color(0xFFE11D48),
    info: Color(0xFF0284C7),
    chart: [
      Color(0xFF7C3AED), // violeta
      Color(0xFF06B6D4), // cian
      Color(0xFFF43F5E), // rosa
      Color(0xFFF59E0B), // ámbar
      Color(0xFF10B981), // esmeralda
      Color(0xFF3B82F6), // azul
    ],
    typeParcial: Color(0xFFF59E0B),
    typeProyecto: Color(0xFF3B82F6),
    typeRecurso: Color(0xFF10B981),
    typeOtro: Color(0xFF8B5CF6),
    border: Color(0x26475569),
    muted: Color(0xFF52607A),
    cardShadow: [
      BoxShadow(color: Color(0x1F4C1D95), blurRadius: 28, offset: Offset(0, 10)),
    ],
    glass: Color(0x8CFFFFFF),
    glassBorder: Color(0xCCFFFFFF),
    glassHighlight: Color(0xB3FFFFFF),
  );

  static const dark = AppTokens(
    success: Color(0xFF34D399),
    warning: Color(0xFFFBBF24),
    danger: Color(0xFFFB7185),
    info: Color(0xFF38BDF8),
    chart: [
      Color(0xFFA78BFA), // violeta
      Color(0xFF22D3EE), // cian
      Color(0xFFFB7185), // rosa
      Color(0xFFFBBF24), // ámbar
      Color(0xFF34D399), // esmeralda
      Color(0xFF60A5FA), // azul
    ],
    typeParcial: Color(0xFFFBBF24),
    typeProyecto: Color(0xFF60A5FA),
    typeRecurso: Color(0xFF34D399),
    typeOtro: Color(0xFFA78BFA),
    border: Color(0x33CBD5E1),
    muted: Color(0xFFA5B0C8),
    cardShadow: [
      BoxShadow(color: Color(0x66000000), blurRadius: 28, offset: Offset(0, 10)),
    ],
    glass: Color(0x991A1738),
    glassBorder: Color(0x38FFFFFF),
    glassHighlight: Color(0xB32A2552),
  );

  /// Pareja de colores análogos (matiz −18° / +22°, algo más claros) a partir
  /// de [c]: da degradados vivos y armónicos sin inventar una paleta por color.
  static List<Color> gradientOf(Color c) {
    final h = HSLColor.fromColor(c);
    // En colores ya claros (tema oscuro) no se aclara más: se lavarían.
    final k = h.lightness > 0.6 ? 0.0 : 1.0;
    Color shift(double dh, double dl) => h
        .withHue((h.hue + dh + 360) % 360)
        .withLightness((h.lightness + dl * k).clamp(0.0, 0.92))
        .withSaturation((h.saturation + 0.04).clamp(0.0, 1.0))
        .toColor();
    return [shift(-18, 0.02), shift(22, 0.10)];
  }

  @override
  AppTokens copyWith({
    Color? success, Color? warning, Color? danger, Color? info,
    List<Color>? chart,
    Color? typeParcial, Color? typeProyecto, Color? typeRecurso, Color? typeOtro,
    Color? border, Color? muted, List<BoxShadow>? cardShadow,
    Color? glass, Color? glassBorder, Color? glassHighlight,
  }) =>
      AppTokens(
        success: success ?? this.success,
        warning: warning ?? this.warning,
        danger: danger ?? this.danger,
        info: info ?? this.info,
        chart: chart ?? this.chart,
        typeParcial: typeParcial ?? this.typeParcial,
        typeProyecto: typeProyecto ?? this.typeProyecto,
        typeRecurso: typeRecurso ?? this.typeRecurso,
        typeOtro: typeOtro ?? this.typeOtro,
        border: border ?? this.border,
        muted: muted ?? this.muted,
        cardShadow: cardShadow ?? this.cardShadow,
        glass: glass ?? this.glass,
        glassBorder: glassBorder ?? this.glassBorder,
        glassHighlight: glassHighlight ?? this.glassHighlight,
      );

  @override
  AppTokens lerp(ThemeExtension<AppTokens>? other, double t) {
    if (other is! AppTokens) return this;
    return AppTokens(
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      info: Color.lerp(info, other.info, t)!,
      chart: [
        for (var i = 0; i < chart.length; i++)
          Color.lerp(chart[i], other.chart[i], t)!,
      ],
      typeParcial: Color.lerp(typeParcial, other.typeParcial, t)!,
      typeProyecto: Color.lerp(typeProyecto, other.typeProyecto, t)!,
      typeRecurso: Color.lerp(typeRecurso, other.typeRecurso, t)!,
      typeOtro: Color.lerp(typeOtro, other.typeOtro, t)!,
      border: Color.lerp(border, other.border, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      cardShadow: t < 0.5 ? cardShadow : other.cardShadow,
      glass: Color.lerp(glass, other.glass, t)!,
      glassBorder: Color.lerp(glassBorder, other.glassBorder, t)!,
      glassHighlight: Color.lerp(glassHighlight, other.glassHighlight, t)!,
    );
  }
}

extension AppTokensContext on BuildContext {
  AppTokens get tokens =>
      Theme.of(this).extension<AppTokens>() ?? AppTokens.light;
}

/// Decoración de panel de vidrio (relleno translúcido con brillo en la esquina
/// superior, borde de luz, sombra suave) para contenedores propios. Sin
/// desenfoque: úsala en listas largas; para el desenfoque usa `AppCard`.
BoxDecoration glassDecoration(BuildContext context,
    {double radius = AppTokens.radiusCard}) {
  final t = context.tokens;
  return BoxDecoration(
    gradient: LinearGradient(
      colors: [t.glassHighlight, t.glass],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: t.glassBorder),
    boxShadow: t.cardShadow,
  );
}
