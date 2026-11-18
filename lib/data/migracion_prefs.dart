import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../models/lote.dart';
import '../models/volteada.dart';

/// Migra a SQLite los datos que las versiones anteriores guardaban en
/// SharedPreferences, en tres lugares distintos:
///
///  - 'lotes_guardados' (LoteService)          → lotes con sus volteadas
///  - 'lotes_data'      (LoteStorageService)   → lotes (servicio no usado)
///  - 'volteadas'       (VolteadaService)      → volteadas confirmadas sueltas
///
/// No se borra nada de SharedPreferences: las claves antiguas se conservan
/// como respaldo y solo se marca que la migración ya se hizo.
class MigracionPrefs {
  static const String claveHecha = 'migrado_a_sqlite_v1';

  static Future<void> migrarSiHaceFalta(Database db) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(claveHecha) ?? false) return;

    final lotes = combinar(
      lotesGuardados: prefs.getString('lotes_guardados'),
      lotesData: prefs.getString('lotes_data'),
      volteadas: prefs.getStringList('volteadas') ?? const [],
    );

    await db.transaction((txn) async {
      for (final lote in lotes) {
        await txn.insert('lotes', lote.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);
        for (final v in lote.volteadas) {
          await txn.insert('registros', v.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
    });

    await prefs.setBool(claveHecha, true);
    debugPrint('Migración a SQLite: ${lotes.length} lotes, '
        '${lotes.fold<int>(0, (s, l) => s + l.volteadas.length)} registros.');
  }

  /// Une los tres orígenes en una lista de lotes, sin perder datos y sin
  /// duplicar volteadas. Es una función pura para poder probarla.
  @visibleForTesting
  static List<Lote> combinar({
    String? lotesGuardados,
    String? lotesData,
    List<String> volteadas = const [],
  }) {
    final porId = <String, Lote>{};

    // 'lotes_data' primero; 'lotes_guardados' (el que usaba la app) tiene prioridad.
    for (final origen in [lotesData, lotesGuardados]) {
      for (final lote in _leerLotes(origen)) {
        porId[lote.id] = lote.copyWith(
          volteadas: lote.volteadas
              .map((v) => v.loteId.isEmpty ? _conLote(v, lote.id) : v)
              .toList(),
        );
      }
    }

    for (final crudo in volteadas) {
      final Volteada v;
      try {
        v = Volteada.fromJson(jsonDecode(crudo) as Map<String, dynamic>);
      } catch (_) {
        continue; // entrada corrupta: se ignora
      }
      if (v.loteId.isEmpty) continue;

      // Volteada de un lote que ya no existe: se conserva en un lote "migrado".
      final lote = porId[v.loteId] ??
          Lote(
            id: v.loteId,
            title: 'Lote migrado ${v.loteId.length > 6 ? v.loteId.substring(0, 6) : v.loteId}',
            status: 'migrado',
            createdAt: v.fecha,
          );
      porId[v.loteId] = lote.copyWith(volteadas: _agregarSinDuplicar(lote.volteadas, v));
    }

    // Garantiza ids únicos de registros dentro de toda la base.
    final vistos = <String>{};
    return porId.values.map((l) {
      final unicas = l.volteadas.where((v) => v.id.isNotEmpty && vistos.add(v.id)).toList();
      return l.copyWith(volteadas: unicas);
    }).toList();
  }

  static List<Lote> _leerLotes(String? json) {
    if (json == null || json.isEmpty) return const [];
    try {
      return (jsonDecode(json) as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .map(Lote.fromJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Volteada _conLote(Volteada v, String loteId) => Volteada.fromJson({...v.toJson(), 'loteId': loteId});

  static bool _vacia(Volteada v) => v.temperatura == 0 && v.humedad == 0 && v.observacion.isEmpty;

  static List<Volteada> _agregarSinDuplicar(List<Volteada> actuales, Volteada v) {
    final lista = List<Volteada>.from(actuales);
    if (lista.any((x) => x.id == v.id)) return lista;

    if (v.confirmada && v.mensaje.isNotEmpty) {
      // 1) Confirmación de una volteada programada: se completa la programada.
      final prog = lista.indexWhere((x) => !x.confirmada && x.mensaje == v.mensaje);
      if (prog != -1) {
        final base = lista[prog];
        lista[prog] = Volteada(
          id: base.id,
          loteId: base.loteId,
          mensaje: base.mensaje,
          temperatura: v.temperatura,
          humedad: v.humedad,
          observacion: v.observacion,
          fecha: v.fecha,
          fechaProgramada: base.fechaProgramada,
          confirmada: true,
          notifId: base.notifId,
        );
        return lista;
      }
      // 2) Ya había una confirmada con el mismo mensaje (el bug anterior
      //    guardaba una vacía al tocar la notificación): se queda la que tiene datos.
      final conf = lista.indexWhere((x) => x.confirmada && x.mensaje == v.mensaje);
      if (conf != -1) {
        if (_vacia(lista[conf]) && !_vacia(v)) lista[conf] = v;
        return lista;
      }
    }
    lista.add(v);
    return lista;
  }
}
