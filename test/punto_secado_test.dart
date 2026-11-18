import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:alarmacacao5_0/data/cacao_database.dart';
import 'package:alarmacacao5_0/models/lote.dart';
import 'package:alarmacacao5_0/models/volteada.dart';
import 'package:alarmacacao5_0/screens/confirmar_volteada_screen.dart';
import 'package:alarmacacao5_0/services/location_service.dart';
import 'package:alarmacacao5_0/services/lote_service.dart';

/// Fuera del reloj falso hay que dar tiempo real a SQLite; cada `await` necesita su vuelta.
Future<void> _esperar(WidgetTester t) async {
  for (var i = 0; i < 10; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await t.pump(const Duration(milliseconds: 50));
  }
}

class _GpsFalso implements PlataformaUbicacion {
  Position? posicion;
  Position? ultima;
  LocationPermission permisoActual = LocationPermission.whileInUse;

  @override
  Future<bool> servicioActivado() async => true;
  @override
  Future<LocationPermission> permiso() async => permisoActual;
  @override
  Future<LocationPermission> pedirPermiso() async => permisoActual;
  @override
  Future<Position> posicionActual(Duration limite) async {
    if (posicion == null) throw Exception('sin fix');
    return posicion!;
  }

  @override
  Future<Position?> ultimaConocida() async => ultima;
}

Position _pos(double lat, double lng, {double precision = 8, DateTime? momento}) => Position(
      latitude: lat, longitude: lng, timestamp: momento ?? DateTime.now(), accuracy: precision,
      altitude: 0, altitudeAccuracy: 0, heading: 0, headingAccuracy: 0, speed: 0, speedAccuracy: 0,
    );

void main() {
  sqfliteFfiInit();

  late Database db;
  late LoteService servicio;
  late _GpsFalso gps;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await CacaoDatabase.abrir(databaseFactoryFfi, inMemoryDatabasePath);
    servicio = LoteService(database: () async => db, cancelarNotificacion: (_) async {});
    gps = _GpsFalso();
    // Lote cuyo ciclo ya terminó: la pantalla abre en "Secado" y pide la ubicación sola.
    final inicio = DateTime.now().subtract(const Duration(hours: 200));
    await servicio.addLote(Lote(
      id: 'L1', title: 'Lote Durania', status: 'en proceso', createdAt: inicio, inicioCiclo: inicio,
      finCiclo: inicio.add(const Duration(hours: 144)),
      volteadas: [
        Volteada(
          id: 'V1', loteId: 'L1', mensaje: 'Registro', temperatura: 0, humedad: 0, observacion: '',
          fecha: inicio, fechaProgramada: DateTime.now(), confirmada: false,
        ),
      ],
    ));
  });

  tearDown(() => db.close());

  Future<void> abrir(WidgetTester t) async {
    t.view.physicalSize = const Size(800, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ConfirmarVolteadaScreen(
                loteId: 'L1', volteadaId: 'V1', loteService: servicio,
                ubicacion: LocationService(plataforma: gps),
                notificarAlerta: (_, __) async {},
              ),
            )),
            child: const Text('abrir'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('abrir'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    await _esperar(t);
  }

  Future<void> llenarYGuardar(WidgetTester t) async {
    final campos = find.byType(TextFormField);
    await t.enterText(campos.at(0), '35');
    await t.enterText(campos.at(1), '60');
    await t.enterText(campos.at(5), 'Secado al sol');
    await t.tap(find.text('Guardar datos'));
    await _esperar(t);
    await t.pumpAndSettle();
  }

  testWidgets('GPS ok: muestra coordenadas y precisión, y las guarda en el registro', (t) async {
    gps.posicion = _pos(7.6031, -72.6012, precision: 8);
    await abrir(t);
    expect(find.text('Secado'), findsWidgets);
    expect(find.text('Lat 7.603100, Lon -72.601200'), findsOneWidget);
    expect(find.text('Precisión: unos 8 m'), findsOneWidget);
    expect(find.textContaining('última ubicación'), findsNothing);

    await llenarYGuardar(t);
    final r = (await t.runAsync(() => servicio.obtenerRegistrosDelLote('L1')))!.single;
    expect([r.latitud, r.longitud], [7.6031, -72.6012]);
    expect(r.etapa, Etapa.secado);
  });

  testWidgets('GPS sin respuesta: usa la última ubicación y avisa que puede ser de otro lugar', (t) async {
    gps.posicion = null;
    gps.ultima = _pos(7.7, -72.7, momento: DateTime.now().subtract(const Duration(hours: 2)));
    await abrir(t);
    expect(find.text('Lat 7.700000, Lon -72.700000'), findsOneWidget);
    expect(find.textContaining('última ubicación que tenía el teléfono (hace 2 h)'), findsOneWidget);
    expect(find.textContaining('puede no ser de este lugar'), findsOneWidget);
  });

  testWidgets('sin GPS ni última posición: explica y deja guardar el registro sin ubicación', (t) async {
    gps.posicion = null;
    gps.ultima = null;
    await abrir(t);
    expect(find.textContaining('lugar abierto'), findsOneWidget);

    await llenarYGuardar(t);
    final r = (await t.runAsync(() => servicio.obtenerRegistrosDelLote('L1')))!.single;
    expect(r.confirmada, isTrue);
    expect([r.latitud, r.longitud], [null, null]);
  });

  testWidgets('permiso bloqueado: ofrece abrir los ajustes', (t) async {
    gps.permisoActual = LocationPermission.deniedForever;
    await abrir(t);
    expect(find.textContaining('bloqueado'), findsOneWidget);
    expect(find.text('Abrir ajustes'), findsOneWidget);
  });
}
