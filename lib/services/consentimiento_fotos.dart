import 'package:shared_preferences/shared_preferences.dart';

/// Permiso del productor para enviar fotos a analizar. Se pide una vez, antes de la primera foto, y se
/// puede cambiar después. Sin permiso la app no envía ninguna foto (la guía y el resto siguen funcionando).
/// La política de privacidad completa y el consentimiento formal (Ley 1581) llegan en la Fase 7.
class ConsentimientoFotos {
  static const clave = 'consentimiento_fotos_v1';

  /// Lo que se le explica al productor. Debe seguir siendo verdad: si cambia cómo viaja la foto, cambia esto.
  static const titulo = '¿Enviar la foto para analizarla?';
  static const texto = 'Para analizar la foto, la app la envía por internet a un servidor y de ahí a un servicio de '
      'inteligencia artificial (Anthropic).\n\n'
      '• Antes de enviarla se reduce y se le borran los datos ocultos (la ubicación y el modelo del teléfono).\n'
      '• Nuestro servidor no guarda la foto ni su resultado. El resultado se guarda solo en su teléfono.\n'
      '• El servicio de inteligencia artificial puede conservar lo que recibe hasta 30 días.\n'
      '• No fotografíe personas ni documentos.\n\n'
      'Si no acepta, la app no envía fotos. Puede cambiarlo cuando quiera.';

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

  /// Vuelve al estado "sin preguntar" (se le pregunta de nuevo la próxima vez).
  static Future<void> olvidar() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(clave);
  }
}
