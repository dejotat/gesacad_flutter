import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../config/app_tokens.dart';
import '../../services/api_service.dart';
import '../../models/course_model.dart';
import '../../models/activity_model.dart';
import '../../widgets/activity_card.dart';
import '../../widgets/meeting/meeting_widgets.dart';
import '../../widgets/ui/ui.dart';
import 'activity_detail_screen.dart';
import 'grades_screen.dart';

/// Contenido de un curso para el estudiante: actividades y calificaciones (CU-02, CU-05, CU-06).
///
/// Usa un [TabController] con dos pestañas:
/// - **Actividades**: lista agrupada por semana; cada tarjeta navega a [ActivityDetailScreen].
/// - **Calificaciones**: muestra el resumen de notas vía [GradesScreen].
///
/// Accesibilidad (CU-07): las pestañas del [TabBar] son accesibles por TalkBack.
class StudentCourseContent extends StatefulWidget {
  /// Curso seleccionado desde [StudentHome].
  final CourseModel course;

  /// ID del estudiante autenticado, requerido por [ActivityDetailScreen] y [GradesScreen].
  final int userId;

  const StudentCourseContent(
      {super.key, required this.course, required this.userId});

  @override
  State<StudentCourseContent> createState() => _StudentCourseContentState();
}

class _StudentCourseContentState extends State<StudentCourseContent>
    with SingleTickerProviderStateMixin {
  List<ActivityModel> _activities = [];
  bool _loading = true;
  bool _error = false;
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
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
      final raw = await ApiService().getActivities(widget.course.id);
      final enriched = <ActivityModel>[];
      for (final a in raw) {
        try {
          final detail = await ApiService().getActivityContent(
              a.id, widget.userId, 'Student');
          enriched.add(detail ?? a);
        } catch (_) {
          enriched.add(a);
        }
      }
      _activities = enriched;
    } catch (_) {
      // Distinguir "no se pudo cargar" de "no hay actividades".
      if (_activities.isEmpty) _error = true;
    }
    if (mounted) setState(() => _loading = false);
  }

  Map<int, List<ActivityModel>> get _byWeek {
    final map = <int, List<ActivityModel>>{};
    for (final a in _activities) {
      map.putIfAbsent(a.week, () => []).add(a);
    }
    return map;
  }

  Widget _weekHeader(int week) {
    final primary = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppTokens.pagePadding, 20, AppTokens.pagePadding, 6),
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
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: primary)),
          ),
        ]),
      ),
    );
  }

  Widget _activitiesTab() {
    if (_loading) {
      return Semantics(
        label: 'Cargando actividades',
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
      );
    }
    if (_error) {
      return ErrorState(
        message: 'No se pudieron cargar las actividades. '
            'Revisa tu conexión e inténtalo de nuevo.',
        onRetry: _load,
      );
    }
    if (_activities.isEmpty) {
      return const EmptyState(
        icon: PhosphorIconsRegular.clipboardText,
        message: 'No hay actividades en este curso',
      );
    }

    final byWeek = _byWeek;
    final weeks = byWeek.keys.toList()..sort();
    return RefreshIndicator(
      onRefresh: _load,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              for (final week in weeks) ...[
                _weekHeader(week),
                for (final a in byWeek[week]!)
                  ActivityCard(
                    activity: a,
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ActivityDetailScreen(
                            activity: a,
                            userId: widget.userId,
                          ),
                        ),
                      );
                      await _load();
                    },
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.course.name),
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(icon: Icon(PhosphorIconsRegular.listChecks), text: 'Actividades'),
            Tab(icon: Icon(PhosphorIconsRegular.trophy), text: 'Mis Notas'),
          ],
        ),
      ),
      body: Column(children: [
        // Aparece solo cuando el docente inició o programó una reunión (CU-09).
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: CourseMeetingCard(courseId: widget.course.id, puedeGestionar: false),
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabCtrl,
            children: [
              _activitiesTab(),
              GradesScreen(
                  courseId: widget.course.id,
                  userId: widget.userId,
                  courseName: widget.course.name),
            ],
          ),
        ),
      ]),
    );
  }
}
