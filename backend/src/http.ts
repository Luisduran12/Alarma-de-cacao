/** Utilidades de respuesta y lectura de peticiones. */
import { registrar } from "./registro.js";

const CABECERAS_BASE = {
  // Nada de lo que responde este servidor debe guardarse en cachés intermedias.
  "Cache-Control": "no-store",
  "X-Content-Type-Options": "nosniff",
} as const;

export function respuestaJson(cuerpo: unknown, estado = 200, extra: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(cuerpo), {
    status: estado,
    headers: { "Content-Type": "application/json; charset=utf-8", ...CABECERAS_BASE, ...extra },
  });
}

export interface OpcionesError {
  reintentarEnSeg?: number;
}

/** Error estándar: `{ error: { codigo, mensaje } }`. El mensaje va escrito para el productor. */
export function errorHttp(estado: number, codigo: string, mensaje: string, opciones: OpcionesError = {}): Response {
  const extra: Record<string, string> = {};
  if (opciones.reintentarEnSeg !== undefined) extra["Retry-After"] = String(Math.max(1, Math.ceil(opciones.reintentarEnSeg)));
  return respuestaJson({ error: { codigo, mensaje } }, estado, extra);
}

export type LecturaJson = { ok: true; valor: unknown } | { ok: false; respuesta: Response };

/**
 * Lee el cuerpo como JSON sin pasar de [maxBytes]. El límite se aplica MIENTRAS se lee
 * (no solo con Content-Length, que puede mentir o faltar), así un cuerpo enorme se corta
 * y no llega a ocupar la memoria del servidor.
 */
export async function leerJson(request: Request, maxBytes: number): Promise<LecturaJson> {
  const tipo = request.headers.get("content-type") ?? "";
  if (!tipo.toLowerCase().includes("application/json")) {
    return { ok: false, respuesta: errorHttp(415, "tipo_no_soportado", "La petición debe ser JSON.") };
  }

  const declarado = Number(request.headers.get("content-length"));
  if (Number.isFinite(declarado) && declarado > maxBytes) {
    return { ok: false, respuesta: errorHttp(413, "cuerpo_muy_grande", "La petición es demasiado grande.") };
  }

  const lector = request.body?.getReader();
  if (!lector) return { ok: false, respuesta: errorHttp(400, "cuerpo_vacio", "La petición viene vacía.") };

  const trozos: Uint8Array[] = [];
  let total = 0;
  for (;;) {
    const { done, value } = await lector.read();
    if (done) break;
    total += value.byteLength;
    if (total > maxBytes) {
      await lector.cancel().catch(() => undefined);
      return { ok: false, respuesta: errorHttp(413, "cuerpo_muy_grande", "La petición es demasiado grande.") };
    }
    trozos.push(value);
  }

  try {
    const texto = new TextDecoder("utf-8", { fatal: true }).decode(Buffer.concat(trozos));
    return { ok: true, valor: JSON.parse(texto) };
  } catch {
    return { ok: false, respuesta: errorHttp(400, "json_invalido", "La petición no se entiende.") };
  }
}

/** IP del cliente. Vercel pone la IP real en estas cabeceras. */
export function ipDe(request: Request): string {
  const real = request.headers.get("x-real-ip")?.trim();
  if (real) return real;
  const primera = request.headers.get("x-forwarded-for")?.split(",")[0]?.trim();
  return primera || "desconocida";
}

/** Quita caracteres de control y las marcas < > (para que el texto del usuario no pueda
 *  cerrar ni abrir las etiquetas que usa este servidor para armar el prompt). */
export function limpiarTexto(t: string): string {
  return t
    .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/g, "")
    .replace(/[<>]/g, "‹")
    .trim();
}

/**
 * Red de seguridad de TODO endpoint: si algo lanza una excepción que nadie previó, se responde un error genérico
 * (sin mensaje, sin traza, sin datos de la petición) y solo se anota un código. Así nunca se filtra información interna.
 */
export function envolverSeguro(manejador: (request: Request) => Promise<Response>, endpoint: string): (request: Request) => Promise<Response> {
  return async (request) => {
    try {
      return await manejador(request);
    } catch {
      registrar("error", "excepcion_no_controlada", { endpoint, codigo: "excepcion", estado: 500 });
      return errorHttp(500, "error_interno", "Algo salió mal. Intente más tarde.");
    }
  };
}
