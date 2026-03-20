import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:alarmacacao5_0/services/notification_service.dart';
import 'package:alarmacacao5_0/services/lote_service.dart';
import 'package:alarmacacao5_0/models/lote.dart';
import 'package:alarmacacao5_0/models/volteada.dart';
import 'package:alarmacacao5_0/main.dart'; // Para navigatorKey

class ConfigurarLoteScreen extends StatefulWidget {
  @override
  _ConfigurarLoteScreenState createState() => _ConfigurarLoteScreenState();
}

class _ConfigurarLoteScreenState extends State<ConfigurarLoteScreen> {
  final TextEditingController tituloController = TextEditingController();
  final List<TextEditingController> horasControllers = List.generate(5, (_) => TextEditingController());

  final LoteService _loteService = LoteService();
  final NotificationService _notiService = NotificationService();
  final uuid = const Uuid();

  /// Botón 1: Crea un lote de alarmas personalizadas
  Future<void> _crearLoteConAlarmas() async {
    final now = DateTime.now();
    final String titulo = tituloController.text.trim();
    final String loteId = uuid.v4();

    List<Volteada> volteadas = [];

    for (int i = 0; i < horasControllers.length; i++) {
      final String texto = horasControllers[i].text.trim();
      if (texto.isNotEmpty && int.tryParse(texto) != null) {
        final int horas = int.parse(texto);
        if (horas > 0) {
          final DateTime fechaProgramada = now.add(Duration(hours: horas));
          final String mensaje = 'Volteada #${i + 1} programada para $horas horas';
          final String idVolteada = uuid.v4();

          await _notiService.programarNotificacion(
            id: idVolteada.hashCode,
            titulo: 'Alarma Volteada',
            cuerpo: mensaje,
            fechaProgramada: fechaProgramada,
            payload: '$loteId|$titulo|$mensaje|${fechaProgramada.toIso8601String()}',
          );

          volteadas.add(
            Volteada(
              id: idVolteada,
              loteId: loteId,
              mensaje: mensaje,
              temperatura: 0.0,
              humedad: 0.0,
              observacion: '',
              fecha: now,
              fechaProgramada: fechaProgramada,
              confirmada: false,
            ),
          );
        }
      }
    }

    final nuevoLote = Lote(
      id: loteId,
      title: titulo.isNotEmpty ? titulo : 'Lote sin nombre',
      createdAt: now,
      volteadas: volteadas,
      status: 'pendiente',
    );

    List<Lote> lotesExistentes = await _loteService.loadLotes();
    lotesExistentes.add(nuevoLote);
    await _loteService.saveLotes(lotesExistentes);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Lote creado con alarmas programadas')),
      );
    }
  }

  /// Botón 2: Alarma predeterminada de prueba
  Future<void> _activarAlarmaPredeterminada() async {
    final now = DateTime.now();
    final DateTime fechaProgramada = now.add(const Duration(seconds: 10));

    await _notiService.programarNotificacion(
      id: now.millisecondsSinceEpoch % 100000,
      titulo: 'Alarma Rápida',
      cuerpo: 'Esta es una alarma predeterminada de prueba',
      fechaProgramada: fechaProgramada,
      payload: 'predeterminada',
    );

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⏰ Alarma predeterminada activada')),
      );
    }
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
      appBar: AppBar(
        title: const Text('Configurar Lote de Volteadas'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
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
                decoration: InputDecoration(labelText: 'Volteada ${index + 1} (horas)'),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.alarm),
              label: const Text('Iniciar Simulación'),
              onPressed: _crearLoteConAlarmas,
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              icon: const Icon(Icons.bolt),
              label: const Text('Alarma Predeterminada'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              onPressed: _activarAlarmaPredeterminada,
            ),
          ],
        ),
      ),
    );
  }
}
