# Formularios de Play Console: respuestas sugeridas

Estado: borrador del 27/10/2026, sobre la rama `ficha-play-legal` (base `origin/main` 0ac471d). Las rutas son
relativas a `app/`. **PENDIENTE** = decide o confirma solo el dueño. Las pantallas y textos de Play Console
cambian: usar esto como guía y comparar con lo que muestre la consola el día de cargar.

## Hechos del código que sostienen las respuestas

| Hecho | Evidencia |
|---|---|
| Permisos propios: solo `INTERNET` y `POST_NOTIFICATIONS` | `android/app/src/main/AndroidManifest.xml:3` y `:5` |
| Sin copias de seguridad automáticas | `AndroidManifest.xml:9` (`allowBackup="false"`) |
| Analytics apagado y sin ID de publicidad | `AndroidManifest.xml:39-44` (`firebase_analytics_collection_deactivated=true`, `google_analytics_adid_collection_enabled=false`); en el manifiesto empaquetado de la compilación local `release` no aparece `AD_ID` |
| Sin Crashlytics ni Analytics en el código | `pubspec.yaml:45-46` solo declara `firebase_core` y `firebase_messaging`; `android/app/build.gradle.kts:5` aplica solo `google-services`; ningún `import` de analytics/crashlytics en `lib/` |
| FCM por temas, sin cuentas | `lib/push.dart:1-7`, `:66` (`subscribeToTopic`), `:69` (`unsubscribeFromTopic`); inicializa `Firebase.initializeApp()` siempre al abrir (`lib/main.dart:37`, `lib/push.dart:118`) |
| Los mensajes llevan solo datos, sin texto | `lib/push.dart:1-7`; `docs/fase-4-avisos-push.md` ("Contenido del push") |
| Descarga solo de GitHub Pages por HTTPS | `assets/config.json:2` (`url_base`), `lib/datos.dart:128` (`GET`) |
| Datos locales: preferencias y copia de los JSON | `lib/avisos.dart:28-44` (claves), `lib/datos.dart:171` (`cache_<archivo>`), `lib/main.dart:94` (tema) |
| Sin ubicación, cámara, contactos, anuncios | Ningún permiso ni dependencia de eso en `AndroidManifest.xml` / `pubspec.yaml` |
| Respaldo en segundo plano cada 30 min (WorkManager) | `lib/notificaciones.dart:106`, `:110-115` |
| Teléfonos de emergencia se marcan con el marcador del sistema | `lib/enlaces.dart:56` (`tel:`), `assets/config.json:5-11`; `AndroidManifest.xml:61-64` (`<queries>` DIAL) |
| Enlaces externos solo a orígenes permitidos | `lib/enlaces.dart:13-39`, `assets/config.json:4` |

**Hallazgo importante, manifiesto fusionado.** En el manifiesto empaquetado de la última compilación `release`
local (`app/build/app/intermediates/packaged_manifests/release/processReleaseManifestForPackage/AndroidManifest.xml`
del árbol principal, fechado 21/10/2026, puede estar desactualizado) aparecen permisos que **no** están en el
manifiesto propio y vienen de dependencias (WorkManager, Firebase, Google Play services): `WAKE_LOCK`,
`ACCESS_NETWORK_STATE`, `VIBRATE`, `RECEIVE_BOOT_COMPLETED`, `com.google.android.c2dm.permission.RECEIVE`,
`FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_SHORT_SERVICE` (líneas 46-69), y un servicio
`androidx.work.impl.foreground.SystemForegroundService` con `foregroundServiceType="shortService"` (líneas 187-192).
**Antes de cargar el AAB**, volver a compilar y revisar el manifiesto fusionado del bundle final (Play Console
muestra los permisos detectados).

---

## 1. Seguridad de los datos (Data safety)

Guía de Google (consultada 27/10/2026): hay que declarar también lo que recogen los SDK de terceros como Firebase;
"Device or other IDs" incluye los *Firebase installation IDs*; el tratamiento solo en el dispositivo no se declara.
Verificar el día de cargar contra la guía de Firebase para FCM:
<https://firebase.google.com/docs/android/play-data-disclosure> (**PENDIENTE de verificar** la lista exacta).

