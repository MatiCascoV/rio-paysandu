# Política de seguridad

## Cómo reportar una vulnerabilidad

Usá el **reporte privado de GitHub**: en la pestaña *Security* del repositorio, botón
*Report a vulnerability* (<https://github.com/MatiCascoV/rio-paysandu/security/advisories/new>).
Así el reporte queda visible solo para el mantenedor.

Por favor **no abras un issue público** ni publiques el detalle antes de que esté corregido.
Incluí, si podés: qué encontraste, cómo reproducirlo, qué impacto creés que tiene y la versión o
commit afectado. No incluyas datos personales de terceros.

## Alcance

Dentro del alcance:

- La app Android "Mi Río UY" (`uy.miriouy.app`) y su código en `app/`.
- El lector de datos en `lector/` y los datos que publica (rama `datos`, GitHub Pages).
- Los workflows de `.github/workflows/` y el envío de avisos push (Firebase Cloud Messaging).

Fuera del alcance:

- Vulnerabilidades de las fuentes de datos de terceros (CARU u otros organismos) o de GitHub, Google
  y Firebase: reportalas a sus responsables.
- Ataques de denegación de servicio por volumen, ingeniería social o acceso físico a un dispositivo.
- Las claves de cliente de Firebase que viajan en la app son públicas por diseño; sí interesa si
  permiten un abuso concreto.

## Limitaciones conocidas

- **Datos de CARU sin cifrar.** La estación automática y el registro de alturas de CARU solo se pueden leer
  por HTTP (puerto 8080), así que alguien en la ruta podría falsear una altura. Mitigaciones: un salto de más
  de 1 m se retiene una pasada; la app cruza el nivel con la altura y marca `dato_a_verificar`; y el aviso
  urgente (alerta o evacuación) espera una **segunda lectura** de la estación con otra fecha, con tope de
  60 minutos para no callar nunca (ver `docs/fase-4-avisos-push.md`, "Segunda lectura antes del urgente").
  Esto reduce el riesgo pero no lo elimina: la solución de fondo es que CARU ofrezca HTTPS o un feed firmado.
  El aviso urgente es opt-in (apagado por defecto).

## Qué esperar

Es un proyecto personal y sin fines de lucro, mantenido por una sola persona:

- Acuse de recibo en un plazo de **7 días**.
- Evaluación inicial y respuesta sobre si se confirma en unos **14 días**.
- Corrección lo antes posible según la gravedad, y reconocimiento público en el aviso si lo querés.

No hay programa de recompensas.

## Versiones con soporte

Solo la última versión publicada (rama `main`).
