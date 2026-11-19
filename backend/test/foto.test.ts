import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { AVISO_FOTO, crearFoto, ENLACE_O_CONTACTO, EsquemaFoto, validarResultado, type ResultadoIA } from "../src/foto.js";
import { costoMicroUsd } from "../src/costos.js";
import { bloquesEjemplos, ErrorIA, type ClienteIA, type RespuestaEstructurada } from "../src/ia.js";
import { CATEGORIAS, NOTA_EJEMPLOS, sistemaFoto, type ModoFoto } from "../src/prompts.js";
import { deps, ID_A, post } from "./ayudas.js";
import { conSegmentos, EXIF_CON_GPS, FIXTURE, seg } from "./jpeg.test.js";

const USO = { tokensEntrada: 1750, tokensSalida: 500, tokensEscrituraCache: 0, tokensLecturaCache: 0 };

const bueno = (modo: ModoFoto = "corte"): ResultadoIA => ({
  foto_valida: true, motivo_foto_no_valida: "ninguno",
  categorias: [{ nombre: CATEGORIAS[modo][0]!, porcentaje: 70 }, { nombre: CATEGORIAS[modo][1]!, porcentaje: 30 }],
  confianza: "media", posibles_causas: ["Fermentación completa"], pasos_recomendados: ["Pase a secado"], semaforo: "verde",
});

class IAFalsa implements ClienteIA {
  llamadas: Array<Parameters<ClienteIA["analizarImagen"]>[0]> = [];
  constructor(public salida: RespuestaEstructurada<unknown> | Error = { valor: bueno(), uso: USO, parada: "fin" }) {}
  async responder(): Promise<never> {
    throw new Error("no se usa en fotos");
  }
  async analizarImagen<T>(p: Parameters<ClienteIA["analizarImagen"]>[0]): Promise<RespuestaEstructurada<T>> {
    this.llamadas.push(p);
    if (this.salida instanceof Error) throw this.salida;
    return this.salida as RespuestaEstructurada<T>;
  }
}

const peticion = (jpg: Buffer = FIXTURE, extra: Record<string, unknown> = {}, modo: ModoFoto = "corte") =>
  post({ modo, imagen: jpg.toString("base64"), ...extra });

/** Copia del JPEG con otro tamaño escrito en su SOF (el limpiador solo lee el tamaño, no decodifica). */
function conTamano(jpg: Buffer, ancho: number, alto: number): Buffer {
  const b = Buffer.from(jpg);
  let i = 2;
  while (b[i + 1] !== 0xc0) i += 2 + b.readUInt16BE(i + 2);
  b.writeUInt16BE(alto, i + 5);
  b.writeUInt16BE(ancho, i + 7);
  return b;
}

let lineas: string[];
beforeEach(() => {
  lineas = [];
  vi.spyOn(console, "log").mockImplementation((l: string) => void lineas.push(String(l)));
  vi.spyOn(console, "error").mockImplementation((l: string) => void lineas.push(String(l)));
});
afterEach(() => vi.restoreAllMocks());