| Campo | Respuesta sugerida | Evidencia / razón |
|---|---|---|
| ¿La app recoge o comparte alguno de los tipos de datos requeridos? | **Sí** | FCM genera un ID de instalación y un token: `lib/push.dart:118`, `:66` |
| ¿Todos los datos del usuario se cifran en tránsito? | **Sí** | `assets/config.json:2` (https); FCM usa TLS. Los enlaces `http://` de `config.json:4` solo se abren en el navegador, no son tráfico de la app |
| ¿Ofrecés una forma de pedir que se borren los datos? | **Sí** (sugerido), con la URL de la política, sección «Tus derechos». **PENDIENTE:** decide el dueño; la alternativa es «No», pero la política ofrece un correo y desinstalar borra todo lo local | Política `03` |
| Ubicación (aproximada / precisa) | No recoge | Sin permiso ni plugin de ubicación |
| Información personal (nombre, correo, dirección, teléfono, etc.) | No recoge | Sin cuentas ni formularios |
| Información financiera, salud y estado físico | No recoge | |
| Mensajes, fotos, videos, audio, archivos, calendario, contactos | No recoge | |
| Actividad en la app / historial / búsquedas | No recoge. Las preferencias de avisos viven en el teléfono (`lib/avisos.dart:28-44`); lo único de preferencia que sale son los **temas** FCM (ver notas) | |
| Información y rendimiento de la app (fallos, diagnósticos) | No recoge (sin Crashlytics ni Analytics) | `pubspec.yaml:45-46`, `AndroidManifest.xml:39-41` |
| **Identificadores de dispositivo u otros (Device or other IDs)** | **Sí: se recoge** | ID de instalación de Firebase y token de FCM |
| ¿Se **comparte** con terceros? | **No** (sugerido): Google trata el ID como proveedor de servicios en nombre del desarrollador. **PENDIENTE de verificar** con la guía de Firebase | |
| ¿Es opcional o requerido? | **Requerido** (sugerido): Firebase arranca siempre (`lib/main.dart:37`) y el usuario no puede apagar el ID, solo los temas | |
| ¿Se procesa de forma efímera? | No | |
| Propósito | **Funcionalidad de la app** (entregar los avisos). No Analytics, no publicidad, no personalización | `lib/push.dart:1-7` |

**Notas:**
- Dirección IP: la ven GitHub Pages (descarga de datos) y Google (FCM) como parte de cualquier conexión. El
  formulario no la lista como tipo propio; se cubre en la política `03`. **PENDIENTE:** si el dueño quiere ser más
  conservador, consultar a un abogado.
- Los **temas** (`alerta-paysandu`, etc.) no identifican a nadie, pero quedan asociados al token dentro de Google.
  Por eso la política los menciona.
- Mantener la hoja y la política en sintonía: si algún día se suma Crashlytics o Analytics, actualizar ambas
  **antes** de publicar.

## 2. Clasificación de contenido (cuestionario IARC)

- Correo para el certificado: **PENDIENTE** (puede ser el del dueño).
- Categoría: **«Referencia, noticias o educativa»** si Play Console la ofrece para esta app, o **«Utilidad»**.
  **PENDIENTE:** elige el dueño; no cambia el resultado. (Informa un dato público; no es juego ni red social.)
- Violencia, sangre, contenido sexual, lenguaje soez, sustancias controladas, juegos de azar: **No** a todo.
- Funciones: **sin interacción entre usuarios**, **sin compartir ubicación**, **sin compras**, **sin contenido
  generado por usuarios**, **sin navegador propio** (los enlaces abren el navegador del sistema: `lib/enlaces.dart`).
- Resultado esperable: **apta para todo público (PEGI 3 / ESRB Everyone)**. Si el cuestionario devolviera otra
  cosa, revisar las respuestas antes de aceptar.

## 3. Público objetivo y contenido

- Grupo etario: **18 años o más** (sugerido). Es lo más simple porque evita la política de Familias; el contenido
  es información de crecidas para residentes. **PENDIENTE:** decide el dueño; si incluye menores de 13 se activan
  los requisitos de Familias, que no conviene asumir.
- «¿La app atrae a niños?»: **No** (sin personajes, dibujos animados ni mecánicas infantiles).
- Programa Designed for Families: **no participar**.

## 4. Anuncios

- «¿Tu app contiene anuncios?»: **No**. Evidencia: sin SDK de anuncios en `pubspec.yaml`; `lib/pantallas/ajustes.dart:358`
  («no tiene publicidad»).
- **ID de publicidad (Advertising ID)**: **la app no lo usa**. Evidencia: ausencia de `AD_ID` en el manifiesto
  fusionado y `AndroidManifest.xml:43-44`. Verificar de nuevo en el AAB final.

## 5. Acceso a la app

- «Todas las funciones están disponibles sin acceso restringido»: **Sí, sin inicio de sesión ni cuenta**.
- No hay que dar credenciales de prueba. Evidencia: ningún flujo de login en `lib/`; `lib/push.dart:5-7`.
- Nota para el revisor (campo de instrucciones): «La app no requiere cuenta. Pide el permiso de notificaciones de
  Android 13+ al abrir. Los avisos urgentes solo llegan cuando el nivel del río sube a alerta o evacuación, así
  que el revisor puede no ver ninguno; el resto de las pantallas funciona sin condiciones.»

