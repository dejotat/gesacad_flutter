import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/tts_service.dart';

/// Servicio global de ajustes — tema visual y TalkBack.
class AppSettings {
  AppSettings._();

  static final ValueNotifier<bool> talkBackEnabled = ValueNotifier(false);
  static final ValueNotifier<AppThemeType> currentTheme =
      ValueNotifier(AppThemeType.neon);

  static const _keyTalkBack = 'gesacad_talkback';
  // v3: el conjunto de temas cambió (paletas nuevas); las claves viejas
  // guardaban índices de otro conjunto.
  static const _keyTheme    = 'gesacad_theme_v3';

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    talkBackEnabled.value = prefs.getBool(_keyTalkBack) ?? false;
    // Sin tema guardado: «Neón» (el principal, el mismo del login). Quien ya eligió uno lo conserva.
    final idx = prefs.getInt(_keyTheme);
    final guardado = (idx != null && idx >= 0 && idx < AppThemeType.values.length)
        ? AppThemeType.values[idx]
        : null;
    currentTheme.value =
        guardado ?? AppThemeType.neon;
  }

  static Future<void> setTalkBack(bool enabled) async {
    talkBackEnabled.value = enabled;
    if (!enabled) await TtsService.instance.stop();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyTalkBack, enabled);
  }

  static Future<void> setTheme(AppThemeType theme) async {
    currentTheme.value = theme;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyTheme, theme.index);
  }
}

/// Temas: 5 claros y 3 oscuros. El principal es Neón (oscuro), el mismo del login. Cada uno
/// define color primario (legible sobre vidrio), secundario, un degradado vivo para encabezados
/// y, los oscuros, su propia escena de fondo (`config/app_scenes.dart`).
///
/// IMPORTANTE: los valores nuevos van AL FINAL; el índice se guarda en SharedPreferences.
enum AppThemeType { aurora, oceano, atardecer, selva, medianoche, neon, lavanda, menta }

extension AppThemeTypeExt on AppThemeType {
  /// Los temas oscuros: Futurista (violeta), Ámbar (grafito y oro) y Neón (verde azulado).
  bool get isDark =>
      this == AppThemeType.aurora ||
      this == AppThemeType.medianoche ||
      this == AppThemeType.neon;

  /// Los temas que se ofrecen en Ajustes, en orden: el principal primero.
  static List<AppThemeType> get ofrecidos => const [
        AppThemeType.neon,
        AppThemeType.aurora,
        AppThemeType.medianoche,
        AppThemeType.atardecer,
        AppThemeType.lavanda,
        AppThemeType.menta,
        AppThemeType.selva,
        AppThemeType.oceano,
      ];

  String get label {
    switch (this) {
      case AppThemeType.aurora:     return 'Futurista';
      case AppThemeType.oceano:     return 'Océano';
      case AppThemeType.atardecer:  return 'Atardecer';
      case AppThemeType.selva:      return 'Selva';
      case AppThemeType.medianoche: return 'Ámbar';
      case AppThemeType.neon:       return 'Neón';
      case AppThemeType.lavanda:    return 'Lavanda';
      case AppThemeType.menta:      return 'Menta';
    }
  }

  Color get primaryColor {
    switch (this) {
      case AppThemeType.aurora:     return const Color(0xFF7C3AED);
      case AppThemeType.oceano:     return const Color(0xFF1D4ED8);
      case AppThemeType.atardecer:  return const Color(0xFFBE123C);
      case AppThemeType.selva:      return const Color(0xFF047857);
      case AppThemeType.medianoche: return const Color(0xFFB45309);
      case AppThemeType.neon:       return const Color(0xFF0D9488);
      case AppThemeType.lavanda:    return const Color(0xFF7E22CE);
      case AppThemeType.menta:      return const Color(0xFF0F766E);
    }
  }

  Color get secondaryColor {
    switch (this) {
      case AppThemeType.aurora:     return const Color(0xFF22D3EE);
      case AppThemeType.oceano:     return const Color(0xFF14B8A6);
      case AppThemeType.atardecer:  return const Color(0xFFF59E0B);
      case AppThemeType.selva:      return const Color(0xFF84CC16);
      case AppThemeType.medianoche: return const Color(0xFFFBBF24);
      case AppThemeType.neon:       return const Color(0xFFA3E635);
      case AppThemeType.lavanda:    return const Color(0xFFEC4899);
      case AppThemeType.menta:      return const Color(0xFF34D399);
    }
  }

  /// Degradado vivo de encabezados y botones destacados.
  List<Color> get gradient {
    switch (this) {
      case AppThemeType.aurora:
        return [const Color(0xFF5B21B6), const Color(0xFFBE185D)];
      case AppThemeType.oceano:
        return [const Color(0xFF2563EB), const Color(0xFF14B8A6)];
      case AppThemeType.atardecer:
        return [const Color(0xFFE11D48), const Color(0xFFF59E0B)];
      case AppThemeType.selva:
        return [const Color(0xFF059669), const Color(0xFF65A30D)];
      case AppThemeType.medianoche:
        return [const Color(0xFF9A3412), const Color(0xFFD97706)];
      case AppThemeType.neon:
        return [const Color(0xFF0D9488), const Color(0xFF65A30D)];
      case AppThemeType.lavanda:
        return [const Color(0xFF7E22CE), const Color(0xFFDB2777)];
      case AppThemeType.menta:
        return [const Color(0xFF0D9488), const Color(0xFF34D399)];
    }
  }

  IconData get icon {
    switch (this) {
      case AppThemeType.aurora:     return Icons.auto_awesome_rounded;
      case AppThemeType.oceano:     return Icons.waves_rounded;
      case AppThemeType.atardecer:  return Icons.wb_twilight_rounded;
      case AppThemeType.selva:      return Icons.eco_rounded;
      case AppThemeType.medianoche: return Icons.local_fire_department_rounded;
      case AppThemeType.neon:       return Icons.bolt_rounded;
      case AppThemeType.lavanda:    return Icons.local_florist_rounded;
      case AppThemeType.menta:      return Icons.spa_rounded;
    }
  }

  /// Color base del fondo (la app pinta un degradado sobre él).
  Color get backgroundColor => switch (this) {
        AppThemeType.aurora => const Color(0xFF150B33),
        AppThemeType.medianoche => const Color(0xFF1E140C),
        AppThemeType.neon => const Color(0xFF041F1C),
        _ => const Color(0xFFF5F3FF),
      };
}
