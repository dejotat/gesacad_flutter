import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../config/app_tokens.dart';
import '../../models/activity_model.dart';
import '../../models/course_model.dart';
import '../../models/meeting_model.dart';
import '../../services/meeting_service.dart';
import '../../widgets/activity_card.dart';
import '../../widgets/course_card.dart';
import '../../widgets/eval/eval_widgets.dart' show RatingOrbs, ScoreRing;
import '../../widgets/meeting/meeting_widgets.dart';
import '../../widgets/ui/ui.dart';

/// Rol que el invitado quiere probar.
enum DemoRole {
  student('Estudiante', PhosphorIconsFill.student),
  teacher('Docente', PhosphorIconsFill.chalkboardTeacher),
  admin('Admin', PhosphorIconsFill.shieldCheck);

  const DemoRole(this.label, this.icon);
  final String label;
  final IconData icon;
}

// ── Datos de ejemplo (nada de esto existe en el servidor) ────────────────────
const _cursos = [
  CourseModel(id: 9001, name: 'Matemáticas Aplicadas', courseCode: 'DEMO-101', imgCourse: 1),
  CourseModel(id: 9002, name: 'Programación I', courseCode: 'DEMO-102', imgCourse: 2),
  CourseModel(id: 9003, name: 'Comunicación Oral y Escrita', courseCode: 'DEMO-103', imgCourse: 3),
];

String _iso(int dias) => DateTime.now().toUtc().add(Duration(days: dias)).toIso8601String();

List<ActivityModel> _actividades(int courseId) => [
      ActivityModel(
        id: courseId * 10 + 1, tittle: 'Taller 1: Fundamentos', week: 1, type: 'project',
        description: 'Actividad de ejemplo ya calificada.', weighting: 0.20,
        startDate: _iso(-14), closingDate: _iso(-7), courseId: courseId,
        gpa: 4.5, resolution: 'demo', dateResolution: _iso(-8),
        teacherComment: '¡Muy buen trabajo! (comentario de ejemplo)',
      ),
      ActivityModel(
        id: courseId * 10 + 2, tittle: 'Parcial 1', week: 3, type: 'midterm',
        description: 'Actividad de ejemplo con plazo abierto.', weighting: 0.30,
        startDate: _iso(-1), closingDate: _iso(5), courseId: courseId,
      ),
      ActivityModel(
        id: courseId * 10 + 3, tittle: 'Lectura recomendada', week: 3, type: 'resource',
        description: 'Material de apoyo de ejemplo.', weighting: 0.0,
        startDate: _iso(-3), closingDate: _iso(30), courseId: courseId,
      ),
    ];

/// Servicio de reuniones SIMULADO: vive en memoria, no toca el servidor. Así el
/// invitado prueba el botón real de reuniones (iniciar, entrar, terminar).
class _ReunionDemo extends MeetingService {
  _ReunionDemo({Meeting? inicial}) : _m = inicial;
  Meeting? _m;

  @override
  Future<Meeting?> current(int courseId) async => _m;

  @override
  Future<Meeting> start(int courseId, {String? title, String? url, DateTime? scheduledAt}) async {
    return _m = Meeting(
      id: 1, courseId: courseId, teacherName: 'Profe Demo',
      title: (title == null || title.trim().isEmpty) ? 'Reunión de clase' : title.trim(),
      provider: 'jitsi', url: 'https://meet.jit.si/demo-gesacad',
      scheduledAt: scheduledAt, isLive: scheduledAt == null,
    );
  }

  @override
  Future<void> end(int courseId) async => _m = null;
}

/// Demostración interactiva de un rol, con datos de ejemplo y SIN conexión al servidor.
class GuestDemo extends StatelessWidget {
  const GuestDemo({super.key, required this.role});
  final DemoRole role;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ListView(
      key: PageStorageKey('demo_${role.name}'),
      padding: const EdgeInsets.fromLTRB(AppTokens.pagePadding, 8, AppTokens.pagePadding, 40),
      children: [
        Semantics(
          liveRegion: true,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: t.info.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppTokens.radiusControl),
              border: Border.all(color: t.info.withValues(alpha: 0.35)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(PhosphorIconsFill.flask, color: t.info, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Modo demostración: son datos de ejemplo y no se guarda nada. '
                    'Toca, califica e inicia una reunión para ver cómo funciona.',
                    style: GoogleFonts.poppins(fontSize: 12.5, height: 1.4)),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 14),
        switch (role) {
          DemoRole.student => const _DemoEstudiante(),
          DemoRole.teacher => const _DemoDocente(),
          DemoRole.admin => const _DemoAdmin(),
        },
      ],
    );
  }
}

