import 'package:flutter_test/flutter_test.dart';

import 'package:alarmacacao5_0/services/evaluador_cacao.dart';

void main() {
  group('evaluarCondicionesCacao - fermentación', () {
    test('adecuado con temperatura > 25 °C y humedad > 80 %', () {
      final r = evaluarCondicionesCacao(
          temperatura: 28, humedad: 85, condicionClima: 'Clouds', proceso: 'fermentación');
      expect(r, contains('es adecuado para la fermentación'));
    });

    test('no adecuado y explica por qué cuando falta temperatura', () {
      final r = evaluarCondicionesCacao(
          temperatura: 22, humedad: 85, condicionClima: 'Clouds', proceso: 'fermentación');
      expect(r, contains('NO es adecuado'));
      expect(r, contains('La temperatura no es suficiente'));
      expect(r, isNot(contains('La humedad no es suficiente')));
    });

    test('los límites son estrictos: 25 °C y 80 % exactos no son adecuados', () {
      final r = evaluarCondicionesCacao(
          temperatura: 25, humedad: 80, condicionClima: 'Clear', proceso: 'fermentación');
      expect(r, contains('NO es adecuado'));
      expect(r, contains('La temperatura no es suficiente'));
      expect(r, contains('La humedad no es suficiente'));
    });
  });

  group('evaluarCondicionesCacao - secado', () {
    test('adecuado con > 30 °C, < 60 % y sin lluvia', () {
      final r = evaluarCondicionesCacao(
          temperatura: 32, humedad: 50, condicionClima: 'Clear', proceso: 'secado');
      expect(r, contains('es adecuado para el secado'));
    });

    test('la lluvia impide el secado (en inglés o en español)', () {
      for (final clima in ['Rain', 'lluvia ligera']) {
        final r = evaluarCondicionesCacao(
            temperatura: 32, humedad: 50, condicionClima: clima, proceso: 'secado');
        expect(r, contains('NO es adecuado'), reason: clima);
        expect(r, contains('Está lloviendo'), reason: clima);
      }
    });

    test('humedad alta impide el secado', () {
      final r = evaluarCondicionesCacao(
          temperatura: 35, humedad: 70, condicionClima: 'Clear', proceso: 'secado');
      expect(r, contains('La humedad es muy alta'));
    });
  });

  test('proceso desconocido', () {
    final r = evaluarCondicionesCacao(
        temperatura: 30, humedad: 70, condicionClima: 'Clear', proceso: 'tostado');
    expect(r, contains('Proceso desconocido'));
  });
}
