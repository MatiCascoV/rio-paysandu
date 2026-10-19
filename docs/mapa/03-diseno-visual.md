# Pestaña "Mapa": diseño visual, UX y cartografía

Rama `mapa-inundacion`. Maqueta navegable: `docs/mapa/maqueta.html` (abrir en el navegador; trae modo claro/oscuro y los estados).

Fuentes de estilo respetadas: `app/lib/tema.dart` (paleta, letra de 18, botones de 56), `textos.dart` (`EstiloNivel`, `ColoresNivel`: tinte por nivel, ícono + palabra), `pantallas/comunes.dart` (`Recuadro` ámbar, deslinde), `olas.dart` (movimiento respetuoso), `PROMPT_MAESTRO.md` §2 y §6 (no reemplaza la alerta oficial, nada inventado, funciona sin conexión, sin datos personales).

---

## 1. Qué tiene que responder la pantalla, en orden

1. **¿Cómo está el río hoy?** (una línea, igual que Inicio: altura, nivel con ícono y palabra, hora y fuente).
2. **¿Qué altura estoy mirando?** (número grande + nivel de esa altura + comparación con hoy).
3. **¿Hasta dónde llega el agua con esa altura?** (el mapa + una frase con las zonas en texto).
4. **¿Cómo pruebo otra altura?** (deslizador con − / + y botones de alturas con nombre).
5. **¿Y mi casa?** (tarjeta opcional).
6. **¿Qué tan confiable es?** (leyenda, aviso de incertidumbre, fuentes).

El mapa queda arriba del pliegue en un teléfono de 360 × 780 con letra normal (barra 56 + hoy 70 + lectura 80 + mapa 300). Con letra grande se corre hacia abajo y está bien: la lectura en texto va primero.

## 2. Estructura (de arriba hacia abajo)

| Bloque | Contenido | Notas |
|---|---|---|
| Barra superior | "Mapa del agua" + botón (?) "Cómo leer el mapa" | Fondo = tinte del nivel de **hoy**, como Inicio. |
| Franja "hoy" | `Río hoy: 3,62 m  ✓ NORMAL` / `Actualizado: hoy 15:00 · Fuente: CARU` | Mismos textos y colores (`familia`) que Inicio. Degradé del tinte al fondo. |
| Recuadro ámbar (solo si algo anda mal) | Sin conexión / dato viejo / sin dato / umbrales sin validar | Reusar `Recuadro`. Nunca más de uno: gana el más grave. |
| Lectura | `Viendo el agua con el río en` / **`6,89 m`** (38, peso 800) + pastilla de nivel / `3,27 m más que hoy.` | La pastilla usa el relleno pleno del nivel con su texto de 5:1 (`EstiloNivel`). |
| Aviso de simulación | Franja oscura: `No es el río de hoy: es una prueba con 6,89 m.` + `Volver a hoy` | Solo cuando la altura elegida ≠ hoy. Va **fuera** del mapa, para no tapar la casa ni la costa. |
| Mapa | Esquema/porción de costa, sello `ESQUEMA · NO ES EXACTO` (solo en la maqueta), botones + / − / centrar en mi casa | Alto fijo 300 dp; esquinas 20 como las superficies. |
| Zonas en texto | `Zonas con agua: Costanera, zona del Puerto, Arroyo Sacra (aprox.).` | Es la alternativa textual del mapa: la ve todo el mundo y la lee el lector. |
| Control de altura | `[−]  ━━━●━━━━  [+]` y marcas `Alerta 4,39` · `Evac. 6,89` | Ver §5. |
| "Elegí una altura" | Grilla de 2 columnas de botones: Hoy · Pronóstico CARU · Nivel de alerta · Nivel de evacuación · Crecida 2009 · 2015 · 2017 · 2019 · 2025 | Grilla, no carrusel horizontal: los mayores no descubren el desplazamiento lateral. |
| Tarjeta "Mi casa" | Ver §7 | Opcional, siempre al final del bloque útil. |
| Leyenda | 5 filas con muestra de 36 × 22 | Ver §4. |
| Aviso + fuentes | Texto fijo (§8) + enlace `Ver fuentes` | Siempre visible, no escondido en (?). |

