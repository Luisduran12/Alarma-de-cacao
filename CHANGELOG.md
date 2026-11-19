# Cambios

Formato basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/). La versión 1.0.0 **todavía no está
publicada**: es la que se prepara para la entrega.

## [1.0.0] - en preparación

### Añadido
- **Curva de valores:** rangos de referencia con fuente (FHIA 2017), pH, Brix y temperatura ambiente opcionales,
  resumen simple, curva ideal propia, banda fuera de rango, comparar dos lotes y exportar a PNG y PDF.
- **Alertas:** recordatorios de medir cada 12 h, reglas de alerta editables con fuente, aviso de fin de fermentación,
  guía ilustrada de la prueba de corte y red de seguridad que reprograma alarmas perdidas.
- **Ubicación y clima:** punto de secado por GPS sin internet, clima con Open-Meteo (sin clave), nombre del lugar con la
  lista del DANE sin internet y con el servidor cuando hay señal.
- **Servidor seguro** (`backend/`): `/chat`, `/analizar-foto` y `/lugar` con límites por instalación, IP y día y tope de
  gasto diario. Sin desplegar.
- **Chat:** base de conocimiento con 61 citas literales verificadas, respuestas locales sin internet e historial por lote.
- **Foto con IA:** foto reducida y sin datos ocultos, cola sin señal, consentimiento previo, resultado con semáforo.
- **Accesibilidad:** letra normal, grande y muy grande, alto contraste, objetivos táctiles de 48 dp y pruebas con las guías
  de Flutter.
- **Dictado por voz** opcional en las observaciones, con autorización previa.
- **Copia de seguridad:** exportar e importar un archivo, validado y todo-o-nada.
- **Glosario y guía rápida**, **política de privacidad** y **créditos** dentro de la app.
- **Ajustes:** autorizaciones (ubicación, fotos, voz), ahorro de batería y "Borrar todos mis datos".
- Integración continua en GitHub Actions (aún sin ejecutar allí), README y documentación en `docs/`.

### Corregido
- Borrar un lote ahora también borra los archivos de sus fotos.
- Contraste del texto sobre tarjetas de color en alto contraste.

### Cambiado
- La ubicación ya no se pide al abrir la app: primero se explica y se pide autorización (Ley 1581 de 2012).
- Compatibilidad con Flutter estable (`sqflite_common_ffi`); AGP 8.9.1 y `compileSdk` 36.
- Identificador de la app: `com.luisduran.cacaolight`.

### Eliminado
- Clima con OpenWeatherMap, la pantalla de clima antigua y el evaluador de clima (daba "clima adecuado" con umbrales
  sin fuente).
- Tráfico sin cifrar (`usesCleartextTraffic` desactivado).

### Seguridad
- La clave de OpenWeatherMap del primer commit (`cb55257`) sigue en el historial público y debe revocarse.
- La app no lleva ninguna clave; la de Anthropic vive solo en el servidor.

### Limitaciones conocidas
- No probada en un teléfono Android real ni contra la API real de Anthropic; el servidor no está desplegado.
- Play Integrity no implementado. El acierto del análisis de fotos no está medido.
- Ningún técnico ni productor ha revisado los textos de las guías.
