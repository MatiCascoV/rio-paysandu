# Fase 4: avisos push

Estado (27/10/2026): **pasos 1 a 7 hechos** y en `main`. El paso 3 (prueba de entrega) dio bien en el Redmi
(ver "Resultado de la prueba de entrega", al final). El paso 4 (app) se probó en el Redmi con el río en alerta
real (`docs/fase-4-informe-app.md`). El paso 6 (identidad federada) se hizo el 26/10/2026
(`docs/fase-4-paso-6-guia.md`).

- **Resumen:** `avisos.yml` ya lo mandó contra FCM a `prueba-resumen-paysandu` (corridas 40333610759 del 26/10
  y 40489758036 del 27/10).
- **Urgente:** el 26/10 se mandó con `herramientas/enviar_aviso_prueba.ps1` a `prueba-evacuacion-paysandu` y
  `prueba-alerta-paysandu`, y FCM aceptó los dos mensajes; no se verificó la llegada al teléfono.
  `avisos.yml` todavía no mandó ningún urgente real (el río viene bajando).
- **Lanzamiento automático:** desde el 26/10/2026 `lanzar-avisos.yml` (#20) lanza `avisos.yml` después de cada
  publicación de Pages (`docs/fase-4-lanzar-avisos.md`). Semana de prueba en los temas `prueba-` hasta el
  ~2/11/2026; después, `AVISOS_REALES=true` y una semana en los temas reales.

Faltan el paso 8 y el resto del 9 (el README ya explica cómo ver, cortar y revisar los envíos, en "Avisos
push").

`app/android/app/google-services.json` **no está en el repositorio** (`.gitignore`): para compilar hace falta
la copia local, y la CI de la app lo escribe desde el secreto `GOOGLE_SERVICES_JSON` (Actions y Dependabot,
ver `.github/workflows/app.yml`).

Objetivo: que los avisos importantes lleguen al teléfono **con la app cerrada**, en minutos, sin depender de
que Android deje correr la revisión periódica (los Xiaomi la cortan seguido).

**Aceptación** (de `PROMPT_MAESTRO.md`, ampliada):
- En el Redmi, con la app cerrada y sin abrirla en el día, llega el aviso urgente dentro de los 15 minutos de
  que el lector publica una subida a alerta o a evacuación.
- El texto de cada notificación sale de `actual.json`, nunca del mensaje push.
- Una subida produce un solo aviso urgente (ni el push y la revisión local por duplicado, ni idas y vueltas
  cuando el río oscila sobre el umbral).
- Como máximo **un resumen por día**.
- Con el río en nivel normal **no llega nada**.
- Apagar un tipo de aviso en la app deja de recibir ese tipo.

## Qué notificaciones se mandan (decidido por el dueño, 17/10/2026)

Solo dos tipos. Nada por cada centímetro, nada con el río normal, nada por pronóstico, nada por bajadas.

| Tipo | Cuándo sale | Cuándo no sale |
|---|---|---|
| **Aviso urgente** | Cuando el nivel **sube** a `alerta` o a `evacuacion` (comparado con el último nivel con dato) **y una segunda lectura lo confirma** (ver "Segunda lectura antes del urgente"). | Bajadas; normal → atención; pronóstico; entrar o salir de `sin_dato` (después de `sin_dato` se compara con el último nivel con dato: atención → `sin_dato` → alerta sí avisa). |
| **Resumen del día** | Una vez por día, solo si el nivel es `atencion`, `alerta` o `evacuacion`. Sale con la primera publicación del día que trae la lectura de Prefectura de ese día (la de las 06:00, que CARU suele publicar entre 7:30 y 9 en días hábiles). Si a las **10:00** todavía no llegó, sale con la primera publicación desde las 10:00, con el dato de la estación automática. Si el río entra en atención o más recién más tarde, sale en ese momento. | Río normal; un segundo resumen el mismo día; pronóstico. |

El mismo día pueden llegar los dos (por ejemplo, el río sube a alerta a las 8 justo cuando llega Prefectura).

**Pestaña Avisos de la app** (paso 4):

- **Aviso urgente**: interruptor, y debajo la elección **"Desde alerta"** (avisa al subir a alerta y a
  evacuación) o **"Solo evacuación"**.
- **Resumen del día**: interruptor, **prendido por defecto**.

## Cómo funciona

1. El lector publica datos nuevos en la rama `datos` y GitHub Pages los publica (como hoy).
2. Cuando Pages termina, `lanzar-avisos.yml` confirma que la URL pública ya sirve el dato y lanza
   `avisos.yml` con ese commit (ver `docs/fase-4-lanzar-avisos.md`).
3. `avisos.yml` corre `lector/avisos.py`, que mira la publicación nueva y las anteriores
   y decide si corresponde un aviso urgente, un resumen, los dos o nada.
4. Si corresponde, manda **un mensaje push sin texto** por Firebase Cloud Messaging (FCM) a uno de tres temas
   (ver la tabla de mensajes abajo).
5. El teléfono recibe el mensaje aunque la app esté cerrada, baja `actual.json` y arma la notificación con
   ese dato.
6. La revisión periódica local (`revisarNivel`) sigue como respaldo, con las mismas reglas y preferencias, y
   comparte con el push la marca de lo ya avisado, así que nunca avisan dos veces.

## Segunda lectura antes del urgente (M-1)

CARU solo contesta por HTTP sin cifrar. Para que una altura inventada (o un error del sensor) no dispare
un "subió a EVACUACIÓN" a todos los suscritos, el urgente espera una segunda lectura:

- La primera publicación con el nivel nuevo **no avisa**. Queda en espera (el motivo dice "Urgente en
  espera").
- Sale en la **primera publicación posterior** que trae una segunda lectura de la estación: `altura_actual.fecha`
  **mayor** que la de la primera (una fecha anterior no vale), de la **misma fuente**, que mantiene el nivel
  (o más) y **sin salto brusco** contra la primera (hasta 1 m). Solo el salto brusco frena la confirmación:
  la marca `dato_a_verificar` por contraste con el pronóstico o por diferencia entre fuentes se repite en
  cada publicación mientras dura (por ejemplo, una crecida real más alta que el informe de CARU) y **no**
  frena el aviso. Si no se pueden comparar las alturas, se exige que la lectura no traiga la marca.
- **Tope de 60 minutos**: si no llega esa segunda lectura (la estación se atrasa, o hay un salto brusco
  sostenido), el urgente sale igual en la **primera publicación con 60 minutos o más** desde la primera. Con la
  latencia de Pages y del lanzamiento puede llegar hasta ~70 minutos después. Nunca se calla una crecida.
- Si el lector acaba de soltar una retención por salto brusco (`nivel_retenido`), el lector ya esperó una
  lectura más nueva: la subida sale de una, **solo si** el nivel que se suelta es el mismo que guardó la
  retención (`nivel_retenido.nivel`, el calculado de la lectura retenida). Si se retuvo "alerta" y se suelta
  "evacuación", hay una sola lectura alta y se espera otra; lo mismo con retenciones viejas sin ese campo.
- Si entre medio el nivel baja, la confirmación se reinicia (un pico de una sola lectura no avisa nunca).
  Las publicaciones `sin_dato` en el medio se saltean, como siempre. Si la alerta estaba en espera y el nivel
  sube a evacuación, la alerta no sale: queda en espera la evacuación, que sale a su segunda lectura.
- Oscilación alerta ↔ atención (M-3): cada baja publicada reinicia la espera, así que un río que oscila en el
  umbral manda el urgente solo cuando se queda dos lecturas seguidas arriba (el margen al bajar del lector
  ya amortigua esas oscilaciones).
- Sigue sin guardar estado: la decisión se reconstruye del historial de `data/actual.json` (se leen solo las
  publicaciones del último plazo, no toda una racha larga), así que es la misma al re-correr un commit y
  nunca sale dos veces.
- Mientras tanto el lector publica la primera lectura con `dato_a_verificar`, y la app ya la muestra como
  "Este dato puede tener un error" sin cambios en `app/`. La marca dura mientras el lector repite la misma
  lectura y se va con la primera distinta.
- Costo: el urgente llega unos 30 minutos más tarde (la estación informa cada 30 min), hasta 60 como tope. Una
  crecida del río Uruguay sube de a centímetros por hora, así que no cambia mucho el tiempo para reaccionar
  (criterio, no medido).
- Con un salto brusco marcado ya no sale el "subió a …" en el primer push (era un error: `avisos.py` ignoraba
  `dato_a_verificar`).

**Límites que quedan** (la mitigación reduce el riesgo, no lo elimina):

- No frena a quien mantenga la mentira en el tiempo, ni a una fuente que repita el mismo error en dos lecturas.
  La solución de fondo es HTTPS o un feed firmado de CARU.
- La revisión local de la app (`revisarNivel`, el respaldo) decide solo con `actual.json` y **no conoce esta
  espera**: un teléfono con la app abierta o con el respaldo corriendo puede mostrar el urgente en la primera
  lectura (con el texto "Dato a verificar por CARU."). Cerrarlo requiere un cambio en `app/` (que el respaldo
  trate `dato_a_verificar` como "esperar" con el mismo tope de 60 minutos). Queda pendiente, sin hacer.
- **Si el lector se corta después de la primera lectura**, el urgente queda en espera hasta que vuelva a
  publicar: la decisión se toma al publicar, no hay un reloj aparte. Lo mitigan el respaldo local de la app y
  el issue automático `avisos-falla`. **Mejora futura (no implementada):** un chequeo de "urgente en espera sin
  publicaciones nuevas" que avise o fuerce el urgente pasado el plazo.
- En el modo de dos archivos (`avisos.py ANTERIOR.json NUEVO.json`, solo para pruebas manuales) no hay
  historial: el urgente nunca sale. El workflow usa `--commit`.

## Decisiones de diseño

| Tema | Decisión | Por qué |
|---|---|---|
| Contenido del push | Solo datos, sin título ni texto: `{"tipo":"urgente","nivel":"alerta"\|"evacuacion","ciudad":"paysandu"}` con prioridad alta, o `{"tipo":"resumen","fuente":"prefectura"\|"estacion","ciudad":"paysandu"}` con prioridad normal | El workflow nunca manda texto: la app arma la notificación solo con lo que dice `actual.json`. No protege contra un robo del token de envío (con él se puede mandar un mensaje con texto a cualquier tema); eso lo acotan el token de 300 s que solo existe en el trabajo `enviar` y la condición del proveedor del paso 6. |
| Destinatarios | Tres temas de FCM por ciudad: `alerta-<ciudad>`, `evacuacion-<ciudad>` y `resumen-<ciudad>` (ver abajo) | No hay que guardar tokens ni datos de nadie; cada persona elige qué recibe; sirve tal cual para la Fase 4.b. |
| Credencial | Identidad federada de GitHub (OIDC) contra Google Cloud, sin clave JSON | No hay secreto de larga duración que se pueda filtrar. La cuenta de servicio solo puede enviar mensajes de FCM y solo la acepta el workflow `avisos.yml` de `main`. |
| Quién decide si avisar | Una función del lector (`lector/avisos.py`), con tests | La regla queda en un solo lugar, probada con fixtures, igual que el resto del lector. No guarda estado: la decisión se puede reproducir desde el historial de `data/actual.json`. |
| Idas y vueltas | Margen al bajar: para pasar a un nivel menor, la altura tiene que quedar **5 cm** por debajo del umbral (`margen_bajada_m` en `lector/config.json`) | Evita un "subió a alerta" repetido cuando el río está justo en el umbral. Se aplica en el `nivel` que calcula el lector, así la app y el push coinciden. El valor se confirma con el Cecoed (consulta 9). |
| Respaldo | Se mantiene `workmanager` cada 30 min | Si el push no llega (sin Google Play Services, restricciones del fabricante), el aviso llega igual, más tarde. |

**Mensajes que manda `avisos.yml`** (con la entrada `prueba`, que viene prendida por defecto, cada tema lleva
el prefijo `prueba-`):

| Caso | Destino | Prioridad Android |
|---|---|---|
| Urgente alerta | tema `alerta-paysandu` | HIGH |
| Urgente evacuación | dos mensajes con los mismos datos: primero al tema `evacuacion-paysandu` y después al tema `alerta-paysandu` | HIGH |
| Resumen | tema `resumen-paysandu` | NORMAL |

La app suscribe así: "Desde alerta" → `alerta-paysandu`; "Solo evacuación" → `evacuacion-paysandu`; resumen
prendido → `resumen-paysandu`. La app deja cada teléfono en un solo tema urgente, así que el urgente de
evacuación le llega una sola vez aunque salga en dos mensajes. Si quedara en los dos (sincronización a medias),
le llegan dos pushes, pero la app no repite el aviso: el segundo ve `ultimo_nivel` ya en evacuación. Así todo
push que llega corresponde a algo que la persona pidió.

Antes el urgente de evacuación era una sola condición de FCM (`'alerta-paysandu' in topics || 'evacuacion-paysandu'
in topics`), pero en la prueba del 21/10 tardó 42 s contra menos de 1 s de un tema directo. Si falla uno de los
mensajes no hay reintentos: se intentan igual los demás, la corrida queda en rojo y el resumen del trabajo
`enviar` dice qué tema recibió el mensaje, cuál no y de cuál no se sabe (curl sin respuesta HTTP, por ejemplo
por tiempo agotado: FCM pudo haberlo recibido, por eso no se reintenta).

**Riesgo a probar primero (resuelto en el paso 3):** los mensajes de solo datos dependen de que Android
despierte la app. En algunos Xiaomi hace falta activar "Inicio automático" y quitar la restricción de batería.
La alternativa era un push **con** texto fijo y neutro por tipo ("El río subió de nivel. Tocá para ver el
dato"), que el sistema muestra solo, con lo que se perdía parte de la protección de la primera fila. **No hace
falta:** en la prueba del 21/10/2026 los mensajes de solo datos llegaron en el Redmi con la app cerrada y en
ahorro de batería, sin tocar "Inicio automático" (ver "Resultado de la prueba de entrega", al final). Queda
solo datos, urgente con prioridad HIGH y resumen con NORMAL.

## Separar los datos del código (antes del envío)

Hoy el trabajo que procesa contenido de CARU sube commits a `main`, aunque se niega a subir cambios fuera de
`data/`. Con credenciales de envío en juego conviene separarlos:

- El lector publica en una rama **`datos`**, y GitHub Pages pasa a publicar esa rama. Las direcciones
  `https://maticascov.github.io/rio-paysandu/data/...` no cambian, así que las apps instaladas siguen andando.
- `avisos.yml` vive en `main` y se lanza con `workflow_dispatch` (`--ref main`) y el commit de `datos` como
  entrada. Así siempre corre la versión de `main`, que es la única que la credencial acepta. **No lo lanza
  el lector:** lo lanza `lanzar-avisos.yml`, que arranca cuando GitHub Pages termina de publicar
  (`workflow_run` de `pages-build-deployment`). Así el trabajo que procesa lo que manda CARU no necesita
  `actions: write`, y el push sale recién cuando la app ya puede ver el dato. Decidido por el dueño el
  26/10/2026; detalles, riesgos y cómo cortarlo en `docs/fase-4-lanzar-avisos.md`.

## Pasos

| # | Paso | Quién | Tamaño |
|---|---|---|---|
| 1 | Crear el proyecto de Firebase "Mi Río UY" con la cuenta de Google del dueño y registrar la app `uy.miriouy.app`. Bajar `google-services.json`. Sin Analytics. **Hecho.** El archivo queda fuera de git (`.gitignore`): cada uno lo tiene en su copia local, y la CI lo escribe desde el secreto `GOOGLE_SERVICES_JSON` (en los secretos de Actions y de Dependabot; ver `.github/workflows/app.yml`). | Dueño (con guía) | S |
| 2 | Margen al bajar en el lector (`margen_bajada_m`) y tests. **Hecho.** | Desarrollo | S |
| 3 | **Prueba de entrega en el Redmi:** app con `firebase_messaging`, suscrita a un tema de prueba; envío manual desde la consola de Firebase con la app cerrada; medir cuánto tarda y si llega con la batería en modo normal y en ahorro, **con prioridad alta y con prioridad normal**. Decide la fila "Riesgo a probar". **Hecho** (21/10/2026; ver "Resultado de la prueba de entrega"). | Desarrollo + dueño | M |
| 4 | App: pestaña **Avisos** nueva (ver arriba). Suscribir y desuscribir los temas según las preferencias. Manejador en segundo plano que baja `actual.json` y arma la notificación. La revisión local `revisarNivel` tiene que respetar **las mismas preferencias y reglas** (urgente solo al subir a alerta o evacuación, resumen como máximo uno por día y nada con río normal), con marcas compartidas con el push para el urgente y para el resumen del día. El texto de cada notificación lo arma la app desde `actual.json`, por ejemplo: título "Río hoy: 5,85 m · Alerta", texto "Bajó 13 cm en 24 h. Abrí la app para ver el dato en tiempo real." Pantalla corta con los ajustes de Xiaomi u otros fabricantes si los avisos no llegan. Tests. **Hecho** en `fase-4-app-avisos` (falta probarlo en el Redmi; ver `docs/fase-4-informe-app.md`). | Desarrollo | M |
| 5 | Mover los datos a la rama `datos` y GitHub Pages a esa rama, sin cortar el servicio (copiar, cambiar Pages, verificar las URLs, recién entonces apuntar el lector). **Hecho** (21/10/2026): `lector.yml` toma el código de `main` y publica en `datos` (`LECTOR_DATOS`); GitHub Pages publica `datos` y `data/` salió de `main`. Falta que el dueño proteja `datos` contra borrado y force-push (Settings → Rules → Rulesets). **Ojo:** el lector se apuntó a `datos` antes de cambiar Pages y la app mostró el dato de las 10:00 durante unas 2 horas; en un corte así, primero Pages y verificar las URLs. | Desarrollo, con OK del dueño | M |
| 6 | Identidad federada: pool exclusivo y proveedor de GitHub en Google Cloud, con la condición completa de `docs/fase-4-informe-agente.md` (IDs de repositorio y dueño, `ref == refs/heads/main`, `workflow_ref` de `avisos.yml`, `event_name == workflow_dispatch`, `run_attempt == 1`, `runner_environment == github-hosted`); cuenta de servicio con un rol propio de solo `cloudmessaging.messages.create` y nada más. **Hecho** (26/10/2026; ver `docs/fase-4-paso-6-guia.md`, con lo que quedó pendiente). | Dueño (con guía; necesita permisos de su cuenta) | M |
| 7 | `lector/avisos.py` (decide urgente y resumen desde el historial de `data/actual.json`) y `avisos.yml` (lo corre y envía por la API HTTP v1 de FCM a los tres temas). Acciones fijadas por SHA, permisos mínimos, entrada `prueba` que envía solo a los temas de prueba. Tests con fixtures. **Hecho.** El resumen ya salió contra FCM (corridas 40333610759 y 40489758036); el urgente todavía no salió por `avisos.yml` (ver el estado, arriba). | Desarrollo | M |
| 8 | Prueba completa: forzar con datos de prueba una subida a alerta y un resumen, en los temas de prueba, con la app cerrada en el Redmi. Después, una semana en los temas reales con el teléfono del dueño. **Ojo:** la decisión sale del historial de `data/actual.json`, así que un `actual.json` falso commiteado en `main`/`datos` queda en ese historial: una versión falsa del día lista para resumen suprime el resumen real de ese día, y una falsa en alerta hace que la próxima subida real no avise. Hacer la prueba un día con río normal y volver enseguida a los datos reales, o probar en una copia del repositorio. El lanzamiento automático lo hace `lanzar-avisos.yml`: sin la variable `AVISOS_REALES` va a los temas `prueba-`; con `AVISOS_REALES=true`, a los reales (ver `docs/fase-4-lanzar-avisos.md`). | Desarrollo + dueño | S |
| 9 | Documentar en el README cómo ver los envíos, cómo cortarlos y qué hacer si fallan; agregar Firebase a la futura política de privacidad (Fase 5). | Desarrollo | S |

Orden: 1 → 2 → 3 (si la prueba falla, se revisa el diseño antes de seguir) → 4 → 5 → 6 → 7 → 8 → 9.

## Lo que no entra en esta fase

- Varias ciudades (Fase 4.b): los temas por ciudad ya quedan preparados.
- Avisos por pronóstico de Google Flood Hub: no se usan para avisar (sus términos lo excluyen; ver
  `docs/proxima-etapa-ciudades.md`).
- iPhone.

## Riesgos que quedan

- FCM y Google Play Services son de Google: sin ellos (algunos teléfonos sin servicios de Google) solo queda
  el respaldo local.
- El aviso nunca es más rápido que el dato: CARU publica con cerca de una hora de atraso respecto de la
  medición, más hasta 20 minutos del lector y GitHub Pages.
- Si GitHub Actions deja de correr, no hay datos ni avisos: es el mismo punto único de falla de hoy.
- El resumen va con prioridad **normal**, y en los Xiaomi un mensaje normal puede demorarse (horas) hasta que
  el teléfono salga del reposo. En la prueba del paso 3 quedó retenido hasta que el teléfono despertó, y se
  **decidió mantenerlo en NORMAL** (el urgente sigue en HIGH): para un resumen diario es aceptable.
- El urgente y el resumen pueden llegar juntos (por ejemplo, sube a alerta con la publicación que trae
  Prefectura). **Decidido en el paso 4:** la app muestra solo el urgente (ya trae la altura) y da por hecho el
  resumen de ese día.

## Resultado de la prueba de entrega (paso 3, 21/10/2026)

Redmi del dueño (MIUI), app de prueba suscrita al tema `prueba-entrega` y push de **solo datos** enviados con
un script. La app de prueba (`lib/push_prueba.dart`) y el script (`herramientas/enviar_push_prueba.ps1`)
estaban en la rama de prueba `fase-4-prueba-entrega`, que **no se integró a `main`**; para probar contra la
app real está `herramientas/enviar_aviso_prueba.ps1` (ver `docs/fase-4-informe-app.md`). "Llegó" = la app
recibió el mensaje y mostró su notificación.

| # | Prioridad | App | Batería | Resultado |
|---|---|---|---|---|
| 1 | HIGH | abierta | normal | llegó en < 1 s |
| 2 | NORMAL | abierta | normal | llegó en < 1 s |
| 3 | HIGH | cerrada (deslizada) | normal | llegó en < 1 s |
| 4 | NORMAL | cerrada (proceso aún vivo) | normal | llegó en < 1 s |
| 5 | HIGH | abierta | ahorro de MIUI | llegó en < 1 s |
| 6 | NORMAL | abierta | ahorro de MIUI | llegó en < 1 s |
| 7 | HIGH | cerrada, arranque en frío | ahorro de MIUI | llegó en < 1 s |
| 8 | NORMAL | cerrada | ahorro de MIUI | llegó en < 1 s |
| 9 | NORMAL | cerrada, pantalla apagada, reposo profundo forzado (`adb shell dumpsys deviceidle force-idle`) | — | **retenido**: llegó recién al salir del reposo (~50 s después, al despertar el teléfono) |
| 10 | HIGH | cerrada, pantalla apagada, reposo profundo forzado | — | llegó en < 1 s |

Conclusiones:

- Los push de solo datos funcionan en el Redmi, también con la app cerrada y en ahorro de batería, sin
  tocar "Inicio automático". **Se mantiene el diseño de solo datos**: no hace falta la alternativa con texto
  de "Riesgo a probar primero".
- El **urgente** (HIGH) atraviesa el reposo profundo al instante: es lo que importa.
- El **resumen** (NORMAL) queda retenido mientras el teléfono duerme y aparece cuando la persona lo usa.
  Para un resumen diario es aceptable; **se mantiene en NORMAL** (ver "Riesgos que quedan").
- No probado: varias horas de reposo real (sin forzar), ni la app "forzada a detenerse" desde Ajustes
  (en ese estado Android no entrega push a ninguna app). Se cubre en la prueba completa del paso 8.
