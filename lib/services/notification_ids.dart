import 'package:shared_preferences/shared_preferences.dart';

/// Genera IDs de notificación estables y únicos.
///
/// Antes se usaba `uuid.hashCode`, que puede cambiar entre ejecuciones y
/// colisionar, por lo que no servía para cancelar una alarma después.
/// Ahora se usa un contador persistente y el ID se guarda en la volteada.
class NotificationIds {
  static const _key = 'ultimo_notification_id';

  /// Devuelve el siguiente ID (1, 2, 3, ...), siempre dentro del rango de int32.
  static Future<int> siguiente() async {
    final prefs = await SharedPreferences.getInstance();
    var id = (prefs.getInt(_key) ?? 0) + 1;
    if (id > 0x7FFFFFFF) id = 1;
    await prefs.setInt(_key, id);
    return id;
  }
}
