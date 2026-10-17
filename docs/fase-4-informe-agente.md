# Fase 4: informe del agente (pasos 2 y 7)

Fecha: 17/10/2026. Rama: `fase-4-lector-avisos` (sin merge ni PR contra `main`).

Alcance: paso 2 (margen al bajar de nivel) y paso 7 sin credenciales (`lector/avisos.py` y
`.github/workflows/avisos.yml`) de [fase-4-avisos-push.md](fase-4-avisos-push.md). No se tocó `main`,
`data/`, `app/`, `lector.yml`, la configuración del repositorio, secretos ni variables, y no se creó nada
en Google.

## Cambio de diseño (17/10/2026)

La decisión de avisos se rehízo con la especificación del dueño (ver "Qué notificaciones se mandan" en
[fase-4-avisos-push.md](fase-4-avisos-push.md)). Antes se avisaba en cada cambio de nivel (al subir y al
bajar) y cuando el pronóstico pasaba a superar un umbral. Ahora hay solo dos tipos:

- **Urgente:** cuando el nivel sube a `alerta` o a `evacuacion`. Las bajadas no avisan.
- **Resumen del día:** uno por día como máximo, solo en `atencion` o más; sale con la lectura de Prefectura
  del día o, si a las 10:00 no llegó, con la estación automática.

El pronóstico ya no genera ningún push: se quitó esa lógica y la opción `--umbrales` de `avisos.py`. El
mensaje pasa de un tema (`nivel-paysandu`) a tres (`alerta-`, `evacuacion-` y `resumen-paysandu`). El margen
al bajar (paso 2) no cambia.

Las secciones de abajo describen la versión nueva, con las correcciones de la revisión del 17/10/2026
(al final).

## Commits

| Commit | Qué |
|---|---|
| `58bab6a` | Margen al bajar de nivel en el lector (paso 2) |
| `1699d20` | `avisos.py`: decide si hay que mandar un aviso push (paso 7) |
| `d64f526` | Workflow `avisos.yml`: envío por FCM con identidad federada |
| `7d92d8f` | `avisos.yml`: decidir y enviar en trabajos separados |
| `66ca8a6` | `avisos.yml`: el comentario de concurrency dice cuándo se pierde un push |
| `aca3523` | Test del margen: la pasada intermedia retiene el nivel |
| `a14915f` | Avisos: urgente al subir a alerta/evacuación y resumen diario en crecida (rediseño) |
| `59a378c` | `avisos.py`: sin aviso si el commit no cambió `actual.json`, y error si la historia no alcanza |
| `37fdb29` | `avisos.yml`: concurrency por commit, sin envío en re-corridas y token sin exportar |

## Margen al bajar (paso 2)

- `margen_bajada_m: 0.05` en `lector/config.json`. Para pasar a un nivel menor que el publicado antes, la
  altura tiene que quedar 5 cm o más por debajo del umbral (justo 5 cm ya baja); al subir, sin margen.
  Puede bajar varios niveles de una, solo hasta donde lo permita el margen.
- `nivel_con_margen` en `lector/nivel.py`: compara en milímetros enteros (en flotante 4,34 + 0,05 no da
  4,39 justo). Se aplica antes de la retención por salto, contra el `nivel` publicado en el `actual.json`
  anterior (aunque esté retenido). Sin nivel anterior con dato (primer arranque, `sin_dato`), sin margen.
- `main()` valida el margen: número de 0 a 0,5 m (0 lo desactiva); si no, código 1.
- Documentado en el README ("Cómo trabaja cada pasada"). Tests en `lector/tests/test_margen.py`.

## Qué decide `avisos.py`

| Caso | Urgente | Resumen |
|---|---|---|
| Sube a `alerta` o a `evacuacion` (desde un nivel menor con dato) | Sí (`alerta` o `evacuacion`) | — |
| Baja, sigue igual, o normal → atención | No | — |
| Entra o sale de `sin_dato` sin subir respecto del último nivel con dato, o sin anterior con dato | No | — |
| El commit no cambió `data/actual.json` (solo historial) | No | No |
| Nivel `normal` | No | No |
| `atencion` o más, llegó la lectura de Prefectura del día, y todavía no hubo resumen hoy | — | Sí (`prefectura`) |
| `atencion` o más, desde las 10:00 sin Prefectura del día, y todavía no hubo resumen hoy | — | Sí (`estacion`) |
| Ya hubo resumen hoy | — | No |
| `generado` inválido | — | No |
| Pronóstico (cualquiera) | No | No |

