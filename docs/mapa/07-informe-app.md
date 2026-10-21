# Pestaña Mapa: informe de la app (etapa 7)

Rama `mapa-inundacion` · 21/10/2026 · Mobile App Builder. Alcance: `app/` y este documento. No se tocó `lector/`, `data/` ni `.github/`. Sin commits.

## Resultado

| Control | Resultado |
|---|---|
| `flutter analyze` | **0 problemas** |
| `flutter test` (toda la suite) | **190 OK, 0 fallas** (mapa: 74, antes 51 OK + 4 fallas) |
| `flutter build apk --release` | **OK**, APK de 51,0 MB (igual que antes de los cambios; ver §6) |
| Recursos nombrados desde Dart en el APK release | presentes (mismo control que `app.yml`, ver §6) |

## 1. Arquitectura (cómo quedó)

```
app/lib/mapa/
  fuente_mapa.dart        FuenteMapa: de dónde salen los bytes (FuenteAssets = APK; FuenteMemoria = pruebas).
                          Mañana, GitHub Pages es otra FuenteMapa con el mismo formato.
  modelos_mapa.dart       IndiceMapa, CapaAgua, BaseMapa, ReferenciaMapa, CurvaMapa + validación desconfiada
                          (contrato 05). ceroDelMapa = 'Local'. Topes de bytes y de puntos.
  logica_mapa.dart        redondearArriba (5,63 → 5,70) y elegirAgua: enCauce / enRango / sobreMaximo + margen.
  repositorio_mapa.dart   Lee índice, fondo, capas y curvas; controla bytes y sha256; decodifica en otro
                          hilo (compute) lo que pasa de 96 KB; guarda en memoria las últimas 12 capas (LRU)
                          y las curvas ya leídas; una capa rota no se reintenta.
app/lib/pantallas/mapa.dart
  PantallaMapa            Recibe Datos (el mismo actual.json de Inicio y Gráfico), Config y el repositorio.
  hoyParaMapa()           Qué "hoy" se puede pintar: nivel vigente, dato viejo, sin conexión y mismo cero.
```

Flujo: `indice()` → si no valida, "El mapa todavía no está disponible" (con el motivo si es el cero). → `base()` → fondo (cauce, arroyos, calles por clase, rótulos sin pisarse). → altura inicial (hoy redondeada hacia arriba; sin dato confiable, el nivel de alerta; sin umbrales, la capa más baja) → `elegirAgua` → `capa(h)` y `capa(h + margen)`; si una capa no se puede leer se usa la siguiente **hacia arriba** y se dice cuál.

Orden de dibujo: cauce → margen (puntos) → agua (borde continuo) → calles → arroyos → contorno de crecida real (trazos, opcional) → rótulos.

## 2. Las 4 fallas: causa y arreglo

| Test | Causa | Arreglo |
|---|---|---|
| "abre en la altura de hoy… redondea hacia arriba…" (no encontraba "Alerta") | La franja de hoy ponía ícono y palabra en un mismo `Text.rich` con `WidgetSpan`. El texto plano queda "￼Alerta" (el ícono es un carácter de reemplazo), así que la palabra del nivel no era un texto por sí misma. Vino con el cambio de estilo de la franja de nivel. | **App:** ícono + palabra como `Row` (mínima) dentro del `Wrap`: con letra grande el par baja de renglón entero, y la palabra vuelve a ser un `Text`. Test sin cambios. |
| "el deslizador lee la altura en metros para TalkBack" (esperaba '4,20 metros', recibía '') | En Flutter 3.47 el `Slider` arma su nodo de accesibilidad en un objeto interno; el `Semantics` de afuera no forma nodo. `getSemantics(find.byType(Slider))` subía hasta el nodo de la fila (botones − / + y barra), que no tiene valor. Además ese nodo del deslizador medía 48 dp (solo el pulgar). | **App:** `MergeSemantics` alrededor del `Slider`: un solo nodo, del ancho de toda la barra (396 dp en la prueba), que dice "4,20 metros" y sube/baja de a 10 cm. **Test (cambio justificado):** lee `getSemanticsData().value` en vez de `.value`. `SemanticsNode.value` es solo lo propio del nodo; lo fusionado (que es lo que lee TalkBack) está en `getSemanticsData()`. Se agregaron chequeos: que sea un deslizador, el valor siguiente y el ancho > 200 dp. |
| "320 dp con letra al 200 %: nada se desborda" y su variante oscura (no encontraba el botón "Bajar 10 cm") | Dos causas. (a) La pantalla era un `ListView`: con letra al 200 % y el recuadro de aviso (más alto con el estilo nuevo de avisos), el control quedaba fuera de lo que el `ListView` arma y el botón no existía. Lo mismo desarmaba el mapa (y perdía zoom y posición) al bajar hasta las fuentes. (b) Al pasar de "sin dato" a un dato real, la pantalla no seguía la altura nueva: en el tercer caso (río a 9,00 m) mostraba "una prueba con 4,20 m (4,80 m menos que hoy)". | **App:** (a) `SingleChildScrollView` + `Column` (son unos 20 bloques; armar todo es barato y el mapa conserva su estado). (b) La pantalla distingue "altura elegida por la persona" de "altura de apertura": mientras la persona no eligió otra, un dato nuevo (o uno que faltaba) mueve el mapa a hoy; si eligió otra, no se la cambia. **Test (reforzado, no aflojado):** baja hasta el botón con `ensureVisible` antes de tocarlo (lo que haría la persona) y además recorre crecida, contorno y pie con letra al 200 %. |

