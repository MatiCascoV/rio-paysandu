# 13 — Revisión legal del mapa: licencias, créditos y descargos

Revisión del 21/10/2026 sobre la rama `mapa-inundacion` (commit WIP `980aeaa`). Rol: Legal Compliance Checker. Paso 3 de `12-retomar.md`.

> **No soy abogado y esto no es asesoramiento legal.** Es una revisión de cumplimiento contra fuentes públicas para un proyecto comunitario y gratuito. Lo marcado **[CONSULTA PROFESIONAL]** conviene verlo con un abogado antes de publicar en la tienda.
>
> Convención (la misma del 04): **[CONFIRMADO]** = leído en la fuente o en el código. **[NO CONFIRMADO]** = inferencia o dato que hoy no pude verificar.
>
> **Limitación de esta revisión:** desde este entorno la red solo dejó hacer búsquedas web. No se pudieron abrir directamente osmfoundation.org, opendatacommons.org, openstreetmap.org, ambiente.gub.uy ni visualizador.ide.uy (el proxy los rechazó). Lo que cito de esas páginas sale del 04 (leído el 19/10), de los resultados de búsqueda o de mi conocimiento del texto de la licencia, y lo marco así. Hay que releerlo antes de publicar.

Qué revisé: `04`, `00`, `01`, `05`, `06`, `09`, `10`, `11`, `README.md`, los textos de `app/lib/pantallas/mapa_partes.dart`, `mapa.dart` y `comunes.dart`, `app/assets/mapa/indice.json` (solo lectura) y de dónde baja los datos el pipeline (`lector/mapa/config.json`, `descarga.py`, `base_osm.py`, `pipeline.py`). No toqué código ni datos.

---

## 1. Resumen y veredicto

**Veredicto: el mapa se puede seguir probando, pero para el PR a `main` y la publicación en la tienda faltan 3 cosas bloqueantes.** Son baratas de resolver (textos y un archivo de licencia) y una depende de Dinagua.

Lo que está bien:

- **Los descargos de seguridad son buenos.** El pie dice siempre "Aproximado. No reemplaza la alerta oficial.", hay sello "Mapa en prueba" con `validado: false`, ningún texto dice "a salvo" ni "zona segura" (y hay tests que lo prohíben: `app/test/mapa_v11_test.dart:437`, `mapa_test.dart:543`). El texto fijo `textoMapaAproximado` cubre: no oficial, borde de una cuadra o más, sin lluvia ni pluviales, "si estás cerca del borde, el agua te puede llegar", "si quedás rodeado de agua, también estás en riesgo", Cecoed, Intendencia y 911.
- **La privacidad del mapa está limpia.** No hay "Mi casa" ni GPS en esta versión. No se piden permisos nuevos (el manifiesto solo tiene `INTERNET` y `POST_NOTIFICATIONS`). El mapa no usa ningún servidor de teselas: todo va dentro del APK. Por lo tanto no hay datos personales en el sentido de la Ley 18.331 y no corre la política de teselas de OSM.
- **La atribución visible sobre el mapa existe** ("© OpenStreetMap · IDE Uruguay · Dinagua", siempre a la vista, abajo a la izquierda) y hay hoja "Fuentes del mapa".

Lo que bloquea:

1. **ODbL (share-alike) sin cumplir en los archivos.** `base.json` es una *base de datos derivada* de OpenStreetMap: son 1.174 calles con nombre, agua, arroyos y barrios sacados del extracto de Geofabrik. Ya se distribuye en un repositorio público (la rama está en `origin`) y va dentro del APK. Las capas de agua también usan OSM (cauce, arroyos quemados, metros de calle de las lomas). Falta declarar esos archivos bajo ODbL, con su aviso, en el repo y en la app. El 04 §2.3 decía "hoy no está previsto" extraer datos de OSM. Cambió con la decisión del 00 y nadie actualizó la parte legal.
2. **Licencia de las curvas de Dinagua sin confirmar**, y las 5 curvas ya se redistribuyen (repo público y APK). Para seguir probando el riesgo es bajo. Para publicar en Play hace falta la respuesta de Dinagua o una decisión explícita del dueño, con plan de retiro.
3. **Nota de origen de la IDE incompleta.** La Licencia de Datos Abiertos – Uruguay exige citar el proveedor, la licencia, **el conjunto de datos** y **las modificaciones**. La app no nombra los dos conjuntos que realmente se usan (MDT urbano 1 m y MDT nacional 2,5 m) y lista solo parte de los cambios.

