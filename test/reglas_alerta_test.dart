import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alarmacacao5_0/data/referencias_curva.dart';
import 'package:alarmacacao5_0/models/volteada.dart';
import 'package:alarmacacao5_0/services/reglas_alerta.dart';

Volteada _reg({
  double temp = 46,
  double hum = 80,
  String etapa = Etapa.fermentacion,
  double? ph,
  double? brix,
  double? amb,
}) =>
    Volteada(
      id: 'r', loteId: 'l', mensaje: '', temperatura: temp, humedad: hum, observacion: '',
      fecha: DateTime(2026), fechaProgramada: DateTime(2026), confirmada: true,
      etapa: etapa, ph: ph, brix: brix, tempAmbiente: amb,
    );

List<AlertaDisparada> _eval(Volteada v, double horas, [List<ReglaAlerta>? reglas]) =>
    EvaluadorAlertas.evaluar(v, horas, reglas ?? reglasDeFabrica());

void main() {
  group('reglas de fábrica', () {
    test('son dos y cada una trae su fuente', () {
      final r = reglasDeFabrica();
      expect(r, hasLength(2));
      for (final x in r) {
        expect(x.fuente.trim(), isNotEmpty);
        expect(x.deFabrica, isTrue);
      }
    });

    test('los números salen de ReferenciasCurva, no están repetidos', () {
      final r = reglasDeFabrica();
      final ferm = r.firstWhere((x) => x.etapa == Etapa.fermentacion);
      final sec = r.firstWhere((x) => x.etapa == Etapa.secado);
      expect(ferm.minimo, ReferenciasCurva.fermentacionTemperatura.minimo);
      expect(ferm.desdeHora, ReferenciasCurva.fermentacionTemperatura.desdeHora);
      expect(sec.maximo, ReferenciasCurva.secadoTemperatura.maximo);
    });

    test('no hay regla de "masa muy caliente": la fuente dice "50 °C o más"', () {
      expect(_eval(_reg(temp: 58), 100), isEmpty);
    });
  });

  group('fermentación fría', () {
    test('por debajo de 45 °C desde la hora 48 dispara la alerta', () {
      final a = _eval(_reg(temp: 43.5), 72);
      expect(a, hasLength(1));
      expect(a.single.bajo, isTrue);
      expect(a.single.valor, 43.5);
    });

    test('exactamente 45 °C no dispara (el rango es "arriba de 45" inclusive del límite)', () {
      expect(_eval(_reg(temp: 45), 72), isEmpty);
    });

    test('antes de la hora 48 no dispara aunque esté frío (la masa aún está subiendo)', () {
      expect(_eval(_reg(temp: 30), 47.9), isEmpty);
      expect(_eval(_reg(temp: 30), 48), hasLength(1));
    });

    test('en secado esa regla no aplica', () {
      expect(_eval(_reg(temp: 30, etapa: Etapa.secado), 100), isEmpty);
    });
  });

  group('secado caliente', () {
    test('sobre 50 °C dispara; 50 exacto no', () {
      expect(_eval(_reg(temp: 51, etapa: Etapa.secado), 150), hasLength(1));
      expect(_eval(_reg(temp: 50, etapa: Etapa.secado), 150), isEmpty);
    });

    test('el texto trae la medida, el límite y el consejo con la fuente de la cifra', () {
      final t = _eval(_reg(temp: 52.5, etapa: Etapa.secado), 150).single.texto;
      expect(t, contains('52,5 °C'));
      expect(t, contains('por encima de 50 °C'));
      expect(t, contains('no debe pasar de 50 °C'));
    });
  });

  group('reglas propias', () {
    const phBajo = ReglaAlerta(
      id: 'mia_ph', variable: VariableMedida.ph, minimo: 4, mensaje: 'pH bajo', fuente: 'Mi técnico',
    );

    test('una variable opcional sin medir no dispara', () {
      expect(_eval(_reg(), 10, [phBajo]), isEmpty);
    });

    test('con el pH medido sí dispara y lo explica', () {
      final a = _eval(_reg(ph: 3.4), 10, [phBajo]);
      expect(a.single.texto, startsWith('pH: 3,4, por debajo de 4.'));
    });

    test('una regla desactivada no dispara', () {
      expect(_eval(_reg(ph: 3.4), 10, [phBajo.copyWith(activa: false)]), isEmpty);
    });

    test('rango con mínimo y máximo: avisa por cualquiera de los dos lados', () {
      const hum = ReglaAlerta(
        id: 'h', variable: VariableMedida.humedad, minimo: 60, maximo: 90, mensaje: '', fuente: 'x',
      );
      expect(_eval(_reg(hum: 55), 1, [hum]).single.bajo, isTrue);
      expect(_eval(_reg(hum: 95), 1, [hum]).single.bajo, isFalse);
      expect(_eval(_reg(hum: 75), 1, [hum]), isEmpty);
    });

    test('varias reglas pueden dispararse con el mismo registro', () {
      const a = ReglaAlerta(id: 'a', variable: VariableMedida.temperatura, minimo: 50, mensaje: '', fuente: 'x');
      const b = ReglaAlerta(id: 'b', variable: VariableMedida.humedad, maximo: 70, mensaje: '', fuente: 'x');
      expect(_eval(_reg(temp: 40, hum: 85), 1, [a, b]), hasLength(2));
    });
  });

  group('JSON y almacenamiento', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('ida y vuelta conserva todos los campos', () {
      const r = ReglaAlerta(
        id: 'x', variable: VariableMedida.brix, etapa: Etapa.fermentacion, minimo: 5, maximo: 20,
        desdeHora: 12, activa: false, mensaje: 'm', fuente: 'f',
      );
      final v = ReglaAlerta.fromJson(r.toJson())!;
      expect([v.id, v.variable, v.etapa, v.minimo, v.maximo, v.desdeHora, v.activa, v.mensaje, v.fuente],
          ['x', VariableMedida.brix, Etapa.fermentacion, 5.0, 20.0, 12.0, false, 'm', 'f']);
    });

    test('un registro dañado se descarta sin romper', () {
      expect(ReglaAlerta.fromJson({'id': 'x', 'variable': 'inventada'}), isNull);
      expect(ReglaAlerta.fromJson('texto'), isNull);
      expect(ReglaAlerta.fromJson({'variable': 'ph'}), isNull);
    });

    test('sin nada guardado devuelve las de fábrica', () async {
      expect((await ReglasAlertaStorage.cargar()).map((r) => r.id), reglasDeFabrica().map((r) => r.id));
    });

    test('guarda una edición y la recupera', () async {
      final lista = reglasDeFabrica();
      lista[0] = lista[0].copyWith(minimo: 44);
      lista.add(const ReglaAlerta(
          id: 'mia', variable: VariableMedida.ph, minimo: 4, mensaje: 'm', fuente: 'Mi técnico'));
      await ReglasAlertaStorage.guardar(lista);

      final c = await ReglasAlertaStorage.cargar();
      expect(c, hasLength(3));
      expect(c[0].minimo, 44);
      expect(c[0].deFabrica, isTrue, reason: 'editar una de fábrica no la vuelve propia');
      expect(c[2].fuente, 'Mi técnico');
    });

    test('se puede apagar una regla de fábrica y queda apagada', () async {
      final lista = reglasDeFabrica();
      lista[0] = lista[0].copyWith(activa: false);
      await ReglasAlertaStorage.guardar(lista);
      expect(_eval(_reg(temp: 30), 72, await ReglasAlertaStorage.cargar()), isEmpty);
    });

    test('restaurar borra ediciones y reglas propias', () async {
      await ReglasAlertaStorage.guardar([
        const ReglaAlerta(id: 'mia', variable: VariableMedida.ph, mensaje: '', fuente: 'x'),
      ]);
      await ReglasAlertaStorage.restaurar();
      expect((await ReglasAlertaStorage.cargar()), hasLength(2));
    });

    test('datos dañados en el teléfono: cae a las de fábrica', () async {
      SharedPreferences.setMockInitialValues({ReglasAlertaStorage.clave: 'esto no es json'});
      expect(await ReglasAlertaStorage.cargar(), hasLength(2));
      SharedPreferences.setMockInitialValues({ReglasAlertaStorage.clave: '{"a":1}'});
      expect(await ReglasAlertaStorage.cargar(), hasLength(2));
    });

    test('copyWith puede quitar un límite (quitarMinimo)', () {
      final r = reglasDeFabrica()[0].copyWith(quitarMinimo: true, quitarDesdeHora: true);
      expect(r.minimo, isNull);
      expect(r.desdeHora, isNull);
    });
  });
}
