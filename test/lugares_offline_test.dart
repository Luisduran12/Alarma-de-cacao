import 'package:flutter_test/flutter_test.dart';

import 'package:alarmacacao5_0/services/lugares_offline.dart';

/// Lista pequeña y controlada para probar la lógica.
const _pequena = '''
{"fuente":"DANE","licencia":"CC BY-SA 4.0","corte":"2024-12-30",
"departamentos":["Norte de Santander","Antioquia"],
"lugares":[
 ["Chinácota","Chinácota",0,7.603112,-72.601162,"M"],
 ["Durania","Durania",0,7.714804,-72.658491,"M"],
 ["Hatoviejo","Durania",0,7.77449,-72.69209,"C"],
 ["Medellín","Medellín",1,6.246631,-75.581775,"M"]
]}
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('con una lista pequeña', () {
    final lista = LugaresOffline.desdeJson(_pequena);

    test('lee fuente, licencia y corte', () {
      expect(lista.cantidad, 4);
      expect([lista.fuente, lista.licencia, lista.corte], ['DANE', 'CC BY-SA 4.0', '2024-12-30']);
    });

    test('un punto sobre un municipio devuelve ese municipio, a menos de 1 km', () {
      final l = lista.masCercano(7.6031, -72.6012)!;
      expect(l.nombre, 'Chinácota');
      expect(l.esMunicipio, isTrue);
      expect(l.departamento, 'Norte de Santander');
      expect(l.texto, 'Cerca de Chinácota (Norte de Santander), a menos de 1 km');
    });

    test('elige un centro poblado si es más cercano que el municipio', () {
      final l = lista.masCercano(7.77, -72.69)!;
      expect(l.nombre, 'Hatoviejo');
      expect(l.esMunicipio, isFalse);
      expect(l.texto, startsWith('Cerca de Hatoviejo, Durania (Norte de Santander), a '));
    });

    test('la distancia sale en km con coma decimal si es menor a 10 km, entera si no', () {
      final cerca = lista.masCercano(7.6031 + 0.03, -72.6012)!; // ~3,3 km al norte de Chinácota
      expect(cerca.nombre, 'Chinácota');
      expect(cerca.texto, matches(RegExp(r'a \d,\d km$')));

      // ~13 km al SUR de Chinácota (al norte quedaría más cerca de Durania).
      final lejos = lista.masCercano(7.6031 - 0.12, -72.6012)!;
      expect(lejos.nombre, 'Chinácota');
      expect(lejos.texto, matches(RegExp(r'a \d{2} km$')));
    });

    test('sin distancia máxima: lejos de todo igual devuelve lo más cercano y dice cuánto', () {
      final l = lista.masCercano(4.6, -74.1)!; // Bogotá
      expect(l.nombre, 'Medellín');
      expect(l.distanciaKm, greaterThan(200));
      expect(l.texto, contains('km'));
    });

    test('coordenadas inválidas devuelven null', () {
      expect(lista.masCercano(double.nan, 0), isNull);
      expect(lista.masCercano(999, 0), isNull);
      expect(lista.masCercano(0, 999), isNull);
    });

    test('lista vacía devuelve null', () {
      final vacia = LugaresOffline.desdeJson('{"departamentos":[],"lugares":[]}');
      expect(vacia.masCercano(7.6, -72.6), isNull);
    });
  });

  group('con la lista real de la app (DANE)', () {
    late LugaresOffline real;
    setUpAll(() async => real = await LugaresOffline.cargar());

    test('trae miles de lugares con su fuente y licencia', () {
      expect(real.cantidad, 8167);
      expect(real.licencia, contains('CC BY-SA 4.0'));
      expect(real.fuente, contains('DANE'));
      expect(real.corte, '2024-12-30');
    });

    test('Chinácota y Durania (los municipios del productor) están en la lista', () {
      final c = real.masCercano(7.603112, -72.601162)!;
      expect(c.nombre, 'Chinácota');
      expect(c.departamento, 'Norte de Santander');
      final d = real.masCercano(7.714804, -72.658491)!;
      expect(d.nombre, 'Durania');
    });

    test('en la zona hay centros poblados con nombre de vereda (Chitacomar, Hatoviejo)', () {
      expect(real.masCercano(7.574227, -72.592433)!.nombre, 'Chitacomar');
      expect(real.masCercano(7.77449, -72.69209)!.nombre, 'Hatoviejo');
    });

    test('un punto cualquiera cerca de Cúcuta cae en Norte de Santander', () {
      final l = real.masCercano(7.89, -72.50)!;
      expect(l.departamento, 'Norte de Santander');
    });

    test('buscar entre ~8.000 lugares es rápido (lista offline usable en un teléfono de gama baja)', () {
      final sw = Stopwatch()..start();
      for (var i = 0; i < 20; i++) {
        real.masCercano(7.6 + i * 0.01, -72.6);
      }
      sw.stop();
      // 20 búsquedas; en un teléfono lento podría ser unas 10 veces más, aún imperceptible.
      expect(sw.elapsedMilliseconds, lessThan(2000));
    });

    test('cargar dos veces devuelve la misma lista (no se vuelve a leer el archivo)', () async {
      expect(identical(await LugaresOffline.cargar(), real), isTrue);
    });
  });
}
