# Riesgos de rechazo en Google Play y qué hacer

Estado: borrador del 27/10/2026. Las rutas son relativas a `app/`. **PENDIENTE** = decide solo el dueño.
Fuentes consultadas el 27/10/2026 (ayuda oficial de Play Console):
- Impersonation: <https://support.google.com/googleplay/android-developer/answer/9888374>
- Requisitos para apps que comunican información del gobierno (Misleading Claims):
  <https://support.google.com/googleplay/android-developer/answer/9514050>
- Data safety: <https://support.google.com/googleplay/android-developer/answer/10787469>
- Cuentas personales nuevas y pruebas cerradas: <https://support.google.com/googleplay/android-developer/answer/14151465>

No pude abrir el texto completo de la política «Sensitive Events» ni de la política de contenido de emergencias;
lo que digo sobre ellas es de mi conocimiento general y **no está verificado hoy**. Antes de enviar, leer esas
páginas en el Centro de políticas: <https://play.google/developer-content-policy/>.

## 1. Resumen: qué puede hacer que rechacen la app

| # | Riesgo | Probabilidad | Por qué |
|---|---|---|---|
| 1 | **Impersonation / afiliación falsa a una entidad pública** (nombre, icono, ficha) | Media | Muestra niveles de «evacuación» y teléfonos del Cecoed y del Sinae: un revisor puede leerla como app oficial si la ficha no lo aclara |
| 2 | **Misleading Claims**: información de gobierno sin fuentes ni aclaración | Media | Google pide, para apps no afiliadas, fuentes visibles y aclarar que no representan al gobierno |
| 3 | **Política de privacidad** ausente o que contradice la app | Alta si no se corrige | Hay que cargar la URL, y hoy la app dice «no recolecta datos personales» (`lib/pantallas/ajustes.dart:358`) aunque FCM genera un ID de instalación |
| 4 | **Data safety** que no coincide con el SDK de Firebase | Media | Hay que declarar «Device or other IDs»; declararlo «no recoge nada» sería una discrepancia |
| 5 | **Contenido de seguridad no validado** («Qué hacer», niveles) | Baja-media | Los umbrales aún los revisa el Cecoed (`lib/pantallas/inicio.dart:194-195`) y las recomendaciones están marcadas «Pendiente: que el Cecoed las revise» (`lib/pantallas/que_hacer.dart:8`) |
| 6 | **Sensitive Events** (aprovechar o ser insensible ante un desastre) | Baja | No hay monetización ni anuncios; evitar lenguaje alarmista en la ficha |
| 7 | **Permisos/foreground service** declarados por dependencias | Baja | Ver `04`, apartado 8 |
| 8 | **Cuenta personal nueva**: no se puede publicar sin pruebas cerradas | Cierta (si aplica) | Ver apartado 5 |

## 2. Impersonation, Misleading Claims y Sensitive Events

**Qué dice la política (resumen de las páginas de Google):**
- No se puede dar a entender una relación o autorización con otra entidad (nombre del desarrollador, título, icono,
  capturas); el ejemplo explícito incluye usar un emblema nacional para sugerir que la app es del gobierno.
- No se puede afirmar falsamente una afiliación con un gobierno ni ofrecer sus servicios sin autorización.
- Una app **no afiliada** que comunica información del gobierno debe incluir **fuentes fáciles de ver** en la
  descripción y la ficha, y **dejar claro que no representa a una entidad gubernamental o política**.
- Sensitive Events (de memoria, sin verificar hoy): no se admiten apps que se aprovechen de un desastre o que sean
  insensibles hacia él (sin monetización oportunista, sin afirmaciones falsas o engañosas).

**Cómo está la app hoy y qué hay que ajustar:**

