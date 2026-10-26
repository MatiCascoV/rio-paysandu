# Fase 4: cómo se lanza `avisos.yml` después de cada publicación

Tarea 3 del paso 6 (requisito del paso 8).

**Decidido por el dueño (26/10/2026): opción (b3)**, el workflow `lanzar-avisos.yml` con `workflow_run` de
`pages-build-deployment`, empezando con una semana de "solo mirar". **Implementado** en la rama
`fase-4-lanzar-avisos`:

- `.github/workflows/lanzar-avisos.yml`, nuevo;
- una línea `run-name` en `avisos.yml`;
- `lector.yml` sin cambios.

Abajo queda la comparación que llevó a la decisión. Las secciones "El cambio aplicado" y "Semana de solo
mirar" dicen cómo quedó y qué hacer después del merge.

## Recomendación en corto

Un **workflow nuevo, `lanzar-avisos.yml`**, que arranca solo cuando GitHub Pages **termina de publicar** un
commit de la rama `datos` (evento `workflow_run` del workflow interno `pages-build-deployment`). Ese
workflow:

1. arma la lista de commits de `datos` que cambiaron `data/actual.json` desde la publicación anterior de
   Pages que salió bien (normalmente uno solo);
2. confirma que `https://maticascov.github.io/rio-paysandu/data/actual.json` ya sirve ese dato (o uno más
   nuevo);
3. en un trabajo aparte, sin datos ni código del repositorio, lanza `avisos.yml` una vez por commit con
   `gh workflow run avisos.yml --ref main -f commit=<sha> -f prueba=<…>`.

Por qué:

- **`lector.yml` no cambia.** El trabajo `leer`, que procesa lo que manda CARU, sigue sin poder lanzar
  workflows.
- **El push sale por construcción después de Pages:** el evento llega cuando la publicación ya terminó, y
  además se verifica la URL pública.
- **No se pierden urgentes** aunque Pages saltee o falle una publicación: la lista cubre los commits que
  quedaron en el medio.
- **No hay duplicados:** las listas de dos corridas no se pisan, y antes de lanzar se revisa si ya hay una
  corrida de `avisos.yml` para ese commit.
- **Ningún token nuevo que mantener:** usa el `GITHUB_TOKEN` de siempre, sin PAT ni GitHub App.
- **La condición de Google del paso 6 no cambia:** `avisos.yml` se sigue lanzando con `workflow_dispatch`
  desde `main`.

**Lo único que no está comprobado:** que GitHub efectivamente dispare `workflow_run` cuando termina
`pages-build-deployment`. Esas corridas las hace `github-pages[bot]` y no el `GITHUB_TOKEN`, así que la
regla de "lo que hace el `GITHUB_TOKEN` no dispara workflows" no debería aplicarse. Igual hay que
**probarlo**: por eso el primer paso de la puesta en marcha es una semana en modo "solo mirar". Si no
dispara, el plan B está más abajo.

## Lo que hay hoy (comprobado el 26/10/2026 con la API de GitHub)

- El lector hace **un push por pasada con datos nuevos**, como mucho uno cada ~10 minutos (en un día
  normal, unos 70 commits en `datos`). Lo hace con el `GITHUB_TOKEN` del trabajo `leer`, que tiene
  `contents: write`.
- Pages está configurado en modo rama (`build_type: legacy`, rama `datos`, carpeta `/`). Cada push dispara
  el workflow interno **`pages-build-deployment`** (ID 379758940, evento `dynamic`, `head_branch: datos`,
  `head_sha` = el commit publicado). Esas corridas las hace **`github-pages[bot]`**, y también el
  *deployment* `github-pages` y sus estados (`waiting → queued → in_progress → success`).
- Desde el push hasta que el deploy queda en `success` pasan **unos 25 segundos**. Por ejemplo, el commit
  `bc3e821`: push a las 13:11:16, corrida de Pages de 13:11:19 a 13:11:42.
- Pages responde con `Cache-Control: max-age=600`, y la app baja `actual.json` sin ningún parámetro que
  esquive la caché. Justo después de un deploy la CDN respondió `X-Cache: MISS`, así que el deploy limpia
  la caché. La app espera 3 s y reintenta una vez antes de mostrar el genérico "hay novedades".
