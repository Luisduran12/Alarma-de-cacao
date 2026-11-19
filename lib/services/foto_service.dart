import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../data/cacao_database.dart';
import '../models/analisis_foto.dart';
import 'consentimiento_fotos.dart';
import 'foto_preparada.dart';
import 'instalacion_id.dart';

/// Por qué no se pudo analizar la foto. [mensaje] está escrito para el productor.
class FotoException implements Exception {
  final String codigo;
  final String mensaje;

  /// true = la foto sigue en la cola y se reintenta cuando haya señal; false = el servidor la rechazó.
  final bool reintentable;
  final Duration? reintentarEn;
  const FotoException(this.codigo, this.mensaje, {required this.reintentable, this.reintentarEn});

  @override
  String toString() => 'FotoException($codigo)';
}

/// Fotos de los lotes: se guardan en el teléfono (reducidas y sin metadatos), se mandan a analizar cuando hay
/// señal y quedan en cola si no la hay. Cliente de `POST {BACKEND_URL}/analizar-foto` (ver `backend/README.md`):
/// el cuerpo lleva SOLO el modo y la foto; ni el lote, ni la ubicación, ni el nombre.
class FotoService {
  static const urlPorDefecto = String.fromEnvironment('BACKEND_URL');
  static const _maxMensaje = 300;

  final Future<Database> Function() _db;
  final http.Client _cliente;
  final Uri? _servidor;
  final Duration _timeout;
  final Future<String> Function() _idInstalacion;
  final Future<Directory> Function() _directorio;
  final Future<bool?> Function() _consentimiento;
  final DateTime Function() _ahora;
  final String Function() _nuevoId;

  FotoService({
    Future<Database> Function()? database,
    http.Client? cliente,
    String? urlServidor,
    Duration? timeout,
    Future<String> Function()? idInstalacion,
    Future<Directory> Function()? directorio,
    Future<bool?> Function()? consentimiento,
    DateTime Function()? ahora,
    String Function()? nuevoId,
  })  : _db = database ?? CacaoDatabase.instancia,
        _cliente = cliente ?? http.Client(),
        _servidor = _leerUrl(urlServidor ?? urlPorDefecto),
        _timeout = timeout ?? const Duration(seconds: 65),
        _idInstalacion = idInstalacion ?? InstalacionId.obtener,
        _directorio = directorio ?? _directorioPorDefecto,
        _consentimiento = consentimiento ?? ConsentimientoFotos.obtener,
        _ahora = ahora ?? DateTime.now,
        _nuevoId = nuevoId ?? (() => const Uuid().v4());

  static Future<Directory> _directorioPorDefecto() async {
    final base = await getApplicationDocumentsDirectory();
    return Directory(p.join(base.path, 'fotos_analisis'));
  }

  static Uri? _leerUrl(String t) {
    if (t.trim().isEmpty) return null;
    final u = Uri.tryParse(t.trim());
    return (u != null && u.hasScheme && u.host.isNotEmpty) ? u : null;
  }

  bool get servidorConfigurado => _servidor != null;

  /// Guarda la foto ya preparada y la deja en la cola ("pendiente").
  Future<AnalisisFoto> guardar({required String loteId, required ModoAnalisis modo, required FotoPreparada foto}) async {
    final dir = await _directorio();
    await dir.create(recursive: true);
    final id = _nuevoId();
    final archivo = File(p.join(dir.path, '$id.jpg'));
    await archivo.writeAsBytes(foto.bytes, flush: true);
    final a = AnalisisFoto(
      id: id, loteId: loteId, modo: modo, ruta: archivo.path, estado: EstadoAnalisis.pendiente, creadoEn: _ahora(),
    );
    try {
      await (await _db()).insert('analisis_fotos', a.toRow());
    } catch (_) {
      await archivo.delete().catchError((_) => archivo); // no dejar una foto suelta si no se pudo registrar
      rethrow;
    }
    return a;
  }

  Future<AnalisisFoto?> obtener(String id) async {
    final f = await (await _db()).query('analisis_fotos', where: 'id = ?', whereArgs: [id]);
    return f.isEmpty ? null : AnalisisFoto.desdeFila(f.first);
  }

