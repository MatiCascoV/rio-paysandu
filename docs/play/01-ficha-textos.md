# Ficha de Google Play: textos

App: **Mi Río UY** (id `uy.miriouy.app`). Idioma de la ficha: español (Uruguay), `es-UY`.
Borrador del 27/10/2026 para pegar en Play Console (Presencia en la tienda > Ficha de la tienda principal).

> Los textos para pegar están dentro de los bloques de código, sin formato extra. El conteo de caracteres
> está en "Verificación de límites", al final.

## Reglas que se respetaron

- Queda dicho en la descripción breve, al principio de la descripción completa y en las notas de la versión
  que **no es una app oficial** y que no reemplaza la alerta de las autoridades (Cecoed / Sinae).
- No promete exactitud ni tiempo real: CARU publica con demora y la app muestra fecha y hora del dato.
- La fuente se nombra: CARU.
- Solo describe funciones que están en `main` (pestañas Inicio, Gráfico, Qué hacer y Avisos; el pronóstico
  de CARU aparece cuando CARU publica un informe de crecida).
- No usa "emergencia", "gobierno", "garantizado" ni promete proteger vidas. La palabra "oficial" aparece
  solo para negarla ("no es oficial"); no se usa como adjetivo de la app, del dato ni del aviso.
- Sin cifras inventadas (no hay cantidad de descargas ni precisión prometida).
- No usa logos ni nombres de organismos como si fueran propios.

## 1. Nombre de la app (máx. 30)

```
Mi Río UY - Nivel del río
```

Alternativa más sobria, por si Play objeta el guion o "nivel": `Mi Río UY`.

## 2. Descripción breve (máx. 80)

```
Nivel del río Uruguay en Paysandú según CARU. App comunitaria, no oficial.
```

## 3. Descripción completa (máx. 4000)

```
Mi Río UY muestra el nivel del río Uruguay en Paysandú de forma simple y con letra grande, y te avisa con una notificación cuando el río sube a un nivel de alerta o de evacuación.

IMPORTANTE: esta NO es una app oficial. Es una ayuda comunitaria, sin vínculo con ningún organismo público, y no reemplaza la alerta de las autoridades. Ante cualquier duda, seguí las indicaciones del Cecoed Paysandú y del Sinae.

DE DÓNDE SALEN LOS DATOS
Las alturas y los informes de crecida son de CARU, la Comisión Administradora del Río Uruguay. La app no inventa ni estima alturas: las lee, las revisa y las muestra con la fecha y la hora de la medición y un enlace a la página de CARU. CARU publica con demora (la estación automática suele publicar cerca de una hora después de medir y a veces en tandas), así que lo que ves puede no ser lo que marca el río en este momento. No es una herramienta de tiempo real ni garantiza que el dato sea exacto.

QUÉ PODÉS HACER
- Inicio: la altura del río en Paysandú, el nivel (Normal, Atención, Alerta, Evacuación o Sin dato), si crece, baja o está estable, y la fecha y la hora del dato. El nivel se dice con ícono y con palabra, no solo con color.
- Gráfico: cómo vino cambiando la altura en los últimos 7, 30 o 90 días, con las líneas de los niveles.
- Pronóstico de CARU: cuando CARU publica un informe de crecida, la app muestra la altura máxima que CARU espera y la fecha del informe.
- Qué hacer: teléfonos útiles para llamar con un toque y recomendaciones generales para antes, durante y después de una crecida.
- Avisos: elegís si querés recibir un aviso urgente (desde alerta, o solo desde evacuación) y un resumen del día.

LOS AVISOS
- Aviso urgente: llega cuando el nivel sube a alerta o a evacuación. No avisa cuando el río baja.
- Resumen del día: una notificación por día, a la mañana, con la altura y cuánto subió o bajó. Solo sale si el río está en atención o más; con el río normal no llega nada.
- Los avisos dependen de que CARU publique el dato, de la conexión del teléfono y del ahorro de batería. En algunos teléfonos (por ejemplo Xiaomi, Redmi o POCO) hay que permitir la app en segundo plano. Pueden llegar con demora o no llegar. No uses esta app como única fuente de información.

PRIVACIDAD
No pide registro, no tiene publicidad y no recolecta datos personales. Los avisos usan Firebase Cloud Messaging, el servicio de Google para notificaciones.

NIVELES DE REFERENCIA
Los niveles de atención, alerta y evacuación son de referencia y todavía se están revisando con las autoridades locales. Pueden cambiar.

PARA QUIÉN ES
Para vecinas y vecinos de Paysandú, sobre todo de las zonas cercanas al río, que quieren mirar rápido cómo viene el nivel y recibir un recordatorio. Pensada para leerse fácil, con modo claro y oscuro.

Mi Río UY es un proyecto comunitario y gratuito. No pertenece ni representa a CARU, al Cecoed, al Sinae ni a ninguna otra institución. Para información y alertas, comunicate con los canales de las autoridades.
```

