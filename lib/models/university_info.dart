/// Información pública de la universidad que ve el invitado (CU-10).
///
/// Viene de `GET /public/university` y la edita el Admin. Mientras nadie la edite el
/// servidor entrega contenido de EJEMPLO (`isSample`), y la app lo avisa.
class UniProgram {
  const UniProgram({required this.name, this.level = '', this.description = ''});
  final String name;
  final String level;
  final String description;

  factory UniProgram.fromJson(Map<String, dynamic> j) => UniProgram(
        name: j['name']?.toString() ?? '',
        level: j['level']?.toString() ?? '',
        description: j['description']?.toString() ?? '',
      );
  Map<String, dynamic> toJson() => {'name': name, 'level': level, 'description': description};
}

class UniStep {
  const UniStep({required this.title, this.text = ''});
  final String title;
  final String text;

  factory UniStep.fromJson(Map<String, dynamic> j) =>
      UniStep(title: j['title']?.toString() ?? '', text: j['text']?.toString() ?? '');
  Map<String, dynamic> toJson() => {'title': title, 'text': text};
}

class UniDate {
  const UniDate({required this.label, this.value = ''});
  final String label;
  final String value;

  factory UniDate.fromJson(Map<String, dynamic> j) =>
      UniDate(label: j['label']?.toString() ?? '', value: j['value']?.toString() ?? '');
  Map<String, dynamic> toJson() => {'label': label, 'value': value};
}

class UniContact {
  const UniContact({this.phone = '', this.email = '', this.address = '', this.website = '', this.schedule = ''});
  final String phone;
  final String email;
  final String address;
  final String website;
  final String schedule;

  bool get isEmpty => phone.isEmpty && email.isEmpty && address.isEmpty && website.isEmpty && schedule.isEmpty;

  factory UniContact.fromJson(Map<String, dynamic> j) => UniContact(
        phone: j['phone']?.toString() ?? '',
        email: j['email']?.toString() ?? '',
        address: j['address']?.toString() ?? '',
        website: j['website']?.toString() ?? '',
        schedule: j['schedule']?.toString() ?? '',
      );
  Map<String, dynamic> toJson() =>
      {'phone': phone, 'email': email, 'address': address, 'website': website, 'schedule': schedule};
}

class UniversityInfo {
  const UniversityInfo({
    required this.name,
    this.tagline = '',
    this.about = '',
    this.programs = const [],
    this.steps = const [],
    this.requirements = const [],
    this.dates = const [],
    this.note = '',
    this.contact = const UniContact(),
  });

  final String name;
  final String tagline;
  final String about;
  final List<UniProgram> programs;
  final List<UniStep> steps;
  final List<String> requirements;
  final List<UniDate> dates;
  final String note;
  final UniContact contact;

  /// Copia local usada solo si nunca se pudo contactar al servidor.
  static const sample = UniversityInfo(
    name: 'Universidad',
    tagline: 'Gestión académica en un solo lugar',
    about: 'Contenido de ejemplo. El administrador puede reemplazarlo con la presentación real de la institución.',
    programs: [UniProgram(name: 'Programa de ejemplo', level: 'Pregrado', description: 'Descripción de ejemplo.')],
    steps: [
      UniStep(title: 'Inscríbete', text: 'Paso de ejemplo.'),
      UniStep(title: 'Entrega tus documentos', text: 'Paso de ejemplo.'),
      UniStep(title: 'Paga y confirma tu matrícula', text: 'Paso de ejemplo.'),
    ],
    requirements: ['Requisito de ejemplo'],
    dates: [UniDate(label: 'Fecha de ejemplo', value: 'Por definir')],
  );

  factory UniversityInfo.fromJson(Map<String, dynamic> j) {
    final e = j['enrollment'] is Map<String, dynamic> ? j['enrollment'] as Map<String, dynamic> : const <String, dynamic>{};
    List<T> lista<T>(dynamic v, T Function(Map<String, dynamic>) f) =>
        (v as List? ?? []).whereType<Map<String, dynamic>>().map(f).toList();
    return UniversityInfo(
      name: j['name']?.toString() ?? 'Universidad',
      tagline: j['tagline']?.toString() ?? '',
      about: j['about']?.toString() ?? '',
      programs: lista(j['programs'], UniProgram.fromJson),
      steps: lista(e['steps'], UniStep.fromJson),
      requirements: (e['requirements'] as List? ?? []).map((r) => r.toString()).toList(),
      dates: lista(e['dates'], UniDate.fromJson),
      note: e['note']?.toString() ?? '',
      contact: j['contact'] is Map<String, dynamic>
          ? UniContact.fromJson(j['contact'] as Map<String, dynamic>)
          : const UniContact(),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'tagline': tagline,
        'about': about,
        'programs': programs.map((p) => p.toJson()).toList(),
        'enrollment': {
          'steps': steps.map((s) => s.toJson()).toList(),
          'requirements': requirements,
          'dates': dates.map((d) => d.toJson()).toList(),
          'note': note,
        },
        'contact': contact.toJson(),
      };
}

/// Resultado de cargar la información pública.
class GuestContent {
  const GuestContent({required this.info, required this.isSample, this.offline = false});
  final UniversityInfo info;

  /// El servidor aún no tiene contenido real (el Admin no lo ha editado).
  final bool isSample;

  /// No hubo conexión: se muestra la última copia guardada (o el ejemplo local).
  final bool offline;
}
