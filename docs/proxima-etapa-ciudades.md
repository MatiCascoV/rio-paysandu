# Próxima etapa: varias ciudades y Google Flood Hub

Estado: **investigado, sin empezar** (16/10/2026). Va después del rediseño de Inicio.

Objetivo: que cada persona elija su ciudad (por ejemplo Salto o Bella Unión) y la app le muestre
la altura, la tendencia, el pronóstico y los avisos de ese punto del río Uruguay.

Marcas: **[V]** verificado (página de CARU, fixture del repo, PDF leído o sitio renderizado);
**[I]** inferencia o dato sin confirmar en la fuente primaria.

## 1. Qué publica CARU

Registro de alturas: `http://190.0.152.194:8080/alturas/web/user/alturas` [V]
(coincide con la fixture `lector/tests/fixtures/registro_alturas_2026-10-09.html`).

### Puertos (lectura manual de Prefectura) — `/alturas/web/user/altura/{id}`

| id | Puerto | Período |
|---|---|---|
| 15 | Monte Caseros | 12 h |
| 27 | Bella Unión | 24 h |
| 16 | Mocoretá | 12 h |
| 17 / 34 | Federación / Federación Embalse | 12 h |
| 33 / 32 | Salto Grande aguas arriba / aguas abajo | 12 h |
| 29 | Salto | 24 h |
| 18 | Concordia | 6 h |
| 12 | Colón | 8 h |
| 24 | Paysandú | 24 h |
| 13 | Concepción del Uruguay | 12 h |
| 30 | Campichuelo | 12 h |
| 26 | Fray Bentos | 24 h |
| 31 | Boca del Gualeguaychú | 24 h |
| 25 | Nueva Palmira | 24 h |

### Estaciones automáticas — `/alturas/web/user/estacion/{id}/0`

| id | Estación | Período | Nota |
|---|---|---|---|
| 19 | Paysandú | 30 min | la que usa hoy la app |
| 20 | Concepción del Uruguay | 1 h | sin datos desde el 09/05/2026 |
| 48 | Concepción del Uruguay SIPH | 1 h | |
| 37 | Fray Bentos | 1 h | |
| 21 | Boca del Gualeguaychú | 1 h | |
| 22 | Nueva Palmira | 30 min | |

- **Salto, Bella Unión y Concordia no tienen estación automática** [V]: solo el dato de Prefectura
  (1 a 4 por día). La app tiene que decirlo ("se mide una vez por día") y ajustar cuándo un dato es viejo
  por ciudad, no con un valor único.
- Todas las filas usan el mismo selector de cero (Local, Wharton, Oficial ROU, MOP) [V].

### Pronóstico en los informes de crecida (PDF)

- La tabla "Alturas esperadas" trae solo 5 puertos: Colón, Paysandú, Concepción del Uruguay,
  Fray Bentos y Boca del Gualeguaychú, con altura esperada, alerta y evacuación [V].
- Salto y Concordia aparecen solo en el texto ("no superarán 11,70 y 12,00 m") [V].
- Bella Unión, Monte Caseros y Nueva Palmira: sin pronóstico [V].
- El formato del informe cambió entre 2016 y 2026 [V]: el parser tiene que tolerar tablas distintas y
  dejar el pronóstico vacío antes que inventar un número.

## 2. Umbrales por ciudad

No hay una tabla oficial única de Sinae o de los Cecoed [I]. Lo encontrado:

| Ciudad | Alerta (m) | Evacuación (m) | Fuente |
|---|---|---|---|
| Colón | 7,10 | 7,90 | informes CARU 2016 y 2026 [V] |
| Concepción del Uruguay | 5,30 | 6,30 | informes CARU 2016 y 2026 [V] |
| Fray Bentos | 3,90 | 5,40 | informes CARU 2026 [V] |
| Boca del Gualeguaychú | 2,90 | 3,10 | informes CARU 2016 y 2026 [V] |
| Concordia | 11,00 | 12,50 | informe CARU 01/01/2016 [V] |
| Salto | 12,00 | sin dato | informe CARU 01/01/2016 [V]; la prensa cita 11, 12,20 y 12,30 [I] |
| Bella Unión | sin dato | sin dato | Dinagua da "nivel de seguridad" 6,30 (informe Nº3, 07/09/2023) [V] |
| Paysandú | 4,39 | 6,89 | informes CARU 2026 [V]; 2016 decía alerta 5,50; el Cecoed habló de 5,80 como cota de seguridad (prensa, 25/07/2026) [I] |

