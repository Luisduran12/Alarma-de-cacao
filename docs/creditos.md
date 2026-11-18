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

## Fotos de referencia y de prueba para el análisis de fotos

Las fotos NO son de esta app. Están en `backend/referencias/` (ejemplos que el servidor puede
mandar a la IA) y en `evaluacion/galeria/` (solo para medir el acierto). Cada foto tiene en su
`manifest.json` la fuente, los autores, el DOI y la licencia. Se separaron con
`tool/importar_galeria.py` a partir de una galería armada a mano de conjuntos públicos.

### Granos cortados (prueba de corte)
- Datos: Oliveira, M. M.; Cerqueira, B. V.; Barbon Jr., S.; Barbin, D. F. *Images of fermented
  cocoa beans from cut-test experiments for computer vision classification* [Conjunto de datos].
  Zenodo. <https://doi.org/10.5281/zenodo.22824982>
- Artículo: Oliveira et al. (2021), *Classification of fermented cocoa beans (cut test) using
  computer vision*, Journal of Food Composition and Analysis, 97, 103771.
  <https://doi.org/10.1016/j.jfca.2020.103771>
- Licencia: CC BY 4.0 **según los metadatos de Zenodo**. El README del depósito dice que los
  dueños deben confirmar la licencia final. **Pendiente: escribir a los autores y guardar su
  respuesta antes de publicar la app o subir el repositorio.**
- Son fotos de Brasil, en laboratorio y con tarjeta de color. No son la NTC 1252 ni fotos de
  un celular en finca: el acierto medido con ellas NO es el acierto en Colombia.
- Cambios: recorte alrededor del grano, reducción a 640 px y sin metadatos.
- Clases de la fuente: bien fermentado, parcialmente fermentado, violeta y "pizarroso y/o con
  moho" (la fuente junta pizarroso y moho en una sola clase).

### Mazorcas con moniliasis (Colombia)
- Datos: Alvarado Molina, J. F.; Restrepo-Arias, J. F.; Velásquez, D.; Branch Bedoya, J. W.;
  Maiza, M. *CocoaMoniliaDataSet* [Conjunto de datos]. Zenodo (2025).
  <https://doi.org/10.5281/zenodo.17716661>
- Artículo: Data in Brief, 64, 112447 (2026). <https://doi.org/10.1016/j.dib.2025.112447>
- Licencia: CC BY 4.0. Fotos con celular en fincas de Santander y Antioquia (no de Norte de Santander).
- Etiquetas según la guía de la Compañía Nacional de Chocolates sobre moniliasis (ciclos 1 a 4)
  y mazorca sana. Una foto puede mostrar varias mazorcas y la etiqueta puede referirse a una.
- Cambios: reducción a 768 px y sin metadatos.

### Qué se comprobó el 2026-11-18 (API de Zenodo, solo lectura)
- Los dos registros declaran licencia `cc-by-4.0` y acceso abierto. Los DOI, títulos y autores
  coinciden con el manifiesto. El depósito de granos cortados tiene fecha 2026-09-18 y el de
  mazorcas 2025-11-25.
- **Las etiquetas del conjunto de granos cortados fueron "inferidas de los prefijos de los
  nombres de archivo originales"** (así lo dice su descripción): no hay una revisión
  individual declarada. Tiene solo 206 imágenes en 2 lotes. Por eso un técnico debe revisar las
  fotos de referencia, y la evaluación con estas fotos no es una medición contra una
  clasificación experta.
- Esto no resuelve la confirmación de licencia final con los autores que pide el README del
  depósito (no se leyó ese archivo).
