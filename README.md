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

## Estado

Fase 0 (entorno) en curso.
