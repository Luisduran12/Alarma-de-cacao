import 'package:flutter/material.dart';

import '../models/volteada.dart';
import '../services/reglas_alerta.dart';

/// Crea o edita una regla de alerta. Devuelve la regla o null si se cancela.
///
/// Toda regla debe llevar su fuente: si la cifra la dio un técnico o un
/// documento, se anota ahí para poder comprobarla después.
class EditarReglaDialog extends StatefulWidget {
  final ReglaAlerta regla;
  const EditarReglaDialog({super.key, required this.regla});

  @override
  State<EditarReglaDialog> createState() => _EditarReglaDialogState();
}

class _EditarReglaDialogState extends State<EditarReglaDialog> {
  late VariableMedida _variable;
  String? _etapa;
  late final TextEditingController _min, _max, _desde, _mensaje, _fuente;
  String? _error;

  static String _txt(double? v) =>
      v == null ? '' : (v == v.roundToDouble() ? v.round().toString() : v.toString());

  @override
  void initState() {
    super.initState();
    final r = widget.regla;
    _variable = r.variable;
    _etapa = r.etapa;
    _min = TextEditingController(text: _txt(r.minimo));
    _max = TextEditingController(text: _txt(r.maximo));
    _desde = TextEditingController(text: _txt(r.desdeHora));
    _mensaje = TextEditingController(text: r.mensaje);
    _fuente = TextEditingController(text: r.fuente);
  }

  @override
  void dispose() {
    for (final c in [_min, _max, _desde, _mensaje, _fuente]) {
      c.dispose();
    }
    super.dispose();
  }

  /// null = vacío; double.nan = texto que no es número.
  static double? _num(String t) {
    final s = t.trim().replaceAll(',', '.');
    if (s.isEmpty) return null;
    return double.tryParse(s) ?? double.nan;
  }

  void _guardar() {
    final min = _num(_min.text), max = _num(_max.text), desde = _num(_desde.text);
    String? error;
    if ([min, max, desde].any((v) => v != null && v.isNaN)) {
      error = 'Escriba solo números en los límites y en la hora.';
    } else if (min == null && max == null) {
      error = 'Escriba al menos un límite: mínimo o máximo.';
    } else if (min != null && max != null && min > max) {
      error = 'El mínimo no puede ser mayor que el máximo.';
    } else if (desde != null && desde < 0) {
      error = 'La hora no puede ser negativa.';
    } else if (_mensaje.text.trim().isEmpty) {
      error = 'Escriba qué debe hacer el productor cuando salte la alerta.';
    } else if (_fuente.text.trim().isEmpty) {
      error = 'Anote la fuente de la regla (por ejemplo, el nombre de su técnico o el documento).';
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(
      context,
      ReglaAlerta(
        id: widget.regla.id,
        variable: _variable,
        etapa: _etapa,
        minimo: min,
        maximo: max,
        desdeHora: desde,
        activa: widget.regla.activa,
        mensaje: _mensaje.text.trim(),
        fuente: _fuente.text.trim(),
        deFabrica: widget.regla.deFabrica,
      ),
    );
  }

  Widget _campoNumero(TextEditingController c, String etiqueta) => TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: etiqueta, border: const OutlineInputBorder()),
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.regla.deFabrica ? 'Editar regla' : 'Regla de alerta'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<VariableMedida>(
              initialValue: _variable,
              decoration: const InputDecoration(labelText: 'Qué se vigila', border: OutlineInputBorder()),
              items: [for (final v in VariableMedida.values) DropdownMenuItem(value: v, child: Text(v.nombre))],
              onChanged: (v) => setState(() => _variable = v ?? _variable),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: _etapa,
              decoration: const InputDecoration(labelText: 'En qué etapa', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: null, child: Text('Cualquiera')),
                DropdownMenuItem(value: Etapa.fermentacion, child: Text('Fermentación')),
                DropdownMenuItem(value: Etapa.secado, child: Text('Secado')),
              ],
              onChanged: (v) => setState(() => _etapa = v),
            ),
            const SizedBox(height: 12),
            const Text('Avisar si el valor sale de este rango:'),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _campoNumero(_min, 'Mínimo')),
              const SizedBox(width: 8),
              Expanded(child: _campoNumero(_max, 'Máximo')),
            ]),
            const SizedBox(height: 12),
            _campoNumero(_desde, 'Desde la hora del lote (opcional)'),
            const SizedBox(height: 12),
            TextField(
              controller: _mensaje,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Qué debe hacer', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _fuente,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Fuente de la regla', border: OutlineInputBorder()),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _guardar, child: const Text('Guardar')),
      ],
    );
  }
}
