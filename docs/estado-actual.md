# Estado actual y próximas tareas

Última actualización: **21/10/2026**. Este archivo es el punto de partida de cada sesión: leelo antes de
`PROMPT_MAESTRO.md` y actualizalo al cerrar cada tarea (fecha, qué cambió, qué sigue).

## Cómo arrancar en VS Code

```powershell
git checkout main
git pull origin main
.\lector\.venv\Scripts\python.exe -m pytest -q   # 1 test se saltea: el de umbrales (ver abajo)
```

- **Los datos ya no están en `main`.** Viven solo en la rama `datos`, que es la que publica GitHub Pages
  (Settings → Pages → rama `datos`, raíz). `data/` está en `.gitignore` de `main`.
- Para ver o editar los datos (por ejemplo `umbrales.json`) y para que corra el test de umbrales, usá una copia
  de `datos` al lado del repositorio:

  ```powershell
  git fetch origin datos
  git worktree add ..\rio-datos datos
  $env:LECTOR_DATOS = (Resolve-Path ..\rio-datos\data).Path
  .\lector\.venv\Scripts\python.exe -m pytest -q   # ahora el test de umbrales también corre
  ```

  Un cambio en `..\rio-datos` se commitea y se sube a `datos` (`git -C ..\rio-datos push origin datos`). El
  lector hace fetch de `datos` antes de cada pasada, así que no pisa lo editado a mano.
- Nada automático escribe en `main`: el lector toma el código de `main` y sube solo a `datos`.

## Qué se hizo el 21/10/2026

| Qué | Dónde |
|---|---|
| App con avisos push (pestaña Avisos), mergeada y **probada en el Redmi** con el río en alerta real | MatiCascoV/rio-paysandu#13, `docs/fase-4-informe-app.md` |
| El lector publica en la rama `datos` (código de `main`) | MatiCascoV/rio-paysandu#14 |
| Pillow 12.3.0 → 13.0.0 revisado: hashes iguales a PyPI, compatible con pdfplumber, 284 tests verdes | MatiCascoV/rio-paysandu#12 |
| **Incidente:** la app mostró el dato de las 10:00 durante unas 2 h (ver abajo) | Arreglado a las ~12:25 |
| `data/` sale de `main`, `.gitignore`, test de umbrales con `LECTOR_DATOS`, docs al día | MatiCascoV/rio-paysandu#15 |

### Incidente: datos desactualizados en la app

- **Qué pasó:** con #14 el lector empezó a subir los datos a `datos`, pero GitHub Pages seguía publicando
  `main`. La app (que lee `https://maticascov.github.io/rio-paysandu/data/`) se quedó con el último dato que
  había en `main`.
- **Causa:** en la lista de corte de #14 el paso "cambiar Pages a `datos`" quedó sin hacer, y el orden estaba
  invertido respecto del diseño (primero Pages y verificar, después mover el lector).
- **Arreglo:** el dueño cambió Pages a `datos` (raíz). La publicación terminó bien y la app volvió a mostrar el
  dato actual.
- **Lección:** en cualquier cambio de dónde se publican los datos, primero cambiar Pages, verificar las URLs
  (`actual.json` con `generado` reciente) y recién después mover el lector. Y comprobar en la app.
- **Atraso normal:** la estación de CARU publica cerca de una hora después de la medición y en tandas (por
  ejemplo, las lecturas de 11:30 y 12:00 llegaron juntas a las 12:18). Un dato de hasta ~1 h 20 min no es falla.

## Fase 4 (avisos push): dónde estamos

Detalle completo en `docs/fase-4-avisos-push.md`.

| Paso | Qué | Estado |
|---|---|---|
| 1 | Proyecto de Firebase y `google-services.json` | Hecho |
| 2 | Margen al bajar de nivel en el lector | Hecho |
| 3 | Prueba de entrega en el Redmi | Hecho |
| 4 | App: pestaña Avisos | Hecho y probado |
| 5 | Rama `datos` y Pages | Hecho; `datos` protegida con `proteger-datos` (tarea A) |
| 6 | Identidad federada en Google Cloud | Hecho (26/10/2026; ver `docs/fase-4-paso-6-guia.md`) |
| 7 | `lector/avisos.py` y `avisos.yml` | Hecho; mandó un resumen real a `prueba-resumen-paysandu` (26/10/2026). El urgente sigue sin probar contra FCM |
| 8 | Prueba completa | Pendiente (tareas D y E) |
| 9 | README: ver, cortar y arreglar envíos | Sección "Avisos push" del README escrita (26/10/2026) |

## Tareas pendientes, en orden

### A. Proteger la rama `datos` — hecha (de otra forma)

