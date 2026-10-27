# Política de privacidad de Mi Río UY

> **Borrador para publicar en una URL pública** (GitHub Pages u otra). Los textos marcados **PENDIENTE** los
> tiene que confirmar el dueño antes de publicar. Se puede borrar este recuadro al publicar.
> Hechos verificados en el código el 27/10/2026; la evidencia está en `04-formularios-play-console.md`.

**Última actualización:** 27 de octubre de 2026 (**PENDIENTE:** poner la fecha real de publicación)

## Quién la hace

**Mi Río UY** (identificador de la app: `uy.miriouy.app`) es una aplicación comunitaria que muestra el nivel
del río Uruguay en Paysandú. **No es una app oficial**: no tiene vínculo con CARU, el Cecoed, el Sinae ni
ningún organismo del Estado.

Responsable: **PENDIENTE: nombre y apellido del dueño** (persona física, Uruguay).
Contacto de privacidad: **matiascas13@gmail.com** (**PENDIENTE:** el dueño confirma que ese es el correo que
quiere publicar).

## Qué datos usa la app

**No hay cuentas, registro ni inicio de sesión.** La app no te pide nombre, correo, teléfono ni ningún dato
personal, no usa tu ubicación, no tiene publicidad y no usa Google Analytics ni informes de fallos.

Lo único que pasa fuera de tu teléfono es esto:

| Dato | Para qué | Quién lo recibe |
|---|---|---|
| Un **identificador de instalación y un token de notificaciones** que genera Firebase Cloud Messaging (FCM) en tu teléfono | Que Google pueda entregarte los avisos de nivel del río en ese teléfono | Google (Firebase). Yo, como autor de la app, **no recibo ni guardo** ese identificador. |
| Los **temas de avisos** a los que te suscribe la app según lo que elegiste en la pestaña Avisos (por ejemplo, «alerta-paysandu» o «resumen-paysandu») | Mandarte solo los avisos que pediste | Google (Firebase). Son temas generales: no dicen quién sos. |
| Tu **dirección IP** y datos técnicos habituales de cualquier conexión (modelo de navegador/cliente, hora) | Descargar los datos del río, que están publicados en GitHub Pages (`maticascov.github.io`) | GitHub (Microsoft), que aloja los archivos. Yo no veo esos registros como un listado de usuarios. |

Los datos del río (altura, nivel, pronóstico) son de **CARU** (Comisión Administradora del Río Uruguay) y se
publican después de que un programa automático los lee y los valida. No son datos tuyos.

**Qué se guarda en tu teléfono (y no sale de él):** si activaste avisos urgentes o el resumen del día, desde
qué nivel querés el aviso, el modo claro/oscuro, el último nivel y día ya avisados (para no repetir avisos) y
una copia de los últimos datos descargados, para que la app muestre algo sin conexión. Se borra al desinstalar
la app o borrar sus datos.

**Permisos de Android:** `INTERNET` (bajar los datos) y `POST_NOTIFICATIONS` (mostrar los avisos; Android 13 o
superior te lo pregunta). La app no pide ubicación, contactos, cámara, micrófono ni almacenamiento. Para
mantener los avisos al día cuando la app está cerrada, Android puede ejecutar tareas cortas en segundo plano
(revisión cada 30 minutos); no recogen datos tuyos.

Los números de teléfono de emergencias de la app se marcan con tu aplicación de teléfono; la app no hace
llamadas por su cuenta. Los enlaces a CARU se abren en tu navegador, que tiene su propia política.

## Firebase y Google

Los avisos se entregan con **Firebase Cloud Messaging**, un servicio de **Google LLC**. Google actúa como
**encargado del tratamiento** (procesador) de lo necesario para entregar los avisos y puede tratar datos
técnicos del teléfono y de la conexión según sus propias condiciones:
<https://firebase.google.com/support/privacy>. Google puede procesar esos datos en servidores fuera de Uruguay
(por ejemplo, en Estados Unidos). **Google Analytics para Firebase está desactivado** en la app y no se usa el
identificador de publicidad.

Si tu teléfono no tiene servicios de Google, la app funciona igual: no recibe los avisos al instante, pero
revisa el río por su cuenta cada tanto.

## Cuánto tiempo se guardan los datos

- **Datos en tu teléfono:** hasta que desinstales la app o borres sus datos.
- **Identificador y token de FCM, y suscripción a temas:** los administra Google. Dejan de usarse cuando
  desinstalás la app, borrás sus datos o la desuscribís de los avisos (apagando los interruptores en la
  pestaña Avisos); según la documentación de Firebase, Google también descarta los tokens que llevan mucho
  tiempo sin actividad. **PENDIENTE (revisar):** confirmar el plazo vigente en la documentación de FCM antes
  de publicar y, si se quiere, ponerlo acá.
- **Registros de GitHub Pages:** los conserva GitHub según su política:
  <https://docs.github.com/site-policy/privacy-policies/github-general-privacy-statement>.
- **Lo que yo guardo sobre vos:** nada. No tengo una base de datos de usuarios.

## Tus derechos (Ley 18.331 de Uruguay)

La Ley N.º 18.331 de Protección de Datos Personales y su decreto reglamentario (N.º 414/009) te reconocen, sobre
tus datos personales, los derechos de **acceso, rectificación, actualización, inclusión y supresión**, y a
iniciar la acción de *habeas data*. Como la app no me permite saber quién sos (no hay cuentas y no recibo tu
identificador de FCM), en la práctica casi no tengo datos tuyos para entregarte, corregirte o borrarte. Aun así:

- Escribime a **matiascas13@gmail.com** (**PENDIENTE:** confirmar) y te respondo dentro de los plazos legales
  (**PENDIENTE:** el dueño confirma que se compromete a responder en 5 días hábiles, el plazo que fija la ley
  para acceso y rectificación; verificarlo con el texto vigente).
- Para dejar de recibir datos en Google: apagá los interruptores en la pestaña Avisos, o desinstalá la app o
  borrá sus datos.
- Los derechos sobre lo que tengan Google o GitHub los podés ejercer directamente ante ellos.
- Si creés que no se respetaron tus derechos, podés reclamar ante la **Unidad Reguladora y de Control de Datos
  Personales (URCDP)**: <https://www.gub.uy/unidad-reguladora-control-datos-personales>.

## Niños

La app **no está dirigida a menores de edad** (**PENDIENTE:** confirmar el rango de edad elegido en Play
Console, ver `04-formularios-play-console.md`) y no recoge a sabiendas datos de nadie, tampoco de niños. Como no
hay cuentas, no sé la edad de quien la usa.

## Seguridad

Los datos del río y los avisos viajan por conexiones cifradas (HTTPS). Los avisos solo llevan un tipo y un
nivel; el texto lo arma la app con los datos publicados, y el mensaje no contiene datos personales.

## Esta app no reemplaza la alerta oficial

Mi Río UY es una ayuda comunitaria, con datos de CARU. **No reemplaza la alerta oficial**, que la dan el Sinae y
el Cecoed. Ante cualquier duda o peligro, comunicate con los canales oficiales o llamá al 911.

## Cambios en esta política

Si cambia lo que hace la app con los datos, voy a actualizar esta página y la fecha de arriba, y lo voy a
avisar en la ficha de la app. Las versiones anteriores quedan en el historial del repositorio. **PENDIENTE:** URL
final de esta política (la misma que se carga en Play Console).

## Contacto

**matiascas13@gmail.com** (**PENDIENTE:** confirmar) · Paysandú, Uruguay (**PENDIENTE:** dirección postal si el
dueño quiere publicarla; Play Console puede pedir una para la cuenta).
