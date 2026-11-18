import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../data/referencias_curva.dart';
import '../models/volteada.dart';
import '../services/curva_ideal.dart';

/// Un lote que se dibuja junto al principal para compararlos.
class SerieComparada {
  final String nombre;
  final List<Volteada> registros;
  final DateTime inicio;
  const SerieComparada({required this.nombre, required this.registros, required this.inicio});
}

/// Curva de temperatura y humedad de un lote en el tiempo.
///
/// Son DOS gráficas pequeñas apiladas que comparten el eje de tiempo (horas
/// desde el inicio), no una gráfica de doble eje: °C y % son medidas
/// distintas y un doble eje engaña al comparar. Al tocar un punto se ve el
/// valor exacto. La lista de registros debajo funciona como vista de tabla.
///
/// En la de temperatura se dibuja la banda de referencia (ver
/// [ReferenciasCurva]); los puntos fuera de ella van en rojo y como cuadrado.
/// Opcionalmente se superpone un segundo lote ([comparacion]) y la curva ideal.
class CurvaLoteChart extends StatelessWidget {
  final List<Volteada> registros;
  final DateTime inicio;
  final String nombre;
  final SerieComparada? comparacion;
  final CurvaIdeal ideal;

  /// Para exportar la curva como imagen (RepaintBoundary).
  final GlobalKey? repaintKey;

  const CurvaLoteChart({
    super.key,
    required this.registros,
    required this.inicio,
    this.nombre = 'Este lote',
    this.comparacion,
    this.ideal = CurvaIdeal.vacia,
    this.repaintKey,
  });

  // Colores validados (CVD y contraste) con la guía de visualización.
  static const _tempClaro = Color(0xFFEB6834), _tempOscuro = Color(0xFFD95926);
  static const _humClaro = Color(0xFF2A78D6), _humOscuro = Color(0xFF3987E5);
  static const _fueraClaro = Color(0xFFC62828), _fueraOscuro = Color(0xFFEF5350);
  static const _compClaro = Color(0xFF6A4C93), _compOscuro = Color(0xFFB39DDB);
  static const _bandaClaro = Color(0xFF2E7D32), _bandaOscuro = Color(0xFF66BB6A);

  static List<Volteada> _confirmadas(List<Volteada> r) =>
      r.where((v) => v.confirmada).toList()..sort((a, b) => a.fecha.compareTo(b.fecha));