Fuentes:
- Informe CARU 01/01/2016: https://caru.org.uy/web/informesprensa/INFORME%20CRECIDA%20DEL%20RIO%20URUGUAY%201%20DE%20ENERO%20DE%202016.pdf
- Dinagua, Informe de Situación y Pronóstico Nº3: https://www.gub.uy/ministerio-ambiente/sites/ministerio-ambiente/files/documentos/publicaciones/Informe_Situacion_y_Pronostico_07_09_2023.pdf
- Información hidrológica de Dinagua: https://www.gub.uy/ministerio-ambiente/politicas-y-gestion/encontrar-informacion-hidrologica-uruguay
- Montevideo Portal, 25/07/2026: https://www.montevideo.com.uy/Noticias/Proyectan-crecida-del-rio-Uruguay-que-podria-provocar-inundaciones-donde-y-que-se-espera-uc969538

Reglas:
- Cada ciudad lleva `"validado": false` hasta que lo confirme su Cecoed (o el organismo argentino que corresponda).
- Si una ciudad no tiene umbrales, la app muestra la altura y la tendencia **sin colores de nivel**,
  y lo dice ("Para esta ciudad no hay niveles de alerta publicados").
- Los umbrales siguen fuera de la app, en `data/` (regla del §9 de `PROMPT_MAESTRO.md`).

## 3. Google Flood Hub

Sistema de Google que pronostica crecidas de ríos hasta 7 días antes. Uruguay, Argentina y Brasil están
cubiertos [V] (https://support.google.com/flood-hub/answer/16508958).

Puntos sobre el río Uruguay [V]: son puntos virtuales del modelo (fuente HYBAS), no estaciones, y
pronostican **caudal en m³/s, no altura**.

| Punto | Id | Advertencia | Peligro | Extremo (m³/s) |
|---|---|---|---|---|
| Paysandú | `hybas_6121320620` | 16.002 | 20.685 | 26.289 |
| Aguas abajo de Salto Grande | `hybas_6120865460` | 15.558 | 20.219 | 25.705 |
| Zona Chapicuy | `hybas_6120869750` | 16.165 | 20.943 | 26.603 |

Bella Unión no tiene punto; el más cercano es Uruguaiana (`ANA_77150000`, en metros, datos de Defensa
Civil de Brasil) [V].

### Formas de integrarlo

1. **Enlace por ciudad (se puede ya).** Cada punto tiene una URL estable, por ejemplo
   https://sites.research.google/floods/l/-32.32659651806086/-58.11492919921875/10/g/hybas_6121320620 .
   No necesita cuenta ni aceptar términos. Texto sugerido: "Pronóstico de Google Flood Hub
   (estimación informativa; la alerta oficial es la del Cecoed)".
2. **API (con condiciones).** https://developers.google.com/flood-forecasting
   - Hay que anotarse en lista de espera y usar un proyecto de Google Cloud con clave [V].
   - Es gratis y los datos tienen licencia **CC BY 4.0**: se pueden mostrar y guardar con atribución [V].
   - Rigen además los Términos de las APIs de Google (https://developers.google.com/terms) [V]:
     §6(b) atribución obligatoria; §5(e)(1) límites de caché (la CC BY 4.0 lo permitiría, lectura [I]);
     **§4(a)(7) prohíbe usar las APIs en actividades donde una falla pueda causar muerte o lesiones** [V].
     Una app que la gente usa para decidir si evacua puede entrar en esa cláusula [I]: hay que
     consultarlo con Google al pedir el acceso.
3. **Embeber el sitio: no.** No hay forma oficial de embeberlo y no está respaldado por los términos [I].

### Decisión propuesta

- Etapa 1: **solo el enlace** por ciudad, en "Más datos".
- Etapa 2 (opcional): pedir acceso a la API, mostrar solo puntos con `qualityVerified=true`, como
  caudal y nivel de severidad (sin convertir a metros), con atribución "Google Flood Hub, CC BY 4.0",
  y **nunca** usarlo para disparar avisos.

## 4. Plan

1. **Lector multi-ciudad.** Lista de ciudades en `data/ciudades.json` (id de puerto, id de estación si
   hay, período esperado, enlace a Flood Hub). Un archivo por ciudad:
   `data/ciudades/<id>/actual.json` e `historial.json`. Paysandú sigue también en las rutas de hoy
   para no romper las apps instaladas. Tests con la fixture actual, que ya trae todas las filas.
2. **Pronóstico por ciudad** desde la tabla del PDF (5 puertos); el resto sin pronóstico.
3. **Umbrales por ciudad** en `data/umbrales.json` (formato nuevo con una entrada por ciudad,
   cada una con su fuente y `validado`). Pedir confirmación a los Cecoed de Salto, Artigas (Bella Unión),
   Río Negro (Fray Bentos) y Colonia (Nueva Palmira).
4. **App:** elegir ciudad en el primer uso y en Ajustes; la app la recuerda; el título dice la ciudad.
   Sin umbrales, sin colores de nivel. Frecuencia de medición a la vista.
5. **Avisos** solo de la ciudad elegida (y en la Fase 4, un tema de push por ciudad).
6. **Flood Hub:** enlace por ciudad (etapa 1). La API queda como decisión aparte.
