import { readFileSync } from "node:fs";
import { join } from "node:path";
import { MemoriaAlmacen } from "./almacen.js";
import { cargarConfig } from "./config.js";
import { costoMicroUsd } from "./costos.js";
import { claseVerdadera, estimarCosto, prediccionTop, type Estimacion, type FilaEvaluacion } from "./evaluacion.js";
import { crearFoto, type ResultadoFoto } from "./foto.js";
import type { ClienteIA, UsoIA } from "./ia.js";
import { procesarJpeg } from "./jpeg.js";
import type { ModoFoto } from "./prompts.js";
import { cargarManifiesto, DIRECTORIO_REFERENCIAS, elegirReferencias } from "./referencias.js";
import { sistemaFoto } from "./prompts.js";

/**
 * Corre las fotos de un conjunto de prueba por el MISMO camino que usa la app (el manejador
 * de /analizar-foto, con su validación) y devuelve una fila por foto. La IA se recibe de fuera:
 * real para medir, falsa para probar el programa.
 */
export const ID_EVALUACION = "00000000-0000-4000-8000-00000000e0a1";

export interface EntradaManifiesto {
  archivo: string;
  modo: "corte" | "mazorca";
  etiqueta: string;
}

export interface OpcionesEvaluacion {
  /** Carpeta con manifest.json y las fotos (evaluacion/galeria o evaluacion/colombia). */
  carpeta: string;
  modos: ModoFoto[];
  ejemplosPorClase: number;
  /** Máximo de fotos por clase (para una prueba barata). Sin límite si no se pone. */
  maxPorClase?: number;
  /** Tope de gasto de ESTA corrida: el manejador se detiene al alcanzarlo. */
  topeUsd: number;
  modelo?: string;
}

const MODO_FOTO: Record<EntradaManifiesto["modo"], ModoFoto> = { corte: "corte", mazorca: "mazorca_hoja" };

export function leerConjunto(carpeta: string, modos: ModoFoto[], maxPorClase?: number): Array<EntradaManifiesto & { modoFoto: ModoFoto }> {
  const lista = JSON.parse(readFileSync(join(carpeta, "manifest.json"), "utf8")) as EntradaManifiesto[];
  const ordenadas = lista.map((e) => ({ ...e, modoFoto: MODO_FOTO[e.modo] })).filter((e) => modos.includes(e.modoFoto)).sort((a, b) => a.archivo.localeCompare(b.archivo));
  if (maxPorClase === undefined) return ordenadas;
  const cuenta = new Map<string, number>();
  return ordenadas.filter((e) => {
    const k = `${e.modoFoto}/${e.etiqueta}`;
    const n = cuenta.get(k) ?? 0;
    cuenta.set(k, n + 1);
    return n < maxPorClase;
  });
}

/** Estimación de costo SIN llamar a la IA. */
export function estimarEvaluacion(o: OpcionesEvaluacion): Estimacion & { fotos: number } {
  const cfg = cargarConfig({});
  const modelo = o.modelo ?? cfg.modeloFoto;
  const entradas = leerConjunto(o.carpeta, o.modos, o.maxPorClase);
  const dims = (ruta: string) => {
    const j = procesarJpeg(readFileSync(ruta));
    if (!j.ok) throw new Error(`JPEG inválido: ${ruta}`);
    return { ancho: j.ancho, alto: j.alto };
  };
  const refs = cargarManifiesto();
  let total = { llamadas: 0, tokensEntrada: 0, escenarios: [] as Estimacion["escenarios"] };
  const parciales: Estimacion[] = [];
  for (const modo of o.modos) {
    const fotos = entradas.filter((e) => e.modoFoto === modo).map((e) => dims(join(o.carpeta, e.archivo)));
    if (fotos.length === 0) continue;
    const ejemplos = elegirReferencias(refs, modo, o.ejemplosPorClase).map((r) => dims(join(DIRECTORIO_REFERENCIAS, r.archivo)));
    parciales.push(estimarCosto({ fotos, ejemplos, tokensTexto: Math.ceil(sistemaFoto(modo).length / 3.5) + 300, modelo }));
  }
  total = parciales.reduce(
    (a, p) => ({
      llamadas: a.llamadas + p.llamadas,
      tokensEntrada: a.tokensEntrada + p.tokensEntrada,
      escenarios: p.escenarios.map((s, i) => ({ ...s, usd: (a.escenarios[i]?.usd ?? 0) + s.usd })),
    }),
    total,
  );
  return { ...total, fotos: total.llamadas };
}

