import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:alarmacacao5_0/data/cacao_database.dart';
import 'package:alarmacacao5_0/models/volteada.dart';
import 'package:alarmacacao5_0/services/lote_service.dart';

void main() {
  sqfliteFfiInit();

  late Directory dir;
  late String ruta;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('cacao_mig_');
    ruta = p.join(dir.path, 'cacao_light.db');
  });

  tearDown(() => dir.deleteSync(recursive: true));

  /// Crea una base con el esquema EXACTO de la versión 2 (sin pH, Brix ni
  /// temperatura ambiente) y le inserta datos, como la tendría un usuario
  /// que ya usa la app.
  Future<void> crearBaseV2() async {
    final db = await databaseFactoryFfi.openDatabase(
      ruta,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE lotes (
              id TEXT PRIMARY KEY, titulo TEXT NOT NULL, estado TEXT NOT NULL,
              creado_en TEXT NOT NULL, inicio_ciclo TEXT, fin_ciclo TEXT, plantilla TEXT,
              calidad_resultado TEXT, observacion_resultado TEXT
            )''');
          await db.execute('''
            CREATE TABLE registros (
              id TEXT PRIMARY KEY,
              lote_id TEXT NOT NULL REFERENCES lotes(id) ON DELETE CASCADE,
              mensaje TEXT NOT NULL DEFAULT '', fecha_programada TEXT NOT NULL,
              fecha TEXT NOT NULL, temperatura REAL, humedad REAL,
              observacion TEXT NOT NULL DEFAULT '', latitud REAL, longitud REAL,
              etapa TEXT NOT NULL DEFAULT 'fermentacion',
              confirmada INTEGER NOT NULL DEFAULT 0, notif_id INTEGER NOT NULL DEFAULT 0
            )''');
        },
      ),
    );
    await db.insert('lotes', {
      'id': 'L1', 'titulo': 'Lote viejo', 'estado': 'en proceso',
      'creado_en': '2026-01-01T08:00:00.000', 'calidad_resultado': 'buena',
      'observacion_resultado': 'Corte 70 % bien fermentado',
    });
    for (var i = 1; i <= 3; i++) {
      await db.insert('registros', {
        'id': 'R$i', 'lote_id': 'L1', 'mensaje': 'Volteada $i',
        'fecha_programada': '2026-01-0${i + 1}T08:00:00.000',
        'fecha': '2026-01-0${i + 1}T08:05:00.000',
        'temperatura': 40.0 + i, 'humedad': 80.0 + i, 'observacion': 'obs $i',
        'latitud': 7.6, 'longitud': -72.6, 'etapa': 'secado',
        'confirmada': 1, 'notif_id': i,
      });
    }
    await db.close();
  }

  test('de v2 a la versión actual conserva todos los datos y agrega columnas vacías', () async {
    await crearBaseV2();

    final db = await CacaoDatabase.abrir(databaseFactoryFfi, ruta);
    addTearDown(db.close);

    expect(await db.getVersion(), CacaoDatabase.version);
    final lotes = await db.query('lotes');
    expect(lotes, hasLength(1));
    expect(lotes.single['titulo'], 'Lote viejo');
    expect(lotes.single['calidad_resultado'], 'buena');

    final regs = await db.query('registros', orderBy: 'id');
    expect(regs, hasLength(3));
    for (var i = 1; i <= 3; i++) {
      final r = regs[i - 1];
      expect(r['temperatura'], 40.0 + i);
      expect(r['humedad'], 80.0 + i);
      expect(r['observacion'], 'obs $i');
      expect(r['latitud'], 7.6);
      expect(r['etapa'], 'secado');
      expect(r['notif_id'], i);
      expect(r['ph'], isNull);
      expect(r['brix'], isNull);
      expect(r['temp_ambiente'], isNull);
    }
  });

  test('los registros migrados se leen con el modelo y las medidas nuevas son null', () async {
    await crearBaseV2();
    final db = await CacaoDatabase.abrir(databaseFactoryFfi, ruta);
    addTearDown(db.close);

    final lote = await LoteService(database: () async => db).obtenerLotePorId('L1');
    final v = lote!.volteadas.first;
    expect(v.temperatura, 41.0);
    expect(v.ph, isNull);
    expect(v.brix, isNull);
    expect(v.tempAmbiente, isNull);
  });

  test('guardar y leer pH, Brix y temperatura ambiente (ida y vuelta)', () async {
    await crearBaseV2();
    final db = await CacaoDatabase.abrir(databaseFactoryFfi, ruta);
    addTearDown(db.close);
    final servicio = LoteService(database: () async => db);

    final nuevo = Volteada(
      id: 'R9', loteId: 'L1', mensaje: 'm', temperatura: 47.5, humedad: 85,
      observacion: 'o', fecha: DateTime(2026, 1, 9), fechaProgramada: DateTime(2026, 1, 9),
      confirmada: true, ph: 4.6, brix: 12.5, tempAmbiente: 26.0,
    );
    await servicio.guardarRegistro(nuevo);

    final leido = (await servicio.obtenerRegistrosDelLote('L1')).firstWhere((v) => v.id == 'R9');
    expect(leido.ph, 4.6);
    expect(leido.brix, 12.5);
    expect(leido.tempAmbiente, 26.0);
  });

  test('toJson/fromJson conserva las medidas nuevas y tolera JSON antiguo', () {
    final v = Volteada(
      id: 'a', loteId: 'b', mensaje: '', temperatura: 1, humedad: 2, observacion: '',
      fecha: DateTime(2026), fechaProgramada: DateTime(2026), confirmada: true,
      ph: 4.2, brix: 10, tempAmbiente: 25,
    );
    final ida = Volteada.fromJson(v.toJson());
    expect([ida.ph, ida.brix, ida.tempAmbiente], [4.2, 10.0, 25.0]);

    final viejo = Volteada.fromJson({'id': 'x', 'loteId': 'y'});
    expect([viejo.ph, viejo.brix, viejo.tempAmbiente], [null, null, null]);
  });

  test('una base nueva (sin migrar) ya trae las columnas', () async {
    final db = await CacaoDatabase.abrir(databaseFactoryFfi, inMemoryDatabasePath);
    addTearDown(db.close);
    final columnas = (await db.rawQuery('PRAGMA table_info(registros)')).map((c) => c['name']);
    expect(columnas, containsAll(['ph', 'brix', 'temp_ambiente']));
  });
}
