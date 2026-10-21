# Contrato de datos del mapa (v1)

Fijado el 19/10/2026 para que el pipeline (`lector/mapa/`) y la app (`app/`) trabajen en paralelo. Cambiarlo requiere avisar al orquestador.

## Dónde viven los archivos

- v1: **dentro del APK**, en `app/assets/mapa/`. El mapa funciona sin conexión desde la primera vez y no depende de GitHub Pages.
- Más adelante, los mismos archivos pueden publicarse en `data/mapa/` (Pages) con idéntico formato. La app los lee a través de una abstracción (`FuenteMapa`), así que agregar Pages no cambia la pantalla.

```
assets/mapa/
  indice.json
  base.json               fondo de OpenStreetMap (calles con nombre, río, arroyos, barrios)
  agua/0400.json … 1050.json   una capa por cada 10 cm
  curvas/2025-07.json …    curvas reales de Dinagua (referencias)
```

## `indice.json`

```json
{
  "version": 1,
  "generado": "2026-10-19T18:00:00-03:00",
  "cero": "Local",
  "validado": false,
  "modelo": {
    "metodo": "Relleno conectado al río sobre el MDT de IDE Uruguay (1 m, vuelo 2017), calibrado con crecidas de Dinagua",
    "delta_m": 0.66,
    "iou_validacion": 0.74,
    "margen_m": 0.5
  },
  "limites": [[-32.365, -58.150], [-32.240, -58.030]],
  "paso_m": 0.10,
  "min_m": 4.00,
  "max_m": 10.50,
  "base": { "archivo": "base.json", "bytes": 268774, "sha256": "…" },
  "capas": [
    { "altura_m": 4.00, "archivo": "agua/0400.json", "bytes": 18000, "sha256": "…" }
  ],
  "referencias": [
    { "tipo": "crecida", "nombre": "Crecida de diciembre de 2015", "altura_m": 9.12, "fecha": "2015-12-10",
      "archivo": "curvas/2015-12.json", "bytes": 0, "sha256": "…", "fuente": "Dinagua" }
  ],
  "fuentes": [
    "© colaboradores de OpenStreetMap, ODbL",
    "Modelo digital del terreno: IDE Uruguay, Licencia de Datos Abiertos – Uruguay. Datos modificados.",
    "Curvas de inundación: Dirección Nacional de Aguas (Dinagua), Ministerio de Ambiente"
  ]
}
```

Reglas:
- `cero` debe ser igual al `cero` de `actual.json` ("Local"). Si no coincide, la app no pinta la altura de hoy.
- `capas` ordenadas por `altura_m` ascendente, paso constante `paso_m`, sin huecos, de `min_m` a `max_m`.
- Nombre de archivo: altura en cm con 4 dígitos (`6.70 m` → `agua/0670.json`).
- `bytes` y `sha256` son del archivo tal como queda en disco.
- Todas las alturas en metros, cero local de la escala de Paysandú.

## `agua/NNNN.json`

GeoJSON `FeatureCollection` con **un** `Feature`:
- `geometry`: `MultiPolygon` (puede tener huecos para zonas altas secas), EPSG:4326, `[lon, lat]`, 5 decimales.
- Solo el agua **sobre tierra** conectada al río a esa altura: **sin** el cauce normal (el cauce ya está en `base.json`).
- `properties`: `{ "altura_m": 6.70 }`.
- Anidadas: la capa de `h` está contenida en la de `h + 0.10` (tolerancia 1 %).
- Puede estar vacía (`"coordinates": []`) si a esa altura el agua no sale del cauce.

## `curvas/AAAA-MM.json`

GeoJSON `FeatureCollection` con un `Feature` `MultiPolygon` y `properties`: `nombre`, `altura_m` (cota_local), `fecha`, `fuente`.

## `base.json`

Formato de `docs/mapa/herramientas/extraer_osm.py`: `FeatureCollection` donde cada `Feature` tiene `properties.t`:
- `"agua"`: polígono de río o espejo de agua;
- `"curso"`: línea de arroyo (`n` = nombre, puede ser null);
- `"calle"`: línea con `k` (1 = principal, 2 = avenida, 3 = calle de barrio) y `n` (nombre, puede ser null).

Además, en la raíz: `"lugares": [{ "n": "Barrio Paysandú Sur", "c": [lon, lat] }]` y `"caja": [O, S, E, N]`.

## Cómo elige la app qué capa pintar

- Altura de hoy `h` (de `actual.json`, la misma que usa Gráfico). Se **redondea hacia arriba** al siguiente múltiplo de 0,10 (prudencia: mejor mostrar un poco más de agua).
- `h < min_m`: no se pinta agua sobre tierra; la pantalla dice que el agua está en su cauce.
- `h > max_m`: se pinta la capa de `max_m` y se avisa que el río supera lo que cubre el mapa.
- Margen: la franja entre la capa de `h` y la de `h + margen_m` se dibuja aparte, como "puede llegar un poco más".
