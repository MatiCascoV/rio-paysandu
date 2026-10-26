# Fase 4: cómo se lanza `avisos.yml` después de cada publicación

Propuesta para la tarea 3 del paso 6 (requisito del paso 8). **Nada de esto está aplicado:** no se tocó
ningún workflow ni código. La decisión es del dueño.

Fecha: 26/10/2026.

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

## El cambio propuesto

### 1. Workflow nuevo `.github/workflows/lanzar-avisos.yml`

```yaml
name: Lanzar avisos

# Cuándo corre: cuando GitHub Pages termina de publicar un commit de la rama datos
# (workflow interno "pages-build-deployment"). Ver docs/fase-4-lanzar-avisos.md.
#
# Qué hace: lanza avisos.yml una vez por cada commit de datos que cambió
# data/actual.json desde la publicación anterior de Pages que salió bien. Casi
# siempre es uno solo; si Pages salteó o falló alguna, también lanza esos, porque
# lector/avisos.py compara cada commit con el anterior y un commit sin lanzar
# perdería su urgente.
#
# Por qué acá y no en lector.yml: así el trabajo que procesa lo que manda CARU
# sigue sin poder lanzar workflows. "revisar" lee datos pero solo puede leer la API;
# "lanzar" puede lanzar workflows pero no trae el repositorio ni datos: solo recibe
# SHAs ya validados.
#
# workflow_run siempre usa este archivo tal como está en main.

on:
  workflow_run:
    workflows: ["pages-build-deployment"]
    types: [completed]

permissions: {}

# Un grupo por commit (no uno solo): GitHub deja una sola corrida en espera por
# grupo y cancela la anterior, y eso perdería commits. Las listas de dos corridas
# no se pisan (cada una va desde la publicación anterior hasta la suya).
concurrency:
  group: lanzar-avisos-${{ github.event.workflow_run.head_sha }}
  cancel-in-progress: false

jobs:
  revisar:
    # Solo publicaciones que salieron bien, de la rama datos de este mismo repositorio.
    if: >-
      github.event.workflow_run.conclusion == 'success' &&
      github.event.workflow_run.head_branch == 'datos' &&
      github.event.workflow_run.head_repository.full_name == github.repository
    runs-on: ubuntu-latest
    timeout-minutes: 8
    permissions:
      actions: read # listar las corridas de pages-build-deployment
    outputs:
      commits: ${{ steps.lista.outputs.commits }}
      pages: ${{ steps.pages.outputs.pages }}
    env:
      URL_ACTUAL: https://maticascov.github.io/rio-paysandu/data/actual.json # la misma que usa la app
      MAX_COMMITS: "12" # unas 2 horas de publicaciones
    steps:
      - name: Armar la lista de commits a lanzar
        id: lista
        env:
          GH_TOKEN: ${{ github.token }}
          REPO: ${{ github.repository }}
          ACTUAL: ${{ github.event.workflow_run.head_sha }}
          ID_PAGES: ${{ github.event.workflow_run.workflow_id }}
          CREADA: ${{ github.event.workflow_run.created_at }}
          GIT_TERMINAL_PROMPT: "0"
        run: |
          # Lo que llega del evento se valida antes de usarlo.
          [[ "$ACTUAL" =~ ^[0-9a-f]{40}$ ]] || { echo "::error::head_sha inválido"; exit 1; }
          [[ "$ID_PAGES" =~ ^[0-9]+$ ]] || { echo "::error::workflow_id inválido"; exit 1; }
          [[ "$CREADA" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] \
            || { echo "::error::created_at inválido"; exit 1; }
          [[ "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo "::error::repositorio inválido"; exit 1; }

          # Publicación anterior de Pages que salió bien (la más nueva antes de esta).
          anterior=$(gh api "repos/$REPO/actions/workflows/$ID_PAGES/runs?branch=datos&status=success&per_page=50" \
            --jq "[.workflow_runs[] | select(.created_at < \"$CREADA\")] | sort_by(.created_at) | last | .head_sha // empty") \
            || anterior=""

          # Historia de datos, sin token: el repositorio es público. No se corre nada
          # de lo que trae: solo git log y git show de un JSON.
          git init --quiet datos && cd datos
          timeout 60 git fetch --quiet --no-tags --depth=300 "https://github.com/$REPO.git" \
            "+refs/heads/datos:refs/remotes/origin/datos"
          if ! git merge-base --is-ancestor "$ACTUAL" origin/datos 2>/dev/null; then
            echo "::error::El commit $ACTUAL no está en datos (o está a más de 300 commits de la punta)"
            exit 1
          fi

          if [[ "$anterior" =~ ^[0-9a-f]{40}$ ]] && git merge-base --is-ancestor "$anterior" "$ACTUAL" 2>/dev/null; then
            # Del más viejo al más nuevo; solo los que cambiaron actual.json.
            mapfile -t lista < <(git rev-list --reverse "$anterior..$ACTUAL" -- data/actual.json)
          else
            echo "::warning::No se encontró la publicación anterior de Pages: se mira solo este commit"
            lista=()
            if [ "$(git log -1 --format=%H "$ACTUAL" -- data/actual.json)" = "$ACTUAL" ]; then
              lista=("$ACTUAL")
            fi
          fi

          if [ "${#lista[@]}" -gt "$MAX_COMMITS" ]; then
            echo "::warning::Hay ${#lista[@]} commits sin lanzar; se lanzan solo los últimos $MAX_COMMITS"
            lista=("${lista[@]: -$MAX_COMMITS}")
          fi
          echo "commits=${lista[*]}" >> "$GITHUB_OUTPUT"
          echo "Commits a lanzar: ${lista[*]:-(ninguno: esta publicación no cambió actual.json)}"

      # El evento ya dice que Pages terminó; esto confirma que la URL pública sirve el
      # dato (o uno más nuevo) antes de mandar el push, para que la app no muestre
      # "hay novedades". Si en 3 minutos no aparece, se lanza igual: es peor callar
      # un urgente que mostrar el genérico.
      - name: Esperar a que Pages sirva el dato
        id: pages
        if: steps.lista.outputs.commits != ''
        env:
          ACTUAL: ${{ github.event.workflow_run.head_sha }}
        run: |
          cd datos
          a_epoca() {  # fecha ISO con offset -> segundos, o vacío si no tiene ese formato
            [[ "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}([+-][0-9]{2}:[0-9]{2}|Z)$ ]] \
              && date -d "$1" +%s 2>/dev/null
          }
          esperado=$(a_epoca "$(git show "$ACTUAL:data/actual.json" | jq -r '.generado // empty' 2>/dev/null | head -c 40)")
          if [ -z "$esperado" ]; then
            echo "::warning::El actual.json del commit no trae una fecha generado válida; no se puede verificar Pages"
            echo "pages=sin_verificar" >> "$GITHUB_OUTPUT"; exit 0
          fi
          for intento in $(seq 1 18); do  # 18 x 10 s = 3 minutos
            servido=$(a_epoca "$(curl -fsS --max-time 10 "$URL_ACTUAL" | jq -r '.generado // empty' 2>/dev/null | head -c 40)")
            if [ -n "$servido" ] && [ "$servido" -ge "$esperado" ]; then
              echo "Pages ya sirve el dato (intento $intento)"
              echo "pages=publicado" >> "$GITHUB_OUTPUT"; exit 0
            fi
            sleep 10
          done
          echo "::warning::Pages no mostró el dato nuevo en 3 minutos; se lanza igual"
          echo "pages=sin_confirmar" >> "$GITHUB_OUTPUT"

  # Trabajo aparte: el único con permiso de lanzar workflows. Sin checkout, sin
  # datos, sin acciones de terceros: solo gh y bash del runner.
  lanzar:
    needs: revisar
    if: needs.revisar.outputs.commits != ''
    runs-on: ubuntu-latest
    timeout-minutes: 5
    permissions:
      actions: write # lanzar avisos.yml (incluye leer sus corridas)
    steps:
      - name: Lanzar avisos.yml por cada commit
        env:
          GH_TOKEN: ${{ github.token }}
          REPO: ${{ github.repository }}
          COMMITS: ${{ needs.revisar.outputs.commits }}
          # Temas reales solo si el dueño pone la variable del repositorio
          # AVISOS_REALES=true. Sin ella (o con cualquier otro valor), temas de prueba.
          REALES: ${{ vars.AVISOS_REALES }}
        run: |
          if [ "$REALES" = "true" ]; then prueba=false; else prueba=true; fi
          read -r -a lista <<< "$COMMITS"
          if [ "${#lista[@]}" -gt 12 ]; then echo "::error::Demasiados commits"; exit 1; fi

          # Para no lanzar dos veces el mismo commit (re-corrida de este workflow, o
          # alguien que lo lanzó a mano): avisos.yml pone el commit en el nombre de
          # la corrida (run-name). Si la lista falla, se sigue sin esta revisión: las
          # listas de dos corridas no se pisan, así que lo normal es que no haya repetidos.
          titulos=$(gh api "repos/$REPO/actions/workflows/avisos.yml/runs?per_page=100" \
            --jq '.workflow_runs[].display_title') || titulos=""

          fallos=0
          for commit in "${lista[@]}"; do
            if ! [[ "$commit" =~ ^[0-9a-f]{40}$ ]]; then
              echo "::error::Commit inválido en la lista"; exit 1
            fi
            if grep -qxF "Avisos $commit prueba=$prueba" <<< "$titulos"; then
              echo "Ya hay una corrida de avisos.yml para $commit (prueba=$prueba): no se lanza otra"
              continue
            fi
            if gh workflow run avisos.yml --repo "$REPO" --ref main \
                 -f commit="$commit" -f prueba="$prueba"; then
              echo "Lanzado avisos.yml para $commit (prueba=$prueba)"
            else
              echo "::error::No se pudo lanzar avisos.yml para $commit"
              fallos=$((fallos + 1))
            fi
          done
          [ "$fallos" -eq 0 ]

  # Si algo falló, un issue (como "avisar" en lector.yml): puede haber un urgente sin
  # lanzar. Para recuperarlo alcanza con "Re-run failed jobs": la revisión de nombres
  # de corrida evita repetir los commits que ya salieron.
  avisar:
    needs: [revisar, lanzar]
    if: failure()
    runs-on: ubuntu-latest
    timeout-minutes: 5
    permissions:
      issues: write
    steps:
      - name: Abrir o comentar el issue "No se lanzaron los avisos"
        env:
          GH_TOKEN: ${{ github.token }}
          ETIQUETA: avisos-falla
        run: |
          corrida="$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID"
          cuerpo="La corrida $corrida de Lanzar avisos falló: puede haber un aviso que no salió. Revisá el registro y, si corresponde, usá Re-run failed jobs. La revisión local de la app sigue de respaldo."
          gh label create "$ETIQUETA" --repo "$GITHUB_REPOSITORY" --color B60205 \
            --description "Falla al lanzar avisos push" 2>/dev/null || true
          numero=$(gh issue list --repo "$GITHUB_REPOSITORY" --state open --label "$ETIQUETA" \
            --json number --jq '.[0].number // empty')
          if [ -n "$numero" ]; then
            gh issue comment "$numero" --repo "$GITHUB_REPOSITORY" --body "$cuerpo"
          else
            gh issue create --repo "$GITHUB_REPOSITORY" --title "No se lanzaron los avisos" \
              --label "$ETIQUETA" --body "$cuerpo"
          fi
```

