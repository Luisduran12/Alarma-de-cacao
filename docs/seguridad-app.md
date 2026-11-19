# Revisión de seguridad de la app (2026-11-18)

Revisión del código y del `AndroidManifest.xml`. Complementa `docs/backend-seguridad.md` (servidor). **No se probó en un
teléfono real.** Las pruebas que vigilan estos puntos están en `test/seguridad_app_test.dart`.

## Lo que se comprobó y está bien
- **Sin claves ni servidor dentro del código ni del APK.** No hay claves (búsqueda en `lib/`); la dirección del servidor
  solo entra por `--dart-define=BACKEND_URL`. El APK release compilado se descomprimió y no tenía claves ni la URL de ningún
  servidor (ver `docs/calidad.md`).
- **Solo HTTPS.** `usesCleartextTraffic="false"` y ninguna dirección `http://` en el código.
- **Componentes exportados.** Solo `MainActivity` (la pantalla de inicio) está exportada; los tres receptores de
  alarmas son `exported="false"`.
- **Autorizaciones.** Ubicación: sin ella no se pide el permiso del sistema (`location_service_test`). Voz: sin ella no se
  abre el micrófono (`dictado_test`). Fotos: ver el hallazgo 2.
- **"Borrar todos mis datos"** borra la base (lotes, registros, recordatorios, chat, fotos, lugares), las fotos y su
  carpeta, el CSV exportado, la carpeta temporal, todas las preferencias (autorizaciones, ajustes, reglas, curva ideal,
  ID de instalación) y cancela las alarmas (`copia_seguridad_test`).
- **Copia de seguridad.** No incluye fotos, ni autorizaciones, ni el ID de instalación, ni ajustes; solo lotes, registros,
  recordatorios, chat, caché de lugares, curva ideal y reglas (`copia_seguridad_test`, `seguridad_app_test`).
- **Paquetes.** `flutter pub get` y `flutter pub outdated` no muestran avisos de seguridad, descontinuados ni retirados.
  **No se pudo confirmar** que esta versión de `pub` consulte las alertas de seguridad (no hay un comando `audit`), así
  que esto no equivale a una auditoría. Hay muchos paquetes con versiones mayores nuevas (por ejemplo `geolocator` 10 →
  14, `flutter_local_notifications` 19 → 23); no se actualizaron porque cambiarían APIs sin poder probarlo en un teléfono.

## Hallazgos corregidos (con pruebas)

| # | Hallazgo | Corrección |
|---|---|---|
| 1 | **Copia automática de Android.** El manifest no desactivaba `allowBackup` (por defecto, activo): Android habría copiado la base de datos (registros, ubicaciones), las fotos y las preferencias (incluidas las autorizaciones y el ID de instalación) a la nube del usuario y a un teléfono nuevo, contra lo que dice la política ("todo queda en su teléfono"). | `allowBackup="false"`, `fullBackupContent="false"` y `res/xml/data_extraction_rules.xml` (excluye todo, para Android 12+). Para cambiar de teléfono se usa la copia de seguridad de Ajustes. |
| 2 | **La autorización de fotos solo se revisaba al tomar la foto.** Una foto que estaba en cola se enviaba aunque el productor hubiera quitado la autorización en Ajustes. | `FotoService.analizar` exige la autorización vigente al ENVIAR: sin ella no sale ninguna petición, la foto sigue guardada y en cola (`foto_service_test`: 3 pruebas nuevas). |
| 3 | `requestLegacyExternalStorage="true"` (permiso heredado de almacenamiento, sin uso). | Eliminado. |

## Pendientes
1. **El chat no tiene un consentimiento propio.** Lo que se pregunta y el contexto del lote (etapa, horas y hasta 8
   registros) viajan al servidor y a Anthropic, y la política de privacidad lo dice, pero no hay una pantalla de "¿Aceptar?"
   antes de la primera pregunta como en fotos y voz. Conviene agregarla (Ley 1581).
2. **Paquetes desactualizados** (arriba): planificar una actualización y probarla en un teléfono real.
3. **Dependencia de Google para la voz:** el reconocimiento de voz lo hace el servicio del teléfono, fuera del control de
   la app. Está advertido en el aviso de la voz y en la política.
4. **Sin ofuscación del código ni protección contra manipulación del APK** (nada de esto se evaluó).
5. **El ID de instalación** sigue siendo un dato estable por instalación (no hay cuenta).
