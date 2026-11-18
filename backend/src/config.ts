/**
 * Configuración del servidor. Todo viene de variables de entorno (las configura
 * quien despliega en Vercel). NINGUNA clave se escribe en el código ni en archivos:
 * ANTHROPIC_API_KEY la lee directamente el SDK de Anthropic desde el entorno.
 */
export interface Config {
  /** true cuando corre en producción en Vercel (VERCEL_ENV === "production"). */
  produccion: boolean;
  modeloChat: string;
  modeloFoto: string;
  limites: {
    /** Preguntas al chat por dispositivo (ID de instalación) y por día. */
    chatPorDia: number;
    /** Análisis de fotos por dispositivo y por día. */
    fotoPorDia: number;
    /** Consultas de nombre de lugar por dispositivo y por día. */
    lugarPorDia: number;
    /** Todas las consultas desde una misma IP por hora (alto: en el campo muchos
     *  teléfonos comparten la IP del operador móvil). */
    porIpPorHora: number;
  };
  /** Tope de gasto en IA por día para TODO el servidor, en millonésimas de dólar. */
  presupuestoDiarioMicroUsd: number;
  /** Si es true, el servidor rechaza todo lo que cuesta dinero (interruptor de emergencia). */
  bloqueoTotal: boolean;
  /** Secreto para anonimizar IDs e IPs antes de contarlos. Obligatorio en producción. */
  pepper: string | undefined;
  /** Contacto que se incluye en el User-Agent de Nominatim (política de OSM). */
  contactoNominatim: string | undefined;
  /** Interruptor para apagar /lugar (la política de Nominatim pide poder cambiar de servicio si lo piden). */
  lugarDesactivado: boolean;
}

/**
 * Valores por defecto: son PROPUESTAS de esta app para acotar el gasto y el abuso,
 * no datos de ninguna fuente. Se pueden cambiar con variables de entorno.
 */
export const POR_DEFECTO = {
  modeloChat: "claude-haiku-5-5",
  modeloFoto: "claude-sonnet-5-5",
  chatPorDia: 30,
  fotoPorDia: 10,
  lugarPorDia: 100,
  porIpPorHora: 300,
  presupuestoDiarioUsd: 5,
} as const;

function entero(valor: string | undefined, porDefecto: number, minimo = 0, maximo = 1_000_000): number {
  if (valor === undefined || valor.trim() === "") return porDefecto;
  const n = Number(valor);
  return Number.isInteger(n) && n >= minimo && n <= maximo ? n : porDefecto;
}

function decimal(valor: string | undefined, porDefecto: number): number {
  if (valor === undefined || valor.trim() === "") return porDefecto;
  const n = Number(valor);
  return Number.isFinite(n) && n >= 0 && n <= 100_000 ? n : porDefecto;
}

function texto(valor: string | undefined): string | undefined {
  const t = valor?.trim();
  return t ? t : undefined;
}

export function cargarConfig(env: Record<string, string | undefined> = process.env): Config {
  return {
    produccion: env.VERCEL_ENV === "production",
    modeloChat: texto(env.MODELO_CHAT) ?? POR_DEFECTO.modeloChat,
    modeloFoto: texto(env.MODELO_FOTO) ?? POR_DEFECTO.modeloFoto,
    limites: {
      chatPorDia: entero(env.LIMITE_CHAT_DIA, POR_DEFECTO.chatPorDia),
      fotoPorDia: entero(env.LIMITE_FOTO_DIA, POR_DEFECTO.fotoPorDia),
      lugarPorDia: entero(env.LIMITE_LUGAR_DIA, POR_DEFECTO.lugarPorDia),
      porIpPorHora: entero(env.LIMITE_IP_HORA, POR_DEFECTO.porIpPorHora),
    },
    presupuestoDiarioMicroUsd: Math.round(decimal(env.PRESUPUESTO_DIARIO_USD, POR_DEFECTO.presupuestoDiarioUsd) * 1_000_000),
    bloqueoTotal: env.BLOQUEO_TOTAL === "1",
    pepper: texto(env.ID_PEPPER),
    contactoNominatim: texto(env.NOMINATIM_CONTACTO),
    lugarDesactivado: env.LUGAR_DESACTIVADO === "1",
  };
}

/** Pepper de desarrollo: SOLO se usa fuera de producción. */
export const PEPPER_DESARROLLO = "pepper-solo-para-desarrollo-no-usar-en-produccion";

/** Devuelve el pepper a usar, o null si falta en producción (error de configuración). */
export function pepperEfectivo(cfg: Config): string | null {
  if (cfg.pepper && cfg.pepper.length >= 16) return cfg.pepper;
  return cfg.produccion ? null : PEPPER_DESARROLLO;
}
