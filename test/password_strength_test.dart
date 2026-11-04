import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gesacad/config/app_tokens.dart';
import 'package:gesacad/widgets/ui/password_strength.dart';

Widget _app(Widget child) => MaterialApp(
      theme: ThemeData(extensions: const [AppTokens.light]),
      home: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: child)),
    );

void main() {
  group('PasswordStrength.evaluate', () {
    test('vacía → nivel 0', () {
      expect(PasswordStrength.evaluate('').level, 0);
    });

    test('niveles según los criterios de la política', () {
      expect(PasswordStrength.evaluate('abc').level, 1); // solo minúsculas
      expect(PasswordStrength.evaluate('abcdefgh').level, 2); // largo + minúscula + sin usuario
      expect(PasswordStrength.evaluate('Abcdefg1').level, 3); // falta símbolo
      expect(PasswordStrength.evaluate('Abcdef1#').level, 4);
    });

    test('"Fuerte" equivale a cumplir la política completa', () {
      expect(PasswordStrength.evaluate('Clave#Segura1').meetsPolicy, isTrue);
      expect(PasswordStrength.evaluate('Clave#Segura1').missing, isEmpty);
      expect(PasswordStrength.evaluate('clave#segura1').meetsPolicy, isFalse);
    });

    test('contener el usuario baja el nivel y lo dice', () {
      final s = PasswordStrength.evaluate('Jorge#2026x', username: 'jorge');
      expect(s.meetsPolicy, isFalse);
      expect(s.missing, ['no usar tu usuario']);
    });

    test('más de 64 caracteres no cumple', () {
      expect(PasswordStrength.evaluate('Aa1#${'x' * 70}').meetsPolicy, isFalse);
    });
  });

  group('PasswordStrengthBar', () {
    testWidgets('sin texto no dibuja nada', (t) async {
      await t.pumpWidget(_app(const PasswordStrengthBar(password: '')));
      expect(find.textContaining('Seguridad'), findsNothing);
    });

    testWidgets('muestra el nivel y NO lista los requisitos', (t) async {
      await t.pumpWidget(_app(const PasswordStrengthBar(password: 'abc')));
      expect(find.text('Seguridad: Débil'), findsOneWidget);
      expect(find.textContaining('Al menos'), findsNothing);
      expect(find.textContaining('Falta'), findsNothing);
    });

    testWidgets('con showHint dice lo que falta', (t) async {
      await t.pumpWidget(_app(const PasswordStrengthBar(password: 'Abcdefg1', showHint: true)));
      expect(find.text('Seguridad: Buena'), findsOneWidget);
      expect(find.text('Falta: un símbolo'), findsOneWidget);
    });

    testWidgets('cambia de color con el nivel y es accesible', (t) async {
      Color? colorDe(WidgetTester t) {
        final tramos = t.widgetList<AnimatedContainer>(find.byType(AnimatedContainer)).toList();
        return (tramos.first.decoration as BoxDecoration).color;
      }

      await t.pumpWidget(_app(const PasswordStrengthBar(password: 'abc')));
      final debil = colorDe(t);
      await t.pumpWidget(_app(const PasswordStrengthBar(password: 'Abcdef1#')));
      await t.pumpAndSettle();
      expect(colorDe(t), isNot(debil));
      expect(find.bySemanticsLabel('Seguridad de la contraseña: Fuerte'), findsOneWidget);
    });
  });
}
