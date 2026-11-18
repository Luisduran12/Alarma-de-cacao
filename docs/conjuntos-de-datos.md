# Conjuntos de fotos de cacao: qué se puede usar

Investigación del 2026-11-18. **La hizo un agente auxiliar leyendo las páginas y las API de
metadatos; yo (quien programa la app) solo volví a comprobar los dos conjuntos que ya se usan
(Zenodo, ver `docs/creditos.md`).** Todo lo demás está tal como lo reportó y debe confirmarse en
la página antes de descargar. Roboflow Universe devolvió 403 y no se pudo leer. No es asesoría legal.

## En uso

| Conjunto | Licencia | Para qué |
|---|---|---|
| Zenodo 10.5281/zenodo.22824982 (granos cortados, Brasil) | CC BY 4.0 (verificado en la API de Zenodo) | corte |
| Zenodo 10.5281/zenodo.17716661 (CocoaMoniliaDataSet, Colombia) | CC BY 4.0 (verificado) | mazorca: sana y monilia |

## Candidatos con licencia abierta declarada (sin descargar aún)

| Conjunto | Licencia declarada | Qué aportaría | Cautela |
|---|---|---|---|
| Mendeley pcx7mj68yn.4 (Antunes, 2019) | CC BY 4.0 | 14 clases de corte, 100 fotos por clase (pizarroso y moho por separado) | Fotos de laboratorio, no de celular. El artículo relacionado (Santos et al. 2019) es CC BY-NC-ND y los autores difieren: **confirmar la procedencia y la licencia con los autores antes de redistribuir en la app**; mientras tanto, solo como material interno de evaluación |
| Mendeley z5n4fy9whk.1 "cocoaNoise" (2025) | CC BY 4.0 | Moho y pizarroso cortados; plano, roto y germinado | No se vio el número de imágenes ni el tamaño; abrir la ficha y contar |
| Harvard Dataverse BBGQSP (KaraAgroAI, Ghana) | CC0 1.0 | Sana, antracnosis y CSSVD en mazorca, hoja y tallo | Enfermedades de Ghana, no de las que importan aquí (no hay mazorca negra ni monilia); su campo "Terms of use" menciona un acceso temporalmente no disponible: verificar |
| Zenodo 7968314 (RipSetCocoaCNCH12, EAFIT, Colombia) | CC BY 4.0 | Madurez de mazorca | No sirve para enfermedades; 27 GB |
| Mendeley hvwth9dsfd.2 (CocoaSwolSet) | CC BY 4.0 | Virus del brote hinchado | Poco relevante |
| Kaggle zaldyjr/cacao-diseases | CC BY-SA 4.0 | Mazorca negra, sana y barrenador (≈4.300 fotos) | Origen de las fotos incierto (Filipinas); la cláusula de compartir igual puede obligar a licenciar derivados igual |

## Descartados

- **No comercial:** Kaggle bryandarquea/cocoa-diseases (CC BY-NC-SA), juanfelipeheredia/cocoa-ripeness (CC BY-NC-SA), luiszhinin979/ecuadorian-cocoa-beans (CC BY-NC), lehetasa/colombian-cocoa-dataset (CC BY-NC-SA, además es tabular).
- **Sin licencia declarada:** Kaggle kenfackbruno/black-pod-rot-and-pod-borer ("Unknown"), khawaritzmiabdallah/cocoa-beans-image-dataset ("Unknown").
- **Licencia contradictoria entre copias:** Amini Cocoa Contamination y Zindi-Cocoa.
- **Procedencia dudosa:** Kaggle serranosebas/enfermedades-cacao-yolov4 (UNAB, Colombia; sana, Phytophthora y monilia): ODbL cubre la base de datos pero el contenido queda como "© Original Authors". **Es lo más cercano a Colombia con mazorca negra; habría que pedir permiso por escrito a la UNAB.**
- Roboflow Universe: no se pudo leer; las licencias las declara quien sube y pueden mezclar fotos de terceros.

## Lo que falta y cómo cubrirlo

1. **Mazorca negra con fotos de campo y licencia limpia: no hay.** Opciones: permiso de la UNAB para su conjunto, o fotografiar con productores y técnicos (`evaluacion/colombia/`).
2. **Grano seco con defectos** (moho, insectos, humedad): lo más cercano es cocoaNoise; sin cantidades verificadas.
3. **Pizarroso separado de moho:** Antunes (Mendeley), con la cautela de procedencia.
4. **AGROSAVIA y Fedecacao:** no se encontraron conjuntos abiertos; no se consultaron sus repositorios directamente. Preguntarles.
5. **Fotos locales clasificadas por un técnico** son lo más valioso para saber el acierto real.
