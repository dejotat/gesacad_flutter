import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/gemini_service.dart';

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
      if (mounted) {
        actualizarSheet(() {
          _mensajes.add(_Mensaje(
            texto:    'No pude conectarme. Verifica tu conexión e intenta de nuevo.',
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
      backgroundColor: const Color(0xFF4F46E5),
      foregroundColor: Colors.white,
      tooltip:         'Asistente GESACAD',
      child: const Icon(Icons.smart_toy_rounded),
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
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // ── Encabezado ─────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
                begin: Alignment.topLeft,
                end:   Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Row(children: [
              Container(
                padding:    const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color:        Colors.white.withOpacity(0.2),
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
              IconButton(
                icon:    const Icon(Icons.delete_outline_rounded,
                    color: Colors.white70),
                tooltip: 'Limpiar conversación',
                onPressed: widget.mensajes.isEmpty ? null : widget.onLimpiar,
              ),
              IconButton(
                icon:     const Icon(Icons.close_rounded, color: Colors.white),
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
              color: Colors.white,
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.06),
                    blurRadius: 8, offset: const Offset(0, -2)),
              ],
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
                        fontSize: 13, color: Colors.grey.shade400),
                    filled:        true,
                    fillColor:     Colors.grey.shade50,
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
                      ? Colors.grey.shade300
                      : const Color(0xFF4F46E5),
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
            color:        const Color(0xFF4F46E5).withOpacity(0.08),
            shape:        BoxShape.circle,
          ),
          child: const Icon(Icons.smart_toy_rounded,
              size: 48, color: Color(0xFF4F46E5)),
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
                fontSize: 12, color: Colors.grey.shade600),
            textAlign: TextAlign.center),
        const SizedBox(height: 20),
        Align(
          alignment: Alignment.centerLeft,
          child: Text('Preguntas frecuentes:',
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  color: Colors.grey.shade600)),
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
                    color:        Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Text(s,
                      style: GoogleFonts.poppins(
                          fontSize: 12, color: Colors.grey.shade700)),
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
              backgroundColor: const Color(0xFF4F46E5).withOpacity(0.12),
              child: const Icon(Icons.smart_toy_rounded,
                  size: 16, color: Color(0xFF4F46E5)),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: esUsuario
                    ? const Color(0xFF4F46E5)
                    : msg.esError
                        ? Colors.red.shade50
                        : Colors.grey.shade100,
                borderRadius: BorderRadius.only(
                  topLeft:     const Radius.circular(16),
                  topRight:    const Radius.circular(16),
                  bottomLeft:  Radius.circular(esUsuario ? 16 : 4),
                  bottomRight: Radius.circular(esUsuario ? 4 : 16),
                ),
              ),
              child: Text(
                msg.texto,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  color:    esUsuario
                      ? Colors.white
                      : msg.esError
                          ? Colors.red.shade700
                          : Colors.grey.shade800,
                  height:   1.45,
                ),
              ),
            ),
          ),
          if (esUsuario) ...[
            const SizedBox(width: 6),
            CircleAvatar(
              radius:          15,
              backgroundColor: const Color(0xFF4F46E5),
              child: const Icon(Icons.person_rounded,
                  size: 16, color: Colors.white),
            ),
          ],
        ],
      ),
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
            backgroundColor: const Color(0xFF4F46E5).withOpacity(0.12),
            child: const Icon(Icons.smart_toy_rounded,
                size: 16, color: Color(0xFF4F46E5)),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color:        Colors.grey.shade100,
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
                      fontSize: 12, color: Colors.grey.shade500)),
              const SizedBox(width: 6),
              const SizedBox(
                width:  20,
                height: 12,
                child:  CircularProgressIndicator(
                    strokeWidth: 2, color: Color(0xFF4F46E5)),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}
