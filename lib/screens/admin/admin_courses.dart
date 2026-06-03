import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/api_service.dart';
import '../../models/course_model.dart';
import '../../models/user_model.dart';
import '../../widgets/course_card.dart';

/// Pantalla de gestión de cursos — diseño moderno con grid compacto.
class AdminCourses extends StatefulWidget {
  const AdminCourses({super.key});

  @override
  State<AdminCourses> createState() => _AdminCoursesState();
}

class _AdminCoursesState extends State<AdminCourses> {
  List<CourseModel> _courses = [];
  List<UserModel> _students = [];
  List<UserModel> _teachers = [];
  bool _loading = true;
  int _myId = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final prefs = await SharedPreferences.getInstance();
    _myId = prefs.getInt('userId') ?? 0;
    try {
      final results = await Future.wait([
        ApiService().getAllCourses(),
        ApiService().getStudents(),
        ApiService().getTeachers(),
      ]);
      _courses = results[0] as List<CourseModel>;
      _students = results[1] as List<UserModel>;
      _teachers = results[2] as List<UserModel>;
      if (_courses.isEmpty && _myId > 0) {
        _courses = await ApiService().getMyCourses(_myId);
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  // ── Crear curso ───────────────────────────────────────────────────────────
  void _showAddCourse() {
    final nameCtrl = TextEditingController();
    final codeCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    List<int> selectedStudents = [];
    UserModel? selectedTeacher;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          backgroundColor: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 480, maxHeight: 640),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 40,
                    offset: const Offset(0, 16))
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF0052D4), Color(0xFF6FB1FC)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(28),
                      topRight: Radius.circular(28),
                    ),
                  ),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.add_circle_rounded,
                          color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Column(crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('Crear Curso',
                          style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w700)),
                      Text('Completa los campos para crear el curso',
                          style: GoogleFonts.poppins(
                              color: Colors.white70, fontSize: 11)),
                    ]),
                  ]),
                ),
                // Formulario
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(22),
                    child: Form(
                      key: formKey,
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        TextFormField(
                          controller: nameCtrl,
                          style: GoogleFonts.poppins(fontSize: 14),
                          decoration: InputDecoration(
                            labelText: 'Nombre del curso',
                            labelStyle: GoogleFonts.poppins(fontSize: 13),
                            prefixIcon: const Icon(Icons.menu_book_rounded,
                                color: Color(0xFF0052D4)),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14)),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(
                                  color: Color(0xFF0052D4), width: 2),
                            ),
                          ),
                          validator: (v) =>
                              (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: codeCtrl,
                          style: GoogleFonts.poppins(fontSize: 14),
                          decoration: InputDecoration(
                            labelText: 'Código del curso',
                            labelStyle: GoogleFonts.poppins(fontSize: 13),
                            prefixIcon: const Icon(Icons.tag_rounded,
                                color: Color(0xFF6FB1FC)),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14)),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(
                                  color: Color(0xFF6FB1FC), width: 2),
                            ),
                          ),
                          validator: (v) =>
                              (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                        ),
                        const SizedBox(height: 18),
                        Text('Profesor asignado',
                            style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: const Color(0xFF1E1B4B))),
                        const SizedBox(height: 8),
                        _teachers.isEmpty
                            ? _emptyChip('No hay profesores registrados')
                            : DropdownButtonFormField<UserModel>(
                                value: selectedTeacher,
                                style: GoogleFonts.poppins(
                                    fontSize: 13, color: Colors.black87),
                                hint: Text('Selecciona un profesor',
                                    style: GoogleFonts.poppins(fontSize: 13)),
                                decoration: InputDecoration(
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14)),
                                  prefixIcon: const Icon(
                                      Icons.school_rounded,
                                      color: Color(0xFF059669)),
                                  isDense: true,
                                ),
                                items: _teachers
                                    .map((t) => DropdownMenuItem(
                                          value: t,
                                          child: Text(t.username),
                                        ))
                                    .toList(),
                                onChanged: (t) =>
                                    setInner(() => selectedTeacher = t),
                                validator: (v) =>
                                    v == null ? 'Selecciona un profesor' : null,
                              ),
                        const SizedBox(height: 18),
                        Row(children: [
                          Text('Estudiantes (opcional)',
                              style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  color: const Color(0xFF1E1B4B))),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2563EB).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${selectedStudents.length} selec.',
                              style: GoogleFonts.poppins(
                                  fontSize: 11,
                                  color: const Color(0xFF2563EB),
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                        ]),
                        const SizedBox(height: 8),
                        _students.isEmpty
                            ? _emptyChip('No hay estudiantes registrados')
                            : Container(
                                constraints:
                                    const BoxConstraints(maxHeight: 180),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                      color: Colors.grey.shade200, width: 1.5),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: ListView(
                                  shrinkWrap: true,
                                  children: _students
                                      .map((s) => CheckboxListTile(
                                            dense: true,
                                            title: Text(s.username,
                                                style: GoogleFonts.poppins(
                                                    fontSize: 13)),
                                            value: selectedStudents
                                                .contains(s.id),
                                            activeColor:
                                                const Color(0xFF2563EB),
                                            onChanged: (v) => setInner(() {
                                              if (v == true) {
                                                selectedStudents.add(s.id);
                                              } else {
                                                selectedStudents.remove(s.id);
                                              }
                                            }),
                                          ))
                                      .toList(),
                                ),
                              ),
                      ]),
                    ),
                  ),
                ),
                // Botones — cada uno en Expanded para ser responsive
                Padding(
                  padding:
                      const EdgeInsets.fromLTRB(22, 0, 22, 22),
                  child: Row(children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          minimumSize: const Size(0, 48),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text('Cancelar',
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF0052D4), Color(0xFF6FB1FC)],
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF0052D4).withOpacity(0.35),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () async {
                              if (!formKey.currentState!.validate()) return;
                              if (selectedTeacher == null) return;
                              Navigator.pop(ctx);
                              final participantes = [
                                ...selectedStudents,
                                if (_myId > 0 &&
                                    !selectedStudents.contains(_myId))
                                  _myId,
                              ];
                              await ApiService().addCourse(
                                nameCtrl.text.trim(),
                                codeCtrl.text.trim(),
                                participantes,
                                selectedTeacher!.id,
                              );
                              await _load();
                              if (mounted) {
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(const SnackBar(
                                  content: Text('Curso creado exitosamente'),
                                  backgroundColor: Colors.green,
                                ));
                              }
                            },
                            child: Center(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.add_circle_rounded,
                                      color: Colors.white, size: 18),
                                  const SizedBox(width: 8),
                                  Text('Crear Curso',
                                      style: GoogleFonts.poppins(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Eliminar curso ────────────────────────────────────────────────────────
  Future<void> _deleteCourse(CourseModel c) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          padding: const EdgeInsets.all(28),
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration:
                  BoxDecoration(color: Colors.red.shade50, shape: BoxShape.circle),
              child: Icon(Icons.delete_forever_rounded,
                  color: Colors.red.shade600, size: 32),
            ),
            const SizedBox(height: 16),
            Text('Eliminar Curso',
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700, fontSize: 18)),
            const SizedBox(height: 8),
            Text(
              '¿Eliminar "${c.name}"?\nSe eliminarán todas sus actividades y matrículas.',
              style: GoogleFonts.poppins(
                  fontSize: 13, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text('Cancelar',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade600,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text('Eliminar',
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w700, color: Colors.white)),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
    if (confirmed == true) {
      await ApiService().deleteCourse(c.id);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Curso eliminado'),
          backgroundColor: Colors.orange,
        ));
      }
    }
  }

  // ── Editar curso ──────────────────────────────────────────────────────────
  void _showEditCourse(CourseModel c) {
    final nameCtrl = TextEditingController(text: c.name);
    final codeCtrl = TextEditingController(text: c.courseCode);
    final searchCtrl = TextEditingController();
    UserModel? selectedTeacher;
    List<int> selectedStudents = [];
    bool loadingMembers = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) {
          if (loadingMembers) {
            ApiService().getCourseMembers(c.id).then((data) {
              final teacherMap = data['teacher'];
              final studentsRaw = data['students'] as List? ?? [];
              setStateDialog(() {
                loadingMembers = false;
                if (teacherMap != null) {
                  final tid = teacherMap['id'] as int?;
                  if (tid != null) {
                    selectedTeacher = _teachers.firstWhere(
                      (t) => t.id == tid,
                      orElse: () => _teachers.isNotEmpty
                          ? _teachers.first
                          : UserModel(
                              id: tid,
                              username:
                                  teacherMap['username']?.toString() ?? '',
                              rol: 'Teacher',
                            ),
                    );
                  }
                } else if (_teachers.isNotEmpty) {
                  selectedTeacher = _teachers.first;
                }
                selectedStudents = studentsRaw
                    .map((s) => (s['id'] as int?) ?? 0)
                    .where((id) => id > 0)
                    .toList();
              });
            });
          }

          final query = searchCtrl.text.toLowerCase();
          final visibleStudents = query.isEmpty
              ? _students
              : _students
                  .where((s) => s.username.toLowerCase().contains(query))
                  .toList();

          return Dialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            backgroundColor: Colors.transparent,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 520, maxHeight: 680),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.18),
                      blurRadius: 40,
                      offset: const Offset(0, 16))
                ],
              ),
              child: Column(children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF059669), Color(0xFF0EA5E9)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(28),
                      topRight: Radius.circular(28),
                    ),
                  ),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.edit_rounded,
                          color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('Editar Curso',
                          style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w700)),
                      Text(c.name,
                          style: GoogleFonts.poppins(
                              color: Colors.white70, fontSize: 11)),
                    ]),
                  ]),
                ),
                // Contenido
                if (loadingMembers)
                  const Expanded(
                      child: Center(child: CircularProgressIndicator()))
                else
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(22),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        TextField(
                          controller: nameCtrl,
                          style: GoogleFonts.poppins(fontSize: 14),
                          decoration: InputDecoration(
                            labelText: 'Nombre del curso',
                            labelStyle: GoogleFonts.poppins(fontSize: 13),
                            prefixIcon: const Icon(Icons.menu_book_rounded,
                                color: Color(0xFF059669)),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: codeCtrl,
                          style: GoogleFonts.poppins(fontSize: 14),
                          decoration: InputDecoration(
                            labelText: 'Código',
                            labelStyle: GoogleFonts.poppins(fontSize: 13),
                            prefixIcon: const Icon(Icons.tag_rounded,
                                color: Color(0xFF0EA5E9)),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text('Profesor asignado',
                            style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w700, fontSize: 13)),
                        const SizedBox(height: 8),
                        _teachers.isEmpty
                            ? _emptyChip('No hay profesores disponibles')
                            : DropdownButtonFormField<UserModel>(
                                value: selectedTeacher,
                                style: GoogleFonts.poppins(
                                    fontSize: 13, color: Colors.black87),
                                decoration: InputDecoration(
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14)),
                                  prefixIcon: const Icon(
                                      Icons.person_rounded,
                                      color: Color(0xFF059669)),
                                ),
                                hint: Text('Seleccionar profesor',
                                    style: GoogleFonts.poppins(fontSize: 13)),
                                items: _teachers
                                    .map((t) => DropdownMenuItem(
                                          value: t,
                                          child: Text(t.username),
                                        ))
                                    .toList(),
                                onChanged: (t) =>
                                    setStateDialog(() => selectedTeacher = t),
                              ),
                        const SizedBox(height: 18),
                        Row(children: [
                          Text('Estudiantes matriculados',
                              style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w700, fontSize: 13)),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color:
                                  const Color(0xFF059669).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text('${selectedStudents.length} selec.',
                                style: GoogleFonts.poppins(
                                    fontSize: 11,
                                    color: const Color(0xFF059669),
                                    fontWeight: FontWeight.w600)),
                          ),
                        ]),
                        const SizedBox(height: 8),
                        TextField(
                          controller: searchCtrl,
                          onChanged: (_) => setStateDialog(() {}),
                          style: GoogleFonts.poppins(fontSize: 13),
                          decoration: InputDecoration(
                            hintText: 'Buscar estudiante...',
                            hintStyle:
                                GoogleFonts.poppins(fontSize: 12),
                            isDense: true,
                            prefixIcon: const Icon(Icons.search_rounded,
                                size: 18),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12)),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          height: 160,
                          decoration: BoxDecoration(
                            border: Border.all(
                                color: Colors.grey.shade200, width: 1.5),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: visibleStudents.isEmpty
                              ? Center(
                                  child: Text('Sin resultados',
                                      style: GoogleFonts.poppins(
                                          color: Colors.grey)))
                              : ListView.builder(
                                  itemCount: visibleStudents.length,
                                  itemBuilder: (_, i) {
                                    final s = visibleStudents[i];
                                    final sel =
                                        selectedStudents.contains(s.id);
                                    return CheckboxListTile(
                                      dense: true,
                                      value: sel,
                                      activeColor: const Color(0xFF059669),
                                      title: Text(s.username,
                                          style: GoogleFonts.poppins(
                                              fontSize: 13)),
                                      onChanged: (v) =>
                                          setStateDialog(() {
                                        if (v == true) {
                                          selectedStudents.add(s.id);
                                        } else {
                                          selectedStudents.remove(s.id);
                                        }
                                      }),
                                    );
                                  },
                                ),
                        ),
                      ]),
                    ),
                  ),
                // Botones
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
                  child: Row(children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text('Cancelar',
                            style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF059669), Color(0xFF0EA5E9)],
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF059669).withOpacity(0.35),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () async {
                              Navigator.pop(ctx);
                              await ApiService().editCourse(
                                  c.id,
                                  nameCtrl.text.trim(),
                                  codeCtrl.text.trim());
                              if (selectedTeacher != null) {
                                await ApiService().updateCourseMembers(
                                    c.id,
                                    selectedTeacher!.id,
                                    selectedStudents);
                              }
                              await _load();
                              if (mounted) {
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(const SnackBar(
                                  content: Text('Curso actualizado'),
                                  backgroundColor: Colors.green,
                                ));
                              }
                            },
                            child: Center(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.save_rounded,
                                      color: Colors.white, size: 18),
                                  const SizedBox(width: 8),
                                  Text('Guardar cambios',
                                      style: GoogleFonts.poppins(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ]),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  Widget _emptyChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Text(text,
          style: GoogleFonts.poppins(
              fontSize: 13, color: Colors.grey.shade500)),
    );
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0052D4), Color(0xFF6FB1FC)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: Text('Gestión de Cursos',
            style: GoogleFonts.poppins(
                color: Colors.white, fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16, top: 8, bottom: 8),
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${_courses.length} cursos',
              style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddCourse,
        backgroundColor: const Color(0xFF0052D4),
        elevation: 6,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: Text('Nuevo Curso',
            style: GoogleFonts.poppins(
                color: Colors.white, fontWeight: FontWeight.w700)),
      ),
      body: _loading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(color: Color(0xFF0052D4)),
                  const SizedBox(height: 16),
                  Text('Cargando cursos...',
                      style: GoogleFonts.poppins(color: Colors.grey)),
                ],
              ),
            )
          : _courses.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.menu_book_outlined,
                          size: 80, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text('No hay cursos registrados',
                          style: GoogleFonts.poppins(
                              color: Colors.grey.shade400,
                              fontSize: 16,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Text('Usa el botón + para crear uno',
                          style: GoogleFonts.poppins(
                              color: Colors.grey.shade400, fontSize: 13)),
                    ],
                  ),
                )
              : LayoutBuilder(builder: (ctx, constraints) {
                  final cross = constraints.maxWidth > 1100
                      ? 5
                      : constraints.maxWidth > 800
                          ? 4
                          : constraints.maxWidth > 550
                              ? 3
                              : constraints.maxWidth > 380
                                  ? 2
                                  : 1;
                  return GridView.builder(
                    padding: const EdgeInsets.all(16).copyWith(bottom: 90),
                    gridDelegate:
                        SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cross,
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 14,
                      childAspectRatio: 1.1,
                    ),
                    itemCount: _courses.length,
                    itemBuilder: (ctx, i) => CourseCard(
                      course: _courses[i],
                      onTap: () {},
                      onEdit: () => _showEditCourse(_courses[i]),
                      onDelete: () => _deleteCourse(_courses[i]),
                      index: i,
                      hideOpenButton: true, // Admin no necesita abrir el curso
                    ),
                  );
                }),
    );
  }
}
