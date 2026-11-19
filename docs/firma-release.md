# Firma del APK de release

La app se firma con una **keystore propia** de Cacao Light (`applicationId` `com.luisduran.cacaolight`).
**No se reutiliza ninguna de las keystores de `AlarmaCacaoLite`:** son de otra app (otro `applicationId`).

> **Perder la keystore o su contraseña impide publicar actualizaciones** de la app para siempre. Guarde dos copias
> fuera del computador (por ejemplo, una memoria USB y un gestor de contraseñas) y **nunca** la suba a git, al
> correo ni a un chat.

## 1. Crear la keystore (en su terminal, una sola vez)

Fuera de la carpeta del proyecto, por ejemplo en `~/claves-cacaolight/`:

```bash
mkdir -p ~/claves-cacaolight
keytool -genkeypair -v \
  -keystore ~/claves-cacaolight/cacaolight-release.jks \
  -alias cacaolight \
  -keyalg RSA -keysize 2048 -validity 10000
```

`keytool` le pregunta la contraseña (la escribe usted, no se muestra) y sus datos. Anote la contraseña en su gestor de
contraseñas. Con `-validity 10000` la clave dura unos 27 años.

## 2. Decirle a Gradle dónde está

```bash
cp android/key.properties.ejemplo android/key.properties
```

Edite `android/key.properties` y llene los cuatro valores (`storeFile` con la ruta completa a la `.jks`):

```properties
storePassword=<la que eligió>
keyPassword=<la misma, si no puso otra>
keyAlias=cacaolight
storeFile=/Users/<usuario>/claves-cacaolight/cacaolight-release.jks
```

`android/key.properties` y `*.jks` ya están en `.gitignore`. `android/app/build.gradle.kts` lee ese archivo y, si
existe, firma el release con él; si no existe, firma con la clave de debug (sirve para probar, Google Play no la acepta).

## 3. Compilar y comprobar la firma

```bash
flutter build apk --release
# o, para Google Play, un paquete .aab:
flutter build appbundle --release

# huella de la firma del APK (necesita el Android SDK instalado):
$ANDROID_HOME/build-tools/<versión>/apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk
```

Si el APK sale firmado con la clave de debug, `apksigner` mostrará `CN=Android Debug`: revise la ruta de `storeFile`.

## 4. Comprobar que nada secreto está en git

```bash
git ls-files | grep -iE '\.jks$|\.keystore$|key\.properties$'   # debe salir vacío (key.properties.ejemplo no cuenta)
git log --all --oneline -S"storePassword=" -- android          # no debe mostrar commits con contraseñas
```

Estado al 2026-11-18: ninguna keystore, `key.properties` ni contraseña está en git (ver `docs/calidad.md`).

## Google Play App Signing

Si se publica en Google Play, conviene activar *Play App Signing*: la keystore de este documento pasa a ser la "clave de
carga" y, si se pierde, Google permite restablecerla. Sin Play App Signing no hay forma de recuperarla.
