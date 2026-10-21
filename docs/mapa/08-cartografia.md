# Pestaña Mapa: cartografía (etapa 8)

Rama `mapa-inundacion` · 21/10/2026 · Cartography Designer. Alcance: el **dibujo** del mapa. No se tocaron la estructura de la pantalla, los textos, los botones, los recuadros ni la leyenda como widget (solo sus muestras de color). Sin commits.

| Control | Resultado |
|---|---|
| `flutter analyze` | **0 problemas** |
| `flutter test` (toda la suite) | **190 OK, 0 fallas**, sin cambiar ningún test |
| Capturas de control | `C:\Users\matic\AppData\Local\Temp\claude\C--Users-matic\7aeaecfb-07bd-4819-84e5-5508d08990ab\scratchpad\capturas-mapa\` (claro y oscuro, 5 de cada uno; ver §9). Capturas v1.1: §7.6 |

## 1. Archivos

- **`app/lib/mapa/estilo_mapa.dart` (nuevo):** toda la cartografía. `ColoresMapa` (paletas `claro` y `noche`), `TrazosMapa` (anchos y patrones), constructores de capas (`poligonosCauce`, `poligonosAgua`, `poligonosContorno`, `lineasCalles`, `lineasCursos`), el rayado (`pinturaRayado`, `TrazadoAgua`, `CapaRayado`), las muestras para la leyenda (`MuestraCauce`, `MuestraAgua`, `MuestraMargen`, `MuestraContorno`) y los rótulos (`Rotulo`, `armarRotulos`, `CacheRotulos`, `CapaRotulos`).
- **`app/lib/pantallas/mapa.dart`:** se sacaron `_ColoresMapa`, `_MuestraMargen`, `_Rotulo`, `_CacheRotulos`, `_CapaRotulos`, `_PintorRotulos`, `_armarRotulos` y `_medio` (pasaron a `estilo_mapa.dart`). La pantalla ahora solo arma las capas con esas piezas; cambió el orden de las capas (§3), se agregó la capa de rayado, el rearmado del fondo si cambia el modo claro/oscuro, y las muestras de la leyenda usan los mismos pintores del mapa (mismas filas, mismos textos).
- **`docs/mapa/herramientas/contraste_mapa.py` (nuevo):** calcula las razones WCAG y la diferencia de color simulando protanopía, deuteranopía y tritanopía (Machado 2009, severidad total). `python -I contraste_mapa.py`.

## 2. Paleta final

Mezclas calculadas como las hace la placa (alfa sobre sRGB). "Efectivo" = el color que se ve. Contraste = razón WCAG 2.x contra el **terreno** salvo que se diga otra cosa.

### Claro (`ColoresMapa.claro`)

| Uso | Hex (ARGB en código) | Efectivo | Contraste | Nota |
|---|---|---|---|---|
| Terreno (fondo) | `#F3F0E8` | — | — | beige cálido: se separa del fondo azulado de la app |
| Cauce (río, espejos) | `#BCD7EF` | `#BCD7EF` | 1,31 | relleno calmo; el contraste lo lleva la orilla |
| Orilla y arroyos | `#3F7FBF` | — | **3,69** | línea 1 px (orilla) y 2,4 px (arroyos) |
| Margen, relleno | `#1F6FC0` al 26 % (`0x421F6FC0`) | `#BCCFDE` | 1,41 | pálido, sin rayado |
| Margen, borde de puntos | `#0B3C5D` | — | **10,1** | puntos de 2,4 px |
| Agua, relleno | `#1F6FC0` al 50 % (`0x801F6FC0`) | `#6D9FCF` (sobre el margen) | 2,46 | translúcido: deja ver las calles |
| Agua, rayado 45° | `#0B3C5D` al 70 % | `#28597F` | **6,49** | 1,4 px cada 7 px; promedio agua+rayado `#5F91BF` = 2,94 |
| Agua, borde continuo | `#0B3C5D` | — | **10,1** · 4,12 contra el agua | 2 px |
| Borde medido de crecida | `#5E2F00` (marrón) | — | **9,80** · 3,98 contra el agua | trazos 9/6, 2,2 px |
| Calle principal (k=1) | `#9C8F76` | — | 2,79 | 3,2 px |
| Avenida (k=2) | `#B3A890` | — | 2,07 | 2,4 px |
| Calle de barrio (k=3) | `#CEC6B6` | — | 1,49 | 1,4 px |
| Nombre de barrio | `#0B2A3F` | — | **13,0** | |
| Nombre de calle | `#33434F` | — | **8,97** | |
| Nombre de arroyo | `#164A7A` | — | **8,04** | itálica |
| Halo de nombres | `#F3F0E8` al 92 % | — | — | 4 px |

