import 'dart:convert';
import 'dart:math' as math;   // Necesario para _BubblePainter (sin animaciones del gráfico)
import 'dart:typed_data';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../services/settings_service.dart';
import '../../widgets/tts_button.dart';
import '../../widgets/chatbot_widget.dart';
import '../login_screen.dart';
import '../settings_screen.dart';
import '../notifications/notifications_panel.dart';
import '../profile/profile_screen.dart';
import '../calendar/calendar_screen.dart';
import 'admin_users.dart';
import 'admin_courses.dart';

/// Panel principal del Administrador con estadísticas y gráficos premium.
class AdminHome extends StatefulWidget {
  const AdminHome({super.key});
  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> with TickerProviderStateMixin {
  // ── Datos del usuario ─────────────────────────────────────────────────────
  String    _name      = 'Admin';
  int       _myId      = 0;
  Uint8List? _photoBytes;

  // ── Estadísticas ──────────────────────────────────────────────────────────
  int _totalStudents = 0;
  int _totalTeachers = 0;
  int _totalAdmins   = 0;

  /// Registros por curso: [{name: String, countUsers: int}]
  List<Map<String, dynamic>> _courseRecords = [];

  // ── Estados UI ────────────────────────────────────────────────────────────
  bool _loading         = true;
  // Índice de la sección de la dona actualmente expandida (explode al tocar)
  int? _touchedPieIndex;

  // ── Animaciones ───────────────────────────────────────────────────────────
  late AnimationController _entryCtrl;
  late Animation<double>   _entryFade;
  late Animation<Offset>   _entrySlide;
  late AnimationController _cardAnim;   // Burbujas decorativas continuas
  late AnimationController _chartAnim; // Gráficos entran animados

  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _entryFade  = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut);
    _entrySlide = Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero)
        .animate(CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut));

    _cardAnim = AnimationController(
        vsync: this, duration: const Duration(seconds: 6))..repeat();

    _chartAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200));

    _loadData();
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    _cardAnim.dispose();
    _chartAnim.dispose();
    super.dispose();
  }

  Future<void> _reloadPhoto() async {
    final prefs   = await SharedPreferences.getInstance();
    final photoB64 = prefs.getString('profile_photo') ?? '';
    if (photoB64.isNotEmpty && mounted) {
      try { setState(() => _photoBytes = base64Decode(photoB64)); } catch (_) {}
    }
  }

  // ── Carga de datos ────────────────────────────────────────────────────────

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final prefs = await SharedPreferences.getInstance();
    _name  = prefs.getString('userName') ?? 'Admin';
    _myId  = prefs.getInt('userId') ?? 0;

    final photoB64 = prefs.getString('profile_photo');
    if (photoB64 != null && photoB64.isNotEmpty) {
      try { _photoBytes = base64Decode(photoB64); } catch (_) {}
    }

    try {
      // Llamadas en paralelo — reduce tiempo de carga a la más lenta (no la suma)
      final results = await Future.wait([
        ApiService().getQuantityUsers(),
        ApiService().getQuantityRecords(),
      ]);
      if (!mounted) return;

      final qty     = results[0];
      final records = results[1];

      _totalStudents = 0; _totalTeachers = 0; _totalAdmins = 0;
      for (final u in (qty['numberOfUsers'] as List)) {
        final rol   = u['rol'];
        final count = (u['COUNT(*)'] as num?)?.toInt() ?? 0;
        if (rol == 'Student') _totalStudents = count;
        if (rol == 'Teacher') _totalTeachers = count;
        if (rol == 'Admin')   _totalAdmins   = count;
      }
      _courseRecords = List<Map<String, dynamic>>.from(
          records['numberOfRecords'] ?? []);
    } catch (_) {}

    if (mounted) {
      setState(() => _loading = false);
      _entryCtrl.forward(from: 0);
      _chartAnim.forward(from: 0);
      // Si fetchAndCachePhoto aún no terminó al llegar aquí, re-intentar en 2s
      Future.delayed(const Duration(seconds: 2), _reloadPhoto);
    }
  }

  Future<void> _logout() async {
    await AuthService().clearSession();
    if (!mounted) return;
    Navigator.pushReplacement(context,
        MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  String get _ttsText =>
      'Panel Administrador. Bienvenido $_name. '
      'Hay $_totalStudents estudiantes, $_totalTeachers profesores y '
      '$_totalAdmins administradores.';

  // ── BUILD ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final primary   = Theme.of(context).colorScheme.primary;
    final themeType = AppSettings.currentTheme.value;

    return Scaffold(
      appBar: _buildAppBar(primary, themeType),
      drawer: _buildDrawer(primary, themeType),
      backgroundColor: const Color(0xFFF0F4FF),
      body: _loading
          ? _buildShimmer()
          : FadeTransition(
              opacity: _entryFade,
              child: SlideTransition(
                position: _entrySlide,
                child: RefreshIndicator(
                  color: primary,
                  onRefresh: _loadData,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(20),
                    child: LayoutBuilder(builder: (ctx, constraints) {
                      final wide = constraints.maxWidth > 700;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildWelcomeCard(primary, themeType),
                          const SizedBox(height: 24),
                          _secTitle('Estadísticas', Icons.bar_chart_rounded, primary),
                          const SizedBox(height: 14),
                          wide ? _statsWide(primary) : _statsNarrow(primary),
                          const SizedBox(height: 28),
                          _secTitle('Acciones Rápidas', Icons.flash_on_rounded, primary),
                          const SizedBox(height: 14),
                          _buildQuickActions(primary),
                          if (_totalStudents + _totalTeachers + _totalAdmins > 0) ...[
                            const SizedBox(height: 28),
                            _secTitle('Distribución de Usuarios',
                                Icons.donut_large_rounded, primary),
                            const SizedBox(height: 14),
                            _buildPieChart(primary),
                          ],
                          if (_courseRecords.isNotEmpty) ...[
                            const SizedBox(height: 28),
                            _secTitle('Estudiantes por Curso',
                                Icons.analytics_rounded, primary),
                            const SizedBox(height: 14),
                            _buildBarChart(primary),
                          ],
                          const SizedBox(height: 100),
                        ],
                      );
                    }),
                  ),
                ),
              ),
            ),
      floatingActionButton: _loading
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ChatbotWidget(),
                const SizedBox(height: 8),
                TtsButton(text: _ttsText),
              ],
            ),
    );
  }

  // ── APP BAR ───────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar(Color primary, AppThemeType themeType) {
    return AppBar(
      elevation: 0,
      backgroundColor: Colors.transparent,
      flexibleSpace: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: themeType.gradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      ),
      leading: Builder(builder: (ctx) => IconButton(
        icon: const Icon(Icons.menu_rounded, color: Colors.white),
        onPressed: () => Scaffold.of(ctx).openDrawer(),
      )),
      title: Text('Panel Administrador',
          style: GoogleFonts.poppins(
              color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18)),
      centerTitle: true,
      actions: [
        NotificationBell(userId: _myId, userRol: 'Admin'),
        IconButton(
          tooltip: 'Calendario',
          icon: const Icon(Icons.calendar_month_rounded, color: Colors.white),
          onPressed: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const CalendarScreen())),
        ),
        IconButton(
          tooltip: 'Mi Perfil',
          icon: _photoBytes != null
              ? CircleAvatar(backgroundImage: MemoryImage(_photoBytes!), radius: 14)
              : const Icon(Icons.account_circle_rounded, color: Colors.white),
          onPressed: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const ProfileScreen()))
              .then((_) => _reloadPhoto()),
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
          onSelected: (v) {
            if (v == 'settings') Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()));
            if (v == 'logout') _logout();
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'settings',
                child: Row(children: [
                  Icon(Icons.settings_rounded, size: 18),
                  SizedBox(width: 8), Text('Ajustes'),
                ])),
            PopupMenuItem(value: 'logout',
                child: Row(children: [
                  Icon(Icons.logout_rounded, size: 18, color: Colors.red.shade600),
                  const SizedBox(width: 8),
                  Text('Cerrar sesión',
                      style: TextStyle(color: Colors.red.shade600)),
                ])),
          ],
        ),
      ],
    );
  }

  // ── DRAWER ────────────────────────────────────────────────────────────────

  Widget _buildDrawer(Color primary, AppThemeType themeType) {
    return Drawer(
      child: Column(children: [
        AnimatedBuilder(
          animation: _cardAnim,
          builder: (_, __) => Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 52, 20, 28),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: themeType.gradient,
                  begin: Alignment.topLeft, end: Alignment.bottomRight),
            ),
            child: Stack(children: [
              Positioned.fill(
                  child: CustomPaint(painter: _BubblePainter(_cardAnim.value))),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 64, height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withOpacity(0.5), width: 2.5),
                    color: Colors.white.withOpacity(0.15),
                  ),
                  child: ClipOval(child: _photoBytes != null
                      ? Image.memory(_photoBytes!, fit: BoxFit.cover)
                      : const Icon(Icons.admin_panel_settings_rounded,
                          color: Colors.white, size: 34)),
                ),
                const SizedBox(height: 14),
                Text(_name, style: GoogleFonts.poppins(
                    color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('🛡️ Administrador del sistema',
                      style: GoogleFonts.poppins(color: Colors.white70, fontSize: 11)),
                ),
              ]),
            ]),
          ),
        ),
        _drawerItem(Icons.dashboard_rounded, 'Panel Principal', primary,
            () => Navigator.pop(context)),
        _drawerItem(Icons.manage_accounts_rounded, 'Gestionar Usuarios', primary, () {
          Navigator.pop(context);
          Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminUsers()))
              .then((_) { if (mounted) _loadData(); });
        }),
        _drawerItem(Icons.menu_book_rounded, 'Gestionar Cursos', primary, () {
          Navigator.pop(context);
          Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminCourses()))
              .then((_) { if (mounted) _loadData(); });
        }),
        _drawerItem(Icons.settings_rounded, 'Ajustes y Acerca de', primary, () {
          Navigator.pop(context);
          Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
        }),
        const Divider(height: 1),
        _drawerItem(Icons.logout_rounded, 'Cerrar Sesión', Colors.red, _logout),
      ]),
    );
  }

  Widget _drawerItem(IconData icon, String label, Color color, VoidCallback onTap) =>
      ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(label, style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        onTap: onTap,
      );

  // ── HELPERS ───────────────────────────────────────────────────────────────

  Widget _secTitle(String title, IconData icon, Color primary) => Row(children: [
    Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: primary.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
      child: Icon(icon, color: primary, size: 20),
    ),
    const SizedBox(width: 10),
    Text(title, style: GoogleFonts.poppins(
        fontSize: 17, fontWeight: FontWeight.w700, color: primary)),
  ]);

  // ── TARJETA DE BIENVENIDA ─────────────────────────────────────────────────

  Widget _buildWelcomeCard(Color primary, AppThemeType themeType) {
    return AnimatedBuilder(
      animation: _cardAnim,
      builder: (_, __) => Container(
        height: 140,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: themeType.gradient,
              begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(28),
          boxShadow: [BoxShadow(color: primary.withOpacity(0.45),
              blurRadius: 28, offset: const Offset(0, 10))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Stack(children: [
            Positioned.fill(child: CustomPaint(painter: _BubblePainter(_cardAnim.value))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
              child: Row(children: [
                Container(
                  width: 72, height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withOpacity(0.5), width: 2.5),
                    color: Colors.white.withOpacity(0.15),
                  ),
                  child: ClipOval(child: _photoBytes != null
                      ? Image.memory(_photoBytes!, fit: BoxFit.cover)
                      : const Icon(Icons.admin_panel_settings_rounded,
                          color: Colors.white, size: 36)),
                ),
                const SizedBox(width: 20),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('👋 Bienvenido,', style: GoogleFonts.poppins(
                        color: Colors.white70, fontSize: 13)),
                    Text(_name, style: GoogleFonts.poppins(
                        color: Colors.white, fontSize: 24,
                        fontWeight: FontWeight.w800, height: 1.1)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('🛡️ Administrador del sistema',
                          style: GoogleFonts.poppins(
                              color: Colors.white, fontSize: 11,
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                )),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  // ── ESTADÍSTICAS ──────────────────────────────────────────────────────────

  Widget _statsWide(Color primary) => Row(children: [
    _statCard('Estudiantes', _totalStudents, '🎓',
        const Color(0xFF1565C0), const Color(0xFFBBDEFB)),
    const SizedBox(width: 12),
    _statCard('Profesores', _totalTeachers, '📚',
        const Color(0xFF2E7D32), const Color(0xFFC8E6C9)),
    const SizedBox(width: 12),
    _statCard('Admins', _totalAdmins, '🛡️',
        const Color(0xFF6A1B9A), const Color(0xFFE1BEE7)),
  ]);

  Widget _statsNarrow(Color primary) => Column(children: [
    Row(children: [
      _statCard('Estudiantes', _totalStudents, '🎓',
          const Color(0xFF1565C0), const Color(0xFFBBDEFB)),
      const SizedBox(width: 12),
      _statCard('Profesores', _totalTeachers, '📚',
          const Color(0xFF2E7D32), const Color(0xFFC8E6C9)),
    ]),
    const SizedBox(height: 12),
    _statCard('Admins', _totalAdmins, '🛡️',
        const Color(0xFF6A1B9A), const Color(0xFFE1BEE7)),
  ]);

  Widget _statCard(String label, int value, String emoji,
      Color color, Color bgColor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.15), width: 1.5),
          boxShadow: [
            BoxShadow(color: color.withOpacity(0.15),
                blurRadius: 16, offset: const Offset(0, 6)),
          ],
        ),
        child: Column(children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
            child: Text(emoji, style: const TextStyle(fontSize: 24)),
          ),
          const SizedBox(height: 10),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: value.toDouble()),
            duration: const Duration(milliseconds: 1200),
            curve: Curves.easeOut,
            builder: (_, v, __) => Text('${v.toInt()}',
                style: GoogleFonts.poppins(
                    fontSize: 32, fontWeight: FontWeight.w900, color: color)),
          ),
          Text(label, style: GoogleFonts.poppins(
              fontSize: 12, color: Colors.grey.shade500,
              fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  // ── ACCIONES RÁPIDAS ──────────────────────────────────────────────────────

  Widget _buildQuickActions(Color primary) => Row(children: [
    Expanded(child: _actionCard('👥', 'Gestionar\nUsuarios',
        'Crear, editar y eliminar',
        const Color(0xFF283593), const Color(0xFF3949AB), () =>
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => const AdminUsers()))
            .then((_) { if (mounted) _loadData(); }))),
    const SizedBox(width: 14),
    Expanded(child: _actionCard('📚', 'Gestionar\nCursos',
        'Administrar catálogo',
        const Color(0xFF004D40), const Color(0xFF00796B), () =>
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => const AdminCourses()))
            .then((_) { if (mounted) _loadData(); }))),
  ]);

  Widget _actionCard(String emoji, String label, String sub,
      Color c1, Color c2, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [c1, c2],
                begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(22),
            boxShadow: [BoxShadow(color: c1.withOpacity(0.5),
                blurRadius: 22, offset: const Offset(0, 8))],
          ),
          child: Column(children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.18),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withOpacity(0.3)),
              ),
              child: Text(emoji, style: const TextStyle(fontSize: 30)),
            ),
            const SizedBox(height: 14),
            Text(label, textAlign: TextAlign.center,
                style: GoogleFonts.poppins(color: Colors.white,
                    fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 5),
            Text(sub, textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                    color: Colors.white.withOpacity(0.75), fontSize: 11)),
          ]),
        ),
      ),
    );
  }

  // ── GRÁFICO DE DONA — Syncfusion DoughnutSeries ──────────────────────────

  Widget _buildPieChart(Color primary) {
    final total = _totalStudents + _totalTeachers + _totalAdmins;
    if (total == 0) return const SizedBox();

    // Modelo de datos para la serie de la dona
    final datos = [
      _PieData('🎓 Estudiantes', _totalStudents, const Color(0xFF1E88E5)),
      _PieData('📚 Profesores',  _totalTeachers, const Color(0xFF43A047)),
      _PieData('🛡️ Admins',      _totalAdmins,   const Color(0xFF8E24AA)),
    ];

    // ── Dona con Syncfusion ───────────────────────────────────────────────────
    // Mismo shell (Card blanca con sombra) — solo se reemplaza la gráfica interior.
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.07),
              blurRadius: 20, offset: const Offset(0, 6)),
        ],
      ),
      child: Column(children: [
        // Cabecera: icono + título + badge total
        Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFF1E88E5), Color(0xFF42A5F5)]),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.donut_large_rounded,
                color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          Text('Distribución de roles',
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700, fontSize: 15)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text('$total usuarios',
                style: GoogleFonts.poppins(
                    fontSize: 11, color: primary,
                    fontWeight: FontWeight.w600)),
          ),
        ]),
        const SizedBox(height: 16),

        // ── Dona con fl_chart ─────────────────────────────────────────────────
        // Stack: dona + anotación central superpuesta
        SizedBox(
          height: 240,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Gráfica de dona con animación de entrada (swapAnimation)
              PieChart(
                PieChartData(
                  // Al tocar una sección se expande hacia afuera
                  pieTouchData: PieTouchData(
                    touchCallback: (FlTouchEvent event, PieTouchResponse? res) {
                      // Bug 2: responder a tap simple Y long press en móvil
                      if (event is! FlTapUpEvent &&
                          event is! FlTapDownEvent &&
                          !event.isInterestedForInteractions) {
                        return;
                      }
                      setState(() {
                        if (res?.touchedSection == null) {
                          _touchedPieIndex = null;
                          return;
                        }
                        final idx = res!.touchedSection!.touchedSectionIndex;
                        // Toggle: tocar la misma sección la deselecciona
                        _touchedPieIndex =
                            _touchedPieIndex == idx ? null : idx;
                      });
                    },
                  ),
                  centerSpaceRadius: 58,
                  sectionsSpace: 4, // Bug 1: solo sectionsSpace, sin borderSide
                  sections: datos.asMap().entries.map((e) {
                    final i      = e.key;
                    final d      = e.value;
                    final tocada = _touchedPieIndex == i;
                    final pct    = total > 0
                        ? (d.value / total * 100).toStringAsFixed(0)
                        : '0';
                    return PieChartSectionData(
                      value:       d.value.toDouble(),
                      color:       d.color,
                      // Sección tocada: radio mayor para efecto "explode"
                      radius:     tocada ? 72 : 60,
                      title:      tocada ? '$pct%' : '',
                      titleStyle: GoogleFonts.poppins(
                          fontSize: 13, fontWeight: FontWeight.w700,
                          color: Colors.white),
                      // Bug 1: sin borderSide — sectionsSpace:4 es suficiente
                      // para separar secciones sin artefactos pixelados
                    );
                  }).toList(),
                ),
                // Animación de aparición al cargar (1500 ms, suave)
                swapAnimationDuration: const Duration(milliseconds: 1500),
                swapAnimationCurve:    Curves.easeInOut,
              ),

              // Anotación central: total de usuarios en el hueco de la dona
              Column(mainAxisSize: MainAxisSize.min, children: [
                Text('$total',
                    style: GoogleFonts.poppins(
                        fontSize: 26, fontWeight: FontWeight.w900,
                        color: const Color(0xFF1A1A2E))),
                Text('usuarios',
                    style: GoogleFonts.poppins(
                        fontSize: 11, color: Colors.grey.shade400)),
              ]),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Leyenda manual debajo de la dona
        // Muestra: punto de color + etiqueta + cantidad + porcentaje
        Wrap(
          spacing: 16,
          runSpacing: 10,
          alignment: WrapAlignment.center,
          children: datos.asMap().entries.map((e) {
            final i   = e.key;
            final d   = e.value;
            final pct = total > 0
                ? (d.value / total * 100).toStringAsFixed(0)
                : '0';
            final sel = _touchedPieIndex == i;
            return GestureDetector(
              onTap: () => setState(
                  () => _touchedPieIndex = sel ? null : i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color:        sel
                      ? d.color.withOpacity(0.10)
                      : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border:       Border.all(
                      color: sel ? d.color : Colors.grey.shade200,
                      width: sel ? 2 : 1),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  // Punto de color
                  Container(
                    width: 10, height: 10,
                    decoration: BoxDecoration(
                        color: d.color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Text('${d.label}  ',
                      style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700)),
                  Text('${d.value}',
                      style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: d.color)),
                  Text('  ($pct%)',
                      style: GoogleFonts.poppins(
                          fontSize: 10,
                          color: Colors.grey.shade500)),
                ]),
              ),
            );
          }).toList(),
        ),
      ]),
    );
  }

  // ── GRÁFICO DE BARRAS — fl_chart BarChart ────────────────────────────────

  Widget _buildBarChart(Color primary) {
    if (_courseRecords.isEmpty) return const SizedBox();

    // Paletas de gradiente: [oscuro, claro] — un par por barra
    const paletasGradiente = [
      [Color(0xFF1565C0), Color(0xFF90CAF9)], // azul
      [Color(0xFF2E7D32), Color(0xFF81C784)], // verde
      [Color(0xFF6A1B9A), Color(0xFFCE93D8)], // morado
      [Color(0xFFBF360C), Color(0xFFFF8A65)], // naranja
      [Color(0xFF00695C), Color(0xFF80CBC4)], // teal
    ];

    // Valor máximo para calcular la altura del eje Y
    final maxVal = _courseRecords.fold<double>(0, (m, r) {
      final v = ((r['countUsers'] ?? r['COUNT(*)'] ?? 0) as num).toDouble();
      return v > m ? v : m;
    });

    // Shell: misma tarjeta blanca con sombra que antes
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color:        Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.07),
              blurRadius: 20, offset: const Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cabecera: icono + título
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                    colors: [primary, primary.withOpacity(0.6)]),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.bar_chart_rounded,
                  color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Text('Estudiantes por curso',
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700, fontSize: 15)),
          ]),
          const SizedBox(height: 20),

          // Barras verticales — fl_chart BarChart
          // AnimatedBuilder usa _chartAnim para que las barras crezcan desde
          // abajo (toY = valor * progreso de animación 0→1).
          // Bug 3: scroll horizontal — cada curso ocupa mínimo 90px de ancho
          AnimatedBuilder(
            animation: _chartAnim,
            builder: (_, __) => LayoutBuilder(
              builder: (_, constraints) => SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: math.max(
                      _courseRecords.length * 90.0, constraints.maxWidth),
                  height: 260, // más alto para acomodar nombres en 2 líneas
                  child: BarChart(
                BarChartData(
                  // Sin grid ni bordes para un look limpio
                  gridData:   const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  // Margen superior para que los valores encima no se corten
                  maxY: (maxVal + 1) * 1.25,
                  // Tooltip limpio: muestra "Nombre\nN estudiantes"
                  barTouchData: BarTouchData(
                    // Bug 2: habilitar tooltip en tap simple (no solo long press)
                    handleBuiltInTouches: true,
                    enabled: true,
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (_) => const Color(0xFF1A1A2E),
                      tooltipRoundedRadius: 10,
                      getTooltipItem: (group, _, rod, __) {
                        final nombre = (_courseRecords[group.x.toInt()]
                                ['name'] as String?) ??
                            '';
                        final n = rod.toY.toInt();
                        return BarTooltipItem(
                          '$nombre\n',
                          GoogleFonts.poppins(
                              color:      Colors.white,
                              fontSize:   12,
                              fontWeight: FontWeight.w700),
                          children: [
                            TextSpan(
                              text: '$n estudiante${n == 1 ? '' : 's'}',
                              style: GoogleFonts.poppins(
                                  color:    Colors.white70,
                                  fontSize: 11),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  // Ejes: solo etiqueta de cursos abajo; todo lo demás oculto
                  titlesData: FlTitlesData(
                    leftTitles:  const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    // Valor del conteo encima de cada barra
                    topTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles:   true,
                        reservedSize: 28,
                        getTitlesWidget: (value, meta) {
                          final idx = value.toInt();
                          if (idx >= _courseRecords.length) {
                            return const SizedBox();
                          }
                          final n = ((_courseRecords[idx]['countUsers'] ??
                                      _courseRecords[idx]['COUNT(*)'] ??
                                      0) as num)
                              .toInt();
                          return Text('$n',
                              style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w800,
                                  fontSize:   13,
                                  color: paletasGradiente[
                                      idx % paletasGradiente.length][0]));
                        },
                      ),
                    ),
                    // Bug 3: nombre completo en 2 líneas, sin truncar
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles:   true,
                        reservedSize: 52,
                        getTitlesWidget: (value, meta) {
                          final idx = value.toInt();
                          if (idx >= _courseRecords.length) {
                            return const SizedBox();
                          }
                          final nombre =
                              (_courseRecords[idx]['name'] as String?) ?? '';
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              nombre,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                  fontSize: 10,
                                  color: Colors.grey.shade600),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  // Grupos de barras: uno por curso
                  barGroups: _courseRecords.asMap().entries.map((e) {
                    final idx = e.key;
                    final r   = e.value;
                    final val = ((r['countUsers'] ?? r['COUNT(*)'] ?? 0)
                            as num)
                        .toDouble();
                    final pal = paletasGradiente[idx % paletasGradiente.length];
                    return BarChartGroupData(
                      x: idx,
                      barRods: [
                        BarChartRodData(
                          // Animación desde abajo: altura * progreso del controller
                          toY:          val * _chartAnim.value,
                          width:        50, // Bug 3: barras más anchas y visibles
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(10)),
                          // Gradiente oscuro → claro de abajo a arriba
                          gradient: LinearGradient(
                            colors: pal,
                            begin:  Alignment.bottomCenter,
                            end:    Alignment.topCenter,
                          ),
                          // Sombra sutil debajo de la barra (efecto glow)
                          backDrawRodData: BackgroundBarChartRodData(
                            show:  true,
                            toY:   (maxVal + 1) * 1.25,
                            color: Colors.grey.shade100,
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
                // Animación de swap cuando cambian los datos
                swapAnimationDuration: const Duration(milliseconds: 400),
              ),             // cierra BarChart
                ),           // cierra SizedBox
              ),             // cierra SingleChildScrollView
            ),               // cierra LayoutBuilder builder
          ),                 // cierra AnimatedBuilder
        ],
      ),
    );
  }

  // ── SHIMMER ───────────────────────────────────────────────────────────────

  Widget _buildShimmer() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        _sBox(140, 24), const SizedBox(height: 14),
        _sBox(70, 18),  const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _sBox(100, 18)), const SizedBox(width: 14),
          Expanded(child: _sBox(100, 18)), const SizedBox(width: 14),
          Expanded(child: _sBox(100, 18)),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _sBox(180, 18)), const SizedBox(width: 14),
          Expanded(child: _sBox(180, 18)),
        ]),
      ]),
    );
  }

  Widget _sBox(double h, double r) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0.35, end: 0.75),
    duration: const Duration(milliseconds: 900),
    builder: (_, v, __) => Container(
      height: h,
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
          color: Colors.grey.shade200.withOpacity(v),
          borderRadius: BorderRadius.circular(r)),
    ),
  );
}

