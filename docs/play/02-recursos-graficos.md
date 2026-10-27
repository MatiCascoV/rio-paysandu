# Ficha de Google Play: recursos gráficos

App: **Mi Río UY** (`uy.miriouy.app`). Borrador del 27/10/2026. No se generó ninguna imagen: esto es la lista
de lo que pide Play, lo que ya existe en el repo y lo que falta producir.

> Las medidas salen de lo que Play Console pide al día de hoy según mi conocimiento; **no pude abrir la
> consola**. Antes de producir las piezas, el dueño debe confirmar los números en Play Console (Presencia
> en la tienda > Ficha de la tienda principal), donde figuran al lado de cada campo. PENDIENTE.

## 1. Lo que pide Play

| Recurso | Obligatorio | Formato | Tamaño | Peso máx. |
|---|---|---|---|---|
| Ícono de la app | Sí | PNG de 32 bits (con alfa) | **512 x 512 px** | 1 MB |
| Gráfico de funciones (feature graphic) | Sí | JPEG o PNG de 24 bits (**sin alfa**) | **1024 x 500 px** | 15 MB |
| Capturas de teléfono | Sí: mínimo **2**, máximo **8** | JPEG o PNG de 24 bits (**sin alfa**) | Cada lado entre **320 y 3840 px**; el lado largo no puede superar el doble del corto | 8 MB cada una |
| Capturas de tablet 7" y 10" | No (opcional) | Igual que teléfono | Igual que teléfono | 8 MB cada una |
| Video promocional | No | Enlace de YouTube | Público o no listado, sin publicidad ni restricción de edad | - |

Recomendaciones de Play para que las capturas puedan destacarse (no son obligatorias, pero conviene
cumplirlas): **4 o más capturas** de teléfono, en vertical **9:16** y de al menos **1080 px de lado corto**
(por ejemplo **1080 x 1920**).

Reglas de contenido de los gráficos (aplican a todo):

- Nada de textos que prometan resultados ("la mejor", "#1", "descargas") ni cifras inventadas.
- No poner logos ni escudos de CARU, Cecoed, Sinae, Intendencia ni Dinagua.
- No poner precios, ni llamadas a la acción de tipo "instalá ya".
- Las capturas deben ser de la app real. Si se agrega un marco de teléfono o un título arriba, que la
  pantalla se vea tal cual es.
- El gráfico de funciones no puede decir "oficial".

## 2. Qué hay en el repo y qué hay que generar

| Recurso | Estado | Dónde / comentario |
|---|---|---|
| Ícono 512 x 512 | **Existe** | `app/assets_fuente/icono/play-512.png` (verificado: PNG de 512 x 512, RGBA, 14 KB). Ver observación abajo. |
| Fuentes vectoriales del ícono | Existen | `app/assets_fuente/icono/` (`fg.svg`, `legacy.svg`, `mono.svg`, `notif.svg`, `4A-referencia.svg`) |
| Gráfico de funciones 1024 x 500 | **Falta generar** | No hay nada en el repo |
| Capturas de teléfono (4 a 8) | **Faltan generar** | No hay capturas en el repo |
| Capturas de tablet | No hacen falta | Opcional; omitir en la primera versión |
| Video promocional | No hace falta | Opcional |

**Observación sobre el ícono existente (PENDIENTE de decidir).** `play-512.png` trae las esquinas
redondeadas dibujadas, con transparencia en la esquina (la esquina (0,0) tiene alfa 0). Play aplica
su propia máscara de esquinas y recomienda subir el ícono **cuadrado completo, sin esquinas redondeadas y sin
sombra**. Con esquinas transparentes puede verse un borde raro sobre fondos oscuros. Conviene regenerarlo
desde las fuentes SVG con el fondo claro a sangre (cuadrado lleno) antes de subirlo. El diseño en sí (regla
de nivel con agua azul sobre fondo claro) no menciona ningún organismo y no se parece a un logo oficial.

## 3. Gráfico de funciones (1024 x 500)

Pieza a generar. Propuesta, sin texto de promesas:

- Fondo azul noche (el mismo de la app) con las olas de la pantalla de Inicio.
- A la izquierda, el ícono; a la derecha, el nombre **Mi Río UY** y una sola línea:
  **"El nivel del río Uruguay en Paysandú"**.
