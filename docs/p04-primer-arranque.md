# P-04 y P-03: pantalla de primer arranque y texto veraz sobre Firebase

Rama `p04-primer-arranque` (base: `main`). Sin push ni PR.

## Qué hace

**Primer arranque (P-04).** En una instalación nueva, antes de pedir ningún permiso o suscribir ningún tema, la app muestra una pantalla única: "¿Querés avisos de crecida?", con dos botones grandes fijos abajo (60 dp de alto, letra del tema, se agrandan con la letra del teléfono) y el texto que se desplaza arriba.

- **Activar avisos**: prende el urgente "desde alerta" y el resumen del día. Recién ahí pide el permiso de notificaciones, programa la revisión de respaldo y suscribe a `alerta-paysandu` y `resumen-paysandu`. La suscripción no traba nada: sin conexión queda pendiente y `Push.iniciar` la reintenta en la próxima apertura (mecanismo que ya existía).
- **Ahora no**: todo apagado, sin pedir permiso y sin llamar a la suscripción de ningún tema.
- Si se niega el permiso, queda todo apagado, se explica en la pantalla cómo activarlo después y un botón "Seguir" entra a la app.
- Enlace "Política de privacidad" en la pantalla.
- Texto sugerido por el informe: "Te avisamos si el río sube a alerta o evacuación, y un resumen cuando el nivel esté alto. App comunitaria, no oficial: la alerta oficial la dan el Sinae y el Cecoed."

**El resumen ya no viene prendido por defecto en instalaciones nuevas.** `prepararPrimerArranque` (en `avisos.dart`, se llama en `main()` antes de `Notificaciones.iniciar`) deja escrito de forma explícita urgente=false, resumen=false hasta que la persona elige. Como no hay nada prendido, `pedirPermisoInicial` tampoco pide el permiso solo.

**Instalaciones existentes** no ven la pantalla ni cambian nada: si ya hay alguna preferencia guardada (avisos, versión de migración, URL de datos, último nivel, permiso pedido, temas al día, modo claro/oscuro, o las claves viejas de la versión sin push), queda marcada `primer_arranque=hecho` y no se toca ninguna preferencia de avisos. El caso fino es el orden: `migrarPreferencias` escribe preferencias en cada arranque, así que la detección corre antes y usa su propia clave (`primer_arranque`: `pendiente` o `hecho`). Si alguien cierra la app sin elegir, la pantalla vuelve en la apertura siguiente.

**Sin conexión**: la pantalla no usa la red. Después de elegir, la app abre como siempre (con la copia guardada o "sin conexión", sin textos raros). En la web no se muestra.

**Texto veraz sobre Firebase (P-03).** Mismo párrafo en la pantalla de primer arranque y al pie de la pestaña Avisos: Firebase asigna un identificador anónimo a la instalación desde que se abre la app, aunque no se active nada; apagar los avisos quita las suscripciones, pero el identificador sigue hasta desinstalar. No cambié cuándo arranca Firebase. Se corrigió además la frase vieja ("Para los avisos, Firebase le asigna..."), que insinuaba que el identificador dependía de los avisos.

## Archivos

- `app/lib/avisos.dart`: `prepararPrimerArranque`, `debeMostrarPrimerArranque`, claves.
- `app/lib/pantallas/primer_arranque.dart` (nuevo): pantalla y su lógica (usa `ControlAvisos`, así se prueba sin teléfono).
- `app/lib/main.dart`: llama la detección, `RioPaysanduApp` recibe `control` (por defecto el del teléfono) y muestra la pantalla hasta que se elige.
- `app/lib/pantallas/ajustes.dart`: texto de Firebase. `app/lib/notificaciones.dart`: solo un comentario.
- `app/test/primer_arranque_test.dart` (nuevo): 13 pruebas (pantalla visible y con todo apagado; Activar; Ahora no; permiso negado; segunda apertura; cierre sin elegir; cinco casos de instalación existente; 200 % de letra a 320 dp; textos nuevos en Avisos).

`flutter analyze`: sin problemas. `flutter test`: 236 pruebas, todas pasan.

## Para reconciliar con `ficha-play-rebase`

En `main` no existían `EnlacePrivacidad` ni `urlPoliticaPrivacidad`. Los copié en `app/lib/pantallas/comunes.dart` idénticos línea por línea a los de esa rama (misma URL, mismo `launchUrl`), así que al mergear ambas ramas el bloque debería coincidir sin conflicto. Lo único que puede dar conflicto textual es `ajustes.dart`: esa rama agrega `const EnlacePrivacidad()` al final de la pestaña Avisos, justo después del párrafo que yo reescribí. Resolución: quedarse con mi párrafo y con su línea del enlace.

## Bugs en `avisos.dart` / `ajustes.dart`

No encontré bugs claros y chicos, así que no hay commits aparte. Un comentario desactualizado ("como el resumen viene prendido...") en `notificaciones.dart` lo ajusté dentro del cambio.

## Pendientes y notas

- **Sin captura ni prueba en teléfono**: no pude verlo en un dispositivo real. Las pruebas de widget cubren la lógica y el desborde a 200 % / 320 dp; falta mirar con TalkBack el orden de lectura (título, texto, enlace, botones) y el diálogo de permiso de Android 13+.
- **Política de privacidad**: debe decir lo mismo que el texto nuevo (identificador desde que se abre la app; apagar quita suscripciones, no el identificador). Esa política vive en `docs/play/03-politica-de-privacidad.md` en la otra rama; no la toqué.
- Quien dice "Ahora no" sigue pasando por `Push.iniciar`, que en cada apertura llama `unsubscribe` de los seis temas (inútil pero inofensivo, ya anotado en P-03 como mejora de bajo costo; no lo cambié).
- Quien activa y después tiene el permiso bloqueado desde los ajustes de Android lo ve en Avisos, como antes.
- La clave `primer_arranque` es nueva; actualizar la política si lista datos locales.