Si alguien la borra o le hace force-push, la app se queda sin datos. **Hecho el 21/10/2026** con un ruleset
propio, `proteger-datos` (id 25566040), que en `datos` bloquea solo el borrado y el force-push. El lector
sigue pudiendo subir: siempre agrega commits encima (fast-forward). Se ve en
`https://github.com/MatiCascoV/rio-paysandu/rules?ref=refs/heads/datos`.

> **No sumar `datos` a `proteger-main`.** Desde el 26/10/2026 `proteger-main` exige pull request para todo
> cambio: aplicado a `datos`, el lector no podría subir y se cortaría la publicación de los datos que usa la
> app.

### B. Urgente de evacuación como dos mensajes — desarrollo, S

En la prueba del Redmi el envío por **condición** (`'alerta-paysandu' in topics || 'evacuacion-paysandu' in
topics`) tardó **42 s**; los envíos a un tema directo, menos de 1 s.

- Archivo: `.github/workflows/avisos.yml`, trabajo `enviar`, bloque `elif [ "$URGENTE" = evacuacion ]`.
- Cambio: en vez de un mensaje con `condition`, mandar **dos** mensajes con `topic`: uno a
  `${prefijo}alerta-paysandu` y otro a `${prefijo}evacuacion-paysandu`, los dos con
  `data: {tipo: "urgente", nivel: "evacuacion", ciudad: "paysandu"}` y `android.priority: HIGH`. Cada teléfono
  está suscrito a un solo tema urgente, así que nadie lo recibe dos veces.
- Actualizar el comentario del bloque, la fila "Contenido del push"/temas en `docs/fase-4-avisos-push.md` y,
  si los hay, los tests o controles del workflow.
- Qué pasa si uno de los dos envíos falla: el trabajo tiene que terminar en error (como hoy con un envío),
  sin cortar el otro.
- Aceptación: con `prueba=true`, el urgente de evacuación llega al Redmi en pocos segundos estando suscrito a
  "Desde alerta" y también a "Solo evacuación" (`herramientas/enviar_aviso_prueba.ps1` sirve de referencia).

### C. Paso 6: identidad federada — dueño con guía, M

Necesita la cuenta de Google del dueño; el asistente guía paso a paso. Todo lo necesario (condición del
proveedor con IDs de repositorio y dueño, `ref`, `workflow_ref`, `event_name`, `run_attempt`,
`runner_environment`; cuenta de servicio con un rol propio de solo `cloudmessaging.messages.create`) está en
`docs/fase-4-informe-agente.md`, sección "Pendiente para el dueño". Al final se cargan las variables del
repositorio `GCP_WIF_PROVIDER`, `GCP_SA_EMAIL` y `FIREBASE_PROJECT_ID`. Sin ellas `avisos.yml` termina sin
enviar.

### D. Lanzar `avisos.yml` desde `lector.yml` — desarrollo, S (antes del paso 8)

Hoy nada lanza `avisos.yml`. Diseño (`docs/fase-4-informe-agente.md`): un trabajo aparte en `lector.yml`,
como `relanzar`, con `actions: write`, que hace `gh workflow run avisos.yml --ref main -f commit=<sha del
commit subido a datos> -f prueba=false` cuando el lector subió un commit nuevo. El trabajo `leer` tiene que
dejar el SHA como salida. Sin checkout ni pip en ese trabajo.

### E. Paso 8: prueba completa — desarrollo + dueño, S

Después de C y D. Primero en los temas de prueba con la app cerrada en el Redmi; después una semana en los
reales. **Cuidado:** la decisión sale del historial de `data/actual.json` en `datos`; un `actual.json` falso
commiteado ahí queda en ese historial (puede suprimir el resumen real del día o tapar la próxima subida). Ver
el paso 8 en `docs/fase-4-avisos-push.md`.

### F. Paso 9: documentación de los envíos — desarrollo, S

En el README: cómo ver los envíos (corridas de `avisos.yml`), cómo cortarlos (deshabilitar el workflow o
quitar las variables) y qué hacer si fallan. Anotar Firebase para la política de privacidad (Fase 5).

### G. Limpieza — cualquiera, S

- Borrar las ramas remotas ya mergeadas: `fase-4-app-avisos`, `fase-4-rama-datos`, `fase-4-corte-datos`.
- GitHub avisa que `ubuntu-latest` pasa a Ubuntu 26 desde el 19/10/2026: mirar que `lector.yml`,
  `avisos.yml`, `tests.yml` y `app.yml` sigan verdes; si algo se rompe, fijar `ubuntu-24.04`.

## Después de la Fase 4

Fase 4.b (varias ciudades): investigada, sin empezar. Ver `docs/proxima-etapa-ciudades.md`.
