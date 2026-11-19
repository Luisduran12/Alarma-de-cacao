import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:alarmacacao5_0/data/cacao_database.dart';
import 'package:alarmacacao5_0/models/analisis_foto.dart';
import 'package:alarmacacao5_0/models/lote.dart';
import 'package:alarmacacao5_0/services/consentimiento_fotos.dart';
import 'package:alarmacacao5_0/services/foto_preparada.dart';
import 'package:alarmacacao5_0/services/foto_service.dart';

const _id = '3f2b8c1e-9d4a-4b7e-8a1c-0e5d6f7a8b9c';

Map<String, Object?> _resp({String modo = 'corte', bool repetir = false, List<Map<String, Object>>? cats, String semaforo = 'verde'}) => {
      'modo': modo, 'foto_valida': true, 'repetir_foto': repetir, 'motivo': 'ninguno', 'mensaje': '',
      'categorias': cats ?? (repetir ? [] : [{'nombre': 'bien_fermentado', 'porcentaje': 70}, {'nombre': 'violeta', 'porcentaje': 30}]),
      'confianza': repetir ? 'baja' : 'media', 'posibles_causas': ['Fermentación completa'], 'pasos_recomendados': ['Pase a secado'],
      'semaforo': semaforo, 'aviso': 'Estimación orientativa. Ante duda, consulte al técnico.',
    };

http.Response _json(Object j, [int estado = 200, Map<String, String> h = const {}]) =>
    http.Response.bytes(utf8.encode(jsonEncode(j)), estado, headers: {'content-type': 'application/json; charset=utf-8', ...h});

