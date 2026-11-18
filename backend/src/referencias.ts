import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { z } from "zod";
import type { ModoFoto } from "./prompts.js";

/**
 * Fotos de REFERENCIA que el servidor puede mandar a la IA como ejemplos (carpeta
 * `backend/referencias`, con su `manifest.json`). Salen de conjuntos de datos públicos con
 * licencia CC BY 4.0 (ver docs/creditos.md). Las fotos de PRUEBA (para medir el acierto) están
 * en `evaluacion/galeria` y nunca se mandan como ejemplo.
 *
 * Por defecto NO se manda ninguna (REFERENCIAS_POR_CLASE=0): que los ejemplos ayuden o no
 * es algo que se tiene que MEDIR con `npm run evaluar` antes de pagar por ellos.
 */
export const MAX_POR_CLASE = 5;
/** Junto al código y, si el despliegue lo movió, relativo a donde corre el proceso (vercel.json: includeFiles). */
function buscarDirectorio(): string {
  const candidatos = [fileURLToPath(new URL("../referencias/", import.meta.url)), join(process.cwd(), "referencias"), join(process.cwd(), "backend", "referencias")];
  return candidatos.find((d) => existsSync(join(d, "manifest.json"))) ?? candidatos[0]!;
}
export const DIRECTORIO_REFERENCIAS = buscarDirectorio();

const Entrada = z
  .object({
    archivo: z.string().regex(/^(cortes|mazorcas)\/[A-Za-z0-9_]+\/[A-Za-z0-9_.-]+\.jpg$/),
    modo: z.enum(["corte", "mazorca"]),
    etiqueta: z.string().min(1),
    descripcion: z.string().min(1),
    clase_original: z.string().min(1),
    fuente: z.string().min(1),
    autores: z.string().min(1),
    doi: z.string().regex(/^10\.\d{4,9}\/\S+$/),
    licencia: z.string().min(1),
    norma: z.string().min(1),
    origen: z.string().min(1),
  })
  .passthrough();

export type Referencia = z.infer<typeof Entrada>;
export interface EjemploReferencia {
  descripcion: string;
  imagenBase64: string;
}

/** Lee y valida el manifiesto. Lanza un Error si algo no cuadra (mejor fallar que mandar basura). */
export function cargarManifiesto(dir = DIRECTORIO_REFERENCIAS, leer: (ruta: string) => string = (r) => readFileSync(r, "utf8")): Referencia[] {
  const crudo = JSON.parse(leer(join(dir, "manifest.json"))) as unknown;
  const lista = z.array(Entrada).min(1).parse(crudo);
  const archivos = lista.map((e) => e.archivo);
  if (new Set(archivos).size !== archivos.length) throw new Error("manifiesto de referencias con archivos repetidos");
  return lista;
}

/** Qué modo del manifiesto sirve de ejemplo para cada modo de foto (grano seco no tiene). */
export function modoDeReferencias(modo: ModoFoto): "corte" | "mazorca" | null {
  return modo === "corte" ? "corte" : modo === "mazorca_hoja" ? "mazorca" : null;
}

/**
 * Hasta [porClase] fotos de cada clase para ese modo. Siempre las mismas (orden por nombre de
 * archivo): así el resultado de una evaluación se puede repetir.
 */
export function elegirReferencias(refs: Referencia[], modo: ModoFoto, porClase: number): Referencia[] {
  const m = modoDeReferencias(modo);
  const n = Math.min(Math.max(Math.trunc(porClase), 0), MAX_POR_CLASE);
  if (!m || n === 0) return [];
  const porEtiqueta = new Map<string, Referencia[]>();
  for (const r of [...refs].filter((x) => x.modo === m).sort((a, b) => a.archivo.localeCompare(b.archivo))) {
    porEtiqueta.set(r.etiqueta, [...(porEtiqueta.get(r.etiqueta) ?? []), r]);
  }
  return [...porEtiqueta.values()].flatMap((l) => l.slice(0, n));
}

/** Los ejemplos listos para mandar (con la foto en base64). */
export function cargarEjemplos(
  modo: ModoFoto,
  porClase: number,
  dir = DIRECTORIO_REFERENCIAS,
  leerArchivo: (ruta: string) => Buffer = (r) => readFileSync(r),
  manifiesto: Referencia[] = cargarManifiesto(dir),
): EjemploReferencia[] {
  return elegirReferencias(manifiesto, modo, porClase).map((r) => ({
    descripcion: r.descripcion,
    imagenBase64: leerArchivo(join(dir, r.archivo)).toString("base64"),
  }));
}
