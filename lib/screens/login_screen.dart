import 'dart:ui' show ImageFilter;
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../config/api_config.dart';
import '../config/app_themes.dart';
import '../config/app_tokens.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import '../widgets/ui/cinematic_backdrop.dart';
import '../widgets/screen_reader_widgets.dart';
import '../widgets/ui/password_strength.dart';
import '../widgets/dev_server_badge.dart';
import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import '../services/connectivity_service.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../utils/route_transitions.dart';
import '../services/settings_service.dart';
import '../widgets/animated_logo.dart';
import 'admin/admin_home.dart';
import 'teacher/teacher_home.dart';
import 'student/student_home.dart';
import 'auth/forgot_password_screen.dart';
import 'guest/guest_home.dart';

/// Pantalla de inicio de sesión. Tiene identidad PROPIA y siempre oscura (fondo cinematográfico
/// verde azulado con aurora y partículas, los colores del tema Neón), sea cual sea el tema que el usuario eligió en Ajustes: es la puerta
/// de la marca y se ve igual para todos. Las pantallas que abre (recuperar contraseña, invitado)
/// siguen usando el tema de la app.
class LoginScreen extends StatelessWidget {
  /// Aviso inicial (p. ej. "Tu sesión expiró").
  final String? mensaje;
  const LoginScreen({super.key, this.mensaje});

  /// Tema oscuro del login (se construye una sola vez).
  static final ThemeData _tema = AppThemes.of(AppThemeType.neon);

  @override
  Widget build(BuildContext context) =>
      Theme(data: _tema, child: _LoginView(mensaje: mensaje));
}

class _LoginView extends StatefulWidget {
  final String? mensaje;
  const _LoginView({this.mensaje});

  @override
  State<_LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<_LoginView>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _showPass = false;
  bool _loading = false;
  late String? _serverError = widget.mensaje;

  final FocusNode _userFocus = FocusNode();
  final FocusNode _passFocus = FocusNode();

  late AnimationController _anim;
  late Animation<double> _fade;
  late Animation<Offset> _slide;
  late AnimationController _loginBtnCtrl;
  late Animation<double> _loginBtnScale;

  // Animación 2: logo cae desde arriba con rebote suave
  late AnimationController _logoCtrl;
  late Animation<Offset>   _logoSlide;
  late Animation<double>   _logoFade;

