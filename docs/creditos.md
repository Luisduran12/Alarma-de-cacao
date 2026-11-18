# Créditos y licencias de datos de terceros

Esta página reúne lo que la app usa de terceros y bajo qué licencia. Cuando haya
una pantalla de créditos en la app (Fase 6B) mostrará lo mismo.

## Clima: Open-Meteo

- Servicio: [Open-Meteo.com](https://open-meteo.com/), API de pronóstico
  (`https://api.open-meteo.com/v1/forecast`), consultada **sin clave**.
- Licencia de los datos: [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).
  La licencia exige dar crédito y poner un enlace junto a los datos: la pantalla de
  clima muestra "Weather data by Open-Meteo.com" con enlace a <https://open-meteo.com/>.
- **Uso gratuito solo no comercial.** Según sus condiciones
  (<https://open-meteo.com/en/terms>): el uso gratuito es para "private or non-profit
  websites or apps that do not have subscriptions or advertising"; las apps con
  suscripciones o publicidad son comerciales. Límites del uso gratuito: menos de
  10.000 llamadas por día, 5.000 por hora y 600 por minuto, por IP y aplicación.
- **Qué NO se verificó:** las condiciones no dicen expresamente si una app gratuita
  para productores entra o no en "no comercial". Si la app llegara a cobrarse o
  llevar publicidad, hay que contratar el plan comercial. Si va a distribuirla una
  entidad, conviene preguntarle a Open-Meteo.
- Privacidad: la app envía la ubicación **redondeada a 2 decimales (≈ 1 km)**, no la
  posición exacta de la finca.
- Los códigos de clima se traducen al español con la tabla WMO de su documentación
  (<https://open-meteo.com/en/docs>).

## Municipios y centros poblados: DANE (DIVIPOLA)

- Archivo: `assets/data/lugares_dane.json` (8.167 lugares), generado con
  `dart tool/generar_lugares.dart`.
- Fuente: Departamento Administrativo Nacional de Estadística (DANE), DIVIPOLA, en
  datos.gov.co, corte 30 de diciembre de 2024:
  - [DIVIPOLA - Códigos municipios](https://www.datos.gov.co/d/gdxc-w37w) (1.122 municipios)
  - [DIVIPOLA - Códigos cabeceras - Centros poblados](https://www.datos.gov.co/d/xaxy-8nri)
    (se usan solo los centros poblados, tipo "CP")
- Licencia: [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/) (atribución
  y compartir igual).
- **Cambios hechos a los datos** (la licencia pide indicarlos): se unieron los dos
  conjuntos; los nombres pasaron de MAYÚSCULAS a mayúscula inicial; los decimales con
  coma pasaron a punto; se quitaron 12 filas repetidas y las cabeceras municipales
  (que ya son los municipios); y se guardó en un formato compacto.
- **Compartir igual:** el archivo derivado se distribuye bajo la misma licencia
  CC BY-SA 4.0. Si esto afecta o no a la licencia del código de la app es una
  pregunta legal que **no se resolvió**.
- **Límite importante:** no existe un conjunto nacional de **veredas** con
  coordenadas (solo algunos municipios publican las suyas, y no se encontró el de
  Chinácota ni el de Durania). Por eso la app dice "Cerca de [centro poblado o
  municipio]" y avisa que es una referencia aproximada, no la vereda.

## Nombre del lugar con internet: OpenStreetMap (Nominatim)

- Lo resolverá el servidor (Fase 4, endpoint `/lugar`), no la app. Aún no existe;
  la app ya tiene la parte del cliente y mientras tanto usa la lista del DANE.
- Los datos de OpenStreetMap son © colaboradores de OpenStreetMap, bajo la licencia
  ODbL (<https://www.openstreetmap.org/copyright>). Cuando un nombre venga del
  servidor, la app muestra el crédito que el servidor envíe.
- Normas de uso de Nominatim que el servidor debe cumplir (a verificar contra su
  política oficial al hacer la Fase 4): máximo una consulta por segundo por
  aplicación, un `User-Agent` que identifique la aplicación, guardar resultados en
  caché y no usarlo para autocompletar. La app ya espera al menos 1,1 s entre
  consultas y agrupa los puntos cercanos (≈ 110 m) para consultarlos una sola vez.
