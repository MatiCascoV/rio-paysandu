# Mapa de inundación — 01. Datos y pipeline

Investigación del 19/10/2026 (rama `mapa-inundacion`). Solo diseño: no hay código de producción.
Marcas: **[VERIFICADO]** = lo consulté en vivo hoy; **[NO VERIFICADO]** = deducido o pendiente.
Las muestras bajadas están en `C:\Users\matic\AppData\Local\Temp\claude\mapa-datos\` (fuera del repo, tratadas como datos no confiables).

## 0. Resumen

- El **MDT urbano de 1 m de Paysandú existe y se descarga sin registro** en hojas GeoTIFF de 1×1 km. Para la costa hacen falta 43 hojas (133 MB) **[VERIFICADO]**. Se puede hacer el pipeline con el MDT.
- **Trampa de datum:** el MDT está en cotas ortométricas **EGM2008**, no en Cero Oficial ni en el cero local de CARU **[VERIFICADO en el informe de metacalidad]**. Hay que calibrar el desfase. Primera estimación empírica: **MDT ≈ cota local + 0,66 m** (sale de la curva de jul-2025, que Dinagua hizo con este mismo MDT).
- Las curvas de Dinagua sirven para calibrar. Para mostrarlas solas sirven menos: cada relevamiento cubre una zona distinta y no están anidadas.
- Peso estimado: **10–40 KB comprimido por nivel**, y entre **1 y 2,5 MB comprimido** para las 66 capas de 4,0 a 10,5 m (extrapolado de 3 hojas medidas).

## 1. Dinagua — GeoServer WFS

Base: `https://www.ambiente.gub.uy/dinagua-gs/dinagua/wfs` **[VERIFICADO]**

| Operación | URL de prueba (GET) | Resultado |
|---|---|---|
| GetCapabilities | `?service=WFS&version=2.0.0&request=GetCapabilities` | 200, 126 KB, 75 capas. `AccessConstraints: NONE`, `Fees: NONE`. Declara solo GML 3.2 como `outputFormat`, pero **`application/json` funciona**. |
| DescribeFeatureType | `?service=WFS&version=2.0.0&request=DescribeFeatureType&typeNames=dinagua:curvas_cri,dinagua:curvas_tr` | 200, esquema abajo |
| GetFeature PA-PSD | `...&request=GetFeature&typeNames=dinagua:curvas_cri&outputFormat=application/json&srsName=EPSG:4326&CQL_FILTER=nombre LIKE 'PA-PSD%'` (URL-encodeado) | `curvas_cri`: 5 entidades, 185 KB · `curvas_tr`: 8 entidades, 485 KB. UTF-8 correcto. |

**Esquema**

| Capa | Campos | Geometría | CRS nativo |
|---|---|---|---|
| `dinagua:curvas_cri` | `gid, nombre, curso, fecha_evento (date), cota_local, cota_oficial, fuentes, realizadores, observaciones` | `MultiPolygon`, 1 polígono sin huecos | EPSG:32721 (se pide en 4326) |
| `dinagua:curvas_tr` | `gid, nombre, curso, cota_local, cota_oficial, tipo_curva, orden_v, fuentes, realizadores, observaciones, sigla_tipo_curva (con espacios a la derecha), categoria` | `MultiPolygon` | EPSG:32721 |

**Curvas de Paysandú — río Uruguay** (áreas en UTM 21S; todas `is_valid`)

