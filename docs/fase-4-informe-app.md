# Fase 4, paso 4: informe de la app (avisos push)

Rama `fase-4-app-avisos`, sin merge ni push (21/10/2026). Compila, `flutter analyze` sin problemas y
`flutter test` todo verde, pero **todavía no se probó en el teléfono**: eso es lo primero que falta (ver
"Cómo probar en el celular").

Diseño completo en `docs/fase-4-avisos-push.md`. Acá está qué se hizo, qué se decidió en el camino y cómo
probarlo.

## Qué se hizo

| Archivo | Qué tiene |
|---|---|
| `app/lib/avisos.dart` (nuevo) | Las reglas, sin plugins: `subidaUrgente` y `resumenListo` (las de `lector/avisos.py`), `decidirAvisos` (la decisión compartida, con las marcas), los textos de las notificaciones, la validación del mensaje push (`validarMensajePush`), `avisosDePush` (qué mostrar al recibir un push), los temas de FCM y la migración de preferencias. |
| `app/lib/push.dart` (nuevo) | Firebase Messaging: arranque, manejador en primer plano (`onMessage`) y en segundo plano o con la app cerrada (`manejarPushEnSegundoPlano`, con `@pragma('vm:entry-point')` y `Firebase.initializeApp()` en su isolate), y la sincronización de temas (`sincronizarTemas`). |
| `app/lib/notificaciones.dart` | Muestra los avisos (canal urgente de importancia alta y canal "Resumen del día" de importancia normal), la revisión de respaldo con workmanager (programada si hay algún aviso prendido) y el permiso de notificaciones. |
| `app/lib/pantallas/ajustes.dart` | Pestaña Avisos nueva, en dos secciones (ver abajo). |
| `app/lib/main.dart` | Arranca Firebase y el push en un `try/catch` aparte del de los avisos locales; pide el permiso una vez después del primer cuadro; la revisión al abrir la app marca el resumen del día como visto. |
| `app/test/avisos_test.dart`, `app/test/avisos_pantalla_test.dart` (nuevos) | Reglas, marcas compartidas, push, textos, migración, temas y la pestaña. Sin internet. |
| Tests existentes | Adaptados a la API nueva (`logica_test`, `seguridad_test`, `ejemplo_test`, `pantallas_test`); `flutter_test_config.dart` reinicia el turno de las decisiones en cada prueba. |

No se agregó ninguna dependencia: alcanzan `firebase_core` y `firebase_messaging` (commit 5943041),
`flutter_local_notifications`, `workmanager` y `shared_preferences`. El ícono de las notificaciones sigue
siendo el único recurso nombrado desde Dart (`@drawable/ic_notificacion`, ya en `keep.xml`); se comprobó con
`aapt2` que está en el APK release.

### Pestaña Avisos

- **Aviso urgente**: interruptor, apagado en una instalación nueva. Debajo, "Desde alerta" (avisa al subir a
  alerta y a evacuación) o "Solo evacuación", con los metros de `umbrales.json`. Con el urgente prendido dice
  en qué nivel está el río y cuándo llega el próximo aviso.
- **Resumen del día**: interruptor, prendido por defecto, con el texto "Solo sale cuando el río está en
  atención o más: con el río normal no llega nada."
- Si las notificaciones están bloqueadas, los dos interruptores se ven apagados (nunca prendido algo que no va
  a llegar) y un recuadro explica cómo permitirlas. Si la revisión de respaldo no se puede programar al
  prender, el interruptor vuelve a apagado con el recuadro de error de siempre.
- Si los temas no se pudieron sincronizar (sin conexión), una línea lo dice; no traba nada.
- Plegable "¿No te llegan los avisos?": pasos para Xiaomi, Redmi y POCO (inicio automático, batería sin
  restricciones) y para otros teléfonos.
