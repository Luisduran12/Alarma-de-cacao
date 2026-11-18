import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:alarmacacao5_0/data/cacao_database.dart';
import 'package:alarmacacao5_0/models/lote.dart';
import 'package:alarmacacao5_0/models/volteada.dart';
import 'package:alarmacacao5_0/screens/confirmar_volteada_screen.dart';
import 'package:alarmacacao5_0/screens/reglas_alerta_screen.dart';
import 'package:alarmacacao5_0/services/lote_service.dart';
import 'package:alarmacacao5_0/services/reglas_alerta.dart';
import 'package:alarmacacao5_0/widgets/editar_regla_dialog.dart';

/// Las operaciones de SQLite son asíncronas de verdad y, con el reloj falso de
/// las pruebas, cada `await` encadenado necesita su propia vuelta de espera real
/// seguida de un `pump`. Se alternan varias veces.
Future<void> _esperar(WidgetTester t) async {
  for (var i = 0; i < 10; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await t.pump(const Duration(milliseconds: 50));
  }
}

void _pantallaGrande(WidgetTester t) {
  t.view.physicalSize = const Size(800, 2200);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

/// [conCarga]: la pantalla muestra un indicador de carga animado mientras lee la
/// base de datos, así que `pumpAndSettle` no terminaría nunca.
Future<void> _abrirDesdeBoton(WidgetTester t, Widget pantalla, {bool conCarga = false}) async {
  await t.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => pantalla)),
            child: const Text('abrir'),
          ),
        ),
      ),
    ),
  ));
  await t.tap(find.text('abrir'));
  if (conCarga) {
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
  } else {
    await t.pumpAndSettle();
  }
}

