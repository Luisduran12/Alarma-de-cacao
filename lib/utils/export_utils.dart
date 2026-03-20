import 'dart:io';
import 'package:alarmacacao5_0/models/lote.dart';
import 'package:alarmacacao5_0/services/lote_service.dart';
import 'package:alarmacacao5_0/services/volteada_service.dart';
import 'package:alarmacacao5_0/models/volteada.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

Future<void> exportarTodosLosLotesCSV(BuildContext context) async {
  final loteService = LoteService();
  final volteadaService = VolteadaService();
  final lotes = await loteService.loadLotes();
  final volteadas = await volteadaService.cargarVolteadas();

  if (lotes.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No hay lotes para exportar.')),
    );
    return;
  }

  final buffer = StringBuffer();
  buffer.writeln('ID Lote,Título,Estado,Creado,Volteada Fecha,Temperatura, Humedad, Observación');

  for (final lote in lotes) {
    final volteadasDelLote = volteadas.where((v) => v.loteId == lote.id).toList();

    if (volteadasDelLote.isEmpty) {
      buffer.writeln('${lote.id},${lote.title},${lote.status},${lote.createdAt.toIso8601String()},,,,');
    } else {
      for (final v in volteadasDelLote) {
        buffer.writeln(
          '${lote.id},${lote.title},${lote.status},${lote.createdAt.toIso8601String()},${v.fecha.toIso8601String()},${v.temperatura},${v.humedad},${v.observacion}',
        );
      }
    }
  }

  final directory = await getApplicationDocumentsDirectory();
  final file = File('${directory.path}/lotes_exportados.csv');
  await file.writeAsString(buffer.toString());

  await Share.shareXFiles(
    [XFile(file.path)],
    text: 'Archivo CSV exportado de lotes de cacao',
  );
}
