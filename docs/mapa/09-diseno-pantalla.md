# Pestaña Mapa: diseño de la pantalla (etapa 9)

Rama `mapa-inundacion` · 21/10/2026 · UI Designer. **Especificación para implementar; no se tocó código.**
Maqueta: [`maqueta-pantalla.html`](maqueta-pantalla.html) (abrir en el navegador: 4 estados en claro y en oscuro, más un ejemplo a 320 dp con letra al 200 %).

Alcance: todo lo que **no** es el dibujo del mapa. El dibujo (colores del agua, rayado, capas, rótulos, atribución sobre el mapa) es del cartógrafo y queda en `docs/mapa/08-cartografia.md`. Esta pantalla solo le reserva un lugar (el **marco del mapa**, §3.5) y arma la **leyenda** como widget que recibe sus muestras.

Resuelve los pendientes del informe 07 §8: **1** (un solo recuadro), **3** (botones de alturas) y **6** (tinte, aviso de simulación, "Cómo se usa", "Ver fuentes"). "Mi casa" y las zonas en texto quedan para más adelante (§9).

Base: `03-diseno-visual.md` (se mantiene salvo donde este documento dice otra cosa), `tema.dart`, `textos.dart`, `comunes.dart`, `inicio.dart`.

---

## 1. Reglas que no se negocian

1. **Nunca transmitir "estás a salvo".** Ninguna frase dice "a salvo", "seguro", "no se inunda", "zona segura", "sin peligro". Nada de tilde verde ni ícono de aprobación junto a una altura, una calle o un barrio. El caso "en su cauce" no lleva pastilla de nivel ni ícono de "todo bien".
2. **"No reemplaza la alerta oficial" siempre a la vista**, pegado al mapa (pie del marco) y otra vez al final de la pantalla.
3. **El tinte es el del río de hoy, nunca el de la altura que se está probando.** Probar 9,20 m no tiñe la pantalla de rojo; tampoco la "tranquiliza" probar 3,00 m en plena crecida.
4. **Ante la duda, más agua y más aviso**: si algo no se pudo leer o el río supera el mapa, se dice con palabras, al lado del número.
5. **Una simulación nunca se confunde con hoy**: el bloque de lectura se invierte (panel oscuro en modo claro, panel claro en modo oscuro) y dice "No es el río de hoy". Al salir de la pestaña y volver, se vuelve a hoy.
6. **Un solo recuadro ámbar** en toda la pantalla (§4).
7. Todo lo tocable mide **48 × 48 dp como mínimo**; los botones principales, 56 dp de alto (tema de la app).

---

## 2. Jerarquía de arriba hacia abajo

Qué responde cada bloque, en el orden en que lo lee la persona y TalkBack:

| # | Bloque | Responde | Aparece |
|---|---|---|---|
| 0 | **Barra superior** teñida | (marco de la app) | siempre |
| 1 | **Franja de hoy** | ¿Cómo está el río hoy? | siempre |
| 2 | **Recuadro ámbar** (uno solo) | ¿Hay algo raro con el dato de hoy? | solo si hay problema |
| 3 | **Tarjeta "Cómo se usa"** | ¿Qué es esto? | solo la primera vez |
| 4 | **Lectura** (normal o invertida) | ¿Qué altura estoy mirando? ¿Es hoy o una simulación? | siempre |
| 5 | **Marco del mapa**: sello de calidad + mapa + pie | ¿Hasta dónde llega el agua? ¿Cuánto le creo? | siempre |
| 6 | **"Ver qué hacer"** en el color del nivel | ¿Qué hago? | solo si **hoy** es alerta o evacuación |
| 7 | **Probar otra altura**: − / deslizador / + y marcas | ¿Cómo pruebo otra altura? | siempre (salvo mapa no disponible) |
| 8 | **Alturas para comparar** (grilla de botones) + interruptor del borde medido | Atajos con nombre | si hay al menos un botón |
| 9 | **Qué muestra el mapa** (leyenda) | ¿Qué es cada cosa? | siempre |
| 10 | **Este mapa es aproximado** (texto fijo) + datos + `Ver fuentes` · `Cómo se usa` | ¿De dónde sale? ¿Qué no tiene en cuenta? | siempre |

En un teléfono de 360 × 780 con letra normal y sin avisos, el mapa entra entero en la primera pantalla: barra 56 + franja 64 + lectura ≈ 112 + sello 44 + mapa 300 + pie 36 ≈ 640 dp (más la barra de estado y la de pestañas, ≈ 96 dp). Con letra grande el mapa baja y está bien: la lectura en texto va primero.

---

## 3. Componentes

### 3.0 Barra superior y tinte (coherente con Inicio)

- La pestaña Mapa se tiñe **igual que Inicio**: misma función `tinteInicio(datos, config, ahora)` → `ColoresNivel.tinte(nivel)`, **gris "Sin dato" si el dato es viejo o no hay dato**. La barra superior toma ese color y pierde la línea de abajo (`shape: const Border()`), como en Inicio.
- Fondo: degradé más corto que el de Inicio (el mapa es opaco y abajo hay muchos controles): `degradeMapa(tinte)` = `[tinte, tinte, Colores.fondo]` con `stops: [0, 0.10, 0.34]`. El degradé no se desplaza con la lista (está detrás, como en Inicio).
- Sobre el tinte solo va texto en `Colores.tinta` o en `ColoresNivel.familia(nivel)` (ya comprobados ≥ 4,5:1 en Inicio). La lectura invertida (§3.4) tiene fondo propio.
- No se repiten las olas de Inicio: el mapa ya es denso.

