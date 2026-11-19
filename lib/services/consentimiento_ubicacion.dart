import 'package:shared_preferences/shared_preferences.dart';

/// Permiso del productor para usar la ubicación del teléfono (Ley 1581 de 2012: autorización previa,
/// expresa e informada). Se pide ANTES de que Android muestre su propio cuadro de permiso, y se puede
/// cambiar después en Ajustes. Sin esta autorización la app no pide el permiso de ubicación al sistema.
class ConsentimientoUbicacion {
  static const clave = 'consentimiento_ubicacion_v1';

  /// Debe seguir siendo verdad: si cambia lo que se hace con la ubicación, cambia este texto.
  static const titulo = '¿Usar la ubicación del teléfono?';
  static const texto = 'La app usa el GPS del teléfono solo cuando usted toca un botón (por ejemplo, '
      '"Marcar punto de secado" o "Ver el clima"). No sigue su ubicación todo el tiempo.\n\n'
      '• Las coordenadas se guardan solo en su teléfono, junto al registro del lote.\n'
      '• Para mostrar el clima se envían las coordenadas (redondeadas) al servicio Open-Meteo.\n'
      '• Para escribir el nombre del lugar, cuando hay internet, se envían las coordenadas (redondeadas) a nuestro servidor, '
      'que consulta OpenStreetMap. Sin internet, el nombre sale de una lista que ya viene en la app.\n'
      '• Nunca se envía el nombre del lote ni su nombre.\n\n'
      'Si no acepta, la app sirve igual: alarmas y registros funcionan sin ubicación. Puede cambiarlo cuando quiera en Ajustes.';

  /// true = aceptó, false = rechazó, null = todavía no se le ha preguntado.
  static Future<bool?> obtener() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(clave);
    if (v == null) return null;
    if (v.startsWith('aceptado')) return true;
    if (v.startsWith('rechazado')) return false;
    return null;
  }

  static Future<void> registrar(bool acepta, {DateTime? ahora}) async {
    final prefs = await SharedPreferences.getInstance();
    final fecha = (ahora ?? DateTime.now()).toUtc().toIso8601String();
    await prefs.setString(clave, '${acepta ? 'aceptado' : 'rechazado'}|$fecha');
  }

  /// Vuelve al estado "sin preguntar".
  static Future<void> olvidar() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(clave);
  }
}
