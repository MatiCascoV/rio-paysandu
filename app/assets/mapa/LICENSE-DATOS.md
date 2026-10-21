# Datos del mapa de inundación — licencias

## Base de datos derivada de OpenStreetMap (ODbL 1.0)

Los archivos `base.json`, `agua/*.json`, `sin_validar.json` e `indice.json` de esta carpeta
contienen información de OpenStreetMap y se ofrecen bajo la Open Database License (ODbL) 1.0:
https://opendatacommons.org/licenses/odbl/1-0/
Los derechos sobre los contenidos individuales de la base se licencian bajo la
Database Contents License: https://opendatacommons.org/licenses/dbcl/1-0/

© colaboradores de OpenStreetMap — https://www.openstreetmap.org/copyright
Extracto usado: Geofabrik, `south-america/uruguay-latest.osm.pbf`, descargado el 21/10/2026.
Cómo se generan (ODbL §4.6): el código está en `lector/mapa/` de este repositorio
(`python -m mapa <salida>`); ver `docs/mapa/06-informe-pipeline.md`.

## Modelo digital del terreno (Licencia de Datos Abiertos – Uruguay)

Las capas `agua/*.json` y `sin_validar.json` se calcularon con datos de la
Infraestructura de Datos Espaciales de Uruguay (IDE Uruguay):
- "MDT urbano de Paysandú, 1 m" (Remesa Urbana 09, vuelo de octubre de 2017), y
- "MDT nacional, 2,5 m" (Remesa 04, vuelo 2017–2018),
del conjunto "Ortoimagen y modelo digital del terreno de cobertura nacional"
(https://catalogodatos.gub.uy/dataset/ide-ortoimagen-mdt-de-cobertura-nacional).
Licencia de Datos Abiertos – Uruguay:
https://www.gub.uy/agencia-gobierno-electronico-sociedad-informacion-conocimiento/sites/agencia-gobierno-electronico-sociedad-informacion-conocimiento/files/documentos/publicaciones/licencia_de_datos_abiertos_0.pdf
Modificaciones hechas por Mi Río UY: recorte al área de Paysandú, unión de los dos MDT,
remuestreo a 2 m, cauces de arroyos de OpenStreetMap marcados en el terreno, cálculo del área
conectada al río por debajo de cada altura (cada 10 cm), ajuste con crecidas reales,
agrandado de 5 m, simplificación y conversión a GeoJSON.

## Curvas de crecidas (`curvas/*.json`) — Dinagua

Curvas de inundación de la Dirección Nacional de Aguas (Dinagua), Ministerio de Ambiente,
del servicio WFS https://www.ambiente.gub.uy/dinagua-gs/dinagua/wfs (capa `curvas_cri`).
Son información pública (Ley 18.381). Dinagua no publicó una licencia para estas capas;
las citamos como pide la Licencia de Datos Abiertos – Uruguay y estamos consultando al
organismo. Si Dinagua lo pide, las retiramos.
Modificaciones: recorte a Paysandú, reproyección a WGS84, simplificación y conversión a GeoJSON.

## Aviso

Mi Río UY es un proyecto comunitario sin vínculo con la IDE, el Ministerio de Ambiente,
CARU, el Cecoed, la Intendencia ni la Fundación OpenStreetMap, que no avalan este trabajo.
Los datos se ofrecen "tal cual", sin garantía.
