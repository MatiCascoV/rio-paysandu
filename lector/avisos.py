"""Decide si hay que mandar avisos push a partir de las publicaciones de actual.json.

Lo usa .github/workflows/avisos.yml: el push va sin texto, así que acá solo se
decide *si* avisar y de qué tipo; la app arma el aviso con lo que diga actual.json.

Hay dos avisos, independientes (pueden salir los dos en la misma pasada):
- Urgente: el nivel SUBE a alerta o a evacuación.
- Resumen del día: uno por día, solo con nivel atención o más.

Uso (desde la raíz del repositorio):
    python lector/avisos.py ANTERIOR.json NUEVO.json
    python lector/avisos.py --commit <commit>

Imprime una línea JSON con la decisión. Si existe GITHUB_OUTPUT, agrega
`avisar=true|false`, `urgente=alerta|evacuacion|ninguno`, `resumen=true|false`
y `fuente=prefectura|estacion|ninguna`. Sale con 0 si pudo decidir (avise o no)
y con 2 si no pudo.

Solo biblioteca estándar: corre en un workflow con credenciales donde no se
instala nada con pip.
"""
import argparse
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

from nivel import NIVELES_CON_DATO

# Nombres para el motivo. Solo se escriben valores que estén en estas listas:
# el motivo termina en el resumen de GitHub Actions y nada del JSON se copia tal cual.
NOMBRES_NIVEL = {
    "normal": "normal",
    "atencion": "atención",
    "alerta": "alerta",
    "evacuacion": "evacuación",
}
NIVELES_URGENTES = ("alerta", "evacuacion")
NIVELES_CON_RESUMEN = ("atencion", "alerta", "evacuacion")

# Uruguay no tiene horario de verano: la hora local es siempre UTC-3.
ZONA_LOCAL = timezone(timedelta(hours=-3))
# Si a esta hora local todavía no llegó la lectura de Prefectura del día, el
# resumen sale con la estación automática.
HORA_RESPALDO = 10

RUTA_ACTUAL = "data/actual.json"
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


def _hora_local(texto):
    """Fecha y hora ISO 8601 con offset -> datetime en UTC-3, o None.
    Sin offset no se sabe qué hora es: se toma como inválida."""
    if not isinstance(texto, str) or len(texto) > 64:
        return None
    if texto.endswith(("Z", "z")):
        texto = texto[:-1] + "+00:00"
    try:
        momento = datetime.fromisoformat(texto)
    except ValueError:
        return None
    if momento.tzinfo is None or momento.utcoffset() is None:
        return None
    try:
        return momento.astimezone(ZONA_LOCAL)
    except (OverflowError, ValueError):
        return None


def _generado(publicacion):
    if not isinstance(publicacion, dict):
        return None
    return _hora_local(publicacion.get("generado"))


def _fecha_prefectura(publicacion):
    lectura = publicacion.get("lectura_prefectura") if isinstance(publicacion, dict) else None
    if not isinstance(lectura, dict):
        return None
    momento = _hora_local(lectura.get("fecha"))
    return momento.date() if momento else None


def resumen_listo(publicacion):
    """Con qué fuente saldría el resumen del día en esta publicación, sin mirar
    si ya salió: "prefectura" si ya llegó la lectura de Prefectura de hoy,
    "estacion" si no llegó pero ya son las 10, None si no corresponde (nivel
    normal o sin dato, fecha inválida, o antes de las 10 sin Prefectura)."""
    if _nivel(publicacion) not in NIVELES_CON_RESUMEN:
        return None
    generado = _generado(publicacion)
    if generado is None:
        return None
    if _fecha_prefectura(publicacion) == generado.date():
        return "prefectura"
    if generado.hour >= HORA_RESPALDO:
        return "estacion"
    return None