## 4. Notas de la versión (máx. 500)

Versión inicial. Pegar solo el texto (en Play Console van por idioma, sin etiquetas):

```
Primera versión de Mi Río UY, una app comunitaria y no oficial.
- Nivel del río Uruguay en Paysandú con datos de CARU (publicados con demora)
- Gráfico de 7, 30 y 90 días
- Teléfonos y recomendaciones para antes, durante y después de una crecida
- Avisos opcionales: urgente al subir a alerta o evacuación, y resumen del día
No reemplaza la alerta de las autoridades (Cecoed, Sinae).
```

## 5. Categoría y etiquetas

- **Tipo:** Aplicación (no juego).
- **Categoría sugerida:** **Herramientas** (alternativa: **Clima**). Se evita "Noticias y revistas" y
  cualquier categoría que sugiera una app de un organismo. PENDIENTE para el dueño: decidir entre
  Herramientas y Clima.
- **Etiquetas:** Play deja elegir unas pocas de una lista cerrada que cambia según la categoría.
  Candidatas: Clima y tiempo, Herramientas, Información local. PENDIENTE: elegir las que ofrezca la consola.
- **Datos de contacto (obligatorios):** correo; sitio web y teléfono son opcionales. PENDIENTE para el
  dueño: correo público de contacto.
- **URL de la política de privacidad (obligatoria):** todavía no existe en el repo (es Fase 5 del
  `PROMPT_MAESTRO.md`). PENDIENTE.

## 6. Palabras clave naturales

Play no tiene campo de palabras clave: indexa el texto de la ficha. Estas expresiones ya están en los
textos de forma natural; no agregar listas sueltas de palabras (Play lo penaliza):

- río Uruguay, nivel del río, altura del río, Paysandú, crecida, CARU, aviso por crecida, alerta y
  evacuación, Cecoed, Sinae.
- Variantes de búsqueda que conviene cubrir si entran en una frase real: "río Uruguay hoy", "altura del
  río Uruguay Paysandú", "creciente del río Uruguay".
- No forzar términos que la app no cumple: "mapa de inundación", "pronóstico del tiempo", "emergencias",
  "tiempo real".

## 7. Declaraciones del formulario de Play (a revisar por el dueño)

Todo esto es PENDIENTE: no pude verificar el texto vigente de las políticas de Play.

- **Aplicaciones gubernamentales:** declarar que la app **no** es gubernamental ni representa a un gobierno.
- **Información sobre desastres o crisis:** si la consola pide una declaración, responder con honestidad:
  toma datos de CARU, no emite alertas propias y lo dice. Leer antes la política vigente de Play sobre
  situaciones de crisis.
- **Seguridad de los datos:** la app no pide datos personales ni tiene publicidad; usa Firebase Cloud
  Messaging (identificador de instalación para notificaciones). Contrastar con el Data Privacy Officer cómo
  se declara.
- **Clasificación de contenido (IARC):** cuestionario sin violencia ni contenido sensible.
- **Público objetivo:** adultos / público general, no dirigida a niños.
- **Suplantación:** revisar que ni el nombre ni el ícono se parezcan a los de CARU, Cecoed, Sinae o la
  Intendencia.

## 8. Si la pestaña "Crecidas" entra en esta versión (hoy NO está en `main`)

Mientras no esté en `main`, **no mencionarla**. Si entra, agregar, y volver a contar los caracteres:

```
[En QUÉ PODÉS HACER, después de Gráfico:]
- Crecidas: [bordes de crecidas pasadas según Dinagua, como referencia histórica. No muestra qué zonas se van a inundar hoy.]

[En las notas de la versión:]
- [Nueva pestaña Crecidas con bordes de crecidas pasadas (Dinagua)]
```

El mapa de inundación no va en esta versión y no se menciona.

## Verificación de límites

Contado con Python sobre el texto exacto de cada bloque (espacios y saltos de línea incluidos).

| Campo | Caracteres | Límite | Resultado |
|---|---|---|---|
| Nombre | 25 | 30 | Cumple |
| Descripción breve | 74 | 80 | Cumple |
| Descripción completa | 2990 | 4000 | Cumple |
| Notas de la versión | 383 | 500 | Cumple |

Si se agrega la pestaña Crecidas (sección 8), recontar: la descripción completa tiene margen; las notas, unos 115 caracteres.
