import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/app_tokens.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../models/course_model.dart';
import '../../models/activity_model.dart';
import '../../utils/activity_type.dart';
import '../../utils/grade_style.dart';
import '../../widgets/course_card.dart';
import '../../widgets/tts_button.dart';
import '../../widgets/ui/ui.dart';
import '../../widgets/eval/evaluation_entry_card.dart';
import '../../widgets/offline_banner.dart';
import '../login_screen.dart';
import '../../utils/route_transitions.dart';
import '../settings_screen.dart';
import '../notifications/notifications_panel.dart';
import '../profile/profile_screen.dart';
import '../calendar/calendar_screen.dart';
import 'student_course_content.dart';
import 'grades_screen.dart';
import '../../widgets/chatbot_widget.dart';

/// Panel principal del Estudiante.
///
/// Resume su avance con datos reales (promedio ponderado, actividades
/// calificadas, próximas entregas) y lista los cursos en que está matriculado.
/// Desde cada curso puede ver actividades, entregar tareas y consultar notas.
class StudentHome extends StatefulWidget {
  const StudentHome({super.key});
  @override
  State<StudentHome> createState() => _StudentHomeState();
}

/// Resumen de notas de un curso para el dashboard.
class _CourseGrades {
  _CourseGrades(this.course);
  final CourseModel course;
  double? average;     // promedio ponderado (null si no hay notas)
  int total = 0;       // actividades con nota asignable
  int graded = 0;      // actividades ya calificadas
  final Set<String> gradedTitles = {};
}

/// Actividad abierta aún por entregar/revisar.
class _Upcoming {
  _Upcoming(this.activity, this.courseName, this.closing);
  final ActivityModel activity;
  final String courseName;
  final DateTime closing; // hora Colombia
}

class _StudentHomeState extends State<StudentHome> {
  List<CourseModel> _courses = [];
  bool       _loading        = true;
  bool       _error          = false;
  String     _name           = '';
  Uint8List? _photoBytes;
  int        _myId           = 0;

  // Resumen académico, calculado en background por [_calcularResumen].
  bool _summaryLoading = true;
  final List<_CourseGrades> _grades = [];
  final List<_Upcoming> _upcoming = [];

  int get _totalActs  => _grades.fold(0, (s, c) => s + c.total);
  int get _gradedActs => _grades.fold(0, (s, c) => s + c.graded);

