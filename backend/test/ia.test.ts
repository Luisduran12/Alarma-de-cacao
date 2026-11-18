import Anthropic from "@anthropic-ai/sdk";
import { afterEach, describe, expect, it, vi } from "vitest";
import { z } from "zod";
import { clasificarError, crearClienteIA, ErrorIA } from "../src/ia.js";

type Llamada = Record<string, unknown>;

function sdkFalso(respuesta: unknown | Error) {
  const llamadas: { metodo: string; params: Llamada }[] = [];
  const hacer = (metodo: string) => async (params: Llamada) => {
    llamadas.push({ metodo, params });
    if (respuesta instanceof Error) throw respuesta;
    return respuesta;
  };
  const cliente = { messages: { create: hacer("create"), parse: hacer("parse") } } as unknown as Anthropic;
  return { cliente, llamadas };
}

const uso = { input_tokens: 1500, output_tokens: 200, cache_creation_input_tokens: null, cache_read_input_tokens: 40 };

afterEach(() => vi.unstubAllEnvs());

describe("responder (chat)", () => {
  it("manda modelo, tope de tokens, sistema y mensajes; sin razonamiento y con esfuerzo bajo; sin parámetros que dan 400", async () => {
    const { cliente, llamadas } = sdkFalso({ content: [{ type: "text", text: "Hola" }], usage: uso, stop_reason: "end_turn" });
    const r = await crearClienteIA({ cliente }).responder({
      modelo: "claude-haiku-5-5", sistema: "SISTEMA", maxTokens: 600, mensajes: [{ role: "user", content: "¿Cuándo volteo?" }],
    });
    const p = llamadas[0]!.params;
    expect(llamadas[0]!.metodo).toBe("create");
    expect(p.model).toBe("claude-haiku-5-5");
    expect(p.max_tokens).toBe(600);
    expect(p.system).toBe("SISTEMA");
    expect(p.messages).toEqual([{ role: "user", content: "¿Cuándo volteo?" }]);
    expect(p.thinking).toEqual({ type: "disabled" });
    expect(p.output_config).toEqual({ effort: "low" });
    for (const prohibido of ["temperature", "top_p", "top_k", "tool_choice", "tools"]) expect(p).not.toHaveProperty(prohibido);
    expect(r.texto).toBe("Hola");
  });

  it("junta solo los bloques de texto y mapea el uso (incluida la caché)", async () => {
    const { cliente } = sdkFalso({
      content: [{ type: "thinking", thinking: "" }, { type: "text", text: "Uno. " }, { type: "text", text: " Dos." }],
      usage: uso, stop_reason: "end_turn",
    });
    const r = await crearClienteIA({ cliente }).responder({ modelo: "m", sistema: "s", maxTokens: 10, mensajes: [] });
    expect(r.texto).toBe("Uno.  Dos.");
    expect(r.uso).toEqual({ tokensEntrada: 1500, tokensSalida: 200, tokensEscrituraCache: 0, tokensLecturaCache: 40 });
  });

  it("mapea las razones de parada", async () => {
    for (const [razon, esperada] of [["end_turn", "fin"], ["max_tokens", "max_tokens"], ["refusal", "rechazo"], ["tool_use", "otra"], [null, "otra"]] as const) {
      const { cliente } = sdkFalso({ content: [{ type: "text", text: "x" }], usage: uso, stop_reason: razon });
      expect((await crearClienteIA({ cliente }).responder({ modelo: "m", sistema: "s", maxTokens: 1, mensajes: [] })).parada).toBe(esperada);
    }
  });
});

describe("analizarImagen (fotos)", () => {
  const Esquema = z.object({ ok: z.boolean() });

  it("manda la imagen en base64 JPEG + el texto, esquema estructurado y esfuerzo medio, sin tool_choice", async () => {
    const { cliente, llamadas } = sdkFalso({ parsed_output: { ok: true }, usage: uso, stop_reason: "end_turn" });
    const r = await crearClienteIA({ cliente }).analizarImagen({
      modelo: "claude-sonnet-5-5", sistema: "S", imagenBase64: "AAAA", texto: "Analiza", maxTokens: 2000, esquema: Esquema,
    });
    const p = llamadas[0]!.params as { messages: Array<{ role: string; content: unknown[] }>; output_config: { effort: string; format: { type: string } } };
    expect(llamadas[0]!.metodo).toBe("parse");
    expect(p.messages[0]!.content).toEqual([
      { type: "image", source: { type: "base64", media_type: "image/jpeg", data: "AAAA" } },
      { type: "text", text: "Analiza" },
    ]);
    expect(p.output_config.effort).toBe("medium");
    expect(p.output_config.format.type).toBe("json_schema");
    for (const prohibido of ["temperature", "top_p", "top_k", "tool_choice", "thinking"]) expect(p).not.toHaveProperty(prohibido);
    expect(r.valor).toEqual({ ok: true });
  });

  it("si la IA no devuelve algo que cumpla el esquema, el valor es null", async () => {
    const { cliente } = sdkFalso({ parsed_output: null, usage: uso, stop_reason: "end_turn" });
    const r = await crearClienteIA({ cliente }).analizarImagen({ modelo: "m", sistema: "s", imagenBase64: "A", texto: "t", maxTokens: 1, esquema: Esquema });
    expect(r.valor).toBeNull();
  });
});

describe("errores: se clasifican y NUNCA copian el mensaje original (puede traer claves)", () => {
  const cabeceras = new Headers();
  const mensaje = "401 invalid x-api-key sk-ant-SECRETO-123";

  it.each([
    [429, "ocupada"], [529, "ocupada"], [401, "configuracion"], [403, "configuracion"],
    [400, "peticion"], [404, "peticion"], [500, "no_disponible"], [502, "no_disponible"],
  ] as const)("HTTP %i → %s", async (estado, tipo) => {
    const e = Anthropic.APIError.generate(estado, { error: { type: "x", message: mensaje } }, mensaje, cabeceras);
    const traducido = clasificarError(e);
    expect(traducido).toBeInstanceOf(ErrorIA);
    expect(traducido.tipo).toBe(tipo);
    expect(traducido.message).not.toContain("SECRETO");
    expect(JSON.stringify(traducido)).not.toContain("SECRETO");
  });

  it("falla de conexión o cualquier otro error → no_disponible", () => {
    expect(clasificarError(new Anthropic.APIConnectionError({ message: mensaje })).tipo).toBe("no_disponible");
    expect(clasificarError(new Error(mensaje)).message).not.toContain("SECRETO");
    expect(clasificarError("texto raro").tipo).toBe("no_disponible");
  });

  it("los métodos lanzan ErrorIA, no el error del SDK", async () => {
    const { cliente } = sdkFalso(Anthropic.APIError.generate(429, { error: { type: "x", message: mensaje } }, mensaje, cabeceras));
    const ia = crearClienteIA({ cliente });
    const e = await ia.responder({ modelo: "m", sistema: "s", maxTokens: 1, mensajes: [] }).catch((x: unknown) => x);
    expect(e).toBeInstanceOf(ErrorIA);
    expect((e as ErrorIA).tipo).toBe("ocupada");
  });

  it("sin ANTHROPIC_API_KEY en el entorno: error de configuración (no se cae la función)", async () => {
    vi.stubEnv("ANTHROPIC_API_KEY", "");
    const e = await crearClienteIA().responder({ modelo: "m", sistema: "s", maxTokens: 1, mensajes: [] }).catch((x: unknown) => x);
    expect(e).toBeInstanceOf(ErrorIA);
    expect((e as ErrorIA).tipo).toBe("configuracion");
  });
});
