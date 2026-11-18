import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alarmacacao5_0/data/codigos_clima.dart';
import 'package:alarmacacao5_0/models/clima.dart';
import 'package:alarmacacao5_0/services/clima_service.dart';
import 'package:alarmacacao5_0/utils/geo.dart';

/// Respuesta REAL de https://api.open-meteo.com/v1/forecast?latitude=7.60&longitude=-72.60
/// &current=temperature_2m,relative_humidity_2m,weather_code,is_day&timezone=auto
/// (consulta hecha el 2026-11-18, sin clave).
const _respuestaReal = '''
{"latitude":7.6274166,"longitude":-72.62753,"generationtime_ms":0.12981891632080078,"utc_offset_seconds":-18000,
"timezone":"America/Bogota","timezone_abbreviation":"GMT-5","elevation":1271.0,
"current_units":{"time":"iso8601","interval":"seconds","temperature_2m":"°C","relative_humidity_2m":"%","weather_code":"wmo code","is_day":""},
"current":{"time":"2026-11-18T17:30","interval":900,"temperature_2m":21.7,"relative_humidity_2m":81,"weather_code":1,"is_day":0}}
''';

/// 17:30 hora de Colombia (UTC-5) = 22:30 UTC.
final _medicionUtc = DateTime.utc(2026, 11, 18, 22, 30);
final _ahora = DateTime.utc(2026, 11, 18, 23, 0); // 30 min después de la medición

