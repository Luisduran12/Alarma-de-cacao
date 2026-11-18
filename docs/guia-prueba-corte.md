# Guía de la prueba de corte: fuentes y lo que no se pudo verificar

La pantalla "Prueba de corte" (`lib/screens/guia_prueba_corte_screen.dart`) usa
solo lo que dicen dos documentos que se leyeron completos. El texto de cada paso
está en `lib/data/guia_prueba_corte.dart`, con su cita.

## Lo que sí está respaldado

**FHIA, InfoCacao No. 14 (septiembre de 2017), p. 4** (ver `docs/fuentes-curva.md`):

- Cuándo: "A partir del cuarto día, al momento de hacer el volteo, se hacen
  pruebas de corte para verificar el grado de fermentación logrado."
- Muestra: "se toman unas 9 submuestras de varios puntos de la masa de cacao, se
  mezclan y se obtiene finalmente una muestra de cien granos."
- Corte: "Cada grano se corta longitudinalmente y se observan las
  características internas para determinar el grado de fermentación."
- Resultado: "Si el resultado indica que de la muestra obtenida 70 a 75 granos
  están bien fermentados, representa un 70 a 75 % de fermentación."
- Grano pasado: "Si al hacer las pruebas de corte aparece un solo grano
  sobrefermentado, se debe parar la fermentación [...]".
- Final: "Cuando la fermentación llega a su final, la temperatura del cacao en el
  cajón empieza a disminuir."
- Comprador: "Los estándares de calidad varían entre los compradores [...]".

**Universidad de La Salle / FEDECACAO (Medina, 2022), p. 10:** lista lo que se
determina en la prueba: "granos bien fermentados, insuficientemente fermentados,
pizarrosos, mohosos, pasilla, germinados y dañados por insectos". Solo da los
nombres, no define cada grupo.

## Lo que NO se pudo verificar (y por eso no está en la app como dato)

1. **El texto de la NTC 1252.** Es una norma de pago de ICONTEC y no se pudo leer.
   Por eso la pantalla dice que sigue el procedimiento de FHIA y que la
   clasificación oficial es la de la NTC 1252, cuyo procedimiento exacto puede ser
   distinto.
2. **Cuántos granos pide la NTC 1252.** Las fuentes secundarias que aparecieron en
   la búsqueda se contradicen (cursos y resúmenes hablan de 10, 25, 30, 50 o 300
   granos; FHIA habla de 100). No se escribió ninguna de esas cifras como si fuera de
   la norma.
3. **Los límites por grado** (por ejemplo, "65 % de granos bien fermentados" o
   "10 % de pizarrosos", que aparecen en un curso en línea): ningún documento leído
   los respalda. No están en la app.
4. **Cómo se ve cada grupo por dentro** (color, textura). Las fuentes secundarias
   no coinciden entre sí (una norma regional y un curso describen distinto el color
   del grano bien fermentado). Por eso las ilustraciones muestran solo el
   **procedimiento** (muestrear, cortar, contar, calcular, ver la temperatura) con
   los colores de la app, y la pantalla le pide al productor que su técnico le
   muestre cada grupo.
5. **El ejemplo "70 de 100"** del dibujo del paso 5 sale del límite inferior del
   ejemplo de FHIA (70 a 75), y es solo un ejemplo de cómo se calcula un porcentaje.

## Qué haría falta para completarla

- El texto vigente de la NTC 1252 (ICONTEC o FEDECACAO) para poner el tamaño de
  muestra y los límites por grado.
- Fotos de referencia con licencia abierta de cada grupo (Fase 6B del plan).
