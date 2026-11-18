# Chat del lote (Fase 5)

Pantalla "Preguntar sobre el lote" (botón en el detalle del lote).

## Cómo responde

1. **Con internet y servidor configurado** (`--dart-define=BACKEND_URL=...`): la app manda a
   `POST /chat` la pregunta, el contexto del lote (etapa, horas y hasta 8 registros), hasta 6
   turnos anteriores y hasta 4 fragmentos de la base de conocimiento (`assets/conocimiento/base.json`)
   elegidos por palabras. La IA debe apoyarse en esos fragmentos y citarlos; la app muestra la
   fuente real de cada fragmento citado.
2. **Sin internet, sin servidor o si la IA falla**: responde `RespuestasLocales` con lo que hay en
   el teléfono (datos del lote, base de conocimiento, preguntas frecuentes y glosario) y avisa
   "La IA necesita conexión a internet". Si el servidor dio un aviso (por ejemplo, límite diario),
   se muestra antes.
3. Lo que no encuentra, lo dice y remite al técnico, la asociación o FEDECACAO.

Aviso fijo siempre visible: "Es una guía, no reemplaza al técnico."

## Qué sale del teléfono

Solo con internet: la pregunta, etapa, horas y medidas (temperatura, humedad, pH, Brix, temp.
ambiente) de los últimos registros, turnos anteriores y los textos de los fragmentos. **No** salen
el nombre del lote, las observaciones, la ubicación ni los identificadores del lote; el ID de
instalación va en una cabecera solo para contar el límite diario. Hay pruebas que lo comprueban
(`test/chat_service_test.dart`, `test/chat_screen_test.dart`). El historial de la conversación
queda solo en el teléfono (tabla `chat_mensajes`, se borra con el lote o con el botón de borrar).

Anthropic conserva las entradas y salidas de la API hasta 30 días: la política de privacidad
(Fase 7) debe decirlo y el consentimiento formal también va en esa fase.

## Piezas

| Archivo | Qué hace |
|---|---|
| `lib/services/buscador_conocimiento.dart` | Búsqueda por palabras (sin tildes, raíz de 5 letras, puntaje mínimo) |
| `lib/services/chat_historial.dart`, `lib/models/mensaje_chat.dart` | Historial por lote (base de datos v6) |
| `lib/services/contexto_lote.dart` | Contexto que se manda a la IA, con los rangos del servidor |
| `lib/services/chat_service.dart` | Cliente HTTP de `/chat` y sus errores |
| `lib/services/respuestas_locales.dart` | Respuestas sin internet y los 5 botones rápidos |
| `lib/screens/chat_screen.dart` | Pantalla |

## Qué NO se verificó

- Nada se probó contra la API real de Anthropic ni contra un servidor desplegado. La captura
  `f5_chat_con_ia_simulada.png` usa un texto de EJEMPLO de un servidor simulado.
- Que la búsqueda por palabras entienda la forma de escribir de los productores (ortografía,
  dictado, jerga): solo se probó con preguntas escritas por quien programó la app.
- Que el chat se vea bien en teléfonos reales de gama baja y con texto grande.
- Si el servidor está configurado pero no hay señal, la espera antes de caer a la guía local
  puede llegar a 40 s (no hay botón de cancelar).
