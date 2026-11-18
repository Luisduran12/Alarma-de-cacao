import { describe, expect, it } from "vitest";
import { crearLugar, FUENTE_OSM, nombreDesdeNominatim } from "../src/lugar.js";
import { deps, ID_A, post } from "./ayudas.js";

/** Respuesta REAL de Nominatim (consulta del 2026-11-18, lat 7.603 lon -72.601, zoom 14, es). */
const RESPUESTA_REAL = {
  place_id: 306192707,
  licence: "Data © OpenStreetMap contributors, ODbL 1.0. http://osm.org/copyright",
  category: "place",
  type: "hamlet",
  name: "Barrio El Dique",
  display_name: "Barrio El Dique, Chinácota, Suroriente, Norte de Santander, RAP Gran Santander, Colombia",
  address: {
    hamlet: "Barrio El Dique", city: "Chinácota", state_district: "Suroriente", state: "Norte de Santander",
    "ISO3166-2-lvl4": "CO-NSA", region: "RAP Gran Santander", country: "Colombia", country_code: "co",
  },
};

function nominatim(respuestas: Array<unknown | { status: number } | Error>) {
  const llamadas: Array<{ url: URL; ua: string | null; otras: string[] }> = [];
  let i = 0;
  const f = (async (url: URL, init: RequestInit) => {
    const h = new Headers(init.headers);
    llamadas.push({ url: new URL(url), ua: h.get("user-agent"), otras: [...h.keys()] });
    const r = respuestas[Math.min(i++, respuestas.length - 1)];
    if (r instanceof Error) throw r;
    if (r && typeof r === "object" && "status" in r) return new Response("{}", { status: (r as { status: number }).status });
    return new Response(JSON.stringify(r), { status: 200 });
  }) as unknown as typeof fetch;
  return { f, llamadas };
}

describe("nombreDesdeNominatim", () => {
  it("con la respuesta real: lugar, municipio y departamento, sin el ruido (state_district, region)", () => {
    expect(nombreDesdeNominatim(RESPUESTA_REAL)).toBe("Barrio El Dique, Chinácota, Norte de Santander");
  });

  it("no repite partes iguales (vereda con el mismo nombre que el municipio)", () => {
    expect(nombreDesdeNominatim({ address: { village: "Durania", town: "Durania", state: "Norte de Santander" } })).toBe("Durania, Norte de Santander");
  });

  it("prefiere el lugar más pequeño disponible", () => {
    expect(nombreDesdeNominatim({ address: { suburb: "Centro", village: "La Cuchilla", town: "Durania", state: "Norte de Santander" } }))
      .toBe("La Cuchilla, Durania, Norte de Santander");
  });

  it("sin `address` usa las primeras 3 partes de display_name", () => {
    expect(nombreDesdeNominatim({ display_name: "A, B, C, D, E" })).toBe("A, B, C");
  });

  it("respuestas vacías o raras dan null", () => {
    for (const x of [null, undefined, 5, "texto", {}, { address: {} }, { address: { country: "Colombia" } }, { display_name: "  " }]) {
      expect(nombreDesdeNominatim(x)).toBeNull();
    }
  });

  it("limita el largo del nombre", () => {
    expect(nombreDesdeNominatim({ address: { village: "x".repeat(500) } })!.length).toBeLessThanOrEqual(200);
  });
});

