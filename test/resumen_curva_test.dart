import 'package:flutter_test/flutter_test.dart';

import 'package:alarmacacao5_0/models/volteada.dart';
import 'package:alarmacacao5_0/services/resumen_curva.dart';

final _inicio = DateTime(2026, 1, 1, 8);

Volteada _reg(double horas, double temp, {bool confirmada = true, String etapa = Etapa.fermentacion}) {
  final f = _inicio.add(Duration(minutes: (horas * 60).round()));
  return Volteada(
    id: 'r$horas',
    loteId: 'l',
    mensaje: '',
    temperatura: temp,
    humedad: 80,
    observacion: '',
    fecha: f,
    fechaProgramada: f,
    confirmada: confirmada,
    etapa: etapa,
  );
}

void main() {
  test('sin registros confirmados no hay resumen', () {
    final r = ResumenCurva.calcular([_reg(10, 30, confirmada: false)], _inicio);
    expect(r.registros, 0);
    expect(r.tempMaxima, isNull);
    expect(r.frases().single, contains('Todavía no hay registros'));
  });

  test('temperatura máxima y la hora en que ocurrió', () {
    final r = ResumenCurva.calcular([_reg(24, 32), _reg(76, 49.5), _reg(100, 47)], _inicio);
    expect(r.tempMaxima, 49.5);
    expect(r.horaTempMaxima, 76);
    expect(r.fechaTempMaxima, _inicio.add(const Duration(hours: 76)));
  });

  test('ignora los registros no confirmados', () {
    final r = ResumenCurva.calcular([_reg(24, 32), _reg(30, 60, confirmada: false)], _inicio);
    expect(r.tempMaxima, 32);
    expect(r.registros, 1);
  });

  group('horas fuera de rango', () {
    test('antes de la hora 48 no hay referencia: 0 h comparables', () {
      final r = ResumenCurva.calcular([_reg(0, 25), _reg(24, 35), _reg(47, 40)], _inicio);
      expect(r.horasConReferencia, 0);
      expect(r.horasFuera, 0);
    });

    test('todo dentro de 45-50 °C: 0 h fuera', () {
      final r = ResumenCurva.calcular([_reg(48, 46), _reg(72, 48), _reg(96, 49)], _inicio);
      expect(r.horasConReferencia, closeTo(48, 0.1));
      expect(r.horasFuera, 0);
    });

    test('todo bajo 45 °C después de la hora 48: todas las horas fuera', () {
      final r = ResumenCurva.calcular([_reg(48, 40), _reg(72, 42)], _inicio);
      expect(r.horasConReferencia, closeTo(24, 0.1));
      expect(r.horasFuera, closeTo(24, 0.1));
    });

    test('cruce por la banda: interpola entre lecturas (44 a 46 en 10 h → ~5 h fuera)', () {
      final r = ResumenCurva.calcular([_reg(60, 44), _reg(70, 46)], _inicio);
      expect(r.horasConReferencia, closeTo(10, 0.1));
      expect(r.horasFuera, closeTo(5, 0.1));
    });

    test('sobre 50 °C cuenta como fuera de la referencia', () {
      final r = ResumenCurva.calcular([_reg(72, 52), _reg(84, 53)], _inicio);
      expect(r.horasFuera, closeTo(12, 0.1));
    });
  });

  group('tendencia (última lectura vs la anterior)', () {
    test('un solo registro: pocos datos', () {
      expect(ResumenCurva.calcular([_reg(10, 30)], _inicio).tendencia, Tendencia.pocosDatos);
    });
    test('sube 1 °C o más', () {
      expect(ResumenCurva.calcular([_reg(10, 30), _reg(20, 31)], _inicio).tendencia, Tendencia.subiendo);
    });
    test('baja 1 °C o más', () {
      expect(ResumenCurva.calcular([_reg(10, 40), _reg(20, 38.5)], _inicio).tendencia, Tendencia.bajando);
    });
    test('cambio menor a 1 °C: estable', () {
      expect(ResumenCurva.calcular([_reg(10, 40), _reg(20, 40.4)], _inicio).tendencia, Tendencia.estable);
    });
    test('usa el orden por fecha aunque la lista venga desordenada', () {
      final r = ResumenCurva.calcular([_reg(20, 38), _reg(10, 45)], _inicio);
      expect(r.tendencia, Tendencia.bajando);
    });
  });

  group('texto', () {
    test('duracion en horas y días', () {
      expect(ResumenCurva.duracion(5), '5 h');
      expect(ResumenCurva.duracion(24), '24 h (1 día)');
      expect(ResumenCurva.duracion(76), '76 h (3 días y 4 h)');
    });

    test('frases en lenguaje simple con coma decimal', () {
      final f = ResumenCurva.calcular([_reg(60, 44), _reg(76, 49.5)], _inicio).frases();
      expect(f.first, contains('49,5 °C'));
      expect(f.first, contains('76 h (3 días y 4 h)'));
      expect(f.join(' '), contains('fuera del rango de referencia'));
      expect(f.last, contains('subiendo'));
    });

    test('sin horas comparables lo dice en vez de inventar un número', () {
      final f = ResumenCurva.calcular([_reg(10, 30), _reg(20, 33)], _inicio).frases();
      expect(f.join(' '), contains('Aún no hay horas para comparar'));
    });
  });
}
