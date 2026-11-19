import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alarmacacao5_0/screens/politica_screen.dart';

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

  testWidgets('la pantalla muestra el responsable, el contacto y que no la revisó un abogado', (t) async {
    t.view.physicalSize = const Size(400, 6000);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(const MaterialApp(home: PoliticaScreen()));
    expect(find.textContaining('Luis Emir Guerrero Duran'), findsOneWidget);
    expect(find.textContaining('Contacto: '), findsOneWidget);
    expect(find.textContaining('no fue revisada por un abogado'), findsOneWidget);
  });
}
