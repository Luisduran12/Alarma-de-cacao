import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:alarmacacao5_0/data/cacao_database.dart';
import 'package:alarmacacao5_0/models/lote.dart';
import 'package:alarmacacao5_0/models/volteada.dart';
import 'package:alarmacacao5_0/services/alarm_scheduler.dart';
import 'package:alarmacacao5_0/services/lote_service.dart';
import 'package:alarmacacao5_0/services/plantillas.dart';
import 'package:alarmacacao5_0/services/recordatorio_service.dart';

class _Programada {
  final int id;
  final String? payload;
  final DateTime fecha;
  _Programada(this.id, this.payload, this.fecha);
}

/// Varios lotes en paralelo (el productor suele tener uno en el cajón y otro secando al mismo tiempo): cada lote
/// debe tener sus propias alarmas, registros y estado, y tocar uno no debe afectar a los demás.
void main() {
  sqfliteFfiInit();

  late Database db;
  late List<_Programada> programadas;
  late List<int> canceladas;
  late AlarmScheduler scheduler;
  late LoteService lotes;
  var contador = 0;

  setUp(() async {
    db = await CacaoDatabase.abrir(databaseFactoryFfi, inMemoryDatabasePath);
    programadas = [];
    canceladas = [];
    contador = 0;
    Future<void> cancelar(int id) async => canceladas.add(id);
    lotes = LoteService(database: () async => db, cancelarNotificacion: cancelar);
    scheduler = AlarmScheduler(
      loteService: lotes,
      recordatorioService: RecordatorioService(database: () async => db, cancelarNotificacion: cancelar),
      siguienteId: () async => ++contador,
      programar: ({required id, required titulo, required cuerpo, required fechaProgramada, payload, esRecordatorio = false}) async {
        programadas.add(_Programada(id, payload, fechaProgramada));
      },
    );
  });
  tearDown(() => db.close());

  Future<List<Lote>> tresLotes() async => [
        await scheduler.crearLote(titulo: 'Cajón 1', plantilla: Plantillas.fedecacao144),
        await scheduler.crearLote(titulo: 'Cajón 2', plantilla: Plantillas.fedecacao144),
        await scheduler.crearLote(titulo: 'Cajón 3', plantilla: Plantillas.fedecacao144),
      ];

  Future<void> medir(Lote l, {double temp = 46}) => lotes.guardarRegistro(Volteada(
        id: 'm-${l.id}-$temp',
        loteId: l.id,
        mensaje: 'medición',
        temperatura: temp,
        humedad: 80,
        observacion: 'de ${l.title}',
        fecha: DateTime.now(),
        fechaProgramada: DateTime.now(),
        confirmada: true,
        notifId: 0,
      ));

  test('tres lotes a la vez: todos quedan "en proceso" y cada uno con sus 5 alarmas', () async {
    final creados = await tresLotes();
    final cargados = await lotes.loadLotes();
    expect(cargados, hasLength(3));
    expect(cargados.every((l) => l.status == 'en proceso'), isTrue);
    for (final l in creados) {
      final propio = cargados.firstWhere((c) => c.id == l.id);
      expect(propio.volteadas.where((v) => !v.confirmada), hasLength(5), reason: l.title);
    }
  });

  test('ningún ID de alarma se repite entre lotes (si se repitiera, una alarma pisaría a otra)', () async {
    await tresLotes();
    final ids = programadas.map((p) => p.id).toList();
    expect(ids.length, 3 * (5 + 7), reason: '3 lotes × (5 alarmas + 7 recordatorios)');
    expect(ids.toSet().length, ids.length);
    final notifRegistros = (await db.query('registros', columns: ['notif_id'])).map((r) => r['notif_id']).toList();
    expect(notifRegistros.toSet().length, notifRegistros.length);
  });

  test('cada alarma apunta a SU lote: el payload lleva el ID de su lote y no el de otro', () async {
    final creados = await tresLotes();
    for (final l in creados) {
      final deEsteLote = l.volteadas.map((v) => v.notifId).toSet();
      final payloads = programadas.where((p) => deEsteLote.contains(p.id)).map((p) => p.payload!);
      expect(payloads, hasLength(5));
      for (final p in payloads) {
        expect(p.split('|')[1], l.id);
      }
    }
  });

  test('registrar una medición en un lote no aparece en los demás', () async {
    final l = await tresLotes();
    await medir(l[0], temp: 47);
    await medir(l[0], temp: 48);
    await medir(l[1], temp: 40);
    expect((await lotes.obtenerConfirmadasDelLote(l[0].id)).map((v) => v.temperatura), unorderedEquals([47, 48]));
    expect((await lotes.obtenerConfirmadasDelLote(l[1].id)).map((v) => v.temperatura), [40]);
    expect(await lotes.obtenerConfirmadasDelLote(l[2].id), isEmpty);
  });

  test('completar un lote no cambia el estado de los otros ni sus alarmas', () async {
    final l = await tresLotes();
    await lotes.actualizarEstado(l[1].id, 'completado');
    final estados = {for (final x in await lotes.loadLotes()) x.id: x.status};
    expect(estados, {l[0].id: 'en proceso', l[1].id: 'completado', l[2].id: 'en proceso'});
    expect(canceladas, isEmpty);
  });

  test('borrar un lote cancela SOLO sus alarmas y deja intactos los otros', () async {
    final l = await tresLotes();
    await medir(l[0]);
    await medir(l[2]);
    final deB = {
      ...l[1].volteadas.map((v) => v.notifId),
      ...(await db.query('recordatorios', columns: ['notif_id'], where: 'lote_id = ?', whereArgs: [l[1].id]))
          .map((r) => r['notif_id'] as int),
    };

    await lotes.deleteLote(l[1].id);

    expect(canceladas.toSet(), deB, reason: 'se cancelaron exactamente las alarmas y recordatorios del lote borrado');
    final quedan = (await lotes.loadLotes()).map((x) => x.id).toSet();
    expect(quedan, {l[0].id, l[2].id});
    expect(await db.query('registros', where: 'lote_id = ?', whereArgs: [l[1].id]), isEmpty);
    expect(await db.query('recordatorios', where: 'lote_id = ?', whereArgs: [l[1].id]), isEmpty);
    expect(await lotes.obtenerConfirmadasDelLote(l[0].id), hasLength(1));
    expect(await lotes.obtenerConfirmadasDelLote(l[2].id), hasLength(1));
    expect(await db.query('recordatorios', where: 'lote_id = ?', whereArgs: [l[0].id]), isNotEmpty);
  });

  test('si el sistema pierde las alarmas, la red de seguridad reprograma las de TODOS los lotes sin duplicar', () async {
    final l = await tresLotes();
    programadas.clear();
    final reprogramadas = await scheduler.reprogramarFaltantes({});
    expect(reprogramadas, 36, reason: '3 lotes × (5 alarmas de volteo/fin + 7 recordatorios)');
    expect(programadas.map((p) => p.id).toSet().length, 36);

    // Si el sistema conserva todo lo de un lote, a ese no se le toca nada.
    programadas.clear();
    final delPrimero = {
      ...l[0].volteadas.map((v) => v.notifId),
      ...(await db.query('recordatorios', columns: ['notif_id'], where: 'lote_id = ?', whereArgs: [l[0].id]))
          .map((r) => r['notif_id'] as int),
    };
    expect(delPrimero, hasLength(12));
    final n = await scheduler.reprogramarFaltantes(delPrimero);
    expect(n, 24);
    expect(programadas.map((p) => p.id).toSet().intersection(delPrimero), isEmpty);
  });

  test('las alarmas de dos lotes que caen a la misma hora no se pisan (cada una conserva su ID)', () async {
    final l = await tresLotes();
    // Los tres lotes se crearon en el mismo instante: sus alarmas coinciden casi a la misma hora.
    final primeras = [for (final x in l) x.volteadas.first];
    expect(primeras.map((v) => v.notifId).toSet(), hasLength(3));
    final horas = primeras.map((v) => v.fechaProgramada.difference(v.fecha).inHours).toSet();
    expect(horas, hasLength(1), reason: 'misma hora relativa, distinto ID');
  });
}
