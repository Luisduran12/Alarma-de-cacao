import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { cargarConfig } from "../src/config.js";
import { calcular, informeMarkdown } from "../src/evaluacion.js";
import { ejecutarEvaluacion, estimarEvaluacion, leerConjunto, type OpcionesEvaluacion } from "../src/ejecutar_evaluacion.js";
import { crearClienteIA, type ClienteIA } from "../src/ia.js";
import type { ModoFoto } from "../src/prompts.js";

const AYUDA = `Evaluación del análisis de fotos (mide el acierto con las fotos de prueba)

Uso:
  npm run evaluar -- --estimar   [opciones]      calcula el costo; NO llama a la IA
  npm run evaluar -- --simulado  [opciones]      prueba el programa con una IA falsa (los números NO son una medición)
  npm run evaluar -- --real --tope-usd 2 [opciones]   llama a la IA de verdad y GASTA DINERO (hace falta ANTHROPIC_API_KEY en el entorno)

Opciones:
  --ejemplos N        fotos de ejemplo por clase que se mandan con cada foto (0 a 5, por defecto 0)
  --modo M            corte | mazorca_hoja | todos (por defecto todos)
  --conjunto C        galeria | colombia (por defecto galeria)
  --max-por-clase K   usa solo K fotos por clase (para una prueba barata)
  --tope-usd X        obligatorio con --real: la corrida se detiene al llegar a este gasto
`;

function argumentos(av: string[]) {
  const valor = (n: string) => {
    const i = av.indexOf(n);
    return i >= 0 ? av[i + 1] : undefined;
  };
  const num = (n: string, def: number) => {
    const v = valor(n);
    if (v === undefined) return def;
    const x = Number(v);
    if (!Number.isFinite(x)) throw new Error(`${n} debe ser un número`);
    return x;
  };
  const modoTxt = valor("--modo") ?? "todos";
  const modos: ModoFoto[] = modoTxt === "todos" ? ["corte", "mazorca_hoja"] : [modoTxt as ModoFoto];
  if (modos.some((m) => m !== "corte" && m !== "mazorca_hoja")) throw new Error("--modo: corte, mazorca_hoja o todos");
  const ejemplos = num("--ejemplos", 0);
  if (!Number.isInteger(ejemplos) || ejemplos < 0 || ejemplos > 5) throw new Error("--ejemplos: de 0 a 5");
  const conjunto = valor("--conjunto") ?? "galeria";
  if (conjunto !== "galeria" && conjunto !== "colombia") throw new Error("--conjunto: galeria o colombia");
  const max = valor("--max-por-clase");
  return {
    estimar: av.includes("--estimar"),
    simulado: av.includes("--simulado"),
    real: av.includes("--real"),
    ejemplos, modos, conjunto,
    maxPorClase: max === undefined ? undefined : num("--max-por-clase", 1),
    topeUsd: valor("--tope-usd") === undefined ? undefined : num("--tope-usd", 0),
  };
}

/** IA falsa: siempre la primera categoría. Sirve solo para probar el programa. */
function iaSimulada(): ClienteIA {
  return {
    async responder() { throw new Error("no se usa"); },
    async analizarImagen(p) {
      const permitidas = /categorías: ([a-z_, ]+)\./.exec(p.sistema)?.[1]?.split(", ") ?? ["x"];
      return {
        valor: p.esquema.parse({
          foto_valida: true, motivo_foto_no_valida: "ninguno", categorias: [{ nombre: permitidas[0]!, porcentaje: 100 }],
          confianza: "media", posibles_causas: [], pasos_recomendados: [], semaforo: "verde",
        }),
        uso: { tokensEntrada: 1000, tokensSalida: 300, tokensEscrituraCache: 0, tokensLecturaCache: 0 },
        parada: "fin",
      } as never;
    },
  };
}

async function main() {
  const av = process.argv.slice(2);
  if (av.length === 0 || av.includes("--ayuda") || av.includes("--help")) return void console.log(AYUDA);
  const a = argumentos(av);
  if ([a.estimar, a.simulado, a.real].filter(Boolean).length !== 1) throw new Error("Elija exactamente uno: --estimar, --simulado o --real");

  const carpeta = join(process.cwd(), "..", "evaluacion", a.conjunto);
  const o: OpcionesEvaluacion = { carpeta, modos: a.modos, ejemplosPorClase: a.ejemplos, maxPorClase: a.maxPorClase, topeUsd: a.topeUsd ?? 1000 };
  let fotos: number;
  try {
    fotos = leerConjunto(carpeta, a.modos, a.maxPorClase).length;
  } catch {
    throw new Error(`No hay fotos en ${carpeta} (falta manifest.json). Para "colombia" vea evaluacion/colombia/LEEME.md`);
  }
  if (fotos === 0) throw new Error("No hay fotos para esos modos.");

  const est = estimarEvaluacion(o);
  console.log(`Fotos: ${fotos}. Ejemplos por clase: ${a.ejemplos}. Modelo: ${cargarConfig({}).modeloFoto}.`);
  console.log(`ESTIMACIÓN de costo (no es una medición; tokens supuestos, precios de src/costos.ts):`);
  for (const s of est.escenarios) console.log(`  ${s.nombre.padEnd(20)} US$ ${s.usd.toFixed(2)}`);
  if (a.estimar) return void console.log("\n(Solo estimación: no se llamó a la IA.)");

  if (a.real) {
    if (a.topeUsd === undefined || a.topeUsd <= 0) throw new Error("Con --real hay que poner --tope-usd (el gasto máximo de esta corrida)");
    if (!process.env.ANTHROPIC_API_KEY) throw new Error("Falta ANTHROPIC_API_KEY en el entorno (no se escribe en ningún archivo)");
  }
  const ia = a.real ? crearClienteIA() : iaSimulada();
  console.log(a.real ? `\nLlamando a la IA de verdad (tope ${a.topeUsd} USD)…` : "\nSIMULADO: IA falsa.");
  const r = await ejecutarEvaluacion(ia, { ...o, topeUsd: a.topeUsd ?? 1000 }, (h, t) => process.stdout.write(`\r${h}/${t}`));
  console.log();
  const m = calcular(r.filas);
  const md = informeMarkdown(
    { fecha: new Date().toISOString().slice(0, 10), modelo: cargarConfig({}).modeloFoto, conjunto: a.conjunto, ejemplosPorClase: a.ejemplos, simulado: !a.real },
    m,
  );
  console.log("\n" + md);
  if (r.incompleta) console.log(`\n⚠ La corrida se detuvo antes de terminar (${r.motivoParada}). Los números son parciales.`);
  if (a.real) {
    const dir = join(process.cwd(), "..", "evaluacion", "resultados");
    mkdirSync(dir, { recursive: true });
    const base = join(dir, `${new Date().toISOString().replace(/[:.]/g, "-")}_${a.conjunto}_ej${a.ejemplos}`);
    writeFileSync(`${base}.md`, md + (r.incompleta ? `\n> Corrida incompleta: ${r.motivoParada}\n` : ""));
    writeFileSync(`${base}.json`, JSON.stringify({ opciones: { ...a }, incompleta: r.incompleta, filas: r.filas, metricas: m }, null, 2) + "\n");
    console.log(`\nGuardado en ${base}.md y .json`);
  }
}

main().catch((e) => {
  console.error(`Error: ${e instanceof Error ? e.message : String(e)}`);
  process.exit(1);
});