Las horas son de Uruguay (UTC-3 fija). "Ya hubo resumen hoy" se calcula mirando las publicaciones anteriores
del mismo día, sin guardar estado. Urgente y resumen pueden salir en la misma pasada.

CLI: `python lector/avisos.py ANTERIOR.json NUEVO.json` o `python lector/avisos.py --commit <sha>` (recorre
hasta 200 versiones de `data/actual.json` hacia atrás, tanto para el nivel anterior con dato como para las
publicaciones del mismo día; con publicaciones cada 5 minutos o más, 200 versiones son más de 16 h, así que
el recorrido del día no se corta antes del primer resumen posible). Con `--commit`, si el commit no cambió
`data/actual.json` no avisa nada, y si la historia es poco profunda y el recorrido llega al borde sin
terminar, sale con 2. Imprime una línea JSON
(`avisar`, `urgente`, `resumen`, `fuente`, `motivo`) y, en GitHub Actions, escribe `avisar`, `urgente`,
`resumen` y `fuente` en `GITHUB_OUTPUT`. Código 0 si decidió, 2 si no pudo.

## `avisos.yml`

- Solo `workflow_dispatch` (entradas `commit`, SHA de 40 caracteres, y `prueba`, por defecto `true`).
- `permissions: {}` arriba. Trabajo `decidir`: `contents: read`; valida el commit, exige que esté en
  `origin/main` (o en la futura rama `datos`) y corre `avisos.py --commit` (solo biblioteca estándar,
  sin pip). Trabajo `enviar`: `id-token: write`, sin checkout ni código del
  repo; si faltan `vars.GCP_WIF_PROVIDER`, `vars.GCP_SA_EMAIL` o `vars.FIREBASE_PROJECT_ID` termina sin
  enviar y lo dice en el resumen; si están, se autentica con `google-github-actions/auth` (OIDC, scope
  `firebase.messaging`, 300 s, sin archivo de credenciales) y manda a FCM HTTP v1 mensajes solo de datos:
  primero el urgente (si hay; prioridad `HIGH`, al tema `alerta-paysandu` o a la condición de evacuación) y
  después el resumen (si hay; prioridad `NORMAL`, al tema `resumen-paysandu`). Con `prueba`, los temas
  llevan el prefijo `prueba-`. Cada uno se manda una vez sin reintentos; si uno falla, igual intenta el otro
  y el trabajo termina con error.
- Acciones fijadas por SHA: checkout v5.1.0, setup-python v6.3.0 (las mismas del repo) y
  google-github-actions/auth v3.0.0 (`7c6bc770dae815cd3e89ee6cdf493a5fab2cc093`, verificado con
  `git ls-remote`). actionlint 1.7.12 con shellcheck: sin errores.
- No se probó en GitHub Actions ni contra FCM: falta el paso 6 y no está conectado al lector.

## Pruebas

`python -m pytest -q` desde la raíz (Python 3.12, dependencias instaladas con
`pip install --require-hashes --only-binary=:all: -r lector/requirements.txt -r lector/requirements-dev.txt`):

<!-- TESTS -->

(La versión anterior daba `240 passed`; ese número ya no vale para el rediseño.)

## Decisiones que tomé por mi cuenta

1. **Búsqueda hacia atrás en modo git:** si el `actual.json` anterior está en `sin_dato`, `avisos.py`
   busca (hasta 200 versiones) el último nivel con dato. Así una caída de la fuente no avisa, pero tampoco
   hace perder una subida real al volver.
2. **Dos trabajos en `avisos.yml`** en lugar de uno: el código que lee datos no puede pedir un token
   OIDC y el que tiene la credencial no corre nada del repositorio.
3. **`prueba` por defecto `true`**, y cualquier valor distinto de `false` va al tema de prueba.
4. **Envío sin reintentos** (un reintento tras un corte podría duplicar el aviso).
5. **Desde una rama distinta de `main`** el workflow decide pero no se autentica (warning, termina bien).
6. **Margen 0–0,5 m validado** en `main()` con código 1.

## Observaciones de la revisión

Siguen vigentes:

