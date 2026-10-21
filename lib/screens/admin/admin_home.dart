import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/app_tokens.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../services/settings_service.dart';
import '../../widgets/tts_button.dart';
import '../../widgets/chatbot_widget.dart';
import '../../widgets/ui/ui.dart';
import '../../widgets/eval/evaluation_entry_card.dart';
import '../evaluation/admin_evaluations_screen.dart';
import '../../widgets/offline_banner.dart';
import '../login_screen.dart';
import '../../utils/route_transitions.dart';
import '../settings_screen.dart';
import '../notifications/notifications_panel.dart';
import '../profile/profile_screen.dart';
import '../calendar/calendar_screen.dart';
import 'admin_university_info.dart';
import 'admin_users.dart';
import 'admin_courses.dart';

/// Panel principal del Administrador.
///
/// Muestra estadísticas globales del sistema (usuarios por rol y matriculados
/// por curso).
///
/// Secciones principales:
///   - AppBar con menú de navegación (perfil, ajustes, calendario, logout)
///   - Encabezado con saludo y rol
///   - Indicadores (estudiantes, profesores, admins, materias)
///   - Gráfica dona: distribución de usuarios por rol
///   - Barras horizontales: estudiantes por curso (orden descendente)
///   - Accesos rápidos a gestión de usuarios y cursos
class AdminHome extends StatefulWidget {
  const AdminHome({super.key});
  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  // ── Datos del usuario autenticado ─────────────────────────────────────────
  String     _name      = 'Admin';
  int        _myId      = 0;
  Uint8List? _photoBytes; // foto de perfil en memoria (base64 decodificado)

  // ── Estadísticas de usuarios ──────────────────────────────────────────────
  int _totalStudents = 0;
  int _totalTeachers = 0;
  int _totalAdmins   = 0;

  // Cursos con su cantidad de estudiantes matriculados, ordenados de mayor a
  // menor. Formato: [{ 'name': 'Cálculo Diferencial', 'countUsers': 12 }, ...]
  // Solo cuenta estudiantes (rol = 'Student').
  List<Map<String, dynamic>> _courseRecords = [];

  // ── Estados UI ────────────────────────────────────────────────────────────
  bool _loading = true;
  bool _error   = false;


  @override
  void initState() {
    super.initState();
    _loadData();
  }

  /// Recarga la foto de perfil desde SharedPreferences sin recargar todos los datos.
  /// Se llama 2s después de [_loadData] (para dar tiempo a
  /// [AuthService.fetchAndCachePhoto] de terminar la descarga en background)
  /// y también al regresar de la pantalla Mi Perfil.
  Future<void> _reloadPhoto() async {
    final prefs   = await SharedPreferences.getInstance();
    final photoB64 = prefs.getString('profile_photo') ?? '';
    if (photoB64.isNotEmpty && mounted) {
      try { setState(() => _photoBytes = base64Decode(photoB64)); } catch (_) {}
    }
  }

  int _countOf(Map<String, dynamic> r) =>
      ((r['countUsers'] ?? r['COUNT(*)'] ?? 0) as num).toInt();

  // ── Carga de datos del dashboard ──────────────────────────────────────────

  /// Carga datos del usuario y estadísticas del sistema desde el backend.
  ///
  /// 1. Lee nombre y foto desde SharedPreferences (instantáneo).
  /// 2. Llama [getQuantityUsers] y [getQuantityRecords] en PARALELO con
  ///    [Future.wait]: el tiempo total es el de la petición más lenta.
  /// 3. Si falla, muestra un estado de error con reintento (no conteos en 0).
  Future<void> _loadData() async {
    setState(() { _loading = true; _error = false; });
    final prefs = await SharedPreferences.getInstance();
    _name  = prefs.getString('userName') ?? 'Admin';
    _myId  = prefs.getInt('userId') ?? 0;

    final photoB64 = prefs.getString('profile_photo');
    if (photoB64 != null && photoB64.isNotEmpty) {
      try { _photoBytes = base64Decode(photoB64); } catch (_) {}
    }

    try {
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
          records['numberOfRecords'] ?? [])
        ..sort((a, b) => _countOf(b).compareTo(_countOf(a)));
    } catch (_) {
      _error = true;
    }

