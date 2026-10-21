import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/tts_service.dart';

/// Servicio global de ajustes — tema visual y TalkBack.
class AppSettings {
  AppSettings._();

  static final ValueNotifier<bool> talkBackEnabled = ValueNotifier(false);
  static final ValueNotifier<AppThemeType> currentTheme =
      ValueNotifier(AppThemeType.aurora);

  static const _keyTalkBack = 'gesacad_talkback';
  // v3: el conjunto de temas cambió (paletas nuevas); las claves viejas
  // guardaban índices de otro conjunto.
  static const _keyTheme    = 'gesacad_theme_v3';

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    talkBackEnabled.value = prefs.getBool(_keyTalkBack) ?? false;
    final idx = prefs.getInt(_keyTheme) ?? 0;
    currentTheme.value = (idx >= 0 && idx < AppThemeType.values.length)
        ? AppThemeType.values[idx]
        : AppThemeType.aurora;
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

/// Temas: 4 claros y 2 oscuros. Cada uno define color primario (legible sobre
/// vidrio), secundario y un degradado vivo para encabezados.
enum AppThemeType { aurora, oceano, atardecer, selva, medianoche, neon }

extension AppThemeTypeExt on AppThemeType {
  bool get isDark =>
      this == AppThemeType.medianoche || this == AppThemeType.neon;

  String get label {
    switch (this) {
      case AppThemeType.aurora:     return 'Aurora';
      case AppThemeType.oceano:     return 'Océano';
      case AppThemeType.atardecer:  return 'Atardecer';
      case AppThemeType.selva:      return 'Selva';
      case AppThemeType.medianoche: return 'Medianoche';
      case AppThemeType.neon:       return 'Neón';
    }
  }

  Color get primaryColor {
    switch (this) {
      case AppThemeType.aurora:     return const Color(0xFF6D28D9);
      case AppThemeType.oceano:     return const Color(0xFF1D4ED8);
      case AppThemeType.atardecer:  return const Color(0xFFBE123C);
      case AppThemeType.selva:      return const Color(0xFF047857);
      case AppThemeType.medianoche: return const Color(0xFFA78BFA);
      case AppThemeType.neon:       return const Color(0xFF22D3EE);
    }
  }

  Color get secondaryColor {
    switch (this) {
      case AppThemeType.aurora:     return const Color(0xFF06B6D4);
      case AppThemeType.oceano:     return const Color(0xFF14B8A6);
      case AppThemeType.atardecer:  return const Color(0xFFF59E0B);
      case AppThemeType.selva:      return const Color(0xFF84CC16);
      case AppThemeType.medianoche: return const Color(0xFFF472B6);
      case AppThemeType.neon:       return const Color(0xFFA3E635);
    }
  }

  /// Degradado vivo de encabezados y botones destacados.
  List<Color> get gradient {
    switch (this) {
      case AppThemeType.aurora:
        return [const Color(0xFF7C3AED), const Color(0xFF06B6D4)];
      case AppThemeType.oceano:
        return [const Color(0xFF2563EB), const Color(0xFF14B8A6)];
      case AppThemeType.atardecer:
        return [const Color(0xFFE11D48), const Color(0xFFF59E0B)];
      case AppThemeType.selva:
        return [const Color(0xFF059669), const Color(0xFF65A30D)];
      case AppThemeType.medianoche:
        return [const Color(0xFF6D28D9), const Color(0xFFDB2777)];
      case AppThemeType.neon:
        return [const Color(0xFF0891B2), const Color(0xFF7C3AED)];
    }
  }

  IconData get icon {
    switch (this) {
      case AppThemeType.aurora:     return Icons.auto_awesome_rounded;
      case AppThemeType.oceano:     return Icons.waves_rounded;
      case AppThemeType.atardecer:  return Icons.wb_twilight_rounded;
      case AppThemeType.selva:      return Icons.eco_rounded;
      case AppThemeType.medianoche: return Icons.nights_stay_rounded;
      case AppThemeType.neon:       return Icons.bolt_rounded;
    }
  }

  /// Color base del fondo (la app pinta un degradado sobre él).
  Color get backgroundColor =>
      isDark ? const Color(0xFF0B0B1A) : const Color(0xFFF5F3FF);
}
