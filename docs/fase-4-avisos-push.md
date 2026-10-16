# Fase 4: avisos push

Estado: **planificada, sin empezar** (16/10/2026).

Objetivo: que el aviso de cambio de nivel llegue al teléfono **con la app cerrada**, en minutos, sin
depender de que Android deje correr la revisión periódica (los Xiaomi la cortan seguido).

**Aceptación** (de `PROMPT_MAESTRO.md`, ampliada):
- En el Redmi, con la app cerrada y sin abrirla en el día, llega el aviso dentro de los 15 minutos de que
  el lector publica un cambio de nivel.
- El texto del aviso sale de `actual.json`, nunca del mensaje push.
- Un cambio de nivel produce un solo aviso (ni el push y la revisión local por duplicado, ni idas y vueltas
  cuando el río oscila sobre el umbral).
- Apagar los avisos en la app deja de recibirlos.

## Cómo funciona

1. El lector publica datos nuevos (como hoy).
2. Si cambió `nivel` (o el pronóstico pasa a superar un umbral), el workflow lanza el envío.
3. Un workflow aparte, `avisos.yml`, compara con la publicación anterior y manda **un mensaje push sin texto**
   al tema de la ciudad (`nivel-paysandu`) por Firebase Cloud Messaging (FCM).
4. El teléfono recibe el mensaje aunque la app esté cerrada, baja `actual.json` y arma el aviso con la misma
   lógica que ya usa la revisión local (`revisarNivel`).
5. La revisión periódica local sigue como respaldo; las dos comparten la marca del último nivel avisado,
   así que nunca avisan dos veces.

## Decisiones de diseño

| Tema | Decisión | Por qué |
|---|---|---|
| Contenido del push | Solo datos (`{"tipo":"nivel","ciudad":"paysandu"}`), prioridad alta, sin título ni texto | Si alguien robara la credencial de envío, no podría mostrar un texto falso como "Evacuar ya": la app solo muestra lo que dice `actual.json`. |
| Destinatarios | Temas de FCM, uno por ciudad (`nivel-<ciudad>`) | No hay que guardar tokens ni datos de nadie; sirve tal cual para la Fase 4.b. |
| Credencial | Identidad federada de GitHub (OIDC) contra Google Cloud, sin clave JSON | No hay secreto de larga duración que se pueda filtrar. La cuenta de servicio solo puede enviar mensajes de FCM y solo la acepta el workflow `avisos.yml` de `main`. |
| Quién decide si avisar | Una función del lector (`lector/avisos.py`), con tests | La regla queda en un solo lugar, probada con fixtures, igual que el resto del lector. |
| Idas y vueltas | Margen al bajar: para pasar a un nivel menor, la altura tiene que quedar **5 cm** por debajo del umbral (`margen_bajada_m` en `lector/config.json`) | Evita avisos "subió" y "bajó" seguidos cuando el río está justo en el umbral. Se aplica en el `nivel` que calcula el lector, así la app y el push coinciden. El valor se confirma con el Cecoed (consulta 9). |
| Respaldo | Se mantiene `workmanager` cada 30 min | Si el push no llega (sin Google Play Services, restricciones del fabricante), el aviso llega igual, más tarde. |

