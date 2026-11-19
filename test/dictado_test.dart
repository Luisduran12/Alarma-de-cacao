import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alarmacacao5_0/services/dictado.dart';
import 'package:alarmacacao5_0/widgets/boton_dictado.dart';

class _MotorFalso implements MotorDictado {
  bool disponible = true;
  int preparaciones = 0;
  bool escuchando = false;
  void Function(String, bool)? alTexto;
  void Function(String)? alError;

  @override
  Future<bool> preparar({required void Function(String error) alError}) async {
    preparaciones++;
    this.alError = alError;
    return disponible;
  }

  @override
  Future<void> escuchar({required void Function(String texto, bool esFinal) alTexto}) async {
    escuchando = true;
    this.alTexto = alTexto;
  }

  @override
  Future<void> detener() async => escuchando = false;
}

void main() {
  late _MotorFalso motor;
  late TextEditingController c;
  bool? guardado;

  Widget pantalla({Future<bool?> Function()? consentimiento}) => MaterialApp(
        home: Scaffold(
          body: TextField(
            controller: c,
            decoration: InputDecoration(
              labelText: 'Observación',
              suffixIcon: BotonDictado(
                controller: c,
                motor: motor,
                leerConsentimiento: consentimiento ?? () async => null,
                guardarConsentimiento: (v) async => guardado = v,
              ),
            ),
          ),
        ),
      );

  setUp(() {
    motor = _MotorFalso();
    c = TextEditingController();
    guardado = null;
  });

  testWidgets('la primera vez explica y pide autorización; si dice que no, no toca el micrófono', (t) async {
    await t.pumpWidget(pantalla());
    await t.tap(find.byTooltip('Dictar con la voz'));
    await t.pumpAndSettle();
    expect(find.text('¿Escribir con la voz?'), findsOneWidget);
    expect(find.textContaining('no guarda el audio'), findsOneWidget);
    await t.tap(find.text('No, usar el teclado'));
    await t.pumpAndSettle();
    expect(guardado, isFalse);
    expect(motor.preparaciones, 0);
    expect(motor.escuchando, isFalse);
  });

  testWidgets('autorizado: escucha, AGREGA lo dictado a lo que ya estaba escrito y termina solo', (t) async {
    c.text = 'Olor a vinagre.';
    await t.pumpWidget(pantalla(consentimiento: () async => true));
    await t.tap(find.byTooltip('Dictar con la voz'));
    await t.pump();
    expect(motor.escuchando, isTrue);
    expect(find.byTooltip('Dejar de escuchar'), findsOneWidget);

    motor.alTexto!('color', false);
    expect(c.text, 'Olor a vinagre. color');
    motor.alTexto!('color café', true);
    await t.pump();
    expect(c.text, 'Olor a vinagre. color café');
    expect(find.byTooltip('Dictar con la voz'), findsOneWidget);
  });

  testWidgets('tocar otra vez detiene la escucha y deja lo que se alcanzó a escribir', (t) async {
    await t.pumpWidget(pantalla(consentimiento: () async => true));
    await t.tap(find.byTooltip('Dictar con la voz'));
    await t.pump();
    motor.alTexto!('grano violeta', false);
    await t.tap(find.byTooltip('Dejar de escuchar'));
    await t.pump();
    expect(motor.escuchando, isFalse);
    expect(c.text, 'grano violeta');
  });

  testWidgets('sin servicio de voz o sin permiso: lo dice y el teclado sigue sirviendo', (t) async {
    motor.disponible = false;
    await t.pumpWidget(pantalla(consentimiento: () async => true));
    await t.tap(find.byTooltip('Dictar con la voz'));
    await t.pump();
    expect(find.textContaining('Escriba con el teclado'), findsOneWidget);
    expect(motor.escuchando, isFalse);
    await t.enterText(find.byType(TextField), 'escrito a mano');
    expect(c.text, 'escrito a mano');
  });

  testWidgets('si el motor falla mientras escucha: vuelve al estado normal y avisa', (t) async {
    await t.pumpWidget(pantalla(consentimiento: () async => true));
    await t.tap(find.byTooltip('Dictar con la voz'));
    await t.pump();
    motor.alError!('error_network');
    await t.pump();
    expect(find.byTooltip('Dictar con la voz'), findsOneWidget);
    expect(find.textContaining('No se pudo escuchar'), findsOneWidget);
  });

  testWidgets('si ya dijo que no, no se le vuelve a preguntar ni se escucha', (t) async {
    await t.pumpWidget(pantalla(consentimiento: () async => false));
    await t.tap(find.byTooltip('Dictar con la voz'));
    await t.pumpAndSettle();
    expect(find.text('¿Escribir con la voz?'), findsNothing);
    expect(motor.preparaciones, 0);
  });
}