  /// Puntos (horas desde el inicio, valor) ordenados por tiempo.
  static List<FlSpot> puntos(List<Volteada> registros, DateTime inicio, double Function(Volteada) valor) {
    return [
      for (final v in _confirmadas(registros)) FlSpot(v.fecha.difference(inicio).inMinutes / 60.0, valor(v)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final oscuro = tema.brightness == Brightness.dark;
    final conf = _confirmadas(registros);
    final temp = puntos(registros, inicio, (v) => v.temperatura);
    final hum = puntos(registros, inicio, (v) => v.humedad);

    if (temp.length < 2) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('La curva aparece cuando el lote tiene al menos 2 registros.'),
      );
    }

    final tempComp = comparacion == null
        ? const <FlSpot>[]
        : puntos(comparacion!.registros, comparacion!.inicio, (v) => v.temperatura);
    final humComp = comparacion == null
        ? const <FlSpot>[]
        : puntos(comparacion!.registros, comparacion!.inicio, (v) => v.humedad);

    final todos = [...temp, ...tempComp, ...hum, ...humComp];
    final minX = todos.map((p) => p.x).reduce((a, b) => a < b ? a : b).clamp(double.negativeInfinity, 0.0);
    final ultimoX = todos.map((p) => p.x).reduce((a, b) => a > b ? a : b);
    final ultimo = ultimoX <= minX ? minX + 1 : ultimoX;
    // Margen a la derecha para que el último punto no quede cortado.
    final maxX = ultimo + (ultimo - minX) * 0.04;
    // Marcas del eje X cada 24 h (o cada 6 h en ciclos cortos) para que no se encimen.
    final intervaloX = (maxX - minX) > 48 ? 24.0 : 6.0;

    final fuera = [
      for (final v in conf)
        ReferenciasCurva.estadoTemperatura(v.temperatura, v.fecha.difference(inicio).inMinutes / 60.0, v.etapa) !=
                EstadoRango.dentro &&
            ReferenciasCurva.estadoTemperatura(v.temperatura, v.fecha.difference(inicio).inMinutes / 60.0, v.etapa) !=
                EstadoRango.sinReferencia,
    ];
    final primerSecado = conf.where((v) => v.etapa == Etapa.secado).firstOrNull;

    return Semantics(
      container: true,
      label: 'Curva de $nombre. ${fuera.where((f) => f).length} de ${conf.length} registros de '
          'temperatura fuera del rango de referencia.',
      child: ColoredBox(
        color: tema.colorScheme.surface,
        child: RepaintBoundary(
          key: repaintKey,
          child: ColoredBox(
            color: tema.colorScheme.surface,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _GraficaTemperatura(
                    conf: conf,
                    inicio: inicio,
                    puntos: temp,
                    fuera: fuera,
                    comparada: tempComp,
                    ideal: ideal,
                    horaPrimerSecado: primerSecado == null
                        ? null
                        : primerSecado.fecha.difference(inicio).inMinutes / 60.0,
                    color: oscuro ? _tempOscuro : _tempClaro,
                    colorFuera: oscuro ? _fueraOscuro : _fueraClaro,
                    colorComp: oscuro ? _compOscuro : _compClaro,
                    colorBanda: oscuro ? _bandaOscuro : _bandaClaro,
                    minX: minX,
                    maxX: maxX,
                    intervaloX: intervaloX,
                  ),
                  const SizedBox(height: 12),
                  _GraficaHumedad(
                    puntos: hum,
                    comparada: humComp,
                    color: oscuro ? _humOscuro : _humClaro,
                    colorComp: oscuro ? _compOscuro : _compClaro,
                    minX: minX,
                    maxX: maxX,
                    intervaloX: intervaloX,
                  ),
                  const SizedBox(height: 8),
                  _Leyenda(
                    nombre: nombre,
                    color: oscuro ? _tempOscuro : _tempClaro,
                    colorFuera: oscuro ? _fueraOscuro : _fueraClaro,
                    colorBanda: oscuro ? _bandaOscuro : _bandaClaro,
                    colorComp: oscuro ? _compOscuro : _compClaro,
                    comparacion: comparacion?.nombre,
                    hayIdeal: !ideal.estaVacia,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Eje común de las dos gráficas.
FlTitlesData _titulos(ThemeData tema, double intervaloX, bool mostrarEjeX) {
  final estiloEje = tema.textTheme.labelSmall?.copyWith(color: tema.colorScheme.onSurfaceVariant);
  return FlTitlesData(
    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    leftTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 36,
        getTitlesWidget: (v, meta) => SideTitleWidget(meta: meta, child: Text(meta.formattedValue, style: estiloEje)),
      ),
    ),
    bottomTitles: AxisTitles(
      axisNameWidget: mostrarEjeX ? Text('Horas desde el inicio', style: estiloEje) : null,
      axisNameSize: mostrarEjeX ? 18 : 0,
      sideTitles: SideTitles(
        showTitles: mostrarEjeX,
        reservedSize: 24,
        interval: intervaloX,
        getTitlesWidget: (v, meta) {
          // fl_chart agrega una marca en el extremo; solo se rotulan los múltiplos.
          if ((v % intervaloX).abs() > 0.01) return const SizedBox.shrink();
          return SideTitleWidget(meta: meta, child: Text('${v.round()} h', style: estiloEje));
        },
      ),
    ),
  );
}

FlGridData _rejilla(ThemeData tema) => FlGridData(
      drawVerticalLine: false,
      getDrawingHorizontalLine: (_) =>
          FlLine(color: tema.colorScheme.outlineVariant.withValues(alpha: 0.5), strokeWidth: 1),
    );

LineChartBarData _linea(List<FlSpot> pts, Color color, {bool punteada = false, double ancho = 2}) =>
    LineChartBarData(
      spots: pts,
      color: color,
      barWidth: ancho,
      isCurved: false,
      dashArray: punteada ? [6, 4] : null,
      dotData: const FlDotData(show: false),
    );

/// Línea invisible que solo sirve de borde de la banda de referencia.
LineChartBarData _bordeBanda(List<FlSpot> pts) => LineChartBarData(
      spots: pts,
      color: Colors.transparent,
      barWidth: 0,
      dotData: const FlDotData(show: false),
    );

class _GraficaTemperatura extends StatelessWidget {
  final List<Volteada> conf;
  final DateTime inicio;
  final List<FlSpot> puntos, comparada;
  final List<bool> fuera;
  final CurvaIdeal ideal;
  final double? horaPrimerSecado;
  final Color color, colorFuera, colorComp, colorBanda;
  final double minX, maxX, intervaloX;

  const _GraficaTemperatura({
    required this.conf,
    required this.inicio,
    required this.puntos,
    required this.fuera,
    required this.comparada,
    required this.ideal,
    required this.horaPrimerSecado,
    required this.color,
    required this.colorFuera,
    required this.colorComp,
    required this.colorBanda,
    required this.minX,
    required this.maxX,
    required this.intervaloX,
  });

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final superficie = tema.colorScheme.surface;

    // Banda de fermentación: desde su hora de inicio hasta el último registro de
    // fermentación (si ya hay secado) o hasta el final de la gráfica.
    final ultimaFerm = conf.where((v) => v.etapa == Etapa.fermentacion).lastOrNull;
    const rf = ReferenciasCurva.fermentacionTemperatura;
    final bandaIni = rf.desdeHora!;
    final bandaFin = (horaPrimerSecado == null || ultimaFerm == null
            ? maxX
            : ultimaFerm.fecha.difference(inicio).inMinutes / 60.0)
        .clamp(bandaIni, maxX);
    final hayBanda = bandaFin > bandaIni && puntos.any((p) => p.x <= bandaFin);

    // Tope de secado (solo máximo): línea punteada desde el primer registro de secado.
    const rs = ReferenciasCurva.secadoTemperatura;
    final hayTopeSecado = horaPrimerSecado != null && horaPrimerSecado! < maxX;

    final idealPts = [
      for (final p in ideal.puntos) FlSpot(p.horas, p.temperatura),
    ];

    final valores = [
      ...puntos.map((p) => p.y),
      ...comparada.map((p) => p.y),
      ...idealPts.map((p) => p.y),
      if (hayBanda) ...[rf.minimo!, rf.maximo!],
      if (hayTopeSecado) rs.maximo!,
    ];
    final bajo = (valores.reduce((a, b) => a < b ? a : b) - 2).floorToDouble();
    final alto = (valores.reduce((a, b) => a > b ? a : b) + 2).ceilToDouble();

    final barras = <LineChartBarData>[];
    final entre = <BetweenBarsData>[];
    if (hayBanda) {
      barras.add(_bordeBanda([FlSpot(bandaIni, rf.minimo!), FlSpot(bandaFin, rf.minimo!)]));
      barras.add(_bordeBanda([FlSpot(bandaIni, rf.maximo!), FlSpot(bandaFin, rf.maximo!)]));
      entre.add(BetweenBarsData(fromIndex: 0, toIndex: 1, color: colorBanda.withValues(alpha: 0.18)));
    }
    if (hayTopeSecado) {
      barras.add(_linea([FlSpot(horaPrimerSecado!, rs.maximo!), FlSpot(maxX, rs.maximo!)], colorBanda,
          punteada: true, ancho: 1.5));
    }
    if (idealPts.length >= 2) {
      barras.add(_linea(idealPts, tema.colorScheme.onSurfaceVariant, punteada: true));
    }
    if (comparada.isNotEmpty) {
      barras.add(LineChartBarData(
        spots: comparada,
        color: colorComp,
        barWidth: 2,
        isCurved: false,
        dotData: FlDotData(
          getDotPainter: (s, p, b, i) =>
              FlDotCirclePainter(radius: 3, color: colorComp, strokeWidth: 1.5, strokeColor: superficie),
        ),
      ));
    }
    // La serie principal va al final para que quede encima.
    barras.add(LineChartBarData(
      spots: puntos,
      color: color,
      barWidth: 2,
      isCurved: false,
      dotData: FlDotData(
        getDotPainter: (spot, pct, bar, i) => fuera[i]
            ? FlDotSquarePainter(size: 9, color: colorFuera, strokeWidth: 2, strokeColor: superficie)
            : FlDotCirclePainter(radius: 4, color: color, strokeWidth: 2, strokeColor: superficie),
      ),
    ));
    final indicePrincipal = barras.length - 1;

    return Semantics(
      label: 'Temperatura de la masa: ${puntos.length} registros, de ${puntos.first.y} a ${puntos.last.y} °C',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Temperatura (°C)', style: tema.textTheme.titleSmall),
          const SizedBox(height: 6),
          SizedBox(
            height: 190,
            child: LineChart(
              LineChartData(
                minX: minX,
                maxX: maxX,
                minY: bajo,
                maxY: alto,
                clipData: const FlClipData.all(),
                borderData: FlBorderData(show: false),
                gridData: _rejilla(tema),
                titlesData: _titulos(tema, intervaloX, false),
                betweenBarsData: entre,
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => tema.colorScheme.inverseSurface,
                    getTooltipItems: (spots) => [
                      for (final s in spots)
                        if (s.barIndex == indicePrincipal)
                          LineTooltipItem(
                            '${s.y.toStringAsFixed(1)} °C\n${s.x.toStringAsFixed(1)} h'
                            '${fuera[s.spotIndex] ? '\nFuera del rango' : ''}',
                            TextStyle(color: tema.colorScheme.onInverseSurface, fontSize: 12),
                          )
                        else
                          null,
                    ],
                  ),
                ),
                lineBarsData: barras,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GraficaHumedad extends StatelessWidget {
  final List<FlSpot> puntos, comparada;
  final Color color, colorComp;
  final double minX, maxX, intervaloX;

  const _GraficaHumedad({
    required this.puntos,
    required this.comparada,
    required this.color,
    required this.colorComp,
    required this.minX,
    required this.maxX,
    required this.intervaloX,
  });

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final superficie = tema.colorScheme.surface;

    return Semantics(
      label: 'Humedad: ${puntos.length} registros, de ${puntos.first.y} a ${puntos.last.y} %',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Humedad (%)', style: tema.textTheme.titleSmall),
          const SizedBox(height: 6),
          SizedBox(
            height: 170,
            child: LineChart(
              LineChartData(
                minX: minX,
                maxX: maxX,
                minY: 0,
                maxY: 100,
                clipData: const FlClipData.all(),
                borderData: FlBorderData(show: false),
                gridData: _rejilla(tema),
                titlesData: _titulos(tema, intervaloX, true),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => tema.colorScheme.inverseSurface,
                    getTooltipItems: (spots) => [
                      for (final s in spots)
                        LineTooltipItem(
                          '${s.y.toStringAsFixed(1)} %\n${s.x.toStringAsFixed(1)} h',
                          TextStyle(color: tema.colorScheme.onInverseSurface, fontSize: 12),
                        ),
                    ],
                  ),
                ),
                lineBarsData: [
                  if (comparada.isNotEmpty)
                    LineChartBarData(
                      spots: comparada,
                      color: colorComp,
                      barWidth: 2,
                      isCurved: false,
                      dotData: FlDotData(
                        getDotPainter: (s, p, b, i) =>
                            FlDotCirclePainter(radius: 3, color: colorComp, strokeWidth: 1.5, strokeColor: superficie),
                      ),
                    ),
                  LineChartBarData(
                    spots: puntos,
                    color: color,
                    barWidth: 2,
                    isCurved: false,
                    dotData: FlDotData(
                      getDotPainter: (spot, pct, bar, i) =>
                          FlDotCirclePainter(radius: 4, color: color, strokeWidth: 2, strokeColor: superficie),
                    ),
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

class _Leyenda extends StatelessWidget {
  final String nombre;
  final Color color, colorFuera, colorBanda, colorComp;
  final String? comparacion;
  final bool hayIdeal;

  const _Leyenda({
    required this.nombre,
    required this.color,
    required this.colorFuera,
    required this.colorBanda,
    required this.colorComp,
    required this.comparacion,
    required this.hayIdeal,
  });

  @override
  Widget build(BuildContext context) {
    final estilo = Theme.of(context).textTheme.bodySmall;
    Widget item(Widget marca, String texto) => Row(mainAxisSize: MainAxisSize.min, children: [
          marca,
          const SizedBox(width: 6),
          Flexible(child: Text(texto, style: estilo)),
        ]);
    Widget punto(Color c, {bool cuadrado = false}) => Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: c, shape: cuadrado ? BoxShape.rectangle : BoxShape.circle),
        );

    return Wrap(
      spacing: 16,
      runSpacing: 4,
      children: [
        item(punto(color), nombre),
        if (comparacion != null) item(punto(colorComp), comparacion!),
        item(Container(width: 18, height: 10, color: colorBanda.withValues(alpha: 0.35)), 'Rango de referencia'),
        item(punto(colorFuera, cuadrado: true), 'Fuera del rango'),
        if (hayIdeal) item(const Icon(Icons.show_chart, size: 14), 'Curva ideal (punteada)'),
      ],
    );
  }
}