describe("validarResultado (lo que devuelve la IA nunca se entrega sin revisar)", () => {
  it("un resultado bueno pasa, con los porcentajes redondeados", () => {
    const r = validarResultado("corte", { ...bueno(), categorias: [{ nombre: "bien_fermentado", porcentaje: 69.6 }, { nombre: "violeta", porcentaje: 30.2 }] })!;
    expect(r.categorias).toEqual([{ nombre: "bien_fermentado", porcentaje: 70 }, { nombre: "violeta", porcentaje: 30 }]);
    expect([r.repetir_foto, r.foto_valida, r.aviso]).toEqual([false, true, AVISO_FOTO]);
  });

  it("foto no válida: NO hay porcentajes, se pide otra foto con el motivo", () => {
    const r = validarResultado("corte", { ...bueno(), foto_valida: false, motivo_foto_no_valida: "borrosa" })!;
    expect(r.repetir_foto).toBe(true);
    expect(r.categorias).toEqual([]);
    expect(r.motivo).toBe("borrosa");
    expect(r.mensaje).toContain("borrosa");
    expect(r.semaforo).toBe("amarillo");
  });

  it("foto no válida sin motivo: se usa 'otro' (nunca queda sin explicar)", () => {
    const r = validarResultado("corte", { ...bueno(), foto_valida: false, motivo_foto_no_valida: "ninguno" })!;
    expect(r.motivo).toBe("otro");
    expect(r.mensaje).not.toBe("");
  });

  it("confianza BAJA aunque la foto sea válida: no se adivina, se pide otra foto y no hay porcentajes", () => {
    const r = validarResultado("corte", { ...bueno(), confianza: "baja" })!;
    expect(r.repetir_foto).toBe(true);
    expect(r.categorias).toEqual([]);
    expect(r.confianza).toBe("baja");
    expect(r.semaforo).toBe("amarillo");
  });

  it("la IA dice que la foto no es cacao: se pide otra con ese motivo", () => {
    const r = validarResultado("mazorca_hoja", { ...bueno("mazorca_hoja"), foto_valida: false, motivo_foto_no_valida: "no_es_cacao", categorias: [] })!;
    expect(r.mensaje).toContain("no se ve cacao");
  });

  const invalidos: Array<[string, Partial<ResultadoIA>]> = [
    ["una categoría que no existe en este modo", { categorias: [{ nombre: "inventada", porcentaje: 100 }] }],
    ["una categoría de OTRO modo", { categorias: [{ nombre: "monilia", porcentaje: 100 }] }],
    ["categorías repetidas", { categorias: [{ nombre: "violeta", porcentaje: 50 }, { nombre: "violeta", porcentaje: 50 }] }],
    ["porcentajes que suman poco", { categorias: [{ nombre: "violeta", porcentaje: 40 }] }],
    ["porcentajes que suman mucho", { categorias: [{ nombre: "violeta", porcentaje: 80 }, { nombre: "moho", porcentaje: 80 }] }],
    ["un porcentaje negativo", { categorias: [{ nombre: "violeta", porcentaje: 120 }, { nombre: "moho", porcentaje: -20 }] }],
    ["un porcentaje que no es número", { categorias: [{ nombre: "violeta", porcentaje: Number.NaN }] }],
    ["foto válida sin ninguna categoría", { categorias: [] }],
  ];
  it.each(invalidos)("rechaza (null) %s", (_n, cambio) => {
    expect(validarResultado("corte", { ...bueno(), ...cambio })).toBeNull();
  });

  it("suma 90 y 110 todavía se aceptan (estimaciones visuales); 89 y 111 no", () => {
    for (const [total, ok] of [[90, true], [110, true], [89, false], [111, false]] as const) {
      const categorias = [{ nombre: "bien_fermentado", porcentaje: total - 40 }, { nombre: "violeta", porcentaje: 40 }];
      expect(validarResultado("corte", { ...bueno(), categorias }) !== null, `suma ${total}`).toBe(ok);
    }
  });

  it("recorta las listas a 5 elementos de 300 caracteres y descarta los vacíos", () => {
    const r = validarResultado("corte", { ...bueno(), posibles_causas: ["a".repeat(500), "", "  ", "b", "c", "d", "e", "f"], pasos_recomendados: [] })!;
    expect(r.posibles_causas).toHaveLength(5);
    expect(r.posibles_causas[0]!.length).toBe(300);
    expect(r.pasos_recomendados).toEqual([]);
  });

  it("cada modo acepta sus propias categorías", () => {
    for (const modo of ["corte", "grano_seco", "mazorca_hoja"] as const) {
      expect(validarResultado(modo, bueno(modo)), modo).not.toBeNull();
    }
  });

  it("el esquema que se le pide a la IA es sencillo y lo valida zod", () => {
    expect(EsquemaFoto.safeParse(bueno()).success).toBe(true);
    expect(EsquemaFoto.safeParse({ ...bueno(), semaforo: "azul" }).success).toBe(false);
  });
});

describe("prompt de la foto", () => {
  it("lista SOLO las categorías del modo y dice que no se adivine ni se den agroquímicos", () => {
    const s = sistemaFoto("corte");
    for (const c of CATEGORIAS.corte) expect(s).toContain(c);
    expect(s).not.toContain("monilia");
    expect(s).toContain("NO adivines");
    expect(s).toContain("No recetes dosis");
    expect(s).toContain("FEDECACAO");
  });
});

