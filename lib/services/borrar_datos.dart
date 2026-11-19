import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../data/cacao_database.dart';
import 'notification_service.dart';
import 'preferencias_app.dart';

/// Resultado de borrar: qué se hizo y qué falló (para decírselo al productor con honestidad).
class ResultadoBorrado {
  final List<String> fallos;
  const ResultadoBorrado(this.fallos);
  bool get completo => fallos.isEmpty;
}

/// "Borrar todos mis datos" (Ley 1581: derecho a suprimir). Quita del teléfono: alarmas y avisos programados,
/// lotes y todo lo que cuelga de ellos (registros, recordatorios, chat, fotos), caché de lugares, archivos de las
/// fotos, el CSV exportado, archivos temporales y todas las preferencias (consentimientos, ajustes, reglas, curva
/// ideal, ID de instalación, caché del clima). No toca nada fuera del teléfono: nuestro servidor no guarda datos
/// del productor, y lo que Anthropic conserve hasta 30 días no lo podemos borrar desde aquí.
class BorrarDatos {
  final Future<Database> Function() _db;
  final Future<void> Function() _cancelarAlarmas;
  final Future<List<Directory>> Function() _carpetas;
  final Future<List<File>> Function() _archivos;

  BorrarDatos({
    Future<Database> Function()? baseDeDatos,
    Future<void> Function()? cancelarAlarmas,
    Future<List<Directory>> Function()? carpetas,
    Future<List<File>> Function()? archivos,
  })  : _db = baseDeDatos ?? CacaoDatabase.instancia,
        _cancelarAlarmas = cancelarAlarmas ?? (() => NotificationService().cancelarTodasLasNotificaciones()),
        _carpetas = carpetas ?? _carpetasPorDefecto,
        _archivos = archivos ?? _archivosPorDefecto;

  static Future<List<Directory>> _carpetasPorDefecto() async {
    final docs = await getApplicationDocumentsDirectory();
    final tmp = await getTemporaryDirectory();
    return [Directory(p.join(docs.path, 'fotos_analisis')), tmp];
  }

  static Future<List<File>> _archivosPorDefecto() async {
    final docs = await getApplicationDocumentsDirectory();
    return [File(p.join(docs.path, 'lotes_exportados.csv'))];
  }

  Future<ResultadoBorrado> todo() async {
    final fallos = <String>[];

    Future<void> paso(String nombre, Future<void> Function() f) async {
      try {
        await f();
      } catch (e) {
        debugPrint('Borrar datos: falló "$nombre": $e');
        fallos.add(nombre);
      }
    }

    // Primero las alarmas: así no suena nada de un lote que ya no existe.
    await paso('alarmas', _cancelarAlarmas);
    await paso('base de datos', () async {
      final db = await _db();
      await db.transaction((t) async {
        // Los registros, recordatorios, chat y fotos se borran en cascada con el lote.
        await t.delete('lotes');
        await t.delete('lugares');
      });
    });
    await paso('fotos y archivos', () async {
      for (final d in await _carpetas()) {
        if (await d.exists()) {
          // Se vacía por dentro; la carpeta (incluida la temporal del sistema) se deja.
          await for (final e in d.list()) {
            await e.delete(recursive: true);
          }
        }
      }
      for (final f in await _archivos()) {
        if (await f.exists()) await f.delete();
      }
    });
    await paso('preferencias', () async {
      await (await SharedPreferences.getInstance()).clear();
      await PreferenciasApp.instancia.restablecer();
    });
    return ResultadoBorrado(fallos);
  }
}