  /// Las fotos del lote, de la más reciente a la más vieja.
  Future<List<AnalisisFoto>> listar(String loteId) async {
    final f = await (await _db()).query('analisis_fotos', where: 'lote_id = ?', whereArgs: [loteId], orderBy: 'creado_en DESC');
    return f.map(AnalisisFoto.desdeFila).toList();
  }

  Future<int> cuantasPendientes() async {
    final r = await (await _db()).rawQuery("SELECT COUNT(*) AS n FROM analisis_fotos WHERE estado = 'pendiente'");
    return (r.first['n'] as int?) ?? 0;
  }

  /// Manda la foto a analizar. Si sale bien, guarda el resultado y la devuelve analizada. Si no hay señal o el
  /// servidor está ocupado, la foto sigue en la cola y se lanza una [FotoException] reintentable; si el servidor
  /// la rechaza (foto dañada, muy pesada...), queda en "error" y la excepción no es reintentable.
  Future<AnalisisFoto> analizar(String id) async {
    final a = await obtener(id);
    if (a == null) throw ArgumentError('No existe la foto $id');
    if (a.estado == EstadoAnalisis.analizada) return a;
    // La autorización se revisa AL ENVIAR, no solo al tomar la foto: si el productor la quitó en Ajustes (o nunca la dio),
    // ninguna foto sale del teléfono, tampoco las que estaban en la cola. La foto queda guardada.
    if (await _consentimiento() != true) {
      throw const FotoException('sin_autorizacion', 'No ha autorizado enviar fotos para analizarlas. Puede hacerlo en Ajustes. La foto queda guardada en el teléfono.',
          reintentable: true);
    }
    final base = _servidor;
    if (base == null) {
      throw const FotoException('sin_servidor', 'El análisis de fotos no está disponible en esta versión de la app. La foto queda guardada.',
          reintentable: true);
    }

    final archivo = File(a.ruta);
    if (!await archivo.exists()) {
      await _marcar(a, EstadoAnalisis.error, error: 'La foto ya no está en el teléfono.');
      throw const FotoException('foto_perdida', 'La foto ya no está en el teléfono. Tome otra.', reintentable: false);
    }

    final ruta = '${base.path.endsWith('/') ? base.path.substring(0, base.path.length - 1) : base.path}/analizar-foto';
    http.Response r;
    try {
      r = await _cliente
          .post(base.replace(path: ruta),
              headers: {'Content-Type': 'application/json', 'X-Install-Id': await _idInstalacion()},
              body: jsonEncode({'modo': a.modo.codigo, 'imagen': base64Encode(await archivo.readAsBytes())}))
          .timeout(_timeout);
    } on TimeoutException {
      throw await _fallaTransitoria(a, 'sin_conexion', 'La consulta tardó demasiado. Se intentará de nuevo cuando haya mejor señal.');
    } on SocketException {
      throw await _fallaTransitoria(a, 'sin_conexion', 'No hay conexión a internet. La foto quedó guardada y se analizará cuando haya señal.');
    } on http.ClientException {
      throw await _fallaTransitoria(a, 'sin_conexion', 'No hay conexión a internet. La foto quedó guardada y se analizará cuando haya señal.');
    }

    dynamic json;
    try {
      json = jsonDecode(utf8.decode(r.bodyBytes));
    } catch (_) {
      json = null;
    }

    if (r.statusCode == 200) {
      try {
        final res = ResultadoAnalisis.desdeJson(json as Map<String, dynamic>);
        final ok = AnalisisFoto(
          id: a.id, loteId: a.loteId, modo: a.modo, ruta: a.ruta, estado: EstadoAnalisis.analizada, resultado: res,
          creadoEn: a.creadoEn, analizadoEn: _ahora(), intentos: a.intentos + 1,
        );
        await (await _db()).update('analisis_fotos', ok.toRow(resultadoJson: jsonEncode(json)), where: 'id = ?', whereArgs: [a.id]);
        return ok;
      } catch (e) {
        debugPrint('Respuesta del análisis no válida: $e');
        throw await _fallaTransitoria(a, 'respuesta_invalida', 'La respuesta no se pudo entender. Intente de nuevo.');
      }
    }

    final e = json is Map ? json['error'] : null;
    final codigo = e is Map && e['codigo'] is String ? e['codigo'] as String : 'error_${r.statusCode}';
    var mensaje = e is Map && e['mensaje'] is String ? (e['mensaje'] as String).trim() : '';
    if (mensaje.isEmpty) mensaje = 'No se pudo analizar la foto ahora. Intente más tarde.';
    if (mensaje.length > _maxMensaje) mensaje = mensaje.substring(0, _maxMensaje);
    final seg = int.tryParse(r.headers['retry-after'] ?? '');
    final espera = seg != null && seg > 0 ? Duration(seconds: seg) : null;

    // 400 y 413: la foto en sí no sirve, reintentar no ayuda. Todo lo demás (429, 5xx) se reintenta luego.
    final definitivo = r.statusCode == 400 || r.statusCode == 413;
    if (definitivo) {
      await _marcar(a, EstadoAnalisis.error, error: mensaje);
      throw FotoException(codigo, mensaje, reintentable: false);
    }
    await _marcar(a, EstadoAnalisis.pendiente, error: mensaje, sumarIntento: true);
    throw FotoException(codigo, mensaje, reintentable: true, reintentarEn: espera);
  }

