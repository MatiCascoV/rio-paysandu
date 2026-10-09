# Prompt maestro — App "Río Paysandú" (alerta de nivel del río Uruguay)

> Guardá este archivo en la raíz del repositorio. Al empezar cada sesión con el asistente de código, pedile:
> "Leé PROMPT_MAESTRO.md y trabajemos en la Fase N". Avanzá **una fase por vez** y no pases a la siguiente
> hasta cumplir sus criterios de aceptación.

---

## 1. Rol y forma de trabajo

Sos un desarrollador senior que me ayuda a construir este proyecto. Yo programo por gusto y quiero entender lo que hacemos:

- Explicá brevemente cada decisión y comentá el código donde aporte, sin sobreingeniería.
- Entorno: **Windows**, **VS Code**, terminal **PowerShell**. Dame comandos para PowerShell y rutas compatibles con Windows.
- Textos de la app y mensajes al usuario en **español rioplatense**, claros y sin tecnicismos.
- Primero la versión mínima que funcione; después mejoras.
- Ejecutá y probá lo que escribas antes de darlo por terminado. Si algo no lo pudiste probar, decilo.
- Nada de claves, tokens ni credenciales escritas en el código: van en variables de entorno o secretos de GitHub.
- Si una decisión cambia la arquitectura, preguntame antes.

## 1.b Equipo de agentes (Agency Agents)

Tenés instalados los agentes especializados de **Agency Agents** (msitarzewski/agency-agents). Vos sos el **orquestador y desarrollador principal**: planificás, delegás tareas acotadas a los especialistas, revisás lo que entregan e integrás. La responsabilidad final del código es tuya.

Antes de empezar:
1. Listá los agentes disponibles en este entorno (por ejemplo `~/.claude/agents/` o `.claude/agents/`) y confirmá los nombres exactos. Si alguno de la tabla no existe, usá el más parecido y avisame.
2. Mostrame qué agentes vas a usar en la fase actual antes de delegar.

Nombres tomados del catálogo de Agency Agents (división entre paréntesis):

| Rol en el proyecto | Agente | Fases |
|---|---|---|
| Plan de tareas a partir de este documento | Senior Project Manager (Project Management) | inicio de cada fase |
| Arquitectura y decisiones técnicas | Software Architect (Engineering) | 0, 1, 2 |
| Lector Python: scraping HTML + PDF, normalización, historial | Data Engineer (Engineering) | 1 |
| Contratos JSON y publicación de datos | Backend Architect (Engineering) | 1, 2 |
| GitHub Actions + GitHub Pages + envío FCM | DevOps Automator (Engineering) | 2, 4 |
| App Flutter | Mobile App Builder (Engineering) | 3, 4 |
| Diseño de pantallas simples y legibles | UI Designer + UX Architect (Design) | 3 |
| Prueba de uso simulando un vecino de barrio costero | Persona Walkthrough Specialist (Design) | 3 |
| Gráfico de alturas con líneas de umbral | Data Visualization Engineer (Engineering) | 3 |
| Accesibilidad (letra grande, contraste, lector de pantalla) | Accessibility Auditor (Testing) | 3, 5 |
| Pruebas del lector y de los JSON | API Tester (Testing) | 1, 2 |
| Revisión de código antes de cerrar cada fase | Code Reviewer (Engineering) | todas |
| Secretos y credenciales (Firebase, GitHub) | Secrets & Credential Hygiene Engineer (Security) | 2, 4 |
| Verificación con evidencia y aprobación de fase | Evidence Collector + Reality Checker (Testing) | todas |
| README y guía de uso | Technical Writer (Engineering) | todas |
| Firma, build de release y publicación en Google Play | Mobile Release Engineer (Engineering) | 5 |
| Política de privacidad y textos legales | Data Privacy Officer + Legal Compliance Checker | 5 |
| Correcciones puntuales posteriores | Minimal Change Engineer (Engineering) | mantenimiento |

No uses **Senior Developer** (está orientado a Laravel/PHP). **Agents Orchestrator** queda como opción si la coordinación se complica, pero por defecto orquestás vos.

Reglas de delegación:
- Cada tarea delegada lleva: objetivo, archivos que puede tocar, criterio de aceptación y la referencia a las secciones de este documento que aplican (sobre todo 4, 5 y 9).
- Los especialistas no cambian la arquitectura (sección 3) ni los contratos de datos (sección 5) sin consultarme.
- No delegues en paralelo tareas que editan los mismos archivos.
- **Cierre de fase:** el Reality Checker revisa contra los criterios de aceptación con evidencia (salida de comandos, tests, capturas). Si no aprueba, se corrige antes de seguir.
- No uses agentes de marketing, ventas u otras áreas que no estén en la tabla salvo que te lo pida.
- Reportame en español: qué hizo cada agente, qué quedó, cómo probarlo y qué decisiones necesito tomar.

