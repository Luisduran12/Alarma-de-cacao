# Probar Cacao Light en un teléfono Android real

APK de reparto: **arm64-v8a** (`build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`, 27.658.057 bytes).
SHA-256: `07d923a4da6a7bf6c4cfe62326d10778e7650b71aacd91276a1fe855614633a6`. Paquete `com.luisduran.cacaolight`,
versión 1.0.0 (el `versionCode` sale 2001 porque Flutter suma 2000 a la versión arm64), `minSdk` 24, `targetSdk` 35.

> **Aviso 1 — firma.** Este APK está firmado con la **clave de debug** (todavía no existe la keystore de release,
> ver `docs/firma-release.md`). Sirve para probar. Cuando exista la keystore, el teléfono **no dejará actualizar encima**:
> habrá que desinstalar la app (y se pierden los datos: haga antes una copia de seguridad).
>
> **Aviso 2 — sin servidor.** Se compiló **sin `BACKEND_URL`**. El chat con IA, el análisis de fotos y el nombre exacto
> del lugar **no funcionarán**: eso es lo esperado (el servidor no está desplegado). Se prueban las respuestas locales,
> la cola de fotos y los avisos de "sin conexión".
>
> **Aviso 3 — registros.** El APK es `release`: `debugPrint` no escribe en `adb logcat`. Se prueba mirando la pantalla.

## 1. Instalar por USB con adb

En el teléfono: **Ajustes → Acerca del teléfono →** toque 7 veces "Número de compilación" → **Opciones de
desarrollador → Depuración por USB** (activar). Conecte el cable y acepte "¿Permitir depuración USB?".

```bash
# adb viene con el Android SDK (si no está en el PATH, use la ruta completa)
export PATH="$HOME/Library/Android/sdk/platform-tools:$PATH"

adb devices                                        # debe salir el teléfono como "device" (no "unauthorized")
adb shell getprop ro.product.cpu.abi               # debe decir arm64-v8a; si dice armeabi-v7a use el APK armeabi-v7a
adb shell getprop ro.build.version.sdk             # debe ser 24 o más

cd ~/alarmacacao5_0
shasum -a 256 build/app/outputs/flutter-apk/app-arm64-v8a-release.apk   # compare con la huella de arriba
adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk  # -r: reinstala conservando datos
adb shell monkey -p com.luisduran.cacaolight -c android.intent.category.LAUNCHER 1   # abrir la app
```

Si `adb install` dice `INSTALL_FAILED_UPDATE_INCOMPATIBLE`, hay otra versión firmada con otra clave:
`adb uninstall com.luisduran.cacaolight` y vuelva a instalar.

**Comandos útiles durante la prueba**

```bash
# ¿Qué alarmas tiene programadas la app? (una línea por alarma, con su hora)
adb shell dumpsys alarm | grep -A3 "com.luisduran.cacaolight" | head -60

# Notificaciones activas y su canal
adb shell dumpsys notification --noredact | grep -A6 "com.luisduran.cacaolight" | head -40

# Permisos concedidos
adb shell dumpsys package com.luisduran.cacaolight | grep -E "granted=(true|false)" | head -20

# Dar o quitar un permiso sin entrar a Ajustes
adb shell pm grant com.luisduran.cacaolight android.permission.POST_NOTIFICATIONS
adb shell pm revoke com.luisduran.cacaolight android.permission.ACCESS_FINE_LOCATION

# Cerrar la app "a la fuerza" y reiniciar el teléfono
adb shell am force-stop com.luisduran.cacaolight
adb reboot

# Modo avión (internet apagado; el GPS sigue funcionando)
adb shell cmd connectivity airplane-mode enable     # y "disable" para quitarlo (en algunos teléfonos no funciona: hágalo a mano)

# Traer al computador un archivo (por ejemplo, la copia de seguridad guardada en Descargas)
adb pull /sdcard/Download/cacao_light_respaldo_AAAA-MM-DD.json ~/Desktop/

# Captura de pantalla para el informe
adb exec-out screencap -p > ~/Desktop/captura.png

# Quitar todo al final
adb uninstall com.luisduran.cacaolight
```

## 2. Lista de revisión de 15 pasos

Marque cada paso **Pasa / Falla / No se pudo** y anote qué pasó (modelo del teléfono, versión de Android y de la app).
Un fallo es información útil: no lo "arregle" probando de nuevo hasta que salga.

**Teléfono:** __________  **Android:** ____  **Fecha:** ____  **Batería ahorro del fabricante:** ☐ activado ☐ desactivado

