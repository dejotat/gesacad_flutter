import 'package:flutter/material.dart';

/// Llaves globales de la app. Permiten mostrar avisos y paneles desde widgets
/// que viven *encima* del Navigator (p. ej. el banner de conexión).
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> appMessengerKey =
    GlobalKey<ScaffoldMessengerState>();
