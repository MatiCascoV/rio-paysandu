# Pestaña "Crecidas": crecidas anteriores medidas por Dinagua

Rama `crecidas-anteriores`, sobre `main` (0ac471d). Reemplaza la idea del mapa con modelo de agua (rama `mapa-inundacion`), que el dueño decidió **no publicar** el 27/10/2026 porque un error del modelo podría dañar la credibilidad de la app.

## Qué muestra

- Mapa de Paysandú que funciona sin conexión (flutter_map, sin mosaicos de internet). Muestra el río, los arroyos, las calles y los barrios de OpenStreetMap, y encima el **borde medido** de una crecida real como línea, sin relleno.
- Por defecto aparece la más reciente: **julio de 2025**. Arriba va la lectura (nombre, "X,XX m según Dinagua · fecha"); debajo del mapa hay una lista para elegir cada una de las 5 crecidas:

  | Crecida | Altura según Dinagua | Fecha (Dinagua) | Trazo con "Ver todas" |
  |---|---|---|---|
  | julio de 2025 | 6,58 m | 3/7/2025 | línea continua |
  | enero de 2019 | 8,45 m | 23/1/2019 | trazos |
  | junio de 2017 | 8,35 m | 12/6/2017 | puntos |
  | diciembre de 2015 | 9,12 m | 10/12/2015 | raya y punto |
  | noviembre de 2009 | 8,93 m | 10/11/2009 | raya y dos puntos |

  Las fechas no llevan hora porque **Dinagua no la publica** (solo da el día, campo `fecha_evento`). Lo dice también la sección "Fuentes" (PROMPT_MAESTRO §9). La fecha aparece en la lectura, en cada opción, en la leyenda, en pantalla completa y en el resumen para TalkBack.
- **Ver todas**: las 5 juntas, cada una con su color **y** su tipo de trazo, nombrado en la leyenda, en las opciones ("En el mapa: trazos.") y en el resumen para TalkBack. Al elegirla, si el mapa está lejos (zoom menor a 14), se acerca solo a la costa céntrica (zoom 14,5), donde las líneas se separan; si ya estaba cerca, se queda donde está. Si se aleja, aparece "Acercá para distinguir las líneas." Cuenta solo las crecidas cuyo borde se pudo leer y avisa cuáles faltan.
- Elegir una crecida **no mueve el mapa**: así se comparan varias en el mismo lugar.
- Orden de la pantalla, de arriba abajo: título, lectura, **aviso aprobado** (sin cambios) con la línea aprobada sobre la escala debajo, el mapa, "Pantalla completa" y las flechas, y la fuente:
  > Muestra hasta dónde llegó el agua en crecidas anteriores, según Dinagua. La ciudad cambió desde entonces, así que una crecida igual no llega necesariamente al mismo lugar. No es un pronóstico ni reemplaza las indicaciones del Cecoed.
  >
  > Las alturas de Dinagua pueden no coincidir exactamente con la escala de CARU.

  Con la app entera (barra de arriba, barra de pestañas y barras del sistema de 24 y 48 dp), Roboto real y 393 × 873 dp, el final de esas dos líneas queda en 456 dp con letra al 100 % y en 662 dp al 130 %; la barra de pestañas empieza en 753 dp. Con letra al **200 % no entra** (termina en 1438 dp): hay que desplazar. Lo mide `test/crecidas_aviso_test.dart`.
- Debajo del mapa va "Fuente: Dirección Nacional de Aguas (Dinagua), Ministerio de Ambiente. Calles y río: © colaboradores de OpenStreetMap". Sobre el mapa, la atribución "© OpenStreetMap · Dinagua". Al pie, "Fuentes", solo texto, con el mismo aviso de deslinde que `LICENSE-DATOS.md` (una prueba controla que sean iguales).
- En la leyenda: "La línea cubre solo la zona que relevó Dinagua, sobre la costa. Donde no hay línea no quiere decir que el agua no haya llegado."

