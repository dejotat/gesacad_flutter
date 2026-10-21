import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../config/app_tokens.dart';
import '../services/settings_service.dart';
import '../widgets/ui/ui.dart';

/// Pantalla de ajustes y "Acerca de" GESACAD.
///
/// Permite:
/// - Activar/desactivar TalkBack (accesibilidad).
/// - Cambiar el tema visual de la aplicación.
/// - Ver información de versión, desarrollador e institución.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static const String version = '1.1.2';
  static const String developer = 'Jorge Tunubala';
  static const String institution = 'Colegio Santander';
  static const String year = '2026';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes y Acerca de')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppTokens.pagePadding),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildAppHero(context),
                const SizedBox(height: AppTokens.sectionGap),
                const SectionTitle('Accesibilidad',
                    icon: PhosphorIconsRegular.personArmsSpread),
                const SizedBox(height: 12),
                _buildTalkBackCard(context),
                const SizedBox(height: AppTokens.sectionGap),
                const SectionTitle('Apariencia',
                    icon: PhosphorIconsRegular.palette),
                const SizedBox(height: 12),
                _buildThemePicker(context),
                const SizedBox(height: AppTokens.sectionGap),
                const SectionTitle('Acerca de', icon: PhosphorIconsRegular.info),
                const SizedBox(height: 12),
                _buildAboutCard(context),
                const SizedBox(height: AppTokens.sectionGap),
                const SectionTitle('Créditos', icon: PhosphorIconsRegular.users),
                const SizedBox(height: 12),
                _buildCreditsCard(context),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAppHero(BuildContext context) {
    return PageHeader(
      title: 'GESACAD',
      subtitle: 'Sistema de Gestión Académica',
      leading: ExcludeSemantics(
        child: Container(
          width: 56, height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
          ),
          child: const Icon(PhosphorIconsRegular.graduationCap,
              color: Colors.white, size: 28),
        ),
      ),
      chips: const [HeaderChip(PhosphorIconsRegular.hash, 'Versión $version')],
    );
  }

  Widget _buildTalkBackCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = context.tokens;
    return ValueListenableBuilder<bool>(
      valueListenable: AppSettings.talkBackEnabled,
      builder: (context, enabled, _) {
        final accent = enabled ? cs.primary : t.muted;
        return AppCard(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            Row(children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppTokens.radiusControl),
                ),
                child: Icon(
                  enabled
                      ? PhosphorIconsRegular.speakerHigh
                      : PhosphorIconsRegular.speakerSlash,
                  color: accent,
                  size: 26,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('TalkBack',
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600, fontSize: 16)),
                  Text(
                    enabled
                        ? 'Activado — el cursor lee en voz alta'
                        : 'Desactivado — sin lectura de voz',
                    style: GoogleFonts.poppins(fontSize: 12, color: accent),
                  ),
                ]),
              ),
              Semantics(
                label: 'TalkBack',
                toggled: enabled,
                child: Switch(
                  value: enabled,
                  onChanged: (v) => AppSettings.setTalkBack(v),
                ),
              ),
            ]),
            if (enabled) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppTokens.radiusControl),
                ),
                child: Row(children: [
                  Icon(PhosphorIconsRegular.lightbulb,
                      color: cs.primary, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Pasa el cursor sobre cualquier elemento para escucharlo. '
                      'El botón de altavoz lee toda la pantalla. '
                      'Desactiva el interruptor para silenciar.',
                      style: GoogleFonts.poppins(fontSize: 12, color: t.muted),
                    ),
                  ),
                ]),
              ),
            ],
          ]),
        );
      },
    );
  }

  Widget _buildThemePicker(BuildContext context) {
    final t = context.tokens;
    return ValueListenableBuilder<AppThemeType>(
      valueListenable: AppSettings.currentTheme,
      builder: (_, current, __) {
        return AppCard(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Elige un tema',
                style: GoogleFonts.poppins(
                    fontSize: 13, fontWeight: FontWeight.w500, color: t.muted)),
            const SizedBox(height: 12),
            LayoutBuilder(builder: (ctx, c) {
              final cols = c.maxWidth > 520 ? 3 : 2;
              const gap = 10.0;
              final w = (c.maxWidth - gap * (cols - 1)) / cols;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final theme in AppThemeType.values)
                    SizedBox(
                      width: w,
                      child: _themeTile(context, theme, theme == current),
                    ),
                ],
              );
            }),
          ]),
        );
      },
    );
  }

  /// Muestra de un tema: degradado en vidrio con su nombre y marca de selección.
  Widget _themeTile(BuildContext context, AppThemeType type, bool selected) {
    return Semantics(
      button: true,
      selected: selected,
      label: 'Tema ${type.label}${selected ? ', seleccionado' : ''}',
      child: ExcludeSemantics(
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTokens.radiusControl),
          onTap: () => AppSettings.setTheme(type),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: type.gradient,
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(AppTokens.radiusControl),
              border: Border.all(
                color: selected
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.25),
                width: selected ? 2.5 : 1,
              ),
              boxShadow: selected
                  ? [BoxShadow(
                      color: type.primaryColor.withValues(alpha: 0.45),
                      blurRadius: 14,
                      offset: const Offset(0, 5))]
                  : null,
            ),
            child: Row(children: [
              Icon(type.icon, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(type.label,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ),
              if (selected)
                const Icon(PhosphorIconsFill.checkCircle,
                    color: Colors.white, size: 18),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _buildAboutCard(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Column(children: [
        _infoRow(context, PhosphorIconsRegular.info, 'Nombre', 'GESACAD'),
        _divider(context),
        _infoRow(context, PhosphorIconsRegular.hash, 'Versión', version),
        _divider(context),
        _infoRow(context, PhosphorIconsRegular.calendarBlank, 'Año', year),
        _divider(context),
        _infoRow(context, PhosphorIconsRegular.buildings, 'Institución',
            institution),
        _divider(context),
        _infoRow(context, PhosphorIconsRegular.devices, 'Plataformas',
            'Android · Web'),
        _divider(context),
        _infoRow(context, PhosphorIconsRegular.code, 'Tecnología',
            'Flutter · Node.js · MySQL'),
      ]),
    );
  }

  Widget _buildCreditsCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = context.tokens;
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        _creditRow(context, PhosphorIconsRegular.user, developer,
            'Desarrollador principal'),
        const SizedBox(height: 14),
        _creditRow(context, PhosphorIconsRegular.buildings, institution,
            'Institución'),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppTokens.radiusControl),
          ),
          child: Row(children: [
            Icon(PhosphorIconsFill.heart, color: t.danger, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Desarrollado con Flutter para la comunidad académica de $institution.',
                style: GoogleFonts.poppins(fontSize: 12, color: t.muted),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _infoRow(BuildContext context, IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary, size: 20),
        const SizedBox(width: 12),
        Text(label,
            style: GoogleFonts.poppins(
                fontSize: 13, color: context.tokens.muted)),
        const Spacer(),
        Flexible(
          child: Text(value,
              style: GoogleFonts.poppins(
                  fontSize: 13, fontWeight: FontWeight.w600),
              textAlign: TextAlign.right),
        ),
      ]),
    );
  }

  Widget _divider(BuildContext context) =>
      Divider(height: 1, color: context.tokens.border);

  Widget _creditRow(BuildContext context, IconData icon, String name, String role) {
    final primary = Theme.of(context).colorScheme.primary;
    return Row(children: [
      Container(
        width: 44, height: 44,
        decoration: BoxDecoration(
          color: primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppTokens.radiusControl),
        ),
        child: Icon(icon, color: primary, size: 22),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name,
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600, fontSize: 14)),
          Text(role,
              style: GoogleFonts.poppins(
                  fontSize: 12, color: context.tokens.muted)),
        ]),
      ),
    ]);
  }
}
