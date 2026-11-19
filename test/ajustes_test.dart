import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:alarmacacao5_0/app_info.dart';
import 'package:alarmacacao5_0/data/base_conocimiento.dart';
import 'package:alarmacacao5_0/data/cacao_database.dart';
import 'package:alarmacacao5_0/data/creditos.dart';
import 'package:alarmacacao5_0/screens/ajustes_screen.dart';
import 'package:alarmacacao5_0/screens/ayuda_screen.dart';
import 'package:alarmacacao5_0/screens/creditos_screen.dart';
import 'package:alarmacacao5_0/screens/politica_screen.dart';
import 'package:alarmacacao5_0/services/archivos_respaldo.dart';
import 'package:alarmacacao5_0/services/borrar_datos.dart';
import 'package:alarmacacao5_0/services/consentimiento_ubicacion.dart';
import 'package:alarmacacao5_0/services/copia_seguridad.dart';
import 'package:alarmacacao5_0/services/preferencias_app.dart';

class _ArchivosFalsos extends ArchivosRespaldo {
  String? elegido;
  Object? errorAlElegir;
  String? compartidoNombre, compartidoContenido;
  @override
  Future<void> compartir(String nombre, String contenido) async {
    compartidoNombre = nombre;
    compartidoContenido = contenido;
  }

  @override
  Future<String?> elegir() async {
    if (errorAlElegir != null) throw errorAlElegir!;
    return elegido;
  }
}

