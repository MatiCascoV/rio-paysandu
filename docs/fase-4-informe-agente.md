# Fase 4: informe del agente (pasos 2 y 7)

Fecha: 17/10/2026. Rama: `fase-4-lector-avisos` (sin merge ni PR contra `main`).

Alcance: paso 2 (margen al bajar de nivel) y paso 7 sin credenciales (`lector/avisos.py` y
`.github/workflows/avisos.yml`) de [fase-4-avisos-push.md](fase-4-avisos-push.md). No se tocó `main`,
`data/`, `app/`, `lector.yml`, la configuración del repositorio, secretos ni variables, y no se creó nada
en Google.

## Commits

| Commit | Qué |
|---|---|
| `58bab6a` | Margen al bajar de nivel en el lector (paso 2) |
| `1699d20` | `avisos.py`: decide si hay que mandar un aviso push (paso 7) |
| `d64f526` | Workflow `avisos.yml`: envío por FCM con identidad federada |
| `7d92d8f` | `avisos.yml`: decidir y enviar en trabajos separados |
| `66ca8a6` | `avisos.yml`: el comentario de concurrency dice cuándo se pierde un push |
| `aca3523` | Test del margen: la pasada intermedia retiene el nivel |

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

| Caso | ¿Avisa? | Tipo |
|---|---|---|
| Cambio de nivel con dato en las dos publicaciones (sube o baja) | Sí | `nivel` |
| Mismo nivel, pronóstico sin cambio de categoría | No | — |
| Entra o sale de `sin_dato`, nivel desconocido o mal formado | No | — |
| Sin publicación anterior (o ilegible) | No | — |
| Pronóstico vigente que pasa a superar alerta | Sí | `pronostico` |
| Pronóstico vigente que pasa a superar evacuación (desde nada o desde alerta) | Sí | `pronostico` |
| Pronóstico que baja, sigue igual o no está vigente | No | — |
| Umbrales inválidos | Solo puede avisar por nivel | `nivel` |
| Cambio de nivel y de pronóstico a la vez | Sí | `nivel` |

CLI: `python lector/avisos.py ANTERIOR.json NUEVO.json [--umbrales RUTA]` o
`python lector/avisos.py --anterior <commit> [--nuevo <commit>]`. Imprime la decisión en JSON y, en
GitHub Actions, escribe `avisar` y `tipo` en `GITHUB_OUTPUT`. Código 0 si decidió, 2 si no pudo.

## `avisos.yml`

- Solo `workflow_dispatch` (entradas `commit`, SHA de 40 caracteres, y `prueba`, por defecto `true`).
- `permissions: {}` arriba. Trabajo `decidir`: `contents: read`; valida el commit, exige que esté en
  `origin/main` (o en la futura rama `datos`), ubica la publicación anterior y corre `avisos.py`
  (solo biblioteca estándar, sin pip). Trabajo `enviar`: `id-token: write`, sin checkout ni código del
  repo; si faltan `vars.GCP_WIF_PROVIDER`, `vars.GCP_SA_EMAIL` o `vars.FIREBASE_PROJECT_ID` termina sin
  enviar y lo dice en el resumen; si están, se autentica con `google-github-actions/auth` (OIDC, scope
  `firebase.messaging`, 300 s, sin archivo de credenciales) y manda a FCM HTTP v1 un mensaje solo de datos
  `{"tipo":"nivel","ciudad":"paysandu"}`, prioridad `HIGH`, al tema `nivel-paysandu` (o `prueba-paysandu`).
- Acciones fijadas por SHA: checkout v5.1.0, setup-python v6.3.0 (las mismas del repo) y
  google-github-actions/auth v3.0.0 (`7c6bc770dae815cd3e89ee6cdf493a5fab2cc093`, verificado con
  `git ls-remote`). actionlint 1.7.12 con shellcheck: sin errores.
- No se probó en GitHub Actions ni contra FCM: falta el paso 6 y no está conectado al lector.

## Pruebas

`python -m pytest -q` desde la raíz (Python 3.12, dependencias instaladas con
`pip install --require-hashes --only-binary=:all: -r lector/requirements.txt -r lector/requirements-dev.txt`):

```
240 passed in 16.62s
```

(137 tenía `main`; se agregaron 19 del margen y 84 de avisos.)

## Decisiones que tomé por mi cuenta

1. **Búsqueda hacia atrás en modo git:** si el `actual.json` anterior está en `sin_dato`, `avisos.py`
   busca (hasta 200 versiones) el último nivel con dato. Así una caída de la fuente no avisa, pero tampoco
   hace perder un cambio de nivel real al volver. El pronóstico se compara contra el anterior inmediato,
   para no repetir un aviso de pronóstico ya mandado durante la caída.
