import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:alarmacacao5_0/screens/permisos_screen.dart';
import 'package:alarmacacao5_0/services/location_service.dart';

Position _pos(double lat, double lng, {double precision = 8, DateTime? momento}) => Position(
      latitude: lat, longitude: lng, timestamp: momento ?? DateTime(2026, 11, 18, 10), accuracy: precision,
      altitude: 0, altitudeAccuracy: 0, heading: 0, headingAccuracy: 0, speed: 0, speedAccuracy: 0,
    );

class _Falsa implements PlataformaUbicacion {
  bool gpsEncendido = true;
  LocationPermission permisoActual = LocationPermission.whileInUse;
  LocationPermission alPedir = LocationPermission.whileInUse;
  Object? errorPosicion; // si no es null, posicionActual lo lanza
  Position? posicion;
  Position? ultima;
  Object? errorUltima;
  int llamadasPosicion = 0, llamadasPedir = 0;
  Duration? limiteRecibido;

  @override
  Future<bool> servicioActivado() async => gpsEncendido;
  @override
  Future<LocationPermission> permiso() async => permisoActual;
  @override
  Future<LocationPermission> pedirPermiso() async {
    llamadasPedir++;
    return permisoActual = alPedir;
  }

  @override
  Future<Position> posicionActual(Duration limite) async {
    llamadasPosicion++;
    limiteRecibido = limite;
    if (errorPosicion != null) throw errorPosicion!;
    return posicion!;
  }

  @override
  Future<Position?> ultimaConocida() async {
    if (errorUltima != null) throw errorUltima!;
    return ultima;
  }
}

