import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'copia_seguridad.dart';

/// Lo que toca el teléfono para el respaldo: compartir el archivo y elegir uno. Se puede cambiar en pruebas.
class ArchivosRespaldo {
  const ArchivosRespaldo();

  /// Guarda el respaldo en la carpeta temporal y abre el menú de compartir (WhatsApp, correo, Drive, guardar...).
  Future<void> compartir(String nombre, String contenido) async {
    final dir = await getTemporaryDirectory();
    final f = File(p.join(dir.path, nombre));
    await f.writeAsString(contenido);
    await SharePlus.instance.share(ShareParams(files: [XFile(f.path)], text: 'Copia de seguridad de Cacao Light'));
  }

  /// Deja elegir un archivo y devuelve su texto; null si cancela. Lanza [RespaldoInvalido] si pesa demasiado.
  Future<String?> elegir() async {
    final r = await FilePicker.pickFiles(type: FileType.any);
    final ruta = r?.files.single.path;
    if (ruta == null) return null;
    final archivo = File(ruta);
    if (await archivo.length() > CopiaSeguridad.maxBytes) {
      throw const RespaldoInvalido('El archivo es demasiado grande para ser un respaldo.');
    }
    return archivo.readAsString();
  }
}