- La rama `datos` tiene solo `.nojekyll` y `data/`: **no hay workflows ahí**.
- `lector/avisos.py --commit <sha>` decide comparando ese commit con las versiones anteriores de
  `actual.json`. Por eso, **si nadie lanza `avisos.yml` para el commit donde el río sube a alerta, el
  siguiente commit (que sigue en alerta) ya no avisa.** Juntar varias publicaciones en "la última" perdería
  urgentes: hay que lanzar cada commit que cambió `actual.json`.

## Requisitos

| # | Requisito |
|---|---|
| R1 | Un lanzamiento de `avisos.yml` por cada commit de `datos` que cambió `data/actual.json`, con su SHA. |
| R2 | Que salga **después** de que Pages sirva ese dato (si no, la app muestra "hay novedades"). |
| R3 | Que no se pierda ningún urgente aunque Pages saltee o falle una publicación, o el disparo se demore. |
| R4 | Sin duplicados: dos publicaciones seguidas no lanzan dos veces el mismo commit, y una re-corrida no repite avisos. |
| R5 | Que el token que lanza workflows no conviva con el código que procesa datos de CARU. |
| R6 | Que `avisos.yml` siga corriendo desde `main` con `workflow_dispatch` (la condición de Google del paso 6 lo exige). |
| R7 | Dentro de los 15 minutos que pide la aceptación, con margen. |

## Opciones comparadas

| Opción | Separa el token (R5) | Espera a Pages (R2) | No pierde ni duplica (R3, R4) | Cambios | Demora típica | Mantenimiento | Veredicto |
|---|---|---|---|---|---|---|---|
| **(a)** `leer` lanza `gh workflow run` tras cada `subir()` | **No:** `actions: write` en el trabajo de CARU | Hay que agregarle a `leer` una espera que mire la URL | Bien si el lanzamiento no falla; si falla, ese commit se pierde (habría que reintentarlo dentro del bucle) | `lector.yml` | ~1–2 min | Ninguno | Funciona, pero agrega riesgo (ver abajo) |
| **(b1)** Trabajo aparte en `lector.yml` con `needs` y salidas | Sí | — | — | `lector.yml` | **~5 h**: `needs` espera a que `leer` termine | — | **Descartada**: llega tarde |
| **(b2)** `on: push` a `datos` | Sí | No, sale antes del deploy | — | Workflow en `datos` | — | — | **Descartada**: un push con `GITHUB_TOKEN` no dispara workflows (no hay ninguna corrida `push` en `datos`). Además, `on: push` lee el workflow **del commit empujado**, y en `datos` no hay ninguno: habría que ponerlo en la rama que escribe el lector. |
| **(b3)** `workflow_run` de `pages-build-deployment` (**recomendada**) | **Sí**: workflow propio, con trabajo de lanzar sin datos | **Sí**: llega cuando Pages terminó, y además se verifica la URL | Sí: cubre los huecos y revisa si ya se lanzó | Workflow nuevo + una línea en `avisos.yml` | ~1–2 min (+ la demora del evento) | Ninguno | **Recomendada**, si la prueba confirma que dispara |
| **(b4)** `deployment_status` del deploy de Pages | Sí | Sí, con `state == success` | Habría que cubrir huecos igual | Workflow en `datos` | ~1 min | — | **Descartada**: para este evento GitHub usa el workflow del **commit desplegado** (`datos`), donde no hay ninguno y no conviene que haya. |
| **(b5)** `page_build` | Sí | Casi: sale cuando termina el *build*, unos segundos antes del deploy | Habría que cubrir huecos | Workflow nuevo | ~1 min | — | **Peor que (b3)**: el build lo hizo el push de `github-actions[bot]` (`pusher` en la API), así que es probable que **no dispare** por la regla del `GITHUB_TOKEN` (sin probar). Y no garantiza que el deploy haya terminado. |
| **(b6)** `repository_dispatch` (o `workflow_dispatch`) con PAT *fine-grained* o GitHub App | **No**: el PAT o la clave de la App tendría que estar igual en `leer`, que es quien sabe cuándo publicó. La clave de una App es peor: con ella se fabrican tokens. | Igual que (a) | Igual que (a) | `lector.yml` + secreto | ~1–2 min | **Alto**: el PAT vence (o queda sin vencimiento, peor), está atado a la cuenta del dueño y hay que rotarlo; la App necesita clave privada, instalación y rotación | **Descartada**: es (a) con un secreto más. Con `repository_dispatch` directo a `avisos.yml`, además, `event_name` deja de ser `workflow_dispatch` y hay que aflojar la condición de Google. |
| **(b7)** Workflow con `schedule` que mire `datos` cada 5 min | Sí | Sí, si mira la URL | Cubre huecos si guarda por dónde iba | Workflow nuevo | **De 5 min a horas** | Bajo | **Descartada**: `lector.yml` ya documenta que el horario de GitHub se atrasa horas o no dispara. |
| **(b8)** Trabajo "vigía" **en paralelo** a `leer` dentro de `lector.yml` (sin `needs`), que mira `datos` cada 30 s | **Sí**: otra máquina con su propio token, sin código de CARU | Sí, mirando la URL | Sí, si guarda el último SHA lanzado | `lector.yml` | ~1 min | Medio: dos trabajos largos en la cadena | **Plan B** si (b3) no dispara |

