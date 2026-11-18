import { createHash } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { procesarJpeg } from "../src/jpeg.js";
import {
  cargarEjemplos, cargarManifiesto, DIRECTORIO_REFERENCIAS, elegirReferencias, MAX_POR_CLASE, modoDeReferencias, type Referencia,
} from "../src/referencias.js";

const EVAL = join(DIRECTORIO_REFERENCIAS, "..", "..", "evaluacion", "galeria");
const refs = cargarManifiesto();
const pruebas = JSON.parse(readFileSync(join(EVAL, "manifest.json"), "utf8")) as Array<{ archivo: string; etiqueta: string; modo: string }>;
const hash = (ruta: string) => createHash("sha256").update(readFileSync(ruta)).digest("hex");

describe("galería de referencia (backend/referencias)", () => {
  it("40 fotos: 4 clases de corte y 4 de mazorca, 5 por clase", () => {
    expect(refs).toHaveLength(40);
    for (const modo of ["corte", "mazorca"]) {
      const clases = new Map<string, number>();
      for (const r of refs.filter((x) => x.modo === modo)) clases.set(r.etiqueta, (clases.get(r.etiqueta) ?? 0) + 1);
      expect(clases.size).toBe(4);
      expect([...clases.values()]).toEqual([5, 5, 5, 5]);
    }
  });

  it("cada foto existe, es un JPEG válido, sin metadatos y de un tamaño razonable", () => {
    for (const r of refs) {
      const ruta = join(DIRECTORIO_REFERENCIAS, r.archivo);
      expect(existsSync(ruta), r.archivo).toBe(true);
      const j = procesarJpeg(readFileSync(ruta));
      expect(j.ok, r.archivo).toBe(true);
      if (!j.ok) continue;
      expect(j.teniaMetadatos, `${r.archivo} trae metadatos`).toBe(false);
      expect(Math.max(j.ancho, j.alto), r.archivo).toBeLessThanOrEqual(800);
      expect(Math.max(j.ancho, j.alto), r.archivo).toBeGreaterThanOrEqual(200);
    }
  });

  it("todas llevan fuente, autores, DOI y licencia CC BY 4.0, y las de corte avisan que no son la NTC 1252", () => {
    for (const r of refs) {
      expect(r.licencia, r.archivo).toContain("CC BY 4.0");
      expect(["10.5281/zenodo.22824982", "10.5281/zenodo.17716661"]).toContain(r.doi);
    }
    for (const r of refs.filter((x) => x.modo === "corte")) expect(r.norma).toContain("No es la NTC 1252");
  });

  it("ninguna foto de PRUEBA está entre las de referencia (ni por nombre ni por contenido)", () => {
    expect(pruebas).toHaveLength(40);
    const nombresRef = new Set(refs.map((r) => r.archivo));
    expect(pruebas.some((p) => nombresRef.has(p.archivo))).toBe(false);
    const hashesRef = new Set(refs.map((r) => hash(join(DIRECTORIO_REFERENCIAS, r.archivo))));
    for (const p of pruebas) {
      expect(hashesRef.has(hash(join(EVAL, p.archivo))), `${p.archivo} es idéntica a una referencia`).toBe(false);
    }
  });

  it("el manifiesto de referencias no trae fotos marcadas como prueba", () => {
    expect(refs.every((r) => !("rol" in r) || (r as { rol?: string }).rol === "referencia")).toBe(true);
  });
});

describe("elegirReferencias", () => {
  it("hasta N por clase, siempre las mismas y en orden", () => {
    const a = elegirReferencias(refs, "corte", 2);
    expect(a).toHaveLength(8);
    expect(a.map((r) => r.archivo)).toEqual(elegirReferencias([...refs].reverse(), "corte", 2).map((r) => r.archivo));
    expect(new Set(a.map((r) => r.etiqueta)).size).toBe(4);
  });

  it("0 (el valor por defecto) no elige nada; el máximo es 5 por clase", () => {
    expect(elegirReferencias(refs, "corte", 0)).toEqual([]);
    expect(elegirReferencias(refs, "corte", -3)).toEqual([]);
    expect(elegirReferencias(refs, "mazorca_hoja", 99)).toHaveLength(4 * MAX_POR_CLASE);
  });

  it("grano seco no tiene ejemplos; mazorca_hoja usa las mazorcas", () => {
    expect(modoDeReferencias("grano_seco")).toBeNull();
    expect(elegirReferencias(refs, "grano_seco", 3)).toEqual([]);
    expect(elegirReferencias(refs, "mazorca_hoja", 1).every((r) => r.modo === "mazorca")).toBe(true);
  });
});

describe("cargarEjemplos y manifiesto", () => {
  it("devuelve la foto en base64 con su descripción", () => {
    const e = cargarEjemplos("corte", 1);
    expect(e).toHaveLength(4);
    expect(e[0]!.descripcion.length).toBeGreaterThan(5);
    expect(Buffer.from(e[0]!.imagenBase64, "base64").subarray(0, 2).toString("hex")).toBe("ffd8");
  });

  it("un manifiesto dañado o con archivos repetidos se rechaza", () => {
    expect(() => cargarManifiesto("x", () => "no es json")).toThrow();
    expect(() => cargarManifiesto("x", () => "[]")).toThrow();
    const una = { ...refs[0] } as Referencia;
    expect(() => cargarManifiesto("x", () => JSON.stringify([una, una]))).toThrow(/repetidos/);
    expect(() => cargarManifiesto("x", () => JSON.stringify([{ ...una, archivo: "../../etc/passwd" }]))).toThrow();
  });
});
