# Calidad del producto según ISO/IEC 25010

Autoevaluación de Cacao Light 4.0 contra las 8 características de calidad del modelo ISO/IEC 25010. Cada fila dice
**qué evidencia hay** (una prueba, un archivo o una medición) y su estado. Lo que no se ha podido comprobar está como
**pendiente**; no se infló nada.

**Estados:** ✅ con evidencia automática · 🟡 parcial (hay diseño o pruebas, pero falta probar en el mundo real) ·
⬜ pendiente (no se ha hecho ni medido).

## Mediciones reales (2026-11-18, en el computador de desarrollo)

| Medición | Resultado | Cómo se obtuvo |
|---|---|---|
| Pruebas de la app | **625 pasan, 0 fallan** (42 archivos en `test/`) | `flutter test` |
| Pruebas del servidor | **241 pasan, 0 fallan** (9 archivos) | `cd backend && npm test` |
| Análisis estático de la app | **4 avisos "info", 0 advertencias, 0 errores** en `lib` y `test` | `flutter analyze lib test` |
| Vulnerabilidades conocidas del servidor | **0** | `cd backend && npm audit` |
| Cobertura de líneas de la app | **81,4 %** (3.749 de 4.605 líneas de 81 archivos) | `flutter test --coverage`. `lib/app.dart` y `lib/utils/csv_utils.dart` no los carga ninguna prueba y no entran en el cálculo. |
| Archivos con menos cobertura | `ver_registro_screen.dart` 0 %, `export_utils.dart` 0 %, `home_screen.dart` 1 %, `comparacion_lotes_screen.dart` 1 %, `dictado.dart` 0 % (necesita un teléfono) | mismo informe |
| Tamaño del APK release | **71,5 MB** (un solo APK con 3 arquitecturas); por arquitectura: **arm64-v8a 27,7 MB**, armeabi-v7a 25,9 MB, x86_64 29,1 MB. APK debug: 171 MB (no es el que se reparte). Firmados con la clave de debug (no hay keystore de release todavía). | `flutter build apk --release` y `--split-per-abi`, 2026-11-18. Casi todo son librerías nativas (64 MB de 71). |
| Búsqueda de claves en el APK | Prefijo de la clave antigua de OpenWeatherMap, el prefijo de las claves de Anthropic, la palabra `OPENWEATHER` y patrones de clave (`x-api-key`, `Bearer`, `api_key`): **0 coincidencias** en el APK release y en el debug. "ANTHROPIC" solo aparece como la palabra visible "Anthropic" en textos de la app. | APK descomprimido y revisado con `grep` y `strings` |
| Tiempo de arranque, consumo de batería, memoria | **No medidos** | Falta probar en un teléfono de gama baja |

Las pruebas corren en el computador con el motor de pruebas de Flutter. **Ninguna se ha ejecutado en un teléfono
Android real.**

## 1. Adecuación funcional

| Subcaracterística | Evidencia | Estado |
|---|---|---|
| Completitud funcional | Todas las funciones del README tienen pruebas: alarmas (`alarm_scheduler_test`), recordatorios (`recordatorios_test`), reglas (`reglas_alerta_test`), curva (`curva_ideal_test`, `resumen_curva_test`, `curva_lote_chart_test`), GPS (`location_service_test`, `punto_secado_test`), clima (`clima_service_test`, `clima_screen_test`), chat (`chat_service_test`, `chat_screen_test`), fotos (`foto_service_test`, `fotos_pantallas_test`), respaldo y borrado (`copia_seguridad_test`), ajustes (`ajustes_test`). | ✅ en pruebas · 🟡 en uso real |
| Corrección funcional | Rangos con fuente (`lib/data/referencias_curva.dart`, `docs/fuentes-curva.md`, `referencias_curva_test`); 61 citas literales verificadas contra los documentos (`tool/verificar_conocimiento.py`, `base_conocimiento_test`); un error de interpolación entre etapas se encontró y corrigió con pruebas. | ✅ |
| Pertinencia funcional | Varios lotes en paralelo (`varios_lotes_test`: IDs de alarma únicos, estados e historial independientes). Las guías **no han sido revisadas por un técnico** ni validadas con productores. | 🟡 |
| Exactitud del análisis de fotos con IA | **No medida.** El script `npm run evaluar` existe (`docs/evaluacion.md`), pero nunca se corrió contra la API real. Las fotos de prueba son de Brasil (granos) y de Santander/Antioquia (moniliasis), con etiquetas inferidas de nombres de archivo en el primer conjunto. | ⬜ |

## 2. Eficiencia de desempeño

