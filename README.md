# Mi Río UY

App Android (antes "Río Paysandú"; el repositorio conserva ese nombre) que muestra el nivel del río Uruguay en Paysandú, su tendencia y el pronóstico
publicado por CARU, y avisa cuando el río se acerca a los niveles de alerta o evacuación.

Los datos salen siempre de la fuente oficial (CARU). Esta app es una ayuda a la comunidad:
**no tiene vínculo con ningún organismo ni canal oficial y no reemplaza la alerta oficial**.
Ante cualquier duda hay que comunicarse con los canales oficiales (Cecoed Paysandú, Sinae).

## Cómo está armado

- `lector/` — programa en Python que lee los datos de CARU, los valida y genera los JSON.
- `data/` — JSON generados por el lector (se publican con GitHub Pages).
- `.github/workflows/` — automatización que corre el lector cada unos 10 minutos (bucle que se relanza solo)
  y los tests del lector y de la app.
- `app/` — app Flutter que lee los JSON publicados.

El detalle del proyecto y sus fases está en [PROMPT_MAESTRO.md](PROMPT_MAESTRO.md).

## Cómo correr el lector

Desde la raíz del repositorio, en PowerShell (la primera vez):

```powershell
py -3.12 -m venv lector\.venv
.\lector\.venv\Scripts\python.exe -m pip install --require-hashes --only-binary=:all: -r lector\requirements.txt -r lector\requirements-dev.txt
```

Las dependencias directas están en `lector/requirements.in` (y pytest en `lector/requirements-dev.in`).
Lo que se instala (acá y en GitHub Actions) es `lector/requirements.txt` y `lector/requirements-dev.txt`:
versiones fijas, con hashes y solo wheels. Dependabot los actualiza. Para cambiar una dependencia a mano,
regenerar los dos archivos con pip-tools (desde `lector/`, con Python 3.12):

```powershell
pip-compile --generate-hashes --strip-extras --allow-unsafe --no-emit-index-url --output-file requirements.txt requirements.in
pip-compile --generate-hashes --strip-extras --allow-unsafe --no-emit-index-url --output-file requirements-dev.txt requirements-dev.in
```

Después, cada vez:

```powershell
.\lector\.venv\Scripts\python.exe lector\lector.py     # lee CARU y actualiza data\
.\lector\.venv\Scripts\python.exe -m pytest -q         # tests (no usan internet)
```

La configuración (direcciones de CARU, cero, límites de antigüedad) está en `lector/config.json`.
Los umbrales de nivel están en `data/umbrales.json` y son **provisorios** hasta que el Cecoed los valide.

### Avisos que puede traer `actual.json`

| Aviso | Qué significa |
|---|---|
| `estacion_desactualizada` | La estación automática lleva más de 3 h sin dato; se muestra la lectura de Prefectura. |
| `dato_desactualizado` | La lectura mostrada es más vieja de lo esperable. |
| `dato_a_verificar` | El dato se publica, pero puede tener un error: salto de más de 1 m en menos de 6 h contra la lectura anterior, estación y Prefectura que difieren más de 1 m con lecturas a menos de 3 h entre sí, una lectura con fecha futura (que se descarta), o una altura que difiere más de 1,5 m de la esperada por un informe de crecida de hasta 1 día (`contraste_pronostico_m`, `contraste_pronostico_dias`). Solo el **salto** retiene `nivel`: se mantiene el anterior hasta que llegue una lectura con fecha más nueva o pasen 30 minutos (`retencion_max_min`), lo que ocurra primero; mientras tanto `actual.json` trae `nivel_retenido` (`fecha_lectura` retenida y `desde` cuándo). Si CARU deja de responder justo después de un salto, el tope de 30 minutos sigue corriendo igual y el aviso se mantiene mientras se muestre esa lectura. Las otras causas solo avisan. |
| `umbrales_invalidos` | `data/umbrales.json` está mal cargado (alturas fuera de 0–20 m o fuera de orden: debe ser atención < alerta < evacuación; atención puede faltar). `nivel` queda en `sin_dato` hasta corregirlo. |
| `dato_fuera_de_rango` | Se descartó una lectura fuera de 0–20 m. |
| `fuente_no_disponible` | No se pudo leer CARU; se conserva el último dato válido con su fecha. |
| `pronostico_no_disponible` | No se pudo leer el informe de crecida vigente (índice caído, PDF ilegible, sin la fila de Paysandú, o sin tiempo en esa pasada). `pronostico` conserva el último que se leyó, con su fecha y `vigente` recalculado. |

`generado` indica la última vez que cambió el contenido, no la última vez que corrió el lector.

### Cómo trabaja cada pasada

