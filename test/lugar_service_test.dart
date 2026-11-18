import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:alarmacacao5_0/data/cacao_database.dart';
import 'package:alarmacacao5_0/models/lote.dart';
import 'package:alarmacacao5_0/models/volteada.dart';
import 'package:alarmacacao5_0/services/lote_service.dart';
import 'package:alarmacacao5_0/services/lugar_service.dart';
import 'package:alarmacacao5_0/services/lugares_offline.dart';

const _idPrueba = '3f2b8c1e-9d4a-4b7e-8a1c-0e5d6f7a8b9c';

const _lista = '''
{"fuente":"DANE","licencia":"CC BY-SA 4.0","corte":"2024-12-30","departamentos":["Norte de Santander"],
"lugares":[["Chinácota","Chinácota",0,7.603112,-72.601162,"M"],["Hatoviejo","Durania",0,7.77449,-72.69209,"C"]]}
''';

Volteada _reg(String id, double? lat, double? lng) => Volteada(
      id: id, loteId: 'L1', mensaje: '', temperatura: 30, humedad: 60, observacion: '',
      fecha: DateTime(2026, 1, 1), fechaProgramada: DateTime(2026, 1, 1), confirmada: true,
      etapa: Etapa.secado, latitud: lat, longitud: lng,
    );