### El mapa con los dedos y en pantalla completa (decisiones del dueño, 27/10/2026)

- **Un dedo mueve el mapa**; el pellizco y el doble toque acercan. Sin rotación (el norte siempre arriba). Como el mapa ocupa el 40 % de la pantalla (entre 260 y 360 dp, siempre menos de la mitad), queda lugar arriba y abajo para desplazar la página con el dedo. Siguen + / −, "Ver toda la zona" y las 4 flechas de 48 dp, para quien no puede arrastrar (WCAG 2.5.7). Ya no existe el cartel de "dos dedos".
- **Pantalla completa** (botón de 48 dp, "Pantalla completa"): el mapa ocupa todo el teléfono con la misma crecida o "Ver todas", gestos libres, + / − / "Ver toda la zona", el nombre de la crecida con altura y fecha, "No es un pronóstico." y la atribución. Se cierra con "Cerrar" o con Atrás, y la pestaña queda con el mismo encuadre que se dejó.

### Accesibilidad

- Para TalkBack, el dibujo se reemplaza por un resumen. Ejemplo: "Crecida de enero de 2019, 8,45 metros según Dinagua, del 23 de enero de 2019: una línea marca hasta dónde llegó el agua en la costa de Paysandú. La línea cubre solo la zona que relevó Dinagua… Este resumen no dice qué calles o barrios alcanzó el agua. Las alturas de Dinagua pueden no coincidir exactamente con la escala de CARU."
- Al elegir una crecida se anuncia "Mapa: crecida de enero de 2019, 8,45 metros según Dinagua, del 23 de enero de 2019." La lectura de arriba ya no es región en vivo (no se repite ni se anuncia al abrir).
- Las opciones son botones de radio de un grupo excluyente (marcado / no marcado). Todo lo que tiene "m" o "·" se lee como "metros" y con coma. La atribución sobre el mapa no se lee (está en la fuente).
- La leyenda no depende del color: muestras de 60 dp que repiten el trazo, y el nombre del trazo en el texto. 2009 pasó de "trazo largo" (se confundía con "trazos") a "raya y dos puntos".
- Contraste: las líneas de crecida dan al menos 4,5:1 contra el terreno, en claro y en oscuro, y llevan ribete. Los botones redondos del mapa tienen borde de 1 dp (`bordeControl`).
- Letra grande: 320 dp con letra al 200 %, en claro y oscuro, sin desbordes, también en pantalla completa. La barra de pestañas tiene tope de 1,3 y, además, baja el agrandado lo justo para que ninguna etiqueta se parta en dos renglones: con Roboto real al 130 %, "Qué hacer" se partía y quedaba cortada en 393 dp (se vio en las capturas). Hay una prueba con Roboto a 360 y 393 dp.

### Rendimiento

El mapa, las capas del fondo (río, arroyos y ~1.200 calles) y la capa de bordes se arman una vez por crecida elegida y paleta, y se guardan. Un redibujo de la página (por ejemplo, el reloj de 5 minutos de `main.dart`) reutiliza los mismos widgets y no vuelve a proyectar nada (lo controla una prueba).

## De dónde salen los datos

`app/assets/crecidas/` (unos 380 KB):

- `base.json`: copia byte a byte del fondo de la salida v11c del mapa (OSM, extracto de Geofabrik del 21/10/2026).
- `curvas/AAAA-MM.json`: bordes de las 5 crecidas, derivados de las curvas de Dinagua (WFS `dinagua:curvas_cri`, filtro `PA-PSD%`) de la misma salida.
- `indice.json`: límites, el fondo y las 5 crecidas (nombre, `altura_m`, fecha, fuente), con `bytes` y `sha256` de cada archivo. La app rechaza un archivo cuyo tamaño o huella no coincida, una fecha imposible (por ejemplo 2019-02-30) y una fuente que no sea "Dinagua". El campo `fuentes` del índice es para quien lea el archivo; la app no lo usa.
- `LICENSE-DATOS.md`: cita a Dinagua (curvas, información pública, sin licencia publicada) y a OpenStreetMap (ODbL 1.0 para `base.json`). Ya **no** cita a la IDE, porque no queda nada calculado con el MDT.

