# Servidor de Cacao Light

Funciones de Vercel (TypeScript) que hacen tres cosas que **no se pueden hacer dentro de la
app** sin exponer una clave o saltarse una regla de uso:

| Ruta | Para qué | Modelo |
|---|---|---|
| `POST /chat` | Responde preguntas de cacao con la IA | `claude-haiku-5-5` |
| `POST /analizar-foto` | Analiza una foto (prueba de corte, grano seco, mazorca u hoja) | `claude-sonnet-5-5` |
| `POST /lugar` | Resuelve el nombre de un lugar con Nominatim (OpenStreetMap), con caché | (sin IA) |

**La clave de Anthropic vive solo aquí**, como variable de entorno del servidor
(`ANTHROPIC_API_KEY`). La app nunca la lleva. Este código no la escribe en ningún archivo.

## Qué NO guarda este servidor

Ni preguntas, ni respuestas, ni fotos, ni coordenadas, ni el ID de instalación, ni la IP.
Solo guarda en Upstash Redis **contadores con vencimiento** (cuántas consultas hizo cada
instalación hoy, cuánto se gastó hoy) y el **caché de nombres de lugar** (coordenadas
redondeadas a ≈110 m → nombre). Los IDs y las IPs se anonimizan con un secreto del servidor
(`ID_PEPPER`) antes de usarse como clave de contador. El registro de errores solo deja
códigos y números. Hay pruebas automáticas de todo esto (`test/chat.test.ts`,
`test/foto.test.ts`, `test/config_http_registro.test.ts`).

> Lo que este servidor no controla: **Anthropic** conserva las entradas y salidas de la API
> hasta 30 días (más si la conversación se marca por violar su política de uso). La política
> de privacidad de la app debe decirlo. Ver `docs/backend-seguridad.md`.

## Contrato de las rutas

Todas piden la cabecera `X-Install-Id` con un UUID v4 (el ID de instalación anónimo que la
app genera una vez). Responden JSON y nunca se guardan en caché. Los errores tienen siempre
la forma `{ "error": { "codigo": "...", "mensaje": "..." } }` (con `Retry-After` cuando
tiene sentido esperar). La app solo debe mostrar el `mensaje` (viene escrito para el productor).

### `POST /chat`

```jsonc
{
  "mensaje": "¿Está normal mi temperatura?",          // 1 a 500 caracteres
  "contexto": {                                        // opcional
    "etapa": "fermentacion",                           // o "secado"
    "horas": 72,
    "registros": [                                     // hasta 8
      { "horas": 48, "temperatura": 42.5, "humedad": 85, "ph": 4.5, "brix": 10, "tempAmbiente": 26 }
    ]
  },
  "historial": [ { "rol": "usuario", "texto": "..." } ],   // hasta 6 turnos
  "fragmentos": [                                      // hasta 5, de la base de conocimiento de la app
    { "id": "F1", "fuente": "FHIA, InfoCacao No. 14 (2017), p. 4", "texto": "..." }
  ]
}
```

El esquema es **estricto**: cualquier campo no previsto (nombre del lote, ubicación, ID…) se
rechaza con 400. Respuesta:

```json
{ "respuesta": "…[F1]", "fuentes": [{ "id": "F1", "fuente": "…" }], "truncada": false,
  "aviso": "Es una guía, no reemplaza al técnico." }
```

`fuentes` son solo los fragmentos que la IA citó como `[F1]` y que sí se enviaron.

### `POST /analizar-foto`

```jsonc
{ "modo": "corte",            // "corte" | "grano_seco" | "mazorca_hoja"
  "imagen": "<JPEG en base64>" }   // ya reducida (máx. ~1024 px); el servidor acepta de 200 a 1600 px y hasta 1,8 MB
```

El servidor **limpia los metadatos** (EXIF con GPS, XMP, IPTC, comentarios) sin reencodificar
la imagen, aunque la app ya deba haberlos quitado. Respuesta:

```jsonc
{ "modo": "corte", "foto_valida": true,
  "repetir_foto": false,         // true = pedir otra foto; en ese caso NO hay porcentajes
  "motivo": "ninguno",           // borrosa | oscura | no_es_cacao | muy_lejos | otro
  "mensaje": "",                 // qué decirle al productor cuando repetir_foto es true
  "categorias": [ { "nombre": "bien_fermentado", "porcentaje": 70 } ],
  "confianza": "media", "posibles_causas": ["…"], "pasos_recomendados": ["…"],
  "semaforo": "verde",           // verde | amarillo | rojo
  "aviso": "Estimación orientativa. La clasificación oficial es la prueba de corte de la NTC 1252. Ante duda, consulte al técnico." }
```