## 3. Decisión clave: el color del agua **no** es el color del nivel

El nivel (verde / amarillo / naranja / rojo) se dice en la franja, la pastilla y las marcas del deslizador, **siempre con ícono y palabra**. El agua del mapa es **siempre azul**, por tres razones:

- **Daltonismo.** Rojo/naranja/verde sobre un plano beige con manzanas es justo la combinación que confunden deuteranopía y protanopía (≈ 8 % de los varones). El azul contra beige/gris se distingue en los tres tipos de daltonismo y en escala de grises (diferencia de luminosidad, no solo de tono).
- **Convención cartográfica.** El agua es azul en todos los mapas que el vecino conoce (Google Maps, mapas del Cecoed, carteles). Agua roja se lee como "zona de peligro definida por alguien", y la app no define zonas de riesgo oficiales.
- **Lectura del nivel sin ambigüedad.** Si el agua cambiara de color al pasar 6,89, el vecino podría creer que el color lo pone una autoridad. El nivel queda en el texto, que es donde ya lo lee en Inicio.

### Capas del mapa (de abajo hacia arriba)

| Capa | Claro | Oscuro | Codificación sin color |
|---|---|---|---|
| Calles / terreno | `#FBFAF7` | `#1B2A37` | — |
| Manzanas | `#E3DCCD` | `#2B3E51` | forma (cuadrados) |
| Río y arroyo en su cauce | `#2F6FAD` sólido | `#0F4C85` sólido | **relleno liso** |
| Agua a la altura elegida | `#3D8BD9` al 55 % + **rayado a 45°** `#0B3C5D` | `#6CB4FF` al 45 % + rayado `#D6ECFF` | **rayado** (se distingue del cauce aunque no se vea el color) |
| Borde del agua elegida | línea discontinua 1,5 | ídem | trazo discontinuo |
| Margen de duda (+50 cm) | **puntos** `#0B3C5D` | puntos `#BFE0FF` | punteado |
| Borde del agua **hoy** | línea continua 3 `#0B2A3F` | `#FFFFFF` | línea gruesa continua (solo cuando se mira otra altura) |
| Mi casa | círculo blanco con borde 3 + casita + rótulo "Mi casa" | invertido | forma + palabra |

Rótulos del mapa: 13 px, peso 600, con halo del color del terreno (`paint-order: stroke`) para que se lean sobre el agua. En la app: `TextPainter` con `foreground` de trazo.

### Por qué el margen de duda va solo **hacia afuera**

El modelo (cota del terreno vs. altura del río) tiene error vertical de unos ±0,5 m entre el MDE, el cero de la escala y los efectos locales. Se dibuja la franja punteada **entre h y h + 0,5 m** (más allá del borde), no hacia adentro: para seguridad, el error que importa es "el agua llega más lejos de lo que dice el mapa". Mostrar también el margen hacia adentro achicaría visualmente la mancha y daría una falsa tranquilidad.

## 4. Leyenda (textos exactos)

- ▬ (azul liso) **Río y arroyo, en su cauce**
- ▨ (rayado) **Hasta dónde llegaría el agua**
- ⠿ (puntos) **Puede llegar un poco más (hasta 50 cm)**
- ━ (línea gruesa) **Borde del agua hoy**
- ◯ **Mi casa (solo queda en este teléfono)**

La leyenda está siempre abierta (no plegable): son 5 líneas y es la clave para entender el rayado.

## 5. Deslizador y botones de altura

