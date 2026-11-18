import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:alarmacacao5_0/data/cacao_database.dart';
import 'package:alarmacacao5_0/models/volteada.dart';
import 'package:alarmacacao5_0/services/alarm_scheduler.dart';
import 'package:alarmacacao5_0/services/lote_service.dart';
import 'package:alarmacacao5_0/services/notification_service.dart';
import 'package:alarmacacao5_0/services/plantillas.dart';
import 'package:alarmacacao5_0/services/recordatorio_service.dart';

class _Llamada {
  final int id;
  final String titulo, cuerpo;
  final DateTime fecha;
  final String? payload;
  final bool esRecordatorio;
  _Llamada(this.id, this.titulo, this.cuerpo, this.fecha, this.payload, this.esRecordatorio);
}

void main() {
  sqfliteFfiInit();

  late Database db;
  late List<_Llamada> programadas;
  late List<int> canceladas;
  late AlarmScheduler scheduler;
  late RecordatorioService recordatorios;
  late LoteService lotes;
  var contador = 0;
  var fallar = false;

  setUp(() async {
    db = await CacaoDatabase.abrir(databaseFactoryFfi, inMemoryDatabasePath);
    programadas = [];
    canceladas = [];
    contador = 0;
    fallar = false;
    Future<void> cancelar(int id) async => canceladas.add(id);
    lotes = LoteService(database: () async => db, cancelarNotificacion: cancelar);
    recordatorios = RecordatorioService(database: () async => db, cancelarNotificacion: cancelar);
    scheduler = AlarmScheduler(
      loteService: lotes,
      recordatorioService: recordatorios,
      siguienteId: () async => ++contador,
      programar: ({required id, required titulo, required cuerpo, required fechaProgramada, payload, esRecordatorio = false}) async {
        if (fallar && esRecordatorio) throw StateError('el sistema rechazó la alarma');
        programadas.add(_Llamada(id, titulo, cuerpo, fechaProgramada, payload, esRecordatorio));
      },
    );
  });

  tearDown(() => db.close());

  List<_Llamada> soloAlarmas() => programadas.where((c) => !c.esRecordatorio).toList();
  List<_Llamada> soloRecordatorios() => programadas.where((c) => c.esRecordatorio).toList();

  group('crear un lote con la plantilla de fermentación 144 h', () {
    test('programa 5 alarmas (4 volteos + fin) y 7 recordatorios cada 12 h', () async {
      final lote = await scheduler.crearLote(titulo: 'Lote A', plantilla: Plantillas.fedecacao144);
      expect(soloAlarmas(), hasLength(5));
      expect(soloRecordatorios(), hasLength(7));
      final horas = soloRecordatorios().map((c) => c.fecha.difference(lote.inicioCiclo!).inHours).toList();
      expect(horas, [12, 24, 36, 60, 84, 108, 132]);
    });

    test('los recordatorios abren un registro nuevo y usan su propio canal', () async {
      final lote = await scheduler.crearLote(titulo: 'Lote A', plantilla: Plantillas.fedecacao144);
      for (final c in soloRecordatorios()) {
        expect(c.payload, NotificationService.payloadMedir(lote.id));
        expect(c.titulo, 'Medir temperatura - Lote A');
      }
      for (final c in soloAlarmas()) {
        expect(c.esRecordatorio, isFalse);
      }
    });

    test('el aviso final es "Fin de la fermentación" y abre la guía de la prueba de corte', () async {
      final lote = await scheduler.crearLote(titulo: 'Lote A', plantilla: Plantillas.fedecacao144);
      final fin = soloAlarmas().last;
      expect(fin.titulo, 'Fin de la fermentación - Lote A');
      expect(fin.cuerpo, contains('prueba de corte'));
      expect(fin.cuerpo, contains('144 h'));
      final registroFinal = lote.volteadas.last;
      expect(fin.payload, NotificationService.payloadCorte(lote.id, registroFinal.id));
      expect(registroFinal.mensaje, startsWith('Fin de la fermentación (144 h)'));
      expect(NotificationService.argumentosDesdePayload(fin.payload)!['ruta'], NotificationService.rutaGuiaCorte);
    });

    test('los volteos intermedios siguen abriendo el formulario como antes', () async {
      final lote = await scheduler.crearLote(titulo: 'Lote A', plantilla: Plantillas.fedecacao144);
      final primero = soloAlarmas().first;
      expect(primero.titulo, 'Volteada 1 - Lote A');
      expect(primero.payload, NotificationService.payloadVolteada(lote.id, lote.volteadas.first.id));
      expect(NotificationService.argumentosDesdePayload(primero.payload)!.containsKey('ruta'), isFalse);
    });

    test('guarda los recordatorios en la base con el mismo id de notificación que se programó', () async {
      final lote = await scheduler.crearLote(titulo: 'Lote A', plantilla: Plantillas.fedecacao144);
      final guardados = await recordatorios.delLote(lote.id);
      expect(guardados, hasLength(7));
      expect(guardados.map((r) => r.notifId), soloRecordatorios().map((c) => c.id));
    });

    test('los recordatorios no cuentan como registros ni cambian cuántas volteadas tiene el lote', () async {
      final lote = await scheduler.crearLote(titulo: 'Lote A', plantilla: Plantillas.fedecacao144);
      expect(await lotes.obtenerRegistrosDelLote(lote.id), hasLength(5));
    });
  });

  group('otras plantillas', () {
    test('predeterminada 24-34-48: 3 alarmas y solo 2 recordatorios (12 h y 36 h)', () async {
      final lote = await scheduler.crearLote(titulo: 'B', plantilla: Plantillas.predeterminada);
      expect(soloAlarmas(), hasLength(3));
      expect(soloRecordatorios().map((c) => c.fecha.difference(lote.inicioCiclo!).inHours), [12, 36]);
    });

    test('un ciclo personalizado con alarma final conserva el texto de "Fin del ciclo"', () async {
      // Plantilla personalizada con volteos a 12 y 30 h → fin a 30 h: no es plantilla de fermentación.
      final lote = await scheduler.crearLote(titulo: 'C', plantilla: Plantillas.personalizada([12, 30]));
      expect(soloAlarmas().map((c) => c.titulo), ['Volteada 1 - C', 'Volteada 2 - C']);
      expect(lote.volteadas, hasLength(2));
      expect(soloAlarmas().any((c) => c.titulo.contains('Fin de la fermentación')), isFalse);
    });
  });

  group('reprogramar, apagar y consultar', () {
    test('programarRecordatorios dos veces no duplica y cancela los anteriores', () async {
      final lote = await scheduler.crearLote(titulo: 'A', plantilla: Plantillas.fedecacao144);
      final primeros = (await recordatorios.delLote(lote.id)).map((r) => r.notifId).toSet();

      final n = await scheduler.programarRecordatorios(lote);
      expect(n, 7);
      expect(await recordatorios.delLote(lote.id), hasLength(7));
      expect(canceladas.toSet().containsAll(primeros), isTrue);
      final ahora = (await recordatorios.delLote(lote.id)).map((r) => r.notifId).toSet();
      expect(ahora.intersection(primeros), isEmpty, reason: 'ids nuevos, ninguno repetido');
    });

    test('con "ahora" avanzado solo reprograma los que faltan', () async {
      final lote = await scheduler.crearLote(titulo: 'A', plantilla: Plantillas.fedecacao144);
      final n = await scheduler.programarRecordatorios(lote, ahora: lote.inicioCiclo!.add(const Duration(hours: 70)));
      expect(n, 3, reason: 'quedan 84, 108 y 132 h; los de 12, 24, 36 y 60 h ya pasaron');
    });

    test('desactivar quita los futuros y recordatoriosActivos pasa a false', () async {
      final lote = await scheduler.crearLote(titulo: 'A', plantilla: Plantillas.fedecacao144);
      expect(await scheduler.recordatoriosActivos(lote.id), isTrue);
      final quitados = await scheduler.desactivarRecordatorios(lote.id);
      expect(quitados, 7);
      expect(await scheduler.recordatoriosActivos(lote.id), isFalse);
      expect(canceladas.length, 7);
    });

    test('un lote que ya terminó no tiene recordatorios activos', () async {
      final lote = await scheduler.crearLote(titulo: 'A', plantilla: Plantillas.fedecacao144);
      final despues = lote.finCiclo!.add(const Duration(days: 1));
      expect(await scheduler.recordatoriosActivos(lote.id, ahora: despues), isFalse);
    });
  });

  group('cuando el sistema falla', () {
    test('si no se pudo programar un recordatorio, no se guarda y el lote igual se crea', () async {
      fallar = true;
      final lote = await scheduler.crearLote(titulo: 'A', plantilla: Plantillas.fedecacao144);
      expect(soloAlarmas(), hasLength(5), reason: 'las alarmas de volteo sí quedaron');
      expect(await recordatorios.delLote(lote.id), isEmpty, reason: 'no hay nada que cancelar ni reprogramar');
      expect(await lotes.obtenerLotePorId(lote.id), isNotNull);
    });

    test('borrar el lote cancela alarmas y recordatorios', () async {
      final lote = await scheduler.crearLote(titulo: 'A', plantilla: Plantillas.fedecacao144);
      await lotes.deleteLote(lote.id);
      final idsProgramados = programadas.map((c) => c.id).toSet();
      expect(canceladas.toSet(), idsProgramados, reason: 'se cancelaron las 12 notificaciones programadas');
      expect(await recordatorios.todos(), isEmpty);
    });
  });

  group('payloads', () {
    test('medir temperatura: m|lote abre un registro nuevo', () {
      expect(NotificationService.argumentosDesdePayload('m|L1'),
          {'loteId': 'L1', 'volteadaId': '', 'mensaje': '', 'ruta': '/confirmar'});
    });

    test('guía de corte: c|lote|volteada', () {
      expect(NotificationService.argumentosDesdePayload('c|L1|V2'),
          {'loteId': 'L1', 'volteadaId': 'V2', 'mensaje': '', 'ruta': '/guia-corte'});
    });

    test('formatos incompletos o raros se rechazan', () {
      expect(NotificationService.argumentosDesdePayload('m|'), isNull);
      expect(NotificationService.argumentosDesdePayload('m'), isNull);
      expect(NotificationService.argumentosDesdePayload('c||V'), isNull);
      expect(NotificationService.argumentosDesdePayload('x|a|b'), isNull);
    });

    test('un payload de volteada no cambia (compatibilidad)', () {
      expect(NotificationService.argumentosDesdePayload(NotificationService.payloadVolteada('L', 'V')),
          {'loteId': 'L', 'volteadaId': 'V', 'mensaje': ''});
    });
  });

  test('los registros de alarma guardan su id de notificación (distinto de 0)', () async {
    final lote = await scheduler.crearLote(titulo: 'A', plantilla: Plantillas.fedecacao144);
    expect(lote.volteadas.every((Volteada v) => v.notifId != 0), isTrue);
  });
}
