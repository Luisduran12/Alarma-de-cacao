import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:alarmacacao5_0/models/lote.dart';
import 'package:alarmacacao5_0/models/volteada.dart';

Volteada _registro() => Volteada(
      id: 'v1',
      loteId: 'L1',
      mensaje: 'Volteada 1 (48 h)',
      temperatura: 45.5,
      humedad: 82,
      observacion: 'Olor a vinagre, buen color',
      fecha: DateTime(2026, 11, 18, 10, 30),
      fechaProgramada: DateTime(2026, 11, 18, 10, 0),
      confirmada: true,
      notifId: 12,
      etapa: Etapa.secado,
      latitud: 7.8939,
      longitud: -72.5078,
    );

void main() {
  group('Volteada', () {
    test('toJson/fromJson conserva todos los campos (ida y vuelta por texto JSON)', () {
      final original = _registro();
      final copia = Volteada.fromJson(jsonDecode(jsonEncode(original.toJson())));

      expect(copia.toJson(), original.toJson());
      expect(copia.latitud, 7.8939);
      expect(copia.etapa, Etapa.secado);
      expect(copia.tieneUbicacion, isTrue);
    });

    test('fromJson tolera datos antiguos incompletos', () {
      final v = Volteada.fromJson({'id': 'x', 'loteId': 'L', 'temperatura': 30});
      expect(v.temperatura, 30.0);
      expect(v.humedad, 0.0);
      expect(v.confirmada, isFalse);
      expect(v.notifId, 0);
      expect(v.etapa, Etapa.fermentacion);
      expect(v.tieneUbicacion, isFalse);
    });

    test('toRow/fromRow (tabla registros) conserva los datos', () {
      final original = _registro();
      expect(Volteada.fromRow(original.toRow()).toJson(), original.toJson());
    });
  });

  group('Lote', () {
    final lote = Lote(
      id: 'L1',
      title: 'Lote finca La Esperanza',
      status: 'en proceso',
      createdAt: DateTime(2026, 11, 18, 8),
      inicioCiclo: DateTime(2026, 11, 18, 8),
      finCiclo: DateTime(2026, 11, 24, 8),
      plantilla: 'fedecacao_144',
      calidadResultado: Calidad.buena,
      observacionResultado: '80 % granos bien fermentados',
      volteadas: [_registro()],
    );

    test('toJson/fromJson conserva el lote y sus volteadas', () {
      final copia = Lote.fromJson(jsonDecode(jsonEncode(lote.toJson())));
      expect(copia.toJson(), lote.toJson());
      expect(copia.volteadas.single.id, 'v1');
    });

    test('fromJson acepta el formato antiguo (sin campos nuevos)', () {
      final viejo = Lote.fromJson({
        'id': 'A',
        'title': 'Viejo',
        'volteadas': [],
        'status': 'en proceso',
        'createdAt': '2025-01-01T00:00:00.000',
      });
      expect(viejo.inicioCiclo, isNull);
      expect(viejo.plantilla, isNull);
      expect(viejo.calidadResultado, isNull);
    });

    test('toRow/fromRow (tabla lotes) conserva los datos', () {
      final copia = Lote.fromRow(lote.toRow(), lote.volteadas);
      expect(copia.toJson(), lote.toJson());
    });

    test('progreso se calcula desde la hora de inicio guardada', () {
      expect(lote.progreso(DateTime(2026, 11, 18, 8)), 0.0);
      expect(lote.progreso(DateTime(2026, 11, 21, 8)), closeTo(0.5, 1e-9)); // 72 de 144 h
      expect(lote.progreso(DateTime(2026, 12, 1)), 1.0);
      expect(Lote(id: 'x', title: 'x', status: 's', createdAt: DateTime(2026)).progreso(), 0.0);
    });
  });
}
