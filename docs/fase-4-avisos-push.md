# Fase 4: avisos push

Estado (26/10/2026): **pasos 1 a 7 hechos** y en `main`. El paso 4 (app) se probó en el Redmi con el río
en alerta real (`docs/fase-4-informe-app.md`). El paso 6 (identidad federada) se hizo el 26/10/2026
(`docs/fase-4-paso-6-guia.md`) y con él `avisos.yml` mandó por primera vez un mensaje real de FCM: un resumen
al tema de prueba `prueba-resumen-paysandu` (corrida 40333610759; falta verificar que llegó al Redmi). El
urgente todavía no se probó contra FCM. Faltan el paso 8 y el resto del 9 (el README ya explica cómo ver,
cortar y revisar los envíos, en "Avisos push").

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
| **Aviso urgente** | Cuando el nivel **sube** a `alerta` o a `evacuacion` (comparado con el último nivel con dato). | Bajadas; normal → atención; pronóstico; entrar o salir de `sin_dato` (después de `sin_dato` se compara con el último nivel con dato: atención → `sin_dato` → alerta sí avisa). |
| **Resumen del día** | Una vez por día, solo si el nivel es `atencion`, `alerta` o `evacuacion`. Sale con la primera publicación del día que trae la lectura de Prefectura de ese día (la de las 06:00, que CARU suele publicar entre 7:30 y 9 en días hábiles). Si a las **10:00** todavía no llegó, sale con la primera publicación desde las 10:00, con el dato de la estación automática. Si el río entra en atención o más recién más tarde, sale en ese momento. | Río normal; un segundo resumen el mismo día; pronóstico. |

El mismo día pueden llegar los dos (por ejemplo, el río sube a alerta a las 8 justo cuando llega Prefectura).

**Pestaña Avisos de la app** (paso 4):

- **Aviso urgente**: interruptor, y debajo la elección **"Desde alerta"** (avisa al subir a alerta y a
  evacuación) o **"Solo evacuación"**.
- **Resumen del día**: interruptor, **prendido por defecto**.

## Cómo funciona

1. El lector publica datos nuevos (como hoy).
2. Un workflow aparte, `avisos.yml`, corre `lector/avisos.py`, que mira la publicación nueva y las anteriores
   y decide si corresponde un aviso urgente, un resumen, los dos o nada.
3. Si corresponde, manda **un mensaje push sin texto** por Firebase Cloud Messaging (FCM) a uno de tres temas
   (ver la tabla de mensajes abajo).
4. El teléfono recibe el mensaje aunque la app esté cerrada, baja `actual.json` y arma la notificación con
   ese dato.
5. La revisión periódica local (`revisarNivel`) sigue como respaldo, con las mismas reglas y preferencias, y
   comparte con el push la marca de lo ya avisado, así que nunca avisan dos veces.

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

**Riesgo a probar primero:** los mensajes de solo datos dependen de que Android despierte la app. En
algunos Xiaomi hace falta activar "Inicio automático" y quitar la restricción de batería. Si en la prueba
del paso 3 no llegan de forma confiable, la alternativa es un push **con** texto fijo y neutro por tipo
("El río subió de nivel. Tocá para ver el dato"), que el sistema muestra solo; se pierde parte de la
protección de la primera fila, porque el texto lo pondría el mensaje. Esa decisión se toma con los
resultados de la prueba.

## Separar los datos del código (antes del envío)

Hoy el trabajo que procesa contenido de CARU sube commits a `main`, aunque se niega a subir cambios fuera de
`data/`. Con credenciales de envío en juego conviene separarlos:

- El lector publica en una rama **`datos`**, y GitHub Pages pasa a publicar esa rama. Las direcciones
  `https://maticascov.github.io/rio-paysandu/data/...` no cambian, así que las apps instaladas siguen andando.
- `avisos.yml` vive en `main` y se lanza con `workflow_dispatch` desde el workflow del lector (como el
  trabajo `relanzar` que ya existe), con el commit de `datos` como entrada. Así siempre corre la versión de
  `main`, que es la única que la credencial acepta.

## Pasos

