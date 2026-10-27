# Fase 4, paso 6: guía para la identidad federada (y tareas de los agentes)

Escrita el 21/10/2026 para retomar al día siguiente. Diseño completo en
[fase-4-avisos-push.md](fase-4-avisos-push.md); condición y permisos acordados en
[fase-4-informe-agente.md](fase-4-informe-agente.md) (sección "Paso 6").

> **Hecho el 26/10/2026** y aprobado por el Reality Checker. Pasos 1 a 7 en Google Cloud (rol
> `enviarAvisosFcm` con solo `cloudmessaging.messages.create`, pool `avisos-github`, proveedor `github`,
> cuenta `avisos-fcm@mi-rio-uy-8ca81.iam.gserviceaccount.com` sin claves); paso 8, las tres variables; paso 9,
> la corrida 40333610759 (intento 1) mandó un resumen a `prueba-resumen-paysandu`
> (`projects/mi-rio-uy-8ca81/messages/8578147430559888155`); paso 10, el intento 2 terminó en rojo con "No se
> envía: es una re-corrida".
>
> También el 26/10/2026, el ruleset `proteger-main` pasó a exigir pull request para entrar a `main` (0
> aprobaciones, sin bypass): `main` ya no acepta push directo.
>
> Paso 10b, también el 26/10/2026: desde la rama descartable `probar-wif`, la corrida 40334850975 (evento
> push) falló en el paso `auth` con `unauthorized_client`: "The given credential is rejected by the attribute
> condition." Google rechaza un carnet que no cumple la condición.
>
> También el 26/10/2026: **7b hecho** (registros de auditoría `DATA_READ` para `iam.googleapis.com` y
> `sts.googleapis.com`) y rama `probar-wif` borrada.
>
> **Queda pendiente:** verificar que los mensajes llegan al Redmi; se hace al pasar a los temas reales
> (paso 8 de `fase-4-avisos-push.md`).
>
> Lo de abajo queda como estaba al escribir la guía, salvo las notas del paso 4 y del paso 7.

## Dónde estamos