### Oscuro (`ColoresMapa.noche`)

| Uso | Hex | Efectivo | Contraste | Nota |
|---|---|---|---|---|
| Terreno | `#1B2A37` | — | — | |
| Cauce | `#173F63` | — | 1,35 | azul hondo, más oscuro que el agua de crecida |
| Orilla y arroyos | `#5B9BD5` | — | **4,95** | |
| Margen, relleno | `#6CB4FF` al 24 % | `#2E4B67` | 1,62 | |
| Margen, borde de puntos | `#BFE0FF` | — | **10,7** | |
| Agua, relleno | `#6CB4FF` al 45 % | `#4A7AAB` | **3,27** | promedio con rayado `#628DB9` = 4,22 |
| Agua, rayado | `#E3F4FF` al 78 % | `#C1D9ED` | **10,1** | |
| Agua, borde continuo | `#E3F1FF` | — | **12,8** · 3,90 contra el agua | |
| Borde medido de crecida | `#FFD89E` (arena) | — | **10,9** · 3,32 contra el agua | |
| Calles k=1 / 2 / 3 | `#7A90A4` / `#61778B` / `#46596B` | — | 4,43 / 3,15 / 2,02 | |
| Nombres barrio / calle / arroyo | `#EAF2F8` / `#C9D7E2` / `#9CCBFF` | — | **12,9 / 9,98 / 8,65** | |
| Halo | `#1B2A37` al 92 % | — | — | |

### Cómo se cumple 3:1 (WCAG 1.4.11, objetos gráficos)

- Cada mancha que hay que distinguir tiene **un borde de ≥ 3:1 contra el terreno y contra su propio relleno**: agua (borde continuo 10,1 / 12,8), margen (puntos 10,1 / 10,7), cauce (orilla 3,69 / 4,95), crecida medida (9,8 / 10,9; y ≥ 3,3 contra el agua). Los rellenos son translúcidos a propósito, para que las calles se vean debajo; el relleno de agua con su rayado queda cerca de 3:1 en claro (2,94) y lo supera en oscuro (4,22).
- Las calles son referencia, no dato: no se les exige 3:1 (las de barrio son claras a propósito para no competir con el agua). Sus nombres sí: todos ≥ 4,5:1 (texto) contra el halo.

### Daltonismo

Diferencia de color (ΔE CIELAB) entre pares que hay que distinguir, simulando cada tipo (de `contraste_mapa.py`):

| Par (claro) | normal | protan. | deutan. | tritan. |
|---|---|---|---|---|
| Cauce / agua+rayado | 30,0 | 28,7 | 31,1 | 29,8 |
| Margen / agua | 27,3 | 25,5 | 29,0 | 26,5 |
| Crecida medida / agua | 78,6 | 73,1 | 76,4 | 75,0 |
| Borde agua / agua | 40,1 | 40,4 | 40,0 | 40,1 |

En oscuro los mismos pares dan 31,8 / 22,4 / 75,6 / 50,0 con variaciones de ±5 entre tipos (tritan., el peor, 54,5 para crecida/agua+rayado). Ningún par baja de ~22 (muy por encima de lo perceptible, ~10). No hay rojo ni verde en el mapa: el eje es **azul ↔ marrón/arena** (el que conservan protanopía y deuteranopía) y, además, **nada depende solo del color**:

| Elemento | Se reconoce por |
|---|---|
| Agua a la altura elegida | **rayado a 45°** + borde **continuo** |
| Margen | **sin rayado**, más pálido + borde de **puntos** |
| Cauce | **liso** + orilla fina |
| Crecida medida | **trazos largos** sin relleno |

En escala de grises (impresión, pantalla al sol con poco brillo) se siguen distinguiendo por lo mismo.

## 3. Simbología y orden de capas

De abajo hacia arriba (`FlutterMap.children` en `mapa.dart`):

