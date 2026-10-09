# Río Paysandú

App Android que muestra el nivel del río Uruguay en Paysandú, su tendencia y el pronóstico
publicado por CARU, y avisa cuando el río se acerca a los niveles de alerta o evacuación.

Los datos salen siempre de la fuente oficial (CARU). Esta app es una ayuda a la comunidad:
**no tiene vínculo con ningún organismo ni canal oficial y no reemplaza la alerta oficial**.
Ante cualquier duda hay que comunicarse con los canales oficiales (Cecoed Paysandú, Sinae).

## Cómo está armado

- `lector/` — programa en Python que lee los datos de CARU, los valida y genera los JSON.
- `data/` — JSON generados por el lector (se publican con GitHub Pages).
- `.github/workflows/` — automatización que corre el lector cada 15–30 minutos.
- `app/` — app Flutter que lee los JSON publicados.

El detalle del proyecto y sus fases está en [PROMPT_MAESTRO.md](PROMPT_MAESTRO.md).

## Cómo correr el lector

Desde la raíz del repositorio, en PowerShell (la primera vez):

```powershell
py -3.12 -m venv lector\.venv
.\lector\.venv\Scripts\python.exe -m pip install -r lector\requirements.txt
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
| `dato_a_verificar` | Salto de más de 1 m en menos de 6 h, fuentes que no coinciden o fecha imposible. |
| `dato_fuera_de_rango` | Se descartó una lectura fuera de 0–20 m. |
| `fuente_no_disponible` | No se pudo leer CARU; se conserva el último dato válido con su fecha. |

`generado` indica la última vez que cambió el contenido, no la última vez que corrió el lector.

## Datos publicados

GitHub Actions corre el lector cada 30 minutos (workflow "Lector CARU") y GitHub Pages publica el resultado:

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

Para instalar por USB en un Xiaomi/Redmi hay que activar, en *Opciones de desarrollador*,
"Depuración USB" e "Instalar vía USB", y aceptar el cartel que aparece en el teléfono.

## Estado

- Fase 0 (entorno): hecha (`flutter doctor` sin problemas).
- Fase 1 (lector local): hecha.
- Fase 2 (automatización y publicación): hecha.
- Fase 3 (app): hecha y probada con tests y capturas; falta probarla en un celular real.
