import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/api_service.dart';
import '../../models/user_model.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../widgets/ui/ui.dart';
import '../../config/app_tokens.dart';

/// Pantalla de gestión de usuarios — diseño moderno con tarjetas en mosaico.
class AdminUsers extends StatefulWidget {
  const AdminUsers({super.key});

  @override
  State<AdminUsers> createState() => _AdminUsersState();
}

class _AdminUsersState extends State<AdminUsers> {
  List<UserModel> _users = [];
  List<UserModel> _filtered = [];
  bool _loading = true;
  final _searchCtrl = TextEditingController();
  String _rolFilter = 'Todos';

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    setState(() => _loading = true);
    try {
      _users = await ApiService().getUsers();
      _applyFilter();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  void _applyFilter() {
    _filtered = _users.where((u) {
      final matchSearch =
          u.username.toLowerCase().contains(_searchCtrl.text.toLowerCase());
      final matchRol = _rolFilter == 'Todos' || u.rol == _rolFilter;
      return matchSearch && matchRol;
    }).toList();
    setState(() {});
  }

  bool _isDuplicateUsername(String username, {int? excludeId}) {
    return _users.any((u) =>
        u.username.toLowerCase() == username.toLowerCase() &&
        u.id != excludeId);
  }

  // ── Colores y datos por rol ───────────────────────────────────────────────
  List<Color> _rolGradient(String rol) {
    switch (rol) {
      case 'Admin':
        return [const Color(0xFF4F46E5), const Color(0xFF9F1239)];
      case 'Teacher':
        return [const Color(0xFF047857), const Color(0xFF0369A1)];
      default:
        return [const Color(0xFF1D4ED8), const Color(0xFF4F46E5)];
    }
  }

  IconData _rolIcon(String rol) {
    switch (rol) {
      case 'Admin':
        return Icons.admin_panel_settings_rounded;
      case 'Teacher':
        return Icons.school_rounded;
      default:
        return Icons.person_rounded;
    }
  }

  String _rolLabel(String rol) {
    switch (rol) {
      case 'Admin':
        return 'Administrador';
      case 'Teacher':
        return 'Profesor';
      default:
        return 'Estudiante';
    }
  }

  // ── Indicador visual de criterio de contraseña ───────────────────────────
  Widget _adminPwCriterion(bool met, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Icon(
          met ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
          size: 15,
          color: met ? context.tokens.success : context.tokens.muted,
        ),
        const SizedBox(width: 6),
        Text(
          text,
          style: GoogleFonts.poppins(
            fontSize: 11,
            color: met ? context.tokens.success : context.tokens.muted,
          ),
        ),
      ]),
    );
  }

  // ── Helpers de criterios de contraseña ───────────────────────────────────

  /// Longitud entre 8 y 64 caracteres.
  bool _adminPwLen(String p)    => p.length >= 8 && p.length <= 64;
  /// Contiene al menos un número.
  bool _adminPwNum(String p)    => p.contains(RegExp(r'[0-9]'));
  /// Contiene al menos una minúscula.
  bool _adminPwLower(String p)  => p.contains(RegExp(r'[a-z]'));
  /// Contiene al menos una mayúscula.
  bool _adminPwUpper(String p)  => p.contains(RegExp(r'[A-Z]'));
  /// Contiene al menos un símbolo especial.
  bool _adminPwSym(String p)    =>
      p.contains(RegExp(r"""[!@#$%^&*()\-_=+\[\]{};:'",./<>?\\|`~]"""));
  /// No incluye el nombre de usuario.
  bool _adminPwNoUser(String p, String uname) {
    final u = uname.trim().toLowerCase();
    return u.isEmpty || !p.toLowerCase().contains(u);
  }

  /// Retorna el primer mensaje de error si la contraseña no cumple los 6
  /// criterios. Retorna null si todo está bien.
  String? _adminPwError(String p, String uname) {
    if (!_adminPwLen(p))       return 'La contraseña debe tener entre 8 y 64 caracteres';
    if (!_adminPwNum(p))       return 'La contraseña debe tener al menos un número';
    if (!_adminPwLower(p))     return 'La contraseña debe tener al menos una letra minúscula';
    if (!_adminPwUpper(p))     return 'La contraseña debe tener al menos una letra mayúscula';
    if (!_adminPwSym(p))       return 'La contraseña debe tener al menos un símbolo (!@#\$%...)';
    if (!_adminPwNoUser(p, uname)) return 'La contraseña no debe incluir el nombre de usuario';
    return null;
  }

  // ── Validación de contraseña segura (usada por el formulario) ─────────────
  String? _validatePassword(String? v, {bool required = true}) {
    if (v == null || v.isEmpty) return required ? 'Requerido' : null;
    if (v.length < 8 || v.length > 64) return 'Entre 8 y 64 caracteres';
    if (!RegExp(r'[A-Z]').hasMatch(v))  return 'Debe incluir una mayúscula';
    if (!RegExp(r'[a-z]').hasMatch(v))  return 'Debe incluir una minúscula';
    if (!RegExp(r'[0-9]').hasMatch(v))  return 'Debe incluir un número';
    if (!_adminPwSym(v))                return 'Debe incluir un símbolo (!@#\$%...)';
    return null;
  }

  // ── Diálogo crear/editar usuario ─────────────────────────────────────────
  void _showUserDialog({UserModel? user}) {
    final nameCtrl = TextEditingController(text: user?.username ?? '');
    final passCtrl = TextEditingController();
    String selectedRol = user?.rol ?? 'Student';
    final formKey = GlobalKey<FormState>();
    bool showPass = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          // Calcular si todos los criterios están cumplidos en este frame.
          // Se evalúa aquí (nivel StatefulBuilder) para que tanto el indicador
          // visual como el botón Guardar lean el mismo valor actualizado.
          final pass  = passCtrl.text;
          final uname = nameCtrl.text;
          final contrasenaIngresada = pass.isNotEmpty || user == null;
          final criteriosOk = !contrasenaIngresada ||
              _adminPwError(pass, uname) == null;

          return Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            decoration: BoxDecoration(
              color: Theme.of(context).dialogTheme.backgroundColor,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 40,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header con gradiente
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: user == null
                          ? [const Color(0xFF1D4ED8), const Color(0xFF4F46E5)]
                          : [const Color(0xFF047857), const Color(0xFF0369A1)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(28),
                      topRight: Radius.circular(28),
                    ),
                  ),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        user == null
                            ? Icons.person_add_rounded
                            : Icons.edit_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user == null ? 'Nuevo Usuario' : 'Editar Usuario',
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          user == null
                              ? 'Completa los campos requeridos'
                              : 'Modifica los datos del usuario',
                          style: GoogleFonts.poppins(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ]),
                ),
                // Formulario
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: formKey,
                    child: Column(
                      children: [
                        // Campo usuario
                        TextFormField(
                          controller: nameCtrl,
                          textInputAction: TextInputAction.next,
                          style: GoogleFonts.poppins(fontSize: 14),
                          decoration: InputDecoration(
                            labelText: 'Nombre de usuario',
                            labelStyle:
                                GoogleFonts.poppins(fontSize: 13),
                            prefixIcon: const Icon(Icons.person_outline_rounded,
                                color: Color(0xFF1D4ED8)),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14)),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(
                                  color: Color(0xFF1D4ED8), width: 2),
                            ),
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty)
                              return 'Requerido';
                            if (v.trim().length < 3) return 'Mínimo 3 caracteres';
                            if (v.trim().length > 50)
                              return 'Máximo 50 caracteres';
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        // Campo contraseña con indicador de 6 criterios en tiempo real
                        Builder(builder: (_) {
                          final pass  = passCtrl.text;
                          final uname = nameCtrl.text;

                          // Evaluar los 6 criterios individualmente
                          final c1 = _adminPwLen(pass);
                          final c2 = _adminPwNum(pass);
                          final c3 = _adminPwLower(pass);
                          final c4 = _adminPwUpper(pass);
                          final c5 = _adminPwSym(pass);
                          final c6 = _adminPwNoUser(pass, uname);

                          final passed = [c1, c2, c3, c4, c5, c6]
                              .where((x) => x).length;

                          // Color de las 6 barras según criterios cumplidos
                          final barColor = passed <= 2
                              ? context.tokens.danger
                              : passed <= 3
                                  ? context.tokens.warning
                                  : passed <= 4
                                      ? context.tokens.warning
                                      : passed <= 5
                                          ? Colors.lightGreen
                                          : context.tokens.success;

                          // criteriosOk se calcula a nivel StatefulBuilder para
                          // que tanto este indicador como el botón Guardar lo lean.
                          // No se redeclara aquí para evitar shadowing.

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              TextFormField(
                                controller: passCtrl,
                                obscureText: !showPass,
                                textInputAction: TextInputAction.next,
                                style: GoogleFonts.poppins(fontSize: 14),
                                onChanged: (_) => setS(() {}),
                                decoration: InputDecoration(
                                  labelText: user == null
                                      ? 'Contraseña'
                                      : 'Nueva contraseña (vacío = no cambiar)',
                                  labelStyle: GoogleFonts.poppins(fontSize: 12),
                                  prefixIcon: const Icon(
                                      Icons.lock_outline_rounded,
                                      color: Color(0xFF4F46E5)),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      showPass
                                          ? Icons.visibility_off_rounded
                                          : Icons.visibility_rounded,
                                      color: context.tokens.muted,
                                    ),
                                    onPressed: () =>
                                        setS(() => showPass = !showPass),
                                  ),
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14)),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: const BorderSide(
                                        color: Color(0xFF4F46E5), width: 2),
                                  ),
                                ),
                                validator: (v) =>
                                    _validatePassword(v, required: user == null),
                              ),

                              // Indicador de fortaleza — aparece al escribir
                              if (pass.isNotEmpty) ...[
                                const SizedBox(height: 8),

                                // 6 barras de color según criterios cumplidos
                                Row(
                                  children: List.generate(6, (i) => Expanded(
                                    child: Container(
                                      margin: const EdgeInsets.symmetric(
                                          horizontal: 2),
                                      height: 4,
                                      decoration: BoxDecoration(
                                        color: i < passed
                                            ? barColor
                                            : context.tokens.border,
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                  )),
                                ),
                                const SizedBox(height: 6),

                                // Lista de los 6 criterios con check verde / círculo gris
                                _adminPwCriterion(c1, '8-64 caracteres'),
                                _adminPwCriterion(c2, 'Al menos un número'),
                                _adminPwCriterion(c3, 'Al menos una letra minúscula'),
                                _adminPwCriterion(c4, 'Al menos una letra mayúscula'),
                                _adminPwCriterion(c5, 'Al menos un símbolo (!@#\$%...)'),
                                _adminPwCriterion(c6, 'No incluir el nombre de usuario'),
                              ],

                            ],
                          );
                        }),
                        const SizedBox(height: 16),
                        // Selector de rol
                        DropdownButtonFormField<String>(
                          value: selectedRol,
                          style: GoogleFonts.poppins(
                              fontSize: 14, color: Theme.of(context).colorScheme.onSurface),
                          decoration: InputDecoration(
                            labelText: 'Rol',
                            labelStyle: GoogleFonts.poppins(fontSize: 13),
                            prefixIcon: const Icon(
                                Icons.badge_rounded,
                                color: Color(0xFF047857)),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14)),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(
                                  color: Color(0xFF047857), width: 2),
                            ),
                          ),
                          items: const [
                            DropdownMenuItem(
                                value: 'Student',
                                child: Text('Estudiante')),
                            DropdownMenuItem(
                                value: 'Teacher',
                                child: Text('Profesor')),
                            DropdownMenuItem(
                                value: 'Admin',
                                child: Text('Administrador')),
                          ],
                          onChanged: (v) => selectedRol = v!,
                        ),
                        const SizedBox(height: 24),
                        // Botones
                        Row(children: [
                          Expanded(
                            child: TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              style: TextButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14)),
                              ),
                              child: Text('Cancelar',
                                  style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.w600)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: Container(
                              height: 48,
                              decoration: BoxDecoration(
                                // Gradiente gris cuando los criterios no se cumplen;
                                // gradiente de color cuando el botón está habilitado.
                                gradient: LinearGradient(
                                  colors: criteriosOk
                                      ? (user == null
                                          ? [const Color(0xFF1D4ED8),
                                             const Color(0xFF4F46E5)]
                                          : [const Color(0xFF047857),
                                             const Color(0xFF0369A1)])
                                      : [context.tokens.muted,
                                         context.tokens.muted],
                                ),
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: criteriosOk
                                    ? [
                                        BoxShadow(
                                          color: (user == null
                                                  ? const Color(0xFF1D4ED8)
                                                  : const Color(0xFF047857))
                                              .withValues(alpha: 0.35),
                                          blurRadius: 12,
                                          offset: const Offset(0, 4),
                                        ),
                                      ]
                                    : [],
                              ),
                              child: Material(
                                color: Colors.transparent,
                                borderRadius: BorderRadius.circular(14),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(14),
                                  onTap: () async {
                                    // Si los criterios de contraseña no se cumplen,
                                    // mostrar mensaje específico y bloquear el guardado.
                                    if (!criteriosOk) {
                                      final error = _adminPwError(
                                          passCtrl.text, nameCtrl.text);
                                      if (error != null && mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(SnackBar(
                                          content: Text(error,
                                              style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 13)),
                                          backgroundColor: context.tokens.danger,
                                          duration:
                                              const Duration(seconds: 3),
                                          behavior: SnackBarBehavior.floating,
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12)),
                                          margin: const EdgeInsets.all(16),
                                        ));
                                      }
                                      return;
                                    }

                                    if (!formKey.currentState!.validate())
                                      return;
                                    final trimmed = nameCtrl.text.trim();
                                    if (_isDuplicateUsername(trimmed,
                                        excludeId: user?.id)) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(SnackBar(
                                        content: Text(
                                            'Ya existe un usuario "$trimmed"'),
                                        backgroundColor: context.tokens.danger,
                                      ));
                                      return;
                                    }
                                    Navigator.pop(ctx);
                                    try {
                                      if (user == null) {
                                        await ApiService().addUser(
                                            trimmed, passCtrl.text, selectedRol);
                                      } else {
                                        // Vacío = no cambiar la contraseña: el servidor ya
                                        // no entrega las actuales (solo guarda su cifrado).
                                        await ApiService().editUser(user.id,
                                            trimmed, passCtrl.text, selectedRol);
                                      }
                                    } on ApiMessageException catch (e) {
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                          content: Text(e.message),
                                          backgroundColor: context.tokens.danger,
                                        ));
                                      }
                                      return;
                                    }
                                    await _loadUsers();
                                    if (mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(SnackBar(
                                        content: Text(user == null
                                            ? 'Usuario "$trimmed" creado'
                                            : 'Usuario "$trimmed" actualizado'),
                                        backgroundColor: context.tokens.success,
                                      ));
                                    }
                                  },
                                  child: Center(
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          user == null
                                              ? Icons.add_circle_rounded
                                              : Icons.save_rounded,
                                          color: Colors.white,
                                          size: 18,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          user == null ? 'Crear' : 'Guardar',
                                          style: GoogleFonts.poppins(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ]),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );       // cierra return Dialog(...)
        },       // cierra el bloque body del builder de StatefulBuilder
      ),         // cierra StatefulBuilder(
    );           // cierra showDialog(
  }

  // ── Eliminar usuario ──────────────────────────────────────────────────────
  Future<void> _deleteUser(UserModel user) async {
    if (user.rol == 'Admin') {
      await showDialog(
        context: context,
        builder: (ctx) => Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Container(
            padding: const EdgeInsets.all(28),
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: context.tokens.typeOtro.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.shield_rounded,
                    color: context.tokens.typeOtro, size: 32),
              ),
              const SizedBox(height: 16),
              Text('Acción no permitida',
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700, fontSize: 18)),
              const SizedBox(height: 8),
              Text(
                'Los administradores no pueden eliminarse por motivos de seguridad.',
                style: GoogleFonts.poppins(
                    fontSize: 13, color: context.tokens.muted),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.tokens.typeOtro,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text('Entendido',
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600, color: Colors.white)),
                ),
              ),
            ]),
          ),
        ),
      );
      return;
    }

    int cursosActivos = 0;
    if (user.rol == 'Teacher') {
      try {
        cursosActivos = await ApiService().getCursosPorProfesor(user.id);
      } catch (_) {}
    }
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          padding: const EdgeInsets.all(28),
          constraints: const BoxConstraints(maxWidth: 380),
          child:
              Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: context.tokens.danger.withValues(alpha: 0.10), shape: BoxShape.circle),
              child: Icon(Icons.delete_forever_rounded,
                  color: context.tokens.danger, size: 32),
            ),
            const SizedBox(height: 16),
            Text('Eliminar Usuario',
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700, fontSize: 18)),
            const SizedBox(height: 8),
            Text('¿Eliminar a "${user.username}"?',
                style: GoogleFonts.poppins(fontSize: 14),
                textAlign: TextAlign.center),
            if (cursosActivos > 0) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.tokens.warning.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.tokens.warning.withValues(alpha: 0.35)),
                ),
                child: Row(children: [
                  Icon(Icons.warning_amber_rounded,
                      color: context.tokens.warning, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Tiene $cursosActivos curso(s) asignados que quedarán sin profesor.',
                      style: GoogleFonts.poppins(
                          fontSize: 12, color: context.tokens.warning),
                    ),
                  ),
                ]),
              ),
            ] else ...[
              const SizedBox(height: 8),
              Text('Esta acción no se puede deshacer.',
                  style: GoogleFonts.poppins(
                      fontSize: 12, color: context.tokens.muted)),
            ],
            const SizedBox(height: 24),
            Row(children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text('Cancelar',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.tokens.danger,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(
                    cursosActivos > 0 ? 'Eliminar' : 'Eliminar',
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );

    if (confirmed == true) {
      try {
        await ApiService().deleteUser(user.id);
      } on ApiMessageException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.message),
            backgroundColor: context.tokens.danger,
          ));
        }
        return;
      }
      await _loadUsers();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Usuario "${user.username}" eliminado'),
          backgroundColor: context.tokens.warning,
        ));
      }
    }
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestión de Usuarios'),
        leading: IconButton(
          tooltip: 'Regresar',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          Semantics(
            label: '${_filtered.length} usuarios',
            child: ExcludeSemantics(
              child: Container(
                margin: const EdgeInsets.only(right: 16, top: 10, bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${_filtered.length} usuarios',
                  style: GoogleFonts.poppins(
                      color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showUserDialog(),
        icon: const Icon(PhosphorIconsRegular.userPlus),
        label: Text('Nuevo usuario',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            children: [
              // ── Barra búsqueda + filtro ────────────────────────────────
              Padding(
                padding: const EdgeInsets.all(16),
                child: AppCard(
                  blur: false,
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    TextField(
                      controller: _searchCtrl,
                      style: GoogleFonts.poppins(fontSize: 14),
                      decoration: const InputDecoration(
                        hintText: 'Buscar usuario...',
                        prefixIcon: Icon(PhosphorIconsRegular.magnifyingGlass),
                        isDense: true,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      onChanged: (_) => _applyFilter(),
                    ),
                    const SizedBox(height: 12),
                    // Filtro de roles como chips (se ajusta en pantallas angostas)
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      _rolChip('Todos', t.muted),
                      _rolChip('Admin', t.chart[3]),
                      _rolChip('Teacher', t.chart[1]),
                      _rolChip('Student', t.chart[0]),
                    ]),
                  ]),
                ),
              ),

              // ── Grid de tarjetas ───────────────────────────────────────
              Expanded(
                child: _loading
                    ? Semantics(
                        label: 'Cargando usuarios',
                        child: ExcludeSemantics(
                          child: GridView.count(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                            crossAxisCount: 2,
                            crossAxisSpacing: 14,
                            mainAxisSpacing: 14,
                            childAspectRatio: 0.85,
                            children: List.generate(
                                4, (_) => const SkeletonBox(height: 160)),
                          ),
                        ),
                      )
                    : _filtered.isEmpty
                        ? const EmptyState(
                            icon: PhosphorIconsRegular.users,
                            message: 'No se encontraron usuarios',
                          )
                        : LayoutBuilder(builder: (ctx, constraints) {
                            final cross = constraints.maxWidth > 900
                                ? 4
                                : constraints.maxWidth > 600
                                    ? 3
                                    : constraints.maxWidth > 400
                                        ? 2
                                        : 1;
                            return GridView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: cross,
                                crossAxisSpacing: 14,
                                mainAxisSpacing: 14,
                                childAspectRatio: 0.85,
                              ),
                              itemCount: _filtered.length,
                              itemBuilder: (ctx, i) => _UserCard(
                                user: _filtered[i],
                                gradient: _rolGradient(_filtered[i].rol),
                                rolIcon: _rolIcon(_filtered[i].rol),
                                rolLabel: _rolLabel(_filtered[i].rol),
                                onEdit: () => _showUserDialog(user: _filtered[i]),
                                onDelete: () => _deleteUser(_filtered[i]),
                                index: i,
                              ),
                            );
                          }),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _rolChip(String rol, Color color) {
    final selected = _rolFilter == rol;
    final label = rol == 'Todos'
        ? 'Todos'
        : rol == 'Admin'
            ? 'Administradores'
            : rol == 'Teacher'
                ? 'Profesores'
                : 'Estudiantes';
    return Semantics(
      button: true,
      selected: selected,
      label: 'Filtrar: $label',
      child: ExcludeSemantics(
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            _rolFilter = rol;
            _applyFilter();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? color : color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: selected ? color : color.withValues(alpha: 0.35)),
            ),
            child: Text(
              label,
              style: GoogleFonts.poppins(
                color: selected ? Colors.white : color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Tarjeta de usuario ────────────────────────────────────────────────────
class _UserCard extends StatefulWidget {
  final UserModel user;
  final List<Color> gradient;
  final IconData rolIcon;
  final String rolLabel;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final int index;

  const _UserCard({
    required this.user,
    required this.gradient,
    required this.rolIcon,
    required this.rolLabel,
    required this.onEdit,
    required this.onDelete,
    required this.index,
  });

  @override
  State<_UserCard> createState() => _UserCardState();
}

class _UserCardState extends State<_UserCard>
    with SingleTickerProviderStateMixin {
  bool _hovered = false;
  late AnimationController _ctrl;
  late Animation<double> _entry;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 450));
    _entry = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack);
    Future.delayed(Duration(milliseconds: 50 * widget.index.clamp(0, 20)),
        () { if (mounted) _ctrl.forward(); });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _entry,
      builder: (_, child) => Transform.translate(
        offset: Offset(0, 20 * (1 - _entry.value)),
        child: Opacity(opacity: _entry.value.clamp(0.0, 1.0), child: child),
      ),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedScale(
          scale: _hovered ? 1.03 : 1.0,
          duration: const Duration(milliseconds: 180),
          child: Container(
            decoration: BoxDecoration(
              color: context.tokens.glass,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: widget.gradient[0]
                      .withValues(alpha: _hovered ? 0.30 : 0.10),
                  blurRadius: _hovered ? 24 : 8,
                  offset: Offset(0, _hovered ? 8 : 3),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Column(
                children: [
                  // ── Header con gradiente ────────────────────────────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: widget.gradient,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Column(children: [
                      // Avatar con inicial
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.22),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.5),
                              width: 2.5),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            widget.user.username.isEmpty ? "?" : widget.user.username[0].toUpperCase(),
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Nombre
                      Text(
                        widget.user.username,
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      // Badge de rol
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(widget.rolIcon,
                                color: Colors.white, size: 12),
                            const SizedBox(width: 4),
                            Text(
                              widget.rolLabel,
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ]),
                  ),
                  // ── Botones de acción ──────────────────────────────
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(children: [
                        Expanded(
                          child: _actionButton(
                            icon: Icons.edit_rounded,
                            label: 'Editar',
                            color: widget.gradient[0],
                            onTap: widget.onEdit,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _actionButton(
                            icon: Icons.delete_rounded,
                            label: 'Eliminar',
                            color: const Color(0xFFDC2626),
                            onTap: widget.onDelete,
                          ),
                        ),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2), width: 1.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 3),
            Text(label,
                style: GoogleFonts.poppins(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                )),
          ],
        ),
      ),
    );
  }
}
