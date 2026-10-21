# Revisión de código de la rama `mapa-inundacion` (21/10/2026)

Paso 4 de `12-retomar.md`. El Code Reviewer (agente de `.claude/agents/`) revisó en solo lectura todo `git diff origin/main...HEAD` (136 archivos) después de cerrar la v1.1. Los arreglos los hicieron el Mobile App Builder (app), el Spatial Data Engineer (pipeline) y el DevOps Automator (CI). Cada arreglo tiene su test.

## Veredicto

La rama está sana en lo central, y quedan arreglados el bloqueante y los cinco importantes. Lo que sigue impidiendo publicar es de datos y de terceros, no de código: falta correr el pipeline v1.1 con datos reales (ver el 15) y los pendientes legales del 13.

Lo que el revisor confirmó que ya estaba bien:
- Cada archivo se controla por tamaño y sha256 antes de parsearlo.
- Si una capa falla, se usa la de arriba, nunca la de abajo.
- Un hueco roto se ignora, lo que deja más agua.
- Con otro `cero` no se pinta el agua de hoy.
- El pie "No reemplaza la alerta oficial" está siempre.
- No hay `TileLayer`.
- Los 72 assets coinciden con `indice.json`.
- El diff no toca `lector/lector.py` ni `lector.yml`.

## Hallazgos y qué se hizo

| # | Gravedad | Hallazgo | Arreglo | Test |
|---|---|---|---|---|
| B1 | Bloqueante | Los assets no traen `sin_validar`, así que la app no avisaba en ningún lado que el valle del San Francisco Grande no está validado (11 §8, condición 3). | Respaldo en la app: si el índice no trae la zona o el archivo no valida, igual se nombra en el resumen y TalkBack (`textoSinValidar` + `textoSinValidarSinDibujo`) y en la leyenda, con una fila sin muestra. No se dibuja borde. | `mapa_v11_test.dart`: "sin el archivo (datos de hoy): se nombra igual, sin borde, y el mapa anda", "con el archivo roto" |
| I1 | Importante | Entre 10,10 y 10,50 m el margen se recortaba en silencio, y la leyenda prometía +0,5. En 10,50 la franja tiene ancho cero. | `EleccionAgua.margenRecortado`. Línea de lectura con aviso (`textoMargenRecortado`) y leyenda y resumen ajustados. | `mapa_revision_test.dart`, grupo I1 (10,00, 10,30 y 10,50 m) |
| I2 | Importante | Con la capa del agua ilegible (p. ej. `agua/1050.json` corrupto y h ≥ 10,50), el mapa quedaba casi sin agua y con un aviso chico. | El dibujo queda tapado por un recuadro ámbar (`textoDibujoIlegible`) y la línea va con aviso. | grupo I2 |
| I3 | Importante | El pipeline publicaba con una calibración que no cumple, con capas vacías o con área que no crece, y no frenaba con terreno sin dato. | `errores_criterio` frena salvo `--forzar` (que deja `forzado: true` en calibracion.json). `validar_areas` frena capa máxima vacía o área decreciente. `control_sin_dato` mide la tierra uruguaya sin dato y frena por encima de `sin_dato.max_fraccion_tierra_uy` (0,05). | `test_mapa_controles.py` |
| I4 | Importante | Nada garantizaba que h + δ cayera en la grilla de cuantización ni que no pasara `max_cm`, así que se podía perder agua en silencio. | `llegada.umbral_en_grilla` y `chequear_umbrales` en `cargar_config` y `generar`. Las curvas con cota impar se suben al umbral siguiente, del lado prudente. | `test_mapa_controles.py` |
| I5 | Importante | Los tests del pipeline se salteaban en CI por falta de numpy. | Job `pytest-mapa` en `tests.yml` con `lector/mapa/requirements-ci.txt` (con hashes). | Corrida de GitHub Actions |
| M1 | Menor | Una zona baja reemplazada por una capa más alta se dibujaba con el estilo "se moja con el río normal". | No se dibuja con ese estilo y se avisa. | grupo M1 |
| M2/M3 | Menor | Aceptaba `min_m` no múltiplo de `paso_m`, `version` ≠ 1 y `margen_m` 0. | Se rechazan en la app (`modelos_mapa.dart`) y en el pipeline (`validar_indice`). | grupo M2/M3 y `test_mapa_controles.py` |
| M7 | Menor | El 07 tenía textos viejos ("3,90 (en su cauce)", el sello) y tamaños del APK que no coincidían. | Corregido y explicado. | — |
| M8 | Menor | Faltaban en el código los cambios del 13 (B1 y B3). | `app/assets/mapa/LICENSE-DATOS.md` y `textosFuentes` con ODbL, los productos MDT, Dinagua sin licencia publicada y CARU. | grupo M8 |
| M9 | Menor | `aCm` redondeaba antes del "hacia arriba". | `(metros*100 - 1e-6).ceil()`. | grupo M9 |
| — | Sugerencia | Fila de la línea de hoy escrita a mano en `mapa.dart`. | Constantes `textoLeyendaHoy` y `textoLeyendaUltimoDato`. | grupo leyenda |

## Abiertos

- **M4. Parseo en el hilo de la interfaz:** las capas (de hasta 80 KB) se parsean en el hilo de la interfaz porque el umbral de `compute` es 96 KB. Hay que medirlo en el Redmi con el deslizador. Si se traba, se baja el umbral.
- **M5. Test de assets:** no detecta archivos de más en `app/assets/mapa/` (calibracion.json, PNG, log) ni features salteados de `base.json`. Hoy no pasa. Conviene una lista blanca.
- **M6. Tests sintéticos:** `fuenteReal()` del test bloqueante usa polígonos sintéticos. Conviene renombrarla y sumar un caso con los assets reales.
- **TalkBack y lomas aisladas:** las marcas de loma quedan dentro de `ExcludeSemantics`, así que con TalkBack no se abre su hoja (el resumen lo compensa en parte). Hay que revisarlo con el checklist del 10.
- **Caché del pipeline:** `descarga.py` nunca revalida. Para que sea reproducible hay que fijar `--osm-pbf` y `--generado` (ya está documentado).
- **Fuera del PR:** separar `.claude/agents/` y `docs/mapa/mapa-real.html`, que tiene datos de OSM embebidos (ODbL, 13 B1).
- **Menor:** `ClipRRect(borderRadius: BorderRadius.zero)` en `mapa.dart`, que no hace nada.
- **`requirements-ci.txt`:** hay que regenerarlo a mano cuando cambie `lector/mapa/requirements.txt`.

## Resultados después de los arreglos

- `flutter analyze`: sin problemas.
- `flutter test`: 297 OK (antes de la revisión, 273).
- `pytest lector/tests/test_mapa_*.py` (venv del mapa): 113 OK (antes, 80).
- `pytest` del lector: 283 OK y 6 salteados (los `test_mapa_*`, que ahora corren en el job `pytest-mapa`).
