import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/settings_service.dart';
import '../widgets/animated_logo.dart';
import 'admin/admin_home.dart';
import 'teacher/teacher_home.dart';
import 'student/student_home.dart';
import 'auth/forgot_password_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _showPass = false;
  bool _loading = false;
  bool _googleLoading = false;
  String? _serverError;

  final FocusNode _userFocus = FocusNode();
  final FocusNode _passFocus = FocusNode();

  late AnimationController _anim;
  late Animation<double> _fade;
  late Animation<Offset> _slide;
  late AnimationController _loginBtnCtrl;
  late Animation<double> _loginBtnScale;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 750));
    _fade = CurvedAnimation(parent: _anim, curve: Curves.easeIn);
    _slide = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(CurvedAnimation(parent: _anim, curve: Curves.easeOut));
    _anim.forward();

    _loginBtnCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 120));
    _loginBtnScale = Tween<double>(begin: 1.0, end: 0.96)
        .animate(CurvedAnimation(parent: _loginBtnCtrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _anim.dispose();
    _loginBtnCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _userFocus.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  // ── Validación ────────────────────────────────────────────────────────────

  String? _validateUsername(String? v) {
    if (v == null || v.trim().isEmpty) return 'El usuario es obligatorio';
    if (v.trim().length < 3) return 'Mínimo 3 caracteres';
    if (v.trim().length > 50) return 'Máximo 50 caracteres';
    return null;
  }

  /// Validación de contraseña al INICIAR SESIÓN.
  /// Solo verifica que no esté vacía — el backend valida si coincide con la BD.
  /// La validación estricta (mayúscula, símbolo, etc.) es solo al registrar usuario.
  String? _validatePassword(String? v) {
    if (v == null || v.isEmpty) return 'La contraseña es obligatoria';
    if (v.length < 3) return 'Contraseña muy corta';
    return null; // El backend verifica si la contraseña es correcta
  }

  String _mapLoginError(Map<String, dynamic> res) {
    final code = res['response']?.toString().toUpperCase() ?? '';
    if (code.contains('USER_NOT_FOUND') || code.contains('USERORPASSINVALID') || code.isEmpty)
      return 'Usuario no encontrado. Verifica tu nombre de usuario.';
    if (code.contains('WRONG_PASSWORD') || code.contains('INCORRECT'))
      return 'Contraseña incorrecta. Intenta de nuevo.';
    if (code.contains('INACTIVE') || code.contains('DISABLED'))
      return 'Cuenta inactiva. Contacta al administrador del sistema.';
    return 'Usuario o contraseña incorrectos. Verifica tus datos.';
  }

  // ── Login con usuario/contraseña ──────────────────────────────────────────

  Future<void> _login() async {
    setState(() => _serverError = null);
    if (!_formKey.currentState!.validate()) return;
    await _loginBtnCtrl.forward();
    await _loginBtnCtrl.reverse();
    setState(() => _loading = true);
    try {
      developer.log('[LoginScreen] Login → ${_userCtrl.text.trim()}',
          name: 'GESACAD.Auth');
      final res =
          await ApiService().login(_userCtrl.text.trim(), _passCtrl.text);
      if (!mounted) return;

      if (res['response'] == 'LOGIN_SUCCESFULLY') {
        await AuthService().saveSession(
          res['id'] as int,
          res['name'] as String? ?? _userCtrl.text.trim(),
          res['rol'] as String,
        );
        final rol = res['rol'] as String;
        final Widget home = rol == 'Admin'
            ? const AdminHome()
            : rol == 'Teacher'
                ? const TeacherHome()
                : const StudentHome();
        if (!mounted) return;
        Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (_) => home));
      } else {
        setState(() => _serverError = _mapLoginError(res));
      }
    } on TimeoutException {
      if (mounted) setState(() => _serverError =
          'El servidor tardó demasiado. Verifica tu conexión a internet.');
    } catch (_) {
      if (mounted) setState(() => _serverError =
          'No se pudo conectar al servidor. Verifica tu conexión a internet.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Google Sign-In ─────────────────────────────────────────────────────────

  static final _gSignIn = GoogleSignIn(scopes: ['email', 'profile']);

  Future<void> _signInWithGoogle() async {
    setState(() { _googleLoading = true; _serverError = null; });
    try {
      final account = await _gSignIn.signIn();
      if (!mounted) return;
      if (account == null) {
        setState(() => _googleLoading = false);
        return;
      }
      developer.log('[LoginScreen] Google auth OK: ${account.email}', name: 'GESACAD.Auth');

      final prefs = await SharedPreferences.getInstance();
      final linkedId   = prefs.getInt('google_id_${account.email}');
      final linkedName = prefs.getString('google_name_${account.email}');
      final linkedRol  = prefs.getString('google_rol_${account.email}');

      if (!mounted) return;
      if (linkedId != null && linkedName != null && linkedRol != null) {
        await AuthService().saveSession(linkedId, linkedName, linkedRol);
        developer.log('[LoginScreen] Google linked session → $linkedName ($linkedRol)',
            name: 'GESACAD.Auth');
        _navigateByRole(linkedRol);
      } else {
        setState(() => _googleLoading = false);
        _showGoogleLinkDialog(account.email, account.displayName ?? '');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _googleLoading = false);
      final msg = e.toString().toLowerCase();
      if (msg.contains('clientid') || msg.contains('audience') ||
          msg.contains('configuration') || msg.contains('initialized') ||
          msg.contains('not been initialized')) {
        _showGoogleSetupDialog();
      } else {
        developer.log('[LoginScreen] Google error: $e', name: 'GESACAD.Auth', error: e);
        setState(() => _serverError = 'No se pudo conectar con Google. Intenta de nuevo.');
      }
    }
  }

  void _showGoogleLinkDialog(String googleEmail, String googleName) {
    final linkUserCtrl = TextEditingController();
    final linkPassCtrl = TextEditingController();
    bool linking = false;
    String? linkError;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.green.shade50, shape: BoxShape.circle),
              child: const Icon(Icons.link_rounded, color: Colors.green, size: 26),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Vincular cuenta Google',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blue.shade50, borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text('Google verificado: $googleEmail',
                    style: GoogleFonts.poppins(fontSize: 12))),
              ]),
            ),
            const SizedBox(height: 14),
            Text('Ingresa tus credenciales GESACAD para vincular:',
                style: GoogleFonts.poppins(fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: linkUserCtrl,
              decoration: InputDecoration(
                labelText: 'Usuario GESACAD',
                prefixIcon: const Icon(Icons.person_rounded),
                labelStyle: GoogleFonts.poppins(fontSize: 13),
              ),
              style: GoogleFonts.poppins(fontSize: 14),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: linkPassCtrl,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'Contraseña',
                prefixIcon: const Icon(Icons.lock_rounded),
                labelStyle: GoogleFonts.poppins(fontSize: 13),
              ),
              style: GoogleFonts.poppins(fontSize: 14),
            ),
            if (linkError != null) ...[
              const SizedBox(height: 8),
              Text(linkError!, style: GoogleFonts.poppins(
                  fontSize: 12, color: Colors.red)),
            ],
          ]),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancelar', style: GoogleFonts.poppins(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: linking ? null : () async {
                setS(() { linking = true; linkError = null; });
                try {
                  final resp = await ApiService().login(
                      linkUserCtrl.text.trim(), linkPassCtrl.text.trim());
                  if (resp['response'] == 'LOGIN_SUCCESFULLY') {
                    final id   = resp['id']   as int;
                    final name = resp['name'] as String;
                    final rol  = resp['rol']  as String;
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setInt('google_id_$googleEmail',    id);
                    await prefs.setString('google_name_$googleEmail', name);
                    await prefs.setString('google_rol_$googleEmail',  rol);
                    await AuthService().saveSession(id, name, rol);
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx);
                    _navigateByRole(rol);
                  } else {
                    setS(() { linking = false; linkError = 'Usuario o contraseña incorrectos'; });
                  }
                } catch (_) {
                  setS(() { linking = false; linkError = 'Error de conexión con el servidor'; });
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppSettings.currentTheme.value.primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: linking
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text('Vincular y entrar', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateByRole(String rol) {
    Widget dest;
    if (rol == 'Admin') dest = const AdminHome();
    else if (rol == 'Teacher') dest = const TeacherHome();
    else dest = const StudentHome();
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => dest));
  }

  void _showGoogleSetupDialog() {
    final primary = AppSettings.currentTheme.value.primaryColor;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.red.shade50, shape: BoxShape.circle,
            ),
            child: const Icon(Icons.g_mobiledata_rounded,
                color: Colors.red, size: 28),
          ),
          const SizedBox(width: 12),
          Text('Configurar Google Sign-In',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 17)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            'Falta el Client ID de OAuth en el proyecto. '
            'El administrador debe configurarlo una sola vez:',
            style: GoogleFonts.poppins(fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50, borderRadius: BorderRadius.circular(10),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Pasos:', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 12)),
              const SizedBox(height: 6),
              _dialogStep('1', 'Ir a console.cloud.google.com → APIs y servicios → Credenciales'),
              _dialogStep('2', 'Crear credencial → OAuth 2.0 → Aplicación web'),
              _dialogStep('3', 'Copiar el CLIENT_ID generado'),
              _dialogStep('4', 'Abrirlo en web/index.html y reemplazar TU_CLIENT_ID_AQUI'),
              _dialogStep('5', 'Ejecutar flutter pub add google_sign_in'),
            ]),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Entendido',
                style: GoogleFonts.poppins(
                    color: primary, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _dialogStep(String num, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 18, height: 18,
          decoration: BoxDecoration(
            color: Colors.grey.shade300, shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(num,
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade700)),
        ),
      ]),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final themeType = AppSettings.currentTheme.value;
    return Scaffold(
      body: Container(
        // Fondo con gradiente de dos colores del tema activo
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              themeType.gradient[0],
              themeType.gradient[1],
              themeType.primaryColor.withOpacity(0.6),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          // LayoutBuilder detecta el tamaño real de pantalla para ser responsive
          child: LayoutBuilder(
            builder: (ctx, constraints) {
              // Definir breakpoints responsive
              final ancho      = constraints.maxWidth;
              final esMobil    = ancho < 420;
              final esTablet   = ancho < 650;
              final logoTam    = esMobil ? 90.0 : esTablet ? 118.0 : 148.0;
              final padH       = esMobil ? 16.0 : esTablet ? 22.0 : 28.0;
              final padCard    = esMobil ? 20.0 : 28.0;

              return Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(horizontal: padH, vertical: 20),
                  child: ConstrainedBox(
                    // Máximo 480px en pantallas grandes (web desktop)
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: FadeTransition(
                      opacity: _fade,
                      child: SlideTransition(
                        position: _slide,
                        child: Column(
                          children: [
                            // ── Logo y título ──────────────────────────────
                            Semantics(
                              label: 'GESACAD, Sistema de Gestión Académica',
                              child: Column(children: [
                                AnimatedLogo(size: logoTam),
                                SizedBox(height: esMobil ? 10 : 16),
                                Text(
                                  'GESACAD',
                                  style: GoogleFonts.poppins(
                                    color: Colors.white,
                                    fontSize: esMobil ? 26 : 36,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 5,
                                    shadows: [
                                      Shadow(
                                        color: Colors.black.withOpacity(0.3),
                                        blurRadius: 12,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  'Campus Virtual',
                                  style: GoogleFonts.poppins(
                                      color: Colors.white70,
                                      fontSize: esMobil ? 11 : 13,
                                      letterSpacing: 2),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Unicomfacauca · v1.0.0',
                                  style: GoogleFonts.poppins(
                                      color: Colors.white38,
                                      fontSize: esMobil ? 9 : 11),
                                ),
                              ]),
                            ),
                            SizedBox(height: esMobil ? 18 : 28),

                            // ── Card de login ──────────────────────────────
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(28),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.22),
                                    blurRadius: 36,
                                    offset: const Offset(0, 12),
                                  ),
                                ],
                              ),
                              child: Padding(
                                padding: EdgeInsets.all(padCard),
                                child: Form(
                                  key: _formKey,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      // Título del formulario
                                      Text(
                                        'Iniciar Sesión',
                                        style: GoogleFonts.poppins(
                                            fontSize: esMobil ? 18 : 22,
                                            fontWeight: FontWeight.w700,
                                            color: themeType.primaryColor),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Ingresa tus credenciales institucionales',
                                        style: GoogleFonts.poppins(
                                            color: Colors.grey.shade500,
                                            fontSize: 12),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 24),

                                      // Campo usuario
                                      FocusTraversalGroup(
                                        policy: OrderedTraversalPolicy(),
                                        child: Column(children: [
                                          FocusTraversalOrder(
                                            order: const NumericFocusOrder(1),
                                            child: _buildField(
                                              controller: _userCtrl,
                                              focusNode: _userFocus,
                                              label: 'Usuario',
                                              icon: Icons.person_outline_rounded,
                                              helper: 'Nombre de usuario institucional',
                                              validator: _validateUsername,
                                              action: TextInputAction.next,
                                              primary: themeType.primaryColor,
                                              onSubmitted: (_) => _passFocus.requestFocus(),
                                              onChanged: (_) {
                                                if (_serverError != null)
                                                  setState(() => _serverError = null);
                                              },
                                            ),
                                          ),
                                          const SizedBox(height: 16),
                                          // Campo contraseña
                                          FocusTraversalOrder(
                                            order: const NumericFocusOrder(2),
                                            child: _buildPasswordField(themeType.primaryColor),
                                          ),
                                        ]),
                                      ),

                                      // Mensaje de error del servidor
                                      if (_serverError != null) ...[
                                        const SizedBox(height: 14),
                                        _buildError(_serverError!),
                                      ],

                                      // Enlace ¿Olvidaste tu contraseña?
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: TextButton(
                                          onPressed: () => Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                  builder: (_) => const ForgotPasswordScreen())),
                                          style: TextButton.styleFrom(
                                              padding: const EdgeInsets.symmetric(vertical: 4)),
                                          child: Text(
                                            '¿Olvidaste tu contraseña?',
                                            style: GoogleFonts.poppins(
                                              color: themeType.primaryColor,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 8),

                                      // Botón iniciar sesión con animación
                                      ScaleTransition(
                                        scale: _loginBtnScale,
                                        child: Semantics(
                                          label: 'Botón Iniciar Sesión',
                                          button: true,
                                          enabled: !_loading,
                                          child: Container(
                                            height: 52,
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                colors: themeType.gradient,
                                                begin: Alignment.centerLeft,
                                                end: Alignment.centerRight,
                                              ),
                                              borderRadius: BorderRadius.circular(14),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: themeType.primaryColor.withOpacity(0.4),
                                                  blurRadius: 16,
                                                  offset: const Offset(0, 6),
                                                ),
                                              ],
                                            ),
                                            child: Material(
                                              color: Colors.transparent,
                                              borderRadius: BorderRadius.circular(14),
                                              child: InkWell(
                                                borderRadius: BorderRadius.circular(14),
                                                onTap: _loading ? null : _login,
                                                splashColor: Colors.white.withOpacity(0.2),
                                                child: Center(
                                                  child: _loading
                                                      ? const SizedBox(
                                                          width: 22, height: 22,
                                                          child: CircularProgressIndicator(
                                                              strokeWidth: 2.5,
                                                              color: Colors.white))
                                                      : Row(
                                                          mainAxisAlignment: MainAxisAlignment.center,
                                                          children: [
                                                            const Icon(Icons.login_rounded,
                                                                color: Colors.white, size: 20),
                                                            const SizedBox(width: 10),
                                                            Text(
                                                              'Iniciar Sesión',
                                                              style: GoogleFonts.poppins(
                                                                color: Colors.white,
                                                                fontSize: 16,
                                                                fontWeight: FontWeight.w700,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 22),

                            // ── Pie de página ──────────────────────────────
                            Text(
                              'Corporación Universitaria Unicomfacauca',
                              style: GoogleFonts.poppins(
                                  color: Colors.white54,
                                  fontSize: esMobil ? 9 : 11),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '© 2025 GESACAD · Todos los derechos reservados',
                              style: GoogleFonts.poppins(
                                  color: Colors.white38,
                                  fontSize: esMobil ? 8 : 10),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }


  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required Color primary,
    FocusNode? focusNode,
    String? helper,
    String? Function(String?)? validator,
    TextInputAction action = TextInputAction.next,
    void Function(String)? onChanged,
    void Function(String)? onSubmitted,
    TextInputType keyboard = TextInputType.text,
  }) {
    return Semantics(
      label: label,
      textField: true,
      child: TextFormField(
        controller: controller,
        focusNode: focusNode,
        textInputAction: action,
        keyboardType: keyboard,
        autocorrect: false,
        style: GoogleFonts.poppins(fontSize: 15),
        onChanged: onChanged,
        onFieldSubmitted: onSubmitted,
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          prefixIcon: Icon(icon, color: primary),
        ),
        validator: validator,
      ),
    );
  }

  Widget _buildPasswordField(Color primary) {
    return Semantics(
      label: 'Campo de contraseña',
      obscured: !_showPass,
      textField: true,
      child: TextFormField(
        controller: _passCtrl,
        focusNode: _passFocus,
        obscureText: !_showPass,
        textInputAction: TextInputAction.done,
        style: GoogleFonts.poppins(fontSize: 15),
        onFieldSubmitted: (_) => _loading ? null : _login(),
        onChanged: (_) {
          if (_serverError != null) setState(() => _serverError = null);
        },
        decoration: InputDecoration(
          labelText: 'Contraseña',
          helperText: 'Ingresa tu contraseña institucional',
          prefixIcon: Icon(Icons.lock_outline_rounded, color: primary),
          suffixIcon: Semantics(
            label: _showPass ? 'Ocultar contraseña' : 'Mostrar contraseña',
            button: true,
            child: IconButton(
              icon: Icon(
                _showPass ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                color: Colors.grey.shade500,
              ),
              onPressed: () => setState(() => _showPass = !_showPass),
            ),
          ),
        ),
        validator: _validatePassword,
      ),
    );
  }

  Widget _buildError(String msg) {
    return Semantics(
      liveRegion: true,
      label: 'Error: $msg',
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Row(children: [
          Icon(Icons.error_outline_rounded, color: Colors.red.shade600, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(msg,
                style: GoogleFonts.poppins(color: Colors.red.shade700, fontSize: 13)),
          ),
        ]),
      ),
    );
  }

  Widget _buildGoogleButton() {
    return Semantics(
      label: 'Iniciar sesión con Google',
      button: true,
      child: SizedBox(
        height: 50,
        child: OutlinedButton(
          onPressed: _googleLoading ? null : _signInWithGoogle,
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: Colors.grey.shade300, width: 1.5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            backgroundColor: Colors.grey.shade50,
          ),
          child: _googleLoading
              ? SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: Colors.grey.shade600))
              : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  SizedBox(
                    width: 22, height: 22,
                    child: CustomPaint(painter: _GoogleLogoPainter()),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Continuar con Google',
                    style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700),
                  ),
                ]),
        ),
      ),
    );
  }
}

/// Dibuja el logo de Google (4 colores) con CustomPainter.
class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cy = h / 2;
    final r = w * 0.44;
    final stroke = w * 0.18;

    void arc(double start, double sweep, Color color) {
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: r),
        start, sweep, false,
        Paint()
          ..color = color
          ..strokeWidth = stroke
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.butt,
      );
    }

    arc(-1.6, 1.62, const Color(0xFFEA4335));
    arc(3.14, 1.60, const Color(0xFFFBBC05));
    arc(1.55, 1.60, const Color(0xFF34A853));
    arc(0.0, 1.57, const Color(0xFF4285F4));

    final armPaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(cx + r * 0.25, cy),
      Offset(cx + r + stroke * 0.5, cy),
      armPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}