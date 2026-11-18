import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../data/cacao_database.dart';
import '../models/recordatorio.dart';
import 'notification_service.dart';

/// Acceso a la tabla `recordatorios` (SQLite).
class RecordatorioService {
  final Future<Database> Function() _db;
  final Future<void> Function(int notifId) _cancelarNotificacion;

  RecordatorioService({
    Future<Database> Function()? database,
    Future<void> Function(int notifId)? cancelarNotificacion,
  })  : _db = database ?? CacaoDatabase.instancia,
        _cancelarNotificacion =
            cancelarNotificacion ?? ((id) => NotificationService().cancelarNotificacion(id));

  Future<void> guardar(Recordatorio r) async {
    final db = await _db();
    await db.insert('recordatorios', r.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Recordatorio>> delLote(String loteId) async {
    final db = await _db();
    final filas = await db.query('recordatorios',
        where: 'lote_id = ?', whereArgs: [loteId], orderBy: 'fecha_programada ASC');
    return filas.map(Recordatorio.fromRow).toList();
  }

  /// Todos los recordatorios de todos los lotes (para revisar que sigan programados).
  Future<List<Recordatorio>> todos() async {
    final db = await _db();
    final filas = await db.query('recordatorios', orderBy: 'fecha_programada ASC');
    return filas.map(Recordatorio.fromRow).toList();
  }

  Future<List<Recordatorio>> futurosDelLote(String loteId, {DateTime? ahora}) async {
    final corte = ahora ?? DateTime.now();
    return (await delLote(loteId)).where((r) => r.fechaProgramada.isAfter(corte)).toList();
  }

  /// Cancela en el sistema las notificaciones de los recordatorios futuros del
  /// lote y los borra. Devuelve cuántos quitó. Un fallo al cancelar una
  /// notificación no impide borrar el resto.
  Future<int> eliminarFuturosDelLote(String loteId, {DateTime? ahora}) async {
    final futuros = await futurosDelLote(loteId, ahora: ahora);
    final db = await _db();
    for (final r in futuros) {
      try {
        await _cancelarNotificacion(r.notifId);
      } catch (e) {
        debugPrint('No se pudo cancelar el recordatorio ${r.notifId}: $e');
      }
      await db.delete('recordatorios', where: 'id = ?', whereArgs: [r.id]);
    }
    return futuros.length;
  }
}
