import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

class FotoInvalidaException implements Exception {
  final String mensaje;
  const FotoInvalidaException(this.mensaje);
  @override
  String toString() => 'FotoInvalidaException($mensaje)';
}

/// La foto lista para guardar y enviar: JPEG de máximo [PreparadorFoto.ladoMaximo] px por el lado
/// largo y SIN metadatos (ni EXIF con la ubicación GPS, ni marca y modelo del teléfono, ni perfil de color).
class FotoPreparada {
  final Uint8List bytes;
  final int ancho;
  final int alto;
  const FotoPreparada(this.bytes, this.ancho, this.alto);
}

class PreparadorFoto {
  static const ladoMaximo = 1024;

  /// El servidor rechaza fotos de menos de 200 px por el lado largo.
  static const ladoMinimo = 200;
  static const calidadJpeg = 85;

  /// Reduce y limpia la foto en otro hilo (decodificar una foto de 12 megapíxeles bloquearía la pantalla
  /// en un teléfono de gama baja). Lanza [FotoInvalidaException] si no es una imagen legible o es muy pequeña.
  static Future<FotoPreparada> preparar(Uint8List original) => compute(prepararSincrono, original);

  @visibleForTesting
  static FotoPreparada prepararSincrono(Uint8List original) {
    img.Image? imagen;
    try {
      imagen = img.decodeImage(original);
    } catch (_) {
      imagen = null;
    }
    if (imagen == null) throw const FotoInvalidaException('No se pudo leer la foto.');

    // Aplica la rotación que decía el EXIF a los píxeles (si no, al borrar el EXIF la foto saldría de lado).
    imagen = img.bakeOrientation(imagen);

    if (imagen.width < ladoMinimo && imagen.height < ladoMinimo) {
      throw const FotoInvalidaException('La foto es muy pequeña. Tome otra más cerca.');
    }
    if (imagen.width > ladoMaximo || imagen.height > ladoMaximo) {
      imagen = imagen.width >= imagen.height
          ? img.copyResize(imagen, width: ladoMaximo, interpolation: img.Interpolation.average)
          : img.copyResize(imagen, height: ladoMaximo, interpolation: img.Interpolation.average);
    }

    // El codificador escribe el EXIF y el perfil ICC si existen: se borran a propósito.
    imagen.exif = img.ExifData();
    imagen.iccProfile = null;

    final bytes = Uint8List.fromList(img.encodeJpg(imagen, quality: calidadJpeg));
    return FotoPreparada(bytes, imagen.width, imagen.height);
  }
}
