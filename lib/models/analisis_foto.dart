import 'dart:convert';

/// Qué se le pide a la IA que mire en la foto. Los códigos son los del servidor (`/analizar-foto`).
enum ModoAnalisis {
  corte('corte', 'Prueba de corte', 'Granos cortados por la mitad'),
  granoSeco('grano_seco', 'Grano seco', 'Granos secos: moho, insectos o humedad'),
  mazorcaHoja('mazorca_hoja', 'Mazorca u hoja', 'Posibles enfermedades');

  final String codigo;
  final String nombre;
  final String descripcion;
  const ModoAnalisis(this.codigo, this.nombre, this.descripcion);

  static ModoAnalisis? desdeCodigo(String? c) {
    for (final m in values) {
      if (m.codigo == c) return m;
    }
    return null;
  }
}

enum Semaforo { verde, amarillo, rojo }

/// Nombre legible de una categoría del servidor.
String nombreCategoria(String codigo) {
  const nombres = {
    'bien_fermentado': 'Bien fermentado',
    'parcialmente_fermentado': 'Parcialmente fermentado',
    'violeta': 'Violeta',
    'pizarroso': 'Pizarroso',
    'moho': 'Moho',
    'sin_defectos': 'Sin defectos',
    'dano_por_insectos': 'Daño por insectos',
    'humedad_visible': 'Humedad visible',
    'sana': 'Sana',
    'monilia': 'Monilia',
    'mazorca_negra': 'Mazorca negra',
    'otra_posible_enfermedad': 'Otra posible enfermedad',
  };
  final n = nombres[codigo];
  if (n != null) return n;
  final t = codigo.replaceAll('_', ' ').trim();
  return t.isEmpty ? codigo : t[0].toUpperCase() + t.substring(1);
}

class CategoriaFoto {
  final String nombre;
  final int porcentaje;
  const CategoriaFoto(this.nombre, this.porcentaje);
}

/// Lo que el servidor respondió. Se valida al leerlo: si algo no cuadra se rechaza (no se muestra a medias).
class ResultadoAnalisis {
  final ModoAnalisis modo;

  /// true = hay que tomar otra foto (en ese caso NO hay porcentajes).
  final bool repetirFoto;
  final String mensaje;
  final List<CategoriaFoto> categorias;
  final String confianza;
  final List<String> posiblesCausas;
  final List<String> pasosRecomendados;
  final Semaforo semaforo;
  final String aviso;

  const ResultadoAnalisis({
    required this.modo,
    required this.repetirFoto,
    required this.mensaje,
    required this.categorias,
    required this.confianza,
    required this.posiblesCausas,
    required this.pasosRecomendados,
    required this.semaforo,
    required this.aviso,
  });

  static List<String> _lista(Object? v, String campo) {
    if (v is! List) throw FormatException('$campo debe ser una lista');
    if (v.length > 10) throw FormatException('$campo es demasiado larga');
    return [
      for (final x in v)
        if (x is String && x.trim().isNotEmpty) (x.length > 400 ? x.substring(0, 400) : x.trim())
    ];
  }

