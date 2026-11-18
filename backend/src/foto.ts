import { z } from "zod";
import { respuestaErrorIA } from "./chat.js";
import { costoMicroUsd } from "./costos.js";
import { errorHttp, leerJson, respuestaJson } from "./http.js";
import { ErrorIA, type ClienteIA } from "./ia.js";
import { procesarJpeg } from "./jpeg.js";
import { registrarGasto } from "./limites.js";
import { cargarEjemplos, type EjemploReferencia } from "./referencias.js";
import { CATEGORIAS, sistemaFoto, type ModoFoto } from "./prompts.js";
import { metodoNoPermitido, pasarPuerta, type Dependencias } from "./puerta.js";
import { registrar } from "./registro.js";

/**
 * POST /analizar-foto  { modo, imagen }  →  resultado estructurado
 *
 * La imagen llega en base64 (JPEG, ya reducida por la app), se LIMPIA de metadatos, se la
 * pasa a la IA y se descarta: no se guarda ni se registra. La respuesta de la IA se valida
 * a fondo antes de entregarla; si la foto es mala o la confianza es baja, NO se entregan
 * porcentajes: se pide otra foto en vez de adivinar.
 */
export const AVISO_FOTO =
  "Estimación orientativa. La clasificación oficial es la prueba de corte de la NTC 1252. Ante duda, consulte al técnico.";

/** Límite de Vercel para el cuerpo de una petición: 4,5 MB (se deja margen). */
const MAX_CUERPO = 2_600_000;
const MAX_IMAGEN_BYTES = 1_800_000;
/** La app reduce a ~1024 px; hasta 1600 px se acepta, más no (cuesta más y no ayuda). */
const MAX_LADO = 1600;
const MIN_LADO = 200;
/**
 * Tope de tokens de SALIDA, que en Sonnet 5.5 incluyen el razonamiento además del JSON. Con un
 * tope bajo, un razonamiento largo dejaría el JSON cortado (respuesta inválida, ya cobrada).
 * El peor caso por foto es este tope × el precio de salida (ver docs/costos-ia.md).
 */
export const MAX_TOKENS_RESPUESTA = 4000;

const Cuerpo = z
  .object({
    modo: z.enum(["corte", "grano_seco", "mazorca_hoja"]),
    imagen: z.string().min(100).regex(/^[A-Za-z0-9+/]+={0,2}$/),
  })
  .strict();

const MOTIVOS = ["ninguno", "borrosa", "oscura", "no_es_cacao", "muy_lejos", "otro"] as const;
export type MotivoFoto = (typeof MOTIVOS)[number];

/** Lo que se le pide a la IA (sencillo a propósito: los esquemas con muchas reglas se aceptan peor). */
export const EsquemaFoto = z.object({
  foto_valida: z.boolean(),
  motivo_foto_no_valida: z.enum(MOTIVOS),
  categorias: z.array(z.object({ nombre: z.string(), porcentaje: z.number() })),
  confianza: z.enum(["alta", "media", "baja"]),
  posibles_causas: z.array(z.string()),
  pasos_recomendados: z.array(z.string()),
  semaforo: z.enum(["verde", "amarillo", "rojo"]),
});
export type ResultadoIA = z.infer<typeof EsquemaFoto>;

export interface ResultadoFoto {
  modo: ModoFoto;
  foto_valida: boolean;
  /** true = la app debe pedir otra foto (mala, o la IA no está segura): no hay porcentajes. */
  repetir_foto: boolean;
  motivo: MotivoFoto;
  mensaje: string;
  categorias: Array<{ nombre: string; porcentaje: number }>;
  confianza: "alta" | "media" | "baja";
  posibles_causas: string[];
  pasos_recomendados: string[];
  semaforo: "verde" | "amarillo" | "rojo";
  aviso: string;
}

const MENSAJES_REPETIR: Record<MotivoFoto, string> = {
  ninguno: "No estoy seguro de lo que veo. Tome otra foto, con buena luz y bien enfocada.",
  borrosa: "La foto salió borrosa. Tome otra, con el teléfono quieto y bien enfocada.",
  oscura: "La foto está muy oscura. Tome otra con luz natural, sin sombras.",
  no_es_cacao: "En la foto no se ve cacao. Tome otra mostrando el grano, la mazorca o la hoja.",
  muy_lejos: "La foto está muy lejos. Acérquese y tome otra.",
  otro: "No se pudo analizar la foto. Tome otra, con buena luz y bien enfocada.",
};

const limpiarLista = (l: string[]) => l.map((t) => t.trim().slice(0, 300)).filter(Boolean).slice(0, 5);

/** null = la respuesta de la IA no es confiable (nombres raros, porcentajes que no cuadran...). */
export function validarResultado(modo: ModoFoto, r: ResultadoIA): ResultadoFoto | null {
  const comun = { modo, aviso: AVISO_FOTO, posibles_causas: limpiarLista(r.posibles_causas), pasos_recomendados: limpiarLista(r.pasos_recomendados) };

  // Foto mala o confianza baja: NO se entregan porcentajes (no adivinar). Se pide otra foto.
  if (!r.foto_valida || r.confianza === "baja") {
    const motivo: MotivoFoto = !r.foto_valida ? (r.motivo_foto_no_valida === "ninguno" ? "otro" : r.motivo_foto_no_valida) : "ninguno";
    return {
      ...comun, foto_valida: r.foto_valida, repetir_foto: true, motivo, mensaje: MENSAJES_REPETIR[motivo],
      categorias: [], confianza: "baja", semaforo: "amarillo",
    };
  }

  const permitidas = CATEGORIAS[modo];
  const nombres = r.categorias.map((c) => c.nombre);
  if (r.categorias.length === 0) return null;
  if (new Set(nombres).size !== nombres.length) return null;
  if (nombres.some((n) => !permitidas.includes(n))) return null;
  if (r.categorias.some((c) => !Number.isFinite(c.porcentaje) || c.porcentaje < 0 || c.porcentaje > 100)) return null;
  const suma = r.categorias.reduce((a, c) => a + c.porcentaje, 0);
  if (suma < 90 || suma > 110) return null;

  return {
    ...comun, foto_valida: true, repetir_foto: false, motivo: "ninguno", mensaje: "",
    categorias: r.categorias.map((c) => ({ nombre: c.nombre, porcentaje: Math.round(c.porcentaje) })),
    confianza: r.confianza, semaforo: r.semaforo,
  };
}