## El riesgo extra de (a), sin vueltas

Hoy `leer` ya tiene `contents: write`: puede escribir lo que quiera en `datos` y también en `main` (salvo
`.github/workflows/`; ver "Otro hueco" más abajo). Y el aislamiento dentro del trabajo es débil: el lector corre con el mismo usuario, puede leer
`/proc/<pid>/environ` y tiene `sudo` (lo dice `lector.yml`). Así que **cualquier token que exista en ese
trabajo lo tiene, en la práctica, el código que procesa lo que manda CARU**. Y ese contenido es ajeno:
llega por **`http://` sin cifrar** (`190.0.152.194:8080`), así que lo puede alterar cualquiera en el camino
de red, no solo CARU. Pasa por `requests`, BeautifulSoup y pdfplumber (este último en un proceso aparte con
tope de tiempo y memoria, pero con el mismo usuario).

Qué **ya puede** hacer un atacante que tome control de `leer`: subir un `actual.json` falso (por ejemplo,
"evacuación"). La app lo muestra y la revisión local avisa sola en su próxima pasada. Para eso no hace
falta ningún permiso nuevo.

Qué **agrega** `actions: write` en ese trabajo:

| Con `actions: write` en `leer` se puede… | Gravedad |
|---|---|
| Lanzar `avisos.yml` con `prueba=false` **cuantas veces quiera** y para cualquier commit de `datos`, incluso viejos: urgentes reales a todos, al instante y repetidos. La marca compartida de la app frena repetir el mismo nivel, pero alternando datos falsos se pasa. | Alta: hoy un dato falso tarda lo que tarde la revisión local, y con esto llega en segundos |
| **Cancelar** corridas de `avisos.yml` (callar un urgente real) y **desactivar** workflows (`avisos.yml`, `tests.yml`). Lo desactivado **queda así** cuando el trabajo termina. | Alta: silencia avisos y persiste |
| **Borrar** corridas y sus registros: se pierde el rastro de lo que pasó | Media: complica entender un incidente |
| Borrar cachés y artefactos; lanzar `lector.yml` de más | Baja |

Lo que **no** agrega: no puede editar workflows (el `GITHUB_TOKEN` nunca tiene el permiso `workflows`), ni
leer secretos, ni pedir la credencial de Google (eso lo frena la condición del proveedor, que exige
`avisos.yml@main`, y `avisos.yml` no corre código de `datos`).

Conclusión: la probabilidad no es alta (hace falta una falla explotable en esas bibliotecas o un ataque en
la red hacia CARU), pero el permiso **convierte un dato falso en una alarma masiva inmediata y repetible, y
permite borrar la evidencia**. Si hay una alternativa que lo evita sin costo de mantenimiento, conviene
usarla. Eso es (b3).

**Riesgo que queda en todas las opciones:** quien pueda escribir en `datos` puede provocar **un** aviso
real con un dato falso, porque el aviso sale de lo publicado. Ninguna forma de lanzar lo evita. Lo acotan
otras cosas: correr el lector con un usuario sin privilegios (tanda pendiente, ver `lector.yml`), proteger
`main` y `datos` con reglas, y el diseño del push sin texto. Con (b3) el atacante logra **como mucho un
lanzamiento por commit nuevo**, no ráfagas, y no puede cancelar, desactivar ni borrar nada.

### Otro hueco, que hay que cerrar antes del paso 8: `leer` puede escribir en `main`