1. **Terreno** (`backgroundColor`).
2. **Cauce** — `PolygonLayer`, relleno liso + orilla 1 px.
3. **Arroyos** — `PolylineLayer`, 2,4 px color orilla. Se omite la línea de un curso que va **dentro** del cauce (la del medio del río Uruguay en OSM ensuciaba el río); su nombre sigue saliendo.
4. **Calles** — `PolylineLayer`, de barrio abajo y principales arriba. Van **sobre** el cauce (se ven los puentes) y **debajo** del agua.
5. **Margen** — `PolygonLayer`, relleno pálido + puntos.
6. **Agua** — `PolygonLayer`, relleno 50 % + borde continuo.
7. **Rayado** — `CapaRayado` (nueva, §4).
8. **Borde medido de crecida** (si se prende) — `PolygonLayer`, trazos sin relleno.
9. **Nombres** — `CapaRotulos`.

Cambio respecto de antes: las calles estaban encima del agua. Ahora el agua translúcida va encima, así se lee primero (jerarquía) y las calles se siguen viendo por transparencia, con sus nombres arriba de todo. El orden y la cantidad de `PolygonLayer` (cauce, margen, agua, contorno) no cambió, por eso los tests que los cuentan siguen igual.

Anchos en píxeles (fijos en todo zoom): orilla 1 · arroyo 2,4 · calles 3,2 / 2,4 / 1,4 · borde agua 2 · puntos del margen 2,4 (separación 2×) · crecida 2,2 con trazos 9/6 · rayado 1,4 cada 7.

## 4. El rayado: cómo y por qué así

`flutter_map` 8 no rellena polígonos con patrones. Opciones evaluadas:

| Opción | Costo | Problema |
|---|---|---|
| Líneas de rayado generadas como `Polyline` recortadas contra el agua | recortar cientos de líneas contra polígonos con huecos en cada cambio de altura; cientos de objetos más para proyectar en cada cuadro | la separación cambia con el zoom (están en metros); multiplica objetos |
| Textura (`ImageShader`) | hay que generar la imagen (asíncrono) | misma idea que la elegida, con más pasos |
| **Elegida: un `drawPath` con un degradé repetido** | **un solo dibujo por cuadro**, costo fijo | — |

`TrazadoAgua` proyecta el contorno del agua **una sola vez por capa** (Web Mercator a zoom 16, relativo a su primer punto para no perder precisión en `float`). En cada cuadro `CapaRayado` solo corre y escala el lienzo y pinta ese camino con `pinturaRayado`: un `Gradient.linear` en modo `repeated` con paradas duras (y medio píxel de borde suave). El rayado queda **pegado al terreno al arrastrar** y con **7 px de separación en cualquier zoom**. No se duplican polígonos ni se agregan líneas; la memoria extra es un `Path` del tamaño de la capa (se guarda uno solo, el de la altura visible).

## 5. Reglas de rótulos

| Tipo (prioridad) | Desde zoom | Letra | Color |
|---|---|---|---|
| Barrio (0) | 12,5 | 14,5 / 800, MAYÚSCULAS, espaciado 0,8 | tinta |
| Arroyo / río (1) | 13,5 | 13 / 600 itálica | azul |
| Calle principal (2) | 14 | 13 / 700 | gris azulado |
| Avenida (3) | 14,5 | 12,5 / 600 | gris azulado |
| Calle de barrio (4) | 15,5 | 12 / 500 | gris azulado |

- Nunca menos de 12 px; crecen con la letra del teléfono hasta 130 %. Misma familia que el resto de la app (la del tema).
- **Halo** de 4 px del color del terreno (92 %): se leen encima del agua rayada y de las calles.
- **Sin superposición:** entran por prioridad (y, a igual prioridad, los tramos más largos); un nombre que pisaría otro no se dibuja. Tope de 60 a la vez. 4 px de aire alrededor.
- **Zonas tapadas:** no se ponen nombres debajo de los botones + / − ni de la atribución (`CapaRotulos.tapadas`).
- **Calles largas:** el nombre se ofrece cada 400 m de calle (antes: solo en el medio, y al acercarse se perdía). Entre dos iguales tiene que haber 260 px, así que de lejos sale uno solo.
- El nombre va girado como la calle, nunca cabeza abajo, y solo si cabe en el tramo.
- Barrios sin la palabra "Barrio" ("Barrio Paysandú Sur" → "PAYSANDÚ SUR"), como en la vista previa aprobada.
- La caché de textos medidos se vacía si cambia la paleta o la letra.

## 6. Para el UI Designer: qué muestra la leyenda

