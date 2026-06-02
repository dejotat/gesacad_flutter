import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../services/api_service.dart';

/// Pantalla para crear una nueva actividad evaluable en un curso (CU-04 / RF06, RF07).
///
/// Implementa las siguientes validaciones de caja blanca:
///
/// | ID    | Regla de validación                                   | Mensaje de error                             |
/// |-------|-------------------------------------------------------|----------------------------------------------|
/// | CA-01 | Título no puede ser vacío                             | "Campo requerido"                            |
/// | CA-02 | Descripción no puede ser vacía                        | "Campo requerido"                            |
/// | CA-03 | Ponderado vacío o no numérico                         | "Requerido"                                  |
/// | CA-04 | Ponderado ≤ 0 o > 100                                 | "Entre 1 y 100"                              |
/// | CA-05 | Ponderado > disponible en el curso (RF07)             | SnackBar rojo con el máximo disponible       |
/// | CA-06 | Fecha de cierre anterior a la de inicio               | SnackBar rojo con instrucción                |
/// | CA-07 | Ponderado disponible = 0%                             | Banner rojo, usuario no puede crear más      |
///
/// Accesibilidad (CU-07): todos los campos de formulario tienen [Semantics]
/// con label y hint compatibles con TalkBack.
class AddActivityScreen extends StatefulWidget {
  /// ID del curso al que pertenecerá la nueva actividad.
  final int courseId;

  /// ID del profesor que crea la actividad.
  final int teacherId;

  const AddActivityScreen(
      {super.key, required this.courseId, required this.teacherId});

  @override
  State<AddActivityScreen> createState() => _AddActivityScreenState();
}

