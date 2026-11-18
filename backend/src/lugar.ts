import { errorHttp, leerJson, respuestaJson } from "./http.js";
import { metodoNoPermitido, pasarPuerta, type Dependencias } from "./puerta.js";
import { registrar } from "./registro.js";
import { z } from "zod";

/**
 * POST /lugar  { lat, lng }  →  { nombre, fuente }
 *
 * Resuelve el nombre del lugar con Nominatim (OpenStreetMap). Política oficial
 * (https://operations.osmfoundation.org/policies/nominatim/, leída el 2026-11-18):
 *  - máximo absoluto de 1 consulta por segundo para TODA la aplicación (no por usuario);
 *  - User-Agent que identifique la aplicación;
 *  - guardar los resultados en caché y no repetir la misma consulta;
 *  - nada de autocompletar;
 *  - mostrar la atribución de OpenStreetMap.
 * Aquí: un cerrojo global de 1,1 s en el almacén compartido, caché de 30 días y una
 * sola consulta por punto de ≈110 m. Las coordenadas viajan en el CUERPO (no en la URL)
 * para que no queden en los registros de la plataforma.
 */
export const FUENTE_OSM = "© colaboradores de OpenStreetMap (ODbL)";

const MAX_CUERPO = 1024;
const CERROJO_MS = 1100;
const CACHE_SEG = 30 * 24 * 3600;
const CACHE_NEGATIVO_SEG = 24 * 3600;

/** Solo Colombia: este servicio no es un geocodificador general (menos abuso posible). */
const LAT = [-5, 14] as const;
const LNG = [-82, -66] as const;

const Cuerpo = z.object({ lat: z.number().finite(), lng: z.number().finite() }).strict();

export interface DepsLugar extends Dependencias {
  fetchFn?: typeof fetch;
}

const redondear = (n: number) => Math.round(n * 1000) / 1000;

interface Direccion {
  [campo: string]: string | undefined;
}

/**
 * "Barrio El Dique, Chinácota, Norte de Santander": lugar más pequeño, municipio, departamento.
 * Se ignoran campos como `state_district` o `region` que meten ruido.
 */
export function nombreDesdeNominatim(j: unknown): string | null {
  if (typeof j !== "object" || j === null) return null;
  const o = j as { address?: Direccion; display_name?: unknown };
  const d = o.address;
  if (d && typeof d === "object") {
    const primero = (campos: string[]) => campos.map((c) => d[c]).find((v): v is string => typeof v === "string" && v.trim() !== "");
    const local = primero(["hamlet", "village", "suburb", "neighbourhood", "quarter", "locality"]);
    const municipio = primero(["city", "town", "municipality", "county"]);
    const depto = primero(["state"]);
    const partes = [local, municipio, depto].filter((x): x is string => !!x);
    const unicas = partes.filter((p, i) => partes.indexOf(p) === i);
    if (unicas.length) return unicas.join(", ").slice(0, 200);
  }
  if (typeof o.display_name === "string" && o.display_name.trim()) {
    return o.display_name.split(",").slice(0, 3).map((s) => s.trim()).join(", ").slice(0, 200);
  }
  return null;
}

export function crearLugar(deps: DepsLugar): (request: Request) => Promise<Response> {
  const fetchFn = deps.fetchFn ?? fetch;
  return async (request) => {
    if (request.method !== "POST") return metodoNoPermitido("POST");

    if (deps.cfg.lugarDesactivado) {
      return errorHttp(503, "lugar_desactivado", "El nombre del lugar no está disponible por ahora.");
    }
    if (!deps.cfg.contactoNominatim) {
      registrar("error", "config_incompleta", { endpoint: "lugar", codigo: "falta_contacto_nominatim", estado: 503 });
      return errorHttp(503, "lugar_no_configurado", "El nombre del lugar no está disponible por ahora.");
    }

    const puerta = await pasarPuerta(request, deps, "lugar", "lugar");
    if (!puerta.ok) return puerta.respuesta;

    const lectura = await leerJson(request, MAX_CUERPO);
    if (!lectura.ok) return lectura.respuesta;
    const c = Cuerpo.safeParse(lectura.valor);
    if (!c.success) return errorHttp(400, "coordenadas_invalidas", "Las coordenadas no son válidas.");
    const { lat, lng } = c.data;
    if (lat < LAT[0] || lat > LAT[1] || lng < LNG[0] || lng > LNG[1]) {
      return errorHttp(400, "fuera_de_colombia", "Este servicio solo funciona para lugares de Colombia.");
    }

    const la = redondear(lat), lo = redondear(lng);
    const clave = `lugar:${la.toFixed(3)},${lo.toFixed(3)}`;

    try {
      const guardado = await puerta.almacen.obtener(clave);
      if (guardado) {
        const g = JSON.parse(guardado) as { nombre?: string; sin?: boolean };
        if (g.sin) return errorHttp(404, "sin_resultado", "No se encontró un nombre para ese lugar.");
        if (typeof g.nombre === "string") return respuestaJson({ nombre: g.nombre, fuente: FUENTE_OSM });
      }

      // Máximo 1 consulta por segundo para toda la aplicación, aunque haya varias instancias.
      if (!(await puerta.almacen.tomarCerrojo("nominatim:cerrojo", CERROJO_MS))) {
        return errorHttp(503, "ocupado", "Intente de nuevo en un momento.", { reintentarEnSeg: 2 });
      }
    } catch {
      registrar("error", "almacen_fallo", { endpoint: "lugar", codigo: "almacen_fallo", estado: 503 });
      return errorHttp(503, "servicio_no_disponible", "El servicio no está disponible ahora. Intente más tarde.", { reintentarEnSeg: 30 });
    }

    // A Nominatim solo viajan las coordenadas redondeadas: nunca el ID, la IP ni otros datos.
    const url = new URL("https://nominatim.openstreetmap.org/reverse");
    url.search = new URLSearchParams({
      format: "jsonv2", lat: la.toFixed(3), lon: lo.toFixed(3), zoom: "14", "accept-language": "es", addressdetails: "1",
    }).toString();

    let j: unknown;
    try {
      const r = await fetchFn(url, {
        headers: { "User-Agent": `CacaoLight/1.0 (${deps.cfg.contactoNominatim})`, Accept: "application/json" },
        signal: AbortSignal.timeout(8000),
      });
      if (!r.ok) throw new Error(`nominatim_${r.status}`);
      j = await r.json();
    } catch {
      registrar("error", "nominatim_fallo", { endpoint: "lugar", codigo: "nominatim_fallo", estado: 502 });
      return errorHttp(502, "lugar_no_disponible", "No se pudo consultar el nombre del lugar. Intente más tarde.");
    }

    const nombre = typeof j === "object" && j !== null && "error" in j ? null : nombreDesdeNominatim(j);
    try {
      if (!nombre) {
        await puerta.almacen.guardar(clave, JSON.stringify({ sin: true }), CACHE_NEGATIVO_SEG);
        return errorHttp(404, "sin_resultado", "No se encontró un nombre para ese lugar.");
      }
      await puerta.almacen.guardar(clave, JSON.stringify({ nombre }), CACHE_SEG);
    } catch {
      // Si no se pudo guardar en caché igual se responde: el nombre ya se obtuvo.
    }
    return respuestaJson({ nombre, fuente: FUENTE_OSM });
  };
}
