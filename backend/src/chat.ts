import { z } from "zod";
import { costoMicroUsd } from "./costos.js";
import { errorHttp, leerJson, limpiarTexto, respuestaJson } from "./http.js";
import type { ClienteIA, MensajeIA } from "./ia.js";
import { ErrorIA } from "./ia.js";
import { registrarGasto } from "./limites.js";
import { AVISO_GUIA, SISTEMA_CHAT } from "./prompts.js";
import { metodoNoPermitido, pasarPuerta, type Dependencias } from "./puerta.js";
import { registrar } from "./registro.js";

/**
 * POST /chat → { respuesta, fuentes, truncada, aviso }
 *
 * Es SIN ESTADO: la app manda lo necesario en cada pregunta (contexto del lote, hasta 6
 * turnos anteriores y los fragmentos de su base de conocimiento) y el servidor no guarda
 * nada de eso. El contexto NO admite nombre del lote ni ubicación: el esquema es estricto
 * y rechaza cualquier campo que no esté previsto.
 */
const MAX_CUERPO = 24 * 1024;
const MAX_TOKENS_RESPUESTA = 600;

const Registro = z
  .object({
    horas: z.number().min(0).max(3000),
    temperatura: z.number().min(-10).max(80),
    humedad: z.number().min(0).max(100),
    ph: z.number().min(0).max(14).optional(),
    brix: z.number().min(0).max(100).optional(),
    tempAmbiente: z.number().min(-10).max(60).optional(),
  })
  .strict();

const Contexto = z
  .object({
    etapa: z.enum(["fermentacion", "secado"]),
    horas: z.number().min(0).max(3000),
    registros: z.array(Registro).max(8),
  })
  .strict();

const Turno = z.object({ rol: z.enum(["usuario", "asistente"]), texto: z.string().min(1).max(800) }).strict();

const Fragmento = z
  .object({
    id: z.string().regex(/^[A-Za-z0-9_.-]{1,40}$/),
    fuente: z.string().min(1).max(200),
    texto: z.string().min(1).max(1500),
  })
  .strict();

const Cuerpo = z
  .object({
    mensaje: z.string().min(1).max(500),
    contexto: Contexto.optional(),
    historial: z.array(Turno).max(6).optional(),
    fragmentos: z.array(Fragmento).max(5).optional(),
  })
  .strict()
  .refine((c) => new Set(c.fragmentos?.map((f) => f.id)).size === (c.fragmentos?.length ?? 0), { message: "ids repetidos" });

export type CuerpoChat = z.infer<typeof Cuerpo>;

export interface DepsChat extends Dependencias {
  ia: ClienteIA;
}

const num = (n: number) => String(Math.round(n * 10) / 10).replace(".", ",");

/** Arma el mensaje final del usuario con secciones etiquetadas. Todo texto del usuario va limpio de < y >. */
export function armarMensaje(c: CuerpoChat): string {
  const partes: string[] = [];
  if (c.contexto) {
    const x = c.contexto;
    const filas = x.registros.map((r) => {
      const extra = [
        r.ph !== undefined ? `pH ${num(r.ph)}` : "",
        r.brix !== undefined ? `°Brix ${num(r.brix)}` : "",
        r.tempAmbiente !== undefined ? `ambiente ${num(r.tempAmbiente)} °C` : "",
      ].filter(Boolean);
      return `- hora ${num(r.horas)}: masa ${num(r.temperatura)} °C; humedad ${num(r.humedad)} %${extra.length ? "; " + extra.join("; ") : ""}`;
    });
    partes.push(
      `<contexto_lote>\nEtapa: ${x.etapa === "fermentacion" ? "fermentación" : "secado"}\nHoras transcurridas: ${num(x.horas)}\n` +
        (filas.length ? `Últimos registros:\n${filas.join("\n")}` : "Sin registros todavía.") +
        `\n</contexto_lote>`,
    );
  }
  if (c.fragmentos?.length) {
    const fr = c.fragmentos.map(
      (f) => `<fragmento id="${f.id}" fuente="${limpiarTexto(f.fuente).replace(/"/g, "'")}">${limpiarTexto(f.texto)}</fragmento>`,
    );
    partes.push(`<material_de_referencia>\n${fr.join("\n")}\n</material_de_referencia>`);
  }
  partes.push(`<pregunta>${limpiarTexto(c.mensaje)}</pregunta>`);
  return partes.join("\n\n");
}

