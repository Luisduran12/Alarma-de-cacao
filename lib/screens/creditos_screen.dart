import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_info.dart';
import '../data/creditos.dart';

class CreditosScreen extends StatelessWidget {
  /// Se puede cambiar en pruebas (abrir un enlace necesita el teléfono).
  final Future<void> Function(Uri)? abrirEnlace;
  const CreditosScreen({super.key, this.abrirEnlace});

  Future<void> _abrir(BuildContext context, String url) async {
    final mensajes = ScaffoldMessenger.of(context);
    try {
      final uri = Uri.parse(url);
      if (abrirEnlace != null) {
        await abrirEnlace!(uri);
      } else if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw StateError('no se pudo abrir');
      }
    } catch (_) {
      mensajes.showSnackBar(SnackBar(content: Text('No se pudo abrir el enlace. Dirección: $url')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Créditos y licencias')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('${AppInfo.nombre} · versión ${AppInfo.version}', style: t.titleMedium),
          const SizedBox(height: 4),
          Text(Creditos.aviso, style: t.bodyLarge),
          const SizedBox(height: 16),
          for (final c in Creditos.items)
            Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(header: true, child: Text(c.titulo, style: t.titleSmall)),
                    const SizedBox(height: 4),
                    Text(c.texto, style: t.bodyMedium),
                    if (c.enlace != null)
                      TextButton.icon(
                        onPressed: () => _abrir(context, c.enlace!),
                        icon: const Icon(Icons.open_in_new),
                        label: Text('Abrir: ${c.enlace}', overflow: TextOverflow.ellipsis),
                      ),
                  ],
                ),
              ),
            ),
          OutlinedButton.icon(
            onPressed: () => showLicensePage(
              context: context,
              applicationName: AppInfo.nombre,
              applicationVersion: AppInfo.version,
            ),
            icon: const Icon(Icons.description_outlined),
            label: const Text('Licencias del software (paquetes)'),
          ),
        ],
      ),
    );
  }
}
