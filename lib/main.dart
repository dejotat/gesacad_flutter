import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'config/app_themes.dart';
import 'services/settings_service.dart';
import 'services/api_service.dart';
import 'utils/route_transitions.dart';
import 'screens/login_screen.dart';
import 'screens/admin/admin_home.dart';
import 'screens/teacher/teacher_home.dart';
import 'screens/student/student_home.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Inicializar locale español para table_calendar y formatos de fecha
  await initializeDateFormatting('es', null);
  await AppSettings.load();

  runApp(const GesacadApp());
}

/// Aplicación raíz de GESACAD con soporte de temas dinámicos.
class GesacadApp extends StatelessWidget {
  const GesacadApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppThemeType>(
      valueListenable: AppSettings.currentTheme,
      builder: (_, themeType, __) {
        final isDark = themeType == AppThemeType.darkCarbon;
        return MaterialApp(
          title: 'GESACAD',
          debugShowCheckedModeBanner: false,
          theme: AppThemes.of(themeType),
          themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
          home: const SplashScreen(),
          // Localización completa en español (menús Cut/Copy/Paste, fechas, etc.)
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            _SpanishMaterialLocalizations.delegate,
          ],
          supportedLocales: const [Locale('es', 'CO'), Locale('es'), Locale('en')],
          locale: const Locale('es', 'CO'),
        );
      },
    );
  }
}

/// Pantalla de carga inicial.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // Controller del logo: escala 0.3→1.0 con rebote + fade in
  late AnimationController _logoCtrl;
  late Animation<double>   _logoScale;
  late Animation<double>   _logoFade;

  // Controller del texto inferior: desliza desde abajo + fade in
  late AnimationController _textCtrl;
  late Animation<Offset>   _textSlide;
  late Animation<double>   _textFade;

  @override
  void initState() {
    super.initState();

    // Logo: aparece en 900ms con rebote elástico
    _logoCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _logoScale = Tween<double>(begin: 0.2, end: 1.0).animate(
        CurvedAnimation(parent: _logoCtrl, curve: Curves.easeOutBack));
    _logoFade = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _logoCtrl, curve: const Interval(0.0, 0.6, curve: Curves.easeIn)));

    // Texto "Campus Virtual": desliza 80px desde abajo usando FractionalOffset
    _textCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _textSlide = Tween<Offset>(
            begin: const Offset(0, 4.0), end: Offset.zero)
        .animate(CurvedAnimation(parent: _textCtrl, curve: Curves.easeOutCubic));
    _textFade = CurvedAnimation(parent: _textCtrl, curve: Curves.easeIn);

    // Logo arranca inmediatamente; texto arranca a los 600ms
    _logoCtrl.forward();
    Future.delayed(const Duration(milliseconds: 600),
        () { if (mounted) _textCtrl.forward(); });

    unawaited(ApiService().ping());
    _checkSession();
  }

  @override
  void dispose() {
    _logoCtrl.dispose();
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkSession() async {
    await Future.delayed(const Duration(milliseconds: 2500));
    final prefs = await SharedPreferences.getInstance();
    final rol = prefs.getString('userRol');
    if (!mounted) return;

    Widget dest;
    if (rol == null) {
      dest = const LoginScreen();
    } else if (rol == 'Admin') {
      dest = const AdminHome();
    } else if (rol == 'Teacher') {
      dest = const TeacherHome();
    } else {
      dest = const StudentHome();
    }
    Navigator.pushReplacement(context, slideRoute(dest));
  }

  @override
  Widget build(BuildContext context) {
    final themeType = AppSettings.currentTheme.value;
    return Scaffold(
      body: Semantics(
        label: 'Pantalla de carga de GESACAD, por favor espere',
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: themeType.gradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ── Logo: escala desde pequeño + fade in con rebote ──────────
                ScaleTransition(
                  scale: _logoScale,
                  child: FadeTransition(
                    opacity: _logoFade,
                    child: Container(
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.12),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: Colors.white.withOpacity(0.3), width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 30,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.school_rounded,
                          size: 80, color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                // ── Nombre GESACAD: fade in junto con el logo ────────────────
                FadeTransition(
                  opacity: _logoFade,
                  child: const Text(
                    'GESACAD',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 42,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 6,
                    ),
                  ),
                ),
                const SizedBox(height: 6),

                // ── Subtítulos: deslizan desde abajo 600ms después ───────────
                SlideTransition(
                  position: _textSlide,
                  child: FadeTransition(
                    opacity: _textFade,
                    child: Column(children: [
                      const Text(
                        'Campus Virtual',
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Unicomfacauca · v 1.1.2',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ]),
                  ),
                ),

                const SizedBox(height: 48),
                FadeTransition(
                  opacity: _logoFade,
                  child: const SizedBox(
                    width: 34,
                    height: 34,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 3),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Localización mínima para traducir el tooltip "Open navigation menu" al español.
class _SpanishMaterialLocalizations
    extends DefaultMaterialLocalizations {
  const _SpanishMaterialLocalizations();

  static const LocalizationsDelegate<MaterialLocalizations> delegate =
      _Delegate();

  @override
  String get openAppDrawerTooltip => 'Abrir menú de navegación';

  @override
  String get backButtonTooltip => 'Regresar';

  @override
  String get closeButtonTooltip => 'Cerrar';

  @override
  String get deleteButtonTooltip => 'Eliminar';

  @override
  String get moreButtonTooltip => 'Más opciones';

  @override
  String get searchFieldLabel => 'Buscar';

  @override
  String get selectAllButtonLabel => 'Seleccionar todo';
}

class _Delegate extends LocalizationsDelegate<MaterialLocalizations> {
  const _Delegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<MaterialLocalizations> load(Locale locale) async =>
      const _SpanishMaterialLocalizations();

  @override
  bool shouldReload(covariant LocalizationsDelegate<MaterialLocalizations> old) =>
      false;
}