Categorías por modo (las únicas que se aceptan; son una propuesta de esta app, alineadas con
las carpetas de referencia de la Fase 6B): `corte` → bien_fermentado, parcialmente_fermentado,
violeta, pizarroso, moho. `grano_seco` → sin_defectos, moho, dano_por_insectos,
humedad_visible. `mazorca_hoja` → sana, monilia, mazorca_negra, otra_posible_enfermedad.

Si la foto es mala **o la confianza es baja**, el servidor no entrega porcentajes: pide otra
foto en vez de adivinar. Si la IA devuelve algo incoherente (categorías inventadas,
porcentajes que no suman ≈100) responde 502 `respuesta_ia_invalida` y no lo entrega.

### `POST /lugar`

```json
{ "lat": 7.603, "lng": -72.601 }
```

Responde `{ "nombre": "Barrio El Dique, Chinácota, Norte de Santander", "fuente": "© colaboradores de OpenStreetMap (ODbL)" }`.
Las coordenadas van en el cuerpo (no en la URL) para que no queden en los registros de la
plataforma. Solo acepta lugares de Colombia. Cumple la política de Nominatim: máximo 1
consulta por segundo para toda la aplicación (cerrojo en el almacén compartido), caché de 30
días, `User-Agent` que identifica la aplicación, sin autocompletar. Política oficial:
<https://operations.osmfoundation.org/policies/nominatim/>.

## Códigos de error frecuentes

`id_invalido` (400), `peticion_invalida` (400), `cuerpo_muy_grande` / `imagen_muy_grande` (413),
`limite_dia` / `limite_ip` (429, con `Retry-After`), `presupuesto_agotado` / `servicio_pausado`
(503), `ia_ocupada` (503), `ia_no_disponible` (502), `respuesta_ia_invalida` (502),
`servidor_mal_configurado` (500).

## Variables de entorno

Ver `.env.example` (solo nombres). Obligatorias: `ANTHROPIC_API_KEY`, `ID_PEPPER` (16+
caracteres), y un almacén Redis (`UPSTASH_REDIS_REST_URL` + `UPSTASH_REDIS_REST_TOKEN`, o
`KV_REST_API_URL` + `KV_REST_API_TOKEN`). Para `/lugar` además `NOMINATIM_CONTACTO`.
**En producción, si falta el almacén o el secreto, el servidor rechaza todo** en lugar de
dejar pasar consultas sin límite.

Opcional: `REFERENCIAS_POR_CLASE` (0 a 5, por defecto 0): fotos de ejemplo de `referencias/` que se mandan
con cada foto. Déjela en 0 hasta medir con `npm run evaluar` (ver `docs/evaluacion.md`) que ayuda.

Límites por defecto (son propuestas de esta app para acotar gasto y abuso, no datos de
ninguna fuente; se cambian con variables): 30 preguntas y 10 fotos por instalación y por día,
100 consultas de lugar, 300 consultas por IP y hora, y un **tope de gasto de 5 USD por día**
para todo el servidor. Interruptores de emergencia: `BLOQUEO_TOTAL=1` (pausa chat y fotos) y
`LUGAR_DESACTIVADO=1`.

## Pruebas

```bash
cd backend
npm install --ignore-scripts
npm test            # 241 pruebas
npm run evaluar -- --ayuda   # mide el acierto de las fotos (ver docs/evaluacion.md)
npm run typecheck
```

Las pruebas usan una IA falsa y un `fetch` falso: **no gastan dinero ni salen a internet**.

## Desplegar (lo hace quien administra el proyecto)

Este código **no se ha desplegado**. Pasos, a cargo de quien tenga la cuenta de Vercel:

1. Crear el proyecto en Vercel con la carpeta `backend/` como raíz.
2. Añadir Upstash Redis desde el Marketplace de Vercel (crea las variables del almacén).
3. Configurar `ANTHROPIC_API_KEY`, `ID_PEPPER` y `NOMINATIM_CONTACTO` como variables de
   entorno **de producción** (nunca en el código ni en un archivo del repositorio).
4. Desplegar, y compilar la app con `--dart-define=BACKEND_URL=https://<su-proyecto>.vercel.app`.
5. Antes de abrirlo al público, revisar el tope de gasto (`PRESUPUESTO_DIARIO_USD`) y los
   límites. Mirar el costo real en los registros: cada llamada deja una línea con
   `tokens_in`, `tokens_out` y `costo_micro_usd`.

## Qué NO se verificó

- **Nada se probó contra la API real de Anthropic** (no hay clave en este entorno): las
  llamadas se validaron con los tipos del SDK oficial y con pruebas con IA falsa, no con
  respuestas reales. Si el esquema de la respuesta estructurada o algún parámetro fuera
  rechazado por la API, aparecería en la primera prueba real.
- Upstash Redis tampoco se probó contra el servicio real (solo con un `fetch` simulado).
- El despliegue en Vercel no se hizo.
- La política de Nominatim se leyó en su página oficial el 2026-11-18; puede cambiar.
