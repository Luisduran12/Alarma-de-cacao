// Genera las capturas del README a partir de las pantallas REALES de la app,
// con datos de ejemplo en una base SQLite de prueba.
//
// No forma parte de `flutter test` (está fuera de test/). Para regenerarlas:
//   flutter test test_capturas --update-goldens
//
// Las fuentes se cargan desde el SDK de Flutter (Roboto e íconos) y, si existe,
// la fuente de emojis de Windows; en otro sistema los emojis salen como cuadros.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:alarmacacao5_0/data/cacao_database.dart';
import 'package:alarmacacao5_0/models/lote.dart';
import 'package:alarmacacao5_0/models/volteada.dart';
import 'package:alarmacacao5_0/screens/comparacion_lotes_screen.dart';
import 'package:alarmacacao5_0/screens/confirmar_volteada_screen.dart';
import 'package:alarmacacao5_0/screens/detalle_lote_screen.dart';
import 'package:alarmacacao5_0/screens/clima_screen.dart';
import 'package:alarmacacao5_0/screens/guia_prueba_corte_screen.dart';
import 'package:alarmacacao5_0/screens/home_screen.dart';
import 'package:alarmacacao5_0/screens/reglas_alerta_screen.dart';
import 'package:alarmacacao5_0/services/clima_service.dart';
import 'package:alarmacacao5_0/services/exportar_curva.dart';
import 'package:alarmacacao5_0/services/location_service.dart';
import 'package:alarmacacao5_0/services/lote_service.dart';
import 'package:alarmacacao5_0/widgets/curva_lote_chart.dart';

Future<void> _cargarFuente(String familia, List<String> rutas) async {
  final loader = FontLoader(familia);
  var alguna = false;
  for (final ruta in rutas) {
    final f = File(ruta);
    if (f.existsSync()) {
      loader.addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
      alguna = true;
    }
  }
  if (alguna) await loader.load();
}

String get _sdkFuentes {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ??
      File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.parent.path;
  return '$flutterRoot/bin/cache/artifacts/material_fonts';
}

Widget _app(Widget home) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.brown),
        useMaterial3: true,
        fontFamily: 'Roboto',
        fontFamilyFallback: const ['Emoji'],
      ),
      home: home,
    );

Volteada _reg(String lote, int horas, double t, double h, String obs,
        {String etapa = Etapa.fermentacion, double? lat, double? lon, DateTime? inicio}) {
  final f = inicio!.add(Duration(hours: horas));
  return Volteada(
    id: '$lote-$horas',
    loteId: lote,
    mensaje: 'Volteada ($horas h)',
    temperatura: t,
    humedad: h,
    observacion: obs,
    fecha: f,
    fechaProgramada: f,
    confirmada: true,
    etapa: etapa,
    latitud: lat,
    longitud: lon,
  );
}

/// GPS simulado en Chinácota (Norte de Santander), para las capturas.
class _GpsCaptura implements PlataformaUbicacion {
  @override
  Future<bool> servicioActivado() async => true;
  @override
  Future<LocationPermission> permiso() async => LocationPermission.whileInUse;
  @override
  Future<LocationPermission> pedirPermiso() async => LocationPermission.whileInUse;
  @override
  Future<Position> posicionActual(Duration limite) async => Position(
      latitude: 7.5851, longitude: -72.5964, timestamp: DateTime.now(), accuracy: 9, altitude: 0,
      altitudeAccuracy: 0, heading: 0, headingAccuracy: 0, speed: 0, speedAccuracy: 0);
  @override
  Future<Position?> ultimaConocida() async => null;
}

/// Respuesta REAL de Open-Meteo (consulta del 2026-11-18, 17:30 hora de Colombia, sin clave).
const _respuestaOpenMeteo =
    '{"utc_offset_seconds":-18000,"current":{"time":"2026-11-18T17:30","interval":900,'
    '"temperature_2m":21.7,"relative_humidity_2m":81,"weather_code":1,"is_day":0}}';
final _momentoClima = DateTime.utc(2026, 11, 18, 23, 0); // 30 min después de esa medición

late Lote _loteDetalle;
late Lote _loteCurso;

