import { describe, expect, it } from "vitest";
import { crearAlmacenDesdeEntorno, MemoriaAlmacen, UpstashAlmacen } from "../src/almacen.js";
import { cargarConfig } from "../src/config.js";
import { costoMicroUsd, tokensDeImagen } from "../src/costos.js";
import { anonimizar, idValido } from "../src/instalacion.js";
import { diaColombia, registrarGasto, segundosHastaMedianoche, verificarLimites } from "../src/limites.js";

describe("ID de instalación", () => {
  it("acepta un UUID v4 y rechaza todo lo demás", () => {
    expect(idValido("3f2b8c1e-9d4a-4b7e-8a1c-0e5d6f7a8b9c")).toBe(true);
    expect(idValido("3F2B8C1E-9D4A-4B7E-8A1C-0E5D6F7A8B9C")).toBe(true);
    for (const malo of ["", "hola", "3f2b8c1e-9d4a-1b7e-8a1c-0e5d6f7a8b9c", "3f2b8c1e9d4a4b7e8a1c0e5d6f7a8b9c", 123, null, undefined, {}, "a".repeat(500)]) {
      expect(idValido(malo)).toBe(false);
    }
  });

  it("anonimizar es estable, depende del secreto y no deja el original", () => {
    const id = "3f2b8c1e-9d4a-4b7e-8a1c-0e5d6f7a8b9c";
    const a = anonimizar("secreto-uno-largo-123", id);
    expect(a).toMatch(/^[0-9a-f]{32}$/);
    expect(anonimizar("secreto-uno-largo-123", id)).toBe(a);
    expect(anonimizar("secreto-dos-largo-456", id)).not.toBe(a);
    expect(a).not.toContain(id.slice(0, 8));
  });
});

describe("MemoriaAlmacen", () => {
  it("suma, vence y empieza de nuevo", async () => {
    let t = 1_000;
    const m = new MemoriaAlmacen(() => t);
    expect(await m.sumar("c", 1, 10)).toBe(1);
    expect(await m.sumar("c", 4, 10)).toBe(5);
    expect(await m.leerNumero("c")).toBe(5);
    t += 10_001;
    expect(await m.leerNumero("c")).toBe(0);
    expect(await m.sumar("c", 1, 10)).toBe(1);
  });

  it("el vencimiento se fija al crear el contador y no se renueva al sumar", async () => {
    let t = 0;
    const m = new MemoriaAlmacen(() => t);
    await m.sumar("c", 1, 10);
    t = 9_000;
    await m.sumar("c", 1, 10);
    t = 10_001;
    expect(await m.leerNumero("c")).toBe(0);
  });

  it("el cerrojo es exclusivo hasta que vence", async () => {
    let t = 0;
    const m = new MemoriaAlmacen(() => t);
    expect(await m.tomarCerrojo("k", 1100)).toBe(true);
    expect(await m.tomarCerrojo("k", 1100)).toBe(false);
    t = 1101;
    expect(await m.tomarCerrojo("k", 1100)).toBe(true);
  });

  it("guardar y obtener con vencimiento", async () => {
    let t = 0;
    const m = new MemoriaAlmacen(() => t);
    await m.guardar("a", "valor", 5);
    expect(await m.obtener("a")).toBe("valor");
    t = 5_001;
    expect(await m.obtener("a")).toBeNull();
    expect(await m.obtener("nunca")).toBeNull();
  });
});

