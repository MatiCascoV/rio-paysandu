# Río Paysandú

App Android que muestra el nivel del río Uruguay en Paysandú, su tendencia y el pronóstico
publicado por CARU, y avisa cuando el río se acerca a los niveles de alerta o evacuación.

Los datos salen siempre de la fuente oficial (CARU). Esta app es un canal de información de la
Intendencia de Paysandú y **no reemplaza la alerta oficial del Sinae / Cecoed**.

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

## Estado

- Fase 0 (entorno): falta completar el SDK de Android y crear el repositorio en GitHub.
- Fase 1 (lector local): hecha.