- Se mantiene que no reemplaza la alerta oficial (Sinae y Cecoed) y lo de los datos personales, ahora
  aclarando que los avisos llegan por Firebase Cloud Messaging de Google, sin cuenta ni registro.

## Cómo funciona en el teléfono

1. Al abrir la app: `Notificaciones.iniciar` (guarda la dirección de los datos, migra las preferencias,
   programa o cancela el respaldo) y después `Push.iniciar` (Firebase, manejadores y sincronización de temas
   sin esperar). Si cualquiera falla, la app abre igual. En web y con `DATOS_EJEMPLO` no se inicializa nada
   de esto.
2. Llega un push: se valida (`tipo`, `nivel` o `fuente`, `ciudad`; cualquier otra cosa se ignora), se mira si
   este teléfono lo pidió (si no, ni se baja el dato), se baja `actual.json` con
   `Repositorio(url).cargar(soloActual: true)` y se decide con las mismas reglas que el respaldo. El texto
   sale solo de `actual.json`.
3. La revisión de respaldo (workmanager cada 30 min) y la de la app abierta usan la misma `decidirAvisos`.

**Marcas compartidas** (en SharedPreferences, con `prefs.reload()` en cada decisión porque cada puerta corre
en su isolate): `ultimo_nivel` (último nivel con dato visto), `ultimo_nivel_generado` (de qué publicación) y
`ultimo_resumen_dia`. La marca se escribe antes de mostrar la notificación. Dentro de un mismo isolate las
decisiones van de a una.

**Temas**: "Desde alerta" → `alerta-paysandu`, "Solo evacuación" → `evacuacion-paysandu`, resumen →
`resumen-paysandu`; con `--dart-define=TEMAS_PRUEBA=true`, los mismos con `prueba-` adelante. Al sincronizar
la app se suscribe a los que corresponden y se sale de **los otros cinco** (también de los de prueba en una
compilación real y al revés). Es idempotente y se repite en cada apertura; si algo falla queda pendiente y se
reintenta en la próxima.

## Decisiones tomadas

1. **Si no se puede bajar el dato**: para el urgente se muestra un aviso genérico, "Río Uruguay: hay
   novedades / No se pudo bajar el dato del río. Abrí la app para ver el nivel. La alerta oficial la dan el
   Sinae y el Cecoed.", sin nivel ni altura. Callar en una crecida es peor que un aviso sin dato, y no se
   inventa nada. No cuenta como visto: cuando la app o el respaldo consiguen el dato, sale el aviso de verdad,
   que reemplaza al genérico (misma notificación). Para el resumen, nada. La copia guardada en el teléfono no
   se usa para avisar (es vieja).
2. **Si `actual.json` todavía no muestra la subida** (el push puede salir antes de que GitHub Pages publique
   el archivo nuevo): se vuelve a bajar a los 20 s y a los 45 s más. Si sigue igual, el genérico. Para saber
   si el dato es anterior al envío se usa la hora de envío que pone FCM (`sentTime`, metadato del mensaje, no
   texto): un dato armado después del envío se toma como bueno aunque sea más bajo (por ejemplo, un push
   viejo que llega al prender el teléfono días después, con el río ya bajo: no avisa nada).
3. **Push urgente que el teléfono ya vio**: si la app o el respaldo ya avisaron esa subida, el push no la
   repite. Pero si lo último que vio el teléfono es de más de 20 min antes del envío y ya estaba en ese nivel,
   hubo una bajada en el medio que no vio (por ejemplo, Xiaomi cortó el respaldo): se le cree al servidor y se
   avisa. Un teléfono sin ningún nivel guardado también le cree al push. El respaldo solo, sin push, sigue la
   regla del servidor tal cual (sin nivel anterior no avisa).
4. **Urgente y resumen juntos**: solo el urgente (ya trae la altura) y el resumen del día se da por hecho.
5. **Resumen con la app a la vista**: si al abrir la app el resumen de hoy ya está listo, se marca como visto
   y no se notifica (el dato se está viendo). El reloj de 5 minutos de la app también corre con la app de
   fondo: ahí sí cuenta como respaldo y notifica.
