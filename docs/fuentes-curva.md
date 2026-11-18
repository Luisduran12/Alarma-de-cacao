# Fuentes de los rangos de la curva

Los rangos están en un solo lugar: `lib/data/referencias_curva.dart`.
Esta página guarda las citas literales para poder comprobarlas. Los dos
documentos se descargaron y se leyó su texto completo (no solo un resumen).

## Documento A: FHIA, InfoCacao No. 14 (septiembre de 2017)

Proyecto PROCACAHO (FUNDER, FHIA y APROCACAO, con apoyo de COSUDE), Honduras.
<https://fhia.org.hn/wp-content/uploads/InfoCacao_No14_Sept_2017.pdf>

- p. 3: "se debe mantener un termómetro [...] para ser colocado dentro del
  centro de la masa y verificar que la temperatura suba y se mantenga arriba
  de 45 ºC a partir del tercer día y aumentará hasta 50 °C o más en los días
  posteriores."
- p. 4: "El proceso de fermentación dura entre 5 a 7 días, según el tipo de
  cacao y el clima."
- p. 5: el secado termina "cuando la humedad del grano sea de 6.5 a 7.0 %";
  "si se seca menos de 6.0 % se vuelve quebradizo".
- p. 5 (secado artificial): empezar a "40 °C" y subir poco a poco "hasta
  alcanzar los 55 °C".

## Documento B: Medina, P.X. (2022). Cacao antioqueño: la sinfonía microbiana, química y sensorial

Corporación Universitaria Lasallista, con FEDECACAO y la Universidad de
Antioquia (proyecto financiado por el Sistema General de Regalías, 2015-2019).
ISBN impreso 978-628-7519-73-2. Se descargó de
<https://repository.unilasallista.edu.co/bitstreams/e9c09d20-867b-40ff-a4cf-cb68fbdbb3d1/download>.

- p. 3: el mucílago "presenta un valor de acidez inicial pH de 3.5".
- p. 4: "Estas reacciones incrementan la temperatura de la masa
  aproximadamente a 50 °C y un pH de 5".
- p. 6: el secado tiene como objetivo "disminuir la humedad al 7%".
- p. 7: "registrar la temperatura de secado la cual no debe superar los 50ºC".

## Qué NO se pudo verificar

- **Un rango para las primeras 48 h de fermentación.** Ninguno de los dos
  documentos lo da. En la app esas horas aparecen "sin referencia".
- **"Tercer día" = hora 48.** Es una interpretación: la fuente dice
  "tercer día", no una hora. Si su técnico usa otro criterio, cambie
  `desdeHora` en la constante.
- **Banda de pH y valores de Brix.** No hay fuente verificable; no se dibuja
  banda. Los campos se guardan igual, para que el productor lleve su propio
  registro.
- **Que el 50 °C sea un tope.** FHIA dice "50 °C o más". Por eso un valor
  sobre 50 se muestra como "sobre la referencia", no como daño al grano.
- **Secado: 50 °C frente a 55 °C.** Las dos fuentes difieren. Se usa 50 °C
  (más prudente); FHIA habla de secadora artificial.
- **Si estos rangos coinciden con la NTC 1252 o con el protocolo de
  FEDECACAO.** No se consultó la norma ni un documento oficial de FEDECACAO.
  Confirmar con el técnico o la asociación.
- **Numeración de páginas.** Las `p.` son la posición en el PDF descargado
  (8 páginas el documento A, 11 el B), no la numeración impresa.
