import 'package:flutter/material.dart';

import '../data/guia_prueba_corte.dart';
import '../widgets/ilustraciones_corte.dart';
import 'confirmar_volteada_screen.dart';

/// Guía ilustrada de la prueba de corte. Funciona sin internet (todo el
/// contenido va en la app). Se abre desde el aviso de fin de fermentación, desde
/// el detalle del lote y desde la pantalla principal.
class GuiaPruebaCorteScreen extends StatelessWidget {
  /// Si se abre desde el aviso de un lote, ofrece registrar los datos de esa alarma.
  final String loteId;
  final String volteadaId;

  const GuiaPruebaCorteScreen({super.key, this.loteId = '', this.volteadaId = ''});

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Prueba de corte')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Cómo hacer la prueba de corte', style: tema.textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text('Sirve para saber si la fermentación ya terminó. Siga los pasos en orden.',
              style: tema.textTheme.bodyLarge),
          const SizedBox(height: 12),
          for (final paso in GuiaPruebaCorte.pasos) _TarjetaPaso(paso: paso),
          const SizedBox(height: 4),
          Text('Grupos en que se separan los granos', style: tema.textTheme.titleLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [for (final g in GuiaPruebaCorte.grupos) Chip(label: Text(g))],
          ),
          const SizedBox(height: 8),
          Text(GuiaPruebaCorte.avisoGrupos, style: tema.textTheme.bodyMedium),
          Text('Fuente: ${GuiaPruebaCorte.fuenteLaSalle}.', style: tema.textTheme.bodySmall),
          const SizedBox(height: 16),
          Card(
            color: tema.colorScheme.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.info_outline, color: tema.colorScheme.onSecondaryContainer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Importante',
                          style: tema.textTheme.titleMedium?.copyWith(color: tema.colorScheme.onSecondaryContainer)),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  Text(GuiaPruebaCorte.avisoNtc,
                      style: tema.textTheme.bodyLarge?.copyWith(color: tema.colorScheme.onSecondaryContainer)),
                  const SizedBox(height: 6),
                  Text(GuiaPruebaCorte.avisoGuia,
                      style: tema.textTheme.bodyLarge
                          ?.copyWith(color: tema.colorScheme.onSecondaryContainer, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
          if (loteId.isNotEmpty) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => ConfirmarVolteadaScreen(loteId: loteId, volteadaId: volteadaId),
              )),
              icon: const Icon(Icons.edit_note),
              label: const Text('Registrar los datos del lote'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _TarjetaPaso extends StatelessWidget {
  final PasoGuia paso;
  const _TarjetaPaso({required this.paso});

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              CircleAvatar(
                backgroundColor: tema.colorScheme.primary,
                foregroundColor: tema.colorScheme.onPrimary,
                child: Text('${paso.numero}'),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(paso.titulo, style: tema.textTheme.titleLarge)),
            ]),
            const SizedBox(height: 8),
            Text(paso.texto, style: tema.textTheme.bodyLarge),
            if (paso.ilustracion != TipoIlustracion.ninguna) ...[
              const SizedBox(height: 8),
              IlustracionCorte(tipo: paso.ilustracion),
            ],
            const SizedBox(height: 6),
            Text('Fuente: ${paso.fuente}', style: tema.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
