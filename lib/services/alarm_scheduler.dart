import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import 'package:alarmacacao5_0/models/lote.dart';
import 'package:alarmacacao5_0/models/recordatorio.dart';
import 'package:alarmacacao5_0/models/volteada.dart';
import 'package:alarmacacao5_0/services/lote_service.dart';
import 'package:alarmacacao5_0/services/notification_ids.dart';
import 'package:alarmacacao5_0/services/notification_service.dart';
import 'package:alarmacacao5_0/services/plan_recordatorios.dart';
import 'package:alarmacacao5_0/services/plantillas.dart';
import 'package:alarmacacao5_0/services/recordatorio_service.dart';
import 'package:alarmacacao5_0/widgets/registro_formulario_dialog.dart';

/// Función que programa una notificación en el sistema (por defecto, la de
/// [NotificationService]). Se puede cambiar en pruebas.
typedef ProgramarNotificacion = Future<void> Function({
  required int id,
  required String titulo,
  required String cuerpo,
  required DateTime fechaProgramada,
  String? payload,
  bool esRecordatorio,
});

/// Crea lotes y programa sus alarmas de volteo y recordatorios en el sistema
/// operativo (zonedSchedule), de modo que suenan aunque la app esté cerrada.
class AlarmScheduler {
  final LoteService _loteService;
  final RecordatorioService _recordatorios;
  final ProgramarNotificacion _programar;
  final Future<int> Function() _siguienteId;
  final Uuid _uuid = const Uuid();

  AlarmScheduler({
    LoteService? loteService,
    NotificationService? notificationService,
    RecordatorioService? recordatorioService,
    ProgramarNotificacion? programar,
    Future<int> Function()? siguienteId,
  })  : _loteService = loteService ?? LoteService(),
        _recordatorios = recordatorioService ?? RecordatorioService(),
        _programar = programar ?? (notificationService ?? NotificationService()).programarNotificacion,
        _siguienteId = siguienteId ?? NotificationIds.siguiente;

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
      final notifId = await _siguienteId();
      final finFermentacion = esFinal && plantilla.finEsFermentacion;
      final mensaje = finFermentacion
          ? 'Fin de la fermentación (${horas[i]} h) - ${fmt.format(fecha)}'
          : esFinal
              ? 'Fin del ciclo (${horas[i]} h) - ${fmt.format(fecha)}'
              : 'Volteada ${i + 1} (${horas[i]} h) - ${fmt.format(fecha)}';

      try {
        await _programar(
          id: notifId,
          titulo: finFermentacion
              ? 'Fin de la fermentación - $titulo'
              : esFinal
                  ? 'Fin del ciclo - $titulo'
                  : 'Volteada ${i + 1} - $titulo',
          cuerpo: finFermentacion
              ? 'Se cumplieron las ${plantilla.duracionHoras} h. Haga la prueba de corte: toque para ver la guía.'
              : esFinal
                  ? 'Terminó el ciclo de ${plantilla.duracionHoras} h. Toca para registrar los datos finales.'
                  : 'Es hora de voltear el cacao. Toca para registrar temperatura y humedad.',
          fechaProgramada: fecha,
          // El aviso de fin de fermentación abre la guía de la prueba de corte;
          // las demás alarmas abren el formulario de la volteada.
          payload: finFermentacion
              ? NotificationService.payloadCorte(loteId, volteadaId)
              : NotificationService.payloadVolteada(loteId, volteadaId),
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
    // Un fallo aquí no debe impedir que el lote exista con sus alarmas de volteo.
    try {
      await programarRecordatorios(lote);
    } catch (e) {
      debugPrint('No se pudieron programar los recordatorios del lote ${lote.id}: $e');
    }
    return lote;
  }

  /// Programa (o reprograma) los recordatorios de medir la temperatura del [lote]
  /// que aún no han pasado: uno cada 12 h, sin los que chocan con una alarma.
  /// Quita antes los futuros que hubiera, así que se puede llamar varias veces
  /// sin duplicar. Devuelve cuántos quedaron programados.
  Future<int> programarRecordatorios(Lote lote, {DateTime? ahora}) async {
    await _recordatorios.eliminarFuturosDelLote(lote.id, ahora: ahora);
    var programados = 0;
    for (final fecha in PlanRecordatorios.paraLote(lote, ahora: ahora)) {
      final notifId = await _siguienteId();
      try {
        await _programar(
          id: notifId,
          titulo: 'Medir temperatura - ${lote.title}',
          cuerpo: 'Mida la temperatura de la masa y anótela. Toca para registrar.',
          fechaProgramada: fecha,
          payload: NotificationService.payloadMedir(lote.id),
          esRecordatorio: true,
        );
      } catch (e) {
        // Si el sistema no lo programó, tampoco se guarda: no habría nada que cancelar ni reprogramar.
        debugPrint('No se pudo programar el recordatorio $notifId: $e');
        continue;
      }
      await _recordatorios.guardar(Recordatorio(
        id: _uuid.v4(),
        loteId: lote.id,
        notifId: notifId,
        fechaProgramada: fecha,
      ));
      programados++;
    }
    return programados;
  }

  /// Apaga los recordatorios futuros del lote (los ya pasados quedan como historial).
  Future<int> desactivarRecordatorios(String loteId, {DateTime? ahora}) =>
      _recordatorios.eliminarFuturosDelLote(loteId, ahora: ahora);

  /// true si el lote tiene algún recordatorio por venir.
  Future<bool> recordatoriosActivos(String loteId, {DateTime? ahora}) async =>
      (await _recordatorios.futurosDelLote(loteId, ahora: ahora)).isNotEmpty;

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
