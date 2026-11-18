import { tokensDeImagen, costoMicroUsd } from "./costos.js";
import type { ResultadoFoto } from "./foto.js";
import type { ModoFoto } from "./prompts.js";

/**
 * Cálculos de la evaluación del análisis de fotos. Solo hace cuentas con lo que se le da:
 * no inventa ni completa nada. Los números que salen de aquí son MEDIDOS si las filas vienen de
 * llamadas reales a la IA, y no son una medición si vienen del modo simulado (el informe lo dice).
 */

/** La clase que usa la evaluación para una etiqueta del manifiesto. */
export function claseVerdadera(modo: ModoFoto, etiqueta: string): string {
  if (modo === "mazorca_hoja" && etiqueta.startsWith("monilia")) return "monilia";
  return etiqueta;
}

/**
 * La clase de una categoría que dio la IA. La fuente de las fotos de corte junta "pizarroso" y
 * "moho" en una sola clase, así que la IA acierta si dice cualquiera de las dos.
 */
export function clasePredicha(modo: ModoFoto, nombre: string): string {
  if (modo === "corte" && (nombre === "pizarroso" || nombre === "moho")) return "pizarroso_o_moho";
  return nombre;
}

/** La categoría con más porcentaje (null si se pidió otra foto o no hay categorías). */
export function prediccionTop(r: ResultadoFoto): string | null {
  if (r.repetir_foto || r.categorias.length === 0) return null;
  const top = [...r.categorias].sort((a, b) => b.porcentaje - a.porcentaje)[0]!;
  return clasePredicha(r.modo, top.nombre);
}

export interface FilaEvaluacion {
  archivo: string;
  modo: ModoFoto;
  verdadera: string;
  /** null = la app habría pedido otra foto. */
  prediccion: string | null;
  semaforo: "verde" | "amarillo" | "rojo" | null;
  /** Código de error del servidor (502, 429...), si la llamada falló. */
  error: string | null;
  tokensEntrada: number;
  tokensSalida: number;
  costoMicroUsd: number;
}

/** Intervalo de Wilson al 95 % para k de n (con pocas fotos es MUY ancho: eso es lo honesto). */
export function wilson(k: number, n: number, z = 1.96): [number, number] {
  if (n === 0) return [0, 1];
  const p = k / n;
  const d = 1 + (z * z) / n;
  const centro = (p + (z * z) / (2 * n)) / d;
  const m = (z * Math.sqrt((p * (1 - p)) / n + (z * z) / (4 * n * n))) / d;
  return [Math.max(0, centro - m), Math.min(1, centro + m)];
}

export interface Metricas {
  total: number;
  errores: number;
  repetidas: number;
  respondidas: number;
  aciertos: number;
  exactitudRespondidas: number | null;
  intervaloRespondidas: [number, number];
  /** Aciertos sobre TODAS las fotos sin error (pedir otra foto cuenta como no acierto). */
  exactitudTodas: number | null;
  clases: string[];
  /** matriz[verdadera][predicha] y la columna "otra_foto" para las que se pidió repetir. */
  matriz: Record<string, Record<string, number>>;
  porClase: Array<{ clase: string; n: number; aciertos: number; repetidas: number; recall: number | null }>;
  semaforoPorClase: Record<string, { verde: number; amarillo: number; rojo: number }>;
  costoMicroUsd: number;
  tokensEntrada: number;
  tokensSalida: number;
}

export const COLUMNA_REPETIR = "(pidió otra foto)";

export function calcular(filas: FilaEvaluacion[]): Metricas {
  const conError = filas.filter((f) => f.error !== null);
  const validas = filas.filter((f) => f.error === null);
  const clases = [...new Set(validas.map((f) => f.verdadera))].sort();
  const columnas = new Set<string>(clases);
  for (const f of validas) if (f.prediccion) columnas.add(f.prediccion);

  const matriz: Metricas["matriz"] = {};
  for (const c of clases) matriz[c] = Object.fromEntries([...columnas, COLUMNA_REPETIR].map((x) => [x, 0]));
  const semaforoPorClase: Metricas["semaforoPorClase"] = {};
  for (const c of clases) semaforoPorClase[c] = { verde: 0, amarillo: 0, rojo: 0 };

  for (const f of validas) {
    matriz[f.verdadera]![f.prediccion ?? COLUMNA_REPETIR]! += 1;
    if (f.semaforo && f.prediccion) semaforoPorClase[f.verdadera]![f.semaforo] += 1;
  }

  const respondidas = validas.filter((f) => f.prediccion !== null);
  const aciertos = respondidas.filter((f) => f.prediccion === f.verdadera).length;
  return {
    total: filas.length,
    errores: conError.length,
    repetidas: validas.length - respondidas.length,
    respondidas: respondidas.length,
    aciertos,
    exactitudRespondidas: respondidas.length ? aciertos / respondidas.length : null,
    intervaloRespondidas: wilson(aciertos, respondidas.length),
    exactitudTodas: validas.length ? aciertos / validas.length : null,
    clases,
    matriz,
    porClase: clases.map((c) => {
      const delaClase = validas.filter((f) => f.verdadera === c);
      const resp = delaClase.filter((f) => f.prediccion !== null);
      const ok = resp.filter((f) => f.prediccion === c).length;
      return { clase: c, n: delaClase.length, aciertos: ok, repetidas: delaClase.length - resp.length, recall: resp.length ? ok / resp.length : null };
    }),
    semaforoPorClase,
    costoMicroUsd: filas.reduce((a, f) => a + f.costoMicroUsd, 0),
    tokensEntrada: filas.reduce((a, f) => a + f.tokensEntrada, 0),
    tokensSalida: filas.reduce((a, f) => a + f.tokensSalida, 0),
  };
}

