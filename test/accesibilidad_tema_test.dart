import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alarmacacao5_0/models/analisis_foto.dart';
import 'package:alarmacacao5_0/services/preferencias_app.dart';
import 'package:alarmacacao5_0/tema_app.dart';
import 'package:alarmacacao5_0/widgets/semaforo_foto.dart';

void main() {
  group('contraste WCAG 2.1 (AA: 4,5 para texto; 3 para texto grande y componentes)', () {
    test('la fórmula da los valores conocidos', () {
      expect(TemaApp.contraste(Colors.black, Colors.white), closeTo(21, 0.01));
      expect(TemaApp.contraste(Colors.white, Colors.white), closeTo(1, 0.001));
      expect(TemaApp.contraste(const Color(0xFF777777), Colors.white), closeTo(4.48, 0.02)); // referencia conocida: #777 sobre blanco
    });

    for (final alto in [false, true]) {
      test('el tema ${alto ? 'de alto contraste' : 'normal'}: todo el texto cumple AA contra su fondo', () {
        final c = TemaApp.construir(altoContraste: alto).colorScheme;
        final pares = <String, (Color, Color)>{
          'texto sobre fondo': (c.onSurface, c.surface),
          'texto sobre fondo de tarjetas': (c.onSurface, c.surfaceContainerHighest),
          'texto secundario sobre fondo': (c.onSurfaceVariant, c.surface),
          'botón principal': (c.onPrimary, c.primary),
          'texto de color principal sobre fondo (botones de texto y enlaces)': (c.primary, c.surface),
          'principal contenedor': (c.onPrimaryContainer, c.primaryContainer),
          'secundario contenedor': (c.onSecondaryContainer, c.secondaryContainer),
          'error contenedor': (c.onErrorContainer, c.errorContainer),
          'error': (c.onError, c.error),
        };
        final fallan = <String>[];
        pares.forEach((n, p) {
          final r = TemaApp.contraste(p.$1, p.$2);
          if (r < 4.5) fallan.add('$n: ${r.toStringAsFixed(2)}');
        });
        expect(fallan, isEmpty, reason: 'por debajo de 4,5: $fallan');
      });

      test('el tema ${alto ? 'de alto contraste' : 'normal'}: los bordes de los campos y botones llegan a 3:1', () {
        final c = TemaApp.construir(altoContraste: alto).colorScheme;
        expect(TemaApp.contraste(c.outline, c.surface), greaterThanOrEqualTo(3.0));
      });
    }

    test('el alto contraste mejora el contraste del texto principal', () {
      final n = TemaApp.construir().colorScheme, a = TemaApp.construir(altoContraste: true).colorScheme;
      expect(TemaApp.contraste(a.primary, a.surface), greaterThanOrEqualTo(TemaApp.contraste(n.primary, n.surface)));
    });

    test('los tres semáforos: palabras sobre su fondo cumplen AA', () {
      for (final s in Semaforo.values) {
        final (fondo, texto) = SemaforoFoto.colores(s);
        expect(TemaApp.contraste(texto, fondo), greaterThanOrEqualTo(4.5), reason: s.name);
      }
    });
  });

  group('botones grandes', () {
    testWidgets('los botones del tema miden al menos 48 dp de alto, también con letra normal', (t) async {
      await t.pumpWidget(MaterialApp(
        theme: TemaApp.construir(),
        home: Scaffold(
          body: Column(children: [
            FilledButton(onPressed: () {}, child: const Text('A')),
            ElevatedButton(onPressed: () {}, child: const Text('B')),
            OutlinedButton(onPressed: () {}, child: const Text('C')),
            TextButton(onPressed: () {}, child: const Text('D')),
            IconButton(onPressed: () {}, icon: const Icon(Icons.add), tooltip: 'E'),
          ]),
        ),
      ));
      for (final tipo in [FilledButton, ElevatedButton, OutlinedButton, TextButton, IconButton]) {
        final alto = t.getSize(find.byType(tipo)).height;
        expect(alto, greaterThanOrEqualTo(48), reason: '$tipo mide $alto');
      }
    });
  });

  group('tamaño de letra', () {
    testWidgets('se multiplica por el tamaño del teléfono (no lo reemplaza)', (t) async {
      final p = PreferenciasApp(tamano: TamanoLetra.grande);
      double? escala;
      await t.pumpWidget(MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
        child: MaterialApp(
          builder: (c, h) => TemaApp.conPreferencias(c, h, p),
          home: Builder(builder: (c) {
            escala = MediaQuery.of(c).textScaler.scale(100) / 100;
            return const SizedBox();
          }),
        ),
      ));
      expect(escala, closeTo(1.5 * 1.3, 0.001));
    });

    test('los tres tamaños: 1, 1,3 y 1,6', () {
      expect(TamanoLetra.values.map((t) => t.factor), [1.0, 1.3, 1.6]);
      expect(TamanoLetra.desdeCodigo('basura'), TamanoLetra.normal);
    });
  });

  group('PreferenciasApp', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('valores por defecto: letra normal, contraste normal, sin ahorro', () async {
      final p = await PreferenciasApp.cargar();
      expect((p.tamano, p.altoContraste, p.ahorroBateria), (TamanoLetra.normal, false, false));
    });

    test('se guardan y se leen al volver a abrir; avisan a quien escucha', () async {
      final p = await PreferenciasApp.cargar();
      var avisos = 0;
      p.addListener(() => avisos++);
      await p.cambiarTamano(TamanoLetra.muyGrande);
      await p.cambiarAltoContraste(true);
      await p.cambiarAhorroBateria(true);
      expect(avisos, 3);
      final otra = await PreferenciasApp.cargar();
      expect((otra.tamano, otra.altoContraste, otra.ahorroBateria), (TamanoLetra.muyGrande, true, true));
      expect(await PreferenciasApp.ahorroDeBateriaActivo(), isTrue);
    });

    test('restablecer vuelve a los valores de fábrica', () async {
      final p = await PreferenciasApp.cargar();
      await p.cambiarTamano(TamanoLetra.grande);
      await p.cambiarAltoContraste(true);
      await p.restablecer();
      final otra = await PreferenciasApp.cargar();
      expect((otra.tamano, otra.altoContraste, otra.ahorroBateria), (TamanoLetra.normal, false, false));
    });
  });
}