void main() {
  late _Falsa plataforma;
  late LocationService servicio;

  setUp(() {
    plataforma = _Falsa()..posicion = _pos(7.6031, -72.6012);
    servicio = LocationService(plataforma: plataforma);
  });

  group('asegurarPermiso', () {
    test('con GPS encendido y permiso: no hace nada y NO pide posición', () async {
      await servicio.asegurarPermiso();
      expect(plataforma.llamadasPosicion, 0, reason: 'el arranque de la app no debe esperar un fix de GPS');
    });

    test('GPS apagado: mensaje claro', () async {
      plataforma.gpsEncendido = false;
      expect(
        servicio.asegurarPermiso(),
        throwsA(isA<UbicacionException>().having((e) => e.mensaje, 'mensaje', contains('GPS está apagado'))),
      );
    });

    test('permiso denegado: lo pide y, si lo conceden, sigue', () async {
      plataforma.permisoActual = LocationPermission.denied;
      plataforma.alPedir = LocationPermission.whileInUse;
      await servicio.asegurarPermiso();
      expect(plataforma.llamadasPedir, 1);
    });

    test('permiso denegado y se vuelve a negar: error sin abrir ajustes', () async {
      plataforma.permisoActual = LocationPermission.denied;
      plataforma.alPedir = LocationPermission.denied;
      await expectLater(
        servicio.asegurarPermiso(),
        throwsA(isA<UbicacionException>()
            .having((e) => e.mensaje, 'mensaje', contains('No se dio permiso'))
            .having((e) => e.abrirAjustes, 'abrirAjustes', isFalse)),
      );
    });

    test('permiso bloqueado para siempre: indica abrir los ajustes y no vuelve a pedir', () async {
      plataforma.permisoActual = LocationPermission.deniedForever;
      await expectLater(
        servicio.asegurarPermiso(),
        throwsA(isA<UbicacionException>().having((e) => e.abrirAjustes, 'abrirAjustes', isTrue)),
      );
      expect(plataforma.llamadasPedir, 0);
    });
  });

  group('obtener', () {
    test('devuelve latitud, longitud y precisión del GPS (sin internet)', () async {
      final u = await servicio.obtener();
      expect([u.latitud, u.longitud], [7.6031, -72.6012]);
      expect(u.precisionMetros, 8);
      expect(u.esUltimaConocida, isFalse);
    });

    test('espera como máximo 30 s al GPS', () async {
      await servicio.obtener();
      expect(plataforma.limiteRecibido, const Duration(seconds: 30));
    });

    test('precisión 0 (desconocida) se informa como null', () async {
      plataforma.posicion = _pos(1, 2, precision: 0);
      expect((await servicio.obtener()).precisionMetros, isNull);
    });

    test('si el GPS tarda demasiado, usa la última posición y lo marca', () async {
      plataforma.errorPosicion = TimeoutException('sin fix');
      plataforma.ultima = _pos(7.7, -72.7, momento: DateTime(2026, 11, 18, 6));
      final u = await servicio.obtener();
      expect([u.latitud, u.longitud], [7.7, -72.7]);
      expect(u.esUltimaConocida, isTrue);
      expect(u.hace(DateTime(2026, 11, 18, 8)), 'hace 2 h');
    });

    test('sin posición nueva ni última conocida: error claro', () async {
      plataforma.errorPosicion = TimeoutException('sin fix');
      plataforma.ultima = null;
      await expectLater(
        servicio.obtener(),
        throwsA(isA<UbicacionException>().having((e) => e.mensaje, 'mensaje', contains('lugar abierto'))),
      );
    });

    test('si hasta leer la última posición falla, el error sigue siendo claro (no se escapa la excepción cruda)', () async {
      plataforma.errorPosicion = StateError('x');
      plataforma.errorUltima = StateError('y');
      await expectLater(servicio.obtener(), throwsA(isA<UbicacionException>()));
    });

    test('sin permiso no llega a pedir posición', () async {
      plataforma.permisoActual = LocationPermission.deniedForever;
      await expectLater(servicio.obtener(), throwsA(isA<UbicacionException>()));
      expect(plataforma.llamadasPosicion, 0);
    });
  });

  group('UbicacionObtenida.hace', () {
    final ahora = DateTime(2026, 11, 18, 12);
    String? hace(Duration d) => UbicacionObtenida(latitud: 0, longitud: 0, momento: ahora.subtract(d)).hace(ahora);

    test('formatos', () {
      expect(hace(const Duration(seconds: 20)), 'hace un momento');
      expect(hace(const Duration(minutes: 5)), 'hace 5 min');
      expect(hace(const Duration(hours: 3)), 'hace 3 h');
      expect(hace(const Duration(days: 1)), 'hace 1 día');
      expect(hace(const Duration(days: 4)), 'hace 4 días');
    });

    test('sin momento no inventa una antigüedad', () {
      expect(const UbicacionObtenida(latitud: 0, longitud: 0).hace(ahora), isNull);
    });
  });

  group('PermisosScreen (primera pantalla de la app)', () {
    Widget pantalla() => MaterialApp(
          home: PermisosScreen(ubicacion: servicio, siguiente: (_) => const Scaffold(body: Text('PANTALLA PRINCIPAL'))),
        );

    testWidgets('con permiso: lo dice, NO espera un fix de GPS y pasa sola a la pantalla principal', (t) async {
      await t.pumpWidget(pantalla());
      await t.pump();
      expect(find.text('Permiso de ubicación listo.'), findsOneWidget);
      expect(plataforma.llamadasPosicion, 0);
      expect(find.text('PANTALLA PRINCIPAL'), findsNothing);

      await t.pumpAndSettle(const Duration(seconds: 2));
      expect(find.text('PANTALLA PRINCIPAL'), findsOneWidget);
    });

    testWidgets('sin permiso: avisa que la app sirve igual y ofrece continuar', (t) async {
      plataforma.permisoActual = LocationPermission.denied;
      plataforma.alPedir = LocationPermission.denied;
      await t.pumpWidget(pantalla());
      await t.pump();
      expect(find.textContaining('La app sirve igual'), findsOneWidget);
      expect(find.text('Continuar sin ubicación'), findsOneWidget);
      expect(find.text('Abrir ajustes'), findsNothing);
    });

    testWidgets('permiso bloqueado: ofrece abrir los ajustes', (t) async {
      plataforma.permisoActual = LocationPermission.deniedForever;
      await t.pumpWidget(pantalla());
      await t.pump();
      expect(find.text('Abrir ajustes'), findsOneWidget);
    });
  });
}