void main() {
  sqfliteFfiInit();

  late Database db;
  late LoteService lotes;
  late List<Uri> pedidos;
  late List<http.Request> peticiones;
  late List<Duration> pausas;
  late http.Response Function(Uri) responder;

  LugarService servicio({String url = 'https://api.cacaolight.example/v1'}) => LugarService(
        database: () async => db,
        cliente: MockClient((r) async {
          pedidos.add(r.url);
          peticiones.add(r);
          return responder(r.url);
        }),
        urlServidor: url,
        idInstalacion: () async => _idPrueba,
        lista: () async => LugaresOffline.desdeJson(_lista),
        esperar: (d) async => pausas.add(d),
        ahora: () => DateTime.utc(2026, 11, 18),
      );

  Future<void> sembrar(List<Volteada> registros) async => lotes.addLote(Lote(
        id: 'L1', title: 'Lote', status: 'en proceso', createdAt: DateTime(2026, 1, 1), volteadas: registros,
      ));

  http.Response ok(String nombre, [String fuente = '© colaboradores de OpenStreetMap']) =>
      http.Response('{"nombre":"$nombre","fuente":"$fuente"}', 200, headers: {'content-type': 'application/json; charset=utf-8'});

  setUp(() async {
    db = await CacaoDatabase.abrir(databaseFactoryFfi, inMemoryDatabasePath);
    lotes = LoteService(database: () async => db, cancelarNotificacion: (_) async {});
    pedidos = [];
    peticiones = [];
    pausas = [];
    responder = (_) => ok('Chinácota, Norte de Santander, Colombia');
  });

  tearDown(() => db.close());

  group('clave', () {
    test('3 decimales (≈ 110 m), con signo', () {
      expect(LugarService.clave(7.603112, -72.601162), '7.603,-72.601');
      expect(LugarService.clave(-4.19895, -69.94), '-4.199,-69.940');
    });
  });

  group('nombreDe (nunca usa internet)', () {
    test('sin dato del servidor: la referencia de la lista offline, marcada como aproximada', () async {
      final n = (await servicio().nombreDe(7.6031, -72.6012))!;
      expect(n.texto, 'Cerca de Chinácota (Norte de Santander), a menos de 1 km');
      expect(n.origen, OrigenLugar.listaOffline);
      expect(n.aproximado, isTrue);
      expect(n.fuente, contains('DANE'));
      expect(pedidos, isEmpty);
    });

    test('con el nombre del servidor guardado: usa ese, con su crédito', () async {
      await servicio().resolver(7.6031, -72.6012);
      pedidos.clear();
      final n = (await servicio().nombreDe(7.6029, -72.6014))!; // mismo punto (≈ 110 m)
      expect(n.texto, 'Chinácota, Norte de Santander, Colombia');
      expect(n.origen, OrigenLugar.servidor);
      expect(n.aproximado, isFalse);
      expect(n.fuente, '© colaboradores de OpenStreetMap');
      expect(pedidos, isEmpty);
    });

    test('un "sin resultado" guardado no se muestra: sigue la referencia offline', () async {
      responder = (_) => http.Response('', 404);
      await servicio().resolver(7.6031, -72.6012);
      final n = (await servicio().nombreDe(7.6031, -72.6012))!;
      expect(n.origen, OrigenLugar.listaOffline);
    });
  });

  group('resolver (una consulta al servidor)', () {
    test('es un POST con lat/lng (3 decimales) en el CUERPO, el ID de instalación en una cabecera y sin ninguna clave', () async {
      await servicio().resolver(7.603112, -72.601162);
      final p = peticiones.single;
      expect(p.method, 'POST');
      expect(p.url.toString(), 'https://api.cacaolight.example/v1/lugar', reason: 'sin coordenadas en la URL');
      expect(jsonDecode(p.body), {'lat': 7.603, 'lng': -72.601});
      expect(p.headers['X-Install-Id'], _idPrueba);
      expect(p.headers['Content-Type'], contains('application/json'));
      expect(p.url.query, isEmpty);
      expect(p.headers.keys.map((k) => k.toLowerCase()), isNot(contains('authorization')));
    });

    test('la URL base puede terminar en "/"', () async {
      await servicio(url: 'https://x.example/').resolver(7.6, -72.6);
      expect(pedidos.single.path, '/lugar');
    });

    test('guarda y devuelve el nombre', () async {
      final n = (await servicio().resolver(7.6031, -72.6012))!;
      expect(n.texto, 'Chinácota, Norte de Santander, Colombia');
      expect(await db.query('lugares'), hasLength(1));
    });

    test('lee bien los acentos de la respuesta (UTF-8)', () async {
      responder = (_) => http.Response.bytes(utf8.encode('{"nombre":"Cúcuta, Norte de Santander, Ñ"}'), 200);
      final n = await servicio().resolver(7.89, -72.5);
      expect(n!.texto, 'Cúcuta, Norte de Santander, Ñ');
    });

    test('sin servidor configurado no consulta y devuelve null', () async {
      final s = servicio(url: '');
      expect(s.servidorConfigurado, isFalse);
      expect(await s.resolver(7.6, -72.6), isNull);
      expect(pedidos, isEmpty);
    });

    test('una URL mal escrita se trata como "sin servidor"', () {
      expect(servicio(url: 'esto no es una url').servidorConfigurado, isFalse);
      expect(servicio(url: 'api.cacaolight.example').servidorConfigurado, isFalse);
    });

    test('sin señal: null y no guarda nada', () async {
      final s = LugarService(
        database: () async => db,
        cliente: MockClient((_) async => throw const SocketException('sin red')),
        urlServidor: 'https://x.example',
        lista: () async => LugaresOffline.desdeJson(_lista),
      );
      expect(await s.resolver(7.6, -72.6), isNull);
      expect(await db.query('lugares'), isEmpty);
    });

    test('respuestas inservibles no se guardan (429, 500, nombre vacío, demasiado largo, no-JSON, sin nombre)', () async {
      for (final r in [
        http.Response('', 429),
        http.Response('', 500),
        http.Response('{"nombre":""}', 200),
        http.Response('{"nombre":"${'x' * 300}"}', 200),
        http.Response('no es json', 200),
        http.Response('{"otra":"cosa"}', 200),
        http.Response('{"nombre":123}', 200),
      ]) {
        responder = (_) => r;
        expect(await servicio().resolver(7.6, -72.6), isNull, reason: '${r.statusCode} ${r.body}');
      }
      expect(await db.query('lugares'), isEmpty);
    });
  });

  group('resolverPendientes', () {
    test('sin servidor configurado no hace nada', () async {
      await sembrar([_reg('a', 7.6, -72.6)]);
      expect(await servicio(url: '').resolverPendientes(), 0);
      expect(pedidos, isEmpty);
    });

    test('una consulta por punto distinto, aunque haya muchos registros en el mismo punto', () async {
      await sembrar([
        _reg('a', 7.603112, -72.601162),
        _reg('b', 7.6031, -72.6012), // mismo punto (≈ 110 m)
        _reg('c', 7.60312, -72.60117),
        _reg('d', 7.77449, -72.69209), // otro punto
        _reg('e', null, null), // sin ubicación: se ignora
      ]);
      expect(await servicio().resolverPendientes(), 2);
      expect(pedidos, hasLength(2));
    });

    test('espera al menos 1 segundo entre consultas (Nominatim: 1 por segundo)', () async {
      await sembrar([_reg('a', 7.60, -72.60), _reg('b', 7.70, -72.70), _reg('c', 7.80, -72.80)]);
      await servicio().resolverPendientes();
      expect(pedidos, hasLength(3));
      expect(pausas, hasLength(2), reason: 'ninguna antes de la primera');
      expect(pausas.every((d) => d >= const Duration(seconds: 1)), isTrue);
    });

    test('no vuelve a consultar lo que ya tiene nombre del servidor', () async {
      await sembrar([_reg('a', 7.60, -72.60), _reg('b', 7.70, -72.70)]);
      await servicio().resolverPendientes();
      pedidos.clear();
      expect(await servicio().resolverPendientes(), 0);
      expect(pedidos, isEmpty);
    });

    test('respeta el máximo por vez y deja el resto para después', () async {
      await sembrar([for (var i = 0; i < 6; i++) _reg('r$i', 7.0 + i * 0.1, -72.6)]);
      expect(await servicio().resolverPendientes(maximo: 4), 4);
      expect(await servicio().resolverPendientes(maximo: 4), 2);
      expect(pedidos, hasLength(6));
    });

    test('al primer fallo de red se detiene (no sigue golpeando) y no guarda nada', () async {
      await sembrar([_reg('a', 7.60, -72.60), _reg('b', 7.70, -72.70), _reg('c', 7.80, -72.80)]);
      responder = (_) => http.Response('', 503);
      expect(await servicio().resolverPendientes(), 0);
      expect(pedidos, hasLength(1));
      expect(await db.query('lugares'), isEmpty);
    });

    test('con 429 (límite) se detiene, conserva lo ya resuelto y lo demás queda pendiente', () async {
      await sembrar([_reg('a', 7.60, -72.60), _reg('b', 7.70, -72.70), _reg('c', 7.80, -72.80)]);
      var n = 0;
      responder = (_) => ++n == 1 ? ok('Primero') : http.Response('', 429);
      expect(await servicio().resolverPendientes(), 1);
      expect(pedidos, hasLength(2));

      responder = (_) => ok('Resuelto después');
      pedidos.clear();
      expect(await servicio().resolverPendientes(), 2, reason: 'los dos que faltaban');
    });

    test('un 404 se guarda como "sin resultado" y no se vuelve a pedir, y no corta el resto', () async {
      await sembrar([_reg('a', 7.60, -72.60), _reg('b', 7.70, -72.70)]);
      var n = 0;
      responder = (_) => ++n == 1 ? http.Response('', 404) : ok('Segundo');
      expect(await servicio().resolverPendientes(), 1, reason: 'el 404 no cuenta como nombre guardado');
      expect(pedidos, hasLength(2));

      pedidos.clear();
      expect(await servicio().resolverPendientes(), 0);
      expect(pedidos, isEmpty, reason: 'ya no se insiste con el que no tuvo resultado');
    });

    test('sin ningún registro con ubicación no consulta', () async {
      await sembrar([_reg('a', null, null)]);
      expect(await servicio().resolverPendientes(), 0);
      expect(pedidos, isEmpty);
    });
  });

  group('migración a v5', () {
    test('una base v4 con datos pasa a la versión actual sin perder nada y con la caché vacía', () async {
      final dir = Directory.systemTemp.createTempSync('cacao_v5_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final ruta = p.join(dir.path, 'cacao.db');
      final v4 = await databaseFactoryFfi.openDatabase(
        ruta,
        options: OpenDatabaseOptions(
          version: 4,
          onCreate: (db, _) async {
            await db.execute('''CREATE TABLE lotes (id TEXT PRIMARY KEY, titulo TEXT NOT NULL, estado TEXT NOT NULL,
              creado_en TEXT NOT NULL, inicio_ciclo TEXT, fin_ciclo TEXT, plantilla TEXT,
              calidad_resultado TEXT, observacion_resultado TEXT)''');
            await db.execute('''CREATE TABLE registros (id TEXT PRIMARY KEY,
              lote_id TEXT NOT NULL REFERENCES lotes(id) ON DELETE CASCADE, mensaje TEXT NOT NULL DEFAULT '',
              fecha_programada TEXT NOT NULL, fecha TEXT NOT NULL, temperatura REAL, humedad REAL,
              observacion TEXT NOT NULL DEFAULT '', latitud REAL, longitud REAL,
              etapa TEXT NOT NULL DEFAULT 'fermentacion', confirmada INTEGER NOT NULL DEFAULT 0,
              notif_id INTEGER NOT NULL DEFAULT 0, ph REAL, brix REAL, temp_ambiente REAL)''');
            await db.execute('''CREATE TABLE recordatorios (id TEXT PRIMARY KEY,
              lote_id TEXT NOT NULL REFERENCES lotes(id) ON DELETE CASCADE, notif_id INTEGER NOT NULL,
              fecha_programada TEXT NOT NULL, tipo TEXT NOT NULL DEFAULT 'medir_temperatura')''');
          },
        ),
      );
      await v4.insert('lotes', {'id': 'L9', 'titulo': 'Lote v4', 'estado': 'en proceso', 'creado_en': '2026-01-01T08:00:00.000'});
      await v4.insert('registros', {
        'id': 'R9', 'lote_id': 'L9', 'fecha_programada': '2026-01-02T08:00:00.000', 'fecha': '2026-01-02T08:05:00.000',
        'temperatura': 33.0, 'humedad': 55.0, 'latitud': 7.6, 'longitud': -72.6, 'etapa': 'secado', 'confirmada': 1,
      });
      await v4.close();

      final nueva = await CacaoDatabase.abrir(databaseFactoryFfi, ruta);
      addTearDown(nueva.close);
      expect(await nueva.getVersion(), CacaoDatabase.version);
      expect((await nueva.query('lotes')).single['titulo'], 'Lote v4');
      final r = (await nueva.query('registros')).single;
      expect([r['temperatura'], r['latitud'], r['longitud']], [33.0, 7.6, -72.6]);
      expect(await nueva.query('lugares'), isEmpty);
      expect(await nueva.query('recordatorios'), isEmpty);
    });
  });
}