Otro hallazgo de la revisión: la pantalla guardaba los polígonos armados de **cada** altura visitada en un mapa sin tope (y con ellos las capas), así que la memoria crecía al arrastrar el deslizador por todo el rango. Ahora solo quedan armados los de la capa y el margen que se ven; el resto lo guarda el repositorio con tope.

## 3. Lista para los datos reales (sin cambios de código)

| Caso del contrato | Qué hace la app | Prueba |
|---|---|---|
| Rango 4,00–10,50 (66 capas) | Valida orden, paso, nombres `agua/NNNN.json`, bytes y sha256 de las 66. El deslizador va de 3,90 (en su cauce) a 10,50 o a la altura de hoy si es mayor. | `mapa_logica_test`: "el índice del rango del contrato valida con 66 capas", "elección en el rango real…"; `mapa_test`: tres alturas con `fuenteRangoReal()` |
| `validado: false` | Recuadro ámbar arriba del mapa: **"Mapa aproximado, en prueba: todavía no se comprobó con suficientes crecidas reales. El agua puede llegar más lejos de lo que muestra."** Si los datos son los provisorios, gana el aviso "Datos de prueba… inventada". | "validado: false → aviso visible…" (también comprueba que va antes del mapa y que con `validado: true` no aparece) |
| sha256 / bytes | Cada archivo se lee solo si pesa lo que dice el índice y su huella coincide; si no, se descarta (capa: se usa la de arriba y se dice; fondo: mapa no disponible; curva: "No se pudo leer el borde medido"). Topes: índice 256 KB, fondo 4 MB, capa y curva 2 MB, total 48 MB, 400 000 puntos por capa. | tests de huella rota de capa, fondo y curva; también en segundo plano |
| `cero` del índice distinto de "Local" | No dibuja agua: "El mapa usa otra referencia de altura ("Oficial") que la escala de CARU, así que no se dibuja el agua." | "índice en otra escala…" |
| `cero` de actual.json distinto del mapa | No pinta hoy (como antes) y **tampoco usa los umbrales** (vienen del mismo lector, en la misma escala que actual.json): abre en la capa más baja. | "actual.json en otra escala…" |
| h < min | "Con 3,90 m el agua queda en su cauce: los puntos muestran hasta dónde podría llegar con un poco más." (el margen se sigue pintando si llega al mapa) | "rango del contrato… 3,85 m" |
| h > max | Capa de `max_m` + "El río supera lo que cubre el mapa (hasta 10,50 m). Se muestra el agua con ese máximo." | "rango del contrato… 10,80 m" |
| `curvas/` (crecidas reales de Dinagua) | Bloque "Alturas para comparar": botones de nivel de alerta, evacuación y cada crecida del índice (ordenadas por altura). Al tocar una crecida: va a su altura redondeada hacia arriba (y lo dice: "…: 9,12 m. El mapa lo redondea hacia arriba a 9,20 m.") y ofrece el interruptor **"Ver el borde medido en esa crecida"** (apagado por defecto). El contorno se dibuja en trazos, encima del agua del modelo, con su fila en la leyenda. Una referencia con archivo inválido (por ejemplo `bytes: 0`, como el ejemplo del contrato) queda como botón de altura sin contorno. | "crecida real: botón, redondeo dicho y contorno opcional", "curva con la huella rota…", tests de `CurvaMapa` |
| `pubspec.yaml` | Declara `assets/mapa/`, `assets/mapa/agua/` y **`assets/mapa/curvas/`** (Flutter no entra en subcarpetas y exige que la carpeta exista: va un `.gitkeep` vacío). Un test falla si aparece una carpeta nueva bajo `assets/mapa/` sin declarar. | "pubspec.yaml declara todas las carpetas de assets/mapa/" |

