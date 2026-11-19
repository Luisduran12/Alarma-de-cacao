import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:alarmacacao5_0/data/cacao_database.dart';
import 'package:alarmacacao5_0/data/guia_foto.dart';
import 'package:alarmacacao5_0/models/analisis_foto.dart';
import 'package:alarmacacao5_0/models/lote.dart';
import 'package:alarmacacao5_0/screens/detalle_lote_screen.dart';
import 'package:alarmacacao5_0/screens/fotos_lote_screen.dart';
import 'package:alarmacacao5_0/screens/resultado_foto_screen.dart';
import 'package:alarmacacao5_0/services/alarm_scheduler.dart';
import 'package:alarmacacao5_0/services/consentimiento_fotos.dart';
import 'package:alarmacacao5_0/services/foto_preparada.dart';
import 'package:alarmacacao5_0/services/foto_service.dart';
import 'package:alarmacacao5_0/services/lote_service.dart';
import 'package:alarmacacao5_0/services/recordatorio_service.dart';
import 'package:alarmacacao5_0/services/selector_foto.dart';

const _id = '3f2b8c1e-9d4a-4b7e-8a1c-0e5d6f7a8b9c';

Future<void> _esperar(WidgetTester t, {int vueltas = 12}) async {
  for (var i = 0; i < vueltas; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await t.pump(const Duration(milliseconds: 60));
  }
}

Map<String, Object?> _resp({String semaforo = 'verde', bool repetir = false, String modo = 'corte'}) => {
      'modo': modo, 'foto_valida': true, 'repetir_foto': repetir, 'motivo': 'ninguno',
      'mensaje': repetir ? 'La foto salió borrosa. Tome otra, con el teléfono quieto y bien enfocada.' : '',
      'categorias': repetir ? [] : [{'nombre': 'bien_fermentado', 'porcentaje': 70}, {'nombre': 'violeta', 'porcentaje': 30}],
      'confianza': repetir ? 'baja' : 'media',
      'posibles_causas': repetir ? [] : ['Fermentación completa'],
      'pasos_recomendados': repetir ? ['Limpie el lente y vuelva a intentar'] : ['Pase a secado'],
      'semaforo': semaforo,
      'aviso': 'Estimación orientativa. La clasificación oficial es la prueba de corte de la NTC 1252. Ante duda, consulte al técnico.',
    };

http.Response _json(Object j, [int estado = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(j)), estado, headers: {'content-type': 'application/json; charset=utf-8'});

class _Selector implements SelectorFoto {
  Uint8List? foto;
  Object? falla;
  final llamadas = <bool>[];
  @override
  Future<Uint8List?> tomar({required bool camara}) async {
    llamadas.add(camara);
    if (falla != null) throw falla!;
    return foto;
  }
}

Uint8List _jpeg([int w = 800, int h = 600]) {
  final im = img.Image(width: w, height: h);
  img.fill(im, color: img.ColorRgb8(100, 60, 30));
  return Uint8List.fromList(img.encodeJpg(im));
}

