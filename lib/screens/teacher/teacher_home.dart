import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/app_tokens.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../models/course_model.dart';
import '../../models/activity_model.dart';
import '../../utils/activity_type.dart';
import '../../widgets/course_card.dart';
import '../../widgets/tts_button.dart';
import '../../widgets/chatbot_widget.dart';
import '../../widgets/ui/ui.dart';
import '../../widgets/eval/evaluation_entry_card.dart';
import '../../widgets/offline_banner.dart';
import '../login_screen.dart';
import '../../utils/route_transitions.dart';
import '../settings_screen.dart';
import '../notifications/notifications_panel.dart';
import '../profile/profile_screen.dart';
import '../calendar/calendar_screen.dart';
import 'teacher_course_content.dart';

/// Panel principal del Profesor.
///
/// Muestra indicadores y gráficos calculados con datos reales (actividades y
/// entregas de sus cursos) y la lista de cursos asignados. Desde cada curso el
/// profesor gestiona actividades y califica entregas.
class TeacherHome extends StatefulWidget {
  const TeacherHome({super.key});
  @override
  State<TeacherHome> createState() => _TeacherHomeState();
}

/// Resumen por curso para los gráficos del dashboard.
class _CourseStat {
  _CourseStat(this.course);
  final CourseModel course;
  int open = 0;      // actividades aún abiertas
  int graded = 0;    // entregas calificadas
  int ungraded = 0;  // entregas enviadas sin nota
}

class _TeacherHomeState extends State<TeacherHome> {
  List<CourseModel> _courses  = []; // cursos del profesor
  bool       _loading         = true;
  bool       _error           = false;
  String     _name            = '';
  Uint8List? _photoBytes;
  int        _myId            = 0;

  // Estadísticas calculadas en background por [_calcularEstadisticas].
  bool _statsLoading = true;
  final List<_CourseStat> _stats = [];
  final Map<String, int> _byType = {};          // actividades por tipo
  final List<int> _gradeBuckets = [0, 0, 0, 0, 0]; // notas 0-1, 1-2, 2-3, 3-4, 4-5

  int get _actsOpen   => _stats.fold(0, (s, c) => s + c.open);
  int get _graded     => _stats.fold(0, (s, c) => s + c.graded);
  int get _ungraded   => _stats.fold(0, (s, c) => s + c.ungraded);
  int get _totalActs  => _byType.values.fold(0, (s, v) => s + v);

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Recarga solo la foto desde SharedPreferences, sin refrescar los cursos.
  Future<void> _reloadPhoto() async {
    final prefs    = await SharedPreferences.getInstance();
    final photoB64 = prefs.getString('profile_photo') ?? '';
    if (photoB64.isNotEmpty && mounted) {
      try { setState(() => _photoBytes = base64Decode(photoB64)); } catch (_) {}
    }
  }

