import 'package:flutter_test/flutter_test.dart';
import 'package:gesacad/utils/voice_picker.dart';

void main() {
  int? elegir(List<(String, String)> v) =>
      mejorVoz([for (final e in v) (nombre: e.$1, idioma: e.$2)]);

  test('prefiere la voz masculina «Natural» (Gonzalo) a una femenina', () {
    final i = elegir([
      ('Microsoft Salome Online (Natural) - Spanish (Colombia)', 'es-CO'),
      ('Microsoft Gonzalo Online (Natural) - Spanish (Colombia)', 'es-CO'),
      ('Microsoft Helena - Spanish (Spain)', 'es-ES'),
    ]);
    expect(i, 1);
  });

  test('entre masculinas elige la más elegante: Natural > clásica', () {
    final i = elegir([
      ('Microsoft Pablo - Spanish (Spain)', 'es-ES'),
      ('Microsoft Alvaro Online (Natural) - Spanish (Spain)', 'es-ES'),
    ]);
    expect(i, 1);
  });

  test('prefiere el acento latino al de España, aunque el de España sea «Natural»', () {
    final i = elegir([
      ('Microsoft Alvaro Online (Natural) - Spanish (Spain)', 'es-ES'),
      ('Microsoft Raul - Spanish (Mexico)', 'es-MX'),
    ]);
    expect(i, 1);
    // Y entre latinas, Colombia primero.
    final j = elegir([
      ('Microsoft Jorge Online (Natural) - Spanish (Mexico)', 'es-MX'),
      ('Microsoft Gonzalo Online (Natural) - Spanish (Colombia)', 'es-CO'),
    ]);
    expect(j, 1);
  });

  test('una voz masculina de España gana a una de género desconocido (Google EE. UU.)', () {
    final i = elegir([
      ('Google español de Estados Unidos', 'es-US'),
      ('Microsoft Pablo - Spanish (Spain)', 'es-ES'),
    ]);
    expect(i, 1);
  });

  test('descarta lo que no es español y devuelve null si no hay ninguna', () {
    expect(elegir([('Microsoft David - English (United States)', 'en-US')]), isNull);
    expect(
        elegir([('Microsoft David - English (United States)', 'en-US'), ('Diego', 'es-AR')]), 1);
  });

  test('sin voz masculina conocida usa una en español (aunque sea femenina)', () {
    expect(elegir([('Microsoft Helena - Spanish (Spain)', 'es-ES')]), 0);
    expect(esVozMasculina('Microsoft Helena - Spanish (Spain)', 'es-ES'), isFalse);
    expect(esVozMasculina('Google español de Estados Unidos', 'es-US'), isFalse);
    expect(esVozMasculina('Microsoft Jorge - Spanish (Mexico)', 'es-MX'), isTrue);
  });

  test('reconoce las voces masculinas de Google en Android', () {
    final i = elegir([
      ('es-us-x-sfb-local', 'es-US'),
      ('es-us-x-esd-local', 'es-US'),
    ]);
    expect(i, 1);
  });
}
