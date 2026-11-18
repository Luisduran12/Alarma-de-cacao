import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { calcular, claseVerdadera, clasePredicha, COLUMNA_REPETIR, estimarCosto, informeMarkdown, prediccionTop, wilson, type FilaEvaluacion } from "../src/evaluacion.js";
import { ejecutarEvaluacion, estimarEvaluacion, leerConjunto } from "../src/ejecutar_evaluacion.js";
import type { ClienteIA, RespuestaEstructurada } from "../src/ia.js";
import type { ResultadoFoto } from "../src/foto.js";

const GALERIA = join(import.meta.dirname, "..", "..", "evaluacion", "galeria");
const fila = (o: Partial<FilaEvaluacion>): FilaEvaluacion => ({
  archivo: "a.jpg", modo: "corte", verdadera: "violeta", prediccion: "violeta", semaforo: "amarillo", error: null,
  tokensEntrada: 1000, tokensSalida: 300, costoMicroUsd: 5000, ...o,
});
const res = (o: Partial<ResultadoFoto>): ResultadoFoto => ({
  modo: "corte", foto_valida: true, repetir_foto: false, motivo: "ninguno", mensaje: "", categorias: [], confianza: "media",
  posibles_causas: [], pasos_recomendados: [], semaforo: "verde", aviso: "", ...o,
});

describe("clases de la evaluación", () => {
  it("pizarroso y moho son una sola clase en corte (la fuente las junta); en otro modo no", () => {
    expect(clasePredicha("corte", "pizarroso")).toBe("pizarroso_o_moho");
    expect(clasePredicha("corte", "moho")).toBe("pizarroso_o_moho");
    expect(clasePredicha("corte", "violeta")).toBe("violeta");
    expect(clasePredicha("grano_seco", "moho")).toBe("moho");
  });
  it("todos los ciclos de monilia cuentan como monilia", () => {
    for (const e of ["monilia_ciclo1", "monilia_ciclo2_3", "monilia_ciclo4"]) expect(claseVerdadera("mazorca_hoja", e)).toBe("monilia");
    expect(claseVerdadera("mazorca_hoja", "sana")).toBe("sana");
    expect(claseVerdadera("corte", "pizarroso_o_moho")).toBe("pizarroso_o_moho");
  });
  it("la predicción es la categoría con más porcentaje; si pidió otra foto no hay", () => {
    expect(prediccionTop(res({ categorias: [{ nombre: "violeta", porcentaje: 30 }, { nombre: "moho", porcentaje: 70 }] }))).toBe("pizarroso_o_moho");
    expect(prediccionTop(res({ repetir_foto: true, categorias: [] }))).toBeNull();
  });
});

describe("wilson", () => {
  it("con pocas fotos el intervalo es muy ancho", () => {
    const [lo, hi] = wilson(5, 5);
    expect(lo).toBeCloseTo(0.566, 2);
    expect(hi).toBe(1);
    const [l2, h2] = wilson(5, 10);
    expect(l2).toBeCloseTo(0.237, 2);
    expect(h2).toBeCloseTo(0.763, 2);
  });
  it("sin fotos: 0 a 1", () => expect(wilson(0, 0)).toEqual([0, 1]));
});

describe("calcular", () => {
  const filas = [
    fila({ verdadera: "violeta", prediccion: "violeta" }),
    fila({ verdadera: "violeta", prediccion: "bien_fermentado", semaforo: "verde" }),
    fila({ verdadera: "violeta", prediccion: null, semaforo: null }),
    fila({ verdadera: "bien_fermentado", prediccion: "bien_fermentado", semaforo: "verde" }),
    fila({ verdadera: "bien_fermentado", prediccion: null, semaforo: null, error: "502", tokensEntrada: 0, tokensSalida: 0, costoMicroUsd: 0 }),
  ];
  const m = calcular(filas);

  it("cuenta errores, fotos que pidieron otra foto y aciertos sin mezclarlos", () => {
    expect(m.total).toBe(5);
    expect(m.errores).toBe(1);
    expect(m.repetidas).toBe(1);
    expect(m.respondidas).toBe(3);
    expect(m.aciertos).toBe(2);
    expect(m.exactitudRespondidas).toBeCloseTo(2 / 3);
    expect(m.exactitudTodas).toBeCloseTo(2 / 4);
  });

  it("la matriz tiene la columna de 'pidió otra foto' y sus sumas cuadran con las fotos sin error", () => {
    expect(m.matriz["violeta"]!["violeta"]).toBe(1);
    expect(m.matriz["violeta"]!["bien_fermentado"]).toBe(1);
    expect(m.matriz["violeta"]![COLUMNA_REPETIR]).toBe(1);
    const suma = Object.values(m.matriz).flatMap((f) => Object.values(f)).reduce((a, b) => a + b, 0);
    expect(suma).toBe(4);
  });

  it("por clase y semáforo", () => {
    const v = m.porClase.find((c) => c.clase === "violeta")!;
    expect(v).toMatchObject({ n: 3, aciertos: 1, repetidas: 1 });
    expect(v.recall).toBeCloseTo(0.5);
    expect(m.semaforoPorClase["violeta"]).toEqual({ verde: 1, amarillo: 1, rojo: 0 });
  });

  it("suma tokens y costo", () => {
    expect(m.tokensEntrada).toBe(4000);
    expect(m.costoMicroUsd).toBe(20000);
  });

  it("sin filas no inventa números", () => {
    const v = calcular([]);
    expect(v.exactitudRespondidas).toBeNull();
    expect(v.exactitudTodas).toBeNull();
    expect(v.porClase).toEqual([]);
  });
});

