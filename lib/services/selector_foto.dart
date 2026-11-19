import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

class SelectorFotoException implements Exception {
  final String mensaje;
  const SelectorFotoException(this.mensaje);
}

/// De dónde sale la foto: la cámara o la galería del teléfono. Se separa para poder probar las pantallas.
abstract class SelectorFoto {
  /// Devuelve los bytes de la foto, o null si la persona cancela.
  Future<Uint8List?> tomar({required bool camara});
}

class SelectorFotoReal implements SelectorFoto {
  final ImagePicker _picker;
  SelectorFotoReal([ImagePicker? picker]) : _picker = picker ?? ImagePicker();

  @override
  Future<Uint8List?> tomar({required bool camara}) async {
    try {
      // maxWidth/maxHeight reducen la foto ya en la lectura (una de 12 megapíxeles gasta mucha memoria en un
      // teléfono de gama baja). La reducción final a 1024 px y la limpieza de metadatos las hace PreparadorFoto.
      final x = await _picker.pickImage(
        source: camara ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 90,
      );
      return x == null ? null : await x.readAsBytes();
    } on PlatformException catch (e) {
      final denegado = e.code.contains('denied') || e.code.contains('permission');
      throw SelectorFotoException(denegado
          ? 'La app no tiene permiso para usar ${camara ? 'la cámara' : 'las fotos'}. Actívelo en los ajustes del teléfono.'
          : 'No se pudo abrir ${camara ? 'la cámara' : 'la galería'}.');
    }
  }
}
