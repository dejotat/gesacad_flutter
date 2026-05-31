import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'config/app_themes.dart';
import 'services/settings_service.dart';
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
          // Localización para reemplazar textos en inglés del framework
          localizationsDelegates: const [
            _SpanishMaterialLocalizations.delegate,
          ],
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
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _scale = Tween<double>(begin: 0.85, end: 1.0).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut));
    _ctrl.forward();
    _checkSession();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _checkSession() async {
    await Future.delayed(const Duration(milliseconds: 2200));
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
    Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => dest));
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
            child: FadeTransition(
              opacity: _fade,
              child: ScaleTransition(
                scale: _scale,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
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
                    const SizedBox(height: 28),
                    const Text(
                      'GESACAD',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 42,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 6,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Sistema de Gestión Académica',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Unicomfacauca · v1.1.2',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    const SizedBox(height: 48),
                    const SizedBox(
                      width: 34,
                      height: 34,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 3),
                    ),
                  ],
                ),
              ),
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
