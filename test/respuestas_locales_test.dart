import 'package:flutter_test/flutter_test.dart';

import 'package:alarmacacao5_0/data/base_conocimiento.dart';
import 'package:alarmacacao5_0/data/guia_prueba_corte.dart';
import 'package:alarmacacao5_0/data/referencias_curva.dart';
import 'package:alarmacacao5_0/models/lote.dart';
import 'package:alarmacacao5_0/models/volteada.dart';
import 'package:alarmacacao5_0/services/respuestas_locales.dart';

final _inicio = DateTime(2026, 11, 10, 8);

Volteada _med(int hora, double t, {String etapa = Etapa.fermentacion}) => Volteada(
    id: 'm$hora', loteId: 'L', mensaje: '', temperatura: t, humedad: 80, observacion: '',
    fecha: _inicio.add(Duration(hours: hora)), fechaProgramada: _inicio.add(Duration(hours: hora)), confirmada: true, etapa: etapa);

Volteada _pend(int hora) => Volteada(
    id: 'p$hora', loteId: 'L', mensaje: '', temperatura: 0, humedad: 0, observacion: '',
    fecha: _inicio.add(Duration(hours: hora)), fechaProgramada: _inicio.add(Duration(hours: hora)), confirmada: false);

Lote _lote(List<Volteada> vs) => Lote(id: 'L', title: 'Lote privado', volteadas: vs, status: 'en proceso', createdAt: _inicio, inicioCiclo: _inicio);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BaseConocimiento base;
  late RespuestasLocales r;
  setUpAll(() async {
    base = await BaseConocimiento.cargar();
    r = RespuestasLocales(base);
  });
  DateTime h(int horas) => _inicio.add(Duration(hours: horas));

  group('botones rápidos', () {
    test('son los 5 pedidos, con esas palabras', () {
      expect(PreguntaRapida.todas.map((p) => p.etiqueta), [
        '¿Cómo va mi lote?', '¿Cuándo volteo?', '¿Está normal mi temperatura?', '¿Cómo hago la prueba de corte?', '¿Cómo seco mi cacao?',
      ]);
    });

    test('escribir el texto de un botón da lo mismo que tocarlo', () {
      final lote = _lote([_med(60, 46)]);
      for (final p in PreguntaRapida.todas) {
        expect(r.responder(p.etiqueta, lote: lote, ahora: h(61)).texto, r.rapida(p.intencion, lote: lote, ahora: h(61)).texto, reason: p.etiqueta);
        expect(r.responder(p.etiqueta.toLowerCase().replaceAll('¿', '').replaceAll('?', ''), lote: lote, ahora: h(61)).texto,
            r.rapida(p.intencion, lote: lote, ahora: h(61)).texto);
      }
    });

    test('toda respuesta con contenido de la guía muestra su fuente en el texto', () {
      for (final i in [IntencionRapida.cuandoVolteo, IntencionRapida.pruebaCorte, IntencionRapida.comoSeco]) {
        final x = r.rapida(i, ahora: h(10));
        expect(x.fuentes, isNotEmpty, reason: '$i');
        for (final f in x.fuentes) {
          expect(x.texto, contains(f.fuente), reason: '$i ${f.id}');
        }
      }
    });
  });

  group('¿Cómo va mi lote?', () {
    test('sin lote o sin registros no inventa', () {
      expect(r.rapida(IntencionRapida.comoVa).encontrada, isFalse);
      final x = r.rapida(IntencionRapida.comoVa, lote: _lote([_pend(48)]), ahora: h(10));
      expect(x.texto, contains('Todavía no hay registros'));
      expect(x.fuentes, isEmpty);
    });

    test('con registros: etapa, horas, cantidad y frases del resumen', () {
      final x = r.rapida(IntencionRapida.comoVa, lote: _lote([_med(24, 35), _med(60, 46), _med(72, 48)]), ahora: h(80));
      expect(x.texto, contains('fermentación'));
      expect(x.texto, contains('80 h'));
      expect(x.texto, contains('3 registros'));
      expect(x.texto, contains('48,0 °C'));
      expect(x.texto, contains('fuera del rango'));
      expect(x.fuentes.single.fuente, ReferenciasCurva.fermentacionTemperatura.fuente);
      expect(x.texto, contains(ReferenciasCurva.fermentacionTemperatura.fuente));
    });

    test('sin horas comparables no cita fuente de rango', () {
      final x = r.rapida(IntencionRapida.comoVa, lote: _lote([_med(10, 30)]), ahora: h(12));
      expect(x.fuentes, isEmpty);
      expect(x.texto, contains('1 registro.'));
    });

    test('no muestra el nombre del lote', () {
      expect(r.rapida(IntencionRapida.comoVa, lote: _lote([_med(60, 46)]), ahora: h(61)).texto, isNot(contains('privado')));
    });
  });

  group('¿Cuándo volteo?', () {
    test('dice la próxima alarma pendiente y explica con la guía, con fuente', () {
      final x = r.rapida(IntencionRapida.cuandoVolteo, lote: _lote([_med(24, 35), _pend(72), _pend(48)]), ahora: h(30));
      expect(x.texto, contains('próxima alarma de volteo es el 12/11 a las 08:00'));
      expect(x.texto, contains('en 18 h'));
      expect(x.fuentes.map((f) => f.id), ['vol-01', 'vol-02']);
    });

    test('volteada vencida y sin pendientes', () {
      expect(r.rapida(IntencionRapida.cuandoVolteo, lote: _lote([_pend(48)]), ahora: h(60)).texto, contains('pendiente desde el 12/11'));
      expect(r.rapida(IntencionRapida.cuandoVolteo, lote: _lote([_med(24, 35)]), ahora: h(30)).texto, contains('no tiene volteadas programadas pendientes'));
    });

    test('sin lote igual explica con la guía', () {
      final x = r.rapida(IntencionRapida.cuandoVolteo);
      expect(x.texto, contains('24 horas'));
      expect(x.fuentes, isNotEmpty);
    });
  });

  group('¿Está normal mi temperatura?', () {
    String texto(double t, int hora, {String etapa = Etapa.fermentacion}) =>
        r.rapida(IntencionRapida.temperaturaNormal, lote: _lote([_med(hora, t, etapa: etapa)]), ahora: h(hora + 1)).texto;

    test('dentro de la referencia', () {
      final x = texto(47, 72);
      expect(x, contains('47,0 °C'));
      expect(x, contains('dentro de la referencia'));
      expect(x, contains('desde 45,0 hasta 50,0 °C o más'));
      expect(x, contains('no la del ambiente'));
    });

    test('por debajo', () => expect(texto(40, 72), allOf(contains('por debajo de la referencia'), contains('consulte a su técnico'))));

    test('más de 50 en fermentación: no lo llama peligroso porque la fuente dice "o más"', () {
      final x = texto(52, 100);
      expect(x, contains('"50,0 °C o más", no un tope'));
      expect(x, isNot(contains('por encima del máximo')));
    });

    test('en las primeras 48 h dice que no hay rango verificado, sin juzgar', () {
      final x = texto(30, 20);
      expect(x, contains('no tengo un rango verificado'));
      expect(x, isNot(contains('dentro de la referencia')));
      expect(x, isNot(contains('por debajo')));
    });

    test('secado: más de 50 es por encima del máximo y cita La Salle', () {
      final x = r.rapida(IntencionRapida.temperaturaNormal, lote: _lote([_med(150, 55, etapa: Etapa.secado)]), ahora: h(151));
      expect(x.texto, contains('por encima del máximo'));
      expect(x.texto, contains('máximo 50,0 °C'));
      expect(x.fuentes.single.id, 'sec-06');
    });

    test('usa la fuente del fragmento de su etapa', () {
      expect(r.rapida(IntencionRapida.temperaturaNormal, lote: _lote([_med(72, 47)]), ahora: h(73)).fuentes.single.id, 'ferm-04');
    });

    test('sin registros: lo dice y da la guía', () {
      final x = r.rapida(IntencionRapida.temperaturaNormal, lote: _lote([]), ahora: h(5));
      expect(x.texto, contains('Todavía no hay temperatura registrada'));
      expect(x.fuentes.single.id, 'ferm-04');
    });
  });

  group('prueba de corte y secado', () {
    test('la prueba de corte lleva el aviso de la NTC 1252', () {
      final x = r.rapida(IntencionRapida.pruebaCorte);
      expect(x.texto, contains(GuiaPruebaCorte.avisoNtc));
      expect(x.fuentes.map((f) => f.id), ['corte-01', 'corte-02']);
    });

    test('cómo seco: fragmentos de secado', () {
      expect(r.rapida(IntencionRapida.comoSeco).fuentes.map((f) => f.id), ['sec-01', 'sec-03']);
    });
  });

  group('preguntas escritas', () {
    test('FAQ con variantes', () {
      expect(r.responder('que es la monilia').fuentes.map((f) => f.id), ['enf-01', 'enf-02']);
      expect(r.responder('¿Cuántos días dura la fermentación?').fuentes.single.id, 'ferm-05');
      expect(r.responder('como guardo los sacos en la bodega').fuentes.single.id, 'alm-01');
    });

    test('glosario cuando preguntan qué significa algo', () {
      final x = r.responder('¿qué significa arrebatar el cacao?');
      expect(x.texto, startsWith('Arrebatar el cacao:'));
      expect(x.texto, contains('(Fuente:'));
    });

    test('término definido por la app se dice como tal, sin fuente inventada', () {
      final x = r.responder('qué es la temperatura ambiente');
      expect(x.texto, contains('definición de esta app'));
      expect(x.fuentes, isEmpty);
    });

    test('búsqueda de fragmentos para lo que no está en la FAQ', () {
      final x = r.responder('mi cacao huele a humo en la fermentación');
      expect(x.encontrada, isTrue);
      expect(x.fuentes.map((f) => f.id), contains('def-03'));
    });

    test('lo que no sabe, lo dice y manda al técnico', () {
      for (final q in ['', '¿cuánto cuesta un kilo de cacao?', '¿quién ganó el partido?', 'qwerty']) {
        final x = r.responder(q);
        expect(x.encontrada, isFalse, reason: q);
        expect(x.fuentes, isEmpty);
        expect(x.texto, contains('FEDECACAO'));
      }
    });

    test('nunca recomienda productos ni dosis', () {
      final prohibido = RegExp(r'fungicida|insecticida|cobre|dosis|gramos por litro|ml/l', caseSensitive: false);
      final textos = [
        for (final p in PreguntaRapida.todas) r.rapida(p.intencion, lote: _lote([_med(72, 47)]), ahora: h(73)).texto,
        for (final f in base.faq) r.responder(f.preguntas.first).texto,
      ];
      for (final t in textos) {
        expect(prohibido.hasMatch(t), isFalse, reason: t);
      }
    });

    test('el aviso de que la IA necesita conexión está definido', () {
      expect(RespuestasLocales.avisoSinIA, contains('IA necesita conexión'));
    });
  });
}
