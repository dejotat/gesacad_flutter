import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:gesacad/config/app_themes.dart';
import 'package:gesacad/config/app_tokens.dart';
import 'package:gesacad/services/settings_service.dart';

/// Construye el tema sin red: google_fonts falla de forma asíncrona al no
/// encontrar Poppins en los assets del test; esos errores no son lo que se prueba.
ThemeData _buildQuiet(AppThemeType type) {
  late ThemeData theme;
  runZonedGuarded(() => theme = AppThemes.of(type), (_, __) {});
  return theme;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  test('cada tema construye un ThemeData con tokens de diseño', () async {
    for (final type in AppThemeType.values) {
      final theme = _buildQuiet(type);
      expect(theme.extension<AppTokens>(), isNotNull, reason: type.name);
      expect(theme.colorScheme.primary, type.primaryColor, reason: type.name);
    }
    await Future<void>.delayed(Duration.zero);
  });

  test('solo Carbón Oscuro usa brillo oscuro', () async {
    for (final type in AppThemeType.values) {
      final expected = type.isDark
          ? Brightness.dark
          : Brightness.light;
      expect(_buildQuiet(type).brightness, expected, reason: type.name);
    }
    await Future<void>.delayed(Duration.zero);
  });
}