describe("UpstashAlmacen (con fetch simulado)", () => {
  function falso(respuestas: Array<unknown | Error | { status: number }>) {
    const llamadas: Array<{ url: string; cuerpo: unknown; auth: string | null }> = [];
    let i = 0;
    const f = (async (url: string, init: RequestInit) => {
      llamadas.push({ url, cuerpo: JSON.parse(String(init.body)), auth: new Headers(init.headers).get("authorization") });
      const r = respuestas[i++];
      if (r instanceof Error) throw r;
      if (r && typeof r === "object" && "status" in r) return new Response("{}", { status: (r as { status: number }).status });
      return new Response(JSON.stringify(r), { status: 200 });
    }) as unknown as typeof fetch;
    return { f, llamadas };
  }
  const nuevo = (f: typeof fetch) => new UpstashAlmacen("https://redis.example.io", "TOKEN-SECRETO", f);

  it("sumar manda INCRBY + EXPIRE NX en un solo pipeline, con el token en la cabecera", async () => {
    const { f, llamadas } = falso([[{ result: 7 }, { result: 1 }]]);
    expect(await nuevo(f).sumar("k", 3, 60)).toBe(7);
    expect(llamadas[0]).toEqual({
      url: "https://redis.example.io/pipeline",
      cuerpo: [["INCRBY", "k", 3], ["EXPIRE", "k", 60, "NX"]],
      auth: "Bearer TOKEN-SECRETO",
    });
  });

  it("tomarCerrojo usa SET PX NX y distingue OK de null", async () => {
    const { f, llamadas } = falso([{ result: "OK" }, { result: null }]);
    const a = nuevo(f);
    expect(await a.tomarCerrojo("k", 1100)).toBe(true);
    expect(await a.tomarCerrojo("k", 1100)).toBe(false);
    expect(llamadas[0]?.cuerpo).toEqual(["SET", "k", "1", "PX", 1100, "NX"]);
  });

  it("guardar usa SET EX; obtener y leerNumero usan GET", async () => {
    const { f, llamadas } = falso([{ result: "OK" }, { result: "Chinácota" }, { result: "42" }, { result: null }]);
    const a = nuevo(f);
    await a.guardar("l", "Chinácota", 100);
    expect(await a.obtener("l")).toBe("Chinácota");
    expect(await a.leerNumero("g")).toBe(42);
    expect(await a.leerNumero("g")).toBe(0);
    expect(llamadas[0]?.cuerpo).toEqual(["SET", "l", "Chinácota", "EX", 100]);
    expect(llamadas[1]?.cuerpo).toEqual(["GET", "l"]);
  });

  it("los errores no revelan la URL ni el token", async () => {
    for (const r of [new Error("fallo de red https://redis.example.io TOKEN-SECRETO"), { status: 401 }, { error: "WRONGPASS TOKEN-SECRETO" }]) {
      const { f } = falso([r]);
      const e = await nuevo(f).obtener("k").catch((x: Error) => x);
      expect(e).toBeInstanceOf(Error);
      expect((e as Error).message).not.toContain("TOKEN-SECRETO");
      expect((e as Error).message).not.toContain("redis.example.io");
    }
  });

  it("sumar con respuesta rara falla en vez de devolver un número inventado", async () => {
    const { f } = falso([[{ error: "x" }, { result: 1 }]]);
    await expect(nuevo(f).sumar("k", 1, 5)).rejects.toThrow("almacen_error");
  });
});

describe("crearAlmacenDesdeEntorno", () => {
  it("con credenciales https usa Upstash (cualquiera de los dos pares de nombres)", () => {
    expect(crearAlmacenDesdeEntorno({ UPSTASH_REDIS_REST_URL: "https://a.io", UPSTASH_REDIS_REST_TOKEN: "t" })).toBeInstanceOf(UpstashAlmacen);
    expect(crearAlmacenDesdeEntorno({ KV_REST_API_URL: "https://a.io", KV_REST_API_TOKEN: "t" })).toBeInstanceOf(UpstashAlmacen);
  });

  it("sin credenciales: memoria fuera de producción, y NADA (null) en producción", () => {
    expect(crearAlmacenDesdeEntorno({})).toBeInstanceOf(MemoriaAlmacen);
    expect(crearAlmacenDesdeEntorno({ VERCEL_ENV: "production" })).toBeNull();
  });

  it("una URL que no es https no se acepta (y en producción queda en null)", () => {
    expect(crearAlmacenDesdeEntorno({ VERCEL_ENV: "production", UPSTASH_REDIS_REST_URL: "http://a.io", UPSTASH_REDIS_REST_TOKEN: "t" })).toBeNull();
  });
});

