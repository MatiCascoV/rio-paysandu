# Mapa de inundación — 06. Informe del pipeline (primera corrida real)

Corrida del 21/10/2026, rama `mapa-inundacion`. Es la primera vez que el pipeline de `lector/mapa/` corre de punta a punta con datos reales. Escrito para quien tenga que volver a correrlo o revisar la salida.

> **Estado: salida generada y validada contra el contrato, con `validado: false`.** La calibración cumple el criterio técnico de 01 §4.1, pero el mapa **no está aprobado**. Antes de ponerlo en la app tiene que pasar un control de calidad y, en lo posible, la revisión de alguien de Dinagua o de la Intendencia. El valle del arroyo San Francisco (§7) no tiene ninguna curva real contra la cual compararlo.

## 0. Resumen

| | |
|---|---|
| Salida | `C:\Users\matic\AppData\Local\Temp\claude\C--Users-matic\7aeaecfb-07bd-4819-84e5-5508d08990ab\scratchpad\mapa-salida\mapa\` (fuera del repo; **no** se copió a `app/assets`) |
| Contenido | `indice.json`, `base.json`, `agua/0400.json` … `agua/1050.json` (66 capas), `curvas/{2009-11,2015-12,2017-06,2019-01,2025-07}.json`; además, `calibracion.json`, `mapa.log` y 4 PNG de control |
| δ calibrado | **0,66 m** (terreno MDT, EGM2008 ≈ cota local + 0,66) |
| IoU de validación (media de 2009/2015/2017/2019) | **0,917**. Mínimo: 0,896 (nov-2009) |
| Peso | **4,90 MB** sin comprimir (4,51 MB las capas); **≈ 1,0 MB** las capas comprimidas con gzip |
| Validación | Sin errores: índice, sha256/bytes, geometrías, límites, paso, anidado (peor caso: 0,20 % afuera, con 1 % de tolerancia) |
| Tests | `test_mapa_*`: 61 pasan con el venv del mapa. Tests del lector: 283 pasan y 4 se saltan, con su venv de siempre |

## 1. Cómo correrlo

Python 3.12 en un venv **propio del mapa** (no el del lector):

```powershell
cd C:\Users\matic\rio-paysandu-mapa\lector
C:\Python312\python.exe -m venv mapa\.venv
mapa\.venv\Scripts\python.exe -m pip install -r mapa\requirements.txt
mapa\.venv\Scripts\python.exe -m pytest tests\test_mapa_*.py -q
mapa\.venv\Scripts\python.exe -m mapa <CARPETA_SALIDA> --cache <CARPETA_CACHE> [--generado 2026-10-21T12:00:00-03:00] [--osm-pbf ARCHIVO] [--sin-png]
```

- `.venv/` y `__pycache__/` ya los ignora el `.gitignore` de la raíz.
- Todas las versiones fijadas en `requirements.txt` existen para Windows/cp312 y se instalaron tal cual, sin sustituciones.
- La salida se arma en `<CARPETA_SALIDA>.parcial` y se mueve a su lugar **solo si todas las validaciones pasan**. Si algo falla, la salida anterior queda intacta y el motivo se lee en `.parcial\mapa.log`.
- `--generado` fija la fecha del índice. Con la misma fecha y la caché completa, dos corridas dan los mismos bytes.
- Caché: cada URL se baja una sola vez, con sha256 en `manifiesto.json`. El terreno y la llegada se guardan en `terreno_<hash>.npz`: si cambian la config o los insumos, se recalculan solos.
- Tiempos en esta PC: unos 15 min sin caché del terreno (la llegada sola tarda 340 s sobre 72,5 M celdas) y unos 5 min con caché. No medí el pico de RAM; la grilla de cálculo tiene 72,5 M celdas y la PC (15,6 GB) lo manejó sin problemas. Bajar todo de cero son unos 675 MB.

## 2. Qué se descargó (fuentes y licencias)

| Fuente | URL | Qué | Tamaño | Fecha de descarga | Licencia |
|---|---|---|---|---|---|
| IDE Uruguay, MDT urbano 1 m, Remesa Urbana 09 (Paysandú, vuelo oct-2017) | `https://visualizador.ide.uy/descargas/datos/CU_Remesa_09/01_MDT_MDS/08_Ciudad_PSD/04_MDT_GeoTIFF_Resolucion_100cm/` | 87 hojas GeoTIFF (todas las de la ciudad), EPSG:5382, float32, nodata −32767 | 279,5 MB | 19/10 (caché del intento anterior, verificada por sha256) | Licencia de Datos Abiertos – Uruguay: hay que citar proveedor, licencia y conjunto, y declarar las modificaciones |
| IDE Uruguay, MDT nacional 2,5 m, Remesa 04 | `https://visualizador.ide.uy/descargas/datos/CN_Remesa_04/01_MDT/02_MDT_GeoTIFF_Resolucion_250cm/` | 18 hojas (P14C6, P14D4–6, P15B1–6, P15C3, P15C6, P15D1–6), EPSG:5382, nodata −32767 | 334,9 MB | 19 y 21/10 | ídem |
| IDE Uruguay, grillas de articulación | `.../Grillas/Urbana/Articulacion_Ortoimagenes_Urbana.*`, `.../Grillas/Nacional/Articulacion_Ortoimagenes_Nacional.*` | Shapefiles para elegir hojas | 4,1 MB | 19/10 | ídem |
| Dinagua (Ministerio de Ambiente), WFS | `https://www.ambiente.gub.uy/dinagua-gs/dinagua/wfs`, capas `dinagua:curvas_cri` y `dinagua:curvas_tr`, filtro `nombre LIKE 'PA-PSD%'` | 5 crecidas + Tr10 + Tr100 del río Uruguay | 0,7 MB | 19/10. El 21/10 se volvió a pedir y las geometrías y los atributos son **idénticos** (solo cambian `timeStamp` y los `fid` volátiles de GeoServer) | El servicio no declara licencia. Por analogía, la misma nota de origen (ver 04 §1.4). **Falta confirmación de Dinagua** |
| OpenStreetMap vía Geofabrik | `https://download.geofabrik.de/south-america/uruguay-latest.osm.pbf` | Extracto de Uruguay: calles, agua y cursos para `base.json`, el cauce y el quemado de arroyos | 56,2 MB | 21/10 | ODbL, "© colaboradores de OpenStreetMap" |

