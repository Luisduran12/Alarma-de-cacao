import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// ID de instalación anónimo: un UUID v4 que se genera una sola vez y se guarda en el
/// teléfono. No tiene nada del productor (ni nombre, ni teléfono, ni ubicación). Se manda
/// al servidor en la cabecera `X-Install-Id` solo para contar cuántas consultas hace esta
/// instalación por día (límite de uso). Si se borran los datos de la app, se crea uno nuevo.
class InstalacionId {
  static const clave = 'instalacion_id_v1';

  static final _uuidV4 =
      RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$', caseSensitive: false);

  static bool esValido(String? id) => id != null && _uuidV4.hasMatch(id);

  /// Devuelve el ID de esta instalación; lo crea la primera vez (o si el guardado no es válido).
  static Future<String> obtener() async {
    final prefs = await SharedPreferences.getInstance();
    final guardado = prefs.getString(clave);
    if (esValido(guardado)) return guardado!;
    final nuevo = const Uuid().v4();
    await prefs.setString(clave, nuevo);
    return nuevo;
  }
}
