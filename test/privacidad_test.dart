import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:alarmacacao5_0/data/politica_privacidad.dart';
import 'package:alarmacacao5_0/services/consentimiento_fotos.dart';

void main() {
  test('docs/privacidad.md es copia fiel de la política de la app (regenere con dart run tool/generar_privacidad.dart)', () {
    final md = File('docs/privacidad.md').readAsStringSync();
    for (final s in PoliticaPrivacidad.secciones) {
      expect(md, contains('## ${s.titulo}\n\n${s.texto}\n'), reason: s.titulo);
    }
  });

  test('la política dice lo de los 30 días de Anthropic', () {
    final t = PoliticaPrivacidad.secciones.map((s) => '${s.titulo} ${s.texto}').join(' ');
    expect(t, contains('30 días'));
    expect(t, contains('Anthropic'));
  });

  test('el texto del consentimiento de fotos y la política no se contradicen en los 30 días ni en el servidor', () {
    expect(ConsentimientoFotos.texto, contains('30 días'));
    expect(ConsentimientoFotos.texto, contains('no guarda la foto'));
    final t = PoliticaPrivacidad.secciones.map((s) => s.texto).join(' ');
    expect(t, contains('no guarda sus preguntas, sus fotos'));
  });
}
