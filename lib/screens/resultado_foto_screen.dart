import 'dart:io';

import 'package:flutter/material.dart';

import '../models/analisis_foto.dart';
import '../services/chat_service.dart' show avisoGuia;
import '../services/foto_service.dart';
import '../widgets/semaforo_foto.dart';

/// El resultado de una foto: semáforo, qué se ve, posibles causas y pasos. Siempre con el aviso de que es
/// una estimación y no reemplaza al técnico.
class ResultadoFotoScreen extends StatefulWidget {
  final AnalisisFoto analisis;
  final FotoService? servicio;
  const ResultadoFotoScreen({super.key, required this.analisis, this.servicio});

  @override
  State<ResultadoFotoScreen> createState() => _ResultadoFotoScreenState();
}

class _ResultadoFotoScreenState extends State<ResultadoFotoScreen> {
  late final FotoService _servicio = widget.servicio ?? FotoService();
  late AnalisisFoto _a = widget.analisis;
  bool _trabajando = false;
  String? _problema;

  Future<void> _reintentar() async {
    setState(() {
      _trabajando = true;
      _problema = null;
    });
    try {
      final nuevo = await _servicio.analizar(_a.id);
      if (mounted) setState(() => _a = nuevo);
    } on FotoException catch (e) {
      final actual = await _servicio.obtener(_a.id);
      if (mounted) {
        setState(() {
          _problema = e.mensaje;
          if (actual != null) _a = actual;
        });
      }
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  Future<void> _borrar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('¿Borrar esta foto?'),
        content: const Text('Se borra la foto y su resultado de este teléfono.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Borrar')),
        ],
      ),
    );
    if (ok != true) return;
    await _servicio.borrar(_a.id);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final r = _a.resultado;
    return Scaffold(
      appBar: AppBar(
        title: Text(_a.modo.nombre),
        actions: [IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Borrar esta foto', onPressed: _borrar)],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              File(_a.ruta),
              height: 240,
              fit: BoxFit.cover,
              semanticLabel: 'La foto que tomó',
              errorBuilder: (_, __, ___) => Container(
                height: 120,
                color: tema.colorScheme.surfaceContainerHighest,
                alignment: Alignment.center,
                child: const Text('La foto ya no está en el teléfono'),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_a.estado == EstadoAnalisis.pendiente) ..._pendiente(tema),
          if (_a.estado == EstadoAnalisis.error) ..._conError(tema),
          if (r != null) ..._resultado(tema, r),
          const SizedBox(height: 16),
          Text(avisoGuia, key: const Key('aviso_guia'), style: tema.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  List<Widget> _pendiente(ThemeData tema) => [
        _tarjeta(tema, Icons.cloud_off, 'Esperando señal',
            'La foto está guardada en el teléfono. Se analizará cuando haya internet.${_a.ultimoError != null ? '\n\n${_a.ultimoError}' : ''}',
            error: false),
        if (_problema != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_problema!, style: tema.textTheme.bodyLarge)),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _trabajando ? null : _reintentar,
          icon: _trabajando ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh),
          label: Text(_trabajando ? 'Analizando…' : 'Analizar ahora'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        ),
      ];

  List<Widget> _conError(ThemeData tema) => [
        _tarjeta(tema, Icons.error_outline, 'No se pudo analizar', _a.ultimoError ?? 'Tome otra foto.', error: true),
      ];

  Widget _tarjeta(ThemeData tema, IconData icono, String titulo, String texto, {required bool error}) => Card(
        color: error ? tema.colorScheme.errorContainer : tema.colorScheme.secondaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icono),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(titulo, style: tema.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(texto, style: tema.textTheme.bodyLarge),
              ]),
            ),
          ]),
        ),
      );

  List<Widget> _resultado(ThemeData tema, ResultadoAnalisis r) {
    if (r.repetirFoto) {
      return [
        _tarjeta(tema, Icons.photo_camera_outlined, 'Tome otra foto', r.mensaje.isEmpty ? 'No se pudo ver bien. Tome otra foto.' : r.mensaje, error: false),
        ..._lista(tema, 'Pasos recomendados', r.pasosRecomendados),
        const SizedBox(height: 8),
        Text(r.aviso, style: tema.textTheme.bodyMedium),
      ];
    }
    return [
      SemaforoFoto(r.semaforo),
      const SizedBox(height: 16),
      Text('Lo que se ve (aproximado)', style: tema.textTheme.titleLarge),
      const SizedBox(height: 8),
      for (final c in r.categorias)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Semantics(
            label: '${nombreCategoria(c.nombre)}: ${c.porcentaje} por ciento',
            excludeSemantics: true,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(nombreCategoria(c.nombre), style: tema.textTheme.bodyLarge)),
                Text('${c.porcentaje} %', style: tema.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 4),
              LinearProgressIndicator(value: c.porcentaje / 100, minHeight: 10, borderRadius: BorderRadius.circular(6)),
            ]),
          ),
        ),
      const SizedBox(height: 4),
      Text('Confianza de la IA: ${r.confianza}', style: tema.textTheme.bodyLarge),
      ..._lista(tema, 'Posibles causas', r.posiblesCausas),
      ..._lista(tema, 'Qué hacer', r.pasosRecomendados),
      const SizedBox(height: 12),
      Card(
        color: tema.colorScheme.secondaryContainer,
        child: Padding(padding: const EdgeInsets.all(12), child: Text(r.aviso, style: tema.textTheme.bodyLarge)),
      ),
    ];
  }

  List<Widget> _lista(ThemeData tema, String titulo, List<String> items) => items.isEmpty
      ? const []
      : [
          const SizedBox(height: 16),
          Text(titulo, style: tema.textTheme.titleLarge),
          const SizedBox(height: 4),
          for (final t in items) Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text('• $t', style: tema.textTheme.bodyLarge)),
        ];
}
