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

## Agregados v1.1 (21/10/2026, tras el control de calidad 11)

Todos son **compatibles hacia atrás**: `version` sigue en 1 y si un campo falta, la app hace lo de antes.

### 1. Zonas sin validar: `sin_validar.json` (nuevo, opcional)

En `indice.json`:

```json
"sin_validar": { "archivo": "sin_validar.json", "bytes": 0, "sha256": "…" }
```

`sin_validar.json` es una `FeatureCollection` con un `Feature` `Polygon`/`MultiPolygon` por zona, EPSG:4326, `[lon, lat]`, 5 decimales.
- `properties`: `{ "nombre": "Valle del arroyo San Francisco", "motivo": "No hay crecidas medidas por Dinagua para comparar el modelo." }`.
- Para la v1 hay una sola zona: el valle del arroyo San Francisco Grande, todo lo que el modelo moja allí hasta 10,50 m, agrandado unos 100 m.
- La app la dibuja encima del agua con su propio estilo y la nombra en la leyenda y en el resumen textual.

### 2. Lomas aisladas: propiedad `aisladas` en cada capa (nueva, opcional)

En `agua/NNNN.json`, `properties` suma:

```json
"aisladas": [ { "c": [-58.08712, -32.31234], "ha": 1.4, "calles_m": 320 } ]
```

- Son las tierras secas totalmente rodeadas por el agua de esa capa, es decir, huecos interiores del MultiPolygon que no tocan el borde de `limites`.
- Solo se incluyen las que tienen al menos 50 m de calle de `base.json` adentro (`calles_m`), porque así se considera que pueden estar habitadas.
- `c` es un punto interior, `ha` el área en hectáreas.
- Lista vacía o ausente: no hay ninguna.
- La app marca cada punto y avisa: "Quedaría rodeada de agua: aunque no se inunde, puede quedar aislada."

### 3. Zona baja de la costa (sin archivo nuevo)

La capa de `min_m` (4,00 m) ya incluye unas 450 ha de islas, bañados y planicies que se mojan con el río normal. Regla de la app:
- Esa capa se dibuja **siempre**, a cualquier altura, con un estilo propio: "Zona baja de la costa: se moja con el río normal".
- Nunca se esconde agua.
- Con `h < min_m`, la app ya no dice "el agua está en su cauce". Dice que el agua no pasa de la zona baja de la costa (texto exacto en 09).

### 4. Margen siempre visible

La franja de margen (entre la capa de `h` y la de `h + margen_m`) se dibuja **siempre** que haya capas, incluso con `h < min_m` o `h > max_m` (en ese caso, hasta la capa máxima). Es condición para publicar (11 §Condiciones).

### 5. Pipeline

- Se agranda el agua **5 m** antes de simplificar con tolerancia de 4 m (antes 4 m), para que ninguna celda mojada quede afuera después del redondeo a 5 decimales (11 §5).
