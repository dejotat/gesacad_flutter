import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../config/app_tokens.dart';
import '../../models/course_model.dart';
import '../../models/semaforo_models.dart';
import '../../models/user_model.dart';
import '../../services/api_service.dart';
import '../../services/semaforo_service.dart';
import '../../utils/route_transitions.dart';
import '../../widgets/ui/ui.dart';
import 'semaforo_screen.dart';

/// DOCENTE: elige una de sus materias, ve a sus estudiantes y abre el semáforo de uno
/// (donde registra la nota definitiva de SUS materias).
class TeacherSemaforoScreen extends StatefulWidget {
  const TeacherSemaforoScreen({super.key, required this.teacherId});
  final int teacherId;

  @override
  State<TeacherSemaforoScreen> createState() => _TeacherSemaforoScreenState();
}

class _TeacherSemaforoScreenState extends State<TeacherSemaforoScreen> {
  List<CourseModel> _cursos = [];
  final Map<int, List<Map<String, dynamic>>?> _estudiantes = {};
  bool _cargando = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = false;
    });
    try {
      final c = await ApiService().getMyCourses(widget.teacherId);
      if (!mounted) return;
      setState(() {
        _cursos = c;
        _cargando = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _cargando = false;
          _error = true;
        });
      }
    }
  }

  Future<void> _cargarEstudiantes(int cursoId) async {
    if (_estudiantes.containsKey(cursoId)) return;
    _estudiantes[cursoId] = null; // cargando
    try {
      final m = await ApiService().getCourseMembers(cursoId);
      final lista = [for (final e in (m['students'] as List? ?? const [])) (e as Map).cast<String, dynamic>()];
      if (mounted) setState(() => _estudiantes[cursoId] = lista);
    } catch (_) {
      if (mounted) setState(() => _estudiantes[cursoId] = const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final ids = {for (final c in _cursos) c.id};
    return Scaffold(
      appBar: AppBar(title: const Text('Semáforo de mis estudiantes')),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error
              ? ErrorState(message: 'No se pudieron cargar tus materias.', onRetry: _cargar)
              : _cursos.isEmpty
                  ? const EmptyState(icon: PhosphorIconsRegular.books, message: 'Sin materias asignadas.')
                  : ListView(
                      padding: const EdgeInsets.all(AppTokens.pagePadding),
                      children: [
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 800),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('Elige una materia y un estudiante para ver su semáforo y registrar la nota definitiva.',
                                  style: GoogleFonts.poppins(fontSize: 13, color: t.muted)),
                              const SizedBox(height: 14),
                              for (final c in _cursos)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: AppCard(
                                    padding: EdgeInsets.zero,
                                    child: Theme(
                                      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                                      child: ExpansionTile(
                                        leading: const Icon(PhosphorIconsRegular.books),
                                        title: Text(c.name,
                                            style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: onSurface)),
                                        subtitle: Text('Código ${c.courseCode}',
                                            style: GoogleFonts.poppins(fontSize: 12, color: t.muted)),
                                        onExpansionChanged: (abierto) {
                                          if (abierto) _cargarEstudiantes(c.id);
                                        },
                                        children: [
                                          if (!_estudiantes.containsKey(c.id) || _estudiantes[c.id] == null)
                                            const Padding(
                                                padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
                                          else if (_estudiantes[c.id]!.isEmpty)
                                            Padding(
                                              padding: const EdgeInsets.all(16),
                                              child: Text('Sin estudiantes matriculados.',
                                                  style: GoogleFonts.poppins(fontSize: 13, color: t.muted)),
                                            )
                                          else
                                            for (final e in _estudiantes[c.id]!)
                                              ListTile(
                                                leading: const Icon(PhosphorIconsRegular.graduationCap),
                                                title: Text(e['username']?.toString() ?? '',
                                                    style: GoogleFonts.poppins(fontSize: 14, color: onSurface)),
                                                trailing: const Icon(PhosphorIconsRegular.caretRight),
                                                onTap: () => Navigator.push(
                                                    context,
                                                    slideRoute(SemaforoScreen(
                                                      studentId: (e['id'] as num).toInt(),
                                                      studentName: e['username']?.toString(),
                                                      rol: 'Teacher',
                                                      teacherCourseIds: ids,
                                                    ))),
                                              ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                            ]),
                          ),
                        ),
                      ],
                    ),
    );
  }
}

/// ADMIN: busca a cualquier estudiante y abre su semáforo (con corrección excepcional e
/// historial). Desde aquí también se configura el plan de estudios.
class AdminSemaforoScreen extends StatefulWidget {
  const AdminSemaforoScreen({super.key});

  @override
  State<AdminSemaforoScreen> createState() => _AdminSemaforoScreenState();
}

class _AdminSemaforoScreenState extends State<AdminSemaforoScreen> {
  List<UserModel> _estudiantes = [];
  String _filtro = '';
  bool _cargando = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = false;
    });
    try {
      final l = await ApiService().getStudents();
      if (!mounted) return;
      setState(() {
        _estudiantes = l..sort((a, b) => a.username.toLowerCase().compareTo(b.username.toLowerCase()));
        _cargando = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _cargando = false;
          _error = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final lista = _estudiantes.where((e) => e.username.toLowerCase().contains(_filtro.toLowerCase())).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Semáforo académico'),
        actions: [
          IconButton(
            tooltip: 'Plan de estudios',
            icon: const Icon(PhosphorIconsRegular.treeStructure),
            onPressed: () => Navigator.push(context, slideRoute(const MallaAdminScreen())),
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error
              ? ErrorState(message: 'No se pudieron cargar los estudiantes.', onRetry: _cargar)
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 800),
                    child: Column(children: [
                      Padding(
                        padding: const EdgeInsets.all(AppTokens.pagePadding),
                        child: TextField(
                          onChanged: (v) => setState(() => _filtro = v),
                          decoration: const InputDecoration(
                            labelText: 'Buscar estudiante',
                            prefixIcon: Icon(PhosphorIconsRegular.magnifyingGlass),
                          ),
                        ),
                      ),
                      Expanded(
                        child: lista.isEmpty
                            ? const EmptyState(icon: PhosphorIconsRegular.graduationCap, message: 'Sin resultados.')
                            : ListView.builder(
                                padding: const EdgeInsets.fromLTRB(AppTokens.pagePadding, 0, AppTokens.pagePadding, 24),
                                itemCount: lista.length,
                                itemBuilder: (_, i) {
                                  final e = lista[i];
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: AppCard(
                                      padding: EdgeInsets.zero,
                                      child: ListTile(
                                        leading: const Icon(PhosphorIconsRegular.graduationCap),
                                        title: Text(e.username, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: onSurface)),
                                        subtitle: Text('Ver semáforo', style: GoogleFonts.poppins(fontSize: 12, color: t.muted)),
                                        trailing: const Icon(PhosphorIconsRegular.caretRight),
                                        onTap: () => Navigator.push(
                                            context,
                                            slideRoute(SemaforoScreen(studentId: e.id, studentName: e.username, rol: 'Admin'))),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ]),
                  ),
                ),
    );
  }
}

/// ADMIN: plan de estudios. Ubica cada materia en la malla (semestre, créditos, área) y define
/// sus pre-requisitos.
class MallaAdminScreen extends StatefulWidget {
  const MallaAdminScreen({super.key, this.service = const SemaforoService()});
  final SemaforoService service;

  @override
  State<MallaAdminScreen> createState() => _MallaAdminScreenState();
}

class _MallaAdminScreenState extends State<MallaAdminScreen> {
  List<MateriaMalla> _materias = [];
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final m = await widget.service.malla();
      if (!mounted) return;
      setState(() {
        _materias = m;
        _cargando = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _cargando = false;
          _error = e is ApiMessageException ? e.message : 'No se pudo cargar el plan de estudios.';
        });
      }
    }
  }

  Future<void> _editar(MateriaMalla m) async {
    final guardado = await showDialog<bool>(
      context: context,
      builder: (_) => _EditarMallaDialog(materia: m, todas: _materias, service: widget.service),
    );
    if (guardado == true) _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final nombres = {for (final m in _materias) m.courseId: m.name};
    return Scaffold(
      appBar: AppBar(title: const Text('Plan de estudios')),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorState(message: _error!, onRetry: _cargar)
              : _materias.isEmpty
                  ? const EmptyState(icon: PhosphorIconsRegular.books, message: 'Aún no hay materias. Crea materias primero.')
                  : Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 800),
                        child: ListView(
                          padding: const EdgeInsets.all(AppTokens.pagePadding),
                          children: [
                            Text(
                                'Ubica cada materia en la malla: semestre, créditos, área y pre-requisitos. '
                                'Las que no tengan semestre solo aparecen a los estudiantes que las cursan.',
                                style: GoogleFonts.poppins(fontSize: 13, color: t.muted)),
                            const SizedBox(height: 14),
                            for (final m in _materias)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: AppCard(
                                  padding: EdgeInsets.zero,
                                  child: ListTile(
                                    onTap: () => _editar(m),
                                    leading: const Icon(PhosphorIconsRegular.books),
                                    title: Text(m.name, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: onSurface)),
                                    subtitle: Text(
                                      [
                                        m.semester != null ? 'Semestre ${m.semester}' : 'Sin semestre',
                                        if (m.credits != null) '${m.credits} créditos',
                                        nombreDeArea(m.area),
                                        if (m.prerequisiteIds.isNotEmpty)
                                          'Requiere: ${m.prerequisiteIds.map((i) => nombres[i] ?? '#$i').join(', ')}',
                                      ].join(' · '),
                                      style: GoogleFonts.poppins(fontSize: 12, color: t.muted),
                                    ),
                                    trailing: const Icon(PhosphorIconsRegular.pencilSimple),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
    );
  }
}

class _EditarMallaDialog extends StatefulWidget {
  const _EditarMallaDialog({required this.materia, required this.todas, required this.service});
  final MateriaMalla materia;
  final List<MateriaMalla> todas;
  final SemaforoService service;

  @override
  State<_EditarMallaDialog> createState() => _EditarMallaDialogState();
}

class _EditarMallaDialogState extends State<_EditarMallaDialog> {
  late int? _semestre = widget.materia.semester;
  late int? _creditos = widget.materia.credits;
  late String? _area = widget.materia.area;
  late final Set<int> _prereq = {...widget.materia.prerequisiteIds};
  bool _guardando = false;
  String? _error;

  Future<void> _guardar() async {
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await widget.service.guardarMalla(widget.materia.courseId,
          semestre: _semestre, creditos: _creditos, area: _area, prerequisitos: _prereq.toList());
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _guardando = false;
          _error = e is ApiMessageException ? e.message : 'No se pudo guardar. Revisa tu conexión.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final otras = widget.todas.where((m) => m.courseId != widget.materia.courseId).toList();
    return AlertDialog(
      title: Text(widget.materia.name),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            DropdownButtonFormField<int?>(
              initialValue: _semestre,
              decoration: const InputDecoration(labelText: 'Semestre'),
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('Sin semestre')),
                for (var i = 1; i <= 12; i++) DropdownMenuItem<int?>(value: i, child: Text('Semestre $i')),
              ],
              onChanged: (v) => setState(() => _semestre = v),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int?>(
              initialValue: _creditos,
              decoration: const InputDecoration(labelText: 'Créditos'),
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('Sin créditos')),
                for (var i = 1; i <= 8; i++) DropdownMenuItem<int?>(value: i, child: Text('$i')),
              ],
              onChanged: (v) => setState(() => _creditos = v),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: _area,
              decoration: const InputDecoration(labelText: 'Área'),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Sin área')),
                for (final a in areasMalla) DropdownMenuItem<String?>(value: a, child: Text(nombreDeArea(a))),
              ],
              onChanged: (v) => setState(() => _area = v),
            ),
            const SizedBox(height: 16),
            Text('Pre-requisitos (hay que aprobarlos antes)',
                style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            if (otras.isEmpty)
              Text('No hay otras materias.', style: GoogleFonts.poppins(fontSize: 12, color: t.muted))
            else
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final o in otras)
                  FilterChip(
                    label: Text(o.name),
                    selected: _prereq.contains(o.courseId),
                    onSelected: (v) => setState(() => v ? _prereq.add(o.courseId) : _prereq.remove(o.courseId)),
                  ),
              ]),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Semantics(liveRegion: true, child: Text(_error!, style: GoogleFonts.poppins(fontSize: 12.5, color: t.danger))),
              ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _guardando ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
        ElevatedButton(
          onPressed: _guardando ? null : _guardar,
          child: _guardando
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Guardar'),
        ),
      ],
    );
  }
}