Seguridad (sin cambios de criterio): ante la duda, más agua (redondeo hacia arriba; capa faltante → la de arriba, nunca la de abajo; hueco roto → se ignora el hueco). Ningún texto dice "a salvo" ni "seguro" (hay un test que lo revisa en cauce, alerta y por encima del máximo). El pie sigue diciendo "Aproximado. No reemplaza la alerta oficial."

Los fixtures (`test/fixtures_mapa.dart`) ahora arman por defecto el set chico (4,00–4,30) **con** una crecida y su `curvas/2015-12.json` y `validado: false`, como van a llegar los datos reales; `desde`/`hasta` arman el rango del contrato y `fuenteRangoReal()` lo da hecho. Las capas crecen 0,0001° por cm, así que hasta 10,50 m quedan dentro de los límites y anidadas.

## 4. Costo: tiempo y memoria

Medido con un test temporal (borrado) sobre una capa sintética del tamaño del tope del pipeline (`tope_capa_bytes` = 600 KB): 590 KB, 167 polígonos, 27 000 puntos. PC de escritorio, Dart JIT; en un teléfono de gama baja contar 5 a 10 veces más.

| Paso | Tiempo |
|---|---|
| sha256 de la capa | 8–12 ms |
| `jsonDecode` | 3–7 ms |
| armar `CapaAgua` (LatLng) | < 1 ms |
| fondo real (`base.json`, 269 KB) | 5–6 ms |
| de punta a punta con `compute` (leer + hilo + huella + JSON + armar + volver) | 22–26 ms |
| abrir la pantalla con la capa grande vs. con las chicas (widget test) | ≈ +90 ms |
| 10 arrastres del mapa con la capa grande | ≈ 6–7 ms por cuadro, igual que con las chicas |

- **Hilo de la interfaz:** antes, con `enSegundoPlano`, solo el JSON iba a otro hilo; la huella (lo más caro) se calculaba en el de la interfaz y el armado se pasaba como clausura (que en Dart puede arrastrar estado no enviable; las pruebas no lo ejercitaban porque usan `enSegundoPlano: false`). Ahora huella + JSON + armado van juntos en `compute` con funciones de nivel superior y datos enviables, para fondo, capas y curvas de más de 96 KB. Hay un test que corre `compute` de verdad (otro isolate) y comprueba que arma lo mismo y descarta una huella rota. En la app (`main.dart`) el repositorio ya se crea con `enSegundoPlano: true`.
- **Memoria:** ≈ 1 a 1,5 MB por capa grande ya armada. Se bajó el tope de capas en memoria de 20 a 12 (≈ 18 MB en el peor caso de capas de 600 KB; con las capas reales, que en su mayoría van a ser más chicas, mucho menos). La pantalla ya no retiene polígonos de alturas que no se ven (§2).
- El dibujo lo hace `flutter_map` en el hilo de la interfaz (proyección y simplificación por zoom); con 27 000 puntos no se notó en la prueba. Falta medirlo en el Redmi con las capas reales (pendiente 4).

## 5. Cómo reemplazar los assets provisorios por los reales

Los archivos los genera el pipeline (`lector/mapa/`, otro agente). Pasos, desde la raíz del repo:

1. Generar en una carpeta aparte, por ejemplo `python -m mapa ../salida_mapa` dentro de `lector/` (ver `lector/mapa/pipeline.py`). Tiene que terminar sin errores de validación (si hay, no publica nada).
2. Borrar los provisorios:
   `app/assets/mapa/indice.json`, `app/assets/mapa/base.json` y todo `app/assets/mapa/agua/*.json`. Dejar `app/assets/mapa/curvas/.gitkeep`.
3. Copiar **solo** lo del contrato:
   - `salida_mapa/indice.json` → `app/assets/mapa/indice.json`
   - `salida_mapa/base.json` → `app/assets/mapa/base.json`
   - `salida_mapa/agua/*.json` → `app/assets/mapa/agua/`
   - `salida_mapa/curvas/*.json` → `app/assets/mapa/curvas/`

   **No** copiar `calibracion.json`, `control.png` ni `mapa.log`: `assets/mapa/` está declarada entera y entrarían en el APK.
