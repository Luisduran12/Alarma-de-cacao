import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alarmacacao5_0/models/lote.dart';
import 'package:alarmacacao5_0/models/volteada.dart';
import 'package:alarmacacao5_0/services/curva_ideal.dart';
import 'package:alarmacacao5_0/widgets/editor_curva_ideal_dialog.dart';
import 'package:alarmacacao5_0/widgets/selector_lote_dialog.dart';

/// Abre el diálogo desde un botón y devuelve lo que el usuario eligió.
Future<void> _abrir<T>(WidgetTester t, Widget dialogo, void Function(T?) alCerrar) async {
  await t.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () async => alCerrar(await showDialog<T>(context: context, builder: (_) => dialogo)),
            child: const Text('abrir'),
          ),
        ),
      ),
    ),
  ));
  await t.tap(find.text('abrir'));
  await t.pumpAndSettle();
}

Lote _lote(String id, int confirmados) => Lote(
      id: id,
      title: 'Lote $id',
      status: 'en proceso',
      createdAt: DateTime(2026, 1, 1),
      volteadas: [
        for (var i = 0; i < confirmados; i++)
          Volteada(
            id: '$id$i', loteId: id, mensaje: '', temperatura: 40, humedad: 80, observacion: '',
            fecha: DateTime(2026, 1, 1 + i), fechaProgramada: DateTime(2026, 1, 1 + i), confirmada: true,
          ),
      ],
    );

void main() {
  group('EditorCurvaIdealDialog', () {
    testWidgets('escribir dos puntos y guardar devuelve la curva', (t) async {
      CurvaIdeal? r;
      await _abrir<CurvaIdeal>(t, const EditorCurvaIdealDialog(inicial: CurvaIdeal.vacia), (v) => r = v);
      final campos = find.byType(TextField);
      await t.enterText(campos.at(0), '48');
      await t.enterText(campos.at(1), '45,5'); // coma decimal
      await t.tap(find.text('Agregar punto'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).at(2), '72');
      await t.enterText(find.byType(TextField).at(3), '49');
      await t.tap(find.text('Guardar'));
      await t.pumpAndSettle();

      expect(r!.puntos.map((p) => [p.horas, p.temperatura]), [
        [48.0, 45.5], [72.0, 49.0],
      ]);
    });

    testWidgets('una fila a medias muestra el error y no cierra', (t) async {
      CurvaIdeal? r;
      var cerro = false;
      await _abrir<CurvaIdeal>(t, const EditorCurvaIdealDialog(inicial: CurvaIdeal.vacia), (v) {
        r = v;
        cerro = true;
      });
      await t.enterText(find.byType(TextField).at(0), '48'); // falta la temperatura
      await t.tap(find.text('Guardar'));
      await t.pumpAndSettle();

      expect(find.textContaining('necesita la hora y la temperatura'), findsOneWidget);
      expect(cerro, isFalse);
      expect(r, isNull);
    });

    testWidgets('temperatura fuera de -10..80 °C se rechaza', (t) async {
      await _abrir<CurvaIdeal>(t, const EditorCurvaIdealDialog(inicial: CurvaIdeal.vacia), (_) {});
      await t.enterText(find.byType(TextField).at(0), '48');
      await t.enterText(find.byType(TextField).at(1), '95');
      await t.tap(find.text('Guardar'));
      await t.pumpAndSettle();
      expect(find.textContaining('entre -10 y 80'), findsOneWidget);
    });

    testWidgets('sin escribir nada guarda una curva vacía (no inventa puntos)', (t) async {
      CurvaIdeal? r;
      await _abrir<CurvaIdeal>(t, const EditorCurvaIdealDialog(inicial: CurvaIdeal.vacia), (v) => r = v);
      await t.tap(find.text('Guardar'));
      await t.pumpAndSettle();
      expect(r!.estaVacia, isTrue);
    });

    testWidgets('"Borrar curva" solo aparece si ya había una y devuelve vacía', (t) async {
      CurvaIdeal? r;
      final con = CurvaIdeal(const [PuntoIdeal(48, 45)]);
      await _abrir<CurvaIdeal>(t, EditorCurvaIdealDialog(inicial: con), (v) => r = v);
      expect(find.text('48'), findsOneWidget, reason: 'muestra el punto guardado');
      await t.tap(find.text('Borrar curva'));
      await t.pumpAndSettle();
      expect(r!.estaVacia, isTrue);

      await _abrir<CurvaIdeal>(t, const EditorCurvaIdealDialog(inicial: CurvaIdeal.vacia), (_) {});
      expect(find.text('Borrar curva'), findsNothing);
    });

    testWidgets('Cancelar devuelve null', (t) async {
      CurvaIdeal? r = CurvaIdeal.vacia;
      await _abrir<CurvaIdeal>(t, const EditorCurvaIdealDialog(inicial: CurvaIdeal.vacia), (v) => r = v);
      await t.tap(find.text('Cancelar'));
      await t.pumpAndSettle();
      expect(r, isNull);
    });
  });

  group('SelectorLoteDialog', () {
    testWidgets('solo ofrece lotes con al menos 2 registros confirmados', (t) async {
      Lote? r;
      await _abrir<Lote>(t, SelectorLoteDialog(lotes: [_lote('A', 3), _lote('B', 1), _lote('C', 0)]), (v) => r = v);
      expect(find.text('Lote A'), findsOneWidget);
      expect(find.text('Lote B'), findsNothing);
      expect(find.text('Lote C'), findsNothing);
      await t.tap(find.text('Lote A'));
      await t.pumpAndSettle();
      expect(r!.id, 'A');
    });

    testWidgets('si no hay candidatos lo explica', (t) async {
      await _abrir<Lote>(t, SelectorLoteDialog(lotes: [_lote('B', 1)]), (_) {});
      expect(find.textContaining('No hay otros lotes'), findsOneWidget);
    });
  });
}