| Curva | cota_local | cota_oficial | Δ | Vértices | Área | Fuente / método |
|---|---|---|---|---|---|---|
| CRI jul-2025 | 6,58 | 6,69 | +0,11 | 2.661 | 1.011 ha | CTM Salto Grande + **MDT urbano IDEuy** |
| Tr10 | 7,74 | 7,88 | **+0,14** | 4.552 | 1.360 ha | CTM 2014 + curvas de nivel cada 2 m |
| CRI jun-2017 | 8,35 | 8,46 | +0,11 | 1.276 | 1.201 ha | Intendencia + Dinagua |
| CRI ene-2019 | 8,45 | 8,56 | +0,11 | 1.797 | 1.529 ha | Dinagua |
| CRI nov-2009 | 8,93 | 9,04 | +0,11 | 327 | 1.161 ha | FAU, sensores remotos |
| CRI dic-2015 | 9,12 | 9,23 | +0,11 | 636 | 1.477 ha | Intendencia + Dinagua |
| Tr100 | 9,49 | 9,63 | **+0,14** | — | 2.120 ha | CTM 2014 |
| CMP | 14,07 | 14,21 | +0,14 | 7.076 | 3.065 ha | CTM 2014 (fuera de rango) |

`curvas_tr` también trae 6 curvas de los arroyos Sacra y La Curtiembre, sin cota. Como no tienen cota, no sirven para el deslizador.

Hallazgos:
- **El paso local→oficial es +0,11 en `curvas_cri` y +0,14 en `curvas_tr`** **[VERIFICADO en los datos]**. No sé cuál es el correcto, y **tampoco verifiqué que la `cota_local` de Dinagua use el mismo cero que la "altura" de CARU** que lee el lector. Con los valores actuales, el error posible por esto es de 3 cm o más.
- **Las áreas no crecen con la cota:** ene-2019 (8,45 m) tiene 1.529 ha y nov-2009 (8,93 m) tiene 1.161 ha. Es porque cada relevamiento cubre una zona distinta: recortadas a la ventana común de 4×8 km (EPSG:32721, x 394372–398402, y 6421407–6429522), las áreas sí crecen: 862 → 942 → 1.025 → 1.027 → 1.066 → 1.129 → 1.139 ha. Entre curvas consecutivas, el IoU va de 0,67 a 0,76 y la contención de 0,71 a 0,99: **no están anidadas**.
- Envolvente de todas las curvas (4326): lon −58,1645 a −58,0714, lat −32,3597 a −32,2416. El borrador de `02-tecnologia-app.md` propone `limites` hasta lat −32,29 y lon −58,12, que **corta el norte y el oeste**. Propongo `[[-32.365, -58.145], [-32.240, -58.030]]`.
- Licencia: el servicio no declara ninguna. `04-licencias-y-textos.md` ya resolvió citar la fuente por analogía con la Licencia de Datos Abiertos.

## 2. MDE de IDE Uruguay

Índice de descargas (Apache, sin registro): `https://visualizador.ide.uy/descargas/datos/` **[VERIFICADO]**
Paysandú es la **Remesa Urbana 09**, con fecha de vuelo **octubre de 2017** (según el informe de metacalidad).

| Producto | URL | Hojas | Tamaño | Formato |
|---|---|---|---|---|
| **MDT urbano 1 m** (recomendado) | `.../CU_Remesa_09/01_MDT_MDS/08_Ciudad_PSD/04_MDT_GeoTIFF_Resolucion_100cm/<HOJA>_MDT_Remesa_09_PSD.tif` | 87 en la ciudad; **43 tocan las curvas** (+300 m) | 267 MB en total; **133 MB las 43** (≈3,8 MB por hoja llena) | GeoTIFF float32, sin compresión, nodata −32767, `AREA_OR_POINT=Point` |
| MDT urbano 1 m, LAS | `.../03_MDT_LAS_Resolucion_100cm/` | 87 | ≈19 MB por hoja | LAS |
| MDS urbano 10 cm | `.../01_MDS_.../`, `02_MDS_GeoTIFF_...` | 87 | 300 MB / 1,9 GB por hoja | No hace falta (incluye edificios) |
| MDT nacional 2,5 m (para fuera de la ciudad) | `.../CN_Remesa_04/01_MDT/02_MDT_GeoTIFF_Resolucion_250cm/P15{B1,B4,B5,C3,C6,D1,D2,D4}_MDT_Remesa_04.tif` | 8 | ≈156 MB | GeoTIFF **[NO VERIFICADO el contenido; no lo bajé]** |
| Grillas de hojas | `.../Grillas/Urbana/Articulacion_Ortoimagenes_Urbana.shp` (campos `Nombre, Localidad, Depto, Remesa`; en geográficas SIRGAS-ROU98) · `.../Grillas/Nacional/...` | — | 0,8 MB / 3,2 MB | Shapefile |
| Licencia | `.../00_Licencia_de_datos_abiertos.pdf` | — | — | Licencia de Datos Abiertos – Uruguay v0.1: uso comercial y no comercial, modificar y redistribuir; **obliga a citar** el proveedor, la licencia y el conjunto de datos, y a declarar las modificaciones |
| Metacalidad RU09 | `.../Documentos_IDE/Proyecto_de_produccion_y_control_de_informacion_geografica/Informe_de_Metacalidad_RU09.pdf` | — | 0,6 MB | PDF |

