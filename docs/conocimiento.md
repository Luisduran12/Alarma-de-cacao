# Base de conocimiento del chat y de las respuestas sin internet

Archivo: `assets/conocimiento/base.json` (va dentro de la app). Lo usan dos cosas: el chat con
IA (manda los fragmentos más relacionados con la pregunta) y las respuestas **sin internet**
(preguntas frecuentes y glosario). No hay nada que no tenga fuente.

## Fuentes (las tres se leyeron completas)

| Id | Documento | Qué aporta |
|---|---|---|
| `fhia2017` | FHIA, boletín *InfoCacao* No. 14 (2017), Honduras. <https://fhia.org.hn/wp-content/uploads/InfoCacao_No14_Sept_2017.pdf> | Cosecha, fermentación, volteo, prueba de corte, secado, almacenamiento, calidad |
| `lasalle2022` | Medina et al. (2022), *Cacao antioqueño: la sinfonía microbiana, química y sensorial*. U. de Antioquia y Unilasallista, con FEDECACAO. <https://repository.unilasallista.edu.co/bitstreams/e9c09d20-867b-40ff-a4cf-cb68fbdbb3d1/download> | Qué pasa en la fermentación, secado a 7 % y máximo 50 °C, defectos de sabor, grupos de la prueba de corte |
| `ica2012` | ICA con Fedecacao (2012), *Manejo fitosanitario del cultivo del cacao: medidas para la temporada invernal*. <https://www.ica.gov.co/getattachment/c01fa43b-cf48-497a-aa7f-51e6da3f7e96/-> | Síntomas y manejo cultural de monilia, escoba de bruja y mazorca negra |

Los números de página son la posición en el PDF descargado. FHIA es un documento de
Honduras: sus cifras hay que confirmarlas con el técnico o la asociación en Colombia.

## Cómo se garantiza que no hay nada inventado

1. Cada fragmento trae `fuente` (con página) y `citas`: frases **copiadas textualmente** del
   documento, con su página.
2. `tool/verificar_conocimiento.py` comprueba dos cosas contra el texto de los PDF:
   - que cada cita aparece en la página indicada;
   - que **todo número** escrito en el resumen de un fragmento aparece en las páginas que cita
     (entiende que "cien" es 100). Las cifras que vienen de la propia app y no de un documento
     (las horas de las alarmas de la plantilla) se declaran aparte en `numeros_app`.
3. Resultado de la última revisión (2026-11-18): **61 citas revisadas, 0 no encontradas, 0
   cifras sin respaldo.** Se comprobó que el verificador sí falla con documentos cambiados, una
   página equivocada, una palabra alterada y una cifra inventada.
4. Las pruebas de la app (`test/base_conocimiento_test.dart`) exigen que cada fragmento tenga
   fuente, página y cita, que cumpla los límites del servidor, y que **no haya productos ni
   dosis de agroquímicos** ni las cifras de fuentes no verificadas (65 %, 300 granos...).

Para repetir la verificación (macOS):

```bash
swiftc -O tool/pdf_a_texto.swift -o /tmp/pdf_a_texto
/tmp/pdf_a_texto fhia.pdf fhia.txt      # igual con los otros dos PDF
python3 -I tool/verificar_conocimiento.py fhia2017=fhia.txt lasalle2022=lasalle.txt ica2012=ica.txt
```

(Otro extractor de texto, como `pdftotext`, parte las columnas de otra forma y puede dar
falsos "no aparece". Las citas se verificaron con este extractor.)

## Qué NO está en la base (pendiente, no se inventa)

- El texto de la **NTC 1252** (norma de pago de ICONTEC): por eso no hay porcentajes mínimos de
  calidad ni tamaño de muestra "oficial". La app dice que su guía sigue a FHIA.
- **Cómo se ve por dentro cada grupo** de la prueba de corte (pizarroso, pasilla, violeta...):
  solo hay un documento que da la lista de grupos, ninguno que los describa.
- Rangos para las primeras 48 h de fermentación, pH y Brix.
- **Productos y dosis** contra plagas y enfermedades: no se incluyen a propósito (el manual del
  ICA los trae; no se copiaron). La IA tiene prohibido darlos.
- Otras enfermedades y plagas del manual del ICA (rosellinia, monalonion, ceratocystis).
- Documentos propios de FEDECACAO y tesis colombianas.

## Conflictos entre fuentes que se dejan a la vista

- **Volteo:** FHIA dice cada 24 horas; la plantilla de 144 h de la app voltea a las 48, 72, 96 y
  120 horas (tesis UIS/UNAD, sin verificar). El fragmento `vol-02` lo advierte.
- **Temperatura de secado:** FHIA admite hasta 55 °C en secadora artificial; La Salle dice que
  no debe superar los 50 °C. La app usa 50 °C como valor más prudente (`sec-06`).