4. No abrir ni reformatear los JSON (cambia el sha256 y la app los descarta). En Windows, copiar en binario (Explorador o `Copy-Item`); no pasar por un editor que cambie los fines de línea.
5. Controlar, desde `app/`:
   - `flutter test test/mapa_logica_test.dart` → el test **"assets/mapa/ es válido"** lee los archivos reales con el mismo código de la app: índice válido, mismo cero que `actual.json`, fondo, las 66 capas sin reemplazo y cada curva. El test de `pubspec.yaml` avisa si apareció una carpeta sin declarar.
   - `flutter analyze`, `flutter test` y `flutter build apk --release`; comparar el tamaño del APK con el de este informe.
6. En el teléfono: la pestaña tiene que mostrar el recuadro "Mapa aproximado, en prueba" (con `validado: false`) y **no** el de "Datos de prueba". Probar Hoy, − / +, una crecida con su contorno y modo avión.
7. Cuando el índice diga `validado: true` (lo decide el pipeline con la revisión externa), el recuadro desaparece solo; el pie "No reemplaza la alerta oficial" queda siempre.

No hace falta tocar código ni `pubspec.yaml` para ningún paso.

## 6. Build release

`flutter build apk --release` (Flutter 3.47.7, AGP del proyecto): **OK**, 51,0 MB (APK con todas las arquitecturas, firmado con la clave de depuración como en el CI). Antes de los cambios: 51,0 MB. Control de recursos (`aapt2 dump resources` de build-tools 36.0.0, mismo criterio que `app.yml`): `@drawable/ic_notificacion` presente. Dentro del APK están `assets/mapa/indice.json`, `base.json`, las 21 capas provisorias y `curvas/.gitkeep` (la carpeta nueva entra).

Con los datos reales el APK crece lo que pesen los archivos: el pipeline topa 600 KB por capa y 20 MB en total; los JSON se comprimen dentro del APK (el pipeline informa `agua_gzip_bytes` en `calibracion.json`).

## 7. Cambios de archivos

- `app/lib/pantallas/mapa.dart`: franja de hoy (ícono + palabra), `MergeSemantics` del deslizador, columna en vez de lista, seguimiento de "hoy" vs. altura elegida, recuadro "en prueba", cero del índice, umbrales solo con el mismo cero, "Alturas para comparar" con crecidas y contorno opcional, leyenda del contorno, polígonos sin crecer, reinicio si cambia el repositorio, texto de cauce con margen.
- `app/lib/mapa/modelos_mapa.dart`: `ceroDelMapa`, `ReferenciaMapa.archivo` (tolerante), `CurvaMapa`, tope `bytesCurva`, referencias ordenadas (máx. 40).
- `app/lib/mapa/repositorio_mapa.dart`: huella + JSON + armado en `compute` con funciones enviables, `curva()`, 12 capas en memoria.
- `app/lib/mapa/logica_mapa.dart`: solo formato.
- `app/pubspec.yaml`: `assets/mapa/curvas/`. `app/assets/mapa/curvas/.gitkeep` (vacío).
- `app/test/fixtures_mapa.dart`, `mapa_logica_test.dart`, `mapa_test.dart`: §2 y §3.

## 8. Pendientes para la etapa de diseño visual

1. **Más de un recuadro a la vez.** El diseño (03 §2) pide uno solo; hoy puede haber dos: el de calidad del mapa ("en prueba"/"datos de prueba") y el del dato de hoy (viejo, sin conexión, sin dato). Decidir si el de "en prueba" pasa a una franja propia, más chica, sin perder visibilidad.
2. **Agua rayada.** La leyenda dice "borde continuo" y "borde de puntos"; el rayado a 45° del diseño (para distinguir el agua del cauce sin color) no está: `flutter_map` 8 no rellena con patrones. Opciones: un `CustomPainter` propio sobre la proyección o una textura con `ImageShader`.
3. **Botones de alturas.** Hoy son una columna de botones anchos (seguro con letra al 200 %). El diseño propone grilla de 2 columnas, botón "Hoy" y "Pronóstico CARU" (si está vigente), marcas de alerta y evacuación bajo el deslizador, vibración al cruzarlas y animación de 400 ms al saltar.
4. **Medir en el Redmi** con las capas reales: arrastrar el deslizador por todo el rango y mover el mapa con el perfilador (dibujo de `flutter_map` en el hilo de la interfaz), y memoria con 12 capas guardadas. Si se traba, bajar `capasEnMemoria` o pedir al pipeline más simplificación.
5. **Color del contorno de crecida** (bordó en claro, rosa en oscuro): revisar contraste con el agua y con el modo oscuro, y si conviene una muestra de trazos en la leyenda en vez de una línea llena.
6. Barra superior con el tinte del nivel, aviso de simulación como franja oscura, zonas en texto debajo del mapa, tarjeta "Cómo se usa" la primera vez, "Mi casa" (03 §7) y la hoja "Ver fuentes".
7. Las crecidas de los botones salen del índice (nombre y altura del pipeline). Confirmar con Dinagua los nombres y picos antes de publicar (03 §12.1).