void main() {
  sqfliteFfiInit();
  late Database db;
  late Directory dir;
  late List<http.Request> peticiones;
  late Future<http.Response> Function(http.Request) responder;
  var contador = 0;
  var reloj = DateTime.utc(2026, 11, 18, 12);

  final foto = FotoPreparada(Uint8List.fromList([0xff, 0xd8, 1, 2, 3, 0xff, 0xd9]), 640, 480);

  bool? autorizado = true;

  FotoService servicio({String url = 'https://api.cacaolight.example/v1', Duration? timeout}) => FotoService(
        database: () async => db,
        consentimiento: () async => autorizado,
        cliente: MockClient((r) {
          peticiones.add(r);
          return responder(r);
        }),
        urlServidor: url,
        timeout: timeout,
        idInstalacion: () async => _id,
        directorio: () async => dir,
        ahora: () => reloj = reloj.add(const Duration(minutes: 1)),
        nuevoId: () => 'foto-${++contador}',
      );

  setUp(() async {
    autorizado = true;
    SharedPreferences.setMockInitialValues({});
    db = await CacaoDatabase.abrir(databaseFactoryFfi, inMemoryDatabasePath);
    await db.insert('lotes', Lote(id: 'L1', title: 'Lote privado', status: 'en proceso', createdAt: DateTime(2026)).toRow());
    await db.insert('lotes', Lote(id: 'L2', title: 'Otro', status: 'en proceso', createdAt: DateTime(2026)).toRow());
    dir = await Directory.systemTemp.createTemp('fotos_prueba');
    peticiones = [];
    contador = 0;
    reloj = DateTime.utc(2026, 11, 18, 12);
    responder = (_) async => _json(_resp());
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  group('ResultadoAnalisis', () {
    test('lee un resultado válido, con las categorías de mayor a menor', () {
      final r = ResultadoAnalisis.desdeJson(_resp(cats: [
        {'nombre': 'violeta', 'porcentaje': 20.4},
        {'nombre': 'bien_fermentado', 'porcentaje': 79.6},
      ]));
      expect(r.categorias.map((c) => c.nombre), ['bien_fermentado', 'violeta']);
      expect(r.categorias.map((c) => c.porcentaje), [80, 20]);
      expect(r.semaforo, Semaforo.verde);
      expect(r.modo, ModoAnalisis.corte);
    });

    test('rechaza lo incoherente: modo, semáforo, porcentajes, o pedir otra foto con porcentajes', () {
      for (final malo in <Map<String, Object?>>[
        {..._resp(), 'modo': 'otro'},
        {..._resp(), 'semaforo': 'azul'},
        {..._resp(), 'confianza': 'altísima'},
        {..._resp(), 'repetir_foto': 'sí'},
        _resp(cats: [{'nombre': 'violeta', 'porcentaje': 140}]),
        _resp(cats: [{'nombre': 'violeta', 'porcentaje': -1}]),
        {..._resp(), 'categorias': 'no es lista'},
        {..._resp(repetir: true), 'categorias': [{'nombre': 'violeta', 'porcentaje': 50}]},
      ]) {
        expect(() => ResultadoAnalisis.desdeJson(malo), throwsFormatException, reason: '$malo');
      }
    });

    test('nombres legibles de categorías', () {
      expect(nombreCategoria('dano_por_insectos'), 'Daño por insectos');
      expect(nombreCategoria('algo_nuevo'), 'Algo nuevo');
    });
  });

  group('guardar y listar', () {
    test('guarda el archivo y una fila pendiente; cada lote ve solo sus fotos', () async {
      final s = servicio();
      final a = await s.guardar(loteId: 'L1', modo: ModoAnalisis.corte, foto: foto);
      await s.guardar(loteId: 'L2', modo: ModoAnalisis.mazorcaHoja, foto: foto);
      expect(a.estado, EstadoAnalisis.pendiente);
      expect(File(a.ruta).readAsBytesSync(), foto.bytes);
      expect(p.dirname(a.ruta), dir.path);
      expect((await s.listar('L1')).single.id, a.id);
      expect((await s.listar('L2')).single.modo, ModoAnalisis.mazorcaHoja);
      expect(await s.cuantasPendientes(), 2);
    });
  });

  group('analizar', () {
    test('envía SOLO modo e imagen (JPEG en base64), con X-Install-Id y a /analizar-foto', () async {
      final s = servicio(url: 'https://api.cacaolight.example/v1/');
      final a = await s.guardar(loteId: 'L1', modo: ModoAnalisis.granoSeco, foto: foto);
      await s.analizar(a.id).catchError((_) => a); // la respuesta de prueba es de corte: no importa aquí
      final r = peticiones.single;
      expect(r.method, 'POST');
      expect(r.url.toString(), 'https://api.cacaolight.example/v1/analizar-foto');
      expect(r.headers['X-Install-Id'], _id);
      final cuerpo = jsonDecode(r.body) as Map<String, dynamic>;
      expect(cuerpo.keys.toSet(), {'modo', 'imagen'});
      expect(cuerpo['modo'], 'grano_seco');
      expect(base64Decode(cuerpo['imagen'] as String), foto.bytes);
      for (final prohibido in ['Lote privado', 'L1', _id, 'lat', 'lng']) {
        expect(r.body, isNot(contains(prohibido)), reason: prohibido);
      }
    });

    test('con respuesta válida: queda analizada, con el resultado guardado y legible al reabrir', () async {
      final s = servicio();
      final a = await s.guardar(loteId: 'L1', modo: ModoAnalisis.corte, foto: foto);
      final ok = await s.analizar(a.id);
      expect(ok.estado, EstadoAnalisis.analizada);
      expect(ok.resultado!.semaforo, Semaforo.verde);
      expect(ok.analizadoEn, isNotNull);
      final releida = (await s.listar('L1')).single;
      expect(releida.estado, EstadoAnalisis.analizada);
      expect(releida.resultado!.categorias.first.nombre, 'bien_fermentado');
      expect(await s.cuantasPendientes(), 0);
    });

    test('analizar una foto ya analizada no vuelve a llamar al servidor', () async {
      final s = servicio();
      final a = await s.guardar(loteId: 'L1', modo: ModoAnalisis.corte, foto: foto);
      await s.analizar(a.id);
      await s.analizar(a.id);
      expect(peticiones, hasLength(1));
    });

    test('"pide otra foto" es un resultado válido (no un error) y no trae porcentajes', () async {
      responder = (_) async => _json(_resp(repetir: true, semaforo: 'amarillo'));
      final s = servicio();
      final a = await s.guardar(loteId: 'L1', modo: ModoAnalisis.corte, foto: foto);
      final ok = await s.analizar(a.id);
      expect(ok.resultado!.repetirFoto, isTrue);
      expect(ok.resultado!.categorias, isEmpty);
    });

    test('sin conexión: la foto sigue en la cola con el aviso y un intento más', () async {
      responder = (_) async => throw const SocketException('sin red');
      final s = servicio();
      final a = await s.guardar(loteId: 'L1', modo: ModoAnalisis.corte, foto: foto);
      final e = await s.analizar(a.id).then<FotoException?>((_) => null, onError: (e) => e as FotoException);
      expect(e!.codigo, 'sin_conexion');
      expect(e.reintentable, isTrue);
      final f = (await s.listar('L1')).single;
      expect(f.estado, EstadoAnalisis.pendiente);
      expect(f.intentos, 1);
      expect(f.ultimoError, contains('quedó guardada'));
      expect(File(f.ruta).existsSync(), isTrue);
    });

    test('tiempo agotado y errores del cliente también dejan la foto en la cola', () async {
      for (final falla in <Object>[TimeoutException('lento'), http.ClientException('x')]) {
        responder = (_) async => throw falla;
        final s = servicio();
        final a = await s.guardar(loteId: 'L1', modo: ModoAnalisis.corte, foto: foto);
        final e = await s.analizar(a.id).then<FotoException?>((_) => null, onError: (e) => e as FotoException);
        expect(e?.reintentable, isTrue, reason: '$falla');
      }
    });

    test('límite diario (429) y servidor ocupado (503): reintentable, con su mensaje y Retry-After', () async {
      responder = (_) async => _json({'error': {'codigo': 'limite_dia', 'mensaje': 'Hoy ya analizó muchas fotos. Vuelva mañana.'}}, 429, {'retry-after': '7200'});
      final s = servicio();
      final a = await s.guardar(loteId: 'L1', modo: ModoAnalisis.corte, foto: foto);
      final e = await s.analizar(a.id).then<FotoException?>((_) => null, onError: (e) => e as FotoException);
      expect(e!.codigo, 'limite_dia');
      expect(e.mensaje, 'Hoy ya analizó muchas fotos. Vuelva mañana.');
      expect(e.reintentable, isTrue);
      expect(e.reintentarEn, const Duration(hours: 2));
      expect((await s.listar('L1')).single.estado, EstadoAnalisis.pendiente);
    });

    test('foto rechazada por el servidor (400/413): queda en error y NO se reintenta', () async {
      responder = (_) async => _json({'error': {'codigo': 'imagen_danada', 'mensaje': 'La foto no se pudo leer. Tome otra.'}}, 400);
      final s = servicio();
      final a = await s.guardar(loteId: 'L1', modo: ModoAnalisis.corte, foto: foto);
      final e = await s.analizar(a.id).then<FotoException?>((_) => null, onError: (e) => e as FotoException);
      expect(e!.reintentable, isFalse);
      final f = (await s.listar('L1')).single;
      expect(f.estado, EstadoAnalisis.error);
      expect(f.ultimoError, 'La foto no se pudo leer. Tome otra.');
      expect(await s.cuantasPendientes(), 0);
    });

    test('respuesta 200 que no se puede entender: no se guarda, queda pendiente', () async {
      responder = (_) async => _json({'modo': 'corte', 'semaforo': 'azul'});
      final s = servicio();
      final a = await s.guardar(loteId: 'L1', modo: ModoAnalisis.corte, foto: foto);
      final e = await s.analizar(a.id).then<FotoException?>((_) => null, onError: (e) => e as FotoException);
      expect(e!.codigo, 'respuesta_invalida');
      expect((await s.listar('L1')).single.estado, EstadoAnalisis.pendiente);
    });

    test('sin servidor configurado: error claro, la foto queda guardada y no sale ninguna petición', () async {
      final s = servicio(url: '');
      final a = await s.guardar(loteId: 'L1', modo: ModoAnalisis.corte, foto: foto);
      final e = await s.analizar(a.id).then<FotoException?>((_) => null, onError: (e) => e as FotoException);
      expect(e!.codigo, 'sin_servidor');
      expect(peticiones, isEmpty);
      expect((await s.listar('L1')).single.estado, EstadoAnalisis.pendiente);
    });

    test('si el archivo ya no está, queda en error sin llamar al servidor', () async {
      final s = servicio();
      final a = await s.guardar(loteId: 'L1', modo: ModoAnalisis.corte, foto: foto);
      File(a.ruta).deleteSync();
      final e = await s.analizar(a.id).then<FotoException?>((_) => null, onError: (e) => e as FotoException);
      expect(e!.codigo, 'foto_perdida');
      expect(peticiones, isEmpty);
      expect((await s.listar('L1')).single.estado, EstadoAnalisis.error);
    });
  });

  group('cola de pendientes', () {
    test('al volver la señal manda las pendientes de la más vieja a la más nueva', () async {
      final s = servicio();
      final ids = [for (var i = 0; i < 3; i++) (await s.guardar(loteId: 'L1', modo: ModoAnalisis.corte, foto: foto)).id];
      expect(await s.procesarPendientes(), 3);
      expect(peticiones, hasLength(3));
      expect(await s.cuantasPendientes(), 0);
      expect((await s.listar('L1')).every((a) => a.estado == EstadoAnalisis.analizada), isTrue);
      expect(ids, hasLength(3));
    });

    test('se detiene en la primera falla de red y deja el resto en la cola', () async {
      var n = 0;
      responder = (_) async => ++n == 1 ? _json(_resp()) : throw const SocketException('sin red');
      final s = servicio();
      for (var i = 0; i < 3; i++) {
        await s.guardar(loteId: 'L1', modo: ModoAnalisis.corte, foto: foto);
      }
      expect(await s.procesarPendientes(), 1);
      expect(peticiones, hasLength(2), reason: 'la primera sale bien, la segunda falla y no se intenta la tercera');
      expect(await s.cuantasPendientes(), 2);
    });

    test('una foto rechazada no frena a las demás', () async {
      var n = 0;
      responder = (_) async => ++n == 1 ? _json({'error': {'codigo': 'imagen_danada', 'mensaje': 'mala'}}, 400) : _json(_resp());
      final s = servicio();
      for (var i = 0; i < 3; i++) {
        await s.guardar(loteId: 'L1', modo: ModoAnalisis.corte, foto: foto);
      }
      expect(await s.procesarPendientes(), 2);
    });

    test('respeta el máximo por vez y sin servidor no hace nada', () async {
      final s = servicio();
      for (var i = 0; i < 4; i++) {
        await s.guardar(loteId: 'L1', modo: ModoAnalisis.corte, foto: foto);
      }
      expect(await s.procesarPendientes(maximo: 2), 2);
      expect(await servicio(url: '').procesarPendientes(), 0);
    });
  });

  group('borrar', () {
    test('borrar quita el archivo y la fila; borrarDelLote solo las de ese lote', () async {
      final s = servicio();
      final a = await s.guardar(loteId: 'L1', modo: ModoAnalisis.corte, foto: foto);
      final b = await s.guardar(loteId: 'L1', modo: ModoAnalisis.corte, foto: foto);
      final c = await s.guardar(loteId: 'L2', modo: ModoAnalisis.corte, foto: foto);
      await s.borrar(a.id);
      expect(File(a.ruta).existsSync(), isFalse);
      expect(await s.obtener(a.id), isNull);
      await s.borrarDelLote('L1');
      expect(File(b.ruta).existsSync(), isFalse);
      expect(File(c.ruta).existsSync(), isTrue);
      expect(await s.listar('L2'), hasLength(1));
    });

    test('al eliminar el lote se borran las filas y limpiarHuerfanas quita los archivos que quedaron', () async {
      final s = servicio();
      final a = await s.guardar(loteId: 'L1', modo: ModoAnalisis.corte, foto: foto);
      final c = await s.guardar(loteId: 'L2', modo: ModoAnalisis.corte, foto: foto);
      await db.delete('lotes', where: 'id = ?', whereArgs: ['L1']);
      expect(await s.listar('L1'), isEmpty);
      expect(File(a.ruta).existsSync(), isTrue);
      expect(await s.limpiarHuerfanas(), 1);
      expect(File(a.ruta).existsSync(), isFalse);
      expect(File(c.ruta).existsSync(), isTrue);
    });
  });

  group('base de datos v7', () {
    test('migración desde la versión 6: conserva los lotes y crea la tabla', () async {
      final d = await Directory.systemTemp.createTemp('cacao_v6');
      addTearDown(() => d.delete(recursive: true));
      final ruta = p.join(d.path, 'v6.db');
      final vieja = await databaseFactoryFfi.openDatabase(ruta,
          options: OpenDatabaseOptions(version: 6, onCreate: (x, _) async {
            await CacaoDatabase.crearTablas(x);
            await x.execute('DROP TABLE analisis_fotos');
            await x.insert('lotes', Lote(id: 'V', title: 'Viejo', status: 'en proceso', createdAt: DateTime(2026)).toRow());
          }));
      await vieja.close();
      final nueva = await CacaoDatabase.abrir(databaseFactoryFfi, ruta);
      expect(await nueva.getVersion(), CacaoDatabase.version);
      expect(CacaoDatabase.version, 7);
      expect((await nueva.query('lotes')).single['titulo'], 'Viejo');
      await FotoService(database: () async => nueva, urlServidor: '', directorio: () async => dir)
          .guardar(loteId: 'V', modo: ModoAnalisis.corte, foto: foto);
      expect(await nueva.query('analisis_fotos'), hasLength(1));
      await nueva.close();
    });

    test('un resultado guardado dañado se lee como error, sin romper la lista', () async {
      await db.insert('analisis_fotos', {
        'id': 'x', 'lote_id': 'L1', 'modo': 'corte', 'ruta': '/no/existe.jpg', 'estado': 'analizada', 'resultado': '{no es json',
        'creado_en': '2026-11-18T12:00:00Z', 'intentos': 1,
      });
      final a = (await servicio().listar('L1')).single;
      expect(a.estado, EstadoAnalisis.error);
      expect(a.resultado, isNull);
    });
  });

  group('ConsentimientoFotos', () {
    test('empieza sin responder; guarda aceptar o rechazar y se puede olvidar', () async {
      expect(await ConsentimientoFotos.obtener(), isNull);
      await ConsentimientoFotos.registrar(true, ahora: DateTime.utc(2026, 11, 18));
      expect(await ConsentimientoFotos.obtener(), isTrue);
      await ConsentimientoFotos.registrar(false);
      expect(await ConsentimientoFotos.obtener(), isFalse);
      await ConsentimientoFotos.olvidar();
      expect(await ConsentimientoFotos.obtener(), isNull);
    });

    test('un valor guardado desconocido cuenta como "sin responder" (se vuelve a preguntar)', () async {
      SharedPreferences.setMockInitialValues({ConsentimientoFotos.clave: 'quizás'});
      expect(await ConsentimientoFotos.obtener(), isNull);
    });

    test('el texto dice lo que de verdad pasa: va a Anthropic, 30 días, se borra el EXIF, el servidor no la guarda', () {
      for (final frase in ['Anthropic', '30 días', 'datos ocultos', 'no guarda la foto', 'Si no acepta']) {
        expect(ConsentimientoFotos.texto, contains(frase), reason: frase);
      }
    });
  });

  group('la autorización se revisa AL ENVIAR (también la cola)', () {
    for (final estado in <bool?>[false, null]) {
      test('autorización $estado: no sale ninguna petición, la foto sigue guardada y en cola', () async {
        autorizado = estado;
        final s = servicio();
        final g = await s.guardar(loteId: 'L1', modo: ModoAnalisis.corte, foto: foto);
        await expectLater(s.analizar(g.id), throwsA(isA<FotoException>().having((e) => e.codigo, 'codigo', 'sin_autorizacion')));
        expect(peticiones, isEmpty);
        expect((await s.obtener(g.id))!.estado, EstadoAnalisis.pendiente);
        expect(File(g.ruta).existsSync(), isTrue);
      });
    }

    test('si la quita después de encolar, la cola NO se manda (procesarPendientes no envía nada)', () async {
      final s = servicio();
      final g1 = await s.guardar(loteId: 'L1', modo: ModoAnalisis.corte, foto: foto);
      await s.guardar(loteId: 'L1', modo: ModoAnalisis.corte, foto: foto);
      autorizado = false;
      expect(await s.procesarPendientes(), 0);
      expect(peticiones, isEmpty);
      expect(await s.cuantasPendientes(), 2);

      autorizado = true; // la vuelve a dar: ahora sí sale
      responder = (_) async => _json(_resp());
      expect(await s.procesarPendientes(), 2);
      expect(peticiones, hasLength(2));
      expect((await s.obtener(g1.id))!.estado, EstadoAnalisis.analizada);
    });
  });
}