### 3.1 Franja de hoy

Una línea fuerte y una de apoyo, mismos textos y colores que Inicio. Un solo nodo para TalkBack.

| Estado | Línea 1 (titleLarge 22, peso 800) | Línea 2 (bodyMedium 16) | Extra |
|---|---|---|---|
| Dato fresco | `Río hoy: 5,63 m` + ícono y palabra del nivel en `familia(nivel)` | `Hoy 15:00 · CARU` | — |
| Dato fresco, sin conexión | `Último dato: 5,63 m` + nivel | `Hoy 09:00 · CARU` | Renglón con ícono `wifi_off` 24: `Sin conexión. Dato guardado en este teléfono.` (titleMedium, como Inicio; **no** es recuadro) |
| Dato viejo | `Último dato: 5,63 m` + nivel | `Ayer 09:00 · CARU` | (el recuadro lo explica, §4) |
| Sin dato | `Río hoy: sin dato` + ícono `help` y palabra `Sin dato` en gris | — | si además no hay conexión, el renglón `wifi_off` dice `Sin conexión a internet.` |
| Otra referencia (cero) | `Río hoy: no se puede pintar` | — | (el recuadro lo explica) |

- Ícono + palabra van en una `Row(mainAxisSize: min)` dentro de un `Wrap` (como hoy): con letra grande el par baja de renglón entero.
- TalkBack: `Río hoy: 5,63 metros. Nivel: Alerta. Medido hoy a las 15:00. Fuente: CARU.`

### 3.2 Recuadro ámbar único

Ver reglas de prioridad en §4. Reusa `Recuadro` de `comunes.dart` (fondo `#FFF4D6` / `#3A2E12`, ícono `#7A4A00` / `#FFC857`, texto bodyLarge 18). Va entre la franja y la lectura, con 12 dp arriba.

### 3.3 Tarjeta "Cómo se usa" (primera vez)

- Superficie (`Colores.superficie`, radio 20, relleno 16), entre el recuadro y la lectura.
- Se muestra hasta que la persona toca `Entendido`; se guarda en `SharedPreferences` con la clave `mapa_como_se_usa_visto = true`. Nunca vuelve sola; se reabre desde `Cómo se usa` al pie (§3.10), que muestra el mismo contenido en una hoja inferior.
- Contenido exacto:

> **Cómo se usa** (titleMedium, encabezado)
> 1. Mové la barra o tocá **−** y **+** para elegir una altura del río.
> 2. El mapa pinta hasta dónde llegaría el agua con esa altura.
> 3. Es aproximado: el agua puede llegar más lejos. No reemplaza la alerta oficial.
>
> [ `Entendido` ] (FilledButton, ancho completo, 56 dp)

- Los números de la lista van como texto (no viñetas de color). Con letra al 200 % cada paso ocupa 2–3 renglones; la tarjeta crece, el mapa baja.

### 3.4 Lectura: qué altura se está mirando

Dos modos visuales. El cambio de modo es **el** aviso de simulación (reemplaza la "franja oscura" separada de 03 §2: un solo bloque, menos ruido, mismo efecto).

**Modo hoy** (la altura elegida es la de hoy redondeada): sin fondo propio, sobre el tinte.

```
Altura de hoy en el mapa                (bodyLarge, tintaSecundaria)
5,70 m                                   (40, peso 800, cifras tabulares)
Hoy el río está en 5,63 m. El mapa lo redondea hacia arriba.   (bodyMedium; solo si difieren)
```
No lleva pastilla de nivel: el nivel de hoy ya está en la franja.

**Modo simulación** (cualquier otra altura, o no hay hoy): panel **invertido**, radio 20, relleno 16.
- Claro: fondo `Colores.tinta` `#0B2A3F`, texto `Colores.fondo` `#EEF4F8` (13,4:1).
- Oscuro: fondo `#EAF2F8`, texto `#0E1A24` (15,6:1).

```
⚠ No es el río de hoy                   (titleMedium 18, peso 800, ícono science/biotech 24)
Simulación con
9,20 m   [■ EVACUACIÓN]                  (40 peso 800 + pastilla de nivel)
3,57 m más que hoy.                      (bodyLarge)
[ ↶ Volver a hoy ]                       (OutlinedButton 56 dp, ancho completo, borde y texto del color del panel)
```
- Pastilla: relleno `estiloNivel(n).fondo`, texto `estiloNivel(n).texto` (≥ 5:1), ícono + palabra en mayúsculas, radio 999, alto 32, relleno 12 horizontal. Si los umbrales no están validados, a la derecha de la pastilla y fuera de ella: `(de referencia)`.
- Sin dato de hoy: rótulo `Simulación con` sin "No es el río de hoy", línea `No hay dato del río de hoy.` y **sin** botón.
- Dato viejo: título `No es el último dato`, botón `Volver al último dato`, comparación `… más que el último dato.`

**Líneas adicionales** (debajo del número, en cualquiera de los dos modos, en este orden):