## v1.1 (contrato 05, "Agregados v1.1")

21/10/2026 · Mobile App Builder. Paso 1 del traspaso (12), parte app. Alcance: `app/lib/mapa/modelos_mapa.dart`, `repositorio_mapa.dart`, `logica_mapa.dart`, `app/lib/pantallas/mapa_partes.dart`, los tests del mapa y este documento. **No** se tocó `estilo_mapa.dart`, `pantallas/mapa.dart` ni `08-cartografia.md` (son del cartógrafo, que trabajó en paralelo), ni `lector/`, `data/`, `.github/` o `app/assets/mapa/`. Sin commits.

### Resultado

| Control | Resultado |
|---|---|
| `flutter analyze` | **0 problemas** |
| `flutter test` | **273 OK, 0 fallas** (antes: 263 OK y 1 falla) |

### La falla y su arreglo

`mapa_v11_test.dart` › "zona sin validar (v1.1 §1) con el archivo: fila en la leyenda y mención en el resumen". El test pedía lo que dice el contrato (05 v1.1 §1: "la nombra en la leyenda y en el resumen textual") y el 09 §3.9 (fila "Zona sin validar…" si el índice trae `sin_validar` y el archivo valida). El resumen ya la nombraba; **la leyenda no tenía la fila**: el bug era del código, no del test. La leyenda se arma en `pantallas/mapa.dart` (`_leyenda`), archivo del cartógrafo, que en paralelo sumó las filas de zona baja, línea de hoy, loma aislada y zona sin validar con sus muestras. Con eso el test pasa sin cambios en lo que pide.

### Qué está y dónde se prueba

| Contrato v1.1 | Qué hace la app | Prueba (`test/mapa_v11_test.dart` salvo aclaración) |
|---|---|---|
| §1 `sin_validar` en el índice | Opcional y tolerante: si falta o viene mal (nombre con `..`, dentro de `agua/` o `curvas/`, `bytes: 0`, huella mal escrita, más de 2 MB) se ignora y el mapa sigue. Sus bytes cuentan para el tope total. | grupo "índice: sin_validar opcional" |
| §1 `sin_validar.json` | Se lee una sola vez, con tamaño y sha256 como las capas; una zona rota se saltea; sin nombre se llama "Zona sin validar"; tope de puntos. Si no valida, null y el mapa sigue. | grupo "repositorio: sin_validar.json" |
| §1 dibujo, leyenda y resumen | Borde de trazo y punto encima del agua (cartógrafo), fila en la leyenda y mención en el resumen para TalkBack. **Nuevo:** `resumenMapa(nombresSinValidar: …)` nombra las zonas con lo que trae el archivo (`textoSinValidarDe`); sin nombres usa el texto fijo del valle del arroyo San Francisco. | "zona sin validar (v1.1 §1)", "zona sin validar: su borde se dibuja solo si el archivo validó", "la zona sin validar se nombra con lo que trae el archivo" |
| §2 `aisladas` | Opcional por capa: punto dentro del mapa, `ha` y `calles_m` opcionales; lo raro se saltea; una lista que no es lista no rompe la capa; tope de 200 marcas por capa. Se avisan las de la capa pintada (o, por debajo del mínimo, las de la zona baja): "Hay una loma marcada en el mapa. Quedaría rodeada de agua: aunque no se inunde, puede quedar aislada." (y el plural). Cada marca abre una hoja con el texto del contrato. | grupo "capa: aisladas opcional", "lomas aisladas (v1.1 §2)", "lomas: una marca por punto, solo en la altura que las trae" |
| §3 zona baja | `elegirAgua` siempre trae `zonaBajaCm` (= `min_m`) y la pantalla siempre lee esa capa y la dibuja con su estilo. Con altura ≤ `min_m` la lectura dice el texto del 09 §3.4, **igual con 3,90 que con 4,00**; nunca "en su cauce" (solo queda en la leyenda del río: "Río y arroyos, en su cauce"). Sin pastilla de nivel por debajo del mínimo. | "zona baja de la costa (v1.1 §3)", "la zona baja se dibuja con su estilo con 3,20 / 4,00 / 7,00 / 11,20 m", "leyenda v1.1" |
| §4 margen siempre | `elegirAgua` siempre da `margenCm`: altura + margen redondeado hacia arriba al paso, recortado a las capas que existen (nunca debajo de la zona baja ni encima del máximo). La pantalla lee y dibuja esa capa siempre; cuando coincide con una capa que va encima (zona baja, agua en el máximo, línea de hoy), el cartógrafo repite los puntos encima para que no quede tapado. | **BLOQUEANTE**, abajo |
| Textos | Ningún texto nuevo dice "a salvo", "seguro", "zona segura", "no se inunda", "sin peligro" ni "en su cauce". El pie sigue con "Aproximado. No reemplaza la alerta oficial." | "ningún texto nuevo promete que no llega el agua", "el texto fijo los tiene todos" |
| Datos de hoy (sin campos nuevos) | `app/assets/mapa/` actual valida igual: sin `sin_validar`, sin `aisladas`, zona baja y margen presentes. | "datos reales de app/assets/mapa (sin los campos nuevos)" |