describe("POST /analizar-foto", () => {
  it("devuelve el resultado validado con el aviso obligatorio; usa Sonnet 5.5 con el prompt del modo y un tope de 4000 tokens", async () => {
    const ia = new IAFalsa();
    const r = await crearFoto({ ...deps(), ia })(peticion());
    expect(r.status).toBe(200);
    const j = (await r.json()) as { categorias: unknown[]; aviso: string; modo: string; repetir_foto: boolean };
    expect(j.modo).toBe("corte");
    expect(j.repetir_foto).toBe(false);
    expect(j.categorias).toHaveLength(2);
    expect(j.aviso).toBe("Estimación orientativa. La clasificación oficial es la prueba de corte de la NTC 1252. Ante duda, consulte al técnico.");
    expect(ia.llamadas[0]!.modelo).toBe("claude-sonnet-5-5");
    expect(ia.llamadas[0]!.sistema).toBe(sistemaFoto("corte"));
    expect(ia.llamadas[0]!.maxTokens).toBe(4000);
  });

  it("a la IA le llega la imagen LIMPIA: sin EXIF, sin GPS", async () => {
    const conGps = conSegmentos(FIXTURE, [EXIF_CON_GPS, seg(0xfe, "finca de Luis")]);
    expect(conGps.includes(Buffer.from("GPSLatitude"))).toBe(true);
    const ia = new IAFalsa();
    const r = await crearFoto({ ...deps(), ia })(peticion(conGps));
    expect(r.status).toBe(200);
    const enviada = Buffer.from(ia.llamadas[0]!.imagenBase64, "base64");
    for (const secreto of ["GPS", "Exif", "7.603112", "finca de Luis"]) expect(enviada.includes(Buffer.from(secreto)), secreto).toBe(false);
  });

  it("también funciona con grano seco y mazorca/hoja", async () => {
    for (const modo of ["grano_seco", "mazorca_hoja"] as const) {
      const ia = new IAFalsa({ valor: bueno(modo), uso: USO, parada: "fin" });
      const r = await crearFoto({ ...deps(), ia })(peticion(FIXTURE, {}, modo));
      expect(r.status, modo).toBe(200);
      expect(ia.llamadas[0]!.sistema).toContain(CATEGORIAS[modo][0]!);
    }
  });

  it("foto mala: 200 con repetir_foto y sin porcentajes", async () => {
    const ia = new IAFalsa({ valor: { ...bueno(), foto_valida: false, motivo_foto_no_valida: "oscura" }, uso: USO, parada: "fin" });
    const j = (await (await crearFoto({ ...deps(), ia })(peticion())).json()) as { repetir_foto: boolean; categorias: unknown[]; mensaje: string };
    expect([j.repetir_foto, j.categorias]).toEqual([true, []]);
    expect(j.mensaje).toContain("oscura");
  });

  it("la IA se niega: 200 pidiendo otra foto y remitiendo al técnico (no es un error)", async () => {
    const j = (await (await crearFoto({ ...deps(), ia: new IAFalsa({ valor: null, uso: USO, parada: "rechazo" }) })(peticion())).json()) as { repetir_foto: boolean; pasos_recomendados: string[] };
    expect(j.repetir_foto).toBe(true);
    expect(j.pasos_recomendados.join(" ")).toContain("técnico");
  });

  it("respuesta de la IA que no cumple el esquema o es incoherente: 502, no se entrega", async () => {
    for (const salida of [
      { valor: null, uso: USO, parada: "fin" as const },
      { valor: { ...bueno(), categorias: [{ nombre: "inventada", porcentaje: 100 }] }, uso: USO, parada: "fin" as const },
    ]) {
      const r = await crearFoto({ ...deps(), ia: new IAFalsa(salida) })(peticion());
      expect(r.status).toBe(502);
      expect(((await r.json()) as { error: { codigo: string } }).error.codigo).toBe("respuesta_ia_invalida");
    }
  });
});