Las muestras ya están hechas (`CustomPainter` de 36 × 22, el mismo dibujo que el mapa). Usar estas; no rehacer colores a mano.

| Fila | Muestra (`estilo_mapa.dart`) | Qué se ve | Texto actual |
|---|---|---|---|
| Cauce | `MuestraCauce(c)` | celeste liso con orilla fina | Río y arroyos, en su cauce |
| Agua | `MuestraAgua(c)` | azul con **rayado** y borde continuo | Hasta dónde llegaría el agua (borde continuo) |
| Margen | `MuestraMargen(c)` | azul pálido, **sin rayado**, borde de **puntos** | Puede llegar un poco más (borde de puntos) |
| Crecida medida (solo si está prendida) | `MuestraContorno(c)` | trazos marrones (arena en oscuro) | Borde medido en esa crecida real (trazos) |

`c = ColoresMapa.actuales()`. Sugerencia de texto (decide el UI Designer): "Hasta dónde llegaría el agua (**rayado**)", porque el rayado es lo que la distingue a simple vista, como pedía 03 §4 y §8. La fila del borde del agua de hoy se agregó en la v1.1 (§7.3). "Mi casa" (03 §3) todavía no se dibuja.

## 7. v1.1: zona baja, zona sin validar, lomas aisladas y línea de hoy

21/10/2026 · Cartography Designer · paso 1 del traspaso (12), parte cartografía. Contrato: 05, "Agregados v1.1". Archivos: `app/lib/mapa/estilo_mapa.dart` y la lista de capas y la leyenda de `app/lib/pantallas/mapa.dart`. Sin commits.

| Control | Resultado |
|---|---|
| Choque de nombres `Path` (`dart:ui` y `latlong2`) | Resuelto: en `estilo_mapa.dart` todo camino es `ui.Path` y no queda ningún `Path` suelto |
| `flutter analyze` | **0 problemas** |
| `flutter test` (toda la suite) | **273 OK, 0 fallas** (incluye `mapa_v11_test.dart`; la fila de la leyenda de la zona sin validar, que fallaba, sale de `mapa.dart`). `resumenMapa` recibe `nombresSinValidar`, como pidió el Mobile App Builder |
| Capturas de control | 16 imágenes (7 escenas en claro y en oscuro más la pantalla con la leyenda), hechas con un test temporal que se borró. No hay goldens en el repo (§7.6) |

### 7.1 Estilos nuevos

Contrastes calculados como en §2, alfa sobre sRGB, con `herramientas/contraste_mapa.py`. "Agua" es el agua con su rayado, en promedio.

| Elemento | Dibujo | Claro | Oscuro | Contraste clave (claro / oscuro) |
|---|---|---|---|---|
| **Zona baja de la costa** (capa de `min_m`, siempre) | Relleno casi opaco (92 %), **rayas horizontales** de 1,3 px cada 5 px y borde fino de 1,5 px. Sin rayado a 45° adentro | relleno `#A9CBEA`, rayas `#2F6CA6`, borde `#1F5F99` | `#1E4E7A` / `#6FA8DC` / `#8CC2F0` | borde contra terreno **5,84 / 7,74**; rayas contra su relleno **3,10 / 3,18** |
| **Zona sin validar** | Solo borde, **raya y punto** (14-5-3-5) de 2,5 px con ribete del color del terreno (1,5 px a cada lado). **Sin relleno.** Rótulo "ZONA SIN VALIDAR" (13 px, 800) con halo, uno solo por vista | `#5B2A86` (violeta) | `#D9B8FF` (lila) | contra el ribete **8,70 / 8,55**; contra el agua 2,96 / 2,03 (por eso lleva ribete) |
| **Línea de hoy** (solo al simular otra altura) | Línea **continua y gruesa** de 3 px con ribete de 1,5 px a cada lado, sin relleno, por el borde de la capa de hoy | `#0B2A3F` con ribete blanco | blanco con ribete `#0E1A24` | contra el terreno **13,0 / 14,7**; contra el agua **4,43 / 3,47** |
| **Loma aislada** | Rombo de 26 px (área tocable de 48 dp): ribete claro, anillo del azul del borde del agua, centro del color del terreno y un **"!"** dibujado (no depende de la letra). Al tocarlo se abre la hoja del aviso | — | — | el "!" usa el color de los nombres de barrio (13,0 / 12,9) |
| **Puntos del margen encima** (v1.1 §4) | Los mismos puntos del margen (2,4 px), con ribete del terreno de 1 px a cada lado, dibujados encima de otra capa cuando coinciden con ella | `#0B3C5D` | `#BFE0FF` | contra el ribete **10,1 / 10,7**; contra la zona baja **5,0 / 4,2** |

