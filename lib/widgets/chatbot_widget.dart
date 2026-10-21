import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'ui/ui.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/gemini_service.dart';
import '../config/app_tokens.dart';

/// Modelo de un mensaje individual en el chat.
class _Mensaje {
  final String texto;
  final bool   esUsuario;
  final bool   esError;

  const _Mensaje({
    required this.texto,
    required this.esUsuario,
    this.esError = false,
  });
}

/// Botón flotante del chatbot con ícono de robot.
///
/// Mantiene el historial de conversación durante la sesión:
/// mientras el widget esté vivo (pantalla abierta), el historial persiste
/// aunque el usuario cierre y vuelva a abrir la ventana de chat.
class ChatbotWidget extends StatefulWidget {
  const ChatbotWidget({super.key});

  @override
  State<ChatbotWidget> createState() => _ChatbotWidgetState();
}

class _ChatbotWidgetState extends State<ChatbotWidget> {
  // Historial en formato de la API de Gemini (turnos usuario/modelo)
  final List<Map<String, dynamic>> _historialGemini = [];

  // Mensajes que se muestran en la UI del chat
  final List<_Mensaje> _mensajes = [];

  bool _enviando = false;

  // ── Enviar mensaje al asistente ───────────────────────────────────────────

  Future<void> _enviar(String texto, StateSetter actualizarSheet) async {
    final trimmed = texto.trim();
    if (trimmed.isEmpty || _enviando) return;

    // Construir el turno del usuario para la API antes de enviarlo
    final turnoUsuario = {
      'role':  'user',
      'parts': [
        {'text': trimmed}
      ],
    };

    actualizarSheet(() {
      _mensajes.add(_Mensaje(texto: trimmed, esUsuario: true));
      _enviando = true;
    });

    try {
      // Pasar historial previo + nuevo turno del usuario a la API
      final historialParaApi = [..._historialGemini, turnoUsuario];
      final respuesta = await GeminiService.generarRespuesta(historialParaApi);

      // Guardar ambos turnos en el historial para mantener contexto
      _historialGemini.add(turnoUsuario);
      _historialGemini.add({
        'role':  'model',
        'parts': [
          {'text': respuesta}
        ],
      });

      if (mounted) {
        actualizarSheet(() {
          _mensajes.add(_Mensaje(texto: respuesta, esUsuario: false));
          _enviando = false;
        });
      }
    } catch (e) {
      // Registrar el error real para diagnóstico en la consola de desarrollo
      developer.log('[Chatbot] Error al llamar a Gemini: $e',
          name: 'GESACAD.Chatbot', error: e);
      if (mounted) {
        actualizarSheet(() {
          // Mostrar el error real en el chat para facilitar el diagnóstico
          _mensajes.add(_Mensaje(
            texto:     'Error: $e',
            esUsuario: false,
            esError:   true,
          ));
          _enviando = false;
        });
      }
    }
  }

  // ── Abrir ventana de chat ─────────────────────────────────────────────────

  void _abrirChat() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, actualizarSheet) => _ChatSheet(
          mensajes:  _mensajes,
          enviando:  _enviando,
          onEnviar:  (texto) => _enviar(texto, actualizarSheet),
          onLimpiar: () => actualizarSheet(() {
            _mensajes.clear();
            _historialGemini.clear();
            _enviando = false;
          }),
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      heroTag:         'chatbot_gesacad',
      onPressed:       _abrirChat,
      backgroundColor: Theme.of(context).colorScheme.primary,
      foregroundColor: Colors.white,
      tooltip:         'Asistente GESACAD',
      child: const MotionIcon(Icons.smart_toy_rounded,
          color: Colors.white, size: 26, motion: IconMotion.tada, halo: true),
    );
  }
}

// ── Hoja de chat (bottom sheet) ───────────────────────────────────────────────

class _ChatSheet extends StatefulWidget {
  final List<_Mensaje>     mensajes;
  final bool               enviando;
  final void Function(String) onEnviar;
  final VoidCallback       onLimpiar;

  const _ChatSheet({
    required this.mensajes,
    required this.enviando,
    required this.onEnviar,
    required this.onLimpiar,
  });

  @override
  State<_ChatSheet> createState() => _ChatSheetState();
}

