import { crearAlmacenDesdeEntorno } from "./almacen.js";
import { cargarConfig } from "./config.js";
import { crearClienteIA } from "./ia.js";
import type { Dependencias } from "./puerta.js";

let guardadas: Dependencias | undefined;

/** Dependencias reales (variables de entorno de Vercel). Se arman una vez por instancia. */
export function dependenciasDelEntorno(): Dependencias {
  return (guardadas ??= { cfg: cargarConfig(), almacen: crearAlmacenDesdeEntorno() });
}

let clienteGuardado: ReturnType<typeof crearClienteIA> | undefined;

/** Cliente real de la IA (usa ANTHROPIC_API_KEY del entorno; se crea la primera vez que se usa). */
export function clienteIADelEntorno() {
  return (clienteGuardado ??= crearClienteIA());
}
