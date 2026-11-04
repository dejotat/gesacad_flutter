import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../config/app_tokens.dart';

/// Menú de cuenta de la barra superior (los tres dashboards lo comparten).
///
/// Cabecera con la foto (o las iniciales), el nombre y el rol; debajo las acciones con un
/// ícono tintado y una línea que explica qué hace cada una; y "Cerrar sesión" separado y en
/// rojo para que no se toque por accidente. Se despliega justo bajo el botón, con animación,
/// y se maneja con teclado y lector de pantalla (CU-07).
class MenuCuenta extends StatelessWidget {
  const MenuCuenta({
    super.key,
    required this.nombre,
    required this.rol,
    required this.onPerfil,
    required this.onAjustes,
    required this.onSalir,
    this.foto,
  });

  final String nombre;

  /// 'Admin', 'Teacher' o 'Student'.
  final String rol;
  final Uint8List? foto;
  final VoidCallback onPerfil;
  final VoidCallback onAjustes;
  final VoidCallback onSalir;

  static const _perfil = 'perfil';
  static const _ajustes = 'ajustes';
  static const _salir = 'salir';

  /// "Ana María Gómez" → "AM"; vacío → "?".
  static String iniciales(String nombre) {
    final partes = nombre.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (partes.isEmpty) return '?';
    if (partes.length == 1) return partes.first.substring(0, partes.first.length >= 2 ? 2 : 1).toUpperCase();
    return '${partes[0][0]}${partes[1][0]}'.toUpperCase();
  }

  static String nombreDelRol(String rol) => switch (rol) {
        'Admin' => 'Administrador',
        'Teacher' => 'Docente',
        'Student' => 'Estudiante',
        _ => rol,
      };

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Cuenta y opciones',
      position: PopupMenuPosition.under,
      offset: const Offset(0, 6),
      elevation: 14,
      shadowColor: Colors.black.withValues(alpha: 0.35),
      padding: EdgeInsets.zero,
      menuPadding: const EdgeInsets.symmetric(vertical: 6),
      constraints: const BoxConstraints(minWidth: 268, maxWidth: 300),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: context.tokens.glassBorder),
      ),
      popUpAnimationStyle: const AnimationStyle(
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeIn,
        duration: Duration(milliseconds: 240),
        reverseDuration: Duration(milliseconds: 140),
      ),
      icon: const Icon(PhosphorIconsRegular.dotsThreeVertical),
      onSelected: (v) {
        switch (v) {
          case _perfil: onPerfil();
          case _ajustes: onAjustes();
          case _salir: onSalir();
        }
      },
      itemBuilder: (ctx) => [
        _Cabecera(nombre: nombre, rol: nombreDelRol(rol), foto: foto),
        const PopupMenuDivider(height: 8),
        _opcion(ctx, valor: _perfil, icono: PhosphorIconsRegular.userCircle, titulo: 'Mi perfil',
            detalle: 'Tus datos y tu foto'),
        _opcion(ctx, valor: _ajustes, icono: PhosphorIconsRegular.gear, titulo: 'Ajustes',
            detalle: 'Tema, voz y accesibilidad'),
        const PopupMenuDivider(height: 8),
        _opcion(ctx, valor: _salir, icono: PhosphorIconsRegular.signOut, titulo: 'Cerrar sesión',
            detalle: 'Salir de esta cuenta', peligro: true),
      ],
    );
  }

  PopupMenuItem<String> _opcion(
    BuildContext ctx, {
    required String valor,
    required IconData icono,
    required String titulo,
    required String detalle,
    bool peligro = false,
  }) {
    final t = ctx.tokens;
    final color = peligro ? t.danger : Theme.of(ctx).colorScheme.primary;
    return PopupMenuItem<String>(
      value: valor,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      height: 56,
      child: Semantics(
        label: '$titulo. $detalle',
        excludeSemantics: true,
        button: true,
        child: Row(children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icono, size: 20, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(titulo,
                  style: GoogleFonts.poppins(
                      fontSize: 13.5, fontWeight: FontWeight.w600, color: peligro ? t.danger : null)),
              Text(detalle,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(fontSize: 11.5, color: t.muted)),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Cabecera del menú: quién tiene la sesión abierta. No es seleccionable.
class _Cabecera extends PopupMenuEntry<String> {
  const _Cabecera({required this.nombre, required this.rol, this.foto});
  final String nombre;
  final String rol;
  final Uint8List? foto;

  @override
  double get height => 76;

  @override
  bool represents(String? value) => false;

  @override
  State<_Cabecera> createState() => _CabeceraState();
}

class _CabeceraState extends State<_Cabecera> {
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final primario = Theme.of(context).colorScheme.primary;
    final nombre = widget.nombre.trim().isEmpty ? 'Tu cuenta' : widget.nombre.trim();
    return Semantics(
      header: true,
      label: 'Sesión de $nombre, ${widget.rol}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Row(children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: AppTokens.gradientOf(primario), begin: Alignment.topLeft, end: Alignment.bottomRight),
              boxShadow: [BoxShadow(color: primario.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 3))],
              image: widget.foto == null ? null : DecorationImage(image: MemoryImage(widget.foto!), fit: BoxFit.cover),
            ),
            alignment: Alignment.center,
            child: widget.foto != null
                ? null
                : Text(MenuCuenta.iniciales(widget.nombre),
                    style: GoogleFonts.poppins(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(nombre,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(fontSize: 14.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
                decoration: BoxDecoration(
                  color: primario.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(widget.rol,
                    style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w700, color: primario)),
              ),
            ]),
          ),
          Icon(PhosphorIconsFill.shieldCheck, size: 18, color: t.success),
        ]),
      ),
    );
  }
}
