import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/course_model.dart';
import '../../models/notification_models.dart';
import '../../services/api_service.dart';
import '../../utils/route_transitions.dart';
import '../evaluation/admin_evaluations_screen.dart';
import '../evaluation/student_evaluations_screen.dart';
import '../evaluation/teacher_evaluation_screen.dart';
import '../student/activity_detail_screen.dart';
import '../student/student_course_content.dart';
import '../teacher/teacher_course_content.dart';

/// Lleva al usuario a lo que originó una notificación o un evento del calendario
/// (CU-11/CU-12): la actividad, el curso, la reunión o la evaluación, según su rol.
///
/// [refType]: `activity`, `course`, `meeting` o `evaluation`. Devuelve `true` si navegó.
/// Si lo referido ya no existe (p. ej. una actividad eliminada) lo explica con un
/// aviso en vez de fallar.
Future<bool> abrirReferencia(
  BuildContext context, {
  required String? refType,
  int? refId,
  int? courseId,
  String? courseName,
  String? courseCode,
  int? courseImg,
  required int userId,
  required String rol,
}) async {
  final nav = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);

  void aviso(String texto) => messenger.showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(texto, style: GoogleFonts.poppins(color: Colors.white)),
      ));

  Future<bool> abrirCurso() async {
    if (courseId == null || rol == 'Admin') return false;
    final c = CourseModel(
      id: courseId,
      name: courseName ?? 'Curso',
      courseCode: courseCode ?? '',
      imgCourse: courseImg ?? 1,
    );
    await nav.push(slideRoute(rol == 'Teacher'
        ? TeacherCourseContent(course: c, teacherId: userId)
        : StudentCourseContent(course: c, userId: userId)));
    return true;
  }

  switch (refType) {
    case 'activity':
      if (rol == 'Student' && refId != null) {
        ActivityDetailScreen? destino;
        try {
          final a = await ApiService().getActivityContent(refId, userId, 'Student');
          if (a != null) destino = ActivityDetailScreen(activity: a, userId: userId);
        } catch (_) {}
        if (destino == null) {
          aviso('Esa actividad ya no está disponible.');
          return false;
        }
        await nav.push(slideRoute(destino));
        return true;
      }
      return abrirCurso();
    case 'course':
    case 'meeting':
      return abrirCurso();
    case 'evaluation':
      final pantalla = switch (rol) {
        'Admin' => AdminEvaluationsScreen(adminId: userId),
        'Teacher' => TeacherEvaluationScreen(teacherId: userId),
        _ => StudentEvaluationsScreen(studentId: userId),
      };
      await nav.push(slideRoute(pantalla));
      return true;
    default:
      return false;
  }
}

/// Atajo para una [AppNotif].
Future<bool> abrirNotificacion(
  BuildContext context,
  AppNotif n, {
  required int userId,
  required String rol,
}) =>
    abrirReferencia(
      context,
      refType: n.refType,
      refId: n.refId,
      courseId: n.courseId,
      courseName: n.courseName,
      courseCode: n.courseCode,
      courseImg: n.courseImg,
      userId: userId,
      rol: rol,
    );
