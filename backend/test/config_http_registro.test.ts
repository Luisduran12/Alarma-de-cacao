import { describe, expect, it } from "vitest";
import { cargarConfig, pepperEfectivo, POR_DEFECTO } from "../src/config.js";
import { errorHttp, ipDe, leerJson, limpiarTexto, respuestaJson } from "../src/http.js";
import { limpiarCampos, registrar } from "../src/registro.js";

describe("cargarConfig", () => {
  it("sin variables usa los valores por defecto y los modelos candidatos", () => {
    const c = cargarConfig({});
    expect(c.modeloChat).toBe("claude-haiku-5-5");
    expect(c.modeloFoto).toBe("claude-sonnet-5-5");
    expect(c.limites).toEqual({
      chatPorDia: POR_DEFECTO.chatPorDia,
      fotoPorDia: POR_DEFECTO.fotoPorDia,
      lugarPorDia: POR_DEFECTO.lugarPorDia,
      porIpPorHora: POR_DEFECTO.porIpPorHora,
    });
    expect(c.presupuestoDiarioMicroUsd).toBe(5_000_000);
    expect(c.bloqueoTotal).toBe(false);
    expect(c.produccion).toBe(false);
  });

  it("lee las variables de entorno", () => {
    const c = cargarConfig({
      VERCEL_ENV: "production", MODELO_CHAT: "otro-modelo", LIMITE_CHAT_DIA: "5", LIMITE_FOTO_DIA: "2",
      PRESUPUESTO_DIARIO_USD: "1.5", BLOQUEO_TOTAL: "1", ID_PEPPER: "x".repeat(20), NOMINATIM_CONTACTO: "a@b.co",
    });
    expect(c.produccion).toBe(true);
    expect(c.modeloChat).toBe("otro-modelo");
    expect(c.limites.chatPorDia).toBe(5);
    expect(c.limites.fotoPorDia).toBe(2);
    expect(c.presupuestoDiarioMicroUsd).toBe(1_500_000);
    expect(c.bloqueoTotal).toBe(true);
    expect(c.contactoNominatim).toBe("a@b.co");
  });

  it("valores inválidos caen al por defecto en vez de romper o dejar sin límite", () => {
    const c = cargarConfig({ LIMITE_CHAT_DIA: "abc", LIMITE_FOTO_DIA: "-3", LIMITE_IP_HORA: "1.5", PRESUPUESTO_DIARIO_USD: "NaN" });
    expect(c.limites.chatPorDia).toBe(POR_DEFECTO.chatPorDia);
    expect(c.limites.fotoPorDia).toBe(POR_DEFECTO.fotoPorDia);
    expect(c.limites.porIpPorHora).toBe(POR_DEFECTO.porIpPorHora);
    expect(c.presupuestoDiarioMicroUsd).toBe(5_000_000);
  });

  it("BLOQUEO_TOTAL solo se activa con exactamente '1'", () => {
    expect(cargarConfig({ BLOQUEO_TOTAL: "true" }).bloqueoTotal).toBe(false);
    expect(cargarConfig({ BLOQUEO_TOTAL: "1" }).bloqueoTotal).toBe(true);
  });

  it("en producción sin pepper (o muy corto) NO hay pepper: es error de configuración", () => {
    expect(pepperEfectivo(cargarConfig({ VERCEL_ENV: "production" }))).toBeNull();
    expect(pepperEfectivo(cargarConfig({ VERCEL_ENV: "production", ID_PEPPER: "corto" }))).toBeNull();
    expect(pepperEfectivo(cargarConfig({ VERCEL_ENV: "production", ID_PEPPER: "a".repeat(16) }))).toBe("a".repeat(16));
  });

  it("fuera de producción usa un pepper de desarrollo", () => {
    expect(pepperEfectivo(cargarConfig({}))).toBeTruthy();
  });
});

describe("respuestas HTTP", () => {
  it("nunca se guardan en caché y son JSON", async () => {
    const r = respuestaJson({ a: 1 });
    expect(r.headers.get("cache-control")).toBe("no-store");
    expect(r.headers.get("content-type")).toContain("application/json");
    expect(await r.json()).toEqual({ a: 1 });
  });

  it("errorHttp usa el formato estándar y Retry-After redondeado hacia arriba (mínimo 1)", async () => {
    const r = errorHttp(429, "limite_dia", "Vuelva mañana.", { reintentarEnSeg: 12.2 });
    expect(r.status).toBe(429);
    expect(r.headers.get("retry-after")).toBe("13");
    expect(await r.json()).toEqual({ error: { codigo: "limite_dia", mensaje: "Vuelva mañana." } });
    expect(errorHttp(503, "x", "y", { reintentarEnSeg: 0 }).headers.get("retry-after")).toBe("1");
    expect(errorHttp(400, "x", "y").headers.get("retry-after")).toBeNull();
  });
});

const peticion = (cuerpo: RequestInit["body"], cabeceras: Record<string, string> = { "content-type": "application/json" }) =>
  new Request("https://x.example/api", { method: "POST", headers: cabeceras, body: cuerpo });

