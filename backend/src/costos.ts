/**
 * Precios de la API de Anthropic en dólares por millón de tokens.
 *
 * Fuente: https://platform.claude.com/docs/en/about-claude/pricing (leída el 2026-11-18).
 * Si cambian, hay que actualizar esta tabla: el tope de gasto diario depende de ella.
 * Un token cuesta (precio por millón) millonésimas de dólar, así que
 * `tokens × precio` ya da el costo en microdólares.
 */
export const PRECIOS_VERIFICADOS_EL = "2026-11-18";

interface Precio {
  entrada: number;
  salida: number;
  escrituraCache5m: number;
  lecturaCache: number;
}

const SONNET_5_5: Precio = { entrada: 2, salida: 10, escrituraCache5m: 2.5, lecturaCache: 0.1 };
const HAIKU_5_5_CORTO: Precio = { entrada: 0.1, salida: 0.5, escrituraCache5m: 0.125, lecturaCache: 0.01 };
/** Haiku 5.5 con un prompt de más de 100.000 tokens (toda la petición paga el precio alto). */
const HAIKU_5_5_LARGO: Precio = { entrada: 0.5, salida: 2.5, escrituraCache5m: 0.625, lecturaCache: 0.05 };
const UMBRAL_HAIKU = 100_000;

export interface Uso {
  tokensEntrada: number;
  tokensSalida: number;
  tokensEscrituraCache?: number;
  tokensLecturaCache?: number;
}

/**
 * Costo en microdólares (redondeado hacia arriba). Un modelo desconocido se cobra al
 * precio MÁS ALTO conocido: así el tope diario nunca subestima el gasto.
 */
export function costoMicroUsd(modelo: string, uso: Uso): number {
  const escritura = uso.tokensEscrituraCache ?? 0;
  const lectura = uso.tokensLecturaCache ?? 0;
  let p: Precio;
  if (modelo === "claude-haiku-5-5") {
    // La longitud del prompt cuenta TODOS los tokens de entrada, incluida la caché.
    p = uso.tokensEntrada + escritura + lectura > UMBRAL_HAIKU ? HAIKU_5_5_LARGO : HAIKU_5_5_CORTO;
  } else if (modelo === "claude-sonnet-5-5") {
    p = SONNET_5_5;
  } else {
    p = { ...SONNET_5_5, entrada: 10, salida: 50, escrituraCache5m: 12.5, lecturaCache: 1 }; // el más caro de la tabla (Fable 5.1)
  }
  return Math.ceil(
    uso.tokensEntrada * p.entrada + uso.tokensSalida * p.salida + escritura * p.escrituraCache5m + lectura * p.lecturaCache,
  );
}

/** Tokens de una imagen: ⌈ancho/28⌉ × ⌈alto/28⌉ (https://platform.claude.com/docs/en/build-with-claude/vision). */
export function tokensDeImagen(ancho: number, alto: number): number {
  return Math.ceil(ancho / 28) * Math.ceil(alto / 28);
}
