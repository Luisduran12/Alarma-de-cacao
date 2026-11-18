import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/volteada.dart';

/// Curva de temperatura y humedad de un lote en el tiempo.
///
/// Son DOS gráficas pequeñas apiladas que comparten el eje de tiempo (horas
/// desde el inicio), no una gráfica de doble eje: °C y % son medidas
/// distintas y un doble eje engaña al comparar. Cada gráfica tiene una sola
/// serie, nombrada en su título; al tocar un punto se ve el valor exacto.
/// La lista de registros debajo funciona como vista de tabla.
class CurvaLoteChart extends StatelessWidget {
  final List<Volteada> registros;
  final DateTime inicio;

  const CurvaLoteChart({super.key, required this.registros, required this.inicio});

  // Colores validados (CVD y contraste) con la guía de visualización.
  static const _tempClaro = Color(0xFFEB6834), _tempOscuro = Color(0xFFD95926);
  static const _humClaro = Color(0xFF2A78D6), _humOscuro = Color(0xFF3987E5);

  /// Puntos (horas desde el inicio, valor) ordenados por tiempo.
  static List<FlSpot> puntos(List<Volteada> registros, DateTime inicio, double Function(Volteada) valor) {
    final ordenados = registros.where((v) => v.confirmada).toList()..sort((a, b) => a.fecha.compareTo(b.fecha));
    return [
      for (final v in ordenados) FlSpot(v.fecha.difference(inicio).inMinutes / 60.0, valor(v)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final oscuro = Theme.of(context).brightness == Brightness.dark;
    final temp = puntos(registros, inicio, (v) => v.temperatura);
    final hum = puntos(registros, inicio, (v) => v.humedad);

    if (temp.length < 2) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('La curva aparece cuando el lote tiene al menos 2 registros.'),
      );
    }

    final minX = temp.first.x < 0 ? temp.first.x : 0.0;
    final maxX = temp.last.x <= minX ? minX + 1 : temp.last.x;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _GraficaSerie(
          titulo: 'Temperatura (°C)',
          unidad: '°C',
          puntos: temp,
          color: oscuro ? _tempOscuro : _tempClaro,
          minX: minX,
          maxX: maxX,
          mostrarEjeX: false,
        ),
        const SizedBox(height: 12),
        _GraficaSerie(
          titulo: 'Humedad (%)',
          unidad: '%',
          puntos: hum,
          color: oscuro ? _humOscuro : _humClaro,
          minX: minX,
          maxX: maxX,
          mostrarEjeX: true,
          minY: 0,
          maxY: 100,
        ),
      ],
    );
  }
}

class _GraficaSerie extends StatelessWidget {
  final String titulo;
  final String unidad;
  final List<FlSpot> puntos;
  final Color color;
  final double minX, maxX;
  final bool mostrarEjeX;
  final double? minY, maxY;

  const _GraficaSerie({
    required this.titulo,
    required this.unidad,
    required this.puntos,
    required this.color,
    required this.minX,
    required this.maxX,
    required this.mostrarEjeX,
    this.minY,
    this.maxY,
  });

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final tinta = tema.colorScheme.onSurfaceVariant; // texto en tinta, no en el color de la serie
    final superficie = tema.colorScheme.surface;
    final estiloEje = tema.textTheme.labelSmall?.copyWith(color: tinta);

    final valores = puntos.map((p) => p.y);
    final bajo = minY ?? (valores.reduce((a, b) => a < b ? a : b) - 2).floorToDouble();
    final alto = maxY ?? (valores.reduce((a, b) => a > b ? a : b) + 2).ceilToDouble();

    return Semantics(
      label: '$titulo: ${puntos.length} registros, de ${puntos.first.y} a ${puntos.last.y} $unidad',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: tema.textTheme.titleSmall),
          const SizedBox(height: 6),
          SizedBox(
            height: mostrarEjeX ? 170 : 150,
            child: LineChart(
              LineChartData(
                minX: minX,
                maxX: maxX,
                minY: bajo,
                maxY: alto,
                clipData: const FlClipData.all(),
                borderData: FlBorderData(show: false),
                gridData: FlGridData(
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) =>
                      FlLine(color: tema.colorScheme.outlineVariant.withValues(alpha: 0.5), strokeWidth: 1),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 36,
                      getTitlesWidget: (v, meta) => SideTitleWidget(
                        meta: meta,
                        child: Text(meta.formattedValue, style: estiloEje),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    axisNameWidget: mostrarEjeX ? Text('Horas desde el inicio', style: estiloEje) : null,
                    axisNameSize: mostrarEjeX ? 18 : 0,
                    sideTitles: SideTitles(
                      showTitles: mostrarEjeX,
                      reservedSize: 24,
                      getTitlesWidget: (v, meta) => SideTitleWidget(
                        meta: meta,
                        child: Text('${v.round()} h', style: estiloEje),
                      ),
                    ),
                  ),
                ),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => tema.colorScheme.inverseSurface,
                    getTooltipItems: (spots) => [
                      for (final s in spots)
                        LineTooltipItem(
                          '${s.y.toStringAsFixed(1)} $unidad\n${s.x.toStringAsFixed(1)} h',
                          TextStyle(color: tema.colorScheme.onInverseSurface, fontSize: 12),
                        ),
                    ],
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: puntos,
                    color: color,
                    barWidth: 2,
                    isCurved: false,
                    dotData: FlDotData(
                      getDotPainter: (spot, pct, bar, i) => FlDotCirclePainter(
                        radius: 4,
                        color: color,
                        strokeWidth: 2,
                        strokeColor: superficie,
                      ),
                    ),
                    belowBarData: BarAreaData(show: false),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