Dato de la revisión de credenciales: el ruleset `proteger-main` solo bloquea el borrado y el force-push,
**no exige PR**. El `contents: write` de `leer` vale para todo el repositorio. Si alguien toma control de
`leer`, puede subir a `main` un `lector/avisos.py` alterado. El `GITHUB_TOKEN` no puede tocar
`.github/workflows/`, pero `avisos.py` no está ahí, y es lo que corre el trabajo `decidir` de
`avisos.yml`. Un `avisos.py` alterado puede decir "urgente" con cualquier dato, incluso con el río normal.
El trabajo `enviar` vuelve a validar el formato de la decisión, pero no puede saber si la decisión es
verdadera. Esto pasa con cualquier opción de lanzamiento, porque toda corrida de `avisos.yml` usa el
`avisos.py` que haya en `main`.

Cómo queda cada opción frente a este hueco:

| Opción | ¿Lo empeora? |
|---|---|
| **(a)** `actions: write` en `leer` | **Sí, bastante.** El mismo proceso comprometido sube el `avisos.py` alterado **y** lanza `avisos.yml` al instante, cuantas veces quiera y con **`prueba=false` elegido por él**: se saltea la decisión del dueño de pasar a los temas reales. Con eso puede mandar urgentes falsos a todos, en ráfaga, aunque el río esté normal y aunque el dueño todavía esté en prueba. |
| **(b3)** recomendada | **No.** `lanzar-avisos.yml` no corre código de `main` (no hace checkout), así que el `avisos.py` alterado no le hace nada a él. Lo usaría la próxima corrida legítima de `avisos.yml`. Mientras no exista `AVISOS_REALES=true`, todo va a los temas `prueba-`, y esa variable no la puede tocar el `GITHUB_TOKEN`. Con la variable puesta, el atacante logra un urgente falso por cada commit nuevo que suba a `datos`: es el mismo techo que con un dato falso, sin ráfagas. |
| **(b6)** PAT o App en `leer` | **Sí**, igual que (a). |
| **(b8)** vigía (plan B) | **No**: igual que (b3). No corre código de `main` y toma `prueba` de la variable. |

**Mitigación (no aplicada; la decide y la hace el dueño):** agregar a `proteger-main` **"Require a pull
request before merging"**, con 0 aprobaciones y **sin bypass para GitHub Actions**, antes del paso 8. Así
el `GITHUB_TOKEN` de `leer` ya no puede subir a `main`. Tampoco puede abrir un PR, porque no tiene
`pull-requests: write`. Con esa regla, `avisos.py` solo cambia por un PR del dueño. **Hay que ponerla
elija la opción que elija**, y con (a) es imprescindible. Con eso, el hueco se reduce al de "dato falso en
`datos`" que ya está descrito arriba.

## El cambio aplicado

### 1. Workflow nuevo `.github/workflows/lanzar-avisos.yml`

El archivo es la referencia; acá va solo cómo está armado. Tiene tres trabajos, `permissions: {}` arriba y
ninguna acción de terceros (solo bash, git, jq, curl y gh del runner), así que no hay nada que fijar por
SHA.

| Trabajo | Permiso | Qué hace |
|---|---|---|
| `revisar` | `actions: read` | Valida lo que trae el evento (`head_sha`, `workflow_id` y `created_at`, con expresiones regulares). Busca la publicación anterior de Pages que salió bien y trae `datos` sin token. Lista los commits que cambiaron `data/actual.json` entre esa publicación y esta, con un tope de 12. Espera hasta 3 min a que `https://maticascov.github.io/rio-paysandu/data/actual.json` sirva ese `generado` o uno más nuevo. Escribe en el resumen de la corrida la lista, el estado de Pages y **cuántos segundos pasaron desde el commit**. |
| `lanzar` | `actions: write` (el único) | Sin checkout ni datos. Vuelve a validar cada SHA. **Si faltan `GCP_WIF_PROVIDER` o `GCP_SA_EMAIL`, no lanza nada** y deja en el resumen qué habría lanzado. Si están, salta los commits que ya tienen una corrida `Avisos <sha> prueba=<…>` y lanza `gh workflow run avisos.yml --ref main -f commit=<sha> -f prueba=<…>`. |
| `avisar` | `issues: write` | Si `revisar` o `lanzar` fallan, abre o comenta el issue "No se lanzaron los avisos" (etiqueta `avisos-falla`). |

Todo lo que viene de afuera (el evento, las variables, las salidas de `revisar`) entra a los `run:` por
`env:`, nunca con `${{ }}` dentro del script. La concurrencia es un grupo por commit publicado
(`lanzar-avisos-<head_sha>`), así dos publicaciones seguidas no se pisan ni se cancelan.

