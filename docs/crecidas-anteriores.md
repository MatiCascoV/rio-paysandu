# Pestaña "Crecidas": crecidas anteriores medidas por Dinagua

Rama `crecidas-anteriores`, sobre `main` (0ac471d). Reemplaza la idea del mapa con modelo de agua (rama `mapa-inundacion`), que el dueño decidió **no publicar** el 27/10/2026 porque un error del modelo podría dañar la credibilidad de la app.

## Qué muestra

- Mapa de Paysandú que funciona sin conexión (flutter_map, sin mosaicos de internet). Muestra el río, los arroyos, las calles y los barrios de OpenStreetMap, y encima el **borde medido** de una crecida real como línea, sin relleno.
- Por defecto aparece la más reciente: **julio de 2025**. Debajo del mapa hay una lista para elegir cada una de las 5 crecidas. Cada opción muestra el nombre, "X,XX m según Dinagua" y la fecha:

  | Crecida | Altura según Dinagua | Fecha (Dinagua) |
  |---|---|---|
  | julio de 2025 | 6,58 m | 3/7/2025 |
  | enero de 2019 | 8,45 m | 23/1/2019 |
  | junio de 2017 | 8,35 m | 12/6/2017 |
  | diciembre de 2015 | 9,12 m | 10/12/2015 |
  | noviembre de 2009 | 8,93 m | 10/11/2009 |

- **Ver todas**: las 5 juntas. Cada crecida tiene su color **y** su tipo de trazo (continuo, trazos, puntos, raya y punto, trazo largo), y una leyenda. Así no se distinguen solo por el color. Con el mapa entero las líneas se pisan en buena parte de la costa, pero al acercar (zoom 15) se separan bien (captura 07). Por eso la opción quedó, y la leyenda y el resumen de TalkBack las nombran a todas.
- El **aviso aprobado** está siempre a la vista, pegado debajo del mapa. No hay que tocar nada para verlo:
  > Muestra hasta dónde llegó el agua en crecidas anteriores, según Dinagua. La ciudad cambió desde entonces, así que una crecida igual no llega necesariamente al mismo lugar. No es un pronóstico ni reemplaza las indicaciones del Cecoed.

  Debajo va "Fuente: Dirección Nacional de Aguas (Dinagua), Ministerio de Ambiente. Calles y río: © colaboradores de OpenStreetMap". Sobre el mapa, la atribución "© OpenStreetMap · Dinagua". Al pie hay una sección "Fuentes", solo con texto y sin enlaces, como en el resto de la app.
- En la leyenda: "La línea cubre solo la zona que relevó Dinagua, sobre la costa. Donde no hay línea no quiere decir que el agua no haya llegado."

### Accesibilidad (como en docs/mapa/10 de la rama del mapa)

- El mapa **no atrapa el desplazamiento**. Con un dedo se mueve la página. El mapa se mueve con dos dedos, con las flechas de 48 dp que están debajo ("Mover el mapa") o con los botones + / − / "Ver toda la zona". Si alguien arrastra de costado con un dedo, aparece 3 segundos "Para mover el mapa usá dos dedos o las flechas de abajo".
- Para TalkBack, el dibujo se reemplaza por un resumen. Ejemplo: "Crecida de enero de 2019, 8,45 metros según Dinagua, del 23 de enero de 2019: una línea marca hasta dónde llegó el agua en la costa de Paysandú. La línea cubre solo la zona que relevó Dinagua…". Las opciones se anuncian como botones de un grupo excluyente, con el estado "seleccionado". La lectura de arriba es una región en vivo.
- Contraste: las líneas de crecida dan al menos 4,5:1 contra el terreno, en claro y en oscuro, y llevan un ribete (blanco en claro, casi negro en oscuro) para leerse sobre calles y río. La elegida se marca con ícono de radio y borde, no solo con color.
- Letra grande: probado a 320 dp con letra al 200 % en claro y en oscuro, sin desbordes. La barra de pestañas tiene tope de 1,3 y las cinco etiquetas entran en 320 dp. Hay un test para eso.

## De dónde salen los datos

`app/assets/crecidas/` (unos 380 KB):

- `base.json`: copia byte a byte del fondo de la salida v11c del mapa (OSM, extracto de Geofabrik del 21/10/2026).
- `curvas/AAAA-MM.json`: bordes de las 5 crecidas, derivados de las curvas de Dinagua (WFS `dinagua:curvas_cri`, filtro `PA-PSD%`) de la misma salida.
- `indice.json`: límites, el fondo y las 5 crecidas (nombre, `altura_m`, fecha, fuente), con `bytes` y `sha256` de cada archivo. La app rechaza un archivo cuyo tamaño o huella no coincida.
- `LICENSE-DATOS.md`: cita a Dinagua (curvas, información pública, sin licencia publicada) y a OpenStreetMap (ODbL 1.0 para `base.json`). Ya **no** cita a la IDE, porque no queda nada calculado con el MDT.

Se regeneran con:

```powershell
python docs\crecidas\bordes_crecidas.py <carpeta mapa-salida-v11c\mapa> app\assets\crecidas
```

(necesita `shapely`). Del índice del mapa usa solo `limites`, `base` y `referencias`.

### El tramo que cruzaba el río

Dinagua entrega cada crecida como un **polígono cerrado**. Del lado del río, y en los extremos norte y sur, lo cierra con tramos rectos de 400 m a 2,9 km. Esos tramos cruzan el cauce del río Uruguay y, en el sur, también tierra. Son el límite del área relevada, no hasta dónde llegó el agua. Si se dibujaba el contorno entero, quedaba una raya en medio del río: por ejemplo, en 2019 y 2025, cerca de −58,100 / −32,312, a zoom 15.