void _aviso(BuildContext context, String texto) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      content: Text(texto, style: GoogleFonts.poppins(color: Colors.white)),
    ));
}

/// Hoja con las actividades de ejemplo de un curso.
void _verCurso(BuildContext context, CourseModel c) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      builder: (_, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppTokens.pagePadding, 0, AppTokens.pagePadding, 8),
            child: Text(c.name, style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700)),
          ),
          for (final a in _actividades(c.id))
            ActivityCard(
              activity: a,
              onTap: () => _aviso(ctx, 'En la app real aquí ves el detalle y entregas tu trabajo.'),
            ),
        ],
      ),
    ),
  );
}

class _DemoEstudiante extends StatefulWidget {
  const _DemoEstudiante();
  @override
  State<_DemoEstudiante> createState() => _DemoEstudianteState();
}

class _DemoEstudianteState extends State<_DemoEstudiante> {
  int? _calificacion;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const PageHeader(
        title: 'Hola, Ana (ejemplo)',
        subtitle: 'Estudiante · Semestre de ejemplo',
        leading: Icon(PhosphorIconsFill.student, size: 28),
      ),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: StatCard(icon: PhosphorIconsRegular.books, value: '3', label: 'Cursos', color: t.chart[0])),
        const SizedBox(width: 10),
        Expanded(child: StatCard(icon: PhosphorIconsRegular.trophy, value: '4.2', label: 'Promedio', color: t.success)),
        const SizedBox(width: 10),
        Expanded(child: StatCard(icon: PhosphorIconsRegular.clock, value: '2', label: 'Pendientes', color: t.warning)),
      ]),
      const SizedBox(height: AppTokens.sectionGap),
      const SectionTitle('Mis cursos', icon: PhosphorIconsRegular.books, subtitle: 'Toca uno para ver sus actividades'),
      const SizedBox(height: 8),
      for (var i = 0; i < _cursos.length; i++)
        CourseCard(course: _cursos[i], index: i, onTap: () => _verCurso(context, _cursos[i])),
      const SizedBox(height: AppTokens.sectionGap),
      const SectionTitle('Reunión virtual', icon: PhosphorIconsRegular.videoCamera),
      CourseMeetingCard(
        courseId: 9001,
        puedeGestionar: false,
        cadaSegundos: 3600,
        servicio: _ReunionDemo(inicial: const Meeting(
          id: 1, courseId: 9001, teacherName: 'Profe Demo', title: 'Repaso del parcial',
          provider: 'jitsi', url: 'https://meet.jit.si/demo-gesacad', scheduledAt: null, isLive: true)),
        abrirEnlace: (_) async {
          _aviso(context, 'En la app real te unes a la videollamada con un toque.');
          return true;
        },
      ),
      const SizedBox(height: AppTokens.sectionGap),
      const SectionTitle('Evalúa a tu docente', icon: PhosphorIconsRegular.chartPolar,
          subtitle: 'Al final del semestre, de forma anónima'),
      const SizedBox(height: 10),
      AppCard(
        blur: false,
        child: Column(children: [
          Text('¿Cómo explica los temas Profe Demo?',
              style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 14),
          RatingOrbs(
            value: _calificacion,
            questionLabel: '¿Cómo explica los temas Profe Demo?',
            onChanged: (v) => setState(() => _calificacion = v),
          ),
          if (_calificacion != null) ...[
            const SizedBox(height: 10),
            Text('En la app real tu respuesta es anónima y el docente solo ve promedios.',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(fontSize: 12, color: t.muted)),
          ],
        ]),
      ),
    ]);
  }
}

class _DemoDocente extends StatefulWidget {
  const _DemoDocente();
  @override
  State<_DemoDocente> createState() => _DemoDocenteState();
}

class _DemoDocenteState extends State<_DemoDocente> {
  final _notas = <String, double>{'Ana Gómez': 4.5, 'Luis Pérez': 3.8, 'María Ruiz': 4.9, 'Carlos Díaz': 2.7};
  final _servicio = _ReunionDemo();

