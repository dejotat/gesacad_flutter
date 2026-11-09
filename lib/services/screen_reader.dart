import 'dart:async';
import 'dart:ui' show CheckedState, Tristate;
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'settings_service.dart';
import 'tts_service.dart';

/// Lector de pantalla integrado («TalkBack» de GESACAD).
///
/// Lee en voz alta **lo que hay realmente en pantalla**, usando el árbol de accesibilidad que
/// Flutter ya construye (el mismo que usa TalkBack/VoiceOver). Por eso cubre TODAS las pantallas,
/// botones, campos y encabezados que tengan etiqueta, sin tener que envolver cada widget:
///
/// * **Cursor (web/escritorio):** al detenerte sobre un elemento lo lee («Guardar»).
/// * **Teclado:** al moverte con Tab lee el elemento enfocado.
/// * **Toque largo (móvil):** lee sin activar el elemento.
/// * **Pantallas:** al abrir o cerrar una pantalla o ventana anuncia su título («Panel
///   Administrador»).
///
/// Se activa con `AppSettings.talkBackEnabled` (Ajustes, menú de cuenta o el botón del lector).
/// En un teléfono con TalkBack del sistema activado no hace falta: ese lector ya usa las mismas
/// etiquetas.
class ScreenReader {
  ScreenReader._();
  static final ScreenReader instance = ScreenReader._();

  /// Cómo se pronuncia un texto (se sustituye en las pruebas).
  @visibleForTesting
  void Function(String texto) decir = (t) => TtsService.instance.speak(t);

  /// Cuánto debe quedarse quieto el cursor sobre un elemento antes de leerlo (evita leer
  /// todo lo que se cruza al mover el ratón).
  @visibleForTesting
  Duration espera = const Duration(milliseconds: 220);

  static const _toqueLargo = Duration(milliseconds: 450);
  static const _maxCaracteres = 260;

  SemanticsHandle? _handle;
  Timer? _temporizador;
  Timer? _pulsacion;
  Timer? _pantalla;
  String _ultima = '';
  bool _iniciado = false;
  bool _escuchando = false;

  bool get activo => AppSettings.talkBackEnabled.value;

  void _alCambiar() => _sincronizar();

  /// Una sola vez desde `main()`, con los ajustes ya cargados.
  void iniciar() {
    if (_iniciado) return;
    _iniciado = true;
    AppSettings.talkBackEnabled.addListener(_alCambiar);
    _sincronizar(anunciar: false);
  }

  void _sincronizar({bool anunciar = true}) {
    if (activo && !_escuchando) {
      _escuchando = true;
      // Fuerza a Flutter a construir el árbol de accesibilidad aunque no haya un lector del sistema.
      _handle ??= SemanticsBinding.instance.ensureSemantics();
      GestureBinding.instance.pointerRouter.addGlobalRoute(_alPuntero);
      FocusManager.instance.addListener(_alEnfocar);
      _ultima = '';
      if (anunciar) decir('Lector de pantalla activado. Pasa el cursor por los elementos para escucharlos.');
    } else if (!activo && _escuchando) {
      _escuchando = false;
      GestureBinding.instance.pointerRouter.removeGlobalRoute(_alPuntero);
      FocusManager.instance.removeListener(_alEnfocar);
      _temporizador?.cancel();
      _pulsacion?.cancel();
      _pantalla?.cancel();
      _handle?.dispose();
      _handle = null;
      TtsService.instance.stop();
    }
  }

  // ── Entradas: cursor, toque largo, teclado y cambio de pantalla ───────────────

  void _alPuntero(PointerEvent e) {
    if (!activo) return;
    final tactil = e.kind == PointerDeviceKind.touch || e.kind == PointerDeviceKind.stylus;
    if (e is PointerHoverEvent || (e is PointerMoveEvent && !tactil)) {
      _programar(e.position, e.viewId, espera);
    } else if (e is PointerDownEvent && tactil) {
      _pulsacion?.cancel();
      _pulsacion = Timer(_toqueLargo, () => _leerEn(e.position, e.viewId));
    } else if (e is PointerUpEvent || e is PointerCancelEvent) {
      _pulsacion?.cancel();
    }
  }

  void _alEnfocar() {
    if (!activo) return;
    // Al abrir una pantalla el foco cambia solo: lo cubre el anuncio de la pantalla.
    if (_pantalla?.isActive ?? false) return;
    final ctx = FocusManager.instance.primaryFocus?.context;
    final ro = ctx?.findRenderObject();
    if (ctx == null || ro is! RenderBox || !ro.attached || !ro.hasSize) return;
    final centro = ro.localToGlobal(ro.size.center(Offset.zero));
    _programar(centro, View.maybeOf(ctx)?.viewId, const Duration(milliseconds: 160));
  }

