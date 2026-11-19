import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:alarmacacao5_0/services/copia_seguridad.dart';

/// Vigilantes de seguridad de la app: si alguien reintroduce una clave, una URL de servidor, tráfico sin cifrar o
/// una copia automática en la nube, una prueba falla.
void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
  final aplicacion = RegExp(r'<application[^>]*>', dotAll: true).firstMatch(manifest)!.group(0)!;

  List<File> codigo() => Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart') || f.path.endsWith('.json'))
      .toList();

  group('AndroidManifest', () {
    test('sin tráfico sin cifrar', () {
      expect(aplicacion, contains('android:usesCleartextTraffic="false"'));
    });

    test('sin copia automática en la nube ni transferencia entre teléfonos (los datos de los productores no salen)', () {
      expect(aplicacion, contains('android:allowBackup="false"'));
      expect(aplicacion, contains('android:fullBackupContent="false"'));
      expect(aplicacion, contains('android:dataExtractionRules="@xml/data_extraction_rules"'));
      final reglas = File('android/app/src/main/res/xml/data_extraction_rules.xml').readAsStringSync();
      for (final seccion in ['cloud-backup', 'device-transfer']) {
        final bloque = RegExp('<$seccion>(.*?)</$seccion>', dotAll: true).firstMatch(reglas)!.group(1)!;
        for (final dominio in ['root', 'file', 'database', 'sharedpref', 'external']) {
          expect(bloque, contains('<exclude domain="$dominio" />'), reason: '$seccion/$dominio');
        }
        expect(bloque, isNot(contains('<include')));
      }
    });

    test('solo la pantalla principal está exportada; los receptores de alarmas no', () {
      final componentes = RegExp(r'<(activity|service|receiver|provider)\b[^>]*>', dotAll: true)
          .allMatches(manifest)
          .map((m) => m.group(0)!)
          .toList();
      final exportados = componentes.where((c) => c.contains('android:exported="true"')).toList();
      expect(exportados, hasLength(1));
      expect(exportados.single, contains('.MainActivity'));
      for (final c in componentes.where((c) => c.contains('<receiver') || c.contains('<service') || c.contains('<provider'))) {
        expect(c, contains('android:exported="false"'), reason: c);
      }
    });

    test('no pide permisos de almacenamiento amplios ni ubicación en segundo plano', () {
      for (final p in ['READ_EXTERNAL_STORAGE', 'WRITE_EXTERNAL_STORAGE', 'MANAGE_EXTERNAL_STORAGE', 'ACCESS_BACKGROUND_LOCATION']) {
        expect(manifest, isNot(contains(p)), reason: p);
      }
      expect(aplicacion, isNot(contains('requestLegacyExternalStorage')));
    });
  });

  group('código de la app', () {
    test('sin claves ni tokens con forma real', () {
      final patron = RegExp(r'sk-ant-[A-Za-z0-9_-]{20,}|sk-[A-Za-z0-9]{32,}|AIza[0-9A-Za-z_-]{35}|ghp_[A-Za-z0-9]{30,}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY');
      for (final f in codigo()) {
        expect(patron.hasMatch(f.readAsStringSync()), isFalse, reason: f.path);
      }
    });

    test('sin la dirección de un servidor desplegado: BACKEND_URL solo se recibe con --dart-define', () {
      final despliegue = RegExp(r'[a-z0-9-]+\.(vercel\.app|herokuapp\.com|railway\.app|onrender\.com|netlify\.app|workers\.dev|fly\.dev|ngrok)');
      for (final f in codigo()) {
        expect(despliegue.hasMatch(f.readAsStringSync()), isFalse, reason: f.path);
      }
      for (final f in codigo().where((f) => f.path.endsWith('.dart'))) {
        for (final l in f.readAsLinesSync().where((l) => l.contains('fromEnvironment'))) {
          expect(l, contains("String.fromEnvironment('BACKEND_URL')"), reason: '${f.path}: $l');
        }
      }
    });

    test('toda dirección de red es https (el único http:// permitido es el de un espacio de nombres XML o comentario)', () {
      final http = RegExp(r'''["']http://''');
      for (final f in codigo().where((f) => f.path.endsWith('.dart'))) {
        expect(http.hasMatch(f.readAsStringSync()), isFalse, reason: f.path);
      }
    });
  });

  test('la copia de seguridad no incluye fotos ni su análisis (solo datos del lote)', () {
    expect(CopiaSeguridad.tablas, isNot(contains('analisis_fotos')));
    expect(CopiaSeguridad.tablas, containsAll(['lotes', 'registros']));
  });
}
