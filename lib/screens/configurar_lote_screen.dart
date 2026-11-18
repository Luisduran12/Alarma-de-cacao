import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:alarmacacao5_0/services/alarm_scheduler.dart';
import 'package:alarmacacao5_0/services/notification_ids.dart';
import 'package:alarmacacao5_0/services/notification_service.dart';
import 'package:alarmacacao5_0/services/plantillas.dart';

/// Ruta '/configurar': crea un lote con horas personalizadas.
/// Usa el mismo AlarmScheduler que la pantalla principal (una sola lógica
/// para programar alarmas).
class ConfigurarLoteScreen extends StatefulWidget {
  const ConfigurarLoteScreen({super.key});

  @override
  State<ConfigurarLoteScreen> createState() => _ConfigurarLoteScreenState();
}

class _ConfigurarLoteScreenState extends State<ConfigurarLoteScreen> {
  final TextEditingController tituloController = TextEditingController();
  final List<TextEditingController> horasControllers = List.generate(5, (_) => TextEditingController());
  bool _guardando = false;

  Future<void> _crearLoteConAlarmas() async {
    final horas = horasControllers.map((c) => int.tryParse(c.text.trim()) ?? 0).toList();
    final plantilla = Plantillas.personalizada(horas);
    final messenger = ScaffoldMessenger.of(context);
    if (plantilla.horasVolteo.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('Ingresa al menos una hora válida.')));
      return;
    }
    setState(() => _guardando = true);
    final titulo = tituloController.text.trim();
    await AlarmScheduler().crearLote(
      titulo: titulo.isNotEmpty ? titulo : 'Lote sin nombre',
      plantilla: plantilla,
    );
    if (!mounted) return;
    setState(() => _guardando = false);
    messenger.showSnackBar(const SnackBar(content: Text('Lote creado con alarmas programadas')));
    Navigator.pop(context);
  }

  /// Alarma de prueba en 10 segundos.
  Future<void> _activarAlarmaDePrueba() async {
    await NotificationService().programarNotificacion(
      id: await NotificationIds.siguiente(),
      titulo: 'Alarma de prueba',
      cuerpo: 'Esta es una alarma de prueba',
      fechaProgramada: DateTime.now().add(const Duration(seconds: 10)),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Alarma de prueba en 10 segundos')),
    );
  }

  @override
  void dispose() {
    tituloController.dispose();
    for (final controller in horasControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configurar Lote de Volteadas')),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          TextField(
            controller: tituloController,
            decoration: const InputDecoration(labelText: 'Título del Lote'),
          ),
          const SizedBox(height: 10),
          ...List.generate(
            horasControllers.length,
            (index) => TextField(
              controller: horasControllers[index],
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(labelText: 'Volteada ${index + 1} (horas desde el inicio)'),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            icon: const Icon(Icons.alarm),
            label: const Text('Crear lote y programar alarmas'),
            onPressed: _guardando ? null : _crearLoteConAlarmas,
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            icon: const Icon(Icons.bolt),
            label: const Text('Probar alarma (10 s)'),
            onPressed: _activarAlarmaDePrueba,
          ),
        ],
      ),
    );
  }
}