  void _programar(Offset posicion, int? viewId, Duration despues) {
    _temporizador?.cancel();
    _temporizador = Timer(despues, () => _leerEn(posicion, viewId));
  }

  /// Un cambio de pantalla (la llama [ScreenReaderObserver]): anuncia su título cuando termina
  /// la transición.
  void pantallaCambio() {
    if (!activo) return;
    if (DateTime.now().isBefore(_sinAnuncioHasta)) return; // la bienvenida ya habla
    _pantalla?.cancel();
    _pantalla = Timer(const Duration(milliseconds: 650), anunciarPantalla);
  }

  void _leerEn(Offset posicion, int? viewId) {
    if (!activo) return;
    final frase = frasePara(posicion, viewId: viewId);
    if (frase == null || frase.isEmpty) {
      _ultima = ''; // al volver sobre el mismo elemento, se lee de nuevo
      return;
    }
    if (frase == _ultima) return;
    _ultima = frase;
    decir(frase);
  }

  DateTime _sinAnuncioHasta = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _saludo;

  /// Saludo al entrar al panel de un rol («Bienvenido al dashboard de administrador»). Sustituye
  /// al anuncio de pantalla de esa transición (si no, uno taparía al otro).
  void bienvenida(String rol) {
    if (!activo) return;
    _sinAnuncioHasta = DateTime.now().add(const Duration(seconds: 3));
    _pantalla?.cancel();
    _saludo?.cancel();
    _saludo = Timer(const Duration(milliseconds: 800), () {
      if (!activo) return;
      _ultima = '';
      decir('Bienvenido al panel de $rol');
    });
  }

  /// Anuncia el título de la pantalla (o ventana) que está arriba.
  void anunciarPantalla() {
    if (!activo) return;
    final raiz = _raiz(null)?.$1;
    if (raiz == null) return;
    String? titulo;
    String? encabezado;
    var detalle = <String>[];
    void visitar(SemanticsNode n) {
      if (titulo != null) return;
      final d = n.getSemanticsData();
      final et = d.label.trim();
      if (et.isNotEmpty) {
        if (d.flagsCollection.namesRoute) {
          titulo = et;
          // Un diálogo o una hoja (el nodo que da nombre a la ruta CONTIENE su contenido): se leen
          // también su título y texto. En una pantalla completa el nodo es el título y no tiene hijos.
          detalle = _textosInternos(n, 4);
          return;
        }
        if (encabezado == null && d.flagsCollection.isHeader) encabezado = et;
      }
      n.visitChildren((c) {
        visitar(c);
        return titulo == null;
      });
    }

    visitar(raiz);
    final nombre = titulo ?? encabezado;
    if (nombre == null) return;
    _ultima = '';
    final resto = detalle.where((x) => x != nombre).join('. ');
    // Solo el título: decir «Pantalla:» antes de cada uno cansaba al volver atrás.
    decir(_recortar('$nombre${resto.isEmpty ? '' : '. $resto'}'));
  }

  /// Hasta [max] textos con etiqueta que contiene [n] (sin repetir), en orden de lectura.
  List<String> _textosInternos(SemanticsNode n, int max) {
    final textos = <String>[];
    void ir(SemanticsNode c) {
      if (textos.length >= max) return;
      final et = c.getSemanticsData().label.trim();
      if (et.isNotEmpty && !textos.contains(et)) textos.add(et);
      if (c.isMergedIntoParent) return;
      c.visitChildren((x) {
        ir(x);
        return textos.length < max;
      });
    }

    n.visitChildren((c) {
      ir(c);
      return textos.length < max;
    });
    return textos;
  }

  // ── Búsqueda en el árbol de accesibilidad ─────────────────────────────────────

  /// Frase que se leería para el punto [posicion] (en píxeles lógicos), o null si ahí no hay
  /// nada con etiqueta. Es pública para poder probarla.
  String? frasePara(Offset posicion, {int? viewId}) {
    final r = _raiz(viewId);
    if (r == null) return null;
    final candidatos = <SemanticsNode>[];
    _reunir(r.$1, posicion * r.$2, candidatos);
    // De arriba abajo: una capa que no dice nada (globo de ayuda, telón, contenedor) no debe
    // tapar lo que hay debajo; se lee el primero que tenga algo que decir.
    for (final n in candidatos) {
      final f = _frase(n);
      if (f != null && f.isNotEmpty) return f;
    }
    return null;
  }

