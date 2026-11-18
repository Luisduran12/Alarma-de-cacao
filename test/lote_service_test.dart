import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:alarmacacao5_0/data/cacao_database.dart';
import 'package:alarmacacao5_0/data/migracion_prefs.dart';
import 'package:alarmacacao5_0/models/lote.dart';
import 'package:alarmacacao5_0/models/volteada.dart';
import 'package:alarmacacao5_0/services/lote_service.dart';

Volteada _volteada(String id, String loteId,
        {bool confirmada = false, String mensaje = 'm', int notifId = 0, double temp = 0}) =>
    Volteada(
      id: id,
      loteId: loteId,
      mensaje: mensaje,
      temperatura: temp,
      humedad: 0,
      observacion: '',
      fecha: DateTime(2026, 1, 1),
      fechaProgramada: DateTime(2026, 1, 2),
      confirmada: confirmada,
      notifId: notifId,
    );

Lote _lote(String id, {List<Volteada> volteadas = const []}) => Lote(
      id: id,
      title: 'Lote $id',
      status: 'en proceso',
      createdAt: DateTime(2026, 1, 1),
      volteadas: volteadas,
    );

void main() {
  sqfliteFfiInit();

  late Database db;
  late LoteService servicio;
  late List<int> canceladas;

  setUp(() async {
    db = await CacaoDatabase.abrir(databaseFactoryFfi, inMemoryDatabasePath);
    canceladas = [];
    servicio = LoteService(
      database: () async => db,
      cancelarNotificacion: (id) async => canceladas.add(id),
    );
  });

  tearDown(() async => db.close());

  group('LoteService (SQLite)', () {
    test('crear un lote NO borra los lotes anteriores', () async {
      await servicio.addLote(_lote('A'));
      await servicio.addLote(_lote('B'));
      await servicio.upsertLote(_lote('C'));

      final ids = (await servicio.loadLotes()).map((l) => l.id).toSet();
      expect(ids, {'A', 'B', 'C'});
    });

    test('saveLotes con un solo lote no elimina los demás (bug anterior)', () async {
      await servicio.addLote(_lote('A'));
      await servicio.addLote(_lote('B'));

      await servicio.saveLotes([_lote('B').copyWith(title: 'B editado')]);

      final lotes = await servicio.loadLotes();
      expect(lotes.length, 2);
      expect(lotes.firstWhere((l) => l.id == 'B').title, 'B editado');
    });

    test('guarda y recupera las volteadas del lote', () async {
      await servicio.addLote(_lote('A', volteadas: [_volteada('v1', 'A'), _volteada('v2', 'A')]));
      final lote = await servicio.obtenerLotePorId('A');
      expect(lote!.volteadas.map((v) => v.id), ['v1', 'v2']);
    });

    test('confirmar una volteada la actualiza sin duplicarla', () async {
      await servicio.addLote(_lote('A', volteadas: [_volteada('v1', 'A')]));
      final lote = (await servicio.obtenerLotePorId('A'))!;
      final confirmada = lote.volteadas.first.copyWith(confirmada: true, temperatura: 45);

      await servicio.updateLote(lote.copyWith(volteadas: [confirmada]));

      final registros = await servicio.obtenerRegistrosDelLote('A');
      expect(registros.length, 1);
      expect(registros.first.confirmada, isTrue);
      expect(registros.first.temperatura, 45);
    });

    test('obtenerConfirmadasDelLote solo devuelve las confirmadas', () async {
      await servicio.addLote(_lote('A', volteadas: [
        _volteada('v1', 'A', confirmada: true),
        _volteada('v2', 'A'),
      ]));
      final confirmadas = await servicio.obtenerConfirmadasDelLote('A');
      expect(confirmadas.map((v) => v.id), ['v1']);
    });

    test('eliminar un lote borra sus registros y cancela solo las alarmas pendientes', () async {
      await servicio.addLote(_lote('A', volteadas: [
        _volteada('v1', 'A', notifId: 7),
        _volteada('v2', 'A', notifId: 8, confirmada: true),
      ]));
      await servicio.addLote(_lote('B'));

      await servicio.deleteLote('A');

      expect(await servicio.obtenerLotePorId('A'), isNull);
      expect(await servicio.obtenerRegistrosDelLote('A'), isEmpty);
      expect(await servicio.obtenerLotePorId('B'), isNotNull);
      expect(canceladas, [7]);
    });
  });

  group('Migración desde SharedPreferences', () {
    test('combina las tres claves sin perder lotes ni duplicar volteadas', () {
      final loteGuardado = _lote('A', volteadas: [_volteada('prog1', 'A', mensaje: 'Volteada 1')]);
      final loteViejo = _lote('Z');

      final lotes = MigracionPrefs.combinar(
        lotesGuardados: jsonEncode([loteGuardado.toJson()]),
        lotesData: jsonEncode([loteViejo.toJson()]),
        volteadas: [
          // Confirmación real de la volteada programada
          jsonEncode(_volteada('conf1', 'A', mensaje: 'Volteada 1', confirmada: true, temp: 44).toJson()),
          // Volteada de un lote que ya no existe
          jsonEncode(_volteada('huerfana', 'X', confirmada: true).toJson()),
          'esto no es json',
        ],
      );

      final porId = {for (final l in lotes) l.id: l};
      expect(porId.keys.toSet(), {'A', 'Z', 'X'});

      final a = porId['A']!;
      expect(a.volteadas.length, 1, reason: 'la confirmación completa la programada');
      expect(a.volteadas.first.id, 'prog1');
      expect(a.volteadas.first.confirmada, isTrue);
      expect(a.volteadas.first.temperatura, 44);

      expect(porId['X']!.volteadas.single.id, 'huerfana');
      expect(porId['X']!.status, 'migrado');
    });

    test('migrarSiHaceFalta inserta en la base una sola vez', () async {
      SharedPreferences.setMockInitialValues({
        'lotes_guardados': jsonEncode([_lote('A', volteadas: [_volteada('v1', 'A')]).toJson()]),
      });

      await MigracionPrefs.migrarSiHaceFalta(db);
      await MigracionPrefs.migrarSiHaceFalta(db); // segunda vez: no hace nada

      final lotes = await servicio.loadLotes();
      expect(lotes.single.id, 'A');
      expect(lotes.single.volteadas.single.id, 'v1');
    });
  });
}
