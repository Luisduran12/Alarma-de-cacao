import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:alarmacacao5_0/data/cacao_database.dart';
import 'package:alarmacacao5_0/services/borrar_datos.dart';
import 'package:alarmacacao5_0/services/copia_seguridad.dart';
import 'package:alarmacacao5_0/services/curva_ideal.dart';

void main() {
  sqfliteFfiInit();
  late Database db;
  late CopiaSeguridad copia;
  var alarmasCanceladas = 0, reprogramadas = 0;

  Future<void> lote(String id, {String estado = 'en proceso'}) => db.insert('lotes', {
        'id': id,
        'titulo': 'Lote $id',
        'estado': estado,
        'creado_en': '2026-11-01T08:00:00.000',
        'plantilla': 'fermentacion_144h',
      });

  Future<void> registro(String id, String loteId, {double temp = 45.5, int notif = 0, String? obs}) => db.insert('registros', {
        'id': id,
        'lote_id': loteId,
        'fecha_programada': '2026-11-02T08:00:00.000',
        'fecha': '2026-11-02T08:05:00.000',
        'temperatura': temp,
        'humedad': 80.0,
        'observacion': obs ?? 'Olor a vinagre ñandú "comillas", coma',
        'latitud': 7.6,
        'longitud': -72.6,
        'confirmada': 1,
        'notif_id': notif,
        'ph': 4.5,
      });

  Future<Database> otraBd() => CacaoDatabase.abrir(databaseFactoryFfi, inMemoryDatabasePath);

  CopiaSeguridad conBd(Database d) => CopiaSeguridad(
        baseDeDatos: () async => d,
        cancelarAlarmas: () async => alarmasCanceladas++,
        reprogramar: () async => reprogramadas++,
        ahora: () => DateTime(2026, 11, 18, 9),
      );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    alarmasCanceladas = 0;
    reprogramadas = 0;
    db = await otraBd();
    copia = conBd(db);
  });
  tearDown(() => db.close());

  group('exportar e importar', () {
    test('ida y vuelta sin perder nada: lo importado es idéntico, incluidas observaciones con comillas y tildes', () async {
      await lote('A');
      await lote('B', estado: 'completado');
      await registro('r1', 'A', notif: 7);
      await registro('r2', 'A', temp: 47.25, notif: 8);
      await registro('r3', 'B');
      await db.insert('recordatorios',
          {'id': 'rec1', 'lote_id': 'A', 'notif_id': 9, 'fecha_programada': '2026-11-03T08:00:00.000', 'tipo': 'medir_temperatura'});
      await db.insert('chat_mensajes',
          {'lote_id': 'A', 'rol': 'usuario', 'texto': '¿Cuándo volteo?', 'origen': 'ia', 'fuentes': '[]', 'creado_en': '2026-11-02T09:00:00'});
      await db.insert('lugares', {'clave': '7.600,-72.600', 'nombre': 'Chinácota', 'origen': 'servidor', 'fuente': '', 'resuelto_en': '2026-11-02'});

      final archivo = await copia.exportar();

      final nueva = await otraBd();
      addTearDown(nueva.close);
      final resumen = await conBd(nueva).importar(archivo);

      expect(resumen.lotes, 2);
      expect(resumen.registros, 3);
      expect(resumen.mensajesChat, 1);
      for (final t in CopiaSeguridad.tablas) {
        final a = await db.query(t, orderBy: t == 'chat_mensajes' ? 'id' : (t == 'lugares' ? 'clave' : 'id'));
        final b = await nueva.query(t, orderBy: t == 'chat_mensajes' ? 'id' : (t == 'lugares' ? 'clave' : 'id'));
        expect(b, a, reason: 'tabla $t');
      }
      expect(reprogramadas, 1, reason: 'se reprograman las alarmas de los registros futuros');
    });

    test('importar REEMPLAZA lo que había y cancela las alarmas de antes', () async {
      await lote('A');
      final archivo = await copia.exportar();
      await lote('VIEJO');
      await registro('rv', 'VIEJO');

      await copia.importar(archivo);

      expect((await db.query('lotes')).map((f) => f['id']), ['A']);
      expect(await db.query('registros'), isEmpty);
      expect(alarmasCanceladas, 1);
    });

    test('la curva ideal y las reglas viajan en el respaldo', () async {
      SharedPreferences.setMockInitialValues({
        CurvaIdealStorage.clave: jsonEncode({'puntos': []}),
        'pref_tamano_letra': 'grande',
        'consentimiento_fotos_v1': 'aceptado|2026-11-01',
        'instalacion_id_v1': 'no-debe-viajar',
      });
      final archivo = await copia.exportar();
      final j = jsonDecode(archivo) as Map;
      expect((j['preferencias'] as Map).keys, [CurvaIdealStorage.clave]);
      expect(archivo, isNot(contains('consentimiento')));
      expect(archivo, isNot(contains('no-debe-viajar')));

      SharedPreferences.setMockInitialValues({'curva_ideal_v1': 'basura'});
      await copia.importar(archivo);
      expect((await SharedPreferences.getInstance()).getString(CurvaIdealStorage.clave), jsonEncode({'puntos': []}));
    });

    test('el contador de IDs de alarma no queda por debajo de los IDs importados', () async {
      await lote('A');
      await registro('r1', 'A', notif: 41);
      final archivo = await copia.exportar();
      SharedPreferences.setMockInitialValues({'ultimo_notification_id': 3});
      await copia.importar(archivo);
      expect((await SharedPreferences.getInstance()).getInt('ultimo_notification_id'), 41);
    });

    test('un respaldo de una versión de base de datos más vieja se importa (columnas que faltan quedan vacías)', () async {
      final j = jsonDecode(await copia.exportar()) as Map;
      j['version_bd'] = 2;
      j['tablas'] = {
        'lotes': [
          {'id': 'A', 'titulo': 'Viejo', 'estado': 'completado', 'creado_en': '2026-01-01T00:00:00'}
        ],
        'registros': [
          {
            'id': 'r',
            'lote_id': 'A',
            'fecha_programada': '2026-01-02T00:00:00',
            'fecha': '2026-01-02T00:00:00',
            'temperatura': 44,
            'humedad': 70,
            'confirmada': 1,
          }
        ],
      };
      await copia.importar(jsonEncode(j));
      final r = (await db.query('registros')).single;
      expect(r['temperatura'], 44);
      expect(r['ph'], isNull);
    });
  });

  group('validación: un archivo malo NO cambia nada', () {
    late String bueno;
    setUp(() async {
      await lote('A');
      await registro('r1', 'A');
      bueno = await copia.exportar();
    });

    Future<void> rechaza(String contenido, {String? contiene}) async {
      final antes = await db.query('registros');
      await expectLater(
        copia.importar(contenido),
        throwsA(isA<RespaldoInvalido>().having((e) => e.mensaje, 'mensaje', contiene == null ? isNotEmpty : contains(contiene))),
      );
      expect(await db.query('registros'), antes, reason: 'los datos siguen intactos');
      expect(alarmasCanceladas, 0, reason: 'ni siquiera se tocaron las alarmas');
    }

    Map mod(void Function(Map j) f) {
      final j = jsonDecode(bueno) as Map;
      f(j);
      return j;
    }

    test('texto que no es JSON', () => rechaza('esto no es un respaldo', contiene: 'no es un respaldo'));
    test('JSON de otra cosa', () => rechaza('{"hola": 1}', contiene: 'no es un respaldo'));
    test('una lista en vez de un objeto', () => rechaza('[1,2,3]'));
    test('archivo vacío', () => rechaza(''));
    test('versión de la base más nueva que la de la app', () => rechaza(jsonEncode(mod((j) => j['version_bd'] = CacaoDatabase.version + 1)), contiene: 'más nueva'));
    test('versión del formato más nueva', () => rechaza(jsonEncode(mod((j) => j['version_formato'] = 99)), contiene: 'más nueva'));
    test('sin fecha de creación', () => rechaza(jsonEncode(mod((j) => j.remove('creado_en'))), contiene: 'incompleto'));
    test('una tabla que no es lista', () => rechaza(jsonEncode(mod((j) => (j['tablas'] as Map)['registros'] = 'x')), contiene: 'registros'));
    test('una columna desconocida (no se inventan columnas)', () {
      return rechaza(jsonEncode(mod((j) => ((j['tablas'] as Map)['registros'] as List).first['columna_falsa'] = 1)), contiene: 'columna_falsa');
    });
    test('un tipo equivocado (temperatura como texto)', () {
      return rechaza(jsonEncode(mod((j) => ((j['tablas'] as Map)['registros'] as List).first['temperatura'] = 'caliente')), contiene: 'temperatura');
    });
    test('un registro sin su lote', () {
      return rechaza(jsonEncode(mod((j) => ((j['tablas'] as Map)['registros'] as List).first['lote_id'] = 'NO_EXISTE')), contiene: 'sin su lote');
    });
    test('lotes repetidos', () {
      return rechaza(jsonEncode(mod((j) {
        final l = (j['tablas'] as Map)['lotes'] as List;
        l.add(Map.of(l.first as Map));
      })), contiene: 'repetidos');
    });
    test('las preferencias deben ser JSON válido', () {
      return rechaza(jsonEncode(mod((j) => j['preferencias'] = {CurvaIdealStorage.clave: '{roto'})), contiene: 'preferencias');
    });
    test('demasiado grande', () => rechaza('x' * (CopiaSeguridad.maxBytes + 1), contiene: 'demasiado grande'));

    test('un fallo a mitad de la importación (falta un dato obligatorio) deja la base como estaba', () async {
      // El lote nuevo no trae "titulo" (NOT NULL): la validación de tipos lo deja pasar, SQLite lo rechaza dentro de la transacción.
      final j = mod((j) {
        ((j['tablas'] as Map)['lotes'] as List).add({'id': 'Z', 'estado': 'x', 'creado_en': 'y'});
      });
      final antes = await db.query('lotes');
      await expectLater(copia.importar(jsonEncode(j)), throwsA(isA<DatabaseException>()));
      expect(await db.query('lotes'), antes);
      expect(await db.query('registros'), isNotEmpty);
      expect(reprogramadas, 1, reason: 'las alarmas que se cancelaron se devuelven');
    });

    test('validar() resume sin tocar nada', () async {
      final r = await copia.validar(bueno);
      expect(r.lotes, 1);
      expect(r.registros, 1);
      expect(r.creadoEn.year, 2026);
      expect(alarmasCanceladas, 0);
    });
  });

  test('el nombre del archivo lleva la fecha', () {
    expect(copia.nombreArchivo(), 'cacao_light_respaldo_2026-11-18.json');
  });

  group('borrar todos los datos', () {
    late Directory tmp;
    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('borrar_');
    });
    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test('quita lotes y todo lo que cuelga de ellos, fotos, CSV y preferencias; cancela alarmas', () async {
      await lote('A');
      await registro('r1', 'A');
      await db.insert('chat_mensajes',
          {'lote_id': 'A', 'rol': 'usuario', 'texto': 'hola', 'origen': 'ia', 'fuentes': '[]', 'creado_en': '2026-11-02T09:00:00'});
      await db.insert('recordatorios',
          {'id': 'rec1', 'lote_id': 'A', 'notif_id': 9, 'fecha_programada': '2026-11-03T08:00:00.000', 'tipo': 'medir_temperatura'});
      await db.insert('analisis_fotos', {'id': 'f1', 'lote_id': 'A', 'modo': 'corte', 'ruta': 'x', 'estado': 'pendiente', 'creado_en': '2026-11-02'});
      await db.insert('lugares', {'clave': 'k', 'nombre': 'n', 'origen': 'o', 'fuente': '', 'resuelto_en': 'r'});
      final fotos = Directory(p.join(tmp.path, 'fotos'))..createSync();
      File(p.join(fotos.path, 'a.jpg')).writeAsStringSync('foto');
      Directory(p.join(fotos.path, 'sub')).createSync();
      final csv = File(p.join(tmp.path, 'lotes_exportados.csv'))..writeAsStringSync('datos');
      SharedPreferences.setMockInitialValues({
        'consentimiento_fotos_v1': 'aceptado|x',
        'consentimiento_ubicacion_v1': 'aceptado|x',
        'instalacion_id_v1': 'id',
        CurvaIdealStorage.clave: '{}',
      });

      var alarmas = 0;
      final r = await BorrarDatos(
        baseDeDatos: () async => db,
        cancelarAlarmas: () async => alarmas++,
        carpetas: () async => [fotos],
        archivos: () async => [csv],
      ).todo();

      expect(r.completo, isTrue, reason: '${r.fallos}');
      expect(alarmas, 1);
      for (final t in [...CopiaSeguridad.tablas, 'analisis_fotos']) {
        expect(await db.query(t), isEmpty, reason: t);
      }
      expect(fotos.listSync(), isEmpty);
      expect(csv.existsSync(), isFalse);
      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
    });

    test('si un paso falla, sigue con los demás y dice cuál falló', () async {
      await lote('A');
      final r = await BorrarDatos(
        baseDeDatos: () async => db,
        cancelarAlarmas: () async => throw StateError('sin permiso'),
        carpetas: () async => [],
        archivos: () async => [],
      ).todo();
      expect(r.completo, isFalse);
      expect(r.fallos, ['alarmas']);
      expect(await db.query('lotes'), isEmpty, reason: 'lo demás sí se borró');
    });

    test('con todo vacío no falla', () async {
      final r = await BorrarDatos(
        baseDeDatos: () async => db,
        cancelarAlarmas: () async {},
        carpetas: () async => [Directory(p.join(tmp.path, 'no_existe'))],
        archivos: () async => [File(p.join(tmp.path, 'no_existe.csv'))],
      ).todo();
      expect(r.completo, isTrue);
    });
  });
}
