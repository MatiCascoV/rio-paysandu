# Mapa de inundación — 11. Control de calidad independiente de la salida del pipeline

Control del 21/10/2026 sobre la salida de la corrida del 21/10, rama `mapa-inundacion`, commit e064adb.
No usé `validar.py` ni `validar_salida.py` del autor: repetí cada medición con scripts propios. Tampoco toqué `lector/`, `app/` ni la salida.

- Salida revisada: `C:\Users\matic\AppData\Local\Temp\claude\C--Users-matic\7aeaecfb-07bd-4819-84e5-5508d08990ab\scratchpad\mapa-salida\mapa\`
- Scripts, resultados (JSON) y mapas del control: `C:\Users\matic\AppData\Local\Temp\claude\C--Users-matic\7aeaecfb-07bd-4819-84e5-5508d08990ab\scratchpad\qa-mapa\`
  - `c1_contrato.py`: contrato (resultado en `c1.json`).
  - `c2_raster.py`: rehace el MDT de trabajo desde las hojas en caché, hace un relleno propio y calcula área contra altura, saltos, zona baja, bajos desconectados y sensibilidad al cero (`c2.json`).
  - `c3_vector.py`: geometría, anidado, cauce, simplificación contra el raster, fidelidad contra las curvas **crudas** del WFS y mapas (`c3.json`).
  - `c4_celdas_afuera.py`: ubica las celdas mojadas que quedan afuera de la capa.
  - `c5_zona4m.py`: mapa de la zona que ya está mojada a 4,00 m.
  - `c6_islas.py`: separa las omisiones en "islas secas" y "borde corrido" (`c6.json`).

## Veredicto

| # | Control | Veredicto |
|---|---|---|
| 1 | Contrato | **PASA** |
| 2 | Geometría | **PASA** |
| 3 | Fidelidad contra las crecidas reales | **PASA CON OBSERVACIONES** |
| 4 | Coherencia física | **PASA CON OBSERVACIONES** |
| 5 | Simplificación | **PASA CON OBSERVACIONES** |
| 6 | Cero de la escala | **PASA CON OBSERVACIONES** (problema abierto; no bloquea con el sello "en prueba") |

**Recomendación sobre `validado`: dejarlo en `false` y publicar con el sello "Mapa en prueba"**, con las condiciones de la §8. No encontré nada crítico: los números del autor se reproducen y no hay capas rotas ni saltos. Pero hay tres razones para no marcarlo como validado:

1. La franja de margen no es opcional. Sin ella, la app deja sin pintar hasta 3,3 % de una crecida real, con bordes hasta 180 m más adentro de lo pintado en zona urbana.
2. Ni con el margen se cubre todo: en nov-2009 queda afuera el 1,8 % de la crecida, en el acceso al puente.
3. El cero de CARU y el valle del San Francisco siguen sin confirmar.

---

## 1. Contrato — PASA

Verificado contra `05-contrato.md`:

- `indice.json` tiene todas las claves, `version` 1, `cero: "Local"`, `validado: false` (booleano), `generado` en ISO 8601 con zona y `modelo` con `metodo`, `delta_m` 0,66, `iou_validacion` 0,9168 y `margen_m` 0,5. `limites` es `[[-32.365,-58.15],[-32.24,-58.03]]`, `paso_m` 0,1, `min_m` 4,0 y `max_m` 10,5.
- Hay **66 capas**, de 4,00 a 10,50, ordenadas, sin huecos y con paso 0,10. Los nombres siguen `agua/NNNN.json`, y no hay archivos de más ni de menos en `agua/`.
- `bytes` y `sha256` coinciden en los 72 archivos listados: 66 capas, `base.json` y 5 curvas.
- Cada capa es una `FeatureCollection` con un solo `Feature` `MultiPolygon` y `properties == {"altura_m": h}`. No hay capas vacías.
  - Los 206.363 vértices están en el orden [lon, lat], dentro de la caja esperada.
  - Ningún número tiene más de 5 decimales.
  - Todos los anillos están cerrados, con 4 puntos o más, y la orientación es RFC 7946 (exterior antihorario).
- Las 5 curvas tienen `properties` iguales a las del índice (`nombre`, `altura_m`, `fecha`, `fuente`). Además verifiqué contra el WFS crudo:
  - las cotas y las fechas coinciden;
  - la geometría simplificada difiere en 0,07–0,12 % de área (diferencia simétrica).
- `base.json`: 13 polígonos de agua, 49 cursos, 1.174 calles, 12 lugares y `caja`. Solo tiene los tipos `agua`, `curso` y `calle`.
- `fuentes` trae OSM/ODbL, IDE Uruguay con la Licencia de Datos Abiertos y la frase "Datos modificados", y Dinagua.
- El total del contrato es 4.904.267 bytes, igual al del informe.

Observación menor: el ejemplo del contrato dice "MDT 1 m" y el `metodo` real dice "1 m remuestreado a 2 m". Está bien así: es más honesto.

## 2. Geometría — PASA

- **Validez:** las 66 capas son `is_valid`, en EPSG:4326 tal como se publican y también reproyectadas a EPSG:5382. No hay autointersecciones y todos los anillos son simples. Hay de 6 a 54 polígonos por capa (54 a 4,00 m) y de 32 a 111 huecos.
- **Anidado h ⊂ h+0,10:**
  - En el raster es **perfecto**: ninguna celda deja de estar mojada al subir 10 cm.
  - En los vectores, el peor caso es **0,20 %** (4,10 → 4,20 m: 10.372 m² afuera). Respecto de la capa de h+0,50, el peor caso son 3.491 m².
  - Es efecto de la simplificación: franjas de pocos metros en el borde. La tolerancia del contrato es 1 %.
- **Cauce:** cada capa se superpone 17,6–20,9 ha con el agua de `base.json`. Eso corresponde a la franja de unos 4 m del buffer más la simplificación de OSM. Más de 8 m adentro del cauce quedan solo **68–77 m²** por capa, así que el cauce normal **no** está en las capas.
- **Huecos e islas secas:** son plausibles. Son lomas y rellenos rodeados de agua (por ejemplo, plataformas junto al acceso al puente, en las crecidas de 9 m). Los huecos de hasta 2.000 m² se rellenan a propósito: solo agrega agua.

## 3. Fidelidad contra las crecidas reales — PASA CON OBSERVACIONES

Método propio:

- Capa que pinta la app: la altura de la crecida redondeada **hacia arriba** al siguiente múltiplo de 0,10.
- Margen: la capa de esa altura + 0,50 m, que es lo que dibuja la app como "puede llegar un poco más".
- Curvas **crudas** del WFS de Dinagua (sin simplificar), reproyectadas a EPSG:5382, recortadas a `limites` y sin el agua de `base.json`.
- El IoU se mide en la caja de cada curva, igual que el autor.

### 3.1 Números

| Evento | Cota | Capa / margen | IoU | IoU sin la zona de 4,00 m | Crecida **no pintada** por la capa | De eso, dentro del margen | **No pintada ni con el margen** | Distancia de la omisión al borde pintado (p95 / máx) |
|---|---|---|---|---|---|---|---|---|
| jul-2025 | 6,58 | 6,60 / 7,10 | 0,926 | 0,876 | 0,21 % (1,0 ha) | 70 % | 0,07 % (0,3 ha) | 23 / 33 m |
| jun-2017 | 8,35 | 8,40 / 8,90 | 0,908 | 0,849 | 2,38 % (16,0 ha) | 66 % | 0,83 % (5,5 ha) | 107 / **179 m** |
| ene-2019 | 8,45 | 8,50 / 9,00 | 0,899 | 0,841 | **3,31 %** (28,1 ha) | 73 % | 0,92 % (7,8 ha) | 134 / **188 m** |
| nov-2009 | 8,93 | 9,00 / 9,50 | 0,882 | 0,822 | 2,58 % (16,9 ha) | **24 %** | **1,97 %** (13,0 ha) | 89 / 123 m |
| dic-2015 | 9,12 | 9,20 / 9,70 | 0,931 | 0,896 | 1,94 % (17,7 ha) | 78 % | 0,44 % (4,0 ha) | 101 / 134 m |
| Tr10 (chequeo) | 7,74 | 7,80 / 8,30 | 0,838 | 0,759 | 1,59 % | 68 % | 0,52 % | 48 / 86 m |
| Tr100 (chequeo) | 9,49 | 9,50 / 10,00 | 0,857 | 0,807 | 6,52 % | 86 % | 0,89 % | 185 / 269 m |

- **Reproduzco exactamente la tabla 4.2 del autor** en IoU, crecida cubierta y capa fuera de la crecida (por ejemplo, 2019: 0,899, 96,7 % y 7,3 %).
- **El "IoU sin la zona de 4,00 m" baja entre 3,5 y 6 puntos.** El IoU publicado (0,92) está inflado por las ~450 ha que se mojan con cualquier altura. La cifra que describe mejor el desempeño es **0,82–0,90**.
- **Punto abierto 4 del autor (margen):** el margen cubre entre el 66 y el 78 % de lo no pintado en 4 de los 5 eventos, pero **solo el 24 % en nov-2009**. Lo que queda sin pintar aun con el margen va de 0,07 a 1,97 % de cada crecida.

### 3.2 Qué son las omisiones

Las curvas de Dinagua son polígonos **sin huecos**, así que marcan como inundadas lomas que el modelo, con razón o sin ella, deja secas. Separé las dos cosas (`c6.json`):

| Evento | No pintada | Islas secas del modelo (rodeadas de agua) | Borde corrido | Borde corrido fuera del margen | Calles en ese borde fuera del margen |
|---|---|---|---|---|---|
| jul-2025 | 1,0 ha | 0,99 ha | 0,03 ha | 0 | 0 m |
| jun-2017 | 16,0 ha | 3,2 ha | 12,7 ha | 4,4 ha (0,66 %) | 292 m |
| ene-2019 | 28,1 ha | 0,3 ha | 27,9 ha | 7,7 ha (0,91 %) | 208 m |
| nov-2009 | 16,9 ha | 2,2 ha | 14,7 ha | **11,7 ha (1,79 %)** | **3.873 m** |
| dic-2015 | 17,7 ha | 8,7 ha | 9,1 ha | 2,9 ha (0,32 %) | 130 m |

- **Islas secas.** Si la loma es real, quien vive ahí queda **aislado**, aunque no le entre el agua. La app no debería mostrarla como "zona segura".
- **Borde corrido.** Es la omisión de verdad, y es la que importa.

### 3.3 Dónde están

Mapas en `...\scratchpad\qa-mapa\`:

- **Generales:** `omisiones_2009-11.png`, `omisiones_2015-12.png`, `omisiones_2017-06.png`, `omisiones_2019-01.png`, `omisiones_2025-07.png`, `omisiones_Tr10.png` y `omisiones_Tr100.png`.
- **Acercamientos:** `omisiones_<evento>_zoom1.png` y `_zoom2.png`.

Convención de colores: azul, la capa; celeste, el margen; naranja, la crecida no pintada pero dentro del margen; rojo, la crecida no pintada ni con el margen; línea roja, la curva de Dinagua.

1. **Puerto y centro, al oeste del casco (≈ −58,0925; −32,3077), en jun-2017 y ene-2019.** Es **zona urbana habitada**: 830–850 m de calles (Avenida Salto, Tacuarembó, Entre Ríos, José Batlle y Ordóñez, Carlos Albo, Coronel Lucas Píriz).
   - La crecida real llegó **hasta 180 m más adentro** de lo que pinta la capa.
   - El 91,5 % de esa zona queda dentro del margen (+0,50 m).
   - Es la omisión urbana más importante.
   - Posibles causas: un bajo que el MDT de oct-2017 no ve (rellenos u obras), o agua que entró por los pluviales.
   - Ver `omisiones_2017-06_zoom1.png`.
2. **Acceso al Puente Internacional General Artigas y Av. de las Américas (≈ −58,093; −32,266), en nov-2009.**
   - Son 11,6 ha, con 3,9 km de calles (accesos del puente, Av. de las Américas, Ángel Nery Coppes, Raúl Celone, María Esther Mussio).
   - **Solo el 4,8 % queda dentro del margen.** Es casi todo el residuo de 2009.
   - Es el terraplén del acceso al puente, que con 9,0–9,5 m el modelo deja seco.
   - La curva de 2009 es la más gruesa de todas: 327 vértices, sacada de sensores remotos de la FAU. Es **probable** que haya generalizado sobre el terraplén, pero **no está probado**.
   - En jun-2017 y dic-2015 aparecen omisiones más chicas en la misma zona (María Esther Mussio, 1,4–2,3 ha). Una parte son plataformas elevadas rodeadas de agua.
   - Ver `omisiones_2009-11_zoom1.png` y `omisiones_2017-06_zoom2.png`.
3. **Bahía al norte del puerto (≈ −58,082; −32,283, cerca de Los Olivos), en jun-2017:** 1,2 ha y 52 m de calles (Marcelina Burgos de Fleitas, República de Bolivia). Hasta 92 m de distancia; el 17 % queda dentro del margen.
4. **Sur, desembocadura del Sacra y Jardines del Hipódromo (≈ −58,114; −32,347).**
   - En ene-2019 son 16 ha y en Tr100 47 ha, hasta 188–269 m.
   - Es planicie rural sin calles, sobre todo en el MDT nacional de 2,5 m. Del 80 al 100 % queda dentro del margen.
   - **No es zona habitada.**
5. **Norte de la costa, bajos junto a la Calle 136 N (≈ −58,092; −32,252), en ene-2019 y Tr10:** 2–3 ha, con 140–230 m de una calle. Están sobre el MDT nacional y solo el 30–43 % queda dentro del margen.

**Lectura de seguridad.** Con el margen dibujado, el residuo urbano es chico: 130–300 m de calles por evento, salvo el acceso al puente en 2009. **Sin el margen**, en el puerto y el centro la app dejaría sin pintar manzanas que se mojaron en 2017 y 2019.

## 4. Coherencia física — PASA CON OBSERVACIONES

### 4.1 Área inundada contra altura

Raster de 2 m, dentro de `limites`, sin el cauce y con el mismo tamizado del pipeline:

| m | 4,0 | 5,0 | 6,0 | 6,6 | 7,0 | 8,0 | 8,4 | 9,0 | 9,2 | 9,5 | 10,0 | 10,5 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ha (raster) | 450 | 607 | 764 | — | 975 | 1.238 | — | 1.571 | — | 1.827 | 2.038 | 2.171 |
| ha (capa publicada) | 500 | 662 | 821 | 943 | 1.035 | 1.299 | 1.424 | 1.636 | 1.721 | 1.892 | 2.099 | 2.229 |

- La curva es **estrictamente monótona**. El incremento por cada 10 cm va de 13 a 68 ha, con una subida suave hasta un máximo entre 9,3 y 9,7 m (44 → 58 → **68** → 54 → 51 ha) y una bajada después.
- **No hay saltos bruscos.** La mancha nueva más grande en un solo paso tiene **24 ha** y aparece a 9,50 m en la planicie rural del sur (−58,1265; −32,359), sobre el MDT nacional y sin calles.
- **El relleno se verificó por separado.** Rehice el MDT de trabajo desde las 87 + 18 hojas en caché: el agua de OSM, el cauce y la fuente salen idénticos. Con un etiquetado propio en 17 umbrales, la llegada en caché da **0 celdas distintas**.
- **Bajos desconectados:** terreno por debajo del nivel sin conexión superficial con el río. Son solo 3–10 ha por altura (≤ 7 ha en manchas de 1 ha o más). El riesgo de que el agua entre "por abajo", por los pluviales, en zonas que el modelo pinta secas existe, pero es acotado en superficie. Los pluviales siguen sin modelarse.

**Arroyo San Francisco Grande.** Mido una franja de 1.200 m a cada lado de su línea de OSM, que es una zona más amplia que la que usó el autor; por eso las áreas no coinciden con su tabla.

- El valle se moja de a poco, de 68 ha a 4,00 m hasta 536 ha a 10,50 m (dentro de `limites`).
- El incremento máximo es de **12 ha** por cada 10 cm (a 9,1 m). **El salto de 543 ha está corregido.**
- Pero sigue **sin ninguna curva real** contra la cual compararlo, y en buena parte usa el MDT nacional y el lecho "quemado" de OSM.
- Recomiendo marcarlo en la app como "zona sin validar".

### 4.2 Zona ya mojada a 4,00 m

Son **450 ha** en el raster y 500 ha en la capa vectorial, por el buffer. Mapa: `...\scratchpad\qa-mapa\zona_4m.png`.

- **236 ha** tienen la llegada en el piso del cálculo: terreno conectado al río a **≤ 2,94 m local**. Son, casi seguro, agua permanente o semipermanente que OSM no tiene como agua: el río aplanado en el MDT, la bahía, la desembocadura del Sacra y el lecho del San Francisco.
- 13 ha se mojan entre 2,94 y 3,00 m y **199 ha** entre 3,00 y 4,00 m.
- El terreno tiene una mediana de **2,90 m local** (p10–p90: 1,98–3,75).
- Por fuente: 269 ha sobre el MDT urbano y 181 sobre el nacional. 68 ha están en el valle del San Francisco y solo 1,5 ha en islas de OSM.
- Hay 0,7 km de calles adentro: el tramo del puente (que va elevado sobre el agua, así que es un artefacto), Ituzaingó y Calle 17 Segunda.

¿Es razonable mostrarla? **Físicamente, sí.** Si el río está en 4,00 m y el terreno conectado está en 2,9 m, ahí hay agua. Mostrar de más es tolerable. El problema es de **comunicación**:

- Con 3,99 m la app dice "el agua está en su cauce" y no pinta nada; con 4,00 m aparecen de golpe 450–500 ha "sobre tierra".
- Ese cambio no es físico: lo produce `min_m`.
- Además, 236 ha de esas son agua casi siempre.

**Recomendación:**

1. **No** agregar un umbral que deje de pintar agua por encima de `min_m`. Esconder agua es el sentido peligroso, y en el rango de 4,00 a 4,39 m (alerta) ya hay calles bajas que se mojan.
2. Pintar la zona de la capa de 4,00 m con un estilo propio, discreto, como "bañados e islas que se mojan con el río normal". Que el color de inundación se use solo para lo que se agrega por encima de 4,00 m. Se resuelve en la app (dibujar `agua/0400.json` debajo, con otro estilo) sin cambiar el contrato.
3. Para h < 4,00, mostrar igualmente la capa de 4,00 m con ese estilo discreto, o decir "bajo 4,00 m el mapa no tiene detalle", en lugar de "el agua está en su cauce". Así se evita el salto.
4. A mediano plazo, que el pipeline ponga las celdas con llegada ≤ 2,94 m local (las 236 ha) como "agua habitual" en `base.json`. Eso cambia el contrato.

**Chequeo de campo, hoy.** El río está en **5,55 m** (`data/actual.json`), así que la app pintaría la capa de 5,60 m. Esa capa tiene **4,6 km de calles bajo agua**, entre ellas tramos de Avenida Salto, Colonia, Ayacucho, Avenida Wilson Ferreira Aldunate, Avenida Al Hipódromo y María Esther Mussio. Es la mejor validación barata que hay: alguien que recorra la costanera estos días puede confirmar o desmentir esos tramos.

## 5. Simplificación — PASA CON OBSERVACIONES

Recalculé la máscara mojada de cada una de las 66 alturas desde la llegada en caché, con un tamizado reimplementado y anidado verificado, y la rasterice contra la capa publicada reproyectada a 5382:

- **Celdas mojadas con el centro fuera de la capa:** 159 en total entre las 66 capas (2 a 13 por capa, de unos 1,1 a 5,4 M mojadas). Están todas a **menos de 0,9 m** del borde.
  - Algunas están sobre el corte de `limites` y otras en canalitos de una celda de ancho.
  - La causa es el redondeo a 5 decimales (≈ 1 m) después de la simplificación.
  - La garantía "buffer ≥ simplify" se cumple en el plano. El redondeo final la rompe, pero por menos de 1 m, que está muy por debajo del error del MDT (±30 m de borde). **No es significativo.**
  - Si se quiere que la garantía sea estricta, se puede usar `buffer_m = simplify_m + 1` (4 y 5 m).
- **Celdas que podrían quedar parcialmente afuera** (centro a menos de 1,41 m del borde): unas 76.000 entre las 66 capas. Son las que tocan el borde. Es lo esperable con buffer = simplify, y por la misma razón tampoco es significativo.
- **Franja de agua de más:** del +2,7 % (a 10,50 m) al **+11,1 %** (a 4,00 m) del área. Equivale a un ancho medio de **5,1–5,3 m** en todo el borde, un poco más que los 4 m del buffer, por la simplificación y los ángulos. El autor midió del +3 al +9 % en 4 capas; el rango real es algo mayor en las capas bajas. Va en el sentido prudente.
- **Lo que saca el tamizado:** las manchas de menos de 100 m² suman 6.446 celdas en total (≈ 2,6 ha entre las 66 capas; a lo sumo 0,27 ha por capa). Es despreciable.

## 6. Cero de la escala — PASA CON OBSERVACIONES (problema abierto)

**Pendiente, y no se puede verificar desde los datos.** No está confirmado:

- que la "altura" de CARU (`actual.json`, `cero: "Local"`) use el mismo cero que la `cota_local` de Dinagua;
- cuál es el paso local→oficial correcto: +0,11 en `curvas_cri` o +0,14 en `curvas_tr`.

La discrepancia conocida es de **3 cm**. La desconocida (CARU frente a Dinagua) puede ser mayor.

Sensibilidad medida en el raster: cuánto avanza el agua si el nivel real es mayor que el que usa la app.

| Altura | Borde total | +2 cm | +4 cm | +10 cm | +20 cm |
|---|---|---|---|---|---|
| 6,60 | 115 km | 4 ha; mediana 2 m, p95 11 m, máx 65 m | 8 ha; p95 10 m | 20 ha; p95 17 m, máx 67 m | 44 ha; p95 50 m, máx 222 m |
| 8,40 | 130 km | 6 ha; p95 8 m, máx 39 m | 13 ha; p95 11 m | 32 ha; p95 26 m, máx 98 m | 65 ha; p95 56 m, máx 237 m |
| 9,20 | 135 km | 9 ha; p95 9 m, máx 51 m | 17 ha; p95 13 m | 44 ha; p95 45 m, máx 217 m | 102 ha; p95 166 m, máx 290 m |

- **Con 3 cm:** el borde se corre en promedio unos **0,5–0,9 m**, con p95 de unos 10–13 m y máximos de 40–65 m en las zonas más planas. Es menor que el error del modelo. El redondeo hacia arriba de la app lo absorbe en cerca del 70 % de los casos; en el 30 % restante (cuando la altura cae justo en un múltiplo de 0,10 o 1–2 cm por debajo), quedan hasta 3 cm sin cubrir. Lo cubre el margen de +0,50 m.
- **Si la diferencia CARU–Dinagua fuera de 10–20 cm**, el error pasa a ser del mismo orden que las omisiones del §3: p95 de 17–166 m y máximos de 100–290 m. Un sesgo así, del lado peligroso, se comería entre un quinto y dos quintos del margen.

**Acción:** confirmar con CARU y Dinagua por escrito, y anotar la respuesta en `indice.json` (por ejemplo, en `modelo.metodo`) o en `calibracion.json`.

## 7. Otras observaciones

- **δ y la calibración.** Coinciden con el informe: el IoU casi no discrimina δ, y δ lo fija la curva de 2025, que no es independiente. Sumado al cero, la altura equivalente puede estar corrida entre ±0,1 y 0,2 m. El margen de +0,50 m lo cubre con holgura.
- **Las islas secas** (§3.2) deberían mostrarse con un aviso, no como zona segura.
- **Etiqueta errónea en mi `c2.json`.** La clave `"<=-0.06 (mínimo del cálculo…)"` en realidad corresponde a **llegada ≤ 2,94 m local**: la llegada está en la referencia del MDT y la confundí al rotular. Los números del texto ya están corregidos.
- **No revisé** la app ni cómo dibuja la franja de margen. Las condiciones de la §8 lo suponen.

## 8. Recomendación sobre `validado`

**Recomiendo `validado: false`: publicar con el sello "Mapa en prueba"** si se cumplen estas condiciones:

1. La app **siempre** dibuja la franja de margen (de la capa de h hasta la de h + 0,50 m) con una leyenda clara del tipo "el agua puede llegar hasta acá". Sin el margen, la omisión urbana del puerto y el centro (hasta 180 m) queda sin mostrar. **Condición bloqueante.**
2. El texto de la app incluye el aviso de 01 §6: el borde puede variar una cuadra o más, no incluye pluviales ni arroyos, y no reemplaza al Cecoed ni a la Intendencia.
3. El valle del arroyo San Francisco Grande se marca como "zona sin validar", con un rayado o una nota.
4. Se atiende el salto de 3,99 a 4,00 m (§4.2, puntos 2 y 3): estilo propio para la zona ya mojada a 4,00 m y un texto que no diga "en su cauce" si debajo se pintan 450 ha.
5. Las islas secas rodeadas de agua no se presentan como zona segura. Alcanza con un texto general: "si quedás rodeado de agua, también estás en riesgo".

**`validado: true`** (mostrar sin el sello) **solo** después de:

- confirmar por escrito, con CARU y Dinagua, el cero de la escala (CARU = `cota_local` de Dinagua, y +0,11 o +0,14);
- la revisión de alguien de Dinagua o de la Intendencia, con foco en: el puerto y el centro (omisión de 2017/2019), el acceso al puente (2009), el valle del San Francisco Grande y la zona de 4,00 m;
- un chequeo de campo con el río actual (≈ 5,5 m) contra la capa de 5,60 m;
- que, con el margen, la crecida no cubierta quede por debajo del 1 % en todos los eventos de validación. Hoy no se cumple en nov-2009 (1,79 % de borde fuera del margen), salvo que la revisión confirme que el terraplén del puente no se mojó y se documente como error de la curva.

**"No publicar"** si:

- la app no puede dibujar la franja de margen, o la oculta en algún nivel de zoom o estado;
- CARU y Dinagua confirman que los ceros difieren en **más de 0,10 m** y no se recalibra δ (o se corrige la altura que entra a la app) antes de publicar;
- se pretende publicar con `validado: true` sin cumplir las condiciones de arriba.
