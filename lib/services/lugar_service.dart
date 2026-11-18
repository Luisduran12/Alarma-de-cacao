import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

import '../data/cacao_database.dart';
import 'lugares_offline.dart';

enum OrigenLugar { servidor, listaOffline }

/// El nombre de un lugar y de dónde salió.
class NombreLugar {
  final String texto;
  final OrigenLugar origen;

  /// Crédito de la fuente (por ejemplo, el de OpenStreetMap si lo da el servidor).
  final String fuente;
  const NombreLugar(this.texto, this.origen, this.fuente);

  /// true si es solo una referencia (centro poblado o municipio más cercano).
  bool get aproximado => origen == OrigenLugar.listaOffline;
}

/// Nombre del lugar de unas coordenadas.
///
///  - SIN internet: el centro poblado o municipio más cercano de la lista del DANE
///    ([LugaresOffline]). Es una referencia, no la vereda.
///  - CON internet: el servidor (endpoint `/lugar`, Fase 4) resuelve el nombre con
///    Nominatim y lo guarda en caché. Acá se guarda en la tabla `lugares`.
///
/// Contrato del servidor: `GET {BACKEND_URL}/lugar?lat=7.603&lng=-72.601` responde
/// 200 `{"nombre": "...", "fuente": "© colaboradores de OpenStreetMap"}`, 404 o 204
/// si no hay resultado, 429 si se pasó del límite. Sin `BACKEND_URL` configurada la
/// app funciona igual con la lista offline.
class LugarService {
  /// Dirección del servidor (no es un secreto): `--dart-define=BACKEND_URL=https://...`.
  static const urlPorDefecto = String.fromEnvironment('BACKEND_URL');

  /// Pausa mínima entre dos consultas seguidas: Nominatim permite como máximo 1 por segundo.
  static const pausaMinima = Duration(milliseconds: 1100);

  static const _origenSinResultado = 'sin_resultado';
  static const _maxNombre = 200;

  final Future<Database> Function() _db;
  final http.Client _cliente;
  final Uri? _servidor;
  final Future<LugaresOffline> Function() _lista;
  final Future<void> Function(Duration) _esperar;
  final DateTime Function() _ahora;
  final Duration _timeout;

  LugarService({
    Future<Database> Function()? database,
    http.Client? cliente,
    String? urlServidor,
    Future<LugaresOffline> Function()? lista,
    Future<void> Function(Duration)? esperar,
    DateTime Function()? ahora,
    Duration? timeout,
  })  : _db = database ?? CacaoDatabase.instancia,
        _cliente = cliente ?? http.Client(),
        _servidor = _leerUrl(urlServidor ?? urlPorDefecto),
        _lista = lista ?? LugaresOffline.cargar,
        _esperar = esperar ?? ((d) => Future<void>.delayed(d)),
        _ahora = ahora ?? DateTime.now,
        _timeout = timeout ?? const Duration(seconds: 12);

  static Uri? _leerUrl(String texto) {
    if (texto.trim().isEmpty) return null;
    final u = Uri.tryParse(texto.trim());
    return (u != null && u.hasScheme && u.host.isNotEmpty) ? u : null;
  }

  bool get servidorConfigurado => _servidor != null;

  /// Clave de caché: coordenadas con 3 decimales (≈ 110 m). También es lo único
  /// que se le manda al servidor, para no entregar la posición exacta de la finca.
  static String clave(double lat, double lng) => '${lat.toStringAsFixed(3)},${lng.toStringAsFixed(3)}';

  /// El nombre para esas coordenadas SIN usar internet: el del servidor si ya se
  /// guardó, o la referencia de la lista offline. null si no hay ninguno.
  Future<NombreLugar?> nombreDe(double lat, double lng) async {
    final db = await _db();
    final filas = await db.query('lugares', where: 'clave = ?', whereArgs: [clave(lat, lng)]);
    if (filas.isNotEmpty && filas.first['origen'] == OrigenLugar.servidor.name) {
      return NombreLugar(
        filas.first['nombre'] as String,
        OrigenLugar.servidor,
        (filas.first['fuente'] as String?) ?? '',
      );
    }
    final cercano = (await _lista()).masCercano(lat, lng);
    if (cercano == null) return null;
    return NombreLugar(cercano.texto, OrigenLugar.listaOffline, 'DANE, DIVIPOLA (CC BY-SA 4.0)');
  }