describe("POST /analizar-foto: validación de la entrada", () => {
  const h = () => crearFoto({ ...deps(), ia: new IAFalsa() });
  const estado = async (r: Request) => (await h()(r)).status;

  it("modo desconocido, sin imagen, base64 inválido o campos extra (ubicación...): 400", async () => {
    expect(await estado(post({ modo: "otro", imagen: FIXTURE.toString("base64") }))).toBe(400);
    expect(await estado(post({ modo: "corte" }))).toBe(400);
    expect(await estado(post({ modo: "corte", imagen: "esto no es base64 !!!".repeat(10) }))).toBe(400);
    expect(await estado(peticion(FIXTURE, { lat: 7.6, lng: -72.6 }))).toBe(400);
    expect(await estado(peticion(FIXTURE, { nombreLote: "x" }))).toBe(400);
  });

  it("un archivo que no es JPEG (PNG) o está dañado: 400", async () => {
    const png = Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), Buffer.alloc(300, 1)]);
    const r1 = await h()(peticion(png));
    expect(r1.status).toBe(400);
    expect(((await r1.json()) as { error: { codigo: string } }).error.codigo).toBe("imagen_no_jpeg");
    const r2 = await h()(peticion(FIXTURE.subarray(0, 300)));
    expect(r2.status).toBe(400);
    expect(((await r2.json()) as { error: { codigo: string } }).error.codigo).toBe("imagen_danada");
  });

  it("tamaño de la foto: de 200 a 1600 px por el lado largo", async () => {
    expect(await estado(peticion(conTamano(FIXTURE, 1024, 768)))).toBe(200);
    expect(await estado(peticion(conTamano(FIXTURE, 1600, 1200)))).toBe(200);
    expect(await estado(peticion(conTamano(FIXTURE, 200, 150)))).toBe(200);
    expect(await estado(peticion(conTamano(FIXTURE, 1601, 1200)))).toBe(413);
    expect(await estado(peticion(conTamano(FIXTURE, 4000, 3000)))).toBe(413);
    expect(await estado(peticion(conTamano(FIXTURE, 199, 150)))).toBe(400);
  });

  it("imagen de más de 1,8 MB: 413; cuerpo de más de 2,6 MB: 413", async () => {
    const pesada = conSegmentos(FIXTURE, [seg(0xe1, Buffer.alloc(60_000)), seg(0xe5, Buffer.alloc(60_000))]);
    const enorme = Buffer.concat([pesada, Buffer.alloc(1_790_000)]);
    const r = await h()(peticion(enorme));
    expect(r.status).toBe(413);
    expect(((await r.json()) as { error: { codigo: string } }).error.codigo).toBe("imagen_muy_grande");
    const r2 = await h()(peticion(Buffer.concat([FIXTURE, Buffer.alloc(2_000_000)])));
    expect(r2.status).toBe(413);
  });

  it("solo POST, y con ID de instalación válido", async () => {
    expect((await h()(new Request("https://x.example/analizar-foto"))).status).toBe(405);
    expect((await h()(post({ modo: "corte", imagen: FIXTURE.toString("base64") }, null))).status).toBe(400);
  });
});