/** Mensajes para la IA: historial (empezando siempre por un turno del usuario) + el mensaje armado. */
export function armarMensajes(c: CuerpoChat): MensajeIA[] {
  const previos: MensajeIA[] = (c.historial ?? []).map((t) => ({
    role: t.rol === "usuario" ? "user" : "assistant",
    content: limpiarTexto(t.texto),
  }));
  while (previos[0]?.role === "assistant") previos.shift();
  return [...previos, { role: "user", content: armarMensaje(c) }];
}

/** Ids de fragmentos citados en la respuesta como [F1], en orden y sin repetir. Solo cuentan los que sí se enviaron. */
export function fuentesCitadas(texto: string, fragmentos: CuerpoChat["fragmentos"]): Array<{ id: string; fuente: string }> {
  const porId = new Map((fragmentos ?? []).map((f) => [f.id, f.fuente]));
  const vistos: Array<{ id: string; fuente: string }> = [];
  for (const m of texto.matchAll(/\[([A-Za-z0-9_.-]{1,40})\]/g)) {
    const id = m[1]!;
    const fuente = porId.get(id);
    if (fuente !== undefined && !vistos.some((v) => v.id === id)) vistos.push({ id, fuente });
  }
  return vistos;
}

const MENSAJE_RECHAZO =
  "No puedo ayudarle con esa pregunta. Si es sobre su cacao, consulte a un técnico, a su asociación de productores o a FEDECACAO.";

export function respuestaErrorIA(e: ErrorIA, endpoint: string): Response {
  registrar("error", "fallo_ia", { endpoint, codigo: `ia_${e.tipo}`, estado: e.tipo === "ocupada" ? 503 : e.tipo === "configuracion" ? 500 : 502 });
  if (e.tipo === "ocupada") return errorHttp(503, "ia_ocupada", "El servicio de IA está muy ocupado. Intente en un momento.", { reintentarEnSeg: 20 });
  if (e.tipo === "configuracion") return errorHttp(500, "servidor_mal_configurado", "El servicio no está listo. Intente más tarde.");
  return errorHttp(502, "ia_no_disponible", "No se pudo consultar a la IA ahora. Intente más tarde o use las respuestas guardadas en la app.");
}

export function crearChat(deps: DepsChat): (request: Request) => Promise<Response> {
  return async (request) => {
    if (request.method !== "POST") return metodoNoPermitido("POST");

    const puerta = await pasarPuerta(request, deps, "chat", "chat");
    if (!puerta.ok) return puerta.respuesta;

    const lectura = await leerJson(request, MAX_CUERPO);
    if (!lectura.ok) return lectura.respuesta;

    // Los mensajes de error de validación NO se devuelven: podrían repetir texto del usuario.
    const c = Cuerpo.safeParse(lectura.valor);
    if (!c.success) return errorHttp(400, "peticion_invalida", "La pregunta no se pudo leer. Revise que no sea muy larga.");

    const inicio = Date.now();
    let r;
    try {
      r = await deps.ia.responder({
        modelo: deps.cfg.modeloChat,
        sistema: SISTEMA_CHAT,
        mensajes: armarMensajes(c.data),
        maxTokens: MAX_TOKENS_RESPUESTA,
      });
    } catch (e) {
      return respuestaErrorIA(e instanceof ErrorIA ? e : new ErrorIA("no_disponible"), "chat");
    }

    const costo = costoMicroUsd(deps.cfg.modeloChat, r.uso);
    try {
      await registrarGasto(puerta.almacen, costo, deps.ahora?.());
    } catch {
      /* no contar el gasto no debe impedir responder */
    }
    registrar("info", "chat_ok", {
      endpoint: "chat", modelo: deps.cfg.modeloChat, estado: 200, ms: Date.now() - inicio,
      tokens_in: r.uso.tokensEntrada + r.uso.tokensEscrituraCache + r.uso.tokensLecturaCache, tokens_out: r.uso.tokensSalida, costo_micro_usd: costo,
    });

    if (r.parada === "rechazo") {
      return respuestaJson({ respuesta: MENSAJE_RECHAZO, fuentes: [], truncada: false, aviso: AVISO_GUIA });
    }
    if (!r.texto) {
      return errorHttp(502, "ia_no_disponible", "No se pudo consultar a la IA ahora. Intente más tarde o use las respuestas guardadas en la app.");
    }
    return respuestaJson({
      respuesta: r.texto,
      fuentes: fuentesCitadas(r.texto, c.data.fragmentos),
      truncada: r.parada === "max_tokens",
      aviso: AVISO_GUIA,
    });
  };
}