describe("POST /lugar", () => {
  const cuerpo = { lat: 7.603112, lng: -72.601162 };

  it("resuelve el nombre y devuelve la atribución de OpenStreetMap", async () => {
    const { f, llamadas } = nominatim([RESPUESTA_REAL]);
    const r = await crearLugar({ ...deps(), fetchFn: f })(post(cuerpo));
    expect(r.status).toBe(200);
    expect(await r.json()).toEqual({ nombre: "Barrio El Dique, Chinácota, Norte de Santander", fuente: FUENTE_OSM });
    expect(llamadas).toHaveLength(1);
  });

  it("a Nominatim solo le llegan las coordenadas redondeadas y un User-Agent que identifica la app", async () => {
    const { f, llamadas } = nominatim([RESPUESTA_REAL]);
    await crearLugar({ ...deps(), fetchFn: f })(post(cuerpo));
    const l = llamadas[0]!;
    expect(l.url.origin + l.url.pathname).toBe("https://nominatim.openstreetmap.org/reverse");
    expect(Object.fromEntries(l.url.searchParams)).toEqual({
      format: "jsonv2", lat: "7.603", lon: "-72.601", zoom: "14", "accept-language": "es", addressdetails: "1",
    });
    expect(l.ua).toBe("CacaoLight/1.0 (contacto@ejemplo.invalid)");
    expect(l.otras).not.toContain("x-install-id");
    expect(l.url.toString()).not.toContain(ID_A);
  });

  it("guarda en caché: el mismo punto (≈110 m) no vuelve a consultar a Nominatim", async () => {
    const { f, llamadas } = nominatim([RESPUESTA_REAL]);
    const d = { ...deps(), fetchFn: f };
    const h = crearLugar(d);
    await h(post(cuerpo));
    const segunda = await h(post({ lat: 7.6029, lng: -72.6014 }));
    expect(segunda.status).toBe(200);
    expect((await segunda.json() as { nombre: string }).nombre).toContain("Chinácota");
    expect(llamadas).toHaveLength(1);
  });

  it("máximo 1 consulta por segundo: si otra instancia tiene el cerrojo, responde 503 con Retry-After y no consulta", async () => {
    const { f, llamadas } = nominatim([RESPUESTA_REAL]);
    const d = { ...deps(), fetchFn: f };
    await d.almacen.tomarCerrojo("nominatim:cerrojo", 1100); // otra instancia acaba de consultar
    const r = await crearLugar(d)(post(cuerpo));
    expect(r.status).toBe(503);
    expect(r.headers.get("retry-after")).toBe("2");
    expect(llamadas).toHaveLength(0);
  });

  it("dos puntos distintos seguidos: el segundo espera (no se superan 1 por segundo)", async () => {
    const { f, llamadas } = nominatim([RESPUESTA_REAL]);
    const d = { ...deps(), fetchFn: f };
    const h = crearLugar(d);
    expect((await h(post({ lat: 7.6, lng: -72.6 }))).status).toBe(200);
    expect((await h(post({ lat: 7.7, lng: -72.7 }))).status).toBe(503);
    expect(llamadas).toHaveLength(1);
  });

  it("Nominatim sin resultado (error de geocodificación): 404 y se recuerda un día para no insistir", async () => {
    const { f, llamadas } = nominatim([{ error: "Unable to geocode" }]);
    const d = { ...deps(), fetchFn: f };
    const h = crearLugar(d);
    expect((await h(post(cuerpo))).status).toBe(404);
    expect((await h(post(cuerpo))).status).toBe(404);
    expect(llamadas).toHaveLength(1);
  });

  it("Nominatim caído, con error o lento: 502 y NO se guarda en caché", async () => {
    for (const falla of [{ status: 500 }, new Error("sin red"), { status: 429 }]) {
      const { f, llamadas } = nominatim([falla]);
      const d = { ...deps(), fetchFn: f };
      const r = await crearLugar(d)(post(cuerpo));
      expect(r.status).toBe(502);
      expect(await d.almacen.obtener("lugar:7.603,-72.601")).toBeNull();
      expect(llamadas).toHaveLength(1);
    }
  });

  it("coordenadas inválidas: 400", async () => {
    const { f, llamadas } = nominatim([RESPUESTA_REAL]);
    const h = crearLugar({ ...deps(), fetchFn: f });
    for (const malo of [{}, { lat: "7.6", lng: -72.6 }, { lat: 7.6 }, { lat: NaN, lng: 1 }, { lat: 7.6, lng: -72.6, extra: 1 }, [], null, "x"]) {
      const r = await h(post(malo));
      expect(r.status, JSON.stringify(malo)).toBe(400);
    }
    expect(llamadas).toHaveLength(0);
  });

  it("fuera de Colombia: 400 (no es un geocodificador general)", async () => {
    const { f, llamadas } = nominatim([RESPUESTA_REAL]);
    const h = crearLugar({ ...deps(), fetchFn: f });
    for (const p of [{ lat: 40.4, lng: -3.7 }, { lat: 15, lng: -72 }, { lat: 7, lng: -60 }, { lat: -6, lng: -72 }, { lat: 7, lng: 120 }]) {
      const r = await h(post(p));
      expect(r.status, JSON.stringify(p)).toBe(400);
      expect(((await r.json()) as { error: { codigo: string } }).error.codigo).toBe("fuera_de_colombia");
    }
    expect(llamadas).toHaveLength(0);
  });

  it("sin contacto configurado no consulta (la política de OSM exige identificar la aplicación)", async () => {
    const { f, llamadas } = nominatim([RESPUESTA_REAL]);
    const d = deps();
    const sinContacto = { ...d, cfg: { ...d.cfg, contactoNominatim: undefined }, fetchFn: f };
    const r = await crearLugar(sinContacto)(post(cuerpo));
    expect(r.status).toBe(503);
    expect(llamadas).toHaveLength(0);
  });

  it("el interruptor LUGAR_DESACTIVADO apaga el servicio", async () => {
    const { f, llamadas } = nominatim([RESPUESTA_REAL]);
    const r = await crearLugar({ ...deps({ LUGAR_DESACTIVADO: "1" }), fetchFn: f })(post(cuerpo));
    expect(r.status).toBe(503);
    expect(llamadas).toHaveLength(0);
  });

  it("solo acepta POST", async () => {
    const r = await crearLugar(deps())(new Request("https://api.example/lugar?lat=7.6&lng=-72.6", { method: "GET" }));
    expect(r.status).toBe(405);
    expect(r.headers.get("allow")).toBe("POST");
  });

  it("sin ID de instalación o con uno inválido: 400", async () => {
    const h = crearLugar(deps());
    expect((await h(post(cuerpo, null))).status).toBe(400);
    expect((await h(post(cuerpo, "no-es-uuid"))).status).toBe(400);
  });

  it("aplica los límites por dispositivo", async () => {
    const { f } = nominatim([RESPUESTA_REAL]);
    const d = { ...deps({ LIMITE_LUGAR_DIA: "2" }), fetchFn: f };
    const h = crearLugar(d);
    await h(post({ lat: 7.601, lng: -72.601 }));
    await h(post({ lat: 7.601, lng: -72.601 }));
    const r = await h(post({ lat: 7.601, lng: -72.601 }));
    expect(r.status).toBe(429);
    expect(r.headers.get("retry-after")).toBeTruthy();
  });

  it("si el almacén falla, rechaza (falla cerrado) y no consulta a Nominatim", async () => {
    const { f, llamadas } = nominatim([RESPUESTA_REAL]);
    const d = deps();
    const roto = { ...d, almacen: { sumar: async () => { throw new Error("x"); } } as never, fetchFn: f };
    const r = await crearLugar(roto)(post(cuerpo));
    expect(r.status).toBe(503);
    expect(llamadas).toHaveLength(0);
  });

  it("en producción sin almacén configurado rechaza todo", async () => {
    const d = deps({ VERCEL_ENV: "production" });
    const r = await crearLugar({ ...d, almacen: null })(post(cuerpo));
    expect(r.status).toBe(503);
  });

  it("en producción sin pepper rechaza todo (500)", async () => {
    const d = deps();
    const prod = { ...d, cfg: { ...d.cfg, produccion: true, pepper: undefined } };
    expect((await crearLugar(prod)(post(cuerpo))).status).toBe(500);
  });

  it("la respuesta de error nunca incluye las coordenadas ni el ID", async () => {
    const { f } = nominatim([{ status: 500 }]);
    const r = await crearLugar({ ...deps(), fetchFn: f })(post(cuerpo));
    const t = await r.text();
    expect(t).not.toContain("7.603");
    expect(t).not.toContain(ID_A);
  });
});
