# 04 — Licencias, atribuciones, deslindes y privacidad para la pestaña "Mapa"

> **Esto no es asesoramiento legal formal.** Es una revisión de fuentes públicas hecha el 19/10/2026 para orientar decisiones de un proyecto comunitario y gratuito. Antes de publicar, si hay dudas, conviene consultar a un abogado o directamente a los organismos (Dinagua, IDE, URCDP).
>
> Convención: **[CONFIRMADO]** = leído en la fuente citada. **[NO CONFIRMADO]** = inferencia o dato que no pude verificar; hay que chequearlo.

---

## Resumen ejecutivo

| Fuente | ¿Se puede copiar, transformar y alojar en GitHub Pages? | Condición principal | Estado |
|---|---|---|---|
| MDT nacional IDE (vuelo 2017-2018) | Sí, incluso uso comercial | "Nota de origen": proveedor + "Licencia de Datos Abiertos – Uruguay" + conjunto + aviso de modificaciones | [CONFIRMADO] en catalogodatos.gub.uy |
| Capas WFS Dinagua `curvas_cri` / `curvas_tr` | Probablemente sí, pero **no están catalogadas** con licencia explícita | Usar la misma nota de origen por analogía y **pedir confirmación a Dinagua** | [NO CONFIRMADO] |
| Mapa base OSM desde `tile.openstreetmap.org` | Técnicamente sí, pero **no recomendado** para una app | Política de uso estricta: sin offline, sin precarga, User-Agent propio, puede bloquearse sin aviso | [CONFIRMADO] |
| Mapa base OSM empaquetado (extracto PMTiles de Protomaps alojado en GitHub Pages) | Sí | Atribución "© OpenStreetMap" visible; es "Produced Work" ODbL | [CONFIRMADO] (licencia) |
| Ubicación del usuario calculada solo en el teléfono | Sí | Google Play no la cuenta como "recolección" si no sale del dispositivo; igual hace falta política de privacidad y aviso claro | [CONFIRMADO] Play / [NO CONFIRMADO] interpretación Ley 18.331 |

---

## 1. Datos de Dinagua / Ministerio de Ambiente e IDE Uruguay

### 1.1 Marco general

