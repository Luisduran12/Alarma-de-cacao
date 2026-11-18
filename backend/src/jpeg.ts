/**
 * Lectura y limpieza de JPEG SIN reencodificar la imagen: se recorren los segmentos del
 * archivo, se copian los que hacen falta para verla y se descartan los de metadatos
 * (EXIF con la ubicación GPS, XMP, IPTC/Photoshop, comentarios...). La imagen no cambia ni
 * un píxel.
 *
 * La app ya debe quitar los metadatos antes de enviar; esto es una SEGUNDA barrera por si
 * una foto llega con ellos (un fallo de la app, un cliente modificado).
 */
export type ErrorJpeg = "no_es_jpeg" | "jpeg_danado";

export type ResultadoJpeg =
  | { ok: true; ancho: number; alto: number; limpio: Buffer; teniaMetadatos: boolean }
  | { ok: false; error: ErrorJpeg };

const SOI = 0xd8;
const EOI = 0xd9;
const SOS = 0xda;
const APP0 = 0xe0;
const APP2 = 0xe2;
const APP14 = 0xee;
const APP1 = 0xe1;
const COM = 0xfe;

/** Marcadores SOFn que traen el tamaño de la imagen (no son DHT 0xC4, JPG 0xC8 ni DAC 0xCC). */
const esSof = (m: number) => m >= 0xc0 && m <= 0xcf && m !== 0xc4 && m !== 0xc8 && m !== 0xcc;

const empiezaCon = (b: Buffer, desde: number, texto: string) =>
  b.length >= desde + texto.length && b.toString("latin1", desde, desde + texto.length) === texto;

/** ¿Se conserva este segmento? Solo lo necesario para ver bien la imagen. */
function conservar(marcador: number, seg: Buffer): boolean {
  if (marcador === APP1 || marcador === COM) return false; // EXIF/XMP y comentarios
  if (marcador === APP0) return true; // JFIF
  if (marcador === APP2) return empiezaCon(seg, 4, "ICC_PROFILE\0"); // perfil de color sí; MPF y otros no
  if (marcador === APP14) return empiezaCon(seg, 4, "Adobe"); // afecta cómo se interpretan los colores
  if (marcador > APP0 && marcador <= 0xef) return false; // cualquier otro APPn (IPTC, Photoshop, fabricante...)
  return true; // tablas, tamaño de imagen, etc.
}

export function procesarJpeg(buf: Buffer): ResultadoJpeg {
  if (buf.length < 4 || buf[0] !== 0xff || buf[1] !== SOI) return { ok: false, error: "no_es_jpeg" };

  const salida: Buffer[] = [buf.subarray(0, 2)];
  let teniaMetadatos = false;
  let ancho = 0;
  let alto = 0;
  let i = 2;

  for (;;) {
    // Cada segmento empieza con 0xFF y un marcador; puede haber bytes de relleno 0xFF.
    if (i >= buf.length || buf[i] !== 0xff) return { ok: false, error: "jpeg_danado" };
    while (buf[i + 1] === 0xff) i++;
    const marcador = buf[i + 1];
    if (marcador === undefined) return { ok: false, error: "jpeg_danado" };

    if (marcador === EOI) {
      // Fin sin datos de imagen: no es un JPEG usable.
      return { ok: false, error: "jpeg_danado" };
    }
    // Marcadores sin longitud (RSTn y similares) no deberían aparecer antes de SOS.
    if (marcador === 0x00 || marcador === 0x01 || (marcador >= 0xd0 && marcador <= 0xd8)) return { ok: false, error: "jpeg_danado" };

    if (i + 4 > buf.length) return { ok: false, error: "jpeg_danado" };
    const largo = buf.readUInt16BE(i + 2); // incluye los 2 bytes del propio largo
    if (largo < 2 || i + 2 + largo > buf.length) return { ok: false, error: "jpeg_danado" };
    const seg = buf.subarray(i, i + 2 + largo);

    if (esSof(marcador)) {
      if (largo < 8) return { ok: false, error: "jpeg_danado" };
      alto = seg.readUInt16BE(5);
      ancho = seg.readUInt16BE(7);
    }

    if (marcador === SOS) {
      // Desde aquí vienen los datos de la imagen hasta el final: se copian tal cual.
      if (!ancho || !alto) return { ok: false, error: "jpeg_danado" };
      salida.push(buf.subarray(i));
      return { ok: true, ancho, alto, limpio: Buffer.concat(salida), teniaMetadatos };
    }

    if (conservar(marcador, seg)) salida.push(seg);
    else teniaMetadatos = true;
    i += 2 + largo;
  }
}
