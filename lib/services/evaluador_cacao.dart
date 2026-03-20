String evaluarCondicionesCacao({
  required double temperatura,
  required int humedad,
  required String condicionClima,
  required String proceso,
}) {
  bool llueve = condicionClima.toLowerCase().contains("rain") || condicionClima.toLowerCase().contains("lluvia");

  if (proceso == "fermentación") {
    bool tempAdecuada = temperatura > 25;
    bool humedadAdecuada = humedad > 80;

    if (tempAdecuada && humedadAdecuada) {
      return '''
✅ El clima es adecuado para la fermentación del cacao.

✔ Temperatura superior a 25 °C
✔ Humedad relativa superior al 80%

🌡 Temperatura: ${temperatura.toStringAsFixed(1)} °C
💧 Humedad: $humedad%
☁️ Clima: $condicionClima
''';
    } else {
      List<String> razones = [];
      if (!tempAdecuada) razones.add('La temperatura no es suficiente (debe ser >25 °C)');
      if (!humedadAdecuada) razones.add('La humedad no es suficiente (debe ser >80%)');

      return '''
⚠️ El clima NO es adecuado para la fermentación del cacao.

${razones.map((r) => '❌ $r').join('\n')}

🌡 Temperatura: ${temperatura.toStringAsFixed(1)} °C
💧 Humedad: $humedad%
☁️ Clima: $condicionClima
''';
    }
  } else if (proceso == "secado") {
    bool tempAdecuada = temperatura > 30;
    bool humedadAdecuada = humedad < 60;
    bool noLluvia = !llueve;

    if (tempAdecuada && humedadAdecuada && noLluvia) {
      return '''
✅ El clima es adecuado para el secado del cacao.

✔ Temperatura superior a 30 °C
✔ Humedad relativa inferior al 60%
✔ No está lloviendo

🌡 Temperatura: ${temperatura.toStringAsFixed(1)} °C
💧 Humedad: $humedad%
☁️ Clima: $condicionClima
''';
    } else {
      List<String> razones = [];
      if (!tempAdecuada) razones.add('La temperatura no es suficiente (debe ser >30 °C)');
      if (!humedadAdecuada) razones.add('La humedad es muy alta (debe ser <60%)');
      if (!noLluvia) razones.add('Está lloviendo');

      return '''
⚠️ El clima NO es adecuado para el secado del cacao.

${razones.map((r) => '❌ $r').join('\n')}

🌡 Temperatura: ${temperatura.toStringAsFixed(1)} °C
💧 Humedad: $humedad%
☁️ Clima: $condicionClima
''';
    }
  } else {
    return "⚠️ Proceso desconocido.";
  }
}
