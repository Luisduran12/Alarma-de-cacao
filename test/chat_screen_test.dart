import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:alarmacacao5_0/data/cacao_database.dart';
import 'package:alarmacacao5_0/models/lote.dart';
import 'package:alarmacacao5_0/models/volteada.dart';
import 'package:alarmacacao5_0/screens/chat_screen.dart';
import 'package:alarmacacao5_0/screens/detalle_lote_screen.dart';
import 'package:alarmacacao5_0/services/alarm_scheduler.dart';
import 'package:alarmacacao5_0/services/chat_historial.dart';
import 'package:alarmacacao5_0/services/recordatorio_service.dart';
import 'package:alarmacacao5_0/services/chat_service.dart';
import 'package:alarmacacao5_0/services/lote_service.dart';
import 'package:alarmacacao5_0/services/respuestas_locales.dart';

const _id = '3f2b8c1e-9d4a-4b7e-8a1c-0e5d6f7a8b9c';

Future<void> _esperar(WidgetTester t, {int vueltas = 10}) async {
  for (var i = 0; i < vueltas; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  sqfliteFfiInit();

  late Database db;
  late LoteService lotes;
  late ChatHistorial historial;
  late List<http.Request> peticiones;
  late Future<http.Response> Function(http.Request) responder;
  late Lote lote;

  ChatService conServidor() => ChatService(
        cliente: MockClient((r) {
          peticiones.add(r);
          return responder(r);
        }),
        urlServidor: 'https://api.cacaolight.example/v1',
        idInstalacion: () async => _id,
        timeout: const Duration(seconds: 5),
      );

  ChatService sinServidor() => ChatService(
      cliente: MockClient((r) async => fail('no debe salir ninguna petición')), urlServidor: '', idInstalacion: () async => _id);

  http.Response ok(Object j, [int estado = 200]) =>
      http.Response.bytes(utf8.encode(jsonEncode(j)), estado, headers: {'content-type': 'application/json; charset=utf-8'});

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await CacaoDatabase.abrir(databaseFactoryFfi, inMemoryDatabasePath);
    lotes = LoteService(database: () async => db, cancelarNotificacion: (_) async {});
    historial = ChatHistorial(database: () async => db);
    peticiones = [];
    responder = (_) async => ok({'respuesta': 'Voltee cada 24 horas [F1].', 'fuentes': [{'id': 'F1', 'fuente': 'x'}], 'truncada': false, 'aviso': 'a'});
    final inicio = DateTime.now().subtract(const Duration(hours: 60));
    lote = Lote(
      id: 'L1', title: 'Lote de Don Pedro', status: 'en proceso', createdAt: inicio, inicioCiclo: inicio,
      finCiclo: inicio.add(const Duration(hours: 144)),
      volteadas: [
        Volteada(id: 'M1', loteId: 'L1', mensaje: '', temperatura: 47, humedad: 80, observacion: 'nota privada',
            fecha: inicio.add(const Duration(hours: 55)), fechaProgramada: inicio.add(const Duration(hours: 55)), confirmada: true),
        Volteada(id: 'V1', loteId: 'L1', mensaje: 'Volteada', temperatura: 0, humedad: 0, observacion: '',
            fecha: inicio, fechaProgramada: DateTime.now().add(const Duration(hours: 12)), confirmada: false, notifId: 5),
      ],
    );
  });

  tearDown(() => db.close());

  Future<void> abrir(WidgetTester t, ChatService chat) async {
    await t.runAsync(() => lotes.addLote(lote));
    t.view.physicalSize = const Size(800, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(home: ChatScreen(lote: lote, loteService: lotes, historial: historial, chat: chat)));
    await _esperar(t);
  }

  /// Los botones rápidos se pliegan al preguntar: si no se ven, se abre el panel.
  Future<void> tocar(WidgetTester t, String texto) async {
    if (find.text(texto).evaluate().isEmpty) {
      await t.tap(find.text('Preguntas rápidas'));
      await t.pump();
    }
    await t.tap(find.text(texto));
    await _esperar(t);
  }

  testWidgets('al abrir: aviso fijo, explicación y los 5 botones', (t) async {
    await abrir(t, sinServidor());
    expect(find.text('Es una guía, no reemplaza al técnico.'), findsOneWidget);
    expect(find.text('Pregunte sobre su lote de cacao'), findsOneWidget);
    expect(find.textContaining('sin el nombre del lote ni su ubicación'), findsOneWidget);
    for (final r in PreguntaRapida.todas) {
      expect(find.text(r.etiqueta), findsOneWidget);
    }
    expect(find.byTooltip('Borrar la conversación'), findsNothing);
  });

  testWidgets('sin servidor: responde con la guía del teléfono, con fuente y aviso de que la IA necesita conexión', (t) async {
    await abrir(t, sinServidor());
    await tocar(t, '¿Cuándo volteo?');

    expect(find.text('¿Cuándo volteo?'), findsOneWidget, reason: 'la pregunta en la conversación; el panel se pliega');
    expect(find.text('Guía del teléfono'), findsOneWidget);
    expect(find.textContaining('próxima alarma de volteo'), findsOneWidget);
    expect(find.textContaining('(Fuente: FHIA'), findsWidgets);
    expect(find.text(RespuestasLocales.avisoSinIA), findsOneWidget);
    expect(find.text('Es una guía, no reemplaza al técnico.'), findsOneWidget);

    final guardados = await t.runAsync(() => historial.listar('L1'));
    expect(guardados!.map((m) => m.rol.name), ['usuario', 'asistente']);
    expect(guardados.last.origen.name, 'local');
    expect(guardados.last.fuentes, isNotEmpty);
  });

  testWidgets('con servidor: respuesta de la IA sin marcas [F1], con la fuente real y sin aviso de modo local', (t) async {
    responder = (_) async => ok({
          'respuesta': 'Voltee cada 24 horas [F1].',
          'fuentes': [{'id': 'F1', 'fuente': 'lo que sea'}],
          'truncada': false,
          'aviso': 'x',
        });
    await abrir(t, conServidor());
    await tocar(t, '¿Cuándo volteo?');

    expect(find.text('Voltee cada 24 horas.'), findsOneWidget);
    expect(find.textContaining('[F1]'), findsNothing);
    expect(find.text('IA'), findsOneWidget);
    expect(find.text('Fuentes:'), findsOneWidget);
    expect(find.textContaining('• FHIA, InfoCacao'), findsOneWidget);
    expect(find.text(RespuestasLocales.avisoSinIA), findsNothing);

    // Lo que viajó: la pregunta, contexto sin nombre ni ubicación y fragmentos con su fuente.
    expect(peticiones, hasLength(1));
    final crudo = peticiones.single.body;
    final cuerpo = jsonDecode(crudo) as Map<String, dynamic>;
    expect(cuerpo['mensaje'], '¿Cuándo volteo?');
    expect(cuerpo['contexto']['etapa'], 'fermentacion');
    expect((cuerpo['contexto']['registros'] as List).single['temperatura'], 47);
    expect(cuerpo['fragmentos'], isNotEmpty);
    expect(cuerpo.containsKey('historial'), isFalse, reason: 'primera pregunta: no hay turnos previos');
    for (final prohibido in ['Pedro', 'nota privada', 'L1', _id]) {
      expect(crudo, isNot(contains(prohibido)), reason: prohibido);
    }
  });

  testWidgets('la segunda pregunta lleva el turno anterior como historial (sin repetir la actual)', (t) async {
    await abrir(t, conServidor());
    await tocar(t, '¿Cuándo volteo?');
    await tocar(t, '¿Cómo seco mi cacao?');

    final cuerpo = jsonDecode(peticiones.last.body) as Map<String, dynamic>;
    final h = (cuerpo['historial'] as List).cast<Map<String, dynamic>>();
    expect(h.map((x) => x['rol']), ['usuario', 'asistente']);
    expect(h.first['texto'], '¿Cuándo volteo?');
    expect(h.any((x) => x['texto'] == '¿Cómo seco mi cacao?'), isFalse);
  });

  testWidgets('la IA falla con un error del servidor: se muestra su aviso y además la guía del teléfono', (t) async {
    responder = (_) async => ok({'error': {'codigo': 'limite_dia', 'mensaje': 'Hoy ya hizo muchas preguntas. Vuelva mañana.'}}, 429);
    await abrir(t, conServidor());
    await tocar(t, '¿Cómo seco mi cacao?');

    expect(find.text('Aviso'), findsOneWidget);
    expect(find.text('Hoy ya hizo muchas preguntas. Vuelva mañana.'), findsOneWidget);
    expect(find.text('Guía del teléfono'), findsOneWidget);
    expect(find.textContaining('(Fuente: '), findsWidgets);
    expect(find.text(RespuestasLocales.avisoSinIA), findsOneWidget);
  });

  testWidgets('sin conexión (socket): cae a la guía del teléfono', (t) async {
    responder = (_) async => throw const SocketException('sin red');
    await abrir(t, conServidor());
    await tocar(t, '¿Cómo hago la prueba de corte?');

    expect(find.text('No hay conexión a internet.'), findsOneWidget);
    expect(find.textContaining('NTC 1252'), findsOneWidget);
    expect(find.text(RespuestasLocales.avisoSinIA), findsOneWidget);
  });

  testWidgets('pregunta escrita: se envía con el botón, se limpia el campo y lo desconocido se dice', (t) async {
    await abrir(t, sinServidor());
    await t.enterText(find.byType(TextField), '¿cuánto cuesta un kilo de cacao?');
    await t.tap(find.byTooltip('Enviar pregunta'));
    await _esperar(t);

    expect(find.textContaining('No encontré eso en la guía'), findsOneWidget);
    expect(find.textContaining('FEDECACAO'), findsOneWidget);
    expect(t.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
  });

  testWidgets('pregunta vacía no envía nada', (t) async {
    await abrir(t, sinServidor());
    await t.enterText(find.byType(TextField), '   ');
    await t.tap(find.byTooltip('Enviar pregunta'));
    await _esperar(t);
    expect(find.text('Pregunte sobre su lote de cacao'), findsOneWidget);
    expect(await t.runAsync(() => historial.listar('L1')), isEmpty);
  });

  testWidgets('mientras la IA piensa: muestra "Pensando…" y no deja enviar otra', (t) async {
    final espera = Completer<http.Response>();
    responder = (_) => espera.future;
    await abrir(t, conServidor());
    await t.tap(find.text('¿Cuándo volteo?'));
    await _esperar(t, vueltas: 4);

    expect(find.text('Pensando…'), findsOneWidget);
    expect(t.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.send)).onPressed, isNull);
    expect(t.widget<TextField>(find.byType(TextField)).enabled, isFalse);

    espera.complete(ok({'respuesta': 'Listo.', 'fuentes': [], 'truncada': false, 'aviso': 'x'}));
    await _esperar(t);
    expect(find.text('Pensando…'), findsNothing);
    expect(find.text('Listo.'), findsOneWidget);
    expect(peticiones, hasLength(1));
  });

  testWidgets('respuesta cortada por la IA se marca con puntos suspensivos', (t) async {
    responder = (_) async => ok({'respuesta': 'Primero seque al sol', 'fuentes': [], 'truncada': true, 'aviso': 'x'});
    await abrir(t, conServidor());
    await tocar(t, '¿Cómo seco mi cacao?');
    expect(find.text('Primero seque al sol…'), findsOneWidget);
  });

  testWidgets('el historial del lote se conserva al volver a abrir y se puede borrar', (t) async {
    await abrir(t, sinServidor());
    await tocar(t, '¿Cómo seco mi cacao?');
    expect(find.text('¿Cómo seco mi cacao?'), findsOneWidget);

    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(MaterialApp(home: ChatScreen(lote: lote, loteService: lotes, historial: historial, chat: sinServidor())));
    await _esperar(t);
    expect(find.text('¿Cómo seco mi cacao?'), findsOneWidget, reason: 'la conversación vuelve');
    expect(find.text('Preguntas rápidas'), findsOneWidget);
    expect(find.text('¿Cuándo volteo?'), findsNothing, reason: 'con conversación el panel arranca plegado');

    await t.tap(find.byTooltip('Borrar la conversación'));
    await t.pumpAndSettle();
    expect(find.text('¿Borrar la conversación?'), findsOneWidget);
    await t.tap(find.text('Borrar'));
    await _esperar(t);
    expect(find.text('Pregunte sobre su lote de cacao'), findsOneWidget);
    expect(await t.runAsync(() => historial.listar('L1')), isEmpty);
  });

  testWidgets('cancelar el borrado no borra', (t) async {
    await abrir(t, sinServidor());
    await tocar(t, '¿Cómo seco mi cacao?');
    await t.tap(find.byTooltip('Borrar la conversación'));
    await t.pumpAndSettle();
    await t.tap(find.text('Cancelar'));
    await t.pumpAndSettle();
    expect(find.text('Guía del teléfono'), findsOneWidget);
  });

  testWidgets('desde el detalle del lote: el botón "Preguntar sobre mi lote" abre el chat', (t) async {
    await t.runAsync(() => lotes.addLote(lote));
    t.view.physicalSize = const Size(800, 3600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final scheduler = AlarmScheduler(
      loteService: lotes,
      recordatorioService: RecordatorioService(database: () async => db, cancelarNotificacion: (_) async {}),
      siguienteId: () async => 1,
      programar: ({required id, required titulo, required cuerpo, required fechaProgramada, payload, esRecordatorio = false}) async {},
    );
    await t.pumpWidget(MaterialApp(
        home: DetalleLoteScreen(
            lote: lote, loteService: lotes, scheduler: scheduler, chatHistorial: historial, chatService: sinServidor())));
    await _esperar(t);

    final boton = find.text('Preguntar sobre mi lote');
    await t.ensureVisible(boton);
    await t.tap(boton);
    await _esperar(t);
    expect(find.text('Preguntar sobre el lote'), findsOneWidget);
    expect(find.text('Es una guía, no reemplaza al técnico.'), findsOneWidget);
  });
}