## 2. Qué construimos

Una app Android para la población de Paysandú (Uruguay) que muestra el **nivel del río Uruguay en Paysandú**, su **tendencia**, el **pronóstico** cuando CARU lo publica, y avisa con **notificaciones** cuando el río se acerca a los niveles de alerta o evacuación.

Principio central: **los datos salen siempre de la fuente oficial (CARU)**. El sistema no inventa ni estima alturas: las lee, las valida y las muestra con fecha, hora, fuente y enlace al original.

La app es un canal de información de la Intendencia de Paysandú; no reemplaza la alerta oficial del Sinae / Cecoed. Eso debe decirse en la app.

## 3. Arquitectura

```
CARU Registro de alturas (cada 30 min) ─┐
CARU Informes de crecida (PDF diario)   ─┼─> LECTOR (Python, GitHub Actions cada 15–30 min)
                                          │        │
                                          │   data/actual.json, data/historial.json, data/umbrales.json
                                          │        │  (publicados por HTTPS en GitHub Pages)
                                          │        ├──> APP Flutter (lee los JSON)
                                          │        └──> Firebase Cloud Messaging (Fase 4)
```

Por qué así:
- El registro de CARU se sirve por **HTTP sin cifrar en una IP:puerto**; Android bloquea ese tráfico por defecto y la dirección puede cambiar. Lo lee el lector, no el teléfono.
- Si CARU cambia el formato, se corrige en un solo lugar.
- Los celulares no golpean el servidor de CARU; leen un JSON estático por HTTPS.
- Android demora las tareas en segundo plano; las alertas confiables van por push (FCM).

Stack:
- **Lector:** Python 3.11+, `requests`, `beautifulsoup4`, `pdfplumber`, `pytest`.
- **Publicación:** GitHub Actions (cron) + GitHub Pages (carpeta `data/` servida como JSON).
- **App:** Flutter (Dart) desarrollada en VS Code. Paquetes sugeridos: `http`, `fl_chart`, `shared_preferences`, `url_launcher`, `flutter_local_notifications`, `workmanager` (Fase 3), `firebase_messaging` (Fase 4).

## 4. Fuentes de datos (verificadas el 9/10/2026)

### 4.1 Registro de alturas de CARU — fuente principal

URL: `http://190.0.152.194:8080/alturas/web/user/alturas`

Página HTML con dos tablas:

**Tabla "Puertos"** (fuentes: Prefectura Naval Argentina y Prefectura Nacional Naval). Columnas:
`Puerto | Fecha - Hora | Ultimo Registro | Variación | Período | Estado | Registro Anterior | Fecha - Hora Anterior`

Fila de ejemplo:
`Paysandú | 08/10/2026 - 06:00 | 5.6 | 0.30 | 24 hs. | Crece | 5.3 | 07/10/2026 - 06:00`
El nombre del puerto enlaza a `.../alturas/web/user/altura/24` (detalle de Paysandú).

**Tabla "Estaciones Automáticas"** (fuente: CARU y CTM). Columnas:
`Estación | Fecha - Hora | Ultimo Registro | Variación | Período | Estado | Registro Anterior | Fecha - Hora Anterior | Temperatura`

Fila de ejemplo:
`Paysandú | 08/10/2026 - 15:00 | 5.7 | 0.01 | 30 min. | Crece | 5.69 | 08/10/2026 - 14:30 | 20.0`
El nombre enlaza a `.../alturas/web/user/estacion/19/0` (detalle; `/19/1` es temperatura).

Notas importantes:
- Hay un filtro **"Ceros"** con opciones Local, Wharton, Oficial ROU y MOP. Las alturas cambian según el cero elegido. Inspeccioná el formulario para ver cómo se envía el filtro y **fijá siempre el mismo cero** (configurable). Guardá en el JSON qué cero se usó.
- Investigá si las páginas de detalle (`/altura/24`, `/estacion/19/0`) ofrecen historial; si es así, úsalo para el gráfico y para cargar datos históricos.
- Decimales con punto; fechas `dd/mm/aaaa - hh:mm`, hora de Uruguay (UTC-3).
- La estación automática puede quedar desactualizada (otra estación de la tabla tenía su último dato de mayo). Si el dato de la estación tiene más de 3 horas, mostrar como principal el de Prefectura y avisar.

