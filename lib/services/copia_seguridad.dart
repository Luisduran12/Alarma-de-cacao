import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../data/cacao_database.dart';
import 'alarm_scheduler.dart';
import 'curva_ideal.dart';
import 'notification_service.dart';
import 'reglas_alerta.dart';

/// El archivo no sirve como respaldo. [mensaje] va escrito para el productor.
class RespaldoInvalido implements Exception {
  final String mensaje;
  const RespaldoInvalido(this.mensaje);
  @override
  String toString() => mensaje;
}

class ResumenRespaldo {
  final int lotes, registros, mensajesChat;
  final DateTime creadoEn;
  const ResumenRespaldo({required this.lotes, required this.registros, required this.mensajesChat, required this.creadoEn});
}

/// Copia de seguridad en UN archivo (JSON) con los datos del productor: lotes, registros, recordatorios, historial
/// del chat, caché de lugares, la curva ideal y las reglas de alerta.
///
/// NO incluye: las fotos (ni su análisis: son archivos pesados y el respaldo tiene que poder viajar por WhatsApp),
/// los consentimientos, los ajustes de letra ni el ID de instalación (esas decisiones se vuelven a tomar en el
/// teléfono nuevo, a propósito: la autorización de otra persona o de otra instalación no vale aquí).
/// Las alarmas del sistema tampoco se guardan: al importar se reprograman las de los registros futuros.
///
/// Importar REEMPLAZA lo que haya en el teléfono, dentro de una sola transacción: si algo falla, no cambia nada.
class CopiaSeguridad {
  static const formato = 'cacao_light_respaldo';
  static const versionFormato = 1;

  /// Tope de tamaño al importar (un respaldo real pesa unos cuantos KB; esto frena archivos equivocados).
  static const maxBytes = 20 * 1024 * 1024;

  /// Tablas que se respaldan, en el orden en que se pueden insertar (lotes primero por las llaves foráneas).
  static const tablas = ['lotes', 'registros', 'recordatorios', 'chat_mensajes', 'lugares'];

  /// Preferencias que viajan en el respaldo.
  static final _prefs = [CurvaIdealStorage.clave, ReglasAlertaStorage.clave];

  final Future<Database> Function() _db;
  final Future<void> Function() _cancelarAlarmas;
  final Future<void> Function() _reprogramar;
  final DateTime Function() _ahora;

  CopiaSeguridad({
    Future<Database> Function()? baseDeDatos,
    Future<void> Function()? cancelarAlarmas,
    Future<void> Function()? reprogramar,
    DateTime Function()? ahora,
  })  : _db = baseDeDatos ?? CacaoDatabase.instancia,
        _cancelarAlarmas = cancelarAlarmas ?? (() => NotificationService().cancelarTodasLasNotificaciones()),
        _reprogramar = reprogramar ?? _reprogramarPorDefecto,
        _ahora = ahora ?? DateTime.now;

  static Future<void> _reprogramarPorDefecto() async {
    final pendientes = (await NotificationService().getPendingNotifications()).map((p) => p.id).toSet();
    await AlarmScheduler().reprogramarFaltantes(pendientes);
  }

  /// Nombre sugerido para el archivo: `cacao_light_respaldo_2026-11-18.json`.
  String nombreArchivo() {
    final f = _ahora();
    String d(int n) => n.toString().padLeft(2, '0');
    return '${formato}_${f.year}-${d(f.month)}-${d(f.day)}.json';
  }

  Future<String> exportar() async {
    final db = await _db();
    final datos = <String, Object?>{};
    for (final t in tablas) {
      datos[t] = await db.query(t);
    }
    final prefs = await SharedPreferences.getInstance();
    final guardadas = <String, String>{};
    for (final k in _prefs) {
      final v = prefs.getString(k);
      if (v != null) guardadas[k] = v;
    }
    return const JsonEncoder.withIndent(' ').convert({
      'formato': formato,
      'version_formato': versionFormato,
      'version_bd': CacaoDatabase.version,
      'creado_en': _ahora().toUtc().toIso8601String(),
      'tablas': datos,
      'preferencias': guardadas,
    });
  }

  /// Comprueba el archivo SIN tocar nada. Devuelve un resumen o lanza [RespaldoInvalido].
  Future<ResumenRespaldo> validar(String contenido, {Database? contraBd}) async {
    final r = await _leer(contenido, contraBd ?? await _db());
    return r.resumen;
  }

  /// Reemplaza los datos del teléfono por los del respaldo. Todo o nada.
  Future<ResumenRespaldo> importar(String contenido) async {
    final db = await _db();
    final r = await _leer(contenido, db);

    // Se cancelan las alarmas de antes ANTES de cambiar los datos: las que queden ya no corresponden a nada.
    await _cancelarAlarmas();
    try {
      await db.transaction((t) async {
        await t.delete('lotes'); // en cascada: registros, recordatorios, chat y fotos
        await t.delete('lugares');
        for (final tabla in tablas) {
          for (final fila in r.filas[tabla]!) {
            await t.insert(tabla, fila);
          }
        }
      });
    } catch (_) {
      // Los datos de antes siguen intactos (transacción); se devuelven también sus alarmas.
      try {
        await _reprogramar();
      } catch (e) {
        debugPrint('No se pudieron reprogramar las alarmas tras el fallo: $e');
      }
      rethrow;
    }

    final prefs = await SharedPreferences.getInstance();
    for (final k in _prefs) {
      final v = r.prefs[k];
      if (v != null) {
        await prefs.setString(k, v);
      } else {
        await prefs.remove(k);
      }
    }
    // El contador de IDs de alarma no puede quedar por debajo de los IDs importados: se repetirían.
    final maxId = await _maxNotifId(db);
    final actual = prefs.getInt('ultimo_notification_id') ?? 0;
    if (maxId > actual) await prefs.setInt('ultimo_notification_id', maxId);

    try {
      await _reprogramar();
    } catch (e) {
      // Los datos ya están bien; las alarmas también se reprograman solas al abrir la app.
      debugPrint('Respaldo importado, pero no se pudieron reprogramar las alarmas ahora: $e');
    }
    return r.resumen;
  }

