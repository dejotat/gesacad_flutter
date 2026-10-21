/// Festivos de Colombia calculados para CUALQUIER año (no una lista fija).
///
/// Reglas (Ley 51 de 1983, "Ley Emiliani"):
/// - Fijos: 1 ene, 1 may, 20 jul, 7 ago, 8 dic y 25 dic.
/// - Se trasladan al lunes siguiente (si no caen en lunes): 6 ene, 19 mar, 29 jun,
///   15 ago, 12 oct, 1 nov y 11 nov.
/// - Según la Pascua: Jueves y Viernes Santo (fijos) y Ascensión, Corpus Christi y
///   Sagrado Corazón (se trasladan al lunes siguiente).
library;

/// Domingo de Pascua (algoritmo gregoriano anónimo).
DateTime domingoDePascua(int anio) {
  final a = anio % 19;
  final b = anio ~/ 100;
  final c = anio % 100;
  final d = b ~/ 4;
  final e = b % 4;
  final f = (b + 8) ~/ 25;
  final g = (b - f + 1) ~/ 3;
  final h = (19 * a + b - d - g + 15) % 30;
  final i = c ~/ 4;
  final k = c % 4;
  final l = (32 + 2 * e + 2 * i - h - k) % 7;
  final m = (a + 11 * h + 22 * l) ~/ 451;
  final mes = (h + l - 7 * m + 114) ~/ 31;
  final dia = ((h + l - 7 * m + 114) % 31) + 1;
  return DateTime(anio, mes, dia);
}

/// Traslada una fecha al lunes siguiente; si ya es lunes, queda igual.
DateTime _alLunes(DateTime d) => d.add(Duration(days: (8 - d.weekday) % 7));

/// Festivos del [anio]: fecha (a medianoche) → nombre.
Map<DateTime, String> festivosColombia(int anio) {
  final pascua = domingoDePascua(anio);
  DateTime desdePascua(int dias) => DateTime(pascua.year, pascua.month, pascua.day + dias);

  final entradas = <(DateTime, String)>[
    (DateTime(anio, 1, 1), 'Año Nuevo'),
    (_alLunes(DateTime(anio, 1, 6)), 'Reyes Magos'),
    (_alLunes(DateTime(anio, 3, 19)), 'Día de San José'),
    (desdePascua(-3), 'Jueves Santo'),
    (desdePascua(-2), 'Viernes Santo'),
    (DateTime(anio, 5, 1), 'Día del Trabajo'),
    (_alLunes(desdePascua(39)), 'Ascensión del Señor'),
    (_alLunes(desdePascua(60)), 'Corpus Christi'),
    (_alLunes(desdePascua(68)), 'Sagrado Corazón'),
    (_alLunes(DateTime(anio, 6, 29)), 'San Pedro y San Pablo'),
    (DateTime(anio, 7, 20), 'Independencia de Colombia'),
    (DateTime(anio, 8, 7), 'Batalla de Boyacá'),
    (_alLunes(DateTime(anio, 8, 15)), 'Asunción de la Virgen'),
    (_alLunes(DateTime(anio, 10, 12)), 'Día de la Raza'),
    (_alLunes(DateTime(anio, 11, 1)), 'Todos los Santos'),
    (_alLunes(DateTime(anio, 11, 11)), 'Independencia de Cartagena'),
    (DateTime(anio, 12, 8), 'Inmaculada Concepción'),
    (DateTime(anio, 12, 25), 'Navidad'),
  ];
  // Dos festivos pueden trasladarse al mismo lunes (p. ej. 30 de junio de 2025):
  // se unen en un solo nombre en vez de perder uno.
  final lista = <DateTime, String>{};
  for (final (fecha, nombre) in entradas) {
    lista.update(fecha, (previo) => '$previo · $nombre', ifAbsent: () => nombre);
  }
  return lista;
}