  @override
  void initState() {
    super.initState();

    // Logo: cae desde arriba con rebote. Arranca primero.
    _logoCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _logoSlide = Tween<Offset>(
            begin: const Offset(0, -1.6), end: Offset.zero)
        .animate(CurvedAnimation(parent: _logoCtrl, curve: Curves.easeOutBack));
    _logoFade = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _logoCtrl, curve: const Interval(0.0, 0.5, curve: Curves.easeIn)));
    _logoCtrl.forward();

    // Formulario: sube desde abajo 200ms después del logo
    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _fade = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _anim, curve: const Interval(0.0, 0.7, curve: Curves.easeIn)));
    _slide = Tween<Offset>(begin: const Offset(0, 0.4), end: Offset.zero)
        .animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));
    Future.delayed(const Duration(milliseconds: 200), () { if (mounted) _anim.forward(); });

    _loginBtnCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 120));
    _loginBtnScale = Tween<double>(begin: 1.0, end: 0.96)
        .animate(CurvedAnimation(parent: _loginBtnCtrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _anim.dispose();
    _logoCtrl.dispose();
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
    // Demasiados intentos fallidos: el servidor indica cuánto esperar.
    if (code == 'TOO_MANY_ATTEMPTS') {
      return res['message']?.toString() ??
          'Demasiados intentos. Espera unos minutos e inténtalo de nuevo.';
    }
    if (code == 'UPDATE_REQUIRED') {
      return 'Esta versión de la app ya no es compatible. Actualízala para continuar.';
    }
    // Un servidor antiguo que distingue «no existe» de «contraseña mala».
    if (code.contains('USER_NOT_FOUND')) return 'No encontramos una cuenta con ese usuario.';
    if (code.contains('INACTIVE') || code.contains('DISABLED')) {
      return 'Cuenta inactiva. Contacta al administrador del sistema.';
    }
    // El servidor actual responde igual para «usuario inexistente» y «contraseña incorrecta»
    // (USER_OR_PASS_INVALID) A PROPÓSITO: si dijera cuál de las dos falló, cualquiera podría
    // averiguar qué usuarios existen. Un solo mensaje claro, sin detalles internos.
    return 'Usuario o contraseña incorrectos.';
  }

  /// Detalle técnico SOLO para la consola de depuración (nunca se muestra al usuario): la causa
  /// más común de «no entra» es usar usuarios de producción contra un servidor local (o al revés).
  void _registrarFallo(String motivo) {
    developer.log('Login fallido ($motivo) · servidor: ${ApiConfig.baseUrl}',
        name: 'GESACAD.Auth');
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
        final userId = res['id'] as int;
        await AuthService().saveSession(
          userId,
          res['name'] as String? ?? _userCtrl.text.trim(),
          res['rol'] as String,
          token: res['token'] as String?,
        );
        // Precarga foto y perfil en caché sin bloquear el login.
        // El home la mostrará en cuanto llegue (~1-2s después de navegar).
        unawaited(AuthService().fetchAndCachePhoto(userId));
        final rol = res['rol'] as String;
        final Widget home = rol == 'Admin'
            ? const AdminHome()
            : rol == 'Teacher'
                ? const TeacherHome()
                : const StudentHome();
        if (!mounted) return;
        Navigator.pushReplacement(context, slideRoute(home));
      } else {
        _registrarFallo('respuesta ${res['response']}');
        setState(() => _serverError = _mapLoginError(res));
      }
    } on TimeoutException {
      _registrarFallo('tiempo agotado');
      if (mounted) {
        setState(() => _serverError = 'El servidor tardó demasiado. Verifica tu conexión a internet.');
      }
    } catch (e) {
      _registrarFallo('error de red: ${e.runtimeType}');
      if (mounted) {
        setState(() => _serverError = isNetworkError(e)
            ? 'Sin conexión. Para iniciar sesión necesitas internet.'
            : 'No se pudo conectar al servidor. Verifica tu conexión a internet.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // El login usa SIEMPRE el tema oscuro de marca (ver [LoginScreen]).
    const themeType = AppThemeType.neon;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Íconos claros en la barra de estado sobre el fondo negro.
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFF05221F),
        body: CinematicBackdrop(
        child: Stack(children: [
         SafeArea(
          // LayoutBuilder detecta el tamaño real de pantalla para ser responsive
          child: LayoutBuilder(
            builder: (ctx, constraints) {
              // Definir breakpoints responsive
              final ancho      = constraints.maxWidth;
              final esMobil    = ancho < 420;
              final esTablet   = ancho < 650;
              // En pantallas bajas (portátil con el navegador) el logo se achica para que el
              // formulario quede a la vista sin tener que desplazarse.
              final bajo       = constraints.maxHeight < 760;
              final logoTam    = bajo
                  ? (esMobil ? 76.0 : 96.0)
                  : esMobil ? 90.0 : esTablet ? 118.0 : 148.0;
              final padH       = esMobil ? 16.0 : esTablet ? 22.0 : 28.0;
              final padCard    = esMobil ? 20.0 : 28.0;

              return Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(horizontal: padH, vertical: 20),
                  child: ConstrainedBox(
                    // Máximo 480px en pantallas grandes (web desktop)
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Column(
                          children: [
                            // ── Logo: cae desde arriba (animación independiente) ──
                            SlideTransition(
                              position: _logoSlide,
                              child: FadeTransition(
                                opacity: _logoFade,
                                child: Semantics(
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
                                            color: const Color(0xFF22D3EE).withValues(alpha: 0.45),
                                            blurRadius: 28,
                                          ),
                                          Shadow(
                                            color: Colors.black.withValues(alpha: 0.6),
                                            blurRadius: 10,
                                            offset: const Offset(0, 3),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      'Campus Virtual',
                                      style: GoogleFonts.poppins(
                                          color: Colors.white.withValues(alpha: 0.88),
                                          fontSize: esMobil ? 11.5 : 13.5,
                                          fontWeight: FontWeight.w500,
                                          letterSpacing: 3),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Unicomfacauca · v 1.1.2',
                                      style: GoogleFonts.poppins(
                                          color: Colors.white.withValues(alpha: 0.6),
                                          fontSize: esMobil ? 10 : 11.5),
                                    ),
                                  ]),
                                ),
                              ),
                            ),
                            SizedBox(height: esMobil ? 18 : 28),

                            // ── Formulario: sube desde abajo (animación independiente) ──
                            SlideTransition(
                              position: _slide,
                              child: FadeTransition(
                                opacity: _fade,
                                child: _glassPanel(
                              themeType,
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
                                            color: Colors.white),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Ingresa tus credenciales institucionales',
                                        style: GoogleFonts.poppins(
                                            color: Colors.white.withValues(alpha: 0.7),
                                            fontSize: 12.5),
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
                                              icon: PhosphorIconsRegular.user,
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

                                      // Solo en depuración: a qué servidor está conectada la app.
                                      if (kDebugMode) const DevServerBadge(),

                                      // Enlace ¿Olvidaste tu contraseña?
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: TextButton(
                                          onPressed: () => Navigator.push(
                                              context,
                                              slideRoute(const ForgotPasswordScreen())),
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
                                                            const Icon(PhosphorIconsRegular.signIn,
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

                                      // ── Modo invitado: explorar sin cuenta ──
                                      const SizedBox(height: 14),
                                      Row(children: [
                                        Expanded(child: Divider(color: themeType.isDark ? Colors.white24 : Colors.black26)),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 12),
                                          child: Text('o',
                                              style: GoogleFonts.poppins(
                                                  fontSize: 12,
                                                  color: themeType.isDark ? Colors.white60 : Colors.black54)),
                                        ),
                                        Expanded(child: Divider(color: themeType.isDark ? Colors.white24 : Colors.black26)),
                                      ]),
                                      const SizedBox(height: 14),
                                      Semantics(
                                        button: true,
                                        label: 'Explorar como invitado, sin iniciar sesión',
                                        child: SizedBox(
                                          height: 48,
                                          child: OutlinedButton.icon(
                                            onPressed: _loading
                                                ? null
                                                : () => Navigator.push(context, slideRoute(const GuestHome())),
                                            icon: Icon(PhosphorIconsFill.compass, size: 20, color: themeType.primaryColor),
                                            label: Text('Explorar como invitado',
                                                style: GoogleFonts.poppins(
                                                    color: themeType.primaryColor,
                                                    fontSize: 14.5,
                                                    fontWeight: FontWeight.w700)),
                                            style: OutlinedButton.styleFrom(
                                              side: BorderSide(color: themeType.primaryColor.withValues(alpha: 0.6), width: 1.4),
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),      // cierra panel de vidrio
                              ),    // cierra FadeTransition del formulario
                            ),      // cierra SlideTransition del formulario
                            const SizedBox(height: 22),

                            // ── Pie de página ──────────────────────────────
                            Text(
                              'Colegio Santander',
                              style: GoogleFonts.poppins(
                                  color: Colors.white.withValues(alpha: 0.62),
                                  fontSize: esMobil ? 10 : 11.5),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '© 2026 GESACAD · Todos los derechos reservados',
                              style: GoogleFonts.poppins(
                                  color: Colors.white.withValues(alpha: 0.5),
                                  fontSize: esMobil ? 9 : 10.5),
                              textAlign: TextAlign.center,
                            ),
                          ],        // cierra children del Column principal
                        ),          // cierra Column (hijo de ConstrainedBox)
                      ),            // cierra ConstrainedBox
                    ),              // cierra SingleChildScrollView
                  );                // cierra Center + return
                },                  // cierra LayoutBuilder builder
              ),                    // cierra LayoutBuilder
            ),                      // cierra SafeArea
          // Accesibilidad: activar el lector de voz sin iniciar sesión.
          const Positioned(
            top: 0, right: 0,
            child: SafeArea(child: Padding(padding: EdgeInsets.all(8), child: BotonLectorVoz(color: Colors.white))),
          ),
          ]),                       // cierra Stack
          ),                        // cierra CinematicBackdrop
      ),                            // cierra Scaffold
    );                              // cierra AnnotatedRegion
  }


  /// Panel de vidrio oscuro del formulario: translúcido, con desenfoque del fondo animado, borde
  /// fino luminoso y un resplandor de marca debajo. Mantiene el contraste del texto claro.
  Widget _glassPanel(AppThemeType themeType, {required Widget child}) {
    final r = BorderRadius.circular(28);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: [
          // Resplandor de marca (se funde con la aurora)
          BoxShadow(
            color: themeType.gradient[1].withValues(alpha: 0.22),
            blurRadius: 70,
            spreadRadius: -10,
            offset: const Offset(0, 24),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 44,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: r,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: r,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xCC0C2B28), Color(0xB8082421)],
              ),
              border: Border.all(color: Colors.white.withValues(alpha: 0.11)),
            ),
            child: Stack(
              children: [
                child,
                // Filo de luz en el borde superior
                Positioned(
                  top: 0,
                  left: 36,
                  right: 36,
                  height: 1,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [
                          Colors.white.withValues(alpha: 0),
                          Colors.white.withValues(alpha: 0.55),
                          Colors.white.withValues(alpha: 0),
                        ]),
                      ),
                    ),
                  ),
                ),
              ],
            ),
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
    final pass = _passCtrl.text;

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
              prefixIcon: Icon(PhosphorIconsRegular.lock, color: primary),
              suffixIcon: Semantics(
                label: _showPass ? 'Ocultar contraseña' : 'Mostrar contraseña',
                button: true,
                child: IconButton(
                  icon: Icon(
                    _showPass
                        ? PhosphorIconsRegular.eyeSlash
                        : PhosphorIconsRegular.eye,
                    color: context.tokens.muted,
                  ),
                  onPressed: () => setState(() => _showPass = !_showPass),
                ),
              ),
            ),
            validator: _validatePassword,
          ),
        ),

        // Barra de seguridad: cambia de color según el nivel; sin lista de requisitos.
        if (pass.isNotEmpty) ...[
          const SizedBox(height: 10),
          PasswordStrengthBar(password: pass, username: _userCtrl.text),
        ],
      ],
    );
  }

  Widget _buildError(String msg) {
    return Semantics(
      liveRegion: true,
      label: 'Error: $msg',
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.tokens.danger.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: context.tokens.danger.withValues(alpha: 0.35)),
        ),
        child: Row(children: [
          Icon(PhosphorIconsRegular.warningCircle,
              color: context.tokens.danger, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(msg,
                style: GoogleFonts.poppins(
                    color: context.tokens.danger, fontSize: 13)),
          ),
        ]),
      ),
    );
  }

}