### 2. Una línea en `avisos.yml`: el commit en el nombre de la corrida

```diff
 name: Avisos push
+# El nombre de cada corrida lleva el commit: así lanzar-avisos.yml sabe si ya se
+# lanzó y en la pestaña Actions se ve qué publicación avisó cada una.
+run-name: Avisos ${{ inputs.commit }} prueba=${{ inputs.prueba }}
```

No cambia nada de lo que ve Google: `ref`, `workflow_ref`, `event_name` y `run_attempt` siguen iguales,
así que la condición del proveedor del paso 6 queda tal cual.

### 3. Variable del repositorio `AVISOS_REALES`

Mientras no exista, todo va a los temas `prueba-`. Para pasar a los temas reales (después de la semana del
paso 8), el dueño la crea con valor `true` en Settings → Secrets and variables → Actions → Variables. Para
volver a los de prueba, la borra. No hace falta tocar código.

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

## Puesta en marcha propuesta (en orden)

0. **Antes del paso 8, sea cual sea la opción:** el dueño agrega "Require a pull request before merging"
   a `proteger-main` (ver "Otro hueco").
1. **Modo "solo mirar", una semana:** subir `lanzar-avisos.yml` con el trabajo `lanzar` desactivado
   (`if: false`). Hay que comprobar que **corre una vez por cada publicación de Pages**, con el `head_sha`
   correcto, y medir cuánto tarda desde el push. Esto confirma lo único que no está comprobado. Si no
   corre nunca, se pasa al plan B.
2. Agregar `run-name` a `avisos.yml` y activar `lanzar` **sin** `AVISOS_REALES`: todo va a los temas
   `prueba-`. Esto coincide con la prueba del paso 8.
3. Con el paso 8 aprobado, el dueño crea `AVISOS_REALES=true`.
4. Actualizar `docs/fase-4-avisos-push.md` (dice que `avisos.yml` "se lanza desde el workflow del lector")
   y el README (tarea 5): cómo cortar los avisos (borrar `AVISOS_REALES`, o desactivar `lanzar-avisos.yml`
   en Actions).

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

## Lo que tiene que decidir el dueño

1. ¿(b3) con la semana de "solo mirar", o directamente (a) aceptando el riesgo?
2. Si (b3) no dispara: ¿plan B (vigía) o (a)?
3. El tope de commits por lanzamiento (12, unas 2 horas) y la espera máxima de Pages (3 minutos).
4. Usar la variable `AVISOS_REALES` para pasar a los temas reales.
5. Exigir PR en `proteger-main` (0 aprobaciones, sin bypass para Actions) antes del paso 8.
