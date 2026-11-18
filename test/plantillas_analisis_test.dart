import 'package:flutter_test/flutter_test.dart';

import 'package:alarmacacao5_0/models/lote.dart';
import 'package:alarmacacao5_0/models/volteada.dart';
import 'package:alarmacacao5_0/services/analisis_lotes.dart';
import 'package:alarmacacao5_0/services/notification_service.dart';
import 'package:alarmacacao5_0/services/plantillas.dart';
import 'package:alarmacacao5_0/widgets/timer_progress_bar.dart';

Volteada _r(String loteId, double t, double h, {String etapa = Etapa.fermentacion, bool conf = true}) =>
    Volteada(
      id: '$loteId-$t-$h-$etapa',
      loteId: loteId,
      mensaje: '',
      temperatura: t,
      humedad: h,
      observacion: '',
      fecha: DateTime(2026, 1, 1),
      fechaProgramada: DateTime(2026, 1, 1),
      confirmada: conf,
      etapa: etapa,
    );

Lote _lote(String id, String? calidad, List<Volteada> regs, {int dia = 1}) => Lote(
      id: id,
      title: id,
      status: 'completado',
      createdAt: DateTime(2026, 1, dia),
      calidadResultado: calidad,
      volteadas: regs,
    );

void main() {
  group('Plantillas', () {
    test('fermentación 144 h: volteos 48/72/96/120 y alarma final a las 144 h', () {
      const p = Plantillas.fedecacao144;
      expect(p.horasVolteo, [48, 72, 96, 120]);
      expect(p.duracionHoras, 144);
      expect(p.tieneAlarmaFinal, isTrue);
    });

    test('predeterminada conserva las horas originales 24/34/48 sin alarma extra', () {
      expect(Plantillas.predeterminada.horasVolteo, [24, 34, 48]);
      expect(Plantillas.predeterminada.tieneAlarmaFinal, isFalse);
    });

    test('personalizada ignora ceros, repetidos y desorden', () {
      final p = Plantillas.personalizada([0, 30, 12, 30, 0]);
      expect(p.horasVolteo, [12, 30]);
      expect(p.duracionHoras, 30);
    });
  });

  group('AnalisisLotes', () {
    final lotes = [
      _lote('A', Calidad.buena, [_r('A', 40, 80), _r('A', 44, 84), _r('A', 99, 99, conf: false)]),
      _lote('B', Calidad.buena, [_r('B', 46, 86), _r('B', 30, 50, etapa: Etapa.secado)], dia: 2),
      _lote('C', Calidad.mala, [_r('C', 30, 70)]),
      _lote('D', null, [_r('D', 35, 75)]),
      _lote('E', Calidad.excelente, []), // sin registros: no entra
    ];

    test('resumir solo usa registros confirmados y separa por etapa', () {
      final a = AnalisisLotes.resumir(lotes[0]);
      expect(a.registros, 2);
      expect(a.tempPromedio, 42);
      expect(a.humedadPromedio, 82);

      final b = AnalisisLotes.resumir(lotes[1]);
      expect(b.tempFermentacion, 46);
      expect(b.tempSecado, 30);
      expect(b.humedadSecado, 50);
    });

    test('compararLotes ordena de mejor a peor calidad, sin evaluar al final', () {
      final orden = AnalisisLotes.compararLotes(lotes).map((r) => r.lote.id).toList();
      expect(orden, ['B', 'A', 'C', 'D']); // B y A son 'buena': primero el más reciente
    });

    test('porCalidad promedia los promedios de los lotes de cada calidad', () {
      final grupos = AnalisisLotes.porCalidad(lotes);
      expect(grupos.map((g) => g.calidad), [Calidad.buena, Calidad.mala]);
      final buena = grupos.first;
      expect(buena.lotes, 2);
      expect(buena.tempPromedio, closeTo((42 + 38) / 2, 1e-9)); // A=42, B=(46+30)/2=38
    });
  });

  group('Progreso persistente', () {
    test('se calcula desde la hora de inicio, no desde un temporizador', () {
      final inicio = DateTime(2026, 1, 1, 0);
      final fin = DateTime(2026, 1, 7, 0); // 144 h
      expect(TimerProgressBar.calcularProgreso(inicio, fin, inicio), 0.0);
      expect(TimerProgressBar.calcularProgreso(inicio, fin, DateTime(2026, 1, 4)), 0.5);
      expect(TimerProgressBar.calcularProgreso(inicio, fin, DateTime(2026, 2, 1)), 1.0);
    });
  });

  group('Payload de notificación', () {
    test('formato nuevo lleva el id de la volteada', () {
      final p = NotificationService.payloadVolteada('L1', 'V9');
      expect(NotificationService.argumentosDesdePayload(p),
          {'loteId': 'L1', 'volteadaId': 'V9', 'mensaje': ''});
    });

    test('acepta el formato antiguo y rechaza payloads vacíos', () {
      expect(NotificationService.argumentosDesdePayload('L1|Lote|Volteada 1|2026-01-01'),
          {'loteId': 'L1', 'volteadaId': '', 'mensaje': 'Volteada 1'});
      expect(NotificationService.argumentosDesdePayload(''), isNull);
      expect(NotificationService.argumentosDesdePayload('predeterminada'), isNull);
    });
  });
}
