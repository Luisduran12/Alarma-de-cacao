import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:alarmacacao5_0/data/cacao_database.dart';
import 'package:alarmacacao5_0/models/lote.dart';
import 'package:alarmacacao5_0/models/volteada.dart';
import 'package:alarmacacao5_0/screens/ajustes_screen.dart';
import 'package:alarmacacao5_0/screens/ayuda_screen.dart';
import 'package:alarmacacao5_0/screens/creditos_screen.dart';
import 'package:alarmacacao5_0/screens/detalle_lote_screen.dart';
import 'package:alarmacacao5_0/models/analisis_foto.dart';
import 'package:alarmacacao5_0/screens/guia_prueba_corte_screen.dart';
import 'package:alarmacacao5_0/screens/permisos_screen.dart';
import 'package:alarmacacao5_0/screens/resultado_foto_screen.dart';
import 'package:alarmacacao5_0/screens/politica_screen.dart';
import 'package:alarmacacao5_0/services/alarm_scheduler.dart';
import 'package:alarmacacao5_0/services/lote_service.dart';
import 'package:alarmacacao5_0/services/preferencias_app.dart';
import 'package:alarmacacao5_0/services/recordatorio_service.dart';
import 'package:alarmacacao5_0/tema_app.dart';
import 'package:alarmacacao5_0/data/base_conocimiento.dart';
import 'dart:io';

/// Auditoría con las guías de accesibilidad que trae Flutter (equivalen a lo que revisa WCAG 2.1 AA para móvil):
///  - objetivos táctiles de al menos 48 × 48 dp (Android),
///  - todo lo que se toca tiene una etiqueta que un lector de pantalla pueda leer,
///  - contraste del texto de al menos 4,5:1 (3:1 en texto grande).
/// Se prueba en teléfono pequeño (360 × 640), con el tema normal y el de alto contraste.
/// NO reemplaza probar con TalkBack en un teléfono real (eso no se ha hecho).
Future<void> _esperar(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  sqfliteFfiInit();
  late Database db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PreferenciasApp.instancia = PreferenciasApp();
    db = await CacaoDatabase.abrir(databaseFactoryFfi, inMemoryDatabasePath);
  });
  tearDown(() => db.close());

  Lote lote() {
    final inicio = DateTime.now().subtract(const Duration(hours: 30));
    return Lote(
      id: 'L1', title: 'Lote Durania', status: 'en proceso', createdAt: inicio, inicioCiclo: inicio,
      finCiclo: inicio.add(const Duration(hours: 144)),
      volteadas: [
        Volteada(
          id: 'V1', loteId: 'L1', mensaje: 'Volteada 1', temperatura: 44, humedad: 80, observacion: 'Olor dulce',
          fecha: inicio.add(const Duration(hours: 24)), fechaProgramada: inicio.add(const Duration(hours: 24)),
          confirmada: true, notifId: 0,
        ),
        Volteada(
          id: 'V2', loteId: 'L1', mensaje: 'Volteada 2', temperatura: 0, humedad: 0, observacion: '',
          fecha: inicio, fechaProgramada: inicio.add(const Duration(hours: 48)), confirmada: false, notifId: 5,
        ),
      ],
    );
  }

  final base = BaseConocimiento.desdeJson(File('assets/conocimiento/base.json').readAsStringSync());

  Map<String, Widget Function()> pantallas() {
    final lotes = LoteService(database: () async => db, cancelarNotificacion: (_) async {});
    return {
      'Ajustes': () => const AjustesScreen(),
      'Política': () => const PoliticaScreen(),
      'Créditos': () => const CreditosScreen(),
      'Ayuda': () => AyudaScreen(cargar: () async => base),
      'Guía de la prueba de corte': () => const GuiaPruebaCorteScreen(),
      'Resultado de foto (con error)': () => ResultadoFotoScreen(
            analisis: AnalisisFoto(
              id: 'f1',
              loteId: 'L1',
              modo: ModoAnalisis.corte,
              ruta: '/no/existe.jpg',
              estado: EstadoAnalisis.error,
              creadoEn: DateTime(2026, 11, 18),
              ultimoError: 'La foto salió borrosa. Tome otra con más luz.',
            ),
          ),
      'Permisos (pregunta de ubicación)': () => PermisosScreen(leerConsentimiento: () async => null),
      'Detalle del lote': () => DetalleLoteScreen(
            lote: lote(),
            loteService: lotes,
            scheduler: AlarmScheduler(
              loteService: lotes,
              recordatorioService: RecordatorioService(database: () async => db, cancelarNotificacion: (_) async {}),
              siguienteId: () async => 1,
              programar: ({required id, required titulo, required cuerpo, required fechaProgramada, payload, esRecordatorio = false}) async {},
            ),
          ),
    };
  }

  for (final alto in [false, true]) {
    final tema = alto ? 'alto contraste' : 'tema normal';
    for (final e in pantallas().entries) {
      group('${e.key} ($tema)', () {
        Future<void> abrir(WidgetTester t) async {
          t.view.physicalSize = const Size(360, 640);
          t.view.devicePixelRatio = 1.0;
          addTearDown(t.view.reset);
          await t.pumpWidget(MaterialApp(theme: TemaApp.construir(altoContraste: alto), home: e.value()));
          await _esperar(t);
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
    }
  }
}