Ninguna URL cambió: todas respondieron 200. El intento del 19/10 se había cortado por un timeout de IDE mientras bajaba las hojas nacionales. El MDT nacional y el urbano vienen los dos en EPSG:5382. El datum vertical del nacional no figura en el archivo; en el solape, el nacional queda **+0,11 m** por encima del urbano (mediana; p25–p75 de −0,26 a +0,48), y ese sesgo se resta antes de usarlo.

## 3. Cambios al código hechos en esta corrida

Todos están en `lector/mapa/` y sus tests (de 45 a 61 tests). Ninguno toca el contrato.

1. **Criterio de calibración** (`calibracion.py`): el código exigía IoU ≥ 0,70 también en el "dejando uno afuera", cosa que 01 §4.1 no pide (ahí sirve para medir la estabilidad de δ). Ahora sigue el documento: IoU medio de validación ≥ 0,70 y δ estable (±0,10 m). El IoU dejando uno afuera se sigue informando, y en esta corrida igual dio 0,916.
2. **Peso de las capas** (`capas.py`, `config.json`): con simplify de 1,5 m las capas pesaban 230–400 KB cada una (**≈ 17 MB** en total), porque el escalonado de los píxeles de 2 m sobrevivía a la simplificación. Ahora:
   - Se rellenan los huecos secos de hasta 2.000 m² (`rellenar_secos_m2`). Solo agrega agua.
   - **Buffer de 4 m antes de simplificar con 4 m** (`buffer_m`, `simplify_m`). Douglas‑Peucker mueve el borde a lo sumo la tolerancia, así que con buffer ≥ simplify **ninguna celda mojada queda afuera**: está garantizado (el código rechaza buffer < simplify) y hay un test. El precio es una franja de unos 4 m de agua de más en todo el borde, entre +3 y +9 % de área según la altura (medido en 4 capas). Es el sentido prudente y queda muy por debajo del error del MDT.
   - Recorte final a `limites`.
   - El tope total en config bajó a 6 MB, para que el pipeline falle fuerte si crece.