describe("POST /analizar-foto: límites, gasto, errores y privacidad", () => {
  it("cuenta el costo con los tokens reales de la respuesta (precios de Sonnet 5.5)", async () => {
    const d = deps({}, new Date("2026-11-18T15:00:00Z"));
    await crearFoto({ ...d, ia: new IAFalsa() })(peticion());
    expect(await d.almacen.leerNumero("gasto:2026-11-18")).toBe(costoMicroUsd("claude-sonnet-5-5", USO));
    expect(costoMicroUsd("claude-sonnet-5-5", USO)).toBe(8500); // $0,0085
  });

  it("al pasar el límite diario de fotos por dispositivo: 429 y no se llama a la IA", async () => {
    const ia = new IAFalsa();
    const h = crearFoto({ ...deps({ LIMITE_FOTO_DIA: "1" }), ia });
    expect((await h(peticion())).status).toBe(200);
    const r = await h(peticion());
    expect(r.status).toBe(429);
    expect(ia.llamadas).toHaveLength(1);
  });

  it("el límite de fotos es independiente del de chat", async () => {
    const h = crearFoto({ ...deps({ LIMITE_FOTO_DIA: "1", LIMITE_CHAT_DIA: "0" }), ia: new IAFalsa() });
    expect((await h(peticion())).status).toBe(200);
  });

  it("con el tope de gasto agotado o el interruptor de emergencia: 503 y no se llama a la IA", async () => {
    for (const env of [{ PRESUPUESTO_DIARIO_USD: "0" }, { BLOQUEO_TOTAL: "1" }] as Array<Record<string, string>>) {
      const ia = new IAFalsa();
      const r = await crearFoto({ ...deps(env), ia })(peticion());
      expect(r.status, JSON.stringify(env)).toBe(503);
      expect(ia.llamadas).toHaveLength(0);
    }
  });

  it.each([["ocupada", 503], ["no_disponible", 502], ["configuracion", 500]] as const)("ErrorIA %s → HTTP %i", async (tipo, estado) => {
    const r = await crearFoto({ ...deps(), ia: new IAFalsa(new ErrorIA(tipo)) })(peticion());
    expect(r.status).toBe(estado);
  });

  it("un error crudo con una clave dentro no sale en la respuesta ni en el registro", async () => {
    const r = await crearFoto({ ...deps(), ia: new IAFalsa(new Error("invalid x-api-key CLAVE-FALSA-SECRETO-123")) })(peticion());
    expect(await r.text()).not.toContain("SECRETO");
    expect(lineas.join("\n")).not.toContain("SECRETO");
  });

  it("la foto NO se guarda ni se registra: ni en el almacén ni en las líneas de registro", async () => {
    const d = deps();
    const conGps = conSegmentos(FIXTURE, [EXIF_CON_GPS]);
    const b64 = conGps.toString("base64");
    await crearFoto({ ...d, ia: new IAFalsa() })(post({ modo: "corte", imagen: b64 }));
    const todo = JSON.stringify(d.almacen.volcar()) + lineas.join("\n");
    expect(todo).not.toContain(b64.slice(200, 260));
    expect(todo).not.toContain(Buffer.from(FIXTURE).toString("base64").slice(300, 360));
    for (const secreto of [ID_A, "10.0.0.1", "GPSLatitude"]) expect(todo, secreto).not.toContain(secreto);
    for (const [clave] of d.almacen.volcar()) expect(clave).toMatch(/^(ip|dia|gasto):/);
  });

  it("el registro de la llamada tiene solo códigos y números", async () => {
    await crearFoto({ ...deps(), ia: new IAFalsa() })(peticion());
    const ok = lineas.map((l) => JSON.parse(l) as Record<string, unknown>).find((o) => o.evento === "foto_ok")!;
    expect(Object.keys(ok).sort()).toEqual(["costo_micro_usd", "endpoint", "estado", "evento", "modelo", "ms", "nivel", "tokens_in", "tokens_out"]);
  });
});

describe("POST /analizar-foto: ejemplos de referencia", () => {
  const ej = (n: number) => Array.from({ length: n }, (_, i) => ({ descripcion: `Ejemplo ${i + 1}`, imagenBase64: Buffer.from(`foto${i}`).toString("base64") }));

  it("por defecto (REFERENCIAS_POR_CLASE sin definir) NO se manda ningún ejemplo ni se leen del disco", async () => {
    const ia = new IAFalsa();
    let lecturas = 0;
    const r = await crearFoto({ ...deps(), ia, ejemplos: () => { lecturas++; return ej(3); } })(peticion());
    expect(r.status).toBe(200);
    expect(lecturas).toBe(0);
    expect(ia.llamadas[0]!.ejemplos).toEqual([]);
  });

  it("con REFERENCIAS_POR_CLASE=2 pide los ejemplos de ese modo con ese número y se los pasa a la IA", async () => {
    const ia = new IAFalsa({ valor: bueno("mazorca_hoja"), uso: USO, parada: "fin" });
    const pedidos: Array<[string, number]> = [];
    const r = await crearFoto({ ...deps({ REFERENCIAS_POR_CLASE: "2" }), ia, ejemplos: (m, n) => { pedidos.push([m, n]); return ej(2); } })(peticion(FIXTURE, {}, "mazorca_hoja"));
    expect(r.status).toBe(200);
    expect(pedidos).toEqual([["mazorca_hoja", 2]]);
    expect(ia.llamadas[0]!.ejemplos).toHaveLength(2);
  });

  it("valores inválidos de la variable (-1, 9, texto) se ignoran: queda en 0", async () => {
    for (const v of ["-1", "9", "mucho", "1.5"]) {
      expect(deps({ REFERENCIAS_POR_CLASE: v }).cfg.referenciasPorClase, v).toBe(0);
    }
    expect(deps({ REFERENCIAS_POR_CLASE: "5" }).cfg.referenciasPorClase).toBe(5);
  });

  it("si los ejemplos no se pueden leer: 500 servidor_mal_configurado y NO se llama a la IA (no se sigue en silencio)", async () => {
    const ia = new IAFalsa();
    const r = await crearFoto({ ...deps({ REFERENCIAS_POR_CLASE: "1" }), ia, ejemplos: () => { throw new Error("ENOENT /ruta/secreta"); } })(peticion());
    expect(r.status).toBe(500);
    expect(((await r.json()) as { error: { codigo: string } }).error.codigo).toBe("servidor_mal_configurado");
    expect(ia.llamadas).toHaveLength(0);
  });

  it("con los archivos reales: 4 clases × 1 ejemplo en corte, y grano seco no lleva ejemplos", async () => {
    const ia = new IAFalsa();
    await crearFoto({ ...deps({ REFERENCIAS_POR_CLASE: "1" }), ia })(peticion());
    await crearFoto({ ...deps({ REFERENCIAS_POR_CLASE: "1" }), ia })(peticion(FIXTURE, {}, "grano_seco"));
    expect(ia.llamadas[0]!.ejemplos).toHaveLength(4);
    expect(ia.llamadas[1]!.ejemplos).toEqual([]);
  });
});

