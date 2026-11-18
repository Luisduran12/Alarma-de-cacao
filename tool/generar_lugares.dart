// Genera assets/data/lugares_dane.json a partir de datos abiertos del DANE.
//
//   dart tool/generar_lugares.dart
//
// Fuentes (datos.gov.co, licencia CC BY-SA 4.0, corte 30-dic-2024):
//   - DIVIPOLA - Códigos municipios:                 gdxc-w37w  (1.122 municipios)
//   - DIVIPOLA - Códigos cabeceras - Centros poblados: xaxy-8nri (centros poblados rurales, tipo "CP")
//
// No hay un conjunto nacional de VEREDAS con coordenadas: la lista llega hasta centros poblados.
import 'dart:convert';
import 'dart:io';

const _municipios = 'https://www.datos.gov.co/resource/gdxc-w37w.json?\$limit=50000';
const _centros = 'https://www.datos.gov.co/resource/xaxy-8nri.json?\$limit=50000';

// Rectángulo que contiene a Colombia continental e insular (San Andrés, Leticia...).
const _latMin = -5.0, _latMax = 14.0, _lngMin = -82.0, _lngMax = -66.0;

Future<List<dynamic>> _bajar(String url) async {
  final cliente = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  try {
    final r = await (await cliente.getUrl(Uri.parse(url))).close();
    if (r.statusCode != 200) throw 'HTTP ${r.statusCode} en $url';
    return jsonDecode(await r.transform(utf8.decoder).join()) as List<dynamic>;
  } finally {
    cliente.close();
  }
}

double? _num(Object? v) => double.tryParse('${v ?? ''}'.replaceAll(',', '.'));

const _chicas = {'de', 'del', 'la', 'las', 'los', 'el', 'y', 'e', 'en'};

/// "SAN JOSÉ DE CÚCUTA" -> "San José de Cúcuta".
String _titulo(String crudo) {
  final palabras = crudo.trim().toLowerCase().split(RegExp(r'\s+'));
  final salida = <String>[];
  for (var i = 0; i < palabras.length; i++) {
    final p = palabras[i];
    if (p.isEmpty) continue;
    if (p.contains('.')) {
      salida.add(p.toUpperCase()); // "D.C."
    } else if (i > 0 && _chicas.contains(p)) {
      salida.add(p);
    } else {
      salida.add(p.substring(0, 1).toUpperCase() + p.substring(1));
    }
  }
  return salida.join(' ');
}

Future<void> main() async {
  final departamentos = <String>[];
  int indiceDepto(String d) {
    final t = _titulo(d);
    final i = departamentos.indexOf(t);
    if (i >= 0) return i;
    departamentos.add(t);
    return departamentos.length - 1;
  }

  var descartados = 0;
  final filas = <List<Object>>[];

  bool dentro(double? lat, double? lng) =>
      lat != null && lng != null && lat >= _latMin && lat <= _latMax && lng >= _lngMin && lng <= _lngMax;

  for (final r in await _bajar(_municipios)) {
    final lat = _num(r['latitud']), lng = _num(r['longitud']);
    if (!dentro(lat, lng)) {
      descartados++;
      continue;
    }
    final nombre = _titulo('${r['nom_mpio']}');
    filas.add([nombre, nombre, indiceDepto('${r['dpto']}'), lat!, lng!, 'M']);
  }
  final municipios = filas.length;

  for (final r in await _bajar(_centros)) {
    if (r['tipo_centro_poblado'] != 'CP') continue; // las cabeceras (CM) ya son los municipios
    final lat = _num(r['latitud']), lng = _num(r['longitud']);
    if (!dentro(lat, lng)) {
      descartados++;
      continue;
    }
    filas.add([
      _titulo('${r['nombre_centro_poblado']}'),
      _titulo('${r['nombre_municipio']}'),
      indiceDepto('${r['nombre_departamento']}'),
      lat!,
      lng!,
      'C',
    ]);
  }

  // El DANE repite algunas filas idénticas: se deja una sola.
  final vistos = <String>{};
  filas.retainWhere((f) => vistos.add('${f[0]}|${f[1]}|${f[3]}|${f[4]}'));

  filas.sort((a, b) {
    final c = (a[2] as int).compareTo(b[2] as int);
    return c != 0 ? c : (a[0] as String).compareTo(b[0] as String);
  });

  final salida = {
    'fuente': 'DANE, DIVIPOLA (datos.gov.co: gdxc-w37w y xaxy-8nri)',
    'licencia': 'Creative Commons Atribución-CompartirIgual 4.0 (CC BY-SA 4.0)',
    'corte': '2024-12-30',
    // Campos de cada lugar: nombre, municipio, índice en "departamentos", latitud, longitud, tipo (M = municipio, C = centro poblado).
    'departamentos': departamentos,
    'lugares': filas,
  };
  final archivo = File('assets/data/lugares_dane.json');
  archivo.writeAsStringSync(jsonEncode(salida));
  stdout.writeln('Lugares: ${filas.length} (municipios: $municipios) | '
      'descartados por coordenadas fuera de Colombia: $descartados | '
      'tamaño: ${(archivo.lengthSync() / 1024).round()} KB');
}