- **Rango:** 2,00 a 11,00 m (cubre bajante hasta por encima de la crecida de 1959 si se agrega). **Paso: 10 cm.** El modelo se precalcula por 10 cm; no tiene sentido ofrecer más precisión que la del dato.
- **Tamaño táctil:** pulgar visual de 32 dp con área táctil de 56 × 56; pista de 10 dp. Botones `−` y `+` de 56 × 56 a cada lado (el deslizador fino es difícil con temblor de manos o dedos gruesos; los botones dan control exacto).
- **Marcas** debajo de la pista, en texto: `Alerta 4,39` y `Evac. 6,89` (de `data/umbrales.json`; si `validado: false`, el recuadro ámbar lo avisa como en Inicio). Sin colores en las marcas para no competir con la pastilla.
- **Pista rellena** hasta el pulgar con `primario`: muestra "cuánto subió" sin depender del color del nivel.
- **Al soltar** (no mientras arrastra): vibración corta (`HapticFeedback.selectionClick`) al cruzar alerta o evacuación, y anuncio para lector (§9).
- **Botones de altura** (grilla 2 columnas, 56 dp de alto, texto en dos líneas `Crecida 2019` / `8,40 m`): al tocarlo, el deslizador salta a esa altura; el botón queda marcado (relleno `primario`, `aria-pressed`). Si la altura coincide con un botón al arrastrar, también se marca.
- **Crecidas históricas:** valor del **pico en Paysandú** con fecha, tomado de Dinagua (cargar en un JSON del repo con fuente y fecha de consulta). En la maqueta son valores de ejemplo y lo dice. Si un año no tiene pico confirmado, el botón no aparece (nunca un valor estimado).
- **Pronóstico CARU:** solo si hay informe vigente (mismo criterio que la tarjeta de Inicio). Texto: `Pronóstico CARU` / `5,60 m`.
- **Animación del agua:** al cambiar de altura con botón, la mancha crece en 400 ms (`easeOut`); arrastrando, sigue al dedo sin animación. Con "menos animaciones" del sistema, todo es instantáneo (mismo criterio que `OlasNivel`). Las olas de Inicio **no** se repiten acá: el mapa ya es denso.
- **Al volver a la pestaña** el deslizador vuelve a **hoy** (o al pronóstico si hay alerta, ver §6). No se recuerda la altura de prueba: evita que alguien abra la app días después y vea una simulación creyendo que es el río.

## 6. Estados

| Estado | Qué cambia | Textos |
|---|---|---|
| **Normal** | Tinte verde. Se abre en hoy. Sin aviso de simulación. | Zonas: `Sin barrios con agua. Solo la orilla y la boca del arroyo (aprox.).` |
| **Crecida (alerta o evacuación)** | Tinte del nivel. Se abre en **el pronóstico de CARU si es mayor que hoy**, si no en hoy. Aparece el aviso de simulación con `Volver a hoy`. Debajo de la tarjeta "Mi casa", botón de ancho completo `Ver qué hacer` en el color del nivel (igual que Inicio). | `No es el río de hoy: es una prueba con 5,60 m.` |
| **Sin conexión** | El mapa funciona igual (va dentro de la app). "Hoy" pasa a "Último dato". | Recuadro: `Sin conexión. El mapa funciona igual, pero "Hoy" es el último dato guardado (hoy 09:00).` |
| **Dato viejo** (más de `horasSinDato`) | Tinte gris "Sin dato" como Inicio. Botón `Último dato` en vez de `Hoy`. Se habla en pasado. | Recuadro: `El último dato es de hace 21 horas. El río pudo cambiar. Mirá la fuente o los canales oficiales.` |
| **Sin dato** | Sin línea "borde de hoy", sin botón Hoy. Se abre en el nivel de alerta. | Recuadro: `No hay un dato confiable de hoy. Igual podés elegir una altura para ver hasta dónde llegaría el agua.` |
| **Cargando** | Solo la primera vez que se arma el mapa (decodificar capas). Esqueleto del tamaño del mapa con barra indeterminada; el resto de la pantalla ya se puede usar. | `Preparando el mapa…` |
| **Altura fuera del modelo** | Si se pide más que la cota máxima calculada. | `El mapa llega hasta 11,00 m. Más arriba no hay cálculo.` |
| **Error al leer el mapa** | Recuadro en lugar del mapa; el resto sigue. | `No se pudo mostrar el mapa en este teléfono. La altura del río sigue en Inicio.` |
| **Primera vez** | Tarjeta "Cómo se usa" encima de la lectura, con `Entendido`. No se vuelve a mostrar (se guarda en el teléfono); queda accesible en (?). | Ver §10. |

## 7. "Mi casa"

**Marcar:** botón `Marcar mi casa` → el mapa entra en modo marcar: `Tocá el mapa donde está tu casa.` + `Cancelar`. En la app real conviene además una cruz fija en el centro y `Usar mi ubicación` (pide permiso solo en ese momento; si lo niega, sigue funcionando a mano). Tocar el río no marca nada.