3. **Arroyos y remanso** (`terreno.py`, `pipeline.py`). **Es el cambio más importante para la seguridad.** En la primera corrida, el valle del **arroyo San Francisco Grande** (norte de la ciudad) quedaba seco hasta 10,40 m y a 10,50 m se inundaban de golpe 543 ha por un desborde. El motivo: el arroyo desemboca en el Uruguay pasando *al norte* de `limites` (llega a lat −32,232), en OSM su tramo angosto es solo una línea, y en el MDT el agua sin dato funciona como pared. O sea, el modelo no dejaba entrar el remanso del río y mostraba **menos agua** de la real. Arreglo:
   - `limites_computo` `[[-32.380, -58.170], [-32.215, -58.005]]`: el cálculo se hace en una caja más grande que la del contrato y la salida se recorta a `limites`.
   - `quemar_cursos`: en las líneas de OSM `waterway=river|stream|canal` se baja el terreno al mínimo de la ventana de 3×3, que es el lecho angosto que el promedio a 2 m había subido. Los tramos sin dato de hasta 100 m se completan con la cota del tramo válido más cercano. Los más largos (3.162 celdas, sobre todo de la otra orilla, fuera del MDT) **no** se completan: no se inventa terreno. Solo baja cotas, así que nunca saca agua; hay test.
   - Resultado: el valle del San Francisco se moja de a poco desde abajo (43 ha a 4,00 m y 315 ha a 9,20 m) y desapareció el salto. La calibración no cambió (mismos IoU), porque la zona calibrada es la misma.
4. **Imágenes de control**: la config pedía la capa 9,12 m, que no existe (las capas van cada 0,10 m), y el pipeline se caía. Ahora se usa la capa que pintaría la app, redondeando **hacia arriba** (`capa_para`, con test), y se generan 4 PNG configurables.
5. **Windows**: (a) la carpeta `.parcial` no se podía renombrar con `mapa.log` abierto, así que ahora el log se cierra antes; (b) stdout se reconfigura a UTF-8, porque la "δ" rompía el log de consola en cp1252.
6. **Métricas nuevas en `calibracion.json`**, por curva: `curva_cubierta` (qué parte de la crecida real marca el modelo), `modelo_fuera_de_curva` e `iou_sin_zona_baja` (IoU sin las celdas que ya se mojan con la capa mínima).
7. Advertencia de deprecación de `affine` (`*` → `@`).

## 4. Calibración y validación por evento

Definición: celda mojada a la altura local *h* si su cota de llegada (relleno conectado al río, 4‑vecinos) es ≤ *h* + δ. δ se fija con la crecida de **jul-2025**, que **no es independiente**: Dinagua la trazó con este mismo MDT. La validación usa 2009, 2015, 2017 y 2019. Tr10 y Tr100 son solo chequeo. El barrido de δ va de −0,20 a +1,20 cada 0,02.

### 4.1 Contra el raster de cálculo (2 m, *h* exacta)

Dominio: la caja de cada curva ∩ la cobertura del MDT urbano, sin el agua de OSM.

| Evento | Cota local | IoU | IoU sin zona baja¹ | Crecida cubierta por el modelo | Modelo fuera de la crecida | Error de borde medio | δ óptimo propio |
|---|---|---|---|---|---|---|---|
| jul-2025 (fija δ) | 6,58 | 0,975 | 0,956 | 99,0 % | 1,5 % | 24 m | 0,66 |
| jun-2017 | 8,35 | 0,911 | 0,858 | 95,9 % | 5,2 % | 81 m | 0,68 |
| ene-2019 | 8,45 | 0,919 | 0,878 | 96,4 % | 4,8 % | 55 m | 0,52 |
| nov-2009 | 8,93 | 0,896 | 0,845 | 96,1 % | 7,0 % | 49 m | 0,54 |
| dic-2015 | 9,12 | 0,940 | 0,914 | 97,2 % | 3,4 % | 33 m | 0,62 |
| Tr10 (chequeo) | 7,74 | 0,898 | 0,829 | 97,6 % | 8,1 % | 33 m | 0,42 |
| Tr100 (chequeo) | 9,49 | 0,936 | 0,911 | 98,0 % | 4,6 % | 30 m | 0,56 |

