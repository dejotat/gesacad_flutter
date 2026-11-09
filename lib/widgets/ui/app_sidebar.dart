import 'dart:typed_data';
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../config/app_tokens.dart';
import '../../services/settings_service.dart';
import '../../utils/route_transitions.dart';
import 'account_menu.dart';
import 'logo_backdrop.dart';
import 'role_style.dart';

/// Ancho desde el que el menú es una barra lateral fija. Por debajo (teléfono) es un cajón
/// (`Drawer`) con el MISMO contenido.
const double kSidebarMinWidth = 900;

/// Una entrada del menú lateral.
class NavItem {
  const NavItem({
    required this.id,
    required this.icon,
    required this.label,
    this.destination,
    this.action,
  });

  /// Identificador (para marcar la entrada activa).
  final String id;
  final IconData icon;
  final String label;

  /// Pantalla que abre. `null` = el inicio del panel (la pantalla de la que se parte).
  final Widget Function()? destination;

  /// Acción propia en lugar de abrir una pantalla (p. ej. desplazarse a «Mis cursos»).
  final VoidCallback? action;
}

/// Todo lo que el menú necesita saber: quién es el usuario, qué entradas tiene su ROL y cómo
/// salir. Los tres paneles (Estudiante, Docente, Administrador) arman uno y comparten el mismo
/// widget [AppSidebar]: solo cambian las entradas, no el diseño.
class SidebarNav {
  const SidebarNav({
    required this.rol,
    required this.nombre,
    required this.items,
    required this.onSalir,
    this.foto,
    this.alVolver,
  });

  /// 'Admin', 'Teacher' o 'Student'.
  final String rol;
  final String nombre;
  final Uint8List? foto;
  final List<NavItem> items;
  final VoidCallback onSalir;

  /// Se llama cuando el usuario regresa al inicio desde otra sección (para refrescar datos).
  final VoidCallback? alVolver;

  bool esAncho(BuildContext context) => MediaQuery.sizeOf(context).width >= kSidebarMinWidth;

  /// El cajón del `Scaffold` del inicio (solo en pantallas estrechas; en las anchas el menú es fijo).
  Widget? cajon(BuildContext context, String activo) => esAncho(context)
      ? null
      : Drawer(
          width: 290,
          child: AppSidebar(nav: this, activo: activo, enCajon: true),
        );

  /// Abre la entrada [it]. En pantallas anchas la nueva sección sigue mostrando el menú fijo.
  void ir(BuildContext context, NavItem it, {bool enCajon = false}) {
    final nav = Navigator.of(context);
    if (enCajon) nav.pop(); // cierra el cajón
    if (it.action != null) {
      // Primero se vuelve al inicio (si se estaba en otra sección) y luego se hace la acción.
      nav.popUntil((r) => r.isFirst);
      WidgetsBinding.instance.addPostFrameCallback((_) => it.action!());
      return;
    }
    if (it.destination == null) {
      nav.popUntil((r) => r.isFirst); // Inicio
      return;
    }
    final ancho = enCajon ? false : MediaQuery.sizeOf(context).width >= kSidebarMinWidth;
    if (ancho) {
      // Reemplaza la sección anterior (no se apilan) pero deja el inicio debajo.
      nav
          .pushAndRemoveUntil(_fundido(AppShell(nav: this, activo: it.id, child: it.destination!())),
              (r) => r.isFirst)
          .then((_) => alVolver?.call());
    } else {
      nav.push(slideRoute(it.destination!())).then((_) => alVolver?.call());
    }
  }

  static Route<void> _fundido(Widget page) => PageRouteBuilder<void>(
        pageBuilder: (_, __, ___) => page,
        transitionDuration: const Duration(milliseconds: 220),
        reverseTransitionDuration: const Duration(milliseconds: 180),
        transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
      );
}

/// Envuelve una pantalla con el menú lateral fijo (en pantallas anchas). En estrechas devuelve
/// la pantalla tal cual: el menú es el cajón del inicio.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.nav, required this.activo, required this.child});

  final SidebarNav nav;
  final String activo;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!nav.esAncho(context)) return child;
    return Material(
      type: MaterialType.transparency,
      child: Row(children: [
        AppSidebar(nav: nav, activo: activo),
        Expanded(child: child),
      ]),
    );
  }
}

/// Menú lateral: logo arriba en su propia sección, las entradas en columna (ícono + texto) con la
/// activa resaltada, y abajo el usuario y «Cerrar sesión». El calendario y las notificaciones NO
/// están aquí: viven en la barra superior de cada panel.
class AppSidebar extends StatelessWidget {
  const AppSidebar({super.key, required this.nav, required this.activo, this.enCajon = false});

  final SidebarNav nav;
  final String activo;
  final bool enCajon;