  /// Pide al servidor el nombre de ese lugar y lo guarda. Devuelve null si no hay
  /// servidor, no hay señal o no hay resultado.
  Future<NombreLugar?> resolver(double lat, double lng) async {
    final r = await _pedir(lat, lng);
    return r is _Resuelto ? NombreLugar(r.nombre, OrigenLugar.servidor, r.fuente) : null;
  }

  /// Resuelve con el servidor los lugares de los registros que todavía no tienen
  /// nombre del servidor: una consulta por cada punto distinto (aunque tenga muchos
  /// registros), con al menos [pausaMinima] entre una y otra. Se detiene al primer
  /// problema de red o de límite y lo que falte queda para la próxima vez.
  /// Devuelve cuántos nombres guardó. Sin servidor configurado no hace nada.
  Future<int> resolverPendientes({int maximo = 10}) async {
    if (!servidorConfigurado || maximo <= 0) return 0;
    final db = await _db();

    final puntos = await db.rawQuery('SELECT DISTINCT latitud, longitud FROM registros '
        'WHERE latitud IS NOT NULL AND longitud IS NOT NULL');
    final yaTienen = {for (final f in await db.query('lugares', columns: ['clave'])) f['clave'] as String};

    final pendientes = <String, (double, double)>{};
    for (final p in puntos) {
      final la = (p['latitud'] as num).toDouble(), lo = (p['longitud'] as num).toDouble();
      final k = clave(la, lo);
      if (!yaTienen.contains(k)) pendientes.putIfAbsent(k, () => (la, lo));
    }

    var guardados = 0, intentos = 0;
    for (final p in pendientes.values) {
      if (intentos >= maximo) break;
      if (intentos > 0) await _esperar(pausaMinima);
      intentos++;
      final r = await _pedir(p.$1, p.$2);
      if (r is _Resuelto) {
        guardados++;
      } else if (r is! _SinResultado) {
        break; // sin señal, límite o error: se reintenta en otra ocasión
      }
    }
    return guardados;
  }

  /// Hace la consulta y guarda el resultado (o el "sin resultado", para no repetirla).
  Future<_Respuesta> _pedir(double lat, double lng) async {
    final base = _servidor;
    if (base == null) return const _Fallo();
    final k = clave(lat, lng);
    final partes = k.split(',');
    final ruta = '${base.path.endsWith('/') ? base.path.substring(0, base.path.length - 1) : base.path}/lugar';
    final url = base.replace(path: ruta, queryParameters: {'lat': partes[0], 'lng': partes[1]});

    try {
      final r = await _cliente.get(url).timeout(_timeout);
      if (r.statusCode == 404 || r.statusCode == 204) {
        await _guardar(k, '', _origenSinResultado, '');
        return const _SinResultado();
      }
      if (r.statusCode != 200) return const _Fallo(); // 429 y demás: no se guarda nada
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      final nombre = j is Map ? j['nombre'] : null;
      if (nombre is! String || nombre.trim().isEmpty || nombre.length > _maxNombre) return const _Fallo();
      final fuente = j['fuente'] is String ? (j['fuente'] as String) : '';
      await _guardar(k, nombre.trim(), OrigenLugar.servidor.name, fuente);
      return _Resuelto(nombre.trim(), fuente);
    } catch (e) {
      debugPrint('No se pudo resolver el nombre del lugar: $e');
      return const _Fallo();
    }
  }

  Future<void> _guardar(String clave, String nombre, String origen, String fuente) async {
    final db = await _db();
    await db.insert(
      'lugares',
      {
        'clave': clave,
        'nombre': nombre,
        'origen': origen,
        'fuente': fuente,
        'resuelto_en': _ahora().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}

sealed class _Respuesta {
  const _Respuesta();
}

class _Resuelto extends _Respuesta {
  final String nombre, fuente;
  const _Resuelto(this.nombre, this.fuente);
}

class _SinResultado extends _Respuesta {
  const _SinResultado();
}

class _Fallo extends _Respuesta {
  const _Fallo();
}
