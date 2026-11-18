import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import 'package:alarmacacao5_0/data/cacao_database.dart';
import 'package:alarmacacao5_0/models/lote.dart';
import 'package:alarmacacao5_0/models/volteada.dart';
import 'package:alarmacacao5_0/services/notification_service.dart';

/// Acceso a lotes y registros. ÚNICA fuente de datos de la app (SQLite).
///
/// Reemplaza a los tres almacenamientos anteriores en SharedPreferences
/// ('lotes_guardados', 'volteadas' y 'lotes_data').
class LoteService {
  final Future<Database> Function() _db;
  final Future<void> Function(int notifId) _cancelarNotificacion;

  LoteService({
    Future<Database> Function()? database,
    Future<void> Function(int notifId)? cancelarNotificacion,
  })  : _db = database ?? CacaoDatabase.instancia,
        _cancelarNotificacion =
            cancelarNotificacion ?? ((id) => NotificationService().cancelarNotificacion(id));

  /// Carga todos los lotes (más recientes primero) con sus registros.
  Future<List<Lote>> loadLotes() async {
    final db = await _db();
    final filasLotes = await db.query('lotes', orderBy: 'creado_en DESC');
    final filasRegistros = await db.query('registros', orderBy: 'fecha_programada ASC');

    final porLote = <String, List<Volteada>>{};
    for (final r in filasRegistros) {
      final v = Volteada.fromRow(r);
      porLote.putIfAbsent(v.loteId, () => []).add(v);
    }
    return filasLotes.map((r) => Lote.fromRow(r, porLote[r['id']] ?? [])).toList();
  }

  /// Obtiene un lote específico por su ID (o null si no existe).
  Future<Lote?> obtenerLotePorId(String id) async {
    final db = await _db();
    final filas = await db.query('lotes', where: 'id = ?', whereArgs: [id]);
    if (filas.isEmpty) return null;
    return Lote.fromRow(filas.first, await obtenerRegistrosDelLote(id));
  }

  /// Todos los registros (programados y confirmados) de un lote.
  Future<List<Volteada>> obtenerRegistrosDelLote(String loteId) async {
    final db = await _db();
    final filas = await db.query('registros',
        where: 'lote_id = ?', whereArgs: [loteId], orderBy: 'fecha_programada ASC');
    return filas.map(Volteada.fromRow).toList();
  }

  /// Solo las volteadas CONFIRMADAS de un lote.
  /// (La versión anterior no filtraba por `confirmada` y devolvía todas.)
  Future<List<Volteada>> obtenerConfirmadasDelLote(String loteId) async {
    final db = await _db();
    final filas = await db.query('registros',
        where: 'lote_id = ? AND confirmada = 1', whereArgs: [loteId], orderBy: 'fecha ASC');
    return filas.map(Volteada.fromRow).toList();
  }

  /// Agrega un lote nuevo con sus registros. NO toca los demás lotes.
  Future<void> addLote(Lote lote) async {
    final db = await _db();
    await db.transaction((txn) async {
      await txn.insert('lotes', lote.toRow());
      for (final v in lote.volteadas) {
        await txn.insert('registros', v.toRow());
      }
    });
  }

  /// Actualiza un lote existente y deja sus registros exactamente como en
  /// `lote.volteadas`. NO toca los demás lotes.
  Future<void> updateLote(Lote lote) async {
    final db = await _db();
    await db.transaction((txn) async {
      final n = await txn.update('lotes', lote.toRow(), where: 'id = ?', whereArgs: [lote.id]);
      if (n == 0) {
        debugPrint('Lote no encontrado para actualizar: ${lote.id}');
        return;
      }
      final ids = lote.volteadas.map((v) => v.id).toList();
      if (ids.isEmpty) {
        await txn.delete('registros', where: 'lote_id = ?', whereArgs: [lote.id]);
      } else {
        await txn.delete('registros',
            where: 'lote_id = ? AND id NOT IN (${List.filled(ids.length, '?').join(',')})',
            whereArgs: [lote.id, ...ids]);
      }
      for (final v in lote.volteadas) {
        await txn.insert('registros', v.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  /// Inserta el lote si no existe o lo actualiza si ya existe.
  Future<void> upsertLote(Lote lote) async {
    if (await obtenerLotePorId(lote.id) == null) {
      await addLote(lote);
    } else {
      await updateLote(lote);
    }
  }

  /// Guarda (inserta o actualiza) cada lote de la lista.
  /// A diferencia de la versión anterior, NO borra los lotes que no estén
  /// en la lista: así ningún llamado puede eliminar datos por accidente.
  Future<void> saveLotes(List<Lote> lotes) async {
    for (final lote in lotes) {
      await upsertLote(lote);
    }
  }

  /// Inserta o reemplaza un solo registro (por ejemplo, al confirmar una volteada).
  Future<void> guardarRegistro(Volteada registro) async {
    final db = await _db();
    await db.insert('registros', registro.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Cambia el estado del lote.
  Future<void> actualizarEstado(String loteId, String estado) async {
    final db = await _db();
    await db.update('lotes', {'estado': estado}, where: 'id = ?', whereArgs: [loteId]);
  }

  /// Elimina un lote, sus registros y recordatorios, y cancela sus alarmas pendientes.
  Future<void> deleteLote(String loteId) async {
    final db = await _db();
    final pendientes = await db.query('registros',
        columns: ['notif_id'],
        where: 'lote_id = ? AND confirmada = 0 AND notif_id != 0',
        whereArgs: [loteId]);
    // También los recordatorios de medir la temperatura (su tabla se borra en cascada).
    final recordatorios = await db.query('recordatorios',
        columns: ['notif_id'], where: 'lote_id = ?', whereArgs: [loteId]);
    for (final r in [...pendientes, ...recordatorios]) {
      try {
        await _cancelarNotificacion(r['notif_id'] as int);
      } catch (e) {
        debugPrint('No se pudo cancelar la notificación ${r['notif_id']}: $e');
      }
    }
    await db.transaction((txn) async {
      await txn.delete('registros', where: 'lote_id = ?', whereArgs: [loteId]);
      await txn.delete('lotes', where: 'id = ?', whereArgs: [loteId]);
    });
  }
}