  /// Promedio general: promedio de los promedios de los cursos con nota.
  double? get _overall {
    final avgs = _grades.map((g) => g.average).whereType<double>().toList();
    if (avgs.isEmpty) return null;
    return avgs.reduce((a, b) => a + b) / avgs.length;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Recarga la foto desde SharedPreferences sin refrescar los cursos.
  Future<void> _reloadPhoto() async {
    final prefs    = await SharedPreferences.getInstance();
    final photoB64 = prefs.getString('profile_photo') ?? '';
    if (photoB64.isNotEmpty && mounted) {
      try { setState(() => _photoBytes = base64Decode(photoB64)); } catch (_) {}
    }
  }

  /// Carga la sesión y los cursos del estudiante.
  ///
  /// [getMyCourses] tiene caché en dos niveles (memoria 5 min y
  /// SharedPreferences). El pull-to-refresh llama a este mismo método.
  Future<void> _load() async {
    setState(() { _loading = true; _error = false; });
    final prefs = await SharedPreferences.getInstance();
    _name = prefs.getString('userName') ?? 'Estudiante';
    _myId = prefs.getInt('userId') ?? 0;
    final photoB64 = prefs.getString('profile_photo');
    if (photoB64 != null && photoB64.isNotEmpty) {
      try { _photoBytes = base64Decode(photoB64); } catch (_) {}
    }
    try {
      _courses = await ApiService().getMyCourses(_myId);
    } catch (_) {
      // Distinguir "no se pudo cargar" de "no tiene cursos".
      if (_courses.isEmpty) _error = true;
    }

    _calcularResumen();

    if (mounted) {
      setState(() => _loading = false);
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) _reloadPhoto();
      });
    }
  }

  /// Calcula el promedio ponderado por curso y las próximas entregas.
  /// Notas y actividades de todos los cursos se piden en paralelo.
  Future<void> _calcularResumen() async {
    if (mounted) setState(() => _summaryLoading = true);
    try {
      final ahoraCol = DateTime.now().toUtc().subtract(const Duration(hours: 5));

      final gradesPerCourse = await Future.wait(_courses.map((c) =>
          ApiService().getGrades(c.id, _myId)
              .catchError((_) => <Map<String, dynamic>>[])));
      final actsPerCourse = await Future.wait(_courses.map((c) =>
          ApiService().getActivities(c.id).catchError((_) => <ActivityModel>[])));

      final grades = <_CourseGrades>[];
      final upcoming = <_Upcoming>[];

      for (var i = 0; i < _courses.length; i++) {
        final cg = _CourseGrades(_courses[i]);
        double total = 0, totalW = 0;
        for (final g in gradesPerCourse[i]) {
          cg.total++;
          final gpa = double.tryParse(g['GPA']?.toString() ?? '');
          final w   = double.tryParse(g['weighting']?.toString() ?? '0') ?? 0;
          if (gpa != null) {
            total += gpa * w;
            totalW += w;
            cg.graded++;
            cg.gradedTitles.add(g['tittle']?.toString() ?? '');
          }
        }
        cg.average = totalW > 0 ? total / totalW : null;
        grades.add(cg);

        for (final a in actsPerCourse[i]) {
          if (a.type == 'resource') continue; // material, no se entrega
          if (cg.gradedTitles.contains(a.tittle)) continue;
          final cierre = ActivityModel.toCol(a.closingDate);
          if (ahoraCol.isBefore(cierre)) {
            upcoming.add(_Upcoming(a, _courses[i].name, cierre));
          }
        }
      }
      upcoming.sort((a, b) => a.closing.compareTo(b.closing));

      if (!mounted) return;
      setState(() {
        _grades..clear()..addAll(grades);
        _upcoming..clear()..addAll(upcoming);
        _summaryLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _summaryLoading = false);
    }
  }

  Future<void> _logout() async {
    if (!await confirmarSalidaConPendientes(context)) return;
    await AuthService().clearSession();
    if (!mounted) return;
    Navigator.pushReplacement(context, slideRoute(const LoginScreen()));
  }

  String get _ttsText {
    if (_courses.isEmpty) {
      return 'Hola $_name. Sin cursos matriculados. Contacta al administrador.';
    }
    final o = _overall;
    return 'Hola $_name. Tienes ${_courses.length} cursos: '
        '${_courses.map((c) => c.name).join(', ')}. '
        '${o != null ? 'Tu promedio general es ${o.toStringAsFixed(1)}. ' : ''}'
        '${_upcoming.isNotEmpty ? 'Tienes ${_upcoming.length} actividades abiertas.' : ''}';
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: _buildAppBar(),
      body: LogoBackdrop(child: RefreshIndicator(
        color: primary,
        onRefresh: _load,
        child: _loading
            ? _buildSkeleton()
            : _error
                ? LayoutBuilder(
                    builder: (_, c) => SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: SizedBox(
                        height: c.maxHeight,
                        child: ErrorState(
                          message: 'No se pudieron cargar tus cursos. '
                              'Revisa tu conexión e inténtalo de nuevo.',
                          onRetry: _load,
                        ),
                      ),
                    ),
                  )
                : CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1100),
                            child: _buildDashboard(),
                          ),
                        ),
                      ),
                      if (_courses.isEmpty)
                        const SliverToBoxAdapter(
                          child: EmptyState(
                            icon: Icons.menu_book_outlined,
                            message: 'Sin cursos matriculados.\n'
                                'Contacta al administrador.',
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(
                              AppTokens.pagePadding, 0,
                              AppTokens.pagePadding, 100),
                          sliver: SliverGrid(
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
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
                                  await Navigator.push(
                                      context,
                                      slideRoute(StudentCourseContent(
                                          course: _courses[i], userId: _myId)));
                                  // Al volver pudo cambiar una entrega o una nota.
                                  if (mounted) _calcularResumen();
                                },
                              ),
                              childCount: _courses.length,
                            ),
                          ),
                        ),
                    ],
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

  PreferredSizeWidget _buildAppBar() {
    final danger = context.tokens.danger;
    return AppBar(
      automaticallyImplyLeading: false,
      title: const Row(mainAxisSize: MainAxisSize.min, children: [
        MotionIcon(PhosphorIconsRegular.graduationCap,
            size: 24, motion: IconMotion.swing, halo: true),
        SizedBox(width: 8),
        Text('GESACAD'),
      ]),
      actions: [
        NotificationBell(userId: _myId, userRol: 'Student'),
        AnimatedIconButton(
          tooltip: 'Calendario',
          icon: PhosphorIconsRegular.calendarBlank,
          reaction: IconReaction.flip,
          onPressed: () => Navigator.push(context, slideRoute(const CalendarScreen())),
        ),
        AnimatedIconButton(
          tooltip: 'Mi Perfil',
          icon: PhosphorIconsRegular.userCircle,
          reaction: IconReaction.pop,
          custom: _photoBytes != null
              ? CircleAvatar(backgroundImage: MemoryImage(_photoBytes!), radius: 15)
              : null,
          onPressed: () => Navigator.push(context, slideRoute(const ProfileScreen()))
              .then((_) => _reloadPhoto()),
        ),
        PopupMenuButton<String>(
          tooltip: 'Más opciones',
          icon: const Icon(PhosphorIconsRegular.dotsThreeVertical),
          onSelected: (v) {
            if (v == 'settings') {
              Navigator.push(context, slideRoute(const SettingsScreen()));
            }
            if (v == 'logout') _logout();
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'settings', child: Row(children: [
              Icon(PhosphorIconsRegular.gear, size: 18),
              SizedBox(width: 8), Text('Ajustes'),
            ])),
            PopupMenuItem(value: 'logout', child: Row(children: [
              Icon(PhosphorIconsRegular.signOut, size: 18, color: danger),
              const SizedBox(width: 8),
              Text('Cerrar sesión', style: TextStyle(color: danger)),
            ])),
          ],
        ),
      ],
    );
  }

  // ── DASHBOARD ─────────────────────────────────────────────────────────────

  Widget _buildDashboard() {
    final now = DateTime.now();
    final saludo = now.hour < 12
        ? 'Buenos días'
        : now.hour < 18 ? 'Buenas tardes' : 'Buenas noches';

    return Padding(
      padding: const EdgeInsets.all(AppTokens.pagePadding),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        PageHeader(
          title: _name,
          subtitle: saludo,
          leading: ExcludeSemantics(
            child: Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.5), width: 2),
                color: Colors.white.withValues(alpha: 0.15),
              ),
              child: ClipOval(
                child: _photoBytes != null
                    ? Image.memory(_photoBytes!, fit: BoxFit.cover)
                    : const Icon(PhosphorIconsRegular.graduationCap,
                        color: Colors.white, size: 28),
              ),
            ),
          ),
          chips: [
            HeaderChip(PhosphorIconsRegular.books,
                '${_courses.length} curso${_courses.length == 1 ? '' : 's'}'),
            const HeaderChip(PhosphorIconsRegular.graduationCap, 'Estudiante'),
          ],
        ),
        // Evaluación docente (CU-08): aparece solo si hay un periodo abierto.
        EvaluationEntryCard(role: EvalRole.student, userId: _myId),
        if (_courses.isNotEmpty) ...[
          const SizedBox(height: AppTokens.sectionGap),
          _buildKpis(),
          const SizedBox(height: AppTokens.sectionGap),
          _buildSummary(),
        ],
        const SizedBox(height: AppTokens.sectionGap),
        SectionTitle('Mis cursos',
            icon: PhosphorIconsRegular.books,
            subtitle: '${_courses.length} matriculados'),
        const SizedBox(height: 12),
      ]),
    );
  }

  Widget _buildKpis() {
    final t = context.tokens;
    final o = _overall;
    final cards = [
      StatCard(icon: PhosphorIconsRegular.books,
          value: '${_courses.length}', label: 'Cursos', color: t.chart[0],
          motion: IconMotion.float),
      StatCard(icon: PhosphorIconsRegular.trophy,
          value: _summaryLoading ? '…' : (o?.toStringAsFixed(1) ?? '—'),
          label: 'Promedio general',
          color: GradeStyle.color(o, t),
          hint: _summaryLoading ? null : GradeStyle.label(o),
          motion: IconMotion.bounce, delay: const Duration(milliseconds: 130)),
      StatCard(icon: PhosphorIconsRegular.checkCircle,
          value: _summaryLoading ? '…' : '$_gradedActs/$_totalActs',
          label: 'Actividades calificadas', color: t.chart[1],
          motion: IconMotion.pulse, delay: const Duration(milliseconds: 260)),
      StatCard(icon: PhosphorIconsRegular.clock,
          value: _summaryLoading ? '…' : '${_upcoming.length}',
          label: 'Entregas abiertas', color: t.chart[3],
          motion: IconMotion.wiggle, delay: const Duration(milliseconds: 390)),
    ];
    return LayoutBuilder(builder: (ctx, c) {
      final cols = c.maxWidth > 900 ? 4 : (c.maxWidth > 480 ? 2 : 1);
      const gap = 12.0;
      final w = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (final card in cards) SizedBox(width: w, child: card)],
      );
    });
  }

  Widget _buildSummary() {
    if (_summaryLoading) {
      return Row(children: const [
        Expanded(child: SkeletonBox(height: 260)),
        SizedBox(width: 16),
        Expanded(child: SkeletonBox(height: 260)),
      ]);
    }
    final cards = [_buildProgressCard(), _buildAveragesCard(), _buildUpcomingCard()];
    return LayoutBuilder(builder: (ctx, c) {
      final cols = c.maxWidth > 760 ? 2 : 1;
      const gap = 16.0;
      final w = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (final card in cards) SizedBox(width: w, child: card)],
      );
    });
  }

  /// Dona: actividades calificadas vs. pendientes, con el promedio al centro.
  Widget _buildProgressCard() {
    final t = context.tokens;
    final o = _overall;
    final pending = _totalActs - _gradedActs;
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionTitle('Mi avance',
            icon: PhosphorIconsRegular.chartDonut,
            subtitle: '$_totalActs actividades evaluables'),
        const SizedBox(height: 12),
        DonutChart(
          slices: [
            DonutSlice('Calificadas', _gradedActs, t.success),
            DonutSlice('Pendientes', pending, t.border),
          ],
          centerValue: o?.toStringAsFixed(1) ?? '—',
          centerLabel: 'promedio',
          summary: 'Mi avance. $_gradedActs actividades calificadas y '
              '$pending pendientes. Promedio general '
              '${o?.toStringAsFixed(1) ?? 'sin notas'}.',
        ),
      ]),
    );
  }

  /// Promedio ponderado por curso (escala 0–5).
  Widget _buildAveragesCard() {
    final t = context.tokens;
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionTitle('Promedio por curso',
            icon: PhosphorIconsRegular.chartBar,
            subtitle: 'Escala 0 a 5 · aprueba con 3.0'),
        const SizedBox(height: 12),
        Semantics(
          label: 'Promedio por curso. ' +
              _grades
                  .map((g) =>
                      '${g.course.name}: ${g.average?.toStringAsFixed(1) ?? 'sin notas'}')
                  .join(', ') +
              '.',
          child: ExcludeSemantics(
            child: BarList(
              color: t.chart[0],
              max: 5,
              items: [
                for (final g in _grades)
                  BarItem(g.course.name, g.average ?? 0,
                      valueLabel: g.average?.toStringAsFixed(1) ?? '—',
                      color: GradeStyle.color(g.average, t)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => Navigator.push(
                context,
                slideRoute(_AllGradesScreen(
                    userId: _myId, courses: _courses, grades: _grades))),
            icon: const Icon(PhosphorIconsRegular.listChecks, size: 18),
            label: const Text('Ver detalle de notas'),
          ),
        ),
      ]),
    );
  }

  /// Próximas entregas, ordenadas por fecha de cierre (hora Colombia).
  Widget _buildUpcomingCard() {
    final t = context.tokens;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final fmt = DateFormat("d MMM · h:mm a", 'es');
    final proximas = _upcoming.take(5).toList();

    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionTitle('Próximas entregas',
            icon: PhosphorIconsRegular.clock,
            subtitle: _upcoming.isEmpty
                ? 'Sin actividades abiertas'
                : '${_upcoming.length} abiertas · se muestran 5'),
        const SizedBox(height: 8),
        if (proximas.isEmpty)
          const EmptyState(
              icon: PhosphorIconsRegular.checkCircle,
              message: 'No tienes entregas pendientes. ¡Buen trabajo!')
        else
          for (final u in proximas)
            Semantics(
              label: '${u.activity.tittle}, ${u.courseName}. '
                  'Cierra ${fmt.format(u.closing)}.',
              child: ExcludeSemantics(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(children: [
                    Container(
                      width: 38, height: 38,
                      decoration: BoxDecoration(
                        color: ActivityTypeInfo.colorOf(u.activity.type, t)
                            .withValues(alpha: 0.12),
                        borderRadius:
                            BorderRadius.circular(AppTokens.radiusControl),
                      ),
                      child: Icon(ActivityTypeInfo.of(u.activity.type).icon,
                          size: 20,
                          color: ActivityTypeInfo.colorOf(u.activity.type, t)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(u.activity.tittle,
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.poppins(
                                    fontSize: 13, fontWeight: FontWeight.w600,
                                    color: onSurface)),
                            Text(u.courseName,
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.poppins(
                                    fontSize: 12, color: t.muted)),
                          ]),
                    ),
                    const SizedBox(width: 8),
                    Text(fmt.format(u.closing),
                        style: GoogleFonts.poppins(
                            fontSize: 12, color: t.muted)),
                  ]),
                ),
              ),
            ),
      ]),
    );
  }

  // ── ESQUELETO DE CARGA ────────────────────────────────────────────────────

  Widget _buildSkeleton() => Semantics(
        label: 'Cargando cursos',
        child: ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.all(AppTokens.pagePadding),
            child: Column(children: const [
              SkeletonBox(height: 110),
              SizedBox(height: 16),
              Row(children: [
                Expanded(child: SkeletonBox(height: 76)),
                SizedBox(width: 12),
                Expanded(child: SkeletonBox(height: 76)),
              ]),
              SizedBox(height: 16),
              SkeletonBox(height: 240),
            ]),
          ),
        ),
      );
}