**Por qué `lanzar` no lanza mientras falte la identidad federada.** Sin esas variables, `avisos.yml` no
puede enviar nada: su trabajo `enviar` termina sin enviar o en error. Lanzarlo igual llenaría Actions con
unas 70 corridas inútiles por día, y si `avisos.yml` terminara en rojo enterraría las fallas de verdad.
Frenarlo en `lanzar` tiene tres ventajas:

- mira las mismas variables que usa `avisos.yml`, así que no hay que acordarse de prender nada aparte;
- deja la corrida en verde, con un aviso `notice` y el resumen de lo que habría lanzado, que es justo lo
  que hay que mirar en la semana de prueba;
- en cuanto el dueño termina el paso 6, empieza a lanzar solo, a los temas de prueba.

Costo: los commits publicados durante la semana sin variables no se lanzan nunca, porque cada corrida mira
solo desde la publicación anterior. Es lo esperado: son avisos viejos.

### 2. Una línea en `avisos.yml`

```yaml
run-name: Avisos ${{ inputs.commit }} prueba=${{ inputs.prueba }}
```

Es lo único que se tocó en `avisos.yml`, a propósito, para que el merge con los cambios de `enviar` que se
hacen en otra rama sea trivial. No cambia nada de lo que ve Google: `ref`, `workflow_ref`, `event_name` y
`run_attempt` siguen iguales.

### 3. Variables del repositorio (Settings → Secrets and variables → Actions → Variables)

| Variable | Sin definir | Con valor |
|---|---|---|
| `LANZAR_AVISOS` | El lanzador anda | `false`: **corta todo**. `revisar` ni arranca, así que no se lanza nada. |
| `AVISOS_REALES` | Todo va a los temas `prueba-` | `true`: temas reales. Cualquier otro valor cuenta como prueba. |
| `GCP_WIF_PROVIDER`, `GCP_SA_EMAIL` | "Solo mirar": no se lanza nada | Las crea el dueño en el paso 6. Con las dos, se lanza. |

Formas de cortar los avisos, de la más suave a la más fuerte:

1. borrar `AVISOS_REALES`: vuelve a los temas de prueba;
2. poner `LANZAR_AVISOS=false`: no se lanza nada;
3. Actions → "Lanzar avisos" → "Disable workflow";
4. quitar la cuenta de servicio del proveedor en Google Cloud.

Ninguna toca el lector ni los datos.

### 4. `lector.yml`: sin cambios

El trabajo `leer` sigue con `contents: write` y nada más.

## Cómo se cumple cada requisito

**R2, el push después de Pages:** `workflow_run` llega cuando `pages-build-deployment` terminó con
`success`, es decir, con el deploy hecho (el *deployment* pasa a `success` antes de que la corrida
termine). Igual, el paso "Esperar a que Pages sirva el dato" baja **la misma URL que usa la app** y compara
el campo `generado`: acepta el del commit o uno más nuevo (si ya salió otra publicación, la app va a
mostrar la más nueva, que está bien). Si en 3 minutos no aparece, lanza igual con un aviso en el registro,
porque callar un urgente es peor que el genérico. Límite honesto: el runner pregunta a un nodo de la CDN
en EE. UU. y el teléfono a otro (en la prueba respondió `EZE`, Buenos Aires). Como el deploy limpia la
caché en todos los nodos, la diferencia es de segundos, y la app ya espera 3 s y reintenta una vez.

**R3, no perder urgentes:**

- **Pages saltea o falla una publicación:** la próxima que sale bien lanza todos los commits del medio
  (desde la anterior que salió bien), del más viejo al más nuevo. Cada `avisos.yml` decide sobre su propio
  commit, igual que si se hubieran lanzado de a uno.
- **Pages caído mucho tiempo:** la app tampoco puede ver el dato. Cuando vuelve, se lanzan hasta los
  últimos 12 commits (~2 h); lo más viejo queda para la revisión local, con un aviso en el registro.
- **Falla `lanzar-avisos.yml`:** se abre un issue, y "Re-run failed jobs" recupera sin repetir.
- **El evento se demora:** GitHub a veces atrasa los `workflow_run` unos minutos. Con ~2 minutos de
  demora normal queda margen para los 15 de la aceptación.

**R4, sin duplicados:**