Future<void> _sembrarDatos() async {
  final servicio = LoteService(cancelarNotificacion: (_) async {});
  final ahora = DateTime.now();

  // Lote en curso (para la pantalla principal)
  final inicioCurso = ahora.subtract(const Duration(hours: 60));
  _loteCurso = Lote(
    id: 'curso',
    title: 'Lote finca La Esperanza',
    status: 'en proceso',
    createdAt: inicioCurso,
    inicioCiclo: inicioCurso,
    finCiclo: inicioCurso.add(const Duration(hours: 144)),
    plantilla: 'fedecacao_144',
    volteadas: [
      _reg('curso', 48, 44.5, 83, 'Masa caliente, olor a vinagre', inicio: inicioCurso),
      for (final h in [72, 96, 120, 144])
        Volteada(
          id: 'curso-p$h',
          loteId: 'curso',
          mensaje: h == 144 ? 'Fin del ciclo (144 h)' : 'Volteada ($h h)',
          temperatura: 0,
          humedad: 0,
          observacion: '',
          fecha: inicioCurso,
          fechaProgramada: inicioCurso.add(Duration(hours: h)),
          confirmada: false,
        ),
    ],
  );
  await servicio.addLote(_loteCurso);

  // Lote terminado con curva, secado y resultado (detalle y comparación)
  final ini = ahora.subtract(const Duration(days: 12));
  _loteDetalle = Lote(
    id: 'detalle',
    title: 'Lote 03 - Cajón de madera',
    status: 'completado',
    createdAt: ini,
    inicioCiclo: ini,
    finCiclo: ini.add(const Duration(hours: 144)),
    plantilla: 'fedecacao_144',
    calidadResultado: Calidad.buena,
    observacionResultado: 'Prueba de corte: 78 % granos bien fermentados, aroma a chocolate.',
    volteadas: [
      _reg('detalle', 24, 34.0, 88, 'Inicio de fase anaeróbica', inicio: ini),
      _reg('detalle', 48, 42.5, 85, 'Primer volteo, olor a alcohol', inicio: ini),
      _reg('detalle', 72, 46.0, 82, 'Color café en el borde', inicio: ini),
      _reg('detalle', 96, 47.5, 80, 'Olor a vinagre suave', inicio: ini),
      _reg('detalle', 120, 45.0, 78, 'Grano hinchado', inicio: ini),
      _reg('detalle', 168, 33.0, 62, 'Secado al sol, día 1', etapa: Etapa.secado,
          lat: 7.893907, lon: -72.507828, inicio: ini),
      _reg('detalle', 192, 35.5, 55, 'Secado al sol, día 2', etapa: Etapa.secado,
          lat: 7.893907, lon: -72.507828, inicio: ini),
    ],
  );
  await servicio.addLote(_loteDetalle);

  Future<void> otro(String id, String titulo, String calidad, String obs, List<List<double>> datos, int dias) async {
    final i = ahora.subtract(Duration(days: dias));
    await servicio.addLote(Lote(
      id: id,
      title: titulo,
      status: 'completado',
      createdAt: i,
      calidadResultado: calidad,
      observacionResultado: obs,
      volteadas: [
        for (var k = 0; k < datos.length; k++) _reg(id, 24 * (k + 1), datos[k][0], datos[k][1], 'ok', inicio: i),
      ],
    ));
  }

  await otro('l1', 'Lote 01 - Canasto', Calidad.regular, 'Muchos granos pizarrosos.',
      [[31, 90], [36, 88], [39, 86]], 30);
  await otro('l2', 'Lote 02 - Cajón escalonado', Calidad.excelente, 'Aroma frutal, 85 % bien fermentado.',
      [[40, 84], [46, 81], [48, 79], [46, 78]], 20);
  await otro('l4', 'Lote 04 - Sacos', Calidad.mala, 'Moho en la superficie.',
      [[28, 93], [30, 92]], 5);
}

