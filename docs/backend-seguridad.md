# Seguridad del servidor: qué protege, qué no, y Play Integrity

Complementa `backend/README.md`. Aquí se explica el razonamiento y se dicen con claridad
los límites.

## El riesgo principal

La app va en teléfonos de terceros: **cualquier cosa que lleve dentro se puede sacar**. Por
eso la clave de Anthropic vive solo en el servidor. Pero un servidor sin controles es un
"grifo abierto": quien descubra la dirección puede gastar tu dinero sin tener la clave. Las
defensas, de la más sólida a la más débil:

| # | Defensa | Qué evita | Qué NO evita |
|---|---|---|---|
| 1 | **Tope de gasto diario de todo el servidor** (`PRESUPUESTO_DIARIO_USD`, 5 USD por defecto) | Que un abuso cueste más que ese tope por día. Cada llamada suma su costo real (tokens reales × precio oficial) | Que un abuso consuma ese tope y deje sin servicio a los productores ese día |
| 2 | **Interruptor de emergencia** (`BLOQUEO_TOTAL=1`) | Parar todo en un minuto desde Vercel | — |
| 3 | **Límite por IP y hora** (300) | Un solo origen que fabrica muchos IDs | Muchos orígenes distintos. Ojo: en el campo muchos teléfonos comparten la IP del operador, por eso el límite es alto |
| 4 | **Límite por instalación y día** (30 chats, 10 fotos) | Uso excesivo de una misma instalación | **Alguien que fabrica IDs nuevos**: el ID lo genera la app y no prueba nada |
| 5 | Tamaños máximos (cuerpo, imagen, mensaje), esquema estricto | Cuerpos gigantes, peticiones que cuestan mucho, datos que no deberían viajar | — |
| 6 | Límites de tokens de salida (600 chat, 4.000 foto) | Respuestas larguísimas | — |
| 7 | **Falla cerrado** | Si el almacén de contadores o el secreto faltan, se rechaza todo en vez de dejar pasar sin control | — |

**Conclusión honesta:** los límites por instalación (4) son una mitigación, **no una
autenticación**. La protección real contra el abuso es el tope de gasto (1). Con 5 USD por
día, el peor día de abuso cuesta 5 USD.

## Play Integrity: ¿es viable?

Fuente: <https://developer.android.com/google/play/integrity/overview> (leída el 2026-11-18).

**Qué hace.** Devuelve a tu servidor veredictos firmados por Google: si la app es el binario
sin modificar que Google Play reconoce (`appRecognitionVerdict` = `PLAY_RECOGNIZED`), si se
instaló desde Google Play (`appLicensingVerdict` = `LICENSED`) y si corre en un dispositivo
genuino y certificado (`MEETS_DEVICE_INTEGRITY`, etc.). Es justo lo que cubriría el hueco
del punto 4. Cuota por defecto: 10.000 solicitudes por día entre todas las instalaciones
(se puede pedir más). La propia documentación recomienda usarlo **junto con otras
defensas, no como la única**.

**Por qué NO se implementó ahora:**

1. **Depende de cómo se distribuya la app.** Los veredictos de app y de licencia solo son
   buenos si la app se instaló **desde Google Play**. Si se reparte el APK por WhatsApp,
   memoria USB o descarga directa (lo normal si la app todavía no está en Play), el
   servidor vería que **todas** las instalaciones "no son reconocidas" y, si se exigiera,
   **bloquearía a todos los productores legítimos**. Hay que publicar primero en Google
   Play (aunque sea en una pista de pruebas) y entonces evaluar.
2. **Teléfonos de gama baja.** La documentación advierte que "fewer devices are in the higher
   trust tiers", y recomienda una aplicación escalonada en lugar de exigir el nivel alto. Un
   teléfono barato o sin certificar puede quedar fuera de `MEETS_DEVICE_INTEGRITY`: exigirlo
   dejaría sin servicio justamente a quienes más necesitan la app.
