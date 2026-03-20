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
    DateTime fechaProgramada = ahora;

    if (lote != null) {
      final volteadaOriginal = lote.volteadas.firstWhere(
        (v) => v.mensaje == widget.mensaje,
        orElse: () => Volteada(fecha: ahora, fechaProgramada: ahora, id: '', loteId: '', mensaje: '', temperatura: 0, humedad: 0, observacion: '', confirmada: false),
      );
      fechaProgramada = volteadaOriginal.fechaProgramada;
    }

    final nuevaVolteada = Volteada(
      id: const Uuid().v4(),
      loteId: widget.loteId,
      mensaje: widget.mensaje,
      temperatura: temperatura,
      humedad: humedad,
      observacion: observacion,
      fecha: ahora,
      fechaProgramada: fechaProgramada,
      confirmada: true,
    );

    await _volteadaService.guardarVolteada(nuevaVolteada);

    // Comprobar si se completó el lote
    final confirmadas = await _volteadaService.obtenerConfirmadasDelLote(widget.loteId);
    if (lote != null && confirmadas.length >= lote.volteadas.length) {
      final loteCompletado = lote.copyWith(status: 'completado');
      await _loteService.updateLote(loteCompletado);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('🎉 Lote completado')),
      );
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('✅ Volteada confirmada')),
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
