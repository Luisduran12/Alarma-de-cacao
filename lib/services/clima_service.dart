import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/clima.dart';
import '../utils/geo.dart';

/// El clima no se pudo obtener y tampoco hay un dato guardado que sirva.
class ClimaException implements Exception {
  final String mensaje;
  const ClimaException(this.mensaje);
  @override
  String toString() => mensaje;
}

/// Un clima y de dónde salió: de internet, o del último dato guardado en el teléfono.
class ResultadoClima {
  final Clima clima;
  final bool desdeCache;

  /// Por qué se muestra el dato guardado (por ejemplo, "sin señal"); null si es nuevo.
  final String? aviso;
  const ResultadoClima(this.clima, {this.desdeCache = false, this.aviso});
}

/// Guarda en el teléfono la ÚLTIMA consulta de clima (o el último dato anotado a mano).
class ClimaCache {
  static const clave = 'clima_ultimo_v1';

  Future<Clima?> leer() async {
    final prefs = await SharedPreferences.getInstance();
    final texto = prefs.getString(clave);
    if (texto == null) return null;
    try {
      return Clima.fromJson(jsonDecode(texto));
    } catch (_) {
      return null;
    }
  }

  Future<void> guardar(Clima clima) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(clave, jsonEncode(clima.toJson()));
  }

  Future<void> borrar() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(clave);
  }
}

/// Clima actual del ambiente con Open-Meteo (https://open-meteo.com/): no usa
/// clave. Los datos son CC BY 4.0: hay que mostrar el crédito junto a ellos
/// (ver [atribucion]).
///
/// Sin señal usa el último dato guardado, o el que el productor escribe a mano.
class ClimaService {
  static const host = 'api.open-meteo.com';
  static const ruta = '/v1/forecast';

  /// Texto y enlace del crédito que exige la licencia de Open-Meteo.
  static const atribucion = 'Weather data by Open-Meteo.com';
  static final enlaceAtribucion = Uri.parse('https://open-meteo.com/');

  /// Se envía la ubicación redondeada a este número de decimales (2 ≈ 1 km): el
  /// clima no cambia a esa escala y así no se comparte la posición exacta de la finca.
  static const decimalesUbicacion = 2;

  /// Si el último dato guardado es de un lugar a más de esta distancia, no se usa
  /// como respaldo sin señal (sería el clima de otro sitio). Valor de la app, no de una norma.
  static const distanciaMaxCacheKm = 10.0;

  /// Límites de sentido común para descartar datos corruptos (no son rangos agronómicos).
  static const _tempMin = -60.0, _tempMax = 60.0;

  final http.Client _cliente;
  final ClimaCache _cache;
  final DateTime Function() _ahora;
  final Duration _espera;

  ClimaService({http.Client? cliente, ClimaCache? cache, DateTime Function()? ahora, Duration? espera})
      : _cliente = cliente ?? http.Client(),
        _cache = cache ?? ClimaCache(),
        _ahora = ahora ?? DateTime.now,
        _espera = espera ?? const Duration(seconds: 12);

  /// Dirección de la consulta (pública para poder probarla).
  static Uri consulta(double lat, double lng) => Uri.https(host, ruta, {
        'latitude': lat.toStringAsFixed(decimalesUbicacion),
        'longitude': lng.toStringAsFixed(decimalesUbicacion),
        'current': 'temperature_2m,relative_humidity_2m,weather_code,is_day',
        'timezone': 'auto',
      });

