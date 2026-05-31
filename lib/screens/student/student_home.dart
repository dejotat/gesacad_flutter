import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../services/settings_service.dart';
import '../../models/course_model.dart';
import '../../widgets/course_card.dart';
import '../../widgets/tts_button.dart';
import '../../widgets/talk_widget.dart';
import '../login_screen.dart';
import '../settings_screen.dart';
import '../notifications/notifications_panel.dart';
import '../profile/profile_screen.dart';
import '../calendar/calendar_screen.dart';
import 'student_course_content.dart';

class StudentHome extends StatefulWidget {
  const StudentHome({super.key});
  @override
  State<StudentHome> createState() => _StudentHomeState();
}

class _StudentHomeState extends State<StudentHome> with TickerProviderStateMixin {
  List<CourseModel> _courses = [];
  bool _loading = true;
  String _name = '';
  Uint8List? _photoBytes;
  int _myId = 0;
  late AnimationController _entryCtrl;
  late Animation<double> _entryFade;
  late AnimationController _cardAnim;

  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _entryFade = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut);
    _cardAnim = AnimationController(vsync: this, duration: const Duration(seconds: 7))..repeat();
    _load();
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    _cardAnim.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final prefs = await SharedPreferences.getInstance();
    _name = prefs.getString('userName') ?? 'Estudiante';
    _myId = prefs.getInt('userId') ?? 0;
    final photoB64 = prefs.getString('profile_photo');
    if (photoB64 != null && photoB64.isNotEmpty) {
      try { _photoBytes = base64Decode(photoB64); } catch (_) {}
    }
    try { _courses = await ApiService().getMyCourses(_myId); } catch (_) {}
    if (mounted) { setState(() => _loading = false); _entryCtrl.forward(from: 0); }
  }

  Future<void> _logout() async {
    await AuthService().clearSession();
    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  String get _ttsText => _courses.isEmpty
      ? 'Hola $_name. Sin cursos matriculados. Contacta al administrador.'
      : 'Hola $_name. Tienes ${_courses.length} cursos: ${_courses.map((c) => c.name).join(', ')}.';

  @override
  Widget build(BuildContext context) {
    final themeType = AppSettings.currentTheme.value;
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      appBar: _buildAppBar(themeType),
      body: RefreshIndicator(
        color: primary,
        onRefresh: _load,
        child: _loading
            ? _buildShimmer()
            : FadeTransition(
                opacity: _entryFade,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(child: _buildHeader(themeType, primary)),
                    SliverToBoxAdapter(child: _buildQuickAccess(primary)),
                    SliverToBoxAdapter(child: _buildSectionTitle(primary)),
                    if (_courses.isEmpty)
                      SliverFillRemaining(child: _buildEmpty())
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                        sliver: SliverGrid(
                          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 260,
                            mainAxisExtent: 220,
                            crossAxisSpacing: 14,
                            mainAxisSpacing: 14,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (_, i) => CourseCard(
                              course: _courses[i],
                              index: i,
                              onTap: () async {
                                await Navigator.push(context, MaterialPageRoute(
                                  builder: (_) => StudentCourseContent(course: _courses[i], userId: _myId),
                                ));
                              },
                            ),
                            childCount: _courses.length,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
      ),
      floatingActionButton: _loading ? null : TtsButton(text: _ttsText),
    );
  }

  PreferredSizeWidget _buildAppBar(AppThemeType themeType) {
    return AppBar(
      automaticallyImplyLeading: false,
      flexibleSpace: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: themeType.gradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      ),
      title: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.school_rounded, color: Colors.white, size: 18),
        ),
        const SizedBox(width: 10),
        Text('GESACAD', style: GoogleFonts.poppins(
            color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18, letterSpacing: 1)),
      ]),
      centerTitle: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      actions: [
        NotificationBell(userId: _myId, userRol: 'Student'),
        IconButton(
          tooltip: 'Calendario',
          icon: const Icon(Icons.calendar_month_rounded, color: Colors.white),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CalendarScreen())),
        ),
        IconButton(
          tooltip: 'Mi Perfil',
          icon: _photoBytes != null
              ? CircleAvatar(backgroundImage: MemoryImage(_photoBytes!), radius: 14)
              : const Icon(Icons.account_circle_rounded, color: Colors.white),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen())),
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
          onSelected: (v) {
            if (v == 'settings') Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
            if (v == 'logout') _logout();
          },
          itemBuilder: (_) => [
            PopupMenuItem(value: 'settings', child: Row(children: [
              const Icon(Icons.settings_rounded, size: 18), const SizedBox(width: 8), const Text('Ajustes'),
            ])),
            PopupMenuItem(value: 'logout', child: Row(children: [
              Icon(Icons.logout_rounded, size: 18, color: Colors.red.shade600),
              const SizedBox(width: 8),
              Text('Cerrar sesión', style: TextStyle(color: Colors.red.shade600)),
            ])),
          ],
        ),
      ],
    );
  }

  Widget _buildHeader(AppThemeType themeType, Color primary) {
    final now = DateTime.now();
    final saludo = now.hour < 12 ? 'Buenos días' : now.hour < 18 ? 'Buenas tardes' : 'Buenas noches';
    final emoji = now.hour < 12 ? '🌤️' : now.hour < 18 ? '☀️' : '🌙';

    return AnimatedBuilder(
      animation: _cardAnim,
      builder: (_, __) => Container(
        margin: const EdgeInsets.fromLTRB(16, 20, 16, 0),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: themeType.gradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(color: primary.withOpacity(0.40), blurRadius: 28, offset: const Offset(0, 10)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Stack(children: [
            Positioned.fill(child: CustomPaint(painter: _BubblePainter(_cardAnim.value))),
            // Línea brillo superior
            Positioned(top: 0, left: 0, right: 0, child: Container(
              height: 1.5,
              decoration: BoxDecoration(gradient: LinearGradient(colors: [
                Colors.white.withOpacity(0.0),
                Colors.white.withOpacity(0.35),
                Colors.white.withOpacity(0.0),
              ])),
            )),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
              child: Row(children: [
                // Avatar
                Container(
                  width: 70, height: 70,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withOpacity(0.55), width: 2.5),
                    color: Colors.white.withOpacity(0.15),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 12, offset: const Offset(0, 4))],
                  ),
                  child: ClipOval(child: _photoBytes != null
                      ? Image.memory(_photoBytes!, fit: BoxFit.cover, width: 70, height: 70)
                      : const Icon(Icons.person_rounded, color: Colors.white, size: 32)),
                ),
                const SizedBox(width: 18),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(children: [
                      Text('$emoji ', style: const TextStyle(fontSize: 13)),
                      Text('$saludo,', style: GoogleFonts.poppins(color: Colors.white70, fontSize: 12)),
                    ]),
                    TalkWidget(label: 'Bienvenido $_name',
                    child: Text(_name, style: GoogleFonts.poppins(
                        color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800, height: 1.2))),
                    const SizedBox(height: 8),
                    Wrap(spacing: 6, children: [
                      _chip('🎓 ${_courses.length} curso${_courses.length == 1 ? '' : 's'}'),
                      _chip('📚 Estudiante'),
                    ]),
                  ],
                )),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _chip(String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.2),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.white.withOpacity(0.3)),
    ),
    child: Text(label, style: GoogleFonts.poppins(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
  );

  Widget _buildQuickAccess(Color primary) {
    final items = [
      _QuickItem('📊', 'Mis Notas', const Color(0xFF1D4ED8),
          () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Row(children: [
              const Text('📖', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 10),
              Text('Ingresa a un curso para ver tus calificaciones',
                  style: GoogleFonts.poppins(color: Colors.white, fontSize: 13)),
            ]),
            backgroundColor: const Color(0xFF1D4ED8),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            duration: const Duration(seconds: 3),
          ))),
      _QuickItem('📅', 'Calendario', const Color(0xFF7C3AED),
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CalendarScreen()))),
      _QuickItem('🔔', 'Avisos', const Color(0xFFDB2777),
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => NotificationsPanel(userId: _myId, userRol: 'Student')))),
      _QuickItem('👤', 'Mi Perfil', const Color(0xFF059669),
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()))),
      _QuickItem('⚙️', 'Ajustes', const Color(0xFFD97706),
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()))),
    ];

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 14, offset: const Offset(0, 4))],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: items.map((item) => _quickBtn(item)).toList(),
      ),
    );
  }

  Widget _quickBtn(_QuickItem item) {
    return InkWell(
      onTap: item.onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [item.color, item.color.withOpacity(0.7)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(color: item.color.withOpacity(0.40), blurRadius: 10, offset: const Offset(0, 4)),
                BoxShadow(color: Colors.white.withOpacity(0.2), blurRadius: 3, offset: const Offset(0, -1)),
              ],
            ),
            child: Text(item.emoji, style: const TextStyle(fontSize: 20)),
          ),
          const SizedBox(height: 6),
          Text(item.label, style: GoogleFonts.poppins(
              fontSize: 9, fontWeight: FontWeight.w700, color: item.color)),
        ]),
      ),
    );
  }

  Widget _buildSectionTitle(Color primary) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: primary.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
          child: Icon(Icons.library_books_rounded, color: primary, size: 18),
        ),
        const SizedBox(width: 10),
        Text('Mis cursos', style: GoogleFonts.poppins(
            fontSize: 16, fontWeight: FontWeight.w700, color: const Color(0xFF1E1B4B))),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [primary, primary.withOpacity(0.7)]),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text('${_courses.length}', style: GoogleFonts.poppins(
              fontSize: 12, color: Colors.white, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFFEFF6FF), Color(0xFFDBEAFE)]),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.school_outlined, size: 64, color: Color(0xFF2563EB)),
        ),
        const SizedBox(height: 20),
        Text('Sin cursos matriculados', style: GoogleFonts.poppins(
            fontSize: 18, fontWeight: FontWeight.w700, color: const Color(0xFF1E1B4B))),
        const SizedBox(height: 8),
        Text('Contacta a tu administrador', style: GoogleFonts.poppins(
            fontSize: 13, color: Colors.grey.shade400)),
      ]),
    );
  }

  Widget _buildShimmer() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        _sBox(150, 24), const SizedBox(height: 14),
        _sBox(80, 18), const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _sBox(220, 18)), const SizedBox(width: 14),
          Expanded(child: _sBox(220, 18)),
        ]),
      ]),
    );
  }

  Widget _sBox(double h, double r) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0.3, end: 0.7),
    duration: const Duration(milliseconds: 900),
    builder: (_, v, __) => Container(
      height: h, margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(color: Colors.grey.shade200.withOpacity(v), borderRadius: BorderRadius.circular(r)),
    ),
  );
}

class _BubblePainter extends CustomPainter {
  final double t;
  _BubblePainter(this.t);
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..style = PaintingStyle.fill;
    final w = size.width; final h = size.height;
    p.color = Colors.white.withOpacity(0.07);
    canvas.drawCircle(Offset(w * 0.85 + 12 * math.sin(t * 2 * math.pi), h * -0.3), h * 1.15, p);
    p.color = Colors.white.withOpacity(0.05);
    canvas.drawCircle(Offset(w * -0.05 + 8 * math.cos(t * 2 * math.pi + 1), h * 1.1), h * 0.75, p);
    p.color = Colors.white.withOpacity(0.06);
    canvas.drawCircle(Offset(w * 0.55 + 10 * math.sin(t * 3 * math.pi), h * 0.55), h * 0.35, p);
    p.color = Colors.white.withOpacity(0.10);
    canvas.drawCircle(Offset(w * 0.72 + 6 * math.cos(t * 4 * math.pi), h * 0.2), 14, p);
  }
  @override
  bool shouldRepaint(_BubblePainter old) => old.t != t;
}

class _QuickItem {
  final String emoji;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _QuickItem(this.emoji, this.label, this.color, this.onTap);
}