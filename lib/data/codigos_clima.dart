/// Descripciones en español de los códigos de clima WMO que devuelve Open-Meteo.
///
/// Los códigos y su significado salen de la documentación de Open-Meteo
/// (https://open-meteo.com/en/docs, "WMO Weather interpretation codes (WW)"); la
/// traducción al español es de esta app. La API solo devuelve el número: la
/// descripción hay que ponerla en el cliente.
class CodigosClima {
  CodigosClima._();

  static const _descripciones = <int, String>{
    0: 'Cielo despejado',
    1: 'Casi despejado',
    2: 'Parcialmente nublado',
    3: 'Nublado',
    45: 'Niebla',
    48: 'Niebla con escarcha',
    51: 'Llovizna ligera',
    53: 'Llovizna moderada',
    55: 'Llovizna densa',
    56: 'Llovizna helada ligera',
    57: 'Llovizna helada densa',
    61: 'Lluvia ligera',
    63: 'Lluvia moderada',
    65: 'Lluvia fuerte',
    66: 'Lluvia helada ligera',
    67: 'Lluvia helada fuerte',
    71: 'Nevada ligera',
    73: 'Nevada moderada',
    75: 'Nevada fuerte',
    77: 'Granos de nieve',
    80: 'Chubascos ligeros',
    81: 'Chubascos moderados',
    82: 'Chubascos violentos',
    85: 'Chubascos de nieve ligeros',
    86: 'Chubascos de nieve fuertes',
    95: 'Tormenta eléctrica',
    96: 'Tormenta con granizo ligero',
    97: 'Tormenta fuerte',
    99: 'Tormenta con granizo fuerte',
  };

  /// Códigos de la tabla (para pruebas).
  static Iterable<int> get conocidos => _descripciones.keys;

  static String descripcion(int? codigo) {
    if (codigo == null) return 'Sin descripción del cielo';
    return _descripciones[codigo] ?? 'Condición no reconocida (código $codigo)';
  }

  /// true si el código indica llovizna, lluvia, chubascos o tormenta.
  static bool hayPrecipitacion(int? codigo) =>
      codigo != null && ((codigo >= 51 && codigo <= 67) || (codigo >= 80 && codigo <= 82) || codigo >= 95);
}
