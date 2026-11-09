import 'package:flutter/material.dart';
import '../services/settings_service.dart';

/// «Escena» de un tema oscuro: el tinte de fondo, superficies, barra, campos y vidrio, más las
/// tres luces difusas. Cada tema oscuro tiene la suya para que NO se vean iguales (antes
/// Futurista, Medianoche y Neón compartían el mismo fondo y solo cambiaba el degradado de la
/// muestra). Ninguna es negra ni pasa por azul.
class DarkScene {
  const DarkScene({
    required this.surface,
    required this.container,
    required this.appBar,
    required this.input,
    required this.glass,
    required this.glassHighlight,
    required this.base,
    required this.halos,
    this.logo,
  });

  final Color surface;
  final Color container;
  final Color appBar;
  final Color input;
  final Color glass;
  final Color glassHighlight;

  /// Degradado vertical del fondo (3 paradas).
  final List<Color> base;

  /// Tres luces: arriba a la derecha, abajo a la izquierda y a la izquierda hacia el centro.
  final List<Color> halos;

  /// Color del logo giratorio de fondo (por defecto, el secundario del tema).
  final Color? logo;
}

extension DarkSceneOf on AppThemeType {
  DarkScene get scene {
    switch (this) {
      // Futurista: tinta violeta profunda con luz violeta, magenta y verde azulado.
      case AppThemeType.aurora:
        return const DarkScene(
          surface: Color(0xFF1A1138),
          container: Color(0xFF2A1D58),
          appBar: Color(0xD91B1040),
          input: Color(0x80241A4C),
          glass: Color(0x8C1A1138),
          glassHighlight: Color(0xB32E2062),
          base: [Color(0xFF1B0F3F), Color(0xFF241352), Color(0xFF150B33)],
          halos: [Color(0x6B8B5CF6), Color(0x2B0FB5A9), Color(0x38DB2777)],
          logo: Color(0xFFD8B4FE), // lila: el cian sobre violeta se veía azul
        );
      // Ámbar: grafito cálido con luz de oro y brasa. Nada de azul ni de violeta.
      case AppThemeType.medianoche:
        return const DarkScene(
          surface: Color(0xFF261B13),
          container: Color(0xFF3B2A1A),
          appBar: Color(0xD92C1E12),
          input: Color(0x80382819),
          glass: Color(0x8C2A1D12),
          glassHighlight: Color(0xB3463219),
          base: [Color(0xFF2E1F13), Color(0xFF3A2614), Color(0xFF1F150C)],
          halos: [Color(0x6BF59E0B), Color(0x30DC2626), Color(0x2EFACC15)],
        );
      // Neón: verde azulado profundo con luz de cian y lima. También es el look del login y la
      // escena por defecto (los temas claros no la usan).
      case AppThemeType.neon:
      default:
        return const DarkScene(
          surface: Color(0xFF0B2724),
          container: Color(0xFF143F3A),
          appBar: Color(0xD9082C29),
          input: Color(0x80103632),
          glass: Color(0x8C0B2724),
          glassHighlight: Color(0xB3135049),
          base: [Color(0xFF07302C), Color(0xFF0A3C37), Color(0xFF05221F)],
          halos: [Color(0x5C2DD4BF), Color(0x38A3E635), Color(0x3322D3EE)],
        );
    }
  }
}