void main() {
  sqfliteFfiInit();
  late Database db;
  late PreferenciasApp prefs;
  late _ArchivosFalsos archivos;
  late CopiaSeguridad copia;
  var cancelaciones = 0;

  Widget app(Widget home, {double escala = 1.0}) => MaterialApp(
        builder: (c, h) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(escala)), child: h!),
        home: home,
      );

  Widget ajustes({double escala = 1.0}) => app(
        AjustesScreen(
          preferencias: prefs,
          copia: copia,
          archivos: archivos,
          borrar: BorrarDatos(
            baseDeDatos: () async => db,
            cancelarAlarmas: () async => cancelaciones++,
            carpetas: () async => [],
            archivos: () async => [],
          ),
          trasBorrar: (_) => const Scaffold(body: Text('INICIO NUEVO')),
        ),
        escala: escala,
      );

  void pantallaPequena(WidgetTester t) {
    t.view.physicalSize = const Size(360, 640);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = PreferenciasApp();
    PreferenciasApp.instancia = prefs;
    archivos = _ArchivosFalsos();
    cancelaciones = 0;
    db = await CacaoDatabase.abrir(databaseFactoryFfi, inMemoryDatabasePath);
    copia = CopiaSeguridad(baseDeDatos: () async => db, cancelarAlarmas: () async {}, reprogramar: () async {}, ahora: () => DateTime(2026, 11, 18));
  });
  tearDown(() => db.close());

  Future<void> esperar(WidgetTester t) async {
    for (var i = 0; i < 4; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await t.pump(const Duration(milliseconds: 100));
    }
    await t.pumpAndSettle();
  }

  Future<T> real<T>(WidgetTester t, Future<T> Function() f) async => (await t.runAsync(f)) as T;

  Future<void> bajarHasta(WidgetTester t, String texto) async {
    await t.scrollUntilVisible(find.text(texto), 200, scrollable: find.byType(Scrollable).first);
    await t.pumpAndSettle();
  }

  group('Ajustes', () {
    testWidgets('cambiar el tamaño de la letra y el contraste actualiza y guarda las preferencias', (t) async {
      pantallaPequena(t);
      await t.pumpWidget(ajustes());
      await esperar(t);
      await t.tap(find.text('Grande'));
      await esperar(t);
      expect(prefs.tamano, TamanoLetra.grande);
      await t.tap(find.text('Alto contraste'));
      await esperar(t);
      expect(prefs.altoContraste, isTrue);
      expect((await SharedPreferences.getInstance()).getBool('pref_alto_contraste'), isTrue);
    });

    testWidgets('las autorizaciones se pueden dar y quitar, y quedan registradas', (t) async {
      pantallaPequena(t);
      await t.pumpWidget(ajustes());
      await esperar(t);
      expect(await real(t, ConsentimientoUbicacion.obtener), isNull);
      await bajarHasta(t, 'Usar mi ubicación');
      await t.tap(find.text('Usar mi ubicación'));
      await esperar(t);
      expect(await real(t, ConsentimientoUbicacion.obtener), isTrue);
      await t.tap(find.text('Usar mi ubicación'));
      await esperar(t);
      expect(await real(t, ConsentimientoUbicacion.obtener), isFalse);
    });

    testWidgets('guardar copia: comparte un archivo con el nombre con fecha y el formato correcto', (t) async {
      pantallaPequena(t);
      await real(t, () => db.insert('lotes', {'id': 'A', 'titulo': 'Lote A', 'estado': 'en proceso', 'creado_en': '2026-11-01T00:00:00'}));
      await t.pumpWidget(ajustes());
      await esperar(t);
      await bajarHasta(t, 'Guardar copia de seguridad');
      await t.tap(find.text('Guardar copia de seguridad'));
      await esperar(t);
      expect(archivos.compartidoNombre, 'cacao_light_respaldo_2026-11-18.json');
      expect((jsonDecode(archivos.compartidoContenido!) as Map)['formato'], CopiaSeguridad.formato);
    });

    testWidgets('recuperar copia: muestra qué trae, pide confirmación y reemplaza', (t) async {
      pantallaPequena(t);
      await real(t, () => db.insert('lotes', {'id': 'A', 'titulo': 'Lote A', 'estado': 'en proceso', 'creado_en': '2026-11-01T00:00:00'}));
      archivos.elegido = await real(t, copia.exportar);
      await real(t, () => db.delete('lotes'));
      await real(t, () => db.insert('lotes', {'id': 'OTRO', 'titulo': 'Otro', 'estado': 'x', 'creado_en': '2026-11-02T00:00:00'}));

      await t.pumpWidget(ajustes());
      await esperar(t);
      await bajarHasta(t, 'Recuperar copia de seguridad');
      await t.tap(find.text('Recuperar copia de seguridad'));
      await esperar(t);
      expect(find.textContaining('1 lotes'), findsOneWidget);
      expect(find.textContaining('REEMPLAZARÁ'), findsOneWidget);
      expect((await real(t, () => db.query('lotes'))).single['id'], 'OTRO', reason: 'todavía no se cambió nada');

      await t.tap(find.text('Sí, recuperar'));
      await esperar(t);
      expect((await real(t, () => db.query('lotes'))).single['id'], 'A');
    });

    testWidgets('recuperar copia: si cancela la confirmación no cambia nada', (t) async {
      pantallaPequena(t);
      await real(t, () => db.insert('lotes', {'id': 'A', 'titulo': 'Lote A', 'estado': 'x', 'creado_en': '2026-11-01T00:00:00'}));
      archivos.elegido = await real(t, copia.exportar);
      await real(t, () => db.delete('lotes'));
      await t.pumpWidget(ajustes());
      await esperar(t);
      await bajarHasta(t, 'Recuperar copia de seguridad');
      await t.tap(find.text('Recuperar copia de seguridad'));
      await esperar(t);
      await t.tap(find.text('Cancelar'));
      await esperar(t);
      expect(await real(t, () => db.query('lotes')), isEmpty);
    });

    testWidgets('recuperar un archivo que no es un respaldo: lo dice y no cambia nada', (t) async {
      pantallaPequena(t);
      await real(t, () => db.insert('lotes', {'id': 'A', 'titulo': 'Lote A', 'estado': 'x', 'creado_en': '2026-11-01T00:00:00'}));
      archivos.elegido = 'esto es una foto, no un respaldo';
      await t.pumpWidget(ajustes());
      await esperar(t);
      await bajarHasta(t, 'Recuperar copia de seguridad');
      await t.tap(find.text('Recuperar copia de seguridad'));
      await esperar(t);
      expect(find.textContaining('No se cambió nada'), findsOneWidget);
      expect(await real(t, () => db.query('lotes')), hasLength(1));
    });

    testWidgets('borrar todos los datos: pide confirmación, borra y vuelve al inicio', (t) async {
      pantallaPequena(t);
      await real(t, () => db.insert('lotes', {'id': 'A', 'titulo': 'Lote A', 'estado': 'x', 'creado_en': '2026-11-01T00:00:00'}));
      await t.pumpWidget(ajustes());
      await esperar(t);
      await bajarHasta(t, 'Borrar todos mis datos');
      await t.tap(find.text('Borrar todos mis datos'));
      await esperar(t);
      expect(find.textContaining('30 días'), findsOneWidget, reason: 'avisa lo que NO se puede borrar');
      expect(await real(t, () => db.query('lotes')), hasLength(1), reason: 'sin confirmar no se borra');

      await t.tap(find.text('Sí, borrar todo'));
      await esperar(t);
      expect(await real(t, () => db.query('lotes')), isEmpty);
      expect(cancelaciones, 1);
      expect(find.text('INICIO NUEVO'), findsOneWidget);
    });

    testWidgets('borrar: si dice Cancelar no se borra nada', (t) async {
      pantallaPequena(t);
      await real(t, () => db.insert('lotes', {'id': 'A', 'titulo': 'Lote A', 'estado': 'x', 'creado_en': '2026-11-01T00:00:00'}));
      await t.pumpWidget(ajustes());
      await esperar(t);
      await bajarHasta(t, 'Borrar todos mis datos');
      await t.tap(find.text('Borrar todos mis datos'));
      await esperar(t);
      await t.tap(find.text('Cancelar'));
      await esperar(t);
      expect(await real(t, () => db.query('lotes')), hasLength(1));
      expect(cancelaciones, 0);
    });
  });

  group('Créditos', () {
    test('mencionan todo lo que pide la entrega: Open-Meteo, DANE, FHIA, La Salle, ICA, Zenodo y las licencias CC BY', () {
      final t = Creditos.items.map((c) => '${c.titulo} ${c.texto}').join(' ');
      for (final k in ['Open-Meteo', 'DANE', 'FHIA', 'La Salle', 'ICA', 'Zenodo', 'CC BY 4.0', 'CC BY-SA 4.0', 'OpenStreetMap', 'Oliveira', 'Alvarado Molina']) {
        expect(t, contains(k), reason: k);
      }
    });

    test('cada fuente de la base de conocimiento está en los créditos', () async {
      final j = jsonDecode(File('assets/conocimiento/base.json').readAsStringSync()) as Map;
      final creditos = Creditos.items.map((c) => c.texto).join(' ');
      for (final f in (j['fuentes'] as Map).values) {
        final titulo = (f as Map)['titulo'] as String;
        expect(creditos, contains(titulo.split(RegExp(r'[:(]')).first.trim()), reason: titulo);
      }
    });

    test('docs/creditos.md sigue mencionando lo mismo (las licencias y los DOI)', () {
      final md = File('docs/creditos.md').readAsStringSync();
      for (final c in Creditos.items.where((c) => c.enlace != null && c.enlace!.contains('doi.org'))) {
        expect(md, contains(c.enlace!));
      }
      for (final k in ['CC BY 4.0', 'CC BY-SA 4.0', 'ODbL']) {
        expect(md, contains(k));
      }
    });

    testWidgets('la pantalla muestra los créditos y abre un enlace (o dice la dirección si no puede)', (t) async {
      pantallaPequena(t);
      Uri? abierto;
      await t.pumpWidget(app(CreditosScreen(abrirEnlace: (u) async => abierto = u)));
      expect(find.text('Clima: Open-Meteo'), findsOneWidget);
      await t.tap(find.byIcon(Icons.open_in_new).first);
      expect(abierto.toString(), 'https://open-meteo.com/');

      await t.pumpWidget(app(CreditosScreen(abrirEnlace: (u) async => throw StateError('x'))));
      await t.tap(find.byIcon(Icons.open_in_new).first);
      await t.pump();
      expect(find.textContaining('Dirección: https://open-meteo.com/'), findsOneWidget);
    });
  });

  group('Ayuda (glosario y guía rápida)', () {
    testWidgets('el glosario muestra cada término de la base con su fuente, y la guía el aviso del técnico', (t) async {
      t.view.physicalSize = const Size(360, 4000); // alta, para que la lista perezosa dibuje todo
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      final base = await BaseConocimiento.desdeJson(File('assets/conocimiento/base.json').readAsStringSync());
      await t.pumpWidget(app(AyudaScreen(cargar: () async => base)));
      await t.pumpAndSettle();
      expect(find.text('Es una guía, no reemplaza al técnico.'), findsOneWidget);
      expect(find.text('Fermentación'), findsOneWidget, reason: 'tema de la guía');
      await t.tap(find.text('Glosario'));
      await t.pumpAndSettle();
      expect(find.text('Masa de cacao'), findsOneWidget);
      expect(find.textContaining('Fuente: U. de La Salle'), findsWidgets);
    });

    test('todos los temas de la base tienen nombre para mostrar', () {
      final j = jsonDecode(File('assets/conocimiento/base.json').readAsStringSync()) as Map;
      for (final tema in j['temas'] as List) {
        expect(nombresTemas, contains(tema));
      }
    });

    testWidgets('si la base no carga: mensaje claro, sin romperse', (t) async {
      await t.pumpWidget(app(AyudaScreen(cargar: () async => throw StateError('x'))));
      await t.pumpAndSettle();
      expect(find.textContaining('No se pudo abrir la guía'), findsOneWidget);
    });
  });

  test('la versión mostrada coincide con pubspec.yaml', () {
    final m = RegExp(r'^version:\s*(\S+)\+', multiLine: true).firstMatch(File('pubspec.yaml').readAsStringSync());
    expect(m!.group(1), AppInfo.version);
  });

  group('letra al 200 % en un teléfono pequeño (360×640): ninguna pantalla desborda', () {
    final base = BaseConocimiento.desdeJson(File('assets/conocimiento/base.json').readAsStringSync());
    final pantallas = <String, Widget Function()>{
      'Ajustes': () => AjustesScreen(preferencias: PreferenciasApp(), copia: copia, archivos: archivos),
      'Política': () => const PoliticaScreen(),
      'Créditos': () => const CreditosScreen(),
      'Ayuda': () => AyudaScreen(cargar: () async => base),
    };
    pantallas.forEach((nombre, crear) {
      testWidgets(nombre, (t) async {
        pantallaPequena(t);
        await t.pumpWidget(app(crear(), escala: 2.0));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      });
    });
  });
}
