import 'dart:io';
import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/lote.dart';
import '../models/volteada.dart';
import '../services/lote_service.dart';
import '../services/plantillas.dart';
import '../widgets/curva_lote_chart.dart';
import 'confirmar_volteada_screen.dart';

class DetalleLoteScreen extends StatefulWidget {
  final Lote lote;

  const DetalleLoteScreen({super.key, required this.lote});

  @override
  State<DetalleLoteScreen> createState() => _DetalleLoteScreenState();
}

class _DetalleLoteScreenState extends State<DetalleLoteScreen> {
  final LoteService _loteService = LoteService();
  final _fmt = DateFormat('dd/MM/yyyy HH:mm');
  late Lote _lote;

  @override
  void initState() {
    super.initState();
    _lote = widget.lote;
    _recargar();
  }

  /// Recarga el lote desde la base de datos (única fuente de datos).
  Future<void> _recargar() async {
    final lote = await _loteService.obtenerLotePorId(_lote.id);
    if (!mounted || lote == null) return;
    setState(() => _lote = lote);
  }

  List<Volteada> get _confirmadas =>
      _lote.volteadas.where((v) => v.confirmada).toList()..sort((a, b) => a.fecha.compareTo(b.fecha));

  List<Volteada> get _pendientes => _lote.volteadas.where((v) => !v.confirmada).toList();

  /// Último punto de secado registrado (si existe).
  Volteada? get _puntoSecado =>
      _confirmadas.where((v) => v.etapa == Etapa.secado && v.tieneUbicacion).lastOrNull;