| Situación | Texto exacto | Estilo |
|---|---|---|
| Río en cauce (`enCauce`) | `Con esta altura el agua queda en su cauce. Los puntos muestran hasta dónde podría llegar con un poco más.` (si no hay margen dibujado: `…en su cauce. El mapa no muestra agua sobre la tierra con esta altura.`) | bodyLarge. **Sin pastilla** de nivel, sin ícono. |
| Río sobre el máximo (`sobreMaximo`) | `El mapa llega hasta 10,50 m. Con más altura, el agua llega más lejos de lo que se ve.` | bodyLarge peso 600 con ícono `warning_amber` 24 a la izquierda |
| Crecida redondeada | `Crecida de dic. 2015: 9,12 m. El mapa lo redondea hacia arriba a 9,20 m.` | bodyMedium |
| Capa reemplazada | `No se pudo leer el dibujo de 6,90 m. Se muestra el de 7,00 m, con un poco más de agua.` | bodyLarge |
| Capa ilegible | `No se pudo leer el dibujo del agua para esta altura.` | bodyLarge |

- El número usa `MediaQuery.withClampedTextScaling(maxScaleFactor: 1.4)` + `FittedBox(scaleDown)`: con letra al 200 % no se corta ni empuja la pastilla fuera (la pastilla baja de renglón: `Wrap`).
- TalkBack: un nodo `liveRegion`. Modo hoy: `Altura de hoy en el mapa: 5,70 metros.` Modo simulación: `No es el río de hoy. Simulación con 9,20 metros, nivel Evacuación. 3,57 metros más que hoy.` El botón `Volver a hoy` es nodo aparte.

### 3.5 Marco del mapa (lugar para el dibujo del cartógrafo)

Una sola superficie con radio 20 y `clip`, en tres partes pegadas:

1. **Sello de calidad** (arriba, solo si el índice no está validado). Franja ámbar (mismos colores que `Recuadro`), relleno 12 × 10, ícono 24 + texto bodyMedium 16 peso 600. **No es un recuadro** (no compite con el de §3.2): es parte del mapa, como un sello.
   - `validado: false`: ícono `construction` · `Mapa en prueba: el agua puede llegar más lejos de lo que muestra.`
   - Provisorio: ícono `science` · `Datos de prueba: el agua es inventada. No la uses para decidir nada.` (peso 800)
2. **Mapa** (del cartógrafo): alto = `clamp(alto de pantalla × 0,40, 240, 320)` dp. Botones de acercar/alejar 48 × 48 (ya están). La atribución sobre el mapa la define el cartógrafo.
3. **Pie del marco** (siempre): franja `Colores.superficie`, relleno 12 × 8, bodyMedium 16, ícono `info_outline` 20: `Aproximado. No reemplaza la alerta oficial.` (constante `textoAvisoMapa`, sin cambios).

TalkBack: el sello y el pie son nodos de texto propios (se leen antes y después de la descripción del mapa).

### 3.6 "Ver qué hacer"

Solo si el nivel **de hoy** (no el probado) es alerta o evacuación: botón de ancho completo, 56 dp, `StadiumBorder`, colores `ColoresNivel.boton(nivel)`, texto `Ver qué hacer`. Va justo debajo del marco del mapa, 16 dp arriba. Lleva a la pestaña Qué hacer arriba de todo (`_irAQueHacer` de `main.dart`). Es el mismo widget de Inicio, movido a `comunes.dart`.

### 3.7 Probar otra altura

```
Probar otra altura                         (titleMedium, encabezado)
Altura elegida: 9,20 m                     (titleMedium peso 800; ExcludeSemantics: el deslizador ya la dice)
[ − ]  ━━━━━━━━━━━━━●━━━━━━━━━━━  [ + ]
           ▲Alerta         ▲Evacuación     (marcas sobre la pista, sin texto)
▲ Alerta: 4,39 m · ▲ Evacuación: 6,89 m    (Wrap, bodyMedium; ícono y palabra del nivel)
```
- La línea "Altura elegida" existe porque, con letra grande, el número grande de la lectura queda fuera de la pantalla mientras se arrastra.
- `−` y `+`: `IconButton.filledTonal` 56 × 56, ícono 28, tooltip `Bajar 10 cm` / `Subir 10 cm`. Deshabilitados en los extremos.
- Deslizador: pista 8 dp, pulgar 28 dp, área táctil de toda la fila (≥ 48 de alto); relleno de la pista en `Colores.primario` (no en el color del nivel). Rango y paso sin cambios (10 cm; del mínimo − 10 cm al máximo o a hoy si es mayor).
- Marcas: palitos de 2 × 10 dp debajo de la pista en `Colores.tinta`, en la posición de alerta y evacuación (y atención si existe). El texto de las marcas va en la línea de abajo (`Wrap`), nunca pegado al palito: así no se pisan a 320 dp ni con letra al 200 %. Con umbrales no validados: `Alerta: 4,39 m (de referencia)`.
- Vibración: `HapticFeedback.selectionClick()` **al soltar** el deslizador o al tocar − / + / un botón de altura, solo si la nueva altura cruzó un umbral respecto de la anterior.
- TalkBack: `MergeSemantics` (como hoy). Valor: `9,20 metros, nivel Evacuación` (sin nivel si no hay umbrales; `…, en su cauce` si está debajo del mapa). Al soltar, anuncio: el mismo texto de la lectura (§3.4).

### 3.8 Alturas para comparar

Encabezado `Alturas para comparar` (titleMedium). Grilla de botones de dos renglones:

