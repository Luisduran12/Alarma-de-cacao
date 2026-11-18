import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:alarmacacao5_0/data/cacao_database.dart';
import 'package:alarmacacao5_0/models/lote.dart';
import 'package:alarmacacao5_0/models/recordatorio.dart';
import 'package:alarmacacao5_0/models/volteada.dart';
import 'package:alarmacacao5_0/services/lote_service.dart';
import 'package:alarmacacao5_0/services/plan_recordatorios.dart';
import 'package:alarmacacao5_0/services/recordatorio_service.dart';

final _inicio = DateTime(2026, 1, 1, 8);

Volteada _alarma(int horas, {int notifId = 1}) => Volteada(
      id: 'a$horas', loteId: 'L1', mensaje: 'Volteada', temperatura: 0, humedad: 0, observacion: '',
      fecha: _inicio, fechaProgramada: _inicio.add(Duration(hours: horas)), confirmada: false, notifId: notifId,
    );

Lote _lote({required int duracion, required List<int> volteos, bool conFin = true}) => Lote(
      id: 'L1', title: 'Lote', status: 'en proceso', createdAt: _inicio, inicioCiclo: _inicio,
      finCiclo: conFin ? _inicio.add(Duration(hours: duracion)) : null,
      volteadas: [for (var i = 0; i < volteos.length; i++) _alarma(volteos[i], notifId: i + 1)],
    );

List<int> _horas(List<DateTime> f) => f.map((d) => d.difference(_inicio).inHours).toList();