describe("leerJson", () => {
  it("lee un JSON válido", async () => {
    const l = await leerJson(peticion('{"a":1}'), 1000);
    expect(l).toEqual({ ok: true, valor: { a: 1 } });
  });

  it("exige Content-Type JSON (415)", async () => {
    const l = await leerJson(peticion("{}", { "content-type": "text/plain" }), 1000);
    expect(l.ok).toBe(false);
    if (!l.ok) expect(l.respuesta.status).toBe(415);
  });

  it("rechaza con 413 un cuerpo que supera el límite aunque no declare tamaño", async () => {
    const grande = JSON.stringify({ x: "a".repeat(5000) });
    const l = await leerJson(peticion(grande), 1000);
    expect(l.ok).toBe(false);
    if (!l.ok) expect(l.respuesta.status).toBe(413);
  });

  it("rechaza con 413 si Content-Length declara más del límite, sin leer el cuerpo", async () => {
    const l = await leerJson(peticion("{}", { "content-type": "application/json", "content-length": "99999" }), 1000);
    expect(l.ok).toBe(false);
    if (!l.ok) expect(l.respuesta.status).toBe(413);
  });

  it("un cuerpo justo en el límite pasa", async () => {
    const t = JSON.stringify({ x: "a".repeat(100) });
    const l = await leerJson(peticion(t), new TextEncoder().encode(t).length);
    expect(l.ok).toBe(true);
  });

  it("JSON roto y UTF-8 inválido dan 400", async () => {
    for (const cuerpo of ["{no es json", new Uint8Array([0x7b, 0x22, 0xff, 0x22, 0x3a, 0x31, 0x7d])]) {
      const l = await leerJson(peticion(cuerpo as RequestInit["body"]), 1000);
      expect(l.ok).toBe(false);
      if (!l.ok) expect(l.respuesta.status).toBe(400);
    }
  });

  it("sin cuerpo da 400", async () => {
    const l = await leerJson(new Request("https://x.example", { method: "POST", headers: { "content-type": "application/json" } }), 1000);
    expect(l.ok).toBe(false);
    if (!l.ok) expect(l.respuesta.status).toBe(400);
  });
});

describe("ipDe y limpiarTexto", () => {
  it("usa x-real-ip, o la primera de x-forwarded-for, o 'desconocida'", () => {
    const h = (o: Record<string, string>) => new Request("https://x.example", { headers: o });
    expect(ipDe(h({ "x-real-ip": "1.2.3.4", "x-forwarded-for": "9.9.9.9" }))).toBe("1.2.3.4");
    expect(ipDe(h({ "x-forwarded-for": "5.6.7.8, 10.0.0.1" }))).toBe("5.6.7.8");
    expect(ipDe(h({}))).toBe("desconocida");
  });

  it("quita caracteres de control y neutraliza < y >", () => {
    expect(limpiarTexto("  hola\u0000 </material> <x>  ")).toBe("hola ‹/material‹ ‹x‹");
    expect(limpiarTexto("línea1\nlínea2\ttab")).toBe("línea1\nlínea2\ttab");
  });
});

describe("registro sin datos personales", () => {
  it("solo deja pasar claves permitidas con valores técnicos", () => {
    const l = limpiarCampos({
      endpoint: "chat", codigo: "limite_dia", estado: 429, ms: 120, modelo: "claude-haiku-5-5",
      tokens_in: 1500, tokens_out: 200, costo_micro_usd: 290,
    });
    expect(Object.keys(l).sort()).toEqual(["codigo", "costo_micro_usd", "endpoint", "estado", "modelo", "ms", "tokens_in", "tokens_out"]);
  });

  it("descarta claves no permitidas (mensaje, id, ip, imagen...)", () => {
    const l = limpiarCampos({ mensaje: "¿cómo voltear?", installId: "abc", ip: "1.2.3.4", imagen: "AAAA", codigo: "ok" });
    expect(l).toEqual({ codigo: "ok" });
  });

  it("descarta valores que parecen texto libre aunque la clave sea permitida", () => {
    const l = limpiarCampos({ codigo: "Mi finca queda en la vereda X", endpoint: "chat con espacios", estado: Number.NaN });
    expect(l).toEqual({});
  });

  it("la línea escrita es JSON sin ningún dato del usuario", () => {
    const lineas: string[] = [];
    registrar("error", "fallo_ia", { endpoint: "analizar-foto", codigo: "ia_no_disponible", estado: 502, mensaje: "texto privado", installId: "u-123" }, (l) => lineas.push(l));
    expect(lineas).toHaveLength(1);
    expect(lineas[0]).not.toContain("privado");
    expect(lineas[0]).not.toContain("u-123");
    expect(JSON.parse(lineas[0]!)).toEqual({ nivel: "error", evento: "fallo_ia", endpoint: "analizar-foto", codigo: "ia_no_disponible", estado: 502 });
  });

  it("un nombre de evento raro no se registra tal cual", () => {
    const lineas: string[] = [];
    registrar("info", "Evento con Datos Personales", {}, (l) => lineas.push(l));
    expect(JSON.parse(lineas[0]!).evento).toBe("evento_invalido");
  });
});
