import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { procesarJpeg } from "../src/jpeg.js";

export const FIXTURE = readFileSync(new URL("./fixtures/cacao_pequena.jpg", import.meta.url)); // JPEG real 240x180

/** Segmento JPEG: FF, marcador, largo (incluye sus 2 bytes) y contenido. */
export function seg(marcador: number, contenido: Buffer | string): Buffer {
  const c = typeof contenido === "string" ? Buffer.from(contenido, "latin1") : contenido;
  const cab = Buffer.alloc(4);
  cab[0] = 0xff;
  cab[1] = marcador;
  cab.writeUInt16BE(c.length + 2, 2);
  return Buffer.concat([cab, c]);
}

/** Inserta segmentos justo después de SOI (antes del resto de los segmentos). */
export function conSegmentos(jpg: Buffer, segmentos: Buffer[]): Buffer {
  return Buffer.concat([jpg.subarray(0, 2), ...segmentos, jpg.subarray(2)]);
}

export const EXIF_CON_GPS = seg(0xe1, "Exif\0\0II*\0GPSLatitudeRef=N GPSLatitude=7.603112 GPSLongitudeRef=W GPSLongitude=72.601162");
const XMP = seg(0xe1, 'http://ns.adobe.com/xap/1.0/\0<x:xmpmeta><rdf:li>gps:Latitude</rdf:li></x:xmpmeta>');

const tiene = (b: Buffer, texto: string) => b.includes(Buffer.from(texto, "latin1"));
/** Datos de la imagen: desde el marcador SOS hasta el final. */
function desdeSos(b: Buffer): Buffer {
  let i = 2;
  while (b[i + 1] !== 0xda) i += 2 + b.readUInt16BE(i + 2);
  return b.subarray(i);
}

describe("procesarJpeg con la imagen real", () => {
  it("lee el tamaño y reconoce que traía metadatos", () => {
    const r = procesarJpeg(FIXTURE);
    expect(r.ok).toBe(true);
    if (r.ok) {
      expect([r.ancho, r.alto]).toEqual([240, 180]);
      expect(r.teniaMetadatos).toBe(true); // el JPEG de sips trae EXIF y Photoshop
      expect(tiene(r.limpio, "Exif")).toBe(false);
      expect(tiene(r.limpio, "JFIF")).toBe(true);
      expect(r.limpio[0]).toBe(0xff);
      expect(r.limpio[1]).toBe(0xd8);
      expect(r.limpio.subarray(-2).equals(Buffer.from([0xff, 0xd9]))).toBe(true);
    }
  });

  it("los datos de la imagen quedan idénticos byte a byte (no se reencodifica)", () => {
    const r = procesarJpeg(FIXTURE);
    if (!r.ok) throw new Error("debía ser ok");
    expect(desdeSos(r.limpio).equals(desdeSos(FIXTURE))).toBe(true);
  });

  it("no modifica el buffer de entrada", () => {
    const copia = Buffer.from(FIXTURE);
    procesarJpeg(FIXTURE);
    expect(FIXTURE.equals(copia)).toBe(true);
  });

  it("es idempotente: limpiar algo ya limpio no cambia nada y ya no hay metadatos", () => {
    const una = procesarJpeg(FIXTURE);
    if (!una.ok) throw new Error("debía ser ok");
    const dos = procesarJpeg(una.limpio);
    expect(dos.ok && dos.limpio.equals(una.limpio)).toBe(true);
    expect(dos.ok && dos.teniaMetadatos).toBe(false);
  });
});

