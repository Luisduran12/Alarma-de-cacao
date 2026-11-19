# Seguridad

Cacao Light es un **prototipo académico** (UNAD). Aun así, maneja datos de productores (ubicación, fotos, registros del
beneficio), así que se toma en serio cualquier vulnerabilidad.

## Cómo reportar una vulnerabilidad

**No abra una incidencia pública (issue) con los detalles.** Escriba al correo del proyecto: **[CORREO_DEL_PROYECTO]**
(el responsable lo reemplazará cuando exista), con:

- qué encontró y dónde (archivo, ruta del servidor o pantalla),
- cómo reproducirlo, y qué podría provocar,
- su nombre o apodo si quiere que se le agradezca (opcional).

También puede usar *Report a vulnerability* en la pestaña **Security** del repositorio de GitHub, si está activada.
Es un proyecto sin presupuesto: se responderá lo antes posible, sin plazos garantizados.

## Qué no se debe publicar nunca (ni en issues, ni en commits, ni en capturas)

- Claves de API, tokens o contraseñas, aunque estén "vencidas" o "de prueba".
- Keystores de firma (`*.jks`, `*.keystore`), `android/key.properties`, certificados (`*.pem`, `*.p12`).
- Archivos `.env`, bases de datos (`*.db`, `*.sqlite`) y copias de seguridad de la app (`cacao_light_respaldo_*.json`).
- Fotos, ubicaciones o nombres de productores, o datos que identifiquen a una persona.
- La dirección del servidor desplegado en documentos o capturas.
- Rutas de su computador (`/Users/...`) y nombres de usuario del sistema.

## Secretos: viven solo en variables de entorno del servidor

La app **no lleva ninguna clave**. Estos valores se configuran únicamente en Vercel (Project Settings → Environment
Variables) y nunca en un archivo del repositorio (`backend/.env.example` solo lista los nombres):

| Variable | Qué protege |
|---|---|
| `ANTHROPIC_API_KEY` | Acceso a la IA (con tope de gasto en la consola de Anthropic). |
| `ID_PEPPER` | Secreto para anonimizar IDs de instalación e IP antes de contarlos. |
| `UPSTASH_REDIS_REST_TOKEN` (o `KV_REST_API_TOKEN`) | Acceso al almacén de contadores. |
| `UPSTASH_REDIS_REST_URL` (o `KV_REST_API_URL`) | Dirección del almacén (tratarla como secreta). |
| `NOMINATIM_CONTACTO` | Contacto personal que exige la política de uso de OpenStreetMap. |

Del lado del teléfono, la contraseña de la keystore de firma (`android/key.properties`) vive solo en el computador del
autor y en un gestor de contraseñas (ver `docs/firma-release.md`).

## Si se filtra un secreto

1. **Revóquelo o rótelo de inmediato** en el servicio (Anthropic, Upstash, Vercel, OpenWeatherMap...). Borrar el commit no
   basta: lo publicado en GitHub debe darse por comprometido.
2. Avise por el correo del proyecto.
3. Después se limpia el código; reescribir el historial es opcional y no sustituye a la revocación.

**Incidente conocido:** la clave de OpenWeatherMap del primer commit (`cb55257`) sigue en el historial público de `main` y
**debe revocarse**; la app ya no la usa.

## Defensas del repositorio

- `.gitignore` bloquea claves, keystores, `.env`, `.apk`/`.aab`, bases de datos y respaldos.
- **Revisión de secretos en cada push y pull request** (gitleaks, `.github/workflows/ci.yml`; reglas en `.gitleaks.toml`).
- **Dependabot** semanal para Flutter (pub), npm (`backend/`) y GitHub Actions.
- **Gancho opcional** `.githooks/pre-commit` que bloquea commits con patrones de claves (ver README).
- El servidor falla cerrado si faltan sus variables de entorno (`docs/backend-seguridad.md`).

## Alcance

Esta política cubre este repositorio y el servidor en `backend/`. Los servicios de terceros (Anthropic, Open-Meteo,
OpenStreetMap, Vercel, Upstash) tienen sus propias políticas.
