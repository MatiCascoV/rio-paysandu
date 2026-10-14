"""Lee un informe de crecida (PDF) en un proceso aparte.

El PDF es contenido ajeno: un archivo armado a propósito podría colgar al
parser o comerse la memoria. Por eso se lee en un proceso hijo con tiempo
máximo y, en Linux (GitHub Actions), con tope de memoria. Si algo sale mal,
el lector sigue con el resto y solo se pierde el pronóstico de esta pasada.
"""
import json
import math
import subprocess
import sys
from datetime import date
from pathlib import Path

LIMITE_MEMORIA_BYTES = 1536 * 1024 * 1024  # memoria virtual del proceso hijo (solo Linux)
MAX_SALIDA = 20_000


class PdfIlegible(ValueError):
    """El PDF no se pudo leer (formato, tiempo, memoria o salida inválida)."""


def parsear_aislado(pdf_bytes, puerto, timeout_s=60):
    """Como caru_informes.parsear_informe, pero en un proceso aparte."""
    try:
        r = subprocess.run([sys.executable, "-I", str(Path(__file__).resolve()), puerto],
                           input=pdf_bytes, capture_output=True, timeout=timeout_s)
    except subprocess.TimeoutExpired as e:
        raise PdfIlegible(f"leer el PDF tardó más de {timeout_s} s") from e
    if r.returncode != 0:
        ultima = (r.stderr.decode("utf-8", "replace").strip().splitlines() or ["?"])[-1][:300]
        raise PdfIlegible(f"no se pudo leer el PDF (código {r.returncode}): {ultima}")
    return _validar_salida(r.stdout)


def _validar_salida(salida):
    """El hijo procesó contenido ajeno: su salida se vuelve a controlar acá."""
    if len(salida) > MAX_SALIDA:
        raise PdfIlegible("salida desmedida")
    try:
        d = json.loads(salida)
        fecha = date.fromisoformat(d["informe_fecha"]) if d["informe_fecha"] else None
    except (ValueError, KeyError, TypeError) as e:
        raise PdfIlegible("salida inválida") from e

    def numero(v, maximo):
        ok = type(v) in (int, float) and math.isfinite(v) and 0 <= v <= maximo
        return v if ok else None

    texto = d.get("texto")
    return {
        "informe_fecha": fecha,
        "altura_esperada_m": numero(d.get("altura_esperada_m"), 20),
        "nivel_alerta_m": numero(d.get("nivel_alerta_m"), 20),
        "nivel_evacuacion_m": numero(d.get("nivel_evacuacion_m"), 20),
        "caudal_salto_grande_m3s": numero(d.get("caudal_salto_grande_m3s"), 100_000),
        "texto": texto if isinstance(texto, str) and len(texto) <= 1000 else None,
    }


def _hijo():
    if sys.platform.startswith("linux"):
        import resource
        resource.setrlimit(resource.RLIMIT_AS, (LIMITE_MEMORIA_BYTES, LIMITE_MEMORIA_BYTES))
    # Con -I no se agrega la carpeta del script a sys.path: se agrega solo lector/.
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from fuentes.caru_informes import parsear_informe

    datos = parsear_informe(sys.stdin.buffer.read(), sys.argv[1])
    datos["informe_fecha"] = datos["informe_fecha"].isoformat() if datos["informe_fecha"] else None
    sys.stdout.write(json.dumps(datos, ensure_ascii=True, allow_nan=False))


if __name__ == "__main__":
    _hijo()