describe("quita la ubicación y demás metadatos", () => {
  it("EXIF con GPS, XMP, IPTC/Photoshop y comentarios desaparecen por completo", () => {
    const sucio = conSegmentos(FIXTURE, [EXIF_CON_GPS, XMP, seg(0xed, "Photoshop 3.0\0 titulo privado"), seg(0xfe, "comentario con la finca de Luis")]);
    for (const secreto of ["GPS", "7.603112", "72.601162", "xmpmeta", "Photoshop", "privado", "finca de Luis"]) {
      expect(tiene(sucio, secreto), `el original debe contener ${secreto}`).toBe(true);
    }
    const r = procesarJpeg(sucio);
    if (!r.ok) throw new Error("debía ser ok");
    for (const secreto of ["GPS", "7.603112", "72.601162", "xmpmeta", "Photoshop", "privado", "finca de Luis", "Exif"]) {
      expect(tiene(r.limpio, secreto), secreto).toBe(false);
    }
    expect(r.teniaMetadatos).toBe(true);
    expect(desdeSos(r.limpio).equals(desdeSos(FIXTURE))).toBe(true);
  });

  it("conserva el perfil de color ICC y la marca Adobe (afectan cómo se ven los colores)", () => {
    const r = procesarJpeg(conSegmentos(FIXTURE, [seg(0xe2, "ICC_PROFILE\0\x01\x01perfil"), seg(0xee, "Adobe\0\x64\x80\0\0\0")]));
    if (!r.ok) throw new Error("debía ser ok");
    expect(tiene(r.limpio, "ICC_PROFILE")).toBe(true);
    expect(tiene(r.limpio, "Adobe")).toBe(true);
  });

  it("quita otros APP2 (MPF) y cualquier otro APPn (de fabricante)", () => {
    const r = procesarJpeg(conSegmentos(FIXTURE, [seg(0xe2, "MPF\0miniatura"), seg(0xe5, "FABRICANTE-SECRETO"), seg(0xef, "otra-cosa")]));
    if (!r.ok) throw new Error("debía ser ok");
    for (const x of ["MPF", "FABRICANTE", "otra-cosa"]) expect(tiene(r.limpio, x), x).toBe(false);
  });

  it("un bloque de metadatos enorme (60 KB) también se quita", () => {
    const grande = conSegmentos(FIXTURE, [seg(0xe1, Buffer.alloc(60_000, 0x41))]);
    const r = procesarJpeg(grande);
    if (!r.ok) throw new Error("debía ser ok");
    expect(grande.length - r.limpio.length).toBeGreaterThan(55_000);
  });

  it("acepta bytes de relleno 0xFF antes de un marcador", () => {
    const conRelleno = Buffer.concat([FIXTURE.subarray(0, 2), Buffer.from([0xff, 0xff, 0xff]), FIXTURE.subarray(2)]);
    expect(procesarJpeg(conRelleno).ok).toBe(true);
  });
});

describe("tamaño: baseline y progresivo", () => {
  const minimo = (sof: number, alto: number, ancho: number) => {
    const cab = Buffer.alloc(6);
    cab[0] = 8;
    cab.writeUInt16BE(alto, 1);
    cab.writeUInt16BE(ancho, 3);
    cab[5] = 1;
    return Buffer.concat([Buffer.from([0xff, 0xd8]), seg(sof, Buffer.concat([cab, Buffer.from([1, 0x11, 0])])), seg(0xda, Buffer.from([1, 1, 0, 0, 0x3f, 0])), Buffer.from("datos"), Buffer.from([0xff, 0xd9])]);
  };

  it("lee el tamaño de un JPEG progresivo (SOF2) y de uno baseline (SOF0)", () => {
    for (const sof of [0xc0, 0xc1, 0xc2]) {
      const r = procesarJpeg(minimo(sof, 300, 400));
      expect(r.ok && [r.ancho, r.alto]).toEqual([400, 300]);
    }
  });
});

describe("archivos que no sirven", () => {
  const malos: Record<string, Buffer> = {
    vacío: Buffer.alloc(0),
    "un solo byte": Buffer.from([0xff]),
    "PNG": Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 0]),
    "texto": Buffer.from("hola, esto no es una imagen"),
    "solo SOI y EOI": Buffer.from([0xff, 0xd8, 0xff, 0xd9]),
    "cortado a la mitad": FIXTURE.subarray(0, 60),
    "sin tamaño (SOF) antes de los datos": Buffer.concat([Buffer.from([0xff, 0xd8]), seg(0xe0, "JFIF\0"), seg(0xda, Buffer.from([1, 1, 0, 0, 0x3f, 0])), Buffer.from("datos")]),
    "largo de segmento menor que 2": Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x01]), Buffer.alloc(20)]),
    "largo mayor que el archivo": Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe1, 0xff, 0xff]), Buffer.alloc(20)]),
    "basura donde debería ir un marcador": Buffer.concat([Buffer.from([0xff, 0xd8]), seg(0xe0, "JFIF\0"), Buffer.from([0x12, 0x34, 0x56, 0x78])]),
  };
  it.each(Object.entries(malos))("%s", (_nombre, b) => {
    const r = procesarJpeg(b);
    expect(r.ok).toBe(false);
  });

  it("distingue 'no es JPEG' de 'JPEG dañado'", () => {
    const png = procesarJpeg(malos["PNG"]!);
    const cortado = procesarJpeg(malos["cortado a la mitad"]!);
    expect(!png.ok && png.error).toBe("no_es_jpeg");
    expect(!cortado.ok && cortado.error).toBe("jpeg_danado");
  });
});
