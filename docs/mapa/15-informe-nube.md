# Informe de la corrida en la nube (21/10/2026)

Pasos 1 a 4 de `12-retomar.md`, hechos en una sesión de Claude Code en la nube sobre la rama `mapa-inundacion`. Hubo dos intentos anteriores con la tarea programada: el primero se cortó a los 5 minutos y el segundo, a los pocos segundos, por el límite de uso. Esta vez se corrió desde una sesión normal.

Los agentes son los de Agency Agents de `.claude/agents/`. Como la sesión arrancó antes de clonar el repo, los primeros (Spatial Data Engineer, Mobile App Builder, Cartography Designer y Legal Compliance Checker) corrieron como agentes generales que leyeron y adoptaron su definición del repo. El resto ya se cargó con su tipo propio, salvo el Spatial Data Engineer, que siguió con el mismo método.

No hubo merge, PR, push a `main` ni force-push, y no se tocaron `data/` ni `lector.yml`.

## Por paso

### 1. Terminar la v1.1

- **Spatial Data Engineer (pipeline):** el test que fallaba (`test_hueco_que_toca_el_borde_de_limites_no_es_aislada`) era un bug del código. La tolerancia del borde ahora es de media unidad del último decimal publicado. También agregó validación de la config (`buffer_m ≥ simplify_m` y zonas sin validar completas), un test del PNG de control y la sección 9 del 06. Commit `4589c1c`.
- **Cartography Designer:** capas de zona baja, borde y rótulo de la zona sin validar, lomas aisladas tocables, línea de hoy, y puntos del margen encima cuando quedaría tapado. Agregó las filas de la leyenda y escribió el §7 del 08 (orden de capas, contrastes, daltonismo, modo oscuro). Ninguna capa tapa el agua.
- **Mobile App Builder:** los nombres de la zona sin validar desde el archivo, los grupos de tests de leyenda y dibujo v1.1, y la sección v1.1 del 07.
  - **Test bloqueante** (`app/test/mapa_v11_test.dart`, grupo "margen siempre"): el margen se elige y se dibuja con su estilo a 3,50, 4,00, 7,00, 10,50 y 11,20 m. Commits `fdb8c60` y `a172536`.

### 2. Pipeline v1.1 y assets

**No se corrió.** La política de red del entorno en la nube rechaza `visualizador.ide.uy` (MDT), `www.ambiente.gub.uy` (WFS de Dinagua) y `download.geofabrik.de` (OSM). Siguiendo la regla del 12, no se inventaron datos.

- **Los assets de `app/assets/mapa/` no se actualizaron:** siguen siendo los v1 (66 capas, 5 crecidas, `validado: false`).
- **Lo único que se agregó** es `LICENSE-DATOS.md`, que no está en el índice ni cambia ningún sha256.
- **Para correrlo:** en tu PC con Windows, o agregando esos tres dominios a la red del entorno en la nube.

Como no hubo salida nueva, el GIS QA Engineer tampoco la revisó.

### 3. Legal → `13-legal.md`

El Legal Compliance Checker encontró 3 bloqueantes, 7 importantes y 7 menores. Commit `9a66f4f`. Lo que entró al código en el paso 4:

- `LICENSE-DATOS.md`: declaración ODbL de la base derivada (B1).
- `textosFuentes` con la nota de origen completa de la IDE (B3).
- Dinagua "sin licencia publicada" (B2, parcial).
- El nombre completo de CARU.

### 4. Revisión de código → `14-revision-codigo.md`

El Code Reviewer encontró 1 bloqueante, 5 importantes, 9 menores y algunas sugerencias. Se arreglaron el bloqueante, los cinco importantes y la mayoría de los menores, cada uno con su test. Commits `d5299d7` (pipeline), `d2d2815` (app), `b72aab3` (CI) y `4475272` (informe 14). Los detalles y los abiertos están en el 14.

## Resultados

| Control | Antes | Después |
|---|---|---|
| `flutter analyze` (Flutter 3.47.7) | sin problemas | sin problemas |
| `flutter test` | 263 OK, 1 falla | **297 OK** |
| `pytest lector/tests/test_mapa_*.py` (venv del mapa, Python 3.12) | 76 OK, 1 falla | **113 OK** |
| `pytest` del lector (Python 3.12) | 283 OK, 5 salteados | **283 OK, 6 salteados** (los `test_mapa_*`, por falta de numpy) |
| GitHub Actions | — | "Tests de la app" y "Tests del lector" en verde, con el job nuevo `pytest-mapa` (113 tests en CI) |

No se armó el APK en la nube porque no hay SDK de Android. El APK lo arma el workflow "Tests de la app", que pasó.

## Abiertos

**Legales (del 13):**
- B2: la licencia de Dinagua sigue sin confirmar.
- I2: falta el descargo en la tarjeta de la primera vez.
- I3: falta el texto de "Limitaciones".
- I4: el repo no tiene `LICENSE` y el README no dice de dónde salen los datos.
- I5: el texto de la ficha de Play.
- I6: la consulta con un abogado.
- I7: el deslinde con Cecoed y la Intendencia.
- El 04 quedó desactualizado.
- Los menores M1 a M7.
- Separar `docs/mapa/mapa-real.html` (datos OSM, ODbL) del PR.

**De la revisión (del 14):**
- M4: parseo de capas en el hilo de la interfaz; medirlo en el Redmi.
- M5: lista blanca en el test de assets.
- M6: test bloqueante con datos reales.
- Las lomas aisladas no se pueden abrir con TalkBack.
- La caché de `descarga.py` nunca revalida.
- `requirements-ci.txt` se regenera a mano.

**Del pipeline:**
- Correr la v1.1 con datos reales.
- Anotar en el 06 §9 `celdas_afuera_total` (tiene que dar 0), los pesos, las hectáreas sin validar, las lomas por capa y `sin_dato_tierra_uy`.
- Los IoU pueden moverse un poco porque las curvas impares ahora suben en la grilla; δ no cambia.
- Después de correrla, la revisión del GIS QA Engineer contra el 11.

## Para el dueño

1. **Correr el pipeline v1.1** en tu PC con el venv de `lector/mapa/requirements.txt` y copiar a `app/assets/mapa/` solo `indice.json`, `base.json`, `agua/`, `curvas/` y `sin_validar.json` (07 §5). Después, `flutter test` y `flutter build apk --release`.
2. **Probar en el Redmi con TalkBack** (checklist del 10):
   - la zona baja, el borde sin validar, las marcas de loma y los puntos del margen a 3,50 y 10,50 m;
   - el aviso de margen recortado entre 10,10 y 10,50 m;
   - el peso de la línea de hoy en modo oscuro;
   - que el deslizador no se trabe (M4).
3. **Confirmar el cero de CARU** contra el de Dinagua.
4. **Mandar el correo a Dinagua** (13 §4.1) y, si no contestan, el pedido por Ley 18.381 (§4.2). Si no hay respuesta, decidir por escrito si se publica con las curvas o sin ellas.
5. **Elegir la licencia del código**, hacer la consulta con un abogado, avisar al Cecoed y preguntarle a CARU por sus condiciones.
6. **Dar el OK para el PR** a `main`, después de los puntos 1 a 4.
