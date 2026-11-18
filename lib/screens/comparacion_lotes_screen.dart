import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/lote.dart';
import '../services/analisis_lotes.dart';
import '../services/lote_service.dart';
import 'detalle_lote_screen.dart';

/// Comparación entre lotes: promedio de temperatura y humedad de cada lote
/// junto con la calidad y la observación del resultado del grano.
class ComparacionLotesScreen extends StatefulWidget {
  const ComparacionLotesScreen({super.key});

  @override
  State<ComparacionLotesScreen> createState() => _ComparacionLotesScreenState();
}

class _ComparacionLotesScreenState extends State<ComparacionLotesScreen> {
  final _loteService = LoteService();
  List<ResumenLote> _resumenes = [];
  List<ResumenCalidad> _porCalidad = [];
  int _sinEvaluar = 0;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final lotes = await _loteService.loadLotes();
    if (!mounted) return;
    setState(() {
      _resumenes = AnalisisLotes.compararLotes(lotes);
      _porCalidad = AnalisisLotes.porCalidad(lotes);
      _sinEvaluar = _resumenes.where((r) => r.lote.calidadResultado == null).length;
      _cargando = false;
    });
  }

  String _n(double? v, String unidad) => v == null ? '—' : '${v.toStringAsFixed(1)} $unidad';

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Comparar lotes')),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _resumenes.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Aún no hay lotes con registros. Registra temperatura y humedad en las volteadas '
                      'para poder comparar.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text('Promedios según la calidad del grano', style: tema.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        'Cruce descriptivo: con pocos lotes es solo orientativo. '
                        'Evalúa el resultado de cada lote en su detalle.',
                        style: tema.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      if (_porCalidad.isEmpty)
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(12),
                            child: Text('Ningún lote tiene todavía el resultado del grano evaluado.'),
                          ),
                        )
                      else
                        Card(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              columns: const [
                                DataColumn(label: Text('Calidad')),
                                DataColumn(label: Text('Lotes'), numeric: true),
                                DataColumn(label: Text('Temp. prom.'), numeric: true),
                                DataColumn(label: Text('Hum. prom.'), numeric: true),
                              ],
                              rows: [
                                for (final c in _porCalidad)
                                  DataRow(cells: [
                                    DataCell(Text(Calidad.nombre(c.calidad))),
                                    DataCell(Text('${c.lotes}')),
                                    DataCell(Text(_n(c.tempPromedio, '°C'))),
                                    DataCell(Text(_n(c.humedadPromedio, '%'))),
                                  ]),
                              ],
                            ),
                          ),
                        ),
                      if (_sinEvaluar > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('$_sinEvaluar lote(s) con registros aún sin evaluar.',
                              style: tema.textTheme.bodySmall),
                        ),
                      const SizedBox(height: 16),
                      Text('Lotes (de mejor a peor resultado)', style: tema.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      for (final r in _resumenes) _tarjeta(r),
                    ],
                  ),
                ),
    );
  }

  Widget _tarjeta(ResumenLote r) {
    final lote = r.lote;
    return Card(
      child: InkWell(
        onTap: () async {
          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => DetalleLoteScreen(lote: lote)));
          await _cargar();
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(lote.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                  Chip(
                    label: Text(Calidad.nombre(lote.calidadResultado)),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              Text('${DateFormat('dd/MM/yyyy').format(lote.createdAt)} · ${r.registros} registros'),
              const SizedBox(height: 6),
              Text('Promedio general: ${_n(r.tempPromedio, '°C')} · ${_n(r.humedadPromedio, '%')}'),
              if (r.tempFermentacion != null)
                Text('Fermentación: ${_n(r.tempFermentacion, '°C')} · ${_n(r.humedadFermentacion, '%')}'),
              if (r.tempSecado != null)
                Text('Secado: ${_n(r.tempSecado, '°C')} · ${_n(r.humedadSecado, '%')}'),
              if ((lote.observacionResultado ?? '').isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('Resultado: ${lote.observacionResultado}', style: const TextStyle(fontStyle: FontStyle.italic)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
