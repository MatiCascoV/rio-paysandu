"""Tests de lector/avisos.py: la decisión de avisar y la línea de comandos."""
import copy
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

import avisos

FIXTURES = Path(__file__).parent / "fixtures" / "avisos"
SCRIPT = Path(__file__).resolve().parent.parent / "avisos.py"


def cargar(nombre):
    return json.loads((FIXTURES / nombre).read_text(encoding="utf-8"))


BASE = cargar("actual_alerta.json")            # nivel alerta, pronóstico 5.83 m
UMBRALES = cargar("umbrales.json")             # alerta 4.39, evacuación 6.89
UMBRALES_INVALIDOS = cargar("umbrales_invalidos.json")


def pub(nivel="alerta", altura=5.83, vigente=True):
    """Publicación realista a partir del fixture, cambiando solo lo que importa."""
    p = copy.deepcopy(BASE)
    p["nivel"] = nivel
    p["pronostico"]["altura_esperada_m"] = altura
    p["pronostico"]["vigente"] = vigente
    return p


# ---------- nivel ----------

def test_subida_de_nivel_avisa():
    d = avisos.decidir(pub("atencion"), pub("alerta"), UMBRALES)
    assert d == {"avisar": True, "tipo": "nivel",
                 "motivo": "El nivel subió de atención a alerta."}


def test_bajada_de_nivel_avisa():
    d = avisos.decidir(pub("evacuacion", 5.0), pub("alerta", 5.0), UMBRALES)
    assert d["avisar"] and d["tipo"] == "nivel"
    assert d["motivo"] == "El nivel bajó de evacuación a alerta."


def test_mismo_nivel_no_avisa():
    d = avisos.decidir(pub(), pub(), UMBRALES)
    assert d == {"avisar": False, "tipo": None, "motivo": "Sin cambios para avisar."}


def test_entrar_y_salir_de_sin_dato_no_avisa():
    sin_dato = cargar("actual_sin_dato.json")
    assert not avisos.decidir(sin_dato, BASE, UMBRALES)["avisar"]
    assert not avisos.decidir(BASE, sin_dato, UMBRALES)["avisar"]


def test_sin_anterior_no_avisa():
    # Ni siquiera con un pronóstico que supera evacuación: no hay contra qué comparar.
    d = avisos.decidir(None, pub("evacuacion", 7.5), UMBRALES)
    assert d["avisar"] is False and d["tipo"] is None


@pytest.mark.parametrize("raro", ["inundado", "", "ALERTA", None, 3, ["alerta"], {"a": 1}])
def test_nivel_desconocido_no_avisa(raro):
    anterior = pub("normal")
    nuevo = pub()
    nuevo["nivel"] = raro
    assert not avisos.decidir(anterior, nuevo, UMBRALES)["avisar"]
    assert not avisos.decidir(nuevo, anterior, UMBRALES)["avisar"]


# ---------- pronóstico ----------

def test_pronostico_pasa_a_superar_alerta():
    d = avisos.decidir(pub(altura=4.0), pub(altura=4.39), UMBRALES)
    assert d == {"avisar": True, "tipo": "pronostico",
                 "motivo": "El pronóstico supera la altura de alerta."}


def test_pronostico_pasa_a_superar_evacuacion():
    d = avisos.decidir(pub(altura=4.0), pub(altura=7.1), UMBRALES)
    assert d["tipo"] == "pronostico"
    assert d["motivo"] == "El pronóstico supera la altura de evacuación."


def test_pronostico_de_alerta_a_evacuacion_avisa():
    d = avisos.decidir(pub(altura=5.83), pub(altura=6.89), UMBRALES)
    assert d["avisar"] and d["tipo"] == "pronostico"


@pytest.mark.parametrize("antes,ahora", [(5.83, 6.2), (7.0, 7.5), (3.0, 4.0)])
def test_pronostico_en_la_misma_categoria_no_avisa(antes, ahora):
    assert not avisos.decidir(pub(altura=antes), pub(altura=ahora), UMBRALES)["avisar"]


@pytest.mark.parametrize("antes,ahora", [(7.0, 5.83), (7.0, 3.0), (5.83, 3.0)])
def test_pronostico_que_baja_no_avisa(antes, ahora):
    assert not avisos.decidir(pub(altura=antes), pub(altura=ahora), UMBRALES)["avisar"]


@pytest.mark.parametrize("vigente", [False, None, "true", 1])
def test_pronostico_no_vigente_no_avisa(vigente):
    d = avisos.decidir(pub(altura=4.0), pub(altura=7.5, vigente=vigente), UMBRALES)
    assert not d["avisar"]


