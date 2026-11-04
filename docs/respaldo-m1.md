# Respaldo local con M-1 (segunda lectura antes del urgente)

Rama `respaldo-m1` (4/11/2026). Cierra el límite que quedaba en `docs/fase-4-avisos-push.md`: el respaldo
local de la app (`revisarNivel`: la app abierta y workmanager) mandaba el urgente con la **primera** lectura,
aunque el servidor (`lector/avisos.py`, PR #40) espera una segunda.

## Qué cambió

- `app/lib/confirmacion_urgente.dart` (nuevo, sin plugins): la regla M-1 del servidor "en marcha". Por cada
  nivel urgente (alerta, evacuación) guarda la subida en curso: la **candidata** (`generado`, fecha, altura y
  fuente de la primera lectura vista con ese nivel o más) y si ya se avisó. Con cada publicación nueva:
  - **confirma** si es del mismo nivel y trae una lectura con fecha mayor, de la misma fuente y con un salto
    de hasta 1 m (la misma cuenta que `_confirma`);
  - si no confirma, **sale por tope** en la primera publicación de ese nivel con `generado` 60 min o más
    después de la candidata (como el servidor: sale aunque la lectura no confirme, "nunca callar");
  - `dato_a_verificar` solo no frena (como el servidor: decide el salto). Si la publicación vista antes
    retenía ese mismo nivel (`nivel_retenido.nivel`), avisa de una;
  - bajar del nivel reinicia la espera; cada nivel avisa una vez por subida; si avisa evacuación, la alerta de
    esa subida ya no avisa; sin nivel anterior conocido no avisa.
- `app/lib/avisos.dart`: `decidirAvisos` usa esa regla para las tres puertas. Lo guardado va en
  SharedPreferences, clave `urgente_confirmacion` (JSON), junto a `ultimo_nivel` y `ultimo_nivel_generado`.
  Las preferencias se respetan igual que antes (urgente apagado, "Desde alerta", "Solo evacuación"; en una
  instalación nueva todo apagado hasta elegir, P-04). La subida avanza aunque el urgente esté apagado: prenderlo
  después no saca un aviso viejo. El resumen del día no cambió.
- `app/lib/modelos.dart`: `Actual.nivelRetenido` (lee `nivel_retenido.nivel`).
- **Push:** el servidor ya confirmó, así que un push urgente avisa de una si el dato bajado muestra ese nivel o
  más. Si el dato todavía no lo muestra (Pages atrasado), sale el genérico "hay novedades" como antes y el push
  **queda anotado**: la próxima revisión que vea la subida avisa sin esperar otra lectura. Se descarta si un
  dato posterior al envío ya no muestra la subida. La deduplicación entre push y respaldo es la misma marca:
  si una puerta avisó la subida, las otras no la repiten (también los dos pushes de evacuación).
- **Actualización desde la versión anterior:** si `ultimo_nivel` ya está en alerta o más y no hay nada
  guardado de M-1, esa subida se da por avisada (la versión anterior avisaba con la primera lectura).

## Revisiones espaciadas (workmanager puede no correr)

Workmanager corre cada 30 min si Android lo deja, y en los Xiaomi puede pasar horas sin correr. Decisión:

- El tiempo se mide con `generado` de las publicaciones, **nunca con el reloj del teléfono** (puede estar mal,
  y el servidor tampoco lo usa).
- Si al volver a revisar el río **ya bajó** del nivel, no sale nada: la subida terminó (no se manda un
  urgente viejo).
- Si el río **sigue** en el nivel y la lectura nueva confirma a la candidata, avisa (es el dato de ahora; el
  texto lleva la hora de la lectura). Con la misma lectura repetida (la estación no informó) sale por tope,
  como el servidor.
- Si pasaron **más de 60 min** desde la publicación vista antes y la lectura nueva **contradice** a la candidata
  (salto de más de 1 m, otra fuente o una fecha anterior), **no** sale por tope: el teléfono no vio lo del
  medio. Esa lectura pasa a ser la candidata y se espera otra. Con revisiones seguidas (menos de 60 min) el
  tope sale igual que en el servidor.
- Si el lector se corta después de la primera lectura, el teléfono tampoco avisa (necesita una publicación
  nueva, como el servidor). Antes el respaldo avisaba con la primera lectura y cubría ese caso; ya no.

## Pruebas

- `app/test/confirmacion_urgente_test.dart` (nuevo): la regla sola (candidata → confirmación, salto de más de
  1 m, justo 1 m, otra fuente, misma fecha, tope de 60 min, sin `generado`, `dato_a_verificar`, retención al
  mismo nivel y a otro, bajada y nueva subida, niveles mezclados, sin nivel anterior, lo guardado roto,
  actualización desde la versión anterior), revisiones espaciadas, push (antes y después del dato, anotado y
  descartado, push de alerta con el dato en evacuación), por `decidirAvisos` (preferencias apagadas, "Solo
  evacuación", P-04, `nivel_retenido`) y una propiedad con revisiones salteadas al azar (nunca con la primera
  lectura vista de la subida, nunca dos veces en la misma subida, solo el nivel que muestra el dato).
- **Mismos casos que el servidor:** `lector/tests/casos_m1.py` arma 220 secuencias (las de `test_avisos.py` y
  200 al azar, con y sin huecos de publicación), las decide con `avisos.decidir` y las escribe en
  `app/test/fixtures/casos_m1_servidor.json`. La prueba de la app las pasa por su regla y exige el mismo urgente
  en cada publicación. `lector/tests/test_casos_m1_app.py` falla si el archivo no está al día con `avisos.py`
  (regenerar con `python lector/tests/casos_m1.py`).
- Diferencias conocidas (3 casos, en `diferenciasConocidas` de la prueba): bordes en los que `avisos.py` no
  avisa nunca aunque el río siga horas en alerta, y la app sí (ver "Límites que quedan" en
  `docs/fase-4-avisos-push.md`). Si se corrige `avisos.py`, la prueba de la app falla hasta sacarlos de la lista.

## Cómo probarlo en el teléfono

Con datos de prueba en un gist, como en `docs/fase-4-informe-app.md` ("Datos de prueba sin tocar el
repositorio"), compilando con `--dart-define=URL_BASE=...` y `--dart-define=TEMAS_PRUEBA=true`. GitHub guarda
el raw en caché unos 5 minutos: después de cada edición, esperar antes de revisar. Para no esperar a
workmanager, la revisión se puede forzar abriendo la app o tirando para actualizar (con la app a la vista el
urgente se muestra igual; el resumen no).

1. Urgente prendido "Desde alerta". Gist en `atencion` (`generado` y `altura_actual.fecha` de hace unos
   minutos). Abrir la app y actualizar: no sale nada.
2. Gist a `alerta` con `generado` nuevo y `altura_actual.fecha` nueva. Actualizar: **no sale nada** (es la
   candidata).
3. Gist: misma `alerta`, `generado` y `altura_actual.fecha` 30 min más tarde, altura a menos de 1 m de la
   anterior. Actualizar: sale "Río Uruguay: subió a ALERTA". Actualizar de nuevo: nada.
4. Salto: empezar de cero en `atencion`. Candidata en `evacuacion` con 6,70 m; segunda lectura (fecha y
   `generado` nuevos) con 8,20 m: no sale (salto de más de 1 m); tercera con 6,80 m: sale "…subió a
   EVACUACIÓN".
5. Tope: candidata en `alerta` y después publicaciones con la **misma** `altura_actual.fecha` y `generado`
   cada vez más tarde: sale recién con `generado` 60 min o más después de la candidata.
6. Push: con la candidata del paso 2 sin confirmar, mandar `.\herramientas\enviar_aviso_prueba.ps1 -Tipo
   urgente -Nivel alerta` con la app cerrada: sale "subió a ALERTA" de una (el servidor ya confirmó). Después
   actualizar: nada.
7. Revisión espaciada: candidata en `alerta`; no abrir la app y poner en el gist una publicación con
   `generado` 2 h más tarde, misma altura y otra `altura_actual.fuente` (cambiar la altura podría cambiar el
   nivel que calcula la app con los umbrales): al abrir, nada (espera otra); con una más de esa misma fuente,
   sale.

Para empezar de cero entre casos: Ajustes, Aplicaciones, Mi Río UY, Almacenamiento, Borrar datos (vuelve el
primer arranque, con todo apagado).

## Diferencias que quedan con el servidor

- El teléfono solo ve lo que baja: si se salteó publicaciones, la candidata es la primera que vio, y puede
  avisar más tarde que el servidor (nunca antes, salvo con push o retención).
- La regla de "más de 60 min sin revisar y lectura que contradice" es solo del teléfono.
- La retención (`nivel_retenido`) solo cuenta si el teléfono vio la publicación que retenía.
- Un dato viejo servido por caché (una publicación anterior a la última vista) se toma como dato nuevo, igual
  que antes: si muestra un nivel más bajo, reinicia la subida y puede repetir el urgente con la confirmación
  siguiente.
- Los dos bordes en los que el servidor no avisa nunca (arriba): la app avisa.
