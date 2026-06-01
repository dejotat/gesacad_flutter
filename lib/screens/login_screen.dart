import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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
                                  'Unicomfacauca · v 1.1.2',
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
                              '© 2026 GESACAD · Todos los derechos reservados',
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

  // ── Criterios de contraseña ────────────────────────────────────────────────

  bool _pwHasLength(String p) => p.length >= 8 && p.length <= 64;
  bool _pwHasNumber(String p) => p.contains(RegExp(r'\d'));
  bool _pwHasLetter(String p) => p.contains(RegExp(r'[a-zA-Z]'));
  bool _pwNoUser(String p) {
    final u = _userCtrl.text.trim().toLowerCase();
    return u.isEmpty || !p.toLowerCase().contains(u);
  }

  Widget _buildPasswordField(Color primary) {
    final pass = _passCtrl.text;
    final criteria = [
      _pwHasLength(pass),
      _pwHasNumber(pass),
      _pwHasLetter(pass),
      _pwNoUser(pass),
    ];
    final passed   = criteria.where((c) => c).length;
    final barColor = passed <= 1
        ? Colors.red
        : passed == 2
            ? Colors.orange
            : passed == 3
                ? Colors.yellow.shade700
                : Colors.green;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
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
            onChanged: (_) => setState(() => _serverError = null),
            decoration: InputDecoration(
              labelText: 'Contraseña',
              helperText: 'Ingresa tu contraseña institucional',
              prefixIcon: Icon(Icons.lock_outline_rounded, color: primary),
              suffixIcon: Semantics(
                label: _showPass ? 'Ocultar contraseña' : 'Mostrar contraseña',
                button: true,
                child: IconButton(
                  icon: Icon(
                    _showPass
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                    color: Colors.grey.shade500,
                  ),
                  onPressed: () => setState(() => _showPass = !_showPass),
                ),
              ),
            ),
            validator: _validatePassword,
          ),
        ),

        // Indicador de fortaleza — aparece al escribir
        if (pass.isNotEmpty) ...[
          const SizedBox(height: 10),
          // Barras de fortaleza
          Row(
            children: List.generate(4, (i) => Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                height: 4,
                decoration: BoxDecoration(
                  color: i < passed ? barColor : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            )),
          ),
          const SizedBox(height: 8),
          // Lista de criterios
          _pwCriterion(_pwHasLength(pass), '8-64 caracteres'),
          _pwCriterion(_pwHasNumber(pass), 'Al menos un número'),
          _pwCriterion(_pwHasLetter(pass), 'Al menos una letra'),
          _pwCriterion(_pwNoUser(pass),    'No incluir tu usuario'),
        ],
      ],
    );
  }

  Widget _pwCriterion(bool met, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Icon(
          met
              ? Icons.check_circle_rounded
              : Icons.radio_button_unchecked_rounded,
          size: 15,
          color: met ? Colors.green : Colors.grey.shade400,
        ),
        const SizedBox(width: 6),
        Text(
          text,
          style: GoogleFonts.poppins(
            fontSize: 11,
            color: met ? Colors.green.shade700 : Colors.grey.shade500,
          ),
        ),
      ]),
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

}