// ── MODELO PARA LA GRÁFICA DE DONA (Syncfusion) ──────────────────────────────

/// Datos de un segmento del DoughnutSeries: etiqueta, valor numérico y color.
class _PieData {
  final String label;
  final int    value;
  final Color  color;
  const _PieData(this.label, this.value, this.color);
}

// _PieChartPainter eliminado — reemplazado por SfCircularChart (Syncfusion)

// ── PAINTER DE BURBUJAS ANIMADAS ──────────────────────────────────────────────

/// Burbujas decorativas animadas para fondos de tarjetas.
class _BubblePainter extends CustomPainter {
  final double t;
  _BubblePainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..style = PaintingStyle.fill;
    final w = size.width;
    final h = size.height;

    p.color = Colors.white.withOpacity(0.07);
    canvas.drawCircle(
        Offset(w * 0.85 + 12 * math.sin(t * 2 * math.pi), h * -0.3),
        h * 1.15, p);
    p.color = Colors.white.withOpacity(0.05);
    canvas.drawCircle(
        Offset(w * -0.05 + 8 * math.cos(t * 2 * math.pi + 1), h * 1.1),
        h * 0.75, p);
    p.color = Colors.white.withOpacity(0.06);
    canvas.drawCircle(
        Offset(w * 0.55 + 10 * math.sin(t * 3 * math.pi), h * 0.55),
        h * 0.35, p);
    p.color = Colors.white.withOpacity(0.12);
    canvas.drawCircle(
        Offset(w * 0.72 + 6 * math.cos(t * 4 * math.pi), h * 0.2), 14, p);
  }

  @override
  bool shouldRepaint(_BubblePainter old) => old.t != t;
}


// _BarConHover/_BarConHoverState eliminados: reemplazados por SfCartesianChart.