### 4.2 Informes de crecida de CARU — pronóstico

Página índice 2026: `https://caru.org.uy/nuevositio/2026/10/05/informes-crecida-rio-uruguay-2026/`

- Lista enlaces "INFORME dd/mm/aaaa" a PDF, el más reciente arriba. Ejemplo:
  `https://caru.org.uy/nuevositio/wp-content/uploads/2026/10/20261008-Crecida.pdf`
- El nombre del archivo **no es siempre igual** (hay `-Crecida-2.pdf`, `-Crecida.docx-1.pdf`): leé los enlaces de la página, no construyas la URL.
- La página índice cambia cada año o temporada. Buscala desde la portada `https://caru.org.uy/nuevositio/` (sección "novedades", título que contenga "INFORMES CRECIDA"); dejá la URL en configuración.
- CARU solo publica informes durante crecidas. Si el último informe tiene más de 2 días, considerar "sin informe de crecida vigente".
- Dentro del PDF hay una tabla por puerto con: **altura esperada** (o observada), **nivel de alerta** y **nivel de evacuación**. Extraer la fila "Paysandú". El formato varió entre años: el parser debe ser tolerante y probarse con varios PDF reales.
- También informa el caudal evacuado por Salto Grande (m³/s) y las cotas esperadas en Concordia y Salto; extraerlo si es simple.

### 4.3 Complementarias (fases posteriores)
- Dinagua — Informe de situación y pronóstico hidrológico (PDF, diario durante eventos).
- Sinae: teléfono nacional 150 1353. Cecoed Paysandú: completar contacto.

### 4.4 Umbrales
Los umbrales de Paysandú **no están validados todavía** (los informes muestran valores distintos según el año y el cero). Por eso:
- Viven en `data/umbrales.json`, nunca en el código de la app.
- Incluyen `"validado": false` hasta que el Cecoed los confirme; mientras sea `false`, la app lo indica.
- Valores provisorios: atención 5,0 m · alerta 6,0 m (cota de seguridad Dinagua) · evacuación 6,89 m (informe CARU jul-2025). **Reemplazar al validar.**

## 5. Contratos de datos

`data/actual.json`
```json
{
  "generado": "2026-10-08T15:05:00-03:00",
  "cero": "Local",
  "altura_actual": {
    "valor_m": 5.70,
    "fecha": "2026-10-08T15:00:00-03:00",
    "variacion_m": 0.01,
    "periodo": "30 min",
    "estado": "crece",
    "fuente": "CARU – estación automática Paysandú",
    "url": "http://190.0.152.194:8080/alturas/web/user/estacion/19/0"
  },
  "lectura_prefectura": {
    "valor_m": 5.60,
    "fecha": "2026-10-08T06:00:00-03:00",
    "variacion_m": 0.30,
    "periodo": "24 hs",
    "estado": "crece",
    "url": "http://190.0.152.194:8080/alturas/web/user/altura/24"
  },
  "pronostico": {
    "vigente": true,
    "informe_fecha": "2026-10-08",
    "altura_esperada_m": 6.40,
    "texto": "Resumen breve tomado del informe",
    "caudal_salto_grande_m3s": 18000,
    "url_informe": "https://caru.org.uy/nuevositio/wp-content/uploads/2026/10/20261008-Crecida.pdf"
  },
  "nivel": "atencion",
  "avisos": []
}
```
(Los valores del ejemplo son ilustrativos.) `nivel` ∈ `normal | atencion | alerta | evacuacion | sin_dato`. `avisos` lista problemas como `"dato_desactualizado"` o `"dato_a_verificar"`.

`data/historial.json`: lista de `{ "fecha", "valor_m", "fuente" }`, sin duplicados, últimos 365 días.

`data/umbrales.json`:
```json
{ "validado": false, "cero": "Local", "atencion_m": 5.0, "alerta_m": 6.0, "evacuacion_m": 6.89, "actualizado": "2026-10-09" }
```

## 6. Interfaz de la app (simple)

1. **Inicio**
   - Número grande: altura actual en metros.
   - Color e indicador de nivel (verde normal, amarillo atención, naranja alerta, rojo evacuación, gris sin dato). No depender solo del color: texto también.
   - Tendencia con flecha y texto ("Crece 30 cm en 24 h").
   - "Actualizado: hoy 15:00 · Fuente: CARU" + botón "Ver fuente".
   - Tarjeta de pronóstico si hay informe vigente ("CARU estima hasta 6,40 m"), con enlace al PDF.
