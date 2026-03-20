# Instrucciones para resolver problemas en AlarmaCacao

## Problema 1: No se guardan registros en dispositivos reales

### Pasos a seguir:

1. **Desinstalar completamente la aplicación**:
   - Ve a Ajustes > Aplicaciones > AlarmaCacao
   - Toca "Desinstalar" o "Eliminar"
   - Reinicia tu dispositivo

2. **Verificar permisos**:
   - Después de reinstalar, asegúrate de conceder todos los permisos solicitados
   - Ve a Ajustes > Aplicaciones > AlarmaCacao > Permisos
   - Activa todos los permisos, especialmente:
     - Notificaciones
     - Almacenamiento
     - Alarmas y recordatorios

3. **Probar el guardado**:
   - Crea un nuevo lote
   - Confirma una volteada
   - Verifica si se guarda correctamente

## Problema 2: Sonido de alarmas

### Verificación del sonido:

1. **Asegúrate de que el archivo de sonido existe**:
   - El archivo debe estar en `assets/sonido/sonido_base.mp3`
   - Verifica que el archivo no esté corrupto

2. **Probar el sonido**:
   - Activa una notificación instantánea desde la app
   - Verifica que se escuche el sonido

3. **Ajustes de volumen**:
   - Ve a Ajustes > Sonido > Volumen de notificaciones
   - Asegúrate de que el volumen no esté en silencio

## Problema 3: Diagnóstico avanzado

### Si los problemas persisten:

1. **Conectar el dispositivo al computador**:
   - Activa "Opciones de desarrollador" en tu dispositivo
   - Activa "Depuración USB"
   - Conecta el dispositivo al computador

2. **Ejecutar en modo debug**:
   - En la terminal, ejecuta: `flutter run --debug`
   - Observa los mensajes en la consola
   - Realiza las acciones que causan problemas
   - Copia los mensajes de error y envíalos para análisis

## Recomendaciones generales:

1. **Mantener la app actualizada**:
   - Usa siempre la última versión del código
   - Ejecuta `flutter pub get` después de cualquier cambio

2. **Limpiar la caché**:
   - Ejecuta `flutter clean` antes de generar una nueva APK
   - Elimina la carpeta `build/` si existe

3. **Verificar compatibilidad**:
   - Asegúrate de que la app es compatible con la versión de Android de tu dispositivo

## Soporte adicional:

Si después de seguir estos pasos el problema persiste, por favor:

1. Proporciona capturas de pantalla del error
2. Copia los mensajes de error del log
3. Indica la versión de Android de tu dispositivo
4. Describe paso a paso lo que estás haciendo cuando ocurre el error

Estas instrucciones te ayudarán a identificar y resolver los problemas más comunes con la aplicación AlarmaCacao.