| # | Qué hacer | Qué debe pasar | Pasa / Falla | Notas |
|---|---|---|---|---|
| 1 | Abrir la app por primera vez. | Aparece la pantalla **"¿Usar la ubicación del teléfono?"** con su explicación **antes** de cualquier cuadro de Android. | | |
| 2 | Tocar **"Sí, usar mi ubicación"**. | Android muestra su cuadro de permiso de ubicación. Concederlo ("mientras uso la app"). Luego pide permiso de notificaciones (y de alarmas exactas en Android 12+; si lo pide en Ajustes, concederlo). | | |
| 3 | Ir a **Ajustes (engranaje) → Sus autorizaciones**. Apagar y encender "Usar mi ubicación". | El interruptor cambia y recuerda su estado al salir y volver. Con la ubicación apagada, "Marcar punto de secado" dice que falta la autorización. | | |
| 4 | Con la app **abierta**, tocar la campana "Probar alarma (10 s)". | A los ~10 s aparece la notificación y suena el **sonido propio** de la app (no el predeterminado). | | |
| 5 | Repetir la campana y **cerrar la app** deslizándola fuera de recientes antes de los 10 s. Bloquear la pantalla. | La alarma **suena con la app cerrada** y la pantalla bloqueada. Tocarla abre el formulario de registro. | | |
| 6 | Crear un lote con **horas personalizadas** (un volteo a ~15 min). Revisar con `adb shell dumpsys alarm \| grep -A3 cacaolight`. | El lote se crea con su alarma; `dumpsys` muestra alarmas de la app. La alarma suena a la hora con la app cerrada. | | |
| 7 | Crear otro lote personalizado con un volteo a ~20 min y **reiniciar el teléfono** (`adb reboot`). No abrir la app. | Tras reiniciar, **la alarma sigue sonando a su hora** sin abrir la app. Si no suena, abrir la app: debe **reprogramarla** (red de seguridad). Anote si falló sin abrirla. | | |
| 8 | Abrir un registro: anotar temperatura 45 y humedad 80. Tocar el **micrófono** de la observación. | Primero explica y pide autorización de la voz. Con permiso del micrófono, escribe lo dicho. Sin internet puede fallar: debe avisar y dejar escribir con el teclado. Guardar el registro. | | |
| 9 | Activar **modo avión** (GPS encendido). En el registro de **secado**, tocar el punto de secado. | Tarda hasta 30 s; guarda latitud y longitud **sin internet** y muestra "Cerca de [centro poblado o municipio]". Si usa la última ubicación conocida, lo **avisa**. Siempre se puede guardar sin ubicación. | | |
| 10 | Aún sin internet: abrir **Clima**. | Dice que no hay señal y deja **escribir temperatura y humedad a mano**; aclara que es clima del aire, no de la masa. | | |
| 11 | Abrir **Fotos del lote → Nueva foto**, elegir "Prueba de corte". Tomar una foto. | Pide autorización antes de la primera foto. Sin servidor/sin internet la foto **queda en espera** ("espera señal") y no se pierde. Dice que no hay conexión, sin mensajes técnicos. | | |
| 12 | Abrir el **chat** del lote sin internet. Tocar un botón rápido (p. ej. "¿Cuándo volteo?"). | Responde con la **guía guardada en el teléfono**, con su fuente, y muestra "Es una guía, no reemplaza al técnico". | | |
| 13 | **Ajustes → Guardar copia de seguridad.** Enviarla a WhatsApp/Drive o guardarla. Borrar un lote. **Recuperar copia de seguridad** y elegir el archivo. | Muestra qué trae la copia y pide confirmación. Tras recuperar, el lote borrado **vuelve con sus registros**. Un archivo que no es un respaldo (p. ej. una foto) se rechaza sin cambiar nada. | | |
| 14 | **Ajustes → Tamaño de letra: Muy grande** y **Alto contraste**. Recorrer inicio, registro, detalle del lote y chat. Probar al sol. Si puede, activar **TalkBack** y recorrer el registro. | Nada se corta ni se sale de la pantalla; todo se puede tocar con el dedo; se lee con sol. TalkBack lee cada botón con un nombre entendible. | | |
| 15 | **Ahorro de batería:** activarlo y reabrir la app. Luego **Ajustes → Borrar todos mis datos** → confirmar. | Con ahorro, no hay video de fondo. Al borrar, pide confirmación, avisa lo de los 30 días de Anthropic y vuelve a la pregunta de ubicación; no queda ningún lote, foto ni alarma (`dumpsys alarm` sin alarmas de la app). | | |

## 3. Si algo falla en un teléfono real
- **La alarma no suena con la app cerrada:** casi siempre es el "ahorro de batería" del fabricante (Xiaomi, Huawei,
  Samsung, Oppo...). Pruebe: Ajustes → Batería → la app → "Sin restricciones", y permitir "Alarmas y recordatorios".
  Anote la marca y el modelo: es el dato más importante de la prueba.
- **No pide permiso de notificaciones:** en Android 13+ se concede en el primer arranque; si lo negó, está en Ajustes de la app.
- **Cierre inesperado:** conecte el cable y mire `adb logcat -b crash`.
- Cualquier fallo: tome captura (`adb exec-out screencap -p`) y anote el paso. Con esas notas se corrige y queda en `CHANGELOG.md`.

## 4. Qué NO prueba esta lista
Acierto de la IA, el servidor, el rendimiento en gama baja, el consumo de batería a largo plazo ni la usabilidad con
productores (para eso, `docs/validacion/`).