| Botón | Renglón 1 (titleMedium) | Renglón 2 (bodyLarge) | Aparece si |
|---|---|---|---|
| Hoy | `Hoy` (o `Último dato` si es viejo o sin conexión) | `5,70 m` (la redondeada) | hay hoy pintable |
| Pronóstico | `Pronóstico CARU` | `hasta 5,60 m · 18/10` | `pronostico.vigente` y `alturaEsperadaM != null` y mismo cero |
| Alerta | `Nivel de alerta` | `4,39 m` (+ ` (de referencia)` si no validado) | hay umbral |
| Evacuación | `Nivel de evacuación` | `6,89 m` | hay umbral |
| Crecidas | nombre del índice, p. ej. `Crecida de dic. 2015` | `9,12 m` | por cada referencia del índice, ordenadas por altura |

- **Columnas**: 2 si `anchoDisponible / escalaLetra ≥ 300` dp; si no, 1. (360 dp con letra normal → 2; 320 dp o letra ≥ 115 % → 1.) Las filas de 2 usan `IntrinsicHeight` para que los dos botones midan lo mismo. Alto mínimo 64 dp; el texto puede bajar de renglón, nunca se corta (sin `ellipsis`).
- Separación 8 dp. Estilo normal: `OutlinedButton` (borde `primario` 1,5). **Elegido**: `FilledButton` en `primario` + ícono `check` 20 a la izquierda del renglón 1 + `Semantics(selected: true)`. El estado no depende solo del color.
- Al tocar: el deslizador va a esa altura redondeada hacia arriba; se anuncia; vibra si cruzó umbral.
- Si se arrastra el deslizador justo a la altura de un botón, el botón se marca (como hoy).
- Debajo de la grilla, sin cambios: el interruptor `Ver el borde medido en esa crecida` (solo con una crecida con contorno elegida) y sus textos.
- TalkBack: `Crecida de diciembre de 2015, 9,12 metros, botón, seleccionado`.

### 3.9 Leyenda: "Qué muestra el mapa"

Widget nuevo `LeyendaMapa` que **no conoce colores**: recibe una lista de entradas `(muestra, texto)` armada en `mapa.dart` con los colores y pinceles del cartógrafo (08). Siempre abierta.

- Encabezado `Qué muestra el mapa` (titleMedium). Filas: muestra 40 × 24 dp (`ExcludeSemantics`) + 12 dp + texto bodyLarge. Alto mínimo de fila 36 dp; con letra grande el texto baja de renglón y la muestra queda arriba (`crossAxisAlignment.start`).
- Textos exactos (la palabra entre paréntesis describe el dibujo para quien no distingue colores; el cartógrafo confirma cuál corresponde en 08):

| Entrada | Texto | Aparece |
|---|---|---|
| Cauce | `Río y arroyos, en su cauce` | siempre |
| Agua | `Hasta dónde llegaría el agua con la altura elegida (rayado)` | siempre |
| Margen | `Puede llegar un poco más: hasta 50 cm más de altura (puntos)` (50 cm = `formatoDiferencia(indice.margenM)`) | siempre |
| Borde de hoy | `Hasta dónde llega el agua con el río de hoy (línea gruesa)` | solo en modo simulación y si el cartógrafo dibuja esa línea |
| Borde medido | `Borde medido en esa crecida, según Dinagua (trazos)` | solo con el interruptor prendido |

- La entrada "Mi casa" queda para cuando exista.

### 3.10 Pie: "Este mapa es aproximado", datos y fuentes

```
Este mapa es aproximado                    (titleMedium, encabezado)
Muestra hasta dónde podría llegar el río con esa altura, según el terreno.
No tiene en cuenta la lluvia, los desagües ni las calles cortadas.
Que una calle no aparezca con agua no quiere decir que no se inunde.
Seguí siempre las indicaciones del Cecoed. Emergencias: 911.      (bodyLarge)

Datos: OpenStreetMap, IDE Uruguay, Dinagua y CARU.
Mapa armado el 3/10/2026.                  (bodyMedium, tintaSecundaria)

[Ver fuentes]   [Cómo se usa]              (TextButton subrayados, 48 dp; Wrap)
```

**Hoja "Fuentes"** (`showModalBottomSheet`, `isScrollControlled`, `useSafeArea`, contenido desplazable, botón `Cerrar` de 56 dp al final). Texto exacto (adaptado de 04 §1.5, sin enlaces en esta versión, ver §9):

> **Fuentes del mapa**
> - **Calles, río y barrios:** © colaboradores de OpenStreetMap. Datos con licencia ODbL (openstreetmap.org/copyright).
> - **Terreno:** modelo digital del terreno de la IDE Uruguay (vuelo 2017–2018). Licencia de Datos Abiertos de Uruguay. Lo recortamos y calculamos qué partes quedan por debajo de cada altura del río.
> - **Crecidas medidas:** curvas de inundación de Dinagua, Ministerio de Ambiente. Las recortamos y simplificamos.
> - **Altura del río y pronóstico:** CARU.
>
> Mapa armado el 3/10/2026. Los datos fueron modificados por Mi Río UY. Ni el Ministerio de Ambiente, ni la IDE, ni CARU, ni OpenStreetMap avalan esta app ni son responsables de lo que muestra.
>
> [ Cerrar ]

Si el índice trae `fuentes`, se listan además debajo, tal cual vienen (como hoy). La línea `textoAtribucion` sobre el mapa no cambia.

---

## 4. Avisos: uno solo y con prioridad clara

Hay **dos familias** y cada una tiene **un solo lugar**:

