import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/settings_service.dart';

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
  static const String institution = 'Corporación Universitaria Unicomfacauca';
  static const String year = '2026';

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text('Ajustes y Acerca de',
            style: GoogleFonts.poppins(
                color: Colors.white, fontWeight: FontWeight.w700)),
        leading: IconButton(
          tooltip: 'Regresar',
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: AppSettings.currentTheme.value.gradient,
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
        ),
        backgroundColor: Colors.transparent,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // -- Hero del app --
            _buildAppHero(context, primary),
            const SizedBox(height: 28),

            // -- Accesibilidad --
            _sectionTitle('Accesibilidad', Icons.accessibility_new_rounded, primary),
            const SizedBox(height: 12),
            _buildTalkBackCard(context, primary, isDark),
            const SizedBox(height: 28),

            // -- Temas --
            _sectionTitle('Apariencia', Icons.palette_rounded, primary),
            const SizedBox(height: 12),
            _buildThemePicker(context, isDark),
            const SizedBox(height: 28),

            // -- Acerca de --
            _sectionTitle('Acerca de', Icons.info_outline_rounded, primary),
            const SizedBox(height: 12),
            _buildAboutCard(context, primary, isDark),
            const SizedBox(height: 28),

            // -- Créditos --
            _sectionTitle('Créditos', Icons.people_rounded, primary),
            const SizedBox(height: 12),
            _buildCreditsCard(context, primary, isDark),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title, IconData icon, Color primary) {
    return Row(
      children: [
        Icon(icon, color: primary, size: 20),
        const SizedBox(width: 8),
        Text(title,
            style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: primary)),
      ],
    );
  }

  Widget _buildAppHero(BuildContext context, Color primary) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: AppSettings.currentTheme.value.gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: primary.withOpacity(0.4),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              shape: BoxShape.circle,
              border:
                  Border.all(color: Colors.white.withOpacity(0.3), width: 2),
            ),
            child: const Icon(Icons.school_rounded,
                color: Colors.white, size: 52),
          ),
          const SizedBox(height: 16),
          Text('GESACAD',
              style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 4)),
          const SizedBox(height: 4),
          Text('Sistema de Gestión Académica',
              style: GoogleFonts.poppins(
                  color: Colors.white70, fontSize: 14, letterSpacing: 1)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('Versión $version',
                style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _buildTalkBackCard(
      BuildContext context, Color primary, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, 4)),
        ],
      ),
      child: ValueListenableBuilder<bool>(
        valueListenable: AppSettings.talkBackEnabled,
        builder: (context, enabled, _) {
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: (enabled ? primary : Colors.grey)
                            .withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        enabled
                            ? Icons.record_voice_over_rounded
                            : Icons.voice_over_off_rounded,
                        color: enabled ? primary : Colors.grey,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('TalkBack',
                              style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16)),
                          Text(
                            enabled
                                ? 'Activado — hover lee en voz alta'
                                : 'Desactivado — sin lectura de voz',
                            style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: enabled
                                    ? primary
                                    : Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: enabled,
                      onChanged: (v) => AppSettings.setTalkBack(v),
                    ),
                  ],
                ),
                if (enabled) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: primary.withOpacity(0.07),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.lightbulb_outline_rounded,
                            color: primary, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Hover: pasa el cursor sobre cualquier elemento para escucharlo. '
                            'Botón 🔊: lee toda la pantalla. '
                            'Desactiva el switch para silenciar.',
                            style: GoogleFonts.poppins(
                                fontSize: 12, color: primary),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildThemePicker(BuildContext context, bool isDark) {
    return ValueListenableBuilder<AppThemeType>(
      valueListenable: AppSettings.currentTheme,
      builder: (_, current, __) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06),
                blurRadius: 16, offset: const Offset(0, 4))],
          ),
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Tema activo destacado
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: current.gradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(
                  color: current.primaryColor.withOpacity(0.4),
                  blurRadius: 16, offset: const Offset(0, 6))],
              ),
              child: Row(children: [
                Text(current.emoji, style: const TextStyle(fontSize: 24)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Tema activo', style: GoogleFonts.poppins(
                      color: Colors.white70, fontSize: 10)),
                  Text(current.label, style: GoogleFonts.poppins(
                      color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                ])),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(current.icon, color: Colors.white, size: 20),
                ),
              ]),
            ),
            const SizedBox(height: 18),
            Text('Elige un tema', style: GoogleFonts.poppins(
                fontSize: 13, fontWeight: FontWeight.w600,
                color: Colors.grey.shade600)),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 2.4,
              children: AppThemeType.values.map((t) {
                final selected = t == current;
                return GestureDetector(
                  onTap: () => AppSettings.setTheme(t),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: t.gradient,
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: selected ? Colors.white : Colors.transparent,
                        width: 2.5,
                      ),
                      boxShadow: selected
                          ? [BoxShadow(color: t.primaryColor.withOpacity(0.5),
                              blurRadius: 12, offset: const Offset(0, 4))]
                          : [BoxShadow(color: t.primaryColor.withOpacity(0.15),
                              blurRadius: 6, offset: const Offset(0, 2))],
                    ),
                    child: Stack(children: [
                      Positioned(top: 0, left: 0, right: 0, child: Container(
                        height: 6,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.18),
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(12)),
                        ),
                      )),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        child: Row(children: [
                          Text(t.emoji, style: const TextStyle(fontSize: 16)),
                          const SizedBox(width: 6),
                          Expanded(child: Text(t.label,
                              style: GoogleFonts.poppins(color: Colors.white,
                                  fontSize: 10, fontWeight: FontWeight.w700),
                              maxLines: 1, overflow: TextOverflow.ellipsis)),
                          if (selected)
                            const Icon(Icons.check_circle_rounded,
                                color: Colors.white, size: 16),
                        ]),
                      ),
                    ]),
                  ),
                );
              }).toList(),
            ),
          ]),
        );
      },
    );
  }

    Widget _buildAboutCard(BuildContext context, Color primary, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, 4)),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          _infoRow(Icons.info_rounded, 'Nombre', 'GESACAD', primary),
          _divider(),
          _infoRow(Icons.tag_rounded, 'Versión', version, primary),
          _divider(),
          _infoRow(Icons.calendar_today_rounded, 'Año', year, primary),
          _divider(),
          _infoRow(Icons.school_rounded, 'Institución', institution, primary),
          _divider(),
          _infoRow(Icons.devices_rounded, 'Plataformas',
              'Android · iOS · Web · Windows', primary),
          _divider(),
          _infoRow(Icons.code_rounded, 'Tecnología',
              'Flutter 3 · Dart · Node.js · MySQL', primary),
        ],
      ),
    );
  }

  Widget _buildCreditsCard(
      BuildContext context, Color primary, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, 4)),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          _creditCard(Icons.person_rounded, developer,
              'Desarrollador principal', primary),
          const SizedBox(height: 12),
          _creditCard(Icons.business_rounded, institution,
              'Institución patrocinadora', primary),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: primary.withOpacity(0.06),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.favorite_rounded, color: Colors.red.shade400, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Desarrollado con Flutter para la comunidad académica de Unicomfacauca.',
                    style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value, Color primary) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(icon, color: primary, size: 20),
          const SizedBox(width: 12),
          Text(label,
              style: GoogleFonts.poppins(
                  fontSize: 13, color: Colors.grey.shade500)),
          const Spacer(),
          Text(value,
              style: GoogleFonts.poppins(
                  fontSize: 13, fontWeight: FontWeight.w600),
              textAlign: TextAlign.right),
        ],
      ),
    );
  }

  Widget _divider() => Divider(height: 1, color: Colors.grey.shade100);

  Widget _creditCard(IconData icon, String name, String role, Color primary) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: primary.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: primary, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700, fontSize: 14)),
              Text(role,
                  style: GoogleFonts.poppins(
                      fontSize: 12, color: Colors.grey.shade500)),
            ],
          ),
        ),
      ],
    );
  }
}
