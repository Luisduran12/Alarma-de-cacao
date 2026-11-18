import { createHmac } from "node:crypto";

/** ID de instalación anónimo: un UUID v4 que la app genera una vez y guarda en el teléfono. */
const UUID_V4 = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function idValido(id: unknown): id is string {
  return typeof id === "string" && UUID_V4.test(id);
}

/**
 * Anonimiza un valor (ID de instalación o IP) antes de usarlo como clave de contador:
 * HMAC-SHA256 con un secreto del servidor. Así en el almacén no queda ningún ID ni IP
 * en claro, y sin el secreto no se puede volver al original.
 */
export function anonimizar(pepper: string, valor: string): string {
  return createHmac("sha256", pepper).update(valor).digest("hex").slice(0, 32);
}
