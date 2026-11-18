import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/referencias_curva.dart';
import '../models/lote.dart';
import '../models/volteada.dart';
import 'curva_ideal.dart';
import 'plantillas.dart';
import 'resumen_curva.dart';

/// Exportación de la curva (PNG) y del lote (PDF de una página). Todo se
/// genera en el teléfono, sin internet.
class ExportarCurva {
  ExportarCurva._();

  /// Captura el widget que lleva [clave] (un RepaintBoundary) como PNG.
  static Future<Uint8List> capturarPng(GlobalKey clave, {double pixelRatio = 3}) async {
    final boundary = clave.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) {
      throw StateError('La curva todavía no está dibujada en pantalla.');
    }
    final imagen = await boundary.toImage(pixelRatio: pixelRatio);
    try {
      final datos = await imagen.toByteData(format: ui.ImageByteFormat.png);
      if (datos == null) throw StateError('No se pudo convertir la curva a imagen.');
      return datos.buffer.asUint8List();
    } finally {
      imagen.dispose();
    }
  }

  /// Máximo de registros que caben en la tabla para que el PDF siga siendo de
  /// UNA página. Si hay más, se muestran los más recientes y se avisa.
  static const maxFilasTabla = 14;

  static final _fmtFecha = DateFormat('dd/MM/yyyy HH:mm');

  /// Las fuentes estándar del PDF solo cubren Latin-1 (tildes, ñ, °): lo demás
  /// (emojis, símbolos) se reemplaza para que no salga un cuadro vacío.
  static String _l1(String t) =>
      String.fromCharCodes(t.runes.map((c) => c <= 0xFF ? c : 0x3F /* ? */));

  static String _n(double? v) => v == null ? '-' : v.toStringAsFixed(1).replaceAll('.', ',');

  /// PDF de una página con los datos del lote, el resumen, la curva ([png]) y
  /// la tabla de los últimos registros.
  static Future<Uint8List> pdfDelLote({
    required Lote lote,
    required List<Volteada> registros,
    required DateTime inicio,
    Uint8List? png,
    CurvaIdeal ideal = CurvaIdeal.vacia,
    DateTime? generado,
  }) async {
    final conf = registros.where((v) => v.confirmada).toList()..sort((a, b) => a.fecha.compareTo(b.fecha));
    final resumen = ResumenCurva.calcular(conf, inicio);
    final frases = resumen.frases();
    final conIdeal = ideal.estaVacia ? null : ideal.comparar(conf, inicio);
    final recientes = conf.length > maxFilasTabla ? conf.sublist(conf.length - maxFilasTabla) : conf;

    const base = pw.TextStyle(fontSize: 9.5);
    final negrita = pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold);

    final doc = pw.Document(title: _l1('Lote ${lote.title}'), author: 'Cacao Light');
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(_l1('Lote: ${lote.title}'), style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 2),
          pw.Text(
            _l1('Creado: ${_fmtFecha.format(lote.createdAt)}   |   Estado: ${lote.status}   |   '
                'Plantilla: ${Plantillas.nombre(lote.plantilla)}'),
            style: base,
          ),
          pw.Text(
            _l1('Resultado del grano: ${Calidad.nombre(lote.calidadResultado)}'
                '${(lote.observacionResultado ?? '').isEmpty ? '' : ' - ${lote.observacionResultado}'}'),
            style: base,
          ),
          pw.Divider(),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Container(
                width: 270,
                height: 330,
                child: png == null
                    ? pw.Center(child: pw.Text('Sin curva', style: base))
                    : pw.Image(pw.MemoryImage(png), fit: pw.BoxFit.contain),
              ),
              pw.SizedBox(width: 14),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Resumen', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 4),
                    for (final f in frases) pw.Padding(padding: const pw.EdgeInsets.only(bottom: 4), child: pw.Text(_l1(f), style: base)),
                    if (conIdeal != null) pw.Text(_l1(conIdeal.frase()), style: base),
                    pw.SizedBox(height: 10),
                    pw.Text('Rango de referencia (temperatura)', style: negrita),
                    pw.Text(
                      _l1('Fermentación: de ${_n(ReferenciasCurva.fermentacionTemperatura.minimo)} a '
                          '${_n(ReferenciasCurva.fermentacionTemperatura.maximo)} °C desde la hora '
                          '${ReferenciasCurva.fermentacionTemperatura.desdeHora!.round()}. '
                          'Secado: no pasar de ${_n(ReferenciasCurva.secadoTemperatura.maximo)} °C.'),
                      style: base,
                    ),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            conf.length > maxFilasTabla
                ? 'Registros (los últimos $maxFilasTabla de ${conf.length})'
                : 'Registros (${conf.length})',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 1.5),
            headers: ['Fecha', 'Etapa', 'Temp. (°C)', 'Humedad (%)', 'pH', 'Brix', 'Ambiente (°C)'],
            data: [
              for (final v in recientes)
                [
                  _fmtFecha.format(v.fecha),
                  _l1(Etapa.nombre(v.etapa)),
                  _n(v.temperatura),
                  _n(v.humedad),
                  _n(v.ph),
                  _n(v.brix),
                  _n(v.tempAmbiente),
                ],
            ],
          ),
          pw.Spacer(),
          pw.Divider(),
          pw.Text(
            _l1('Es una guía, no reemplaza al técnico. Referencias: FHIA, InfoCacao No. 14 (2017); '
                'Universidad de La Salle / FEDECACAO (Medina, 2022). Los rangos no son la norma NTC 1252. '
                'Generado el ${_fmtFecha.format(generado ?? DateTime.now())} con Cacao Light.'),
            style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700),
          ),
        ],
      ),
    ));
    return doc.save();
  }

  /// Nombre de archivo seguro (sin espacios ni símbolos).
  static String nombreArchivo(String titulo, String extension) {
    final limpio = titulo.replaceAll(RegExp(r'[^\w\-]+'), '_');
    return '${limpio.isEmpty ? 'lote' : limpio}.$extension';
  }

  @visibleForTesting
  static int paginasDelPdf(Uint8List pdf) =>
      RegExp(r'/Type\s*/Page(?!s)').allMatches(String.fromCharCodes(pdf)).length;
}
