# Datos de la pestaña Crecidas — fuentes y licencias

## Bordes de las crecidas (`curvas/*.json`) — Dinagua

Curvas de inundación de la Dirección Nacional de Aguas (Dinagua), Ministerio de Ambiente,
del servicio WFS https://www.ambiente.gub.uy/dinagua-gs/dinagua/wfs (capa `dinagua:curvas_cri`,
filtro `nombre LIKE 'PA-PSD%'`), pedidas el 19/10/2026 y verificadas iguales el 21/10/2026.
Son información pública (Ley 18.381) y se usan citando la fuente. Dinagua no publicó una
licencia para estas capas. Si Dinagua lo pide, las retiramos.

La altura (`altura_m`, el campo `cota_local` de Dinagua), la fecha y el nombre de cada crecida
son los que da Dinagua, sin cambios.

Modificaciones hechas por Mi Río UY: recorte a Paysandú, reproyección a WGS84, simplificación
(unos 2 m), y conversión del polígono a líneas sin los tramos rectos con que Dinagua cierra
la zona relevada sobre el cauce del río (no marcan hasta dónde llegó el agua). Los bordes en
tierra conservan los puntos de Dinagua. Script: `docs/crecidas/bordes_crecidas.py`; detalle en
`docs/crecidas-anteriores.md`.

## Base de datos derivada de OpenStreetMap (ODbL 1.0) — `base.json`

`base.json` (río, arroyos, calles y nombres de barrios) contiene información de OpenStreetMap
y se ofrece bajo la Open Database License (ODbL) 1.0:
https://opendatacommons.org/licenses/odbl/1-0/
Los derechos sobre los contenidos individuales de la base se licencian bajo la
Database Contents License: https://opendatacommons.org/licenses/dbcl/1-0/

© colaboradores de OpenStreetMap — https://www.openstreetmap.org/copyright
Extracto usado: Geofabrik, `south-america/uruguay-latest.osm.pbf`, descargado el 21/10/2026.
La base derivada es este mismo archivo (`app/assets/crecidas/base.json` del repositorio).
Se generó con el script `docs/crecidas/extraer_osm.py` de este mismo repositorio, a partir de ese
extracto, sin cambios posteriores.

`indice.json` solo lista los archivos, sus huellas y estas fuentes.

## Aviso

Mi Río UY es un proyecto comunitario sin vínculo con el Ministerio de Ambiente, Dinagua,
CARU, el Cecoed, la Intendencia ni la Fundación OpenStreetMap, que no avalan este trabajo.
Los datos se ofrecen «tal cual», sin garantía.