- **Dos publicaciones seguidas:** son dos corridas de Pages y dos de este workflow, cada una con su lista,
  y las listas no se pisan.
- **Mismo commit dos veces:** no corren a la vez (el grupo de concurrencia es por commit), y antes de
  lanzar se mira si ya hay una corrida de `avisos.yml` con ese commit en el nombre.
- **Re-corrida de `avisos.yml`:** la frena `run_attempt == 1`, como hoy.
- **Lanzamiento a mano para reintentar:** sigue funcionando. Quien lanza a mano lo hace a propósito.
- **Lo que no se cubre:** si alguien lanza a mano con el mismo commit y el mismo `prueba` **justo** a la
  vez que este workflow, pueden salir dos. La marca compartida de la app evita mostrar dos veces el mismo
  urgente.

**R5:** el token con `actions: write` existe solo en el trabajo `lanzar`, en otra máquina, sin checkout,
sin datos y sin dependencias. `revisar` toca datos (solo `git` y `jq`, sin ejecutar nada de `datos`) y
tiene solo `actions: read`.

**R6:** `gh workflow run avisos.yml --ref main` lanzado con el `GITHUB_TOKEN` sí crea la corrida
(`workflow_dispatch` es una de las dos excepciones a la regla del `GITHUB_TOKEN`; `lector.yml` ya lo usa
en `relanzar`).

## Límites y costos

- **API de GitHub:** el `GITHUB_TOKEN` tiene 1.000 pedidos por hora por repositorio. Cada corrida hace unos
  3 pedidos más uno por commit lanzado; con ~6 publicaciones por hora son menos de 50 por hora.
- **Builds de Pages:** en modo rama, GitHub tiene un límite blando de 10 builds por hora. El lector hace
  como mucho ~6. Si se pasa (por ediciones a mano en `datos`), Pages se atrasa, y la lista de huecos cubre
  lo que quede en el medio.
- **Minutos de Actions:** el repositorio es público, así que no se cobran. Son unas 140 corridas cortas
  por día (~30 s cada una) más las de `avisos.yml`.
- **Cadenas de `workflow_run`:** GitHub corta después de 3 niveles. Acá hay uno solo (Pages → este
  workflow); `avisos.yml` arranca por `workflow_dispatch` y no cuenta como otro nivel.
- **Commits que solo cambian el historial** (o umbrales editados a mano): no tocan `actual.json`, así que
  no lanzan nada.

## Semana de solo mirar y puesta en marcha

### Antes del merge (o junto con él)

0. **Exigir PR en `main`:** agregar "Require a pull request before merging" a `proteger-main`, con 0
   aprobaciones y sin bypass para GitHub Actions. Tiene que estar antes del paso 8 (ver "Otro hueco").

### Semana de solo mirar (sin `GCP_WIF_PROVIDER` / `GCP_SA_EMAIL`)

No hace falta configurar nada: mientras el paso 6 no esté hecho, `lanzar` no lanza.

**Después de la primera publicación del lector tras el merge** (como mucho unos 10 minutos), en Actions:

1. Al lado de "pages build and deployment" de ese commit aparece una corrida de **"Lanzar avisos"**, con
   evento `workflow_run` y el mismo commit. **Si no aparece en unos 5 minutos, `workflow_run` no dispara
   para Pages:** se pasa al plan B (más abajo). Se puede confirmar con
   `gh run list --workflow lanzar-avisos.yml --limit 5`.
2. La corrida está en verde, con `revisar` y `lanzar` hechos y `avisar` salteado.
3. En el resumen de la corrida (Summary):
   - "Publicación de Pages" tiene el mismo SHA que el commit de `datos`;
   - "Commits que cambiaron actual.json" trae normalmente uno solo, el mismo;
   - "Pages: ya sirve el dato (intento 1 de 18)", o un intento bajo;
   - "este trabajo arrancó: … (N s después del commit)": lo normal sería menos de 2 minutos;
   - "Lanzamiento: **no** (solo mirar…)", con la lista que habría lanzado.

**Durante la semana**, cada uno o dos días:

- **¿Hay una corrida "Lanzar avisos" por cada "pages build and deployment"?** Se puede comparar
  `gh run list --workflow lanzar-avisos.yml --limit 50` con
  `gh run list --workflow pages-build-deployment --limit 50`.