  (SemanticsNode, double)? _raiz(int? viewId) {
    for (final rv in RendererBinding.instance.renderViews) {
      if (viewId != null && rv.flutterView.viewId != viewId) continue;
      final raiz = rv.owner?.semanticsOwner?.rootSemanticsNode;
      if (raiz != null) return (raiz, rv.flutterView.devicePixelRatio);
    }
    return null;
  }

  /// Reúne los nodos que contienen el punto, del más profundo y superior al más general.
  void _reunir(SemanticsNode n, Offset enPadre, List<SemanticsNode> salida) {
    if (n.isInvisible) return;
    var local = enPadre;
    final t = n.transform;
    if (t != null) {
      final inversa = Matrix4.tryInvert(t);
      if (inversa == null) return;
      local = MatrixUtils.transformPoint(inversa, enPadre);
    }
    if (!n.rect.contains(local)) return;
    final hijos = <SemanticsNode>[];
    n.visitChildren((c) {
      hijos.add(c);
      return true;
    });
    // Los hijos posteriores se pintan encima: se visitan primero.
    for (final c in hijos.reversed) {
      _reunir(c, local, salida);
    }
    salida.add(n);
  }

  String? _frase(SemanticsNode nodo) {
    SemanticsNode? n = nodo;
    while (n != null && n.isMergedIntoParent) {
      n = n.parent;
    }
    // Si el nodo más profundo no dice nada, sube a quien lo contiene (máx. 4 niveles).
    SemanticsData? d;
    for (var i = 0; i < 5 && n != null; i++) {
      final x = n.getSemanticsData();
      if (x.label.trim().isNotEmpty || x.value.trim().isNotEmpty || x.tooltip.trim().isNotEmpty) {
        d = x;
        break;
      }
      n = n.parent;
    }
    if (d == null) return null;

    final partes = <String>[];
    // Un botón de solo ícono (IconButton) se nombra con su `tooltip`, no con su etiqueta.
    final base = d.label.trim().isNotEmpty ? d.label : d.tooltip;
    final etiqueta = base.replaceAll(RegExp(r'\s*\n\s*'), '. ').trim();
    if (etiqueta.isNotEmpty) partes.add(etiqueta);
    final valor = d.value.trim();
    if (valor.isNotEmpty && !etiqueta.contains(valor)) partes.add(valor);

    // Rol y estado, en español natural. Solo se dice el rol cuando APORTA algo: un control
    // deslizante o un enlace. «Botón», «encabezado» y «campo de texto» no se dicen: repetirlos en
    // cada frase cansaba («Guardar, botón»; «Usuario, campo de texto»…).
    if (d.flagsCollection.isSlider) {
      partes.add('control deslizante');
    } else if (d.flagsCollection.isLink) {
      partes.add('enlace');
    }
    final f = d.flagsCollection;
    if (f.isChecked != CheckedState.none) {
      partes.add(switch (f.isChecked) {
        CheckedState.isTrue => 'activado',
        CheckedState.mixed => 'parcialmente activado',
        _ => 'desactivado',
      });
    } else if (f.isToggled != Tristate.none) {
      partes.add(f.isToggled == Tristate.isTrue ? 'activado' : 'desactivado');
    } else if (f.isSelected == Tristate.isTrue) {
      partes.add('seleccionado');
    }
    if (f.isEnabled == Tristate.isFalse) partes.add('no disponible');
    if (d.hint.trim().isNotEmpty) partes.add(d.hint.trim());
    return _recortar(partes.join(', '));
  }

  static String _recortar(String s) =>
      s.length <= _maxCaracteres ? s : '${s.substring(0, _maxCaracteres - 1)}…';

  /// Apaga todo y suelta recursos (pruebas).
  @visibleForTesting
  void reiniciar() {
    if (_escuchando) {
      _escuchando = false;
      GestureBinding.instance.pointerRouter.removeGlobalRoute(_alPuntero);
      FocusManager.instance.removeListener(_alEnfocar);
    }
    _temporizador?.cancel();
    _pulsacion?.cancel();
    _pantalla?.cancel();
    _saludo?.cancel();
    _sinAnuncioHasta = DateTime.fromMillisecondsSinceEpoch(0);
    _handle?.dispose();
    _handle = null;
    _ultima = '';
    if (_iniciado) AppSettings.talkBackEnabled.removeListener(_alCambiar);
    _iniciado = false;
  }
}

/// Avisa al lector cuando se abre o se cierra una pantalla, un diálogo o una hoja. Se registra
/// en `MaterialApp.navigatorObservers`.
class ScreenReaderObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => ScreenReader.instance.pantallaCambio();

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => ScreenReader.instance.pantallaCambio();

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) => ScreenReader.instance.pantallaCambio();

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => ScreenReader.instance.pantallaCambio();
}
