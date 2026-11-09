/// Elección de la voz del lector: masculina, en español LATINO (no de España) y lo más natural
/// disponible.
///
/// Cada sistema trae sus propias voces (Edge/Windows, macOS, Android…), así que no se puede fijar
/// una sola. Se puntúa cada voz por su nombre y se usa la mejor; si no hay ninguna masculina
/// conocida se queda con una voz en español cualquiera (y el tono grave la acerca a una masculina).
library;

/// Voces masculinas en español conocidas (más puntos = más elegante). Las «Natural» de Edge son
/// redes neuronales y suenan mucho mejor que las clásicas. El ACENTO lo decide [_acento].
const _masculinas = <String, int>{
  'gonzalo': 10, 'jorge': 9, 'alonso': 9, 'lorenzo': 8, 'tomas': 8, 'tomás': 8, 'mateo': 8,
  'sebastian': 8, 'sebastián': 8, 'cesar': 7, 'césar': 7, 'alex': 7, 'roberto': 7, 'luis': 7,
  'emilio': 7, 'federico': 7, 'mario': 7, 'rodrigo': 7, 'marcelo': 7, 'manuel': 7, 'victor': 7,
  'víctor': 7, 'raul': 7, 'raúl': 7, 'diego': 7, 'carlos': 7, 'juan': 7, 'andres': 7,
  'andrés': 7, 'alejandro': 7, 'antonio': 6, 'enrique': 6, 'miguel': 6, 'pablo': 6,
  'alvaro': 6, 'álvaro': 6, 'male': 5, 'hombre': 5,
  // Códigos de las voces masculinas de Google en Android (es-us-x-esd-local).
  'x-esd': 8, 'x-eed': 5,
};

const _femeninas = <String>[
  'helena', 'sabina', 'laura', 'paulina', 'monica', 'mónica', 'salome', 'salomé', 'elvira',
  'dalia', 'elena', 'lucia', 'lucía', 'esperanza', 'marisol', 'paloma', 'ximena', 'camila',
  'female', 'mujer', 'penelope', 'penélope', 'conchita', 'marta', 'paola', 'valentina',
  'catalina', 'abril', 'lupe', 'sofia', 'sofía', 'karla', 'margarita', 'belkys', 'marcela',
  'yolanda', 'ines', 'inés', 'andrea', 'reina', 'tania', 'maria', 'maría', 'lorena', 'larissa',
];

/// Puntos por ACENTO. El usuario pidió una voz latina: la de España pronuncia la «z» y la «c»
/// como «th» y suena rara en Colombia. Colombia primero; el resto de Latinoamérica después.
int _acento(String loc) {
  if (loc.startsWith('es-co')) return 40;
  if (loc.startsWith('es-mx') || loc.startsWith('es-us') || loc.startsWith('es-419')) return 32;
  // Penalización moderada: una voz masculina de España sigue ganando a una voz de género
  // desconocido (p. ej. «Google español de Estados Unidos», que es femenina).
  if (loc.startsWith('es-es')) return -15;
  return 26; // es-AR, es-CL, es-PE, es-VE, es-UY, es-EC, es-CR…
}

/// Puntúa una voz. `-1` = no es español (descartada); `1` = española pero femenina; `10` =
/// española de género desconocido; `50+` = masculina conocida (con acento latino, bastante más).
int puntuarVoz(String nombre, String idioma) {
  final loc = idioma.toLowerCase().replaceAll('_', '-');
  if (!loc.startsWith('es')) return -1;
  final n = nombre.toLowerCase();

  if (_femeninas.any(n.contains)) return 1;
  var base = 10;
  for (final e in _masculinas.entries) {
    if (n.contains(e.key)) {
      base = 60 + e.value;
      break;
    }
  }
  var extra = _acento(loc);
  if (n.contains('natural')) extra += 30;
  if (n.contains('online')) extra += 10;
  return base + extra;
}

/// Índice de la mejor voz de [voces] (pares nombre / idioma), o `null` si no hay ninguna en español.
int? mejorVoz(List<({String nombre, String idioma})> voces) {
  int? mejor;
  var puntos = -1;
  for (var i = 0; i < voces.length; i++) {
    final p = puntuarVoz(voces[i].nombre, voces[i].idioma);
    if (p > puntos) {
      puntos = p;
      mejor = i;
    }
  }
  return mejor;
}

/// Si la voz elegida es masculina conocida (para saber cuánto bajar el tono).
bool esVozMasculina(String nombre, String idioma) {
  final n = nombre.toLowerCase();
  if (_femeninas.any(n.contains)) return false;
  return _masculinas.keys.any(n.contains);
}
