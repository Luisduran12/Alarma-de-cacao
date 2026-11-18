import 'package:flutter_test/flutter_test.dart';

import 'package:alarmacacao5_0/data/base_conocimiento.dart';
import 'package:alarmacacao5_0/services/buscador_conocimiento.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BaseConocimiento base;
  late BuscadorConocimiento b;
  setUpAll(() async {
    base = await BaseConocimiento.cargar();
    b = BuscadorConocimiento(base);
  });

  List<String> ids(String q, {String? etapa, int limite = 4}) => b.buscar(q, etapa: etapa, limite: limite).map((f) => f.id).toList();

  group('normalizar y tokens', () {
    test('quita tildes, signos y mayúsculas', () {
      expect(BuscadorConocimiento.normalizar('¿Cuándo volteo?'), 'cuando volteo');
      expect(BuscadorConocimiento.normalizar('  COMO   SECO, mi CACAO?? '), 'como seco mi cacao');
      expect(BuscadorConocimiento.normalizar('Niño pingüino'), 'nino pinguino');
    });

    test('ignora palabras vacías (incluida "cacao", que está en todo)', () {
      expect(BuscadorConocimiento.tokens('¿Cómo seco mi cacao?'), ['seco']);
      expect(BuscadorConocimiento.tokens('el de la y'), isEmpty);
    });
  });

  group('encuentra lo que corresponde', () {
    test('¿Cuándo volteo? → los fragmentos del volteo', () {
      final r = ids('¿Cuándo volteo?');
      expect(r.take(2), containsAll(['vol-01', 'vol-02']));
    });

    test('"cada cuánto se voltea el cacao" → vol-01 primero', () => expect(ids('cada cuánto se voltea el cacao').first, 'vol-01'));
    test('¿Cómo seco mi cacao? → secado al sol entre los primeros', () => expect(ids('¿Cómo seco mi cacao?').take(2), contains('sec-01')));
    test('¿Cómo hago la prueba de corte? → corte-01 primero', () => expect(ids('¿Cómo hago la prueba de corte?').first, 'corte-01'));
    test('¿Qué es la monilia? → enf-01 primero', () => expect(ids('¿Qué es la monilia?').first, 'enf-01'));
    test('mazorca negra → enf-06 primero', () => expect(ids('mi mazorca está negra, es mazorca negra?').first, 'enf-06'));
    test('"mi cacao huele a humo" → el del humo entre los primeros', () => expect(ids('mi cacao huele a humo').take(3), contains('def-03')));
    test('"hay ratones en la bodega" → almacenamiento', () => expect(ids('hay ratones en la bodega').first, 'alm-01'));
    test('¿Cuánto dura la fermentación? → ferm-05', () => expect(ids('¿Cuántos días dura la fermentación?').first, 'ferm-05'));

    test('no distingue mayúsculas, tildes ni signos', () {
      expect(ids('COMO SECO MI CACAO??'), ids('¿Cómo seco mi cacao?'));
    });

    test('es determinista: misma pregunta, mismo resultado y mismo orden', () {
      expect(ids('temperatura de la masa'), ids('temperatura de la masa'));
    });
  });

  group('la etapa del lote desempata', () {
    test('"¿Está normal mi temperatura?": en fermentación → ferm-04; en secado → sec-06', () {
      expect(ids('¿Está normal mi temperatura?', etapa: 'fermentacion').first, 'ferm-04');
      expect(ids('¿Está normal mi temperatura?', etapa: 'secado').first, 'sec-06');
    });

    test('la etapa no hace aparecer cosas que no tienen que ver', () {
      expect(ids('¿cuánto cuesta un kilo?', etapa: 'secado'), isEmpty);
    });
  });

  group('sin relación: no inventa', () {
    test('preguntas que no son de cacao o no se parecen a nada devuelven vacío', () {
      for (final q in ['hola', '', '   ', '¿qué hora es?', '¿cuánto cuesta un kilo de cacao?', '¿quién ganó el partido?', 'asdfgh qwerty', '???']) {
        expect(ids(q), isEmpty, reason: q);
      }
    });

    test('limite 0 o negativo devuelve vacío', () {
      expect(b.buscar('volteo', limite: 0), isEmpty);
      expect(b.buscar('volteo', limite: -1), isEmpty);
    });
  });

  group('límite y orden', () {
    test('respeta el límite', () {
      expect(b.buscar('fermentación', limite: 2), hasLength(2));
      expect(b.buscar('fermentación', limite: 5).length, lessThanOrEqualTo(5));
    });

    test('ordena del mejor al peor puntaje', () {
      final r = b.buscarConPuntaje('secado del cacao temperatura humedad', limite: 5);
      for (var i = 1; i < r.length; i++) {
        expect(r[i - 1].puntaje, greaterThanOrEqualTo(r[i].puntaje));
      }
      for (final x in r) {
        expect(x.puntaje, greaterThanOrEqualTo(BuscadorConocimiento.puntajeMinimo));
      }
    });
  });

  group('cada fragmento se puede encontrar', () {
    test('buscando por su propio título, el fragmento aparece entre los 5 primeros', () {
      final fallan = <String>[];
      for (final f in base.fragmentos) {
        if (!ids(f.titulo, limite: 5).contains(f.id)) fallan.add('${f.id} ("${f.titulo}")');
      }
      expect(fallan, isEmpty, reason: 'estos fragmentos no se encuentran por su título: $fallan');
    });
  });

  group('preguntas frecuentes', () {
    test('cada pregunta de la lista, tal cual está escrita, lleva a su propia FAQ', () {
      for (final f in base.faq) {
        for (final p in f.preguntas) {
          expect(b.mejorFaq(p)?.id, f.id, reason: p);
        }
      }
    });

    test('variantes: sin tildes, sin signos, con otras palabras', () {
      expect(b.mejorFaq('cada cuanto se voltea el cacao')?.id, 'faq-01');
      expect(b.mejorFaq('que es la monilia')?.id, 'faq-10');
      expect(b.mejorFaq('como guardo los sacos en la bodega')?.id, 'faq-09');
    });

    test('lo que no está en la lista da null', () {
      for (final q in ['', 'hola', '¿cuánto cuesta un kilo?', 'qwerty']) {
        expect(b.mejorFaq(q), isNull, reason: q);
      }
    });
  });

  group('glosario', () {
    test('encuentra el término por el que se pregunta', () {
      expect(b.terminoEn('¿qué es arrebatar el cacao?')?.termino, 'Arrebatar el cacao');
      expect(b.terminoEn('que es la fermentacion')?.termino, 'Fermentación');
      expect(b.terminoEn('qué significa volteo')?.termino, 'Volteo');
      expect(b.terminoEn('qué es la temperatura ambiente')?.termino, 'Temperatura ambiente');
    });

    test('prefiere el término más específico (mazorca negra, no solo "mazorca")', () {
      expect(b.terminoEn('qué es la mazorca negra')?.termino, 'Mazorca negra');
      expect(b.terminoEn('escoba de bruja')?.termino, 'Escoba de bruja');
    });

    test('no confunde palabras parecidas ni inventa', () {
      expect(b.terminoEn('hola'), isNull);
      expect(b.terminoEn(''), isNull);
      expect(b.terminoEn('quiero un volteador'), isNull);
    });
  });
}