3. **Requiere cosas que no existen todavía:** un proyecto de Google Cloud vinculado a la
   consola de Play, integración nativa en la app (un plugin de Flutter o código Android),
   y decodificar y validar el veredicto en el servidor con credenciales de Google. Nada de
   eso se puede probar sin la app publicada y un teléfono real.
4. Implementarlo a medias daría una **falsa sensación de seguridad**: peor que no tenerlo.

**Cómo se haría cuando esté viable** (recomendación de Google, que coincide con el sentido
común): (a) publicar en Google Play; (b) integrar Play Integrity en modo **solo
telemetría**, sin bloquear a nadie, y ver qué veredictos devuelven las instalaciones reales
de los productores; (c) con esos datos, aplicar una exigencia **escalonada y suave** (por
ejemplo, límites más bajos para quien no pase, en vez de bloquear). Mientras tanto la
defensa es el tope de gasto.

## Lo que se guarda y lo que no

- **En el servidor (Upstash Redis):** contadores con vencimiento (clave = HMAC del ID o de
  la IP, nunca el valor original), el gasto del día, un cerrojo de 1,1 s para Nominatim y el
  caché de nombres de lugar (coordenadas redondeadas a ≈110 m → nombre; no se asocia a
  ninguna instalación). **Nunca**: preguntas, respuestas, fotos, ID o IP en claro.
- **En el registro (Vercel):** una línea por evento con códigos y números (endpoint, estado,
  modelo, tokens, costo, milisegundos). Hay una lista permitida: cualquier otro dato se
  descarta aunque alguien lo pase por error.
- **Las coordenadas van en el cuerpo de las peticiones**, no en la URL, para que no queden en
  los registros de acceso de la plataforma.

## Lo que está fuera del control de este servidor

- **Anthropic conserva lo que recibe por la API.** Su política oficial
  (<https://privacy.claude.com/en/articles/7996866-how-long-do-you-store-my-organization-s-data>,
  leída el 2026-11-18) dice que las entradas y salidas se borran de su almacenamiento "within
  30 days", con excepciones: hasta 2 años si una conversación se marca por violar su política
  de uso, y por acuerdo (por ejemplo, cero retención). Así que **no es cierto decir "no se
  guarda nada"**: lo cierto es "este servidor no guarda nada; el proveedor de IA puede
  conservarlo hasta 30 días". La política de privacidad de la app (Fase 7) y el aviso de
  consentimiento antes de enviar una foto deben decir esto.
- **No se verificó** si Anthropic usa por defecto los datos de la API para entrenar: la página
  consultada no lo dice y remite a otra que no se leyó.
- **Nominatim (OpenStreetMap)** recibe las coordenadas redondeadas del lugar para devolver su
  nombre. Su `User-Agent` lleva el contacto de quien administra el servidor
  (`NOMINATIM_CONTACTO`), como exige su política.
- **El ID de instalación** es anónimo, pero es un identificador estable de la instalación;
  conviene mencionarlo en la política de privacidad (Ley 1581 de 2012).

## Riesgos conocidos y pendientes

- Ver "Qué NO se verificó" en `backend/README.md`: nada se probó contra la API real de
  Anthropic, ni contra Upstash, ni desplegado en Vercel.
- La inyección de instrucciones dentro de una pregunta o de los fragmentos de la base de
  conocimiento se mitiga (etiquetas, `<` y `>` neutralizados, instrucción de tratarlo como
  información) pero **no se puede garantizar al 100 %**: se prueba que el texto no escape de
  sus etiquetas, no que el modelo nunca obedezca. El daño posible está acotado: la pregunta
  y los fragmentos son del propio usuario, y las respuestas tienen tope de longitud y de costo.
- La IA puede equivocarse. Las respuestas del chat y de las fotos llevan siempre el aviso de
  que son una guía; los porcentajes de las fotos son estimaciones y su exactitud real **no
  está medida** (es la Fase 6B).
