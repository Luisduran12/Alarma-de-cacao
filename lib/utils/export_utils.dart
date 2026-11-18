import 'dart:io';
import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:alarmacacao5_0/models/volteada.dart';
import 'package:alarmacacao5_0/services/lote_service.dart';

/// Exporta todos los lotes y sus registros confirmados a un CSV y lo comparte.
Future<void> exportarTodosLosLotesCSV(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  final lotes = await LoteService().loadLotes();

  if (lotes.isEmpty) {
    messenger.showSnackBar(const SnackBar(content: Text('No hay lotes para exportar.')));
    return;
  }

  final fmt = DateFormat('yyyy-MM-dd HH:mm');
  final rows = <List<dynamic>>[
    ['ID Lote', 'Título', 'Estado', 'Creado', 'Fecha registro', 'Etapa',
     'Temperatura (°C)', 'Humedad (%)', 'Observación', 'Latitud', 'Longitud'],
  ];

  for (final lote in lotes) {
    final registros = lote.volteadas.where((v) => v.confirmada).toList();
    if (registros.isEmpty) {
      rows.add([lote.id, lote.title, lote.status, fmt.format(lote.createdAt), '', '', '', '', '', '', '']);
    }
    for (final v in registros) {
      rows.add([
        lote.id, lote.title, lote.status, fmt.format(lote.createdAt),
        fmt.format(v.fecha), Etapa.nombre(v.etapa), v.temperatura, v.humedad,
        v.observacion, v.latitud ?? '', v.longitud ?? '',
      ]);
    }
  }

  final directory = await getApplicationDocumentsDirectory();
  final file = File('${directory.path}/lotes_exportados.csv');
  // ListToCsvConverter escapa comas y comillas de las observaciones.
  await file.writeAsString(const ListToCsvConverter().convert(rows));

  await SharePlus.instance.share(ShareParams(
    files: [XFile(file.path)],
    text: 'Archivo CSV exportado de lotes de cacao',
  ));
}
