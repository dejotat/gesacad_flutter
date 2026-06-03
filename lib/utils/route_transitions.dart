import 'package:flutter/material.dart';

/// Transición horizontal personalizada para navegación entre pantallas.
///
/// La pantalla nueva entra deslizándose desde la derecha.
/// Al hacer pop (regresar), Flutter invierte automáticamente la transición
/// → la pantalla sale hacia la derecha y la anterior vuelve desde la izquierda.
///
/// Uso: reemplazar [MaterialPageRoute] por [slideRoute]:
///   Navigator.push(context, slideRoute(const MiPantalla()));
PageRouteBuilder<T> slideRoute<T>(Widget page) => PageRouteBuilder<T>(
      pageBuilder: (_, __, ___) => page,
      transitionDuration:        const Duration(milliseconds: 280),
      reverseTransitionDuration: const Duration(milliseconds: 280),
      transitionsBuilder: (_, animation, __, child) {
        // Pantalla nueva: entra desde la derecha (x=1 → x=0)
        final slide = Tween<Offset>(
          begin: const Offset(1.0, 0),
          end:   Offset.zero,
        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeInOutCubic));

        // Fade suave en la primera mitad de la transición (0% → 50%)
        final fade = Tween<double>(begin: 0.0, end: 1.0)
            .animate(CurvedAnimation(
                parent: animation,
                curve: const Interval(0.0, 0.5, curve: Curves.easeIn)));

        return SlideTransition(
          position: slide,
          child: FadeTransition(opacity: fade, child: child),
        );
      },
    );