describe("bloquesEjemplos (lo que ve la IA)", () => {
  it("sin ejemplos no agrega nada", () => expect(bloquesEjemplos([])).toEqual([]));

  it("nota, cada foto con su etiqueta, y un rótulo que separa la foto del productor", () => {
    const b = bloquesEjemplos([{ descripcion: "Grano violeta", imagenBase64: "QUJD" }, { descripcion: "Mazorca sana", imagenBase64: "REVG" }]);
    expect(b.map((x) => x.type)).toEqual(["text", "image", "text", "image", "text", "text"]);
    expect((b[0] as { text: string }).text).toBe(NOTA_EJEMPLOS);
    expect((b[2] as { text: string }).text).toBe("Ejemplo de referencia: Grano violeta");
    expect((b[5] as { text: string }).text).toContain("ÚNICA que debes analizar");
  });

  it("la nota dice que los ejemplos pueden ser distintos y que no se copie la etiqueta", () => {
    expect(NOTA_EJEMPLOS).toContain("No copies la etiqueta");
    expect(NOTA_EJEMPLOS).toContain("baja tu confianza");
  });
});

describe("texto libre de la IA: nunca llegan enlaces ni contactos al productor (inyección desde la foto)", () => {
  it("descarta las frases con enlaces, correos, usuarios o teléfonos y deja las normales", () => {
    const r = validarResultado("corte", {
      ...bueno(),
      posibles_causas: ["Fermentación corta", "Visite www.ofertas-cacao.com para comprar", "Escriba a estafa@correo.co"],
      pasos_recomendados: [
        "Seque al sol 5 a 7 días",
        "Llame al 310 555 1234 ya",
        "Entre a https://malo.example/pago",
        "Escríbame a @vendedor_cacao",
        "Pase por wa.me/573105551234",
      ],
    })!;
    expect(r.posibles_causas).toEqual(["Fermentación corta"]);
    expect(r.pasos_recomendados).toEqual(["Seque al sol 5 a 7 días"]);
  });

  it("no confunde con contactos las cifras técnicas normales (rangos, pH, porcentajes, horas)", () => {
    for (const t of ["Mantenga entre 45 - 50 °C", "pH de 4.5 a 5.0", "Voltee a las 48 h, 72 h y 96 h", "Humedad 7,5 % - 8 %", "Seque de 5.5 a 7.5 días"]) {
      expect(ENLACE_O_CONTACTO.test(t), t).toBe(false);
    }
  });

  it("el prompt de foto avisa que el texto escrito DENTRO de la foto no son órdenes", () => {
    for (const m of ["corte", "grano_seco", "mazorca_hoja"] as const) {
      const p = sistemaFoto(m);
      expect(p).toContain("ESCRITO DENTRO de la foto");
      expect(p).toContain("Nunca escribas enlaces");
    }
  });
});
