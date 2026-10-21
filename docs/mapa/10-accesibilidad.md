# Pestaña Mapa: auditoría de accesibilidad (etapa 10)

Rama `mapa-inundacion` · 21/10/2026 · Accessibility Auditor. Norma: **WCAG 2.2 AA** y pautas de accesibilidad de Android (toques de 48 dp, TalkBack, "Quitar animaciones"). Sin commits.

| Control | Resultado |
|---|---|
| `flutter analyze` | **0 problemas** |
| `flutter test` (toda la suite) | **227 OK** (202 de antes + 25 nuevos en `test/mapa_accesibilidad_test.dart`), sin cambiar ningún test existente |
| Archivos tocados | `app/lib/pantallas/mapa.dart`, `app/lib/pantallas/mapa_partes.dart`, `app/test/mapa_accesibilidad_test.dart` (nuevo). **No** se tocó `estilo_mapa.dart` (ningún color del mapa necesitó cambio), ni `lector/`, `data/` o `.github/` |
| Capturas de control | `C:\Users\matic\AppData\Local\Temp\claude\C--Users-matic\7aeaecfb-07bd-4819-84e5-5508d08990ab\scratchpad\capturas-a11y\` (claro 100 % y oscuro 200 % a 320 dp, con el aviso de dos dedos a la vista) |

## 1. Cómo se probó y qué falta

- **Árbol de semántica real**: se volcó el árbol que Flutter le pasa a TalkBack, en orden de recorrido, en hoy, en simulación y con crecida. Los hallazgos de TalkBack de §3 salen de ese volcado, no de leer el código.
- **Pautas automáticas de Flutter** (`androidTapTargetGuideline`, `labeledTapTargetGuideline`, `textContrastGuideline`): a 320 dp, con letra al 100, 130 y 200 %, en claro y oscuro y en 4 estados (hoy en alerta con "Cómo se usa", simulación con crecida y borde medido, sin dato, dato viejo). Son 24 pantallas y pasan todas.
- **Contrastes** calculados con la fórmula WCAG (`contraste()` de `textos.dart` en los tests y el mismo cálculo en Python para las tablas).
- **Gestos** simulados en test: un dedo vertical y horizontal sobre el mapa, pellizco con dos dedos, flechas y + / −. Se comprobó que el test de "un dedo mueve la página" **falla con la configuración anterior** (la página se quedaba quieta: 0 px) y pasa con la nueva.

**Sin probar (hay que hacerlo a mano, §7):** TalkBack real en el Redmi (cómo pronuncia cada etiqueta, a dónde va el foco, si se oyen los anuncios), Voice Access, Accesibilidad con interruptores, lupa, alto contraste del sistema y pantalla al sol.

**Conformidad WCAG 2.2 AA: NO DETERMINADA.** Lo automatizable pasa, pero falta la prueba con TalkBack en el teléfono, y queda un hallazgo moderado abierto (M6). No hay que declarar "cumple" hasta hacer §7.

## 2. Resumen

| Severidad | Encontrados | Arreglados | Abiertos |
|---|---|---|---|
| Crítico | 1 | 1 | 0 |
| Serio | 5 | 5 | 0 |
| Moderado | 6 | 5 | 1 (M6, foco al tocar "Volver a hoy") |
| Menor | 5 | 0 | 5 (aceptados, con motivo) |

## 3. Hallazgos

### Crítico

**C1. El mapa atrapaba el desplazamiento de la página.** WCAG 2.5.7 (Movimientos de arrastre) y pauta de Android: un gesto no puede quedar atrapado. *Arreglado.*
- Antes, el `FlutterMap` (240 a 320 dp de alto, casi todo el ancho) tenía `InteractiveFlag.all`. Un dedo sobre el mapa movía el mapa y no la página. Con TalkBack es peor, porque el desplazamiento con dos dedos llega a la app como un solo dedo: quien exploraba con el dedo y quería bajar quedaba "pegado" al mapa. Comprobado en test: la página no se movía nada.
- Ahora, con **un dedo** se mueve la **página**. El mapa se mueve con **dos dedos** (`pinchMove`), se acerca pellizcando (`pinchZoom`) o con **doble toque** sobre el punto que interesa (`doubleTapZoom`), y siempre con **+ / −** y con las **flechas** nuevas (S3). Se sacaron `drag`, `flingAnimation`, `doubleTapDragZoom` y `rotate`.
- Si alguien arrastra **de costado** con un dedo sobre el mapa, aparece 3 s el aviso "Para mover el mapa usá dos dedos o las flechas de abajo." (tinta sobre fondo: 13,4:1 en claro y 15,6:1 en oscuro). Es solo visual, porque quien usa TalkBack no arrastra el mapa. Se sumó un paso a "Cómo se usa".
- **Cambio de uso para validar con vecinos:** quien está acostumbrado a Google Maps va a intentar mover el mapa con un dedo. Es el mismo criterio que usa Google Maps incrustado en una página ("usá dos dedos"). Ver §7.

### Serios

**S1. Botones de "Alturas para comparar": TalkBack no decía cuál estaba elegido.** WCAG 4.1.2. *Arreglado.*
En el árbol, `selected` quedaba en un **nodo vacío aparte**, padre del botón. El botón no llevaba el estado. Ahora `MergeSemantics` deja un solo nodo: "Nivel de evacuación, 6,89 metros (de referencia)", botón, seleccionado. Visualmente ya estaba bien: relleno y tilde, no solo color.

**S2. La lectura era `liveRegion` y se anunciaba de más.** WCAG 4.1.3 (Mensajes de estado). *Arreglado.*
- El bloque de la lectura era región viva. Con el arrastre se habría anunciado en **cada paso de 10 cm**, contra lo que pide el 09 §8. Además se sumaba al `sendAnnouncement`, así que al soltar se oía dos veces. Su etiqueta era el texto pegado: "4,30 m", "EVACUACIÓN".
- Ahora la lectura es **un nodo sin `liveRegion`**, con el texto en palabras: "No es el río de hoy. Simulación con 4,30 metros, nivel Evacuación (de referencia). 10 centímetros más que hoy." "Volver a hoy" queda como nodo aparte. Se anuncia **una sola vez**, al soltar el deslizador, al tocar − / + o un botón, o con la acción de TalkBack sobre el deslizador (subir o bajar con el volumen). Está fijado en tests: nada mientras se arrastra, uno al soltar y uno por acción.

**S3. No había forma de mover el mapa sin arrastrar.** WCAG 2.5.7. *Arreglado.*
Se agregó la fila **"Mover el mapa"** dentro del marco, entre el mapa y el pie: ← ↑ ↓ →, de 48 × 48 dp, con nombres "Ver más al oeste, hacia el río", "Ver más al norte", "Ver más al sur" y "Ver más al este". Cada toque corre el mapa un tercio de lo que se ve. Junto con + / − (48 dp), todo el mapa se recorre con toques sueltos.

**S4. La descripción del mapa no equivalía al dibujo.** WCAG 1.1.1. *Arreglado (sin lista de barrios, como decidió el usuario).*
Antes decía solo "Agua dibujada con X metros. Es aproximado." Ahora `resumenMapa()` (función pura, testeada) arma, según el caso:
- "Mapa de la costa de Paysandú, con el río, las calles y los barrios."
- en simulación: "Simulación: no es el río de hoy."
- "Agua dibujada con 6,20 metros: el rayado muestra hasta dónde llegaría. Los puntos, hasta dónde puede llegar con 50 centímetros más de altura."
- en el cauce, sobre el máximo ("El mapa llega hasta 10,50 metros. Con 10,80 metros el agua llega más lejos de lo que se ve.") y con el dibujo ilegible, su frase propia;
- con el borde medido prendido: "Línea de trazos: el borde medido en la crecida "…"."
- siempre al final: "Es aproximado: el agua puede llegar más lejos. Este resumen no dice qué calles o barrios alcanza el agua."

La última frase es a propósito. Sin la lista de barrios, el resumen no puede dar a entender que una zona queda seca.

**S5. Al cambiar la altura no se decía qué pasaba con el agua.** WCAG 4.1.3. *Arreglado.*
Al anuncio de la lectura se le agrega `fraseAgua()`: "El mapa ahora muestra el agua con 4,30 metros. Puede llegar más lejos." En el cauce, sobre el máximo o con el dibujo ilegible no se agrega, porque la lectura ya lo dice con palabras.

### Moderados

**M1. El deslizador no tenía nombre**: TalkBack leía solo "4,20 metros, nivel Alerta". WCAG 4.1.2. *Arreglado*: "Altura del río para el mapa" + el valor.

**M2. La pista vacía del deslizador no se veía.** WCAG 1.4.11. *Arreglado.*
`primarioSuave` contra el fondo daba **1,15:1** en claro y **1,49:1** en oscuro: no se veía hasta dónde llega la barra. La nueva `ColoresDeslizador.pistaVacia` es `#5E8199` en claro (**3,73:1** contra el fondo, 4,14 contra la tarjeta) y `#4A7590` en oscuro (**3,56:1**). Contra la parte llena da 2,8, y el pulgar las separa.
*Residual:* el degradé del tinte está fijo detrás de la lista. Si se desplaza la página hasta que el control queda en el 10 % de arriba de la pantalla, con un nivel fuerte en oscuro la pista vacía puede bajar a ~2,1:1 (Atención). Es poco probable y la parte llena y el pulgar siguen arriba de 5:1.