| Familia | Lugar | Por qué |
|---|---|---|
| **El dato de hoy** (¿le creo al número?) | Recuadro ámbar único, arriba (§3.2) | Afecta todo lo que dice "hoy": franja, lectura, botón Hoy. |
| **La calidad del mapa** (¿le creo al dibujo?) | Sello pegado arriba del mapa (§3.5) | Afecta solo al dibujo; tiene que leerse justo antes de mirarlo, y no puede taparse con el aviso del dato. |

Así nunca hay dos recuadros, y ninguno de los dos mensajes se pierde.

**Prioridad del recuadro** (gana el primero que se cumple; los demás no se muestran):

| # | Condición | Ícono | Texto exacto |
|---|---|---|---|
| 1 | `hoy.motivo == 'cero'` | `straighten` | `El mapa usa otra referencia de altura que el dato del río. Por eso no se pinta el río de hoy. Igual podés probar alturas.` |
| 2 | Sin dato (y sin conexión) | `wifi_off` | `Sin conexión y sin un dato confiable de hoy. Esto no quiere decir que el río esté bajo. Igual podés probar alturas.` |
| 3 | Sin dato | `help_outline` | `No hay un dato confiable de hoy. Esto no quiere decir que el río esté bajo. Igual podés probar alturas.` |
| 4 | Dato viejo | `schedule` | `El último dato es de ayer 09:00. El río pudo cambiar: mirá Inicio o los canales oficiales.` |
| 5 | Aviso `dato_a_verificar` del lector | `warning_amber` | `textoAviso('dato_a_verificar')` (mismo de Inicio) |

- **Sin conexión con dato fresco** no es recuadro: es el renglón `wifi_off` de la franja (igual que Inicio).
- **Umbrales no validados**: no es recuadro; se marca `(de referencia)` en marcas, botones y pastilla (como hoy).
- **Sello del mapa**: provisorio gana sobre `validado: false`; con `validado: true` no hay sello.
- El problema de la altura que se está mirando (cauce, sobre el máximo, capa reemplazada) va **en la lectura**, al lado del número, nunca en el recuadro.

Función pura testeable: `avisoHoyMapa(HoyMapa hoy, DateTime ahora) → ({IconData icono, String texto})?` y `selloMapa(IndiceMapa) → ({IconData icono, String texto, bool fuerte})?`.

---

## 5. Estados de la pantalla

| Estado | Tinte / barra | Franja | Recuadro | Lectura | Sello | Qué hacer | Botón Hoy |
|---|---|---|---|---|---|---|---|
| **Normal** | verde | `Río hoy: 3,62 m ✓ Normal` | — | modo hoy | según índice | — | sí |
| **Alerta** | naranja | `Río hoy: 5,63 m ⚠ Alerta` | — | modo hoy | según índice | **sí** | sí |
| **Evacuación** | rojo | `Río hoy: 7,05 m ■ Evacuación` | — | modo hoy (abre en hoy) | según índice | **sí** | sí |
| **Simulando otra altura** | el de **hoy** | igual | igual | **invertida** + `Volver a hoy` | igual | si hoy es grave | sí (no marcado) |
| **Sin dato** | gris | `Río hoy: sin dato` | #3 (o #2) | invertida, `Simulación con` (abre en alerta) | según índice | — | **no** |
| **Dato viejo** | gris | `Último dato: …` | #4 | modo hoy con rótulo `Altura del último dato en el mapa` | según índice | si el nivel del último dato es grave | `Último dato` |
| **Sin conexión, dato fresco** | del nivel | `Último dato: …` + renglón `wifi_off` | — | modo hoy | según índice | según nivel | `Último dato` |
| **Otra referencia (cero)** | gris | `Río hoy: no se puede pintar` | #1 | invertida, `Simulación con` (abre en la capa más baja) | según índice | — | no |
| **Río en cauce** (altura < mínimo) | el de hoy | igual | igual | sin pastilla + línea de cauce | igual | igual | igual |
| **Río sobre el máximo** | el de hoy | igual | igual | número real (10,80) + línea `El mapa llega hasta 10,50 m…` con ícono | igual | casi seguro sí | sí |
| **Mapa en prueba** (`validado: false`) | — | — | — | — | `Mapa en prueba: …` | — | — |
| **Datos provisorios** | — | — | — | — | `Datos de prueba: el agua es inventada…` | — | — |
| **Cargando el río** | sin tinte | — | — | — | — | — | — (texto `Cargando el nivel del río…`, como hoy) |
| **Preparando el mapa** | del nivel | franja ya visible | — | — | — | — | — (texto `Preparando el mapa…` en el lugar del marco, alto del mapa) |
| **Mapa no disponible** | del nivel | franja | — | — | — | — | — (`El mapa todavía no está disponible` + motivo + `La altura del río sigue en Inicio y en Gráfico.`) |

Notas:
- "Preparando el mapa" y "no disponible": hoy la pantalla entera se reemplaza por el texto. Propuesta: mantener la franja de hoy arriba y poner el texto en lugar del marco (la persona igual ve cómo está el río). Es un cambio chico de `build`.
- **Al volver a la pestaña** (venir de otra), si la persona había elegido otra altura, se vuelve a hoy sin anuncio, y se apaga el borde medido. Evita que alguien vuelva días después y vea una simulación creyendo que es el río.
- **Abre en hoy también en crecida** (03 §6 proponía abrir en el pronóstico; ver decisión en §9).

---

## 6. Letra al 200 % y 320 dp

Se prueba con `MediaQuery(textScaler: TextScaler.linear(2.0))` y ancho 320 (contenido 288 dp).

