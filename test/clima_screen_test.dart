import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alarmacacao5_0/screens/clima_screen.dart';
import 'package:alarmacacao5_0/services/clima_service.dart';
import 'package:alarmacacao5_0/services/location_service.dart';
import 'package:alarmacacao5_0/services/lugar_service.dart';

const _respuesta = '''
{"utc_offset_seconds":-18000,"current":{"time":"2026-11-18T17:30","interval":900,
"temperature_2m":21.7,"relative_humidity_2m":81,"weather_code":1,"is_day":0}}
''';

/// 30 minutos después de la medición (17:30 hora de Colombia = 22:30 UTC).
final _ahora = DateTime.utc(2026, 11, 18, 23, 0);

class _Gps implements PlataformaUbicacion {
  LocationPermission permisoActual = LocationPermission.whileInUse;
  @override
  Future<bool> servicioActivado() async => true;
  @override
  Future<LocationPermission> permiso() async => permisoActual;
  @override
  Future<LocationPermission> pedirPermiso() async => permisoActual;
  @override
  Future<Position> posicionActual(Duration limite) async => Position(
        latitude: 7.603112, longitude: -72.601162, timestamp: _ahora, accuracy: 8, altitude: 0,
        altitudeAccuracy: 0, heading: 0, headingAccuracy: 0, speed: 0, speedAccuracy: 0);
  @override
  Future<Position?> ultimaConocida() async => null;
}

/// Devuelve siempre el mismo lugar, sin base de datos.
class _LugarFalso extends LugarService {
  @override
  Future<NombreLugar?> nombreDe(double lat, double lng) async =>
      const NombreLugar('Cerca de Chinácota (Norte de Santander), a menos de 1 km', OrigenLugar.listaOffline, 'DANE');
}

