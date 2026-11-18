import '../data/base_conocimiento.dart';

class ResultadoBusqueda {
  final Fragmento fragmento;
  final int puntaje;
  const ResultadoBusqueda(this.fragmento, this.puntaje);
}

/// Búsqueda por palabras, sin internet y sin IA: sirve para elegir qué fragmentos mandar con
/// la pregunta al chat y para contestar sin conexión. Es determinista (misma pregunta, mismo
/// resultado) y tiene un puntaje mínimo: si la pregunta no se parece a nada, devuelve vacío en
/// vez de traer material por casualidad.
class BuscadorConocimiento {
  final BaseConocimiento base;
  BuscadorConocimiento(this.base);

  /// Con menos que esto no se considera que la pregunta tenga que ver con el fragmento.
  static const puntajeMinimo = 3;

  static const _paraEtapa = {
    'fermentacion': {'fermentacion', 'volteo', 'prueba_corte'},
    'secado': {'secado', 'defectos', 'almacenamiento'},
  };

  static const _ignoradas = {
    'de', 'la', 'el', 'los', 'las', 'un', 'una', 'unos', 'unas', 'y', 'o', 'u', 'en', 'a', 'al', 'del', 'lo', 'que',
    'es', 'son', 'mi', 'mis', 'tu', 'tus', 'su', 'sus', 'se', 'por', 'para', 'con', 'sin', 'como', 'cuando', 'cual',
    'cuales', 'cuanto', 'cuantos', 'cuanta', 'donde', 'quien', 'porque', 'esta', 'este', 'estos', 'estas', 'ese',
    'eso', 'hay', 'ser', 'fue', 'ya', 'mas', 'muy', 'me', 'te', 'le', 'les', 'si', 'no', 'ni', 'pero', 'cacao',
  };

  /// Minúsculas, sin tildes ni signos: "¿Cuándo volteo?" → "cuando volteo".
  static String normalizar(String t) {
    const de = 'áàäâéèëêíìïîóòöôúùüûñ', a = 'aaaaeeeeiiiioooouuuun';
    final b = StringBuffer();
    for (final c in t.toLowerCase().runes) {
      final s = String.fromCharCode(c);
      final i = de.indexOf(s);
      b.write(i >= 0 ? a[i] : s);
    }
    return b.toString().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  }

  static List<String> tokens(String t) =>
      normalizar(t).split(' ').where((w) => w.length >= 2 && !_ignoradas.contains(w)).toList();

  /// Raíz aproximada: "voltear", "voltee" y "volteo" comparten "volte".
  static String _raiz(String w) => w.length >= 5 ? w.substring(0, 5) : w;
  static bool _igual(String a, String b) => a.length < 4 || b.length < 4 ? a == b : _raiz(a) == _raiz(b);

  int _puntuar(String pregunta, Set<String> q, {required List<String> palabras, String titulo = '', String texto = ''}) {
    var p = 0;
    final frases = palabras.map(normalizar);
    // Frase completa de las palabras clave dentro de la pregunta.
    for (final f in frases) {
      if (f.contains(' ') && pregunta.contains(f)) p += 5;
    }
    final clave = frases.expand((f) => f.split(' ')).where((w) => w.length >= 2).toSet();
    final enTitulo = tokens(titulo).toSet();
    final enTexto = tokens(texto).toSet();
    // Coincidencia exacta vale más que la de raíz: "partido" no debe parecerse a "partir".
    for (final w in q) {
      if (clave.contains(w)) {
        p += 3;
      } else if (enTitulo.contains(w)) {
        p += 2;
      } else if (clave.any((k) => _igual(w, k))) {
        p += 2;
      } else if (enTitulo.any((k) => _igual(w, k)) || enTexto.contains(w)) {
        p += 1;
      }
    }
    return p;
  }

  /// Los fragmentos más relacionados con [pregunta], del mejor al peor (máximo [limite]).
  /// [etapa] ('fermentacion' o 'secado') da una ventaja a los temas de esa etapa.
  List<ResultadoBusqueda> buscarConPuntaje(String pregunta, {String? etapa, int limite = 4}) {
    final norm = normalizar(pregunta);
    final q = tokens(pregunta).toSet();
    if (q.isEmpty || limite <= 0) return const [];
    final temas = _paraEtapa[etapa] ?? const <String>{};
    final r = <ResultadoBusqueda>[];
    for (final f in base.fragmentos) {
      var p = _puntuar(norm, q, palabras: f.palabras, titulo: f.titulo, texto: f.texto);
      if (p >= puntajeMinimo && temas.contains(f.tema)) p += 1;
      if (p >= puntajeMinimo) r.add(ResultadoBusqueda(f, p));
    }
    r.sort((a, b) => b.puntaje != a.puntaje ? b.puntaje.compareTo(a.puntaje) : a.fragmento.id.compareTo(b.fragmento.id));
    return r.take(limite).toList();
  }

  List<Fragmento> buscar(String pregunta, {String? etapa, int limite = 4}) =>
      buscarConPuntaje(pregunta, etapa: etapa, limite: limite).map((r) => r.fragmento).toList();

  /// La pregunta frecuente que mejor responde, o null. Una pregunta escrita igual que una de
  /// la lista gana siempre.
  PreguntaFrecuente? mejorFaq(String pregunta) {
    final norm = normalizar(pregunta);
    if (norm.isEmpty) return null;
    for (final f in base.faq) {
      if (f.preguntas.any((p) => normalizar(p) == norm)) return f;
    }
    final q = tokens(pregunta).toSet();
    PreguntaFrecuente? mejor;
    var mejorPuntaje = puntajeMinimo - 1;
    for (final f in base.faq) {
      final p = _puntuar(norm, q, palabras: f.palabras, titulo: f.preguntas.join(' '));
      if (p > mejorPuntaje) {
        mejor = f;
        mejorPuntaje = p;
      }
    }
    return mejor;
  }

  /// El término del glosario por el que se pregunta ("¿qué es arrebatar el cacao?"), o null.
  TerminoGlosario? terminoEn(String pregunta) {
    final norm = normalizar(pregunta);
    if (norm.isEmpty) return null;
    TerminoGlosario? mejor;
    var largo = 0;
    for (final g in base.glosario) {
      final candidatos = [g.termino, ...g.palabras].map(normalizar);
      for (final c in candidatos) {
        if (c.length > largo && RegExp('(^| )${RegExp.escape(c)}( |\$)').hasMatch(norm)) {
          mejor = g;
          largo = c.length;
        }
      }
    }
    return mejor;
  }
}
