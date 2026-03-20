import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:alarmacacao5_0/models/lote.dart';
import 'package:alarmacacao5_0/models/volteada.dart';
import 'package:alarmacacao5_0/services/lote_service.dart';
import 'package:alarmacacao5_0/services/notification_service.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:alarmacacao5_0/widgets/registro_formulario_dialog.dart';

class AlarmScheduler {
  final LoteService _loteService = LoteService();
  final Uuid _uuid = const Uuid();
  final NotificationService _notificationService = NotificationService();

  Future<void> programarAlarmasPredeterminadas(
    Lote lote,
    Function(double) onProgressUpdate,
    Function(Lote) onLoteCompleted,
  ) async {
    const int totalVolteadas = 5;
    List<int> predefinedHours = List.generate(totalVolteadas, (i) => 48 + (i * 24)); // 48, 72, 96, 120, 144
    await _programarAlarmasReales(lote, predefinedHours, onProgressUpdate, onLoteCompleted);
  }

  Future<Lote?> mostrarDialogoConfigurarYProgramar(
    BuildContext context, {
    required Function(double) onProgressUpdate,
    required Function(Lote) onLoteCompleted,
  }) async {
    final Map<String, dynamic>? dialogResult = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (BuildContext dialogContext) {
        return const RegistroFormularioDialog();
      },
    );

    if (dialogResult == null || !(dialogResult.containsKey('title') && dialogResult.containsKey('hours'))) {
      debugPrint('DEBUG: Creación de lote cancelada o datos del diálogo incompletos.');
      return null;
    }

    final String loteTitle = dialogResult['title'] as String;
    final List<int> inputHours = dialogResult['hours'] as List<int>;
    List<int> validHours = inputHours.where((h) => h > 0).toList();

    if (validHours.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se ingresaron horas válidas (> 0).')),
      );
      debugPrint('DEBUG: No se encontraron horas válidas.');
      return null;
    }

    Lote newLote = Lote(
      id: _uuid.v4(),
      title: loteTitle.isEmpty ? 'Lote Personalizado' : loteTitle,
      volteadas: [],
      status: 'en proceso',
      createdAt: DateTime.now(),
    );

    await _programarAlarmasReales(newLote, validHours, onProgressUpdate, onLoteCompleted);

    return newLote;
  }

  Future<void> _programarAlarmasReales(
    Lote lote,
    List<int> hoursToSchedule,
    Function(double) onProgressUpdate,
    Function(Lote) onLoteCompleted,
  ) async {
    Lote currentLote = lote;
    final int totalVolteadas = hoursToSchedule.length;
    List<Volteada> volteadasProgramadas = [];

    for (int i = 0; i < totalVolteadas; i++) {
      int currentHour = hoursToSchedule[i];
      final scheduledTime = tz.TZDateTime.now(tz.local).add(Duration(hours: currentHour));
      final message = 'Volteada ${i + 1} programada para ${DateFormat('dd/MM/yyyy HH:mm').format(scheduledTime)}';

      await _notificationService.programarNotificacion(
        id: currentLote.id.hashCode + i,
        titulo: currentLote.title,
        cuerpo: message,
        fechaProgramada: scheduledTime,
        payload: '${currentLote.id}|${currentLote.title}|$message|${scheduledTime.toIso8601String()}',
      );

      final nuevaVolteada = Volteada(
        id: _uuid.v4(),
        loteId: currentLote.id,
        mensaje: message,
        temperatura: 0.0,
        humedad: 0.0,
        observacion: '',
        fecha: DateTime.now(),           // Fecha de creación
        fechaProgramada: scheduledTime, // Cuándo debe sonar
        confirmada: false,              // Aún no ha sido confirmada
      );

      volteadasProgramadas.add(nuevaVolteada);
      onProgressUpdate((i + 1) / totalVolteadas.toDouble());
      await Future.delayed(const Duration(milliseconds: 300));
    }

    currentLote = currentLote.copyWith(volteadas: volteadasProgramadas);
    onLoteCompleted(currentLote);
  }
}
