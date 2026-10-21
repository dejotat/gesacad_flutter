import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../config/app_tokens.dart';
import '../../services/api_service.dart';
import '../../models/course_model.dart';
import '../../models/activity_model.dart';
import '../../models/user_model.dart';
import '../../utils/activity_type.dart';
import '../../widgets/activity_card.dart';
import '../../widgets/meeting/meeting_widgets.dart';
import '../../widgets/ui/ui.dart';
import 'add_activity_screen.dart';
import 'grade_students_screen.dart';

/// Contenido del curso para el profesor: Actividades + Estudiantes matriculados.
class TeacherCourseContent extends StatefulWidget {
  final CourseModel course;
  final int teacherId;
  const TeacherCourseContent({super.key, required this.course, required this.teacherId});
  @override
  State<TeacherCourseContent> createState() => _TeacherCourseContentState();
}

class _TeacherCourseContentState extends State<TeacherCourseContent>
    with SingleTickerProviderStateMixin {
  List<ActivityModel> _activities = [];
  List<UserModel> _students = [];
  bool _loading = true;
  bool _error = false;
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    // Solo reconstruye al cambiar de pestaña (para mostrar/ocultar el botón +).
    _tabCtrl.addListener(() {
      if (!_tabCtrl.indexIsChanging) setState(() {});
    });
    _load();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = false; });
    try {
      // Cargar actividades
      _activities = await ApiService().getActivities(widget.course.id);

      // Cargar estudiantes: primero intenta /courses/:id/members
      // Si falla o devuelve vacío, usa fallback: todos los usuarios Student
      // que están matriculados en este curso vía /registration
      await _loadStudents();
    } catch (_) {
      // Distinguir "no se pudo cargar" de "no hay actividades".
      if (_activities.isEmpty) _error = true;
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadStudents() async {
    try {
      // Endpoint /courses/:id/members devuelve {teacher, students}
      // students tiene formato: [{id, username, email, rol}]
      final members = await ApiService().getCourseMembers(widget.course.id);
      final studentsRaw = members['students'];
      if (studentsRaw is List && studentsRaw.isNotEmpty) {
        _students = studentsRaw
            .whereType<Map<String, dynamic>>()
            .where((s) => (s['id'] ?? 0) > 0)
            .map((s) => UserModel(
                  id: s['id'] as int,
                  username: s['username']?.toString() ?? 'Estudiante',
                  rol: 'Student',
                ))
            .toList();
        if (_students.isNotEmpty) return;
      }
    } catch (_) {}

    // Fallback: registration endpoint — obtener todos los estudiantes y
    // verificar cuáles están en este curso
    try {
      final allStudents = await ApiService().getStudents();
      final List<UserModel> enrolled = [];
      for (final student in allStudents) {
        try {
          final courses = await ApiService().getMyCourses(student.id);
          if (courses.any((c) => c.id == widget.course.id)) {
            enrolled.add(student);
          }
        } catch (_) {}
      }
      _students = enrolled;
    } catch (_) {}
  }

  Map<int, List<ActivityModel>> get _byWeek {
    final map = <int, List<ActivityModel>>{};
    for (final a in _activities) {
      map.putIfAbsent(a.week, () => []).add(a);
    }
    return map;
  }

  Future<void> _deleteActivity(ActivityModel a) async {
    int entregas = 0;
    try { entregas = await ApiService().checkSubmissions(a.id); } catch (_) {}
    if (!mounted) return;
    final t = context.tokens;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: t.danger.withValues(alpha: 0.14), shape: BoxShape.circle),
            child: Icon(PhosphorIconsRegular.trash, color: t.danger, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Eliminar actividad',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 16)),
          ),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('¿Eliminar "${a.tittle}"?', style: GoogleFonts.poppins(fontSize: 14)),
            if (entregas > 0) ...[
              const SizedBox(height: 10),
              Semantics(
                liveRegion: true,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: t.danger.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: t.danger.withValues(alpha: 0.35)),
                  ),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(PhosphorIconsRegular.warning, color: t.danger, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$entregas entrega${entregas == 1 ? '' : 's'} se perderán.',
                        style: GoogleFonts.poppins(
                            color: t.danger, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ]),
                ),
              ),
            ] else ...[
              const SizedBox(height: 6),
              Text('Esta acción no se puede deshacer.',
                  style: GoogleFonts.poppins(fontSize: 12, color: t.muted)),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: t.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(entregas > 0 ? 'Eliminar de todas formas' : 'Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await ApiService().deleteActivity(a.id, widget.course.id);
      await _load();
      if (mounted) _snack('Actividad eliminada', t.success);
    } catch (_) {
      if (mounted) _snack('No se pudo eliminar la actividad. Inténtalo de nuevo.', t.danger);
    }
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  void _showActivityDetail(ActivityModel a) {
    final t = context.tokens;
    final info = ActivityTypeInfo.of(a.type);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              left: 24, right: 24, top: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                      color: t.border, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              Semantics(
                header: true,
                child: Text(a.tittle,
                    style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 4),
              if (a.description.isNotEmpty)
                Text(a.description,
                    style: GoogleFonts.poppins(fontSize: 13, color: t.muted)),
              const SizedBox(height: 16),
              _infoRow(info.icon, 'Tipo', info.label, ActivityTypeInfo.colorOf(a.type, t)),
              _infoRow(PhosphorIconsRegular.percent, 'Ponderado',
                  '${(a.weighting * 100).toStringAsFixed(0)}%', t.warning),
              _infoRow(PhosphorIconsRegular.calendarBlank, 'Inicio',
                  a.startDate.split('T')[0], t.success),
              _infoRow(PhosphorIconsRegular.calendarCheck, 'Cierre',
                  a.closingDate.split('T')[0], t.danger),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => GradeStudentsScreen(
                            courseId: widget.course.id,
                            courseName: widget.course.name,
                            activityId: a.id,
                            activityName: a.tittle,
                          ),
                        ));
                  },
                  icon: const Icon(PhosphorIconsRegular.users, size: 20),
                  label: const Text('Ver entregas y calificar'),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value, Color color) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 10),
          Text('$label: ',
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600, fontSize: 13, color: context.tokens.muted)),
          Text(value,
              style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final weeks = _byWeek.keys.toList()..sort();
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.course.name,
              style: GoogleFonts.poppins(
                  color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
          Text('Código: ${widget.course.courseCode}',
              style: GoogleFonts.poppins(color: Colors.white70, fontSize: 12)),
        ]),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(PhosphorIconsRegular.chartBar),
            tooltip: 'Calificaciones generales',
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => GradeStudentsScreen(
                      courseId: widget.course.id, courseName: widget.course.name),
                )),
          ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: [
            Tab(text: 'Actividades (${_activities.length})'),
            Tab(text: 'Estudiantes (${_students.length})'),
          ],
        ),
      ),
      floatingActionButton: !_loading && _tabCtrl.index == 0
          ? FloatingActionButton.extended(
              onPressed: () async {
                await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AddActivityScreen(
                          courseId: widget.course.id, teacherId: widget.teacherId),
                    ));
                await _load();
              },
              icon: const Icon(PhosphorIconsRegular.plus),
              label: Text('Nueva actividad',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
            )
          : null,
      body: Column(children: [
        // Iniciar/entrar a la reunión virtual del curso (CU-09).
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: CourseMeetingCard(courseId: widget.course.id, puedeGestionar: true),
          ),
        ),
        Expanded(
          child: _loading
          ? Semantics(
              label: 'Cargando curso',
              child: ExcludeSemantics(
                child: ListView(
                  padding: const EdgeInsets.all(AppTokens.pagePadding),
                  children: const [
                    SkeletonBox(height: 78), SizedBox(height: 10),
                    SkeletonBox(height: 78), SizedBox(height: 10),
                    SkeletonBox(height: 78),
                  ],
                ),
              ),
            )
          : _error
              ? ErrorState(
                  message: 'No se pudo cargar el curso. '
                      'Revisa tu conexión e inténtalo de nuevo.',
                  onRetry: _load,
                )
              : TabBarView(
                  controller: _tabCtrl,
                  children: [
                    _buildActivitiesTab(weeks),
                    _buildStudentsTab(),
                  ],
                ),
        ),
      ]),
    );
  }

  Widget _buildActivitiesTab(List<int> weeks) {
    if (_activities.isEmpty) {
      return const EmptyState(
        icon: PhosphorIconsRegular.clipboardText,
        message: 'No hay actividades aún.\nUsa el botón "Nueva actividad" para agregar una.',
      );
    }
    final primary = Theme.of(context).colorScheme.primary;
    return RefreshIndicator(
      onRefresh: _load,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 100, top: 4),
            children: [
              for (final week in weeks) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppTokens.pagePadding, 16, AppTokens.pagePadding, 6),
                  child: Semantics(
                    header: true,
                    child: Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: primary.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: primary.withValues(alpha: 0.30)),
                        ),
                        child: Text('Semana $week',
                            style: GoogleFonts.poppins(
                                fontSize: 13, fontWeight: FontWeight.w600, color: primary)),
                      ),
                    ]),
                  ),
                ),
                for (final a in _byWeek[week]!)
                  ActivityCard(
                    activity: a,
                    onTap: () => _showActivityDetail(a),
                    onDelete: () => _deleteActivity(a),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStudentsTab() {
    if (_students.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const EmptyState(
            icon: PhosphorIconsRegular.users,
            message: 'Sin estudiantes matriculados.\nEl administrador puede matricular estudiantes.',
          ),
          OutlinedButton.icon(
            onPressed: _load,
            icon: const Icon(PhosphorIconsRegular.arrowClockwise, size: 18),
            label: const Text('Actualizar'),
          ),
        ]),
      );
    }

    final t = context.tokens;
    return RefreshIndicator(
      onRefresh: _load,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView.separated(
            padding: const EdgeInsets.all(AppTokens.pagePadding),
            itemCount: _students.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (ctx, i) {
              final s = _students[i];
              final inicial = s.username.isNotEmpty ? s.username[0].toUpperCase() : '?';
              final color = t.chart[i % t.chart.length];
              return Semantics(
                label: 'Estudiante ${s.username}',
                child: ExcludeSemantics(
                  child: AppCard(
                    blur: false,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(children: [
                      Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.16),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(inicial,
                              style: GoogleFonts.poppins(
                                  color: color, fontSize: 18, fontWeight: FontWeight.w700)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(s.username,
                              style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w600, fontSize: 14)),
                          Text('Estudiante',
                              style: GoogleFonts.poppins(fontSize: 12, color: t.muted)),
                        ]),
                      ),
                    ]),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