6. **"Río hoy" solo con el dato de hoy**: el resumen sale solo si el `generado` es del mismo día de Uruguay
   que el reloj del teléfono, para no titular "Río hoy" con el dato de anoche.
7. **Texto del resumen**: con Prefectura, el título lleva la altura de Prefectura (la de las 6:00) para que
   coincida con su variación de 24 h ("Río hoy: 5,85 m · Alerta" / "Bajó 13 cm en 24 h. Abrí la app para ver
   el dato en tiempo real."); el nivel es el que publica el lector. Si la lectura no trae variación o el
   período no es de 24 h, no se dice nada de 24 h. Con la estación: "Dato de la estación automática de CARU de
   las 10:00 (todavía no llegó la lectura de Prefectura)."
8. **Sin la confirmación al prender**: antes, al prender los avisos en plena crecida llegaba un aviso del
   nivel de ese momento. Ahora la regla es la del servidor (solo subidas) y la confirmación es la línea de la
   pestaña "Ahora el río está en nivel ALERTA (5,95 m). El próximo aviso urgente llega si…".
9. **Permiso**: se pide una sola vez, después del primer cuadro de la primera apertura con esta versión (clave
   `permiso_avisos_pedido`), porque el resumen viene prendido. Al prender un interruptor se vuelve a pedir
   (Android no muestra el cuadro si ya está dado o si se negó para siempre).
10. **Migración**: `avisos_activos` y `avisar_desde` se pasan a `aviso_urgente`, `aviso_urgente_desde` y
    `aviso_resumen` una sola vez (`avisos_version = 1`) y se borran. Antes de migrar, la lectura ya interpreta
    las viejas igual, así la pestaña nunca muestra otra cosa. La migración se llama desde todas las puertas
    (la tarea de workmanager puede correr con la versión nueva antes de que se abra la app).
11. **Canales**: el urgente sigue en el canal `nivel_rio` de la versión anterior (Android no deja cambiarle
    la importancia a un canal existente; ahora se llama "Aviso urgente"). El resumen va en `resumen_dia`,
    importancia normal. Cada tipo usa siempre el mismo número de notificación.
12. **Temas al desuscribir**: se sale también de los temas de prueba en una compilación real (y al revés),
    para que instalar una encima de la otra no deje al teléfono en temas viejos.

## Qué quedó pendiente

- **Probarlo en el Redmi** (abajo), con la app cerrada, en ahorro de batería y en reposo.
- El script para mandar `{"tipo": ...}` a los temas `prueba-*` (propuesta abajo; no se tocó
  `fase-4-prueba-entrega`).
- Pasos 5, 6, 8 y 9 del diseño (rama `datos`, identidad federada, prueba completa con `avisos.yml`, README).
- `docs/fase-4-avisos-push.md` dice que `google-services.json` "va en el repo", pero está en `.gitignore`; la
  CI ahora lo escribe desde el secreto `GOOGLE_SERVICES_JSON` (commit f6bb40e). Conviene corregir esa frase
  cuando se decida.

## Cómo probar en el celular

### 1. Compilar con los temas de prueba

```powershell
cd app
C:\src\flutter\bin\flutter build apk --release --dart-define=TEMAS_PRUEBA=true
# APK: app\build\app\outputs\flutter-apk\app-release.apk
```

Usa el `google-services.json` local. Se instala encima de la app actual (mismo id). Al abrirla, la app se
suscribe a `prueba-resumen-paysandu` (y a `prueba-alerta-paysandu` o `prueba-evacuacion-paysandu` si se
prende el urgente) y se sale de los reales. Para volver a los temas reales, instalar una compilación sin
`TEMAS_PRUEBA` y abrirla una vez.

Para empezar de cero (urgente apagado, resumen prendido, el permiso se pide de nuevo): Ajustes del teléfono,
Aplicaciones, Mi Río UY, Almacenamiento, Borrar datos.

### 2. Datos de prueba sin tocar el repositorio

Con los datos reales casi nunca hay algo que avisar (hay que esperar una subida). Para forzar casos conviene
apuntar la app a una copia que se pueda editar, **sin commitear datos falsos** en el repositorio (eso
ensucia el historial que usa `avisos.py`, ver paso 8 del diseño):

1. Crear un gist secreto con `actual.json`, `umbrales.json` e `historial.json` (copias de los reales).
2. Compilar con `--dart-define=URL_BASE=https://gist.githubusercontent.com/<usuario>/<id>/raw/` además de
   `TEMAS_PRUEBA=true`. GitHub guarda en caché los raw unos 5 minutos: después de editar, esperar antes de
   mandar el push.
3. Editar `nivel`, `generado`, `altura_actual.fecha` y `lectura_prefectura` según el caso. Ojo: la altura
   tiene que ser de menos de 48 h y no más de 1 h posterior a `generado`; el resumen solo sale con
   `generado` de hoy (hora de Uruguay).

### 3. Mandar el push de prueba

`herramientas/enviar_push_prueba.ps1` (en `fase-4-prueba-entrega`) manda al tema `prueba-entrega` un mensaje
con otros datos, que esta app ignora. Propuesta de un script nuevo, `herramientas/enviar_aviso_prueba.ps1`,
que manda exactamente lo que va a mandar `avisos.yml` con la entrada `prueba`:

```powershell
# Fase 4, paso 4: manda un aviso push de prueba, igual al de avisos.yml con prueba=true.
# Usa la sesión de gcloud del dueño (gcloud auth login); no guarda ninguna clave.
# Uso: .\herramientas\enviar_aviso_prueba.ps1 -Tipo urgente -Nivel alerta
#      .\herramientas\enviar_aviso_prueba.ps1 -Tipo resumen -Fuente prefectura
param(
    [ValidateSet('urgente', 'resumen')][string]$Tipo = 'urgente',
    [ValidateSet('alerta', 'evacuacion')][string]$Nivel = 'alerta',
    [ValidateSet('prefectura', 'estacion')][string]$Fuente = 'prefectura'
)
$ErrorActionPreference = 'Stop'
$proyecto = 'mi-rio-uy-8ca81'
$gcloud = Join-Path $env:LOCALAPPDATA 'google-cloud-sdk-zip\google-cloud-sdk\bin\gcloud.cmd'
$token = (& $gcloud auth print-access-token).Trim()
if ($Tipo -eq 'urgente') {
    $data = @{ tipo = 'urgente'; nivel = $Nivel; ciudad = 'paysandu' }
    # Igual que avisos.yml: el de evacuación va a quien esté en cualquiera de los dos temas urgentes.
    if ($Nivel -eq 'alerta') { $destino = @{ topic = 'prueba-alerta-paysandu' } }
    else { $destino = @{ condition = "'prueba-alerta-paysandu' in topics || 'prueba-evacuacion-paysandu' in topics" } }
    $prioridad = 'HIGH'
} else {
    $data = @{ tipo = 'resumen'; fuente = $Fuente; ciudad = 'paysandu' }
    $destino = @{ topic = 'prueba-resumen-paysandu' }
    $prioridad = 'NORMAL'
}
# Solo datos, sin notification: la app arma el texto con actual.json.
$mensaje = $destino + @{ data = $data; android = @{ priority = $prioridad } }
$cuerpo = @{ message = $mensaje } | ConvertTo-Json -Depth 5
$respuesta = Invoke-RestMethod -Method Post `
    -Uri "https://fcm.googleapis.com/v1/projects/$proyecto/messages:send" `
    -Headers @{ Authorization = "Bearer $token"; 'x-goog-user-project' = $proyecto } `
    -ContentType 'application/json; charset=utf-8' -Body $cuerpo
"Enviado $Tipo ($($data.nivel)$($data.fuente), $prioridad) a las $(Get-Date -Format HH:mm:ss): $($respuesta.name)"
```

Cambios respecto del script de la prueba de entrega: el destino es uno de los temas `prueba-*` (o la
condición del urgente de evacuación), los datos son los de la app (`tipo`, `nivel` o `fuente`, `ciudad`) y
la prioridad sale del tipo (HIGH el urgente, NORMAL el resumen) como en `avisos.yml`. Sin `-ConTexto`: un
mensaje con texto lo mostraría Android solo y no probaría nada de la app.

### 4. Casos a probar (con la app cerrada, en ahorro de batería y en reposo)

| # | Preparación | Push | Lo esperado |
|---|---|---|---|
| 1 | Urgente prendido "Desde alerta". Gist en `atencion`, abrir la app (queda visto atención), cerrarla. Gist a `alerta`. | urgente alerta | "Río Uruguay: subió a ALERTA", con la altura y la hora del gist. |
| 2 | Seguido del 1. | urgente alerta otra vez | Nada (ya avisado). |
| 3 | Seguido del 1. Gist a `evacuacion`. | urgente evacuacion | "…subió a EVACUACIÓN". |
| 4 | "Solo evacuación". Gist de `atencion` a `alerta`. | urgente alerta | Nada (no está en ese tema; si llegara, la app igual lo ignora). |
| 5 | Compilación aparte con `URL_BASE` a una dirección que no existe (así falla la descarga), urgente prendido. | urgente alerta | "Río Uruguay: hay novedades", después de ~1 minuto de reintentos. |
| 6 | Resumen prendido, gist en `alerta` con `generado` de hoy y `lectura_prefectura` de hoy a las 06:00. **No abrir la app** después de editar (con la app a la vista el resumen se da por visto). | resumen prefectura | "Río hoy: X m · Alerta" / "Bajó N cm en 24 h…". |
| 7 | Seguido del 6. | resumen otra vez | Nada (uno por día). |
| 8 | Gist en `normal`. | resumen | Nada. |
| 9 | Apagar el urgente en la pestaña, esperar unos segundos. | urgente alerta | Nada. |
| 10 | Sin push: gist de `atencion` a `alerta` y esperar el respaldo (hasta 30 min, si Android lo deja). | — | El mismo aviso del caso 1, una sola vez aunque después llegue el push. |

Para el caso 10 el respaldo puede tardar mucho más en un Xiaomi; es justamente lo que el push viene a
resolver.

## Riesgos y dudas abiertas

- **No probado en el teléfono.** En particular: que el manejador en segundo plano pueda usar
  SharedPreferences y bajar el dato con la app cerrada (se llama a `DartPluginRegistrant.ensureInitialized()`
  por las dudas), y cuánto deja Android correr los reintentos de ~1 minuto en reposo.
- **Dos isolates a la vez** (push y respaldo en el mismo segundo): queda una ventana de milisegundos entre
  releer y escribir la marca. En el peor caso la segunda notificación reemplaza a la primera (mismo número),
  con un sonido de más.
- **Push urgente sin `sentTime`** (no debería pasar): se decide solo por el nivel; si el teléfono no vio una
  bajada en el medio, esa subida no se avisa por push. La revisión de la app y la del resumen diario (que
  también baja el dato) acortan esa ventana.
- **Margen de 20 minutos** entre que el lector arma la publicación y `avisos.yml` manda el push: si la cola de
  GitHub Actions demora más, un urgente que el teléfono ya vio se puede repetir una vez.
- **Resumen y app abierta**: quien abre la app a la mañana no recibe el resumen ese día. Es a propósito, pero
  conviene confirmarlo con el dueño.
- Con el permiso negado, los temas siguen suscritos (los push llegan y no se muestran): no molesta, y al
  volver a permitir funciona sin hacer nada.