| Bloque | Comportamiento |
|---|---|
| Franja | `Wrap`: el par ícono + palabra baja de renglón entero. |
| Recuadro | Crece en alto; ícono arriba a la izquierda. |
| Tarjeta "Cómo se usa" | Crece; botón `Entendido` de ancho completo. |
| Lectura | Número con tope 1,4 × y `FittedBox`; la pastilla baja de renglón (`Wrap`); botón `Volver a hoy` de ancho completo con texto en 2 renglones si hace falta (sin `ellipsis`). |
| Sello y pie del marco | Crecen en alto; sin tope (son avisos). |
| Mapa | Alto fijo dentro de [240, 320]: no se achica por la letra. Rótulos del mapa: tope 1,3 × (del cartógrafo). |
| Control | `−` / `+` de 56 fijos; el deslizador se queda con 288 − 112 − 16 = 160 dp (suficiente con paso de 10 cm porque − / + dan el control fino). Texto de marcas en `Wrap` debajo. |
| Grilla | Pasa a **1 columna**. |
| Leyenda | Texto en varios renglones; muestra arriba. |
| Pie y hoja de fuentes | Desplazables; botones en `Wrap`. |

Nada usa `maxLines` + `ellipsis` en textos de seguridad. Prueba: ningún `RenderFlex overflowed` en los estados de §5, en claro y oscuro, y todos los botones alcanzables con `ensureVisible`.

---

## 7. Modo oscuro

Todo sale de `Colores` y `ColoresNivel`, que ya tienen las dos paletas. Puntos propios de esta pantalla:

| Elemento | Claro | Oscuro | Contraste del texto |
|---|---|---|---|
| Tinte | `ColoresNivel.tinte(n)` (16 % sobre blanco) | 22 % sobre `#0E1A24` | tinta sobre tinte ≥ 4,5 (ya probado en Inicio) |
| Lectura invertida | fondo `#0B2A3F`, texto `#EEF4F8` | fondo `#EAF2F8`, texto `#0E1A24` | 13,4:1 / 15,6:1 |
| Botón `Volver a hoy` (dentro del panel) | borde y texto `#EEF4F8` | borde y texto `#0E1A24` | ídem |
| Sello del mapa | `#FFF4D6` + ícono `#7A4A00` + tinta | `#3A2E12` + ícono `#FFC857` + tinta clara | 13,5:1 / 11,7:1 |
| Pie del marco | `Colores.superficie` `#FFFFFF` | `#16283A` | tinta ≥ 12:1 |
| Pastilla de nivel | `EstiloNivel.fondo/texto` | ídem (sus valores oscuros) | ≥ 5:1 (garantizado en `textos.dart`) |
| Botón elegido de la grilla | `primario` `#0B3C5D` + texto blanco | `#8CCBEE` + texto `#06283D` | 11,5:1 / 8,6:1 |

Agregar a la prueba de contraste de la app (`contraste()` de `textos.dart`): panel invertido en los dos modos y texto `familia(nivel)` sobre `tinte(nivel)` para la franja.

---

## 8. TalkBack: orden de foco

franja → recuadro → tarjeta "Cómo se usa" → lectura (liveRegion) → `Volver a hoy` → sello → mapa (descripción del cartógrafo) → pie del marco → `Ver qué hacer` → `Bajar 10 cm` → deslizador → `Subir 10 cm` → marcas (texto) → botones de altura → interruptor del borde → leyenda → "Este mapa es aproximado" → `Ver fuentes` → `Cómo se usa`.

Anuncios (`SemanticsService.sendAnnouncement`) solo al soltar el deslizador o tocar un botón, nunca en cada paso del arrastre.

---

## 9. Lo que tenés que decidir

1. **¿Abrir en hoy o en el pronóstico durante una crecida?** 03 §6 proponía abrir en el pronóstico de CARU si es mayor que hoy. **Recomiendo abrir siempre en hoy** y dejar `Pronóstico CARU` como primer botón después de `Hoy`: abrir en una simulación hace que lo primero que ve alguien en plena crecida no sea el río real, y la línea "borde de hoy" todavía no está dibujada para comparar.
2. **Enlaces en "Ver fuentes".** Para abrir openstreetmap.org, gub.uy y la IDE hay que agregarlos a `enlaces_permitidos` de `assets/config.json`. Recomiendo la primera versión **solo con texto** (sin enlaces) y sumarlos después.
3. **Zonas en texto** ("el agua llega a: Costanera, Puerto…"). Con los datos de hoy (`lugares` son puntos, no barrios) la lista saldría incompleta y un barrio ausente se leería como "no le llega": **riesgo de falsa tranquilidad**. Recomiendo esperar a que el pipeline publique, por capa, qué barrios toca cualquier parte del agua o del margen. Mientras, la descripción para TalkBack se queda como está.
4. **Palabra para otra altura.** ~~"Prueba"~~ → el usuario eligió **"Simulación"**: `No es el río de hoy` / `Simulación con 9,20 m`. Vale probarlo con 2–3 vecinos mayores.

---

## 10. Cambios de código (para implementar cuando termine el cartógrafo)

Para no pisar `mapa.dart`, los widgets nuevos van en un archivo aparte; `mapa.dart` solo los arma.

### `app/lib/pantallas/mapa_partes.dart` (nuevo)

