import 'package:flutter/material.dart';

import '../data/base_conocimiento.dart';
import '../services/chat_service.dart' show avisoGuia;

/// Nombres de los temas de la base de conocimiento, tal como se muestran.
const nombresTemas = <String, String>{
  'cosecha': 'Cosecha',
  'fermentacion': 'Fermentación',
  'volteo': 'Volteo',
  'prueba_corte': 'Prueba de corte',
  'secado': 'Secado',
  'defectos': 'Defectos del grano',
  'almacenamiento': 'Almacenamiento',
  'calidad': 'Calidad',
  'enfermedades': 'Enfermedades',
};

/// Glosario y guía rápida. Todo sale de la base de conocimiento verificada que ya va dentro del teléfono:
/// funciona sin internet y cada texto dice de dónde sale.
class AyudaScreen extends StatelessWidget {
  /// Se puede cambiar en pruebas.
  final Future<BaseConocimiento> Function()? cargar;
  const AyudaScreen({super.key, this.cargar});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Ayuda'),
          bottom: const TabBar(tabs: [Tab(text: 'Guía rápida'), Tab(text: 'Glosario')]),
        ),
        body: FutureBuilder<BaseConocimiento>(
          future: (cargar ?? BaseConocimiento.cargar)(),
          builder: (context, snap) {
            if (snap.hasError) {
              return const Center(
                  child: Padding(padding: EdgeInsets.all(16), child: Text('No se pudo abrir la guía guardada en el teléfono.')));
            }
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final base = snap.data!;
            return TabBarView(children: [_Guia(base), _Glosario(base)]);
          },
        ),
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso();
  @override
  Widget build(BuildContext context) => Card(
        color: Theme.of(context).colorScheme.secondaryContainer,
        child: const Padding(padding: EdgeInsets.all(12), child: Text(avisoGuia)),
      );
}

class _Guia extends StatelessWidget {
  final BaseConocimiento base;
  const _Guia(this.base);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _Aviso(),
        const SizedBox(height: 12),
        for (final tema in base.temas)
          if (base.fragmentos.any((f) => f.tema == tema))
            ExpansionTile(
              title: Text(nombresTemas[tema] ?? tema, style: t.titleMedium),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final f in base.fragmentos.where((f) => f.tema == tema)) ...[
                  Text(f.titulo, style: t.titleSmall),
                  const SizedBox(height: 4),
                  Text(f.texto, style: t.bodyLarge),
                  const SizedBox(height: 4),
                  Text('Fuente: ${f.fuente}', style: t.bodySmall),
                  const SizedBox(height: 16),
                ],
              ],
            ),
        const SizedBox(height: 12),
        Semantics(header: true, child: Text('Lo que esta guía no cubre', style: t.titleMedium)),
        const SizedBox(height: 6),
        for (final p in base.pendientes) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('• $p')),
      ],
    );
  }
}

class _Glosario extends StatelessWidget {
  final BaseConocimiento base;
  const _Glosario(this.base);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final terminos = [...base.glosario]..sort((a, b) => a.termino.toLowerCase().compareTo(b.termino.toLowerCase()));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _Aviso(),
        const SizedBox(height: 12),
        for (final g in terminos)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(header: true, child: Text(g.termino, style: t.titleSmall)),
                const SizedBox(height: 2),
                Text(g.definicion, style: t.bodyLarge),
                const SizedBox(height: 2),
                Text('Fuente: ${g.fuente}', style: t.bodySmall),
              ],
            ),
          ),
      ],
    );
  }
}