void main() {
  sqfliteFfiInit();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('EditarReglaDialog', () {
    const nueva = ReglaAlerta(id: 'mia_1', variable: VariableMedida.temperatura, mensaje: '', fuente: '');

    Future<ReglaAlerta?> abrir(WidgetTester t, {ReglaAlerta regla = nueva}) async {
      ReglaAlerta? r;
      var cerro = false;
      await t.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                r = await showDialog<ReglaAlerta>(context: context, builder: (_) => EditarReglaDialog(regla: regla));
                cerro = true;
              },
              child: const Text('abrir'),
            ),
          ),
        ),
      ));
      await t.tap(find.text('abrir'));
      await t.pumpAndSettle();
      addTearDown(() => cerro);
      return r;
    }

    testWidgets('sin ningún límite no deja guardar', (t) async {
      _pantallaGrande(t);
      await abrir(t);
      await t.tap(find.text('Guardar'));
      await t.pumpAndSettle();
      expect(find.textContaining('al menos un límite'), findsOneWidget);
    });

    testWidgets('mínimo mayor que máximo se rechaza', (t) async {
      _pantallaGrande(t);
      await abrir(t);
      await t.enterText(find.widgetWithText(TextField, 'Mínimo'), '50');
      await t.enterText(find.widgetWithText(TextField, 'Máximo'), '40');
      await t.tap(find.text('Guardar'));
      await t.pumpAndSettle();
      expect(find.textContaining('mínimo no puede ser mayor'), findsOneWidget);
    });

    testWidgets('sin fuente no deja guardar: toda regla lleva fuente', (t) async {
      _pantallaGrande(t);
      await abrir(t);
      await t.enterText(find.widgetWithText(TextField, 'Mínimo'), '40');
      await t.enterText(find.widgetWithText(TextField, 'Qué debe hacer'), 'Revise el volteo');
      await t.tap(find.text('Guardar'));
      await t.pumpAndSettle();
      expect(find.textContaining('Anote la fuente'), findsOneWidget);
    });

    testWidgets('texto que no es número se rechaza', (t) async {
      _pantallaGrande(t);
      await abrir(t);
      await t.enterText(find.widgetWithText(TextField, 'Mínimo'), 'abc');
      await t.tap(find.text('Guardar'));
      await t.pumpAndSettle();
      expect(find.textContaining('solo números'), findsOneWidget);
    });

    testWidgets('con todo completo devuelve la regla (coma decimal incluida)', (t) async {
      _pantallaGrande(t);
      ReglaAlerta? r;
      await t.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async => r = await showDialog<ReglaAlerta>(
                  context: context, builder: (_) => const EditarReglaDialog(regla: nueva)),
              child: const Text('abrir'),
            ),
          ),
        ),
      ));
      await t.tap(find.text('abrir'));
      await t.pumpAndSettle();
      await t.enterText(find.widgetWithText(TextField, 'Mínimo'), '4,5');
      await t.enterText(find.widgetWithText(TextField, 'Desde la hora del lote (opcional)'), '24');
      await t.enterText(find.widgetWithText(TextField, 'Qué debe hacer'), 'Revise el cajón');
      await t.enterText(find.widgetWithText(TextField, 'Fuente de la regla'), 'Técnico de la asociación');
      await t.tap(find.text('Guardar'));
      await t.pumpAndSettle();

      expect(r, isNotNull);
      expect([r!.minimo, r!.maximo, r!.desdeHora], [4.5, null, 24.0]);
      expect(r!.fuente, 'Técnico de la asociación');
      expect(r!.id, 'mia_1');
    });
  });

  group('ReglasAlertaScreen', () {
    testWidgets('muestra las reglas de fábrica, cada una con su fuente', (t) async {
      _pantallaGrande(t);
      await t.pumpWidget(const MaterialApp(home: ReglasAlertaScreen()));
      await t.pumpAndSettle();
      expect(find.textContaining('Fuente: FHIA'), findsOneWidget);
      expect(find.textContaining('Fuente: Universidad de La Salle'), findsOneWidget);
      expect(find.textContaining('Es una guía, no reemplaza al técnico'), findsOneWidget);
    });

    testWidgets('apagar una regla se guarda en el teléfono', (t) async {
      _pantallaGrande(t);
      await t.pumpWidget(const MaterialApp(home: ReglasAlertaScreen()));
      await t.pumpAndSettle();
      await t.tap(find.byType(Switch).first);
      await t.pumpAndSettle();
      final guardadas = await t.runAsync(ReglasAlertaStorage.cargar);
      expect(guardadas!.first.activa, isFalse);
      expect(guardadas.last.activa, isTrue);
    });

    testWidgets('borrar y restaurar devuelve las de fábrica', (t) async {
      _pantallaGrande(t);
      await t.pumpWidget(const MaterialApp(home: ReglasAlertaScreen()));
      await t.pumpAndSettle();
      await t.tap(find.text('Borrar').first);
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'Borrar'));
      await t.pumpAndSettle();
      expect(find.byType(Switch), findsOneWidget);

      await t.tap(find.byTooltip('Restaurar reglas'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'Restaurar'));
      await t.pumpAndSettle();
      expect(find.byType(Switch), findsNWidgets(2));
    });

    testWidgets('agregar una regla propia la deja en la lista', (t) async {
      _pantallaGrande(t);
      await t.pumpWidget(const MaterialApp(home: ReglasAlertaScreen()));
      await t.pumpAndSettle();
      await t.tap(find.text('Agregar regla'));
      await t.pumpAndSettle();
      await t.enterText(find.widgetWithText(TextField, 'Máximo'), '90');
      await t.enterText(find.widgetWithText(TextField, 'Qué debe hacer'), 'Ventile el cajón');
      await t.enterText(find.widgetWithText(TextField, 'Fuente de la regla'), 'Mi técnico');
      await t.tap(find.text('Guardar'));
      await t.pumpAndSettle();
      expect(find.byType(Switch), findsNWidgets(3));
      expect(find.textContaining('Fuente: Mi técnico'), findsOneWidget);
    });
  });

  group('guardar un registro evalúa las alertas', () {
    late Database db;
    late LoteService servicio;
    late List<(String, String)> avisos;

    setUp(() async {
      db = await CacaoDatabase.abrir(databaseFactoryFfi, inMemoryDatabasePath);
      servicio = LoteService(database: () async => db, cancelarNotificacion: (_) async {});
      avisos = [];
      final inicio = DateTime.now().subtract(const Duration(hours: 72));
      await servicio.addLote(Lote(
        id: 'L1', title: 'Lote Durania', status: 'en proceso', createdAt: inicio, inicioCiclo: inicio,
        finCiclo: inicio.add(const Duration(hours: 144)),
        volteadas: [
          Volteada(
            id: 'V1', loteId: 'L1', mensaje: 'Volteada 2', temperatura: 0, humedad: 0, observacion: '',
            fecha: inicio, fechaProgramada: DateTime.now(), confirmada: false,
          ),
        ],
      ));
    });

    tearDown(() => db.close());

    ConfirmarVolteadaScreen pantalla({Future<void> Function(String, String)? notificar}) => ConfirmarVolteadaScreen(
          loteId: 'L1',
          volteadaId: 'V1',
          loteService: servicio,
          notificarAlerta: notificar ?? (t, c) async => avisos.add((t, c)),
        );

    Future<void> llenarYGuardar(WidgetTester t, {required String temp}) async {
      final campos = find.byType(TextFormField);
      await t.enterText(campos.at(0), temp);
      await t.enterText(campos.at(1), '80');
      await t.enterText(campos.at(5), 'Olor a vinagre');
      await t.tap(find.text('Guardar datos'));
      // No `pumpAndSettle`: mientras el aviso está abierto, el botón sigue mostrando su progreso animado.
      await _esperar(t);
    }

    testWidgets('masa fría a las 72 h: avisa en pantalla, notifica y guarda el registro', (t) async {
      _pantallaGrande(t);
      await _abrirDesdeBoton(t, pantalla(), conCarga: true);
      await _esperar(t);
      await llenarYGuardar(t, temp: '41,5');

      expect(find.text('Atención: un valor fuera de rango'), findsOneWidget);
      expect(find.textContaining('41,5 °C, por debajo de 45 °C'), findsOneWidget);
      expect(find.textContaining('Fuente: FHIA'), findsOneWidget);
      expect(find.textContaining('Es una guía, no reemplaza al técnico'), findsOneWidget);
      expect(avisos, hasLength(1));
      expect(avisos.single.$1, 'Alerta - Lote Durania');
      expect(avisos.single.$2, contains('41,5 °C'));

      await t.tap(find.text('Entendido'));
      await _esperar(t);
      await t.pumpAndSettle();
      final guardado = (await t.runAsync(() => servicio.obtenerRegistrosDelLote('L1')))!.single;
      expect(guardado.confirmada, isTrue);
      expect(guardado.temperatura, 41.5);
    });

    testWidgets('temperatura normal: no hay aviso ni notificación', (t) async {
      _pantallaGrande(t);
      await _abrirDesdeBoton(t, pantalla(), conCarga: true);
      await _esperar(t);
      await llenarYGuardar(t, temp: '47');

      expect(find.textContaining('fuera de rango'), findsNothing);
      expect(avisos, isEmpty);
      final guardado = (await t.runAsync(() => servicio.obtenerRegistrosDelLote('L1')))!.single;
      expect(guardado.confirmada, isTrue);
    });

    testWidgets('si la notificación falla, el aviso en pantalla y el guardado siguen', (t) async {
      _pantallaGrande(t);
      await _abrirDesdeBoton(t, pantalla(notificar: (_, __) async => throw StateError('sin permiso')), conCarga: true);
      await _esperar(t);
      await llenarYGuardar(t, temp: '40');

      expect(find.text('Atención: un valor fuera de rango'), findsOneWidget);
      await t.tap(find.text('Entendido'));
      await _esperar(t);
      await t.pumpAndSettle();
      final guardado = (await t.runAsync(() => servicio.obtenerRegistrosDelLote('L1')))!.single;
      expect(guardado.temperatura, 40);
    });

    testWidgets('con las reglas apagadas no avisa', (t) async {
      _pantallaGrande(t);
      final apagadas = [for (final r in reglasDeFabrica()) r.copyWith(activa: false)];
      await _abrirDesdeBoton(
        t,
        ConfirmarVolteadaScreen(
          loteId: 'L1', volteadaId: 'V1', loteService: servicio,
          cargarReglas: () async => apagadas,
          notificarAlerta: (t, c) async => avisos.add((t, c)),
        ),
        conCarga: true,
      );
      await _esperar(t);
      await llenarYGuardar(t, temp: '30');
      expect(find.textContaining('fuera de rango'), findsNothing);
      expect(avisos, isEmpty);
    });
  });
}