void main() {
  sqfliteFfiInit();
  late Database db;
  late Directory dir;
  late LoteService lotes;
  late FotoService servicio;
  late _Selector selector;
  late List<http.Request> peticiones;
  late Future<http.Response> Function(http.Request) responder;
  late Lote lote;
  var contador = 0;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await CacaoDatabase.abrir(databaseFactoryFfi, inMemoryDatabasePath);
    dir = await Directory.systemTemp.createTemp('fotos_ui');
    lotes = LoteService(database: () async => db, cancelarNotificacion: (_) async {});
    lote = Lote(id: 'L1', title: 'Lote privado', status: 'en proceso', createdAt: DateTime(2026, 11, 10));
    await db.insert('lotes', lote.toRow());
    peticiones = [];
    contador = 0;
    selector = _Selector()..foto = _jpeg();
    responder = (_) async => _json(_resp());
    servicio = FotoService(
      database: () async => db,
      cliente: MockClient((r) {
        peticiones.add(r);
        return responder(r);
      }),
      urlServidor: 'https://api.cacaolight.example/v1',
      idInstalacion: () async => _id,
      directorio: () async => dir,
      nuevoId: () => 'foto-${++contador}',
      timeout: const Duration(seconds: 5),
    );
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  Future<void> abrirLista(WidgetTester t) async {
    t.view.physicalSize = const Size(800, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      home: FotosLoteScreen(lote: lote, servicio: servicio, selector: selector, preparar: (b) async => PreparadorFoto.prepararSincrono(b)),
    ));
    await _esperar(t);
  }

  Future<void> tocar(WidgetTester t, String texto) async {
    await t.ensureVisible(find.text(texto));
    await t.tap(find.text(texto));
    await _esperar(t);
  }

  Future<void> hastaLaGuia(WidgetTester t, String modo) async {
    await tocar(t, 'Nueva foto');
    await tocar(t, modo);
  }

  testWidgets('lista vacía: aviso fijo, explicación y botón de nueva foto', (t) async {
    await abrirLista(t);
    expect(find.text('Todavía no hay fotos en este lote'), findsOneWidget);
    expect(find.text('Es una guía, no reemplaza al técnico.'), findsOneWidget);
    expect(find.textContaining('no reemplaza la prueba de corte oficial'), findsOneWidget);
    expect(find.text('Nueva foto'), findsOneWidget);
  });

  testWidgets('elegir qué mirar muestra los 3 modos y cada uno su guía, con la nota de que son consejos de la app', (t) async {
    await abrirLista(t);
    await tocar(t, 'Nueva foto');
    for (final m in ModoAnalisis.values) {
      expect(find.text(m.nombre), findsOneWidget);
    }
    await tocar(t, 'Prueba de corte');
    expect(find.text('Cómo fotografiar la prueba de corte'), findsOneWidget);
    expect(find.text(GuiaFoto.nota), findsOneWidget);
    expect(find.textContaining('Corte cada grano a lo largo'), findsWidgets);
    expect(find.text('Tomar la foto'), findsOneWidget);
    expect(find.text('Elegir una foto del teléfono'), findsOneWidget);

    await t.tap(find.byTooltip('Cambiar lo que quiere mirar'));
    await _esperar(t, vueltas: 3);
    await tocar(t, 'Mazorca u hoja');
    expect(find.text('Cómo fotografiar una mazorca o una hoja'), findsOneWidget);
  });

  testWidgets('cada guía termina con "no fotografíe personas"', (t) async {
    for (final m in ModoAnalisis.values) {
      expect(GuiaFoto.para(m).pasos.last.texto, contains('No fotografíe personas'));
    }
  });

  testWidgets('primera foto: pide permiso; si no acepta, no se abre la cámara ni se envía nada', (t) async {
    await abrirLista(t);
    await hastaLaGuia(t, 'Prueba de corte');
    await tocar(t, 'Tomar la foto');

    expect(find.text(ConsentimientoFotos.titulo), findsOneWidget);
    expect(find.textContaining('Anthropic'), findsOneWidget);
    await t.tap(find.text('No enviar'));
    await _esperar(t);

    expect(find.textContaining('Sin su permiso la app no analiza fotos'), findsOneWidget);
    expect(selector.llamadas, isEmpty);
    expect(peticiones, isEmpty);
    expect(await t.runAsync(() => servicio.listar('L1')), isEmpty);
    expect(await t.runAsync(() => ConsentimientoFotos.obtener()), isFalse);
  });

  testWidgets('acepta: reduce la foto, la analiza y muestra el resultado con semáforo, porcentajes y aviso', (t) async {
    await abrirLista(t);
    await hastaLaGuia(t, 'Prueba de corte');
    await tocar(t, 'Tomar la foto');
    await t.tap(find.text('Sí, enviar'));
    await _esperar(t, vueltas: 20);

    expect(selector.llamadas, [true]);
    expect(peticiones, hasLength(1));
    final cuerpo = jsonDecode(peticiones.single.body) as Map<String, dynamic>;
    expect(cuerpo.keys.toSet(), {'modo', 'imagen'});
    expect(peticiones.single.body, isNot(contains('Lote privado')));

    expect(find.text('Sin problemas a la vista'), findsOneWidget);
    expect(find.text('Bien fermentado'), findsOneWidget);
    expect(find.text('70 %'), findsOneWidget);
    expect(find.text('Violeta'), findsOneWidget);
    expect(find.text('Es una guía, no reemplaza al técnico.'), findsOneWidget);
    expect(find.textContaining('NTC 1252'), findsOneWidget);
    expect(find.text('Pase a secado', skipOffstage: false), findsNothing, reason: 'se muestra con viñeta');
    expect(find.text('• Pase a secado', skipOffstage: false), findsOneWidget);
    expect(await t.runAsync(() => ConsentimientoFotos.obtener()), isTrue);

    final guardadas = await t.runAsync(() => servicio.listar('L1'));
    final jpg = await t.runAsync(() => File(guardadas!.single.ruta).readAsBytes());
    final d = img.decodeJpg(jpg!)!;
    expect(d.width, lessThanOrEqualTo(1024));
    expect(d.exif.isEmpty, isTrue);
  });

  testWidgets('la segunda foto ya no pregunta el permiso', (t) async {
    await t.runAsync(() => ConsentimientoFotos.registrar(true));
    await abrirLista(t);
    await hastaLaGuia(t, 'Grano seco');
    await tocar(t, 'Elegir una foto del teléfono');
    await _esperar(t, vueltas: 15);
    expect(find.text(ConsentimientoFotos.titulo), findsNothing);
    expect(selector.llamadas, [false]);
    expect(peticiones, hasLength(1));
    expect(jsonDecode(peticiones.single.body)['modo'], 'grano_seco');
  });

  testWidgets('sin señal: la foto queda guardada, se avisa y luego se analiza con "Reintentar ahora"', (t) async {
    await t.runAsync(() => ConsentimientoFotos.registrar(true));
    responder = (_) async => throw const SocketException('sin red');
    await abrirLista(t);
    await hastaLaGuia(t, 'Prueba de corte');
    await tocar(t, 'Tomar la foto');
    await _esperar(t, vueltas: 15);

    expect(find.text('La foto quedó guardada'), findsOneWidget);
    expect(find.textContaining('No hay conexión a internet'), findsOneWidget);
    await t.tap(find.text('Entendido'));
    await _esperar(t, vueltas: 8);

    expect(find.text('1 foto espera señal para analizarse'), findsOneWidget);
    expect(find.textContaining('Esperando señal'), findsOneWidget);

    responder = (_) async => _json(_resp(semaforo: 'amarillo'));
    await tocar(t, 'Reintentar ahora');
    await _esperar(t, vueltas: 10);
    expect(find.textContaining('foto espera señal'), findsNothing);
    expect(find.textContaining('· Analizada'), findsOneWidget);
    expect(find.text('Hay algo que vigilar'), findsOneWidget);
  });

  testWidgets('al abrir la lista reintenta solo las fotos pendientes', (t) async {
    final dirFoto = await t.runAsync(() => servicio.guardar(
        loteId: 'L1', modo: ModoAnalisis.corte, foto: PreparadorFoto.prepararSincrono(_jpeg())));
    expect(dirFoto!.estado, EstadoAnalisis.pendiente);
    await abrirLista(t);
    await _esperar(t, vueltas: 10);
    expect(peticiones, hasLength(1));
    expect(find.textContaining('· Analizada'), findsOneWidget);
  });

  testWidgets('cancelar la cámara no hace nada; un error del selector se explica', (t) async {
    await t.runAsync(() => ConsentimientoFotos.registrar(true));
    await abrirLista(t);
    await hastaLaGuia(t, 'Prueba de corte');
    selector.foto = null;
    await tocar(t, 'Tomar la foto');
    expect(peticiones, isEmpty);
    expect(find.text('Tomar la foto'), findsOneWidget);

    selector.falla = const SelectorFotoException('La app no tiene permiso para usar la cámara. Actívelo en los ajustes del teléfono.');
    await tocar(t, 'Tomar la foto');
    expect(find.textContaining('no tiene permiso para usar la cámara'), findsOneWidget);
    expect(peticiones, isEmpty);
  });

  testWidgets('un archivo que no es una foto se rechaza con un mensaje y no se guarda', (t) async {
    await t.runAsync(() => ConsentimientoFotos.registrar(true));
    selector.foto = Uint8List.fromList([1, 2, 3, 4]);
    await abrirLista(t);
    await hastaLaGuia(t, 'Prueba de corte');
    await tocar(t, 'Tomar la foto');
    expect(find.text('No se pudo leer la foto.'), findsOneWidget);
    expect(await t.runAsync(() => servicio.listar('L1')), isEmpty);
    expect(peticiones, isEmpty);
  });

  group('resultado', () {
    Future<void> abrirResultado(WidgetTester t, Map<String, Object?> respuesta) async {
      final a = await t.runAsync(() async {
        final g = await servicio.guardar(loteId: 'L1', modo: ModoAnalisis.corte, foto: PreparadorFoto.prepararSincrono(_jpeg()));
        responder = (_) async => _json(respuesta);
        return servicio.analizar(g.id);
      });
      t.view.physicalSize = const Size(800, 2600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(home: ResultadoFotoScreen(analisis: a!, servicio: servicio)));
      await _esperar(t, vueltas: 4);
    }

    testWidgets('los tres semáforos tienen ícono y palabras, no solo color', (t) async {
      for (final (s, texto, icono) in [
        ('verde', 'Sin problemas a la vista', Icons.check_circle),
        ('amarillo', 'Hay algo que vigilar', Icons.warning_amber_rounded),
        ('rojo', 'Problema serio: consulte al técnico', Icons.error),
      ]) {
        await abrirResultado(t, _resp(semaforo: s));
        expect(find.text(texto), findsOneWidget, reason: s);
        expect(find.byIcon(icono), findsWidgets, reason: s);
        await t.pumpWidget(const SizedBox());
      }
    });

    testWidgets('si la IA pide otra foto: mensaje y pasos, sin porcentajes ni semáforo', (t) async {
      await abrirResultado(t, _resp(repetir: true, semaforo: 'amarillo'));
      expect(find.text('Tome otra foto'), findsOneWidget);
      expect(find.textContaining('salió borrosa'), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);
      expect(find.text('Sin problemas a la vista'), findsNothing);
      expect(find.text('Hay algo que vigilar'), findsNothing);
      expect(find.text('Es una guía, no reemplaza al técnico.'), findsOneWidget);
    });

    testWidgets('borrar pide confirmación y quita la foto del teléfono', (t) async {
      await abrirResultado(t, _resp());
      final antes = await t.runAsync(() => servicio.listar('L1'));
      expect(File(antes!.single.ruta).existsSync(), isTrue);

      await t.tap(find.byTooltip('Borrar esta foto'));
      await _esperar(t, vueltas: 3);
      expect(find.text('¿Borrar esta foto?'), findsOneWidget);
      await t.tap(find.text('Cancelar'));
      await _esperar(t, vueltas: 3);
      expect(await t.runAsync(() => servicio.listar('L1')), hasLength(1));

      await t.tap(find.byTooltip('Borrar esta foto'));
      await _esperar(t, vueltas: 3);
      await t.tap(find.text('Borrar'));
      await _esperar(t, vueltas: 6);
      expect(await t.runAsync(() => servicio.listar('L1')), isEmpty);
      expect(File(antes.single.ruta).existsSync(), isFalse);
    });
  });

  testWidgets('desde el detalle del lote: el botón "Fotos del lote" abre la lista', (t) async {
    await t.runAsync(() => lotes.addLote(Lote(id: 'L9', title: 'Otro', status: 'en proceso', createdAt: DateTime.now())));
    final scheduler = AlarmScheduler(
      loteService: lotes,
      recordatorioService: RecordatorioService(database: () async => db, cancelarNotificacion: (_) async {}),
      siguienteId: () async => 1,
      programar: ({required id, required titulo, required cuerpo, required fechaProgramada, payload, esRecordatorio = false}) async {},
    );
    t.view.physicalSize = const Size(800, 3600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
        home: DetalleLoteScreen(lote: lote, loteService: lotes, scheduler: scheduler, fotoService: servicio, selectorFoto: selector)));
    await _esperar(t);
    await tocar(t, 'Fotos del lote (análisis con IA)');
    expect(find.text('Fotos del lote'), findsOneWidget);
    expect(find.text('Todavía no hay fotos en este lote'), findsOneWidget);
  });
}