class _ChatSheetState extends State<_ChatSheet> {
  final TextEditingController _inputCtrl   = TextEditingController();
  final ScrollController      _scrollCtrl  = ScrollController();

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  /// Desplaza la lista al último mensaje automáticamente.
  void _scrollAlFinal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve:    Curves.easeOut,
        );
      }
    });
  }

  void _enviar() {
    final texto = _inputCtrl.text.trim();
    if (texto.isEmpty || widget.enviando) return;
    _inputCtrl.clear();
    widget.onEnviar(texto);
    _scrollAlFinal();
  }

  @override
  Widget build(BuildContext context) {
    _scrollAlFinal();

    return Container(
      height: MediaQuery.of(context).size.height * 0.78,
      decoration: BoxDecoration(
        color: Theme.of(context).dialogTheme.backgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: context.tokens.glassBorder),
      ),
      child: Column(
        children: [
          // ── Encabezado ─────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.primary],
                begin: Alignment.topLeft,
                end:   Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Row(children: [
              Container(
                padding:    const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color:        Colors.white.withValues(alpha: 0.2),
                  shape:        BoxShape.circle,
                ),
                child: const Icon(Icons.smart_toy_rounded,
                    color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Asistente GESACAD',
                        style: GoogleFonts.poppins(
                            color:      Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize:   15)),
                    Text('Unicomfacauca · con Gemini AI',
                        style: GoogleFonts.poppins(
                            color: Colors.white70, fontSize: 11)),
                  ],
                ),
              ),
              // Botón limpiar conversación
              AnimatedIconButton(
                icon:    Icons.delete_outline_rounded,
                color:   Colors.white,
                reaction: IconReaction.shake,
                tooltip: 'Limpiar conversación',
                onPressed: widget.mensajes.isEmpty ? null : widget.onLimpiar,
              ),
              AnimatedIconButton(
                icon:     Icons.close_rounded,
                color:    Colors.white,
                reaction: IconReaction.spin,
                tooltip:  'Cerrar',
                onPressed: () => Navigator.pop(context),
              ),
            ]),
          ),

          // ── Área de mensajes ───────────────────────────────────────────
          Expanded(
            child: widget.mensajes.isEmpty
                ? _buildBienvenida()
                : ListView.builder(
                    controller:  _scrollCtrl,
                    padding:     const EdgeInsets.all(16),
                    itemCount:   widget.mensajes.length +
                        (widget.enviando ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (widget.enviando && i == widget.mensajes.length) {
                        return _buildIndicadorEscribiendo();
                      }
                      return _buildBurbuja(widget.mensajes[i]);
                    },
                  ),
          ),

          // ── Área de entrada ────────────────────────────────────────────
          Container(
            padding: EdgeInsets.only(
              left:   12,
              right:  12,
              top:    10,
              bottom: MediaQuery.of(context).viewInsets.bottom + 12,
            ),
            decoration: BoxDecoration(
              color: context.tokens.glass,
              border: Border(top: BorderSide(color: context.tokens.border)),
            ),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller:   _inputCtrl,
                  textInputAction: TextInputAction.send,
                  onSubmitted:  (_) => _enviar(),
                  enabled:      !widget.enviando,
                  maxLines:     3,
                  minLines:     1,
                  style: GoogleFonts.poppins(fontSize: 14),
                  decoration: InputDecoration(
                    hintText:      'Escribe tu pregunta...',
                    hintStyle:     GoogleFonts.poppins(
                        fontSize: 13, color: context.tokens.muted),
                    filled:        true,
                    fillColor:     context.tokens.border.withValues(alpha: 0.4),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide:   BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                child: FloatingActionButton.small(
                  heroTag:         'chat_send',
                  onPressed:       widget.enviando ? null : _enviar,
                  backgroundColor: widget.enviando
                      ? context.tokens.border
                      : Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  child: widget.enviando
                      ? const SizedBox(
                          width:  18,
                          height: 18,
                          child:  CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.send_rounded, size: 18),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  // ── Pantalla de bienvenida cuando no hay mensajes ─────────────────────────

  Widget _buildBienvenida() {
    final sugerencias = [
      '¿Qué programas académicos ofrece Unicomfacauca?',
      '¿Cómo entrego una tarea en GESACAD?',
      '¿Cuál es el proceso de matrícula?',
      '¿Cómo veo mis calificaciones?',
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        const SizedBox(height: 12),
        Container(
          padding:    const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color:        Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
            shape:        BoxShape.circle,
          ),
          child: Icon(Icons.smart_toy_rounded,
              size: 48, color: Theme.of(context).colorScheme.primary),
        ),
        const SizedBox(height: 16),
        Text('¡Hola! Soy el Asistente GESACAD',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700, fontSize: 16),
            textAlign: TextAlign.center),
        const SizedBox(height: 6),
        Text('Puedo ayudarte con información sobre Unicomfacauca, '
            'tus cursos y el uso de la plataforma.',
            style: GoogleFonts.poppins(
                fontSize: 12, color: context.tokens.muted),
            textAlign: TextAlign.center),
        const SizedBox(height: 20),
        Align(
          alignment: Alignment.centerLeft,
          child: Text('Preguntas frecuentes:',
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  color: context.tokens.muted)),
        ),
        const SizedBox(height: 8),
        ...sugerencias.map((s) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  _inputCtrl.text = s;
                  _enviar();
                },
                child: Container(
                  width:   double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color:        context.tokens.border.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: context.tokens.border),
                  ),
                  child: Text(s,
                      style: GoogleFonts.poppins(
                          fontSize: 12, color: context.tokens.muted)),
                ),
              ),
            )),
      ]),
    );
  }

  // ── Burbuja de mensaje ─────────────────────────────────────────────────────

  Widget _buildBurbuja(_Mensaje msg) {
    final esUsuario = msg.esUsuario;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment:
            esUsuario ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!esUsuario) ...[
            CircleAvatar(
              radius:          15,
              backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
              child: Icon(Icons.smart_toy_rounded,
                  size: 16, color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: esUsuario
                    ? Theme.of(context).colorScheme.primary
                    : msg.esError
                        ? context.tokens.danger.withValues(alpha: 0.10)
                        : context.tokens.border.withValues(alpha: 0.4),
                borderRadius: BorderRadius.only(
                  topLeft:     const Radius.circular(16),
                  topRight:    const Radius.circular(16),
                  bottomLeft:  Radius.circular(esUsuario ? 16 : 4),
                  bottomRight: Radius.circular(esUsuario ? 4 : 16),
                ),
              ),
              // Las burbujas del usuario muestran texto plano.
              // Las burbujas del bot detectan URLs y las renderiza como
              // enlaces azules tocables que abren el navegador.
              child: esUsuario
                  ? Text(
                      msg.texto,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color:   Colors.white,
                        height:  1.45,
                      ),
                    )
                  : _buildTextoConLinks(
                      msg.texto,
                      msg.esError
                          ? context.tokens.danger
                          : Theme.of(context).colorScheme.onSurface,
                    ),
            ),
          ),
          if (esUsuario) ...[
            const SizedBox(width: 6),
            CircleAvatar(
              radius:          15,
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: const Icon(Icons.person_rounded,
                  size: 16, color: Colors.white),
            ),
          ],
        ],
      ),
    );
  }

  // ── Texto con URLs detectadas y tocables ─────────────────────────────────

  /// Renderiza [texto] como un [RichText] donde cualquier URL que comience con
  /// http:// o https:// aparece en azul subrayado y al tocarla abre el navegador.
  Widget _buildTextoConLinks(String texto, Color colorBase) {
    final urlRegex = RegExp(r'https?://[^\s]+');
    final coincidencias = urlRegex.allMatches(texto);

    // Sin URLs: devolver un Text normal para no gastar recursos
    if (coincidencias.isEmpty) {
      return Text(
        texto,
        style: GoogleFonts.poppins(fontSize: 13, color: colorBase, height: 1.45),
      );
    }

    final spans = <InlineSpan>[];
    int cursor  = 0;

    for (final m in coincidencias) {
      // Fragmento de texto antes de la URL
      if (m.start > cursor) {
        spans.add(TextSpan(
          text:  texto.substring(cursor, m.start),
          style: GoogleFonts.poppins(fontSize: 13, color: colorBase, height: 1.45),
        ));
      }

      // La URL como WidgetSpan con GestureDetector (evita gestionar
      // TapGestureRecognizer y su ciclo de vida manualmente)
      final url = m.group(0)!;
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline:  TextBaseline.alphabetic,
        child: GestureDetector(
          onTap: () async {
            final uri = Uri.tryParse(url);
            if (uri != null && await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          },
          child: Text(
            url,
            style: GoogleFonts.poppins(
              fontSize:   13,
              color:      context.tokens.info,
              decoration: TextDecoration.underline,
              decorationColor: context.tokens.info,
              height:     1.45,
            ),
          ),
        ),
      ));

      cursor = m.end;
    }

    // Texto restante después de la última URL
    if (cursor < texto.length) {
      spans.add(TextSpan(
        text:  texto.substring(cursor),
        style: GoogleFonts.poppins(fontSize: 13, color: colorBase, height: 1.45),
      ));
    }

    return RichText(
      text: TextSpan(children: spans),
    );
  }

  // ── Indicador de "escribiendo..." ─────────────────────────────────────────

  Widget _buildIndicadorEscribiendo() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          CircleAvatar(
            radius:          15,
            backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
            child: Icon(Icons.smart_toy_rounded,
                size: 16, color: Theme.of(context).colorScheme.primary),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color:        context.tokens.border.withValues(alpha: 0.4),
              borderRadius: const BorderRadius.only(
                topLeft:     Radius.circular(16),
                topRight:    Radius.circular(16),
                bottomRight: Radius.circular(16),
                bottomLeft:  Radius.circular(4),
              ),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text('Escribiendo',
                  style: GoogleFonts.poppins(
                      fontSize: 12, color: context.tokens.muted)),
              const SizedBox(width: 6),
              SizedBox(
                width:  20,
                height: 12,
                child:  CircularProgressIndicator(
                    strokeWidth: 2, color: Theme.of(context).colorScheme.primary),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}