  /// Consulta el clima de ese lugar. Si no hay señal o el servidor falla, devuelve el
  /// último dato guardado (marcado `desdeCache`); si tampoco hay, lanza [ClimaException].
  Future<ResultadoClima> consultar(double lat, double lng) async {
    String motivo;
    try {
      final r = await _cliente.get(consulta(lat, lng)).timeout(_espera);
      if (r.statusCode == 200) {
        final clima = _leer(r.body, lat, lng);
        await _cache.guardar(clima);
        return ResultadoClima(clima);
      }
      motivo = 'El servicio del clima respondió con un error (${r.statusCode}).';
    } on TimeoutException {
      motivo = 'El servicio del clima tardó demasiado.';
    } on FormatException {
      motivo = 'El servicio del clima mandó una respuesta que no se entiende.';
    } catch (_) {
      motivo = 'Sin señal de internet.';
    }

    final guardado = await _cache.leer();
    if (guardado != null && _esDeEsteLugar(guardado, lat, lng)) {
      return ResultadoClima(guardado, desdeCache: true, aviso: '$motivo Se muestra el último dato guardado.');
    }
    throw ClimaException(guardado == null
        ? '$motivo No hay un dato guardado: puede escribir la temperatura y la humedad a mano.'
        : '$motivo El último dato guardado es de otro lugar: puede escribir la temperatura y la humedad a mano.');
  }

  /// El último dato guardado (de internet o anotado a mano), sin consultar nada.
  Future<Clima?> ultimo() => _cache.leer();

  /// Guarda lo que el productor escribe cuando no hay señal. Devuelve el dato guardado.
  /// Lanza [ArgumentError] si los valores no son posibles.
  Future<Clima> guardarManual({
    required double temperaturaC,
    required double humedadPct,
    double? lat,
    double? lng,
  }) async {
    if (temperaturaC.isNaN || temperaturaC < _tempMin || temperaturaC > _tempMax) {
      throw ArgumentError('La temperatura debe estar entre ${_tempMin.round()} y ${_tempMax.round()} °C.');
    }
    if (humedadPct.isNaN || humedadPct < 0 || humedadPct > 100) {
      throw ArgumentError('La humedad debe estar entre 0 y 100 %.');
    }
    final clima = Clima(
      temperaturaC: temperaturaC,
      humedadPct: humedadPct.round(),
      medidoEn: _ahora().toUtc(),
      fuente: FuenteClima.manual,
      latitud: lat == null ? null : double.parse(lat.toStringAsFixed(decimalesUbicacion)),
      longitud: lng == null ? null : double.parse(lng.toStringAsFixed(decimalesUbicacion)),
    );
    await _cache.guardar(clima);
    return clima;
  }

  bool _esDeEsteLugar(Clima c, double lat, double lng) {
    if (c.latitud == null || c.longitud == null) return true; // anotado a mano sin lugar
    return distanciaKm(c.latitud!, c.longitud!, lat, lng) <= distanciaMaxCacheKm;
  }

  /// Lee la respuesta de Open-Meteo. Lanza [FormatException] si no trae lo necesario.
  Clima _leer(String cuerpo, double lat, double lng) {
    final json = jsonDecode(cuerpo);
    if (json is! Map || json['current'] is! Map) throw const FormatException('sin "current"');
    final c = json['current'] as Map;
    final t = c['temperature_2m'], h = c['relative_humidity_2m'];
    if (t is! num || h is! num) throw const FormatException('faltan temperatura o humedad');
    if (t < _tempMin || t > _tempMax || h < 0 || h > 100) throw const FormatException('valores imposibles');

    // `time` viene en la hora local del lugar (timezone=auto) sin zona: se pasa a UTC
    // con `utc_offset_seconds` para poder calcular "hace X horas" con cualquier reloj.
    final hora = DateTime.tryParse('${c['time']}Z');
    final desfase = (json['utc_offset_seconds'] as num?)?.toInt() ?? 0;
    final medido = hora == null ? _ahora().toUtc() : hora.subtract(Duration(seconds: desfase));

    final esDia = c['is_day'];
    return Clima(
      temperaturaC: t.toDouble(),
      humedadPct: h.round(),
      codigoWmo: (c['weather_code'] as num?)?.toInt(),
      esDeDia: esDia is num ? esDia != 0 : null,
      medidoEn: medido,
      fuente: FuenteClima.openMeteo,
      latitud: double.parse(lat.toStringAsFixed(decimalesUbicacion)),
      longitud: double.parse(lng.toStringAsFixed(decimalesUbicacion)),
    );
  }
}