**M3. La pastilla de nivel no crecía más que 130 %.** WCAG 1.4.4. *Arreglado*: tope de 200 % y la palabra puede bajar de renglón dentro de la pastilla. Pasa sin desbordes a 320 dp × 200 %.

**M4. Unidades abreviadas para el lector.** Los botones de la grilla y las marcas del deslizador decían "4,39 m" y "hasta 6,66 m · 8/10". *Arreglado*: "4,39 metros", "hasta 6,66 metros, informe del 8/10", "Marca de alerta: 4,15 metros (de referencia)". Así es en toda la app (`unidadesEnPalabras`).

**M5. No se respetaba "Quitar animaciones".** Es WCAG 2.3.3 (AAA) y además lo pidió el usuario. *Arreglado*: con la preferencia del sistema prendida, el doble toque acerca **sin animar** (`doubleTapZoomDuration: 0`) y las hojas "Ver fuentes" y "Cómo se usa" **aparecen sin deslizarse**. El arrastre ya no tiene inercia (se sacó `flingAnimation`). No queda ninguna animación propia en la pestaña. La **vibración** (`HapticFeedback.selectionClick`, solo al cruzar un umbral) respeta el ajuste del sistema "Respuesta táctil": si está apagado, Android no vibra.

**M6. Al tocar "Volver a hoy", el botón desaparece y el foco de TalkBack queda sin destino.** WCAG 2.4.3. *No arreglado.*
Flutter no tiene una forma estable de mover el foco de accesibilidad a otro nodo. El anuncio dice qué pasó ("Altura de hoy en el mapa: 4,20 metros…"). Hay que ver en el Redmi a dónde cae el foco (§7). Si cae arriba de todo, la alternativa es dejar el botón visible y deshabilitado en modo hoy, lo que cambiaría el diseño del 09.

