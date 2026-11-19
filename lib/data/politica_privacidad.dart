/// Política de privacidad breve (Ley 1581 de 2012). Es la ÚNICA fuente: `docs/privacidad.md` repite estos mismos
/// textos y una prueba comprueba que coincidan. Si cambia lo que la app envía o guarda, cambie aquí y en el documento.
class SeccionPolitica {
  final String titulo;
  final String texto;
  const SeccionPolitica(this.titulo, this.texto);
}

class PoliticaPrivacidad {
  PoliticaPrivacidad._();

  static const titulo = 'Política de privacidad';

  /// Quién responde por los datos y cómo contactarlo. El correo es un marcador que el autor debe reemplazar.
  static const responsable = 'Luis Emir Guerrero Duran, proyecto académico de la UNAD (prototipo).';
  static const contacto = '[CORREO_DEL_PROYECTO]';

  /// Se muestra siempre: la política no ha sido revisada por un abogado.
  static const avisoLegal = 'Esta política no fue revisada por un abogado. Es un prototipo académico.';

  static const secciones = <SeccionPolitica>[
    SeccionPolitica(
      'Qué guarda la app en su teléfono',
      'Sus lotes y registros (temperatura, humedad, pH, Brix, observaciones), las coordenadas si usted toma el '
          'punto de secado, las fotos que usted toma para analizar y el historial del chat. Todo queda solo en su '
          'teléfono. La app no tiene cuentas: no le pide nombre, cédula, correo ni número de teléfono.',
    ),
    SeccionPolitica(
      'Qué sale del teléfono y cuándo',
      '• Clima: al ver el clima, la ubicación (redondeada a unos 1.000 m) va a Open-Meteo.\n'
          '• Nombre del lugar: con internet, la ubicación (redondeada a unos 100 m) va a nuestro servidor, que '
          'consulta OpenStreetMap.\n'
          '• Chat con la IA: su pregunta, la etapa del lote, las horas y hasta los 8 últimos registros (sin el nombre '
          'del lote y sin ubicación) van a nuestro servidor y de ahí a Anthropic.\n'
          '• Foto con la IA: la foto, reducida y sin datos ocultos (ubicación, modelo del teléfono), va a nuestro '
          'servidor y de ahí a Anthropic.\n'
          '• Dictado por voz (opcional): lo escucha el servicio de voz de su teléfono, que según el teléfono puede enviar el '
          'audio por internet a su proveedor. Esta app no guarda el audio, solo el texto que usted deje.\n'
          '• Un código anónimo de la instalación, sin relación con su nombre, para limitar cuántas consultas se hacen por día.\n'
          'Nada de esto se envía si usted no usa esas funciones. Sin internet, la app sigue sirviendo.',
    ),
    SeccionPolitica(
      'Qué guarda nuestro servidor',
      'Nuestro servidor no guarda sus preguntas, sus fotos ni sus resultados. Solo anota códigos y números '
          '(por ejemplo, "consulta correcta" y su costo). El código de la instalación y la dirección de internet '
          'de la conexión se mezclan con un secreto del servidor antes de contar las consultas, así que no quedan '
          'guardados tal cual.',
    ),
    SeccionPolitica(
      'Anthropic puede conservar lo que recibe hasta 30 días',
      'El servicio de inteligencia artificial (Anthropic) puede conservar las preguntas y las fotos que recibe '
          'hasta 30 días. Por eso no escriba datos personales en el chat ni fotografíe personas ni documentos.',
    ),
    SeccionPolitica(
      'Su autorización y sus derechos',
      'La ubicación y las fotos solo se usan si usted lo autoriza, y puede cambiar su respuesta cuando quiera en '
          'Ajustes. Puede conocer, corregir o borrar sus datos: en Ajustes, "Borrar todos mis datos" elimina de su '
          'teléfono los lotes, registros, fotos, chat y preferencias. Si no autoriza, la app sirve igual para las '
          'alarmas y los registros.',
    ),
    SeccionPolitica(
      'Un aviso importante',
      'La app es una guía de apoyo y no reemplaza al técnico agropecuario.',
    ),
  ];
}
