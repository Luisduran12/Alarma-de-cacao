import { esEntornoDesplegado } from "./config.js";
/**
 * Almacén de contadores, cerrojos y caché. En producción es Upstash Redis (por su API
 * REST, sin dependencias); en pruebas y desarrollo, memoria.
 *
 * Aquí se guardan SOLO contadores con vencimiento y el caché de nombres de lugar:
 * nunca conversaciones, preguntas, respuestas ni imágenes.
 */
export interface Almacen {
  /** Suma [n] al contador [clave] (lo crea con vencimiento [ttlSeg] si no existe). Devuelve el valor nuevo. */
  sumar(clave: string, n: number, ttlSeg: number): Promise<number>;
  leerNumero(clave: string): Promise<number>;
  /** Intenta tomar el cerrojo [clave] durante [ms]. true si lo logró (nadie más lo tiene). */
  tomarCerrojo(clave: string, ms: number): Promise<boolean>;
  obtener(clave: string): Promise<string | null>;
  guardar(clave: string, valor: string, ttlSeg: number): Promise<void>;
}

/** Almacén en memoria: SOLO para pruebas y desarrollo (no se comparte entre instancias). */
export class MemoriaAlmacen implements Almacen {
  private datos = new Map<string, { valor: string; vence: number }>();

  constructor(private readonly ahora: () => number = Date.now) {}

  private vivo(clave: string): { valor: string; vence: number } | undefined {
    const e = this.datos.get(clave);
    if (e && e.vence <= this.ahora()) {
      this.datos.delete(clave);
      return undefined;
    }
    return e;
  }

  async sumar(clave: string, n: number, ttlSeg: number): Promise<number> {
    const e = this.vivo(clave);
    const nuevo = (e ? Number(e.valor) : 0) + n;
    this.datos.set(clave, { valor: String(nuevo), vence: e ? e.vence : this.ahora() + ttlSeg * 1000 });
    return nuevo;
  }

  async leerNumero(clave: string): Promise<number> {
    const e = this.vivo(clave);
    const n = e ? Number(e.valor) : 0;
    return Number.isFinite(n) ? n : 0;
  }

  async tomarCerrojo(clave: string, ms: number): Promise<boolean> {
    if (this.vivo(clave)) return false;
    this.datos.set(clave, { valor: "1", vence: this.ahora() + ms });
    return true;
  }

  async obtener(clave: string): Promise<string | null> {
    return this.vivo(clave)?.valor ?? null;
  }

  async guardar(clave: string, valor: string, ttlSeg: number): Promise<void> {
    this.datos.set(clave, { valor, vence: this.ahora() + ttlSeg * 1000 });
  }

  /** Todo lo que hay guardado (ayuda para PRUEBAS: comprobar que nunca se guarda contenido del usuario). */
  volcar(): Array<[string, string]> {
    return [...this.datos.entries()].filter(([c]) => this.vivo(c)).map(([c, e]) => [c, e.valor]);
  }
}

type Comando = (string | number)[];
type Fetch = typeof fetch;

/** Almacén sobre la API REST de Upstash Redis (https://upstash.com/docs/redis/features/restapi). */
export class UpstashAlmacen implements Almacen {
  constructor(
    private readonly url: string,
    private readonly token: string,
    private readonly fetchFn: Fetch = fetch,
    private readonly esperaMs = 3000,
  ) {}

  /** Los errores NO incluyen la URL ni el token. */
  private async pedir(ruta: string, cuerpo: unknown): Promise<unknown> {
    let r: Response;
    try {
      r = await this.fetchFn(`${this.url}${ruta}`, {
        method: "POST",
        headers: { Authorization: `Bearer ${this.token}`, "Content-Type": "application/json" },
        body: JSON.stringify(cuerpo),
        signal: AbortSignal.timeout(this.esperaMs),
      });
    } catch {
      throw new Error("almacen_sin_conexion");
    }
    if (!r.ok) throw new Error(`almacen_http_${r.status}`);
    return r.json();
  }

  private async comando(c: Comando): Promise<unknown> {
    const j = (await this.pedir("", c)) as { result?: unknown; error?: string };
    if (j.error) throw new Error("almacen_error");
    return j.result ?? null;
  }

  async sumar(clave: string, n: number, ttlSeg: number): Promise<number> {
    const j = (await this.pedir("/pipeline", [
      ["INCRBY", clave, n],
      ["EXPIRE", clave, ttlSeg, "NX"],
    ])) as Array<{ result?: unknown; error?: string }>;
    const primero = j[0];
    if (!primero || primero.error || typeof primero.result !== "number") throw new Error("almacen_error");
    return primero.result;
  }

  async leerNumero(clave: string): Promise<number> {
    const r = await this.comando(["GET", clave]);
    const n = Number(r ?? 0);
    return Number.isFinite(n) ? n : 0;
  }

  async tomarCerrojo(clave: string, ms: number): Promise<boolean> {
    return (await this.comando(["SET", clave, "1", "PX", ms, "NX"])) === "OK";
  }

  async obtener(clave: string): Promise<string | null> {
    const r = await this.comando(["GET", clave]);
    return typeof r === "string" ? r : null;
  }

  async guardar(clave: string, valor: string, ttlSeg: number): Promise<void> {
    await this.comando(["SET", clave, valor, "EX", ttlSeg]);
  }
}

let memoriaDeDesarrollo: MemoriaAlmacen | undefined;

/**
 * Elige el almacén según el entorno. Devuelve null si falta (en producción sin Upstash
 * configurado): quien lo llama debe RECHAZAR la petición en vez de dejarla pasar sin límite.
 */
export function crearAlmacenDesdeEntorno(
  env: Record<string, string | undefined> = process.env,
  fetchFn: Fetch = fetch,
): Almacen | null {
  const url = env.UPSTASH_REDIS_REST_URL ?? env.KV_REST_API_URL;
  const token = env.UPSTASH_REDIS_REST_TOKEN ?? env.KV_REST_API_TOKEN;
  if (url && token && url.startsWith("https://")) return new UpstashAlmacen(url.replace(/\/+$/, ""), token, fetchFn);
  // Desplegado (producción o preview) sin Upstash: NO se usa la memoria (en serverless no cuenta nada entre instancias).
  if (esEntornoDesplegado(env)) return null;
  return (memoriaDeDesarrollo ??= new MemoriaAlmacen());
}