def test_pronostico_que_deja_de_estar_vigente_y_vuelve_avisa():
    # No vigente cuenta como "ninguna": al volver vigente sobre alerta se avisa.
    d = avisos.decidir(pub(altura=5.83, vigente=False), pub(altura=5.83), UMBRALES)
    assert d["tipo"] == "pronostico"


@pytest.mark.parametrize("umbrales", [UMBRALES_INVALIDOS, None, {}, [], "x",
                                      {"alerta_m": True, "evacuacion_m": 6.89}])
def test_umbrales_invalidos_no_avisan_por_pronostico(umbrales):
    assert not avisos.decidir(pub(altura=3.0), pub(altura=7.5), umbrales)["avisar"]


def test_umbrales_invalidos_no_frenan_el_aviso_de_nivel():
    d = avisos.decidir(pub("normal"), pub("alerta"), UMBRALES_INVALIDOS)
    assert d["tipo"] == "nivel"


# ---------- los dos juntos ----------

def test_nivel_y_pronostico_juntos():
    d = avisos.decidir(pub("normal", 4.0), pub("alerta", 7.0), UMBRALES)
    assert d == {"avisar": True, "tipo": "nivel",
                 "motivo": "El nivel subió de normal a alerta y el pronóstico "
                           "supera la altura de evacuación."}


# ---------- datos mal formados ----------

@pytest.mark.parametrize("raro", [None, [], "texto", 5, {}, {"nivel": None},
                                  {"nivel": "alerta", "pronostico": None},
                                  {"nivel": "alerta", "pronostico": []},
                                  {"nivel": "alerta", "pronostico": {"vigente": True}}])
def test_datos_mal_formados_no_lanzan(raro):
    for anterior, nuevo in ((raro, BASE), (BASE, raro), (raro, raro)):
        d = avisos.decidir(anterior, nuevo, UMBRALES)
        assert set(d) == {"avisar", "tipo", "motivo"}
        assert d["tipo"] in ("nivel", "pronostico", None)


@pytest.mark.parametrize("altura", [float("nan"), float("inf"), True, "7.5", 0, -1, 25, None])
def test_altura_esperada_invalida_es_sin_dato(altura):
    assert not avisos.decidir(pub(altura=3.0), pub(altura=altura), UMBRALES)["avisar"]


def test_motivo_no_copia_texto_del_json():
    nuevo = pub("evacuacion", 7.5)
    nuevo["pronostico"]["texto"] = "Evacuar ya\nfalso=1"
    d = avisos.decidir(pub("alerta", 3.0), nuevo, UMBRALES)
    assert "Evacuar" not in d["motivo"] and "\n" not in d["motivo"]


# ---------- línea de comandos: dos archivos ----------

def correr(args, cwd, salida_github=None):
    env = {k: v for k, v in os.environ.items() if k != "GITHUB_OUTPUT"}
    if salida_github:
        env["GITHUB_OUTPUT"] = str(salida_github)
    return subprocess.run([sys.executable, str(SCRIPT), *args], cwd=cwd, env=env,
                          capture_output=True, text=True, timeout=60)


def escribir(ruta, datos):
    ruta.parent.mkdir(parents=True, exist_ok=True)
    texto = datos if isinstance(datos, str) else json.dumps(datos, ensure_ascii=False)
    ruta.write_text(texto, encoding="utf-8")
    return ruta


def test_cli_archivos_avisa_y_escribe_github_output(tmp_path):
    anterior = escribir(tmp_path / "a.json", pub("atencion"))
    nuevo = escribir(tmp_path / "n.json", pub("alerta"))
    escribir(tmp_path / "data" / "umbrales.json", UMBRALES)
    salida = tmp_path / "github_output"
    salida.write_text("previo=1\n", encoding="utf-8")
    r = correr([str(anterior), str(nuevo)], tmp_path, salida)
    assert r.returncode == 0, r.stderr
    assert json.loads(r.stdout) == {"avisar": True, "tipo": "nivel",
                                    "motivo": "El nivel subió de atención a alerta."}
    assert salida.read_text(encoding="utf-8") == "previo=1\navisar=true\ntipo=nivel\n"


