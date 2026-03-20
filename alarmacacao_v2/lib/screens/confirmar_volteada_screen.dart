import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:alarmacacao5_0/models/volteada.dart';
import 'package:alarmacacao5_0/models/lote.dart';
import 'package:alarmacacao5_0/services/volteada_service.dart';
import 'package:alarmacacao5_0/services/lote_service.dart';

class ConfirmarVolteadaScreen extends StatefulWidget {
  final String loteId;
  final String mensaje;

  const ConfirmarVolteadaScreen({
    super.key,
    required this.loteId,
    required this.mensaje,
  });

  @override
  State<ConfirmarVolteadaScreen> createState() => _ConfirmarVolteadaScreenState();
}

class _ConfirmarVolteadaScreenState extends State<ConfirmarVolteadaScreen> {
  final _formKey = GlobalKey<FormState>();
  final _tempController = TextEditingController();
  final _humedadController = TextEditingController();
  final _observacionController = TextEditingController();

  final _volteadaService = VolteadaService();
  final _loteService = LoteService();

  @override
  void dispose() {
    _tempController.dispose();
    _humedadController.dispose();
    _observacionController.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (_formKey.currentState!.validate()) {
      final double temperatura = double.tryParse(_tempController.text.trim()) ?? 0.0;
      final double humedad = double.tryParse(_humedadController.text.trim()) ?? 0.0;
      final String observacion = _observacionController.text.trim();

      final ahora = DateTime.now();

      final volteada = Volteada(
        id: const Uuid().v4(),
        loteId: widget.loteId,
        mensaje: widget.mensaje,
        temperatura: temperatura,
        humedad: humedad,
        observacion: observacion,
        fecha: ahora,
        fechaProgramada: ahora, // ✅ Campo obligatorio añadido correctamente
        confirmada: true, // o false, según tu lógica
      );

      await _volteadaService.guardarVolteada(volteada);

      final confirmadas = await _volteadaService.obtenerConfirmadasDelLote(widget.loteId);
      final loteActual = await _loteService.obtenerLotePorId(widget.loteId);

      if (loteActual != null && confirmadas.length >= loteActual.volteadas.length) {
        final loteCompletado = loteActual.copyWith(status: 'completado');
        await _loteService.updateLote(loteCompletado);

        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('🎉 Lote marcado como completado')),
        );
      }

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Volteada confirmada y registrada')),
      );

      Navigator.pop(context);
    }
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
                '🧾 Lote: ${widget.loteId}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              Text(
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
                label: 'Observaciones',
                controller: _observacionController,
                keyboardType: TextInputType.text,
                maxLines: 3,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _guardar,
                icon: const Icon(Icons.save),
                label: const Text('Guardar datos'),
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