El fondo `base.json` se generó con `docs/crecidas/extraer_osm.py` (traído sin cambios de `mapa-inundacion`, ODbL §4.6). Los bordes y el índice se regeneran con:

```powershell
python docs\crecidas\bordes_crecidas.py <carpeta mapa-salida-v11c\mapa> app\assets\crecidas
```

(necesita `shapely`). Del índice del mapa usa solo `limites`, `base` y `referencias`.

### El tramo que cruzaba el río

Dinagua entrega cada crecida como un **polígono cerrado**. Del lado del río, y en los extremos norte y sur, lo cierra con tramos rectos de 270 m a 2,9 km. Esos tramos cruzan el cauce del río Uruguay y, en el sur, también tierra. Son el límite del área relevada, no hasta dónde llegó el agua.

El script no mueve ningún punto: solo deja de dibujar tramos.

1. Saca cada segmento de **más de 250 m** que tenga **al menos el 10 % dentro del río Uruguay** (el polígono de agua de mayor área de `base.json`; los arroyos y lagunas no cuentan).
2. Cada corte tiene que ser de un tipo conocido, o el script **se frena con error**: "en el río" (90 % o más adentro), "recta a latitud constante" (el cierre norte o sur, menos de 0,0005° de diferencia de latitud) o "entra o sale del río" (un extremo dentro del río). Imprime cada corte y cada línea descartada con largo, % en el río y coordenadas. En los datos actuales todos los cortes son "en el río", salvo los cierres norte y sur de 2009, 2015, 2017 y 2019 (rectas a latitud constante) y dos de 2025 que unen el cierre con la costa (563 m al sur, 37 % en el río, y 672 m al norte, 69 %).
3. Lo que queda se parte en líneas. Se descartan las que caen casi enteras (≥ 90 %) dentro del río y las de menos de 20 m: un resto de 371 m en 2015, 2017 y 2019 y otro de 63 m en 2025, todos 100 % en el río. Un anillito cerrado de 14 m que trae Dinagua en 2025 queda, porque no tiene ningún corte.
4. Los bordes en tierra quedan con los mismos puntos que da Dinagua, aunque tengan tramos largos rectos (300 a 370 m en el sur en 2009 y en el norte en 2019).

Con el corte solo contra el río, la salida es **idéntica byte a byte** a la anterior (antes se cortaba contra toda el agua, pero ningún corte tocaba otra cosa que el río).

Resultado: 2025 queda en 1 línea de 36,3 km (2559 puntos) más el anillito de 14 m (4 puntos); 2019 en 1 (27,1 km, 1157 puntos), 2017 en 1 (16,9 km, 583), 2015 en 1 (19,8 km, 452) y 2009 en 1 (17,4 km, 266). Pruebas:

- `ningún borde cruza el río` (Dart): con el río de `base.json`, ningún tramo de más de 250 m tiene 10 % o más dentro del río.
- `control de los bordes` (Dart): puntos por línea y km de cada crecida, con 0,2 km de tolerancia.
- `docs/crecidas/test_bordes_crecidas.py` (Python, `python -m pytest docs/crecidas`): anillos inventados; saca el cierre, deja tramos largos en tierra, descarta restos en el río y se frena ante un corte raro.

## Qué se dejó afuera a propósito, y por qué

