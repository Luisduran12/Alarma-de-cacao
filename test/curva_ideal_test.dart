import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alarmacacao5_0/models/volteada.dart';
import 'package:alarmacacao5_0/services/curva_ideal.dart';

final _inicio = DateTime(2026, 1, 1, 8);

Volteada _reg(double horas, double temp, {bool confirmada = true}) {
  final f = _inicio.add(Duration(minutes: (horas * 60).round()));
  return Volteada(
    id: 'r$horas', loteId: 'l', mensaje: '', temperatura: temp, humedad: 80,
    observacion: '', fecha: f, fechaProgramada: f, confirmada: confirmada,
  );
}

void main() {
  group('CurvaIdeal', () {
    final curva = CurvaIdeal(const [PuntoIdeal(72, 45), PuntoIdeal(48, 40), PuntoIdeal(96, 50)]);

    test('ordena los puntos por hora', () {
      expect(curva.puntos.map((p) => p.horas), [48, 72, 96]);
    });

    test('interpola entre puntos', () {
      expect(curva.valorEn(48), 40);
      expect(curva.valorEn(60), closeTo(42.5, 1e-9));
      expect(curva.valorEn(96), 50);
    });

    test('no extrapola fuera del tramo definido', () {
      expect(curva.valorEn(47.9), isNull);
      expect(curva.valorEn(96.1), isNull);
    });

    test('vacía: no hay valores y se reconoce como vacía', () {
      expect(CurvaIdeal.vacia.estaVacia, isTrue);
      expect(CurvaIdeal.vacia.valorEn(10), isNull);
    });

    test('hora repetida: se queda con la última; descarta horas negativas', () {
      final c = CurvaIdeal(const [PuntoIdeal(10, 30), PuntoIdeal(10, 35), PuntoIdeal(-5, 20)]);
      expect(c.puntos, hasLength(1));
      expect(c.puntos.single.temperatura, 35);
      expect(c.valorEn(10), 35);
    });

    test('ida y vuelta por texto JSON; JSON dañado da curva vacía', () {
      final ida = CurvaIdeal.fromJsonString(curva.toJsonString());
      expect(ida.puntos.map((p) => [p.horas, p.temperatura]), [
        [48.0, 40.0], [72.0, 45.0], [96.0, 50.0],
      ]);
      expect(CurvaIdeal.fromJsonString('esto no es json').estaVacia, isTrue);
      expect(CurvaIdeal.fromJsonString('{"a":1}').estaVacia, isTrue);
      expect(CurvaIdeal.fromJsonString(null).estaVacia, isTrue);
    });
  });

  group('comparar con un lote', () {
    final curva = CurvaIdeal(const [PuntoIdeal(48, 40), PuntoIdeal(96, 50)]);

    test('diferencia promedio con signo (lote - ideal)', () {
      // ideal a las 60 h = 42,5 y a las 84 h = 47,5 (recta de 40 a 50 °C entre 48 h y 96 h)
      final c = curva.comparar([_reg(60, 44), _reg(84, 48)], _inicio);
      expect(c.lecturas, 2);
      expect(c.diferenciaPromedio, closeTo(1, 1e-9));
      expect(c.frase(), contains('1,0 °C por encima'));
    });

    test('por debajo', () {
      final c = curva.comparar([_reg(60, 41), _reg(84, 45)], _inicio);
      expect(c.diferenciaPromedio, closeTo(-2, 1e-9));
      expect(c.frase(), contains('2,0 °C por debajo'));
    });

    test('solo cuenta lecturas confirmadas y dentro del tramo', () {
      final c = curva.comparar([_reg(10, 99), _reg(60, 42.5), _reg(70, 99, confirmada: false)], _inicio);
      expect(c.lecturas, 1);
      expect(c.diferenciaPromedio, 0);
      expect(c.frase(), contains('coincidió'));
    });

    test('sin lecturas en el tramo lo dice', () {
      final c = curva.comparar([_reg(10, 30)], _inicio);
      expect(c.lecturas, 0);
      expect(c.frase(), contains('Ninguna lectura'));
    });
  });

  group('CurvaIdealStorage', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('empieza vacía (no trae valores inventados)', () async {
      expect((await CurvaIdealStorage.cargar()).estaVacia, isTrue);
    });

    test('guarda y recupera', () async {
      await CurvaIdealStorage.guardar(CurvaIdeal(const [PuntoIdeal(48, 45), PuntoIdeal(72, 48)]));
      final c = await CurvaIdealStorage.cargar();
      expect(c.valorEn(60), closeTo(46.5, 1e-9));
    });

    test('guardar una curva vacía la borra', () async {
      await CurvaIdealStorage.guardar(CurvaIdeal(const [PuntoIdeal(48, 45)]));
      await CurvaIdealStorage.guardar(CurvaIdeal.vacia);
      expect((await CurvaIdealStorage.cargar()).estaVacia, isTrue);
    });
  });
}
