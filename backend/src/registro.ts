/**
 * Registro mínimo de eventos, SIN datos personales.
 *
 * Solo deja pasar claves de esta lista y valores cortos "técnicos" (códigos como
 * `limite_dia`, números). Todo lo demás se descarta: aunque alguien por error pase
 * el texto de una pregunta, un ID de instalación o una IP, no llega al registro.
 */
const CLAVES_PERMITIDAS = new Set([
  "endpoint",
  "codigo",
  "estado",
  "ms",
  "modelo",
  "tokens_in",
  "tokens_out",
  "costo_micro_usd",
]);

/** Solo letras minúsculas, números y `_ - . /` (sin espacios): un código, no un texto. */
const CODIGO_TECNICO = /^[a-z0-9_\-./]{1,60}$/;

export type Salida = (linea: string) => void;

export function limpiarCampos(campos: Record<string, unknown>): Record<string, string | number> {
  const limpio: Record<string, string | number> = {};
  for (const [clave, valor] of Object.entries(campos)) {
    if (!CLAVES_PERMITIDAS.has(clave)) continue;
    if (typeof valor === "number" && Number.isFinite(valor)) limpio[clave] = valor;
    else if (typeof valor === "string" && CODIGO_TECNICO.test(valor)) limpio[clave] = valor;
  }
  return limpio;
}

export function registrar(
  nivel: "info" | "error",
  evento: string,
  campos: Record<string, unknown> = {},
  salida: Salida = (l) => (nivel === "error" ? console.error(l) : console.log(l)),
): void {
  const codigoEvento = CODIGO_TECNICO.test(evento) ? evento : "evento_invalido";
  salida(JSON.stringify({ nivel, evento: codigoEvento, ...limpiarCampos(campos) }));
}
