// utils/csv_utils.dart
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/volteada.dart';

class CSVUtils {
  static Future<void> exportarVolteadasComoCSV(List<Volteada> volteadas, String nombreLote) async {
    List<List<dynamic>> rows = [
      ['Fecha', 'Temperatura (°C)', 'Humedad (%)', 'Observación', 'Lote']
    ];

    for (var v in volteadas) {
      rows.add([
        v.fecha.toLocal().toString(),
        v.temperatura.toString(),
        v.humedad.toString(),
        v.observacion,
        nombreLote
      ]);
    }

    String csv = const ListToCsvConverter().convert(rows);

    final directory = await getTemporaryDirectory();
    final path = '${directory.path}/volteadas_${nombreLote.replaceAll(' ', '_')}.csv';
    final file = File(path);
    await file.writeAsString(csv);

    await Share.shareXFiles([XFile(path)], text: 'Volteadas del lote $nombreLote');
  }
}