| Subcaracterística | Evidencia | Estado |
|---|---|---|
| Comportamiento temporal | Sin medición. Decisiones de diseño: GPS espera máximo 30 s y usa la última ubicación; la app abre sin esperar un fix (`location_service_test`); todo lo esencial es local (SQLite). | ⬜ medición |
| Utilización de recursos | Fotos reducidas a 1024 px y sin metadatos antes de enviarse (`foto_preparada_test`); sin ubicación continua ni servicios en segundo plano (revisión del código: no hay `getPositionStream`, WorkManager ni servicios en primer plano; solo alarmas del sistema y un temporizador de 30 s de la barra de progreso mientras está visible); el ahorro de batería quita el video de fondo, los nombres de lugar y el reintento automático (`lib/main.dart`, `home_screen.dart`, `fotos_lote_screen.dart`). | 🟡 diseño, sin medir en teléfono |
| Capacidad | Límites del servidor y tope de gasto diario (`backend/test/almacen_limites_costos.test.ts`); la base local es SQLite con índices por lote. No se probó con muchos lotes ni con fotos de 12 MP en gama baja. | 🟡 |

## 3. Compatibilidad

| Subcaracterística | Evidencia | Estado |
|---|---|---|
| Coexistencia | La app no usa servicios en segundo plano propios. Sin prueba con otras apps. | 🟡 |
| Interoperabilidad | Exporta CSV, PNG, PDF y un respaldo JSON (`exportar_curva_test`, `copia_seguridad_test`); abre mapas con un enlace; el servidor habla con Anthropic y Nominatim; el clima, con Open-Meteo. | ✅ |
| Versiones de Android | `minSdk` 24 (Android 7.0), `targetSdk` 35, `compileSdk` 36 (`android/app/build.gradle.kts`). No hay prueba en ninguna versión ni marca de teléfono (los fabricantes que bloquean alarmas en segundo plano son un riesgo conocido, mitigado por la red de seguridad de `reprogramarFaltantes`). | 🟡 |

## 4. Usabilidad

| Subcaracterística | Evidencia | Estado |
|---|---|---|
| Reconocibilidad de la adecuación | Aviso fijo "Es una guía, no reemplaza al técnico" en chat, guía y resultados; semáforo con ícono y palabra, no solo color (`fotos_pantallas_test`). | 🟡 sin usuarios |
| Capacidad de aprendizaje | Glosario y guía rápida sin internet (`ajustes_test`, grupo Ayuda); guía ilustrada de la prueba de corte (`guia_prueba_corte_test`). | 🟡 |
| Operabilidad | Botones de al menos 48 dp (`accesibilidad_tema_test`); letra normal, grande y muy grande (1, 1,3 y 1,6) sin desbordes al 200 % en 360×640 (`ajustes_test`); dictado por voz opcional (`dictado_test`, con motor simulado). | ✅ en pruebas |
| Protección contra errores del usuario | Confirmaciones al borrar y al recuperar una copia; validación de rangos al registrar; la foto borrosa pide otra en vez de adivinar. | ✅ |
| Estética de la interfaz | Sin evaluación. | ⬜ |
| Accesibilidad | Auditoría automática con las guías de Flutter (objetivo táctil 48 dp, etiquetas, contraste de texto) en 8 pantallas (Ajustes, Política, Créditos, Ayuda, guía de la prueba de corte, resultado de foto, pregunta de ubicación y detalle del lote), con tema normal y de alto contraste (`accesibilidad_pantallas_test`, 48 pruebas); contraste WCAG 2.1 AA calculado (`accesibilidad_tema_test`). La auditoría encontró y se corrigió un fallo de contraste (2,33:1) en las tarjetas de color. **Sin probar con TalkBack ni con personas.** Más tarde se auditaron también el registro de volteada, el chat, el clima, la lista de fotos y la comparación de lotes (`accesibilidad_pantallas2_test`, 30 pruebas, sin fallos). Sin auditar: la pantalla de inicio (tiene video de fondo). | 🟡 |
| Validación con productores | Pendiente: encuesta y guion en la Fase 8; no hay resultados. | ⬜ |

## 5. Fiabilidad

| Subcaracterística | Evidencia | Estado |
|---|---|---|
| Madurez | 625 pruebas; sin uso real. | 🟡 |
| Disponibilidad | Lo esencial funciona sin internet (SQLite, alarmas del sistema, guía local). Las alarmas con la app cerrada y tras reiniciar **no se han probado en un teléfono**. | 🟡 |
| Tolerancia a fallos | Si una notificación falla, el guardado sigue (`alertas_ui_test`); si el GPS no responde, se usa la última ubicación y se avisa; si no hay señal, las fotos quedan en cola (`fotos_pantallas_test`); si falla un paso de "Borrar todo", se informa cuál (`copia_seguridad_test`). | ✅ |
| Capacidad de recuperación | Respaldo exportar/importar validado y todo-o-nada: un archivo malo (16 casos de validación) o un fallo a mitad no cambia nada y devuelve las alarmas (`copia_seguridad_test`); red de seguridad que reprograma alarmas perdidas al abrir la app (`alarm_scheduler_test`, `varios_lotes_test`); migración de datos antiguos (`migracion_v3_test`, `lote_service_test`). | ✅ |

## 6. Seguridad