def test_cli_archivos_sin_aviso_y_umbrales_por_opcion(tmp_path):
    anterior = escribir(tmp_path / "a.json", pub(altura=3.0))
    nuevo = escribir(tmp_path / "n.json", pub(altura=5.0))
    umbrales = escribir(tmp_path / "u.json", UMBRALES)
    salida = tmp_path / "out"
    r = correr([str(anterior), str(nuevo)], tmp_path, salida)   # sin data/umbrales.json
    assert r.returncode == 0 and json.loads(r.stdout)["avisar"] is False
    r = correr([str(anterior), str(nuevo), "--umbrales", str(umbrales)], tmp_path, salida)
    assert r.returncode == 0 and json.loads(r.stdout)["tipo"] == "pronostico"
    assert salida.read_text(encoding="utf-8") == (
        "avisar=false\ntipo=ninguno\navisar=true\ntipo=pronostico\n")


def test_cli_anterior_ilegible_equivale_a_sin_anterior(tmp_path):
    anterior = escribir(tmp_path / "a.json", "{roto")
    nuevo = escribir(tmp_path / "n.json", pub("evacuacion", 7.5))
    r = correr([str(anterior), str(nuevo)], tmp_path)
    assert r.returncode == 0 and json.loads(r.stdout)["avisar"] is False
    r = correr([str(tmp_path / "no_existe.json"), str(nuevo)], tmp_path)
    assert r.returncode == 0 and json.loads(r.stdout)["avisar"] is False


@pytest.mark.parametrize("contenido", [None, "{roto", "[1, 2]", "\"alerta\"", b"\xff\xfe\x00"])
def test_cli_nuevo_inexistente_o_ilegible_sale_con_2(tmp_path, contenido):
    anterior = escribir(tmp_path / "a.json", BASE)
    nuevo = tmp_path / "n.json"
    if isinstance(contenido, bytes):
        nuevo.write_bytes(contenido)
    elif contenido is not None:
        escribir(nuevo, contenido)
    salida = tmp_path / "out"
    r = correr([str(anterior), str(nuevo)], tmp_path, salida)
    assert r.returncode == 2 and r.stdout == ""
    assert not salida.exists()


@pytest.mark.parametrize("args", [[], ["uno.json"], ["a", "b", "c"], ["--nuevo", "HEAD"],
                                  ["--anterior", "HEAD", "a.json", "b.json"], ["--otra"]])
def test_cli_argumentos_mal_sale_con_2(tmp_path, args):
    assert correr(args, tmp_path).returncode == 2


# ---------- línea de comandos: git ----------

class Repo:
    def __init__(self, ruta):
        self.ruta = ruta
        self.git("init", "-q")
        self.git("config", "user.name", "Prueba")
        self.git("config", "user.email", "prueba@example.com")
        self.git("config", "commit.gpgsign", "false")

    def git(self, *args):
        env = dict(os.environ, GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull)
        r = subprocess.run(["git", *args], cwd=self.ruta, env=env,
                           capture_output=True, text=True, check=True)
        return r.stdout.strip()

    def commit(self, actual=None, umbrales=None, mensaje="datos"):
        if actual is not None:
            escribir(self.ruta / "data" / "actual.json", actual)
        if umbrales is not None:
            escribir(self.ruta / "data" / "umbrales.json", umbrales)
        if actual is None and umbrales is None:
            escribir(self.ruta / "otro.txt", mensaje)
        self.git("add", "-A")
        self.git("commit", "-q", "-m", mensaje)
        return self.git("rev-parse", "HEAD")


@pytest.fixture
def repo(tmp_path):
    if shutil.which("git") is None:
        pytest.skip("git no disponible")
    return Repo(tmp_path)


def test_git_cambio_de_nivel(repo):
    c1 = repo.commit(pub("atencion"), UMBRALES)
    c2 = repo.commit(pub("alerta"))
    salida = repo.ruta / "out"
    r = correr(["--anterior", c1, "--nuevo", c2], repo.ruta, salida)
    assert r.returncode == 0, r.stderr
    assert json.loads(r.stdout)["tipo"] == "nivel"
    assert salida.read_text(encoding="utf-8") == "avisar=true\ntipo=nivel\n"
    # --nuevo por defecto es HEAD; también acepta revisiones relativas.
    r = correr(["--anterior", "HEAD~1"], repo.ruta)
    assert r.returncode == 0 and json.loads(r.stdout)["tipo"] == "nivel"