export interface EntradaEstimacion {
  /** Lado mayor y menor de cada foto a evaluar. */
  fotos: Array<{ ancho: number; alto: number }>;
  /** Fotos de ejemplo que se mandan con CADA foto. */
  ejemplos: Array<{ ancho: number; alto: number }>;
  /** Tokens de las instrucciones (supuesto: ≈ 3,5 caracteres por token). */
  tokensTexto: number;
  modelo: string;
}

export interface Estimacion {
  llamadas: number;
  tokensEntrada: number;
  /** Costo según cuánto razone el modelo: lo que NO se sabe (ver docs/costos-ia.md). */
  escenarios: Array<{ nombre: string; tokensSalidaPorFoto: number; usd: number }>;
}

/** ESTIMACIÓN (no medición): precios verificados + tokens supuestos. */
export function estimarCosto(e: EntradaEstimacion): Estimacion {
  const tokensEj = e.ejemplos.reduce((a, i) => a + tokensDeImagen(i.ancho, i.alto), 0);
  const porFoto = (f: { ancho: number; alto: number }) => tokensDeImagen(f.ancho, f.alto) + tokensEj + e.tokensTexto;
  const tokensEntrada = e.fotos.reduce((a, f) => a + porFoto(f), 0);
  const escenarios = [
    ["sin razonamiento", 350],
    ["razonamiento corto", 1350],
    ["razonamiento largo", 3350],
    ["tope (peor caso)", 4000],
  ] as const;
  return {
    llamadas: e.fotos.length,
    tokensEntrada,
    escenarios: escenarios.map(([nombre, out]) => ({
      nombre,
      tokensSalidaPorFoto: out,
      usd: costoMicroUsd(e.modelo, { tokensEntrada, tokensSalida: out * e.fotos.length }) / 1_000_000,
    })),
  };
}

const pct = (x: number | null) => (x === null ? "—" : `${(x * 100).toFixed(1)} %`);

export interface MetaInforme {
  fecha: string;
  modelo: string;
  conjunto: string;
  ejemplosPorClase: number;
  simulado: boolean;
}

export function informeMarkdown(meta: MetaInforme, m: Metricas): string {
  const l: string[] = [];
  l.push(`# Evaluación del análisis de fotos${meta.simulado ? " — SIMULADA" : ""}`, "");
  if (meta.simulado) {
    l.push("> **SIMULADA: la IA es falsa. Estos números NO son una medición.** Solo prueban que el programa funciona.", "");
  }
  l.push(
    `- Fecha: ${meta.fecha}`,
    `- Modelo: ${meta.modelo}`,
    `- Conjunto de fotos: ${meta.conjunto}`,
    `- Ejemplos de referencia por clase: ${meta.ejemplosPorClase}`,
    `- Fotos: ${m.total} (con error de llamada: ${m.errores})`,
    "",
    "## Resultado",
    "",
    `- Respondió con una clase: ${m.respondidas}. Pidió otra foto: ${m.repetidas}.`,
    `- Aciertos entre las que respondió: **${m.aciertos} de ${m.respondidas}** (${pct(m.exactitudRespondidas)}; intervalo de confianza 95 %: ${pct(m.intervaloRespondidas[0])} a ${pct(m.intervaloRespondidas[1])}).`,
    `- Aciertos sobre todas las fotos sin error (pedir otra foto cuenta como no acierto): ${pct(m.exactitudTodas)}.`,
    `- Tokens: ${m.tokensEntrada} de entrada, ${m.tokensSalida} de salida. Costo: US$ ${(m.costoMicroUsd / 1_000_000).toFixed(4)}.`,
    "",
    "## Por clase",
    "",
    "| Clase | Fotos | Aciertos | Pidió otra foto | Acierto entre las respondidas |",
    "|---|---|---|---|---|",
    ...m.porClase.map((c) => `| ${c.clase} | ${c.n} | ${c.aciertos} | ${c.repetidas} | ${pct(c.recall)} |`),
    "",
    "## Matriz de confusión (filas: clase verdadera; columnas: lo que dijo la IA)",
    "",
  );
  const cols = Object.keys(m.matriz[m.clases[0] ?? ""] ?? {});
  l.push(`| verdadera \\ IA | ${cols.join(" | ")} |`, `|---|${cols.map(() => "---").join("|")}|`);
  for (const c of m.clases) l.push(`| **${c}** | ${cols.map((x) => m.matriz[c]![x]).join(" | ")} |`);
  l.push("", "## Semáforo según la clase verdadera (solo fotos que respondió)", "", "| Clase | verde | amarillo | rojo |", "|---|---|---|---|");
  for (const c of m.clases) {
    const s = m.semaforoPorClase[c]!;
    l.push(`| ${c} | ${s.verde} | ${s.amarillo} | ${s.rojo} |`);
  }
  l.push(
    "",
    "## Cómo leer esto",
    "",
    "- Son pocas fotos por clase: los porcentajes por clase se mueven mucho con una sola foto de diferencia.",
    "- Las etiquetas de las fotos son las de sus fuentes (ver `docs/creditos.md`), no las de un técnico colombiano.",
    "- Las fotos de corte son de laboratorio en Brasil; el acierto aquí NO es el acierto con un celular en finca ni con la prueba de corte NTC 1252.",
    "- \"Pizarroso\" y \"moho\" se cuentan como una sola clase porque la fuente las junta.",
    "- Todas las clases de monilia se cuentan como \"monilia\".",
    "",
  );
  return l.join("\n");
}
