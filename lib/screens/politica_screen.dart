import 'package:flutter/material.dart';

import '../data/politica_privacidad.dart';

class PoliticaScreen extends StatelessWidget {
  const PoliticaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text(PoliticaPrivacidad.titulo)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final s in PoliticaPrivacidad.secciones) ...[
            Semantics(header: true, child: Text(s.titulo, style: t.titleMedium)),
            const SizedBox(height: 6),
            Text(s.texto, style: t.bodyLarge),
            const SizedBox(height: 20),
          ],
          if (PoliticaPrivacidad.contactoResponsable.isNotEmpty) ...[
            Semantics(header: true, child: Text('Contacto', style: t.titleMedium)),
            const SizedBox(height: 6),
            Text(PoliticaPrivacidad.contactoResponsable, style: t.bodyLarge),
          ],
        ],
      ),
    );
  }
}
