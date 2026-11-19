# Ficha para el técnico que clasifica las fotos

Una ficha por sesión de clasificación. **El técnico clasifica mirando solo la foto**, sin ver lo que respondió la IA, y con
su criterio profesional (anote cuál usa, por ejemplo la prueba de corte de la NTC 1252 o el protocolo de su asociación).

| Dato | Valor |
|---|---|
| Rol del técnico (no hace falta el nombre) | |
| Entidad o asociación | |
| Criterio que aplica (norma o protocolo, con su versión) | |
| Fecha | |
| Municipio / vereda | |
| ¿Hay permiso por escrito del productor para usar las fotos? | ☐ Sí ☐ No (si no, **no** guardarlas aquí) |
| ¿Se ve alguna persona o documento en alguna foto? | ☐ No ☐ Sí (si sí, descartarla) |

## Cómo tomar las fotos
- Con un celular común, como lo haría el productor (sin trípode ni estudio), con luz de día.
- **Corte:** granos cortados por la mitad, una foto por tanda, mostrando la superficie del corte. Anote cuántos granos se cortaron.
- **Mazorca:** una mazorca por foto si se puede; si hay varias, anote a cuál se refiere la etiqueta.
- Reducir a 1024 px de lado mayor y quitar los datos ocultos (EXIF/GPS) antes de guardarlas. La app lo hace sola; para fotos
  tomadas fuera de la app, use cualquier herramienta que borre los metadatos y compruebe el resultado.

## Etiquetas
Use exactamente las de `LEEME.md` (corte: `bien_fermentado`, `parcialmente_fermentado`, `violeta`, `pizarroso_o_moho`;
mazorca: `sana`, `monilia_ciclo1`, `monilia_ciclo2_3`, `monilia_ciclo4`). Si una foto **no** se puede clasificar con
seguridad, no la ponga en el manifiesto: es mejor tener pocas fotos seguras que muchas dudosas.

## Cuántas fotos
Para que el acierto por clase signifique algo hacen falta varias fotos por clase (el informe da el intervalo de confianza:
con pocas fotos será muy ancho y eso es lo correcto). Anote aquí cuántas hay de cada una:

| Etiqueta | Cantidad |
|---|---|
| bien_fermentado | |
| parcialmente_fermentado | |
| violeta | |
| pizarroso_o_moho | |
| sana | |
| monilia_ciclo1 | |
| monilia_ciclo2_3 | |
| monilia_ciclo4 | |

## Después
1. Copie `manifest.plantilla.json` como `manifest.json` y escriba una entrada por foto.
2. Verifique que ninguna foto esté también en `backend/referencias/`.
3. `cd backend && npm run evaluar -- --estimar --conjunto colombia` (calcula el costo; no llama a la IA). La corrida real la hace
   el autor con su clave y su tope de gasto (ver `docs/evaluacion.md`).
4. Hasta que haya corrida real con estas fotos, **no se afirma ningún acierto en Colombia.**