  Future<FotoException> _fallaTransitoria(AnalisisFoto a, String codigo, String mensaje) async {
    await _marcar(a, EstadoAnalisis.pendiente, error: mensaje, sumarIntento: true);
    return FotoException(codigo, mensaje, reintentable: true);
  }

  Future<void> _marcar(AnalisisFoto a, EstadoAnalisis estado, {String? error, bool sumarIntento = false}) async {
    await (await _db()).update(
      'analisis_fotos',
      {'estado': estado.name, 'ultimo_error': error, 'intentos': a.intentos + (sumarIntento ? 1 : 0)},
      where: 'id = ?',
      whereArgs: [a.id],
    );
  }

  /// Manda las fotos en cola, de la más vieja a la más nueva. Se detiene en la primera falla de red o de
  /// límite (no tiene sentido seguir). Devuelve cuántas quedaron analizadas.
  Future<int> procesarPendientes({int maximo = 5}) async {
    if (!servidorConfigurado || maximo <= 0) return 0;
    final filas = await (await _db()).query('analisis_fotos',
        where: "estado = 'pendiente'", orderBy: 'creado_en ASC', limit: maximo);
    var hechas = 0;
    for (final f in filas) {
      try {
        await analizar(f['id'] as String);
        hechas++;
      } on FotoException catch (e) {
        if (e.reintentable) break; // sin señal, límite o servidor ocupado: la cola sigue para otra ocasión
      }
    }
    return hechas;
  }

  /// Borra la foto (archivo y registro).
  Future<void> borrar(String id) async {
    final a = await obtener(id);
    if (a == null) return;
    await (await _db()).delete('analisis_fotos', where: 'id = ?', whereArgs: [id]);
    await _borrarArchivo(a.ruta);
  }

  /// Borra las fotos de un lote (por ejemplo, al eliminarlo o al "borrar todo").
  Future<void> borrarDelLote(String loteId) async {
    for (final a in await listar(loteId)) {
      await borrar(a.id);
    }
  }

  /// Quita del disco las fotos que ya no tienen registro (por ejemplo, las de un lote que se eliminó).
  Future<int> limpiarHuerfanas() async {
    final dir = await _directorio();
    if (!await dir.exists()) return 0;
    final ids = {for (final f in await (await _db()).query('analisis_fotos', columns: ['ruta'])) f['ruta'] as String};
    var n = 0;
    await for (final e in dir.list()) {
      if (e is File && e.path.endsWith('.jpg') && !ids.contains(e.path)) {
        await e.delete().catchError((_) => e);
        n++;
      }
    }
    return n;
  }

  Future<void> _borrarArchivo(String ruta) async {
    try {
      final f = File(ruta);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
