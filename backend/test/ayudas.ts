import { MemoriaAlmacen } from "../src/almacen.js";
import { cargarConfig, type Config } from "../src/config.js";
import type { Dependencias } from "../src/puerta.js";

export const ID_A = "3f2b8c1e-9d4a-4b7e-8a1c-0e5d6f7a8b9c";
export const ID_B = "9a1d7c33-52ee-4f0b-b6a4-1c2d3e4f5a6b";

export const ENTORNO_PRUEBA = {
  ID_PEPPER: "pepper-de-prueba-largo-123456",
  NOMINATIM_CONTACTO: "contacto@ejemplo.invalid",
};

export function deps(extra: Record<string, string> = {}, ahora?: Date): Dependencias & { cfg: Config; almacen: MemoriaAlmacen } {
  return {
    cfg: cargarConfig({ ...ENTORNO_PRUEBA, ...extra }),
    almacen: new MemoriaAlmacen(),
    ahora: ahora ? () => ahora : undefined,
  };
}

/** Petición POST JSON con ID de instalación. */
export function post(cuerpo: unknown, id: string | null = ID_A, cabeceras: Record<string, string> = {}): Request {
  const h: Record<string, string> = { "content-type": "application/json", "x-real-ip": "10.0.0.1", ...cabeceras };
  if (id) h["x-install-id"] = id;
  return new Request("https://api.example/x", { method: "POST", headers: h, body: JSON.stringify(cuerpo) });
}