  /// Carga cursos del profesor e inicia el cálculo de estadísticas en background.
  Future<void> _load() async {
    setState(() { _loading = true; _error = false; });
    final prefs = await SharedPreferences.getInstance();
    _name = prefs.getString('userName') ?? 'Profesor';
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

    // Se calculan en segundo plano para no bloquear la pantalla.
    _calcularEstadisticas();

    if (mounted) {
      setState(() => _loading = false);
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) _reloadPhoto();
      });
    }
  }

  double? _gpa(dynamic v) => v == null ? null : double.tryParse(v.toString());

  /// Calcula, por curso, actividades abiertas y entregas calificadas / sin
  /// calificar, además de la distribución de notas y actividades por tipo.
  ///
  /// [Future.wait] carga las actividades de todos los cursos en paralelo y luego
  /// las entregas de todas las actividades en otra ronda paralela.
  /// Compara con hora Colombia (UTC-5) para decidir si una actividad sigue abierta.
  Future<void> _calcularEstadisticas() async {
    if (mounted) setState(() => _statsLoading = true);
    try {
      final ahoraCol = DateTime.now().toUtc().subtract(const Duration(hours: 5));

      final listaActividades = await Future.wait(
        _courses.map((c) =>
            ApiService().getActivities(c.id).catchError((_) => <ActivityModel>[])),
      );

      final stats = [for (final c in _courses) _CourseStat(c)];
      final byType = <String, int>{};
      final buckets = [0, 0, 0, 0, 0];

      // (índice de curso, futuro de entregas) por cada actividad
      final pendientes = <MapEntry<int, Future<List<Map<String, dynamic>>>>>[];
      for (var i = 0; i < listaActividades.length; i++) {
        for (final a in listaActividades[i]) {
          byType[a.type] = (byType[a.type] ?? 0) + 1;
          if (ahoraCol.isBefore(ActivityModel.toCol(a.closingDate))) {
            stats[i].open++;
          }
          pendientes.add(MapEntry(
            i,
            ApiService().getResolutions(a.id)
                .catchError((_) => <Map<String, dynamic>>[]),
          ));
        }
      }

      final resols = await Future.wait(pendientes.map((e) => e.value));
      for (var k = 0; k < resols.length; k++) {
        final stat = stats[pendientes[k].key];
        for (final r in resols[k]) {
          final entregada = r['resolution'] != null &&
              r['resolution'].toString().isNotEmpty;
          final nota = _gpa(r['GPA']);
          if (nota != null) {
            stat.graded++;
            buckets[nota.clamp(0, 4.999).floor()]++;
          } else if (entregada) {
            stat.ungraded++;
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _stats..clear()..addAll(stats);
        _byType..clear()..addAll(byType);
        for (var i = 0; i < buckets.length; i++) {
          _gradeBuckets[i] = buckets[i];
        }
        _statsLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _statsLoading = false);
    }
  }

  Future<void> _logout() async {
    if (!await confirmarSalidaConPendientes(context)) return;
    await AuthService().clearSession();
    if (!mounted) return;
    Navigator.pushReplacement(context, slideRoute(const LoginScreen()));
  }

  String get _ttsText => _courses.isEmpty
      ? 'Hola profesor $_name. Sin cursos asignados.'
      : 'Hola profesor $_name. Tienes ${_courses.length} cursos: '
          '${_courses.map((c) => c.name).join(', ')}. '
          'Hay $_ungraded entregas sin calificar.';

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
                      SliverToBoxAdapter(child: _centered(_buildDashboard())),
                      if (_courses.isEmpty)
                        const SliverToBoxAdapter(
                          child: EmptyState(
                            icon: Icons.menu_book_outlined,
                            message: 'Sin cursos asignados.\nContacta al administrador.',
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
                                      slideRoute(TeacherCourseContent(
                                          course: _courses[i],
                                          teacherId: _myId)));
                                  // Al volver puede haber cambiado lo calificado.
                                  if (mounted) _calcularEstadisticas();
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

  Widget _centered(Widget child) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: child,
        ),
      );

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
        NotificationBell(userId: _myId, userRol: 'Teacher'),
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
          subtitle: '$saludo, profe',
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
                    : const Icon(PhosphorIconsRegular.chalkboardTeacher,
                        color: Colors.white, size: 28),
              ),
            ),
          ),
          chips: [
            HeaderChip(PhosphorIconsRegular.books,
                '${_courses.length} curso${_courses.length == 1 ? '' : 's'}'),
            const HeaderChip(PhosphorIconsRegular.chalkboardTeacher, 'Docente'),
          ],
        ),
        // Resultados de evaluación docente (CU-08): solo con periodos cerrados.
        EvaluationEntryCard(role: EvalRole.teacher, userId: _myId),
        const SizedBox(height: AppTokens.sectionGap),
        _buildKpis(),
        const SizedBox(height: AppTokens.sectionGap),
        _buildCharts(),
        const SizedBox(height: AppTokens.sectionGap),
        SectionTitle('Mis cursos',
            icon: PhosphorIconsRegular.books,
            subtitle: '${_courses.length} asignados'),
        const SizedBox(height: 12),
      ]),
    );
  }

  Widget _buildKpis() {
    final t = context.tokens;
    final cards = [
      StatCard(icon: PhosphorIconsRegular.books,
          value: '${_courses.length}', label: 'Cursos asignados',
          color: t.chart[0], motion: IconMotion.float),
      StatCard(icon: PhosphorIconsRegular.clock,
          value: _statsLoading ? '…' : '$_actsOpen',
          label: 'Actividades abiertas', color: t.chart[3],
          motion: IconMotion.pulse, delay: const Duration(milliseconds: 140)),
      StatCard(icon: PhosphorIconsRegular.clipboardText,
          value: _statsLoading ? '…' : '$_ungraded',
          label: 'Entregas por calificar', color: t.chart[2],
          motion: IconMotion.wiggle, delay: const Duration(milliseconds: 280)),
    ];
    return LayoutBuilder(builder: (ctx, c) {
      final cols = c.maxWidth > 760 ? 3 : (c.maxWidth > 480 ? 2 : 1);
      const gap = 12.0;
      final w = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (final card in cards) SizedBox(width: w, child: card)],
      );
    });
  }

  Widget _buildCharts() {
    if (_courses.isEmpty) return const SizedBox.shrink();
    if (_statsLoading) {
      return Row(children: const [
        Expanded(child: SkeletonBox(height: 280)),
        SizedBox(width: 16),
        Expanded(child: SkeletonBox(height: 280)),
      ]);
    }
    if (_totalActs == 0) {
      return AppCard(
        child: EmptyState(
          icon: PhosphorIconsRegular.chartBar,
          message: 'Cuando crees actividades y recibas entregas, '
              'verás aquí tus estadísticas.',
        ),
      );
    }

    final cards = [
      _buildGradingCard(),
      _buildGradesHistogram(),
      _buildPendingByCourse(),
      _buildTypesCard(),
    ];

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

  /// Dona: entregas calificadas vs. por calificar.
  Widget _buildGradingCard() {
    final t = context.tokens;
    final total = _graded + _ungraded;
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionTitle('Estado de calificación',
            icon: PhosphorIconsRegular.chartDonut,
            subtitle: '$total entregas recibidas'),
        const SizedBox(height: 12),
        DonutChart(
          slices: [
            DonutSlice('Calificadas', _graded, t.success),
            DonutSlice('Por calificar', _ungraded, t.warning),
          ],
          centerValue: total == 0 ? '0%' : '${(_graded / total * 100).round()}%',
          centerLabel: 'calificado',
          summary: 'Estado de calificación. $_graded entregas calificadas y '
              '$_ungraded por calificar.',
        ),
      ]),
    );
  }

  /// Histograma de notas (0-1 … 4-5) con todas las entregas calificadas.
  Widget _buildGradesHistogram() {
    final t = context.tokens;
    const labels = ['0–1', '1–2', '2–3', '3–4', '4–5'];
    final maxV = _gradeBuckets.fold<int>(0, (m, v) => v > m ? v : m);
    final hasData = maxV > 0;

    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionTitle('Distribución de notas',
            icon: PhosphorIconsRegular.chartBar,
            subtitle: 'Número de entregas por rango de nota'),
        const SizedBox(height: 16),
        if (!hasData)
          const EmptyState(
              icon: PhosphorIconsRegular.chartBar,
              message: 'Aún no hay entregas calificadas.')
        else
          Semantics(
            label: 'Distribución de notas. '
                '${[for (var i = 0; i < labels.length; i++) '${labels[i]}: ${_gradeBuckets[i]}'].join(', ')}.',
            child: ExcludeSemantics(
              child: GradientColumns(
                height: 220,
                items: [
                  for (var i = 0; i < _gradeBuckets.length; i++)
                    BarItem(labels[i], _gradeBuckets[i].toDouble(),
                        color: i < 3 ? t.danger : t.success),
                ],
              ),
            ),
          ),
        const SizedBox(height: 10),
        Wrap(spacing: 14, runSpacing: 4, children: [
          _legendDot(t.danger, 'Por debajo de 3.0'),
          _legendDot(t.success, '3.0 o más'),
        ]),
      ]),
    );
  }

  Widget _legendDot(Color c, String text) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 10, height: 10,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: AppTokens.gradientOf(c)),
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: c.withValues(alpha: 0.5), blurRadius: 6)],
          ),
        ),
        const SizedBox(width: 6),
        Text(text,
            style: GoogleFonts.poppins(fontSize: 12, color: context.tokens.muted)),
      ]);

  /// Entregas por calificar en cada curso (ordenadas de mayor a menor).
  Widget _buildPendingByCourse() {
    final t = context.tokens;
    final ordenados = [..._stats]..sort((a, b) => b.ungraded.compareTo(a.ungraded));
    final todoAlDia = ordenados.every((s) => s.ungraded == 0);

    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionTitle('Por calificar, por curso',
            icon: PhosphorIconsRegular.clipboardText,
            subtitle: 'Entregas enviadas sin nota'),
        const SizedBox(height: 12),
        if (todoAlDia)
          const EmptyState(
              icon: PhosphorIconsRegular.checkCircle,
              message: 'Todo al día: no tienes entregas por calificar.')
        else
          Semantics(
            label: 'Entregas por calificar por curso. ' +
                ordenados
                    .map((s) => '${s.course.name}: ${s.ungraded}')
                    .join(', ') +
                '.',
            child: ExcludeSemantics(
              child: BarList(
                color: t.warning,
                items: [
                  for (final s in ordenados)
                    BarItem(s.course.name, s.ungraded.toDouble()),
                ],
              ),
            ),
          ),
      ]),
    );
  }

  /// Actividades por tipo (parcial, proyecto, recurso, otro).
  Widget _buildTypesCard() {
    final t = context.tokens;
    final tipos = _byType.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionTitle('Actividades por tipo',
            icon: PhosphorIconsRegular.exam,
            subtitle: '$_totalActs actividades en total'),
        const SizedBox(height: 12),
        Semantics(
          label: 'Actividades por tipo. ' +
              tipos
                  .map((e) => '${ActivityTypeInfo.of(e.key).label}: ${e.value}')
                  .join(', ') +
              '.',
          child: ExcludeSemantics(
            child: BarList(
              color: t.chart[0],
              items: [
                for (final e in tipos)
                  BarItem(ActivityTypeInfo.of(e.key).label, e.value.toDouble(),
                      color: ActivityTypeInfo.colorOf(e.key, t)),
              ],
            ),
          ),
        ),
      ]),
    );
  }

  // ── ESQUELETO DE CARGA ────────────────────────────────────────────────────

  Widget _buildSkeleton() => Semantics(
        label: 'Cargando cursos y estadísticas',
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
