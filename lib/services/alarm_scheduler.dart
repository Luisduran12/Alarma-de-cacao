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

/// Título, cuerpo y payload de la notificación de un registro de alarma.
///
/// Se deduce del `mensaje` que se guarda en el registro, de modo que los textos
/// salen siempre del mismo sitio: al crear el lote y al reprogramar una alarma
/// que el sistema perdió.
class TextoAlarma {
  final String titulo;
  final String cuerpo;
  final String payload;
  const TextoAlarma(this.titulo, this.cuerpo, this.payload);

  static const prefijoFinFermentacion = 'Fin de la fermentación';
  static const prefijoFinCiclo = 'Fin del ciclo';

  static String? _horas(String mensaje) => RegExp(r'\((\d+) h\)').firstMatch(mensaje)?.group(1);

  static TextoAlarma deRegistro({
    required String tituloLote,
    required String mensaje,
    required String loteId,
    required String volteadaId,
  }) {
    final horas = _horas(mensaje);
    if (mensaje.startsWith(prefijoFinFermentacion)) {
      return TextoAlarma(
        '$prefijoFinFermentacion - $tituloLote',
        '${horas == null ? 'Terminó la fermentación.' : 'Se cumplieron las $horas h.'} '
            'Haga la prueba de corte: toque para ver la guía.',
        // Abre la guía de la prueba de corte.
        NotificationService.payloadCorte(loteId, volteadaId),
      );
    }
    if (mensaje.startsWith(prefijoFinCiclo)) {
      return TextoAlarma(
        '$prefijoFinCiclo - $tituloLote',
        '${horas == null ? 'Terminó el ciclo.' : 'Terminó el ciclo de $horas h.'} '
            'Toca para registrar los datos finales.',
        NotificationService.payloadVolteada(loteId, volteadaId),
      );
    }
    final n = RegExp(r'Volteada (\d+)').firstMatch(mensaje)?.group(1);
    return TextoAlarma(
      n == null ? 'Volteada - $tituloLote' : 'Volteada $n - $tituloLote',
      'Es hora de voltear el cacao. Toca para registrar temperatura y humedad.',
      NotificationService.payloadVolteada(loteId, volteadaId),
    );
  }
}

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
          ? '${TextoAlarma.prefijoFinFermentacion} (${horas[i]} h) - ${fmt.format(fecha)}'
          : esFinal
              ? '${TextoAlarma.prefijoFinCiclo} (${horas[i]} h) - ${fmt.format(fecha)}'
              : 'Volteada ${i + 1} (${horas[i]} h) - ${fmt.format(fecha)}';
      final texto = TextoAlarma.deRegistro(
          tituloLote: titulo, mensaje: mensaje, loteId: loteId, volteadaId: volteadaId);

      try {
        await _programar(
          id: notifId,
          titulo: texto.titulo,
          cuerpo: texto.cuerpo,
          fechaProgramada: fecha,
          payload: texto.payload,
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

  /// Red de seguridad para teléfonos que bloquean el reinicio de alarmas (los
  /// ahorradores de batería de algunos Android lo hacen): reprograma, con el MISMO
  /// id, las alarmas de volteo y los recordatorios que todavía no han pasado y que
  /// el sistema ya no tiene en su lista [idsPendientes]. Las que siguen
  /// programadas no se tocan, así que no se duplica nada. Devuelve cuántas
  /// reprogramó. Se llama al abrir la app.
  Future<int> reprogramarFaltantes(Set<int> idsPendientes, {DateTime? ahora}) async {
    final corte = ahora ?? DateTime.now();
    var reprogramadas = 0;

    final lotes = await _loteService.loadLotes();
    final titulos = {for (final l in lotes) l.id: l.title};

    for (final lote in lotes) {
      for (final v in lote.volteadas) {
        if (v.confirmada || v.notifId == 0 || !v.fechaProgramada.isAfter(corte)) continue;
        if (idsPendientes.contains(v.notifId)) continue;
        final texto = TextoAlarma.deRegistro(
            tituloLote: lote.title, mensaje: v.mensaje, loteId: lote.id, volteadaId: v.id);
        try {
          await _programar(
            id: v.notifId,
            titulo: texto.titulo,
            cuerpo: texto.cuerpo,
            fechaProgramada: v.fechaProgramada,
            payload: texto.payload,
          );
          reprogramadas++;
        } catch (e) {
          debugPrint('No se pudo reprogramar la alarma ${v.notifId}: $e');
        }
      }
    }

    for (final r in await _recordatorios.todos()) {
      if (!r.fechaProgramada.isAfter(corte) || idsPendientes.contains(r.notifId)) continue;
      final titulo = titulos[r.loteId];
      if (titulo == null) continue;
      try {
        await _programar(
          id: r.notifId,
          titulo: 'Medir temperatura - $titulo',
          cuerpo: 'Mida la temperatura de la masa y anótela. Toca para registrar.',
          fechaProgramada: r.fechaProgramada,
          payload: NotificationService.payloadMedir(r.loteId),
          esRecordatorio: true,
        );
        reprogramadas++;
      } catch (e) {
        debugPrint('No se pudo reprogramar el recordatorio ${r.notifId}: $e');
      }
    }
    return reprogramadas;
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
