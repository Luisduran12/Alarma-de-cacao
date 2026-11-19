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

## Revisión de seguridad del servidor (2026-11-18)

Revisión del código de `backend/` línea por línea. **No se ejecutó contra servicios reales ni se desplegó nada.**

### Lo que se comprobó y está bien
- **Entradas y tamaños:** esquemas `zod` estrictos (`.strict()`, rechazan campos extra), tope de cuerpo por ruta
  (24 KB chat, 2,6 MB foto, 1 KB lugar) aplicado *mientras se lee*, JPEG validado marcador por marcador (recorrido
  lineal, sin decodificar), coordenadas solo de Colombia. Los errores de validación no devuelven el texto del usuario.
- **Registro sin datos:** `registro.ts` solo deja pasar 8 claves y valores con forma de código; un ID, una IP, una
  pregunta o unas coordenadas que se colaran por error se descartan. El ID y la IP se anonimizan con HMAC y un secreto
  del servidor antes de contarse.
- **Límites:** por IP y hora, por instalación y día, y tope de gasto diario de todo el servidor; se cuentan los intentos
  fallidos también; `BLOQUEO_TOTAL=1` corta chat y fotos (y `LUGAR_DESACTIVADO=1` corta lugar).
- **SSRF:** ninguna ruta hace una petición a una dirección que venga del usuario. Los destinos son fijos: Nominatim
  (la URL se arma con coordenadas numéricas redondeadas), Anthropic (el SDK) y Upstash (de una variable de entorno, que
  debe empezar por `https://`).
- **Inyección de instrucciones:** el texto del usuario va entre etiquetas con `<` y `>` neutralizados y el prompt dice
  que es información, no órdenes (mitigación, no garantía: ver "Riesgos conocidos").
- **Dependencias:** `npm audit` sin vulnerabilidades (0).

### Hallazgos corregidos (con pruebas en `backend/test/`)

| # | Hallazgo | Riesgo | Corrección |
|---|---|---|---|
| 1 | En **preview** de Vercel (URL pública que puede heredar `ANTHROPIC_API_KEY`) el servidor usaba el secreto de desarrollo —que es público— y un almacén **en memoria**, que en serverless no cuenta nada entre instancias: sin límite real de gasto. | Medio | `esEntornoDesplegado()` (`config.ts`): producción, preview y `NODE_ENV=production` fallan cerrado (sin secreto o sin Upstash, se rechaza todo). Solo el desarrollo local usa el modo de desarrollo. |
| 2 | Una excepción imprevista dependía del manejo por defecto de la plataforma. | Bajo | `envolverSeguro()` envuelve las 3 rutas: error 500 genérico, sin mensaje ni traza; solo se anota un código. |
| 3 | El texto libre que la IA devuelve en las fotos (`posibles_causas`, `pasos_recomendados`) podía traer un enlace o un teléfono copiado de un cartel dentro de la foto. | Bajo-medio | El prompt lo prohíbe y `validarResultado` descarta las frases con enlaces, correos, usuarios o teléfonos (sin tocar cifras técnicas normales). |
| 4 | `vercel.json` no declaraba cabeceras de seguridad. | Bajo | Cabeceras `X-Content-Type-Options`, `Cache-Control: no-store`, `X-Frame-Options`, `Referrer-Policy`, `Content-Security-Policy`, `Cross-Origin-Resource-Policy`, `Strict-Transport-Security` y `Permissions-Policy`. **CORS restringido por no abrirlo:** no hay ninguna cabecera `Access-Control-Allow-*` (la app móvil no es un navegador); una prueba lo comprueba. |
| 5 | El servidor **guarda en Upstash, 30 días, el nombre del lugar de cada punto redondeado (~110 m)** (caché de `/lugar`), y la política de privacidad decía que no guardaba nada. | Transparencia | La política de la app y `docs/privacidad.md` ahora lo dicen (sin relación con la persona ni con el ID). |

### Pendientes (no se cambiaron: más riesgo o necesitan decisión)
1. **El tope de gasto no es atómico:** se consulta antes de llamar a la IA y se suma después; muchas peticiones
   simultáneas pueden pasarse un poco del tope (acotado por tokens máximos × concurrencia). Solución posible: reservar
   un gasto estimado antes de llamar.
2. **La IP sale de `x-real-ip`.** En Vercel la pone la plataforma; si el servidor se mudara a otro proveedor, hay que
   revisar que no la pueda falsear el cliente. Si faltaran ambas cabeceras, todos comparten una cubeta llamada
   `desconocida`.
3. **El ID de instalación lo genera la app:** no es autenticación. Play Integrity sigue sin implementarse (arriba).
4. **Inyección de instrucciones en el chat:** la respuesta del chat no se filtra en busca de enlaces (solo la de fotos);
   la pregunta es del propio usuario y el daño está acotado.
5. **Nada probado contra servicios reales** (Anthropic, Upstash, Vercel) ni prueba de penetración.
6. `/lugar` guarda coordenadas redondeadas aunque la IA no esté involucrada: si se quiere cero retención, hay que quitar
   la caché (más llamadas a Nominatim, que limita a 1 por segundo).
