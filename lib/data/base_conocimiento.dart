import 'dart:convert';

import 'package:flutter/services.dart';

/// Un documento de donde sale el material (para créditos y para la sección "fuentes").
class FuenteDocumento {
  final String id;
  final String corta;
  final String titulo;
  final String autor;
  final int anio;
  final String url;
  final String nota;

  const FuenteDocumento({
    required this.id,
    required this.corta,
    required this.titulo,
    required this.autor,
    required this.anio,
    required this.url,
    required this.nota,
  });
}

/// Frase copiada TEXTUAL del documento, con su página. `tool/verificar_conocimiento.py`
/// comprueba que de verdad aparece ahí.
class CitaTextual {
  final int pagina;
  final String texto;
  const CitaTextual(this.pagina, this.texto);
}

/// Un trozo de conocimiento: un resumen en español sencillo, su fuente y sus citas.
class Fragmento {
  final String id;
  final String tema;
  final String titulo;
  final String texto;

  /// "FHIA, InfoCacao No. 14 (2017), p. 4": lo que se muestra y se cita.
  final String fuente;
  final String fuenteId;
  final List<CitaTextual> citas;

  /// Palabras clave (sin tildes, en minúscula) para encontrarlo.
  final List<String> palabras;

  const Fragmento({
    required this.id,
    required this.tema,
    required this.titulo,
    required this.texto,
    required this.fuente,
    required this.fuenteId,
    required this.citas,
    required this.palabras,
  });
}

class PreguntaFrecuente {
  final String id;
  final List<String> preguntas;
  final List<String> palabras;

  /// Ids de los fragmentos que forman la respuesta (así la respuesta siempre lleva su fuente).
  final List<String> fragmentos;

  const PreguntaFrecuente({required this.id, required this.preguntas, required this.palabras, required this.fragmentos});
}

class TerminoGlosario {
  final String termino;
  final String definicion;
  final String? fuenteId;
  final String fuente;
  final List<String> palabras;

  const TerminoGlosario({
    required this.termino,
    required this.definicion,
    required this.fuenteId,
    required this.fuente,
    required this.palabras,
  });
}

/// Los límites con los que el servidor acepta los fragmentos (ver backend/src/chat.ts).
class LimitesServidor {
  static final idFragmento = RegExp(r'^[A-Za-z0-9_.-]{1,40}$');
  static const maxFuente = 200;
  static const maxTexto = 1500;
  static const maxFragmentos = 5;
}

/// Base de conocimiento propia de la app: va dentro del teléfono y funciona sin internet.
/// Cada fragmento lleva su fuente; lo que no se pudo verificar está en [pendientes] y NO se
/// responde como si se supiera.
class BaseConocimiento {
  static const rutaAsset = 'assets/conocimiento/base.json';

  final String revisado;
  final List<String> temas;
  final Map<String, FuenteDocumento> fuentes;
  final List<String> pendientes;
  final List<Fragmento> fragmentos;
  final List<PreguntaFrecuente> faq;
  final List<TerminoGlosario> glosario;
  final Map<String, Fragmento> _porId;

  BaseConocimiento._(this.revisado, this.temas, this.fuentes, this.pendientes, this.fragmentos, this.faq, this.glosario)
      : _porId = {for (final f in fragmentos) f.id: f};

  Fragmento? fragmentoPorId(String id) => _porId[id];

  /// Lee y VALIDA el JSON. Lanza [FormatException] si algo no cumple (ids repetidos, fuente
  /// vacía, tema desconocido, FAQ que apunta a un fragmento que no existe...).
  factory BaseConocimiento.desdeJson(String texto) {
    final j = jsonDecode(texto) as Map<String, dynamic>;
    String s(Object? v, String campo) {
      if (v is! String || v.trim().isEmpty) throw FormatException('Falta "$campo"');
      return v;
    }

    List<String> lista(Object? v) => (v as List? ?? const []).map((e) => '$e').toList();

    final temas = lista(j['temas']);
    final fuentes = <String, FuenteDocumento>{};
    (j['fuentes'] as Map<String, dynamic>).forEach((id, v) {
      final m = v as Map<String, dynamic>;
      fuentes[id] = FuenteDocumento(
        id: id,
        corta: s(m['corta'], 'fuente.corta'),
        titulo: s(m['titulo'], 'fuente.titulo'),
        autor: s(m['autor'], 'fuente.autor'),
        anio: (m['anio'] as num).toInt(),
        url: s(m['url'], 'fuente.url'),
        nota: (m['nota'] as String?) ?? '',
      );
    });

    final fragmentos = <Fragmento>[];
    for (final v in j['fragmentos'] as List) {
      final m = v as Map<String, dynamic>;
      final id = s(m['id'], 'id');
      final tema = s(m['tema'], 'tema');
      if (!temas.contains(tema)) throw FormatException('Tema desconocido "$tema" en $id');
      final fuenteId = s(m['fuente_id'], 'fuente_id');
      if (!fuentes.containsKey(fuenteId)) throw FormatException('Fuente desconocida "$fuenteId" en $id');
      fragmentos.add(Fragmento(
        id: id,
        tema: tema,
        titulo: s(m['titulo'], 'titulo'),
        texto: s(m['texto'], 'texto'),
        fuente: s(m['fuente'], 'fuente'),
        fuenteId: fuenteId,
        citas: [for (final c in m['citas'] as List) CitaTextual((c['p'] as num).toInt(), s(c['t'], 'cita'))],
        palabras: lista(m['palabras']),
      ));
    }
    if (fragmentos.map((f) => f.id).toSet().length != fragmentos.length) throw const FormatException('Ids de fragmento repetidos');
    final ids = fragmentos.map((f) => f.id).toSet();

    final faq = <PreguntaFrecuente>[];
    for (final v in j['faq'] as List) {
      final m = v as Map<String, dynamic>;
      final frs = lista(m['fragmentos']);
      final falta = frs.where((id) => !ids.contains(id));
      if (falta.isNotEmpty) throw FormatException('La FAQ ${m['id']} apunta a fragmentos que no existen: $falta');
      faq.add(PreguntaFrecuente(id: s(m['id'], 'faq.id'), preguntas: lista(m['preguntas']), palabras: lista(m['palabras']), fragmentos: frs));
    }

    final glosario = [
      for (final v in j['glosario'] as List)
        TerminoGlosario(
          termino: s((v as Map)['termino'], 'termino'),
          definicion: s(v['definicion'], 'definicion'),
          fuenteId: v['fuente_id'] as String?,
          fuente: s(v['fuente'], 'glosario.fuente'),
          palabras: lista(v['palabras']),
        ),
    ];

    return BaseConocimiento._(s(j['revisado'], 'revisado'), temas, fuentes, lista(j['pendientes']), fragmentos, faq, glosario);
  }

  static BaseConocimiento? _cargada;

  /// Carga la base de la app (una sola vez).
  static Future<BaseConocimiento> cargar([AssetBundle? bundle]) async {
    final ya = _cargada;
    if (ya != null && bundle == null) return ya;
    final b = BaseConocimiento.desdeJson(await (bundle ?? rootBundle).loadString(rutaAsset));
    if (bundle == null) _cargada = b;
    return b;
  }
}