**Riesgo a probar primero:** los mensajes de solo datos dependen de que Android despierte la app. En
algunos Xiaomi hace falta activar "Inicio automático" y quitar la restricción de batería. Si en la prueba
del paso 3 no llegan de forma confiable, la alternativa es un push **con** texto fijo y neutro ("Cambió el
nivel del río. Tocá para ver el dato"), que el sistema muestra solo; se pierde parte de la protección de la
primera fila, porque el texto lo pondría el mensaje. Esa decisión se toma con los resultados de la prueba.

## Separar los datos del código (antes del envío)

Hoy el trabajo que procesa contenido de CARU sube commits a `main`, aunque se niega a subir cambios fuera de
`data/`. Con credenciales de envío en juego conviene separarlos:

- El lector publica en una rama **`datos`**, y GitHub Pages pasa a publicar esa rama. Las direcciones
  `https://maticascov.github.io/rio-paysandu/data/...` no cambian, así que las apps instaladas siguen andando.
- `avisos.yml` vive en `main` y se lanza con `workflow_dispatch` desde el workflow del lector (como el
  trabajo `relanzar` que ya existe), con el commit de `datos` como entrada. Así siempre corre la versión de
  `main`, que es la única que la credencial acepta.

## Pasos

| # | Paso | Quién | Tamaño |
|---|---|---|---|
| 1 | Crear el proyecto de Firebase "Mi Río UY" con la cuenta de Google del dueño y registrar la app `uy.miriouy.app`. Bajar `google-services.json` (no es secreto, va en el repo). Sin Analytics. | Dueño (con guía) | S |
| 2 | Margen al bajar en el lector (`margen_bajada_m`) y tests. | Desarrollo | S |
| 3 | **Prueba de entrega en el Redmi:** app con `firebase_messaging`, suscrita a un tema de prueba; envío manual desde la consola de Firebase con la app cerrada; medir cuánto tarda y si llega con la batería en modo normal y en ahorro. Decide la fila "Riesgo a probar". | Desarrollo + dueño | M |
| 4 | App: suscribir y desuscribir el tema al prender o apagar los avisos; manejador en segundo plano que baja `actual.json` y llama a `revisarNivel`; marca compartida con el respaldo; pantalla corta con los ajustes de Xiaomi u otros fabricantes si los avisos no llegan. Tests. | Desarrollo | M |
| 5 | Mover los datos a la rama `datos` y GitHub Pages a esa rama, sin cortar el servicio (copiar, cambiar Pages, verificar las URLs, recién entonces apuntar el lector). | Desarrollo, con OK del dueño | M |
| 6 | Identidad federada: pool y proveedor de GitHub en Google Cloud, condición `repository == MatiCascoV/rio-paysandu`, `ref == refs/heads/main` y el archivo `avisos.yml`; cuenta de servicio con el rol de envío de FCM y nada más. | Dueño (con guía; necesita permisos de su cuenta) | M |
| 7 | `lector/avisos.py` (decide si hay que avisar, comparando con la publicación anterior) y `avisos.yml` (lo corre y envía por la API HTTP v1 de FCM). Acciones fijadas por SHA, permisos mínimos, entrada `prueba` que envía solo al tema de prueba. Tests con fixtures. | Desarrollo | M |
| 8 | Prueba completa: forzar un cambio de nivel con datos de prueba en el tema de prueba, con la app cerrada en el Redmi. Después, una semana en el tema real con el teléfono del dueño. | Desarrollo + dueño | S |
| 9 | Documentar en el README cómo ver los envíos, cómo cortarlos y qué hacer si fallan; agregar Firebase a la futura política de privacidad (Fase 5). | Desarrollo | S |

Orden: 1 → 2 → 3 (si la prueba falla, se revisa el diseño antes de seguir) → 4 → 5 → 6 → 7 → 8 → 9.

## Lo que no entra en esta fase

- Varias ciudades (Fase 4.b): los temas por ciudad ya quedan preparados.
- Avisos por pronóstico de Google Flood Hub: no se usan para avisar (sus términos lo excluyen; ver
  `docs/proxima-etapa-ciudades.md`).
- iPhone.

## Riesgos que quedan

- FCM y Google Play Services son de Google: sin ellos (algunos teléfonos sin servicios de Google) solo queda
  el respaldo local.
- El aviso nunca es más rápido que el dato: CARU publica con cerca de una hora de atraso respecto de la
  medición, más hasta 20 minutos del lector y GitHub Pages.
- Si GitHub Actions deja de correr, no hay datos ni avisos: es el mismo punto único de falla de hoy.
