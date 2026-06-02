import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/api_service.dart';
import '../../models/user_model.dart';

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
        return [const Color(0xFF7C3AED), const Color(0xFFDB2777)];
      case 'Teacher':
        return [const Color(0xFF059669), const Color(0xFF0EA5E9)];
      default:
        return [const Color(0xFF2563EB), const Color(0xFF7C3AED)];
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
          color: met ? Colors.green : Colors.grey.shade400,
        ),
        const SizedBox(width: 6),
        Text(
          text,
          style: GoogleFonts.poppins(
            fontSize: 11,
            color: met ? Colors.green.shade700 : Colors.grey.shade500,
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
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.18),
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
                          ? [const Color(0xFF2563EB), const Color(0xFF7C3AED)]
                          : [const Color(0xFF059669), const Color(0xFF0EA5E9)],
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
                        color: Colors.white.withOpacity(0.2),
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
                                color: Color(0xFF2563EB)),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14)),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(
                                  color: Color(0xFF2563EB), width: 2),
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
                              ? Colors.red
                              : passed <= 3
                                  ? Colors.orange
                                  : passed <= 4
                                      ? Colors.yellow.shade700
                                      : passed <= 5
                                          ? Colors.lightGreen
                                          : Colors.green;

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
                                      color: Color(0xFF7C3AED)),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      showPass
                                          ? Icons.visibility_off_rounded
                                          : Icons.visibility_rounded,
                                      color: Colors.grey,
                                    ),
                                    onPressed: () =>
                                        setS(() => showPass = !showPass),
                                  ),
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14)),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: const BorderSide(
                                        color: Color(0xFF7C3AED), width: 2),
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
                                            : Colors.grey.shade200,
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
                              fontSize: 14, color: Colors.black87),
                          decoration: InputDecoration(
                            labelText: 'Rol',
                            labelStyle: GoogleFonts.poppins(fontSize: 13),
                            prefixIcon: const Icon(
                                Icons.badge_rounded,
                                color: Color(0xFF059669)),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14)),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(
                                  color: Color(0xFF059669), width: 2),
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
                                          ? [const Color(0xFF2563EB),
                                             const Color(0xFF7C3AED)]
                                          : [const Color(0xFF059669),
                                             const Color(0xFF0EA5E9)])
                                      : [Colors.grey.shade400,
                                         Colors.grey.shade500],
                                ),
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: criteriosOk
                                    ? [
                                        BoxShadow(
                                          color: (user == null
                                                  ? const Color(0xFF2563EB)
                                                  : const Color(0xFF059669))
                                              .withOpacity(0.35),
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
                                          backgroundColor: Colors.red.shade700,
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
                                        backgroundColor: Colors.red,
                                      ));
                                      return;
                                    }
                                    Navigator.pop(ctx);
                                    if (user == null) {
                                      await ApiService().addUser(
                                          trimmed, passCtrl.text, selectedRol);
                                    } else {
                                      final pass = passCtrl.text.isEmpty
                                          ? user.pass ?? ''
                                          : passCtrl.text;
                                      await ApiService().editUser(
                                          user.id, trimmed, pass, selectedRol);
                                    }
                                    await _loadUsers();
                                    if (mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(SnackBar(
                                        content: Text(user == null
                                            ? 'Usuario "$trimmed" creado'
                                            : 'Usuario "$trimmed" actualizado'),
                                        backgroundColor: Colors.green,
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
                  color: Colors.purple.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.shield_rounded,
                    color: Colors.purple.shade700, size: 32),
              ),
              const SizedBox(height: 16),
              Text('Acción no permitida',
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700, fontSize: 18)),
              const SizedBox(height: 8),
              Text(
                'Los administradores no pueden eliminarse por motivos de seguridad.',
                style: GoogleFonts.poppins(
                    fontSize: 13, color: Colors.grey.shade600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple.shade700,
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
                  color: Colors.red.shade50, shape: BoxShape.circle),
              child: Icon(Icons.delete_forever_rounded,
                  color: Colors.red.shade600, size: 32),
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
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.shade300),
                ),
                child: Row(children: [
                  Icon(Icons.warning_amber_rounded,
                      color: Colors.amber.shade800, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Tiene $cursosActivos curso(s) asignados que quedarán sin profesor.',
                      style: GoogleFonts.poppins(
                          fontSize: 12, color: Colors.amber.shade900),
                    ),
                  ),
                ]),
              ),
            ] else ...[
              const SizedBox(height: 8),
              Text('Esta acción no se puede deshacer.',
                  style: GoogleFonts.poppins(
                      fontSize: 12, color: Colors.grey.shade500)),
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
                    backgroundColor: Colors.red.shade600,
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
      await ApiService().deleteUser(user.id);
      await _loadUsers();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Usuario "${user.username}" eliminado'),
          backgroundColor: Colors.orange,
        ));
      }
    }
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1E1B4B), Color(0xFF2563EB)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: Text('Gestión de Usuarios',
            style: GoogleFonts.poppins(
                color: Colors.white, fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16, top: 8, bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${_filtered.length} usuarios',
              style: GoogleFonts.poppins(
                  color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showUserDialog(),
        backgroundColor: const Color(0xFF2563EB),
        elevation: 6,
        icon: const Icon(Icons.person_add_rounded, color: Colors.white),
        label: Text('Nuevo Usuario',
            style: GoogleFonts.poppins(
                color: Colors.white, fontWeight: FontWeight.w700)),
      ),
      body: Column(
        children: [
          // ── Barra búsqueda + filtro ────────────────────────────────────
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  style: GoogleFonts.poppins(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Buscar usuario...',
                    hintStyle: GoogleFonts.poppins(
                        fontSize: 13, color: Colors.grey.shade400),
                    prefixIcon: const Icon(Icons.search_rounded,
                        color: Color(0xFF2563EB)),
                    filled: true,
                    fillColor: const Color(0xFFF0F4FF),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                  ),
                  onChanged: (_) => _applyFilter(),
                ),
              ),
              const SizedBox(width: 12),
              // Filtro de roles como chips
              _rolChip('Todos', Colors.grey),
              _rolChip('Admin', const Color(0xFF7C3AED)),
              _rolChip('Teacher', const Color(0xFF059669)),
              _rolChip('Student', const Color(0xFF2563EB)),
            ]),
          ),

          // ── Grid de tarjetas ──────────────────────────────────────────
          Expanded(
            child: _loading
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(
                            color: Color(0xFF2563EB)),
                        const SizedBox(height: 16),
                        Text('Cargando usuarios...',
                            style: GoogleFonts.poppins(color: Colors.grey)),
                      ],
                    ),
                  )
                : _filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.people_outline_rounded,
                                size: 80,
                                color: Colors.grey.shade300),
                            const SizedBox(height: 16),
                            Text('No se encontraron usuarios',
                                style: GoogleFonts.poppins(
                                    color: Colors.grey.shade400,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
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
                          itemBuilder: (ctx, i) =>
                              _UserCard(
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
    );
  }

  Widget _rolChip(String rol, Color color) {
    final selected = _rolFilter == rol;
    return GestureDetector(
      onTap: () {
        _rolFilter = rol;
        _applyFilter();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color : color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? color : color.withOpacity(0.2), width: 1.5),
        ),
        child: Text(
          rol == 'Todos'
              ? 'Todos'
              : rol == 'Admin'
                  ? 'Admin'
                  : rol == 'Teacher'
                      ? 'Prof.'
                      : 'Est.',
          style: GoogleFonts.poppins(
            color: selected ? Colors.white : color,
            fontSize: 11,
            fontWeight: FontWeight.w700,
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
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: widget.gradient[0]
                      .withOpacity(_hovered ? 0.30 : 0.10),
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
                          color: Colors.white.withOpacity(0.22),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: Colors.white.withOpacity(0.5),
                              width: 2.5),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.15),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            widget.user.username[0].toUpperCase(),
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
                          color: Colors.white.withOpacity(0.22),
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
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2), width: 1.5),
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