**Privacidad:** el punto se guarda **solo en el teléfono** (`shared_preferences`), nunca se envía. Texto bajo el botón: `Queda guardada solo en este teléfono. No se envía a nadie.` Botones `Mover` y `Borrar`.

**Cálculo:** cota del terreno en ese punto (mismo cero que la escala de CARU), redondeada a 10 cm.

**Textos exactos** (h = altura elegida, c = cota de la casa):

- h ≥ c: **`Con 9,40 m, el mapa muestra agua en tu casa.`**
- c − 0,5 ≤ h < c: **`Con 8,20 m, el agua quedaría muy cerca de tu casa.`**
- h < c − 0,5: **`Con 5,60 m, el mapa no muestra agua en tu casa.`**
- Siempre: `Según el mapa, el agua llegaría a tu casa con el río en aprox. 8,60 m. Podría ser hasta 50 cm antes.`
- Si hoy < c: `Hoy el río está en 5,12 m: faltan unos 3,48 m.`
- Siempre al pie: `Es una estimación. Ante la duda, seguí las indicaciones del Cecoed.`

**Lo que nunca dice:** "estás a salvo", "tu casa no se inunda", "zona segura", ni ningún verde/tilde junto a la casa. El caso "no muestra agua" va en el mismo peso y color que los demás, sin ícono de aprobación. Tampoco se usa la casa para avisos push (fuera de alcance; requeriría otra discusión de privacidad).

## 8. Textos fijos

- **Aviso de incertidumbre** (siempre visible, debajo de la leyenda):
  > **Este mapa es aproximado.** Muestra hasta dónde podría llegar el río con esa altura, según el terreno. No tiene en cuenta la lluvia, los desagües ni las calles cortadas. No reemplaza la alerta oficial: seguí las indicaciones del Cecoed.
- **Fuente:** `Terreno y zonas inundables: Dinagua / IDE Uruguay. Altura del río y pronóstico: CARU.` + `Ver fuentes` (abre una hoja con los enlaces y la fecha de los datos del mapa: `Mapa armado con datos de [mes año]`).
- **(?) Cómo leer el mapa:** `El rayado celeste es hasta dónde llegaría el río con la altura que elegiste. Los puntitos muestran que puede llegar un poco más. La línea gruesa es hasta dónde llega hoy. Las alturas son las de la escala de CARU en el puerto de Paysandú.`
- Unidades siempre con coma y "m" (`formatoAltura`), diferencias con `formatoDiferencia` ("48 cm", "3,27 m").

## 9. Lector de pantalla (TalkBack)

- **Franja hoy**: un solo nodo, igual que `_CabeceraNivel`: "Río hoy, 3,62 metros. Nivel: Normal. Actualizado hoy a las 15."
- **Mapa**: `Semantics(image: true, label: …)` con la descripción generada: "Esquema del mapa. Río en 6,89 metros. Con esta altura el agua llegaría a: Costanera, zona del Puerto, Arroyo Sacra. Tu casa: el agua llegaría con aproximadamente 8,60 metros." El dibujo en sí va en `ExcludeSemantics`.
- **Deslizador**: `Slider` con `semanticFormatterCallback` → "6 coma 89 metros, nivel Evacuación". Subir/bajar con gestos de volumen = 10 cm.
- **Anuncios**: al soltar el deslizador o tocar un botón, `SemanticsService.announce` con la lectura + zonas (no en cada paso del arrastre, para no saturar).
- **Botones de altura**: rol botón con estado "seleccionado"; etiqueta "Crecida 2019, 8,40 metros".
- **Botones del mapa**: etiquetas "Acercar", "Alejar", "Centrar en mi casa" (no solo ícono).
- **Orden de foco**: hoy → recuadro → lectura → aviso de simulación → mapa → zonas → − / deslizador / + → botones de altura → mi casa → leyenda → aviso → fuentes.
- **Letra grande** (hasta 200 %): el número grande usa `FittedBox` como el nombre del nivel en Inicio; la grilla de botones pasa a 1 columna si el texto no entra; el mapa no se achica por debajo de 240 dp.

## 10. Flujos