// ── Pantalla de resumen de notas ──────────────────────────────────────────────
// Todas las calificaciones agrupadas por curso: promedio ponderado y actividades
// calificadas vs. totales. Reutiliza los datos ya calculados por el dashboard.

class _AllGradesScreen extends StatelessWidget {
  final int userId;
  final List<CourseModel> courses;
  final List<_CourseGrades> grades;
  const _AllGradesScreen({
    required this.userId,
    required this.courses,
    required this.grades,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Scaffold(
      appBar: AppBar(title: const Text('Mis Notas')),
      body: grades.isEmpty
          ? const EmptyState(
              icon: Icons.menu_book_outlined, message: 'Sin cursos matriculados')
          : ListView.separated(
              padding: const EdgeInsets.all(AppTokens.pagePadding),
              itemCount: grades.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) {
                final g = grades[i];
                final color = GradeStyle.color(g.average, t);
                return Semantics(
                  button: true,
                  label: '${g.course.name}. '
                      'Promedio ${g.average?.toStringAsFixed(1) ?? 'sin notas'}. '
                      '${g.graded} de ${g.total} actividades calificadas. '
                      '${GradeStyle.label(g.average)}.',
                  child: ExcludeSemantics(
                    child: AppCard(
                      onTap: () => Navigator.push(
                        context,
                        slideRoute(Scaffold(
                          appBar: AppBar(title: Text(g.course.name)),
                          body: GradesScreen(
                            courseId: g.course.id,
                            userId: userId,
                            courseName: g.course.name,
                          ),
                        )),
                      ),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Expanded(
                                child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(g.course.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.poppins(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w600,
                                              color: onSurface)),
                                      Text(g.course.courseCode,
                                          style: GoogleFonts.poppins(
                                              fontSize: 12, color: t.muted)),
                                    ]),
                              ),
                              Container(
                                width: 56, height: 56,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: color.withValues(alpha: 0.12),
                                  border: Border.all(
                                      color: color.withValues(alpha: 0.5),
                                      width: 2),
                                ),
                                child: Center(
                                  child: Text(
                                      g.average?.toStringAsFixed(1) ?? '—',
                                      style: GoogleFonts.poppins(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w700,
                                          color: color)),
                                ),
                              ),
                            ]),
                            const SizedBox(height: 12),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: g.average != null
                                    ? (g.average! / 5.0).clamp(0.0, 1.0)
                                    : 0,
                                minHeight: 6,
                                backgroundColor: t.border,
                                color: color,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(children: [
                              Text('${g.graded} de ${g.total} calificadas',
                                  style: GoogleFonts.poppins(
                                      fontSize: 12, color: t.muted)),
                              const Spacer(),
                              Text(GradeStyle.label(g.average),
                                  style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: color)),
                            ]),
                          ]),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