Conteo: **3 bloqueantes, 7 importantes, 7 menores** (tabla §2).

---

## 2. Hallazgos

Gravedad: **bloqueante** = no hacer el PR a `main` ni publicar sin resolverlo · **importante** = resolver antes de publicar en la tienda · **menor** = conviene, no frena.

| # | Gravedad | Qué | Dónde | Por qué | Cómo arreglar |
|---|---|---|---|---|---|
| B1 | **Bloqueante** | `base.json` (y, muy probablemente, `agua/*.json`, `sin_validar.json` y las `aisladas`) son una base derivada de OSM y no tienen aviso ODbL ni declaración de licencia | `app/assets/mapa/` (no hay `LICENSE` ni aviso); hoja Fuentes; `README.md` | ODbL 1.0 §4.2 (aviso), §4.4 (share-alike: la base derivada que se usa en público se ofrece bajo ODbL) y §4.6 (dar acceso a la base derivada o al método). La rama `mapa-inundacion` ya está publicada en GitHub (`origin/mapa-inundacion`), así que la distribución pública ya existe. Las capas de agua se calculan restando el agua de OSM, quemando arroyos de OSM y midiendo calles de OSM: tratarlas como derivadas es la lectura prudente **[NO CONFIRMADO; CONSULTA PROFESIONAL si se quisiera otra licencia]** | Agregar `app/assets/mapa/LICENSE-DATOS.md` (texto en §3.1) que declare `base.json`, `agua/`, `sin_validar.json` e `indice.json` bajo ODbL 1.0, con el aviso del Anexo A de la ODbL y los créditos de IDE. Sumar una línea en la hoja Fuentes (§3.3). El acceso de §4.6 se cumple con el repo público y el pipeline (`lector/mapa/`): hay que decirlo en el archivo. No hace falta tocar los datos |
| B2 | **Bloqueante** (para la tienda y para `main`) | Las curvas de Dinagua (`curvas/*.json`) no tienen licencia escrita y ya se redistribuyen | `app/assets/mapa/curvas/`; hoja Fuentes ("Crecidas medidas…") | El WFS no declara licencia (los metadatos son los valores por defecto de GeoServer) y las curvas no están en el Catálogo Nacional (04 §1.4, revisado otra vez por búsqueda: la página de datos abiertos del Ministerio no las lista). Ley 18.381 art. 2: es información pública, pero eso **no** equivale a una licencia de reuso (04 §1.1). Podrían estar protegidas como compilación (Ley 9.739 con la redacción de la Ley 17.616) **[NO CONFIRMADO; CONSULTA PROFESIONAL]**. Riesgo práctico: bajo (dato público, uso gratuito, con cita), pero Dinagua podría pedir el retiro | (1) Mandar ya el correo de §4.1, que ahora además pide la licencia por escrito. Si en 10 días hábiles no hay respuesta, presentar un pedido formal por Ley 18.381 (§4.2). (2) Mientras tanto, el texto de la hoja Fuentes dice que no hay licencia publicada y que se retira si lo piden (§3.3). (3) Probar que la app funciona sin `curvas/` (el repositorio ya devuelve `null` si falta una curva: `repositorio_mapa.dart:152`), para poder retirarlas en un día. (4) Publicar en la tienda solo con respuesta favorable o con decisión escrita del dueño en `docs/mapa/` |
| B3 | **Bloqueante** | Nota de origen de la IDE incompleta | `textosFuentes` en `mapa_partes.dart:62`; `fuentes` de `indice.json` y `lector/mapa/config.json` | Licencia de Datos Abiertos – Uruguay v0.1: hay que citar el proveedor, la licencia, **el conjunto de datos usado** y **las modificaciones** (04 §1.2, [CONFIRMADO el 19/10]). El Decreto 54/2017, art. 2, pide además identificar la licencia en la aplicación que usa los datos abiertos (resúmenes de IMPO y AGESIC, [CONFIRMADO parcial]). Hoy dice "Modelo digital del terreno de la IDE Uruguay (vuelo 2017–2018)…" y no nombra los dos productos: MDT urbano 1 m de Paysandú (Remesa Urbana 09, vuelo oct-2017) y MDT nacional 2,5 m (Remesa 04) (`config.json`; 06 §2) | Reemplazar el texto de "Terreno" por el de §3.3. En la próxima corrida, cambiar `fuentes` en `lector/mapa/config.json` por los textos de §3.2. No editar `indice.json` a mano: lo controla el sha256 |
| I1 | Importante | El 04 quedó desactualizado y se contradice con lo construido | `04-licencias-y-textos.md` §1.5, §2.2, §2.3, §3.3 | Recomienda PMTiles de Protomaps y la atribución "Teselas generadas con Protomaps", pero la app usa GeoJSON propio (00 §2). §2.3 dice que no habrá base derivada de OSM (ver B1). §3.3 (GPS) no aplica a la v1 | Agregar al 04 una nota arriba: "Actualizado por 13-legal.md: ver allí atribución, ODbL y textos vigentes". No borrar el análisis de GPS: sirve para cuando se haga "Mi casa" |
| I2 | Importante | La tarjeta de la primera vez no trae el descargo principal | `TarjetaComoSeUsa` / `pasosComoSeUsa` (`mapa_partes.dart:54`, `:461`) | 04 §3.2 recomendaba aceptar un aviso la primera vez: "no oficial", "que tu casa no aparezca pintada no significa que esté a salvo", Cecoed / 911. Hoy la tarjeta solo enseña a usar el mapa y cierra con "Es aproximado… No reemplaza la alerta oficial". El texto completo está en el pie, al fondo de la pantalla, y se puede no llegar a leerlo. Para la responsabilidad civil importa que el aviso **se haya mostrado** antes de usar el mapa | Agregar a la tarjeta los dos renglones de §3.4. Sin pantalla bloqueante nueva: el "Entendido" que ya existe alcanza |
| I3 | Importante | Falta el texto de "Limitaciones" (sin garantía, "tal cual") | Hoja Fuentes | 04 §3.2 lo proponía y no está en la app. Un servicio gratuito con un aviso claro de que no hay garantía reduce, sin eliminar, la exposición por responsabilidad extracontractual (Código Civil, art. 1319 y siguientes). Un descargo unilateral **no** exime de culpa grave ni de dolo **[NO CONFIRMADO; CONSULTA PROFESIONAL]** | Agregar el bloque "Limitaciones" de §3.3 al final de la hoja Fuentes |
| I4 | Importante | No hay licencia del repositorio ni sección de créditos de datos en el README | Raíz del repo (no hay `LICENSE`); `README.md`, "Estado" | El repo es público. Sin `LICENSE` el código queda "todos los derechos reservados", y eso contradice el espíritu comunitario y la nota del correo a Dinagua ("código abierto"). El Decreto 54/2017 pide identificar la licencia de datos abiertos donde se usan, y GitHub es uno de esos lugares. Si más adelante se publica `data/mapa/` en Pages, aplica igual | El dueño elige la licencia del código (sugerencia: MIT o GPL-3.0; es decisión suya). Agregar al README la sección "Datos del mapa y licencias" de §3.5 |
| I5 | Importante | Ficha de Google Play: no hay borrador y la app usa información del gobierno | No existe documento de publicación (Fase 5 sin empezar) | Política de Play "Misleading Claims" / "apps que comunican información gubernamental": una app no oficial tiene que decir con claridad, en la descripción, que no representa a ningún gobierno y mostrar las fuentes de forma verificable ([support.google.com/…/9514050](https://support.google.com/googleplay/android-developer/answer/9514050), [CONFIRMADO por búsqueda]; releer el texto vigente). Dinagua, IDE y Cecoed son organismos del Estado; CARU es binacional | Usar el texto de §3.6 en la ficha. En "Seguridad de los datos": el mapa no recolecta nada. La política de privacidad sigue siendo obligatoria y debe sumar Firebase cuando entre la Fase 4 |
| I6 | Importante | Revisión profesional del descargo antes de la tienda | General | Es un mapa de seguridad de vida con `validado: false` y omisiones conocidas de hasta 180 m en zona urbana sin margen (11 §3). La medida de fondo es el diseño (margen siempre visible, sello "en prueba", nunca "a salvo"); los textos acompañan | Consulta corta con un abogado: (a) suficiencia del descargo, (b) si conviene una aceptación explícita, (c) el riesgo de B2, (d) la licencia del código. Llevar este documento |
| I7 | Importante | El deslinde de aval no nombra al Cecoed ni a la Intendencia | `textoFuentesDeslinde` (`mapa_partes.dart:73`) | El texto fijo nombra al Cecoed y a la Intendencia como referentes, así que hay que aclarar que tampoco avalan el mapa. Por la Ley 18.621 la gestión de emergencias es del Sinae y de los comités departamentales y Cecoed: el mapa no debe parecer de ellos. Además 04 §3.1 punto 4 ("que se perciba como mapa del Cecoed") | Texto de §3.3 |
| M1 | Menor | Hoja Fuentes sin enlaces, con la URL de OSM solo como texto | `textosFuentes` | La decisión del 21/10 (09 §9) fue no poner enlaces. La guía de atribución de OSMF pide, cuando el medio lo permite, enlazar a openstreetmap.org/copyright (04 §2.3; [NO CONFIRMADO hoy] el texto actual de la guía). Mostrar la URL como texto es aceptable para una primera versión | Mantener la URL visible en texto. Sumar también las URL de las licencias en texto (§3.3). Cuando se toque `enlaces_permitidos`, hacerlas enlaces |
| M2 | Menor | Fuentes repetidas con otra redacción | `mostrarFuentes` muestra `textosFuentes` y además `indice.fuentes` | Dos versiones del mismo crédito confunden y una puede quedar vieja | Dejar una sola: o `textosFuentes` fijo, o mostrar `indice.fuentes` solo si trae algo que la app no conoce. Es decisión de la app |
| M3 | Menor | CARU sin nombre completo en el mapa y sin términos de uso verificados | `textosFuentes` ("CARU.") | No encontré términos de uso de datos en caru.org.uy (búsqueda sin resultados). Es la misma fuente que ya usa la app en `main` | Escribir "Comisión Administradora del Río Uruguay (CARU)". En el correo que ya está pendiente con CARU (HTTPS, cero), preguntar si hay condiciones de reuso |
| M4 | Menor | "Vuelo 2017–2018" en la app y "vuelo 2017" en `indice.json` | `textoMapaAproximado`, `textosFuentes`, `modelo.metodo` | Las dos cosas son ciertas: urbano oct-2017 y nacional 2017-2018. Igual parece una inconsistencia | El texto de §3.3 lo explica |
| M5 | Menor | No queda registrada la fecha del extracto de OSM | `indice.json` / `calibracion.json` | Sirve para §4.6 de la ODbL y para la trazabilidad. El 06 dice que la descarga de Geofabrik fue el 21/10 y la vista previa dice "18/10" | Anotarla en `LICENSE-DATOS.md` (§3.1) y, si se puede, en `calibracion.json` en la próxima corrida |
| M6 | Menor | En "Ajustes" dice "no recolecta datos personales" | `ajustes.dart:172` | Hoy es cierto. Con la Fase 4 (FCM: token del dispositivo) deja de serlo en sentido estricto | Revisarlo cuando entre FCM; fuera del alcance del mapa |
| M7 | Menor | "Mi casa" (futuro) cambia el análisis de privacidad | 00 §1 y 09 §9 (postergado) | Un punto de la casa guardado en el teléfono identifica un domicilio. Si nunca sale del teléfono, no hay base de datos del responsable (Ley 18.331, arts. 4 y 29) **[NO CONFIRMADO]**, pero hay que avisar y dar forma de borrarlo | Cuando se haga: usar el texto de 04 §3.3 adaptado ("se guarda solo en tu teléfono; podés borrarlo"), sin GPS en segundo plano, y nunca un aviso del tipo "tu casa se va a inundar" |

Lo que **no** encontré como problema:

- **Política de teselas de OSM:** no aplica. No hay `TileLayer` ni ninguna URL de teselas en `app/lib`, y la vista previa `docs/mapa/mapa-real.html` tampoco usa `tile.openstreetmap.org`.
- **Descarga de datos:** el pipeline baja OSM de Geofabrik (ODbL), el MDT de la IDE y el WFS de Dinagua con un User-Agent propio (`descarga.py:22`). Está bien. Sugerencia menor: poner en el User-Agent la URL real del repo en vez de `https://github.com`.
- **Seguridad de vida:** cumple la regla del 12 (nunca esconder agua, nunca "a salvo", pie con "No reemplaza la alerta oficial").

---

## 3. Textos propuestos, listos para pegar

Todos en español rioplatense y sin "a salvo" ni "seguro/a", para que sigan pasando los tests de palabras prohibidas.

### 3.1 `app/assets/mapa/LICENSE-DATOS.md` (archivo nuevo; lo crea quien edite `app/`)

> Importante: este archivo **no** va en `indice.json` y no altera ningún sha256. Si `pubspec.yaml` declara la carpeta `assets/mapa/` entera, va a entrar en el APK, y está bien que entre.

```markdown
# Datos del mapa de inundación — licencias

## Base de datos derivada de OpenStreetMap (ODbL 1.0)

Los archivos `base.json`, `agua/*.json`, `sin_validar.json` e `indice.json` de esta carpeta
contienen información de OpenStreetMap y se ofrecen bajo la Open Database License (ODbL) 1.0:
https://opendatacommons.org/licenses/odbl/1-0/
Los derechos sobre los contenidos individuales de la base se licencian bajo la
Database Contents License: https://opendatacommons.org/licenses/dbcl/1-0/

© colaboradores de OpenStreetMap — https://www.openstreetmap.org/copyright
Extracto usado: Geofabrik, `south-america/uruguay-latest.osm.pbf`, descargado el 21/10/2026.
Cómo se generan (ODbL §4.6): el código está en `lector/mapa/` de este repositorio
(`python -m mapa <salida>`); ver `docs/mapa/06-informe-pipeline.md`.

## Modelo digital del terreno (Licencia de Datos Abiertos – Uruguay)

Las capas `agua/*.json` y `sin_validar.json` se calcularon con datos de la
Infraestructura de Datos Espaciales de Uruguay (IDE Uruguay):
- "MDT urbano de Paysandú, 1 m" (Remesa Urbana 09, vuelo de octubre de 2017), y
- "MDT nacional, 2,5 m" (Remesa 04, vuelo 2017–2018),
del conjunto "Ortoimagen y modelo digital del terreno de cobertura nacional"
(https://catalogodatos.gub.uy/dataset/ide-ortoimagen-mdt-de-cobertura-nacional).
Licencia de Datos Abiertos – Uruguay:
https://www.gub.uy/agencia-gobierno-electronico-sociedad-informacion-conocimiento/sites/agencia-gobierno-electronico-sociedad-informacion-conocimiento/files/documentos/publicaciones/licencia_de_datos_abiertos_0.pdf
Modificaciones hechas por Mi Río UY: recorte al área de Paysandú, unión de los dos MDT,
remuestreo a 2 m, cauces de arroyos de OpenStreetMap marcados en el terreno, cálculo del área
conectada al río por debajo de cada altura (cada 10 cm), ajuste con crecidas reales,
agrandado de 5 m, simplificación y conversión a GeoJSON.

## Curvas de crecidas (`curvas/*.json`) — Dinagua

Curvas de inundación de la Dirección Nacional de Aguas (Dinagua), Ministerio de Ambiente,
del servicio WFS https://www.ambiente.gub.uy/dinagua-gs/dinagua/wfs (capa `curvas_cri`).
Son información pública (Ley 18.381). Dinagua no publicó una licencia para estas capas;
las citamos como pide la Licencia de Datos Abiertos – Uruguay y estamos consultando al
organismo. Si Dinagua lo pide, las retiramos.
Modificaciones: recorte a Paysandú, reproyección a WGS84, simplificación y conversión a GeoJSON.

## Aviso

Mi Río UY es un proyecto comunitario sin vínculo con la IDE, el Ministerio de Ambiente,
CARU, el Cecoed, la Intendencia ni la Fundación OpenStreetMap, que no avalan este trabajo.
Los datos se ofrecen "tal cual", sin garantía.
```

**[NO CONFIRMADO hoy]:** que las URL de opendatacommons.org sigan con ese formato (`/licenses/odbl/1-0/`). El aviso es el del Anexo A de la ODbL, transcripto de memoria porque no pude abrir el sitio. Revisarlo.

### 3.2 `fuentes` de `lector/mapa/config.json` (para la próxima corrida del pipeline)

```json
"fuentes": [
  "© colaboradores de OpenStreetMap. Base derivada bajo licencia ODbL 1.0 (openstreetmap.org/copyright).",
  "Terreno: IDE Uruguay, MDT urbano de Paysandú 1 m (vuelo 2017) y MDT nacional 2,5 m (vuelo 2017–2018). Licencia de Datos Abiertos – Uruguay. Datos modificados por Mi Río UY.",
  "Crecidas medidas: Dirección Nacional de Aguas (Dinagua), Ministerio de Ambiente. Información pública, sin licencia publicada; datos modificados."
]
```

### 3.3 Hoja "Fuentes del mapa" (`textosFuentes` y `textoFuentesDeslinde` en `mapa_partes.dart`)

```dart
const textosFuentes = [
  (
    'Calles, río y barrios',
    '© colaboradores de OpenStreetMap. Los usamos para el fondo y para calcular el agua; '
        'esos datos derivados se comparten con la misma licencia, ODbL 1.0 '
        '(openstreetmap.org/copyright).',
  ),
  (
    'Terreno',
    'IDE Uruguay: modelo digital del terreno urbano de Paysandú, 1 m (vuelo de 2017), y nacional, 2,5 m '
        '(vuelo 2017–2018), del conjunto "Ortoimagen y modelo digital del terreno de cobertura nacional". '
        'Licencia de Datos Abiertos – Uruguay (catalogodatos.gub.uy). Datos modificados: los recortamos, '
        'unimos y pasamos a 2 m, y calculamos qué partes quedan por debajo de cada altura del río.',
  ),
  (
    'Crecidas medidas',
    'Curvas de inundación de la Dirección Nacional de Aguas (Dinagua), Ministerio de Ambiente. '
        'Información pública; Dinagua no publicó una licencia para estas capas y le estamos consultando. '
        'Las recortamos y simplificamos.',
  ),
  ('Altura del río y pronóstico', 'Comisión Administradora del Río Uruguay (CARU).'),
];

const textoFuentesDeslinde =
    'Los datos fueron modificados por Mi Río UY. Ni el Ministerio de Ambiente, ni la IDE, ni CARU, ni el Cecoed, '
    'ni la Intendencia, ni OpenStreetMap avalan esta app ni son responsables de lo que muestra.';

/// Va al final de la hoja Fuentes (04 §3.2, hallazgo I3 de 13-legal).
const textoLimitaciones =
    'Limitaciones: esta herramienta es gratuita y se ofrece tal cual, para informar. No garantizamos que '
    'sea exacta, completa ni que esté al día, ni que funcione siempre. No la uses como única fuente para '
    'decidir si evacuar, mover tus cosas o pasar por una zona. Las decisiones de evacuación son de las '
    'autoridades: Cecoed Paysandú y Sinae. Emergencias: 911.';
```

### 3.4 Tarjeta de la primera vez (sumar antes del "Entendido")

Agregar como último paso de `pasosComoSeUsa`, en lugar del actual "Es aproximado: el agua puede llegar más lejos. No reemplaza la alerta oficial.":

```dart
  'Es una estimación comunitaria, no un mapa oficial: el agua puede llegar más lejos. Que tu calle no '
      'aparezca con agua no quiere decir que no se inunde. No reemplaza la alerta oficial: seguí al Cecoed. '
      'Emergencias: 911.',
```

(Ojo: "Que tu calle no aparezca con agua no quiere decir que no se inunde" contiene "no se inunde" y no "no se inunda". La regex de `mapa_v11_test.dart:438` prohíbe `no se inunda\b`, así que pasa. El texto fijo actual ya usa esa misma frase.)

### 3.5 README, sección nueva (debajo de "Estado" o de "App Android")

```markdown
## Datos del mapa y licencias

La pestaña Mapa (en desarrollo) usa:

- **OpenStreetMap** — © colaboradores de OpenStreetMap. `app/assets/mapa/base.json` y las capas de agua
  son una base de datos derivada y se publican bajo **ODbL 1.0** (ver `app/assets/mapa/LICENSE-DATOS.md`).
- **IDE Uruguay** — MDT urbano de Paysandú (1 m, vuelo 2017) y MDT nacional (2,5 m, vuelo 2017–2018),
  bajo la **Licencia de Datos Abiertos – Uruguay**. Datos modificados (recorte, unión, remuestreo y cálculo
  de áreas bajo cada altura).
- **Dinagua (Ministerio de Ambiente)** — curvas de crecidas reales. Información pública sin licencia publicada:
  estamos consultando al organismo y las retiramos si lo pide.
- **CARU** — altura del río y pronóstico.

Ninguno de estos organismos avala la app. El mapa es una estimación: **no reemplaza la alerta oficial**.
```

### 3.6 Ficha de Google Play (Fase 5), párrafo obligatorio en la descripción

> **Mi Río UY no es una app oficial.** No representa a ningún gobierno ni organismo y no tiene vínculo con CARU, el Ministerio de Ambiente (Dinagua), la IDE Uruguay, el Sinae, el Cecoed ni la Intendencia de Paysandú. No reemplaza la alerta oficial: ante una crecida, seguí las indicaciones del Cecoed Paysandú y del Sinae. Emergencias: 911.
>
> Fuentes de los datos:
> • Altura y pronóstico del río: CARU — https://www.caru.org.uy
> • Crecidas medidas: Dinagua, Ministerio de Ambiente — https://www.gub.uy/ministerio-ambiente/politicas-y-gestion/inundaciones
> • Terreno: IDE Uruguay — https://www.gub.uy/infraestructura-datos-espaciales
> • Mapa: © colaboradores de OpenStreetMap — https://www.openstreetmap.org/copyright
>
> El mapa de inundación es una estimación aproximada y está en prueba: el agua puede llegar más lejos de lo que muestra.

---

## 4. Pendientes del dueño

| # | Qué | Cuándo |
|---|---|---|
| P1 | **Correo a Dinagua** (§4.1) pidiendo la licencia por escrito, el significado de `curvas_cri` y `curvas_tr` y el cero de la `cota_local`. Guardar la respuesta en `docs/mapa/` | Ya. Bloquea la tienda (B2) |
| P2 | Si en 10 días hábiles no hay respuesta, **pedido formal de acceso a la información** (Ley 18.381) al Ministerio de Ambiente con las mismas preguntas (§4.2). El plazo legal de respuesta es de 20 días hábiles (art. 15) **[NO CONFIRMADO hoy: verificar en IMPO]** | Después de P1 |
| P3 | Elegir la licencia del código del repo (I4) | Antes del PR |
| P4 | Consulta breve con un abogado (I6), con este documento | Antes de Play |
| P5 | Avisar al Cecoed Paysandú (borrador en 04 §4, variante Cecoed) | Antes de Play |
| P6 | En el correo pendiente a CARU (HTTPS, cero), preguntar si hay condiciones para reusar sus datos (M3) | Cuando se mande |
| P7 | Decidir, si Dinagua no contesta, entre: (a) publicar con las curvas, el texto de §3.3 y el compromiso de retiro, o (b) publicar sin `curvas/` (la app sigue andando; se pierden los bordes de las crecidas). Dejar la decisión escrita | Antes de Play |

Para quien edite `app/` y `lector/` (no lo hice yo): crear `LICENSE-DATOS.md` (§3.1), cambiar los textos de §3.3 y §3.4, el README (§3.5), `fuentes` en `config.json` (§3.2) y agregar al 04 la nota de I1.

### 4.1 Correo a Dinagua (versión actualizada del 04 §4)

> **Asunto:** Consulta sobre licencia de las curvas de inundación de Paysandú (app comunitaria gratuita)
>
> Estimados/as:
>
> Les escribo por **Mi Río UY**, una app Android gratuita, sin fines de lucro y sin vínculo oficial, que muestra la altura del río Uruguay en Paysandú con datos públicos de CARU (código abierto: https://github.com/MatiCascoV/rio-paysandu).
>
> Estamos probando una pestaña de mapa que muestra, de forma orientativa y con advertencias claras, hasta dónde podría llegar el agua según la altura del río. La calculamos con el modelo digital del terreno de la IDE y la ajustamos con las curvas de crecidas reales de la capa `curvas_cri` de su servicio WFS (https://www.ambiente.gub.uy/dinagua-gs/dinagua/wfs): jul-2025, jun-2017, ene-2019, nov-2009 y dic-2015 en Paysandú. Además mostramos esas cinco curvas, recortadas y simplificadas, citando a Dinagua / Ministerio de Ambiente como fuente, aclarando que los datos fueron modificados y que la app no es oficial ni reemplaza al Cecoed ni al Sinae.
>
> Como esas capas no figuran en el Catálogo Nacional de Datos Abiertos con una licencia, queríamos consultarles:
>
> 1. Si podemos redistribuir ese recorte bajo la Licencia de Datos Abiertos – Uruguay (o con la condición que ustedes indiquen), y cómo prefieren que los citemos.
> 2. A qué cero corresponde la `cota_local` de esas curvas: si es el mismo de la escala de CARU en el puerto de Paysandú, y cuál es la diferencia correcta con el Cero Oficial (en `curvas_cri` vemos +0,11 m y en `curvas_tr`, +0,14 m).
> 3. Si tienen alguna advertencia o texto que les gustaría que incluyamos.
>
> Con gusto les mostramos la versión de prueba y corregimos lo que nos señalen. Si prefieren que no redistribuyamos las curvas, las retiramos.
>
> Muchas gracias,
> [Nombre] · [correo] · Paysandú

Canales: el formulario https://www.gub.uy/ministerio-ambiente/institucional/contacto o el tel. 2917 3380 (04 §4). Si se consigue un correo del área de Inundaciones y Drenaje Urbano, mejor.

### 4.2 Pedido por Ley 18.381 (si no contestan)

Se presenta en el Ministerio de Ambiente (trámite "Solicitud de acceso a la información pública" en gub.uy). El texto: "Solicito, al amparo de la Ley 18.381, (1) las condiciones de uso o licencia aplicables a las capas `dinagua:curvas_cri` y `dinagua:curvas_tr` del servicio WFS de Dinagua; (2) la documentación de sus atributos y la referencia altimétrica de `cota_local` para Paysandú." **[CONSULTA PROFESIONAL opcional]**: el silencio del organismo no es una licencia.

---

## 5. Fuentes

Revisadas hoy (búsqueda web, 21/10/2026):

- Google Play, requisitos para apps que comunican información gubernamental: https://support.google.com/googleplay/android-developer/answer/9514050
- Decreto 54/2017 (directrices de datos abiertos; art. 2, identificar la licencia en la aplicación): https://impo.com.uy/bases/decretos/54-2017
- AGESIC, normativa de datos abiertos (Ley 19.355 art. 82, Decreto 54/017): https://www.gub.uy/agencia-gobierno-electronico-sociedad-informacion-conocimiento/sites/agencia-gobierno-electronico-sociedad-informacion-conocimiento/files/2020-09/Normativa%20de%20Datos%20Abiertos.pdf
- Ministerio de Ambiente, datos abiertos (no lista las curvas): https://www.gub.uy/ministerio-ambiente/datos-y-estadisticas/datos-abiertos
- Ministerio de Ambiente, inundaciones: https://www.gub.uy/ministerio-ambiente/politicas-y-gestion/inundaciones
- Ley 18.621 (Sinae): https://impo.com.uy/bases/leyes/18621-2009
- Ley 17.616 (modifica la Ley 9.739, derecho de autor): https://www.wipo.int/wipolex/es/legislation/details/3978
- Compilaciones de datos en el derecho uruguayo (CERLALC): https://cerlalc.org/wp-content/uploads/dar/jurisprudencia/2494.pdf
- OSM, copyright y licencia: https://www.openstreetmap.org/copyright
- OSMF, guía de atribución: https://osmfoundation.org/wiki/Licence/Attribution_Guidelines
- OSM wiki, archivos de alteraciones (ODbL §4.6; página comunitaria, no oficial): https://wiki.openstreetmap.org/wiki/Open_Data_License/Alteration_Files_-_Guideline

Del 04 (leídas el 19/10/2026, no las pude reabrir hoy):

- Licencia de Datos Abiertos – Uruguay v0.1: https://www.gub.uy/agencia-gobierno-electronico-sociedad-informacion-conocimiento/sites/agencia-gobierno-electronico-sociedad-informacion-conocimiento/files/documentos/publicaciones/licencia_de_datos_abiertos_0.pdf
- Términos del Catálogo Nacional de Datos Abiertos: https://catalogodatos.gub.uy/terminos-catalogodatos.pdf
- Conjunto IDE MDT: https://catalogodatos.gub.uy/dataset/ide-ortoimagen-mdt-de-cobertura-nacional
- Ley 18.381: https://impo.com.uy/bases/leyes-originales/18381-2008
- Ley 18.331: https://www.impo.com.uy/bases/leyes/18331-2008
- WFS Dinagua: https://www.ambiente.gub.uy/dinagua-gs/dinagua/wfs?service=WFS&request=GetCapabilities&version=2.0.0
- OSMF, política de teselas: https://operations.osmfoundation.org/policies/tiles/
- ODbL 1.0: https://opendatacommons.org/licenses/odbl/1-0/
- Google Play, Seguridad de los datos: https://support.google.com/googleplay/android-developer/answer/10787469

Del repo: `app/lib/pantallas/mapa_partes.dart` (líneas 25–75, 461–480, 512–540, 1225–1255), `app/lib/pantallas/mapa.dart:755`, `app/lib/pantallas/comunes.dart:67`, `app/lib/pantallas/ajustes.dart:172`, `app/assets/mapa/indice.json`, `lector/mapa/config.json`, `lector/mapa/descarga.py:22`, `docs/mapa/06-informe-pipeline.md` §2.