- **Todo el modelo de agua**: `agua/*.json` (66 capas), `sin_validar.json`, `calibracion.json`, el deslizador de altura, la lectura de "hoy", el margen, las lomas aisladas, la zona baja, las zonas sin validar y la palabra "Simulación". Es lo que el dueño decidió no publicar.
- **Nada del nivel actual** en esta pestaña: no usa `actual.json`, no tiñe la barra con el color del nivel, no compara la crecida con el río de hoy y no muestra el botón "Ver qué hacer" según el nivel. Mezclar "hasta dónde llegó" con "cómo está hoy" invitaría a leer la línea como pronóstico, justo lo que el aviso dice que no es.
- **Relleno de agua dentro de la línea**: Dinagua midió un borde, no cuánta agua hubo adentro. Además, el polígono incluye el cauce y los cierres artificiales.
- **Tr10 / Tr100** (curvas de recurrencia de `curvas_tr`): no son crecidas que hayan pasado.
- **Nombres de calles "afectadas"**: una lista incompleta se leería como "ahí no llegó" (la misma decisión que en el 09 del mapa).
- **Enlace a Dinagua**: la fuente va como texto. La app solo abre enlaces de una lista permitida, y en la rama del mapa ya se había decidido "solo texto" para las fuentes.

## Qué se reutilizó de `mapa-inundacion`

De `estilo_mapa.dart` se tomaron la paleta del fondo, las calles, el cauce, los arroyos y los nombres sin pisarse. De `repositorio_mapa.dart`, la lectura desconfiada con tamaño y sha256, en otro hilo para el fondo. Se reutilizaron también las flechas, los botones + / −, el enum `Pestana` y la creación perezosa de la pestaña (se arma recién la primera vez que se visita).

No se trajo el rayado, la zona baja, la cartografía del agua, los textos del modelo ni `logica_mapa.dart`. Los modelos se simplificaron a `IndiceCrecidas`, `Crecida`, `BaseMapa` y `BordeCrecida` (líneas), en `app/lib/crecidas/`.

## Otros cambios

- `main.dart`: quinta pestaña "Crecidas" (ícono de historial), entre Gráfico y Qué hacer. Los saltos entre pestañas pasan por `enum Pestana` en vez de números.
- `tema.dart`: la barra de arriba toma explícitamente la familia de letra del tema. En el teléfono no cambia nada (es la misma Roboto), y en las capturas de prueba deja de verse con cuadraditos.
- Dependencias nuevas: `flutter_map`, `latlong2` y `crypto` (Dart puro).
- `.gitattributes`: `app/assets/crecidas/** -text`, para que git no cambie los fines de línea y no se rompan las huellas.
- `main.dart`: la barra de pestañas baja el agrandado de letra lo justo para que ninguna etiqueta se parta (`topeLetraQueEntra`).
- `ajustes.dart`: "Las alturas del río son de CARU; las crecidas anteriores, de Dinagua, y el mapa, de OpenStreetMap."
- APK release: **53.521.992 bytes** (51,0 MB), contra **51.909.603 bytes** (49,5 MB) de `main` sin la pestaña. Son **+1,61 MB** (la versión anterior de la rama pesaba 53.456.388).

## Dudas abiertas

- **Escala de las alturas**: las alturas son las `cota_local` de Dinagua, tal cual. Sigue sin confirmarse que el cero de Dinagua sea el mismo que el de CARU (docs/mapa/01 §7: +0,11 frente a +0,14). Por eso dicen "según Dinagua", la pestaña no las compara con el nivel de hoy y lleva la línea aprobada "Las alturas de Dinagua pueden no coincidir exactamente con la escala de CARU."
- **Qué fecha es**: es el campo `fecha_evento` de Dinagua, sin hora. No está claro si es el pico de la crecida o el día del relevamiento. Se muestra como "la fecha" sin interpretarla.
- **Licencia de Dinagua**: es información pública sin licencia publicada. Se cita la fuente y el dueño decidió usarla así. La consulta al organismo sigue pendiente.
- **`extraer_osm.py`**: es la última versión de `mapa-inundacion` (commit 08adabd, 19/10/2026, anterior a la extracción del 21/10). No se volvió a correr (necesita el `.osm.pbf` y osmium), así que no está comprobado byte a byte que reproduzca `base.json`.
- **Letra al 200 %**: el aviso no entra sin desplazar en 393 × 873 (sí al 100 % y al 130 %).