Future<void> _capturar(WidgetTester tester, Widget pantalla, String archivo,
    {double alto = 915, Future<void> Function(WidgetTester)? interaccion}) async {
  // En pruebas Flutter reemplaza las sombras por un borde negro; se desactiva
  // solo durante la captura (debe volver a true al terminar cada prueba).
  debugDisableShadows = false;
  tester.view.devicePixelRatio = 2.0;
  tester.view.physicalSize = Size(412 * 2.0, alto * 2.0);
  addTearDown(tester.view.reset);

  await tester.runAsync(() async {
    await tester.pumpWidget(_app(pantalla));
    await Future<void>.delayed(const Duration(milliseconds: 800));
  });
  await tester.pump(const Duration(milliseconds: 300));
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
  await tester.pump();
  if (interaccion != null) await interaccion(tester);

  await expectLater(find.byType(MaterialApp), matchesGoldenFile('../docs/capturas/$archivo'));
  await tester.pumpWidget(const SizedBox()); // libera timers
  debugDisableShadows = true;
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({'migrado_a_sqlite_v1': true});

    final dbPath = '${await databaseFactoryFfi.getDatabasesPath()}/${CacaoDatabase.nombreArchivo}';
    await databaseFactoryFfi.deleteDatabase(dbPath);

    await _cargarFuente('Roboto', ['$_sdkFuentes/roboto-regular.ttf', '$_sdkFuentes/roboto-bold.ttf',
      '$_sdkFuentes/roboto-medium.ttf', '$_sdkFuentes/roboto-italic.ttf']);
    await _cargarFuente('MaterialIcons', ['$_sdkFuentes/materialicons-regular.otf']);
    await _cargarFuente('Emoji', ['C:/Windows/Fonts/seguiemj.ttf']);

    await _sembrarDatos();
  });

  testWidgets('inicio', (t) => _capturar(t, const HomeScreen(title: 'Cacao Light 4.0'), '01_inicio.png', alto: 1080));
  testWidgets('detalle', (t) => _capturar(t, DetalleLoteScreen(lote: _loteDetalle), '02_detalle_lote.png', alto: 1900));
  testWidgets('registro',
      (t) => _capturar(t, const ConfirmarVolteadaScreen(loteId: 'curso', volteadaId: 'curso-p72'), '03_registro.png', alto: 640));
  testWidgets('comparar', (t) => _capturar(t, const ComparacionLotesScreen(), '04_comparar_lotes.png', alto: 1150));

  // ---- Fase 1: curva de valores (datos de EJEMPLO, no medidos) ----

  testWidgets('fase1 detalle con banda y resumen',
      (t) => _capturar(t, DetalleLoteScreen(lote: _loteDetalle), 'fase1/f1_detalle_curva.png', alto: 2600));

  testWidgets('fase1 comparar con otro lote y curva ideal', (t) async {
    // Curva ideal de EJEMPLO para la captura; la app real no trae ninguna.
    SharedPreferences.setMockInitialValues({
      'migrado_a_sqlite_v1': true,
      'curva_ideal_v1': '[{"h":48,"t":43},{"h":72,"t":46},{"h":120,"t":47}]',
    });
    await _capturar(t, DetalleLoteScreen(lote: _loteDetalle), 'fase1/f1_comparar_ideal.png', alto: 2600,
        interaccion: (t) async {
      await t.tap(find.text('Comparar con otro lote'));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
      await t.pumpAndSettle();
      await t.tap(find.text('Lote 02 - Cajón escalonado'));
      await t.pumpAndSettle();
    });
  });

  testWidgets('fase1 registro con pH, Brix y temperatura ambiente',
      (t) => _capturar(t, const ConfirmarVolteadaScreen(loteId: 'curso', volteadaId: 'curso-p72'),
          'fase1/f1_registro_campos.png', alto: 1000));

  testWidgets('fase1 pdf del lote', (t) async {
    debugDisableShadows = false;
    final clave = GlobalKey();
    final ini = _loteDetalle.inicioCiclo!;
    await t.pumpWidget(_app(Scaffold(
      body: SingleChildScrollView(
        child: SizedBox(
          width: 390,
          child: CurvaLoteChart(
              registros: _loteDetalle.volteadas, inicio: ini, nombre: _loteDetalle.title, repaintKey: clave),
        ),
      ),
    )));
    await t.runAsync(() async {
      final png = await ExportarCurva.capturarPng(clave);
      final pdf = await ExportarCurva.pdfDelLote(
          lote: _loteDetalle, registros: _loteDetalle.volteadas, inicio: ini, png: png,
          generado: DateTime(2026, 11, 18, 10));
      final destino = File('docs/capturas/fase1/f1_lote.pdf')..createSync(recursive: true);
      destino.writeAsBytesSync(pdf);
      File('docs/capturas/fase1/f1_curva.png').writeAsBytesSync(png);
    });
    await t.pumpWidget(const SizedBox());
    debugDisableShadows = true;
  });

  // ---- Fase 2: alertas y recordatorios (datos de EJEMPLO, no medidos) ----

  testWidgets('fase2 reglas de alerta',
      (t) => _capturar(t, const ReglasAlertaScreen(), 'fase2/f2_reglas_alerta.png', alto: 1250));

  testWidgets('fase2 guia de la prueba de corte',
      (t) => _capturar(t, const GuiaPruebaCorteScreen(), 'fase2/f2_guia_prueba_corte.png', alto: 5600));

  testWidgets('fase2 detalle con interruptor de recordatorios',
      (t) => _capturar(t, DetalleLoteScreen(lote: _loteCurso), 'fase2/f2_detalle_recordatorios.png', alto: 1500,
              interaccion: (t) async {
            // Espera a que cargue el estado de los recordatorios (lee la base de datos).
            for (var i = 0; i < 10; i++) {
              await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
              await t.pump(const Duration(milliseconds: 60));
            }
          }));

  testWidgets('fase2 aviso de valor fuera de rango al guardar', (t) async {
    SharedPreferences.setMockInitialValues({'migrado_a_sqlite_v1': true});
    await _capturar(
      t,
      ConfirmarVolteadaScreen(loteId: 'curso', volteadaId: 'curso-p72', notificarAlerta: (_, __) async {}),
      'fase2/f2_aviso_fuera_de_rango.png',
      alto: 1100,
      interaccion: (t) async {
        final campos = find.byType(TextFormField);
        await t.enterText(campos.at(0), '41,5');
        await t.enterText(campos.at(1), '85');
        await t.enterText(campos.at(5), 'Masa fría, poco olor a vinagre');
        await t.tap(find.text('Guardar datos'));
        for (var i = 0; i < 10; i++) {
          await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
          await t.pump(const Duration(milliseconds: 60));
        }
      },
    );
  });

  // ---- Fase 3: ubicación, clima y lugar (clima REAL de una consulta; lugares reales del DANE) ----

  ClimaService servicioClima({required bool internet, DateTime? ahora}) => ClimaService(
        cliente: MockClient((_) async =>
            internet ? http.Response(_respuestaOpenMeteo, 200) : throw http.ClientException('sin red')),
        ahora: () => ahora ?? _momentoClima,
      );

  Widget pantallaClima(ClimaService c, {DateTime? ahora}) => ClimaScreen(
        clima: c,
        ubicacion: LocationService(plataforma: _GpsCaptura()),
        ahora: () => ahora ?? _momentoClima,
      );

  testWidgets('fase3 clima en linea', (t) async {
    SharedPreferences.setMockInitialValues({'migrado_a_sqlite_v1': true});
    await _capturar(t, pantallaClima(servicioClima(internet: true)), 'fase3/f3_clima_en_linea.png', alto: 1500);
  });

  testWidgets('fase3 clima sin senal con ultimo dato guardado', (t) async {
    SharedPreferences.setMockInitialValues({'migrado_a_sqlite_v1': true});
    final seisHorasDespues = _momentoClima.add(const Duration(hours: 6));
    await t.runAsync(() => servicioClima(internet: true).consultar(7.59, -72.60)); // deja el dato guardado
    await _capturar(t, pantallaClima(servicioClima(internet: false, ahora: seisHorasDespues), ahora: seisHorasDespues),
        'fase3/f3_clima_sin_senal.png', alto: 1500);
  });

  testWidgets('fase3 clima escrito a mano sin senal', (t) async {
    SharedPreferences.setMockInitialValues({'migrado_a_sqlite_v1': true});
    await _capturar(t, pantallaClima(servicioClima(internet: false)), 'fase3/f3_clima_manual.png', alto: 1500,
        interaccion: (t) async {
      await t.enterText(find.widgetWithText(TextFormField, 'Temperatura del aire (°C)'), '26,5');
      await t.enterText(find.widgetWithText(TextFormField, 'Humedad del aire (%)'), '78');
      await t.tap(find.text('Guardar lo que anoté'));
      for (var i = 0; i < 8; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
        await t.pump(const Duration(milliseconds: 60));
      }
    });
  });

  testWidgets('fase3 punto de secado por GPS con el lugar',
      (t) => _capturar(
          t,
          ConfirmarVolteadaScreen(
              loteId: 'detalle', ubicacion: LocationService(plataforma: _GpsCaptura()), notificarAlerta: (_, __) async {}),
          'fase3/f3_punto_secado_gps.png',
          alto: 1500));

  testWidgets('fase3 detalle con el lugar del punto de secado',
      (t) => _capturar(t, DetalleLoteScreen(lote: _loteDetalle), 'fase3/f3_detalle_lugar.png', alto: 2800));
}