Lista de las 43 hojas costeras (el pipeline la deriva sola de la grilla; esto es de referencia):
`P15B1P6 P15B1P8 P15B1P9 P15B4N2 P15B4N3 P15B4N5 P15B4N6 P15B4N8 P15B4N9 P15B4P2 P15B4P3 P15B4P5 P15B4P6 P15B4P8 P15B4P9 P15B5M4 P15B5M7 P15B5O1 P15D1N1 P15D1N2 P15D1N3 P15D1N4 P15D1N5 P15D1N7 P15D1N8 P15D1N9 P15D1O3 P15D1O5 P15D1O6 P15D1O9 P15D1P1 P15D1P2 P15D1P3 P15D1P4 P15D1P5 P15D1P6 P15D1P7 P15D1P8 P15D2M7 P15D2O1 P15D2O2 P15D2O4 P15D4N1`

Datos técnicos:
- **CRS horizontal:** EPSG:5382, SIRGAS-ROU98 / UTM 21S, celda de 1,0 m **[VERIFICADO en 4 hojas]**. Ojo: las curvas de Dinagua vienen en EPSG:32721 (WGS84 / UTM 21S). La diferencia entre los dos es menor a 1 m, pero conviene reproyectar explícitamente con pyproj.
- **Datum vertical:** según el informe, "para el cálculo de las cotas ortométricas se utilizó el modelo geoidal EGM2008; el origen de cotas es el del modelo geoidal EGM2008" **[VERIFICADO]**. **No es el Cero Oficial**, y no conozco la diferencia EGM2008 − Cero Oficial en Paysandú **[NO VERIFICADO]**.
- **Exactitud vertical exigida al MDT:** ≤ 0,30 m en z al 95 %. Exactitud relativa: 0,30–0,60 m. En la aerotriangulación del bloque PSD se midió 0,10 m en z con 6 puntos de control (GCP) **[VERIFICADO]**.
- **Cobertura:** el MDT urbano tiene el 84–94 % del área de las curvas históricas (71 % de la Tr100). El resto, sobre todo el norte y el oeste, queda en el nacional de 2,5 m.
- **El río es nodata o está aplanado:** en P15B4N8 falta el 26 % de las celdas, y el agua aparece aplanada a 1,84 m (en P15D1N4, a 1,67 m). **No se puede usar el mínimo del MDT como "río"**: la semilla del relleno tiene que ser una máscara del cauce.
- **Fecha:** el terreno es el de 2017. Rellenos, obras o calles nuevas posteriores no están.

## 3. Calibración preliminar (3 hojas, solo exploración)

Muestreé el MDT cada 2 m sobre el borde de cada curva, dentro de las 4 hojas que bajé:

