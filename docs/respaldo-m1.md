# Respaldo local con M-1 (segunda lectura antes del urgente)

Rama `respaldo-m1` (4/11/2026). Cierra el límite que quedaba en `docs/fase-4-avisos-push.md`: el respaldo
local de la app (`revisarNivel`: la app abierta y workmanager) mandaba el urgente con la **primera** lectura,
aunque el servidor (`lector/avisos.py`, PR #40) espera una segunda.

## Qué cambió

- `app/lib/confirmacion_urgente.dart` (nuevo, sin plugins): la regla M-1 del servidor "en marcha". Por cada
  nivel urgente (alerta, evacuación) guarda la subida en curso: la **candidata** (`generado`, fecha, altura y
  fuente de la primera lectura vista con ese nivel o más), si ya se avisó y con qué publicación. Con cada
  publicación nueva:
  - **confirma** si es del mismo nivel y trae una lectura con fecha mayor, de la misma fuente y con un salto
    de hasta 1 m (la misma cuenta que `_confirma`);
  - si no confirma, **sale por tope** en la primera publicación de ese nivel con `generado` 60 min o más
    después del `generado` más temprano de las publicaciones vistas en la subida (normalmente la candidata; el
    más temprano por si el reloj no crece, como el servidor desde #46), aunque la lectura no confirme ("nunca
    callar");
  - `dato_a_verificar` solo no frena (como el servidor: decide el salto);
  - si la publicación vista justo antes (hasta 40 min antes) retenía ese mismo nivel (`nivel_retenido.nivel`),
    avisa la primera publicación de ese nivel de la subida: de una, o más tarde si la subida arrancó en un nivel
    más alto (se retuvo alerta y se soltó en evacuación: la alerta sale al volver a alerta, salvo que antes se
    confirme la evacuación; como el servidor desde #46). Es el `pub_antes` del servidor; una retención vista
    hace horas no cuenta. Son 40 min y no
    menos porque el lector solo publica cuando algo cambia (`guardar_actual`) y la estación informa cada
    30 min: la publicación que suelta la retención suele llegar ~30 min después de la que retenía;
  - bajar del nivel reinicia la espera; cada nivel avisa una vez por subida; si avisa evacuación, la alerta de
    esa subida ya no avisa; sin nivel anterior conocido no avisa.
- `app/lib/avisos.dart`: `decidirAvisos` usa esa regla para las tres puertas. Todo lo del urgente va **junto,
  en una sola clave** de SharedPreferences, `urgente_confirmacion` (JSON): último nivel con dato visto y su
  `generado`, las subidas en curso, la última retención vista y un push anotado. Reemplaza a `ultimo_nivel` y
  `ultimo_nivel_generado`: si todavía no hay nada guardado se leen esas, y se borran después de la primera
  escritura. Las preferencias se respetan igual que antes (urgente apagado, "Desde alerta", "Solo
  evacuación"; en una instalación nueva todo apagado hasta elegir, P-04). La subida avanza aunque el urgente
  esté apagado: prenderlo después no saca un aviso viejo. El resumen del día no cambió.
- **Caché vieja:** una publicación con `generado` anterior a la última vista no cambia nada (si no, un nivel más
  bajo reiniciaría la subida y el urgente se repetiría). Excepción: si lo último visto es de más de 6 h después
  del reloj del teléfono, no se usa para esto (un `generado` mal puesto en el futuro no congela los avisos).
- `app/lib/modelos.dart`: `Actual.nivelRetenido` (lee `nivel_retenido.nivel`).
- **Push:** el servidor ya confirmó, así que un push urgente avisa de una si el dato bajado muestra ese nivel o
  más. Si el dato todavía no lo muestra (Pages atrasado), no se pudo bajar o es una copia vieja, sale el
  genérico "hay novedades" como antes y el push **queda anotado**: la próxima revisión que vea la subida avisa
  sin esperar otra lectura. Se descarta si un dato posterior al envío ya no muestra la subida.
- **Deduplicación:** si una puerta avisó la subida, las otras no la repiten (también los dos pushes de
  evacuación). La corrección de "bajada no vista" del push (lo último visto es de más de 20 min antes del envío
  y ya estaba en ese nivel) no se aplica si el propio teléfono avisó esa subida dentro de los 80 min
  (60 de espera + 20 de envío) anteriores al envío: es el mismo aviso, que el teléfono dio antes que el servidor.
- **Actualización desde la versión anterior:** si `ultimo_nivel` ya está en alerta o más y no hay nada
  guardado de M-1, esa subida se da por avisada (la versión anterior avisaba con la primera lectura).

### Lo que se puede perder

- Lo guardado se escribe **antes** de mostrar la notificación. Si Android mata el proceso entre las dos cosas,
  ese urgente queda como avisado y no se muestra (se prefiere a repetirlo en cada revisión). Si fue un push que
  tuvo que esperar el dato, el genérico "hay novedades" ya se mostró.
- Entre isolates distintos (push con la app cerrada y workmanager a la vez) no hay candado: en una ventana de
  milisegundos los dos pueden leer lo mismo. En el peor caso avisan los dos (la segunda notificación reemplaza
  a la primera: mismo número) o el que escribe último pisa lo del otro (una candidata nueva o un push anotado),
  y se rehace en la revisión siguiente. Dentro de un mismo isolate las decisiones van de a una.

## Revisiones espaciadas (workmanager puede no correr)

Workmanager corre cada 30 min si Android lo deja, y en los Xiaomi puede pasar horas sin correr. Decisión:

- El tiempo se mide con `generado` de las publicaciones, **nunca con el reloj del teléfono** (puede estar mal,
  y el servidor tampoco lo usa).
- Si al volver a revisar el río **ya bajó** del nivel, no sale nada: la subida terminó (no se manda un
  urgente viejo).
- Si el río **sigue** en el nivel, la regla es la del servidor: sale si la lectura nueva confirma a la candidata
  o si su `generado` está 60 min o más después del más temprano de la subida, aunque no confirme (salto, otra fuente o la
  misma lectura repetida). El texto lleva la hora de la lectura. Se probó frenar el tope cuando el teléfono no
  vio lo del medio, pero podía callar el urgente para siempre (fuentes que se alternan, un salto sostenido, o un
  lector que publica cada más de 60 min), así que no se hace.
- Si el lector se corta después de la primera lectura, el teléfono tampoco avisa (necesita una publicación
  nueva, como el servidor). Antes el respaldo avisaba con la primera lectura y cubría ese caso; ya no.

## Pruebas

- `app/test/confirmacion_urgente_test.dart` (nuevo): la regla sola (candidata → confirmación, salto de más de
  1 m, justo 1 m, otra fuente, misma fecha, tope de 60 min, tope desde el `generado` más temprano, sin
  `generado`, `dato_a_verificar`, retención al mismo nivel, a otro nivel, soltada en evacuación con alerta
  después, y vieja, bajada y nueva subida, niveles mezclados, sin nivel anterior, lo guardado
  roto, actualización desde la versión anterior), revisiones espaciadas (fuentes alternadas y salto sostenido
  no callan), push (antes y después del dato, sin poder bajarlo, anotado y descartado, el teléfono avisó antes
  que el servidor, bajada no vista), por `decidirAvisos` (preferencias apagadas, "Solo evacuación", P-04,
  `nivel_retenido`, caché vieja, migración de las claves viejas) y propiedades con revisiones salteadas al azar:
  nunca con la primera lectura vista de la subida, nunca dos veces en la misma subida, solo el nivel que
  muestra el dato, y **vivacidad**: si el servidor avisó en una subida y el teléfono vio antes una publicación
  más baja y 2 o más lecturas de ese nivel con 60 min o más entre ellas, el teléfono termina avisando.
- **Mismos casos que el servidor:** `lector/tests/casos_m1.py` arma 321 secuencias (las de `test_avisos.py`,
  los dos bordes que corrigió #46, un reloj que no crece, 100 cada 10 min, 100 con huecos de publicación y 100 con huecos, cambios de fuente y saltos de 1,5 m), las
  decide con `avisos.decidir` y las escribe en `app/test/fixtures/casos_m1_servidor.json`. La prueba de la app
  las pasa por su regla y exige el mismo urgente en cada publicación. `lector/tests/test_casos_m1_app.py` falla
  si el archivo no está al día con `avisos.py` (regenerar con `python lector/tests/casos_m1.py`); el workflow de
  tests de Python también corre si cambia el fixture.
- **Sin diferencias:** la app coincide con el servidor en las 321 secuencias, publicación por publicación
  (`diferenciasConocidas` está vacía). Antes de #46 había 3: dos bordes en los que `avisos.py` callaba una
  alerta sostenida (retención de alerta soltada en evacuación; evacuación de una sola lectura tras un hueco de
  más de 2 h) y un caso al azar con el segundo borde. Los encontró esta comparación y se corrigieron en el
  servidor; la app llevó además el tope medido desde el `generado` más temprano.

## Cómo probarlo en el teléfono

Con datos de prueba en un gist, como en `docs/fase-4-informe-app.md` ("Datos de prueba sin tocar el
repositorio"), compilando con `--dart-define=URL_BASE=...` y `--dart-define=TEMAS_PRUEBA=true`. GitHub guarda
el raw en caché unos 5 minutos: después de cada edición, esperar antes de revisar. Para no esperar a
workmanager, la revisión se puede forzar abriendo la app o tirando para actualizar (con la app a la vista el
urgente se muestra igual; el resumen no). Cada publicación nueva del gist tiene que tener un `generado` más
nuevo que la anterior (una más vieja se ignora como caché).

1. Urgente prendido "Desde alerta". Gist en `atencion` (`generado` y `altura_actual.fecha` de hace unos
   minutos). Abrir la app y actualizar: no sale nada.
2. Gist a `alerta` con `generado` nuevo y `altura_actual.fecha` nueva. Actualizar: **no sale nada** (es la
   candidata).
3. Gist: misma `alerta`, `generado` y `altura_actual.fecha` 30 min más tarde, altura a menos de 1 m de la
   anterior. Actualizar: sale "Río Uruguay: subió a ALERTA". Actualizar de nuevo: nada.
4. Salto: empezar de cero en `atencion`. Candidata en `evacuacion` con 6,70 m; segunda lectura (fecha y
   `generado` 30 min más tarde) con 8,20 m: no sale (salto de más de 1 m); tercera, 30 min después, con 6,80 m:
   sale "…subió a EVACUACIÓN".
5. Tope: candidata en `alerta` y después publicaciones con la **misma** `altura_actual.fecha` y `generado`
   cada vez más tarde: sale recién con `generado` 60 min o más después de la candidata (con un `generado` que
   crece; uno más viejo que el último visto se ignora como caché).
6. Push: con la candidata del paso 2 sin confirmar, mandar `.\herramientas\enviar_aviso_prueba.ps1 -Tipo
   urgente -Nivel alerta` con la app cerrada: sale "subió a ALERTA" de una (el servidor ya confirmó). Después
   actualizar: nada.
7. Push sin dato: con el teléfono en modo avión justo después de que llegue el push no se puede forzar; en su
   lugar, compilar con `URL_BASE` a una dirección que no existe, mandar el push (sale "hay novedades"),
   volver a instalar encima la compilación con el gist (sin borrar datos) y actualizar con el gist en `alerta`:
   sale "subió a ALERTA" sin esperar otra lectura.

Para empezar de cero entre casos: Ajustes, Aplicaciones, Mi Río UY, Almacenamiento, Borrar datos (vuelve el
primer arranque, con todo apagado).

## Diferencias que quedan con el servidor

Viendo las mismas publicaciones deciden lo mismo (ver "Sin diferencias" arriba). Las diferencias vienen de lo
que el teléfono no ve:

- El teléfono solo ve lo que baja. Si se salteó publicaciones, puede avisar **más tarde** que el servidor (su
  candidata es la primera que vio) y también **antes**: si no vio una bajada del medio, la subida siguiente
  le parece la misma, y la publicación que para el servidor es una candidata nueva al teléfono le confirma (o
  le vence el tope de) una candidata vieja. También avisa antes con un push o con una retención.
- La retención (`nivel_retenido`) solo cuenta si el teléfono vio la publicación que retenía, y hasta 40 min
  antes (el servidor mira la publicación anterior, sin límite de tiempo).
- Caché vieja: `decidirAvisos` ignora una publicación con `generado` anterior a la última vista (la comparación
  con el servidor pasa por `pasoM1` directo, que sí la cuenta como el servidor). Si el reloj del lector
  retrocede de verdad (un revert o un commit a mano), el teléfono deja de mirar hasta que `generado` vuelva a
  pasar el último visto; el servidor sigue decidiendo. Se eligió así para no repetir urgentes por una copia
  vieja servida por caché.
