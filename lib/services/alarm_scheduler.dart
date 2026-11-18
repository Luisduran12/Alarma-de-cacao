import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import 'package:alarmacacao5_0/models/lote.dart';
import 'package:alarmacacao5_0/models/volteada.dart';
import 'package:alarmacacao5_0/services/lote_service.dart';
import 'package:alarmacacao5_0/services/notification_ids.dart';
import 'package:alarmacacao5_0/services/notification_service.dart';
import 'package:alarmacacao5_0/services/plantillas.dart';
import 'package:alarmacacao5_0/widgets/registro_formulario_dialog.dart';

/// Crea lotes y programa sus alarmas de volteo en el sistema operativo
/// (zonedSchedule), de modo que suenan aunque la app esté cerrada.
class AlarmScheduler {
  final LoteService _loteService;
  final NotificationService _notificationService;
  final Uuid _uuid = const Uuid();

  AlarmScheduler({LoteService? loteService, NotificationService? notificationService})
      : _loteService = loteService ?? LoteService(),
        _notificationService = notificationService ?? NotificationService();

  /// Crea un lote a partir de una plantilla, programa todas sus alarmas y lo
  /// guarda en la base de datos (sin tocar los demás lotes).
  Future<Lote> crearLote({required String titulo, required PlantillaCiclo plantilla}) async {
    final inicio = DateTime.now();
    final loteId = _uuid.v4();
    final fmt = DateFormat('dd/MM/yyyy HH:mm');
    final volteadas = <Volteada>[];

    final horas = [
      ...plantilla.horasVolteo,
      if (plantilla.tieneAlarmaFinal) plantilla.duracionHoras,
    ];

    for (var i = 0; i < horas.length; i++) {
      final esFinal = plantilla.tieneAlarmaFinal && i == horas.length - 1;
      final fecha = inicio.add(Duration(hours: horas[i]));
      final volteadaId = _uuid.v4();
      final notifId = await NotificationIds.siguiente();
      final mensaje = esFinal
          ? 'Fin del ciclo (${horas[i]} h) - ${fmt.format(fecha)}'
          : 'Volteada ${i + 1} (${horas[i]} h) - ${fmt.format(fecha)}';

      try {
        await _notificationService.programarNotificacion(
          id: notifId,
          titulo: esFinal ? 'Fin del ciclo - $titulo' : 'Volteada ${i + 1} - $titulo',
          cuerpo: esFinal
              ? 'Terminó el ciclo de ${plantilla.duracionHoras} h. Toca para registrar los datos finales.'
              : 'Es hora de voltear el cacao. Toca para registrar temperatura y humedad.',
          fechaProgramada: fecha,
          payload: NotificationService.payloadVolteada(loteId, volteadaId),
        );
      } catch (e) {
        debugPrint('No se pudo programar la alarma $notifId: $e');
      }

      volteadas.add(Volteada(
        id: volteadaId,
        loteId: loteId,
        mensaje: mensaje,
        temperatura: 0,
        humedad: 0,
        observacion: '',
        fecha: inicio,
        fechaProgramada: fecha,
        confirmada: false,
        notifId: notifId,
      ));
    }

    final lote = Lote(
      id: loteId,
      title: titulo,
      status: 'en proceso',
      createdAt: inicio,
      inicioCiclo: inicio,
      finCiclo: inicio.add(Duration(hours: plantilla.duracionHoras)),
      plantilla: plantilla.id,
      volteadas: volteadas,
    );
    await _loteService.addLote(lote);
    return lote;
  }

  /// Muestra el formulario de horas personalizadas y crea el lote.
  Future<Lote?> crearLotePersonalizado(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final resultado = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const RegistroFormularioDialog(),
    );
    if (resultado == null) return null;

    final titulo = (resultado['title'] as String).trim();
    final plantilla = Plantillas.personalizada(resultado['hours'] as List<int>);
    if (plantilla.horasVolteo.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Debes ingresar al menos una hora válida.')),
      );
      return null;
    }
    return crearLote(
      titulo: titulo.isNotEmpty ? titulo : 'Lote personalizado',
      plantilla: plantilla,
    );
  }
}
