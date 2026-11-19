import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:alarmacacao5_0/data/cacao_database.dart';
import 'package:alarmacacao5_0/models/lote.dart';
import 'package:alarmacacao5_0/models/volteada.dart';
import 'package:alarmacacao5_0/screens/chat_screen.dart';
import 'package:alarmacacao5_0/screens/clima_screen.dart';
import 'package:alarmacacao5_0/screens/comparacion_lotes_screen.dart';
import 'package:alarmacacao5_0/screens/confirmar_volteada_screen.dart';
import 'package:alarmacacao5_0/screens/fotos_lote_screen.dart';
import 'package:alarmacacao5_0/services/chat_service.dart';
import 'package:alarmacacao5_0/services/clima_service.dart';
import 'package:alarmacacao5_0/services/foto_service.dart';
import 'package:alarmacacao5_0/services/location_service.dart';
import 'package:alarmacacao5_0/services/lote_service.dart';
import 'package:alarmacacao5_0/services/preferencias_app.dart';
import 'package:alarmacacao5_0/tema_app.dart';

/// Segunda parte de la auditoría de accesibilidad: registro de volteada, chat, clima, lista de fotos y comparación de
/// lotes (las otras pantallas están en `accesibilidad_pantallas_test.dart`). Mismas guías de Flutter: objetivos
/// táctiles de 48 dp, etiquetas y contraste, en 360×640, con tema normal y de alto contraste.
/// No reemplaza probar con TalkBack en un teléfono real.
class _Gps implements PlataformaUbicacion {
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

Future<void> _esperar(WidgetTester t) async {
  for (var i = 0; i < 14; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  sqfliteFfiInit();
  late Lote curso;
  late Directory tmp;

  Volteada v(String id, String lote, DateTime inicio, int horas, {double? t, double? h, bool ok = true}) => Volteada(
        id: id, loteId: lote, mensaje: 'Volteada a las $horas h', temperatura: t ?? 0, humedad: h ?? 0,
        observacion: ok ? 'Olor dulce' : '', fecha: inicio.add(Duration(hours: horas)),
        fechaProgramada: inicio.add(Duration(hours: horas)), confirmada: ok, notifId: ok ? 0 : 77,
      );

  setUpAll(() async {
    databaseFactory = databaseFactoryFfi;
    tmp = await Directory.systemTemp.createTemp('acc2_');
    await databaseFactoryFfi.setDatabasesPath(tmp.path);
    SharedPreferences.setMockInitialValues({'migrado_a_sqlite_v1': true});
    PreferenciasApp.instancia = PreferenciasApp();

    final ahora = DateTime.now();
    final inicio = ahora.subtract(const Duration(hours: 80));
    curso = Lote(
      id: 'curso', title: 'Lote Durania', status: 'en proceso', createdAt: inicio, inicioCiclo: inicio,
      finCiclo: inicio.add(const Duration(hours: 144)),
      volteadas: [
        v('c1', 'curso', inicio, 24, t: 38, h: 85),
        v('c2', 'curso', inicio, 48, t: 44, h: 82),
        v('c3', 'curso', inicio, 72, t: 47, h: 80),
        v('curso-p72', 'curso', inicio, 96, ok: false),
      ],
    );
    final servicio = LoteService();
    await servicio.addLote(curso);
    for (final (id, cal, temps) in [('l1', Calidad.regular, [31.0, 36.0]), ('l2', Calidad.excelente, [40.0, 46.0, 48.0])]) {
      final ini = ahora.subtract(const Duration(days: 20));
      await servicio.addLote(Lote(
        id: id, title: 'Lote $id', status: 'completado', createdAt: ini, inicioCiclo: ini,
        finCiclo: ini.add(const Duration(hours: 144)), calidadResultado: cal, observacionResultado: 'Observación de $id',
        volteadas: [for (var i = 0; i < temps.length; i++) v('$id-$i', id, ini, 24 * (i + 1), t: temps[i], h: 80)],
      ));
    }
  });

  tearDownAll(() async {
    await (await CacaoDatabase.instancia()).close();
    await tmp.delete(recursive: true);
  });

  setUp(() => SharedPreferences.setMockInitialValues({'migrado_a_sqlite_v1': true}));

  final sinRed = MockClient((_) async => throw http.ClientException('sin red'));

  final pantallas = <String, Widget Function()>{
    'Registro de volteada': () => ConfirmarVolteadaScreen(
          loteId: 'curso',
          volteadaId: 'curso-p72',
          ubicacion: LocationService(plataforma: _Gps(), consentimiento: () async => true),
          notificarAlerta: (_, __) async {},
        ),
    'Chat del lote': () => ChatScreen(lote: curso, chat: ChatService(cliente: sinRed, urlServidor: '')),
    'Clima': () => ClimaScreen(
          clima: ClimaService(cliente: sinRed),
          ubicacion: LocationService(plataforma: _Gps(), consentimiento: () async => true),
        ),
    'Lista de fotos': () => FotosLoteScreen(
          lote: curso,
          servicio: FotoService(cliente: sinRed, urlServidor: '', directorio: () async => tmp),
        ),
    'Comparación de lotes': () => const ComparacionLotesScreen(),
  };

  // Algo que SOLO aparece cuando la pantalla terminó de cargar (si no, se auditaría un círculo de espera).
  final contenido = <String, String>{
    'Registro de volteada': 'Confirmar volteada',
    'Chat del lote': 'Es una guía, no reemplaza al técnico.',
    'Clima': 'Clima del lugar',
    'Lista de fotos': 'Nueva foto',
    'Comparación de lotes': 'Lote l2',
  };

  for (final alto in [false, true]) {
    final tema = alto ? 'alto contraste' : 'tema normal';
    pantallas.forEach((nombre, crear) {
      group('$nombre ($tema)', () {
        Future<void> abrir(WidgetTester t) async {
          t.view.physicalSize = const Size(360, 640);
          t.view.devicePixelRatio = 1.0;
          addTearDown(t.view.reset);
          await t.pumpWidget(MaterialApp(theme: TemaApp.construir(altoContraste: alto), home: crear()));
          await _esperar(t);
          expect(find.textContaining(contenido[nombre]!), findsWidgets, reason: '$nombre no terminó de cargar');
        }

        testWidgets('objetivos táctiles de 48 dp', (t) async {
          final h = t.ensureSemantics();
          await abrir(t);
          await expectLater(t, meetsGuideline(androidTapTargetGuideline));
          h.dispose();
        });

        testWidgets('todo lo que se toca tiene etiqueta', (t) async {
          final h = t.ensureSemantics();
          await abrir(t);
          await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
          h.dispose();
        });

        testWidgets('contraste del texto', (t) async {
          final h = t.ensureSemantics();
          await abrir(t);
          await expectLater(t, meetsGuideline(textContrastGuideline));
          h.dispose();
        });
      });
    });
  }
}