**Daltonismo** (ΔE CIELAB con protanopía, deuteranopía y tritanopía): zona baja contra agua 12–15 en todos los tipos, y zona baja contra margen 15–20. Son valores bajos, pero el color no es lo que las distingue: las rayas **horizontales** contra las de **45°** y el relleno parejo contra el pálido con puntos. Zona sin validar contra el borde del agua: 17 en deuteranopía (el violeta tira a azul), pero la separa el ribete claro (8,7:1) y el patrón de raya y punto, que no usa ninguna otra línea. Línea de hoy contra el borde del agua: ~10 en todos (los dos son azul muy oscuro en claro y casi blanco en oscuro). Las distingue el **grosor** (6 px con ribete contra 2 px) y el ribete del color opuesto. No hay rojo ni verde. Todo se reconoce sin color:

| Elemento | Se reconoce por |
|---|---|
| Zona baja | rayas **horizontales** + relleno parejo |
| Zona sin validar | **raya y punto** con ribete, sin relleno, y su nombre escrito |
| Línea de hoy | la línea **más gruesa** del mapa, continua y con ribete |
| Loma aislada | **rombo con "!"** |

### 7.2 Orden de capas final

De abajo hacia arriba (`FlutterMap.children` en `pantallas/mapa.dart`):

1. Terreno (`backgroundColor`).
2. Cauce: `PolygonLayer`.
3. Arroyos: `PolylineLayer`.
4. Calles: `PolylineLayer`.
5. **Margen**: `PolygonLayer`, siempre que haya capas (v1.1 §4).
6. **Agua**: `PolygonLayer`.
7. **Rayado del agua**: `CapaRayado`, con `excluir` igual a la zona baja (el rayado a 45° es para el agua que se suma al río normal).
8. **Zona baja**: `CapaZonaBaja`, siempre.
9. Borde medido de una crecida (si se prende): `PolygonLayer` sin relleno. Sigue siendo el último `PolygonLayer`, como fija `mapa_test`.
10. **Zona sin validar**: `PolylineLayer`, solo líneas.
11. **Línea de hoy**: `PolylineLayer`, solo líneas.
12. **Puntos del margen encima**: `PolylineLayer`, solo cuando la capa del margen es la misma que la del agua (en 10,50 m o más), la de la zona baja (con 3,50 m o menos) o la de la línea de hoy.
13. Nombres: `CapaRotulos`.
14. Rótulo "Zona sin validar": `CapaRotuloZona`.
15. **Lomas aisladas**: `MarkerLayer`, arriba de todo para que se puedan tocar.

**Por qué nada tapa el agua ni el margen:**
- De la capa 9 para arriba son **solo líneas sin relleno**, textos y marcas puntuales.
- La única capa nueva con relleno es la **zona baja** (8). Va encima del agua, pero la capa de `min_m` está **dentro de toda capa de agua** (son anidadas, con 1 % de tolerancia). Por eso no le quita agua al mapa: a ese pedazo de agua lo muestra con su propio dibujo, que también es agua (azul, nunca color de tierra).
- Va encima y no debajo para que se vea **igual con cualquier altura**: debajo del agua translúcida cambiaba de tono al pasar por 4,00 m, y el rayado a 45° le daba un cuadriculado ilegible.
- El borde del agua y el del margen quedan **afuera** de la zona baja, así que no se tapan.
- Cuando el margen coincide con otra capa que va arriba, sus puntos se repiten encima (capa 12). Con 3,50 m, el margen (capa de 4,00) es igual a la zona baja. Con 10,50 m o más, es igual al agua: el borde del agua se ve de puntos ("puede llegar más lejos"). Los dos casos se ven en las capturas 5b y 6.
- **La línea de hoy no se dibuja si su capa es la misma que la del agua** (por encima del máximo, las dos serían la de 10,50 m y la línea no diría nada). Cambio en `_lineaHoyVisible` de `mapa.dart`.

### 7.3 Leyenda

Filas nuevas en `_leyenda` de `mapa.dart`, con los textos de `mapa_partes.dart` y la palabra del dibujo:

