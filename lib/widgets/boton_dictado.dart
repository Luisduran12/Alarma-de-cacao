import 'package:flutter/material.dart';

import '../services/consentimiento_voz.dart';
import '../services/dictado.dart';

/// Botón de micrófono para dictar dentro de un campo de texto. Es opcional: el campo se puede escribir igual.
/// Lo dictado se AGREGA al final de lo que ya había escrito. Antes de la primera vez se explica y se pide autorización.
class BotonDictado extends StatefulWidget {
  final TextEditingController controller;
  final MotorDictado? motor;
  final Future<bool?> Function()? leerConsentimiento;
  final Future<void> Function(bool)? guardarConsentimiento;

  const BotonDictado({super.key, required this.controller, this.motor, this.leerConsentimiento, this.guardarConsentimiento});

  @override
  State<BotonDictado> createState() => _BotonDictadoState();
}

class _BotonDictadoState extends State<BotonDictado> {
  late final MotorDictado _motor = widget.motor ?? MotorDictadoReal();
  bool _escuchando = false;
  String _antes = '';

  @override
  void dispose() {
    if (_escuchando) _motor.detener();
    super.dispose();
  }

  void _aviso(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  Future<bool> _autorizado() async {
    final v = await (widget.leerConsentimiento ?? ConsentimientoVoz.obtener)();
    if (v != null) return v;
    if (!mounted) return false;
    final acepta = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text(ConsentimientoVoz.titulo),
        content: const SingleChildScrollView(child: Text(ConsentimientoVoz.texto)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('No, usar el teclado')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Sí, dictar')),
        ],
      ),
    );
    if (acepta == null) return false;
    await (widget.guardarConsentimiento ?? ConsentimientoVoz.registrar)(acepta);
    return acepta;
  }

  Future<void> _alternar() async {
    if (_escuchando) {
      await _motor.detener();
      if (mounted) setState(() => _escuchando = false);
      return;
    }
    if (!await _autorizado()) return;
    final listo = await _motor.preparar(alError: (e) {
      if (mounted) setState(() => _escuchando = false);
      _aviso('No se pudo escuchar. Escriba la observación con el teclado.');
    });
    if (!listo) {
      _aviso('El dictado no está disponible (sin permiso del micrófono o sin servicio de voz). Escriba con el teclado.');
      return;
    }
    _antes = widget.controller.text.trimRight();
    setState(() => _escuchando = true);
    try {
      await _motor.escuchar(alTexto: (texto, esFinal) {
        if (!mounted) return;
        final nuevo = texto.trim();
        widget.controller.text = nuevo.isEmpty ? _antes : (_antes.isEmpty ? nuevo : '$_antes $nuevo');
        widget.controller.selection = TextSelection.collapsed(offset: widget.controller.text.length);
        if (esFinal) setState(() => _escuchando = false);
      });
    } catch (_) {
      if (mounted) setState(() => _escuchando = false);
      _aviso('No se pudo escuchar. Escriba la observación con el teclado.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: _escuchando ? 'Dejar de escuchar' : 'Dictar con la voz',
      icon: Icon(_escuchando ? Icons.stop_circle : Icons.mic, color: _escuchando ? Theme.of(context).colorScheme.error : null),
      onPressed: _alternar,
    );
  }
}
