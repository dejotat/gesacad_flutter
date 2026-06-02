import 'package:gesacad/utils/platform_utils.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:typed_data';
import 'dart:convert';
import '../../services/settings_service.dart';
import '../../services/api_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailPersonalCtrl = TextEditingController();
  final _emailInstCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _programaCtrl = TextEditingController();
  final _semestreCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();

  String _rol = '';
  bool _saving = false;
  bool _saved = false;
  Uint8List? _photoBytes;
  late AnimationController _anim;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _fade = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
    _anim.forward();
    _loadProfile();
  }

  @override
  void dispose() {
    _anim.dispose();
    for (final c in [_nameCtrl, _emailPersonalCtrl, _emailInstCtrl, _telefonoCtrl, _programaCtrl, _semestreCtrl, _bioCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Carga el perfil directamente desde el backend (fuente de verdad).
  /// Si no hay conexión, cae al caché de SharedPreferences.
  Future<void> _loadProfile() async {
    final prefs  = await SharedPreferences.getInstance();
    final userId = prefs.getInt('userId') ?? 0;
    _rol         = prefs.getString('userRol') ?? '';
    _nameCtrl.text = prefs.getString('userName') ?? '';

    // Foto desde caché local (no está en el backend aún)
    final photoB64 = prefs.getString('profile_photo');
    if (photoB64 != null && photoB64.isNotEmpty) {
      try { _photoBytes = base64Decode(photoB64); } catch (_) {}
    }

    if (userId > 0) {
      // Intentar cargar desde el backend (fuente de verdad)
      try {
        final uri = Uri.https(
          'gesacad-backend-production.up.railway.app',
          '/users/getProfile/$userId',
        );
        final res = await http
            .get(uri)
            .timeout(const Duration(seconds: 15));

        if (res.statusCode == 200 && mounted) {
          final perfil = jsonDecode(res.body) as Map<String, dynamic>;

          void setField(TextEditingController ctrl, String key) {
            final val = perfil[key]?.toString() ?? '';
            if (val.isNotEmpty) ctrl.text = val;
          }

          setField(_telefonoCtrl,      'telefono');
          setField(_bioCtrl,           'bio');
          setField(_emailPersonalCtrl, 'email_personal');
          setField(_programaCtrl,      'programa');
          setField(_semestreCtrl,      'semestre');

          // Actualizar caché local con los valores del servidor
          await prefs.setString('profile_telefono',       _telefonoCtrl.text);
          await prefs.setString('profile_bio',            _bioCtrl.text);
          await prefs.setString('profile_email_personal', _emailPersonalCtrl.text);
          await prefs.setString('profile_programa',       _programaCtrl.text);
          await prefs.setString('profile_semestre',       _semestreCtrl.text);

          if (mounted) setState(() {});
          return;
        }
      } catch (_) {
        // Si falla el backend se usa caché local (abajo)
      }
    }

    // Fallback: sin conexión o error → usar caché local
    _emailPersonalCtrl.text = prefs.getString('profile_email_personal') ?? '';
    _emailInstCtrl.text     = prefs.getString('profile_email_inst')     ?? '';
    _telefonoCtrl.text      = prefs.getString('profile_telefono')       ?? '';
    _programaCtrl.text      = prefs.getString('profile_programa')       ?? '';
    _semestreCtrl.text      = prefs.getString('profile_semestre')       ?? '';
    _bioCtrl.text           = prefs.getString('profile_bio')            ?? '';
    if (mounted) setState(() {});
  }

  Future<void> _pickPhoto() async {
    // PlatformUtils selecciona automáticamente web (dart:html) o Android (image_picker)
    final bytes = await PlatformUtils.pickImage();
    if (bytes == null || !mounted) return;
    setState(() => _photoBytes = Uint8List.fromList(bytes));
  }

  /// Guarda el perfil: primero en el backend y luego actualiza la caché local.
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final prefs  = await SharedPreferences.getInstance();
    final userId = prefs.getInt('userId') ?? 0;

    // Guardar datos extendidos en el backend (persistencia real)
    bool exito = false;
    if (userId > 0) {
      exito = await ApiService().updateUserProfile(
        userId:        userId,
        telefono:      _telefonoCtrl.text.trim(),
        bio:           _bioCtrl.text.trim(),
        emailPersonal: _emailPersonalCtrl.text.trim(),
        programa:      _programaCtrl.text.trim(),
        semestre:      _semestreCtrl.text.trim(),
      );
    }

    // Actualizar la caché local de SharedPreferences (para acceso rápido sin red)
    await prefs.setString('userName',               _nameCtrl.text.trim());
    await prefs.setString('profile_email_personal', _emailPersonalCtrl.text.trim());
    await prefs.setString('profile_email_inst',     _emailInstCtrl.text.trim());
    await prefs.setString('profile_telefono',       _telefonoCtrl.text.trim());
    await prefs.setString('profile_programa',       _programaCtrl.text.trim());
    await prefs.setString('profile_semestre',       _semestreCtrl.text.trim());
    await prefs.setString('profile_bio',            _bioCtrl.text.trim());
    if (_photoBytes != null) {
      await prefs.setString('profile_photo', base64Encode(_photoBytes!));
    }

    if (mounted) {
      setState(() { _saving = false; _saved = true; });
      // Mostrar mensaje diferenciado según si el backend respondió correctamente
      if (!exito && userId > 0) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Sin conexión — datos guardados localmente'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ));
      }
      Future.delayed(
        const Duration(seconds: 3),
        () { if (mounted) setState(() => _saved = false); },
      );
    }
  }

  String get _initials {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return '?';
    final parts = name.split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return parts[0][0].toUpperCase();
  }

  List<Color> get _rolGradient {
    if (_rol == 'Admin') return [const Color(0xFF7C3AED), const Color(0xFFDB2777)];
    if (_rol == 'Teacher') return [const Color(0xFF059669), const Color(0xFF0EA5E9)];
    return [const Color(0xFF2563EB), const Color(0xFF7C3AED)];
  }

  IconData get _rolIcon {
    if (_rol == 'Admin') return Icons.admin_panel_settings_rounded;
    if (_rol == 'Teacher') return Icons.school_rounded;
    return Icons.person_rounded;
  }

  String get _rolLabel {
    if (_rol == 'Admin') return 'Administrador del sistema';
    if (_rol == 'Teacher') return 'Profesor';
    return 'Estudiante';
  }

  @override
  Widget build(BuildContext context) {
    final themeType = AppSettings.currentTheme.value;
    final primary = Theme.of(context).colorScheme.primary;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFF),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: themeType.gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
          ),
        ),
        leading: IconButton(
          tooltip: 'Regresar',
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Mi Perfil', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700)),
        centerTitle: true,
        actions: [
          if (_saved)
            Container(
              margin: const EdgeInsets.only(right: 14, top: 8, bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
              child: Row(children: [
                const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 16),
                const SizedBox(width: 4),
                Text('Guardado', style: GoogleFonts.poppins(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
              ]),
            ),
        ],
      ),
      body: FadeTransition(
        opacity: _fade,
        child: SingleChildScrollView(
          child: Column(
            children: [
              // Header con avatar
              _buildAvatarHeader(themeType, primary),
              // Contenido
              Padding(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _sectionTitle('Datos Personales', Icons.person_rounded, primary),
                    const SizedBox(height: 12),
                    _card(isDark, children: [
                      _field(_nameCtrl, 'Nombre completo', Icons.badge_rounded, primary,
                          validator: (v) => (v == null || v.trim().length < 2) ? 'Mínimo 2 caracteres' : null),
                      const SizedBox(height: 14),
                      _field(_telefonoCtrl, 'Teléfono / Celular', Icons.phone_rounded, primary,
                          keyboard: TextInputType.phone),
                      const SizedBox(height: 14),
                      _fieldArea(_bioCtrl, 'Descripción personal / Bio', Icons.description_rounded, primary),
                    ]),
                    const SizedBox(height: 24),
                    _sectionTitle('Datos Institucionales', Icons.school_rounded, primary),
                    const SizedBox(height: 12),
                    _card(isDark, children: [
                      _field(_emailInstCtrl, 'Correo institucional', Icons.email_rounded, primary,
                          keyboard: TextInputType.emailAddress, helper: 'usuario@unicomfacauca.edu.co'),
                      const SizedBox(height: 14),
                      _field(_emailPersonalCtrl, 'Correo personal', Icons.alternate_email_rounded, primary,
                          keyboard: TextInputType.emailAddress),
                      const SizedBox(height: 14),
                      _field(_programaCtrl, 'Programa académico', Icons.book_rounded, primary),
                      const SizedBox(height: 14),
                      _field(_semestreCtrl, 'Semestre / Período', Icons.calendar_today_rounded, primary,
                          keyboard: TextInputType.number),
                    ]),
                    const SizedBox(height: 28),
                    // Botón guardar
                    Container(
                      width: double.infinity,
                      height: 54,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: themeType.gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [BoxShadow(color: primary.withOpacity(0.4), blurRadius: 16, offset: const Offset(0, 6))],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: _saving ? null : _save,
                          child: Center(child: _saving
                              ? const SizedBox(width: 22, height: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                              : Row(mainAxisSize: MainAxisSize.min, children: [
                                  const Icon(Icons.save_rounded, color: Colors.white, size: 20),
                                  const SizedBox(width: 10),
                                  Text('Guardar cambios', style: GoogleFonts.poppins(
                                      fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
                                ])),
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarHeader(AppThemeType themeType, Color primary) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          themeType.gradient[0].withOpacity(0.08),
          themeType.gradient[1].withOpacity(0.04),
        ], begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      child: Column(children: [
        GestureDetector(
          onTap: _pickPhoto,
          child: Stack(children: [
            Container(
              width: 110, height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: _rolGradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
                boxShadow: [BoxShadow(color: primary.withOpacity(0.35), blurRadius: 24, offset: const Offset(0, 8))],
                border: Border.all(color: Colors.white, width: 4),
              ),
              child: _photoBytes != null
                  ? ClipOval(child: Image.memory(_photoBytes!, fit: BoxFit.cover, width: 110, height: 110))
                  : Center(child: Text(_initials, style: GoogleFonts.poppins(
                      color: Colors.white, fontSize: 38, fontWeight: FontWeight.w800))),
            ),
            Positioned(bottom: 4, right: 4, child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: _rolGradient),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2.5),
                boxShadow: [BoxShadow(color: primary.withOpacity(0.3), blurRadius: 8)],
              ),
              child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 15),
            )),
          ]),
        ),
        const SizedBox(height: 12),
        Text(_nameCtrl.text.isNotEmpty ? _nameCtrl.text : 'Tu nombre',
            style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w700, color: const Color(0xFF1E1B4B))),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: _rolGradient),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: primary.withOpacity(0.25), blurRadius: 8, offset: const Offset(0, 3))],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(_rolIcon, color: Colors.white, size: 14),
            const SizedBox(width: 6),
            Text(_rolLabel, style: GoogleFonts.poppins(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
          ]),
        ),
        const SizedBox(height: 6),
        Text('Toca la foto para cambiarla', style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade400)),
      ]),
    );
  }

  Widget _sectionTitle(String title, IconData icon, Color primary) => Row(children: [
    Container(padding: const EdgeInsets.all(7), decoration: BoxDecoration(
      color: primary.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
      child: Icon(icon, color: primary, size: 18)),
    const SizedBox(width: 10),
    Text(title, style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: const Color(0xFF1E1B4B))),
  ]);

  Widget _card(bool isDark, {required List<Widget> children}) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 16, offset: const Offset(0, 4))],
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
  );

  Widget _field(TextEditingController ctrl, String label, IconData icon, Color primary, {
    TextInputType keyboard = TextInputType.text, String? helper, String? Function(String?)? validator,
  }) => TextFormField(
    controller: ctrl,
    keyboardType: keyboard,
    style: GoogleFonts.poppins(fontSize: 14),
    decoration: InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.poppins(color: Colors.grey.shade500, fontSize: 13),
      prefixIcon: Icon(icon, color: primary, size: 20),
      helperText: helper,
      helperStyle: GoogleFonts.poppins(fontSize: 11),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: primary, width: 2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade200, width: 1.5),
      ),
    ),
    validator: validator,
  );

  Widget _fieldArea(TextEditingController ctrl, String label, IconData icon, Color primary) => TextFormField(
    controller: ctrl,
    maxLines: 3,
    style: GoogleFonts.poppins(fontSize: 14),
    decoration: InputDecoration(
      labelText: label,
      alignLabelWithHint: true,
      labelStyle: GoogleFonts.poppins(color: Colors.grey.shade500, fontSize: 13),
      prefixIcon: Padding(padding: const EdgeInsets.only(bottom: 48), child: Icon(icon, color: primary, size: 20)),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: primary, width: 2)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200, width: 1.5)),
    ),
  );
}