### A. Primera vez
1. Toca la pestaña **Mapa** (5.ª pestaña; ícono de mapa plegado, rótulo "Mapa", entre Gráfico y Qué hacer).
2. Ve la tarjeta **Cómo se usa** (2 frases + "no reemplaza la alerta oficial") y el mapa en la altura de hoy debajo.
3. Toca `Entendido` → la tarjeta se va.
4. Mueve el deslizador o toca `Nivel de evacuación`: la mancha rayada crece; aparece `No es el río de hoy…` y la frase de zonas cambia.
5. Baja y ve **Mi casa** → `Marcar mi casa` → toca el mapa → la tarjeta dice con qué altura llegaría el agua.
6. `Volver a hoy`.

### B. Uso diario (río normal)
1. Abre Mapa → está en hoy, tinte verde, `Sin barrios con agua…`.
2. Si tiene casa marcada, lee `Hoy el río está en 3,62 m: faltan unos 4,98 m.` Eso es todo: 3 segundos.
3. Curiosidad: toca `Crecida 2019` para ver "cómo fue" → `Volver a hoy`.

### C. En crecida
1. Llega por la notificación o desde Inicio (en alerta, Inicio puede ofrecer el enlace `Ver en el mapa` debajo del pronóstico).
2. La pestaña abre **en el pronóstico de CARU** (si es mayor que hoy), con el aviso de simulación y la línea del borde de hoy: ve de un golpe dónde está el agua hoy y hasta dónde se espera.
3. Lee la tarjeta de su casa: `Con 5,60 m, el mapa no muestra agua en tu casa. … llegaría con aprox. 8,60 m.` o `…muestra agua en tu casa.`
4. Toca `Ver qué hacer` (color del nivel) → teléfonos del Cecoed/Sinae.
5. Si está sin conexión, el mapa sigue ahí con el último dato y su hora.

## 11. Recomendaciones cartográficas para la implementación

- **Mapa dentro de la app, no por internet.** Precalcular las manchas por cada 10 cm (o una capa de cotas en grilla y calcular el borde en el teléfono) desde el MDE de IDE Uruguay y las cartas de zonas inundables de Dinagua. Así funciona sin conexión y la "carga" es un instante.
- **Mismo cero.** La cota del terreno tiene que estar en el **mismo cero que la escala de CARU** que lee la app (`data/umbrales.json` dice `"cero": "Local"`). Si el MDE está en cero Oficial ROU, convertir con la diferencia publicada para la escala de Paysandú. Es el error más fácil de cometer y el más grave (un desfase de 1 m mueve el borde varias cuadras).
- **Plano base simple.** Solo río, costa, manzanas, 4–6 nombres (Costanera, Puerto, Arroyo Sacra, barrios costeros que usen los vecinos, "Centro →"). Sin imagen satelital (pesa, se ve mal en oscuro y compite con el rayado). Norte arriba y escala gráfica.
- **Encuadre.** Porción de costa entre el Arroyo Sacra y el sur de la zona portuaria; zoom limitado a 1×–3× con botones + y − (no solo pellizco). Si hay casa marcada, el encuadre inicial la incluye.
- **Rótulos** con halo, nunca encima del rayado sin halo; los nombres de barrios en texto debajo del mapa (lista de zonas) para que no dependa de leer el plano.
- **Nada interpolado como oficial:** si la capa de Dinagua tiene manchas oficiales para ciertas cotas, se pueden mostrar esas; para cotas intermedias, el cálculo propio va con la misma advertencia y la franja de duda.

## 12. Pendientes / decisiones para vos

1. Confirmar los **picos históricos en Paysandú** (2009, 2015, 2017, 2019, 2025) con fecha y fuente Dinagua; la maqueta usa valores de ejemplo.
2. Confirmar **qué cero** usa el MDE frente al cero "Local" de CARU.
3. ¿`Usar mi ubicación` para marcar la casa (pide permiso de ubicación) o solo tocar el mapa? Recomiendo ofrecer ambos, con el toque como principal.
4. ¿La pestaña Mapa va siempre o solo para Paysandú? Para las ciudades de la fase 4 sin mapa, ocultarla.
5. Probar con 3–5 vecinos mayores el deslizador con − / + y la palabra "rayado" en la leyenda.
