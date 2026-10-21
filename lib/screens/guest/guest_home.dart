import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/app_tokens.dart';
import '../../models/university_info.dart';
import '../../services/guest_service.dart';
import '../../widgets/animated_logo.dart';
import '../../widgets/ui/ui.dart';
import 'guest_demo.dart';

/// Modo invitado (CU-10): se entra desde el login SIN cuenta y SIN sesión.
///
/// - **Inicio**: bienvenida, elegir un perfil y funciones destacadas.
/// - **Universidad**: presentación, programas, "Mi ruta de matrícula" (pasos + lista de
///   requisitos que el visitante va marcando) y contacto. Lo edita el Admin.
/// - **Probar la app**: demostración interactiva de cada rol con datos de ejemplo.
///
/// El invitado nunca obtiene token ni toca datos reales: solo lee `/public/university`.
class GuestHome extends StatefulWidget {
  const GuestHome({super.key, this.servicio = const GuestService()});
  final GuestService servicio;

  @override
  State<GuestHome> createState() => _GuestHomeState();
}

class _GuestHomeState extends State<GuestHome> {
  int _tab = 0;
  DemoRole _rol = DemoRole.student;
  late Future<GuestContent> _contenido;

  @override
  void initState() {
    super.initState();
    _contenido = widget.servicio.load();
  }

  void _recargar() => setState(() => _contenido = widget.servicio.load());

  void _probar(DemoRole r) => setState(() { _rol = r; _tab = 2; });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Modo invitado'),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.maybePop(context),
            icon: const Icon(PhosphorIconsRegular.signIn, color: Colors.white, size: 18),
            label: Text('Iniciar sesión',
                style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
          ),
        ],
      ),
      body: LogoBackdrop(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: FutureBuilder<GuestContent>(
              future: _contenido,
              builder: (context, snap) {
                final c = snap.data;
                return IndexedStack(index: _tab, children: [
                  _Inicio(info: c?.info, onProbar: _probar, onUniversidad: () => setState(() => _tab = 1)),
                  _Universidad(contenido: c, servicio: widget.servicio, onRecargar: _recargar),
                  Column(children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(AppTokens.pagePadding, 12, AppTokens.pagePadding, 4),
                      child: SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<DemoRole>(
                          showSelectedIcon: false,
                          segments: [
                            for (final r in DemoRole.values)
                              ButtonSegment(value: r, icon: Icon(r.icon, size: 18), label: Text(r.label)),
                          ],
                          selected: {_rol},
                          onSelectionChanged: (s) => setState(() => _rol = s.first),
                        ),
                      ),
                    ),
                    Expanded(child: GuestDemo(role: _rol)),
                  ]),
                ]);
              },
            ),
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(PhosphorIconsRegular.house), selectedIcon: Icon(PhosphorIconsFill.house), label: 'Inicio'),
          NavigationDestination(
              icon: Icon(PhosphorIconsRegular.buildings),
              selectedIcon: Icon(PhosphorIconsFill.buildings),
              label: 'Universidad'),
          NavigationDestination(
              icon: Icon(PhosphorIconsRegular.playCircle),
              selectedIcon: Icon(PhosphorIconsFill.playCircle),
              label: 'Probar la app'),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Inicio
// ═════════════════════════════════════════════════════════════════════════════
class _Inicio extends StatelessWidget {
  const _Inicio({required this.info, required this.onProbar, required this.onUniversidad});
  final UniversityInfo? info;
  final ValueChanged<DemoRole> onProbar;
  final VoidCallback onUniversidad;

