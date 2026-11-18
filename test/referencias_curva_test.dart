import 'package:alarmacacao5_0/data/referencias_curva.dart';
import 'package:alarmacacao5_0/models/volteada.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ReferenciasCurva.estadoTemperatura', () {
    test('fermentación: antes de la hora 48 no hay referencia', () {
      expect(ReferenciasCurva.estadoTemperatura(30, 24, Etapa.fermentacion), EstadoRango.sinReferencia);
      expect(ReferenciasCurva.estadoTemperatura(30, 47.9, Etapa.fermentacion), EstadoRango.sinReferencia);
    });

    test('fermentación: desde la hora 48 se compara con 45-50 °C', () {
      expect(ReferenciasCurva.estadoTemperatura(44.9, 48, Etapa.fermentacion), EstadoRango.bajo);
      expect(ReferenciasCurva.estadoTemperatura(45, 72, Etapa.fermentacion), EstadoRango.dentro);
      expect(ReferenciasCurva.estadoTemperatura(50, 72, Etapa.fermentacion), EstadoRango.dentro);
      expect(ReferenciasCurva.estadoTemperatura(50.1, 96, Etapa.fermentacion), EstadoRango.alto);
    });

    test('secado: solo hay máximo (50 °C), sin mínimo', () {
      expect(ReferenciasCurva.estadoTemperatura(20, 150, Etapa.secado), EstadoRango.dentro);
      expect(ReferenciasCurva.estadoTemperatura(50, 150, Etapa.secado), EstadoRango.dentro);
      expect(ReferenciasCurva.estadoTemperatura(51, 150, Etapa.secado), EstadoRango.alto);
    });
  });

  group('Constante única con fuente', () {
    test('cada rango tiene fuente escrita', () {
      for (final r in [
        ReferenciasCurva.fermentacionTemperatura,
        ReferenciasCurva.secadoTemperatura,
        ReferenciasCurva.humedadGranoFinalSecado,
      ]) {
        expect(r.fuente.trim(), isNotEmpty);
      }
    });

    test('lo que no tiene fuente verificada está declarado, no inventado', () {
      expect(ReferenciasCurva.sinReferenciaVerificada.keys, containsAll(['ph', 'brix', 'tempAmbiente']));
    });

    test('el máximo de fermentación es referencia ("o más"), no tope', () {
      expect(ReferenciasCurva.fermentacionTemperatura.maximoEsLimite, isFalse);
    });
  });
}