def decidir(nuevo, anteriores):
    """Decide los avisos de `nuevo`. `anteriores` son las publicaciones previas,
    de la más reciente a la más vieja (puede ser un generador: se lee solo lo
    necesario). Nunca lanza excepción: lo que venga mal formado se trata como
    sin dato.

    - Urgente: el nivel nuevo es alerta o evacuación y es mayor que el último
      nivel con dato anterior (se saltean las publicaciones sin_dato, así una
      caída de la fuente no hace perder una subida real). Bajar, quedarse igual
      o entrar/salir de sin_dato no avisa. Sin anterior con dato no avisa.
      El nivel publicado ya trae la retención y el margen al bajar del lector,
      así que no se recalcula desde la altura.
    - Resumen: `resumen_listo(nuevo)` no es None y ninguna publicación anterior
      del mismo día local lo tenía. Así se decide sin estado guardado y es
      reproducible desde el historial: nunca dos resúmenes el mismo día.
    """
    nivel_ahora = _nivel(nuevo)
    generado = _generado(nuevo)
    hoy = generado.date() if generado else None
    fuente = resumen_listo(nuevo)

    nivel_antes = None
    ya_hubo_resumen = False
    buscar_nivel = nivel_ahora in NIVELES_URGENTES
    buscar_dia = fuente is not None
    iterador = iter(anteriores) if (buscar_nivel or buscar_dia) else iter(())
    for anterior in iterador:
        if buscar_nivel and _nivel(anterior):
            nivel_antes = _nivel(anterior)
            buscar_nivel = False
        if buscar_dia:
            fecha = _generado(anterior)
            if fecha is None or fecha.date() > hoy:
                continue    # sin fecha o de un día posterior: no cuenta para hoy
            if fecha.date() < hoy:
                buscar_dia = False      # llegamos a un día anterior: no hubo resumen hoy
            elif resumen_listo(anterior) is not None:
                ya_hubo_resumen = True
                buscar_dia = False
        if not (buscar_nivel or buscar_dia):
            break       # no se lee una versión más de la necesaria (cada una es un git show)

    urgente = None
    if (nivel_ahora in NIVELES_URGENTES and nivel_antes
            and NIVELES_CON_DATO.index(nivel_ahora) > NIVELES_CON_DATO.index(nivel_antes)):
        urgente = nivel_ahora
    resumen = fuente is not None and not ya_hubo_resumen

    partes = []
    if urgente:
        partes.append("El nivel subió de {} a {}.".format(
            NOMBRES_NIVEL[nivel_antes], NOMBRES_NIVEL[urgente]))
    if resumen:
        partes.append("Resumen del día con la lectura de Prefectura."
                      if fuente == "prefectura" else
                      "Resumen del día con la estación automática "
                      "(no llegó la lectura de Prefectura antes de las 10).")
    if not partes:
        if nivel_ahora is None:
            motivo = "Sin aviso: la publicación nueva no tiene nivel."
        elif nivel_ahora == "normal":
            motivo = "Sin aviso: nivel normal."
        elif ya_hubo_resumen:
            motivo = "Sin aviso: el nivel no subió y el resumen de hoy ya salió."
        elif generado is None:
            motivo = "Sin aviso: el nivel no subió y la fecha de la publicación no es válida."
        else:
            motivo = ("Sin aviso: el nivel no subió y todavía no llegó la lectura "
                      "de Prefectura de hoy (antes de las 10).")
        partes.append(motivo)

    return {"avisar": bool(urgente or resumen), "urgente": urgente,
            "resumen": resumen, "fuente": fuente if resumen else None,
            "motivo": " ".join(partes)}


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


def _log_de_actual(commit):
    """Commits que cambiaron actual.json hasta `commit`, del más reciente al más
    viejo (hasta MAX_HISTORIA + 1, contando el que dejó la versión vigente)."""
    codigo, salida = _git("log", "--format=%H", "-n", str(MAX_HISTORIA + 1),
                          commit, "--", RUTA_ACTUAL)
    if codigo != 0:
        raise ErrorAvisos("git log falló")
    return salida.decode("ascii", "replace").split()


