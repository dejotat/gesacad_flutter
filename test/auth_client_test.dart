import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gesacad/config/api_config.dart';
import 'package:gesacad/services/api_service.dart';
import 'package:gesacad/services/auth_client.dart';
import 'package:gesacad/services/auth_service.dart';
import 'package:gesacad/services/connectivity_service.dart';

/// Token de prueba con los datos indicados (firma ficticia: el cliente no la verifica).
String _jwt({required int iat, required int exp, String rol = 'Student'}) {
  String b64(Object o) => base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  return '${b64({'alg': 'HS256', 'typ': 'JWT'})}.${b64({'sub': 4, 'rol': rol, 'iat': iat, 'exp': exp})}.firma';
}

int _ahora() => DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ConnectivityService.instance = ConnectivityService.test(
        probe: () async => true, interval: const Duration(hours: 1));
    await AuthService().saveSession(4, 'ana', 'Student', token: _jwt(iat: _ahora(), exp: _ahora() + 3600));
  });
  tearDown(() => ConnectivityService.instance.dispose());

  group('AuthService: token', () {
    test('lee iat y exp del token sin verificar la firma', () {
      final t = _jwt(iat: 1800000000, exp: 1800003600);
      expect(AuthService.issuedAtOf(t), DateTime.utc(2027, 1, 15, 8));
      expect(AuthService.expiryOf(t)!.difference(AuthService.issuedAtOf(t)!), const Duration(hours: 1));
      expect(AuthService.decodePayload(t)!['rol'], 'Student');
    });

    test('un token ilegible no rompe nada', () {
      for (final malo in [null, '', 'a.b', 'a.b.c', 'x.@@@.z']) {
        expect(AuthService.decodePayload(malo), isNull);
        expect(AuthService.expiryOf(malo), isNull);
      }
    });

    test('saveSession guarda el token en memoria y en disco; clearSession lo borra', () async {
      expect(AuthService.currentToken, isNotNull);
      expect(AuthService.legacySession, isFalse);
      expect(AuthService.tokenExpired, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('authToken'), AuthService.currentToken);

      await AuthService().clearSession();
      expect(AuthService.currentToken, isNull);
      expect(prefs.getString('authToken'), isNull);
    });

    test('un token vencido se detecta', () async {
      await AuthService().saveSession(4, 'ana', 'Student', token: _jwt(iat: _ahora() - 7200, exp: _ahora() - 60));
      expect(AuthService.tokenExpired, isTrue);
    });

    test('una sesión abierta contra un servidor antiguo (sin token) se marca como heredada', () async {
      await AuthService().saveSession(4, 'ana', 'Student');
      expect(AuthService.legacySession, isTrue);
      await AuthService.loadToken();
      expect(AuthService.legacySession, isTrue, reason: 'se recuerda al reiniciar la app');
    });

    test('expireSession quita solo el token y conserva los datos de la sesión', () async {
      await AuthService().expireSession();
      expect(AuthService.currentToken, isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('userId'), 4);
      expect(prefs.getString('userRol'), 'Student');
    });

    test('refreshIfNeeded renueva un token con más de 12 h, y solo entonces', () async {
      var llamadas = 0;
      final nuevo = _jwt(iat: _ahora(), exp: _ahora() + 7 * 86400);
      await http.runWithClient(() async {
        // Reciente: no pide nada
        expect(await AuthService().refreshIfNeeded(), isFalse);
        expect(llamadas, 0);
        // Con 13 h de antigüedad: renueva
        await AuthService().saveSession(4, 'ana', 'Student',
            token: _jwt(iat: _ahora() - 13 * 3600, exp: _ahora() + 3600));
        expect(await AuthService().refreshIfNeeded(), isTrue);
        expect(llamadas, 1);
        expect(AuthService.currentToken, nuevo);
        // Vencido: no lo intenta
        await AuthService().saveSession(4, 'ana', 'Student',
            token: _jwt(iat: _ahora() - 90000, exp: _ahora() - 60));
        expect(await AuthService().refreshIfNeeded(), isFalse);
        expect(llamadas, 1);
      }, () => MockClient((req) async {
            llamadas++;
            expect(req.url.path, '/auth/refresh');
            return http.Response(jsonEncode({'token': nuevo}), 200);
          }));
    });

    test('refreshIfNeeded tolera falta de red o rechazo sin perder el token', () async {
      final viejo = _jwt(iat: _ahora() - 13 * 3600, exp: _ahora() + 3600);
      await AuthService().saveSession(4, 'ana', 'Student', token: viejo);
      await http.runWithClient(() async {
        expect(await AuthService().refreshIfNeeded(), isFalse);
        expect(AuthService.currentToken, viejo);
      }, () => MockClient((_) async => throw http.ClientException('sin red')));
      await http.runWithClient(() async {
        expect(await AuthService().refreshIfNeeded(), isFalse);
        expect(AuthService.currentToken, viejo);
      }, () => MockClient((_) async => http.Response('{}', 401)));
    });
  });

  group('AuthClient', () {
    final api = Uri.parse('${ApiConfig.baseUrl}/courses/getCourses');

    test('añade el token SOLO al servidor de GESACAD', () async {
      final vistos = <Uri, String?>{};
      final guard = SessionGuard.instance;
      final c = AuthClient(
        inner: MockClient((req) async {
          vistos[req.url] = req.headers['Authorization'];
          return http.Response('{}', 200);
        }),
        guard: guard,
      );
      await c.get(api);
      await c.get(Uri.parse('https://res.cloudinary.com/demo/foto.jpg'));
      await c.get(Uri.parse('https://evil.example/robar'));
      await c.get(Uri.parse('${ApiConfig.baseUrl}.evil.example/x')); // dominio parecido
      expect(vistos[api], 'Bearer ${AuthService.currentToken}');
      expect(vistos[Uri.parse('https://res.cloudinary.com/demo/foto.jpg')], isNull);
      expect(vistos[Uri.parse('https://evil.example/robar')], isNull);
      expect(vistos[Uri.parse('${ApiConfig.baseUrl}.evil.example/x')], isNull, reason: 'otro origen aunque se parezca');
    });

    test('sin sesión no envía cabecera de autorización', () async {
      await AuthService().clearSession();
      String? cabecera = 'sin-llamar';
      final c = AuthClient(inner: MockClient((req) async { cabecera = req.headers['Authorization']; return http.Response('{}', 200); }));
      await c.get(api);
      expect(cabecera, isNull);
    });

    test('no pisa una cabecera Authorization que ya traiga la petición', () async {
      String? cabecera;
      final c = AuthClient(inner: MockClient((req) async { cabecera = req.headers['Authorization']; return http.Response('{}', 200); }));
      await c.get(api, headers: {'Authorization': 'Bearer otro'});
      expect(cabecera, 'Bearer otro');
    });

    test('un 401 de sesión vencida avisa UNA vez y devuelve el cuerpo intacto', () async {
      var avisos = 0;
      final guard = SessionGuard.instance..alInvalidarse = (_) => avisos++;
      final c = AuthClient(
        inner: MockClient((_) async => http.Response(
            jsonEncode({'error': 'TOKEN_EXPIRADO', 'message': 'Tu sesión expiró.'}), 401)),
        guard: guard,
      );
      // Ráfaga de peticiones que fallan a la vez: un solo aviso.
      final rs = await Future.wait([c.get(api), c.get(api), c.get(api)]);
      for (final r in rs) {
        expect(r.statusCode, 401);
        expect(jsonDecode(r.body)['message'], 'Tu sesión expiró.');
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(avisos, 1);
      expect(AuthService.currentToken, isNull, reason: 'el token vencido se descarta');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('userId'), 4, reason: 'los datos de la sesión se conservan');
    });

    test('no se confunde: un 401 del login, un 403 o un 401 de otra causa no cierran la sesión', () async {
      var avisos = 0;
      final guard = SessionGuard.instance..alInvalidarse = (_) => avisos++;
      Future<void> prueba(Uri url, int status, Map<String, dynamic> cuerpo) async {
        final c = AuthClient(inner: MockClient((_) async => http.Response(jsonEncode(cuerpo), status)), guard: guard);
        await c.get(url);
      }
      await prueba(Uri.parse('${ApiConfig.baseUrl}/auth/login'), 401, {'error': 'TOKEN_EXPIRADO'});
      await prueba(Uri.parse('${ApiConfig.baseUrl}/users/ana/clave'), 401, {'error': 'CREDENCIALES_INVALIDAS'});
      await prueba(api, 403, {'error': 'SIN_PERMISO'});
      await prueba(api, 401, {'error': 'OTRA_COSA'});
      await prueba(Uri.parse('https://res.cloudinary.com/x'), 401, {'error': 'TOKEN_EXPIRADO'});
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(avisos, 0);
      expect(AuthService.currentToken, isNotNull);
    });

    test('un 401 sin cuerpo JSON no lanza ni cierra la sesión', () async {
      var avisos = 0;
      final guard = SessionGuard.instance..alInvalidarse = (_) => avisos++;
      final c = AuthClient(inner: MockClient((_) async => http.Response('<html>no</html>', 401)), guard: guard);
      expect((await c.get(api)).statusCode, 401);
      expect(avisos, 0);
    });
  });

  group('ApiService.login', () {
    test('usa POST con la contraseña en el cuerpo (nunca en la URL)', () async {
      late http.Request visto;
      await http.runWithClient(() async {
        final r = await ApiService().login('ana', 'Clave#Secreta1');
        expect(r['response'], 'LOGIN_SUCCESFULLY');
        expect(r['token'], 'tok');
      }, () => MockClient((req) async {
            visto = req;
            return http.Response(jsonEncode({'token': 'tok', 'id': 4, 'rol': 'Student', 'name': 'ana', 'response': 'LOGIN_SUCCESFULLY'}), 200);
          }));
      expect(visto.method, 'POST');
      expect(visto.url.path, '/auth/login');
      expect(visto.url.toString().contains('Clave'), isFalse, reason: 'la contraseña no va en la URL');
      expect(jsonDecode(visto.body), {'username': 'ana', 'password': 'Clave#Secreta1'});
    });

    test('credenciales inválidas y demasiados intentos llegan como datos, no como excepción', () async {
      await http.runWithClient(() async {
        final r = await ApiService().login('ana', 'mala');
        expect(r['response'], 'USER_OR_PASS_INVALID');
      }, () => MockClient((_) async => http.Response(jsonEncode({'response': 'USER_OR_PASS_INVALID'}), 401)));
      await http.runWithClient(() async {
        final r = await ApiService().login('ana', 'mala');
        expect(r['response'], 'TOO_MANY_ATTEMPTS');
        expect(r['message'], contains('15 min'));
      }, () => MockClient((_) async => http.Response(
          jsonEncode({'response': 'TOO_MANY_ATTEMPTS', 'message': 'Vuelve a intentarlo en 15 min.'}), 429)));
    });

    test('contra un servidor antiguo (404 sin JSON) recurre al inicio de sesión anterior', () async {
      final llamadas = <String>[];
      await http.runWithClient(() async {
        final r = await ApiService().login('ana', 'c/l?a#v%e');
        expect(r['response'], 'LOGIN_SUCCESFULLY');
        expect(r.containsKey('token'), isFalse);
      }, () => MockClient((req) async {
            llamadas.add('${req.method} ${req.url.path}');
            if (req.method == 'POST') return http.Response('<html>Cannot POST /auth/login</html>', 404);
            return http.Response(jsonEncode({'id': 4, 'rol': 'Student', 'name': 'ana', 'response': 'LOGIN_SUCCESFULLY'}), 200);
          }));
      expect(llamadas.first, 'POST /auth/login');
      expect(llamadas.last.startsWith('GET /users/ana/'), isTrue);
      expect(llamadas.last.contains('%2F'), isTrue, reason: 'los caracteres especiales se codifican');
    });

    test('un 404 con JSON del servidor nuevo NO activa el respaldo', () async {
      var gets = 0;
      await http.runWithClient(() async {
        final r = await ApiService().login('ana', 'x');
        expect(r['error'], 'ALGO');
      }, () => MockClient((req) async {
            if (req.method == 'GET') gets++;
            return http.Response(jsonEncode({'error': 'ALGO'}), 404);
          }));
      expect(gets, 0);
    });

    test('sin red lanza una excepción de red (la pantalla la explica)', () async {
      await http.runWithClient(() async {
        await expectLater(ApiService().login('ana', 'x'), throwsA(isA<http.ClientException>()));
      }, () => MockClient((_) async => throw http.ClientException('sin red')));
    });
  });

  group('ApiService: gestión de usuarios muestra el mensaje del servidor', () {
    test('contraseña débil o usuario repetido lanzan ApiMessageException con su texto', () async {
      await http.runWithClient(() async {
        await expectLater(
          ApiService().addUser('nuevo', 'abc', 'Student'),
          throwsA(isA<ApiMessageException>()
              .having((e) => e.message, 'message', 'La contraseña debe tener al menos un símbolo (!@#\$%...).')
              .having((e) => e.status, 'status', 400)),
        );
      }, () => MockClient((_) async => http.Response(
          jsonEncode({'error': 'PASSWORD_DEBIL', 'message': 'La contraseña debe tener al menos un símbolo (!@#\$%...).'}), 400)));
      await http.runWithClient(() async {
        await expectLater(ApiService().deleteUser(1), throwsA(isA<ApiMessageException>().having((e) => e.status, 'status', 409)));
        await expectLater(ApiService().editUser(1, 'x', '', 'Admin'), throwsA(isA<ApiMessageException>()));
      }, () => MockClient((_) async => http.Response(
          jsonEncode({'error': 'NO_PUEDES_ELIMINARTE', 'message': 'No puedes eliminar tu propia cuenta.'}), 409)));
    });

    test('con éxito devuelven el texto de siempre', () async {
      await http.runWithClient(() async {
        expect(await ApiService().addUser('nuevo', 'Valida#2026x', 'Student'), 'USER_ADD_SUCCESSFULLY');
        expect(await ApiService().editUser(1, 'nuevo', '', 'Student'), 'USER_EDIT_SUCCESSFULLY');
      }, () => MockClient((req) async => http.Response(
          jsonEncode(req.method == 'POST' ? 'USER_ADD_SUCCESSFULLY' : 'USER_EDIT_SUCCESSFULLY'), 200)));
    });
  });
}
