import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../models/course_model.dart';
import '../../models/activity_model.dart';
import '../../widgets/activity_card.dart';
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
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
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
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Map<int, List<ActivityModel>> get _byWeek {
    final map = <int, List<ActivityModel>>{};
    for (final a in _activities) {
      map.putIfAbsent(a.week, () => []).add(a);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final weeks = _byWeek.keys.toList()..sort();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.course.name),
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(icon: Icon(Icons.list_alt), text: 'Actividades'),
            Tab(icon: Icon(Icons.grade), text: 'Mis Notas'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _loading
              ? const Center(child: CircularProgressIndicator())
              : _activities.isEmpty
                  ? const Center(
                      child: Text('No hay actividades en este curso',
                          style: TextStyle(color: Colors.grey)))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        children: [
                          ...weeks.map((week) => Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF0D47A1),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text('Semana $week',
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold)),
                                    ),
                                  ),
                                  ..._byWeek[week]!.map((a) => ActivityCard(
                                        activity: a,
                                        onTap: () async {
                                          await Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  ActivityDetailScreen(
                                                activity: a,
                                                userId: widget.userId,
                                              ),
                                            ),
                                          );
                                          await _load();
                                        },
                                      )),
                                ],
                              )),
                        ],
                      ),
                    ),
          GradesScreen(
              courseId: widget.course.id,
              userId: widget.userId,
              courseName: widget.course.name),
        ],
      ),
    );
  }
}