El script no mueve ningún punto: solo deja de dibujar tramos.

1. Saca cada segmento de **más de 250 m** que tenga **al menos el 10 % dentro del agua** de `base.json` (el cauce).
2. Lo que queda se parte en líneas. Se descartan las que caen casi enteras (≥ 90 %) dentro del cauce y las de menos de 20 m. En la práctica se descartaron restos del cierre que estaban 100 % dentro del río: un pedazo de 371 m en 2015, 2017 y 2019, y otro de 63 m en 2025. Un anillito cerrado de 14 m que trae Dinagua en 2025 queda, porque no tiene ningún corte.
3. Los bordes en tierra quedan con los mismos puntos que da Dinagua. Los segmentos largos que están **enteros en tierra** se dejan, aunque sean rectos (por ejemplo, tramos de 300 a 370 m en el sur en 2009 y en el norte en 2019).

Resultado: 2025 queda en 2 líneas (36,3 km de borde, más el anillito), 2019 en 1 (27,1 km), 2017 en 1 (16,9 km), 2015 en 1 (19,8 km) y 2009 en 1 (17,4 km). Un test (`ningún borde cruza el cauce`) controla que no quede ningún tramo de 400 m o más. Las capturas `05-*-2019-costa-zoom15` y `06-*-2025-costa-zoom15` muestran esa zona sin la raya.

## Qué se dejó afuera a propósito, y por qué

- **Todo el modelo de agua**: `agua/*.json` (66 capas), `sin_validar.json`, `calibracion.json`, el deslizador de altura, la lectura de "hoy", el margen, las lomas aisladas, la zona baja, las zonas sin validar y la palabra "Simulación". Es lo que el dueño decidió no publicar.
- **Nada del nivel actual** en esta pestaña: no usa `actual.json`, no tiñe la barra con el color del nivel, no compara la crecida con el río de hoy y no muestra el botón "Ver qué hacer" según el nivel. Mezclar "hasta dónde llegó" con "cómo está hoy" invitaría a leer la línea como pronóstico, justo lo que el aviso dice que no es.
- **Relleno de agua dentro de la línea**: Dinagua midió un borde, no cuánta agua hubo adentro. Además, el polígono incluye el cauce y los cierres artificiales.
- **Tr10 / Tr100** (curvas de recurrencia de `curvas_tr`): no son crecidas que hayan pasado.
- **Nombres de calles "afectadas"**: una lista incompleta se leería como "ahí no llegó" (la misma decisión que en el 09 del mapa).
- **Enlace a Dinagua**: la fuente va como texto. La app solo abre enlaces de una lista permitida, y en la rama del mapa ya se había decidido "solo texto" para las fuentes.

## Qué se reutilizó de `mapa-inundacion`

De `estilo_mapa.dart` se tomaron la paleta del fondo, las calles, el cauce, los arroyos y los nombres sin pisarse. De `repositorio_mapa.dart`, la lectura desconfiada con tamaño y sha256, en otro hilo para el fondo. Se reutilizaron también los gestos sin atrapar el scroll, las flechas, los botones + / −, el aviso de dos dedos, el enum `Pestana` y la creación perezosa de la pestaña (se arma recién la primera vez que se visita).

No se trajo el rayado, la zona baja, la cartografía del agua, los textos del modelo ni `logica_mapa.dart`. Los modelos se simplificaron a `IndiceCrecidas`, `Crecida`, `BaseMapa` y `BordeCrecida` (líneas), en `app/lib/crecidas/`.

## Otros cambios

- `main.dart`: quinta pestaña "Crecidas" (ícono de historial), entre Gráfico y Qué hacer. Los saltos entre pestañas pasan por `enum Pestana` en vez de números.
- `tema.dart`: la barra de arriba toma explícitamente la familia de letra del tema. En el teléfono no cambia nada (es la misma Roboto), y en las capturas de prueba deja de verse con cuadraditos.
- Dependencias nuevas: `flutter_map`, `latlong2` y `crypto` (Dart puro).
- `.gitattributes`: `app/assets/crecidas/** -text`, para que git no cambie los fines de línea y no se rompan las huellas.
- APK release: **53.456.388 bytes** (51,0 MB), contra **51.909.603 bytes** (49,5 MB) de `main` sin la pestaña. Son **+1,55 MB**.

## Dudas abiertas

- **Escala de las alturas**: las alturas son las `cota_local` de Dinagua, tal cual. Sigue sin confirmarse que el cero de Dinagua sea el mismo que el de CARU que usa el resto de la app (docs/mapa/01 §7: +0,11 frente a +0,14). Por eso siempre dicen "según Dinagua" y la pestaña no las compara con el nivel de hoy.
- **Qué fecha es**: es el campo `fecha_evento` de Dinagua. No está claro si corresponde al pico de la crecida o al día del relevamiento. Se muestra como "la fecha" sin interpretarla.
- **Licencia de Dinagua**: es información pública sin licencia publicada. Se cita la fuente y el dueño decidió usarla así. La consulta al organismo sigue pendiente.
- **ODbL §4.6**: `base.json` es la base derivada y está en el repositorio. El script que la generó (`extraer_osm.py`) vive solo en la rama `mapa-inundacion`. Si esa rama se borra, conviene traer el script.
- **"Ver todas" con el mapa entero**: las líneas se pisan. Se entiende al acercar. Si al dueño no le convence, se saca con una línea (la opción `_Opcion(titulo: 'Ver todas', …)`).