- Línea chica abajo: **"Datos de CARU. App comunitaria, no oficial."**
- Dejar los 15 % de los bordes libres de texto (Play puede recortar).
- Sin alfa. Exportar JPEG o PNG de 24 bits.

## 4. Capturas de teléfono

Producir en 1080 x 1920 (9:16), con el teléfono en modo claro salvo que se indique. Pueden ser capturas
puras o con un título corto arriba. **Cada captura debe mostrar la fecha y la hora del dato**, para no dar
la idea de tiempo real. Usar datos reales de CARU o los de ejemplo de la app (`app/lib/ejemplo.dart`) y no
mezclar valores de distintos días.

| # | Pantalla | Título para sobreimprimir (máx. ~40 caracteres) | Qué tiene que verse |
|---|---|---|---|
| 1 | Inicio, nivel Atención o Alerta | **El nivel del río, de un vistazo** | La altura, el nombre del nivel con ícono, la tendencia y la fecha y hora del dato. |
| 2 | Gráfico | **Cómo vino cambiando en 7, 30 o 90 días** | El gráfico con las líneas de nivel y los botones de 7, 30 y 90 días. |
| 3 | Avisos | **Elegí qué avisos querés recibir** | Los interruptores de Aviso urgente (Desde alerta / Solo evacuación) y Resumen del día. |
| 4 | Qué hacer | **Teléfonos y recomendaciones** | La tarjeta de teléfonos con el botón Llamar y el texto "Sobre esta app". |
| 5 | Inicio con pronóstico de CARU (solo si hay informe de crecida vigente al sacar la captura) | **Pronóstico de CARU, cuando lo publica** | La fila del pronóstico con la altura máxima esperada y la fecha del informe. |
| 6 | Inicio en modo oscuro | **También en modo oscuro** | Misma pantalla que la 1, en oscuro. |
| 7 | Notificación de aviso urgente en el teléfono | **Un aviso cuando sube a alerta o evacuación** | La notificación en la pantalla de bloqueo o en la barra, armada con datos de la app. |
| 8 | [Crecidas, solo si la pestaña entra en esta versión] | [**Crecidas pasadas, como referencia**] | [Pantalla con los bordes de crecidas pasadas según Dinagua.] |

Orden recomendado: 1, 2, 3, 4 como mínimo (cumple las 4 que recomienda Play). Las 5 a 8 son opcionales; la 7
es la más persuasiva pero hay que fabricarla con cuidado (ver abajo). La 8 no existe todavía: no generarla
hasta que la pestaña esté en `main`.

Reglas para sacar las capturas:

- Hacerlas en el Redmi o en un emulador de 1080 x 1920 o más, con la barra de estado limpia (sin otras
  notificaciones, batería llena, hora cualquiera).
- Nada de datos personales ni de otras apps visibles.
- La captura 1 muestra un nivel de alerta o atención **real o de ejemplo, pero nunca inventado**: si se usan
  los datos de `ejemplo.dart`, aclararlo en el texto del título o evitar números llamativos. PENDIENTE:
  decidir si se muestran datos reales del día de la captura (más honesto) o los de ejemplo.
- No mostrar un nivel "Evacuación" que pueda leerse como alarma pasada de moda: la captura queda en la ficha
  meses; mejor un nivel de **Atención**, que es también el que dispara el resumen del día.
- La captura 7 debe ser una notificación real recibida en el teléfono (de las pruebas con los temas
  `prueba-`), no un montaje.
- Los títulos no deben decir "en vivo", "al instante", "en tiempo real" ni "te salva".

## 5. Pendientes para el dueño

1. Confirmar en Play Console los tamaños y pesos de la tabla de la sección 1.
2. Decidir si se regenera el ícono con el cuadrado lleno (recomendado) y quién lo hace.
3. Aprobar el texto del gráfico de funciones y de los títulos de capturas.
4. Elegir si las capturas usan datos reales o de ejemplo (ver sección 4).
5. Fijar si la pestaña "Crecidas" entra en esta versión; si no, la captura 8 y su mención se descartan.
