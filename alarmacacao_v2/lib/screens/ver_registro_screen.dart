import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:alarmacacao5_0/models/lote.dart';
import 'package:alarmacacao5_0/services/lote_service.dart';
import 'package:alarmacacao5_0/screens/detalle_lote_screen.dart';
import 'package:alarmacacao5_0/utils/export_utils.dart'; // ✅ Asegúrate de tener este archivo

class VerRegistroScreen extends StatefulWidget {
  final LoteService loteService;
  final VoidCallback onLotesChanged;

  const VerRegistroScreen({
    super.key,
    required this.loteService,
    required this.onLotesChanged,
  });

  @override
  State<VerRegistroScreen> createState() => _VerRegistroScreenState();
}

class _VerRegistroScreenState extends State<VerRegistroScreen> {
  List<Lote> _lotes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _cargarLotes();
  }

  Future<void> _cargarLotes() async {
    setState(() => _isLoading = true);
    _lotes = await widget.loteService.loadLotes();
    setState(() => _isLoading = false);
  }

  void _eliminarLote(String loteId) async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirmar Eliminación'),
          content: const Text('¿Estás seguro de que quieres eliminar este lote?'),
          actions: [
            TextButton(
              child: const Text('Cancelar'),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            TextButton(
              child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      await widget.loteService.deleteLote(loteId);
      await _cargarLotes();
      widget.onLotesChanged();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lote eliminado correctamente.')),
      );
    }
  }

  void _verDetalleLote(Lote lote) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DetalleLoteScreen(lote: lote),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Registro de Lotes de Cacao'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Exportar todo a CSV',
            onPressed: () async {
              await exportarTodosLosLotesCSV(context); // ✅ Exportar todo
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _lotes.isEmpty
              ? const Center(child: Text('No hay lotes registrados aún.', style: TextStyle(fontSize: 16)))
              : ListView.builder(
                  itemCount: _lotes.length,
                  itemBuilder: (context, index) {
                    final lote = _lotes[index];
                    return Card(
                      margin: const EdgeInsets.all(8.0),
                      elevation: 4.0,
                      child: ListTile(
                        title: Text(lote.title),
                        subtitle: Text(
                          'Estado: ${lote.status} | Creado: ${DateFormat('dd/MM/yyyy HH:mm').format(lote.createdAt)}',
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _eliminarLote(lote.id),
                          tooltip: 'Eliminar Lote',
                        ),
                        onTap: () => _verDetalleLote(lote),
                      ),
                    );
                  },
                ),
    );
  }
}