| Fila | Muestra | Cuándo |
|---|---|---|
| `textoLeyendaZonaBaja` + "(rayas horizontales)" | `MuestraZonaBaja` | siempre que se pudo leer la capa |
| "Hasta dónde llega el agua con el río de hoy (línea gruesa)", o "con el último dato" | `MuestraHoy` | solo si la línea está dibujada |
| `textoLeyendaAisladas` + "(rombo con "!")" | `MarcaAislada` | si la capa pintada tiene lomas |
| `textoLeyendaSinValidar` + "(raya y punto)" | `MuestraSinValidar` | si `sin_validar.json` se pudo leer |

El texto de la fila de hoy está escrito en `mapa.dart`, porque en `mapa_partes.dart` no hay una constante para eso (§10).

### 7.4 Decisiones v1.1

- **Línea de hoy de 3 + 3 px**, no 3,5 + 4 px como en el primer borrador. En las capturas, la línea de 7,5 px tapaba casi toda la zona baja angosta de la costa y el rayado de las franjas finas.
- **La línea de hoy también corre por el lado del río**, porque es el contorno completo de la capa. Se ve como un borde grueso entre el cauce y el agua. Recortarla contra el cauce dejaría igual media línea (va justo sobre la orilla), así que se dejó entera.
- **Zona sin validar sin relleno:** un velo encima del agua cambiaría su tono y podría leerse como "acá hay menos agua". Si se pintara debajo, el agua lo taparía.
- **Violeta/lila** para la zona sin validar: no es azul de agua, ni marrón/arena de crecida medida, ni naranja/amarillo de niveles, ni rojo/verde.
- **Un solo rótulo por vista** para la zona sin validar: el punto interior más cerca del centro que entra entero y no cae bajo los botones. Va arriba de los nombres de calles y puede pisar alguno.
- **La loma tiene el centro del color del terreno** porque es tierra seca, pero lleva "!" y el anillo de agua, y el texto dice que puede quedar aislada. Nunca usa verde ni dice "seguro".

### 7.5 Lo que se ve en las capturas

Datos reales de `app/assets/mapa/`. La **zona sin validar** es un rectángulo **sintético** al norte de la ciudad (-58,105 a -58,075; -32,285 a -32,265) y la **loma aislada** es un punto **sintético** (-58,0945; -32,3051, un hueco real de la capa de 7,00 m). Los datos reales todavía no traen esos campos.

1. **Hoy 5,93 m, zoom 13,5:** en la costa, una franja celeste de rayas horizontales (zona baja) contra el río. Tierra adentro, el agua rayada a 45° con borde continuo y el margen de puntos por fuera. El rombo de la loma se lee sobre el agua.
2. **Zoom 15 sobre la loma:** se distinguen los tres dibujos (horizontal, 45° y puntos) y los nombres de calles con halo.
3. **Simulación de 8,00 m con hoy en 6,00:** la línea de hoy, oscura con ribete blanco (blanca con ribete oscuro de noche), corre dentro del agua y por el lado del río. Es lo primero que se ve, como corresponde a "hasta dónde llega hoy". En oscuro es el elemento que más resalta.
4. **8,00 m sobre la zona sin validar:** el borde de raya y punto violeta (lila de noche) con ribete y el rótulo "ZONA SIN VALIDAR". Adentro, el agua y la zona baja se ven igual que afuera.
5. **Simulación de 3,90 m:** zona baja y margen de 4,40 m. 5b (hoy 3,50 m): solo la zona baja, con los puntos del margen encima de su borde. El margen se ve.
6. **Hoy 11,20 m:** el agua de 10,50 m con el borde de puntos encima ("puede llegar más lejos"). El margen se ve.
7. **Pantalla con la leyenda:** filas de cauce, agua, margen, zona baja, hoy, loma y zona sin validar, legibles en claro y en oscuro.

Defectos vistos: ninguno que tape agua. Quedan para mirar en el teléfono el peso de la línea de hoy en modo oscuro y que el rótulo de la zona pise algún nombre de calle (§10).

### 7.6 Capturas

En `/tmp/claude-0/-home-user/b1728d81-bcdd-5e42-8a2b-64b12d87fbb1/scratchpad/capturas/` (fuera del repo, temporales). Se hicieron con un `matchesGoldenFile` de ruta absoluta en `app/test/zz_capturas_temporal_test.dart`, con la letra Roboto cargada desde el SDK, y el archivo **se borró** después de correrlo.

