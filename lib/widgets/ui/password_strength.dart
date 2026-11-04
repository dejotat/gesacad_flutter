import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config/app_tokens.dart';

/// Nivel de seguridad de una contraseña, de 0 (vacía) a 4 (fuerte).
///
/// Usa los mismos criterios que exige el servidor (8–64 caracteres, minúscula,
/// mayúscula, número, símbolo y sin el nombre de usuario): "Fuerte" significa
/// que la contraseña ya cumple la política completa.
class PasswordStrength {
  const PasswordStrength._(this.level, this.label, this.missing);

  /// 0 = sin texto · 1 = débil · 2 = regular · 3 = buena · 4 = fuerte.
  final int level;
  final String label;

  /// Lo que todavía falta, en lenguaje corriente (vacío si cumple todo).
  final List<String> missing;

  bool get meetsPolicy => level == 4;

  static final _symbol = RegExp(r"""[!@#$%^&*()\-_=+\[\]{};:'",./<>?\\|`~]""");

  static PasswordStrength evaluate(String pass, {String username = ''}) {
    if (pass.isEmpty) return const PasswordStrength._(0, '', []);
    final user = username.trim().toLowerCase();
    final checks = <String, bool>{
      'entre 8 y 64 caracteres': pass.length >= 8 && pass.length <= 64,
      'una minúscula': pass.contains(RegExp(r'[a-z]')),
      'una mayúscula': pass.contains(RegExp(r'[A-Z]')),
      'un número': pass.contains(RegExp(r'\d')),
      'un símbolo': pass.contains(_symbol),
      'no usar tu usuario': user.isEmpty || !pass.toLowerCase().contains(user),
    };
    final missing = [
      for (final e in checks.entries)
        if (!e.value) e.key
    ];
    final passed = checks.length - missing.length;
    if (missing.isEmpty) return PasswordStrength._(4, 'Fuerte', missing);
    if (passed == 5) return PasswordStrength._(3, 'Buena', missing);
    if (passed >= 3) return PasswordStrength._(2, 'Regular', missing);
    return PasswordStrength._(1, 'Débil', missing);
  }

  /// Color del nivel: rojo → naranja → verde claro → verde.
  Color color(AppTokens tk) => switch (level) {
        1 => tk.danger,
        2 => tk.warning,
        3 => Color.lerp(tk.warning, tk.success, 0.5)!,
        4 => tk.success,
        _ => tk.border,
      };
}

/// Barra de 4 tramos que cambia de color con la seguridad de la contraseña.
/// No muestra la lista de requisitos: solo el nivel y, si [showHint], lo que falta.
class PasswordStrengthBar extends StatelessWidget {
  const PasswordStrengthBar({
    super.key,
    required this.password,
    this.username = '',
    this.showHint = false,
  });

  final String password;
  final String username;

  /// Muestra "Falta: …" bajo la barra (útil al CREAR una contraseña, no al iniciar sesión).
  final bool showHint;

  @override
  Widget build(BuildContext context) {
    final tk = context.tokens;
    final s = PasswordStrength.evaluate(password, username: username);
    if (s.level == 0) return const SizedBox.shrink();
    final color = s.color(tk);

    return Semantics(
      label: 'Seguridad de la contraseña: ${s.label}',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              for (var i = 0; i < 4; i++)
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    margin: EdgeInsets.only(right: i < 3 ? 4 : 0),
                    height: 5,
                    decoration: BoxDecoration(
                      color: i < s.level ? color : tk.border,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
            ]),
            const SizedBox(height: 6),
            Text(
              'Seguridad: ${s.label}',
              style: GoogleFonts.poppins(
                  fontSize: 11, fontWeight: FontWeight.w600, color: color),
            ),
            if (showHint && s.missing.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'Falta: ${s.missing.join(', ')}',
                  style: GoogleFonts.poppins(fontSize: 11, color: tk.muted),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