| Curva | cota oficial | MDT en el borde (mediana; p25–p75) | Desfase MDT − local |
|---|---|---|---|
| jul-2025 (hecha con el MDT) | 6,69 | **7,24** (7,18–7,29) | **+0,66** |
| Tr10 | 7,88 | 8,35 (8,04–8,71) | +0,61 |
| jun-2017 | 8,46 | 8,81 (8,52–9,11) | +0,46 |
| ene-2019 | 8,56 | 8,74 (8,62–8,99) | +0,29 |
| nov-2009 | 9,04 | 9,57 (9,44–9,71) | +0,64 |
| dic-2015 | 9,23 | 9,82 (9,64–10,00) | +0,70 |
| Tr100 | 9,63 | 9,79 (9,64–9,98) | +0,30 |

Cómo lo leo: la curva de 2025 sigue una isolínea del MDT casi perfecta, con 11 cm de rango intercuartil. Eso hace pensar que Dinagua usó **nivel MDT = local + ~0,66**. Las demás curvas, que vienen de otros métodos (imagen satelital, curvas cada 2 m), dan desfases de +0,29 a +0,70: **±0,2 m de dispersión**. Con 43 hojas hay que repetir la medición antes de dar el número por bueno.

## 4. Pipeline propuesto

Es un proceso aparte del lector: corre **a mano** (`workflow_dispatch`) o cuando cambian los datos de entrada, **no en el cron de 15 min**. Las capas solo cambian si cambia el MDT o la calibración.

```
config/mapa.json  (URLs, lista de hojas o bbox, rango 4,0–10,5, paso 0,10, δ inicial, tolerancias)
  1 descargar   → cache/ con sha256; falla si falta una hoja o el tamaño no coincide con el índice
  2 mosaico     → MDT 1 m (43 hojas) + nacional 2,5 m remuestreado solo en los huecos; EPSG:5382
  3 cauce       → máscara del río: nodata o celdas aplanadas conectadas al borde oeste
                   ∪ orilla OSM/Dinagua (shp_espejos_de_agua) [fuente NO VERIFICADA]
  4 llegada     → "priority-flood" desde el cauce: para cada celda, la cota mínima del río a la que se
                   moja por superficie (raster float, 1 m). Las capas quedan anidadas por construcción.
  5 por nivel h → llegada ≤ h_local + δ  → quitar el cauce normal → sieve (<100 m²) → polygonize
                   → make_valid → simplify 1,5 m (preserve_topology) → EPSG:4326 → 5 decimales
  6 validar     → geometría válida; área(h) ≤ área(h+0,1); A(h) ⊆ A(h+0,1) (tolerancia 1 %);
                   bbox dentro de los límites; bytes ≤ tope; si algo falla, no se publica nada
  7 calibrar    → ver 4.1; escribe calibracion.json
  8 publicar    → data/mapa/indice.json + agua/NNNN.json + calibracion.json + LICENSE-DATOS.md
                   (formato del §2.3 de 02-tecnologia-app.md; `cero: "Local"`)
  log           → filas, áreas, bytes, δ, IoU y hashes por paso en mapa.log
```

Herramientas: Python 3.11+, `rasterio` (trae GDAL en la rueda), `numpy`, `scipy.ndimage` o `richdem` para el priority-flood, `shapely` 2.x, `pyproj`. Todo instalado en el venv de prueba sin problemas; en GitHub Actions corre en ubuntu-latest **[NO VERIFICADO en CI]**. Hay que trabajar por ventanas para no cargar 12×13 km a 1 m de una vez: son ~150 Mpx, unos 600 MB en float32. Alternativa: hacer el relleno a 2 m.

Notas:
- **Conectividad 4 vecinos**, no 8, para que el agua no pase en diagonal entre dos celdas de un terraplén.
- Las líneas de quiebre del MDT mantienen terraplenes y calles elevadas. Bien. Pero **el agua que sube por los pluviales**, que en Paysandú pasa, no sale en un relleno por superficie: el modelo marca zonas "secas" que en la realidad se mojan desde abajo.
- La pendiente del río a lo largo de 12 km de costa se ignora: un solo nivel para toda la ciudad. Probablemente sean pocos cm **[NO VERIFICADO]**.

### 4.1 Calibración contra las curvas reales

