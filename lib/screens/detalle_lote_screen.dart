import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:csv/csv.dart';

import '../models/lote.dart';
import '../models/volteada.dart';
import '../services/volteada_service.dart';
import '../services/lote_service.dart';

class DetalleLoteScreen extends StatefulWidget {
  final Lote lote;

  const DetalleLoteScreen({super.key, required this.lote});

  @override
  State<DetalleLoteScreen> createState() => _DetalleLoteScreenState();
}

class _DetalleLoteScreenState extends State<DetalleLoteScreen> {
  final VolteadaService _volteadaService = VolteadaService();
  final LoteService _loteService = LoteService();
  late Lote _lote;
  List<Volteada> _volteadasDelLote = [];

  @override
  void initState() {
    super.initState();
    _lote = widget.lote;
    _cargarVolteadas();
  }

  Future<void> _cargarVolteadas() async {
    final todas = await _volteadaService.cargarVolteadas();
    final filtradas = todas.where((v) => v.loteId == _lote.id).toList()
      ..sort((a, b) => b.fecha.compareTo(a.fecha));
    setState(() => _volteadasDelLote = filtradas);
  }

  Future<void> _exportarCSV() async {
    if (_volteadasDelLote.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay volteadas para exportar.')),
      );
      return;
    }

    final rows = <List<dynamic>>[
      ['Fecha', 'Temperatura (°C)', 'Humedad (%)', 'Observación']
    ];

    for (final v in _volteadasDelLote) {
      rows.add([
        DateFormat('yyyy-MM-dd HH:mm').format(v.fecha),
        v.temperatura,
        v.humedad,
        v.observacion
      ]);
    }

    final csvData = const ListToCsvConverter().convert(rows);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/volteadas_${_lote.title}.csv');
    await file.writeAsString(csvData);

    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'Historial de volteadas del lote "${_lote.title}"',
    );
  }

  Future<void> _editarLote() async {
    final titleCtrl = TextEditingController(text: _lote.title);
    final statusCtrl = TextEditingController(text: _lote.status);

    final actualizado = await showDialog<Lote>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Editar Lote'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(labelText: 'Título'),
            ),
            TextField(
              controller: statusCtrl,
              decoration: const InputDecoration(labelText: 'Estado'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          TextButton(
            onPressed: () {
              final nuevo = _lote.copyWith(
                title: titleCtrl.text.trim(),
                status: statusCtrl.text.trim(),
              );
              Navigator.pop(context, nuevo);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (actualizado != null) {
      await _loteService.updateLote(actualizado);
      setState(() => _lote = actualizado);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Lote actualizado')));
    }
  }

  Future<void> _eliminarLote() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar lote'),
        content: const Text('¿Estás seguro de que deseas eliminar este lote y su historial?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _loteService.deleteLote(_lote.id);
      if (context.mounted) {
        Navigator.pop(context); // vuelve a la lista
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('🗑️ Lote eliminado')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle del Lote'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download),
            tooltip: 'Exportar historial a CSV',
            onPressed: _exportarCSV,
          ),
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Editar Lote',
            onPressed: _editarLote,
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            tooltip: 'Eliminar Lote',
            onPressed: _eliminarLote,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('🆔 ID: ${_lote.id}'),
            Text('📌 Título: ${_lote.title}'),
            Text('📅 Creado: ${DateFormat('yyyy-MM-dd HH:mm').format(_lote.createdAt.toLocal())}'),
            Text('🔁 Estado: ${_lote.status}'),
            const Divider(height: 32),
            const Text('🔄 Volteadas registradas:',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Expanded(
              child: _volteadasDelLote.isEmpty
                  ? const Center(child: Text('No hay volteadas para este lote.'))
                  : ListView.builder(
                      itemCount: _volteadasDelLote.length,
                      itemBuilder: (context, index) {
                        final v = _volteadasDelLote[index];
                        return Card(
                          elevation: 2,
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          child: ListTile(
                            title: Text(
                              '🕒 ${DateFormat('dd/MM/yyyy HH:mm').format(v.fecha.toLocal())}',
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('🌡️ Temperatura: ${v.temperatura}°C'),
                                Text('💧 Humedad: ${v.humedad}%'),
                                if (v.observacion.isNotEmpty)
                                  Text('📝 Observación: ${v.observacion}'),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
