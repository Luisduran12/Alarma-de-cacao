import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/lote.dart';

/// Lista de lotes para elegir uno (por ejemplo, para comparar curvas).
/// Solo ofrece los que tienen al menos 2 registros confirmados, porque con
/// menos no hay curva.
class SelectorLoteDialog extends StatelessWidget {
  final List<Lote> lotes;
  const SelectorLoteDialog({super.key, required this.lotes});

  static int _confirmados(Lote l) => l.volteadas.where((v) => v.confirmada).length;

  @override
  Widget build(BuildContext context) {
    final candidatos = lotes.where((l) => _confirmados(l) >= 2).toList();
    return AlertDialog(
      title: const Text('Comparar con otro lote'),
      content: SizedBox(
        width: double.maxFinite,
        child: candidatos.isEmpty
            ? const Text('No hay otros lotes con al menos 2 registros para comparar.')
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final l in candidatos)
                    ListTile(
                      title: Text(l.title),
                      subtitle: Text('${DateFormat('dd/MM/yyyy').format(l.createdAt)} · '
                          '${_confirmados(l)} registros'),
                      onTap: () => Navigator.pop(context, l),
                    ),
                ],
              ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar'))],
    );
  }
}