| Punto | Estado | Acción |
|---|---|---|
| Nombre «Mi Río UY» | No incluye CARU, Cecoed, Sinae ni «oficial» (`AndroidManifest.xml:7`, `lib/main.dart:102`) | Mantenerlo. No agregar «Oficial», «Alerta» ni siglas de organismos al título |
| Icono y capturas | **PENDIENTE verificar:** que no lleven escudos, logos, colores o tipografías de CARU, Cecoed, Sinae, Intendencia o Gobierno | Revisar el icono (`@mipmap/ic_launcher`) y las capturas antes de subirlas |
| Nombre del desarrollador | **PENDIENTE:** persona física; usar el nombre real, sin «Cecoed», «Sinae» ni «oficial» | |
| Fuentes visibles en la ficha | **Falta** | Agregar en la descripción: «Fuente de los datos: CARU (https://www.caru.org.uy)» |
| Aclaración de que no es una app de gobierno en la ficha | **Falta** (el texto existe en la app, no en la ficha) | Primera línea de la descripción larga (texto sugerido abajo) |
| Aclaración dentro de la app | **Existe** | Ver tabla siguiente |

**Dónde ya está el aviso de «no oficial» dentro de la app (verificado en el código):**

| Lugar | Texto | Evidencia |
|---|---|---|
| Pantalla principal, siempre a la vista | «App comunitaria, sin vínculo oficial. No reemplaza la alerta oficial» | `lib/pantallas/comunes.dart:70`, usado en `lib/pantallas/inicio.dart:661` |
| «Qué hacer», sección «Sobre esta app» | Deslinde completo: sin vínculo con ningún organismo, no reemplaza la alerta oficial, ir al Cecoed o al Sinae | `lib/pantallas/comunes.dart:65-67`, usado en `lib/pantallas/que_hacer.dart:81-85` |
| Pestaña Avisos | «Estos avisos no reemplazan la alerta oficial: la dan el Sinae y el Cecoed.» | `lib/pantallas/ajustes.dart:325-328` |
| En cada notificación | «La alerta oficial la dan el Sinae y el Cecoed.» | `lib/avisos.dart:156`, `:174`, `:185` |
| Fuente de cada dato | «Fuente: CARU…» junto a la altura | `lib/pantallas/inicio.dart:261`, `lib/textos.dart:331-336`, `lib/pantallas/grafico.dart:124-125` |
| Datos de referencia sin validar | «Los niveles son de referencia; el Cecoed todavía los está revisando.» | `lib/pantallas/inicio.dart:194-195` |

**Brechas encontradas (no corregidas acá; esta tarea es solo documentación):**
1. **Sin pantalla de bienvenida** que muestre el aviso la primera vez: el deslinde corto está en la pantalla principal,
   pero no hay un «aceptar y seguir». Sugerencia: no hace falta aceptar, pero el aviso corto ya está a la vista; alcanza.
2. **No hay enlace a la política de privacidad dentro de la app.** Play lo exige «fácil de encontrar en la app y en
   la ficha» (ayuda de Play, apps que comunican información del gobierno). Agregar un enlace en la pestaña Avisos
   o en «Sobre esta app».
3. **`lib/pantallas/ajustes.dart:358`** dice «no recolecta datos personales». FCM genera un ID de instalación en el
   teléfono. Sugerencia de texto: «no pide registro, no tiene publicidad y no guarda datos personales tuyos; Google
   (Firebase) usa un identificador de instalación para entregar los avisos». Cambia código: **PENDIENTE** de que el
   dueño lo autorice.
4. El «Qué hacer» y los umbrales están «Pendiente: que el Cecoed las revise» (`lib/pantallas/que_hacer.dart:8`):
   mantener el aviso de «referencia» y no usar «validado por el Cecoed» en la ficha.
5. Las notificaciones de **evacuación** (`lib/textos.dart:259`, `:316`) ya dicen que la orden la da el Cecoed y que
   se llame al 911 si hay peligro. Bien; no cambiar ese enfoque.

**Texto sugerido para la ficha** (primeras líneas de la descripción larga; **PENDIENTE:** aprobación del dueño):

> Mi Río UY es una app comunitaria e independiente. **No es una aplicación oficial ni está afiliada, autorizada o
> respaldada por CARU, el Cecoed, el Sinae ni ningún organismo del Estado, y no reemplaza la alerta oficial.**
> Muestra el nivel del río Uruguay en Paysandú con datos de CARU (Comisión Administradora del Río Uruguay):
> https://www.caru.org.uy. La alerta o la orden de evacuación oficial las dan el Sinae y el Cecoed. En caso de
> peligro, llamá al 911.
> No tiene publicidad, no pide registro y no usa tu ubicación.

Descripción corta (80 caracteres máx.): «Nivel del río Uruguay en Paysandú. App comunitaria, no oficial.» (66).

Qué **no** poner en la ficha: «oficial», «alerta oficial», «del Cecoed», logos de organismos, «certificada», «garantiza»
o «tiempo real» sin matices (la fuente publica con atraso; ver `docs/fase-4-avisos-push.md`, «Riesgos que quedan»),
ni lenguaje alarmista («¡peligro!», «catástrofe») en el título o las capturas.

## 3. Política de privacidad y Data safety (riesgo de discrepancia)

- Cargar la URL de `03-politica-de-privacidad.md` ya publicada, accesible sin iniciar sesión, en HTTPS y no como PDF.
- La política, la hoja de Data safety (`04`) y el comportamiento real tienen que decir lo mismo: FCM crea un ID de
  instalación, no hay Analytics/Crashlytics, no hay anuncios ni ubicación.
- Cada vez que se agregue un SDK (Crashlytics, Analytics, mapas, anuncios), actualizar política y Data safety **antes**
  de subir esa versión.
- **Registro de bases de datos en la URCDP (Uruguay):** como la app no mantiene ninguna base de datos de usuarios,
  probablemente no corresponda registrar nada, pero **PENDIENTE:** el dueño lo confirma con la URCDP o con un
  abogado (no es asesoramiento legal).

## 4. Qué más puede frenar la revisión

- **Notificaciones**: una notificación de «evacuación» enviada por error sería un incidente serio. Mantener la
  semana de prueba en los temas `prueba-` y la regla de que el texto sale de `actual.json` y no del mensaje
  (`docs/fase-4-avisos-push.md`). La política de Spam/notificaciones de Play pide que no sean engañosas: la app
  muestra solo dos tipos, ambos pedidos por el usuario (el resumen viene prendido por defecto:
  `lib/avisos.dart:67`; el permiso se pide una vez, `lib/notificaciones.dart:145-149`).
- **Resumen prendido por defecto y permiso al abrir**: aceptable, pero si el revisor lo toma como notificación no
  solicitada, la respuesta es que la pestaña Avisos permite apagarlo y que no se vuelve a pedir el permiso solo.
- **Estabilidad**: revisar que la app abra sin servicios de Google (el código lo contempla: `lib/main.dart:35-38`,
  `lib/push.dart:106`) y sin conexión (copia local: `lib/datos.dart:171`).
- **Datos desactualizados**: la app muestra fecha y hora del dato y avisa si es viejo (`lib/pantallas/inicio.dart:49`,
  `:179`); mantenerlo, es una defensa frente a «Misleading claims».
- **Teléfonos de la ficha/app**: el 911, el 150 1353 y los del Cecoed (`assets/config.json:5-11`) deben ser
  correctos; **PENDIENTE:** el dueño o el Cecoed los verifican antes de publicar.

## 5. Pruebas cerradas obligatorias para cuentas personales nuevas

**Confirmado el 27/10/2026** en la ayuda oficial de Play Console (<https://support.google.com/googleplay/android-developer/answer/14151465>):

- Aplica a las **cuentas de desarrollador personales creadas después del 13 de noviembre de 2023**.
- Hay que correr una **prueba cerrada con al menos 12 testers** que se mantengan **inscritos de forma continua
  durante los 14 días** previos a pedir el acceso a producción (si uno sale y vuelve a entrar, los 14 días tienen
  que ser consecutivos). Algunos blogs aún mencionan «20 testers», un requisito anterior; la ayuda oficial dice 12.
- Producción queda **deshabilitada** hasta cumplirlo; antes hay que **terminar la configuración de la app**
  (contenido de la app, ficha, etc.).
- Después se usa **«Solicitar acceso a producción»** en el panel. El formulario pide: detalles de la prueba cerrada
  (cómo se buscaron testers, qué participación y comentarios hubo), de la audiencia y valor de la app, y si está
  lista para producción. Google tarda **alrededor de 7 días**, a veces más; si faltan testers o participación, hay
  que seguir probando.
- Las pruebas **internas** no cuentan; tiene que ser la pista **cerrada**.
- Las cuentas de **organización** (con D-U-N-S) no tienen este requisito, según lo que publican terceros; no lo
  verifiqué en la ayuda oficial.

**PENDIENTE (solo el dueño):**
1. ¿La cuenta es personal y se creó después del 13/11/2023? Si es una cuenta anterior, esto puede no aplicar.
2. Reclutar 12 testers reales (vecinos de Paysandú con Android; sus correos o un grupo de Google) y mantenerlos
   14 días; ir recogiendo comentarios para el formulario de producción.
3. Decidir si se prefiere una cuenta de organización para evitar este paso (requiere D-U-N-S y entidad); no
   recomendado solo por esto.

Plan sugerido: completar contenido de la app (`04`), subir el primer AAB a la pista cerrada, invitar a los testers
con un enlace, contar los 14 días y llevar un registro simple de comentarios (fecha, quién, qué) para el formulario.

## 6. Lista previa a enviar

1. Política publicada en una URL y enlazada en la ficha **y** en la app (brecha 2).
2. Frase de `ajustes.dart:358` corregida o aclarada (brecha 3).
3. Ficha con el texto de la sección 2 y sin logos ni palabras de organismos oficiales.
4. Data safety y demás formularios como en `04`.
5. Manifiesto fusionado del AAB final revisado (permisos y servicio en primer plano).
6. Cuenta, testers y 14 días de prueba cerrada resueltos (sección 5).
7. Correo de contacto, nombre del desarrollador y países confirmados por el dueño.