¹ Sin las celdas que el modelo ya moja a 4,00 m (≈ 240–270 ha por curva). Esas celdas están mojadas para cualquier δ, así que inflan el IoU sin decir nada sobre la calibración.

- Validación: IoU medio **0,917** y mínimo 0,896. Dejando uno afuera, δ sale 0,58–0,64 y el IoU medio 0,916. Dispersión de δ: 0,08 m. **Cumple** el criterio (IoU ≥ 0,70 y ±0,10 m).
- Ojo con la lectura: **el IoU casi no discrimina δ**. Entre δ = 0,46 y 0,86, el IoU de cada evento cambia apenas 1–5 puntos, y el "mejor δ" de cada evento por separado va de 0,52 a 0,68. En la práctica, δ lo fija la curva de 2025, que no es independiente. La estabilidad dejando uno afuera es una buena señal, pero no es una prueba fuerte.
- Lo que más importa para la seguridad: **el modelo no marca entre el 1 y el 4 % de cada crecida real** (más en jun-2017). Son franjas de borde de unos 25–80 m. En la app, la franja de margen de +0,50 m que pide el contrato tendría que cubrir la mayor parte. No lo medí por separado.
- Las curvas de Dinagua no cubren todo: tienen un borde recto hacia el río y cada relevamiento abarca una zona distinta. Por eso el IoU se mide dentro de la caja de cada curva.

### 4.2 Contra las capas publicadas (lo que vería la app)

Capa = altura redondeada hacia arriba al siguiente 0,10, con buffer y simplificación. Se mide en UTM, dentro de la caja de la curva y sin el agua de `base.json` (incluye la zona del MDT nacional). Script: `scratchpad\scripts\validar_salida.py`.

| Evento | Cota | Capa | IoU | Crecida cubierta | Capa fuera de la crecida |
|---|---|---|---|---|---|
| jul-2025 | 6,58 | 6,60 | 0,926 | 99,8 % | 7,2 % |
| jun-2017 | 8,35 | 8,40 | 0,908 | 97,6 % | 7,2 % |
| ene-2019 | 8,45 | 8,50 | 0,899 | 96,7 % | 7,3 % |
| nov-2009 | 8,93 | 9,00 | 0,882 | 97,4 % | 9,6 % |
| dic-2015 | 9,12 | 9,20 | 0,931 | 98,1 % | 5,2 % |

## 5. Salida y tamaños

| | Bytes |
|---|---|
| `agua/` (66 capas) | 4.510.719 (61–80 KB por capa; la mayor es `agua/0940.json`, con 80 KB) |
| `base.json` | 268.774 |
| `curvas/` (5) | 111.928 |
| `indice.json` | 12.846 |
| **Total del contrato** | **4.904.267 (4,90 MB)** |
| Capas comprimidas con gzip -9 | 993.914 (≈ 1,0 MB) |

Superficie mojada sobre tierra dentro de `limites` (sin el cauce de OSM):

| Altura | 4,00 | 5,00 | 6,00 | 6,60 | 7,00 | 8,00 | 8,40 | 9,00 | 9,20 | 10,00 | 10,50 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| ha | 500 | 662 | 821 | 943 | 1.035 | 1.299 | 1.424 | 1.636 | 1.721 | 2.099 | 2.229 |
| de ellas, valle del San Francisco (norte) | 43 | 90 | 141 | 176 | 197 | 245 | 264 | 297 | 315 | 362 | 392 |

¿Entra en el APK? Sí: queda debajo de los ~5 MB, aunque justo. El APK comprime los assets con deflate, así que en la descarga deberían ocupar del orden de 1 MB (estimado con gzip; no lo medí en un APK). Si hace falta achicar más:
1. Simplify y buffer de 5 m, con huecos secos de hasta 5.000 m²: entre −15 y −23 % según la capa (prueba en 4 capas con una variante parecida: buffer 3, simplify 5). Es la opción menos invasiva.
2. Empaquetar en el APK solo cada 0,20 m (33 capas, ≈ 2,3 MB), manteniendo el redondeo hacia arriba.
3. Franjas incrementales o un raster de "cota de llegada" (ver 01 §4.2): cambian el contrato.