1. Lee el registro de alturas de CARU (hasta 3 intentos, como mucho 120 s) y escribe **enseguida**
   `actual.json` y las lecturas actuales en `historial.json`: si algo después se cuelga, la altura nueva
   ya quedó publicada.
2. Revisa el índice de informes de crecida y, si hay uno nuevo, baja el PDF y lo lee en un proceso aparte
   (`lector/pdf_aislado.py`: 60 s como máximo y, en Linux, 1,5 GB de memoria). Si el PDF no se puede leer,
   se anota en `data/estado_lector.json` y no se reintenta hasta 6 h después (`pdf_reintento_horas`).
3. Completa el historial con las páginas de detalle (última semana). Un punto ya guardado solo se corrige
   si es de las últimas 48 h (`historial_correccion_horas`), para que una corrección de CARU borre un pico
   falso; lo más viejo no se reescribe.

Lo de los pasos 2 y 3 se pide con un solo intento, solo si pasaron menos de 90 s desde el arranque
(`presupuesto_secundarias_s`) y nunca después de los 150 s (`limite_descargas_s`). Los tiempos están en
`lector/config.json`.

**Margen al bajar de nivel.** Para que `nivel` pase a uno menor que el publicado antes, la altura tiene
que quedar 5 cm o más por debajo del umbral (`margen_bajada_m` en `lector/config.json`; justo 5 cm ya
baja). Al subir no hay margen: al tocar el umbral, sube. Puede bajar varios niveles de una, pero solo hasta
donde lo permita el margen. Evita avisos "subió" y "bajó" seguidos cuando el río está justo en el umbral.
Sin un nivel anterior con dato (primer arranque, `sin_dato`) no se aplica. El margen va antes de la
retención por salto, así que una oscilación dentro del margen no crea `nivel_retenido`. El valor se
confirma con el Cecoed; tiene que ser de 0 a 0,5 m (0 lo desactiva), si no el lector sale con código `1`.

Código de salida de `lector.py`: `0` bien; `3` no se pudo leer el registro de CARU o vino sin el dato de
Paysandú (se publicó el último dato con `fuente_no_disponible`); `4` `data/umbrales.json` inválido (además
imprime `::error::`); `1` `lector/config.json` mal escrito o con un cero no soportado.

Un archivo de `data/` ilegible no frena la pasada (se avisa con `::error::` en el registro):
`umbrales.json` cuenta como umbrales inválidos (altura publicada, `nivel` en `sin_dato`, código 4, y el
archivo no se pisa); `historial.json` no se toca en esa pasada; `actual.json` se trata como si no hubiera
dato anterior; `estado_lector.json` se empieza de cero.

## Datos publicados

GitHub Actions corre el lector **cada unos 10 minutos**, en un bucle que se relanza solo (workflow
"Lector CARU", ver abajo), y GitHub Pages publica el resultado:

- https://maticascov.github.io/rio-paysandu/data/actual.json
- https://maticascov.github.io/rio-paysandu/data/historial.json
- https://maticascov.github.io/rio-paysandu/data/umbrales.json

### Cómo se mantiene actualizado

El horario programado de GitHub no resultó confiable (pasó horas sin disparar), así que el workflow
"Lector CARU" trabaja en cadena: cada corrida lee CARU **cada 10 minutos durante unas 5 horas** y,
antes de terminar, lanza la corrida siguiente. El horario programado queda solo como respaldo.

- **Ver que está vivo:** `gh run list --workflow lector.yml --limit 3` tiene que mostrar una corrida
  `in_progress`. Los commits "Datos de CARU …" aparecen cada vez que CARU publica algo nuevo.
- **Si la cadena se cortó** (ninguna corrida en curso): `gh workflow run lector.yml`, o pestaña
  **Actions → Lector CARU → Run workflow**.
- **Si algo falla seguido:** cada lectura tiene un corte duro de 7 minutos (el lector se acota solo a
  unos 4). Si el lector termina con error 12 pasadas seguidas (unas 2 horas: CARU caído, umbrales
  inválidos...), o si durante 6 pasadas (una hora) no se pueden subir los datos nuevos (token,
  permisos, GitHub caído), la corrida termina en error y el trabajo "avisar" abre un issue **"El lector falló"**
  (etiqueta `lector-falla`), o comenta el que ya esté abierto. Llega como notificación a quien sigue el
  repositorio; el correo de falla de GitHub no sirve, porque las corridas las lanza github-actions[bot].
  Cerrar el issue cuando esté resuelto. La cadena sigue igual: si una corrida no termina bien, la
  siguiente se lanza 10 minutos después (para no encadenar corridas que fallan al instante).