### Menores (aceptados)

- **m1.** La atribución sobre el mapa tiene un tope de 120 % y los nombres del mapa uno de 130 % (WCAG 1.4.4). Se dejan así: los nombres son parte del dibujo, que tiene su resumen textual, y la atribución está repetida en el pie ("Datos: OpenStreetMap, IDE Uruguay, Dinagua y CARU.") con la letra completa.
- **m2.** La pastilla amarilla de Atención casi no se distingue del panel invertido claro (1,25:1, modo oscuro), pero la identifican su texto (12,3:1) y su ícono. 1.4.11 no exige el borde.
- **m3.** Los círculos blancos de + / − se confunden con el terreno beige (1,14:1). Los identifica el ícono: 11,6:1 en claro y 8,5:1 en oscuro.
- **m4.** El nodo del mapa es una imagen y TalkBack dice "imagen" después del resumen. Es correcto y se deja.
- **m5.** `SemanticsService.sendAnnouncement` usa `announceForAccessibility`, que Android 16 marca como obsoleto. Funciona en las versiones anteriores. Si el Redmi tiene Android 16 y los anuncios no se oyen, el plan B es una región viva propia que cambie solo al soltar (§7).

## 4. Lo que ya estaba bien (conservarlo)

- La franja de hoy es un solo nodo con todo en palabras ("Río hoy: 4,13 metros. Nivel: Alerta. Medido hoy 12:00. Fuente: CARU…").
- Orden de lectura comprobado en test: franja → recuadro → "Cómo se usa" → lectura → "Volver a hoy" → **sello "Mapa en prueba"** (nodo propio, antes del mapa) → mapa en palabras → Acercar / Alejar → "Mover el mapa" y flechas → **pie "Aproximado. No reemplaza la alerta oficial."** → "Probar otra altura" → Bajar → deslizador → Subir → marcas → grilla → interruptor → leyenda → pie → Ver fuentes / Cómo se usa.
- Encabezados en cada bloque ("Probar otra altura", "Alturas para comparar", "Qué muestra el mapa", "Este mapa es aproximado", "Cómo se usa").
- Nada depende solo del color: agua **rayada**, margen de **puntos**, borde medido en **trazos** (y la leyenda lo dice con palabras); el nivel lleva ícono y palabra; el botón elegido lleva relleno y tilde; el interruptor, tilde o cruz.
- Todos los toques miden 48 dp o más: − / + 56, grilla 64 de alto, botones 56, enlaces del pie 48, zoom y flechas 48. Lo confirma `androidTapTargetGuideline`.
- A 320 dp con letra al 130 y al 200 %, en claro y oscuro, nada se corta ni se superpone (tests existentes y nuevos).
- El interruptor del borde medido tiene nombre, subtítulo y estado ("activado" o "desactivado").

