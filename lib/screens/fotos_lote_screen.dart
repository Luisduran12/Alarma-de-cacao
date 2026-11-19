import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:alarmacacao5_0/services/preferencias_app.dart';
import 'package:intl/intl.dart';

import '../models/analisis_foto.dart';
import '../models/lote.dart';
import '../services/chat_service.dart' show avisoGuia;
import '../services/foto_preparada.dart';
import '../services/foto_service.dart';
import '../services/selector_foto.dart';
import '../widgets/semaforo_foto.dart';
import 'nueva_foto_screen.dart';
import 'resultado_foto_screen.dart';

/// Las fotos de un lote con su análisis. Las que no se pudieron enviar por falta de señal se reintentan al
/// abrir la pantalla y con el botón "Reintentar ahora".
class FotosLoteScreen extends StatefulWidget {
  final Lote lote;
  final FotoService? servicio;
  final SelectorFoto? selector;
  final Future<FotoPreparada> Function(Uint8List)? preparar;
  const FotosLoteScreen({super.key, required this.lote, this.servicio, this.selector, this.preparar});

  @override
  State<FotosLoteScreen> createState() => _FotosLoteScreenState();
}

class _FotosLoteScreenState extends State<FotosLoteScreen> {
  late final FotoService _servicio = widget.servicio ?? FotoService();
  static final _fmt = DateFormat('d/MM HH:mm');

  List<AnalisisFoto> _fotos = [];
  bool _cargando = true;
  bool _reintentando = false;

  int get _pendientes => _fotos.where((f) => f.estado == EstadoAnalisis.pendiente).length;

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  Future<void> _iniciar() async {
    await _recargar();
    // Con el ahorro de batería no se reintenta solo: queda el botón "Reintentar ahora".
    if (_pendientes > 0 && !PreferenciasApp.instancia.ahorroBateria) await _reintentar();
    await _servicio.limpiarHuerfanas();
  }

  Future<void> _recargar() async {
    final f = await _servicio.listar(widget.lote.id);
    if (mounted) {
      setState(() {
        _fotos = f;
        _cargando = false;
      });
    }
  }

  Future<void> _reintentar() async {
    if (_reintentando) return;
    setState(() => _reintentando = true);
    try {
      await _servicio.procesarPendientes();
    } finally {
      await _recargar();
      if (mounted) setState(() => _reintentando = false);
    }
  }

  Future<void> _nueva() async {
    await Navigator.of(context).push(MaterialPageRoute<bool>(
        builder: (_) => NuevaFotoScreen(loteId: widget.lote.id, servicio: _servicio, selector: widget.selector, preparar: widget.preparar)));
    await _recargar();
  }

  Future<void> _abrir(AnalisisFoto a) async {
    await Navigator.of(context).push(MaterialPageRoute<bool>(builder: (_) => ResultadoFotoScreen(analisis: a, servicio: _servicio)));
    await _recargar();
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Fotos del lote')),
      floatingActionButton: FloatingActionButton.extended(onPressed: _nueva, icon: const Icon(Icons.add_a_photo), label: const Text('Nueva foto')),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                Text(avisoGuia, style: tema.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('El análisis de fotos es una estimación de una IA; no reemplaza la prueba de corte oficial ni al técnico.',
                    style: tema.textTheme.bodyMedium),
                const SizedBox(height: 12),
                if (_pendientes > 0)
                  Card(
                    color: tema.colorScheme.secondaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Icon(Icons.cloud_off, color: tema.colorScheme.onSecondaryContainer),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text('$_pendientes ${_pendientes == 1 ? 'foto espera' : 'fotos esperan'} señal para analizarse',
                                style: tema.textTheme.titleMedium?.copyWith(color: tema.colorScheme.onSecondaryContainer)),
                          ),
                        ]),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _reintentando ? null : _reintentar,
                          icon: _reintentando
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.refresh),
                          label: Text(_reintentando ? 'Reintentando…' : 'Reintentar ahora'),
                          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                        ),
                      ]),
                    ),
                  ),
                if (_fotos.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Column(children: [
                      Icon(Icons.photo_camera_outlined, size: 48, color: tema.colorScheme.primary),
                      const SizedBox(height: 8),
                      Text('Todavía no hay fotos en este lote', style: tema.textTheme.titleMedium, textAlign: TextAlign.center),
                      const SizedBox(height: 4),
                      const Text('Toque "Nueva foto" para tomar una.', textAlign: TextAlign.center),
                    ]),
                  ),
                for (final f in _fotos) _fila(tema, f),
              ],
            ),
    );
  }

  Widget _fila(ThemeData tema, AnalisisFoto f) {
    final r = f.resultado;
    final estado = switch (f.estado) {
      EstadoAnalisis.pendiente => 'Esperando señal',
      EstadoAnalisis.error => 'No se pudo analizar',
      EstadoAnalisis.analizada => r != null && r.repetirFoto ? 'Hay que tomar otra foto' : 'Analizada',
    };
    return Card(
      child: InkWell(
        onTap: () => _abrir(f),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(File(f.ruta), width: 64, height: 64, fit: BoxFit.cover, excludeFromSemantics: true,
                  errorBuilder: (_, __, ___) => const SizedBox(width: 64, height: 64, child: Icon(Icons.broken_image_outlined))),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(f.modo.nombre, style: tema.textTheme.titleMedium),
                Text('${_fmt.format(f.creadoEn)} · $estado', style: tema.textTheme.bodyMedium),
                if (f.estado == EstadoAnalisis.analizada && r != null && !r.repetirFoto) ...[
                  const SizedBox(height: 6),
                  SemaforoFoto(r.semaforo, compacto: true),
                ],
              ]),
            ),
            const Icon(Icons.chevron_right),
          ]),
        ),
      ),
    );
  }
}
