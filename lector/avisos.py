"""Decide si hay que mandar un aviso push comparando dos publicaciones de actual.json.

Lo usa .github/workflows/avisos.yml: el push va sin texto, así que acá solo se
decide *si* avisar y de qué tipo; la app arma el aviso con lo que diga actual.json.

Uso (desde la raíz del repositorio):
    python lector/avisos.py ANTERIOR.json NUEVO.json [--umbrales data/umbrales.json]
    python lector/avisos.py --anterior <commit> [--nuevo <commit>]

Imprime una línea JSON con la decisión. Si existe GITHUB_OUTPUT, agrega
`avisar=true|false` y `tipo=nivel|pronostico|ninguno`. Sale con 0 si pudo
decidir (avise o no) y con 2 si no pudo.

Solo biblioteca estándar: corre en un workflow con credenciales donde no se
instala nada con pip.
"""
import argparse
import json
import math
import os
import re
import subprocess
import sys
from pathlib import Path

from nivel import NIVELES_CON_DATO, umbrales_validos

# Nombres para el motivo. Solo se escriben valores que estén en estas listas:
# el motivo termina en el resumen de GitHub Actions y nada del JSON se copia tal cual.
NOMBRES_NIVEL = {
    "normal": "normal",
    "atencion": "atención",
    "alerta": "alerta",
    "evacuacion": "evacuación",
}
NOMBRES_PRONOSTICO = {1: "alerta", 2: "evacuación"}

RUTA_ACTUAL = "data/actual.json"
RUTA_UMBRALES = "data/umbrales.json"
REVISION_VALIDA = re.compile(r"[0-9A-Za-z_./~^-]+")
MAX_HISTORIA = 200


class ErrorAvisos(Exception):
    """No se pudo decidir: argumentos mal, git falla o falta el actual.json nuevo."""


# ---------- decisión ----------

def _nivel(publicacion):
    """Nivel con dato o None (sin_dato, ausente, desconocido o mal formado)."""
    if not isinstance(publicacion, dict):
        return None
    nivel = publicacion.get("nivel")
    if isinstance(nivel, str) and nivel in NIVELES_CON_DATO:
        return nivel
    return None


def _altura_valida(v):
    return type(v) in (int, float) and math.isfinite(v) and 0 < v <= 20


def _categoria_pronostico(publicacion, umbrales):
    """0 = ninguna, 1 = supera alerta, 2 = supera evacuación."""
    if not isinstance(publicacion, dict) or not umbrales_validos(umbrales):
        return 0
    pronostico = publicacion.get("pronostico")
    if not isinstance(pronostico, dict) or pronostico.get("vigente") is not True:
        return 0
    altura = pronostico.get("altura_esperada_m")
    if not _altura_valida(altura):
        return 0
    if altura >= umbrales["evacuacion_m"]:
        return 2
    if altura >= umbrales["alerta_m"]:
        return 1
    return 0


def decidir(anterior, nuevo, umbrales):
    """Compara dos publicaciones de actual.json. Nunca lanza excepción: lo que
    venga mal formado se trata como sin dato.

    - Nivel: avisa si los dos tienen nivel con dato y son distintos (subida o
      bajada; la app filtra según el mínimo que eligió el usuario). Entrar o
      salir de sin_dato no avisa: una caída de la fuente no es un cambio de nivel.
      El nivel publicado ya trae la retención y el margen al bajar del lector,
      así que no se recalcula desde la altura.
    - Pronóstico: avisa si la altura esperada pasa a superar un umbral más alto
      que antes (ninguno < alerta < evacuación). Bajar no avisa.
    - Sin anterior (primer arranque) no hay contra qué comparar: no avisa.
    """
    if not isinstance(anterior, dict):
        return {"avisar": False, "tipo": None,
                "motivo": "No hay publicación anterior para comparar."}

    nivel_antes, nivel_ahora = _nivel(anterior), _nivel(nuevo)
    cambio_nivel = None
    if nivel_antes and nivel_ahora and nivel_antes != nivel_ahora:
        subio = NIVELES_CON_DATO.index(nivel_ahora) > NIVELES_CON_DATO.index(nivel_antes)
        cambio_nivel = "El nivel {} de {} a {}".format(
            "subió" if subio else "bajó",
            NOMBRES_NIVEL[nivel_antes], NOMBRES_NIVEL[nivel_ahora])

    cat_antes = _categoria_pronostico(anterior, umbrales)
    cat_ahora = _categoria_pronostico(nuevo, umbrales)
    cambio_pronostico = None
    if cat_ahora > cat_antes:
        cambio_pronostico = "el pronóstico supera la altura de {}".format(
            NOMBRES_PRONOSTICO[cat_ahora])

    if cambio_nivel and cambio_pronostico:
        return {"avisar": True, "tipo": "nivel",
                "motivo": f"{cambio_nivel} y {cambio_pronostico}."}
    if cambio_nivel:
        return {"avisar": True, "tipo": "nivel", "motivo": f"{cambio_nivel}."}
    if cambio_pronostico:
        return {"avisar": True, "tipo": "pronostico",
                "motivo": cambio_pronostico[0].upper() + cambio_pronostico[1:] + "."}
    if not (nivel_antes and nivel_ahora):
        motivo = "Sin aviso: falta el nivel en alguna de las dos publicaciones."
    else:
        motivo = "Sin cambios para avisar."
    return {"avisar": False, "tipo": None, "motivo": motivo}


# ---------- lectura ----------