  Future<int> _maxNotifId(DatabaseExecutor db) async {
    var m = 0;
    for (final t in ['registros', 'recordatorios']) {
      final v = (await db.rawQuery('SELECT MAX(notif_id) AS m FROM $t')).first['m'];
      if (v is int && v > m) m = v;
    }
    return m;
  }

  // ---------------------------------------------------------------------------------------------------------------

  Future<_Leido> _leer(String contenido, Database db) async {
    if (contenido.length > maxBytes) throw const RespaldoInvalido('El archivo es demasiado grande para ser un respaldo.');
    Object? j;
    try {
      j = jsonDecode(contenido);
    } catch (_) {
      throw const RespaldoInvalido('El archivo no es un respaldo de Cacao Light (no se puede leer).');
    }
    if (j is! Map || j['formato'] != formato) {
      throw const RespaldoInvalido('El archivo no es un respaldo de Cacao Light.');
    }
    final vf = j['version_formato'];
    if (vf is! int || vf > versionFormato) {
      throw const RespaldoInvalido('El respaldo viene de una versión más nueva de la app. Actualice la app e intente de nuevo.');
    }
    final vbd = j['version_bd'];
    if (vbd is! int || vbd < 1 || vbd > CacaoDatabase.version) {
      throw const RespaldoInvalido('El respaldo viene de una versión más nueva de la app. Actualice la app e intente de nuevo.');
    }
    final creado = DateTime.tryParse('${j['creado_en']}');
    final t = j['tablas'];
    if (creado == null || t is! Map) throw const RespaldoInvalido('El respaldo está incompleto o dañado.');

    final filas = <String, List<Map<String, Object?>>>{};
    for (final tabla in tablas) {
      final crudas = t[tabla];
      // Un respaldo de una versión vieja puede no tener tablas que se crearon después.
      if (crudas == null) {
        filas[tabla] = [];
        continue;
      }
      if (crudas is! List) throw RespaldoInvalido('El respaldo está dañado (tabla $tabla).');
      final columnas = await _columnas(db, tabla);
      final lista = <Map<String, Object?>>[];
      for (final f in crudas) {
        if (f is! Map) throw RespaldoInvalido('El respaldo está dañado (tabla $tabla).');
        final fila = <String, Object?>{};
        for (final e in f.entries) {
          final tipo = columnas['${e.key}'];
          if (tipo == null) throw RespaldoInvalido('El respaldo trae un dato desconocido ("${e.key}" en $tabla).');
          fila['${e.key}'] = _validarValor(tabla, '${e.key}', tipo, e.value);
        }
        lista.add(fila);
      }
      filas[tabla] = lista;
    }
    _validarRelaciones(filas);

    final prefs = <String, String>{};
    final p = j['preferencias'];
    if (p is Map) {
      for (final k in _prefs) {
        final v = p[k];
        if (v == null) continue;
        if (v is! String) throw const RespaldoInvalido('El respaldo está dañado (preferencias).');
        try {
          jsonDecode(v);
        } catch (_) {
          throw const RespaldoInvalido('El respaldo está dañado (preferencias).');
        }
        prefs[k] = v;
      }
    }

    return _Leido(
      filas,
      prefs,
      ResumenRespaldo(
        lotes: filas['lotes']!.length,
        registros: filas['registros']!.length,
        mensajesChat: filas['chat_mensajes']!.length,
        creadoEn: creado,
      ),
    );
  }

  /// nombre de columna → tipo declarado (TEXT, REAL, INTEGER), leído de la base real.
  Future<Map<String, String>> _columnas(DatabaseExecutor db, String tabla) async {
    final info = await db.rawQuery('PRAGMA table_info($tabla)');
    return {for (final c in info) '${c['name']}': '${c['type']}'.toUpperCase()};
  }

  Object? _validarValor(String tabla, String col, String tipo, Object? v) {
    if (v == null) return null;
    final ok = switch (tipo) {
      'TEXT' => v is String,
      'REAL' => v is num,
      'INTEGER' => v is int,
      _ => false,
    };
    if (!ok) throw RespaldoInvalido('El respaldo está dañado (valor inválido en $tabla.$col).');
    return v;
  }

  /// Cada fila hija debe apuntar a un lote que esté en el respaldo (si no, SQLite la rechazaría a medias).
  void _validarRelaciones(Map<String, List<Map<String, Object?>>> filas) {
    final ids = {for (final l in filas['lotes']!) l['id']};
    if (ids.length != filas['lotes']!.length) throw const RespaldoInvalido('El respaldo está dañado (lotes repetidos).');
    for (final tabla in ['registros', 'recordatorios', 'chat_mensajes']) {
      for (final f in filas[tabla]!) {
        if (!ids.contains(f['lote_id'])) {
          throw RespaldoInvalido('El respaldo está dañado (hay datos de $tabla sin su lote).');
        }
      }
    }
  }
}

class _Leido {
  final Map<String, List<Map<String, Object?>>> filas;
  final Map<String, String> prefs;
  final ResumenRespaldo resumen;
  _Leido(this.filas, this.prefs, this.resumen);
}