void main() {
  sqfliteFfiInit();

  group('PlanRecordatorios', () {
    final antes = _inicio.subtract(const Duration(hours: 1));

    test('fermentación 144 h con volteos a 48-72-96-120 y fin a 144: 7 avisos, sin chocar con alarmas', () {
      final lote = _lote(duracion: 144, volteos: [48, 72, 96, 120, 144]);
      expect(_horas(PlanRecordatorios.paraLote(lote, ahora: antes)), [12, 24, 36, 60, 84, 108, 132]);
    });

    test('predeterminada 24-34-48: omite 24 y 48 (alarmas) y deja 12 y 36', () {
      final lote = _lote(duracion: 48, volteos: [24, 34, 48]);
      expect(_horas(PlanRecordatorios.paraLote(lote, ahora: antes)), [12, 36]);
    });

    test('una alarma a menos de 1 h de un aviso lo omite (34 h vs 36 h no; 35,5 h sí)', () {
      final lote = Lote(
        id: 'L1', title: 'x', status: 'en proceso', createdAt: _inicio, inicioCiclo: _inicio,
        finCiclo: _inicio.add(const Duration(hours: 48)),
        volteadas: [
          Volteada(
            id: 'a', loteId: 'L1', mensaje: '', temperatura: 0, humedad: 0, observacion: '',
            fecha: _inicio, fechaProgramada: _inicio.add(const Duration(minutes: 35 * 60 + 30)),
            confirmada: false, notifId: 5,
          ),
        ],
      );
      expect(_horas(PlanRecordatorios.paraLote(lote, ahora: antes)), [12, 24, 48]);
    });

    test('solo cuenta las alarmas programadas (los registros manuales, notifId 0, no bloquean)', () {
      final lote = Lote(
        id: 'L1', title: 'x', status: 'en proceso', createdAt: _inicio, inicioCiclo: _inicio,
        finCiclo: _inicio.add(const Duration(hours: 24)), volteadas: [_alarma(12, notifId: 0)],
      );
      expect(_horas(PlanRecordatorios.paraLote(lote, ahora: antes)), [12, 24]);
    });

    test('no incluye fechas que ya pasaron', () {
      final lote = _lote(duracion: 144, volteos: [48, 72, 96, 120, 144]);
      final ahora = _inicio.add(const Duration(hours: 50));
      expect(_horas(PlanRecordatorios.paraLote(lote, ahora: ahora)), [60, 84, 108, 132]);
    });

    test('sin fin de ciclo o sin inicio no hay recordatorios', () {
      expect(PlanRecordatorios.paraLote(_lote(duracion: 48, volteos: [], conFin: false), ahora: antes), isEmpty);
      final sinInicio = Lote(id: 'x', title: 'x', status: 'en proceso', createdAt: _inicio);
      expect(PlanRecordatorios.paraLote(sinInicio, ahora: antes), isEmpty);
    });

    test('con cadaHoras <= 0 no hay recordatorios (no se cuelga en un bucle)', () {
      expect(PlanRecordatorios.paraLote(_lote(duracion: 48, volteos: []), ahora: antes, cadaHoras: 0), isEmpty);
    });

    test('ciclo más corto que 12 h: ninguno', () {
      expect(PlanRecordatorios.paraLote(_lote(duracion: 10, volteos: [10]), ahora: antes), isEmpty);
    });
  });

  group('RecordatorioService y migración', () {
    late Database db;
    late List<int> canceladas;
    late RecordatorioService servicio;
    late LoteService lotes;

    Recordatorio rec(int n, int horas, {String loteId = 'L1'}) => Recordatorio(
          id: 'r$n', loteId: loteId, notifId: 100 + n, fechaProgramada: _inicio.add(Duration(hours: horas)),
        );

    setUp(() async {
      db = await CacaoDatabase.abrir(databaseFactoryFfi, inMemoryDatabasePath);
      canceladas = [];
      Future<void> cancelar(int id) async => canceladas.add(id);
      servicio = RecordatorioService(database: () async => db, cancelarNotificacion: cancelar);
      lotes = LoteService(database: () async => db, cancelarNotificacion: cancelar);
      await lotes.addLote(_lote(duracion: 144, volteos: [48]));
    });

    tearDown(() => db.close());

    test('guarda y lee, en orden de fecha', () async {
      await servicio.guardar(rec(2, 24));
      await servicio.guardar(rec(1, 12));
      final l = await servicio.delLote('L1');
      expect(l.map((r) => r.id), ['r1', 'r2']);
      expect(l.first.tipo, Recordatorio.medirTemperatura);
    });

    test('eliminarFuturosDelLote cancela y borra solo los que no han pasado', () async {
      await servicio.guardar(rec(1, 12));
      await servicio.guardar(rec(2, 36));
      await servicio.guardar(rec(3, 60));
      final ahora = _inicio.add(const Duration(hours: 24));
      final n = await servicio.eliminarFuturosDelLote('L1', ahora: ahora);
      expect(n, 2);
      expect(canceladas, [102, 103]);
      expect((await servicio.delLote('L1')).map((r) => r.id), ['r1'], reason: 'el ya pasado queda como historial');
    });

    test('si cancelar una notificación falla, igual se borra el recordatorio', () async {
      final fallando = RecordatorioService(
          database: () async => db, cancelarNotificacion: (_) async => throw StateError('sin plugin'));
      await fallando.guardar(rec(1, 36));
      await fallando.eliminarFuturosDelLote('L1', ahora: _inicio);
      expect(await fallando.delLote('L1'), isEmpty);
    });

    test('borrar el lote cancela sus alarmas pendientes Y sus recordatorios y limpia la tabla', () async {
      await servicio.guardar(rec(1, 36));
      await servicio.guardar(rec(2, 60));
      await lotes.deleteLote('L1');
      expect(canceladas, containsAll([1, 101, 102]), reason: '1 = alarma de volteo; 101 y 102 = recordatorios');
      expect(await servicio.todos(), isEmpty);
    });

    test('los recordatorios no son registros: no aparecen ni bloquean "completado"', () async {
      await servicio.guardar(rec(1, 36));
      expect((await lotes.obtenerRegistrosDelLote('L1')), hasLength(1));
    });
  });

  group('migración a v4', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('cacao_v4_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('una base v3 con datos pasa a v4 sin perder nada y con la tabla vacía', () async {
      final ruta = p.join(dir.path, 'cacao.db');
      // Crea una base v3 REAL: las tablas de la versión actual sin `recordatorios`.
      final v3 = await databaseFactoryFfi.openDatabase(
        ruta,
        options: OpenDatabaseOptions(
          version: 3,
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
          },
        ),
      );
      await v3.insert('lotes', {'id': 'L9', 'titulo': 'Lote v3', 'estado': 'en proceso', 'creado_en': '2026-01-01T08:00:00.000'});
      await v3.insert('registros', {
        'id': 'R9', 'lote_id': 'L9', 'fecha_programada': '2026-01-02T08:00:00.000', 'fecha': '2026-01-02T08:05:00.000',
        'temperatura': 46.5, 'humedad': 80.0, 'observacion': 'ok', 'confirmada': 1, 'ph': 4.5,
      });
      await v3.close();

      final db = await CacaoDatabase.abrir(databaseFactoryFfi, ruta);
      addTearDown(db.close);
      expect(await db.getVersion(), 4);
      expect((await db.query('lotes')).single['titulo'], 'Lote v3');
      final reg = (await db.query('registros')).single;
      expect([reg['temperatura'], reg['ph'], reg['observacion']], [46.5, 4.5, 'ok']);
      expect(await db.query('recordatorios'), isEmpty);

      // y la tabla nueva funciona, con su clave foránea
      final servicio = RecordatorioService(database: () async => db, cancelarNotificacion: (_) async {});
      await servicio.guardar(Recordatorio(id: 'x', loteId: 'L9', notifId: 5, fechaProgramada: DateTime(2026, 2, 1)));
      expect(await servicio.delLote('L9'), hasLength(1));
      expect(
        () => servicio.guardar(Recordatorio(id: 'y', loteId: 'NO_EXISTE', notifId: 6, fechaProgramada: DateTime(2026, 2, 1))),
        throwsA(isA<DatabaseException>()),
        reason: 'no se puede crear un recordatorio de un lote que no existe',
      );
    });
  });
}