- Pasos 1 a 5 hechos: proyecto de Firebase `mi-rio-uy-8ca81`, prueba de entrega en el Redmi, app con avisos
  push en `main` (#13) y datos en la rama `datos` (#14, #15).
- `avisos.yml` ya existe en `main`, pero **no puede enviar**: le faltan la credencial de Google Cloud y tres
  variables del repositorio. Hoy, si se lanza, termina con el aviso "faltan las variables del repositorio".
- Nadie lanza `avisos.yml` todavía: el lector no lo llama. Eso es del paso 8 (ver la tarea 3).

**Objetivo del paso 6:** que `avisos.yml`, y **solo** `avisos.yml` corriendo desde `main`, pueda pedirle a
Google un permiso de 5 minutos para enviar mensajes de FCM, sin ninguna clave guardada en GitHub.

## Cómo funciona (en corto)

1. GitHub le da a cada corrida de un workflow un "carnet" firmado (token OIDC) que dice qué repositorio,
   qué rama, qué workflow y qué intento es.
2. En Google Cloud se crea un **pool** con un **proveedor** que acepta esos carnets **solo si** cumplen la
   condición de abajo.
3. Si el carnet pasa, Google deja usar una **cuenta de servicio** que solo tiene un permiso: enviar mensajes
   de FCM.

No hay contraseña ni archivo JSON que se pueda filtrar. Un fork, otra rama, otro workflow o una re-corrida
quedan afuera.

## Qué se crea

| Cosa | Nombre | Para qué |
|---|---|---|
| APIs | `iam`, `iamcredentials`, `sts`, `fcm` | Identidad federada y envío |
| Pool de identidades | `avisos-github` | Exclusivo para esto |
| Proveedor OIDC | `github` (en ese pool) | Acepta solo el carnet de `avisos.yml` en `main` |
| Rol propio | `enviarAvisosFcm` | Un único permiso: `cloudmessaging.messages.create` |
| Cuenta de servicio | `avisos-fcm@mi-rio-uy-8ca81.iam.gserviceaccount.com` | La que usa `avisos.yml`; sin claves |
| Variables del repositorio | `GCP_WIF_PROVIDER`, `GCP_SA_EMAIL`, `FIREBASE_PROJECT_ID` | Las lee `avisos.yml` (no son secretas) |

Datos fijos: proyecto `mi-rio-uy-8ca81`, número `993936321335`. Repositorio `MatiCascoV/rio-paysandu`, con
ID de repositorio `1412063651` y de dueño `141058604`, verificados con `gh api` el 21/10/2026.

**La condición del proveedor** está en [herramientas/paso6/proveedor.yaml](../herramientas/paso6/proveedor.yaml):

| Línea | Qué deja afuera |
|---|---|
| `repository_id == '1412063651'` y `repository_owner_id == '141058604'` | Otro repositorio con el mismo nombre, si este se borrara (los ID no se reusan) |
| `repository == 'MatiCascoV/rio-paysandu'` | Un fork; si el repositorio se renombra, falla cerrado |
| `ref == 'refs/heads/main'` | Cualquier otra rama (un PR o una rama de prueba con el workflow editado) |
| `workflow_ref == '…/avisos.yml@refs/heads/main'` | Cualquier otro workflow, aunque corra en `main` |
| `event_name == 'workflow_dispatch'` | Disparos por push, PR, horario, etc. |
| `run_attempt == '1'` | "Re-run jobs", que repetiría avisos ya enviados |
| `runner_environment == 'github-hosted'` | Máquinas propias (self-hosted) |

## Pasos (dueño, con guía)

Antes de empezar: hace falta la sesión de gcloud del dueño. Si `print-access-token` da error, volver a correr
el login (lo tiene que correr el dueño: a Claude no se lo permiten).

```powershell
$G = "$env:LOCALAPPDATA\google-cloud-sdk-zip\google-cloud-sdk\bin\gcloud.cmd"
& $G auth print-access-token > $null; if ($?) { 'sesión OK' } else { & $G auth login }
```

Los pasos 1 a 7 los puede pegar el dueño en PowerShell, o correrlos Claude con su OK explícito: son cambios
de permisos en su cuenta de Google.

**Desde qué carpeta.** Los pasos 3 y 4 usan los archivos `herramientas\paso6\*.yaml`, que hoy solo están en la
rama del PR #17. Lo normal es mergear primero el PR #17 y correr todo desde `C:\Users\matic\rio-paysandu`
después de un `git pull`. Si el PR todavía no está mergeado, correr desde el worktree de esa rama,
`C:\Users\matic\rio-paysandu-guia6`. Pegar todos los bloques en la **misma ventana** de PowerShell: los
comandos usan las variables `$G`, `$P`, `$N` y `$SA` que se definen acá.

```powershell
cd C:\Users\matic\rio-paysandu          # con el PR #17 mergeado
git switch main
git pull
# Si el PR #17 no está mergeado, en lugar de lo de arriba:
# cd C:\Users\matic\rio-paysandu-guia6

$G = "$env:LOCALAPPDATA\google-cloud-sdk-zip\google-cloud-sdk\bin\gcloud.cmd"
$P = 'mi-rio-uy-8ca81'
$N = '993936321335'
$SA = "avisos-fcm@$P.iam.gserviceaccount.com"
```

**Controles antes de empezar.** Tienen que dar exactamente esto; si no, **parar**:

```powershell
Test-Path herramientas\paso6\proveedor.yaml, herramientas\paso6\rol-enviar-fcm.yaml   # dos True
& $G projects describe $P --format="value(projectNumber)"                             # 993936321335
```

Si sale algún `False`, se está en la carpeta equivocada o falta el `git pull`. Si el número no es
`993936321335`, `$P` está mal escrito o la sesión de gcloud es de otra cuenta.

> **Nunca pegar la condición del proveedor a mano en la consola.** Las comillas simples y los `&&` se rompen
> en PowerShell y en cmd, y un error ahí puede dejar una condición distinta de la acordada. Siempre por el
> archivo, con `--flags-file` (paso 4).

**1. Activar las APIs** (si ya estaban, no cambia nada):

```powershell
& $G services enable iam.googleapis.com iamcredentials.googleapis.com sts.googleapis.com fcm.googleapis.com --project $P
```

**2. Confirmar que el permiso se puede usar en un rol propio.** Tiene que aparecer una sola fila,
`cloudmessaging.messages.create`:

```powershell
& $G iam list-testable-permissions "//cloudresourcemanager.googleapis.com/projects/$P" `
    --filter="name=cloudmessaging.messages.create" --format="table(name,stage,customRolesSupportLevel)"
```

Mirar la columna `CUSTOM_ROLES_SUPPORT_LEVEL`:
- vacía o `SUPPORTED`: seguir;
- `TESTING` o `NOT_SUPPORTED`: **parar** y avisar.

Si no sale ninguna fila, también **parar** y avisar. La alternativa, `roles/firebasecloudmessaging.admin`,
da más de lo necesario y hay que decidirla.

**3. Crear el rol propio:**

```powershell
& $G iam roles create enviarAvisosFcm --project $P --file=herramientas\paso6\rol-enviar-fcm.yaml
```

**4. Crear el pool y el proveedor:**

```powershell
& $G iam workload-identity-pools create avisos-github --project $P --location=global --display-name="GitHub avisos.yml"
& $G iam workload-identity-pools providers create-oidc github --project $P --location=global `
    --workload-identity-pool=avisos-github --display-name="GitHub Actions" `
    --flags-file=herramientas\paso6\proveedor.yaml
```

> **Visto el 26/10/2026:** con la condición escrita como bloque de varias líneas (`>-`) en
> `proveedor.yaml`, gcloud en Windows la rechazó con "token recognition error" después de cada `&&`. Por eso
> la condición va en **una sola línea** entre comillas dobles, como está ahora en
> `herramientas/paso6/proveedor.yaml`. La causa probable es un `\r` de fin de línea de Windows (CRLF) pegado
> después de cada `&&` (no se reprodujo); `.gitattributes` deja esos archivos con fin de línea LF.

**5. Crear la cuenta de servicio, sin claves, y darle solo el rol propio:**

```powershell
& $G iam service-accounts create avisos-fcm --project $P --display-name="avisos.yml (solo FCM)"
& $G projects add-iam-policy-binding $P --member="serviceAccount:$SA" --role="projects/$P/roles/enviarAvisosFcm" --condition=None
```

Si la segunda línea dice que la cuenta no existe, es que Google todavía no la terminó de crear: esperar unos
segundos y repetir **solo la segunda línea**.

**6. Dejar que el pool use esa cuenta.** Solo los carnets del repositorio `1412063651` que ya pasaron la
condición:

```powershell
& $G iam service-accounts add-iam-policy-binding $SA --project $P --role=roles/iam.workloadIdentityUser `
    --member="principalSet://iam.googleapis.com/projects/$N/locations/global/workloadIdentityPools/avisos-github/attribute.repository_id/1412063651"
```

**7. Revisar lo creado** (la salida es lo que verifica el Secrets & Credential Hygiene Engineer, tarea 1):

```powershell
& $G iam workload-identity-pools providers list --project $P --location=global --workload-identity-pool=avisos-github
& $G iam workload-identity-pools providers describe github --project $P --location=global --workload-identity-pool=avisos-github
& $G iam service-accounts get-iam-policy $SA --project $P
& $G iam service-accounts keys list --iam-account=$SA --managed-by=user   # tiene que salir vacío
& $G projects get-iam-policy $P --flatten="bindings[].members" --filter="bindings.members:$SA" --format="table(bindings.role)"
```

Lo esperado:
- En el pool, un solo proveedor: `github`.
- En el `describe` del proveedor:
  - `state: ACTIVE`;
  - `oidc.issuerUri: https://token.actions.githubusercontent.com`, **sin** `allowedAudiences`;
  - `attributeMapping` con 6 entradas (`google.subject`, `attribute.repository`, `attribute.repository_id`,
    `attribute.repository_owner_id`, `attribute.ref`, `attribute.workflow_ref`);
  - `attributeCondition`: la condición completa, las 8 cláusulas unidas por `&&` (gcloud puede mostrarla
    cortada en varias líneas; es una sola cadena), incluida `assertion.run_attempt == '1'`.
- La cuenta: un solo `roles/iam.workloadIdentityUser` para ese `principalSet`.
- Ninguna clave de usuario.
- En el proyecto, solo `projects/mi-rio-uy-8ca81/roles/enviarAvisosFcm`.

**7b. (Opcional) Registros de auditoría de los canjes de token.** Por defecto Google no guarda quién canjeó un
carnet por un token. Para poder revisarlo después, en la consola de Google Cloud (proyecto
`mi-rio-uy-8ca81`): **IAM y administración → Registros de auditoría**. Buscar estos tres servicios, marcarlos
y activar solo **"Lectura de datos"** (Data Read):

- Identity and Access Management (IAM) API
- IAM Service Account Credentials API
- Security Token Service API

El volumen es mínimo: unas pocas entradas por cada corrida de `avisos.yml`. Se ven en el Explorador de
registros.

**8. Variables del repositorio.** No son secretas: identifican, no autorizan. Las puede cargar Claude con
el OK del dueño:

```powershell
gh variable set FIREBASE_PROJECT_ID --repo MatiCascoV/rio-paysandu --body "mi-rio-uy-8ca81"
gh variable set GCP_SA_EMAIL --repo MatiCascoV/rio-paysandu --body "avisos-fcm@mi-rio-uy-8ca81.iam.gserviceaccount.com"
gh variable set GCP_WIF_PROVIDER --repo MatiCascoV/rio-paysandu --body "projects/993936321335/locations/global/workloadIdentityPools/avisos-github/providers/github"
```

**9. Prueba de punta a punta, en los temas de prueba.** El commit `e29d22a` ("Datos de CARU 21/10/2026 10:14",
en la historia de `datos`) hace que `avisos.py` decida un resumen con la estación (verificado el 21/10/2026):

```powershell
gh workflow run avisos.yml --ref main -f commit=e29d22ad23787bfb95bafb4ef78c7cec60f8a572 -f prueba=true
gh run list --workflow avisos.yml --limit 1
gh run watch <id de la corrida>
```

Lo esperado:
- `decidir` en verde, con "resumen (estacion)".
- `enviar` en verde, con el paso "Autenticar en Google Cloud" bien y el resumen de la corrida mostrando el
  nombre del mensaje de FCM (`projects/mi-rio-uy-8ca81/messages/…`).
- Si el Redmi tiene la app compilada con `TEMAS_PRUEBA=true`, el mensaje llega (`FLTFireMsgReceiver` en
  `adb logcat`), pero **no muestra notificación**: es un resumen de otro día y la app solo muestra el
  "Río hoy" del día. Es correcto.

Ese commit sirve unos 7 días, mientras esté entre los últimos 500 de `datos`. Para buscar otro que avise:

```powershell
git fetch origin datos
foreach ($c in (git log --format=%H origin/datos -n 80)) {
  $r = .\lector\.venv\Scripts\python.exe lector\avisos.py --commit $c
  if ($r -match '"avisar": true') { "$c $r"; break }
}
```

**10. Prueba en contra: la re-corrida.** En la página de esa corrida, tocar **"Re-run all jobs"**: tiene que
terminar en rojo, sin enviar nada, con el error "No se envía: es una re-corrida". Lo frena el control de
`run_attempt` del workflow (la credencial ni se pide). Esta prueba **no** pasa por Google: que la condición del
proveedor incluye `run_attempt == '1'` se verifica leyendo el `describe` del paso 7.

**10b. (Opcional) Prueba de que Google rechaza.** Para ver la condición del proveedor trabajando, se lanza desde
una rama descartable un workflow que solo intenta autenticarse, **sin enviar nada**. Como no corre en `main` ni
es `avisos.yml`, no coinciden `ref` ni `workflow_ref` y Google tiene que rechazarlo.

En la rama `probar-wif`, crear `.github/workflows/probar-wif.yml` con este contenido:

```yaml
# Prueba descartable: la credencial de avisos.yml NO tiene que funcionar desde acá.
# Solo autentica; no envía nada. Borrar la rama después.
name: probar-wif
on:
  push:
    branches: [probar-wif]
permissions:
  id-token: write
jobs:
  probar:
    runs-on: ubuntu-latest
    steps:
      - name: Autenticar en Google Cloud (tiene que fallar)
        uses: google-github-actions/auth@7c6bc770dae815cd3e89ee6cdf493a5fab2cc093 # v3.0.0
        with:
          workload_identity_provider: ${{ vars.GCP_WIF_PROVIDER }}
          service_account: ${{ vars.GCP_SA_EMAIL }}
          token_format: access_token
```

Correrlo desde `C:\Users\matic\rio-paysandu` (no desde el worktree `rio-paysandu-guia6`: ahí no se puede
cambiar a `main`):

```powershell
cd C:\Users\matic\rio-paysandu
git fetch origin
git switch -c probar-wif origin/main
# (crear el archivo de arriba)
git add .github\workflows\probar-wif.yml
git commit -m "Prueba descartable de la condición del proveedor"
git push -u origin probar-wif            # el push mismo lanza la prueba
gh run list --repo MatiCascoV/rio-paysandu --workflow probar-wif.yml --limit 1
gh run watch <id de la corrida> --repo MatiCascoV/rio-paysandu
```

Se lanza con `push` y no a mano porque GitHub solo deja lanzar a mano (`workflow_dispatch`) los workflows que
ya están en `main`. Además de `ref` y `workflow_ref`, tampoco coincide `event_name`.

Lo esperado: el paso de `auth` **falla** con `unauthorized_client` y un mensaje sobre la `attribute condition`.
Si en cambio pasa, **parar**: la condición no es la acordada (revisar el `describe` del paso 7) y desactivar el
proveedor (ver "Vuelta atrás").

Después, borrar la rama, en GitHub y en la PC:

```powershell
git switch main
git push origin --delete probar-wif
git branch -D probar-wif
```

### Si algo sale mal

| Síntoma | Causa probable |
|---|---|
| `enviar` dice "faltan las variables del repositorio" | Falta el paso 8 |
| `auth` falla con `unauthorized_client` / `attribute condition` | El carnet no cumple la condición: revisar que la corrida sea en `main`, `workflow_dispatch` y primer intento; comparar la condición con el `describe` del paso 7 |
| `auth` falla con `Permission 'iam.serviceAccounts.getAccessToken' denied` | Falta o está mal el paso 6 (el `principalSet` usa el **número** del proyecto, no el ID) |
| FCM responde 403 `PERMISSION_DENIED` | Falta el rol del paso 5, o el permiso del paso 2 no es el correcto |
| FCM responde 404 | `FIREBASE_PROJECT_ID` mal escrito |

**Vuelta atrás** (con `$G`, `$P` y `$SA` definidos como al principio de los pasos):

- **Corte inmediato:** desactivar la cuenta de servicio. Desde ese momento no se emite ningún token para ella,
  aunque el carnet pase la condición. Se revierte con `enable`.

  ```powershell
  & $G iam service-accounts disable $SA --project $P
  # para volver atrás: & $G iam service-accounts enable $SA --project $P
  ```

- Borrar las tres variables (`gh variable delete … --repo MatiCascoV/rio-paysandu`) deja a `avisos.yml` sin
  poder enviar.
- Para cortar del todo, desactivar también el proveedor:

  ```powershell
  & $G iam workload-identity-pools providers disable github --project $P --location=global --workload-identity-pool=avisos-github
  ```

## Tareas de los agentes para mañana

Según la tabla de `PROMPT_MAESTRO.md` (sección 1.b). Claude orquesta e integra. Ningún agente hace push,
merge, cambios en Google Cloud ni en la configuración de GitHub: eso lo hace Claude con el OK del dueño, o el
dueño. Los merges los hace el dueño (el filtro de permisos bloquea a Claude).

### Tarea 1: revisión de credenciales (Secrets & Credential Hygiene Engineer), solo lectura

- **Antes del paso 3:** revisar `herramientas/paso6/proveedor.yaml`, `herramientas/paso6/rol-enviar-fcm.yaml`
  y los comandos de esta guía contra el trabajo `enviar` de `.github/workflows/avisos.yml`.
- **Después del paso 7:** revisar la salida de los `describe` y `get-iam-policy`.
- **Criterio:** mínimo privilegio. Un solo permiso en el rol, ninguna clave de la cuenta, el `principalSet`
  acotado al ID del repositorio y la condición idéntica a la acordada.
- **Entrega:** lista de hallazgos (bloqueante, importante o menor), sin editar nada.

### Tarea 2: urgente de evacuación en dos mensajes (DevOps Automator)

Hoy el urgente de evacuación sale con una condición de FCM (`'alerta-…' in topics || 'evacuacion-…' in topics`).
En la prueba del 21/10 tardó **42 s**, contra menos de 1 s de un tema directo.

- **Cambio:** mandar dos mensajes con el mismo `data`, uno al tema de alerta y otro al de evacuación. Cada
  teléfono está en un solo tema urgente, así que nadie lo recibe dos veces.
- **Fallas:** decidir qué pasa si falla uno de los dos. Sin reintentos, como hoy; la corrida queda en rojo
  y el resumen dice cuál salió.
- **Archivos:** `.github/workflows/avisos.yml` (trabajo `enviar`), `herramientas/enviar_aviso_prueba.ps1`
  (igual que el workflow) y la tabla de mensajes de `docs/fase-4-avisos-push.md`.
- **No tocar:** `lector/`, `app/` ni la condición del proveedor.
- **Criterio:** `actionlint` sin errores. Los temas siguen saliendo de nombres fijos, con el prefijo `prueba-`
  salvo `prueba=false` explícito, solo datos y prioridad HIGH. Probado en los temas de prueba después del
  paso 9.

### Tarea 3: cómo lanza el lector a `avisos.yml` (DevOps Automator, solo propuesta)

Requisito del paso 8. El lector hace muchas publicaciones dentro de una corrida de 5 h, y los push hechos con
`GITHUB_TOKEN` no disparan otros workflows. Hay que proponer cómo se lanza `avisos.yml` con el SHA de cada
publicación en `datos`. Comparar al menos estas dos opciones:

- **(a)** el trabajo `leer` lanza `gh workflow run avisos.yml -f commit=<sha> -f prueba=…` después de cada
  `subir()`. Necesita `actions: write` en el mismo trabajo que corre el código de CARU: evaluar el riesgo
  extra.
- **(b)** otra forma que mantenga separado el token que lanza workflows. Por ejemplo, un trabajo o workflow
  aparte que vigile `datos`, o `repository_dispatch` con un token acotado.

En los dos casos, tener en cuenta que el push tiene que salir **después** de que GitHub Pages publique el
dato; si sale antes, la app muestra el genérico "hay novedades".

- **Entrega:** `docs/fase-4-lanzar-avisos.md` con la recomendación, los riesgos y el cambio exacto propuesto.
  Sin editar workflows. La decisión es del dueño.

### Tarea 4: revisión y verificación (Code Reviewer y luego Reality Checker)

- **Code Reviewer:** revisa el diff de la tarea 2.
- **Reality Checker:** aprueba el paso 6 con evidencia:
  - la corrida verde del paso 9, con el nombre del mensaje de FCM;
  - la re-corrida en rojo del paso 10, con el error "No se envía: es una re-corrida" y el paso de `auth`
    salteado (prueba el control del workflow, no la condición de Google);
  - la salida del paso 7, con `assertion.run_attempt == '1'` dentro de `attributeCondition`: esa es la
    evidencia de que Google también rechaza las re-corridas;
  - si se hizo el paso 10b, la corrida de `probar-wif.yml` con `auth` en rojo por la `attribute condition`.

  Si no aprueba, se corrige antes de seguir.

### Tarea 5: documentación (Technical Writer), al final

Cuando el paso 6 esté aprobado:
- README, sección "Estado": paso 6 hecho.
- Nueva sección corta "Avisos push": cómo ver los envíos (Actions → avisos.yml), cómo cortarlos (borrar
  variables o desactivar el proveedor) y qué hacer si fallan. Es parte del paso 9 del plan.

## Orden sugerido

1. Tarea 1, primera parte.
2. Pasos 1 a 8, con el dueño.
3. Tarea 1, segunda parte.
4. Paso 9, y después el paso 10 (y el 10b, si se hace).
5. Tarea 2 (puede ir en paralelo con la tarea 3, porque tocan archivos distintos).
6. Tarea 4.
7. Prueba de la tarea 2 en los temas de prueba.
8. Tarea 5.
9. Con la propuesta de la tarea 3 decidida por el dueño, sigue el paso 8.
