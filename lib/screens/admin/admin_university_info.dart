import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../config/app_tokens.dart';
import '../../models/university_info.dart';
import '../../services/guest_service.dart';
import '../../widgets/ui/ui.dart';

/// Un renglón editable con varios campos (programa, paso, fecha…).
class _Fila {
  _Fila(List<String> valores) : c = [for (final v in valores) TextEditingController(text: v)];
  final List<TextEditingController> c;
  void dispose() { for (final x in c) { x.dispose(); } }
}

/// El Admin edita lo que ven los invitados en la sección "Universidad" (CU-10).
class AdminUniversityInfo extends StatefulWidget {
  const AdminUniversityInfo({super.key, this.servicio = const GuestService()});
  final GuestService servicio;

  @override
  State<AdminUniversityInfo> createState() => _AdminUniversityInfoState();
}

class _AdminUniversityInfoState extends State<AdminUniversityInfo> {
  final _nombre = TextEditingController();
  final _lema = TextEditingController();
  final _acerca = TextEditingController();
  final _nota = TextEditingController();
  final _tel = TextEditingController();
  final _correo = TextEditingController();
  final _web = TextEditingController();
  final _direccion = TextEditingController();
  final _horario = TextEditingController();
  final _programas = <_Fila>[];
  final _pasos = <_Fila>[];
  final _requisitos = <_Fila>[];
  final _fechas = <_Fila>[];