## 5. Contrastes (claro / oscuro)

| Elemento | Colores | Contraste |
|---|---|---|
| Lectura invertida (simulación) | `#EEF4F8` sobre `#0B2A3F` / `#0E1A24` sobre `#EAF2F8` | 13,4 / 15,6 |
| Pastilla de nivel (texto sobre relleno) | Atención · Alerta · Evacuación | 12,3 · 5,65 · 6,57 (oscuro 5,62) |
| Sello ámbar: texto / ícono | tinta / `#7A4A00` sobre `#FFF4D6` · tinta clara / `#FFC857` sobre `#3A2E12` | 13,5 / 6,8 · 11,8 / 8,6 |
| Botón elegido de la grilla | blanco sobre `#0B3C5D` / `#06283D` sobre `#8CCBEE` | 11,5 / 8,6 |
| Botón sin elegir (texto y borde) | `primario` sobre el fondo | 10,4 / 10,0 |
| Rótulo de la lectura en modo hoy sobre el tinte | `tintaSecundaria` sobre `tinte(nivel)`, los 5 niveles | ≥ 5,9 / ≥ 5,2 |
| Deslizador: parte llena / pista vacía | contra el fondo | 10,4 / **3,73** · 10,0 / **3,56** (antes 1,15 / 1,49) |
| Muestras de la leyenda, bordes contra el fondo de la app | orilla · borde del agua · puntos · trazos | ≥ 3,79 (claro), ≥ 5,95 (oscuro) |
| Botones − / + y flechas (ícono sobre relleno) | `primario` sobre `primarioSuave` | 9,05 / 6,71 |
| Aviso de dos dedos | fondo sobre tinta | 13,4 / 15,6 |

Los colores del dibujo del mapa (08 §2) **no cambiaron**: sus bordes ya tenían 3:1 o más, y las muestras de la leyenda también tienen 3:1 o más sobre el fondo de la app (fijado en test).

## 6. Pruebas nuevas (`app/test/mapa_accesibilidad_test.dart`, 25)