| Subcaracterística | Evidencia | Estado |
|---|---|---|
| Confidencialidad | La app no lleva claves: la de Anthropic vive solo en el servidor (`backend/`). El contexto que sale hacia la IA excluye el nombre del lote y la ubicación (`chat_service_test`, `backend/test/chat.test.ts`); las fotos salen sin EXIF/GPS (`foto_preparada_test`, `backend/test/jpeg.test.ts`); HTTP sin cifrar desactivado; consentimiento previo para ubicación, fotos y voz (`location_service_test`, `fotos_pantallas_test`, `dictado_test`). **Falta** descomprimir el APK y buscar claves (Fase 9). | 🟡 |
| Integridad | El servidor valida con esquema estricto lo que recibe y lo que devuelve la IA (`backend/test`); el respaldo se valida columna por columna al importar. | ✅ |
| No repudio / Responsabilidad | El registro del servidor solo guarda códigos y números (`backend/test/config_http_registro.test.ts`). | ✅ |
| Autenticidad | **Play Integrity no está implementado**: el ID de instalación lo genera la app y no prueba nada. La defensa real es el tope de gasto diario y los límites por IP (`docs/backend-seguridad.md`). | ⬜ |
| Resistencia a abuso | Límites por instalación, IP y día; tope de gasto diario; falla cerrado si faltan el almacén o el secreto (`backend/test/almacen_limites_costos.test.ts`); `npm audit` en 0. **Nunca se probó contra Upstash ni contra la API real, y no hay prueba de penetración.** | 🟡 |
| Cumplimiento (Ley 1581 de 2012) | Autorización previa para la ubicación, política en la app y en `docs/privacidad.md` (con la nota de la retención de hasta 30 días de Anthropic), y "Borrar todos mis datos" (`privacidad_test`, `ajustes_test`, `copia_seguridad_test`). **No la ha revisado un abogado** y falta definir el responsable y su contacto. | 🟡 |
| Incidente conocido | La clave de OpenWeatherMap del commit `cb55257` sigue en el historial público; **debe revocarse** (tarea del autor). | ⬜ |

## 7. Mantenibilidad

| Subcaracterística | Evidencia | Estado |
|---|---|---|
| Modularidad | Pantallas (`lib/screens`), servicios (`lib/services`), datos (`lib/data`) y servidor (`backend/`) separados; los servicios reciben sus dependencias por parámetro para poder probarse. | ✅ |
| Reusabilidad | Rangos de referencia, reglas, textos de consentimiento y política en una sola fuente cada uno (`referencias_curva.dart`, `reglas_alerta.dart`, `politica_privacidad.dart`); la política del documento se genera desde el código (`tool/generar_privacidad.dart`) y una prueba comprueba que coincidan. | ✅ |
| Capacidad de ser analizado | Documentación en `docs/` y comentarios que explican el porqué; cada dato técnico lleva su fuente. | ✅ |
| Capacidad de ser modificado | Migraciones de la base versionadas (de la v1 a la v7). | ✅ |
| Capacidad de ser probado | 625 + 241 pruebas; cobertura 81,4 %. GitHub Actions (`.github/workflows/ci.yml`) corre analyze, test y `npm test`, **pero aún no se ha ejecutado en GitHub**. | 🟡 |
| Deuda conocida | 4 avisos de análisis (API `Share` obsoleta en `csv_utils.dart`, un `BuildContext` tras un `await` en `ver_registro_screen.dart`, un `const` faltante); `image` fijado en 4.8.0 porque 4.11.0 no compila con `archive` 4.0.9; pantallas sin pruebas (`ver_registro_screen`, `home_screen`, `comparacion_lotes_screen`). | 🟡 |

## 8. Portabilidad

| Subcaracterística | Evidencia | Estado |
|---|---|---|
| Adaptabilidad | Se adapta al tamaño de letra del teléfono (se multiplica, no se reemplaza; `accesibilidad_tema_test`) y a pantallas de 360×640 con letra al 200 % (`ajustes_test`). | ✅ en pruebas |
| Instalabilidad | `applicationId` `com.luisduran.cacaolight`; firma de release desde `android/key.properties` (documentada en el README). El APK compila (debug y release, firmados con la clave de debug); la keystore de release **la crea el autor** (`docs/firma-release.md`) y no existe todavía. `speech_to_text` pide NDK 28.2 y el proyecto usa 27: compila, pero Gradle lo advierte. 🟡 |
| Capacidad de reemplazo | Los datos se pueden sacar (CSV, JSON de respaldo) y la app no depende de una cuenta. | ✅ |
| Otras plataformas | Existen carpetas de iOS, Linux, macOS y Windows generadas por Flutter, pero **solo se apunta y se prueba Android**. | ⬜ |

## Lo que más falta para poder afirmar calidad

1. Probar en teléfonos Android reales de gama baja: alarmas con la app cerrada y tras reiniciar, GPS, cámara, permisos, TalkBack.
2. Medir tamaño del APK, arranque y batería; buscar claves dentro del APK (Fase 9).
3. Desplegar el servidor y medir el acierto de la IA con fotos locales clasificadas por un técnico.
4. Validar con 3 a 5 productores (Fase 8) y que un técnico revise las guías.
5. Revisión legal de la política de privacidad; revocar la clave de OpenWeatherMap.
