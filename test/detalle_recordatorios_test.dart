import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:alarmacacao5_0/data/cacao_database.dart';
import 'package:alarmacacao5_0/models/lote.dart';
import 'package:alarmacacao5_0/models/volteada.dart';
import 'package:alarmacacao5_0/screens/detalle_lote_screen.dart';
import 'package:alarmacacao5_0/services/alarm_scheduler.dart';
import 'package:alarmacacao5_0/services/lote_service.dart';
import 'package:alarmacacao5_0/services/recordatorio_service.dart';

/// Con el reloj falso de las pruebas, cada `await` de SQLite necesita su propia
/// vuelta de espera real seguida de un `pump`.
Future<void> _esperar(WidgetTester t) async {
  for (var i = 0; i < 10; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  sqfliteFfiInit();

  late Database db;
  late LoteService lotes;
  late RecordatorioService recordatorios;
  late AlarmScheduler scheduler;
  late List<int> programadas;
  late List<int> canceladas;
  var contador = 0;

  Lote loteEnCurso({int horasTranscurridas = 10, int duracion = 144}) {
    final inicio = DateTime.now().subtract(Duration(hours: horasTranscurridas));
    return Lote(
      id: 'L1', title: 'Lote Durania', status: 'en proceso', createdAt: inicio, inicioCiclo: inicio,
      finCiclo: inicio.add(Duration(hours: duracion)),
      volteadas: [
        for (var i = 0; i < 5; i++)
          Volteada(
            id: 'V$i', loteId: 'L1', mensaje: 'Volteada ${i + 1} (${48 + i * 24} h)', temperatura: 0, humedad: 0,
            observacion: '', fecha: inicio, fechaProgramada: inicio.add(Duration(hours: 48 + i * 24)),
            confirmada: false, notifId: 900 + i,
          ),
      ],
    );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await CacaoDatabase.abrir(databaseFactoryFfi, inMemoryDatabasePath);
    programadas = [];
    canceladas = [];
    contador = 0;
    Future<void> cancelar(int id) async => canceladas.add(id);
    lotes = LoteService(database: () async => db, cancelarNotificacion: cancelar);
    recordatorios = RecordatorioService(database: () async => db, cancelarNotificacion: cancelar);
    scheduler = AlarmScheduler(
      loteService: lotes,
      recordatorioService: recordatorios,
      siguienteId: () async => ++contador,
      programar: ({required id, required titulo, required cuerpo, required fechaProgramada, payload, esRecordatorio = false}) async {
        programadas.add(id);
      },
    );
  });

  tearDown(() => db.close());

  Future<void> abrir(WidgetTester t, Lote lote) async {
    t.view.physicalSize = const Size(800, 3600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(home: DetalleLoteScreen(lote: lote, loteService: lotes, scheduler: scheduler)));
    await _esperar(t);
  }

  SwitchListTile interruptor(WidgetTester t) => t.widget<SwitchListTile>(find.byType(SwitchListTile));

  testWidgets('lote en curso sin recordatorios: el interruptor aparece apagado y listo para usarse', (t) async {
    final lote = loteEnCurso();
    await t.runAsync(() => lotes.addLote(lote));
    await abrir(t, lote);

    expect(find.text('Recordar medir la temperatura cada 12 h'), findsOneWidget);
    expect(interruptor(t).value, isFalse);
    expect(interruptor(t).onChanged, isNotNull, reason: 'una vez cargado el estado ya se puede usar');
  });

  testWidgets('encenderlo programa los recordatorios, lo avisa y el interruptor queda activo', (t) async {
    final lote = loteEnCurso();
    await t.runAsync(() => lotes.addLote(lote));
    await abrir(t, lote);

    await t.tap(find.byType(Switch));
    await _esperar(t);

    expect(programadas, hasLength(7), reason: '12, 24, 36, 60, 84, 108 y 132 h');
    expect(interruptor(t).value, isTrue);
    expect(find.textContaining('avisaremos 7 veces'), findsOneWidget);
    expect((await t.runAsync(() => recordatorios.delLote('L1')))!, hasLength(7));
  });

  testWidgets('apagarlo cancela los recordatorios y deja las alarmas de volteo', (t) async {
    final lote = loteEnCurso();
    await t.runAsync(() => lotes.addLote(lote));
    await abrir(t, lote);
    await t.tap(find.byType(Switch));
    await _esperar(t);
    expect(interruptor(t).value, isTrue);

    await t.tap(find.byType(Switch));
    await _esperar(t);
    // El aviso anterior se retira con una animación antes de que aparezca el nuevo.
    await t.pump(const Duration(seconds: 1));

    expect(interruptor(t).value, isFalse);
    expect(canceladas, hasLength(7));
    expect(canceladas.toSet(), programadas.toSet(), reason: 'se cancelaron exactamente los que se habían programado');
    expect(find.textContaining('Recordatorios apagados'), findsOneWidget);
    expect((await t.runAsync(() => recordatorios.delLote('L1')))!, isEmpty);
    expect(canceladas.any((id) => id >= 900), isFalse, reason: 'las alarmas de volteo (900+) no se tocan');
  });

  testWidgets('lote que ya terminó y sin recordatorios: no ofrece el interruptor', (t) async {
    final terminado = loteEnCurso(horasTranscurridas: 200);
    await t.runAsync(() => lotes.addLote(terminado));
    await abrir(t, terminado);
    expect(find.byType(SwitchListTile), findsNothing);
  });

  testWidgets('ya con recordatorios programados el interruptor aparece encendido', (t) async {
    final lote = loteEnCurso();
    await t.runAsync(() async {
      await lotes.addLote(lote);
      await scheduler.programarRecordatorios(lote);
    });
    await abrir(t, lote);
    expect(interruptor(t).value, isTrue);
  });

  testWidgets('el botón de la guía abre la guía de la prueba de corte', (t) async {
    final lote = loteEnCurso();
    await t.runAsync(() => lotes.addLote(lote));
    await abrir(t, lote);

    await t.tap(find.text('Guía de la prueba de corte'));
    await t.pumpAndSettle();
    expect(find.text('Cómo hacer la prueba de corte'), findsOneWidget);
  });
}
