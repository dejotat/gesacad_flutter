import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/settings_service.dart';
import 'app_tokens.dart';

/// Fábrica de temas de Material 3 para GESACAD.
/// Base neutra (slate) + un color primario por tema; superficies planas con
/// borde de 1 px. Los colores semánticos viven en [AppTokens].
class AppThemes {
  AppThemes._();

  static ThemeData of(AppThemeType type) {
    if (type.isDark) return _build(type, Brightness.dark);
    return _build(type, Brightness.light);
  }

  static ThemeData _build(AppThemeType type, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final tokens = isDark ? AppTokens.dark : AppTokens.light;
    final primary = type.primaryColor;

    final surface = isDark ? const Color(0xFF1A1738) : Colors.white;
    final onSurface = isDark ? const Color(0xFFF1F0FF) : const Color(0xFF1E1B4B);
    const onPrimary = Colors.white;

    final cs = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: brightness,
    ).copyWith(
      primary: primary,
      onPrimary: onPrimary,
      secondary: type.secondaryColor,
      surface: surface,
      onSurface: onSurface,
      surfaceContainerHighest:
          isDark ? const Color(0xFF241F4A) : const Color(0xFFEDE9FE),
      outline: tokens.border,
      outlineVariant: tokens.border,
      error: tokens.danger,
    );

    final base = ThemeData(colorScheme: cs, useMaterial3: true);
    final text = GoogleFonts.poppinsTextTheme(base.textTheme)
        .apply(bodyColor: onSurface, displayColor: onSurface);

    // Superficies flotantes (diálogos, menús, hojas): casi opacas para legibilidad.
    final floating = isDark ? const Color(0xF21A1738) : const Color(0xF2FFFFFF);

    OutlineInputBorder inputBorder(Color c, [double w = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusControl),
          borderSide: BorderSide(color: c, width: w),
        );

    return base.copyWith(
      extensions: [tokens],
      textTheme: text,
      // Transparente: el fondo con degradado lo pinta AppBackground (main.dart).
      scaffoldBackgroundColor: Colors.transparent,
      dividerColor: tokens.border,
      appBarTheme: AppBarTheme(
        backgroundColor: isDark
            ? const Color(0xE61A1738)
            : primary.withValues(alpha: 0.94),
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.poppins(
          fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: tokens.glass,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusCard),
          side: BorderSide(color: tokens.glassBorder),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: floating,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusCard),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: floating,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusControl),
          side: BorderSide(color: tokens.glassBorder),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: floating,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: floating,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: floating,
        surfaceTintColor: Colors.transparent,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.radiusControl),
          ),
          textStyle: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: isDark ? onSurface : primary,
          side: BorderSide(color: tokens.border),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.radiusControl),
          ),
          textStyle: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: isDark ? type.secondaryColor : primary,
          textStyle: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0x66241F4A) : const Color(0x99FFFFFF),
        border: inputBorder(tokens.border),
        enabledBorder: inputBorder(tokens.border),
        focusedBorder: inputBorder(primary, 2),
        errorBorder: inputBorder(tokens.danger),
        focusedErrorBorder: inputBorder(tokens.danger, 2),
        labelStyle: GoogleFonts.poppins(color: tokens.muted),
        hintStyle: GoogleFonts.poppins(color: tokens.muted),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: cs.surfaceContainerHighest,
        side: BorderSide(color: tokens.border),
        labelStyle: GoogleFonts.poppins(fontSize: 12, color: onSurface),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusControl),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? primary : tokens.muted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? primary.withValues(alpha: 0.35)
              : tokens.border,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: onPrimary,
        elevation: 2,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusControl),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelStyle: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600),
        unselectedLabelStyle: GoogleFonts.poppins(fontSize: 14),
      ),
    );
  }
}
