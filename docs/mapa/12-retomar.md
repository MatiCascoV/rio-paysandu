# Retomar el mapa (traspaso del 21/10/2026)

Rama `mapa-inundacion`, sin merge a `main`. Lo último es un commit **WIP** con la tanda v1.1 a medias: los tres agentes se cortaron por el límite de uso.

## Hecho (commits anteriores al WIP)

- **Propuesta y contrato:** `00`–`05`; v1.1 al final de `05-contrato.md`.
- **Pipeline real:** `lector/mapa/` y el informe `06`. δ = 0,66 m. Cubre del 96,7 al 99,8 % de cada crecida real.
- **App:** informe `07`, cartografía `08`, pantalla `09` (decisiones del usuario al final) y accesibilidad `10`. Último estado verde: 227 tests OK y APK release de 52,2 MB.
- **Datos reales en `app/assets/mapa/`:** 66 capas de 4,00 a 10,50 m y 5 crecidas, con `validado: false`.
- **Control de calidad independiente:** `11-control-calidad.md`. Veredicto: publicar con `validado: false` y el sello "Mapa en prueba", con condiciones.

## A medias (commit WIP): tanda v1.1 (contrato 05, "Agregados v1.1")

| Parte | Archivos | Estado al cortarse |
|---|---|---|
| Pipeline | `lector/mapa/zonas.py` (nuevo), `pipeline.py`, `validar.py`, `control.py`, `config.json`, `lector/tests/test_mapa_v11.py` | Buffer de 5 m, `sin_validar.json` y `aisladas`. Estaba por correr sus tests nuevos. **No se corrió la salida v1.1.** |
| Cartografía | `app/lib/mapa/estilo_mapa.dart`, la lista de capas de `mapa.dart` | Zona baja, zona sin validar, lomas aisladas y línea de hoy. Estaba arreglando un choque de nombres `Path` (usar `ui.Path`). Le falta el §7 del 08 y las capturas. |
| App | `modelos_mapa.dart`, `repositorio_mapa.dart`, `logica_mapa.dart`, `mapa_partes.dart`, tests (`mapa_v11_test.dart` nuevo) | Modelo y repositorio v1.1, textos de la zona baja, margen siempre visible y avisos. Estaba corriendo los tests. Le falta la sección v1.1 del 07. |

**Puede que no compile o que fallen tests.** Lo primero es `flutter analyze` y `flutter test` en `app/`, y `pytest tests/test_mapa_*.py` en `lector/`. El pipeline usa sus propias dependencias: `lector/mapa/requirements.txt`, en un venv aparte del lector.

## Qué falta, en orden

1. **Terminar v1.1:** que compile y que pasen todos los tests. La condición bloqueante es un test que fije que el margen se dibuja siempre: a 3,50, 4,00, 7,00, 10,50 y 11,20 m.
2. **Correr el pipeline v1.1 y copiar la salida a `app/assets/mapa/`.** Copiar solo `indice.json`, `base.json`, `agua/`, `curvas/` y `sin_validar.json`, nunca `calibracion.json`, PNG ni log. Ver el 07 §5.
   - La descarga del MDT de IDE es de unos 500 MB.
   - Si en la nube no se puede descargar o tarda demasiado, NO inventar datos: dejar los assets actuales, que sin los campos nuevos siguen funcionando, y anotarlo.
3. **Legal Compliance Checker:** créditos y licencias (OSM ODbL, IDE Uruguay y Dinagua, cuya licencia está sin confirmar) y los textos del 04. Entrega en `13-legal.md`.
4. **Code Reviewer:** revisar todo el diff de la rama contra `main`. Arreglar lo bloqueante y lo importante. Entrega en `14-revision-codigo.md`.
5. **Solo local, con el dueño:** Reality Checker en el Redmi (checklist del 10), confirmar el cero de CARU contra Dinagua y el correo a Dinagua. Después, el PR con OK del dueño.

## Reglas

- Mapa de seguridad de vida: nunca esconder agua ni decir "estás a salvo". El pie siempre dice "No reemplaza la alerta oficial".
- No hacer merge a `main` ni abrir el PR sin el OK del dueño. No tocar `data/` ni `.github/workflows/lector.yml`.
- Los datos de `app/assets/mapa/` se controlan por sha256: no reformatearlos (`.gitattributes` ya los marca `-text`).
- Escribir en español rioplatense.