- **Concurrency:** desde la revisión del 17/10 hay un grupo por commit, así que una corrida de otro commit
  (o una prueba a mano) ya no cancela la que esperaba. Si un envío falla no hay reintentos (queda la
  revisión local), y una re-corrida no envía.
- **Margen después de `sin_dato`:** el lector no aplica margen si el anterior es `sin_dato`, pero
  `avisos.py` busca hacia atrás. Tras una caída larga (más de 48 h) o umbrales inválidos con el río
  justo en el umbral, el nivel puede bajar sin margen y volver a subir. Como las bajadas ya no avisan, lo
  único que puede pasar es **un urgente de más** si el río vuelve a subir. Es raro; arreglarlo pide guardar
  el último nivel con dato en `actual.json` (cambia el contrato, sección 5).

Resueltas por el cambio de diseño (el pronóstico ya no avisa):

- ~~Un push de tipo `pronostico` no mostraba nada en la app.~~
- ~~Pronóstico sin histéresis: informes que alternan 4,40 / 4,38 / 4,40 daban dos avisos.~~
- ~~Caso raro: con el anterior inmediato ilegible se podía repetir un aviso de pronóstico.~~

## Pendiente para el dueño

| Paso | Qué |
|---|---|
| 1 | Proyecto de Firebase "Mi Río UY", registrar `uy.miriouy.app`, `google-services.json`, sin Analytics. |
| 3 | Prueba de entrega en el Redmi con la app cerrada (decide si sirve el mensaje solo de datos). |
| 4 | App: pestaña Avisos, suscripción a los tres temas según preferencias, manejador en segundo plano, `revisarNivel` con las mismas reglas y marcas compartidas; decidir si se muestran urgente y resumen cuando llegan juntos. |
| 5 | Mover los datos a la rama `datos` y GitHub Pages a esa rama. |
| 6 | Identidad federada (ver abajo) y las tres variables del repositorio. |
| 8 | Prueba completa en el tema de prueba y una semana en el real. Antes, lanzar `avisos.yml` desde `lector.yml` (trabajo aparte con `actions: write`, `--ref main`, `commit` y `prueba=false`). |

Paso 6, condición recomendada para el proveedor (emisor `https://token.actions.githubusercontent.com`):

```
assertion.repository_id == '1412063651' &&
assertion.repository_owner_id == '141058604' &&
assertion.repository == 'MatiCascoV/rio-paysandu' &&
assertion.ref == 'refs/heads/main' &&
assertion.workflow_ref == 'MatiCascoV/rio-paysandu/.github/workflows/avisos.yml@refs/heads/main' &&
assertion.event_name == 'workflow_dispatch' &&
assertion.run_attempt == '1' &&
assertion.runner_environment == 'github-hosted'
```

`run_attempt == '1'` hace que la credencial rechace las re-corridas ("Re-run jobs"), que repetirían avisos
ya enviados; para reintentar hay que lanzar el workflow de nuevo a propósito.

Mapeo: `google.subject=assertion.sub` y `attribute.repository`, `attribute.repository_id`,
`attribute.repository_owner_id`, `attribute.ref`, `attribute.workflow_ref`. Cuenta de servicio: un rol
propio con solo `cloudmessaging.messages.create` (confirmarlo en la consola; `roles/firebasecloudmessaging.admin`
solo si no queda otra) y `roles/iam.workloadIdentityUser` sobre la cuenta para
`principalSet://iam.googleapis.com/projects/<número>/locations/global/workloadIdentityPools/<pool>/attribute.repository_id/1412063651`,
en un pool exclusivo para esto. Variables:
`GCP_WIF_PROVIDER` (`projects/<número>/locations/global/workloadIdentityPools/<pool>/providers/<proveedor>`),
`GCP_SA_EMAIL` y `FIREBASE_PROJECT_ID`. Los IDs numéricos salen de la API pública de GitHub; verificarlos.

## Agentes

Orquesté e integré yo. Data Engineer: margen y sus tests. API Tester: `avisos.py` y sus tests. DevOps
Automator: `avisos.yml`. Secrets & Credential Hygiene Engineer: revisión de credenciales y separación en
dos trabajos. Code Reviewer: sin bloqueantes; corregí el comentario de concurrency y el resto quedó
anotado arriba. Reality Checker: aprobado con evidencia (pytest, actionlint, CLI probado a mano).
