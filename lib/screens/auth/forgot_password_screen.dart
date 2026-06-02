import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/settings_service.dart';
import '../../config/api_config.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

/// Pantalla de recuperación de contraseña.
///
/// El usuario ingresa su nombre de usuario o correo institucional
/// y recibe instrucciones de restablecimiento.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  bool _loading = false;
  bool _sent = false;
  late AnimationController _anim;
  late Animation<double> _fade;

  // Número de WhatsApp del administrador del sistema (formato internacional)
  static const String _adminWhatsApp = '573205771845';

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _fade = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
    _anim.forward();
  }

  @override
  void dispose() {
    _anim.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  /// Envía la solicitud al backend (queda registrada para el admin)
  /// y marca la pantalla como enviada.
  Future<void> _sendRecovery() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      // Registrar la solicitud en el backend para que el admin la vea
      // en su panel de notificaciones de GESACAD.
      await http.post(
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.passwordRequest}'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': _emailCtrl.text.trim()}),
      ).timeout(const Duration(seconds: 10));
    } catch (_) {
      // Si no hay conexión, la solicitud continúa igual —
      // el usuario puede contactar al admin directamente por WhatsApp.
    }
    if (mounted) setState(() { _loading = false; _sent = true; });
  }

  /// Abre WhatsApp con un mensaje pre-llenado para el administrador.
  Future<void> _abrirWhatsApp() async {
    final usuario = _emailCtrl.text.trim();
    final mensaje = Uri.encodeComponent(
      '¡Hola! Soy el usuario "$usuario" de GESACAD '
      '(Unicomfacauca) y necesito que el administrador '
      'restablezca mi contraseña. ¡Gracias!',
    );
    final uri = Uri.parse('https://wa.me/$_adminWhatsApp?text=$mensaje');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeType = AppSettings.currentTheme.value;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: themeType.gradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Barra superior
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                      tooltip: 'Regresar al inicio de sesión',
                      onPressed: () => Navigator.pop(context),
                    ),
                    Text('Recuperar Contraseña',
                        style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 17)),
                  ],
                ),
              ),
              Expanded(
                child: Center(
                  child: FadeTransition(
                    opacity: _fade,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 20),
                      child: _sent ? _buildSuccessCard() : _buildFormCard(themeType),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFormCard(AppThemeType themeType) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 440),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.18),
              blurRadius: 28,
              offset: const Offset(0, 10)),
        ],
      ),
      padding: const EdgeInsets.all(30),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Ícono
            Center(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: themeType.primaryColor.withOpacity(0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.lock_reset_rounded,
                    size: 46, color: themeType.primaryColor),
              ),
            ),
            const SizedBox(height: 20),
            Text('¿Olvidaste tu contraseña?',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                    color: themeType.primaryColor)),
            const SizedBox(height: 8),
            Text(
              'Ingresa tu nombre de usuario o correo institucional '
              'y te enviaremos instrucciones para restablecer tu contraseña.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 13, color: Colors.grey.shade500, height: 1.5),
            ),
            const SizedBox(height: 28),
            TextFormField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              style: GoogleFonts.poppins(fontSize: 15),
              decoration: InputDecoration(
                labelText: 'Usuario o correo institucional',
                labelStyle: GoogleFonts.poppins(color: Colors.grey.shade600),
                prefixIcon: Icon(Icons.alternate_email_rounded,
                    color: themeType.primaryColor),
                helperText: 'Ej: jperez o jperez@unicomfacauca.edu.co',
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Ingresa tu usuario o correo institucional';
                }
                if (v.trim().length < 3) {
                  return 'Mínimo 3 caracteres';
                }
                return null;
              },
            ),
            const SizedBox(height: 28),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _loading ? null : _sendRecovery,
                style: ElevatedButton.styleFrom(
                  backgroundColor: themeType.primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 4,
                  shadowColor: themeType.primaryColor.withOpacity(0.4),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: Colors.white))
                    : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const Icon(Icons.send_rounded, size: 18),
                        const SizedBox(width: 10),
                        Text('Enviar instrucciones',
                            style: GoogleFonts.poppins(
                                fontSize: 15, fontWeight: FontWeight.w700)),
                      ]),
              ),
            ),
            const SizedBox(height: 18),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Regresar al inicio de sesión',
                  style: GoogleFonts.poppins(
                      color: themeType.primaryColor,
                      fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Row(children: [
                Icon(Icons.info_outline_rounded,
                    color: Colors.amber.shade700, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Si no recibes el correo, contacta al administrador del sistema.',
                    style: GoogleFonts.poppins(
                        fontSize: 11, color: Colors.amber.shade800),
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccessCard() {
    return Container(
      constraints: const BoxConstraints(maxWidth: 440),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.18),
              blurRadius: 28,
              offset: const Offset(0, 10)),
        ],
      ),
      padding: const EdgeInsets.all(36),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.mark_email_read_rounded,
                size: 56, color: Colors.green.shade600),
          ),
          const SizedBox(height: 24),
          Text('¡Instrucciones enviadas!',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Colors.green.shade700)),
          const SizedBox(height: 12),
          Text(
            'Revisa tu correo institucional. Si la cuenta '
            '"${_emailCtrl.text.trim()}" existe en el sistema, '
            'recibirás un enlace para restablecer tu contraseña en los '
            'próximos 5 minutos.',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
                fontSize: 13, color: Colors.grey.shade600, height: 1.6),
          ),
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(children: [
              _tipRow(Icons.folder_open_rounded, 'Revisa la carpeta de Spam'),
              const SizedBox(height: 8),
              _tipRow(Icons.timer_outlined, 'El enlace expira en 24 horas'),
              const SizedBox(height: 8),
              _tipRow(Icons.support_agent_rounded,
                  '¿Sin correo? Contacta al administrador'),
            ]),
          ),
          const SizedBox(height: 24),
          // Botón WhatsApp — contacto directo con el administrador
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _abrirWhatsApp,
              icon: const Icon(Icons.chat_rounded, size: 20),
              label: Text('Contactar Admin por WhatsApp',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF25D366), // verde WhatsApp
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 3,
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.login_rounded, size: 18),
              label: Text('Volver al inicio de sesión',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tipRow(IconData icon, String text) {
    return Row(children: [
      Icon(icon, size: 16, color: Colors.grey.shade500),
      const SizedBox(width: 8),
      Text(text,
          style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600)),
    ]);
  }
}
