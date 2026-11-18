import Anthropic from "@anthropic-ai/sdk";
import { zodOutputFormat } from "@anthropic-ai/sdk/helpers/zod";
import type { ZodType } from "zod";
import { NOTA_EJEMPLOS } from "./prompts.js";
import type { EjemploReferencia } from "./referencias.js";

export interface UsoIA {
  tokensEntrada: number;
  tokensSalida: number;
  tokensEscrituraCache: number;
  tokensLecturaCache: number;
}

export type Parada = "fin" | "max_tokens" | "rechazo" | "otra";

export interface MensajeIA {
  role: "user" | "assistant";
  content: string;
}

export interface RespuestaTexto {
  texto: string;
  uso: UsoIA;
  parada: Parada;
}

export interface RespuestaEstructurada<T> {
  /** null si la IA no devolvió algo que cumpla el esquema. */
  valor: T | null;
  uso: UsoIA;
  parada: Parada;
}

/** Qué salió mal con la IA, sin ningún detalle del error original (podría contener datos). */
export type TipoErrorIA = "ocupada" | "no_disponible" | "configuracion" | "peticion";

export class ErrorIA extends Error {
  constructor(readonly tipo: TipoErrorIA) {
    super(tipo); // el mensaje es solo el tipo: nunca texto del error del SDK
    this.name = "ErrorIA";
  }
}

/** Lo único que el resto del servidor sabe de la IA. En pruebas se reemplaza por uno falso. */
export interface ClienteIA {
  responder(p: { modelo: string; sistema: string; mensajes: MensajeIA[]; maxTokens: number }): Promise<RespuestaTexto>;
  analizarImagen<T>(p: {
    modelo: string;
    sistema: string;
    imagenBase64: string;
    texto: string;
    maxTokens: number;
    esquema: ZodType<T>;
    /** Fotos de ejemplo (con su etiqueta) que van ANTES de la foto del productor. */
    ejemplos?: EjemploReferencia[];
  }): Promise<RespuestaEstructurada<T>>;
}

/**
 * Los ejemplos van primero, cada foto seguida de su etiqueta, y al final un rótulo que separa la
 * foto del productor de los ejemplos (sin él la IA podría analizar un ejemplo por error).
 */
export function bloquesEjemplos(ejemplos: EjemploReferencia[]) {
  if (ejemplos.length === 0) return [];
  return [
    { type: "text" as const, text: NOTA_EJEMPLOS },
    ...ejemplos.flatMap((e) => [
      { type: "image" as const, source: { type: "base64" as const, media_type: "image/jpeg" as const, data: e.imagenBase64 } },
      { type: "text" as const, text: `Ejemplo de referencia: ${e.descripcion}` },
    ]),
    { type: "text" as const, text: "FIN DE LOS EJEMPLOS. La siguiente foto es la del productor y es la ÚNICA que debes analizar:" },
  ];
}

function paradaDe(razon: string | null | undefined): Parada {
  if (razon === "end_turn" || razon === "stop_sequence") return "fin";
  if (razon === "max_tokens") return "max_tokens";
  if (razon === "refusal") return "rechazo";
  return "otra";
}

function usoDe(u: {
  input_tokens: number;
  output_tokens: number;
  cache_creation_input_tokens?: number | null;
  cache_read_input_tokens?: number | null;
}): UsoIA {
  return {
    tokensEntrada: u.input_tokens,
    tokensSalida: u.output_tokens,
    tokensEscrituraCache: u.cache_creation_input_tokens ?? 0,
    tokensLecturaCache: u.cache_read_input_tokens ?? 0,
  };
}

/** Traduce cualquier error del SDK a uno de [TipoErrorIA], sin copiar su mensaje. */
export function clasificarError(e: unknown): ErrorIA {
  if (e instanceof ErrorIA) return e;
  if (e instanceof Anthropic.RateLimitError) return new ErrorIA("ocupada");
  if (e instanceof Anthropic.AuthenticationError || e instanceof Anthropic.PermissionDeniedError) return new ErrorIA("configuracion");
  if (e instanceof Anthropic.BadRequestError || e instanceof Anthropic.NotFoundError) return new ErrorIA("peticion");
  if (e instanceof Anthropic.APIError && typeof e.status === "number" && e.status === 529) return new ErrorIA("ocupada");
  return new ErrorIA("no_disponible"); // conexión, tiempo agotado, 5xx, o cualquier otra cosa
}

/**
 * Cliente real. La clave (ANTHROPIC_API_KEY) la lee el SDK del entorno; este código solo
 * comprueba que exista, nunca la lee ni la escribe. Se crea la primera vez que se usa: si
 * falta la clave, el error es "configuracion" en vez de tumbar la función.
 */
export function crearClienteIA(opciones: { cliente?: Anthropic } = {}): ClienteIA {
  let cliente: Anthropic | undefined = opciones.cliente;
  const obtener = (): Anthropic => {
    if (cliente) return cliente;
    // El SDK NO falla al construirse sin clave: fallaría en la primera petición con un error
    // genérico. Se comprueba aquí, de forma explícita, para diagnosticarlo como configuración.
    if (!process.env.ANTHROPIC_API_KEY?.trim()) throw new ErrorIA("configuracion");
    return (cliente = new Anthropic({ maxRetries: 1, timeout: 25_000 }));
  };

  return {
    async responder({ modelo, sistema, mensajes, maxTokens }) {
      try {
        const r = await obtener().messages.create({
          model: modelo,
          max_tokens: maxTokens,
          system: sistema,
          messages: mensajes,
          // Chat corto: sin razonamiento largo, para que el costo sea predecible.
          thinking: { type: "disabled" },
          output_config: { effort: "low" },
        });
        const texto = r.content
          .filter((b): b is Anthropic.TextBlock => b.type === "text")
          .map((b) => b.text)
          .join("")
          .trim();
        return { texto, uso: usoDe(r.usage), parada: paradaDe(r.stop_reason) };
      } catch (e) {
        throw clasificarError(e);
      }
    },

    async analizarImagen<T>({ modelo, sistema, imagenBase64, texto, maxTokens, esquema, ejemplos = [] }: {
      modelo: string; sistema: string; imagenBase64: string; texto: string; maxTokens: number; esquema: ZodType<T>;
      ejemplos?: EjemploReferencia[];
    }) {
      try {
        const r = await obtener().messages.parse({
          model: modelo,
          max_tokens: maxTokens,
          system: sistema,
          messages: [
            {
              role: "user",
              content: [
                ...bloquesEjemplos(ejemplos),
                { type: "image", source: { type: "base64", media_type: "image/jpeg", data: imagenBase64 } },
                { type: "text", text: texto },
              ],
            },
          ],
          output_config: { effort: "medium", format: zodOutputFormat(esquema) },
        });
        return { valor: (r.parsed_output as T | null) ?? null, uso: usoDe(r.usage), parada: paradaDe(r.stop_reason) };
      } catch (e) {
        throw clasificarError(e);
      }
    },
  };
}