  Future<void> _abrirRegistro({String volteadaId = ''}) async {
    final guardado = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => ConfirmarVolteadaScreen(loteId: _lote.id, volteadaId: volteadaId),
    ));
    if (guardado == true) await _recargar();
  }

  Future<void> _abrirMapa(double lat, double lon) async {
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lon');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir el mapa.')),
      );
    }
  }

  Future<void> _exportarCSV() async {
    final registros = _confirmadas;
    if (registros.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay registros para exportar.')),
      );
      return;
    }

    final rows = <List<dynamic>>[
      ['Fecha', 'Etapa', 'Temperatura (°C)', 'Humedad (%)', 'Observación', 'Latitud', 'Longitud'],
      for (final v in registros)
        [
          DateFormat('yyyy-MM-dd HH:mm').format(v.fecha),
          Etapa.nombre(v.etapa),
          v.temperatura,
          v.humedad,
          v.observacion,
          v.latitud ?? '',
          v.longitud ?? '',
        ],
    ];

    final dir = await getTemporaryDirectory();
    final nombre = _lote.title.replaceAll(RegExp(r'[^\w\-]+'), '_');
    final file = File('${dir.path}/registros_$nombre.csv');
    await file.writeAsString(const ListToCsvConverter().convert(rows));

    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path)],
      text: 'Registros del lote "${_lote.title}"',
    ));
  }

  Future<void> _editarLote() async {
    final titleCtrl = TextEditingController(text: _lote.title);
    String estado = _lote.status;

    final actualizado = await showDialog<Lote>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Editar lote'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Título')),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: const ['en proceso', 'completado', 'migrado'].contains(estado) ? estado : 'en proceso',
                decoration: const InputDecoration(labelText: 'Estado'),
                items: const [
                  DropdownMenuItem(value: 'en proceso', child: Text('En proceso')),
                  DropdownMenuItem(value: 'completado', child: Text('Completado')),
                  DropdownMenuItem(value: 'migrado', child: Text('Migrado')),
                ],
                onChanged: (v) => setLocal(() => estado = v ?? estado),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            TextButton(
              onPressed: () => Navigator.pop(
                context,
                _lote.copyWith(
                  title: titleCtrl.text.trim().isEmpty ? _lote.title : titleCtrl.text.trim(),
                  status: estado,
                ),
              ),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );

    if (actualizado != null) {
      await _loteService.updateLote(actualizado);
      await _recargar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Lote actualizado')));
    }
  }

  /// Calidad del grano y observación del resultado (para comparar lotes).
  Future<void> _editarResultado() async {
    String? calidad = _lote.calidadResultado;
    final obsCtrl = TextEditingController(text: _lote.observacionResultado ?? '');

    final guardar = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Resultado del grano'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: calidad,
                decoration: const InputDecoration(labelText: 'Calidad'),
                items: [
                  for (final c in Calidad.todas) DropdownMenuItem(value: c, child: Text(Calidad.nombre(c))),
                ],
                onChanged: (v) => setLocal(() => calidad = v),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: obsCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Observación del resultado',
                  hintText: 'Prueba de corte, color, aroma, % de granos violetas…',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Guardar')),
          ],
        ),
      ),
    );

    if (guardar == true) {
      await _loteService.updateLote(_lote.copyWith(
        calidadResultado: calidad,
        observacionResultado: obsCtrl.text.trim(),
      ));
      await _recargar();
    }
  }

  Future<void> _eliminarLote() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar lote'),
        content: const Text('¿Seguro que deseas eliminar este lote, su historial y sus alarmas pendientes?'),
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('🗑️ Lote eliminado')));
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final confirmadas = _confirmadas.reversed.toList(); // más reciente primero
    final punto = _puntoSecado;

    return Scaffold(
      appBar: AppBar(
        title: Text(_lote.title),
        actions: [
          IconButton(icon: const Icon(Icons.file_download), tooltip: 'Exportar a CSV', onPressed: _exportarCSV),
          IconButton(icon: const Icon(Icons.edit), tooltip: 'Editar lote', onPressed: _editarLote),
          IconButton(icon: const Icon(Icons.delete), tooltip: 'Eliminar lote', onPressed: _eliminarLote),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrirRegistro(),
        icon: const Icon(Icons.add),
        label: const Text('Agregar registro'),
      ),
      body: RefreshIndicator(
        onRefresh: _recargar,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            Text('📅 Creado: ${_fmt.format(_lote.createdAt.toLocal())}'),
            Text('🔁 Estado: ${_lote.status}'),
            Text('🧪 Plantilla: ${Plantillas.nombre(_lote.plantilla)}'),
            if (_lote.finCiclo != null) Text('⏱️ Fin del ciclo: ${_fmt.format(_lote.finCiclo!)}'),
            _seccion('🏆 Resultado del grano'),
            Card(
              child: ListTile(
                title: Text('Calidad: ${Calidad.nombre(_lote.calidadResultado)}'),
                subtitle: Text((_lote.observacionResultado ?? '').isEmpty
                    ? 'Sin observación. Evalúa el grano al terminar para poder comparar lotes.'
                    : _lote.observacionResultado!),
                trailing: TextButton(onPressed: _editarResultado, child: const Text('Evaluar')),
              ),
            ),
            _seccion('📈 Curva de temperatura y humedad'),
            CurvaLoteChart(
              registros: _confirmadas,
              inicio: _lote.inicioCiclo ?? _confirmadas.firstOrNull?.fecha ?? _lote.createdAt,
            ),
            _seccion('📍 Punto de secado'),
            if (punto == null)
              const Text('Aún no hay registros de secado con ubicación.')
            else
              Card(
                child: ListTile(
                  leading: const Icon(Icons.place, color: Colors.red),
                  title: Text('Lat ${punto.latitud!.toStringAsFixed(6)}, '
                      'Lon ${punto.longitud!.toStringAsFixed(6)}'),
                  subtitle: Text('Registrado el ${_fmt.format(punto.fecha)}'),
                  trailing: TextButton(
                    onPressed: () => _abrirMapa(punto.latitud!, punto.longitud!),
                    child: const Text('Ver en mapa'),
                  ),
                ),
              ),
            if (_pendientes.isNotEmpty) ...[
              _seccion('⏰ Volteadas pendientes'),
              for (final v in _pendientes)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.alarm),
                    title: Text(v.mensaje),
                    subtitle: Text('Programada: ${_fmt.format(v.fechaProgramada)}'),
                    trailing: TextButton(
                      onPressed: () => _abrirRegistro(volteadaId: v.id),
                      child: const Text('Registrar'),
                    ),
                  ),
                ),
            ],
            _seccion('🔄 Registros (${confirmadas.length})'),
            if (confirmadas.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('No hay registros para este lote.'),
              ),
            for (final v in confirmadas)
              Card(
                child: ListTile(
                  onTap: () => _abrirRegistro(volteadaId: v.id),
                  title: Text('🕒 ${_fmt.format(v.fecha.toLocal())} · ${Etapa.nombre(v.etapa)}'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('🌡️ ${v.temperatura} °C   💧 ${v.humedad} %'),
                      if (v.observacion.isNotEmpty) Text('📝 ${v.observacion}'),
                      if (v.tieneUbicacion)
                        Text('📍 ${v.latitud!.toStringAsFixed(5)}, ${v.longitud!.toStringAsFixed(5)}'),
                    ],
                  ),
                  trailing: v.tieneUbicacion
                      ? IconButton(
                          icon: const Icon(Icons.map_outlined),
                          tooltip: 'Ver en mapa',
                          onPressed: () => _abrirMapa(v.latitud!, v.longitud!),
                        )
                      : null,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _seccion(String titulo) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Text(titulo, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      );
}
