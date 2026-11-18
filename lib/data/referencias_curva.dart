import '../models/volteada.dart';

/// Un rango de referencia con su fuente.
///
/// [minimo] o [maximo] en null significa que esa fuente no da ese límite.
/// [desdeHora]: el rango solo aplica desde esa hora del lote (null = siempre).
/// [maximoEsLimite]: false si la fuente dice "o más" (el máximo es solo la
/// referencia habitual, no un tope que dañe el grano).
class RangoReferencia {
  final double? minimo;
  final double? maximo;
  final double? desdeHora;
  final bool maximoEsLimite;
  final String unidad;
  final String fuente;

  const RangoReferencia({
    this.minimo,
    this.maximo,
    this.desdeHora,
    this.maximoEsLimite = true,
    required this.unidad,
    required this.fuente,
  });

  bool aplicaEn(double horas) => desdeHora == null || horas >= desdeHora!;
}

enum EstadoRango { dentro, bajo, alto, sinReferencia }

/// ÚNICA tabla de rangos de referencia de la curva. Ningún otro archivo debe
/// escribir estos números.
///
/// Los valores salen de dos documentos que se leyeron completos. Las citas
/// literales y la página de cada una están en docs/fuentes-curva.md.
///
/// LO QUE NO TIENE FUENTE VERIFICADA (por eso no hay banda):
///  - Temperatura de la masa en las primeras 48 h: ninguna de las dos fuentes
///    da un rango para esas horas.
///  - pH: las fuentes describen una evolución (de ~3,5 a ~5) pero no un rango
///    de "normal / fuera de rango" para el productor.
///  - Brix: no aparece en ninguna de las dos fuentes.
///  - Temperatura ambiente: depende del lugar; no hay rango de "normal".
class ReferenciasCurva {
  ReferenciasCurva._();

  /// FHIA (2017): "verificar que la temperatura suba y se mantenga arriba de
  /// 45 ºC a partir del tercer día y aumentará hasta 50 °C o más en los días
  /// posteriores". Se toma el tercer día como desde la hora 48 (interpretación
  /// propia: la fuente dice "tercer día", no una hora). Universidad de La Salle
  /// (Medina, 2022): la masa llega "aproximadamente a 50 °C".
  static const fermentacionTemperatura = RangoReferencia(
    minimo: 45,
    maximo: 50,
    desdeHora: 48,
    maximoEsLimite: false,
    unidad: '°C',
    fuente: 'FHIA, InfoCacao No. 14 (2017), p. 3: "arriba de 45 ºC a partir del tercer día '
        'y aumentará hasta 50 °C o más". Universidad de La Salle / FEDECACAO '
        '(Medina, 2022): masa a "aproximadamente 50 °C". Medida en el centro de la masa.',
  );

  /// Universidad de La Salle (Medina, 2022): la temperatura de secado "no debe
  /// superar los 50ºC". FHIA (2017) acepta secado artificial de 40 hasta 55 °C:
  /// aquí se usa el valor más prudente. Sin mínimo en las fuentes.
  static const secadoTemperatura = RangoReferencia(
    maximo: 50,
    unidad: '°C',
    fuente: 'Universidad de La Salle / FEDECACAO (Medina, 2022), p. 7: temperatura de '
        'secado "no debe superar los 50ºC". FHIA (2017), p. 5, para secadora '
        'artificial: de 40 °C hasta 55 °C.',
  );

  /// Meta de humedad del GRANO al terminar el secado. No se dibuja como banda
  /// en la curva: la "humedad" que registra la app no se define como humedad
  /// del grano, y esta cifra es un valor final, no un rango durante el proceso.
  static const humedadGranoFinalSecado = RangoReferencia(
    minimo: 6.5,
    maximo: 7.0,
    unidad: '%',
    fuente: 'FHIA, InfoCacao No. 14 (2017), p. 5: "humedad del grano sea de 6.5 a 7.0 %"; '
        'menos de 6,0 % se vuelve quebradizo. Medina (2022): secar hasta 7 %.',
  );

  /// Variables sin banda por falta de fuente verificable (se muestran en la app).
  static const sinReferenciaVerificada = <String, String>{
    'ph': 'No hay un rango verificado de pH para decir "normal" o "fuera de rango".',
    'brix': 'No se encontró fuente verificable para Brix.',
    'tempAmbiente': 'La temperatura ambiente depende del lugar; no hay un rango de referencia.',
  };

  /// Banda de temperatura de la masa para una etapa (null = sin banda).
  static RangoReferencia? temperaturaPara(String etapa) =>
      etapa == Etapa.secado ? secadoTemperatura : fermentacionTemperatura;

  /// Compara [valor] (°C) con la banda de [etapa] a las [horas] del lote.
  static EstadoRango estadoTemperatura(double valor, double horas, String etapa) {
    final r = temperaturaPara(etapa);
    if (r == null || !r.aplicaEn(horas)) return EstadoRango.sinReferencia;
    if (r.minimo != null && valor < r.minimo!) return EstadoRango.bajo;
    if (r.maximo != null && valor > r.maximo!) return EstadoRango.alto;
    return EstadoRango.dentro;
  }
}
