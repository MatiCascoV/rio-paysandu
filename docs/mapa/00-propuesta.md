# Pestaña "Mapa": propuesta unificada

Rama `mapa-inundacion` · 19/10/2026 · Sin código de la app todavía. `main` no se toca hasta el OK final.

Este documento junta y decide entre los cuatro informes del equipo:

| Documento | Agente | Tema |
|---|---|---|
| [01-datos-y-pipeline.md](01-datos-y-pipeline.md) | Spatial Data Engineer | Dinagua, modelo de terreno de IDE, cálculo y calibración |
| [02-tecnologia-app.md](02-tecnologia-app.md) | Mobile App Builder | Librería de mapa, arquitectura, caché, pruebas |
| [03-diseno-visual.md](03-diseno-visual.md) + [maqueta.html](maqueta.html) | UI Designer | Pantalla, estados, textos, accesibilidad, flujos |
| [04-licencias-y-textos.md](04-licencias-y-textos.md) | Legal Compliance Checker | Licencias, atribución, deslindes, privacidad, correos |
| [mapa-real.html](mapa-real.html) | (orquestador) | Vista previa con calles reales de OSM y las 7 curvas de Dinagua |

Vistas publicadas: maqueta https://claude.ai/artifact/1oTspgWKky8Cbp7AmK9xs4 · mapa real https://claude.ai/artifact/1Y5uJUi7ZuayEaAWnbWZci

## 1. Qué hace la pestaña

Una quinta pestaña, **Mapa**, entre Gráfico y Qué hacer. Muestra la costa de Paysandú con calles reales y pinta hasta dónde llegaría el agua:

- con la **altura de hoy** (la misma que usa Gráfico, de `actual.json`);
- con cualquier otra altura elegida con un deslizador o con botones − / + de 10 cm;
- con botones de referencia: pronóstico de CARU, alerta (4,39 m), evacuación (6,89 m) y las crecidas reales de Dinagua (jul 2025 6,58 · jun 2017 8,35 · ene 2019 8,45 · nov 2009 8,93 · dic 2015 9,12).

Además, **"Mi casa"**: el usuario toca el mapa, el punto queda solo en el teléfono y la app dice "el agua llegaría a tu casa con el río en aprox. X m; podría ser hasta 50 cm antes", y cuánto falta desde hoy. Nunca dice "estás a salvo".

## 2. Decisiones tomadas (y por qué)

| Tema | Decisión | Motivo |
|---|---|---|
| Librería de mapa | `flutter_map` 8.3.x | Dart puro: no agrega código nativo que choque con AGP 9.4.1 / Kotlin 2.4.21 ni con el control aapt2 del CI; se puede probar con widget tests y goldens. |
| Mapa base | GeoJSON propio sacado de OpenStreetMap, **dentro del APK** | Funciona sin internet en plena crecida. Ya probado: el recorte de Paysandú pesa 269 KB. Se descarta `tile.openstreetmap.org` (su política prohíbe este uso) y MapLibre (varios MB nativos por arquitectura). La opción PMTiles del informe 04 queda como plan B. |
| Calles con nombre | Sí: nombres de calles y barrios de OSM dentro del mismo `base.json`. Al acercar aparecen más; un control evita que se pisen (barrios primero, después avenidas, después calles) | Pedido del usuario el 19/10. Ya funciona en la vista previa; en la app se hace con la capa de rótulos de `flutter_map` y la misma prioridad. |
| Agua | Polígonos **precalculados cada 10 cm** con el modelo de terreno de IDE (1 m, 2017), calibrados contra las curvas reales de Dinagua | Es lo único que cubre cualquier altura. Las curvas de Dinagua solas no alcanzan: no hay nada por debajo de 6,58 m (hoy el río está en 5,68) y no están anidadas. |
| Respaldo | Si la calibración no da (IoU en tierra < 0,70), la app muestra **solo las curvas de Dinagua** en escalón, como la vista previa | Es lo honesto: dato oficial, sin inventar entre eventos. |
| Color del agua | Siempre azul; rayado = agua a la altura elegida; punteado = margen de duda de 50 cm hacia afuera; línea gruesa = borde de hoy | Se distingue sin depender del color (daltonismo). El nivel (alerta, evacuación) va en texto. |
| Límites del mapa | lon −58,150 a −58,030 · lat −32,365 a −32,240 | Cubre todas las curvas reales (el borrador de 02 cortaba el norte y el oeste). |
| Mi casa | Primera versión: **tocar el mapa**, sin GPS ni permisos | Sin permisos no hay nada que declarar en Play. El GPS ("Usar mi ubicación", solo en primer plano) queda para después. |
| Datos publicados | `data/mapa/indice.json` + `data/mapa/agua/NNNN.json` + `base.json`, con `cero: "Local"`, `validado: false`, sha256 y tope de bytes | Mismo esquema que los JSON actuales. Si el `cero` del mapa no coincide con el de `actual.json`, no se pinta la altura de hoy. |
| Cálculo | Proceso **aparte del lector**, a mano (`workflow_dispatch`), no en el cron de 15 min | Las capas solo cambian si cambia el terreno o la calibración. |
| Licencias | Atribución a OSM (ODbL), IDE (Licencia de Datos Abiertos, "datos modificados") y Dinagua; pantalla "Fuentes y licencias" | El `base.json` que publiquemos es una base derivada de OSM: va con licencia ODbL. |