def _json_de_texto(texto):
    """Objeto JSON o None si no es JSON o no es un objeto."""
    try:
        datos = json.loads(texto)
    except (ValueError, RecursionError):
        return None
    return datos if isinstance(datos, dict) else None


def _leer_archivo(ruta):
    try:
        texto = Path(ruta).read_text(encoding="utf-8-sig")
    except (OSError, UnicodeDecodeError):
        return None
    return _json_de_texto(texto)


def _git(*args):
    """Corre git sin shell. Devuelve (código, stdout en bytes)."""
    try:
        r = subprocess.run(["git", *args], capture_output=True, timeout=60)
    except (OSError, subprocess.SubprocessError) as e:
        raise ErrorAvisos(f"no se pudo correr git: {type(e).__name__}") from e
    return r.returncode, r.stdout


def _resolver(revision):
    """Revisión -> hash del commit. Se rechaza todo lo que no parezca una
    revisión común, para que nunca se tome como una opción de git."""
    if (not isinstance(revision, str) or revision.startswith("-")
            or not REVISION_VALIDA.fullmatch(revision)):
        raise ErrorAvisos("revisión inválida")
    codigo, salida = _git("rev-parse", "--verify", "--quiet", revision + "^{commit}")
    if codigo != 0:
        raise ErrorAvisos("la revisión no existe")
    return salida.decode("ascii", "replace").strip()


def _leer_de_commit(commit, ruta):
    """JSON de `ruta` en `commit`, o None si no está o no se puede leer."""
    codigo, salida = _git("show", f"{commit}:{ruta}")
    if codigo != 0:
        return None
    try:
        return _json_de_texto(salida.decode("utf-8-sig"))
    except UnicodeDecodeError:
        return None


def _anterior_con_nivel(commit, anterior):
    """Si el anterior no tiene nivel con dato, busca hacia atrás la última
    versión de actual.json que sí lo tenga: así una caída de la fuente no hace
    perder un cambio de nivel real cuando vuelve.

    El pronóstico se sigue comparando contra el anterior inmediato (si se pudo
    leer), para no repetir un aviso de pronóstico ya mandado durante la caída."""
    if _nivel(anterior):
        return anterior
    codigo, salida = _git("log", "--format=%H", "-n", str(MAX_HISTORIA),
                          commit, "--", RUTA_ACTUAL)
    if codigo != 0:
        raise ErrorAvisos("git log falló")
    for linea in salida.decode("ascii", "replace").split():
        if linea == commit:
            continue
        candidato = _leer_de_commit(linea, RUTA_ACTUAL)
        if _nivel(candidato):
            if isinstance(anterior, dict):
                candidato = dict(candidato, pronostico=anterior.get("pronostico"))
            return candidato
    return anterior


# ---------- línea de comandos ----------

class _Argumentos(argparse.ArgumentParser):
    def error(self, mensaje):
        raise ErrorAvisos(mensaje)


def _decidir_desde_argumentos(argv):
    p = _Argumentos(description="Decide si hay que mandar un aviso push.")
    p.add_argument("archivos", nargs="*", metavar="JSON",
                   help="ANTERIOR.json NUEVO.json")
    p.add_argument("--umbrales", help=f"por defecto {RUTA_UMBRALES}")
    p.add_argument("--anterior", help="commit de la publicación anterior")
    p.add_argument("--nuevo", help="commit de la publicación nueva (por defecto HEAD)")
    a = p.parse_args(argv)

    if a.anterior is not None:
        if a.archivos or a.umbrales is not None:
            raise ErrorAvisos("--anterior no se combina con archivos ni con --umbrales")
        anterior_commit = _resolver(a.anterior)
        nuevo_commit = _resolver(a.nuevo if a.nuevo is not None else "HEAD")
        nuevo = _leer_de_commit(nuevo_commit, RUTA_ACTUAL)
        if nuevo is None:
            raise ErrorAvisos("el actual.json nuevo falta o no es un objeto JSON")
        umbrales = _leer_de_commit(nuevo_commit, RUTA_UMBRALES)
        anterior = _anterior_con_nivel(
            anterior_commit, _leer_de_commit(anterior_commit, RUTA_ACTUAL))
        return decidir(anterior, nuevo, umbrales)

    if a.nuevo is not None:
        raise ErrorAvisos("--nuevo necesita --anterior")
    if len(a.archivos) != 2:
        raise ErrorAvisos("hacen falta ANTERIOR.json y NUEVO.json")
    nuevo = _leer_archivo(a.archivos[1])
    if nuevo is None:
        raise ErrorAvisos("el actual.json nuevo falta o no es un objeto JSON")
    umbrales = _leer_archivo(a.umbrales if a.umbrales is not None else RUTA_UMBRALES)
    return decidir(_leer_archivo(a.archivos[0]), nuevo, umbrales)


def main(argv=None):
    try:
        decision = _decidir_desde_argumentos(sys.argv[1:] if argv is None else argv)
    except ErrorAvisos as e:
        print(f"avisos: no se pudo decidir: {e}", file=sys.stderr)
        return 2

    print(json.dumps(decision))
    salida = os.environ.get("GITHUB_OUTPUT")
    if salida:
        lineas = "avisar={}\ntipo={}\n".format(
            "true" if decision["avisar"] else "false", decision["tipo"] or "ninguno")
        try:
            with open(salida, "a", encoding="utf-8") as f:
                f.write(lineas)
        except OSError as e:
            print(f"avisos: no se pudo escribir GITHUB_OUTPUT: {type(e).__name__}",
                  file=sys.stderr)
            return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
