import 'package:flutter/material.dart';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:alarmacacao5_0/data/cacao_database.dart';
import 'package:alarmacacao5_0/models/lote.dart';
import 'package:alarmacacao5_0/models/volteada.dart';
import 'package:alarmacacao5_0/screens/detalle_lote_screen.dart';
import 'package:alarmacacao5_0/services/alarm_scheduler.dart';
import 'package:alarmacacao5_0/services/lote_service.dart';
import 'package:alarmacacao5_0/services/lugar_service.dart';
import 'package:alarmacacao5_0/services/lugares_offline.dart';
import 'package:alarmacacao5_0/services/recordatorio_service.dart';
import 'package:alarmacacao5_0/widgets/lugar_texto.dart';

const _lista = '''
{"fuente":"DANE","licencia":"CC BY-SA 4.0","corte":"2024-12-30","departamentos":["Norte de Santander"],
"lugares":[["Chinácota","Chinácota",0,7.603112,-72.601162,"M"],["Hatoviejo","Durania",0,7.77449,-72.69209,"C"]]}
''';

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

  LugarService lugar({String lista = _lista, http.Client? cliente}) => LugarService(
        database: () async => db,
        cliente: cliente ?? MockClient((_) async => http.Response('', 500)),
        urlServidor: 'https://x.example',
        lista: () async => LugaresOffline.desdeJson(lista),
      );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await CacaoDatabase.abrir(databaseFactoryFfi, inMemoryDatabasePath);
    lotes = LoteService(database: () async => db, cancelarNotificacion: (_) async {});
  });

  tearDown(() => db.close());

  Future<void> montar(WidgetTester t, Widget w) async {
    t.view.physicalSize = const Size(800, 3000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: w))));
    await _esperar(t);
  }

  group('LugarTexto', () {
    testWidgets('sin internet: la referencia más cercana, avisando que es aproximada y NO la vereda', (t) async {
      await montar(t, LugarTexto(latitud: 7.6031, longitud: -72.6012, servicio: lugar()));
      expect(find.text('Cerca de Chinácota (Norte de Santander), a menos de 1 km'), findsOneWidget);
      expect(find.textContaining('Referencia aproximada'), findsOneWidget);
      expect(find.textContaining('no la vereda'), findsOneWidget);
      expect(find.textContaining('DANE'), findsOneWidget);
    });

    testWidgets('con el nombre del servidor guardado: muestra ese y su crédito, sin el aviso de aproximado', (t) async {
      // Un servidor real manda JSON en UTF-8.
      final s = lugar(cliente: MockClient((_) async => http.Response.bytes(
          utf8.encode('{"nombre":"Chinácota, Norte de Santander","fuente":"© colaboradores de OpenStreetMap"}'), 200)));
      await t.runAsync(() => s.resolver(7.6031, -72.6012));
      await montar(t, LugarTexto(latitud: 7.6031, longitud: -72.6012, servicio: s));
      expect(find.text('Chinácota, Norte de Santander'), findsOneWidget);
      expect(find.text('© colaboradores de OpenStreetMap'), findsOneWidget);
      expect(find.textContaining('Referencia aproximada'), findsNothing);
    });

    testWidgets('si no hay ninguna referencia no muestra nada', (t) async {
      await montar(t, LugarTexto(latitud: 7.6, longitud: -72.6, servicio: lugar(lista: '{"departamentos":[],"lugares":[]}')));
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('si falla la base de datos no rompe la pantalla', (t) async {
      final roto = LugarService(
        database: () async => throw StateError('base cerrada'),
        urlServidor: '',
        lista: () async => LugaresOffline.desdeJson(_lista),
      );
      await montar(t, LugarTexto(latitud: 7.6, longitud: -72.6, servicio: roto));
      expect(find.byType(Text), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('si cambian las coordenadas, vuelve a buscar el nombre', (t) async {
      final s = lugar();
      final lat = ValueNotifier(7.6031);
      final lng = ValueNotifier(-72.6012);
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder(
            valueListenable: lat,
            builder: (_, la, __) => LugarTexto(latitud: la, longitud: lng.value, servicio: s),
          ),
        ),
      ));
      await _esperar(t);
      expect(find.textContaining('Chinácota'), findsOneWidget);

      lat.value = 7.7745;
      lng.value = -72.6921;
      await _esperar(t);
      expect(find.textContaining('Hatoviejo'), findsOneWidget);
    });
  });

  group('en el detalle del lote (punto de secado)', () {
    Lote loteConSecado({bool conUbicacion = true}) => Lote(
          id: 'L1', title: 'Lote Durania', status: 'en proceso', createdAt: DateTime(2026, 1, 1),
          volteadas: [
            Volteada(
              id: 'V1', loteId: 'L1', mensaje: '', temperatura: 33, humedad: 60, observacion: 'sol',
              fecha: DateTime(2026, 1, 10), fechaProgramada: DateTime(2026, 1, 10), confirmada: true,
              etapa: Etapa.secado, latitud: conUbicacion ? 7.574227 : null, longitud: conUbicacion ? -72.592433 : null,
            ),
          ],
        );

    Future<void> abrir(WidgetTester t, Lote lote) async {
      await t.runAsync(() => lotes.addLote(lote));
      t.view.physicalSize = const Size(800, 3600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        home: DetalleLoteScreen(
          lote: lote,
          loteService: lotes,
          lugarService: lugar(),
          scheduler: AlarmScheduler(
            loteService: lotes,
            recordatorioService: RecordatorioService(database: () async => db, cancelarNotificacion: (_) async {}),
            programar: ({required id, required titulo, required cuerpo, required fechaProgramada, payload, esRecordatorio = false}) async {},
          ),
        ),
      ));
      await _esperar(t);
    }

    testWidgets('muestra las coordenadas y debajo el lugar más cercano', (t) async {
      await abrir(t, loteConSecado());
      expect(find.textContaining('Lat 7.574227'), findsOneWidget);
      expect(find.textContaining('Cerca de Chinácota (Norte de Santander), a 3'), findsOneWidget);
    });

    testWidgets('sin ubicación en el registro no hay lugar que mostrar', (t) async {
      await abrir(t, loteConSecado(conUbicacion: false));
      expect(find.textContaining('Cerca de'), findsNothing);
      expect(find.text('Aún no hay registros de secado con ubicación.'), findsOneWidget);
    });
  });
}