void main() {
  late _Gps gps;
  late List<Uri> pedidos;
  late List<Uri> enlaces;
  var internet = true;
  DateTime ahoraDePantalla = _ahora;

  ClimaService servicio() => ClimaService(
        cliente: MockClient((r) async {
          pedidos.add(r.url);
          if (!internet) throw const SocketException('sin red');
          return http.Response(_respuesta, 200);
        }),
        ahora: () => ahoraDePantalla,
      );

  Future<void> abrir(WidgetTester t, {ClimaService? clima}) async {
    t.view.physicalSize = const Size(800, 3200);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      home: ClimaScreen(
        clima: clima ?? servicio(),
        ubicacion: LocationService(plataforma: gps, consentimiento: () async => true),
        lugarService: _LugarFalso(),
        abrirEnlace: (u) async {
          enlaces.add(u);
          return true;
        },
        ahora: () => ahoraDePantalla,
      ),
    ));
    await t.pumpAndSettle();
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    gps = _Gps();
    pedidos = [];
    enlaces = [];
    internet = true;
    ahoraDePantalla = _ahora;
  });

  testWidgets('en línea: temperatura, humedad, cielo, antigüedad y crédito de Open-Meteo', (t) async {
    await abrir(t);
    expect(find.text('21,7 °C'), findsOneWidget);
    expect(find.text('81 %'), findsOneWidget);
    expect(find.text('Casi despejado'), findsOneWidget);
    expect(find.text('Dato de hace 30 min'), findsOneWidget);
    expect(find.text('Weather data by Open-Meteo.com'), findsOneWidget);
    expect(pedidos, hasLength(1));
    expect(pedidos.single.queryParameters['latitude'], '7.60', reason: 'ubicación redondeada, no la exacta');
    expect(pedidos.single.query.toLowerCase(), isNot(contains('key')));
  });

  testWidgets('muestra el lugar donde se tomó el clima (referencia aproximada)', (t) async {
    await abrir(t);
    expect(find.text('Cerca de Chinácota (Norte de Santander), a menos de 1 km'), findsOneWidget);
    expect(find.textContaining('no la vereda'), findsOneWidget);
  });

  testWidgets('deja clarísimo que es el clima del ambiente y no la temperatura del grano', (t) async {
    await abrir(t);
    expect(find.textContaining('clima del ambiente'), findsOneWidget);
    expect(find.textContaining('NO es la temperatura de la masa de cacao ni la del grano'), findsOneWidget);
    expect(find.text('Temperatura del aire'), findsOneWidget);
  });

  testWidgets('no da veredictos ("adecuado") ni recomendaciones sin fuente', (t) async {
    await abrir(t);
    final textos = t.widgetList<Text>(find.byType(Text)).map((w) => w.data ?? '').join(' ').toLowerCase();
    for (final palabra in ['adecuado', 'recomienda', 'no es suficiente', '✅', '⚠️']) {
      expect(textos.contains(palabra), isFalse, reason: palabra);
    }
  });

  testWidgets('tocar el crédito abre el sitio de Open-Meteo', (t) async {
    await abrir(t);
    await t.tap(find.text('Weather data by Open-Meteo.com'));
    await t.pump();
    expect(enlaces.single.toString(), 'https://open-meteo.com/');
  });

  testWidgets('"Actualizar" vuelve a consultar', (t) async {
    await abrir(t);
    await t.tap(find.text('Actualizar'));
    await t.pumpAndSettle();
    expect(pedidos, hasLength(2));
  });

  testWidgets('sin señal y con un dato guardado: lo muestra con "hace X horas" y el aviso', (t) async {
    await t.runAsync(() => servicio().consultar(7.6, -72.6)); // deja un dato guardado
    internet = false;
    ahoraDePantalla = _ahora.add(const Duration(hours: 6));
    await abrir(t);

    expect(find.text('21,7 °C'), findsOneWidget);
    expect(find.text('Dato de hace 6 horas'), findsOneWidget);
    expect(find.textContaining('Sin señal de internet. Se muestra el último dato guardado.'), findsOneWidget);
  });

  testWidgets('sin señal y sin nada guardado: avisa y ofrece escribirlo a mano', (t) async {
    internet = false;
    await abrir(t);
    expect(find.text('21,7 °C'), findsNothing);
    expect(find.textContaining('puede escribir la temperatura y la humedad a mano'), findsOneWidget);
    expect(find.text('Escribirlo a mano'), findsOneWidget);
  });

  testWidgets('escribir a mano: se guarda, se muestra como anotado por el usuario y sin crédito de Open-Meteo', (t) async {
    internet = false;
    await abrir(t);
    await t.enterText(find.widgetWithText(TextFormField, 'Temperatura del aire (°C)'), '26,5');
    await t.enterText(find.widgetWithText(TextFormField, 'Humedad del aire (%)'), '78');
    await t.tap(find.text('Guardar lo que anoté'));
    await t.pumpAndSettle();

    expect(find.text('26,5 °C'), findsOneWidget);
    expect(find.text('78 %'), findsOneWidget);
    expect(find.text('Anotado por usted hace un momento'), findsOneWidget);
    expect(find.text('Weather data by Open-Meteo.com'), findsNothing, reason: 'ese dato no viene de Open-Meteo');
    expect((await t.runAsync(() => servicio().ultimo()))!.esManual, isTrue);
  });

  testWidgets('validaciones del formulario a mano', (t) async {
    internet = false;
    await abrir(t);
    final temp = find.widgetWithText(TextFormField, 'Temperatura del aire (°C)');
    final hum = find.widgetWithText(TextFormField, 'Humedad del aire (%)');

    await t.tap(find.text('Guardar lo que anoté'));
    await t.pump();
    expect(find.text('Escriba la temperatura'), findsOneWidget);
    expect(find.text('Escriba la humedad'), findsOneWidget);

    await t.enterText(temp, 'abc');
    await t.enterText(hum, '150');
    await t.tap(find.text('Guardar lo que anoté'));
    await t.pump();
    expect(find.text('Escriba solo números'), findsOneWidget);
    expect(find.text('Debe estar entre 0 y 100'), findsOneWidget);

    await t.enterText(temp, '99');
    await t.tap(find.text('Guardar lo que anoté'));
    await t.pump();
    expect(find.text('Debe estar entre -60 y 60'), findsOneWidget);
    expect(await t.runAsync(() => servicio().ultimo()), isNull, reason: 'lo inválido no se guarda');
  });

  testWidgets('sin permiso de GPS y con dato guardado: muestra el guardado y explica', (t) async {
    await t.runAsync(() => servicio().consultar(7.6, -72.6));
    gps.permisoActual = LocationPermission.deniedForever;
    await abrir(t);
    expect(find.text('21,7 °C'), findsOneWidget);
    expect(find.textContaining('permiso de ubicación está bloqueado'), findsOneWidget);
    expect(pedidos, hasLength(1), reason: 'sin ubicación no se consulta de nuevo');
  });

  testWidgets('sin GPS y sin dato guardado: explica y deja escribirlo a mano', (t) async {
    gps.permisoActual = LocationPermission.deniedForever;
    await abrir(t);
    expect(find.textContaining('permiso de ubicación está bloqueado'), findsOneWidget);
    expect(find.text('Escribirlo a mano'), findsOneWidget);
    expect(pedidos, isEmpty);
  });

  testWidgets('la descripción accesible de las cifras dice "ambiente"', (t) async {
    final h = t.ensureSemantics();
    await abrir(t);
    expect(find.bySemanticsLabel(RegExp('Temperatura del ambiente 21,7 grados')), findsOneWidget);
    h.dispose();
  });
}