## 8. Decisiones

- **Cauce calmo, crecida fuerte** (como la vista previa aprobada, `mapa-real.html`), no al revés como decía 03 §3: lo que hay que ver primero es el agua sobre tierra.
- **Agua siempre azul**, nunca el color del nivel (03 §3).
- **Margen hacia afuera y "con agua":** se pinta azul (pálido), nunca del color del terreno, para no sugerir que esa franja está seca. Ante la duda, más agua.
- **Crecida medida en marrón/arena** (antes bordó/rosa): el bordó y el rosa se confunden con el azul en deuteranopía y tritanopía; el marrón/arena es el opuesto del azul en todos los tipos, y no es el naranja ni el amarillo de los niveles.
- **Sin "casing" (borde) en las calles:** duplicaría las polilíneas que proyecta `flutter_map`. Las calles se jerarquizan por ancho y tono.
- **Modo claro/oscuro en caliente:** si cambia la paleta con la pantalla abierta, el fondo, el agua, el contorno y los nombres se rearman con la nueva.

## 9. Capturas de control

En `C:\Users\matic\AppData\Local\Temp\claude\C--Users-matic\7aeaecfb-07bd-4819-84e5-5508d08990ab\scratchpad\capturas-mapa\`, en claro y oscuro:

1. `1-ciudad-z13_5-*` — apertura (zoom 13,5).
2. `2-barrio-z15_5-*` — costa a zoom de barrio: agua rayada, margen de puntos, borde medido en trazos, nombres de calles.
3. `3-calle-z17-*` — zoom de calle (el rayado mantiene 7 px).
4. `4-costa-z14_5-*`.
5. `5-pantalla-*` — pantalla entera con la leyenda.

Hechas con un test temporal (copiado a `test/`, corrido y borrado: el repo no usa goldens) sobre los assets provisorios + una **curva de control sintética** (la capa de 6,30 m usada como "borde medido") y el río en 5,93 m. El agua es la inventada de los assets provisorios.

## 10. Pendientes

1. **Probar en el Redmi al sol y de noche** con los datos reales: legibilidad de nombres de 12 px, si el rayado de 7 px "vibra" en pantallas de baja densidad (si molesta, subir a 8–9 px en `TrazosMapa.periodoRayado`), y fluidez al arrastrar (perfilador).
2. **Borde del agua hoy:** hecho en la v1.1 (§7). **Mi casa** todavía no existe en la pantalla. Simbología propuesta: círculo con halo y la palabra "Mi casa" (nunca verde).
3. **Margen sobre la tierra seca solamente:** hoy el agua se pinta encima del margen (capas anidadas) y su color efectivo incluye el margen; está contemplado en los contrastes. Si los datos reales no cumplen el anidado (tolerancia 1 %), puede verse un filo de margen dentro del agua: inofensivo.
4. **Nombres de OSM raros** ("P3", "E. Garzon" sin tilde): vienen del fondo; corregir en el pipeline o en OSM, no en la app.
5. Con letra al 200 % los nombres se topan en 130 %: confirmar con vecinos si alcanza.
6. Escala gráfica y flecha de norte (03 §11): no están; el mapa no rota, así que el norte es siempre arriba.
7. **v1.1, mirar en el Redmi:** el peso de la línea de hoy en modo oscuro (si tapa demasiado, bajar a 2,5 + 2,5 px en `TrazosMapa.hoy`/`ribeteHoy`); que las rayas horizontales de 5 px de la zona baja no "vibren"; y que el rótulo "ZONA SIN VALIDAR" no pise nombres importantes.
8. **v1.1, para el equipo de la app:** el texto de la fila de la leyenda de la línea de hoy está escrito en `mapa.dart`. Conviene pasarlo a una constante `textoLeyendaHoy` en `mapa_partes.dart`, como las demás, y fijarlo en un test. Además, el resumen dice "Línea gruesa: hasta dónde llega el agua con el río de hoy" y ahora la línea no se dibuja cuando su capa es la misma que la del agua (por encima del máximo). El resumen ya lo sigue, porque recibe `hoyCm` de `_lineaHoyVisible`.
9. **v1.1, con los datos reales del pipeline:** volver a mirar la zona sin validar y las lomas con su geometría verdadera. Si las lomas son muchas en una misma vista, los rombos de 26 px pueden taparse entre sí; en ese caso habría que agruparlos.
