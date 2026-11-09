import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../services/screen_reader.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/app_tokens.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../widgets/tts_button.dart';
import '../../widgets/chatbot_widget.dart';
import '../../widgets/ui/account_menu.dart';
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
import '../academic/semaforo_pickers.dart';
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
    ScreenReader.instance.bienvenida('administrador');
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
    // Quita TODAS las pantallas (el inicio y la sección abierta con el menú lateral).
    Navigator.pushAndRemoveUntil(context, slideRoute(const LoginScreen()), (_) => false);
  }

  String get _ttsText =>
      'Panel Administrador. Bienvenido $_name. '
      'Hay $_totalStudents estudiantes, $_totalTeachers profesores y '
      '$_totalAdmins administradores, en ${_courseRecords.length} materias.';

  // ── BUILD ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final nav = _nav;

    return AppShell(nav: nav, activo: 'inicio', child: Scaffold(
      appBar: _buildAppBar(),
      drawer: nav.cajon(context, 'inicio'),
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
    ));
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
    // En pantallas estrechas el AppBar muestra solo el botón del cajón (Scaffold lo añade).
    return AppBar(
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
        // Menú de cuenta compartido (foto, rol, perfil, ajustes y salida).
        MenuCuenta(
          nombre: _name,
          rol: 'Admin',
          foto: _photoBytes,
          onPerfil: () => Navigator.push(context, slideRoute(const ProfileScreen()))
              .then((_) => _reloadPhoto()),
          onAjustes: () => Navigator.push(context, slideRoute(const SettingsScreen())),
          onSalir: _logout,
        ),
      ],
    );
  }

  // ── MENÚ LATERAL ──────────────────────────────────────────────────────────

  SidebarNav get _nav => SidebarNav(
        rol: 'Admin',
        nombre: _name,
        foto: _photoBytes,
        onSalir: _logout,
        alVolver: () { if (mounted) { _reloadPhoto(); _loadData(); } },
        items: [
          const NavItem(id: 'inicio', icon: PhosphorIconsRegular.squaresFour, label: 'Panel principal'),
          NavItem(id: 'usuarios', icon: PhosphorIconsRegular.userGear, label: 'Gestionar usuarios',
              destination: () => const AdminUsers()),
          NavItem(id: 'materias', icon: PhosphorIconsRegular.books, label: 'Gestionar materias',
              destination: () => const AdminCourses()),
          NavItem(id: 'semaforo', icon: PhosphorIconsRegular.trafficSignal, label: 'Semáforo académico',
              destination: () => const AdminSemaforoScreen()),
          NavItem(id: 'evaluacion', icon: PhosphorIconsRegular.chartPolar, label: 'Evaluación docente',
              destination: () => AdminEvaluationsScreen(adminId: _myId)),
          NavItem(id: 'invitados', icon: PhosphorIconsRegular.buildings, label: 'Información para invitados',
              destination: () => const AdminUniversityInfo()),
          NavItem(id: 'perfil', icon: PhosphorIconsRegular.userCircle, label: 'Mi perfil',
              destination: () => const ProfileScreen()),
          NavItem(id: 'ajustes', icon: PhosphorIconsRegular.gear, label: 'Ajustes y Acerca de',
              destination: () => const SettingsScreen()),
        ],
      );

  // ── ENCABEZADO ────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return PageHeader(
      title: 'Hola, $_name',
      subtitle: 'Resumen general del sistema académico',
      leading: RoleBadge(role: RoleKind.admin, photo: _photoBytes),
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
          value: '$_totalStudents', label: 'Estudiantes', color: roleStyleOf(RoleKind.student).color,
          hint: avg != null ? '$avg por materia' : null,
          motion: roleStyleOf(RoleKind.student).motion),
      StatCard(icon: PhosphorIconsRegular.chalkboardTeacher,
          value: '$_totalTeachers', label: 'Profesores', color: roleStyleOf(RoleKind.teacher).color,
          motion: roleStyleOf(RoleKind.teacher).motion, delay: const Duration(milliseconds: 120)),
      StatCard(icon: PhosphorIconsRegular.shieldCheck,
          value: '$_totalAdmins', label: 'Administradores', color: roleStyleOf(RoleKind.admin).color,
          motion: roleStyleOf(RoleKind.admin).motion, delay: const Duration(milliseconds: 240)),
      StatCard(icon: PhosphorIconsRegular.books,
          value: '${_courseRecords.length}', label: 'Materias', color: t.chart[3],
          motion: IconMotion.pulse, delay: const Duration(milliseconds: 360)),
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
              DonutSlice('Estudiantes', _totalStudents, roleStyleOf(RoleKind.student).color),
              DonutSlice('Profesores', _totalTeachers, roleStyleOf(RoleKind.teacher).color),
              DonutSlice('Administradores', _totalAdmins, roleStyleOf(RoleKind.admin).color),
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