2. **Dos trabajos en `avisos.yml`** en lugar de uno: el código que lee datos no puede pedir un token
   OIDC y el que tiene la credencial no corre nada del repositorio.
3. **`prueba` por defecto `true`**, y cualquier valor distinto de `false` va al tema de prueba.
4. **Envío sin reintentos** (un reintento tras un corte podría duplicar el aviso).
5. **Desde una rama distinta de `main`** el workflow decide pero no se autentica (warning, termina bien).
6. **Margen 0–0,5 m validado** en `main()` con código 1.

## Observaciones de la revisión que quedan para decidir

- **Un push de tipo `pronostico` hoy no muestra nada:** el mensaje siempre dice `"tipo":"nivel"` (como pide
  el plan) y la app (`revisarNivel`) solo avisa por cambio de nivel. Hay que definirlo en el paso 4:
  pasar el tipo en el mensaje y qué muestra la app (con su propia marca), o no enviar por pronóstico
  hasta entonces.
- **Margen después de `sin_dato`:** el lector no aplica margen si el anterior es `sin_dato`, pero
  `avisos.py` busca hacia atrás. Tras una caída larga (más de 48 h) o umbrales inválidos con el río
  justo en el umbral, puede haber un "bajó" y un "subió" seguidos. Es raro; arreglarlo pide guardar el
  último nivel con dato en `actual.json` (cambia el contrato, sección 5).
- **Pronóstico sin histéresis:** informes diarios que alternan 4,40 / 4,38 / 4,40 darían dos avisos.
- **Concurrency:** si una corrida en espera es cancelada por otra y era justo la del cambio, ese push se
  pierde (queda la revisión local).
- Caso raro: si el anterior inmediato es ilegible, la búsqueda hacia atrás usa el pronóstico de la versión
  encontrada y podría repetir un aviso de pronóstico.

## Pendiente para el dueño

| Paso | Qué |
|---|---|
| 1 | Proyecto de Firebase "Mi Río UY", registrar `uy.miriouy.app`, `google-services.json`, sin Analytics. |
| 3 | Prueba de entrega en el Redmi con la app cerrada (decide si sirve el mensaje solo de datos). |
| 4 | App: suscripción al tema, manejador en segundo plano, marca compartida con el respaldo; definir el caso `pronostico`. |
| 5 | Mover los datos a la rama `datos` y GitHub Pages a esa rama. |
| 6 | Identidad federada (ver abajo) y las tres variables del repositorio. |
| 8 | Prueba completa en el tema de prueba y una semana en el real. Antes, lanzar `avisos.yml` desde `lector.yml` (trabajo aparte con `actions: write`, `--ref main`, `commit` y `prueba=false`). |

Paso 6, condición recomendada para el proveedor (emisor `https://token.actions.githubusercontent.com`):

```
assertion.repository_id == '1412063651' &&
assertion.repository_owner_id == '141058604' &&
assertion.repository == 'MatiCascoV/rio-paysandu' &&
assertion.ref == 'refs/heads/main' &&
assertion.workflow_ref == 'MatiCascoV/rio-paysandu/.github/workflows/avisos.yml@refs/heads/main'
```

Mapeo: `google.subject=assertion.sub` y `attribute.repository`, `attribute.repository_id`,
`attribute.repository_owner_id`, `attribute.ref`, `attribute.workflow_ref`. Cuenta de servicio: rol
`roles/firebasecloudmessaging.admin` (el predefinido más chico que encontramos; lo mínimo real es un rol
propio con solo `cloudmessaging.messages.create`, conviene confirmarlo en la consola) y
`roles/iam.workloadIdentityUser` sobre la cuenta para el `principalSet` del repositorio. Variables:
`GCP_WIF_PROVIDER` (`projects/<número>/locations/global/workloadIdentityPools/<pool>/providers/<proveedor>`),
`GCP_SA_EMAIL` y `FIREBASE_PROJECT_ID`. Los IDs numéricos salen de la API pública de GitHub; verificarlos.

## Agentes

Orquesté e integré yo. Data Engineer: margen y sus tests. API Tester: `avisos.py` y sus tests. DevOps
Automator: `avisos.yml`. Secrets & Credential Hygiene Engineer: revisión de credenciales y separación en
dos trabajos. Code Reviewer: sin bloqueantes; corregí el comentario de concurrency y el resto quedó
anotado arriba. Reality Checker: aprobado con evidencia (pytest, actionlint, CLI probado a mano).