export interface DepsFoto extends Dependencias {
  ia: ClienteIA;
  /** Ejemplos de referencia para el modo (se cambia en pruebas). Por defecto lee backend/referencias. */
  ejemplos?: (modo: ModoFoto, porClase: number) => EjemploReferencia[];
}

export function crearFoto(deps: DepsFoto): (request: Request) => Promise<Response> {
  return async (request) => {
    if (request.method !== "POST") return metodoNoPermitido("POST");

    const puerta = await pasarPuerta(request, deps, "foto", "analizar-foto");
    if (!puerta.ok) return puerta.respuesta;

    const lectura = await leerJson(request, MAX_CUERPO);
    if (!lectura.ok) return lectura.respuesta;
    const c = Cuerpo.safeParse(lectura.valor);
    if (!c.success) return errorHttp(400, "peticion_invalida", "La foto no se pudo leer. Tome otra.");

    const bytes = Buffer.from(c.data.imagen, "base64");
    if (bytes.length > MAX_IMAGEN_BYTES) {
      return errorHttp(413, "imagen_muy_grande", "La foto es muy pesada. Tome otra más pequeña.");
    }
    const jpeg = procesarJpeg(bytes);
    if (!jpeg.ok) {
      return errorHttp(400, jpeg.error === "no_es_jpeg" ? "imagen_no_jpeg" : "imagen_danada", "La foto no se pudo leer. Tome otra.");
    }
    if (Math.max(jpeg.ancho, jpeg.alto) > MAX_LADO) {
      return errorHttp(413, "imagen_muy_grande", "La foto es muy grande. La app debe reducirla antes de enviarla.");
    }
    if (Math.max(jpeg.ancho, jpeg.alto) < MIN_LADO) {
      return errorHttp(400, "imagen_muy_pequena", "La foto es muy pequeña. Tome otra más cerca.");
    }

    // Ejemplos de referencia: solo si están activados (REFERENCIAS_POR_CLASE > 0). Si no se pueden
    // leer, se falla en vez de seguir sin ellos en silencio: el servicio cambiaría de calidad sin avisar.
    let ejemplos: EjemploReferencia[] = [];
    if (deps.cfg.referenciasPorClase > 0) {
      try {
        ejemplos = (deps.ejemplos ?? cargarEjemplos)(c.data.modo, deps.cfg.referenciasPorClase);
      } catch {
        registrar("error", "referencias_no_disponibles", { endpoint: "analizar-foto", codigo: "servidor_mal_configurado", estado: 500 });
        return errorHttp(500, "servidor_mal_configurado", "El servicio no está bien configurado. Intente más tarde.");
      }
    }

    const inicio = Date.now();
    let r;
    try {
      r = await deps.ia.analizarImagen({
        ejemplos,
        modelo: deps.cfg.modeloFoto,
        sistema: sistemaFoto(c.data.modo),
        // La imagen que va a la IA es la LIMPIA (sin EXIF/GPS).
        imagenBase64: jpeg.limpio.toString("base64"),
        texto: "Analiza esta foto siguiendo las reglas.",
        maxTokens: MAX_TOKENS_RESPUESTA,
        esquema: EsquemaFoto,
      });
    } catch (e) {
      return respuestaErrorIA(e instanceof ErrorIA ? e : new ErrorIA("no_disponible"), "analizar-foto");
    }

    const costo = costoMicroUsd(deps.cfg.modeloFoto, r.uso);
    try {
      await registrarGasto(puerta.almacen, costo, deps.ahora?.());
    } catch {
      /* no contar el gasto no debe impedir responder */
    }
    registrar("info", "foto_ok", {
      endpoint: "analizar-foto", modelo: deps.cfg.modeloFoto, estado: 200, ms: Date.now() - inicio,
      tokens_in: r.uso.tokensEntrada + r.uso.tokensEscrituraCache + r.uso.tokensLecturaCache, tokens_out: r.uso.tokensSalida, costo_micro_usd: costo,
    });

    if (r.parada === "rechazo") {
      const resultado: ResultadoFoto = {
        modo: c.data.modo, foto_valida: false, repetir_foto: true, motivo: "otro", mensaje: MENSAJES_REPETIR.otro,
        categorias: [], confianza: "baja", posibles_causas: [], pasos_recomendados: ["Consulte a un técnico, a su asociación o a FEDECACAO."],
        semaforo: "amarillo", aviso: AVISO_FOTO,
      };
      return respuestaJson(resultado);
    }

    const validado = r.valor ? validarResultado(c.data.modo, r.valor) : null;
    if (!validado) {
      registrar("error", "respuesta_ia_invalida", { endpoint: "analizar-foto", codigo: "respuesta_ia_invalida", estado: 502 });
      return errorHttp(502, "respuesta_ia_invalida", "No se pudo analizar la foto. Intente de nuevo o tome otra.");
    }
    return respuestaJson(validado);
  };
}
