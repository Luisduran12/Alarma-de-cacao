import type { Almacen } from "./almacen.js";
import type { Config } from "./config.js";

export type TipoPeticion = "chat" | "foto" | "lugar";

export type ResultadoLimite =
  | { ok: true }
  | { ok: false; estado: number; codigo: string; mensaje: string; reintentarEnSeg?: number };

const DESFASE_COLOMBIA_MS = 5 * 3600_000; // UTC-5, sin horario de verano

/** Día calendario en Colombia, "AAAA-MM-DD". */
export function diaColombia(ahora: Date): string {
  return new Date(ahora.getTime() - DESFASE_COLOMBIA_MS).toISOString().slice(0, 10);
}

/** Segundos que faltan para la medianoche de Colombia. */
export function segundosHastaMedianoche(ahora: Date): number {
  const local = new Date(ahora.getTime() - DESFASE_COLOMBIA_MS);
  const siguiente = Date.UTC(local.getUTCFullYear(), local.getUTCMonth(), local.getUTCDate() + 1);
  return Math.max(1, Math.ceil((siguiente - local.getTime()) / 1000));
}

const horaUtc = (ahora: Date) => ahora.toISOString().slice(0, 13);

export interface ParametrosLimite {
  almacen: Almacen;
  cfg: Config;
  /** ID de instalación ya anonimizado. */
  idHash: string;
  /** IP ya anonimizada. */
  ipHash: string;
  tipo: TipoPeticion;
  ahora?: Date;
}

/**
 * Decide si una petición puede seguir. Orden: interruptor de emergencia → límite por IP →
 * límite diario del dispositivo → tope de gasto del servidor. Cuenta TODOS los intentos
 * (también los que luego fallen): contar de menos dejaría abusar.
 *
 * Los límites son una MITIGACIÓN, no una autenticación: el ID de instalación lo genera la
 * app y cualquiera puede fabricar IDs nuevos. Por eso existen también el límite por IP y,
 * sobre todo, el tope de gasto diario de todo el servidor (ver docs/backend-seguridad.md).
 */
export async function verificarLimites(p: ParametrosLimite): Promise<ResultadoLimite> {
  const ahora = p.ahora ?? new Date();
  const cuesta = p.tipo !== "lugar";

  if (cuesta && p.cfg.bloqueoTotal) {
    return { ok: false, estado: 503, codigo: "servicio_pausado", mensaje: "El servicio de IA está pausado por ahora. Use las respuestas guardadas en la app." };
  }

  const enIp = await p.almacen.sumar(`ip:${horaUtc(ahora)}:${p.ipHash}`, 1, 7200);
  if (enIp > p.cfg.limites.porIpPorHora) {
    return { ok: false, estado: 429, codigo: "limite_ip", mensaje: "Hay demasiadas consultas desde su conexión. Espere un rato e intente de nuevo.", reintentarEnSeg: 3600 };
  }

  const dia = diaColombia(ahora);
  const maximo = p.tipo === "chat" ? p.cfg.limites.chatPorDia : p.tipo === "foto" ? p.cfg.limites.fotoPorDia : p.cfg.limites.lugarPorDia;
  const enDispositivo = await p.almacen.sumar(`dia:${p.tipo}:${dia}:${p.idHash}`, 1, 90_000);
  if (enDispositivo > maximo) {
    return { ok: false, estado: 429, codigo: "limite_dia", mensaje: "Ya usó todas las consultas de hoy. Vuelva mañana.", reintentarEnSeg: segundosHastaMedianoche(ahora) };
  }

  if (cuesta) {
    const gastado = await p.almacen.leerNumero(`gasto:${dia}`);
    if (gastado >= p.cfg.presupuestoDiarioMicroUsd) {
      return { ok: false, estado: 503, codigo: "presupuesto_agotado", mensaje: "El servicio de IA descansa por hoy. Use las respuestas guardadas en la app.", reintentarEnSeg: segundosHastaMedianoche(ahora) };
    }
  }
  return { ok: true };
}

/** Suma al gasto del día lo que costó una llamada a la IA (en microdólares). */
export async function registrarGasto(almacen: Almacen, microUsd: number, ahora: Date = new Date()): Promise<void> {
  if (microUsd <= 0) return;
  await almacen.sumar(`gasto:${diaColombia(ahora)}`, Math.ceil(microUsd), 90_000);
}