- **¿La demora sigue baja?** Anotar la más alta que aparezca.
- **¿Algún issue `avisos-falla`?** No tendría que haber ninguno.
- **Commits que solo cambian el historial:** tienen que decir "ninguno" y no lanzar nada.

Si todo esto da bien, `workflow_run` queda comprobado.

### Después

1. **Paso 6 (dueño):** identidad federada y variables `GCP_WIF_PROVIDER`, `GCP_SA_EMAIL` y
   `FIREBASE_PROJECT_ID`. Desde ese momento `lanzar` empieza a lanzar `avisos.yml` con `prueba=true`. En
   Actions aparecen corridas "Avisos <sha> prueba=true", casi todas con "no hay aviso que mandar" (río
   normal).
2. **Paso 8:** la prueba en los temas de prueba con el Redmi.
3. **Con el paso 8 aprobado:** crear `AVISOS_REALES=true`. Las corridas pasan a decir `prueba=false`.
4. **README (tarea 5):** cómo ver los envíos (Actions → "Lanzar avisos" y "Avisos push") y cómo cortarlos
   (la lista de arriba).

## Plan B si `workflow_run` no dispara: trabajo "vigía" en `lector.yml`

Un segundo trabajo en `lector.yml`, `vigilar`, **sin `needs`**, que corre en paralelo a `leer` durante el
mismo tiempo, en otra máquina. Tiene solo `actions: write` y no hace checkout del código ni instala nada.
Cada 30 s:

1. mira la punta de `datos` con `git ls-remote` (sin token);
2. si cambió, trae la historia y arma la lista de commits que cambiaron `actual.json` desde el último que
   lanzó;
3. espera la URL de Pages igual que arriba;
4. lanza `avisos.yml` por cada commit.

`relanzar` pasa a esperar a los dos (`needs: [leer, vigilar]`).

- **Ventajas:** separa el token de verdad (otra máquina, otro token) y no depende de cómo se comporte
  Pages.
- **Contras:** dos trabajos largos en la cadena, y el "último lanzado" vive en memoria, así que en el
  cambio de corrida hay que recuperarlo de los nombres de las corridas de `avisos.yml` (con el mismo
  `run-name`). Además, un cuelgue de `vigilar` frena la cadena hasta su `timeout-minutes`. Es más
  complejo que (b3), pero mejor que (a).

Si el dueño prefiere lo más simple y acepta el riesgo, **(a)** es una sola línea por publicación en
`leer`, después de `subir()` y de esperar la URL de Pages:
`gh workflow run avisos.yml --ref main -f commit="$(git -C publicado rev-parse HEAD)" -f prueba=…`, más
`actions: write` en `leer`. Con eso, los riesgos de la tabla de arriba quedan aceptados a sabiendas.

## Riesgos que quedan con la recomendación

- **Que GitHub cambie cómo dispara `workflow_run` para Pages**, o que Pages deje de usar
  `pages-build-deployment` (por ejemplo, si se pasa Pages a "GitHub Actions" con un workflow propio).
  Se nota porque `lanzar-avisos.yml` deja de correr. Habría que revisar las corridas de vez en cuando; un
  control automático ("hay commits en `datos` sin corrida de avisos") queda como mejora posible.
- **Un dato falso en `datos` produce un aviso real** (común a todas las opciones; ver más arriba).
- **Mientras `main` no exija PR**, un `leer` comprometido puede cambiar `lector/avisos.py` y hacer que la
  próxima corrida legítima mande un urgente falso (ver "Otro hueco").
- **Demoras de GitHub Actions** en horas pico: el urgente puede tardar unos minutos más; la revisión local
  sigue de respaldo.
- **Si Pages no muestra el dato en 3 minutos**, el push sale igual y algunos teléfonos pueden mostrar el
  genérico "hay novedades" hasta su próxima revisión.

## Lo que tiene que hacer el dueño después del merge

1. Exigir PR en `proteger-main` (0 aprobaciones, sin bypass para Actions), antes del paso 8.
2. Hacer la semana de solo mirar: revisar la primera corrida "Lanzar avisos" y, después, cada uno o dos
   días (ver "Semana de solo mirar"). Si no dispara, avisar para pasar al plan B.
3. Paso 6: identidad federada y sus variables. Desde ahí se lanza a los temas de prueba.
4. Paso 8 en los temas de prueba; con el paso aprobado, crear `AVISOS_REALES=true`.
5. Para cortar en cualquier momento: `LANZAR_AVISOS=false`, o desactivar el workflow en Actions.
