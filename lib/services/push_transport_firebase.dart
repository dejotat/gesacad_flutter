import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'push_service.dart';

/// Implementación real de [PushTransport] con Firebase Cloud Messaging. Es el ÚNICO archivo
/// que importa los paquetes de Firebase.
///
/// Firebase se inicializa con las opciones recibidas por `--dart-define` (no hace falta
/// `google-services.json`). Los avisos con la app cerrada o en segundo plano los muestra el
/// propio sistema: el servidor los envía con carga `notification`, así no hay que ejecutar
/// código de la app para mostrarlos.
///
/// Token: se usa `getToken()` / `onTokenRefresh` / `deleteToken()` (el token de registro clásico
/// de FCM, que es el que acepta `messages:send` de la API HTTP v1). `firebase_messaging` 17 los
/// marca como obsoletos a favor de `register()`, que entrega un Installation ID para "envío
/// directo": es otro identificador y no se ha verificado que el servidor lo acepte. Si algún día
/// el paquete retira los antiguos, migrar cambiando AQUÍ y adaptando `Backend/push.js`.
class FirebasePushTransport implements PushTransport {
  FirebaseMessaging get _fcm => FirebaseMessaging.instance;

  @override
  Future<void> init() async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: PushConfig.apiKey,
          appId: PushConfig.appId,
          messagingSenderId: PushConfig.senderId,
          projectId: PushConfig.projectId,
        ),
      );
    }
  }

  PermisoPush _permiso(AuthorizationStatus s) => switch (s) {
        AuthorizationStatus.authorized || AuthorizationStatus.provisional => PermisoPush.concedido,
        AuthorizationStatus.denied || AuthorizationStatus.deniedPermanently => PermisoPush.denegado,
        AuthorizationStatus.notDetermined => PermisoPush.sinDecidir,
      };

  @override
  Future<PermisoPush> permiso() async => _permiso((await _fcm.getNotificationSettings()).authorizationStatus);

  @override
  Future<PermisoPush> solicitarPermiso() async => _permiso((await _fcm.requestPermission()).authorizationStatus);

  @override
  // ignore: deprecated_member_use
  Future<String?> token() => _fcm.getToken();

  @override
  // ignore: deprecated_member_use
  Stream<String> get tokenRenovado => _fcm.onTokenRefresh;

  PushMensaje _mensaje(RemoteMessage m) => PushMensaje(
        title: m.notification?.title ?? m.data['title']?.toString(),
        body: m.notification?.body ?? m.data['body']?.toString(),
        data: m.data.map((k, v) => MapEntry(k, v.toString())),
      );

  @override
  Stream<PushMensaje> get enPrimerPlano => FirebaseMessaging.onMessage.map(_mensaje);

  @override
  Stream<PushMensaje> get alAbrir => FirebaseMessaging.onMessageOpenedApp.map(_mensaje);

  @override
  Future<PushMensaje?> mensajeInicial() async {
    final m = await _fcm.getInitialMessage();
    return m == null ? null : _mensaje(m);
  }

  @override
  // ignore: deprecated_member_use
  Future<void> borrarToken() => _fcm.deleteToken();
}