2. **Gráfico**: 7 / 30 / 90 días, con líneas de umbral.
3. **Qué hacer**: recomendaciones, teléfonos Sinae y Cecoed, aviso de que la alerta oficial es del Sinae/Cecoed.
4. **Ajustes**: activar notificaciones, elegir desde qué nivel avisar.

Requisitos: funciona sin conexión mostrando el último dato guardado con su fecha; letra grande y alto contraste; carga rápida; sin registro de usuario; sin publicidad; sin recolectar datos personales.

## 7. Estructura del repositorio

```
rio-paysandu/
├─ PROMPT_MAESTRO.md
├─ README.md
├─ lector/
│  ├─ lector.py              # punto de entrada
│  ├─ config.json            # URLs, cero, umbrales de antigüedad
│  ├─ fuentes/
│  │  ├─ caru_registro.py    # tabla HTML
│  │  └─ caru_informes.py    # índice + PDF
│  ├─ validar.py
│  ├─ nivel.py               # cálculo de nivel vs umbrales
│  ├─ requirements.txt
│  └─ tests/
│     ├─ fixtures/           # HTML y PDF reales guardados
│     └─ test_*.py
├─ data/                     # generado por el lector (publicado en GitHub Pages)
├─ .github/workflows/lector.yml
└─ app/                      # proyecto Flutter
```

## 8. Fases

### Fase 0 — Entorno
- Instalar: Git, Python 3.11+, Flutter SDK, Android Studio (solo para el SDK de Android y el emulador), extensiones de VS Code: Python, Flutter, Dart.
- `flutter doctor` sin errores para Android.
- Crear repo en GitHub, estructura de carpetas, `.gitignore`.
- **Aceptación:** `python --version` y `flutter doctor` OK; repo creado.

### Fase 1 — Lector de CARU (local)
- Descargar la página del registro y **guardarla como fixture** antes de escribir el parser.
- Extraer filas Paysandú de ambas tablas → normalizar a números, fechas ISO con zona -03:00, estado en minúsculas.
- Leer el índice de informes, detectar el PDF más reciente, descargarlo, extraer la fila Paysandú. Guardar 3–4 PDF reales de distintas fechas como fixtures.
- Validación: rango 0–20 m; salto mayor a 1 m respecto a la lectura anterior en menos de 6 h → `dato_a_verificar`; dato viejo → `dato_desactualizado`.
- Escribir `data/actual.json` y agregar al `historial.json` sin duplicar.
- Reintentos con espera ante errores de red; si una fuente falla, no borrar el último dato válido.
- **Aceptación:** `python lector/lector.py` genera los JSON correctos; `pytest` pasa con los fixtures.

### Fase 2 — Automatización y publicación
- Workflow de GitHub Actions cada 15–30 min que corre el lector y hace commit de `data/` solo si cambió.
- Publicar `data/` con GitHub Pages por HTTPS.
- Verificar que el runner de GitHub puede acceder a `190.0.152.194:8080`.
- **Aceptación:** los JSON se actualizan solos y se pueden abrir desde el navegador del celular.

### Fase 3 — App MVP
- Pantallas de la sección 6 leyendo los JSON publicados (URL base en configuración).
- Caché local del último dato; estados de carga, error y sin conexión.
- Notificación local al abrir o en chequeo periódico (`workmanager`) si cambia el nivel.
- **Aceptación:** APK funcionando en un celular real; probado con un `actual.json` falso para cada nivel.

### Fase 4 — Notificaciones push
- Proyecto Firebase; el workflow envía mensaje FCM al tema `paysandu` solo cuando cambia el nivel (o aparece un pronóstico que supera un umbral). Credenciales en secretos de GitHub.
- **Aceptación:** la notificación llega con la app cerrada.

### Fase 5 — Publicación
- Ícono, nombre, política de privacidad, textos de Google Play, pruebas con usuarios del Cecoed y vecinos.

## 9. Reglas

- No hardcodear umbrales ni URLs en la app.
- No consultar CARU desde el teléfono.
- Toda altura mostrada lleva fecha, hora y fuente.
- Si no hay dato confiable, decirlo; nunca mostrar un valor inventado o interpolado como si fuera oficial.
- Mensajes de error comprensibles para cualquier vecino.
- Al terminar cada fase: resumen corto de qué quedó hecho, cómo probarlo (comandos PowerShell) y qué sigue.
