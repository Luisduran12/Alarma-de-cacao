import { crearAlmacenDesdeEntorno } from "./almacen.js";
import { cargarConfig } from "./config.js";
import type { Dependencias } from "./puerta.js";

let guardadas: Dependencias | undefined;

/** Dependencias reales (variables de entorno de Vercel). Se arman una vez por instancia. */
export function dependenciasDelEntorno(): Dependencias {
  return (guardadas ??= { cfg: cargarConfig(), almacen: crearAlmacenDesdeEntorno() });
}
