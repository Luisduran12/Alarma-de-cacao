import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../data/guia_foto.dart';
import '../models/analisis_foto.dart';
import '../services/consentimiento_fotos.dart';
import '../services/foto_preparada.dart';
import '../services/foto_service.dart';
import '../services/selector_foto.dart';
import 'resultado_foto_screen.dart';

/// Tomar (o elegir) una foto de un lote y analizarla: 1) qué se quiere mirar, 2) guía de cómo tomar la foto,
/// 3) permiso la primera vez, 4) reducir la foto y quitarle los datos ocultos, 5) guardar y analizar.
/// Si no hay señal la foto queda guardada y se analiza después.
class NuevaFotoScreen extends StatefulWidget {
  final String loteId;
  final FotoService? servicio;
  final SelectorFoto? selector;
  final Future<FotoPreparada> Function(Uint8List)? preparar;
  const NuevaFotoScreen({super.key, required this.loteId, this.servicio, this.selector, this.preparar});

  @override
  State<NuevaFotoScreen> createState() => _NuevaFotoScreenState();
}

class _NuevaFotoScreenState extends State<NuevaFotoScreen> {
  late final FotoService _servicio = widget.servicio ?? FotoService();
  late final SelectorFoto _selector = widget.selector ?? SelectorFotoReal();
  late final Future<FotoPreparada> Function(Uint8List) _preparar = widget.preparar ?? PreparadorFoto.preparar;

  ModoAnalisis? _modo;
  String? _trabajo; // lo que se está haciendo ("Preparando la foto…")
  String? _problema;

  bool get _ocupado => _trabajo != null;

  Future<bool> _pedirPermiso() async {
    if (await ConsentimientoFotos.obtener() == true) return true;
    if (!mounted) return false;
    final acepta = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: const Text(ConsentimientoFotos.titulo),
        content: const SingleChildScrollView(child: Text(ConsentimientoFotos.texto)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('No enviar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Sí, enviar')),
        ],
      ),
    );
    await ConsentimientoFotos.registrar(acepta == true);
    return acepta == true;
  }

  Future<void> _capturar(bool camara) async {
    final modo = _modo;
    if (modo == null || _ocupado) return;
    setState(() => _problema = null);

    if (!await _pedirPermiso()) {
      if (mounted) setState(() => _problema = 'No se envió ninguna foto. Sin su permiso la app no analiza fotos.');
      return;
    }

    Uint8List? bytes;
    try {
      bytes = await _selector.tomar(camara: camara);
    } on SelectorFotoException catch (e) {
      if (mounted) setState(() => _problema = e.mensaje);
      return;
    }
    if (bytes == null || !mounted) return;

    setState(() => _trabajo = 'Preparando la foto…');
    final FotoPreparada foto;
    try {
      foto = await _preparar(bytes);
    } on FotoInvalidaException catch (e) {
      if (mounted) {
        setState(() {
          _trabajo = null;
          _problema = e.mensaje;
        });
      }
      return;
    }

    AnalisisFoto guardada;
    try {
      guardada = await _servicio.guardar(loteId: widget.loteId, modo: modo, foto: foto);
    } catch (_) {
      if (mounted) {
        setState(() {
          _trabajo = null;
          _problema = 'No se pudo guardar la foto en el teléfono. Revise que tenga espacio.';
        });
      }
      return;
    }
    if (!mounted) return;

    setState(() => _trabajo = 'Analizando la foto…');
    try {
      final analizada = await _servicio.analizar(guardada.id);
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => ResultadoFotoScreen(analisis: analizada, servicio: _servicio)),
      );
    } on FotoException catch (e) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(e.reintentable ? 'La foto quedó guardada' : 'No se pudo analizar'),
          content: Text(e.mensaje),
          actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Entendido'))],
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final modo = _modo;
    return Scaffold(
      appBar: AppBar(
        title: Text(modo == null ? 'Nueva foto' : modo.nombre),
        leading: modo != null && !_ocupado
            ? IconButton(icon: const Icon(Icons.arrow_back), tooltip: 'Cambiar lo que quiere mirar', onPressed: () => setState(() => _modo = null))
            : null,
      ),
      body: _ocupado
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(_trabajo!, style: tema.textTheme.titleMedium, textAlign: TextAlign.center),
                ]),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: modo == null ? _elegir(tema) : _guia(tema, modo),
            ),
    );
  }

  List<Widget> _elegir(ThemeData tema) => [
        Text('¿Qué quiere mirar?', style: tema.textTheme.titleLarge),
        const SizedBox(height: 12),
        for (final m in ModoAnalisis.values)
          Card(
            child: ListTile(
              minVerticalPadding: 14,
              leading: Icon(switch (m) {
                ModoAnalisis.corte => Icons.content_cut,
                ModoAnalisis.granoSeco => Icons.grain,
                ModoAnalisis.mazorcaHoja => Icons.eco_outlined,
              }, size: 32),
              title: Text(m.nombre, style: tema.textTheme.titleMedium),
              subtitle: Text(m.descripcion),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => setState(() => _modo = m),
            ),
          ),
      ];

  List<Widget> _guia(ThemeData tema, ModoAnalisis modo) {
    final g = GuiaFoto.para(modo);
    return [
      Text(g.titulo, style: tema.textTheme.titleLarge),
      const SizedBox(height: 4),
      Text(GuiaFoto.nota, style: tema.textTheme.bodyMedium),
      const SizedBox(height: 12),
      for (var i = 0; i < g.pasos.length; i++)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(g.pasos[i].icono, size: 30, color: tema.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${i + 1}. ${g.pasos[i].titulo}', style: tema.textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(g.pasos[i].texto, style: tema.textTheme.bodyLarge),
                ]),
              ),
            ]),
          ),
        ),
      if (_problema != null)
        Card(
          color: tema.colorScheme.errorContainer,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(_problema!, key: const Key('problema'), style: tema.textTheme.bodyLarge?.copyWith(color: tema.colorScheme.onErrorContainer)),
          ),
        ),
      const SizedBox(height: 8),
      FilledButton.icon(
        onPressed: () => _capturar(true),
        icon: const Icon(Icons.photo_camera),
        label: const Text('Tomar la foto'),
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: () => _capturar(false),
        icon: const Icon(Icons.photo_library_outlined),
        label: const Text('Elegir una foto del teléfono'),
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
      ),
    ];
  }
}
