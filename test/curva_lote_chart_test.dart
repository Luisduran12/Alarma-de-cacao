import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alarmacacao5_0/models/volteada.dart';
import 'package:alarmacacao5_0/services/curva_ideal.dart';
import 'package:alarmacacao5_0/widgets/curva_lote_chart.dart';

final _inicio = DateTime(2026, 1, 1, 8);

Volteada _reg(double horas, double temp, {String etapa = Etapa.fermentacion}) {
  final f = _inicio.add(Duration(minutes: (horas * 60).round()));
  return Volteada(
    id: 'r$horas', loteId: 'l', mensaje: '', temperatura: temp, humedad: 80,
    observacion: '', fecha: f, fechaProgramada: f, confirmada: true, etapa: etapa,
  );
}

Widget _app(Widget hijo) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: hijo)));

/// La gráfica de temperatura es la primera LineChart.
LineChartData _datosTemp(WidgetTester t) => t.widget<LineChart>(find.byType(LineChart).first).data;

void main() {
  // 24 h sin referencia, 60 h dentro, 84 h bajo (43), 96 h sobre (52)
  final registros = [_reg(24, 32), _reg(60, 46), _reg(84, 43), _reg(96, 52)];

  testWidgets('con menos de 2 registros muestra un aviso en vez de la curva', (t) async {
    await t.pumpWidget(_app(CurvaLoteChart(registros: [_reg(10, 30)], inicio: _inicio)));
    expect(find.byType(LineChart), findsNothing);
    expect(find.textContaining('al menos 2 registros'), findsOneWidget);
  });

  testWidgets('dibuja dos gráficas y la banda de referencia', (t) async {
    await t.pumpWidget(_app(CurvaLoteChart(registros: registros, inicio: _inicio)));
    expect(find.byType(LineChart), findsNWidgets(2));
    final d = _datosTemp(t);
    expect(d.betweenBarsData, hasLength(1), reason: 'banda 45-50 °C entre dos líneas invisibles');
    final b0 = d.lineBarsData[0].spots, b1 = d.lineBarsData[1].spots;
    expect([b0.first.y, b1.first.y], [45, 50]);
    expect(b0.first.x, 48, reason: 'la banda empieza en la hora 48');
    expect(find.text('Rango de referencia'), findsOneWidget);
  });

  testWidgets('los puntos fuera de rango son cuadrados rojos; dentro y sin referencia, círculos', (t) async {
    await t.pumpWidget(_app(CurvaLoteChart(registros: registros, inicio: _inicio)));
    final serie = _datosTemp(t).lineBarsData.last; // la serie principal va al final
    FlDotPainter pintor(int i) => serie.dotData.getDotPainter(serie.spots[i], 0, serie, i);

    expect(pintor(0), isA<FlDotCirclePainter>(), reason: '24 h: sin referencia');
    expect(pintor(1), isA<FlDotCirclePainter>(), reason: '60 h, 46 °C: dentro');
    expect(pintor(2), isA<FlDotSquarePainter>(), reason: '84 h, 43 °C: bajo');
    expect(pintor(3), isA<FlDotSquarePainter>(), reason: '96 h, 52 °C: sobre');
  });

  testWidgets('superpone un segundo lote y la curva ideal', (t) async {
    final comp = SerieComparada(
      nombre: 'Lote B',
      registros: [_reg(30, 30), _reg(70, 47)],
      inicio: _inicio,
    );
    final ideal = CurvaIdeal(const [PuntoIdeal(48, 45), PuntoIdeal(96, 49)]);
    await t.pumpWidget(_app(CurvaLoteChart(registros: registros, inicio: _inicio, comparacion: comp, ideal: ideal)));

    final d = _datosTemp(t);
    // banda(2) + ideal(1) + comparada(1) + principal(1)
    expect(d.lineBarsData, hasLength(5));
    expect(find.text('Lote B'), findsOneWidget);
    expect(find.textContaining('Curva ideal'), findsOneWidget);
  });

  testWidgets('en secado la referencia es solo un tope de 50 °C', (t) async {
    final r = [_reg(100, 40), _reg(130, 48, etapa: Etapa.secado), _reg(150, 55, etapa: Etapa.secado)];
    await t.pumpWidget(_app(CurvaLoteChart(registros: r, inicio: _inicio)));
    final serie = _datosTemp(t).lineBarsData.last;
    FlDotPainter pintor(int i) => serie.dotData.getDotPainter(serie.spots[i], 0, serie, i);
    expect(pintor(1), isA<FlDotCirclePainter>());
    expect(pintor(2), isA<FlDotSquarePainter>());
  });

  testWidgets('con secado, la banda de fermentación termina en el último registro de fermentación', (t) async {
    final r = [_reg(60, 46), _reg(100, 47), _reg(130, 40, etapa: Etapa.secado), _reg(150, 42, etapa: Etapa.secado)];
    await t.pumpWidget(_app(CurvaLoteChart(registros: r, inicio: _inicio)));
    final d = _datosTemp(t);
    expect(d.betweenBarsData, hasLength(1));
    expect(d.lineBarsData[0].spots.last.x, 100, reason: 'no se extiende hasta el primer registro de secado (130 h)');
  });

  testWidgets('la descripción accesible dice cuántos registros están fuera de rango', (t) async {
    final h = t.ensureSemantics();
    await t.pumpWidget(_app(CurvaLoteChart(registros: registros, inicio: _inicio, nombre: 'Lote A')));
    expect(find.bySemanticsLabel(RegExp('2 de 4 registros de temperatura fuera')), findsOneWidget);
    h.dispose();
  });
}