- **Ley 18.381 (acceso a la información pública), art. 2:** "Se considera información pública toda la que emane o esté en posesión de cualquier organismo público, sea o no estatal, salvo las excepciones o secretos establecidos por ley." [CONFIRMADO]
  Fuentes: https://impo.com.uy/bases/leyes-originales/18381-2008 · https://www.bps.gub.uy/bps/file/10816/25/ley-18.381---acceso-a-la-informacion-publica.pdf
  Ojo: la ley **no regula expresamente la reutilización**; que la información sea "pública" no equivale automáticamente a una licencia de reuso. Hay discusión doctrinaria al respecto (ver análisis de FING: https://eva.fing.edu.uy/mod/resource/view.php?id=53536). [CONFIRMADO que existe la discusión]
- **Decreto 54/2017** (reglamenta el art. 82 de la Ley 19.355, "Directrices técnicas para la publicación de datos abiertos") aprueba como anexo la **Licencia de Datos Abiertos – Uruguay**, y según los resúmenes consultados establece que la licencia debe identificarse en sitios/aplicaciones que usen datos abiertos. [CONFIRMADO parcialmente: leí resúmenes, no el anexo completo dentro del decreto]
  Fuente: https://impo.com.uy/bases/decretos/54-2017
- **Términos del Catálogo Nacional de Datos Abiertos (AGESIC)**, punto 3 y 7: si un organismo público cataloga un conjunto sin indicar licencia, rige la Licencia de Datos Abiertos de Uruguay; quien reutiliza "deberá aplicar la Licencia de Datos Abiertos asociada al conjunto de datos utilizado", y si combina varios conjuntos, aplica la más restrictiva. Punto 8: la veracidad y actualidad de los datos son responsabilidad del organismo que los publica y AGESIC se exonera de responsabilidad. [CONFIRMADO]
  Fuente: https://catalogodatos.gub.uy/terminos-catalogodatos.pdf

### 1.2 Texto de la Licencia de Datos Abiertos – Uruguay (v0.1) [CONFIRMADO]

Fuente: https://www.gub.uy/agencia-gobierno-electronico-sociedad-informacion-conocimiento/sites/agencia-gobierno-electronico-sociedad-informacion-conocimiento/files/documentos/publicaciones/licencia_de_datos_abiertos_0.pdf

- **Autorización:** uso comercial y no comercial; los datos pueden ser "reproducidos, distribuidos, publicados, traducidos, adaptados, transformados [...]", "fusionados con datos propios y de terceros" e "integrados en [...] productos y aplicaciones".
- **Nota de Origen (obligatoria):** "se deberá en todos los casos citar la siguiente información: el nombre del proveedor, la referencia a la 'Licencia de Datos Abiertos – Uruguay', la referencia al conjunto de datos que está siendo utilizado. Los cambios, las ediciones, los nuevos diseños o modificaciones deben ser mencionados en la nota de origen."

Conclusión: copiar, recortar a Paysandú, convertir formato, simplificar geometrías y alojar en GitHub Pages está permitido **siempre que** la app y el repo muestren la nota de origen e indiquen que los datos fueron modificados.

### 1.3 Modelo digital de terreno de IDE (vuelo 2017-2018) [CONFIRMADO]

- Conjunto en el catálogo: **"Ortoimagen y modelo digital del terreno de cobertura nacional"** (`ide-ortoimagen-mdt-de-cobertura-nacional`), organización **IDE**, licencia "Licencia de DAG de Uruguay" (enlaza al PDF de arriba). Descripción: "Imágenes obtenidas a partir del vuelo aerofotogramétrico realizado en el año 2017 y 2018". Última modificación de metadatos: 26/08/2026.
  Fuente: https://catalogodatos.gub.uy/dataset/ide-ortoimagen-mdt-de-cobertura-nacional (verificado vía API: https://catalogodatos.gub.uy/api/3/action/package_show?id=ide-ortoimagen-mdt-de-cobertura-nacional)
- Contexto del proyecto: https://www.gub.uy/infraestructura-datos-espaciales/proyecto-produccion-control-ortoimagenes-modelos-digitales-elevacion-cartografia
- Geoservicios y descargas IDE: https://www.gub.uy/infraestructura-datos-espaciales/geoservicios-ide · https://www.gub.uy/infraestructura-datos-espaciales/tramites-y-servicios/servicios/descargas
- [NO CONFIRMADO] No encontré una página de "términos de uso" propia del visualizador/geoportal IDE distinta del catálogo. Se toma como válida la licencia del catálogo.

### 1.4 Capas WFS de Dinagua (`curvas_cri`, `curvas_tr`) [NO CONFIRMADO]

- Las capas existen en el GetCapabilities de `https://www.ambiente.gub.uy/dinagua-gs/dinagua/wfs` (verificado el 19/10/2026), en EPSG:32721, **sin título descriptivo ni resumen** (Title = nombre técnico, Abstract vacío). [CONFIRMADO]
- El servicio declara `Fees: NONE` y `AccessConstraints: NONE`, pero la ficha del servicio tiene los **valores por defecto de GeoServer** (proveedor "OSGeo", contacto "Claudius Ptolomaeus"), así que **no debe leerse como una licencia** otorgada por el Ministerio. [CONFIRMADO el contenido; la interpretación es mía]
- En catalogodatos.gub.uy, buscando "dinagua", solo aparecen 4 conjuntos (mediciones de nivel 2017-2019 y aprovechamientos de recursos hídricos), todos con la Licencia de Datos Abiertos de Uruguay. **Las curvas de inundación no están catalogadas.** [CONFIRMADO vía API https://catalogodatos.gub.uy/api/3/action/package_search?q=dinagua]
- El Ministerio publica las curvas en su visualizador público (https://www.ambiente.gub.uy/dinagua-obh/planificacion/idu ; página: https://www.gub.uy/ministerio-ambiente/politicas-y-gestion/inundaciones) y en el Atlas Nacional de Inundaciones (https://www.gub.uy/ministerio-ambiente/politicas-y-gestion/atlas-nacional-inundaciones-drenaje-pluvial-urbano-version-diciembre-2025).
- **Recomendación:** tratarlas como información pública (Ley 18.381) y aplicar por analogía la misma nota de origen; **escribir a Dinagua** para confirmar que se pueden redistribuir derivados (ver sección 4). Mientras no haya respuesta, el riesgo práctico es bajo (dato público, uso gratuito, sin fines de lucro, con atribución), pero no es cero: podrían pedir que se retire la copia.
- [NO CONFIRMADO] Significado exacto de los campos (qué TR incluye `curvas_tr`, qué representa `curvas_cri` — presumiblemente "crecida de referencia/cota de riesgo", fecha de relevamiento). Pedirlo a Dinagua en el mismo correo.

### 1.5 Texto de atribución recomendado

**Versión completa (pantalla "Fuentes y licencias" de la app y README / página de GitHub Pages):**

> **Fuentes de datos**
> - Curvas de inundación (capas `curvas_tr` y `curvas_cri`): Ministerio de Ambiente — Dirección Nacional de Aguas (Dinagua), servicio WFS https://www.ambiente.gub.uy/dinagua-gs/dinagua/wfs. Datos públicos (Ley 18.381); se aplica por analogía la Licencia de Datos Abiertos – Uruguay. Modificaciones: recorte al área de Paysandú, reproyección a WGS84, simplificación de geometrías y conversión de formato.
> - Modelo digital del terreno: Infraestructura de Datos Espaciales (IDE Uruguay), conjunto "Ortoimagen y modelo digital del terreno de cobertura nacional" (vuelo 2017-2018), Licencia de Datos Abiertos – Uruguay. Modificaciones: recorte al área de Paysandú, remuestreo y cálculo de áreas por debajo de cada altura del río.
> - Niveles del río: Comisión Administradora del Río Uruguay (CARU).
> - Mapa base: © colaboradores de OpenStreetMap (datos bajo licencia ODbL, https://www.openstreetmap.org/copyright). Teselas generadas con Protomaps.
>
> Los datos fueron modificados por Mi Río UY. Ni el Ministerio de Ambiente, ni la IDE, ni CARU, ni la Fundación OpenStreetMap avalan esta aplicación ni son responsables de su contenido.
> Licencia de Datos Abiertos – Uruguay: https://www.gub.uy/agencia-gobierno-electronico-sociedad-informacion-conocimiento/sites/agencia-gobierno-electronico-sociedad-informacion-conocimiento/files/documentos/publicaciones/licencia_de_datos_abiertos_0.pdf

**Versión corta (pie del mapa, siempre visible o tras un botón "i"):**

> © OpenStreetMap · Dinagua/MA · IDE Uruguay (Lic. Datos Abiertos UY, datos modificados)

Si se usa la fuente "Mi Río UY" en archivos alojados (GeoJSON/PMTiles) en GitHub Pages, conviene incluir también un `LICENSE-DATOS.md` o `README` en esa carpeta con la versión completa.

---

## 2. Mapa base: OpenStreetMap

### 2.1 `tile.openstreetmap.org` — política de uso [CONFIRMADO]

Fuente: https://operations.osmfoundation.org/policies/tiles/

- Atribución visible y clara sobre el mapa.
- **User-Agent propio y estable** que identifique la app; los User-Agent por defecto de librerías "will be blocked".
- Respetar caché (mínimo 7 días si no se leen cabeceras); no enviar `no-cache`.
- **Prohibido** precargar teselas que el usuario no está viendo y **"Offline use is not permitted on tile.openstreetmap.org"**.
- "We may block access, without notice, if your usage degrades the service." No hay SLA; es un servicio donado.
- Recomienda no fijar la URL en el código (poder cambiar de proveedor sin publicar una versión nueva).

**Conclusión:** para una app que puede tener picos de uso justo en una crecida (muchos usuarios a la vez en la misma zona) y donde sería útil verlo sin conexión, **no conviene depender de `tile.openstreetmap.org`**.

### 2.2 Alternativas

| Opción | Costo / condiciones | Apta para la app | Estado |
|---|---|---|---|
| **Extracto PMTiles de Protomaps alojado en GitHub Pages** (recomendado) | Gratis. Licencia: "Open Database License Produced Work (OpenStreetMap attribution required)". Se genera con `pmtiles extract` acotando a Paysandú y `--maxzoom`. Recomiendan copiar el archivo a almacenamiento propio, no enlazar al de ellos. | Sí; funciona offline si se empaqueta en la app; sin dependencia de terceros | [CONFIRMADO] https://docs.protomaps.com/basemaps/downloads |
| **OpenFreeMap** (instancia pública) | Gratis, sin clave ni registro; sin SLA ("At the moment, I don't offer SLA guarantee"); offline permitido hasta 3.000 teselas o 50 MB por descarga, máx. 4 conexiones y User-Agent único; estilos compatibles con MapLibre Native | Sí, como plan B | [CONFIRMADO] https://openfreemap.org · https://openfreemap.org/quick_start/ ; [NO CONFIRMADO] texto exacto de atribución exigido (los ejemplos muestran "OpenFreeMap © OpenMapTiles Data from OpenStreetMap") |
| **OSM US Tileservice** | "Starter": gratis, bajo volumen y **no comercial**, sin clave; "Partner" para más volumen. Atribuir a OpenStreetMap y OpenStreetMap US | Posible (la app es no comercial); no confirmé soporte explícito para apps móviles ni límites numéricos | [CONFIRMADO parcial] https://openstreetmap.us/news/2025/09/tileservice-general-availability/ |
| MapTiler / Stadia / CARTO | Planes gratuitos con clave y límites, en general **solo no comercial** | Posible, pero exigen clave (que quedaría expuesta en una app pública) | [NO CONFIRMADO] no revisé sus términos vigentes |

### 2.3 Licencia ODbL y atribución [CONFIRMADO]

Fuentes: https://osmfoundation.org/wiki/Licence/Attribution_Guidelines · https://osmfoundation.org/wiki/Licence/Community_Guidelines/Produced_Work_-_Guideline · https://www.openstreetmap.org/copyright

- La atribución debe ser a **"OpenStreetMap"** y dejar claro que los datos están bajo ODbL; habitual: "© OpenStreetMap" o "© colaboradores de OpenStreetMap" enlazado a `openstreetmap.org/copyright`.
- En una esquina del mapa. Puede **colapsarse** (tras interactuar o a los 5 segundos) siempre que el usuario pueda encontrar la información de licencia, p. ej. con un botón "(i)" o en "Acerca de".
- Un mapa renderizado (teselas) es un **Produced Work**: se puede distribuir con cualquier licencia, con atribución. Superponer **capas separadas** de otras fuentes (curvas de Dinagua, MDT) está admitido por la guía.
- Si en algún momento se **extraen datos de OSM** (p. ej. calles o edificios para calcular "cuántas casas quedan bajo el agua") y se publica ese conjunto, eso sería una **base de datos derivada** y debería publicarse bajo ODbL. Hoy no está previsto; tenerlo en cuenta.

---

## 3. Responsabilidad y privacidad

### 3.1 Riesgos de mostrar zonas inundables

Riesgos principales (análisis propio, [NO CONFIRMADO] jurídicamente):

1. **Falsa sensación de seguridad:** que alguien no evacúe porque "el mapa no pinta su casa". Es el riesgo más serio.
2. **Errores técnicos:** el MDT 2017-18 no refleja rellenos, obras o terraplenes posteriores; la superficie del agua no es horizontal en una crecida; el cálculo "por debajo de la cota" ignora defensas, desagües y remanso de arroyos (Sacra, San Francisco, etc.); diferencias de referencia altimétrica entre la escala de CARU y el MDT (cero de escala vs. nivel oficial) pueden desplazar todo.
3. **Datos desactualizados o caídos:** si CARU no publica, la app podría mostrar una altura vieja.
4. **Confusión con la información oficial:** que se perciba como mapa "del Cecoed" o "de Dinagua".
5. **Impacto en terceros:** valor de propiedades, estigmatización de barrios.

Medidas recomendadas:

- **Nunca** usar "zona segura", "fuera de peligro", "no se inunda", "a salvo". Usar "según el modelo", "estimación", "aproximado".
- Diferenciar visualmente **curvas oficiales de Dinagua** (relevadas/modeladas por el organismo) de la **estimación propia con el MDT**, y rotularlas distinto.
- Mostrar **fecha y hora de la altura usada** y avisar si tiene más de X horas.
- Botón fijo "Información oficial" con teléfono del **Cecoed Paysandú** y **911**, y enlace a SINAE.
- Aceptación del aviso la **primera vez** que se abre la pestaña (no solo en la política de privacidad).
- No enviar notificaciones del tipo "tu casa se va a inundar" basadas en la ubicación.
- Uruguay: en principio, un servicio gratuito con avisos claros reduce el riesgo, pero la responsabilidad civil extracontractual (Código Civil, arts. 1319 y ss.) no se elimina con un deslinde si hubiera culpa grave. [NO CONFIRMADO; no revisé jurisprudencia]

### 3.2 Textos sugeridos

**Aviso al abrir la pestaña Mapa (con botón "Entendido"):**

> **Este mapa es una estimación aproximada, no un pronóstico oficial.**
> Muestra hasta dónde *podría* llegar el agua según la altura del río, usando curvas de inundación de Dinagua y un modelo del terreno de 2017-2018. Puede haber errores de varios metros o más: no tiene en cuenta obras recientes, desagües, defensas ni el comportamiento real de la crecida.
> Que tu casa no aparezca pintada **no significa que esté a salvo**.
> Ante una crecida, seguí siempre las indicaciones del Cecoed Paysandú y del Sinae. Emergencias: **911**.
> Mi Río UY es una app comunitaria, sin vínculo con CARU, el Ministerio de Ambiente, la IDE ni el Cecoed.

**Pie permanente del mapa:**

> Estimación aproximada · No oficial · Ante emergencias: Cecoed / 911

**Leyenda de capas:**

> - *Curvas de inundación de Dinagua* — información del Ministerio de Ambiente (puede no estar actualizada).
> - *Estimación Mi Río UY* — cálculo propio: terreno más bajo que la altura del río indicada. Es solo orientativo.

**Sección "Limitaciones" (Acerca de / Fuentes):**

> Esta herramienta se ofrece gratis, "tal cual", con fines informativos. No garantizamos que la información sea exacta, completa o esté actualizada, ni que la app funcione sin interrupciones. No la uses como única fuente para decidir si evacuar, mover bienes o circular por una zona. Las decisiones de evacuación corresponden a las autoridades (Cecoed Paysandú / Sinae).

**Palabras a evitar / usar:**

| Evitar | Usar |
|---|---|
| zona segura, a salvo, no se inunda | zona no alcanzada *según el modelo* |
| se va a inundar | podría quedar bajo agua *según esta estimación* |
| mapa oficial | mapa comunitario con datos públicos |
| exacto, preciso | aproximado, orientativo |

### 3.3 Ubicación del usuario: Ley 18.331 y Google Play

**Ley 18.331** (https://www.impo.com.uy/bases/leyes/18331-2008) [CONFIRMADO texto; interpretación NO CONFIRMADA]:

- Art. 4 lit. D: dato personal es "información de cualquier tipo referida a personas físicas o jurídicas determinadas o determinables". La ubicación precisa de un teléfono puede serlo.
- Art. 9: el tratamiento requiere consentimiento "libre, previo, expreso e informado".
- Art. 13: derecho de información previo (finalidad, responsable, destinatarios, etc.).
- Art. 29: toda base de datos pública o privada debe inscribirse en el registro de la URCDP.

Interpretación práctica [NO CONFIRMADO]: si la ubicación **se calcula y usa solo en el teléfono, no se guarda ni se envía a ningún servidor (ni a GitHub Pages, ni analítica, ni logs)**, el responsable de la app no forma una base de datos ni "trata" datos en sentido fuerte, por lo que no habría registro ante la URCDP. Igual conviene cumplir el espíritu de los arts. 9 y 13: explicar antes de pedir el permiso y que sea opcional. Si en el futuro se envía la ubicación (p. ej. avisos por zona), cambia el análisis: consentimiento documentado, política detallada y posible inscripción.

Atención a un detalle técnico: **pedir las teselas del mapa base a un servidor de terceros revela al proveedor la zona que se mira (y la IP)**. Con PMTiles empaquetado o alojado en GitHub Pages, GitHub ve la IP y qué archivo se pide (no la ubicación GPS). Mencionarlo en la política.

**Google Play** [CONFIRMADO]:

- Sección Seguridad de los datos (https://support.google.com/googleplay/android-developer/answer/10787469): "'Collect' means transmitting data from your app off a user's device." Los datos procesados solo en el dispositivo "do not need to be disclosed" como recolectados.
- Aun así: "Even developers with apps that do not collect any user data must complete this form and provide a link to their privacy policy."
- Política de datos de usuario (https://support.google.com/googleplay/android-developer/answer/10144311): la ubicación es dato personal y sensible; si se accede, se requiere divulgación destacada dentro de la app y consentimiento antes del acceso cuando corresponde; en segundo plano, requisitos mucho más estrictos.
- Recomendaciones: pedir solo `ACCESS_COARSE_LOCATION` o `ACCESS_FINE_LOCATION` **en primer plano** y **solo al tocar "Mostrar mi ubicación"**; **no** pedir `ACCESS_BACKGROUND_LOCATION`; pantalla previa explicativa.

**Pantalla previa al permiso (sugerida):**

> **¿Mostrar tu ubicación en el mapa?**
> Si aceptás, la app usa la ubicación de tu teléfono solo para marcar dónde estás en el mapa. Se calcula en tu teléfono y **no se guarda ni se envía a nadie**. Podés usar el mapa sin dar este permiso y retirarlo cuando quieras desde la configuración de Android.
> [Ahora no] [Continuar]

**Párrafo para agregar a la política de privacidad:**

> **Ubicación (opcional).** Si activás "Mostrar mi ubicación" en la pestaña Mapa, la app accede a la ubicación de tu dispositivo únicamente mientras la estás usando, para dibujar tu posición sobre el mapa. Ese cálculo se hace en tu teléfono: Mi Río UY no guarda, no envía a ningún servidor y no comparte tu ubicación con terceros. No se usa en segundo plano. Podés negar o retirar el permiso en cualquier momento desde la configuración de Android y el resto de la app sigue funcionando.
> **Mapa base y capas.** Para mostrar el mapa, la app descarga archivos alojados en GitHub Pages (GitHub, Inc.). Como cualquier sitio web, GitHub recibe tu dirección IP y la información técnica de la solicitud, según su propia política de privacidad (https://docs.github.com/es/site-policy/privacy-policies/github-general-privacy-statement). Mi Río UY no recibe esos datos.
> Responsable: [nombre o alias del desarrollador], contacto: [correo]. Normativa: Ley 18.331 de Protección de Datos Personales (Uruguay).

En la ficha de Play (Seguridad de los datos): "Ubicación — no recolectada" (si efectivamente nunca sale del dispositivo). [CONFIRMADO criterio de Google; verificar en el código antes de declarar]

---

## 4. ¿Avisar a Dinagua y al Cecoed?

**Sí, conviene**, por tres razones: (1) confirmar la licencia de las curvas, que no están catalogadas; (2) entender bien qué representan `curvas_tr` y `curvas_cri` y la referencia altimétrica, que es la mayor fuente de error; (3) que el Cecoed no se entere por los vecinos y, si quiere, sugiera textos o un número de contacto. No es obligatorio para usar datos abiertos.

Contactos [parcialmente CONFIRMADOS]:

- **Ministerio de Ambiente / Dinagua:** formulario https://www.gub.uy/ministerio-ambiente/institucional/contacto · tel. 2917 3380 · Juncal 1385 (Montevideo), lun-vie 9:15-16:00. [CONFIRMADO en https://www.gub.uy/ministerio-ambiente/politicas-y-gestion/inundaciones]. No encontré un correo específico del área de Inundaciones y Drenaje Urbano. [NO CONFIRMADO]
- **Datos abiertos (AGESIC), si hiciera falta:** datosabiertos@agesic.gub.uy [CONFIRMADO en los términos del catálogo].
- **Cecoed Paysandú:** no encontré correo oficial verificado. Buscar en https://www.paysandu.gub.uy o vía Sinae (https://www.gub.uy/sistema-nacional-emergencias). [NO CONFIRMADO]

### Borrador de correo (Dinagua; adaptar para Cecoed)

> **Asunto:** Uso de curvas de inundación de Dinagua en app comunitaria gratuita (Paysandú)
>
> Estimados/as:
>
> Les escribo para informarles sobre un proyecto comunitario y gratuito, **Mi Río UY**, una app Android sin fines de lucro y sin vínculo oficial que muestra la altura del río Uruguay en Paysandú con los datos públicos de CARU (código abierto: https://github.com/MatiCascoV/rio-paysandu).
>
> Estamos preparando una pestaña de mapa que mostraría, de forma orientativa, hasta dónde podría llegar el agua según la altura del río. Para eso usaríamos las capas `curvas_tr` y `curvas_cri` del servicio WFS de Dinagua (https://www.ambiente.gub.uy/dinagua-gs/dinagua/wfs) y el modelo digital del terreno de la IDE (vuelo 2017-2018). Copiaríamos un recorte de Paysandú a nuestro sitio en GitHub Pages, citando a Dinagua / Ministerio de Ambiente como fuente, indicando que los datos fueron modificados y aclarando que no se trata de información oficial ni sustituye las indicaciones del Cecoed y el Sinae.
>
> Quisiéramos consultarles:
> 1. Si hay algún inconveniente en redistribuir ese recorte bajo la Licencia de Datos Abiertos – Uruguay, o si prefieren otra forma de cita.
> 2. Qué representan exactamente los atributos de esas capas (períodos de retorno, cota de referencia, fecha) y a qué referencia altimétrica corresponden, para poder vincularlas correctamente con la escala de CARU en Paysandú.
> 3. Si tienen alguna recomendación o texto de advertencia que les gustaría que incluyamos.
>
> Con gusto les mostramos una versión de prueba antes de publicarla y corregimos lo que nos señalen.
>
> Muchas gracias por su tiempo y por el trabajo que hacen.
>
> Saludos cordiales,
> [Nombre]
> [Correo] · Paysandú

**Variante para el Cecoed Paysandú** (reemplazar el segundo y tercer párrafo):

> Estamos preparando una pestaña de mapa orientativa basada en datos públicos de Dinagua y la IDE. La app aclara que no es información oficial, nunca indica "zonas seguras" e incluye un botón con el contacto del Cecoed y el 911. Queríamos que lo supieran antes de publicarla, y consultarles si hay un teléfono o enlace oficial que prefieran que mostremos, y si tienen sugerencias sobre los textos de advertencia.

---

## 5. Pendientes antes de publicar

- [ ] Enviar los correos a Dinagua y Cecoed; guardar las respuestas en `docs/mapa/`.
- [ ] Confirmar atributos y referencia altimétrica de `curvas_tr` / `curvas_cri`.
- [ ] Elegir mapa base (recomendado: extracto PMTiles propio) y verificar atribución en pantalla.
- [ ] Agregar pantalla "Fuentes y licencias" con la atribución completa.
- [ ] Actualizar la política de privacidad y el formulario de Seguridad de los datos en Play.
- [ ] Revisar que el código no registre ni envíe la ubicación (logs, analítica, crash reports).
- [ ] [Opcional] Consulta breve a un abogado sobre el deslinde de responsabilidad.

## Fuentes consultadas

- Licencia de Datos Abiertos – Uruguay v0.1: https://www.gub.uy/agencia-gobierno-electronico-sociedad-informacion-conocimiento/sites/agencia-gobierno-electronico-sociedad-informacion-conocimiento/files/documentos/publicaciones/licencia_de_datos_abiertos_0.pdf
- Términos del Catálogo Nacional de Datos Abiertos: https://catalogodatos.gub.uy/terminos-catalogodatos.pdf
- Conjunto IDE MDT: https://catalogodatos.gub.uy/dataset/ide-ortoimagen-mdt-de-cobertura-nacional
- Decreto 54/2017: https://impo.com.uy/bases/decretos/54-2017
- Ley 18.381: https://impo.com.uy/bases/leyes-originales/18381-2008
- Ley 18.331: https://www.impo.com.uy/bases/leyes/18331-2008
- Análisis jurídico de datos abiertos (FING): https://eva.fing.edu.uy/mod/resource/view.php?id=53536
- WFS Dinagua (GetCapabilities): https://www.ambiente.gub.uy/dinagua-gs/dinagua/wfs?service=WFS&request=GetCapabilities&version=2.0.0
- Inundaciones, Ministerio de Ambiente: https://www.gub.uy/ministerio-ambiente/politicas-y-gestion/inundaciones
- IDE geoservicios: https://www.gub.uy/infraestructura-datos-espaciales/geoservicios-ide
- OSMF Tile Usage Policy: https://operations.osmfoundation.org/policies/tiles/
- OSMF Attribution Guidelines: https://osmfoundation.org/wiki/Licence/Attribution_Guidelines
- OSMF Produced Work Guideline: https://osmfoundation.org/wiki/Licence/Community_Guidelines/Produced_Work_-_Guideline
- Protomaps downloads: https://docs.protomaps.com/basemaps/downloads
- OpenFreeMap: https://openfreemap.org · https://openfreemap.org/quick_start/
- OSM US Tileservice: https://openstreetmap.us/news/2025/09/tileservice-general-availability/
- Google Play, Seguridad de los datos: https://support.google.com/googleplay/android-developer/answer/10787469
- Google Play, Política de datos del usuario: https://support.google.com/googleplay/android-developer/answer/10144311
