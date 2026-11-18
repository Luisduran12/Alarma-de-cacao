# Costo de la IA por consulta

**Todo lo de esta página es una ESTIMACIÓN calculada, no una medición**: no hay clave de
Anthropic en este entorno, así que no se hizo ninguna llamada real. Las cifras de PRECIO
sí son oficiales; los TOKENS son supuestos (se explican). El servidor registra los tokens
reales y el costo de cada llamada: con una semana de uso real esta tabla se reemplaza por
datos medidos (ver "Cómo medirlo de verdad").

## Modelos y precios (verificados)

Fuente: <https://platform.claude.com/docs/en/about-claude/pricing>, leída el **2026-11-18**.

| Uso | Modelo (nombre actual de la API) | Entrada | Salida |
|---|---|---|---|
| Chat | `claude-haiku-5-5` | $0,10 por millón de tokens (prompts de hasta 100.000 tokens) | $0,50 por millón |
| Fotos | `claude-sonnet-5-5` | $2 por millón | $10 por millón |

Los nombres de modelo salen de la referencia oficial de la API (tabla de modelos actuales) y
de las páginas de precios y de visión, que los listan. Notas verificadas: Haiku 5.5 cobra más
(0,50 / 2,50) si el prompt pasa de 100.000 tokens (aquí no ocurre); la lectura de caché de
Sonnet 5.5 cuesta $0,10 por millón (la referencia cacheada decía $0,20: se usó la página de
precios). Los precios están en `backend/src/costos.ts` con su fecha de verificación.

**Imágenes:** una imagen cuesta ⌈ancho/28⌉ × ⌈alto/28⌉ tokens (documentación de visión,
leída el mismo día). La documentación da 2.576 px como máximo sin reducir para "Claude 4.7 y modelos posteriores"; se asume que Sonnet 5.5 entra en ese grupo (la página lo lista entre los modelos con visión, pero no lo nombra en esa tabla). Una foto de
1024×768 cuesta **1.036 tokens** de entrada; una de 768×576, 588.

## Supuestos sobre los tokens (NO medidos)

- Texto en español: ≈ 3,5 caracteres por token.
- Prompt del chat: 1.906 caracteres ≈ 545 tokens. Prompt de la foto (modo corte): 1.351
  caracteres ≈ 398 tokens. Más ≈ 300 tokens por el esquema de la respuesta estructurada
  (esto último es un supuesto sin base).
- Respuesta del chat: 150 a 200 tokens típicos; el tope es 600.
- Respuesta de la foto: ≈ 350 tokens de JSON, **más el razonamiento** del modelo
  (`effort: medium`, razonamiento adaptativo). No se sabe cuánto razonará: por eso se
  muestran varios escenarios. El tope total de salida es 4.000 tokens.

## Costo estimado por consulta

### Chat (Haiku 5.5)

| Caso | Tokens entrada | Tokens salida | Costo |
|---|---|---|---|
| Pregunta corta, sin contexto ni material | ~570 | 150 | **$0,00013** |
| Típico: 5 registros, 3 fragmentos, 2 turnos | ~1.630 | 200 | **$0,00026** |
| Peor caso permitido (todo al máximo) | ~4.630 | 600 | **$0,00076** |

Es decir, **menos de una milésima de dólar por pregunta**: mil preguntas cuestan alrededor
de $0,26 a $0,76.

### Foto (Sonnet 5.5), imagen de 1024×768

| Razonamiento del modelo | Tokens salida | Costo |
|---|---|---|
| Ninguno | ~350 | **$0,0070** |
| 1.000 tokens | ~1.350 | **$0,0170** |
| 3.000 tokens | ~3.350 | **$0,0370** |
| Peor caso (tope de 4.000 de salida) | 4.000 | **$0,0435** |

Una foto cuesta entre **$0,007 y $0,044** según cuánto razone el modelo; lo más probable
es lo bajo o intermedio, pero **eso es lo que más falta medir**. Si el costo real resultara
alto, se baja con `effort: "low"` en `backend/src/ia.ts` (o con un modelo más barato, tras
medir la calidad con `/evaluacion`).

## Cuántas referencias conviene usar (Fase 6B)

Cada imagen de referencia de 768×576 suma 588 tokens de entrada: **$0,0012 sin caché** y
**$0,00006 si se lee de la caché del prompt** ($0,10 por millón). Con 3 a 5 referencias por
clase y 5 clases, mandar todas serían 15 a 25 imágenes: $0,018 a $0,029 sin caché. Con
caché serían ≈ $0,001 a $0,0015 más la escritura inicial. **La cantidad óptima no se puede
decidir sin medir la exactitud** con fotos etiquetadas; esa medición es la Fase 6B y requiere
tu OK por el costo.

## Por dispositivo y por día (con los límites por defecto)

| | Típico | Peor caso |
|---|---|---|
| 30 preguntas de chat | $0,008 | $0,023 |
| 10 fotos | $0,07 a $0,17 | $0,435 |
| **Total por instalación y día** | **≈ $0,08 a $0,18** | **≈ $0,46** |

Con el **tope de gasto de 5 USD por día** para todo el servidor, el peor caso absoluto de
fotos son ≈ 115 en un día; con el costo típico, entre 300 y 700. Ese tope es la defensa
real contra el abuso (los IDs de instalación se pueden fabricar). Se cambia con
`PRESUPUESTO_DIARIO_USD`.

## Cómo medirlo de verdad

Cada llamada deja en el registro de Vercel una línea como
`{"evento":"foto_ok","modelo":"claude-sonnet-5-5","tokens_in":1734,"tokens_out":820,"costo_micro_usd":11668}`
(sin ningún dato del usuario). Sumando `costo_micro_usd` (millonésimas de dólar) y dividiendo
entre el número de líneas se obtiene el costo real por consulta. El precio por token está en
`backend/src/costos.ts`; si Anthropic lo cambia, hay que actualizarlo ahí.

## Lo que NO se verificó

- Ningún número de tokens: todos salen de supuestos. En particular, el razonamiento de
  Sonnet 5.5 y el peso del esquema de respuesta.
- Que `effort: "low"` en el chat y `thinking: disabled` sean aceptados por Haiku 5.5: la
  referencia oficial lo permite y los tipos del SDK lo aceptan, pero no se probó contra la API.
- Que la API acepte el esquema de respuesta estructurada tal como está.