ClimaService _servicio(http.Client cliente, {DateTime? ahora}) =>
    ClimaService(cliente: cliente, ahora: () => ahora ?? _ahora);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('consulta a Open-Meteo', () {
    test('la dirección NO lleva clave y redondea la ubicación a 2 decimales', () {
      final u = ClimaService.consulta(7.603112, -72.601162);
      expect(u.host, 'api.open-meteo.com');
      expect(u.scheme, 'https');
      expect(u.path, '/v1/forecast');
      expect(u.queryParameters['latitude'], '7.60');
      expect(u.queryParameters['longitude'], '-72.60');
      expect(u.queryParameters['current'], 'temperature_2m,relative_humidity_2m,weather_code,is_day');
      expect(u.queryParameters['timezone'], 'auto');
      expect(u.query.toLowerCase(), isNot(contains('key')));
      expect(u.query.toLowerCase(), isNot(contains('appid')));
    });

    test('lee la respuesta real: temperatura, humedad, cielo, de día/noche y la hora en UTC', () async {
      Uri? pedida;
      final s = _servicio(MockClient((r) async {
        pedida = r.url;
        return http.Response(_respuestaReal, 200);
      }));
      final r = await s.consultar(7.603112, -72.601162);

      expect(pedida!.queryParameters['latitude'], '7.60');
      expect(r.desdeCache, isFalse);
      expect(r.aviso, isNull);
      expect(r.clima.temperaturaC, 21.7);
      expect(r.clima.humedadPct, 81);
      expect(r.clima.codigoWmo, 1);
      expect(r.clima.descripcion, 'Casi despejado');
      expect(r.clima.esDeDia, isFalse);
      expect(r.clima.medidoEn, _medicionUtc);
      expect(r.clima.fuente, FuenteClima.openMeteo);
      expect([r.clima.latitud, r.clima.longitud], [7.6, -72.6]);
    });

    test('la consulta exitosa queda guardada como último dato', () async {
      final s = _servicio(MockClient((_) async => http.Response(_respuestaReal, 200)));
      await s.consultar(7.6, -72.6);
      final guardado = await s.ultimo();
      expect(guardado!.temperaturaC, 21.7);
    });
  });

  group('"dato de hace X"', () {
    Clima conEdad(Duration d) => Clima(
          temperaturaC: 20, humedadPct: 80, medidoEn: _ahora.subtract(d), fuente: FuenteClima.openMeteo);

    test('formatos', () {
      expect(conEdad(const Duration(seconds: 10)).haceCuanto(_ahora), 'hace un momento');
      expect(conEdad(const Duration(minutes: 25)).haceCuanto(_ahora), 'hace 25 min');
      expect(conEdad(const Duration(hours: 1)).haceCuanto(_ahora), 'hace 1 hora');
      expect(conEdad(const Duration(hours: 5)).haceCuanto(_ahora), 'hace 5 horas');
      expect(conEdad(const Duration(hours: 24)).haceCuanto(_ahora), 'hace 1 día');
      expect(conEdad(const Duration(days: 3)).haceCuanto(_ahora), 'hace 3 días');
    });

    test('una medición "en el futuro" (reloj atrasado) no da un número negativo', () {
      expect(conEdad(const Duration(minutes: -5)).haceCuanto(_ahora), 'hace un momento');
    });

    test('se calcula desde la hora de la medición, no desde que se abrió la pantalla', () async {
      final s = _servicio(MockClient((_) async => http.Response(_respuestaReal, 200)));
      final r = await s.consultar(7.6, -72.6);
      expect(r.clima.haceCuanto(_ahora), 'hace 30 min');
      expect(r.clima.haceCuanto(_ahora.add(const Duration(hours: 5))), 'hace 5 horas');
    });
  });

  group('sin señal o con fallas', () {
    Future<ClimaService> conDatoGuardado() async {
      final bien = _servicio(MockClient((_) async => http.Response(_respuestaReal, 200)));
      await bien.consultar(7.6, -72.6);
      return bien;
    }

    ClimaService sin(Object error, {DateTime? ahora}) => _servicio(MockClient((_) async => throw error), ahora: ahora);

    test('sin internet y con dato guardado del mismo lugar: devuelve el guardado y lo avisa', () async {
      await conDatoGuardado();
      final r = await sin(const SocketException('sin red'), ahora: _ahora.add(const Duration(hours: 6)))
          .consultar(7.61, -72.61);
      expect(r.desdeCache, isTrue);
      expect(r.clima.temperaturaC, 21.7);
      expect(r.aviso, contains('Sin señal de internet'));
      expect(r.aviso, contains('último dato guardado'));
      expect(r.clima.haceCuanto(_ahora.add(const Duration(hours: 6))), 'hace 6 horas');
    });

    test('sin internet y sin nada guardado: error que ofrece escribirlo a mano', () async {
      await expectLater(
        sin(const SocketException('sin red')).consultar(7.6, -72.6),
        throwsA(isA<ClimaException>().having((e) => e.mensaje, 'mensaje', contains('a mano'))),
      );
    });

    test('el dato guardado es de otro lugar (más de 10 km): NO se usa y se explica', () async {
      await conDatoGuardado(); // 7.6, -72.6
      await expectLater(
        sin(const SocketException('sin red')).consultar(4.6, -74.1), // Bogotá
        throwsA(isA<ClimaException>().having((e) => e.mensaje, 'mensaje', contains('de otro lugar'))),
      );
    });

    test('servidor con error 500: usa el guardado y dice el código', () async {
      await conDatoGuardado();
      final r = await _servicio(MockClient((_) async => http.Response('boom', 500))).consultar(7.6, -72.6);
      expect(r.desdeCache, isTrue);
      expect(r.aviso, contains('(500)'));
    });

    test('error 400 (por ejemplo, latitud inválida) no se toma como un dato', () async {
      final s = _servicio(MockClient((_) async =>
          http.Response('{"error":true,"reason":"Latitude must be in range of -90 to 90°."}', 400)));
      await expectLater(s.consultar(999, -72.6), throwsA(isA<ClimaException>()));
    });

    test('tiempo de espera agotado', () async {
      await conDatoGuardado();
      final r = await sin(TimeoutException('lento')).consultar(7.6, -72.6);
      expect(r.aviso, contains('tardó demasiado'));
    });

    test('respuesta que no es JSON o no trae lo necesario se descarta', () async {
      await conDatoGuardado();
      for (final cuerpo in ['esto no es json', '{}', '{"current":{}}', '{"current":{"temperature_2m":"20"}}']) {
        final r = await _servicio(MockClient((_) async => http.Response(cuerpo, 200))).consultar(7.6, -72.6);
        expect(r.desdeCache, isTrue, reason: cuerpo);
        expect(r.clima.temperaturaC, 21.7, reason: 'se conserva el dato bueno, no se pisa con basura: $cuerpo');
      }
    });

    test('valores imposibles (999 °C, humedad 150 %) se descartan', () async {
      for (final cuerpo in [
        '{"current":{"time":"2026-11-18T17:30","temperature_2m":999,"relative_humidity_2m":50}}',
        '{"current":{"time":"2026-11-18T17:30","temperature_2m":20,"relative_humidity_2m":150}}',
      ]) {
        await expectLater(
          _servicio(MockClient((_) async => http.Response(cuerpo, 200))).consultar(7.6, -72.6),
          throwsA(isA<ClimaException>()),
          reason: cuerpo,
        );
      }
    });

    test('una consulta fallida no borra el último dato bueno', () async {
      final s = await conDatoGuardado();
      await sin(const SocketException('x')).consultar(7.6, -72.6);
      expect((await s.ultimo())!.temperaturaC, 21.7);
    });

    test('los campos opcionales pueden faltar (sin weather_code ni is_day)', () async {
      final s = _servicio(MockClient((_) async => http.Response(
          '{"utc_offset_seconds":-18000,"current":{"time":"2026-11-18T17:30","temperature_2m":22,"relative_humidity_2m":70}}', 200)));
      final c = (await s.consultar(7.6, -72.6)).clima;
      expect([c.codigoWmo, c.esDeDia], [null, null]);
      expect(c.descripcion, 'Sin descripción del cielo');
    });
  });

  group('escribir a mano (sin señal)', () {
    final s = _servicio(MockClient((_) async => http.Response('', 500)));

    test('guarda temperatura y humedad, marcadas como anotadas por el usuario', () async {
      final c = await s.guardarManual(temperaturaC: 26.5, humedadPct: 78, lat: 7.603112, lng: -72.601162);
      expect(c.esManual, isTrue);
      expect([c.temperaturaC, c.humedadPct, c.latitud, c.longitud], [26.5, 78, 7.6, -72.6]);
      expect(c.medidoEn, _ahora);
      expect((await s.ultimo())!.esManual, isTrue);
    });

    test('sin lugar también se guarda', () async {
      final c = await s.guardarManual(temperaturaC: 24, humedadPct: 60);
      expect([c.latitud, c.longitud], [null, null]);
    });

    test('un dato anotado a mano sirve de respaldo sin señal', () async {
      await s.guardarManual(temperaturaC: 26.5, humedadPct: 78);
      final r = await _servicio(MockClient((_) async => throw const SocketException('x'))).consultar(7.6, -72.6);
      expect(r.desdeCache, isTrue);
      expect(r.clima.esManual, isTrue);
    });

    test('valores imposibles se rechazan', () async {
      expect(() => s.guardarManual(temperaturaC: 99, humedadPct: 50), throwsArgumentError);
      expect(() => s.guardarManual(temperaturaC: 25, humedadPct: 101), throwsArgumentError);
      expect(() => s.guardarManual(temperaturaC: 25, humedadPct: -1), throwsArgumentError);
      expect(() => s.guardarManual(temperaturaC: double.nan, humedadPct: 50), throwsArgumentError);
    });

    test('lo rechazado no pisa el último dato', () async {
      await s.guardarManual(temperaturaC: 20, humedadPct: 50);
      try {
        await s.guardarManual(temperaturaC: 99, humedadPct: 50);
      } on ArgumentError {
        // esperado
      }
      expect((await s.ultimo())!.temperaturaC, 20);
    });
  });

  group('datos guardados dañados', () {
    test('texto que no es JSON se ignora', () async {
      SharedPreferences.setMockInitialValues({ClimaCache.clave: 'basura'});
      expect(await ClimaCache().leer(), isNull);
    });

    test('JSON incompleto se ignora', () async {
      SharedPreferences.setMockInitialValues({ClimaCache.clave: '{"temperaturaC":20}'});
      expect(await ClimaCache().leer(), isNull);
    });

    test('ida y vuelta conserva todo', () {
      final c = Clima(
          temperaturaC: 21.7, humedadPct: 81, codigoWmo: 61, esDeDia: true, medidoEn: _medicionUtc,
          fuente: FuenteClima.manual, latitud: 7.6, longitud: -72.6);
      final v = Clima.fromJson(c.toJson())!;
      expect([v.temperaturaC, v.humedadPct, v.codigoWmo, v.esDeDia, v.medidoEn, v.fuente, v.latitud, v.longitud],
          [21.7, 81, 61, true, _medicionUtc, FuenteClima.manual, 7.6, -72.6]);
    });
  });

  group('atribución y códigos', () {
    test('la atribución exigida por la licencia está definida con su enlace', () {
      expect(ClimaService.atribucion, 'Weather data by Open-Meteo.com');
      expect(ClimaService.enlaceAtribucion.toString(), 'https://open-meteo.com/');
    });

    test('todos los códigos de la tabla de Open-Meteo tienen descripción en español', () {
      expect(CodigosClima.conocidos, hasLength(29));
      for (final c in CodigosClima.conocidos) {
        expect(CodigosClima.descripcion(c), isNot(contains('no reconocida')), reason: '$c');
      }
    });

    test('un código desconocido no se inventa', () {
      expect(CodigosClima.descripcion(42), 'Condición no reconocida (código 42)');
      expect(CodigosClima.descripcion(null), 'Sin descripción del cielo');
    });

    test('precipitación', () {
      for (final c in [51, 55, 61, 65, 67, 80, 82, 95, 99]) {
        expect(CodigosClima.hayPrecipitacion(c), isTrue, reason: '$c');
      }
      for (final c in [0, 1, 2, 3, 45, 48, 71, 85]) {
        expect(CodigosClima.hayPrecipitacion(c), isFalse, reason: '$c');
      }
      expect(CodigosClima.hayPrecipitacion(null), isFalse);
    });
  });

  group('distanciaKm', () {
    test('mismo punto: 0', () => expect(distanciaKm(7.6, -72.6, 7.6, -72.6), 0));

    test('Chinácota a Durania (coordenadas DIVIPOLA del DANE): unos 14 km', () {
      final d = distanciaKm(7.603112, -72.601162, 7.714804, -72.658491);
      expect(d, inInclusiveRange(13, 15));
    });

    test('un grado de latitud ≈ 111 km', () {
      expect(distanciaKm(0, 0, 1, 0), closeTo(111.2, 0.5));
    });

    test('es simétrica', () {
      expect(distanciaKm(7.6, -72.6, 4.6, -74.1), closeTo(distanciaKm(4.6, -74.1, 7.6, -72.6), 1e-9));
    });
  });
}