describe("costos (precios oficiales leídos el 2026-11-18)", () => {
  it("Haiku 5.5 hasta 100.000 tokens: 0,10 de entrada y 0,50 de salida por millón", () => {
    expect(costoMicroUsd("claude-haiku-5-5", { tokensEntrada: 1600, tokensSalida: 250 })).toBe(160 + 125);
  });

  it("Haiku 5.5 con prompt de más de 100.000 tokens paga el precio alto en TODA la petición", () => {
    expect(costoMicroUsd("claude-haiku-5-5", { tokensEntrada: 100_001, tokensSalida: 100 })).toBe(Math.ceil(100_001 * 0.5 + 100 * 2.5));
    expect(costoMicroUsd("claude-haiku-5-5", { tokensEntrada: 100_000, tokensSalida: 100 })).toBe(Math.ceil(100_000 * 0.1 + 100 * 0.5));
  });

  it("Sonnet 5.5: 2 de entrada y 10 de salida por millón; caché 2,5 (escribir) y 0,10 (leer)", () => {
    expect(costoMicroUsd("claude-sonnet-5-5", { tokensEntrada: 1750, tokensSalida: 500 })).toBe(3500 + 5000);
    expect(costoMicroUsd("claude-sonnet-5-5", { tokensEntrada: 0, tokensSalida: 0, tokensEscrituraCache: 1000, tokensLecturaCache: 1000 })).toBe(2500 + 100);
  });

  it("un modelo desconocido se cobra al precio más alto (el tope nunca subestima)", () => {
    expect(costoMicroUsd("modelo-nuevo", { tokensEntrada: 1000, tokensSalida: 1000 })).toBeGreaterThan(costoMicroUsd("claude-sonnet-5-5", { tokensEntrada: 1000, tokensSalida: 1000 }));
  });

  it("redondea hacia arriba y nunca da negativo ni NaN", () => {
    expect(costoMicroUsd("claude-haiku-5-5", { tokensEntrada: 1, tokensSalida: 0 })).toBe(1);
    expect(costoMicroUsd("claude-haiku-5-5", { tokensEntrada: 0, tokensSalida: 0 })).toBe(0);
  });

  it("tokens de imagen: ⌈ancho/28⌉ × ⌈alto/28⌉ (valores de la documentación)", () => {
    expect(tokensDeImagen(1000, 1000)).toBe(1296);
    expect(tokensDeImagen(200, 200)).toBe(64);
    expect(tokensDeImagen(1092, 1092)).toBe(1521);
    expect(tokensDeImagen(1024, 768)).toBe(1036);
  });
});

describe("día de Colombia", () => {
  it("la medianoche de Colombia es a las 05:00 UTC", () => {
    expect(diaColombia(new Date("2026-11-18T04:59:59Z"))).toBe("2026-11-17");
    expect(diaColombia(new Date("2026-11-18T05:00:00Z"))).toBe("2026-11-18");
  });

  it("segundos hasta la medianoche", () => {
    expect(segundosHastaMedianoche(new Date("2026-11-18T04:00:00Z"))).toBe(3600);
    expect(segundosHastaMedianoche(new Date("2026-11-18T05:00:00Z"))).toBe(86_400);
  });
});