### Test bloqueante del margen (condición para publicar, 11 §8)

En `test/mapa_v11_test.dart`, grupo **"margen siempre (v1.1 §4, condición bloqueante para publicar)"**, con el rango real (4,00–10,50 m, margen 50 cm):

- **"BLOQUEANTE: la elección trae margen en las cinco alturas (3,50 · 4,00 · 7,00 · 10,50 · 11,20)"**: para cada una, la situación (debajo del mínimo / en rango / sobre el máximo), la capa del margen (400, 450, 750, 1050, 1050), que esa capa exista y que nunca quede por debajo del agua pintada.
- **"BLOQUEANTE: con 3,50 / 4,00 / 7,00 / 10,50 / 11,20 m se dibuja la franja de margen (capa …)"** (cinco widget tests): el mapa abre en esa altura, lee la capa del margen, pinta **todos** sus polígonos con el estilo del margen, y cuando el margen coincide con una capa que va encima (3,50: zona baja; 10,50 y 11,20: capa máxima) sus puntos aparecen también arriba. La leyenda lo explica.
- Además: "elegirAgua siempre da un margen dentro de las capas" (0, 3,50 … 11,20 m) y "también al simular cada altura con el deslizador en todo el rango" (de a 50 cm).

### Cambios de esta tanda

- `app/lib/pantallas/mapa_partes.dart`: `textoSinValidarDe(nombres)` y el parámetro opcional `nombresSinValidar` de `resumenMapa` (sin él, el texto de antes).
- `app/test/mapa_v11_test.dart`: test bloqueante del margen reforzado (las cinco alturas en lógica y en pantalla, lectura, todos los polígonos, puntos encima cuando queda tapado); grupos "leyenda v1.1" y "dibujo v1.1 en el mapa"; la mención de la zona sin validar se busca por lugar, para que siga valiendo cuando la pantalla pase los nombres del archivo.
- `modelos_mapa.dart`, `repositorio_mapa.dart` y `logica_mapa.dart`: revisados contra el contrato; quedan como en el WIP (no hizo falta cambiarlos).

### Pendientes

1. **Cartógrafo (`pantallas/mapa.dart`):** pasar los nombres al resumen: `nombresSinValidar: [for (final z in _sinValidar?.zonas ?? const <ZonaSinValidar>[]) z.nombre]` en la llamada a `resumenMapa`. Mientras no esté, TalkBack dice el texto fijo del valle del arroyo San Francisco (correcto para los datos v1, que traen una sola zona).
2. **Datos v1.1 reales** (paso 2 del 12): cuando el pipeline publique `sin_validar.json` y `aisladas`, correr `flutter test test/mapa_logica_test.dart test/mapa_v11_test.dart` sobre los assets nuevos y `flutter build apk --release`.
3. **Redmi:** ver con el sol y TalkBack la zona baja, el borde de la zona sin validar, las marcas de loma (48 dp) y los puntos del margen encima en 3,50 y 10,50 m.
