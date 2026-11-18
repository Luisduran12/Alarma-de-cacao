import type { Almacen } from "./almacen.js";
import { pepperEfectivo, type Config } from "./config.js";
import { errorHttp, ipDe } from "./http.js";
import { anonimizar, idValido } from "./instalacion.js";
import { verificarLimites, type TipoPeticion } from "./limites.js";
import { registrar } from "./registro.js";

export interface Dependencias {
  cfg: Config;
  /** null = no hay almacén configurado (en producción): se rechaza todo en vez de dejar pasar sin límite. */
  almacen: Almacen | null;
  ahora?: () => Date;
}

export type Puerta =
  | { ok: true; almacen: Almacen; idHash: string; ipHash: string }
  | { ok: false; respuesta: Response };

/** Nombre de la cabecera donde la app manda su ID de instalación anónimo (así no queda en URLs ni en cuerpos). */
export const CABECERA_ID = "x-install-id";

/**
 * Lo primero que pasa por CADA endpoint: configuración, ID de instalación válido y límites.
 * Falla CERRADO: si algo del control de uso no funciona, la petición se rechaza.
 */
export async function pasarPuerta(request: Request, deps: Dependencias, tipo: TipoPeticion, endpoint: string): Promise<Puerta> {
  const pepper = pepperEfectivo(deps.cfg);
  if (!pepper) {
    registrar("error", "config_incompleta", { endpoint, codigo: "falta_pepper", estado: 500 });
    return { ok: false, respuesta: errorHttp(500, "servidor_mal_configurado", "El servicio no está listo. Intente más tarde.") };
  }
  if (!deps.almacen) {
    registrar("error", "config_incompleta", { endpoint, codigo: "sin_almacen", estado: 503 });
    return { ok: false, respuesta: errorHttp(503, "servicio_no_disponible", "El servicio no está listo. Intente más tarde.") };
  }

  const id = request.headers.get(CABECERA_ID);
  if (!idValido(id)) {
    return { ok: false, respuesta: errorHttp(400, "id_invalido", "Falta el identificador de la instalación o no es válido.") };
  }

  const idHash = anonimizar(pepper, id);
  const ipHash = anonimizar(pepper, ipDe(request));

  let r;
  try {
    r = await verificarLimites({ almacen: deps.almacen, cfg: deps.cfg, idHash, ipHash, tipo, ahora: deps.ahora?.() });
  } catch {
    registrar("error", "almacen_fallo", { endpoint, codigo: "almacen_fallo", estado: 503 });
    return { ok: false, respuesta: errorHttp(503, "servicio_no_disponible", "El servicio no está disponible ahora. Intente más tarde.", { reintentarEnSeg: 30 }) };
  }
  if (!r.ok) {
    registrar("info", "peticion_rechazada", { endpoint, codigo: r.codigo, estado: r.estado });
    return { ok: false, respuesta: errorHttp(r.estado, r.codigo, r.mensaje, { reintentarEnSeg: r.reintentarEnSeg }) };
  }
  return { ok: true, almacen: deps.almacen, idHash, ipHash };
}

export function metodoNoPermitido(permitido: string): Response {
  const r = errorHttp(405, "metodo_no_permitido", `Use ${permitido}.`);
  r.headers.set("Allow", permitido);
  return r;
}