- **TalkBack:** la lectura es un nodo en palabras y sin `liveRegion`, con "Volver a hoy" aparte; el deslizador tiene nombre, valor y acciones; los botones de la grilla llevan "seleccionado" en el mismo nodo, también después de elegir una crecida; el interruptor tiene nombre y estado; orden de lectura del sello al deslizador.
- **Mapa en palabras:** `resumenMapa` en 5 situaciones (sin "m" abreviada y sin palabras prohibidas) y el nodo del mapa en simulación con borde medido.
- **Anuncios** (canal `SystemChannels.accessibility`): nada al abrir; uno por cambio con la frase del agua; nada durante el arrastre y uno al soltar; uno con la acción "bajar" de TalkBack.
- **Gestos:** un dedo vertical mueve la página y no el mapa; un dedo de costado no mueve el mapa y muestra el aviso, que se va solo; el pellizco acerca; + / − y las cuatro flechas mueven (de 48 × 48).
- **Movimiento reducido:** el doble toque sin animación y la hoja de fuentes sin deslizarse; sin `drag`, `fling` ni `rotate`.
- **Pautas** `androidTapTargetGuideline`, `labeledTapTargetGuideline` y `textContrastGuideline`: 320 dp × letra 100, 130 y 200 % × claro y oscuro × 4 estados.
- **Contraste:** pista del deslizador, textos sobre los 5 tintes, grilla, pastillas, sello, panel invertido y bordes de la leyenda.

## 7. Qué probar a mano en el Redmi con TalkBack

Prender TalkBack y "Quitar animaciones" (Opciones de accesibilidad). Probar con letra normal y con la más grande, en claro y oscuro.

1. **Recorrido lineal** (deslizar a la derecha) desde la barra hasta "Cómo se usa": que el orden sea el de §4 y que ningún nodo se lea dos veces ni quede mudo. Que el sello "Mapa en prueba" se lea **antes** del mapa y "Aproximado. No reemplaza la alerta oficial." **después**.
2. **Pronunciación:** que "4,20 metros" se oiga "cuatro coma veinte metros", "10 centímetros", "8/10" (anotar si dice "ocho barra diez") y "Simulación".
3. **Deslizador:** que diga "Altura del río para el mapa", el valor y "deslizador". Subir y bajar con el volumen o deslizando arriba y abajo: que se oiga **una vez** el valor y después **un** anuncio con "El mapa ahora muestra el agua…", sin que se pisen ni se repitan.
4. **Grilla:** que el botón elegido diga "seleccionado" (o "marcado") y que al elegir otro el anterior deje de decirlo.
5. **"Volver a hoy" (M6):** tocarlo con doble toque y anotar **dónde queda el foco** y qué se oye.
6. **Interruptor del borde medido:** "activado" / "desactivado", y que la descripción del mapa pase a nombrar la línea de trazos.
7. **Desplazamiento con dos dedos de TalkBack** con los dedos **sobre el mapa**: tiene que bajar la página. Sin TalkBack, con un dedo sobre el mapa: baja la página. Con dos dedos: se mueve el mapa. De costado con un dedo: aparece el aviso de dos dedos.
8. **Flechas y + / −** con doble toque de TalkBack: que el mapa se mueva o se acerque y que el foco quede en el botón.
9. **Hojas "Ver fuentes" y "Cómo se usa":** que el foco entre a la hoja, que "Cerrar" se alcance y que al cerrar vuelva al botón que la abrió. Con "Quitar animaciones", que aparezca sin deslizarse.
10. **Anuncios en Android 16** (si aplica, m5): si no se oyen, avisar para pasar a una región viva propia.
11. **Al sol y de noche:** que la pista del deslizador se vea entera y que el aviso de dos dedos se lea.
12. **Con 2 o 3 vecinos mayores:** si entienden que el mapa se mueve con dos dedos o con las flechas, o si buscan moverlo con uno (C1). Si la mayoría se frustra, evaluar un botón "Mover el mapa con un dedo" que lo habilite mientras está prendido.