  bool _cargando = true;
  bool _guardando = false;
  bool _esEjemplo = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    for (final x in [_nombre, _lema, _acerca, _nota, _tel, _correo, _web, _direccion, _horario]) { x.dispose(); }
    for (final l in [_programas, _pasos, _requisitos, _fechas]) { for (final f in l) { f.dispose(); } }
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() { _cargando = true; _error = null; });
    final c = await widget.servicio.load();
    if (!mounted) return;
    final i = c.info;
    for (final l in [_programas, _pasos, _requisitos, _fechas]) {
      for (final f in l) { f.dispose(); }
      l.clear();
    }
    setState(() {
      _nombre.text = i.name; _lema.text = i.tagline; _acerca.text = i.about; _nota.text = i.note;
      _tel.text = i.contact.phone; _correo.text = i.contact.email; _web.text = i.contact.website;
      _direccion.text = i.contact.address; _horario.text = i.contact.schedule;
      _programas.addAll(i.programs.map((p) => _Fila([p.name, p.level, p.description])));
      _pasos.addAll(i.steps.map((s) => _Fila([s.title, s.text])));
      _requisitos.addAll(i.requirements.map((r) => _Fila([r])));
      _fechas.addAll(i.dates.map((d) => _Fila([d.label, d.value])));
      _esEjemplo = c.isSample;
      _cargando = false;
    });
  }

  UniversityInfo _armar() => UniversityInfo(
        name: _nombre.text.trim(),
        tagline: _lema.text.trim(),
        about: _acerca.text.trim(),
        note: _nota.text.trim(),
        programs: [
          for (final f in _programas)
            if (f.c[0].text.trim().isNotEmpty)
              UniProgram(name: f.c[0].text.trim(), level: f.c[1].text.trim(), description: f.c[2].text.trim()),
        ],
        steps: [
          for (final f in _pasos)
            if (f.c[0].text.trim().isNotEmpty) UniStep(title: f.c[0].text.trim(), text: f.c[1].text.trim()),
        ],
        requirements: [for (final f in _requisitos) if (f.c[0].text.trim().isNotEmpty) f.c[0].text.trim()],
        dates: [
          for (final f in _fechas)
            if (f.c[0].text.trim().isNotEmpty) UniDate(label: f.c[0].text.trim(), value: f.c[1].text.trim()),
        ],
        contact: UniContact(
          phone: _tel.text.trim(), email: _correo.text.trim(), website: _web.text.trim(),
          address: _direccion.text.trim(), schedule: _horario.text.trim(),
        ),
      );

  Future<void> _guardar() async {
    if (_nombre.text.trim().isEmpty) {
      setState(() => _error = 'El nombre de la universidad es obligatorio.');
      return;
    }
    setState(() { _guardando = true; _error = null; });
    try {
      await widget.servicio.save(_armar());
      if (!mounted) return;
      setState(() { _guardando = false; _esEjemplo = false; });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: context.tokens.success,
        content: Text('Guardado. Los invitados ya ven la nueva información.',
            style: GoogleFonts.poppins(color: Colors.white)),
      ));
    } catch (e) {
      if (mounted) setState(() { _guardando = false; _error = e.toString(); });
    }
  }

  Future<void> _restablecer() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('¿Restablecer el ejemplo?', style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        content: const Text('Se descartará la información publicada y los invitados volverán a ver contenido de ejemplo.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Restablecer')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.servicio.reset();
      await _cargar();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Widget _campo(TextEditingController c, String etiqueta,
          {int lineas = 1, int? max, TextInputType? tipo, String? pista}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          minLines: lineas, maxLines: lineas == 1 ? 1 : lineas + 2,
          maxLength: max, keyboardType: tipo,
          decoration: InputDecoration(labelText: etiqueta, hintText: pista, counterText: ''),
        ),
      );

  /// Lista editable de renglones con botón de agregar y de quitar.
  Widget _lista({
    required String titulo,
    required IconData icono,
    required List<_Fila> filas,
    required List<String> etiquetas,
    required String agregar,
    List<int> lineas = const [],
  }) {
    final t = context.tokens;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionTitle(titulo, icon: icono),
      const SizedBox(height: 8),
      for (var i = 0; i < filas.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: AppCard(
            blur: false,
            padding: const EdgeInsets.fromLTRB(14, 12, 6, 2),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(children: [
                  for (var k = 0; k < etiquetas.length; k++)
                    _campo(filas[i].c[k], etiquetas[k], lineas: k < lineas.length ? lineas[k] : 1),
                ]),
              ),
              AnimatedIconButton(
                tooltip: 'Quitar ${titulo.toLowerCase()} ${i + 1}',
                icon: PhosphorIconsRegular.trash,
                reaction: IconReaction.shake,
                onPressed: () => setState(() { filas.removeAt(i).dispose(); }),
              ),
            ]),
          ),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: AppButton(
          label: agregar, icon: PhosphorIconsBold.plus, style: AppButtonStyle.tonal, height: 40,
          onPressed: () => setState(() => filas.add(_Fila([for (final _ in etiquetas) '']))),
        ),
      ),
      SizedBox(height: AppTokens.sectionGap, child: Divider(color: t.muted.withValues(alpha: 0.0))),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Información para invitados'),
        actions: [
          AnimatedIconButton(
            tooltip: 'Restablecer contenido de ejemplo',
            icon: PhosphorIconsRegular.arrowCounterClockwise,
            reaction: IconReaction.spin,
            onPressed: _cargando || _guardando ? null : _restablecer,
          ),
        ],
      ),
      body: _cargando
          ? ListView(padding: const EdgeInsets.all(AppTokens.pagePadding),
              children: const [SkeletonBox(height: 100), SizedBox(height: 12), SkeletonBox(height: 160)])
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(AppTokens.pagePadding, 12, AppTokens.pagePadding, 40),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: (_esEjemplo ? t.warning : t.info).withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(AppTokens.radiusControl),
                        border: Border.all(color: (_esEjemplo ? t.warning : t.info).withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        _esEjemplo
                            ? 'Los invitados están viendo contenido de EJEMPLO. Reemplázalo con la información real y guarda.'
                            : 'Esto es lo que ven los visitantes que entran como invitados desde el inicio de sesión.',
                        style: GoogleFonts.poppins(fontSize: 12.5, height: 1.4)),
                    ),
                    const SizedBox(height: AppTokens.sectionGap),
                    const SectionTitle('General', icon: PhosphorIconsRegular.buildings),
                    const SizedBox(height: 8),
                    _campo(_nombre, 'Nombre de la universidad *', max: 80),
                    _campo(_lema, 'Lema', max: 120),
                    _campo(_acerca, 'Presentación', lineas: 3, max: 1500),
                    const SizedBox(height: 8),
                    _lista(
                      titulo: 'Programas', icono: PhosphorIconsRegular.graduationCap, filas: _programas,
                      etiquetas: const ['Nombre del programa', 'Nivel (ej. Pregrado)', 'Descripción'],
                      lineas: const [1, 1, 2], agregar: 'Agregar programa'),
                    _lista(
                      titulo: 'Pasos de matrícula', icono: PhosphorIconsRegular.signpost, filas: _pasos,
                      etiquetas: const ['Título del paso', 'Explicación'], lineas: const [1, 2],
                      agregar: 'Agregar paso'),
                    _lista(
                      titulo: 'Requisitos', icono: PhosphorIconsRegular.listChecks, filas: _requisitos,
                      etiquetas: const ['Requisito'], agregar: 'Agregar requisito'),
                    _lista(
                      titulo: 'Fechas importantes', icono: PhosphorIconsRegular.calendarCheck, filas: _fechas,
                      etiquetas: const ['Nombre (ej. Cierre de inscripciones)', 'Fecha o valor'],
                      agregar: 'Agregar fecha'),
                    _campo(_nota, 'Nota sobre la matrícula (opcional)', lineas: 2, max: 400),
                    const SectionTitle('Contacto', icon: PhosphorIconsRegular.addressBook),
                    const SizedBox(height: 8),
                    _campo(_tel, 'Teléfono', tipo: TextInputType.phone, max: 40),
                    _campo(_correo, 'Correo', tipo: TextInputType.emailAddress, max: 120),
                    _campo(_web, 'Sitio web (https://…)', tipo: TextInputType.url, max: 200),
                    _campo(_direccion, 'Dirección', max: 200),
                    _campo(_horario, 'Horario de atención', max: 120),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(_error!,
                              style: GoogleFonts.poppins(fontSize: 12.5, color: t.danger, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    AppButton(
                      label: 'Guardar y publicar',
                      icon: PhosphorIconsFill.floppyDisk,
                      reaction: IconReaction.bounce,
                      expand: true,
                      loading: _guardando,
                      onPressed: _guardando ? null : _guardar,
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