  factory ResultadoAnalisis.desdeJson(Map<String, dynamic> j) {
    final modo = ModoAnalisis.desdeCodigo(j['modo'] as String?);
    if (modo == null) throw const FormatException('modo desconocido');
    final repetir = j['repetir_foto'];
    if (repetir is! bool) throw const FormatException('repetir_foto debe ser verdadero o falso');
    final sem = Semaforo.values.where((s) => s.name == j['semaforo']);
    if (sem.isEmpty) throw const FormatException('semáforo desconocido');
    final confianza = j['confianza'];
    if (confianza is! String || !const ['alta', 'media', 'baja'].contains(confianza)) {
      throw const FormatException('confianza desconocida');
    }
    final cats = j['categorias'];
    if (cats is! List || cats.length > 12) throw const FormatException('categorías inválidas');
    final categorias = <CategoriaFoto>[];
    for (final c in cats) {
      if (c is! Map || c['nombre'] is! String || c['porcentaje'] is! num) throw const FormatException('categoría inválida');
      final p = (c['porcentaje'] as num).toDouble();
      if (!p.isFinite || p < 0 || p > 100) throw const FormatException('porcentaje fuera de rango');
      categorias.add(CategoriaFoto(c['nombre'] as String, p.round()));
    }
    if (repetir && categorias.isNotEmpty) throw const FormatException('pide otra foto pero trae porcentajes');
    final mensaje = j['mensaje'];
    final aviso = j['aviso'];
    return ResultadoAnalisis(
      modo: modo,
      repetirFoto: repetir,
      mensaje: mensaje is String ? (mensaje.length > 300 ? mensaje.substring(0, 300) : mensaje) : '',
      categorias: categorias..sort((a, b) => b.porcentaje.compareTo(a.porcentaje)),
      confianza: confianza,
      posiblesCausas: _lista(j['posibles_causas'], 'posibles_causas'),
      pasosRecomendados: _lista(j['pasos_recomendados'], 'pasos_recomendados'),
      semaforo: sem.first,
      aviso: aviso is String && aviso.isNotEmpty ? (aviso.length > 400 ? aviso.substring(0, 400) : aviso) : AnalisisFoto.avisoPorDefecto,
    );
  }
}

enum EstadoAnalisis { pendiente, analizada, error }

/// Una foto de un lote y su análisis (o el hecho de que está esperando señal).
class AnalisisFoto {
  static const avisoPorDefecto =
      'Estimación orientativa. La clasificación oficial es la prueba de corte de la NTC 1252. Ante duda, consulte al técnico.';

  final String id;
  final String loteId;
  final ModoAnalisis modo;
  final String ruta;
  final EstadoAnalisis estado;
  final ResultadoAnalisis? resultado;
  final DateTime creadoEn;
  final DateTime? analizadoEn;
  final int intentos;
  final String? ultimoError;

  const AnalisisFoto({
    required this.id,
    required this.loteId,
    required this.modo,
    required this.ruta,
    required this.estado,
    this.resultado,
    required this.creadoEn,
    this.analizadoEn,
    this.intentos = 0,
    this.ultimoError,
  });

  Map<String, Object?> toRow({String? resultadoJson}) => {
        'id': id,
        'lote_id': loteId,
        'modo': modo.codigo,
        'ruta': ruta,
        'estado': estado.name,
        'resultado': resultadoJson,
        'creado_en': creadoEn.toUtc().toIso8601String(),
        'analizado_en': analizadoEn?.toUtc().toIso8601String(),
        'intentos': intentos,
        'ultimo_error': ultimoError,
      };

  /// Lee una fila; un resultado guardado que ya no se pueda leer se trata como "sin resultado".
  factory AnalisisFoto.desdeFila(Map<String, Object?> f) {
    ResultadoAnalisis? r;
    final crudo = f['resultado'] as String?;
    if (crudo != null) {
      try {
        r = ResultadoAnalisis.desdeJson(jsonDecode(crudo) as Map<String, dynamic>);
      } catch (_) {}
    }
    var estado = EstadoAnalisis.values.firstWhere((e) => e.name == f['estado'], orElse: () => EstadoAnalisis.error);
    if (estado == EstadoAnalisis.analizada && r == null) estado = EstadoAnalisis.error;
    return AnalisisFoto(
      id: f['id'] as String,
      loteId: f['lote_id'] as String,
      modo: ModoAnalisis.desdeCodigo(f['modo'] as String?) ?? ModoAnalisis.corte,
      ruta: f['ruta'] as String,
      estado: estado,
      resultado: r,
      creadoEn: DateTime.tryParse((f['creado_en'] as String?) ?? '')?.toLocal() ?? DateTime.fromMillisecondsSinceEpoch(0),
      analizadoEn: DateTime.tryParse((f['analizado_en'] as String?) ?? '')?.toLocal(),
      intentos: (f['intentos'] as int?) ?? 0,
      ultimoError: f['ultimo_error'] as String?,
    );
  }
}
