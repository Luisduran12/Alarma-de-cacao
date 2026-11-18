import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alarmacacao5_0/data/guia_prueba_corte.dart';
import 'package:alarmacacao5_0/screens/guia_prueba_corte_screen.dart';
import 'package:alarmacacao5_0/widgets/ilustraciones_corte.dart';

void _pantallaGrande(WidgetTester t) {
  t.view.physicalSize = const Size(800, 7000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

void main() {
  group('contenido de la guía', () {
    test('8 pasos numerados en orden, cada uno con su fuente', () {
      expect(GuiaPruebaCorte.pasos.map((p) => p.numero), [1, 2, 3, 4, 5, 6, 7, 8]);
      for (final p in GuiaPruebaCorte.pasos) {
        expect(p.fuente, anyOf(contains('FHIA'), contains('La Salle')), reason: 'paso ${p.numero}');
        expect(p.texto.trim(), isNotEmpty);
        expect(p.titulo.trim(), isNotEmpty);
      }
    });

    test('los 7 grupos son los que lista la fuente', () {
      expect(GuiaPruebaCorte.grupos, hasLength(7));
      expect(GuiaPruebaCorte.grupos, containsAll(['Bien fermentados', 'Pizarrosos', 'Mohosos', 'Pasilla']));
    });

    test('no se cuelan cifras de fuentes no verificadas (65 %, 300 granos, 30 granos, 50 granos)', () {
      final todo = [
        for (final p in GuiaPruebaCorte.pasos) '${p.titulo} ${p.texto}',
        GuiaPruebaCorte.avisoGrupos,
      ].join(' ');
      for (final prohibido in ['65 %', '300 granos', '30 granos', '50 granos', '10 granos', '25 granos']) {
        expect(todo.contains(prohibido), isFalse, reason: '"$prohibido" no está respaldado por un documento leído');
      }
    });

    test('lo no verificado está declarado y el aviso de la NTC 1252 es explícito', () {
      expect(GuiaPruebaCorte.noVerificado, isNotEmpty);
      expect(GuiaPruebaCorte.avisoNtc, contains('NTC 1252'));
      expect(GuiaPruebaCorte.avisoNtc, contains('no incluye el texto de la norma'));
      expect(GuiaPruebaCorte.avisoGuia, 'Es una guía, no reemplaza al técnico.');
    });

    test('las ilustraciones solo están en los pasos que las necesitan', () {
      final con = GuiaPruebaCorte.pasos.where((p) => p.ilustracion != TipoIlustracion.ninguna).map((p) => p.numero);
      expect(con, [2, 3, 5, 7]);
    });
  });

  group('pantalla', () {
    testWidgets('muestra todos los pasos con su fuente y los avisos', (t) async {
      _pantallaGrande(t);
      await t.pumpWidget(const MaterialApp(home: GuiaPruebaCorteScreen()));
      for (final p in GuiaPruebaCorte.pasos) {
        expect(find.text(p.titulo), findsOneWidget, reason: p.titulo);
        expect(find.text(p.texto), findsOneWidget);
      }
      expect(find.textContaining('Fuente: FHIA'), findsWidgets);
      expect(find.textContaining('NTC 1252'), findsOneWidget);
      expect(find.text('Es una guía, no reemplaza al técnico.'), findsOneWidget);
      for (final g in GuiaPruebaCorte.grupos) {
        expect(find.text(g), findsOneWidget);
      }
    });

    testWidgets('sin lote no ofrece registrar datos', (t) async {
      _pantallaGrande(t);
      await t.pumpWidget(const MaterialApp(home: GuiaPruebaCorteScreen()));
      expect(find.text('Registrar los datos del lote'), findsNothing);
    });

    testWidgets('abierta desde el aviso de un lote ofrece registrar los datos', (t) async {
      _pantallaGrande(t);
      await t.pumpWidget(const MaterialApp(home: GuiaPruebaCorteScreen(loteId: 'L1', volteadaId: 'V1')));
      expect(find.text('Registrar los datos del lote'), findsOneWidget);
    });

    testWidgets('dibuja las 4 ilustraciones, cada una con su descripción accesible', (t) async {
      _pantallaGrande(t);
      final h = t.ensureSemantics();
      await t.pumpWidget(const MaterialApp(home: GuiaPruebaCorteScreen()));
      expect(find.byType(IlustracionCorte), findsNWidgets(4));
      for (final tipo in [TipoIlustracion.muestreo, TipoIlustracion.corte, TipoIlustracion.conteo, TipoIlustracion.temperatura]) {
        expect(find.bySemanticsLabel(IlustracionCorte.descripcion(tipo)), findsOneWidget, reason: '$tipo');
      }
      h.dispose();
    });
  });

  group('IlustracionCorte', () {
    for (final tipo in TipoIlustracion.values) {
      testWidgets('$tipo se dibuja sin errores en tema claro y oscuro', (t) async {
        for (final brillo in [Brightness.light, Brightness.dark]) {
          await t.pumpWidget(MaterialApp(
            theme: ThemeData(brightness: brillo, colorSchemeSeed: Colors.brown, useMaterial3: true),
            home: Scaffold(body: IlustracionCorte(tipo: tipo)),
          ));
          expect(t.takeException(), isNull);
        }
      });
    }

    testWidgets('"ninguna" no ocupa espacio', (t) async {
      await t.pumpWidget(const MaterialApp(home: Scaffold(body: IlustracionCorte(tipo: TipoIlustracion.ninguna))));
      expect(t.getSize(find.byType(IlustracionCorte)).height, 0);
    });
  });
}
