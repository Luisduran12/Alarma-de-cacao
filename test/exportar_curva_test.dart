import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alarmacacao5_0/models/lote.dart';
import 'package:alarmacacao5_0/models/volteada.dart';
import 'package:alarmacacao5_0/services/curva_ideal.dart';
import 'package:alarmacacao5_0/services/exportar_curva.dart';
import 'package:alarmacacao5_0/widgets/curva_lote_chart.dart';

final _inicio = DateTime(2026, 1, 1, 8);

Volteada _reg(int i, {double temp = 46, String etapa = Etapa.fermentacion}) {
  final f = _inicio.add(Duration(hours: 50 + i * 3));
  return Volteada(
    id: 'r$i', loteId: 'l', mensaje: '', temperatura: temp + (i % 5), humedad: 80, observacion: '',
    fecha: f, fechaProgramada: f, confirmada: true, etapa: etapa, ph: 4.5, brix: 10, tempAmbiente: 26,
  );
}

Lote _lote({String titulo = 'Lote Durania'}) => Lote(
      id: 'l', title: titulo, status: 'en proceso', createdAt: _inicio,
      plantilla: 'fedecacao_144', calidadResultado: 'buena', observacionResultado: 'Corte 70 % bien fermentado',
    );

bool _esPng(Uint8List b) =>
    b.length > 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47;

/// Ancho y alto desde el encabezado IHDR del PNG.
(int, int) _dimensiones(Uint8List b) {
  final d = ByteData.sublistView(b);
  return (d.getUint32(16), d.getUint32(20));
}

void main() {
  group('PNG de la curva', () {
    testWidgets('captura la curva como un PNG válido y con tamaño', (t) async {
      final clave = GlobalKey();
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CurvaLoteChart(registros: [for (var i = 0; i < 6; i++) _reg(i)], inicio: _inicio, repaintKey: clave),
          ),
        ),
      ));
      final png = await t.runAsync(() => ExportarCurva.capturarPng(clave));
      expect(_esPng(png!), isTrue);
      final (ancho, alto) = _dimensiones(png);
      expect(ancho, greaterThan(300));
      expect(alto, greaterThan(300), reason: 'dos gráficas apiladas y la leyenda');
    });

    testWidgets('si la curva no está en pantalla, avisa con un error claro', (t) async {
      await t.pumpWidget(const MaterialApp(home: SizedBox()));
      expect(() => ExportarCurva.capturarPng(GlobalKey()), throwsA(isA<StateError>()));
    });
  });

  group('PDF del lote', () {
    test('es un PDF de UNA página aunque haya muchos registros', () async {
      final regs = [for (var i = 0; i < 40; i++) _reg(i)];
      final pdf = await ExportarCurva.pdfDelLote(lote: _lote(), registros: regs, inicio: _inicio);
      expect(String.fromCharCodes(pdf.sublist(0, 5)), '%PDF-');
      expect(ExportarCurva.paginasDelPdf(pdf), 1);
    });

    testWidgets('con la imagen de la curva y la curva ideal sigue siendo de una página', (t) async {
      final clave = GlobalKey();
      final regs = [for (var i = 0; i < 20; i++) _reg(i)];
      await t.pumpWidget(MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: CurvaLoteChart(registros: regs, inicio: _inicio, repaintKey: clave))),
      ));
      final bytes = await t.runAsync(() async {
        final png = await ExportarCurva.capturarPng(clave);
        return ExportarCurva.pdfDelLote(
          lote: _lote(),
          registros: regs,
          inicio: _inicio,
          png: png,
          ideal: CurvaIdeal(const [PuntoIdeal(48, 45), PuntoIdeal(96, 49)]),
        );
      });
      expect(ExportarCurva.paginasDelPdf(bytes!), 1);
      expect(bytes.length, greaterThan(5000), reason: 'incluye la imagen de la curva');
    });

    test('sin registros ni imagen igual genera una página', () async {
      final pdf = await ExportarCurva.pdfDelLote(lote: _lote(), registros: const [], inicio: _inicio);
      expect(ExportarCurva.paginasDelPdf(pdf), 1);
    });

    test('títulos con emojis, tildes y ñ no rompen el PDF', () async {
      final pdf = await ExportarCurva.pdfDelLote(
        lote: _lote(titulo: 'Lote 🍫 Mañana — vereda Él'),
        registros: [_reg(0), _reg(1)],
        inicio: _inicio,
      );
      expect(ExportarCurva.paginasDelPdf(pdf), 1);
    });

    test('la fecha de generación se puede fijar (resultado repetible)', () async {
      final a = await ExportarCurva.pdfDelLote(
          lote: _lote(), registros: [_reg(0)], inicio: _inicio, generado: DateTime(2026, 2, 1));
      expect(a, isNotEmpty);
    });
  });

  test('nombreArchivo deja solo letras ASCII, números, guion y guion bajo', () {
    expect(ExportarCurva.nombreArchivo('Lote Mañana #1', 'pdf'), 'Lote_Ma_ana_1.pdf', reason: 'nombre ASCII seguro');
    expect(ExportarCurva.nombreArchivo('///', 'png'), '_.png');
    expect(ExportarCurva.nombreArchivo('', 'png'), 'lote.png');
  });
}
