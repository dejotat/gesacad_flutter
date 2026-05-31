import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/api_service.dart';
import '../../models/course_model.dart';
import '../../models/activity_model.dart';
import '../../models/user_model.dart';
import '../../widgets/activity_card.dart';
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
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _tabCtrl.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      // Cargar actividades
      _activities = await ApiService().getActivities(widget.course.id);

      // Cargar estudiantes: primero intenta /courses/:id/members
      // Si falla o devuelve vacío, usa fallback: todos los usuarios Student
      // que están matriculados en este curso vía /registration
      await _loadStudents();
    } catch (_) {}
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

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          Container(padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.red.shade50, shape: BoxShape.circle),
            child: Icon(Icons.delete_forever_rounded, color: Colors.red.shade700, size: 22)),
          const SizedBox(width: 10),
          Expanded(child: Text('Eliminar Actividad',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 16))),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('¿Eliminar "${a.tittle}"?', style: GoogleFonts.poppins(fontSize: 14)),
          if (entregas > 0) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.shade200)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(
                    '$entregas entrega${entregas == 1 ? '' : 's'} se perderán.',
                    style: GoogleFonts.poppins(color: Colors.red.shade800, fontSize: 12, fontWeight: FontWeight.w600))),
              ]),
            ),
          ] else ...[
            const SizedBox(height: 6),
            Text('Esta acción no se puede deshacer.',
                style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade500)),
          ],
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancelar', style: GoogleFonts.poppins())),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(entregas > 0 ? 'Eliminar de todas formas' : 'Eliminar',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ApiService().deleteActivity(a.id, widget.course.id);
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Actividad eliminada'), backgroundColor: Colors.orange));
    }
  }

  void _showActivityDetail(ActivityModel a) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 28,
            left: 24, right: 24, top: 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          Text(a.tittle, style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          if (a.description.isNotEmpty)
            Text(a.description, style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade600)),
          const SizedBox(height: 16),
          _infoRow(Icons.category_rounded, 'Tipo', _typeLabel(a.type), Colors.indigo),
          _infoRow(Icons.percent_rounded, 'Ponderado', '${(a.weighting * 100).toStringAsFixed(0)}%', Colors.orange),
          _infoRow(Icons.calendar_today_rounded, 'Inicio', a.startDate.split('T')[0], Colors.green),
          _infoRow(Icons.event_rounded, 'Cierre', a.closingDate.split('T')[0], Colors.red),
          const SizedBox(height: 20),
          Container(
            width: double.infinity, height: 50,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF1A237E), Color(0xFF3949AB)]),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: const Color(0xFF1A237E).withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 4))],
            ),
            child: Material(color: Colors.transparent, borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => GradeStudentsScreen(
                    courseId: widget.course.id, courseName: widget.course.name,
                    activityId: a.id, activityName: a.tittle,
                  )));
                },
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.people_rounded, color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Text('Ver entregas y calificar',
                      style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value, Color color) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(children: [
      Container(padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, size: 14, color: color)),
      const SizedBox(width: 10),
      Text('$label: ', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.grey.shade700)),
      Text(value, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500)),
    ]),
  );

  String _typeLabel(String type) {
    switch (type) {
      case 'midterm': return 'Parcial';
      case 'project': return 'Proyecto';
      case 'resource': return 'Recurso';
      default: return 'Otro';
    }
  }

  @override
  Widget build(BuildContext context) {
    final weeks = _byWeek.keys.toList()..sort();
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1A237E), Color(0xFF3949AB)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.course.name,
              style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
          Text('Código: ${widget.course.courseCode}',
              style: GoogleFonts.poppins(color: Colors.white60, fontSize: 11)),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart_rounded, color: Colors.white),
            tooltip: 'Calificaciones generales',
            onPressed: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => GradeStudentsScreen(courseId: widget.course.id, courseName: widget.course.name),
            )),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: TabBar(
            controller: _tabCtrl,
            indicatorColor: Colors.white,
            indicatorWeight: 3,
            labelStyle: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 13),
            unselectedLabelStyle: GoogleFonts.poppins(fontSize: 13),
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            tabs: [
              Tab(text: 'Actividades (${_activities.length})'),
              Tab(text: 'Estudiantes (${_students.length})'),
            ],
          ),
        ),
      ),
      floatingActionButton: !_loading && _tabCtrl.index == 0
          ? FloatingActionButton.extended(
              onPressed: () async {
                await Navigator.push(context, MaterialPageRoute(
                  builder: (_) => AddActivityScreen(courseId: widget.course.id, teacherId: widget.teacherId),
                ));
                await _load();
              },
              backgroundColor: const Color(0xFF1A237E),
              icon: const Icon(Icons.add_rounded, color: Colors.white),
              label: Text('Nueva Actividad',
                  style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700)),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A237E)))
          : TabBarView(
              controller: _tabCtrl,
              children: [
                _buildActivitiesTab(weeks),
                _buildStudentsTab(),
              ],
            ),
    );
  }

  Widget _buildActivitiesTab(List<int> weeks) {
    if (_activities.isEmpty) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: Colors.indigo.shade50, shape: BoxShape.circle),
          child: Icon(Icons.assignment_outlined, size: 56, color: Colors.indigo.shade300)),
        const SizedBox(height: 16),
        Text('No hay actividades aún',
            style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.grey.shade600)),
        const SizedBox(height: 6),
        Text('Usa el botón + para agregar una',
            style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade400)),
      ]));
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: const Color(0xFF1A237E),
      child: ListView(
        padding: const EdgeInsets.only(bottom: 90, top: 8),
        children: weeks.map((week) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF1A237E), Color(0xFF3949AB)]),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: const Color(0xFF1A237E).withOpacity(0.25), blurRadius: 8, offset: const Offset(0, 3))],
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.calendar_view_week_rounded, color: Colors.white, size: 14),
                  const SizedBox(width: 6),
                  Text('Semana $week',
                      style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                ]),
              ),
            ),
            ..._byWeek[week]!.map((a) => ActivityCard(
              activity: a, onTap: () => _showActivityDetail(a), onDelete: () => _deleteActivity(a),
            )),
          ],
        )).toList(),
      ),
    );
  }

  Widget _buildStudentsTab() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF1A237E)));
    }
    if (_students.isEmpty) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: Colors.blue.shade50, shape: BoxShape.circle),
          child: Icon(Icons.people_outline_rounded, size: 56, color: Colors.blue.shade300)),
        const SizedBox(height: 16),
        Text('Sin estudiantes matriculados',
            style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.grey.shade600)),
        const SizedBox(height: 6),
        Text('El administrador puede matricular estudiantes',
            style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade400)),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded),
          label: Text('Actualizar', style: GoogleFonts.poppins()),
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A237E), foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        ),
      ]));
    }

    final colors = [
      [const Color(0xFF2563EB), const Color(0xFF7C3AED)],
      [const Color(0xFF059669), const Color(0xFF0EA5E9)],
      [const Color(0xFFDB2777), const Color(0xFFEA580C)],
      [const Color(0xFF7C3AED), const Color(0xFFDB2777)],
      [const Color(0xFF0EA5E9), const Color(0xFF059669)],
      [const Color(0xFFEA580C), const Color(0xFF2563EB)],
    ];

    return RefreshIndicator(
      onRefresh: _load,
      color: const Color(0xFF1A237E),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _students.length,
        itemBuilder: (ctx, i) {
          final s = _students[i];
          final inicial = s.username.isNotEmpty ? s.username[0].toUpperCase() : '?';
          final grad = colors[i % colors.length];
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: grad[0].withOpacity(0.10), blurRadius: 12, offset: const Offset(0, 4))],
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              leading: Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: grad, begin: Alignment.topLeft, end: Alignment.bottomRight),
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: grad[0].withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 3))],
                ),
                child: Center(child: Text(inicial,
                    style: GoogleFonts.poppins(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800))),
              ),
              title: Text(s.username,
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 14)),
              subtitle: Row(children: [
                Container(
                  margin: const EdgeInsets.only(top: 3),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: grad[0].withOpacity(0.10), borderRadius: BorderRadius.circular(10)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.school_rounded, size: 11, color: grad[0]),
                    const SizedBox(width: 3),
                    Text('Estudiante', style: GoogleFonts.poppins(fontSize: 10, color: grad[0], fontWeight: FontWeight.w600)),
                  ]),
                ),
              ]),
              trailing: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: grad[0].withOpacity(0.08), shape: BoxShape.circle),
                child: Icon(Icons.person_rounded, color: grad[0], size: 18),
              ),
            ),
          );
        },
      ),
    );
  }
}