def test_git_umbrales_salen_del_commit_nuevo(repo):
    c1 = repo.commit(pub(altura=5.0), UMBRALES_INVALIDOS)
    c2 = repo.commit(pub(altura=5.0), UMBRALES)
    # Con los umbrales del nuevo, el anterior también se mide contra alerta 4.39:
    # mismo pronóstico, misma categoría, sin aviso.
    r = correr(["--anterior", c1, "--nuevo", c2], repo.ruta)
    assert r.returncode == 0 and json.loads(r.stdout)["avisar"] is False
    c3 = repo.commit(pub(altura=7.0), UMBRALES_INVALIDOS)
    r = correr(["--anterior", c2, "--nuevo", c3], repo.ruta)
    assert r.returncode == 0 and json.loads(r.stdout)["avisar"] is False


def test_git_busca_hacia_atras_saltando_sin_dato(repo):
    repo.commit(pub("normal"), UMBRALES, "normal")
    repo.commit(pub("atencion"), mensaje="atencion")
    caida = repo.commit(cargar("actual_sin_dato.json"), mensaje="caída")
    repo.commit(mensaje="commit que no toca actual.json")
    vuelta = repo.commit(pub("alerta"), mensaje="vuelve")
    # El anterior inmediato de la vuelta es sin_dato: se compara contra "atencion".
    r = correr(["--anterior", "HEAD~1", "--nuevo", vuelta], repo.ruta)
    assert r.returncode == 0, r.stderr
    assert json.loads(r.stdout) == {"avisar": True, "tipo": "nivel",
                                    "motivo": "El nivel subió de atención a alerta."}
    r = correr(["--anterior", caida, "--nuevo", vuelta], repo.ruta)
    assert json.loads(r.stdout)["tipo"] == "nivel"


def test_git_vuelta_al_mismo_nivel_no_avisa(repo):
    repo.commit(pub("alerta"), UMBRALES)
    caida = repo.commit(cargar("actual_sin_dato.json"))
    vuelta = repo.commit(pub("alerta"))
    r = correr(["--anterior", caida, "--nuevo", vuelta], repo.ruta)
    assert r.returncode == 0 and json.loads(r.stdout)["avisar"] is False


def test_git_no_repite_pronostico_avisado_durante_la_caida(repo):
    repo.commit(pub("alerta", 3.0), UMBRALES)
    caida = cargar("actual_sin_dato.json")
    caida["pronostico"]["altura_esperada_m"] = 5.0     # en la caída ya se avisó alerta
    c_caida = repo.commit(caida)
    vuelta = repo.commit(pub("alerta", 5.0))
    r = correr(["--anterior", c_caida, "--nuevo", vuelta], repo.ruta)
    assert r.returncode == 0 and json.loads(r.stdout)["avisar"] is False


def test_git_sin_historia_con_dato_no_avisa(repo):
    c1 = repo.commit(cargar("actual_sin_dato.json"), UMBRALES)
    c2 = repo.commit(pub("evacuacion"))
    r = correr(["--anterior", c1, "--nuevo", c2], repo.ruta)
    assert r.returncode == 0 and json.loads(r.stdout)["avisar"] is False


def test_git_anterior_sin_actual_json_no_avisa(repo):
    c1 = repo.commit(umbrales=UMBRALES)
    c2 = repo.commit(pub("evacuacion", 7.5))
    r = correr(["--anterior", c1, "--nuevo", c2], repo.ruta)
    assert r.returncode == 0 and json.loads(r.stdout)["avisar"] is False


def test_git_nuevo_sin_actual_json_sale_con_2(repo):
    c1 = repo.commit(umbrales=UMBRALES)
    repo.commit(mensaje="otro")
    assert correr(["--anterior", c1], repo.ruta).returncode == 2


@pytest.mark.parametrize("revision", ["-h", "--output=/tmp/x", "-", "HEAD;ls", "HEAD:data/x",
                                      "HEAD@{1}", "HEAD a", "", "no-existe"])
def test_git_revision_invalida_sale_con_2(repo, revision):
    repo.commit(pub(), UMBRALES)
    salida = repo.ruta / "out"
    # Con "=" la revisión llega entera a avisos.py (argparse no la toma como opción).
    assert correr([f"--anterior={revision}"], repo.ruta, salida).returncode == 2
    assert correr(["--anterior=HEAD", f"--nuevo={revision}"], repo.ruta).returncode == 2
    assert not salida.exists()


def test_revision_que_empieza_con_guion_se_rechaza_sin_llamar_a_git(monkeypatch):
    def no_llamar(*args):
        raise AssertionError("no tenía que correr git")
    monkeypatch.setattr(avisos, "_git", no_llamar)
    for revision in ("-h", "--output=x", "-", "HEAD;ls", "HEAD:data/x", ""):
        with pytest.raises(avisos.ErrorAvisos):
            avisos._resolver(revision)