describe("verificarLimites", () => {
  const cfg = cargarConfig({ LIMITE_CHAT_DIA: "3", LIMITE_FOTO_DIA: "2", LIMITE_LUGAR_DIA: "4", LIMITE_IP_HORA: "10", PRESUPUESTO_DIARIO_USD: "1" });
  const base = (almacen: MemoriaAlmacen, extra: Record<string, unknown> = {}) => ({
    almacen, cfg, idHash: "dispositivo-1", ipHash: "ip-1", tipo: "chat" as const, ahora: new Date("2026-11-18T15:00:00Z"), ...extra,
  });

  it("deja pasar hasta el límite y bloquea justo en el intento siguiente", async () => {
    const a = new MemoriaAlmacen();
    for (let i = 0; i < 3; i++) expect((await verificarLimites(base(a))).ok).toBe(true);
    const r = await verificarLimites(base(a));
    expect(r.ok).toBe(false);
    if (!r.ok) {
      expect([r.estado, r.codigo]).toEqual([429, "limite_dia"]);
      expect(r.reintentarEnSeg).toBe(segundosHastaMedianoche(new Date("2026-11-18T15:00:00Z")));
    }
  });

  it("cada dispositivo y cada tipo tiene su propio contador", async () => {
    const a = new MemoriaAlmacen();
    for (let i = 0; i < 4; i++) await verificarLimites(base(a));
    expect((await verificarLimites(base(a, { idHash: "dispositivo-2", ipHash: "ip-2" }))).ok).toBe(true);
    expect((await verificarLimites(base(a, { tipo: "foto" }))).ok).toBe(true);
  });

  it("al cambiar el día en Colombia el contador del dispositivo empieza de nuevo", async () => {
    const a = new MemoriaAlmacen();
    const noche = new Date("2026-11-19T04:30:00Z"); // 23:30 del 18 en Colombia
    for (let i = 0; i < 4; i++) await verificarLimites(base(a, { ahora: noche }));
    expect((await verificarLimites(base(a, { ahora: noche }))).ok).toBe(false);
    expect((await verificarLimites(base(a, { ahora: new Date("2026-11-19T05:30:00Z"), ipHash: "ip-nueva" }))).ok).toBe(true);
  });

  it("el límite por IP actúa aunque se cambie de ID de instalación (ID falsos)", async () => {
    const a = new MemoriaAlmacen();
    let bloqueado: string | undefined;
    for (let i = 0; i < 12; i++) {
      const r = await verificarLimites(base(a, { idHash: `falso-${i}` }));
      if (!r.ok) {
        bloqueado = r.codigo;
        break;
      }
    }
    expect(bloqueado).toBe("limite_ip");
  });

  it("el tope de gasto del día bloquea chat y foto pero NO el nombre de lugar", async () => {
    const a = new MemoriaAlmacen();
    const ahora = new Date("2026-11-18T15:00:00Z");
    await registrarGasto(a, 1_000_000, ahora);
    const chat = await verificarLimites(base(a, { ahora }));
    expect(chat.ok).toBe(false);
    if (!chat.ok) expect([chat.estado, chat.codigo]).toEqual([503, "presupuesto_agotado"]);
    expect((await verificarLimites(base(a, { ahora, tipo: "lugar" }))).ok).toBe(true);
  });

  it("justo por debajo del tope todavía deja pasar", async () => {
    const a = new MemoriaAlmacen();
    const ahora = new Date("2026-11-18T15:00:00Z");
    await registrarGasto(a, 999_999, ahora);
    expect((await verificarLimites(base(a, { ahora }))).ok).toBe(true);
  });

  it("el gasto de ayer no cuenta hoy", async () => {
    const a = new MemoriaAlmacen();
    await registrarGasto(a, 5_000_000, new Date("2026-11-17T15:00:00Z"));
    expect((await verificarLimites(base(a, { ahora: new Date("2026-11-18T15:00:00Z") }))).ok).toBe(true);
  });

  it("el interruptor de emergencia pausa chat y foto, no el lugar", async () => {
    const a = new MemoriaAlmacen();
    const c = cargarConfig({ BLOQUEO_TOTAL: "1" });
    const r = await verificarLimites({ ...base(a), cfg: c });
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.codigo).toBe("servicio_pausado");
    expect((await verificarLimites({ ...base(a), cfg: c, tipo: "lugar" })).ok).toBe(true);
  });

  it("si el almacén falla, el error sube (quien llama debe rechazar la petición, no dejarla pasar)", async () => {
    const roto = { sumar: async () => { throw new Error("almacen_sin_conexion"); } } as unknown as MemoriaAlmacen;
    await expect(verificarLimites(base(roto))).rejects.toThrow("almacen_sin_conexion");
  });

  it("registrarGasto ignora montos cero o negativos y redondea hacia arriba", async () => {
    const a = new MemoriaAlmacen();
    const ahora = new Date("2026-11-18T15:00:00Z");
    await registrarGasto(a, 0, ahora);
    await registrarGasto(a, -5, ahora);
    await registrarGasto(a, 10.2, ahora);
    expect(await a.leerNumero("gasto:2026-11-18")).toBe(11);
  });
});