| Elemento | Qué es |
|---|---|
| Textos (`const`) | Todos los de §3–§4 y §3.10 (`textoComoSeUsa…`, `textoMapaAproximado…`, `textoFuentes…`). `textoAvisoMapa`, `textoAtribucion`, `textoMapaNoDisponible` se mueven acá y se reexportan desde `mapa.dart` para no romper los tests. `textoMapaEnPrueba` y `textoMapaProvisorio` cambian de texto (§3.5). |
| `avisoHoyMapa(HoyMapa, DateTime)` | Prioridad de §4 (reemplaza `_aviso`). Pura. |
| `selloMapa(IndiceMapa)` | Provisorio > en prueba > nada. Pura. |
| `FranjaHoyMapa` | Reemplaza `_FranjaHoy`; agrega el renglón `wifi_off` y el caso cero. |
| `LecturaMapa` | Reemplaza `_Lectura`. Parámetro `modo` (hoy / simulación) calculado afuera; panel invertido; pastilla; líneas de §3.4; `alVolver` + texto del botón. |
| `PastillaNivel` | Ícono + palabra sobre `EstiloNivel.fondo`. |
| `MarcoMapa` | `child` (el mapa del cartógrafo) + sello + pie. Recibe el alto. |
| `ControlAltura` | Reemplaza `_control` y `_BotonPaso`: encabezado, línea "Altura elegida", − / deslizador / +, marcas (`CustomPaint` debajo del `Slider` con las fracciones de los umbrales) y `Wrap` de textos. Callbacks `alCambiar(cm)` y `alSoltar()`. |
| `AlturaComparar` | Registro: `tipo` (hoy, pronostico, alerta, evacuacion, crecida), `titulo`, `detalle`, `metros`, `referencia?`. |
| `GrillaAlturas` + `BotonAltura` | Reemplazan `_alturasDeReferencia` (la parte de botones) y `_BotonAltura`: dos renglones, check en el elegido, 1 o 2 columnas según §3.8. |
| `LeyendaMapa` + `EntradaLeyenda` | Reemplaza `_Leyenda`; recibe las muestras. |
| `TarjetaComoSeUsa` + `mostrarComoSeUsa(context)` | Tarjeta de primera vez y la misma en hoja inferior. |
| `PieMapa` + `mostrarFuentes(context, IndiceMapa)` | Bloque final y hoja de fuentes. |

### `app/lib/pantallas/mapa.dart`

- `PantallaMapa`: nuevos parámetros `SharedPreferences? prefs` (primera vez), `VoidCallback? alVerQueHacer`, `bool activa` (para volver a hoy al regresar a la pestaña).
- `didUpdateWidget`: si `activa` pasa de `false` a `true` y `_elegidaPorUsuario`, `_elegirInicial()` sin anuncio y apagar `_verContorno`.
- `build`: nuevo orden de §2. Mientras carga o si no está disponible, la franja de hoy queda arriba y el texto va en el lugar del marco (§5).
- Quitar los dos `Recuadro` de provisorio / en prueba de arriba (pasan al sello).
- `_ir`: después de fijar `_cm`, si cruzó un umbral respecto del valor anterior → `HapticFeedback.selectionClick()` (solo con `usuario: true`).
- `_textoAnuncio` y `semanticFormatterCallback`: textos de §3.4 y §3.7 (con nivel).
- Lista de alturas: agregar `Hoy`/`Último dato` y `Pronóstico CARU` (de `widget.datos?.actual?.pronostico`, solo si `vigente`, `alturaEsperadaM != null` y `hoy.motivo != 'cero'`).
- Alto del mapa: `altoMapa` pasa a calcularse (`clamp(MediaQuery.sizeOf(context).height * 0.40, 240, 320)`).
- La leyenda se arma con los colores y pinceles que defina el cartógrafo.

### `app/lib/pantallas/comunes.dart`

- Mover `_BotonQueHacer` de `inicio.dart` como `BotonQueHacer` público (sin cambios de estilo).

### `app/lib/pantallas/inicio.dart`

- Usar `BotonQueHacer`. Agregar `degradeMapa(Color tinte)` al lado de `degradeInicio`.

### `app/lib/main.dart`

- Tinte también en Mapa: `final tenida = _pestana == Pestana.inicio || _pestana == Pestana.mapa;` → `tinte = tenida ? tinteInicio(…) : null`; la barra sin borde inferior en las dos; degradé `degradeInicio` o `degradeMapa` según la pestaña.
- Pasar a `PantallaMapa`: `prefs: widget.prefs`, `alVerQueHacer: _irAQueHacer`, `activa: _pestana == Pestana.mapa`.

### Pruebas (`app/test/mapa_test.dart` y nuevas)

- Ajustar los textos que cambian: `Se muestra el agua con …` → `Altura de hoy en el mapa` / `Simulación con` + número; `No es el río de hoy: es una prueba con 4,30 m (10 cm más que hoy)` → `No es el río de hoy` + `10 cm más que hoy.`; `Río hoy: sin dato confiable` → `Río hoy: sin dato`; textos de recuadros nuevos; `textoMapaEnPrueba` sigue apareciendo **antes** del mapa (el sello está arriba del mapa: la prueba de 07 vale tal cual).
- Nuevas: prioridad del recuadro (tabla §4, un caso por fila y combinaciones: sin dato + en prueba muestra recuadro **y** sello, nunca dos recuadros); botón Hoy y Pronóstico (aparece / no aparece); grilla 1 vs 2 columnas; "Cómo se usa" se muestra una vez y se guarda; al volver a la pestaña vuelve a hoy; vibración solo al cruzar umbral (`SystemChannels.platform` mock); ningún texto de la pantalla contiene "a salvo", "seguro", "zona segura", "no se inunda" en todos los estados; tinte de la barra en Mapa = tinte de Inicio; panel invertido con contraste ≥ 7:1 en los dos modos; 320 dp × 200 % sin desbordes en todos los estados de §5.