- **Métrica:** IoU **solo en tierra**, sacando el cauce normal (si no, el río infla el IoU por encima de 0,9), dentro de la cobertura del MDT y de la ventana de cada curva. Además, el error de borde: la distancia media simétrica entre contornos, en metros.
- **Ajuste:** δ global (barrido de −0,2 a +1,2 cada 0,02) para maximizar el IoU medio. **jul-2025 no es independiente** (se hizo con el mismo MDT): sirve para fijar δ, pero la validación se hace con 2009, 2015, 2017 y 2019, dejando uno afuera por vez. Tr10 y Tr100 entran como chequeo secundario, porque son curvas de diseño y no eventos.
- **Criterio propuesto de aceptación:** IoU en tierra ≥ 0,70 en validación y δ estable (±0,1) entre los eventos dejados afuera. Si no se cumple, se pasa a la alternativa mínima (§5).
- `calibracion.json`: δ, IoU por evento, error de borde, fecha del MDT y versión de config. El índice lo resume en `"modelo"` y mantiene `validado: false` hasta que lo revise alguien de Dinagua o de la Intendencia.

### 4.2 Peso

Medido en 3 hojas costeras (con el relleno conectado, sieve de 50 m² y simplify de 1,5 m): **2–7 KB de GeoJSON por hoja y nivel, 0,6–1,3 KB comprimido**. Con tolerancia de 3 m queda en 2–4 KB.

| Escenario | Por nivel | 66 niveles (4,0–10,5 m) |
|---|---|---|
| GeoJSON, 5 decimales, tol 1,5 m | 40–150 KB (≈ 25 hojas con agua × 2–6 KB) | 3–10 MB |
| Lo mismo comprimido (GitHub Pages sirve gzip) | 10–40 KB | **1–2,5 MB** |
| Empaquetar en el APK solo cada 50 cm (14 capas) | — | 0,2–0,6 MB comprimido |

Es una extrapolación **[NO VERIFICADO con las 43 hojas]**. Formato recomendado: **GeoJSON por nivel**, que encaja con el contrato del §2.3 de 02 y no necesita PMTiles vectorial en Flutter. Si pesa más de lo previsto: (a) subir la tolerancia a 3 m, (b) publicar franjas incrementales (cada archivo con lo que se agrega respecto del nivel anterior; la app las suma), o (c) publicar un solo raster de "cota de llegada" cuantizado a 10 cm (uint8, PNG de ~1–2 MB) y dibujar el umbral en la app. La (c) es la más liviana y continua, pero complica flutter_map.

## 5. Alternativa mínima (sin MDE)

Mostrar las curvas de Dinagua tal cual, como "crecidas reales de referencia":
- Se baja un GeoJSON de 7 curvas (5 CRI + Tr10 + Tr100) recortado y simplificado a 2 m: **174 KB, ~50 KB comprimido** (medido).
- **No interpolar polígonos entre eventos:** no están anidados y cada uno cubre una zona distinta, así que el resultado sería inventado. Lo honesto es una función escalón: para la altura h se muestra la **curva real más alta con cota ≤ h**, rotulada "así llegó el agua en dic-2015 con 9,12 m", y la siguiente como contorno punteado ("con 9,49 m, crecida de 100 años").
- Por debajo de 6,58 m no hay ninguna curva: la app no pinta agua y lo dice.
- Opcional, si se quiere forzar que las capas queden anidadas: usar la unión acumulada de las curvas con cota ≤ h, recortada a la ventana común. Es más prolija visualmente, pero mezcla eventos.

## 6. Riesgos, margen de error y qué decirle al usuario

