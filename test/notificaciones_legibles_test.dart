import 'package:flutter_test/flutter_test.dart';
import 'package:gesacad/models/notification_models.dart';

void main() {
  group('cuerpoLegible: el texto técnico de auditoría nunca llega al usuario', () {
    test('baja de usuario (userId y userid, con o sin espacios en el nombre)', () {
      expect(cuerpoLegible(NotifType.system, 'Usuario eliminado del sistema', 'userId=34 username=manuel rol=Student'),
          'Se eliminó la cuenta «manuel» (estudiante).');
      expect(cuerpoLegible(NotifType.system, 'Usuario eliminado del sistema', 'userid=41 username=carlos zuñiga rol=Teacher'),
          'Se eliminó la cuenta «carlos zuñiga» (docente).');
    });

    test('alta de usuario y administrador inicial', () {
      expect(cuerpoLegible(NotifType.system, 'Nuevo usuario registrado', 'username=ana rol=Admin'),
          'Se creó la cuenta «ana» (administrador).');
      expect(cuerpoLegible(NotifType.system, 'Nuevo usuario registrado', 'username=admin rol=Admin (administrador inicial)'),
          'Se creó la cuenta «admin» (administrador).');
    });

    test('datos desconocidos no muestran signos de interrogación', () {
      expect(cuerpoLegible(NotifType.system, 'Usuario eliminado del sistema', 'userId=5 username=? rol=?'),
          'Se eliminó una cuenta.');
    });

    test('lo que ya viene en lenguaje claro, o es de otro tipo, no se toca', () {
      const clara = "El usuario 'ana' solicita restablecer su contraseña.";
      expect(cuerpoLegible(NotifType.system, 'Solicitud de recuperación de contraseña', clara), clara);
      expect(cuerpoLegible(NotifType.system, 'Usuario eliminado del sistema', 'Se eliminó la cuenta «juan» (estudiante).'),
          'Se eliminó la cuenta «juan» (estudiante).');
      expect(cuerpoLegible(NotifType.activity, 'Nueva actividad: X', 'username=a rol=b'), 'username=a rol=b',
          reason: 'solo se reescriben avisos de sistema');
    });
  });

  group('AppNotif', () {
    Map<String, dynamic> json(String titulo, String cuerpo, {String tipo = 'system'}) => {
          'id': 1, 'type': tipo, 'title': titulo, 'body': cuerpo,
          'createdAt': '2026-11-09T12:00:00Z', 'read': false,
        };

    test('fromJson repara el cuerpo técnico (servidor antiguo o copia guardada)', () {
      final n = AppNotif.fromJson(json('Usuario eliminado del sistema', 'userId=38 username=juan rol=Student'));
      expect(n.body, 'Se eliminó la cuenta «juan» (estudiante).');
      // Y al guardarla de nuevo en la copia local queda ya en claro.
      expect(n.toJson()['body'], 'Se eliminó la cuenta «juan» (estudiante).');
    });

    test('cada evento de sistema tiene su etiqueta, ícono y color propios', () {
      final eliminado = AppNotif.fromJson(json('Usuario eliminado del sistema', 'x'));
      final creado = AppNotif.fromJson(json('Nuevo usuario registrado', 'x'));
      final clave = AppNotif.fromJson(json('Solicitud de recuperación de contraseña', 'x'));
      final otro = AppNotif.fromJson(json('Mantenimiento', 'x'));
      expect(eliminado.evento, EventoSistema.usuarioEliminado);
      expect(creado.evento, EventoSistema.usuarioCreado);
      expect(clave.evento, EventoSistema.restablecerClave);
      expect(otro.evento, EventoSistema.otro);
      expect({eliminado.icono, creado.icono, clave.icono, otro.icono}.length, 4, reason: 'íconos distintos');
      expect({eliminado.colorAviso, creado.colorAviso, clave.colorAviso}.length, 3, reason: 'colores distintos');
      expect(eliminado.etiqueta, 'Usuarios');
      expect(clave.etiqueta, 'Seguridad');
      expect(otro.etiqueta, 'Sistema');
    });

    test('los avisos que no son de sistema conservan su presentación por tipo', () {
      final a = AppNotif.fromJson(json('Nueva actividad: Taller', 'En Cálculo.', tipo: 'activity'));
      expect(a.evento, EventoSistema.otro);
      expect(a.etiqueta, NotifType.activity.label);
      expect(a.icono, NotifType.activity.icon);
      expect(a.colorAviso, NotifType.activity.color);
      expect(a.body, 'En Cálculo.');
    });
  });
}