## Decisiones del usuario (21/10/2026)

1. En crecida la pestaña abre en la altura de **hoy**; "Pronóstico CARU" queda como segundo botón.
2. "Ver fuentes": **solo texto**, sin enlaces (no se toca `enlaces_permitidos`).
3. Lista de zonas o barrios en texto: **se espera** a que el pipeline publique qué barrios toca cada altura.
4. Palabra para otra altura: **"Simulación"** (no "Prueba"). Ej.: "No es el río de hoy · Simulación con 9,20 m". Cambiar en todos los textos y tests que la usen.

## Implementado (21/10/2026)

Sin commit. Archivos: `app/lib/pantallas/mapa_partes.dart` (nuevo), `mapa.dart` (solo el armado de la pantalla y la lógica de lectura/alturas; el dibujo del cartógrafo quedó igual), `comunes.dart` (`BotonQueHacer`, sin cambios de aspecto), `inicio.dart` (usa `BotonQueHacer`; `degradeMapa`), `main.dart` (tinte en Mapa; `prefs`, `alVerQueHacer`, `activa`), `test/mapa_test.dart`. No se tocó `estilo_mapa.dart`, `lector/`, `data/` ni `.github/`.

Controles: `flutter analyze` sin problemas · `flutter test` **202 OK** (mapa: 49) · `flutter build apk --release` OK, 51,4 MB.

**Quedó como dice el diseño**
- Orden de §2; tinte y barra del nivel de **hoy** también en Mapa (degradé corto), nunca el de la altura simulada.
- Un solo recuadro (`avisoHoyMapa`, prioridad de §4) + sello de calidad pegado arriba del mapa (`selloMapa`); "sin conexión" con dato fresco es un renglón de la franja.
- Lectura en dos modos: hoy (sobre el tinte) y **Simulación** (panel invertido, 13,4:1 / 15,6:1): "No es el río de hoy" / "Simulación con" / número / pastilla / "10 cm más que hoy." / "Volver a hoy". Variantes de último dato, sin dato y otra referencia. Abre en hoy (decisión 1).
- Cauce, sobre el máximo (con ícono), crecida redondeada y capa reemplazada como renglones de la lectura.
- Marco del mapa: sello arriba, mapa de 240–320 dp (40 % de la pantalla), pie "Aproximado. No reemplaza la alerta oficial." pegado abajo.
- "Ver qué hacer" en el color del nivel solo si hoy es alerta o evacuación.
- Control: encabezado, "Altura elegida", − / deslizador / + de 56 dp, marcas de los umbrales dibujadas sobre la pista (`PistaConMarcas`) y su texto en renglón aparte; TalkBack dice "4,20 metros, nivel Alerta"; vibración solo al soltar o tocar si cruzó un umbral.
- Grilla "Alturas para comparar" de dos renglones: Hoy / Último dato, Pronóstico CARU (si vigente y mismo cero), alerta, evacuación y crecidas; 2 columnas si `ancho / letra ≥ 300`, si no 1; elegido con relleno y tilde.
- Leyenda "Qué muestra el mapa" con las muestras del cartógrafo (08 §6) y la palabra del dibujo: "(rayado)", "(borde de puntos)", "(trazos)".
- "Cómo se usa" la primera vez (se guarda en `mapa_como_se_usa_visto`) y en hoja desde el pie; "Ver fuentes" en hoja, **solo texto** (decisión 2).
- Al volver a la pestaña, una simulación vuelve a hoy y se apaga el borde medido.
- Pruebas nuevas: prioridad de avisos, nunca dos recuadros, Hoy/Pronóstico, columnas, vibración, "Cómo se usa", fuentes, vuelta a hoy, tinte igual a Inicio, contraste del panel, "Ver qué hacer" solo con hoy grave, palabras prohibidas en 7 estados y simulando, 320 dp × 130/200 % en 6 estados, claro y oscuro.

**Cambios respecto del diseño**
- Con nivel **Normal** la simulación no lleva pastilla (sería un tilde verde junto a una altura, contra la regla 1). Solo Atención, Alerta y Evacuación.
- El texto "(de referencia)" va al lado de la pastilla y baja de renglón con letra grande.

**No quedó (pendiente)**
- Fila de leyenda y línea "Hasta dónde llega el agua con el río de hoy": el dibujo no existe en `estilo_mapa.dart` (08 §6). Es del cartógrafo.
- "Preparando el mapa" y "Mapa no disponible" siguen ocupando toda la pantalla (sin la franja de hoy arriba, §5): necesita el índice para calcular "hoy" y se dejó como estaba.
- Zonas en texto (decisión 3), "Mi casa" y enlaces en fuentes (decisión 2): para más adelante.
- Probar en el Redmi y con 2–3 vecinos mayores la palabra "Simulación" y el panel invertido.

Capturas (claro y oscuro: normal con "Cómo se usa", alerta, evacuación con simulación de una crecida y su borde, sin dato, 320 dp con letra al 200 %): carpeta `capturas-pantalla` del scratchpad de la sesión. El test temporal de capturas no quedó en el repo.
