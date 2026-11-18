import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/volteada.dart';
import '../services/reglas_alerta.dart';
import '../widgets/editar_regla_dialog.dart';

/// Tabla de reglas de alerta: cada una con su fuente, que se pueden apagar,
/// editar, agregar o restaurar. Todo se guarda en el teléfono (sin internet).
class ReglasAlertaScreen extends StatefulWidget {
  const ReglasAlertaScreen({super.key});

  @override
  State<ReglasAlertaScreen> createState() => _ReglasAlertaScreenState();
}

class _ReglasAlertaScreenState extends State<ReglasAlertaScreen> {
  List<ReglaAlerta>? _reglas;

  @override
  void initState() {
    super.initState();
    ReglasAlertaStorage.cargar().then((r) {
      if (mounted) setState(() => _reglas = r);
    });
  }

  Future<void> _cambiar(List<ReglaAlerta> nuevas) async {
    await ReglasAlertaStorage.guardar(nuevas);
    if (mounted) setState(() => _reglas = nuevas);
  }

  String _rango(ReglaAlerta r) {
    String n(double v) => (v == v.roundToDouble() ? v.round().toString() : v.toString()).replaceAll('.', ',');
    final u = r.variable.unidad.isEmpty ? '' : ' ${r.variable.unidad}';
    final partes = [
      if (r.minimo != null) 'menos de ${n(r.minimo!)}$u',
      if (r.maximo != null) 'más de ${n(r.maximo!)}$u',
    ];
    final etapa = r.etapa == null ? '' : ' en ${Etapa.nombre(r.etapa!).toLowerCase()}';
    final desde = r.desdeHora == null ? '' : ', desde la hora ${n(r.desdeHora!)}';
    return 'Avisa si hay ${partes.join(' o ')}$etapa$desde';
  }

  Future<void> _editar(ReglaAlerta regla, {bool nueva = false}) async {
    final editada = await showDialog<ReglaAlerta>(context: context, builder: (_) => EditarReglaDialog(regla: regla));
    if (editada == null) return;
    final lista = [..._reglas!];
    final i = lista.indexWhere((r) => r.id == regla.id);
    if (nueva || i == -1) {
      lista.add(editada);
    } else {
      lista[i] = editada;
    }
    await _cambiar(lista);
  }

  Future<void> _borrar(ReglaAlerta regla) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Borrar regla'),
        content: Text(regla.deFabrica
            ? 'Es una regla que trae la app. Puede volver a tenerla con "Restaurar reglas".'
            : '¿Borrar esta regla?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Borrar')),
        ],
      ),
    );
    if (ok == true) await _cambiar([..._reglas!]..removeWhere((r) => r.id == regla.id));
  }

  Future<void> _restaurar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restaurar reglas'),
        content: const Text('Se borran sus cambios y sus reglas propias, y vuelven las que trae la app.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Restaurar')),
        ],
      ),
    );
    if (ok != true) return;
    await ReglasAlertaStorage.restaurar();
    final r = await ReglasAlertaStorage.cargar();
    if (mounted) setState(() => _reglas = r);
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final reglas = _reglas;
    return Scaffold(
      appBar: AppBar(title: const Text('Alertas por reglas'), actions: [
        IconButton(icon: const Icon(Icons.restore), tooltip: 'Restaurar reglas', onPressed: _restaurar),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: reglas == null
            ? null
            : () => _editar(
                  ReglaAlerta(
                    id: 'mia_${const Uuid().v4()}',
                    variable: VariableMedida.temperatura,
                    mensaje: '',
                    fuente: '',
                  ),
                  nueva: true,
                ),
        icon: const Icon(Icons.add),
        label: const Text('Agregar regla'),
      ),
      body: reglas == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                Text(
                  'Cuando guarda un registro, la app lo compara con estas reglas y le avisa si algún '
                  'valor sale de rango. Funciona sin internet. Es una guía, no reemplaza al técnico.',
                  style: tema.textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                if (reglas.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text('No hay reglas. Agregue una o restaure las que trae la app.'),
                  ),
                for (final r in reglas)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Expanded(
                              child: Text(r.variable.nombre,
                                  style: tema.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                            ),
                            Switch(
                              value: r.activa,
                              onChanged: (v) => _cambiar([
                                for (final x in reglas) x.id == r.id ? x.copyWith(activa: v) : x,
                              ]),
                            ),
                          ]),
                          Text(_rango(r), style: tema.textTheme.bodyLarge),
                          const SizedBox(height: 4),
                          Text(r.mensaje, style: tema.textTheme.bodyMedium),
                          const SizedBox(height: 6),
                          Text('Fuente: ${r.fuente}', style: tema.textTheme.bodySmall),
                          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                            TextButton.icon(
                                onPressed: () => _editar(r), icon: const Icon(Icons.edit), label: const Text('Editar')),
                            TextButton.icon(
                                onPressed: () => _borrar(r), icon: const Icon(Icons.delete_outline), label: const Text('Borrar')),
                          ]),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
