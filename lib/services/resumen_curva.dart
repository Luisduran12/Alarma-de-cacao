import '../data/referencias_curva.dart';
import '../models/volteada.dart';

enum Tendencia { subiendo, bajando, estable, pocosDatos }

/// Resumen de la curva de temperatura de un lote, en palabras simples.
///
/// Solo usa registros confirmados. Las "horas fuera de rango" se ESTIMAN
/// uniendo con una recta cada par de lecturas seguidas (no hay medidas entre
/// una y otra) y contando solo las horas en que existe una banda de
/// referencia (ver [ReferenciasCurva]).
class ResumenCurva {
  final int registros;
  final double? tempMaxima;
  final DateTime? fechaTempMaxima;

  /// Horas desde el inicio del lote en que se registró la máxima.
  final double? horaTempMaxima;

  /// Horas estimadas fuera de la banda, y horas (de las estimadas) que tenían banda.
  final double horasFuera;
  final double horasConReferencia;
  final Tendencia tendencia;

  const ResumenCurva({
    required this.registros,
    this.tempMaxima,
    this.fechaTempMaxima,
    this.horaTempMaxima,
    this.horasFuera = 0,
    this.horasConReferencia = 0,
    this.tendencia = Tendencia.pocosDatos,
  });

  /// Convención de la app, NO una norma: un cambio menor a este valor entre las
  /// dos últimas lecturas se considera "estable" (es del orden de lo que se
  /// equivoca un termómetro de campo).
  static const umbralTendenciaC = 1.0;

  static const _paso = Duration(minutes: 1);

  static ResumenCurva calcular(List<Volteada> registros, DateTime inicio) {
    final pts = registros.where((v) => v.confirmada).toList()..sort((a, b) => a.fecha.compareTo(b.fecha));
    if (pts.isEmpty) return const ResumenCurva(registros: 0);

    var max = pts.first;
    for (final v in pts) {
      if (v.temperatura > max.temperatura) max = v;
    }

    var fuera = 0.0, conRef = 0.0;
    for (var i = 0; i < pts.length - 1; i++) {
      final a = pts[i], b = pts[i + 1];
      final total = b.fecha.difference(a.fecha);
      if (total <= Duration.zero) continue;
      for (var t = Duration.zero; t < total; t += _paso) {
        final f = t.inMicroseconds / total.inMicroseconds;
        final valor = a.temperatura + (b.temperatura - a.temperatura) * f;
        final horas = a.fecha.add(t).difference(inicio).inMinutes / 60.0;
        final e = ReferenciasCurva.estadoTemperatura(valor, horas, a.etapa);
        if (e == EstadoRango.sinReferencia) continue;
        conRef += 1 / 60;
        if (e != EstadoRango.dentro) fuera += 1 / 60;
      }
    }

    var tendencia = Tendencia.pocosDatos;
    if (pts.length >= 2) {
      final d = pts.last.temperatura - pts[pts.length - 2].temperatura;
      tendencia = d >= umbralTendenciaC
          ? Tendencia.subiendo
          : d <= -umbralTendenciaC
              ? Tendencia.bajando
              : Tendencia.estable;
    }

    return ResumenCurva(
      registros: pts.length,
      tempMaxima: max.temperatura,
      fechaTempMaxima: max.fecha,
      horaTempMaxima: max.fecha.difference(inicio).inMinutes / 60.0,
      horasFuera: fuera,
      horasConReferencia: conRef,
      tendencia: tendencia,
    );
  }

  static String _num(double v) => v.toStringAsFixed(1).replaceAll('.', ',');

  /// "76 h (3 días y 4 h)" / "30 h".
  static String duracion(double horas) {
    final h = horas.round();
    if (h < 24) return '$h h';
    final d = h ~/ 24, r = h % 24;
    final dias = d == 1 ? '1 día' : '$d días';
    return r == 0 ? '$h h ($dias)' : '$h h ($dias y $r h)';
  }

  /// Frases cortas para el productor.
  List<String> frases() {
    if (registros == 0) return ['Todavía no hay registros para resumir.'];
    return [
      'La temperatura más alta fue ${_num(tempMaxima!)} °C, a las ${duracion(horaTempMaxima!)} '
          'del lote.',
      if (horasConReferencia < 1)
        'Aún no hay horas para comparar con la referencia (la de fermentación empieza a las 48 h).'
      else
        'Estuvo fuera del rango de referencia unas ${horasFuera.round()} h '
            'de ${horasConReferencia.round()} h comparables (cálculo aproximado entre registros).',
      switch (tendencia) {
        Tendencia.subiendo => 'En la última lectura la temperatura iba subiendo.',
        Tendencia.bajando => 'En la última lectura la temperatura iba bajando.',
        Tendencia.estable => 'En la última lectura la temperatura se mantuvo casi igual.',
        Tendencia.pocosDatos => 'Con un solo registro todavía no se puede ver la tendencia.',
      },
    ];
  }
}
