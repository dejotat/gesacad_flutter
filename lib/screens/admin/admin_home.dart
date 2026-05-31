import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../services/settings_service.dart';
import '../../widgets/tts_button.dart';
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
  Uint8List? _photoBytes;

  // ── Estadísticas ──────────────────────────────────────────────────────────
  int _totalStudents = 0;
  int _totalTeachers = 0;
  int _totalAdmins   = 0;

  /// Registros por curso: [{name: String, countUsers: int}]
  List<Map<String, dynamic>> _courseRecords = [];

  // ── Estados UI ────────────────────────────────────────────────────────────
  bool _loading         = true;
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

  // ── Carga de datos ────────────────────────────────────────────────────────

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final prefs = await SharedPreferences.getInstance();
    _name = prefs.getString('userName') ?? 'Admin';

    final photoB64 = prefs.getString('profile_photo');
    if (photoB64 != null && photoB64.isNotEmpty) {
      try { _photoBytes = base64Decode(photoB64); } catch (_) {}
    }

    try {
      final qty     = await ApiService().getQuantityUsers();
      final records = await ApiService().getQuantityRecords();
      if (!mounted) return;

      _totalStudents = 0; _totalTeachers = 0; _totalAdmins = 0;
      for (final u in (qty['numberOfUsers'] as List)) {
        final rol   = u['rol'];
        final count = (u['COUNT(*)'] as num?)?.toInt() ?? 0;
        if (rol == 'Student') _totalStudents = count;
        if (rol == 'Teacher') _totalTeachers = count;
        if (rol == 'Admin')   _totalAdmins   = count;
      }

      // El campo es 'countUsers' (no COUNT(*))
      _courseRecords = List<Map<String, dynamic>>.from(
          records['numberOfRecords'] ?? []);
    } catch (_) {}

    if (mounted) {
      setState(() => _loading = false);
      _entryCtrl.forward(from: 0);
      _chartAnim.forward(from: 0);
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
      floatingActionButton: _loading ? null : TtsButton(text: _ttsText),
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
        const NotificationBell(),
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
              MaterialPageRoute(builder: (_) => const ProfileScreen())),
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

  // ── GRÁFICO DE TORTA PREMIUM (Custom Paint) ───────────────────────────────

  Widget _buildPieChart(Color primary) {
    final total = _totalStudents + _totalTeachers + _totalAdmins;
    if (total == 0) return const SizedBox();

    final datos = [
      _PieSec('Estudiantes', _totalStudents, '🎓',
          const Color(0xFF1565C0), const Color(0xFF42A5F5)),
      _PieSec('Profesores',  _totalTeachers, '📚',
          const Color(0xFF2E7D32), const Color(0xFF66BB6A)),
      _PieSec('Admins',      _totalAdmins,   '🛡️',
          const Color(0xFF6A1B9A), const Color(0xFFAB47BC)),
    ];

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
        // Cabecera
        Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFF1565C0), Color(0xFF42A5F5)]),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.pie_chart_rounded,
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
                    fontSize: 11, color: primary, fontWeight: FontWeight.w600)),
          ),
        ]),
        const SizedBox(height: 24),

        // Gráfico + leyenda
        SizedBox(
          height: 260,
          child: Row(children: [
            // Gráfico Custom Paint HD con zoom al interactuar
            Expanded(
              flex: 5,
              child: AnimatedBuilder(
                animation: _chartAnim,
                builder: (_, __) => Transform.scale(
                  // Efecto zoom: parte en 0.9 y llega a 1.0 al animar
                  scale: 0.90 + (_chartAnim.value * 0.10),
                  child: CustomPaint(
                    painter: _PieChartPainter(
                      datos: datos,
                      total: total,
                      progress: _chartAnim.value,
                      tocadoIdx: _touchedPieIndex,
                    ),
                    child: Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text('$total',
                            style: GoogleFonts.poppins(
                                fontSize: 26, fontWeight: FontWeight.w900,
                                color: const Color(0xFF1A1A2E))),
                        Text('usuarios',
                            style: GoogleFonts.poppins(
                                fontSize: 11, color: Colors.grey.shade400)),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 20),

            // Leyenda interactiva
            Expanded(
              flex: 4,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: datos.asMap().entries.map((e) {
                  final idx   = e.key;
                  final d     = e.value;
                  final sel   = _touchedPieIndex == idx;
                  final pct   = total > 0
                      ? (d.valor / total * 100).toStringAsFixed(0)
                      : '0';
                  return GestureDetector(
                    onTap: () {
                      setState(() =>
                          _touchedPieIndex = sel ? null : idx);
                      // Reiniciar animación para efecto de zoom/pulso
                      _chartAnim.forward(from: 0.8);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(bottom: 5),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: sel
                            ? d.c1.withOpacity(0.08)
                            : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: sel ? d.c1 : Colors.grey.shade200,
                          width: sel ? 2 : 1,
                        ),
                        boxShadow: sel
                            ? [BoxShadow(color: d.c1.withOpacity(0.15),
                                blurRadius: 8, offset: const Offset(0, 3))]
                            : [],
                      ),
                      child: Row(children: [
                        // Punto de color con gradiente
                        Container(
                          width: 12, height: 12,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: [d.c1, d.c2]),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${d.emoji} ${d.etiqueta}',
                                style: GoogleFonts.poppins(
                                    fontSize: 11, fontWeight: FontWeight.w600,
                                    color: Colors.grey.shade700)),
                          ],
                        )),
                        // Número y %
                        Column(crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                          Text('${d.valor}', style: GoogleFonts.poppins(
                              fontSize: 16, fontWeight: FontWeight.w900,
                              color: d.c1)),
                          Text('$pct%', style: GoogleFonts.poppins(
                              fontSize: 9, color: Colors.grey.shade400)),
                        ]),
                      ]),
                    ),
                  );
                }).toList(),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        Text('Toca una categoría para resaltar',
            style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade400)),
      ]),
    );
  }

  // ── GRÁFICO DE BARRAS PREMIUM (Custom Paint) ──────────────────────────────

  Widget _buildBarChart(Color primary) {
    if (_courseRecords.isEmpty) return const SizedBox();

    // Leer el campo correcto: 'countUsers' (no 'COUNT(*)')
    final valores = _courseRecords.map((r) {
      final v = r['countUsers'] ?? r['COUNT(*)'] ?? 0;
      return (v as num).toDouble();
    }).toList();

    final maxVal = valores.fold(0.0, math.max);

    // Paleta de gradientes vibrantes por barra
    final paletas = [
      [const Color(0xFF1565C0), const Color(0xFF42A5F5)],
      [const Color(0xFF2E7D32), const Color(0xFF66BB6A)],
      [const Color(0xFF6A1B9A), const Color(0xFFAB47BC)],
      [const Color(0xFFBF360C), const Color(0xFFFF7043)],
      [const Color(0xFF004D40), const Color(0xFF26A69A)],
    ];

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.07),
            blurRadius: 20, offset: const Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cabecera
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
          const SizedBox(height: 24),

          // Barras Custom Paint HD
          AnimatedBuilder(
            animation: _chartAnim,
            builder: (_, __) => SizedBox(
              height: 200,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: _courseRecords.asMap().entries.map((e) {
                  final idx    = e.key;
                  final r      = e.value;
                  final nombre = (r['name'] as String?) ?? '';
                  final val    = valores[idx];
                  final pct    = maxVal > 0 ? (val / maxVal) * _chartAnim.value : 0.0;
                  final pal    = paletas[idx % paletas.length];

                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      child: _BarConHover(
                        nombre: nombre,
                        valor: val,
                        pct: pct,
                        colores: pal,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          // Línea base decorativa
          const SizedBox(height: 8),
          Container(
            height: 2,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                primary.withOpacity(0.0),
                primary.withOpacity(0.25),
                primary.withOpacity(0.0),
              ]),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
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

// ── MODELOS DE DATOS ──────────────────────────────────────────────────────────

/// Datos de un segmento del gráfico de torta.
class _PieSec {
  final String etiqueta;
  final int    valor;
  final String emoji;
  final Color  c1; // Color oscuro (base)
  final Color  c2; // Color claro (gradiente)

  const _PieSec(this.etiqueta, this.valor, this.emoji, this.c1, this.c2);
}

// ── CUSTOM PAINTER DEL GRÁFICO DE TORTA ──────────────────────────────────────

/// Pinta un gráfico de donut HD con sombra 3D, gradientes y animación de entrada.
class _PieChartPainter extends CustomPainter {
  final List<_PieSec> datos;
  final int           total;
  final double        progress; // 0.0 → 1.0 (animación de entrada)
  final int?          tocadoIdx;

  const _PieChartPainter({
    required this.datos,
    required this.total,
    required this.progress,
    this.tocadoIdx,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (total == 0) return;

    final cx = size.width / 2;
    final cy = size.height / 2;
    final r  = math.min(cx, cy) * 0.88;

    // Radio exterior e interior del donut
    final rExt = r;
    final rInt = r * 0.55;

    // Ángulo inicial (12 en punto = -π/2)
    double startAngle = -math.pi / 2;

    for (int i = 0; i < datos.length; i++) {
      final d   = datos[i];
      final pct = d.valor / total;
      final sw  = 2 * math.pi * pct * progress; // Barrido animado
      final sel = tocadoIdx == i;

      // Desplazar el segmento seleccionado hacia afuera
      final despl = sel ? 8.0 : 0.0;
      final midA  = startAngle + sw / 2;
      final dx    = math.cos(midA) * despl;
      final dy    = math.sin(midA) * despl;

      final rect = Rect.fromCircle(
          center: Offset(cx + dx, cy + dy), radius: rExt);

      // ── Sombra 3D ────────────────────────────────────────────────────────
      final shadowPaint = Paint()
        ..color = d.c1.withOpacity(sel ? 0.35 : 0.2)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx + dx + 3, cy + dy + 4), radius: rExt),
        startAngle, sw, true, shadowPaint,
      );

      // ── Relleno con color sólido ──────────────────────────────────────────
      final fillPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = sel ? d.c2 : d.c1;
      canvas.drawArc(rect, startAngle, sw, true, fillPaint);

      // ── Brillo en borde superior (efecto 3D luz) ──────────────────────────
      final highlightPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white.withOpacity(0.35);
      canvas.drawArc(rect, startAngle, sw * 0.4, false, highlightPaint);

      // ── Separador blanco entre segmentos ──────────────────────────────────
      final sepPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white;
      canvas.drawArc(rect, startAngle, sw, true, sepPaint);

      startAngle += sw;
    }

    // ── Hueco central del donut (blanco) ─────────────────────────────────────
    final holePaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.white;
    canvas.drawCircle(Offset(cx, cy), rInt, holePaint);

    // ── Sombra interior del hueco (efecto profundidad) ────────────────────────
    final innerShadow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..color = Colors.black.withOpacity(0.06)
      ..maskFilter = const MaskFilter.blur(BlurStyle.inner, 4);
    canvas.drawCircle(Offset(cx, cy), rInt, innerShadow);
  }

  @override
  bool shouldRepaint(_PieChartPainter old) =>
      old.progress != progress ||
      old.tocadoIdx != tocadoIdx ||
      old.total != total;
}

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


// ── BARRA CON EFECTO HOVER ANIMADO ────────────────────────────────────────────

/// Barra individual del gráfico de barras con efecto hover.
/// Al pasar el cursor: crece 15%, muestra tooltip, cambia gradiente.
class _BarConHover extends StatefulWidget {
  final String nombre;
  final double valor;
  final double pct;        // Porcentaje 0.0 a 1.0 relativo al máximo
  final List<Color> colores; // [colorOscuro, colorClaro]

  const _BarConHover({
    required this.nombre,
    required this.valor,
    required this.pct,
    required this.colores,
  });

  @override
  State<_BarConHover> createState() => _BarConHoverState();
}

class _BarConHoverState extends State<_BarConHover>
    with SingleTickerProviderStateMixin {
  bool _hover = false;
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c1 = widget.colores[0];
    final c2 = widget.colores[1];
    final alturaBase = math.max(widget.pct * 140, 6.0);

    return MouseRegion(
      onEnter: (_) { setState(() => _hover = true); _ctrl.forward(); },
      onExit: (_) { setState(() => _hover = false); _ctrl.reverse(); },
      child: AnimatedBuilder(
        animation: _anim,
        builder: (_, __) {
          // Al hacer hover la barra crece 18%
          final altura = alturaBase * (1.0 + _anim.value * 0.18);
          return Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // Número encima de la barra
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 180),
                style: GoogleFonts.poppins(
                  fontSize: _hover ? 14 : 11,
                  fontWeight: FontWeight.w800,
                  color: c1,
                ),
                child: Text(widget.valor.toInt().toString()),
              ),
              const SizedBox(height: 4),

              // Barra con gradiente y efectos 3D
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: altura,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: _hover ? [c2, c1] : [c1, c2],
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                  ),
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(10)),
                  boxShadow: [
                    BoxShadow(
                      color: c1.withOpacity(_hover ? 0.6 : 0.3),
                      blurRadius: _hover ? 16 : 8,
                      offset: Offset(0, _hover ? 6.0 : 4.0),
                    ),
                  ],
                ),
                // Brillos 3D internos
                child: Stack(children: [
                  // Brillo lateral izquierdo
                  Positioned(left: 0, top: 0, bottom: 0,
                    child: Container(
                      width: 5,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(_hover ? 0.35 : 0.2),
                        borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(10)),
                      ),
                    ),
                  ),
                  // Brillo superior
                  Positioned(top: 0, left: 0, right: 0,
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(_hover ? 0.4 : 0.25),
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(10)),
                      ),
                    ),
                  ),
                ]),
              ),

              // Base 3D
              Container(
                height: 5,
                decoration: BoxDecoration(
                  color: c1.withOpacity(0.25),
                  borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(4)),
                ),
              ),
              const SizedBox(height: 6),

              // Nombre del curso
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 180),
                style: GoogleFonts.poppins(
                  fontSize: _hover ? 10 : 9,
                  color: _hover ? c1 : Colors.grey.shade600,
                  fontWeight: _hover ? FontWeight.w700 : FontWeight.w500,
                ),
                child: Text(
                  widget.nombre.length > 9
                      ? '${widget.nombre.substring(0, 8)}\u2026'
                      : widget.nombre,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
