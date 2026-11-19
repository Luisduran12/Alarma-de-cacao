import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Los documentos de la Fase 8 (validación con productores) son PLANTILLAS: tienen que existir, tener el formato pedido
/// y estar vacíos de resultados (no se inventan datos).
void main() {
  String leer(String r) => File(r).readAsStringSync();

  test('la encuesta tiene exactamente 8 preguntas con 5 caritas', () {
    final t = leer('docs/validacion/encuesta-usabilidad.md');
    final preguntas = RegExp(r'^\| ([1-9]) \| ', multiLine: true).allMatches(t).map((m) => m.group(1)).toList();
    expect(preguntas, ['1', '2', '3', '4', '5', '6', '7', '8']);
    for (final c in ['😞', '😕', '😐', '🙂', '😀']) {
      expect(t, contains(c));
    }
  });

  test('el guion es de 10 minutos y tiene sus 9 tareas', () {
    final t = leer('docs/validacion/guion-observacion.md');
    expect(t, contains('10 minutos'));
    expect(RegExp(r'^\| \d+–\d+ \|', multiLine: true).allMatches(t), hasLength(9));
  });

  test('la plantilla de resultados está vacía: el CSV solo tiene el encabezado y las tablas no traen datos', () {
    final csv = leer('docs/validacion/plantilla-resultados.csv').trim().split('\n');
    expect(csv, hasLength(1));
    expect(csv.single, startsWith('codigo,fecha,'));
    final md = leer('docs/validacion/plantilla-resultados.md');
    expect(md, contains('Todo está vacío a propósito'));
    // Una fila de participante vacía: solo el código y celdas en blanco.
    expect(md, contains('| P1 | | | | | |'));
    expect(md, contains('| 1 | Fácil empezar un lote | | | | | | |'));
  });

  test('el consentimiento nombra al responsable y no pide cédula ni teléfono', () {
    final t = leer('docs/validacion/consentimiento.md');
    expect(t, contains('Luis Emir Guerrero Duran'));
    expect(t, contains('No se anota su cédula ni su teléfono'));
  });

  test('evaluacion/colombia: plantilla del manifiesto con los campos del formato y sin fotos ni manifiesto real', () {
    final t = leer('evaluacion/colombia/manifest.plantilla.json');
    for (final c in ['archivo', 'modo', 'etiqueta', 'tecnico', 'fecha', 'lugar']) {
      expect(t, contains('"$c"'));
    }
    expect(File('evaluacion/colombia/manifest.json').existsSync(), isFalse);
    final fotos = Directory('evaluacion/colombia').listSync().where((e) => e.path.endsWith('.jpg') || e.path.endsWith('.png'));
    expect(fotos, isEmpty);
  });
}
