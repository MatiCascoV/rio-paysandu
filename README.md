# Río Paysandú

App Android que muestra el nivel del río Uruguay en Paysandú, su tendencia y el pronóstico
publicado por CARU, y avisa cuando el río se acerca a los niveles de alerta o evacuación.

Los datos salen siempre de la fuente oficial (CARU). Esta app es una ayuda a la comunidad:
**no tiene vínculo con ningún organismo ni canal oficial y no reemplaza la alerta oficial**.
Ante cualquier duda hay que comunicarse con los canales oficiales (Cecoed Paysandú, Sinae).

## Cómo está armado

- `lector/` — programa en Python que lee los datos de CARU, los valida y genera los JSON.
- `data/` — JSON generados por el lector (se publican con GitHub Pages).
- `.github/workflows/` — automatización que corre el lector cada unos 10 minutos (bucle que se relanza solo).
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
| `dato_a_verificar` | El dato se publica, pero puede tener un error: salto de más de 1 m en menos de 6 h contra la lectura anterior, estación y Prefectura que difieren más de 1 m con lecturas a menos de 3 h entre sí, o una lectura con fecha futura (que se descarta). Solo el **salto** retiene `nivel`: se mantiene el anterior hasta que llegue una lectura con fecha más nueva o pasen 30 minutos (`retencion_max_min`), lo que ocurra primero; mientras tanto `actual.json` trae `nivel_retenido` (`fecha_lectura` retenida y `desde` cuándo). Las otras causas solo avisan. |
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
3. Completa el historial con las páginas de detalle.

Lo de los pasos 2 y 3 se pide con un solo intento, solo si pasaron menos de 90 s desde el arranque
(`presupuesto_secundarias_s`) y nunca después de los 150 s (`limite_descargas_s`). Los tiempos están en
`lector/config.json`.

Código de salida de `lector.py`: `0` bien; `3` no se pudo leer el registro de CARU o vino sin el dato de
Paysandú (se publicó el último dato con `fuente_no_disponible`); `4` `data/umbrales.json` inválido (además
imprime `::error::`); `1` configuración o archivo de `data/` con JSON mal escrito (no se modifica nada).

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
  del lector: el repositorio se trae sin token (es público) y el token se pasa solo al `git push`.
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


## Estado

- Fase 0 (entorno): hecha (`flutter doctor` sin problemas).
- Fase 1 (lector local): hecha.
- Fase 2 (automatización y publicación): hecha.
- Fase 3 (app): hecha y probada con tests y capturas; falta probarla en un celular real.