def _bordes_shallow():
    """Commits donde se corta una historia poco profunda (git fetch --depth), o
    conjunto vacío si la historia está completa."""
    codigo, salida = _git("rev-parse", "--git-path", "shallow")
    if codigo != 0:
        raise ErrorAvisos("git rev-parse falló")
    try:
        texto = Path(salida.decode("utf-8", "replace").strip()).read_text(encoding="ascii")
    except FileNotFoundError:
        return set()
    except (OSError, UnicodeDecodeError) as e:
        raise ErrorAvisos(f"no se pudo leer el borde de la historia: {type(e).__name__}") from e
    return set(texto.split())


def _anteriores_de_git(log):
    """Versiones anteriores de actual.json, de la más reciente a la más vieja
    (hasta MAX_HISTORIA). Se leen de a una, a medida que decidir() las pide.

    `log` es lo que devuelve _log_de_actual(): la primera entrada es la
    publicación nueva y se saltea.

    En una historia poco profunda git muestra el commit del borde como si
    hubiera creado actual.json y no ve nada más atrás. Si decidir() pide una
    versión más allá del borde, se corta con error en vez de decidir con la
    historia incompleta (podría perder un urgente o repetir un resumen)."""
    anteriores = log[1:]
    for linea in anteriores:
        yield _leer_de_commit(linea, RUTA_ACTUAL)
    if anteriores and len(log) <= MAX_HISTORIA and anteriores[-1] in _bordes_shallow():
        raise ErrorAvisos("la historia traída no alcanza para decidir (hace falta un fetch más profundo)")


# ---------- línea de comandos ----------

class _Argumentos(argparse.ArgumentParser):
    def error(self, mensaje):
        raise ErrorAvisos(mensaje)


def _decidir_desde_argumentos(argv):
    p = _Argumentos(description="Decide si hay que mandar avisos push.")
    p.add_argument("archivos", nargs="*", metavar="JSON",
                   help="ANTERIOR.json NUEVO.json")
    p.add_argument("--commit", help="commit con el data/actual.json nuevo")
    a = p.parse_args(argv)

    if a.commit is not None:
        if a.archivos:
            raise ErrorAvisos("--commit no se combina con archivos")
        commit = _resolver(a.commit)
        nuevo = _leer_de_commit(commit, RUTA_ACTUAL)
        if nuevo is None:
            raise ErrorAvisos("el actual.json nuevo falta o no es un objeto JSON")
        log = _log_de_actual(commit)
        if not log or log[0] != commit:
            # El lector hace `git add data`: un commit que solo cambió el historial
            # trae el mismo actual.json que el anterior, que ya se avisó (o no) en
            # su momento. Decidir de nuevo repetiría el urgente y el resumen.
            return {"avisar": False, "urgente": None, "resumen": False, "fuente": None,
                    "motivo": "Sin aviso: el commit no cambió data/actual.json."}
        return decidir(nuevo, _anteriores_de_git(log))

    if len(a.archivos) != 2:
        raise ErrorAvisos("hacen falta ANTERIOR.json y NUEVO.json, o --commit")
    nuevo = _leer_archivo(a.archivos[1])
    if nuevo is None:
        raise ErrorAvisos("el actual.json nuevo falta o no es un objeto JSON")
    # Un anterior que no se puede leer equivale a no tener publicación previa.
    anterior = _leer_archivo(a.archivos[0])
    return decidir(nuevo, [anterior] if anterior is not None else [])


def main(argv=None):
    try:
        decision = _decidir_desde_argumentos(sys.argv[1:] if argv is None else argv)
    except ErrorAvisos as e:
        print(f"avisos: no se pudo decidir: {e}", file=sys.stderr)
        return 2

    print(json.dumps(decision))
    salida = os.environ.get("GITHUB_OUTPUT")
    if salida:
        lineas = "avisar={}\nurgente={}\nresumen={}\nfuente={}\n".format(
            "true" if decision["avisar"] else "false",
            decision["urgente"] or "ninguno",
            "true" if decision["resumen"] else "false",
            decision["fuente"] or "ninguna")
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