| Riesgo | Efecto | Mitigación |
|---|---|---|
| δ del datum mal estimado (EGM2008 vs local) | Todo el mapa corrido decenas de cm | Calibrar con las 5 curvas; publicar δ e IoU |
| Cero de CARU ≠ cota_local de Dinagua; +0,11 vs +0,14 | 3+ cm de sesgo | Confirmar con CARU/Dinagua **[NO VERIFICADO]** |
| Exactitud del MDT (≤0,30 m al 95 %) | En una pendiente del 1 %, ±30 m de borde | Comunicarlo como banda, no como línea |
| Terreno de 2017 (obras posteriores) | Zonas mal marcadas localmente | Fecha del MDT visible en la app |
| Pluviales, lluvia local y crecida propia de los arroyos Sacra y Curtiembre | Zonas que se mojan y el modelo marca secas | Avisarlo en el texto |
| Fuera de la ciudad: MDT 2,5 m nacional | Menos detalle en el norte y el oeste | Sombrear "detalle menor" o recortar |
| Pronóstico de CARU | Es una altura esperada, no un máximo garantizado | Redondear **hacia arriba** al siguiente 10 cm y rotular "pronóstico" |
| Disponibilidad del WFS o del IDE | El pipeline no corre | Los resultados quedan commiteados; el pipeline no corre en vivo |

**Margen razonable para comunicar:** unos ±0,3 m en la altura equivalente. En el terreno, el borde puede correrse **una cuadra o más** en las zonas planas.

Texto sugerido en la app:
> "Zona aproximada que quedaría bajo agua con **X,XX m** en el puerto de Paysandú (cero local de CARU). Es una estimación calculada con el relieve de 2017 (IDE Uruguay) y ajustada con crecidas reales registradas por Dinagua. El borde puede variar **una cuadra o más**. No incluye agua de lluvia, desbordes de pluviales ni de arroyos. **No reemplaza los avisos del Cecoed ni de la Intendencia.** Si estás cerca del borde, considerá que te puede llegar el agua."

## 7. Pendientes que NO pude verificar

1. Que la "altura" de CARU (`actual.json`, `cero: "Local"`) y la `cota_local` de Dinagua usen el mismo cero del hidrómetro.
2. Cuál es el paso correcto local→oficial: +0,11 (CRI) o +0,14 (TR).
3. La diferencia EGM2008 − Cero Oficial en Paysandú (ni siquiera es seguro que haga falta: δ se calibra directo contra el cero local).
4. El contenido de las hojas nacionales de 2,5 m (CRS y datum vertical; el informe sugiere 5382/5383 y EGM2008).
5. El tamaño final con las 43 hojas y la estabilidad de δ fuera de las 4 hojas de prueba.
6. Una fuente limpia para la máscara del cauce (`dinagua:shp_espejos_de_agua` u OSM).
7. Que el pipeline corra en GitHub Actions dentro de los límites de memoria y tiempo.

## Fuentes

- [WFS Dinagua — GetCapabilities](https://www.ambiente.gub.uy/dinagua-gs/dinagua/wfs?service=WFS&version=2.0.0&request=GetCapabilities)
- [IDE Uruguay — índice de descargas](https://visualizador.ide.uy/descargas/datos/)
- [IDE — MDT urbano Paysandú 1 m](https://visualizador.ide.uy/descargas/datos/CU_Remesa_09/01_MDT_MDS/08_Ciudad_PSD/04_MDT_GeoTIFF_Resolucion_100cm/)
- [IDE — Licencia de Datos Abiertos](https://visualizador.ide.uy/descargas/datos/00_Licencia_de_datos_abiertos.pdf)
- [IDE — Informe de metacalidad RU09](https://visualizador.ide.uy/descargas/datos/Documentos_IDE/Proyecto_de_produccion_y_control_de_informacion_geografica/Informe_de_Metacalidad_RU09.pdf)
- [IDE — Proyecto de ortoimágenes y MDE](https://www.gub.uy/infraestructura-datos-espaciales/proyecto-produccion-control-ortoimagenes-modelos-digitales-elevacion-cartografia)
- [IDE — Noticia: MDT/MDS disponibles](https://www.gub.uy/infraestructura-datos-espaciales/comunicacion/noticias/ide-comienza-disponibilizar-modelos-digitales-terreno-superficie-uruguay)
