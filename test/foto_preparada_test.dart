import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:alarmacacao5_0/services/foto_preparada.dart';

/// Los segmentos APPn/COM que trae un JPEG: marcador y primeros bytes de su contenido.
List<(int, String)> _segmentos(Uint8List b) {
  final r = <(int, String)>[];
  var i = 2;
  while (i + 4 <= b.length && b[i] == 0xff) {
    final m = b[i + 1];
    if (m == 0xda || m == 0xd9) break;
    final len = (b[i + 2] << 8) | b[i + 3];
    if ((m >= 0xe0 && m <= 0xef) || m == 0xfe) {
      r.add((m, String.fromCharCodes(b.sublist(i + 4, (i + 4 + 8).clamp(0, b.length)).where((c) => c >= 32 && c < 127))));
    }
    i += 2 + len;
  }
  return r;
}

Uint8List _jpegConMetadatos({int ancho = 2000, int alto = 1500, int? orientacion}) {
  final im = img.Image(width: ancho, height: alto);
  img.fill(im, color: img.ColorRgb8(120, 70, 40));
  img.fillRect(im, x1: 0, y1: 0, x2: ancho ~/ 4, y2: alto ~/ 4, color: img.ColorRgb8(10, 200, 10)); // marca arriba a la izquierda
  im.exif.imageIfd.make = 'TELEFONO-DE-PRUEBA';
  im.exif.imageIfd.model = 'MODELO-X';
  im.exif.gpsIfd.setGpsLocation(latitude: 7.603, longitude: -72.601);
  if (orientacion != null) im.exif.imageIfd.orientation = orientacion;
  return Uint8List.fromList(img.encodeJpg(im, quality: 90));
}

void main() {
  group('PreparadorFoto', () {
    test('la foto de prueba sí trae EXIF con GPS (si no, las demás pruebas no probarían nada)', () {
      final original = _jpegConMetadatos();
      expect(_segmentos(original).any((s) => s.$1 == 0xe1 && s.$2.contains('Exif')), isTrue);
      final leida = img.decodeJpg(original)!;
      expect(leida.exif.gpsIfd.gpsLatitude, isNotNull);
      expect(leida.exif.imageIfd.make, 'TELEFONO-DE-PRUEBA');
    });

    test('reduce a 1024 px por el lado largo y mantiene la proporción', () {
      final f = PreparadorFoto.prepararSincrono(_jpegConMetadatos(ancho: 2000, alto: 1500));
      expect(f.ancho, 1024);
      expect(f.alto, 768);
      final d = img.decodeJpg(f.bytes)!;
      expect((d.width, d.height), (1024, 768));
    });

    test('una foto vertical se reduce por el alto', () {
      final f = PreparadorFoto.prepararSincrono(_jpegConMetadatos(ancho: 1500, alto: 3000));
      expect((f.ancho, f.alto), (512, 1024));
    });

    test('una foto que ya cabe no se agranda ni se reduce', () {
      final f = PreparadorFoto.prepararSincrono(_jpegConMetadatos(ancho: 800, alto: 600));
      expect((f.ancho, f.alto), (800, 600));
    });

    test('la salida NO trae ningún segmento de metadatos: ni EXIF, ni GPS, ni marca del teléfono, ni perfil de color', () {
      final f = PreparadorFoto.prepararSincrono(_jpegConMetadatos());
      final extra = _segmentos(f.bytes).where((s) => s.$1 != 0xe0).toList(); // APP0 (JFIF) es solo el encabezado
      expect(extra, isEmpty, reason: 'segmentos inesperados: $extra');
      final texto = String.fromCharCodes(f.bytes);
      expect(texto, isNot(contains('Exif')));
      expect(texto, isNot(contains('TELEFONO-DE-PRUEBA')));
      expect(texto, isNot(contains('MODELO-X')));
      final d = img.decodeJpg(f.bytes)!;
      expect(d.exif.isEmpty, isTrue);
      expect(d.exif.gpsIfd.gpsLatitude, isNull);
    });

    test('también limpia una foto pequeña que no hace falta reducir', () {
      final f = PreparadorFoto.prepararSincrono(_jpegConMetadatos(ancho: 640, alto: 480));
      expect(_segmentos(f.bytes).where((s) => s.$1 != 0xe0), isEmpty);
    });

    test('aplica la rotación del EXIF a los píxeles antes de borrarlo (no queda de lado)', () {
      // Orientación 6: la imagen guardada es 400×200 pero se debe ver 200×400 (girada 90°).
      final f = PreparadorFoto.prepararSincrono(_jpegConMetadatos(ancho: 400, alto: 200, orientacion: 6));
      expect((f.ancho, f.alto), (200, 400));
    });

    test('lo que no es una imagen se rechaza con un mensaje claro', () {
      for (final basura in [Uint8List(0), Uint8List.fromList([1, 2, 3, 4, 5]), Uint8List.fromList('hola mundo'.codeUnits)]) {
        expect(() => PreparadorFoto.prepararSincrono(basura), throwsA(isA<FotoInvalidaException>()));
      }
    });

    test('una foto de menos de 200 px por los dos lados se rechaza (el servidor tampoco la acepta)', () {
      expect(() => PreparadorFoto.prepararSincrono(_jpegConMetadatos(ancho: 150, alto: 100)),
          throwsA(isA<FotoInvalidaException>().having((e) => e.mensaje, 'mensaje', contains('muy pequeña'))));
    });

    test('un PNG también se convierte a JPEG limpio', () {
      final im = img.Image(width: 1200, height: 900);
      img.fill(im, color: img.ColorRgb8(1, 2, 3));
      final f = PreparadorFoto.prepararSincrono(Uint8List.fromList(img.encodePng(im)));
      expect(f.bytes.sublist(0, 2), [0xff, 0xd8]);
      expect(f.ancho, 1024);
    });

    test('preparar() hace lo mismo en otro hilo', () async {
      final f = await PreparadorFoto.preparar(_jpegConMetadatos());
      expect((f.ancho, f.alto), (1024, 768));
      expect(_segmentos(f.bytes).where((s) => s.$1 != 0xe0), isEmpty);
    });
  });
}