  static const _funciones = [
    (PhosphorIconsFill.listChecks, 'Actividades y entregas', 'Sube tus trabajos y consulta plazos.'),
    (PhosphorIconsFill.trophy, 'Calificaciones', 'Notas y comentarios de tus docentes.'),
    (PhosphorIconsFill.chartPolar, 'Evaluación docente', 'Anónima, al final del semestre.'),
    (PhosphorIconsFill.videoCamera, 'Reuniones virtuales', 'Videollamadas por curso con un toque.'),
    (PhosphorIconsFill.wifiSlash, 'Sin conexión', 'Sigue trabajando y se envía al volver.'),
    (PhosphorIconsFill.speakerHigh, 'Accesible', 'Lectura en voz alta y lector de pantalla.'),
  ];

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ListView(
      key: const PageStorageKey('guest_inicio'),
      padding: const EdgeInsets.fromLTRB(AppTokens.pagePadding, 16, AppTokens.pagePadding, 32),
      children: [
        const Center(child: ExcludeSemantics(child: AnimatedLogo(size: 110))),
        const SizedBox(height: 14),
        Semantics(
          header: true,
          child: Text(info?.name ?? 'GESACAD',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.w800)),
        ),
        if ((info?.tagline ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(info!.tagline,
                textAlign: TextAlign.center, style: GoogleFonts.poppins(fontSize: 14, color: t.muted)),
          ),
        const SizedBox(height: 8),
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: t.info.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(16)),
            child: Text('Estás explorando como invitado',
                style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: t.info)),
          ),
        ),
        const SizedBox(height: AppTokens.sectionGap),
        const SectionTitle('Elige tu perfil y pruébalo', icon: PhosphorIconsRegular.userSwitch,
            subtitle: 'Verás la app como la ve cada rol'),
        const SizedBox(height: 10),
        Row(children: [
          for (final r in DemoRole.values) ...[
            Expanded(
              child: AppCard(
                blur: false,
                onTap: () => onProbar(r),
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                child: Semantics(
                  button: true,
                  label: 'Probar la app como ${r.label}',
                  child: Column(children: [
                    MotionIcon(r.icon, size: 30, color: Theme.of(context).colorScheme.primary, halo: true),
                    const SizedBox(height: 8),
                    Text(r.label, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
            ),
            if (r != DemoRole.values.last) const SizedBox(width: 10),
          ],
        ]),
        const SizedBox(height: 14),
        AppButton(
          label: 'Cómo matricularme',
          icon: PhosphorIconsFill.graduationCap,
          reaction: IconReaction.bounce,
          expand: true,
          onPressed: onUniversidad,
        ),
        const SizedBox(height: AppTokens.sectionGap),
        const SectionTitle('Lo que puedes hacer en GESACAD', icon: PhosphorIconsRegular.sparkle),
        const SizedBox(height: 10),
        LayoutBuilder(builder: (context, c) {
          final dosColumnas = c.maxWidth >= 520;
          final ancho = dosColumnas ? (c.maxWidth - 10) / 2 : c.maxWidth;
          return Wrap(spacing: 10, runSpacing: 10, children: [
            for (var i = 0; i < _funciones.length; i++)
              SizedBox(
                width: ancho,
                child: AppCard(
                  blur: false,
                  child: Row(children: [
                    MotionIcon(_funciones[i].$1, size: 26, color: t.chart[i % t.chart.length],
                        delay: Duration(milliseconds: 80 * i)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_funciones[i].$2,
                            style: GoogleFonts.poppins(fontSize: 13.5, fontWeight: FontWeight.w700)),
                        Text(_funciones[i].$3,
                            style: GoogleFonts.poppins(fontSize: 11.5, color: t.muted, height: 1.35)),
                      ]),
                    ),
                  ]),
                ),
              ),
          ]);
        }),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Universidad
// ═════════════════════════════════════════════════════════════════════════════
class _Universidad extends StatefulWidget {
  const _Universidad({required this.contenido, required this.servicio, required this.onRecargar});
  final GuestContent? contenido;
  final GuestService servicio;
  final VoidCallback onRecargar;

  @override
  State<_Universidad> createState() => _UniversidadState();
}

class _UniversidadState extends State<_Universidad> {
  Set<String> _hechos = {};

  @override
  void initState() {
    super.initState();
    widget.servicio.loadChecklist().then((h) { if (mounted) setState(() => _hechos = h); });
  }

  void _marcar(String requisito, bool v) {
    setState(() => v ? _hechos.add(requisito) : _hechos.remove(requisito));
    widget.servicio.saveChecklist(_hechos);
  }

  Future<void> _abrir(Uri uri) async {
    var ok = false;
    try { ok = await launchUrl(uri, mode: LaunchMode.externalApplication); } catch (_) {}
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('No se pudo abrir ${uri.toString()}', style: GoogleFonts.poppins(color: Colors.white)),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.contenido;
    if (c == null) {
      return ListView(
        padding: const EdgeInsets.all(AppTokens.pagePadding),
        children: const [SkeletonBox(height: 120), SizedBox(height: 12), SkeletonBox(height: 160)],
      );
    }
    final t = context.tokens;
    final info = c.info;
    final listos = info.requirements.where(_hechos.contains).length;
    final total = info.requirements.length;

    return RefreshIndicator(
      onRefresh: () async => widget.onRecargar(),
      child: ListView(
        key: const PageStorageKey('guest_universidad'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(AppTokens.pagePadding, 12, AppTokens.pagePadding, 40),
        children: [
          if (c.isSample || c.offline)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Semantics(
                liveRegion: true,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: t.warning.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(AppTokens.radiusControl),
                    border: Border.all(color: t.warning.withValues(alpha: 0.4)),
                  ),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(c.offline ? PhosphorIconsFill.wifiSlash : PhosphorIconsFill.info, color: t.warning, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        c.offline
                            ? 'Sin conexión: mostrando la última información guardada. Desliza hacia abajo para actualizar.'
                            : 'Esta información es de ejemplo: la universidad aún no ha publicado la definitiva.',
                        style: GoogleFonts.poppins(fontSize: 12.5, height: 1.4)),
                    ),
                  ]),
                ),
              ),
            ),
          if (info.about.isNotEmpty) ...[
            SectionTitle(info.name, icon: PhosphorIconsRegular.buildings),
            const SizedBox(height: 8),
            AppCard(blur: false, child: Text(info.about, style: GoogleFonts.poppins(fontSize: 13.5, height: 1.5))),
            const SizedBox(height: AppTokens.sectionGap),
          ],
          if (info.programs.isNotEmpty) ...[
            const SectionTitle('Programas', icon: PhosphorIconsRegular.graduationCap),
            const SizedBox(height: 8),
            for (final p in info.programs)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AppCard(
                  blur: false,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(p.name, style: GoogleFonts.poppins(fontSize: 14.5, fontWeight: FontWeight.w700))),
                      if (p.level.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10)),
                          child: Text(p.level, style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600)),
                        ),
                    ]),
                    if (p.description.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(p.description, style: GoogleFonts.poppins(fontSize: 12.5, color: t.muted, height: 1.4)),
                      ),
                  ]),
                ),
              ),
            const SizedBox(height: AppTokens.sectionGap - 10),
          ],
          if (info.steps.isNotEmpty || info.requirements.isNotEmpty) ...[
            const SectionTitle('Mi ruta de matrícula', icon: PhosphorIconsRegular.signpost,
                subtitle: 'Sigue los pasos y marca lo que ya tienes'),
            const SizedBox(height: 8),
            if (total > 0)
              AppCard(
                blur: false,
                child: Semantics(
                  label: 'Requisitos listos: $listos de $total',
                  child: Row(children: [
                    SizedBox(
                      width: 56, height: 56,
                      child: Stack(alignment: Alignment.center, children: [
                        CircularProgressIndicator(
                          value: listos / total, strokeWidth: 6,
                          backgroundColor: t.muted.withValues(alpha: 0.18),
                          color: listos == total ? t.success : Theme.of(context).colorScheme.primary,
                        ),
                        ExcludeSemantics(
                          child: Text('$listos/$total',
                              style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w800)),
                        ),
                      ]),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        listos == total ? '¡Tienes todos los requisitos listos!' : 'Requisitos que ya reuniste',
                        style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700)),
                    ),
                  ]),
                ),
              ),
            const SizedBox(height: 10),
            for (var i = 0; i < info.steps.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AppCard(
                  blur: false,
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    ExcludeSemantics(
                      child: CircleAvatar(
                        radius: 14,
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        child: Text('${i + 1}', style: GoogleFonts.poppins(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Paso ${i + 1}: ${info.steps[i].title}',
                            style: GoogleFonts.poppins(fontSize: 13.5, fontWeight: FontWeight.w700)),
                        if (info.steps[i].text.isNotEmpty)
                          Text(info.steps[i].text,
                              style: GoogleFonts.poppins(fontSize: 12.5, color: t.muted, height: 1.4)),
                      ]),
                    ),
                  ]),
                ),
              ),
            if (total > 0) ...[
              const SizedBox(height: 4),
              AppCard(
                blur: false,
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                child: Column(children: [
                  for (final r in info.requirements)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _hechos.contains(r),
                      onChanged: (v) => _marcar(r, v ?? false),
                      title: Text(r, style: GoogleFonts.poppins(fontSize: 13)),
                    ),
                ]),
              ),
            ],
            if (info.note.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(info.note, style: GoogleFonts.poppins(fontSize: 12, color: t.muted, height: 1.4)),
              ),
            const SizedBox(height: AppTokens.sectionGap - 10),
          ],
          if (info.dates.isNotEmpty) ...[
            const SectionTitle('Fechas importantes', icon: PhosphorIconsRegular.calendarCheck),
            const SizedBox(height: 8),
            AppCard(
              blur: false,
              child: Column(children: [
                for (final d in info.dates)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(children: [
                      Expanded(child: Text(d.label, style: GoogleFonts.poppins(fontSize: 13))),
                      Text(d.value, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700)),
                    ]),
                  ),
              ]),
            ),
            const SizedBox(height: AppTokens.sectionGap),
          ],
          const SectionTitle('Contacto', icon: PhosphorIconsRegular.addressBook),
          const SizedBox(height: 8),
          if (info.contact.isEmpty)
            const EmptyState(icon: PhosphorIconsRegular.addressBook, message: 'La universidad aún no ha publicado sus datos de contacto.')
          else
            AppCard(
              blur: false,
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(children: [
                if (info.contact.phone.isNotEmpty)
                  _contacto(PhosphorIconsRegular.phone, 'Llamar', info.contact.phone,
                      () => _abrir(Uri(scheme: 'tel', path: info.contact.phone.replaceAll(RegExp(r'[^0-9+]'), '')))),
                if (info.contact.email.isNotEmpty)
                  _contacto(PhosphorIconsRegular.envelopeSimple, 'Escribir', info.contact.email,
                      () => _abrir(Uri(scheme: 'mailto', path: info.contact.email))),
                if (info.contact.website.isNotEmpty)
                  _contacto(PhosphorIconsRegular.globe, 'Sitio web', info.contact.website,
                      () => _abrir(Uri.parse(info.contact.website))),
                if (info.contact.address.isNotEmpty)
                  _contacto(PhosphorIconsRegular.mapPin, 'Dirección', info.contact.address, null),
                if (info.contact.schedule.isNotEmpty)
                  _contacto(PhosphorIconsRegular.clock, 'Horario', info.contact.schedule, null),
              ]),
            ),
        ],
      ),
    );
  }

  Widget _contacto(IconData icono, String etiqueta, String valor, VoidCallback? onTap) => ListTile(
        dense: true,
        leading: Icon(icono, color: Theme.of(context).colorScheme.primary),
        title: Text(valor, style: GoogleFonts.poppins(fontSize: 13.5, fontWeight: FontWeight.w600)),
        subtitle: Text(etiqueta, style: GoogleFonts.poppins(fontSize: 11.5)),
        trailing: onTap == null ? null : const Icon(PhosphorIconsRegular.arrowSquareOut, size: 18),
        onTap: onTap,
      );
}
