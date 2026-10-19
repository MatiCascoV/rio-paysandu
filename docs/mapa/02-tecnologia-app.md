# Mapa de inundación: tecnología en la app (propuesta)

> Rama `mapa-inundacion`. Documento de diseño, sin código. Lo complementa el diseño del
> pipeline de polígonos (otro documento de `docs/mapa/`). Versiones verificadas en pub.dev
> el 19/10/2026.

## 0. Recomendación en una línea

**`flutter_map` 8.3.x sin mapa base de terceros**: el fondo (río, calles, manzanas, rótulos
principales) lo dibuja la propia app desde un GeoJSON chico sacado de OpenStreetMap, que va
**empaquetado en el APK** y se puede actualizar desde GitHub Pages. Encima va el polígono de
agua de la altura elegida (uno cada 10 cm, bajados de Pages y guardados en el teléfono).
"¿Llega a mi casa?" arranca **marcando el punto a mano**, sin GPS ni permisos; el GPS
queda como segundo paso opcional.

Por qué: Dart puro (cero código nativo nuevo → nada que choque con AGP 9.4.1 / Kotlin 2.4.21 /
Gradle 9.8.1 ni con el control aapt2 del CI), funciona sin conexión desde la primera vez,
no depende de la política de ningún servidor de mosaicos, sigue el modo oscuro de la app y se
puede probar con widget tests y goldens como el resto de las pantallas.

---

## 1. Opciones de mapa

### 1.1 Lo que se verificó en pub.dev (19/10/2026)

| Paquete | Última versión | Publicada | Notas |
|---|---|---|---|
| `flutter_map` | 8.3.2 (hay 8.4.0-dev.1) | 27/08/2026 | Dart puro. 160/160 puntos, ~1 M descargas/mes, publisher fleaflet.dev. Requiere Flutter ≥ 3.27 (CI usa 3.47.7). Trae `latlong2`, `dart_earcut`, `proj4dart`, `path_provider`. |
| `maplibre_gl` | 0.27.1 | 10/09/2026 | Plugin nativo (MapLibre Native Android). 160/160, ~131 k/mes, publisher maplibre.org, etiqueta `is:built-in-kotlin`. |
| `maplibre` (joscha-eckert) | 0.3.6 | 25/08/2026 | Nativo vía `jni`/`ffi`. Requiere Flutter ≥ 3.44. API todavía 0.x, ~15 k/mes. |
| `flutter_map_pmtiles` | 1.0.5 | 05/02/2025 | Proveedor de mosaicos **raster** PMTiles. Pide `pmtiles ^1.2` (la última es 2.2.0) y `flutter_map <9`. Mantenimiento atrasado. |
| `vector_map_tiles` | 8.0.0 | 16/08/2024 | Fija `flutter_map ^7`: **no es compatible con flutter_map 8**. Descarta mosaicos vectoriales dentro de flutter_map. |
| `geolocator` | 14.1.2 | 19/10/2026 (hoy) | Para la fase GPS. Usar 14.1.1 (27/09) o esperar dos semanas a que 14.1.2 se asiente. |

### 1.2 Comparación