| # | Paso | Quién | Tamaño |
|---|---|---|---|
| 1 | Crear el proyecto de Firebase "Mi Río UY" con la cuenta de Google del dueño y registrar la app `uy.miriouy.app`. Bajar `google-services.json`. Sin Analytics. **Hecho.** El archivo queda fuera de git (`.gitignore`): cada uno lo tiene en su copia local, y la CI lo escribe desde el secreto `GOOGLE_SERVICES_JSON` (en los secretos de Actions y de Dependabot; ver `.github/workflows/app.yml`). | Dueño (con guía) | S |
| 2 | Margen al bajar en el lector (`margen_bajada_m`) y tests. **Hecho.** | Desarrollo | S |
| 3 | **Prueba de entrega en el Redmi:** app con `firebase_messaging`, suscrita a un tema de prueba; envío manual desde la consola de Firebase con la app cerrada; medir cuánto tarda y si llega con la batería en modo normal y en ahorro, **con prioridad alta y con prioridad normal**. Decide la fila "Riesgo a probar". | Desarrollo + dueño | M |
| 4 | App: pestaña **Avisos** nueva (ver arriba). Suscribir y desuscribir los temas según las preferencias. Manejador en segundo plano que baja `actual.json` y arma la notificación. La revisión local `revisarNivel` tiene que respetar **las mismas preferencias y reglas** (urgente solo al subir a alerta o evacuación, resumen como máximo uno por día y nada con río normal), con marcas compartidas con el push para el urgente y para el resumen del día. El texto de cada notificación lo arma la app desde `actual.json`, por ejemplo: título "Río hoy: 5,85 m · Alerta", texto "Bajó 13 cm en 24 h. Abrí la app para ver el dato en tiempo real." Pantalla corta con los ajustes de Xiaomi u otros fabricantes si los avisos no llegan. Tests. **Hecho** en `fase-4-app-avisos` (falta probarlo en el Redmi; ver `docs/fase-4-informe-app.md`). | Desarrollo | M |
| 5 | Mover los datos a la rama `datos` y GitHub Pages a esa rama, sin cortar el servicio (copiar, cambiar Pages, verificar las URLs, recién entonces apuntar el lector). **Hecho** (21/10/2026): `lector.yml` toma el código de `main` y publica en `datos` (`LECTOR_DATOS`); GitHub Pages publica `datos` y `data/` salió de `main`. Falta que el dueño proteja `datos` contra borrado y force-push (Settings → Rules → Rulesets). **Ojo:** el lector se apuntó a `datos` antes de cambiar Pages y la app mostró el dato de las 10:00 durante unas 2 horas; en un corte así, primero Pages y verificar las URLs. | Desarrollo, con OK del dueño | M |
| 6 | Identidad federada: pool exclusivo y proveedor de GitHub en Google Cloud, con la condición completa de `docs/fase-4-informe-agente.md` (IDs de repositorio y dueño, `ref == refs/heads/main`, `workflow_ref` de `avisos.yml`, `event_name == workflow_dispatch`, `run_attempt == 1`, `runner_environment == github-hosted`); cuenta de servicio con un rol propio de solo `cloudmessaging.messages.create` y nada más. **Hecho** (26/10/2026; ver `docs/fase-4-paso-6-guia.md`, con lo que quedó pendiente). | Dueño (con guía; necesita permisos de su cuenta) | M |
| 7 | `lector/avisos.py` (decide urgente y resumen desde el historial de `data/actual.json`) y `avisos.yml` (lo corre y envía por la API HTTP v1 de FCM a los tres temas). Acciones fijadas por SHA, permisos mínimos, entrada `prueba` que envía solo a los temas de prueba. Tests con fixtures. **Hecho** (sin probar contra FCM). | Desarrollo | M |
| 8 | Prueba completa: forzar con datos de prueba una subida a alerta y un resumen, en los temas de prueba, con la app cerrada en el Redmi. Después, una semana en los temas reales con el teléfono del dueño. **Ojo:** la decisión sale del historial de `data/actual.json`, así que un `actual.json` falso commiteado en `main`/`datos` queda en ese historial: una versión falsa del día lista para resumen suprime el resumen real de ese día, y una falsa en alerta hace que la próxima subida real no avise. Hacer la prueba un día con río normal y volver enseguida a los datos reales, o probar en una copia del repositorio. | Desarrollo + dueño | S |
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
  el teléfono salga del reposo. Se prueba en el paso 3; si se demora demasiado, se pasa a prioridad alta.
- El urgente y el resumen pueden llegar juntos (por ejemplo, sube a alerta con la publicación que trae
  Prefectura). **Decidido en el paso 4:** la app muestra solo el urgente (ya trae la altura) y da por hecho el
  resumen de ese día.
