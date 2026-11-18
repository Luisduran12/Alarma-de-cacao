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
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:alarmacacao5_0/data/cacao_database.dart';
import 'package:alarmacacao5_0/models/lote.dart';
import 'package:alarmacacao5_0/models/volteada.dart';
import 'package:alarmacacao5_0/screens/comparacion_lotes_screen.dart';
import 'package:alarmacacao5_0/screens/confirmar_volteada_screen.dart';
import 'package:alarmacacao5_0/screens/detalle_lote_screen.dart';
import 'package:alarmacacao5_0/screens/home_screen.dart';
import 'package:alarmacacao5_0/services/lote_service.dart';

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

late Lote _loteDetalle;

Future<void> _sembrarDatos() async {
  final servicio = LoteService(cancelarNotificacion: (_) async {});
  final ahora = DateTime.now();

  // Lote en curso (para la pantalla principal)
  final inicioCurso = ahora.subtract(const Duration(hours: 60));
  await servicio.addLote(Lote(
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
  ));

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

Future<void> _capturar(WidgetTester tester, Widget pantalla, String archivo, {double alto = 915}) async {
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
}
