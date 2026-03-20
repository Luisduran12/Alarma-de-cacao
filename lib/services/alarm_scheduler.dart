import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:alarmacacao5_0/models/lote.dart';
import 'package:alarmacacao5_0/models/volteada.dart';
import 'package:alarmacacao5_0/services/lote_service.dart';
import 'package:alarmacacao5_0/services/notification_service.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:alarmacacao5_0/widgets/registro_formulario_dialog.dart';
import 'real_time_timer.dart';

class AlarmScheduler {
  final LoteService _loteService = LoteService();
  final Uuid _uuid = const Uuid();
  final NotificationService _notificationService = NotificationService();

  /// Programar alarmas predeterminadas (24h, 34h, 48h)
  Future<void> programarAlarmasPredeterminadas(
    Lote lote,
    Function(double) onProgressUpdate,
    Function(Lote) onLoteCompleted,
  ) async {
    try {
      final List<int> predefinedHours = [24, 34, 48];
      await _programarAlarmasReales(lote, predefinedHours, onProgressUpdate, onLoteCompleted);
    } catch (e) {
      debugPrint('❌ Error al programar alarmas predeterminadas: $e');
    }
  }

  /// Diálogo de usuario para configurar y programar alarmas personalizadas
  Future<Lote?> mostrarDialogoConfigurarYProgramar(
    BuildContext context, {
    required Function(double) onProgressUpdate,
    required Function(Lote) onLoteCompleted,
  }) async {
    final Map<String, dynamic>? dialogResult = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const RegistroFormularioDialog(),
    );

    if (dialogResult == null ||
        !(dialogResult.containsKey('title') && dialogResult.containsKey('hours'))) {
      debugPrint('⚠️ Diálogo cancelado o sin datos');
      return null;
    }

    final String title = dialogResult['title'] as String;
    final List<int> inputHours = dialogResult['hours'] as List<int>;
    final List<int> validHours = inputHours.where((h) => h > 0).toList();

    if (validHours.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Debes ingresar al menos una hora válida.')),
      );
      return null;
    }

    final Lote lote = Lote(
      id: _uuid.v4(),
      title: title.isNotEmpty ? title : 'Lote Personalizado',
      volteadas: [],
      status: 'en proceso',
      createdAt: DateTime.now(),
    );

    await _programarAlarmasReales(lote, validHours, onProgressUpdate, onLoteCompleted);
    return lote;
  }

  /// Lógica para programar las alarmas reales a partir de una lista de horas
  Future<void> _programarAlarmasReales(
    Lote lote,
    List<int> horas,
    Function(double) onProgressUpdate,
    Function(Lote) onLoteCompleted,
  ) async {
    try {
      final now = tz.TZDateTime.now(tz.local);
      final List<Volteada> nuevasVolteadas = [];
      final RealTimeTimer timer = RealTimeTimer();

      for (int i = 0; i < horas.length; i++) {
        final int h = horas[i];
        final int durationInSeconds = h * 3600;

        final tz.TZDateTime scheduledDate = now.add(Duration(hours: h));
        final String mensaje = 'Volteada ${i + 1} para el ${DateFormat('dd/MM/yyyy HH:mm').format(scheduledDate)}';

        // ✅ Llamada corregida usando parámetros nombrados
        await timer.startTimer(
          durationInSeconds,
          title: lote.title,
          mensaje: mensaje,
        );

        nuevasVolteadas.add(
          Volteada(
            id: _uuid.v4(),
            loteId: lote.id,
            mensaje: mensaje,
            temperatura: 0.0,
            humedad: 0.0,
            observacion: '',
            fecha: DateTime.now(),
            fechaProgramada: scheduledDate,
            confirmada: false,
          ),
        );

        // Actualizar progreso visual
        onProgressUpdate((i + 1) / horas.length);
        await Future.delayed(const Duration(milliseconds: 250));
      }

      // Crear lote actualizado con volteadas programadas
      final Lote actualizado = lote.copyWith(volteadas: nuevasVolteadas);
      await _loteService.saveLotes([actualizado]);

      onLoteCompleted(actualizado);

      debugPrint("✅ Lote '${actualizado.title}' guardado con ${nuevasVolteadas.length} volteadas.");
    } catch (e) {
      debugPrint("❌ Error al programar alarmas: $e");
    }
  }
}
