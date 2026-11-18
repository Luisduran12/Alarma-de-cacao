import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:alarmacacao5_0/data/base_conocimiento.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BaseConocimiento base;
  setUpAll(() async => base = await BaseConocimiento.cargar());

  group('la base que va en la app', () {
    test('trae fragmentos, preguntas frecuentes y glosario', () {
      expect(base.fragmentos.length, greaterThanOrEqualTo(35));
      expect(base.faq, hasLength(14));
      expect(base.glosario, hasLength(10));
      expect(base.revisado, '2026-11-18');
    });

    test('cubre los 7 temas pedidos (fermentación, volteo, secado, prueba de corte, defectos, almacenamiento y enfermedades)', () {
      for (final tema in ['fermentacion', 'volteo', 'secado', 'prueba_corte', 'defectos', 'almacenamiento', 'enfermedades']) {
        expect(base.fragmentos.where((f) => f.tema == tema), isNotEmpty, reason: tema);
      }
      for (final f in base.fragmentos) {
        expect(base.temas, contains(f.tema), reason: f.id);
      }
    });

    test('cada fragmento cumple los límites del servidor (id, fuente ≤ 200, texto ≤ 1500)', () {
      for (final f in base.fragmentos) {
        expect(LimitesServidor.idFragmento.hasMatch(f.id), isTrue, reason: f.id);
        expect(f.fuente.length, inInclusiveRange(1, LimitesServidor.maxFuente), reason: f.id);
        expect(f.texto.length, inInclusiveRange(1, LimitesServidor.maxTexto), reason: f.id);
        expect(f.titulo.trim(), isNotEmpty, reason: f.id);
      }
    });

    test('TODO fragmento tiene fuente conocida, página y al menos una cita textual', () {
      for (final f in base.fragmentos) {
        final doc = base.fuentes[f.fuenteId];
        expect(doc, isNotNull, reason: f.id);
        expect(f.fuente, startsWith(doc!.corta), reason: f.id);
        expect(f.fuente, matches(RegExp(r'p\. \d+')), reason: f.id);
        expect(f.citas, isNotEmpty, reason: f.id);
        for (final c in f.citas) {
          expect(c.pagina, greaterThan(0), reason: f.id);
          expect(c.texto.trim().length, greaterThan(15), reason: f.id);
        }
      }
    });

    test('los ids son únicos y la FAQ solo apunta a fragmentos que existen', () {
      expect(base.fragmentos.map((f) => f.id).toSet(), hasLength(base.fragmentos.length));
      for (final q in base.faq) {
        expect(q.preguntas, isNotEmpty, reason: q.id);
        expect(q.fragmentos, isNotEmpty, reason: q.id);
        for (final id in q.fragmentos) {
          expect(base.fragmentoPorId(id), isNotNull, reason: '${q.id} → $id');
        }
      }
    });

    test('el glosario: cada término está definido por una fuente, salvo el que define la propia app', () {
      for (final g in base.glosario) {
        if (g.fuenteId == null) {
          expect(g.fuente, 'Definición de esta app');
          expect(g.termino, 'Temperatura ambiente');
        } else {
          expect(base.fuentes, contains(g.fuenteId), reason: g.termino);
          expect(g.fuente, matches(RegExp(r'p\. \d+')), reason: g.termino);
        }
      }
    });

    test('tiene las 3 fuentes, con enlace y año', () {
      expect(base.fuentes.keys, containsAll(['fhia2017', 'lasalle2022', 'ica2012']));
      for (final d in base.fuentes.values) {
        expect(d.url, startsWith('https://'));
        expect(d.anio, greaterThan(2000));
      }
    });

    test('declara lo pendiente en vez de inventarlo (NTC 1252, aspecto de los grupos, rangos...)', () {
      final p = base.pendientes.join(' ');
      expect(p, contains('NTC 1252'));
      expect(p, contains('prueba de corte'));
      expect(p, contains('Productos y dosis'));
    });

    test('NO hay productos ni dosis de agroquímicos en ningún texto', () {
      final prohibido = RegExp(
        r'ridomil|c[uú]prico|cobre|fungicida|insecticida|herbicida|dosis|cucharada|g/ ?l|gramos por litro|cm3|ml/ ?l|aplicaci[oó]n(es)? de',
        caseSensitive: false,
      );
      for (final f in base.fragmentos) {
        expect(prohibido.hasMatch('${f.titulo} ${f.texto}'), isFalse, reason: f.id);
      }
      for (final g in base.glosario) {
        expect(prohibido.hasMatch(g.definicion), isFalse, reason: g.termino);
      }
    });

    test('NO aparecen cifras de fuentes no verificadas (65 %, 300 granos, 10 % de pizarrosos...)', () {
      final todo = base.fragmentos.map((f) => f.texto).join(' ');
      for (final x in ['65 %', '300 granos', '10 % de pizarr', '30 granos', '50 granos']) {
        expect(todo.contains(x), isFalse, reason: x);
      }
    });

    test('los fragmentos de enfermedades siempre remiten al técnico, a la asociación o a FEDECACAO cuando hablan de tratar', () {
      final tratamiento = base.fragmentos.firstWhere((f) => f.id == 'enf-08');
      expect(tratamiento.texto, contains('FEDECACAO'));
      expect(tratamiento.texto, contains('técnico'));
    });
  });

  group('desdeJson valida lo que lee', () {
    Map<String, dynamic> minimo() => {
          'revisado': '2026-01-01',
          'temas': ['secado'],
          'fuentes': {'x': {'corta': 'X', 'titulo': 't', 'autor': 'a', 'anio': 2020, 'url': 'https://x', 'nota': ''}},
          'pendientes': [],
          'fragmentos': <dynamic>[
            {'id': 'a-1', 'tema': 'secado', 'titulo': 't', 'texto': 'x', 'fuente_id': 'x', 'fuente': 'X, p. 1', 'citas': [], 'palabras': []},
          ],
          'faq': <dynamic>[],
          'glosario': <dynamic>[],
        };

    BaseConocimiento desde(void Function(Map<String, dynamic>) cambiar) {
      final m = minimo();
      cambiar(m);
      return BaseConocimiento.desdeJson(jsonEncode(m));
    }

    test('lo mínimo válido se acepta', () => expect(desde((_) {}).fragmentos, hasLength(1)));

    test('tema desconocido, fuente desconocida, ids repetidos y FAQ rota se rechazan', () {
      Map<String, dynamic> fr(Map<String, dynamic> m) => (m['fragmentos'] as List).first as Map<String, dynamic>;
      expect(() => desde((m) => fr(m)['tema'] = 'otro'), throwsFormatException);
      expect(() => desde((m) => fr(m)['fuente_id'] = 'nada'), throwsFormatException);
      expect(() => desde((m) => (m['fragmentos'] as List).add(Map<String, dynamic>.from(fr(m)))), throwsFormatException);
      expect(
        () => desde((m) => (m['faq'] as List).add({'id': 'q', 'preguntas': ['?'], 'palabras': [], 'fragmentos': ['no-existe']})),
        throwsFormatException,
      );
      expect(() => desde((m) => fr(m)['fuente'] = ''), throwsFormatException);
    });
  });
}
