# Análisis de fotos (Fase 6)

Botón "Fotos del lote (análisis con IA)" en el detalle del lote.

## Flujo

1. **Qué mirar:** prueba de corte, grano seco, o mazorca u hoja. Cada una tiene su guía de cómo tomar la foto.
   Los consejos de la guía son de esta app (luz, fondo, distancia...), no una norma; lo único con fuente es
   "cortar el grano a lo largo" (FHIA, InfoCacao No. 14, 2017). Termina siempre con "no fotografíe personas".
2. **Permiso** la primera vez (y mientras no lo haya dado): se explica que la foto va a un servidor y de ahí a
   Anthropic, que se le borran los datos ocultos, que el servidor no la guarda, que Anthropic puede conservarla
   hasta 30 días y que puede decir que no. Sin permiso no se abre la cámara ni se envía nada. El consentimiento
   formal (Ley 1581) y la política de privacidad son de la Fase 7.
3. **Preparar en el teléfono** (`PreparadorFoto`): reduce a 1024 px por el lado largo, aplica la rotación del EXIF a los
   píxeles y vuelve a codificar a JPEG **sin EXIF, sin GPS y sin perfil de color** (hay una prueba que recorre los
   segmentos del archivo). Rechaza lo que no es una imagen o mide menos de 200 px.
4. **Guardar y analizar** (`FotoService`): la foto queda en el teléfono (tabla `analisis_fotos`, base de datos v7). Se manda
   `POST /analizar-foto` con SOLO el modo y la foto. Sin señal, con límite diario o con el servidor ocupado la foto
   queda **en cola** y se reintenta al abrir la lista de fotos o con "Reintentar ahora". Si el servidor la rechaza
   (foto dañada o muy pesada) queda en error y no se reintenta.
5. **Resultado:** semáforo con ícono y palabras ("Sin problemas a la vista", "Hay algo que vigilar", "Problema serio:
   consulte al técnico"), lo que se ve con porcentajes aproximados, confianza, posibles causas y pasos. Si la IA no
   está segura o la foto no sirve, **no se muestran porcentajes**: se pide otra foto. Siempre con "Es una guía, no
   reemplaza al técnico" y la nota de que la clasificación oficial es la prueba de corte de la NTC 1252.

## Servidor

- Acepta fotos de 200 a 1600 px, JPEG, hasta 1,8 MB, y las limpia de metadatos otra vez (segunda barrera).
- Valida la respuesta de la IA (categorías permitidas, porcentajes que sumen ≈ 100) antes de entregarla.
- **Ejemplos de referencia:** `REFERENCIAS_POR_CLASE` (0 a 5, por defecto **0**) manda fotos de ejemplo de
  `backend/referencias/` junto a la del productor. Está apagado hasta medir con `docs/evaluacion.md` que ayuda.
  No hay ejemplos para grano seco ni para mazorca negra. `vercel.json` incluye la carpeta en el despliegue de la
  función (`includeFiles`), pero **no se probó un despliegue real**.

## Qué NO se verificó

- **Nada se probó con la IA real ni con un servidor desplegado.** No se sabe qué tan bien acierta ni si los
  ejemplos ayudan: el programa de evaluación existe y está probado con una IA falsa, pero no se corrió con la real
  (hace falta tu clave en el entorno y tu OK por el costo).
- **No se probó la cámara ni la galería en un teléfono real** (ni los permisos de Android). Las pantallas se
  probaron con un selector falso.
- Que la reducción a 1024 px y la decodificación aguanten en un teléfono de gama baja con fotos de 12 megapíxeles
  (se pide al selector que reduzca antes a 1600 px y se decodifica en otro hilo, pero no se midió).
- Los textos de la guía de la foto no los revisó ningún técnico ni se probaron con productores.
- La licencia de las fotos de corte (Zenodo) debe confirmarse con sus autores antes de publicar (ver `docs/creditos.md`).