## 6. Permisos y declaraciones sensibles

| Declaración / permiso | Respuesta | Evidencia |
|---|---|---|
| `INTERNET` | Normal, sin declaración | `AndroidManifest.xml:3` |
| `POST_NOTIFICATIONS` | Normal; se pide en tiempo de ejecución con la app a la vista, una sola vez | `AndroidManifest.xml:5`, `lib/notificaciones.dart:145-149` |
| Ubicación, SMS, registro de llamadas, accesibilidad, todos los archivos, VPN, superposición | **No usa** | Manifiesto |
| Permisos fusionados (`WAKE_LOCK`, `RECEIVE_BOOT_COMPLETED`, etc.) | Los agregan WorkManager y Firebase; no requieren formulario | Manifiesto empaquetado, líneas 46-69 |
| Alarmas exactas, intención de pantalla completa, consulta de paquetes | **No usa** | Manifiesto |
| Política de privacidad (URL) | URL pública de `03-politica-de-privacidad.md`. **PENDIENTE:** publicar y cargar; falta además el enlace dentro de la app (ver `05`) | |
| Países de disponibilidad | **PENDIENTE:** sugerido solo Uruguay (la app trata un solo punto, Paysandú) | `README.md` |
| Tipo de cuenta y datos del desarrollador | **PENDIENTE:** persona física en Uruguay; ver `05` | |

## 7. Declaración de app de noticias / gobierno / emergencias

- **Apps de gobierno (Government apps)**: marcar que **no es una app del gobierno ni la desarrolla o autoriza una
  entidad gubernamental**. Es el punto clave: la app es **comunitaria y no oficial** (`README.md:6-8`,
  `lib/pantallas/comunes.dart:65-70`). Google exige además, para apps no afiliadas que comunican información del
  gobierno, **fuentes visibles en la descripción y dejar claro que no representa a una entidad gubernamental**
  (ayuda de Play, «Requirements for apps that communicate government information», consultada 27/10/2026).
  Ver texto sugerido en `05`.
- **Apps de noticias**: **No es una app de noticias** (no publica artículos de un editor). Sugerido: «No».
  **PENDIENTE:** si la consola lo pregunta distinto, decide el dueño.
- **Respuesta a emergencias / desastres**: no encontré un formulario propio para apps de este tipo (**PENDIENTE de
  verificar** en la consola el día de cargar). Aplican las políticas generales descriptas en `05`.
- **Salud**: **no es una app de salud**: el contenido es el nivel de un río.
- **Funciones financieras**: **no aplica** (sin pagos, préstamos, cripto ni cuentas; sin compras en la app).
- Otras declaraciones (VPN, COVID, seguimiento de contactos): **no aplican**.

## 8. Servicios en primer plano (foreground services)

- Código propio: **no declara ningún servicio en primer plano** (`AndroidManifest.xml` propio, sin `<service>`).
- El manifiesto fusionado trae `SystemForegroundService` con `foregroundServiceType="shortService"` y los permisos
  `FOREGROUND_SERVICE` / `FOREGROUND_SERVICE_SHORT_SERVICE`, aportados por WorkManager (`workmanager`,
  `pubspec.yaml:44`). La app no pide ejecutar en primer plano: la tarea periódica es de WorkManager común
  (`lib/notificaciones.dart:110-115`).
- Si Play Console pregunta por el tipo de servicio en primer plano: **«servicio corto (short service)»**, como lo
  declara la dependencia, con la descripción «Revisión breve del nivel del río para mostrar un aviso cuando el
  teléfono no recibe el push». **PENDIENTE de verificar** en la consola: no confirmé que ese tipo exima de
  declaración. Si la consola exige declarar algo que la app no usa, la alternativa es quitar el permiso con
  `tools:node="remove"` en el manifiesto propio y recompilar (decisión de ingeniería, no de este documento).

## 9. Apps financieras / salud

**No aplican.** No hay pagos, préstamos, inversiones, criptoactivos, historiales médicos, diagnósticos ni
seguimiento de salud. Responder «No» en todas las casillas de «Funciones financieras» y «Funciones de salud».

## 10. Otros campos de la ficha

- Categoría de la app: **Herramientas** o **Clima** (**PENDIENTE:** el dueño; evitar «Noticias y revistas» para
  no activar esa declaración).
- Datos de contacto públicos: correo (**PENDIENTE: confirmar**); sitio web opcional (la política).
- Texto de la ficha y capturas: ver `05`.
