import '../models/lote.dart';
import '../models/volteada.dart';

/// Promedios de un lote (solo registros confirmados).
class ResumenLote {
  final Lote lote;
  final int registros;
  final double? tempPromedio;
  final double? humedadPromedio;
  final double? tempFermentacion;
  final double? humedadFermentacion;
  final double? tempSecado;
  final double? humedadSecado;

  const ResumenLote({
    required this.lote,
    required this.registros,
    this.tempPromedio,
    this.humedadPromedio,
    this.tempFermentacion,
    this.humedadFermentacion,
    this.tempSecado,
    this.humedadSecado,
  });
}

/// Promedios de todos los lotes que tienen la misma calidad de resultado.
class ResumenCalidad {
  final String calidad;
  final int lotes;
  final double? tempPromedio;
  final double? humedadPromedio;

  const ResumenCalidad({
    required this.calidad,
    required this.lotes,
    this.tempPromedio,
    this.humedadPromedio,
  });
}

/// Análisis descriptivo para comparar lotes: qué temperatura y humedad
/// promedio tuvieron los lotes según la calidad del grano obtenida.
///
/// Es un cruce de promedios, no un modelo estadístico: con pocos lotes
/// los resultados son solo orientativos.
class AnalisisLotes {
  static double? _prom(Iterable<double> xs) {
    final l = xs.toList();
    if (l.isEmpty) return null;
    return l.reduce((a, b) => a + b) / l.length;
  }

  static ResumenLote resumir(Lote lote) {
    final conf = lote.volteadas.where((v) => v.confirmada).toList();
    final ferm = conf.where((v) => v.etapa == Etapa.fermentacion);
    final sec = conf.where((v) => v.etapa == Etapa.secado);
    return ResumenLote(
      lote: lote,
      registros: conf.length,
      tempPromedio: _prom(conf.map((v) => v.temperatura)),
      humedadPromedio: _prom(conf.map((v) => v.humedad)),
      tempFermentacion: _prom(ferm.map((v) => v.temperatura)),
      humedadFermentacion: _prom(ferm.map((v) => v.humedad)),
      tempSecado: _prom(sec.map((v) => v.temperatura)),
      humedadSecado: _prom(sec.map((v) => v.humedad)),
    );
  }

  /// Resumen por lote, ordenado de mejor a peor calidad (sin evaluar al final)
  /// y, dentro de la misma calidad, del más reciente al más antiguo.
  static List<ResumenLote> compararLotes(List<Lote> lotes) {
    final resumenes = lotes.map(resumir).where((r) => r.registros > 0).toList();
    resumenes.sort((a, b) {
      final c = Calidad.rango(a.lote.calidadResultado).compareTo(Calidad.rango(b.lote.calidadResultado));
      return c != 0 ? c : b.lote.createdAt.compareTo(a.lote.createdAt);
    });
    return resumenes;
  }

  /// Promedio de temperatura y humedad (promedio de los promedios de cada
  /// lote) agrupado por calidad. Solo lotes evaluados y con registros.
  static List<ResumenCalidad> porCalidad(List<Lote> lotes) {
    final resultado = <ResumenCalidad>[];
    for (final calidad in Calidad.todas) {
      final grupo = lotes
          .where((l) => l.calidadResultado == calidad)
          .map(resumir)
          .where((r) => r.registros > 0)
          .toList();
      if (grupo.isEmpty) continue;
      resultado.add(ResumenCalidad(
        calidad: calidad,
        lotes: grupo.length,
        tempPromedio: _prom(grupo.map((r) => r.tempPromedio!)),
        humedadPromedio: _prom(grupo.map((r) => r.humedadPromedio!)),
      ));
    }
    return resultado;
  }
}