export interface ResultadoCorrida {
  filas: FilaEvaluacion[];
  /** true si se paró antes de terminar (tope de gasto o interruptor). */
  incompleta: boolean;
  motivoParada: string | null;
}

export async function ejecutarEvaluacion(ia: ClienteIA, o: OpcionesEvaluacion, alProgreso?: (hechas: number, total: number) => void): Promise<ResultadoCorrida> {
  const cfg = cargarConfig({
    ID_PEPPER: "evaluacion-local-pepper-123456",
    LIMITE_FOTO_DIA: "1000000",
    LIMITE_IP_HORA: "1000000",
    PRESUPUESTO_DIARIO_USD: String(o.topeUsd),
    REFERENCIAS_POR_CLASE: String(o.ejemplosPorClase),
    ...(o.modelo ? { MODELO_FOTO: o.modelo } : {}),
  });
  let ultimoUso: UsoIA | null = null;
  const grabadora: ClienteIA = {
    responder: (p) => ia.responder(p),
    analizarImagen: async (p) => {
      const r = await ia.analizarImagen(p);
      ultimoUso = r.uso;
      return r;
    },
  };
  const manejador = crearFoto({ cfg, almacen: new MemoriaAlmacen(), ia: grabadora });
  const entradas = leerConjunto(o.carpeta, o.modos, o.maxPorClase);
  const filas: FilaEvaluacion[] = [];
  const logOriginal = console.log;
  let incompleta = false;
  let motivo: string | null = null;
  try {
    console.log = () => {}; // el manejador escribe una línea de registro por llamada
    for (const e of entradas) {
      ultimoUso = null;
      const cuerpo = JSON.stringify({ modo: e.modoFoto, imagen: readFileSync(join(o.carpeta, e.archivo)).toString("base64") });
      const r = await manejador(
        new Request("https://evaluacion.local/analizar-foto", {
          method: "POST",
          headers: { "content-type": "application/json", "x-install-id": ID_EVALUACION, "x-real-ip": "10.0.0.1" },
          body: cuerpo,
        }),
      );
      const json = (await r.json()) as ResultadoFoto & { error?: { codigo: string } };
      const uso = ultimoUso as UsoIA | null;
      const base = {
        archivo: e.archivo, modo: e.modoFoto, verdadera: claseVerdadera(e.modoFoto, e.etiqueta),
        tokensEntrada: uso ? uso.tokensEntrada + uso.tokensEscrituraCache + uso.tokensLecturaCache : 0,
        tokensSalida: uso?.tokensSalida ?? 0,
        costoMicroUsd: uso ? costoMicroUsd(cfg.modeloFoto, uso) : 0,
      };
      if (r.status === 200) {
        filas.push({ ...base, prediccion: prediccionTop(json), semaforo: json.repetir_foto ? null : json.semaforo, error: null });
      } else {
        const codigo = json.error?.codigo ?? `http_${r.status}`;
        filas.push({ ...base, prediccion: null, semaforo: null, error: codigo });
        if (codigo === "presupuesto_agotado" || codigo === "servicio_pausado" || codigo === "limite_dia") {
          incompleta = true;
          motivo = codigo;
          break;
        }
      }
      alProgreso?.(filas.length, entradas.length);
    }
  } finally {
    console.log = logOriginal;
  }
  return { filas, incompleta, motivoParada: motivo };
}