class _AddActivityScreenState extends State<AddActivityScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();

  String _type = 'midterm';
  int _week = 1;
  DateTime _startDate = DateTime.now();
  DateTime _closeDate = DateTime.now().add(const Duration(days: 7));
  // Hora de apertura — por defecto 00:00 (disponible desde el inicio del día).
  TimeOfDay _startTime = const TimeOfDay(hour: 0, minute: 0);
  // Hora de cierre — por defecto 11:59 PM para dar el día completo al estudiante.
  TimeOfDay _closeTime = const TimeOfDay(hour: 23, minute: 59);
  bool _loading = false;
  List<Map<String, dynamic>> _archivos = [];

  /// Porcentaje de ponderado ya usado en el curso (obtenido del backend).
  double _usedWeighting = 0;

  /// Ponderado ingresado en tiempo real para mostrar feedback inmediato.
  double _inputWeight = 0;

  @override
  void initState() {
    super.initState();
    _loadWeighting();
    // Escuchar cambios en el campo de ponderado para feedback en tiempo real.
    _weightCtrl.addListener(_onWeightChanged);
  }

  @override
  void dispose() {
    _weightCtrl.removeListener(_onWeightChanged);
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _weightCtrl.dispose();
    super.dispose();
  }

  /// Obtiene el ponderado ya usado en el curso desde el backend (RF07).
  Future<void> _loadWeighting() async {
    try {
      _usedWeighting = await ApiService().getWeightingMax(widget.courseId);
      if (mounted) setState(() {});
    } catch (_) {
      // Si falla, se asume 0% usado (no bloquear al usuario por error de red).
    }
  }

  void _onWeightChanged() {
    final v = double.tryParse(_weightCtrl.text) ?? 0;
    if (v != _inputWeight) {
      setState(() => _inputWeight = v);
    }
  }

  /// Abre el selector de archivos y agrega los seleccionados a [_archivos].
  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.any,
    );
    if (result == null) return;
    final nuevos = result.files
        .where((f) => f.bytes != null && f.name.isNotEmpty)
        .map((f) => {'name': f.name, 'bytes': f.bytes as Uint8List})
        .toList();
    if (nuevos.isNotEmpty) {
      setState(() => _archivos.addAll(nuevos));
    }
  }

  /// Abre el selector de fecha para inicio o cierre.
  Future<void> _pickDate(bool isStart) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : _closeDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
        } else {
          _closeDate = picked;
        }
      });
    }
  }

  /// Abre el selector de hora para la fecha de inicio.
  Future<void> _pickStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime,
      helpText: 'Hora de apertura de la actividad',
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: false),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _startTime = picked);
  }

  /// Abre el selector de hora para la fecha de cierre.
  Future<void> _pickCloseTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _closeTime,
      helpText: 'Hora límite de entrega',
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: false),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _closeTime = picked);
  }

  /// Formatea fecha de inicio con la hora elegida por el profesor.
  String _formatStartDate(DateTime d, TimeOfDay t) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}'
      'T${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  /// Formatea fecha de cierre con la hora elegida por el profesor.
  String _formatCloseDate(DateTime d, TimeOfDay t) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}'
      'T${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  /// Guarda la nueva actividad en el backend tras superar todas las validaciones.
  ///
  /// Validaciones previas al envío:
  /// 1. Formulario válido (CA-01 a CA-04).
  /// 2. Ponderado no supera el disponible (CA-05 / RF07).
  /// 3. Fecha de cierre posterior a inicio (CA-06).
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final weight = double.tryParse(_weightCtrl.text) ?? 0;
    final available = 100 - _usedWeighting;

    // CA-05: verificar que el ponderado no supere el disponible (RF07).
    if (weight > available) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'El ponderado excede el disponible. Máximo permitido: ${available.toStringAsFixed(0)}%'),
          backgroundColor: Colors.red));
      return;
    }

    // CA-06a: fecha de cierre no puede ser anterior a hoy.
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    final closeOnly = DateTime(_closeDate.year, _closeDate.month, _closeDate.day);
    if (closeOnly.isBefore(todayOnly)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'La fecha de cierre no puede ser anterior a hoy'),
          backgroundColor: Colors.red));
      return;
    }

    // CA-06b: el cierre completo (fecha+hora) debe ser posterior al inicio completo (fecha+hora).
    final inicioCompleto = DateTime(
      _startDate.year, _startDate.month, _startDate.day,
      _startTime.hour, _startTime.minute,
    );
    final cierreCompleto = DateTime(
      _closeDate.year, _closeDate.month, _closeDate.day,
      _closeTime.hour, _closeTime.minute,
    );
    if (!cierreCompleto.isAfter(inicioCompleto)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('La fecha y hora de cierre deben ser posteriores a las de inicio'),
          backgroundColor: Colors.red));
      return;
    }

    setState(() => _loading = true);
    try {
      await ApiService().addActivity(
        week: _week,
        type: _type,
        tittle: _titleCtrl.text.trim(),
        description: _descCtrl.text.trim(),
        weighting: weight / 100,
        startDate:   _formatStartDate(_startDate, _startTime),
        closingDate: _formatCloseDate(_closeDate, _closeTime),
        courseId: widget.courseId,
        teacherId: widget.teacherId,
        archivos: _archivos,
      );
      if (mounted) {
        // Capturar messenger antes de salir de la pantalla para evitar
        // usar BuildContext a través de gaps asíncronos.
        final messenger = ScaffoldMessenger.of(context);

        messenger.showSnackBar(const SnackBar(
            content: Text('Actividad creada exitosamente'),
            backgroundColor: Colors.green));

        // Informar al profesor que los archivos adjuntos no se subieron aún.
        // El endpoint del backend no acepta archivos; se subirán en versión futura.
        if (_archivos.isNotEmpty) {
          messenger.showSnackBar(const SnackBar(
            content: Text(
                '📎 Actividad creada. La subida de archivos adjuntos '
                'estará disponible próximamente desde el detalle de la actividad.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
          ));
        }

        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error al crear actividad: $e'),
            backgroundColor: Colors.red));
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final available = 100 - _usedWeighting;
    // Ponderado que quedaría disponible luego de crear esta actividad.
    final remaining = available - _inputWeight;

    return Scaffold(
      appBar: AppBar(title: const Text('Nueva Actividad')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Banner de ponderado disponible (CA-07 — RF07).
            Semantics(
              label: available > 0
                  ? 'Ponderado disponible en este curso: ${available.toStringAsFixed(0)} por ciento'
                  : 'No hay ponderado disponible. El curso ya tiene 100 por ciento asignado.',
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: available > 0
                      ? Colors.green.shade50
                      : Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: available > 0 ? Colors.green : Colors.red),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          available > 0 ? Icons.check_circle : Icons.warning,
                          color: available > 0 ? Colors.green : Colors.red,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Ponderado disponible: ${available.toStringAsFixed(0)}%',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: available > 0
                                  ? Colors.green.shade800
                                  : Colors.red),
                        ),
                      ],
                    ),
                    // Feedback en tiempo real del ponderado restante (RF07).
                    if (_inputWeight > 0 && available > 0) ...[
                      const SizedBox(height: 6),
                      Text(
                        remaining >= 0
                            ? 'Tras crear esta actividad quedaría disponible: ${remaining.toStringAsFixed(0)}%'
                            : '⚠ El ponderado ingresado supera el disponible en ${(-remaining).toStringAsFixed(0)}%',
                        style: TextStyle(
                            fontSize: 12,
                            color: remaining >= 0
                                ? Colors.green.shade700
                                : Colors.red),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // CA-01: Campo Título.
            Semantics(
              label: 'Campo título de la actividad',
              hint: 'Ingresa el nombre de la actividad',
              textField: true,
              child: TextFormField(
                controller: _titleCtrl,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Título de la actividad *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.title),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Campo requerido';
                  if (v.trim().length < 3) return 'Mínimo 3 caracteres';
                  if (v.trim().length > 120) return 'Máximo 120 caracteres';
                  return null;
                },
              ),
            ),

            const SizedBox(height: 16),

            // CA-02: Campo Descripción.
            Semantics(
              label: 'Campo descripción de la actividad',
              hint: 'Ingresa las instrucciones para los estudiantes',
              textField: true,
              child: TextFormField(
                controller: _descCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Descripción *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.description),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Campo requerido' : null,
              ),
            ),

            const SizedBox(height: 16),

            // Tipo de actividad.
            Semantics(
              label: 'Selector de tipo de actividad',
              child: DropdownButtonFormField<String>(
                value: _type,
                decoration: const InputDecoration(
                  labelText: 'Tipo de actividad',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.category),
                ),
                items: const [
                  DropdownMenuItem(value: 'midterm', child: Text('Parcial')),
                  DropdownMenuItem(
                      value: 'project', child: Text('Proyecto')),
                  DropdownMenuItem(
                      value: 'resource',
                      child: Text('Recurso/Material')),
                  DropdownMenuItem(value: 'other', child: Text('Otro')),
                ],
                onChanged: (v) => setState(() => _type = v!),
              ),
            ),

            const SizedBox(height: 16),

            Row(
              children: [
                // CA-03, CA-04: Campo Ponderado.
                Expanded(
                  child: Semantics(
                    label: 'Campo ponderado de la actividad en porcentaje',
                    hint: 'Ingresa un valor entre 1 y ${available.toStringAsFixed(0)}',
                    textField: true,
                    child: TextFormField(
                      controller: _weightCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Ponderado (%)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.percent),
                        suffixText: '%',
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Requerido';
                        final n = double.tryParse(v);
                        if (n == null || n <= 0 || n > 100) {
                          return 'Entre 1 y 100';
                        }
                        return null;
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 16),

                // Semana del semestre.
                Expanded(
                  child: Semantics(
                    label: 'Selector de semana del semestre',
                    child: DropdownButtonFormField<int>(
                      value: _week,
                      decoration: const InputDecoration(
                        labelText: 'Semana',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.calendar_view_week),
                      ),
                      items: List.generate(
                          16,
                          (i) => DropdownMenuItem(
                              value: i + 1,
                              child: Text('Semana ${i + 1}'))),
                      onChanged: (v) => setState(() => _week = v!),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Fechas de inicio y cierre.
            Card(
              child: Column(
                children: [
                  Semantics(
                    label: 'Fecha de inicio con hora',
                    hint: 'Toca fecha u hora para cambiarlas',
                    child: ListTile(
                      leading: const Icon(Icons.event_available, color: Colors.green),
                      title: const Text('Fecha de inicio'),
                      subtitle: Text(
                        '${_startDate.day.toString().padLeft(2, '0')}/'
                        '${_startDate.month.toString().padLeft(2, '0')}/'
                        '${_startDate.year}  —  '
                        '${_startTime.hour.toString().padLeft(2, '0')}:'
                        '${_startTime.minute.toString().padLeft(2, '0')}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Cambiar fecha',
                            icon: const Icon(Icons.calendar_today_rounded,
                                color: Colors.green, size: 20),
                            onPressed: () => _pickDate(true),
                          ),
                          IconButton(
                            tooltip: 'Cambiar hora',
                            icon: const Icon(Icons.access_time_rounded,
                                color: Colors.green, size: 20),
                            onPressed: _pickStartTime,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  Semantics(
                    label: 'Fecha de cierre con hora',
                    hint: 'Toca fecha u hora para cambiarlas',
                    child: ListTile(
                      leading: const Icon(Icons.event_busy, color: Colors.red),
                      title: const Text('Fecha de cierre'),
                      subtitle: Text(
                        '${_closeDate.day.toString().padLeft(2, '0')}/'
                        '${_closeDate.month.toString().padLeft(2, '0')}/'
                        '${_closeDate.year}  —  '
                        '${_closeTime.hour.toString().padLeft(2, '0')}:'
                        '${_closeTime.minute.toString().padLeft(2, '0')}',
                      ),
                      // Botones separados para fecha y hora
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Cambiar fecha',
                            icon: const Icon(Icons.calendar_today_rounded,
                                color: Colors.red, size: 20),
                            onPressed: () => _pickDate(false),
                          ),
                          IconButton(
                            tooltip: 'Cambiar hora',
                            icon: const Icon(Icons.access_time_rounded,
                                color: Colors.red, size: 20),
                            onPressed: _pickCloseTime,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Sección adjuntar archivos.
            OutlinedButton.icon(
              onPressed: _pickFiles,
              icon: const Icon(Icons.attach_file),
              label: const Text('Agregar archivo'),
            ),
            if (_archivos.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: _archivos.asMap().entries.map((entry) {
                  final i = entry.key;
                  final f = entry.value;
                  return Chip(
                    label: Text(
                      f['name'] as String,
                      overflow: TextOverflow.ellipsis,
                    ),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () => setState(() => _archivos.removeAt(i)),
                  );
                }).toList(),
              ),
            ],

            const SizedBox(height: 28),

            // Botón de guardar.
            Semantics(
              label: 'Botón Crear Actividad',
              button: true,
              enabled: !_loading,
              hint: 'Toca dos veces para guardar la nueva actividad',
              child: SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _loading ? null : _save,
                  icon: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save),
                  label: Text(_loading ? 'Guardando...' : 'Crear Actividad'),
                ),
              ),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