## 3. Riesgos principales

1. **El cero de la altura.** El modelo de terreno usa EGM2008, no el cero de la escala de CARU. Estimación preliminar: terreno ≈ cota local + 0,66 m (±0,2). Un error de 1 m corre el borde varias cuadras, por eso la calibración es el primer paso y decide si seguimos.
2. **Lo que el modelo no ve:** agua que sube por pluviales, lluvia local, crecidas propias de los arroyos Sacra y La Curtiembre, obras posteriores a 2017. Se dice en pantalla.
3. **Licencia de las curvas de Dinagua:** son públicas, pero sin licencia escrita. Hay que pedir confirmación por correo antes de publicar la app (no antes de prototipar).
4. **Margen:** ±0,3 m en altura; el borde se puede correr una cuadra o más en zonas planas. Se muestra como banda, no como línea exacta.

## 4. Plan paso a paso

Cada paso termina con algo que se puede ver o probar, y nada pasa a `main` sin tu OK. Agentes según la tabla de PROMPT_MAESTRO más los de GIS.

| # | Paso | Agentes | Entrega y cómo se prueba | Decisión al terminar |
|---|---|---|---|---|
| 0 | Correos a Dinagua (licencia y cero de `cota_local`) y al Cecoed (si tiene mapas por cota) | Vos; borradores en 04 §4 | Respuestas guardadas en `docs/mapa/` | No frena los pasos 1 a 7 |
| 1 | **Prototipo del modelo de terreno**: bajar las 43 hojas (133 MB), relleno conectado al río, calibrar δ contra las 5 crecidas | Spatial Data Engineer + Geoprocessing Specialist; GIS QA Engineer revisa | Informe con δ, IoU por crecida y peso real; la vista previa `mapa-real.html` pinta la altura de hoy | **¿IoU ≥ 0,70?** Sí → modelo. No → respaldo con curvas |
| 2 | Pipeline reproducible en `lector/mapa/` + `.github/workflows/mapa.yml` (solo a mano) que publica `data/mapa/` | Data Engineer + DevOps Automator; API Tester | Tests pytest (validez, anidado, tope de bytes); corrida verde en Actions **en la rama** | Revisar archivos antes de publicarlos |
| 3 | Prueba de `flutter_map` en CI: agregar la dependencia y compilar el release | Mobile App Builder | `app.yml` verde; cuánto crece el APK | Si algo choca, plan B |
| 4 | `enum Pestana` + quinta pestaña vacía + prueba de desborde con 5 etiquetas a 320 dp | Minimal Change Engineer | Tests de navegación que ya existen, pasando | — |
| 5 | `RepositorioMapa` (descarga con tope, caché por versión, validación del `cero`) | Mobile App Builder; API Tester | Pruebas unitarias | — |
| 6 | Pantalla: fondo, agua, deslizador, botones, estados (normal, crecida, sin conexión, dato viejo, sin dato) | Mobile App Builder + UI Designer; Accessibility Auditor | Widget tests + goldens claro/oscuro; prueba en el Redmi | Ajustes visuales |
| 7 | "Mi casa" con toque en el mapa | Mobile App Builder | Pruebas unitarias del cálculo; prueba en el Redmi | ¿Agregar GPS? |
| 8 | Textos: aviso de primera vez, pie, "Fuentes y licencias", README | Technical Writer + Legal Compliance Checker | Textos en la app y en el repo | — |
| 9 | Cierre: revisión de código, prueba con un vecino simulado, verificación con evidencia | Code Reviewer, Persona Walkthrough Specialist, Evidence Collector + Reality Checker | Informe; APK en el Redmi | **Tu OK para el PR a `main`** |

Los pasos 1 y 3 son independientes y se pueden hacer en paralelo. Del 4 al 7 tocan los mismos archivos de la app y van en orden.

## 5. Lo que tenés que decidir

1. **Arrancar por el paso 1** (prototipo del modelo de terreno) y, en paralelo, el 3. Recomendado.
2. **Mi casa:** solo tocar el mapa en la primera versión (recomendado) o también GPS.
3. **Correos (paso 0):** si los mandás vos o te dejo los borradores en tu Gmail, como con CARU.
4. **Ciudades:** la pestaña aparece solo para Paysandú hasta tener datos de otras ciudades (Salto y Bella Unión tienen curvas en Dinagua).