    if (mounted) {
      setState(() => _loading = false);
      // Si fetchAndCachePhoto aún no terminó al llegar aquí, re-intentar en 2s
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) _reloadPhoto();
      });
    }
  }

  /// Cierra la sesión del Admin: borra SharedPreferences y navega al login.
  Future<void> _logout() async {
    if (!await confirmarSalidaConPendientes(context)) return;
    await AuthService().clearSession();
    if (!mounted) return;
    Navigator.pushReplacement(context, slideRoute(const LoginScreen()));
  }

  String get _ttsText =>
      'Panel Administrador. Bienvenido $_name. '
      'Hay $_totalStudents estudiantes, $_totalTeachers profesores y '
      '$_totalAdmins administradores, en ${_courseRecords.length} materias.';

  // ── BUILD ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: _buildAppBar(),
      drawer: _buildDrawer(primary),
      body: LogoBackdrop(child: _loading
          ? _buildSkeleton()
          : _error
              ? ErrorState(
                  message: 'No se pudieron cargar las estadísticas. '
                      'Revisa tu conexión e inténtalo de nuevo.',
                  onRetry: _loadData,
                )
              : RefreshIndicator(
                  color: primary,
                  onRefresh: _loadData,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(AppTokens.pagePadding),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1100),
                        child: _buildContent(),
                      ),
                    ),
                  ),
                )),
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

  Widget _buildContent() {
    final total = _totalStudents + _totalTeachers + _totalAdmins;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(),
        // Evaluación docente (CU-08): avance del periodo abierto o acceso para crearlo.
        EvaluationEntryCard(role: EvalRole.admin, userId: _myId),
        const SizedBox(height: AppTokens.sectionGap),
        _buildKpis(),
        const SizedBox(height: AppTokens.sectionGap),
        LayoutBuilder(builder: (ctx, c) {
          final wide = c.maxWidth > 760;
          final donut = total > 0 ? _buildDonutCard(total) : null;
          final bars  = _courseRecords.isNotEmpty ? _buildCoursesCard() : null;
          if (donut == null && bars == null) {
            return const EmptyState(
              icon: Icons.insights_rounded,
              message: 'Aún no hay datos para mostrar. '
                  'Crea usuarios y materias para ver las estadísticas.',
            );
          }
          if (wide && donut != null && bars != null) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: donut),
                const SizedBox(width: 16),
                Expanded(child: bars),
              ],
            );
          }
          return Column(children: [
            if (donut != null) donut,
            if (donut != null && bars != null) const SizedBox(height: 16),
            if (bars != null) bars,
          ]);
        }),
        const SizedBox(height: AppTokens.sectionGap),
        SectionTitle('Accesos rápidos', icon: PhosphorIconsRegular.lightning),
        const SizedBox(height: 12),
        _buildQuickActions(),
        const SizedBox(height: 100),
      ],
    );
  }

  // ── APP BAR ───────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar() {
    final danger = context.tokens.danger;
    return AppBar(
      leading: Builder(builder: (ctx) => AnimatedIconButton(
        tooltip: 'Abrir menú de navegación',
        icon: PhosphorIconsRegular.list,
        reaction: IconReaction.nudge,
        onPressed: () => Scaffold.of(ctx).openDrawer(),
      )),
      title: const Text('Panel Administrador'),
      actions: [
        NotificationBell(userId: _myId, userRol: 'Admin'),
        AnimatedIconButton(
          tooltip: 'Calendario',
          icon: PhosphorIconsRegular.calendarBlank,
          reaction: IconReaction.flip,
          onPressed: () => Navigator.push(context,
              slideRoute(const CalendarScreen())),
        ),
        AnimatedIconButton(
          tooltip: 'Mi Perfil',
          icon: PhosphorIconsRegular.userCircle,
          reaction: IconReaction.pop,
          custom: _photoBytes != null
              ? CircleAvatar(backgroundImage: MemoryImage(_photoBytes!), radius: 15)
              : null,
          onPressed: () => Navigator.push(context,
              slideRoute(const ProfileScreen()))
              .then((_) => _reloadPhoto()),
        ),
        PopupMenuButton<String>(
          tooltip: 'Más opciones',
          icon: const Icon(PhosphorIconsRegular.dotsThreeVertical),
          onSelected: (v) {
            if (v == 'settings') Navigator.push(context,
                slideRoute(const SettingsScreen()));
            if (v == 'logout') _logout();
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'settings',
                child: Row(children: [
                  Icon(PhosphorIconsRegular.gear, size: 18),
                  SizedBox(width: 8), Text('Ajustes'),
                ])),
            PopupMenuItem(value: 'logout',
                child: Row(children: [
                  Icon(PhosphorIconsRegular.signOut, size: 18, color: danger),
                  const SizedBox(width: 8),
                  Text('Cerrar sesión', style: TextStyle(color: danger)),
                ])),
          ],
        ),
      ],
    );
  }

  // ── DRAWER ────────────────────────────────────────────────────────────────

  Widget _buildDrawer(Color primary) {
    final themeType = AppSettings.currentTheme.value;
    return Drawer(
      child: Column(children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 52, 20, 24),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: themeType.gradient,
                begin: Alignment.topLeft, end: Alignment.bottomRight),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Semantics(
              label: 'Foto de perfil de $_name',
              child: Container(
                width: 64, height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.5), width: 2),
                  color: Colors.white.withValues(alpha: 0.15),
                ),
                child: ClipOval(child: _photoBytes != null
                    ? ExcludeSemantics(
                        child: Image.memory(_photoBytes!, fit: BoxFit.cover))
                    : const Icon(PhosphorIconsRegular.shieldCheck,
                        color: Colors.white, size: 32)),
              ),
            ),
            const SizedBox(height: 14),
            Text(_name, style: GoogleFonts.poppins(
                color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            const HeaderChip(PhosphorIconsRegular.shieldCheck,
                'Administrador del sistema'),
          ]),
        ),
        _drawerItem(PhosphorIconsRegular.squaresFour, 'Panel Principal',
            () => Navigator.pop(context)),
        _drawerItem(PhosphorIconsRegular.userGear, 'Gestionar Usuarios', () {
          Navigator.pop(context);
          Navigator.push(context, slideRoute(const AdminUsers()))
              .then((_) { if (mounted) _loadData(); });
        }),
        _drawerItem(PhosphorIconsRegular.books, 'Gestionar Materias', () {
          Navigator.pop(context);
          Navigator.push(context, slideRoute(const AdminCourses()))
              .then((_) { if (mounted) _loadData(); });
        }),
        _drawerItem(PhosphorIconsRegular.chartPolar, 'Evaluación Docente', () {
          Navigator.pop(context);
          Navigator.push(context, slideRoute(AdminEvaluationsScreen(adminId: _myId)));
        }),
        _drawerItem(PhosphorIconsRegular.buildings, 'Información para invitados', () {
          Navigator.pop(context);
          Navigator.push(context, slideRoute(const AdminUniversityInfo()));
        }),
        _drawerItem(PhosphorIconsRegular.gear, 'Ajustes y Acerca de', () {
          Navigator.pop(context);
          Navigator.push(context, slideRoute(const SettingsScreen()));
        }),
        const Divider(height: 1),
        _drawerItem(PhosphorIconsRegular.signOut, 'Cerrar Sesión', _logout,
            color: context.tokens.danger),
      ]),
    );
  }

  Widget _drawerItem(IconData icon, String label, VoidCallback onTap,
          {Color? color}) =>
      ListTile(
        leading: Icon(icon, color: color ?? Theme.of(context).colorScheme.primary),
        title: Text(label,
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w500, fontSize: 14, color: color)),
        onTap: onTap,
      );

  // ── ENCABEZADO ────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return PageHeader(
      title: 'Hola, $_name',
      subtitle: 'Resumen general del sistema académico',
      leading: ExcludeSemantics(
        child: Container(
          width: 56, height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.5), width: 2),
            color: Colors.white.withValues(alpha: 0.15),
          ),
          child: ClipOval(child: _photoBytes != null
              ? Image.memory(_photoBytes!, fit: BoxFit.cover)
              : const Icon(PhosphorIconsRegular.shieldCheck,
                  color: Colors.white, size: 28)),
        ),
      ),
      chips: const [
        HeaderChip(PhosphorIconsRegular.shieldCheck, 'Administrador'),
      ],
    );
  }

  // ── INDICADORES ───────────────────────────────────────────────────────────

  Widget _buildKpis() {
    final t = context.tokens;
    final avg = (_courseRecords.isEmpty || _totalStudents == 0)
        ? null
        : (_totalStudents / _courseRecords.length).toStringAsFixed(1);

    final cards = [
      StatCard(icon: PhosphorIconsRegular.graduationCap,
          value: '$_totalStudents', label: 'Estudiantes', color: t.chart[0],
          hint: avg != null ? '$avg por materia' : null,
          motion: IconMotion.float),
      StatCard(icon: PhosphorIconsRegular.chalkboardTeacher,
          value: '$_totalTeachers', label: 'Profesores', color: t.chart[1],
          motion: IconMotion.pulse, delay: const Duration(milliseconds: 120)),
      StatCard(icon: PhosphorIconsRegular.shieldCheck,
          value: '$_totalAdmins', label: 'Administradores', color: t.chart[2],
          motion: IconMotion.wiggle, delay: const Duration(milliseconds: 240)),
      StatCard(icon: PhosphorIconsRegular.books,
          value: '${_courseRecords.length}', label: 'Materias', color: t.chart[3],
          motion: IconMotion.bounce, delay: const Duration(milliseconds: 360)),
    ];

    return LayoutBuilder(builder: (ctx, c) {
      final cols = c.maxWidth > 900 ? 4 : (c.maxWidth > 520 ? 2 : 1);
      const gap = 12.0;
      final w = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (final card in cards) SizedBox(width: w, child: card)],
      );
    });
  }

  // ── DONA: USUARIOS POR ROL ────────────────────────────────────────────────

  Widget _buildDonutCard(int total) {
    final t = context.tokens;
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionTitle('Usuarios por rol',
            icon: PhosphorIconsRegular.chartDonut,
            subtitle: '$total usuarios registrados'),
        const SizedBox(height: 16),
        Center(
          child: DonutChart(
            slices: [
              DonutSlice('Estudiantes', _totalStudents, t.chart[0]),
              DonutSlice('Profesores', _totalTeachers, t.chart[1]),
              DonutSlice('Administradores', _totalAdmins, t.chart[2]),
            ],
            centerValue: '$total',
            centerLabel: 'usuarios',
            summary: 'Distribución de usuarios por rol. '
                '$_totalStudents estudiantes, $_totalTeachers profesores, '
                '$_totalAdmins administradores.',
          ),
        ),
      ]),
    );
  }

  // ── BARRAS: ESTUDIANTES POR CURSO ─────────────────────────────────────────

  Widget _buildCoursesCard() {
    final t = context.tokens;
    const maxRows = 10;
    final shown = _courseRecords.take(maxRows).toList();
    final hidden = _courseRecords.length - shown.length;

    return Semantics(
      label: 'Estudiantes por materia. '
          '${shown.map((r) => '${r['name']}: ${_countOf(r)}').join(', ')}.',
      child: AppCard(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SectionTitle('Estudiantes por materia',
              icon: PhosphorIconsRegular.chartBar,
              subtitle: hidden > 0
                  ? 'Top $maxRows de ${_courseRecords.length} materias'
                  : '${_courseRecords.length} materias'),
          const SizedBox(height: 12),
          ExcludeSemantics(
            child: BarList(
              color: t.chart[0],
              rotateColors: true,
              items: [
                for (final r in shown)
                  BarItem((r['name'] as String?) ?? 'Sin nombre',
                      _countOf(r).toDouble()),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  // ── ACCESOS RÁPIDOS ───────────────────────────────────────────────────────

  Widget _buildQuickActions() {
    final t = context.tokens;
    final actions = [
      _ActionTile(
        icon: PhosphorIconsRegular.userGear,
        title: 'Gestionar usuarios',
        subtitle: 'Crear, editar y eliminar',
        color: t.chart[0],
        onTap: () => Navigator.push(context, slideRoute(const AdminUsers()))
            .then((_) { if (mounted) _loadData(); }),
      ),
      _ActionTile(
        icon: PhosphorIconsRegular.books,
        title: 'Gestionar materias',
        subtitle: 'Administrar el catálogo',
        color: t.chart[1],
        onTap: () => Navigator.push(context, slideRoute(const AdminCourses()))
            .then((_) { if (mounted) _loadData(); }),
      ),
    ];
    return LayoutBuilder(builder: (ctx, c) {
      if (c.maxWidth > 560) {
        return Row(children: [
          Expanded(child: actions[0]),
          const SizedBox(width: 12),
          Expanded(child: actions[1]),
        ]);
      }
      return Column(children: [
        actions[0], const SizedBox(height: 12), actions[1],
      ]);
    });
  }

  // ── ESQUELETO DE CARGA ────────────────────────────────────────────────────

  Widget _buildSkeleton() {
    return Semantics(
      label: 'Cargando estadísticas',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.pagePadding),
          child: Column(children: [
            const SkeletonBox(height: 110),
            const SizedBox(height: 16),
            Row(children: const [
              Expanded(child: SkeletonBox(height: 76)),
              SizedBox(width: 12),
              Expanded(child: SkeletonBox(height: 76)),
            ]),
            const SizedBox(height: 16),
            const SkeletonBox(height: 260),
          ]),
        ),
      ),
    );
  }
}

/// Acceso rápido: ícono, título y subtítulo. Un solo elemento accesible.
class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Semantics(
      button: true,
      label: '$title. $subtitle',
      child: ExcludeSemantics(
        child: AppCard(
          onTap: onTap,
          child: Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppTokens.radiusControl),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title,
                    style: GoogleFonts.poppins(
                        fontSize: 14, fontWeight: FontWeight.w600,
                        color: onSurface)),
                Text(subtitle,
                    style: GoogleFonts.poppins(fontSize: 12, color: t.muted)),
              ]),
            ),
            Icon(PhosphorIconsRegular.caretRight, size: 18, color: t.muted),
          ]),
        ),
      ),
    );
  }
}
