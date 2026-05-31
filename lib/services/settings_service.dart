import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/tts_service.dart';

/// Servicio global de ajustes — tema visual y TalkBack.
class AppSettings {
  AppSettings._();

  static final ValueNotifier<bool> talkBackEnabled = ValueNotifier(false);
  static final ValueNotifier<AppThemeType> currentTheme =
      ValueNotifier(AppThemeType.oceanBlue);

  static const _keyTalkBack = 'gesacad_talkback';
  static const _keyTheme    = 'gesacad_theme';

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    talkBackEnabled.value = prefs.getBool(_keyTalkBack) ?? false;
    final idx = prefs.getInt(_keyTheme) ?? 0;
    currentTheme.value =
        AppThemeType.values[idx.clamp(0, AppThemeType.values.length - 1)];
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

enum AppThemeType {
  oceanBlue, purpleNeon, sunsetFire, emeraldForest,
  midnightGold, cosmicPurple, roseGarden, arcticTeal,
  volcanicRed, darkCarbon,
}

extension AppThemeTypeExt on AppThemeType {
  String get label {
    switch (this) {
      case AppThemeType.oceanBlue:     return 'Océano Azul';
      case AppThemeType.purpleNeon:    return 'Violeta Neón';
      case AppThemeType.sunsetFire:    return 'Atardecer';
      case AppThemeType.emeraldForest: return 'Bosque Esmeralda';
      case AppThemeType.midnightGold:  return 'Medianoche Dorado';
      case AppThemeType.cosmicPurple:  return 'Cósmico';
      case AppThemeType.roseGarden:    return 'Jardín Rosa';
      case AppThemeType.arcticTeal:    return 'Ártico Teal';
      case AppThemeType.volcanicRed:   return 'Volcánico';
      case AppThemeType.darkCarbon:    return 'Carbón Oscuro';
    }
  }

  Color get primaryColor {
    switch (this) {
      case AppThemeType.oceanBlue:     return const Color(0xFF1565C0);
      case AppThemeType.purpleNeon:    return const Color(0xFF7C3AED);
      case AppThemeType.sunsetFire:    return const Color(0xFFEA580C);
      case AppThemeType.emeraldForest: return const Color(0xFF059669);
      case AppThemeType.midnightGold:  return const Color(0xFF1E3A8A);
      case AppThemeType.cosmicPurple:  return const Color(0xFF4F46E5);
      case AppThemeType.roseGarden:    return const Color(0xFFBE185D);
      case AppThemeType.arcticTeal:    return const Color(0xFF0369A1);
      case AppThemeType.volcanicRed:   return const Color(0xFFB91C1C);
      case AppThemeType.darkCarbon:    return const Color(0xFF374151);
    }
  }

  Color get secondaryColor {
    switch (this) {
      case AppThemeType.oceanBlue:     return const Color(0xFF0891B2);
      case AppThemeType.purpleNeon:    return const Color(0xFFDB2777);
      case AppThemeType.sunsetFire:    return const Color(0xFFDC2626);
      case AppThemeType.emeraldForest: return const Color(0xFF0EA5E9);
      case AppThemeType.midnightGold:  return const Color(0xFFB45309);
      case AppThemeType.cosmicPurple:  return const Color(0xFF7C3AED);
      case AppThemeType.roseGarden:    return const Color(0xFFEA580C);
      case AppThemeType.arcticTeal:    return const Color(0xFF059669);
      case AppThemeType.volcanicRed:   return const Color(0xFFEA580C);
      case AppThemeType.darkCarbon:    return const Color(0xFF6B7280);
    }
  }

  List<Color> get gradient {
    switch (this) {
      case AppThemeType.oceanBlue:
        return [const Color(0xFF1565C0), const Color(0xFF06B6D4)];
      case AppThemeType.purpleNeon:
        return [const Color(0xFF7C3AED), const Color(0xFFDB2777)];
      case AppThemeType.sunsetFire:
        return [const Color(0xFFEA580C), const Color(0xFFDC2626)];
      case AppThemeType.emeraldForest:
        return [const Color(0xFF059669), const Color(0xFF0EA5E9)];
      case AppThemeType.midnightGold:
        return [const Color(0xFF1E3A8A), const Color(0xFFB45309)];
      case AppThemeType.cosmicPurple:
        return [const Color(0xFF4F46E5), const Color(0xFF7C3AED)];
      case AppThemeType.roseGarden:
        return [const Color(0xFFBE185D), const Color(0xFFEA580C)];
      case AppThemeType.arcticTeal:
        return [const Color(0xFF0369A1), const Color(0xFF059669)];
      case AppThemeType.volcanicRed:
        return [const Color(0xFFB91C1C), const Color(0xFFEA580C)];
      case AppThemeType.darkCarbon:
        return [const Color(0xFF111827), const Color(0xFF374151)];
    }
  }

  IconData get icon {
    switch (this) {
      case AppThemeType.oceanBlue:     return Icons.waves_rounded;
      case AppThemeType.purpleNeon:    return Icons.auto_awesome_rounded;
      case AppThemeType.sunsetFire:    return Icons.wb_sunny_rounded;
      case AppThemeType.emeraldForest: return Icons.forest_rounded;
      case AppThemeType.midnightGold:  return Icons.nights_stay_rounded;
      case AppThemeType.cosmicPurple:  return Icons.blur_on_rounded;
      case AppThemeType.roseGarden:    return Icons.local_florist_rounded;
      case AppThemeType.arcticTeal:    return Icons.ac_unit_rounded;
      case AppThemeType.volcanicRed:   return Icons.local_fire_department_rounded;
      case AppThemeType.darkCarbon:    return Icons.dark_mode_rounded;
    }
  }

  String get emoji {
    switch (this) {
      case AppThemeType.oceanBlue:     return '🌊';
      case AppThemeType.purpleNeon:    return '✨';
      case AppThemeType.sunsetFire:    return '🌅';
      case AppThemeType.emeraldForest: return '🌿';
      case AppThemeType.midnightGold:  return '🌙';
      case AppThemeType.cosmicPurple:  return '🌌';
      case AppThemeType.roseGarden:    return '🌹';
      case AppThemeType.arcticTeal:    return '❄️';
      case AppThemeType.volcanicRed:   return '🌋';
      case AppThemeType.darkCarbon:    return '⚫';
    }
  }

  Color get backgroundColor {
    if (this == AppThemeType.darkCarbon) return const Color(0xFF0D1117);
    return const Color(0xFFF0F4FF);
  }
}
