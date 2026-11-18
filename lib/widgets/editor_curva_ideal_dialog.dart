import 'package:flutter/material.dart';

import '../services/curva_ideal.dart';

/// Editor de la curva ideal: una lista de puntos "a la hora X, Y °C".
///
/// Devuelve la curva nueva (puede ser vacía para borrarla) o null si se cancela.
/// La app NO trae una curva de fábrica: el productor escribe la que le indique
/// su técnico o su asociación.
class EditorCurvaIdealDialog extends StatefulWidget {
  final CurvaIdeal inicial;
  const EditorCurvaIdealDialog({super.key, required this.inicial});

  @override
  State<EditorCurvaIdealDialog> createState() => _EditorCurvaIdealDialogState();
}

class _Fila {
  final TextEditingController horas, temp;
  _Fila(String h, String t)
      : horas = TextEditingController(text: h),
        temp = TextEditingController(text: t);
  void dispose() {
    horas.dispose();
    temp.dispose();
  }
}

class _EditorCurvaIdealDialogState extends State<EditorCurvaIdealDialog> {
  final _filas = <_Fila>[];
  String? _error;

  static String _fmt(double v) => v == v.roundToDouble() ? v.round().toString() : v.toString();

  @override
  void initState() {
    super.initState();
    for (final p in widget.inicial.puntos) {
      _filas.add(_Fila(_fmt(p.horas), _fmt(p.temperatura)));
    }
    if (_filas.isEmpty) _filas.add(_Fila('', ''));
  }

  @override
  void dispose() {
    for (final f in _filas) {
      f.dispose();
    }
    super.dispose();
  }

  static double? _num(String t) => double.tryParse(t.trim().replaceAll(',', '.'));

  void _guardar() {
    final puntos = <PuntoIdeal>[];
    for (final f in _filas) {
      final h = f.horas.text.trim(), t = f.temp.text.trim();
      if (h.isEmpty && t.isEmpty) continue; // fila vacía: se ignora
      final horas = _num(h), temp = _num(t);
      if (horas == null || temp == null) {
        setState(() => _error = 'Cada fila necesita la hora y la temperatura, en números.');
        return;
      }
      if (horas < 0) {
        setState(() => _error = 'La hora no puede ser negativa.');
        return;
      }
      if (temp < -10 || temp > 80) {
        setState(() => _error = 'La temperatura debe estar entre -10 y 80 °C.');
        return;
      }
      puntos.add(PuntoIdeal(horas, temp));
    }
    Navigator.pop(context, CurvaIdeal(puntos));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Curva ideal'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Escriba la temperatura que espera a cada hora del lote (por ejemplo, la que le '
                'indique su técnico). La app no trae valores: se unen con rectas.',
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < _filas.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _filas[i].horas,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'Hora (h)', border: OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _filas[i].temp,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: '°C', border: OutlineInputBorder()),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Quitar este punto',
                        icon: const Icon(Icons.close),
                        onPressed: _filas.length == 1
                            ? null
                            : () => setState(() => _filas.removeAt(i).dispose()),
                      ),
                    ],
                  ),
                ),
              TextButton.icon(
                onPressed: () => setState(() => _filas.add(_Fila('', ''))),
                icon: const Icon(Icons.add),
                label: const Text('Agregar punto'),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        if (!widget.inicial.estaVacia)
          TextButton(onPressed: () => Navigator.pop(context, CurvaIdeal.vacia), child: const Text('Borrar curva')),
        FilledButton(onPressed: _guardar, child: const Text('Guardar')),
      ],
    );
  }
}
