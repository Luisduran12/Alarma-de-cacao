# Fotos colombianas clasificadas por un técnico

Aquí van las fotos que SÍ representan el uso real: tomadas con un celular, en finca o beneficiadero
colombiano, y **clasificadas por un técnico** (no por la propia IA ni por el nombre del archivo).
Con ellas se mide el acierto que de verdad importa. Mientras esta carpeta esté vacía, el acierto
medido con `evaluacion/galeria` (fotos de Brasil en laboratorio y mazorcas de Santander y Antioquia)
**no debe presentarse como acierto en Colombia**.

## Formato

- `manifest.json`: lista de `{ "archivo", "modo", "etiqueta", "tecnico", "fecha", "lugar" }`.
  - `modo`: `corte` o `mazorca`.
  - `etiqueta` (las mismas de la galería): corte → `bien_fermentado`, `parcialmente_fermentado`,
    `violeta`, `pizarroso_o_moho`; mazorca → `sana`, `monilia_ciclo1`, `monilia_ciclo2_3`, `monilia_ciclo4`.
  - `tecnico`: quién la clasificó (rol, no hace falta el nombre). `lugar`: municipio o vereda, sin coordenadas.
- Las fotos como `.jpg`, con el mismo tratamiento que usa la app (máximo 1024 px, sin metadatos).
- Una foto no puede estar también en `backend/referencias/` (la de ejemplo y la de prueba son siempre distintas).

## Permisos

Antes de guardar fotos de productores, hace falta su permiso por escrito y que no se vea ninguna
persona ni dato identificable. Si la carpeta se sube a un repositorio público, esas fotos quedan públicas.

Para medir: `cd backend && npm run evaluar -- --estimar --conjunto colombia`

## Archivos de esta carpeta

- `ficha-tecnico.md`: ficha para el técnico (cómo tomar y clasificar las fotos).
- `manifest.plantilla.json`: plantilla del `manifest.json` (cópiela y llénela).
- Todavía **no hay fotos ni `manifest.json`**: esta carpeta está vacía de datos.