  double get _promedio => _notas.values.reduce((a, b) => a + b) / _notas.length;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const PageHeader(
        title: 'Hola, Profe Demo',
        subtitle: 'Docente · 2 cursos de ejemplo',
        leading: Icon(PhosphorIconsFill.chalkboardTeacher, size: 28),
      ),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: StatCard(icon: PhosphorIconsRegular.books, value: '2', label: 'Cursos', color: t.chart[0])),
        const SizedBox(width: 10),
        Expanded(child: StatCard(icon: PhosphorIconsRegular.student, value: '${_notas.length}', label: 'Estudiantes', color: t.chart[4])),
        const SizedBox(width: 10),
        Expanded(child: StatCard(icon: PhosphorIconsRegular.clipboardText, value: '3', label: 'Por calificar', color: t.warning)),
      ]),
      const SizedBox(height: AppTokens.sectionGap),
      const SectionTitle('Reunión virtual', icon: PhosphorIconsRegular.videoCamera,
          subtitle: 'Prueba iniciar una: es una simulación'),
      CourseMeetingCard(
        courseId: 9001,
        puedeGestionar: true,
        cadaSegundos: 3600,
        servicio: _servicio,
        abrirEnlace: (_) async {
          _aviso(context, 'En la app real se abre la videollamada para ti y tus estudiantes.');
          return true;
        },
      ),
      const SizedBox(height: AppTokens.sectionGap),
      const SectionTitle('Libreta de calificaciones', icon: PhosphorIconsRegular.chartBar,
          subtitle: 'Mueve las notas y mira cómo cambia el promedio'),
      const SizedBox(height: 10),
      AppCard(
        blur: false,
        child: Column(children: [
          Row(children: [
            ScoreRing(value: _promedio, size: 84, caption: 'Promedio'),
            const SizedBox(width: 14),
            Expanded(
              child: Text('Programación I — Parcial 1',
                  style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 8),
          for (final e in _notas.entries)
            Semantics(
              label: 'Nota de ${e.key}: ${e.value.toStringAsFixed(1)}',
              child: Row(children: [
                Expanded(flex: 3, child: Text(e.key, style: GoogleFonts.poppins(fontSize: 13))),
                Expanded(
                  flex: 4,
                  child: Slider(
                    value: e.value, min: 0, max: 5, divisions: 50,
                    onChanged: (v) => setState(() => _notas[e.key] = v),
                  ),
                ),
                SizedBox(
                  width: 34,
                  child: Text(e.value.toStringAsFixed(1),
                      style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700)),
                ),
              ]),
            ),
        ]),
      ),
      const SizedBox(height: AppTokens.sectionGap),
      const SectionTitle('Mis cursos', icon: PhosphorIconsRegular.books),
      const SizedBox(height: 8),
      for (var i = 0; i < 2; i++)
        CourseCard(course: _cursos[i], index: i, onTap: () => _verCurso(context, _cursos[i])),
    ]);
  }
}

class _DemoAdmin extends StatelessWidget {
  const _DemoAdmin();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const PageHeader(
        title: 'Panel Administrador',
        subtitle: 'Vista general de ejemplo',
        leading: Icon(PhosphorIconsFill.shieldCheck, size: 28),
      ),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: StatCard(icon: PhosphorIconsRegular.graduationCap, value: '120', label: 'Estudiantes', color: t.chart[0])),
        const SizedBox(width: 10),
        Expanded(child: StatCard(icon: PhosphorIconsRegular.chalkboardTeacher, value: '8', label: 'Docentes', color: t.chart[4])),
        const SizedBox(width: 10),
        Expanded(child: StatCard(icon: PhosphorIconsRegular.books, value: '6', label: 'Materias', color: t.success)),
      ]),
      const SizedBox(height: AppTokens.sectionGap),
      const SectionTitle('Estudiantes por materia', icon: PhosphorIconsRegular.chartBar),
      const SizedBox(height: 10),
      AppCard(
        blur: false,
        child: BarList(
          color: t.chart[0],
          rotateColors: true,
          items: const [
            BarItem('Matemáticas Aplicadas', 38),
            BarItem('Programación I', 32),
            BarItem('Comunicación Oral y Escrita', 27),
            BarItem('Física General', 23),
          ],
        ),
      ),
      const SizedBox(height: AppTokens.sectionGap),
      const SectionTitle('Qué puede hacer el Admin', icon: PhosphorIconsRegular.lightning),
      const SizedBox(height: 10),
      for (final f in const [
        (PhosphorIconsFill.userGear, 'Gestionar usuarios', 'Crear, editar y asignar roles a estudiantes y docentes.'),
        (PhosphorIconsFill.books, 'Gestionar materias', 'Crear cursos y asignarles docente y estudiantes.'),
        (PhosphorIconsFill.chartPolar, 'Evaluación docente', 'Abrir periodos, elegir participantes y ver resultados.'),
        (PhosphorIconsFill.buildings, 'Información de la universidad', 'Editar lo que ven los invitados: programas, matrícula y contacto.'),
      ])
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: AppCard(
            blur: false,
            child: Row(children: [
              Icon(f.$1, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(f.$2, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700)),
                  Text(f.$3, style: GoogleFonts.poppins(fontSize: 12, color: t.muted, height: 1.35)),
                ]),
              ),
            ]),
          ),
        ),
    ]);
  }
}
