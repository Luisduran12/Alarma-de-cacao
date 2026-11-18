import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/volteada.dart';

/// Un punto de la curva ideal: temperatura (°C) esperada a cierta hora del lote.
class PuntoIdeal {
  final double horas;
  final double temperatura;
  const PuntoIdeal(this.horas, this.temperatura);

  Map<String, dynamic> toJson() => {'h': horas, 't': temperatura};

  static PuntoIdeal? fromJson(Object? j) {
    if (j is! Map) return null;
    final h = j['h'], t = j['t'];
    if (h is! num || t is! num) return null;
    return PuntoIdeal(h.toDouble(), t.toDouble());
  }
}

/// Curva ideal de temperatura que el productor (o su técnico) define.
///
/// NO viene con valores de fábrica: no hay una curva "ideal" única y
/// verificada, así que la app empieza vacía y cada quien escribe la suya.
/// Entre dos puntos se une con una recta; fuera del primer y último punto no
/// se extrapola.
class CurvaIdeal {
  final List<PuntoIdeal> puntos;

  /// Ordena por hora y, si hay horas repetidas, se queda con la última escrita.
  CurvaIdeal(Iterable<PuntoIdeal> puntos) : puntos = _normalizar(puntos);

  static const vacia = CurvaIdeal._(<PuntoIdeal>[]);
  const CurvaIdeal._(this.puntos);

  static List<PuntoIdeal> _normalizar(Iterable<PuntoIdeal> ps) {
    final porHora = <double, PuntoIdeal>{};
    for (final p in ps) {
      if (p.horas < 0 || p.horas.isNaN || p.temperatura.isNaN) continue;
      porHora[p.horas] = p;
    }
    return porHora.values.toList()..sort((a, b) => a.horas.compareTo(b.horas));
  }

  bool get estaVacia => puntos.isEmpty;

  /// Temperatura ideal a las [horas], o null si está fuera del tramo definido.
  double? valorEn(double horas) {
    if (puntos.isEmpty || horas < puntos.first.horas || horas > puntos.last.horas) return null;
    for (var i = 0; i < puntos.length - 1; i++) {
      final a = puntos[i], b = puntos[i + 1];
      if (horas >= a.horas && horas <= b.horas) {
        if (b.horas == a.horas) return a.temperatura;
        final f = (horas - a.horas) / (b.horas - a.horas);
        return a.temperatura + (b.temperatura - a.temperatura) * f;
      }
    }
    return puntos.last.temperatura; // un solo punto y horas == su hora
  }

  String toJsonString() => jsonEncode(puntos.map((p) => p.toJson()).toList());

  static CurvaIdeal fromJsonString(String? texto) {
    if (texto == null || texto.isEmpty) return vacia;
    try {
      final lista = jsonDecode(texto);
      if (lista is! List) return vacia;
      return CurvaIdeal(lista.map(PuntoIdeal.fromJson).whereType<PuntoIdeal>());
    } catch (_) {
      return vacia;
    }
  }

  /// Compara las lecturas confirmadas con la curva ideal.
  ComparacionIdeal comparar(List<Volteada> registros, DateTime inicio) {
    final difs = <double>[];
    for (final v in registros.where((v) => v.confirmada)) {
      final ideal = valorEn(v.fecha.difference(inicio).inMinutes / 60.0);
      if (ideal != null) difs.add(v.temperatura - ideal);
    }
    if (difs.isEmpty) return const ComparacionIdeal(lecturas: 0);
    return ComparacionIdeal(
      lecturas: difs.length,
      diferenciaPromedio: difs.reduce((a, b) => a + b) / difs.length,
      diferenciaMaxima: difs.reduce((a, b) => a.abs() >= b.abs() ? a : b),
    );
  }
}

/// Resultado de comparar un lote con la curva ideal. Diferencia = lote − ideal
/// (positiva: el lote estuvo más caliente que lo ideal).
class ComparacionIdeal {
  final int lecturas;
  final double? diferenciaPromedio;
  final double? diferenciaMaxima;
  const ComparacionIdeal({required this.lecturas, this.diferenciaPromedio, this.diferenciaMaxima});

  String frase() {
    if (lecturas == 0) return 'Ninguna lectura cae dentro del tramo de la curva ideal.';
    final d = diferenciaPromedio!;
    final n = d.abs().toStringAsFixed(1).replaceAll('.', ',');
    final lect = lecturas == 1 ? '1 lectura comparada' : '$lecturas lecturas comparadas';
    if (d.abs() < 0.05) return 'En promedio coincidió con la curva ideal ($lect).';
    return 'En promedio estuvo $n °C ${d > 0 ? 'por encima' : 'por debajo'} de la curva ideal ($lect).';
  }
}

/// Guarda la curva ideal en el teléfono (funciona sin internet).
class CurvaIdealStorage {
  static const clave = 'curva_ideal_v1';

  static Future<CurvaIdeal> cargar() async {
    final prefs = await SharedPreferences.getInstance();
    return CurvaIdeal.fromJsonString(prefs.getString(clave));
  }

  static Future<void> guardar(CurvaIdeal curva) async {
    final prefs = await SharedPreferences.getInstance();
    if (curva.estaVacia) {
      await prefs.remove(clave);
    } else {
      await prefs.setString(clave, curva.toJsonString());
    }
  }
}