  static const double ancho = 268;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final cs = Theme.of(context).colorScheme;
    final tema = AppSettings.currentTheme.value;
    final acento = tema.isDark ? cs.secondary : cs.primary;

    final contenido = Column(children: [
      // ── Marca, en su propia sección ──
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
        child: Semantics(
          label: 'GESACAD',
          excludeSemantics: true,
          child: Row(children: [
            SizedBox(
              width: 44, height: 44,
              child: FittedBox(child: GesacadMark(size: 160, opacity: 0.95, color: acento, animate: false)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text('GESACAD',
                  style: GoogleFonts.poppins(
                      fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: cs.onSurface)),
            ),
          ]),
        ),
      ),
      Divider(height: 1, color: t.border),
      // ── Entradas ──
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
          children: [
            for (final it in nav.items)
              _Entrada(
                item: it,
                activa: it.id == activo,
                acento: acento,
                onTap: () => nav.ir(context, it, enCajon: enCajon),
              ),
          ],
        ),
      ),
      Divider(height: 1, color: t.border),
      // ── Usuario y salida ──
      _Usuario(nav: nav, acento: acento),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
        child: _Entrada(
          item: const NavItem(id: '_salir', icon: PhosphorIconsRegular.signOut, label: 'Cerrar sesión'),
          activa: false,
          acento: acento,
          peligro: true,
          onTap: () {
            if (enCajon) Navigator.of(context).pop();
            nav.onSalir();
          },
        ),
      ),
    ]);

    final panel = DecoratedBox(
      decoration: BoxDecoration(
        color: enCajon ? null : t.glass,
        border: enCajon ? null : Border(right: BorderSide(color: t.glassBorder)),
      ),
      child: SafeArea(child: contenido),
    );

    if (enCajon) return panel;
    return SizedBox(
      width: ancho,
      child: ClipRect(
        child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18), child: panel),
      ),
    );
  }
}

class _Entrada extends StatefulWidget {
  const _Entrada({
    required this.item,
    required this.activa,
    required this.acento,
    required this.onTap,
    this.peligro = false,
  });

  final NavItem item;
  final bool activa;
  final Color acento;
  final bool peligro;
  final VoidCallback onTap;

  @override
  State<_Entrada> createState() => _EntradaState();
}

class _EntradaState extends State<_Entrada> {
  bool _encima = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final cs = Theme.of(context).colorScheme;
    final color = widget.peligro ? t.danger : (widget.activa ? widget.acento : cs.onSurface.withValues(alpha: 0.8));
    final fondo = widget.activa
        ? LinearGradient(colors: [
            widget.acento.withValues(alpha: 0.26),
            widget.acento.withValues(alpha: 0.07),
          ])
        : null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Semantics(
        button: true,
        selected: widget.activa,
        label: widget.item.label,
        excludeSemantics: true,
        onTap: widget.onTap,
        child: MouseRegion(
          onEnter: (_) => setState(() => _encima = true),
          onExit: (_) => setState(() => _encima = false),
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              constraints: const BoxConstraints(minHeight: 48),
              decoration: BoxDecoration(
                gradient: fondo,
                color: !widget.activa && _encima ? cs.onSurface.withValues(alpha: 0.07) : null,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(children: [
                // Barra lateral de la entrada activa.
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 4,
                  height: widget.activa ? 26 : 0,
                  margin: const EdgeInsets.only(left: 2, right: 10),
                  decoration: BoxDecoration(
                    color: widget.acento,
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: widget.activa
                        ? [BoxShadow(color: widget.acento.withValues(alpha: 0.7), blurRadius: 8)]
                        : null,
                  ),
                ),
                if (!widget.activa) const SizedBox(width: 4),
                Icon(widget.item.icon, size: 22, color: color),
                const SizedBox(width: 14),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(widget.item.label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: widget.activa ? FontWeight.w700 : FontWeight.w500,
                            color: color)),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _Usuario extends StatelessWidget {
  const _Usuario({required this.nav, required this.acento});
  final SidebarNav nav;
  final Color acento;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final cs = Theme.of(context).colorScheme;
    final estilo = roleStyleOf(roleKindFromName(nav.rol) ?? RoleKind.student);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
      child: Semantics(
        label: '${nav.nombre}, ${MenuCuenta.nombreDelRol(nav.rol)}',
        excludeSemantics: true,
        child: Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: estilo.gradient),
              image: nav.foto != null
                  ? DecorationImage(image: MemoryImage(nav.foto!), fit: BoxFit.cover)
                  : null,
            ),
            alignment: Alignment.center,
            child: nav.foto != null
                ? null
                : Text(MenuCuenta.iniciales(nav.nombre),
                    style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(nav.nombre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface)),
              Text(MenuCuenta.nombreDelRol(nav.rol),
                  style: GoogleFonts.poppins(fontSize: 11.5, color: t.muted)),
            ]),
          ),
        ]),
      ),
    );
  }
}
