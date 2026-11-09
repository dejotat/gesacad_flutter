import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'motion_icon.dart';

/// Los tres roles de GESACAD.
enum RoleKind { student, teacher, admin }

/// Identidad visual de un rol: ícono, gesto de movimiento y color de gráficos. Es la ÚNICA fuente:
/// encabezados, indicadores, tarjetas del modo invitado y leyendas usan lo mismo, de modo que cada
/// rol se reconoce igual en toda la app.
///
/// El movimiento expresa el carácter del rol, sin ser caricaturesco:
/// * **Estudiante** → el birrete asiente con un leve cabeceo (`nod`).
/// * **Docente** → la pizarra flota con calma (`float`).
/// * **Administrador** → el escudo «respira», como algo que vigila con serenidad (`breathe`).
@immutable
class RoleStyle {
  const RoleStyle(this.kind, this.label, this.icon, this.motion, this.color, this.gradient);

  final RoleKind kind;
  final String label;
  final IconData icon;
  final IconMotion motion;

  /// Color del rol, FIJO (no depende del tema): cian, violeta y rosa. Validados juntos en
  /// cualquier combinación sobre superficies claras y oscuras (dona de usuarios por rol).
  final Color color;

  /// Degradado del rol, para tarjetas y cabeceras con texto blanco.
  final List<Color> gradient;
}

const _student = RoleStyle(RoleKind.student, 'Estudiante',
    PhosphorIconsRegular.graduationCap, IconMotion.nod, Color(0xFF0EA0BF), [Color(0xFF0B7F99), Color(0xFF19B8D8)]);
const _teacher = RoleStyle(RoleKind.teacher, 'Docente',
    PhosphorIconsRegular.chalkboardTeacher, IconMotion.float, Color(0xFF7F52EE), [Color(0xFF5B33C4), Color(0xFF8B5CF6)]);
const _admin = RoleStyle(RoleKind.admin, 'Administrador',
    PhosphorIconsRegular.shieldCheck, IconMotion.breathe, Color(0xFFD44378), [Color(0xFFB02D5E), Color(0xFFE0518F)]);

RoleStyle roleStyleOf(RoleKind kind) => switch (kind) {
      RoleKind.student => _student,
      RoleKind.teacher => _teacher,
      RoleKind.admin => _admin,
    };

/// Rol a partir del nombre que guarda el servidor ('Admin', 'Teacher', 'Student'); null si no se
/// reconoce.
RoleKind? roleKindFromName(String? rol) => switch (rol) {
      'Admin' => RoleKind.admin,
      'Teacher' => RoleKind.teacher,
      'Student' => RoleKind.student,
      _ => null,
    };

/// Degradado del rol a partir del nombre que guarda el servidor (Estudiante si no se reconoce).
List<Color> roleGradientFromName(String? rol) =>
    roleStyleOf(roleKindFromName(rol) ?? RoleKind.student).gradient;

/// Insignia circular del encabezado de un panel: la foto del usuario o, si no tiene, el ícono de
/// su rol con su movimiento y una onda suave. Va sobre el degradado oscuro del encabezado.
class RoleBadge extends StatelessWidget {
  const RoleBadge({super.key, required this.role, this.photo, this.size = 56});

  final RoleKind role;
  final Uint8List? photo;
  final double size;

  @override
  Widget build(BuildContext context) {
    final style = roleStyleOf(role);
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.38), width: 1.5),
        ),
        child: ClipOval(
          child: photo != null
              ? Image.memory(photo!, fit: BoxFit.cover)
              : Center(
                  child: MotionIcon(
                    style.icon,
                    color: Colors.white,
                    size: size * 0.5,
                    motion: style.motion,
                    halo: true,
                  ),
                ),
        ),
      ),
    );
  }
}
