import 'dart:convert';

import 'package:flutter/services.dart';

import '../utils/geo.dart';

/// El lugar de la lista más cercano a unas coordenadas.
class LugarCercano {
  final String nombre;
  final String municipio;
  final String departamento;
  final double latitud;
  final double longitud;

  /// true si es un municipio; false si es un centro poblado (caserío, centro rural).
  final bool esMunicipio;
  final double distanciaKm;

  const LugarCercano({
    required this.nombre,
    required this.municipio,
    required this.departamento,
    required this.latitud,
    required this.longitud,
    required this.esMunicipio,
    required this.distanciaKm,
  });

  String get _distanciaTexto {
    if (distanciaKm < 1) return 'a menos de 1 km';
    final n = distanciaKm < 10 ? distanciaKm.toStringAsFixed(1).replaceAll('.', ',') : '${distanciaKm.round()}';
    return 'a $n km';
  }

  /// "Cerca de Hatoviejo, Durania (Norte de Santander), a 3,2 km".
  /// Es una REFERENCIA aproximada: el centro poblado o municipio más cercano, no la vereda.
  String get texto {
    final donde = esMunicipio || nombre == municipio ? nombre : '$nombre, $municipio';
    return 'Cerca de $donde ($departamento), $_distanciaTexto';
  }
}

/// Lista de municipios y centros poblados de Colombia con coordenadas (DANE, DIVIPOLA,
/// CC BY-SA 4.0), que va dentro de la app y funciona SIN internet.
///
/// No incluye veredas: no existe un conjunto nacional de veredas con coordenadas.
/// Se genera con `dart tool/generar_lugares.dart`.
class LugaresOffline {
  static const rutaAsset = 'assets/data/lugares_dane.json';

  final List<String> _departamentos;
  // Cada fila: nombre, municipio, índice de departamento, latitud, longitud, tipo.
  final List<List<Object?>> _filas;

  /// Fuente, licencia y fecha de corte de los datos (para los créditos).
  final String fuente;
  final String licencia;
  final String corte;

  LugaresOffline._(this._departamentos, this._filas, this.fuente, this.licencia, this.corte);

  int get cantidad => _filas.length;

  factory LugaresOffline.desdeJson(String texto) {
    final j = jsonDecode(texto) as Map<String, dynamic>;
    return LugaresOffline._(
      (j['departamentos'] as List).cast<String>(),
      (j['lugares'] as List).map((f) => (f as List).cast<Object?>()).toList(),
      j['fuente'] as String? ?? '',
      j['licencia'] as String? ?? '',
      j['corte'] as String? ?? '',
    );
  }

  static LugaresOffline? _cargada;

  /// Carga la lista de la app (una sola vez).
  static Future<LugaresOffline> cargar([AssetBundle? bundle]) async {
    final ya = _cargada;
    if (ya != null && bundle == null) return ya;
    final texto = await (bundle ?? rootBundle).loadString(rutaAsset);
    final l = LugaresOffline.desdeJson(texto);
    if (bundle == null) _cargada = l;
    return l;
  }

  /// El lugar más cercano a esas coordenadas, o null si la lista está vacía o las
  /// coordenadas no son válidas. No hay distancia máxima: [LugarCercano.distanciaKm]
  /// dice qué tan lejos está.
  LugarCercano? masCercano(double lat, double lng) {
    if (_filas.isEmpty || lat.isNaN || lng.isNaN || lat.abs() > 90 || lng.abs() > 180) return null;
    List<Object?>? mejor;
    var mejorKm = double.infinity;
    for (final f in _filas) {
      final d = distanciaKm(lat, lng, f[3] as double, f[4] as double);
      if (d < mejorKm) {
        mejorKm = d;
        mejor = f;
      }
    }
    final f = mejor!;
    return LugarCercano(
      nombre: f[0] as String,
      municipio: f[1] as String,
      departamento: _departamentos[f[2] as int],
      latitud: f[3] as double,
      longitud: f[4] as double,
      esMunicipio: f[5] == 'M',
      distanciaKm: mejorKm,
    );
  }
}