No recomiendo bajar la resolución de cálculo: el error de borde actual (24–81 m) ya es del orden de una cuadra.

## 6. Imágenes de control

En la carpeta de salida: `control_2025-07.png`, `control_2017-06.png`, `control_2009-11.png` y `control_2015-12.png`. Cada una muestra la capa que pintaría la app para la cota de la crecida (azul oscuro), la de +0,50 m (celeste, la franja de margen), la curva real de Dinagua (rojo) y el fondo de `base.json`. Revisadas a ojo:
- El borde del modelo sigue muy de cerca la curva en la costanera, en el puerto y en la bahía de la Curtiembre.
- En el sur (zona del Sacra y del puerto), el modelo moja más que la curva hacia el oeste. Es tierra baja que los relevamientos no cubren.
- El valle del San Francisco aparece mojado en todas las crecidas y **no hay curva de Dinagua para compararlo**.

## 7. Limitaciones

- **Sin validación externa**: `validado: false`. Hay que mostrarlo así en la app y no presentar el mapa como definitivo.
- **El valle del arroyo San Francisco Grande no está validado.** Es un remanso modelado por el lecho de OSM quemado en el MDT, en parte sobre el MDT nacional de 2,5 m. Puede tener más o menos agua que la real. Hacen falta las curvas de Dinagua de ese arroyo (la capa `curvas_tr` trae curvas de los arroyos Sacra y Curtiembre, pero sin cota) o un relevamiento local. Lo mismo vale, en menor escala, para el Sacra y la Curtiembre aguas arriba.
- **Zona baja a 4,00 m**: con 4,00 m el modelo ya moja unas 500 ha sobre tierra (islas, bañados y la planicie del sur y del San Francisco). Si en la realidad esas zonas tienen agua permanente o vegetación que el MDT no ve como agua, la app va a mostrar "agua sobre tierra" con alturas normales del río. Hay que revisarlo con alguien que conozca la costa.
- **δ poco discriminado** (§4.1) y la curva que lo fija no es independiente. Error posible: unos ±0,1–0,2 m en la altura equivalente. A eso se suma la duda, que sigue abierta, de si el cero de CARU es igual a la `cota_local` de Dinagua (01 §7.1–7.2).
- **El terreno es de 2017** (urbano). Las obras posteriores no están. Entran por superficie: no se modelan los pluviales, la lluvia local ni las crecidas propias de los arroyos.
- **El MDT urbano cubre solo el 17,6 % de la caja de cálculo.** El resto del lado uruguayo (el norte, el valle del San Francisco y el sur rural) usa el nacional de 2,5 m con el sesgo corregido, pero su dispersión es grande (p25–p75 de −0,26 a +0,48 m).
- **La orilla argentina no tiene MDT** (es la mayor parte de las 18,5 M celdas sin dato fuera del agua, que funcionan como pared). No afecta el lado uruguayo, pero el mapa no dice nada de Argentina.
- Tamizado: se sacan manchas de agua de menos de 100 m² (el 0,02 % del agua a 4,00 m). Es lo único del procesamiento que puede sacar agua, y es despreciable frente al buffer de 4 m.
- El buffer hace que las capas invadan unos 4 m el polígono del cauce de `base.json`. Es invisible al pintar el agua encima.

## 8. Qué quedó sin hacer

- **Control de calidad y revisión externa** (Dinagua o Intendencia), sobre todo del valle del San Francisco y de la zona baja a 4,00 m. Recién después se puede cambiar `validado`.
- **Copiar la salida a `app/assets/mapa/`**: no lo hice, a propósito (está fuera de mi terreno y no está aprobada).
- Confirmar con CARU/Dinagua el cero local (+0,11 frente a +0,14) y la licencia de las curvas.
- Medir cuánto de la crecida real que el modelo no marca queda cubierto por la franja de margen (+0,50 m).
- Correr el pipeline en GitHub Actions (memoria y tiempo); no se probó.
- `base.json` se extrajo del extracto OSM del 21/10 (268.774 bytes, el mismo tamaño que figura en el ejemplo del contrato). No lo comparé contenido a contenido con el de la maqueta.
- Script de validación vectorial (`validar_salida.py`): está en el scratchpad. Si se quiere en el repo, hay que pasarlo a `lector/mapa/`.
