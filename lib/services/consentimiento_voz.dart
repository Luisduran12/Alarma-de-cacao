import 'package:shared_preferences/shared_preferences.dart';

/// Autorización del productor para dictar por voz. El dictado es opcional: el teclado siempre sirve.
class ConsentimientoVoz {
  static const clave = 'consentimiento_voz_v1';

  static const titulo = '¿Escribir con la voz?';
  static const texto = 'Usted habla y el teléfono escribe lo que dice en la observación.\n\n'
      '• Lo escucha el servicio de voz que trae su teléfono, no esta app. Según el teléfono, ese servicio puede enviar '
      'el audio por internet a su proveedor.\n'
      '• Esta app no guarda el audio: solo guarda el texto que usted deje en la observación.\n'
      '• Android le pedirá permiso para usar el micrófono.\n\n'
      'Si no acepta, escriba con el teclado como siempre. Puede cambiarlo en Ajustes.';

  static Future<bool?> obtener() async {
    final v = (await SharedPreferences.getInstance()).getString(clave);
    if (v == null) return null;
    if (v.startsWith('aceptado')) return true;
    if (v.startsWith('rechazado')) return false;
    return null;
  }

  static Future<void> registrar(bool acepta, {DateTime? ahora}) async {
    final fecha = (ahora ?? DateTime.now()).toUtc().toIso8601String();
    await (await SharedPreferences.getInstance()).setString(clave, '${acepta ? 'aceptado' : 'rechazado'}|$fecha');
  }

  static Future<void> olvidar() async => (await SharedPreferences.getInstance()).remove(clave);
}