- **Permisos:** cada trabajo tiene solo el permiso que usa (`leer`: escribir contenido; `avisar`:
  issues; `relanzar`: lanzar workflows). En `leer`, el token no queda en `.git/config` ni en el entorno
  que hereda el lector: el repositorio se trae sin token (es público) y el token se pasa solo al
  `git push`, que además se niega a subir un commit que toque algo fuera de `data/`. Es una **reducción**
  de exposición, no aislamiento: el lector corre con el mismo usuario (que puede leer el entorno inicial
  del proceso del bucle y tiene sudo en el runner). Correrlo con un usuario sin privilegios queda pendiente.
- **Arranque a mano con otros tiempos:** `minutos_entre_lecturas` tiene que ser al menos 5 y
  `minutos_de_trabajo + minutos_entre_lecturas` como mucho 330; si no, la corrida falla y la
  siguiente arranca con los valores normales.
- **Para detenerla:** `gh workflow disable lector.yml`. Cancelar una corrida no alcanza, porque al
  cancelarse lanza la siguiente. Para reanudar: `gh workflow enable lector.yml` y lanzarla.

Entre que CARU publica y que la app lo muestra pasan hasta unos 20 minutos (10 del lector más la
copia que guarda GitHub Pages). La estación automática de CARU suele publicar con cerca de una hora
de atraso respecto de la hora de la medición; eso no depende de este proyecto.

## App Android

Proyecto Flutter en `app/`. La dirección de los datos y los teléfonos están en `app/assets/config.json`.

```powershell
cd app
flutter test                 # tests (no usan internet)
flutter run                  # con un celular conectado por USB
flutter build apk --release  # genera build/app/outputs/flutter-apk/app-release.apk
```

En GitHub Actions (`.github/workflows/app.yml`, con cada cambio en `app/`) corren `flutter analyze` y
`flutter test`, y se compila el APK de release para controlar que siga adentro todo recurso que el código
Dart nombra como texto (`'@drawable/...'`, `'@mipmap/...'`): la reducción de recursos del release los borra
si no están en `tools:keep` de `app/android/app/src/main/res/raw/keep.xml`. Ese APK no se guarda (está
firmado con la clave de depuración). Igual conviene correr `flutter test` y `flutter analyze` antes de subir.

- **Identificador:** `uy.miriouy.app`. No se cambia más: Android trataría otro identificador como otra app.
- **Firma:** el APK de release se firma con la clave propia si existe `app/android/key.properties`
  (fuera de git, igual que el `.jks`). Sin ese archivo se firma con la clave de depuración y la compilación
  lo avisa: ese APK sirve para probar, **no para repartir**. La clave y su contraseña tienen respaldo fuera
  de la PC; sin ellas no se pueden publicar actualizaciones.
- **Ícono:** fuentes SVG en `app/assets_fuente/icono/` (ícono adaptativo, monocromo y el de notificación).
- **Datos de ejemplo** para revisar el diseño en cada nivel: `flutter build web --dart-define=DATOS_EJEMPLO=url`
  y abrir con `?ejemplo=normal|atencion|alerta|evacuacion|sindato`. Con datos de ejemplo la app no guarda
  nada ni manda avisos. **Nunca publicar una compilación hecha con `DATOS_EJEMPLO`.**

## Estado

- Fase 0 (entorno): hecha (`flutter doctor` sin problemas).
- Fase 1 (lector local): hecha.
- Fase 2 (automatización y publicación): hecha.
- Fase 3 (app): hecha y probada en un celular real (Redmi), del 9 al 14/10/2026 sin fallas del lector.
  - 16/10/2026: nombre "Mi Río UY", identificador `uy.miriouy.app`, firma con clave propia e ícono nuevo.
  - 16/10/2026: rediseño de Inicio: fondo teñido según el nivel, agua que sube con la altura del río,
    gráfico de 7 días en Inicio y paleta azulada en modo claro y oscuro.
- Fase 4 (notificaciones push): en curso. Hechos el margen al bajar y el lector de avisos (`lector/avisos.py`
  y `avisos.yml`, sin probar contra FCM). Falta el proyecto de Firebase, la prueba de entrega en el celular,
  la app, la rama `datos` y la identidad federada. Ver [docs/fase-4-avisos-push.md](docs/fase-4-avisos-push.md).
  - 17/10/2026: arreglados los avisos locales en el APK de release (la reducción de recursos borraba el ícono
    de notificación).
- Fase 4.b (varias ciudades y enlace a Google Flood Hub): investigada, sin empezar. Ver
  [docs/proxima-etapa-ciudades.md](docs/proxima-etapa-ciudades.md).
- Fase 5 (publicación): sin empezar.
- Umbrales de Paysandú: provisorios hasta que los valide el Cecoed. Pendiente consultar a CARU si el
  registro de alturas tiene acceso por HTTPS.