describe("informe", () => {
  const m = calcular([fila({})]);
  const meta = { fecha: "2026-11-18", modelo: "claude-sonnet-5-5", conjunto: "galeria", ejemplosPorClase: 0, simulado: false };
  it("una evaluación simulada dice en grande que NO es una medición", () => {
    const t = informeMarkdown({ ...meta, simulado: true }, m);
    expect(t).toContain("SIMULADA");
    expect(t).toContain("NO son una medición");
  });
  it("una real no lo dice, e incluye las advertencias de lectura", () => {
    const t = informeMarkdown(meta, m);
    expect(t).not.toContain("SIMULADA");
    expect(t).toContain("1 de 1");
    expect(t).toContain("NO es el acierto con un celular en finca");
    expect(t).toContain("intervalo de confianza 95 %");
  });
});

describe("estimarCosto", () => {
  it("sube con los ejemplos y el peor caso es el de 4000 tokens de salida", () => {
    const base = { fotos: Array(10).fill({ ancho: 640, alto: 480 }), tokensTexto: 700, modelo: "claude-sonnet-5-5" };
    const sin = estimarCosto({ ...base, ejemplos: [] });
    const con = estimarCosto({ ...base, ejemplos: Array(8).fill({ ancho: 640, alto: 480 }) });
    expect(sin.llamadas).toBe(10);
    expect(con.tokensEntrada).toBeGreaterThan(sin.tokensEntrada);
    expect(con.escenarios[0]!.usd).toBeGreaterThan(sin.escenarios[0]!.usd);
    expect(sin.escenarios.at(-1)!.tokensSalidaPorFoto).toBe(4000);
    // 10 fotos de 640×480 = 10 × (23×18=414) + 10×700 = 11140 tokens de entrada
    expect(sin.tokensEntrada).toBe(11140);
  });
});

/** IA falsa que responde siempre con la primera categoría permitida del modo. */
function iaFalsa(llamadas: Array<Parameters<ClienteIA["analizarImagen"]>[0]> = []): ClienteIA {
  return {
    async responder() { throw new Error("no se usa"); },
    async analizarImagen<T>(p: Parameters<ClienteIA["analizarImagen"]>[0]) {
      llamadas.push(p);
      const cat = /Usa SOLO estas categorías: ([a-z_, ]+)\./.exec(p.sistema)![1]!.split(", ")[0]!;
      return {
        valor: { foto_valida: true, motivo_foto_no_valida: "ninguno", categorias: [{ nombre: cat, porcentaje: 100 }], confianza: "media", posibles_causas: [], pasos_recomendados: [], semaforo: "verde" },
        uso: { tokensEntrada: 1000, tokensSalida: 300, tokensEscrituraCache: 0, tokensLecturaCache: 0 },
        parada: "fin",
      } as RespuestaEstructurada<T>;
    },
  };
}

describe("ejecutarEvaluacion (con IA falsa, por el mismo camino que la app)", () => {
  it("lee las 40 fotos de prueba (20 de corte y 20 de mazorca) y respeta --max-por-clase", () => {
    expect(leerConjunto(GALERIA, ["corte", "mazorca_hoja"])).toHaveLength(40);
    expect(leerConjunto(GALERIA, ["corte"])).toHaveLength(20);
    expect(leerConjunto(GALERIA, ["corte", "mazorca_hoja"], 2)).toHaveLength(16);
  });

  it("una corrida completa devuelve una fila por foto con su costo", async () => {
    const r = await ejecutarEvaluacion(iaFalsa(), { carpeta: GALERIA, modos: ["corte"], ejemplosPorClase: 0, topeUsd: 10, maxPorClase: 2 });
    expect(r.incompleta).toBe(false);
    expect(r.filas).toHaveLength(8);
    expect(r.filas.every((f) => f.error === null && f.costoMicroUsd === 5000)).toBe(true);
    const m = calcular(r.filas);
    expect(m.respondidas).toBe(8);
    expect(m.aciertos).toBe(2); // la IA falsa siempre dice "bien_fermentado": acierta solo en esa clase
  });

  it("con ejemplos, la IA recibe 4 clases × N fotos de REFERENCIA y nunca una foto de prueba", async () => {
    const llamadas: Array<Parameters<ClienteIA["analizarImagen"]>[0]> = [];
    await ejecutarEvaluacion(iaFalsa(llamadas), { carpeta: GALERIA, modos: ["corte"], ejemplosPorClase: 2, topeUsd: 10, maxPorClase: 1 });
    expect(llamadas).toHaveLength(4);
    for (const l of llamadas) expect(l.ejemplos).toHaveLength(8);
  });

  it("al alcanzar el tope de gasto se detiene y lo dice (los números son parciales)", async () => {
    const r = await ejecutarEvaluacion(iaFalsa(), { carpeta: GALERIA, modos: ["corte", "mazorca_hoja"], ejemplosPorClase: 0, topeUsd: 0.012 });
    expect(r.incompleta).toBe(true);
    expect(r.motivoParada).toBe("presupuesto_agotado");
    expect(r.filas.length).toBeLessThan(40);
    expect(r.filas.at(-1)!.error).toBe("presupuesto_agotado");
  });

  it("estimarEvaluacion no llama a la IA y da cuatro escenarios crecientes", () => {
    const e = estimarEvaluacion({ carpeta: GALERIA, modos: ["corte", "mazorca_hoja"], ejemplosPorClase: 0, topeUsd: 1 });
    expect(e.fotos).toBe(40);
    expect(e.escenarios.map((s) => s.usd)).toEqual([...e.escenarios.map((s) => s.usd)].sort((a, b) => a - b));
  });
});
