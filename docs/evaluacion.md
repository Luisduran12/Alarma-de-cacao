# Evaluación del análisis de fotos

Mide cuánto acierta la IA con fotos cuya clase se conoce, **por el mismo camino que usa la app**
(el manejador de `/analizar-foto`, con sus reglas y su validación).

## Qué hay

| Carpeta | Qué es |
|---|---|
| `backend/referencias/` | 40 fotos de EJEMPLO (5 por clase) que el servidor puede mandar a la IA |
| `evaluacion/galeria/` | 40 fotos de PRUEBA (5 por clase), distintas de las de ejemplo (hay una prueba que lo comprueba por nombre y por contenido) |
| `evaluacion/colombia/` | Vacía: fotos colombianas clasificadas por un técnico (ver su `LEEME.md`) |
| `evaluacion/resultados/` | Informes de las corridas REALES (`.md` y `.json`) |

Las fotos vienen de dos conjuntos con licencia CC BY 4.0 (ver `docs/creditos.md`).

## Cómo correrla

```bash
cd backend
npm run evaluar -- --estimar                        # solo calcula el costo; no llama a la IA
npm run evaluar -- --simulado                       # IA falsa: prueba el programa (NO es una medición)
ANTHROPIC_API_KEY=… npm run evaluar -- --real --tope-usd 2 --ejemplos 0   # llama a la IA y gasta dinero
ANTHROPIC_API_KEY=… npm run evaluar -- --real --tope-usd 3 --ejemplos 3   # con 3 ejemplos por clase
```

- La clave se lee del entorno al correr; **no se escribe en ningún archivo**.
- Con `--real` es obligatorio `--tope-usd`: el programa se detiene al llegar a ese gasto y lo dice.
- Para saber si los ejemplos ayudan hay que correr los dos brazos (`--ejemplos 0` y `--ejemplos N`)
  y comparar. **Hasta que se mida, el servidor trabaja sin ejemplos** (`REFERENCIAS_POR_CLASE=0`).

## Qué reporta

Fotos con respuesta y fotos en las que pidió otra foto; aciertos "k de n" con su intervalo de
confianza al 95 %; acierto por clase; matriz de confusión; semáforo según la clase verdadera;
tokens y costo. Un informe simulado se rotula "SIMULADA … NO son una medición".

## Costo estimado (ESTIMACIÓN, no medición)

Con los precios de `backend/src/costos.ts` (verificados el 2026-11-18) y tokens supuestos
(imagen = ⌈ancho/28⌉×⌈alto/28⌉; texto ≈ 3,5 caracteres por token; razonamiento del modelo
desconocido): 40 fotos sin ejemplos cuestan entre ≈ US$ 0,24 y 1,70; con 3 ejemplos por clase,
entre ≈ US$ 0,79 y 2,25. Lo que más falta saber es cuánto razona el modelo en cada foto.

## Límites de lo que mide

- Pocas fotos (5 por clase): el resultado por clase cambia mucho con una foto de diferencia.
- Las etiquetas son las de las fuentes. En el conjunto de granos cortados fueron **inferidas de los
  nombres de archivo** (según su descripción en Zenodo), no revisadas una por una.
- Las fotos de corte son de laboratorio en Brasil con tarjeta de color: no equivalen a un celular
  en finca ni a la prueba de corte de la NTC 1252.
- "Pizarroso" y "moho" cuentan como una clase; toda la monilia, como "monilia".
- Mazorca negra, grano seco con defectos y hojas no tienen fotos todavía: **esos modos no se pueden evaluar**.