| Criterio | A. flutter_map + mosaicos OSM online | B. maplibre_gl (vectorial) | C. flutter_map + fondo propio offline (**recomendada**) | C'. flutter_map + raster PMTiles propio |
|---|---|---|---|---|
| Peso del APK | Casi nada (Dart) | **Varios MB por ABI** (librería nativa de MapLibre; medir, del orden de 3–5 MB en arm64) + estilo/fuentes | Casi nada de código + el GeoJSON de fondo (estimado 200–600 KB) + polígonos empaquetados (ver §2.5) | Código chico + archivo PMTiles (estimado 5–15 MB para zoom 12–17 de la zona costera) |
| Sin conexión | Solo lo que quedó en caché; la primera vez, mapa en blanco | Requiere armar un paquete offline (estilo + mosaicos + fuentes) | **Funciona desde la primera apertura** | Funciona; hay que copiar el PMTiles del asset a un archivo al primer uso |
| Términos del mapa base | `tile.openstreetmap.org` prohíbe uso intensivo, descarga masiva y uso offline; una app con miles de usuarios en plena crecida es justo el caso que la política pide no hacer. Alternativas comerciales (Stadia, MapTiler, CARTO) piden clave/cuenta y tienen topes; no hay claves en la app (regla del proyecto) | Necesita un servidor de mosaicos vectoriales (OpenFreeMap es gratuito y sin clave, pero es un tercero del que dependeríamos en emergencia) o un PMTiles propio | Solo datos OSM (ODbL): basta con atribuir "© colaboradores de OpenStreetMap". Sin servidores de terceros | Igual que C, pero hay que **renderizar** los mosaicos uno mismo (no bajarlos de OSM) |
| AGP 9.4.1 / Kotlin 2.4.21 / Gradle 9.8.1 | Sin riesgo (Dart) | **Riesgo medio**: plugin nativo con dependencias Maven propias; el proyecto tiene `android.builtInKotlin=false` y ya hubo un choque Kotlin/AGP (PR #4). Hay que probarlo en el CI antes de comprometerse | Sin riesgo. Único plugin nativo que entra es `path_provider` (del equipo de Flutter, transitivo de flutter_map) | Sin riesgo nativo; `flutter_map_pmtiles` atrasado |
| Control aapt2 del CI | No lo toca | No lo rompe (solo mira recursos nombrados desde Dart), pero agrega recursos y reglas R8 nativas que hay que vigilar | No lo toca | No lo toca |
| Pruebas | Los widget tests no tienen red: el fondo sale vacío | **Platform view: no se dibuja en `flutter test`**; sin goldens, solo pruebas de integración en emulador | **Widget tests y goldens deterministas** (todo es Dart, sin red) | Goldens posibles leyendo el PMTiles de prueba |
| Modo oscuro | Mosaicos claros (o un segundo proveedor) | Con un segundo estilo | **Gratis**: los colores salen de `Colores` | Dos juegos de mosaicos |
| Rótulos de calles | Excelentes | Excelentes | Limitados: solo los que elijamos (calles principales, puerto, costanera, referencias) | Buenos (horneados en la imagen) |
| Mantenimiento del paquete | Muy bueno | Bueno | Muy bueno | Flojo |

**Descartadas:**
- **A** por la política de OSM y porque en una crecida puede no haber conexión, que es
  justamente cuando más se usa la pestaña.
- **B** por peso, riesgo de compilación y porque se pierden los goldens; su ventaja (mapa
  vectorial lindo con todas las calles) no compensa para una pantalla de un solo barrio costero.
- **Una sola imagen georreferenciada** (`OverlayImageLayer`): lo más simple, pero se ve
  borrosa al acercar y pesa más que el GeoJSON a calidad comparable.

**C' queda como plan B** si al probar C los vecinos no se ubican sin más rótulos: se renderizan
mosaicos raster desde datos OSM (por ejemplo con el basemap de Protomaps recortado con
`pmtiles extract`, renderizado en el CI) y se sirven con `flutter_map_pmtiles` o un
`TileProvider` propio. Nunca descargando mosaicos de `tile.openstreetmap.org`.

**Capa de foto aérea opcional (a futuro, a verificar):** las ortoimágenes nacionales de la
IDE Uruguay se publican como datos abiertos por WMS/WMTS. Si los términos y la URL se
confirman, se puede ofrecer un botón "Ver con foto aérea" (solo con conexión), siempre
encima del fondo propio, que sigue siendo el que se ve sin red.

### 1.3 Qué lleva el fondo propio

Un archivo `mapa/base.json` (GeoJSON, EPSG:4326, coordenadas redondeadas a 5–6 decimales)
generado por el pipeline a partir de un extracto de OSM (Geofabrik Uruguay), recortado al
rectángulo de la costa de Paysandú:

- `rio`: polígono del cauce normal (para no pintar como "inundado" lo que ya es río).
- `manzanas` o `edificaciones` simplificadas.
- `calles` como líneas, con `clase` (principal / secundaria / resto) para el grosor.
- `rotulos`: punto + texto para ~30–50 calles y lugares (puerto, costanera, plazas,
  escuelas y centros de evacuación si el Cecoed los publica).

Se dibuja con `PolygonLayer`, `PolylineLayer` y `MarkerLayer`, y la atribución con
`SimpleAttributionWidget` ("© colaboradores de OpenStreetMap").

---

## 2. Arquitectura de la pestaña

### 2.1 Navegación

Hoy `PaginaPrincipal` (en `lib/main.dart`) tiene un `IndexedStack` con 4 páginas y un
`NavigationBar` con 4 destinos; los saltos usan índices sueltos (`_pestana = 1`, `2`, `3`).

Propuesta:
- Quinto destino **"Mapa"** (ícono `Icons.map`) en la posición 2: Inicio · Gráfico · **Mapa** ·
  Qué hacer · Avisos. Material admite hasta 5 destinos.
- Reemplazar los números por un `enum Pestana { inicio, grafico, mapa, queHacer, avisos }`
  antes de agregar la quinta, para que `_irAQueHacer` y `alPedirAvisos` no apunten a la
  pestaña equivocada.
- El tope de letra actual (`maxScaleFactor: 1.3`) se pensó para 4 etiquetas. Con 5 hay que
  medir a 320 dp de ancho: probablemente baje a 1.2, o se use
  `NavigationDestinationLabelBehavior.onlyShowSelected`. Lo decide la prueba de desborde (§4).
- **Construcción diferida:** el `IndexedStack` arma todas las páginas al inicio. El mapa
  solo se construye la primera vez que se visita la pestaña (un `Set<Pestana>` de visitadas)
  para no cargar polígonos ni GeoJSON en el arranque. `TickerMode` ya apaga lo que se mueve
  en las pestañas ocultas.
- Desde Inicio, más adelante, un enlace "Ver en el mapa" (como `alVerGrafico`).
- Ojo: al cambiar claro/oscuro la app rehace todo (`KeyedSubtree(key: ValueKey(_oscuro))`);
  la cámara del mapa volvería a su lugar inicial. Guardar centro y zoom en el estado de
  `PaginaPrincipal` (o en `PageStorage`) si molesta.

### 2.2 Pantalla

```
┌───────────────────────────────────────┐
│ Se dibuja el agua con 5,70 m           │  ← siempre dice qué altura está pintada
│ Río ahora: 5,69 m · hoy 13:00 · CARU   │
├───────────────────────────────────────┤
│                                        │
│        MAPA (fondo propio + agua)      │  sin rotación, limitado a la zona,
│        · punto marcado (si hay)        │  zoom 12–18
│                                        │
├───────────────────────────────────────┤
│ [Ahora] [Pronóstico] [Alerta] [Evac.]  │  ← chips de referencias (de los JSON)
│ [Crecida 20xx] ...                     │
│ ───────────●────────────  6,50 m       │  ← deslizador, paso 10 cm
│ ¿Llega a mi punto? [Marcar punto]      │
│ Mapa aproximado, no oficial. Seguí     │
│ las indicaciones del Cecoed / Sinae.   │
└───────────────────────────────────────┘
```

- El deslizador (`Slider`, `divisions` = cantidad de capas) va del mínimo al máximo del índice
  y su valor semántico se lee "6,50 metros".
- Chips: **Ahora** (altura actual), **Pronóstico** (`pronostico.altura_esperada_m` si
  `vigente`), **Atención / Alerta / Evacuación** (de `umbrales.json`, con "de referencia" si
  `validado == false`), y **crecidas históricas** (vienen en el índice del pipeline; nada
  escrito en el código, regla 9).
- Interacción del mapa: `InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate)`
  y `CameraConstraint.contain(bounds: limites)`.

### 2.3 Contrato de datos propuesto (a acordar con el pipeline)

Todo bajo la misma `url_base` de `assets/config.json` (`.../data/`):

`mapa/indice.json`
```json
{
  "version": 3,
  "generado": "2026-10-19T12:00:00-03:00",
  "cero": "Local",
  "validado": false,
  "modelo": "Texto corto: DEM usado, fecha, método",
  "limites": [[-32.36, -58.12], [-32.29, -58.04]],
  "paso_m": 0.10,
  "min_m": 3.00,
  "max_m": 12.00,
  "base": { "archivo": "base.json", "bytes": 412000, "sha256": "..." },
  "capas": [
    { "altura_m": 3.00, "archivo": "agua/0300.json", "bytes": 18000, "sha256": "..." }
  ],
  "referencias": [
    { "tipo": "historica", "nombre": "Crecida de abril de 20xx", "altura_m": 0.0, "fecha": "20xx-04-xx", "fuente": "..." }
  ]
}
```
(valores ilustrativos)

`mapa/agua/0650.json`: GeoJSON `FeatureCollection` con un `MultiPolygon` (con huecos para las
zonas altas que quedan secas), solo el agua **conectada al río** a esa altura, simplificado a
~1–2 m y sin el cauce normal.

Validación en la app (mismo espíritu que `Repositorio.esValido` y `modelos.dart`):
- `cero` del índice **igual** al `cero` de `actual.json`. Si no coincide, no se pinta la
  altura actual y se avisa ("el mapa usa otra referencia de altura"): pintar con el cero
  equivocado es mostrar algo falso.
- Alturas ascendentes, dentro de 0–20 m, paso constante; `limites` dentro de Uruguay.
- Tope de bytes por archivo (reusar la descarga con tope y tiempo máximo de
  `Repositorio._bajar`, extraída a una función común en vez de duplicarla).
- Un polígono que no parsea o no coincide con su `sha256` se descarta y no pisa la copia buena.

### 2.4 Modelo en Dart (borrador)

```dart
class IndiceMapa { int version; String cero; bool validado; LatLngBounds limites;
                   double pasoM, minM, maxM; List<CapaAgua> capas; List<Referencia> referencias; }
class CapaAgua   { double alturaM; String archivo; int bytes; String sha256; }
class Referencia { String tipo, nombre; double alturaM; DateTime? fecha; String? fuente; }
class AguaDibujada { double alturaM; List<Polygon> poligonos; }   // ya proyectable por flutter_map
```

Un `RepositorioMapa` (archivo nuevo `lib/mapa_datos.dart`) con `cargarIndice()`,
`capa(alturaM)` y `base()`. La pantalla nueva sería `lib/pantallas/mapa.dart`, que recibe
`Datos` y `Config` igual que `PantallaGrafico` (no vuelve a bajar `actual.json`).

### 2.5 Caché de polígonos

- **En disco**, no en `shared_preferences` (que hoy guarda los JSON chicos):
  `getApplicationSupportDirectory()/mapa/v<version>/...` con `path_provider` (ya viene con
  flutter_map). Al cambiar la `version` del índice se baja lo nuevo y se borra la carpeta vieja
  recién cuando lo nuevo está completo.
- **Empaquetado en el APK** (`assets/mapa/`): el índice, `base.json` y las capas cada 50 cm
  (o todas, si el total comprimido queda por debajo de ~2–3 MB; decidirlo con los tamaños
  reales del pipeline). Así la pestaña funciona sin conexión desde la primera apertura. Si el
  índice bajado es más nuevo y válido, gana el bajado.
- **Prebúsqueda:** al abrir la pestaña se bajan la capa de la altura actual, ±50 cm, la del
  pronóstico y las de los umbrales. El resto, a demanda al mover el deslizador (con un
  pequeño retardo para no bajar 30 capas al arrastrar).
- **En memoria:** últimas ~20 capas decodificadas (LRU). El parseo de GeoJSON grande va con
  `compute()` para no trabar el deslizador.
- Tope total en disco (por ejemplo 15 MB) por si el pipeline crece.

### 2.6 Altura actual y datos viejos

La altura sale de lo que ya tiene `PaginaPrincipal`: `datos.actual?.altura` (`Lectura`, con
`valorM`, `fecha`, `fuente`) y `actual.nivelVigente(ahora, config.horasSinDato)`.

- **Qué capa se pinta:** se redondea **para arriba** al múltiplo de 10 cm (5,63 m → 5,70 m),
  del lado de la precaución, y la pantalla dice las dos cifras: "Se dibuja el agua con
  5,70 m · río ahora 5,63 m". Nunca se presenta la capa como si fuera la medición.
- **Dato con más de `horas_aviso_dato_viejo` (6 h):** se pinta, con la fecha bien visible
  ("Dato de hace 9 horas").
- **`nivelVigente == sinDato`** (sin altura, más de 48 h, fecha imposible): no hay chip
  "Ahora" ni capa inicial de "ahora"; el deslizador arranca en el umbral de alerta y un
  cartel dice "No hay un dato actual confiable del río. Podés mover la barra para ver otras
  alturas".
- **`avisos` con `dato_a_verificar`:** se pinta con la advertencia que ya usa Inicio.
- **Sin conexión:** se usa lo guardado/empaquetado. Si falta la capa exacta, se muestra la
  más cercana **por encima** que haya, diciendo cuál es ("No se pudo bajar el dibujo de
  6,50 m; se muestra el de 7,00 m"). Si no hay ninguna por encima, se muestra solo el fondo y
  se explica.
- **Fuera de rango:** por encima de `max_m`, "El mapa llega hasta 12,00 m".
- **Leyenda fija:** "Mapa aproximado, hecho con un modelo del terreno. No es un mapa oficial
  de riesgo. Ante una evacuación seguí las indicaciones del Cecoed y el Sinae". Encaja con la
  sección 2 y la regla 9 de `PROMPT_MAESTRO.md` (no presentar estimaciones como oficiales).
  Si existe cartografía oficial de zonas inundables de Paysandú (Dinagua / Intendencia), vale
  la pena contrastarla antes de publicar.

---

## 3. "¿Llega a mi casa?"

### 3.1 Paso 1 (recomendado para la primera versión): punto a mano, sin GPS

- Botón "Marcar mi punto" → el usuario toca el mapa (o mantiene apretado) y aparece un
  marcador que se puede mover. Sin permisos nuevos.
- Se guarda **solo en el teléfono** (`shared_preferences`, lat/lng redondeadas a 5 decimales,
  ~1 m) con "Borrar mi punto". `android:allowBackup="false"` ya está, así que no viaja en
  copias de seguridad. Nunca se manda a ningún servidor (la sección 6 dice "sin recolectar
  datos personales").
- **Cálculo en el teléfono:**
  - Punto en polígono con huecos (algoritmo de rayos, ~20 líneas propias, sin dependencias).
  - "¿Desde qué altura llega?": búsqueda binaria sobre las capas del índice (las capas son
    anidadas: si llega con 6,50 m, llega con más). Con ~90 capas son ~7 polígonos a revisar;
    se bajan solo esos.
  - Distancia al borde del agua en esa capa: si está a menos de ~30 m, "estás cerca del borde:
    el modelo puede errar".
- Texto (también para el lector de pantalla, que no puede "ver" el mapa):
  "Según el modelo, el agua empezaría a llegar a tu punto con el río en 7,10 m. Hoy está en
  5,69 m (faltan 1,41 m)." o "Con 12,00 m (lo máximo del mapa) el agua no llega a tu punto".

### 3.2 Paso 2 (opcional): "Usar mi ubicación"

- `geolocator` (14.1.1, o 14.1.2 cuando tenga dos semanas). Pedido **solo al tocar el botón**,
  una lectura (`getCurrentPosition`) y listo: nada en segundo plano.
- Permisos en el manifiesto: `ACCESS_FINE_LOCATION` + `ACCESS_COARSE_LOCATION` (Android 12+
  exige declarar las dos; si el usuario elige "aproximada", ~1–3 km no sirve para esto y se
  le dice que marque el punto a mano). **Nunca** `ACCESS_BACKGROUND_LOCATION`.
- La ubicación solo coloca el marcador; después vale lo mismo del paso 1. Se muestra la
  precisión ("± 15 m").
- Google Play: formulario de seguridad de datos (la ubicación se procesa en el teléfono y no
  se transmite) y párrafo nuevo en la política de privacidad (Fase 5).
- Antes de mergear: probar el build con AGP 9.4.1 en el CI y revisar el manifiesto fusionado
  (`build/app/intermediates/merged_manifests/release/...`).

### 3.3 A futuro

Aviso "el río se acerca a la altura que llega a tu punto": posible y 100 % local (la tarea
de `workmanager` ya compara alturas en el teléfono), pero solo después de validar el modelo.

---

## 4. Plan de pruebas

### 4.1 Unitarias (`test/mapa_logica_test.dart`)
- Parseo tolerante del índice: campos faltantes, alturas fuera de 0–20 m, paso irregular,
  orden, `cero` distinto, límites absurdos → se rechaza sin romper.
- GeoJSON: `Polygon` y `MultiPolygon`, huecos, anillos sin cerrar, coordenadas NaN, archivo
  que pasa el tope de bytes.
- Redondeo: 5,63 → 5,70; 5,70 → 5,70; debajo de `min_m`; encima de `max_m`.
- Elección de capa sin conexión: la más cercana **por encima**, nunca por debajo.
- Punto en polígono: dentro, fuera, dentro de un hueco, sobre el borde.
- Búsqueda binaria de "desde qué altura llega" con capas sintéticas anidadas.
- Caché: cambio de `version`, archivo corrupto no pisa el bueno, LRU, tope en disco
  (con un directorio temporal en lugar de `path_provider`).
- Datos viejos: tabla de casos con `nivelVigente` (actual, >6 h, >48 h, fecha posterior a
  `generado`, `dato_a_verificar`).

### 4.2 Widget tests (`test/mapa_test.dart`)
- Con un `RepositorioMapa` falso (o `MockClient`, como hoy en `pantallas_test.dart`):
  cargando, con datos, sin conexión con caché, sin conexión sin caché, sin dato actual.
- El texto "Se dibuja el agua con X m" coincide con la capa pintada.
- Los chips salen de `umbrales.json` / `pronostico` / índice (no hay números en el código) y
  "de referencia" aparece con `validado: false`.
- Deslizador: paso 10 cm, valor semántico en metros, mover → cambia la capa.
- Marcar punto, persistencia en `SharedPreferences.setMockInitialValues`, borrar punto.
- **Ampliar las pruebas existentes** que recorren pestañas en `test/pantallas_test.dart`
  (desborde por nivel y modo oscuro: hoy `['Gráfico', 'Qué hacer', 'Avisos', 'Inicio']`)
  y `test/rediseno_test.dart` para incluir **'Mapa'**, con letra agrandada y 320 dp de ancho
  (las cinco etiquetas del `NavigationBar`).
- Que el mapa no se construya hasta visitar la pestaña.

### 4.3 Goldens
- Con la opción C todo es Dart y sin red, así que el mapa se dibuja igual en cada corrida.
  Fixtures sintéticas chicas (`test/fixtures/mapa/`): fondo mínimo + dos capas.
- Casos: claro y oscuro × altura baja y alta × con y sin punto marcado.
- Las fuentes se dibujan distinto en Windows y en Linux: los goldens se generan y comparan
  **solo en el runner Ubuntu** (`@Tags(['golden'])`, en Windows se saltean) o con un
  comparador con tolerancia en `flutter_test_config.dart`. Para regenerarlos, un
  `workflow_dispatch` que suba los PNG como artifact.

### 4.4 CI (`.github/workflows/app.yml`)
- `flutter analyze` y `flutter test` como hoy (incluyen lo nuevo).
- El control aapt2 queda igual: flutter_map no agrega recursos nombrados desde Dart.
- Pasos nuevos propuestos:
  - **Tamaño del APK:** imprimir el tamaño de `app-release.apk` y fallar si crece más de un
    tope acordado (por ejemplo +3 MB) respecto de un valor de referencia guardado en el repo.
  - **Sin mosaicos de OSM:** `grep` que falle si aparece `tile.openstreetmap.org` en `lib/`.
  - **Assets del mapa:** validar `assets/mapa/*.json` (forma y tamaño) con el mismo código
    de validación de la app (test de Dart).
  - (Con GPS) revisar que el manifiesto fusionado no tenga `ACCESS_BACKGROUND_LOCATION`.

### 4.5 A mano, en teléfono real
- Teléfono viejo/gama baja: arrastrar el deslizador sin trabas (ver en el perfilador que el
  parseo no cae en el hilo de la interfaz).
- Modo avión desde una instalación limpia: el mapa tiene que verse.
- Ubicarse en el mapa con vecinos de un barrio costero (Persona Walkthrough): ¿encuentran
  su casa sólo con los rótulos del fondo propio? Si no, pasar al plan B (C').

---

## 5. Pasos para implementar (cuando se apruebe)

1. Acordar con el pipeline el contrato de §2.3 y tamaños reales.
2. Probar en esta rama `flutter pub add flutter_map:^8.3.2` + `flutter build apk --release`
   en el CI (confirmar que `path_provider` compila con AGP 9.4.1) y medir cuánto crece el APK.
3. Enum de pestañas + quinta pestaña vacía + pruebas de desborde.
4. `RepositorioMapa` + modelos + pruebas unitarias.
5. Pantalla con fondo, capa, deslizador y chips + widget tests + goldens.
6. Punto a mano.
7. (Opcional, aparte) GPS con `geolocator`.
