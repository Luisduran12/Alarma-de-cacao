import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:alarmacacao5_0/models/volteada.dart';
import 'package:alarmacacao5_0/services/lote_service.dart';

class ConfirmarVolteadaScreen extends StatefulWidget {
  final String loteId;
  final String volteadaId;
  final String mensaje;

  const ConfirmarVolteadaScreen({
    super.key,
    required this.loteId,
    this.volteadaId = '',
    this.mensaje = '',
  });

  @override
  State<ConfirmarVolteadaScreen> createState() => _ConfirmarVolteadaScreenState();
}

class _ConfirmarVolteadaScreenState extends State<ConfirmarVolteadaScreen> {
  final _formKey = GlobalKey<FormState>();
  final _tempController = TextEditingController();
  final _humedadController = TextEditingController();
  final _observacionController = TextEditingController();

  final _loteService = LoteService();

  bool _guardando = false;

  @override
  void dispose() {
    _tempController.dispose();
    _humedadController.dispose();
    _observacionController.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _guardando = true);

    final double temperatura = double.tryParse(_tempController.text.trim()) ?? 0.0;
    final double humedad = double.tryParse(_humedadController.text.trim()) ?? 0.0;
    final String observacion = _observacionController.text.trim();
    final ahora = DateTime.now();

    final lote = await _loteService.obtenerLotePorId(widget.loteId);
    if (lote == null) {
      if (!mounted) return;
      setState(() => _guardando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se encontró el lote de esta volteada.')),
      );
      return;
    }

    // Se busca la volteada PROGRAMADA (por id; o por mensaje en alarmas antiguas)
    // y se ACTUALIZA. Antes se agregaba una nueva volteada cada vez: duplicados.
    final volteadas = List<Volteada>.from(lote.volteadas);
    int index = widget.volteadaId.isNotEmpty
        ? volteadas.indexWhere((v) => v.id == widget.volteadaId)
        : volteadas.indexWhere((v) => v.mensaje == widget.mensaje && !v.confirmada);

    final base = index == -1 ? null : volteadas[index];
    final registro = Volteada(
      id: base?.id ?? const Uuid().v4(),
      loteId: widget.loteId,
      mensaje: base?.mensaje ?? widget.mensaje,
      temperatura: temperatura,
      humedad: humedad,
      observacion: observacion,
      fecha: ahora,
      fechaProgramada: base?.fechaProgramada ?? ahora,
      confirmada: true,
    );
    if (index == -1) {
      volteadas.add(registro);
    } else {
      volteadas[index] = registro;
    }

    final completado = volteadas.every((v) => v.confirmada);
    await _loteService.updateLote(lote.copyWith(
      volteadas: volteadas,
      status: completado ? 'completado' : lote.status,
    ));

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(completado ? '🎉 Lote completado' : '✅ Volteada confirmada')),
    );
    Navigator.pop(context);
  }

  Widget _buildTextInput({
    required String label,
    required TextEditingController controller,
    required TextInputType keyboardType,
    String? Function(String?)? validator,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      validator: validator,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Confirmar Volteada')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              Text(
                '🧾 Lote ID: ${widget.loteId}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              if (widget.mensaje.isNotEmpty) Text(
                '📅 Alarma: ${widget.mensaje}',
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 24),
              _buildTextInput(
                label: 'Temperatura (°C)',
                controller: _tempController,
                keyboardType: TextInputType.number,
                validator: (val) {
                  if (val == null || val.trim().isEmpty) return 'Ingrese la temperatura';
                  final temp = double.tryParse(val);
                  if (temp == null || temp < 0) return 'Valor inválido';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              _buildTextInput(
                label: 'Humedad (%)',
                controller: _humedadController,
                keyboardType: TextInputType.number,
                validator: (val) {
                  if (val == null || val.trim().isEmpty) return 'Ingrese la humedad';
                  final hum = double.tryParse(val);
                  if (hum == null || hum < 0) return 'Valor inválido';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              _buildTextInput(
                label: 'Observación',
                controller: _observacionController,
                keyboardType: TextInputType.text,
                maxLines: 3,
                validator: (val) => (val == null || val.trim().isEmpty) ? 'Ingrese una observación' : null,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _guardando ? null : _guardar,
                icon: _guardando
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.save),
                label: Text(_guardando ? 'Guardando...' : 'Guardar datos'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
