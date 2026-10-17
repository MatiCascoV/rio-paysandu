"""Tests de lector/avisos.py: aviso urgente, resumen del día y la línea de comandos."""
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


BASE = cargar("actual_alerta.json")            # alerta, generado 16/10 20:17, Prefectura 16/10 06:00
MANANA = cargar("actual_atencion_manana.json")  # atención, generado 17/10 07:40, Prefectura 17/10 06:00
SIN_DATO = cargar("actual_sin_dato.json")       # sin_dato, sin lecturas

DIA = "2026-10-17"
AYER = "2026-10-16"


def pub(nivel="alerta", hora="12:00", dia=DIA, prefectura=DIA, generado=None):
    """Publicación realista a partir del fixture, cambiando solo lo que importa.

    `hora`/`dia` arman `generado` en UTC-3 (o se pasa `generado` entero).
    `prefectura` es el día de la lectura de Prefectura de las 06:00 (None = sin lectura)."""
    p = copy.deepcopy(BASE)
    p["nivel"] = nivel
    p["generado"] = generado if generado is not None else f"{dia}T{hora}:00-03:00"
    if prefectura is None:
        p["lectura_prefectura"] = None
    else:
        p["lectura_prefectura"]["fecha"] = f"{prefectura}T06:00:00-03:00"
    return p


def sin_dato(hora="12:00", dia=DIA):
    p = copy.deepcopy(SIN_DATO)
    p["generado"] = f"{dia}T{hora}:00-03:00"
    return p


def decidir(nuevo, *anteriores):
    """Anteriores de la más reciente a la más vieja."""
    return avisos.decidir(nuevo, list(anteriores))


CLAVES = {"avisar", "urgente", "resumen", "fuente", "motivo"}


# ---------- urgente ----------

@pytest.mark.parametrize("antes,ahora", [("atencion", "alerta"), ("normal", "alerta"),
                                         ("alerta", "evacuacion"), ("atencion", "evacuacion"),
                                         ("normal", "evacuacion")])
def test_subida_a_alerta_o_evacuacion_es_urgente(antes, ahora):
    # Antes de las 10 y sin Prefectura del día: solo el urgente.
    d = decidir(pub(ahora, "08:30", prefectura=AYER), pub(antes, "08:00", prefectura=AYER))
    assert d["urgente"] == ahora and d["avisar"] is True
    assert d["resumen"] is False and d["fuente"] is None


def test_normal_a_evacuacion_de_una():
    d = decidir(pub("evacuacion", "08:30", prefectura=AYER), pub("normal", "08:00", prefectura=AYER))
    assert d == {"avisar": True, "urgente": "evacuacion", "resumen": False, "fuente": None,
                 "motivo": "El nivel subió de normal a evacuación."}


def test_subida_a_atencion_no_es_urgente():
    d = decidir(pub("atencion", "08:30", prefectura=AYER), pub("normal", "08:00", prefectura=AYER))
    assert d["urgente"] is None and d["avisar"] is False


@pytest.mark.parametrize("antes,ahora", [("evacuacion", "alerta"), ("alerta", "atencion"),
                                         ("evacuacion", "normal"), ("alerta", "normal"),
                                         ("atencion", "normal")])
def test_bajadas_no_avisan(antes, ahora):
    d = decidir(pub(ahora, "08:30", prefectura=AYER), pub(antes, "08:00", prefectura=AYER))
    assert d["urgente"] is None and d["avisar"] is False


@pytest.mark.parametrize("nivel", ["normal", "atencion", "alerta", "evacuacion"])
def test_mismo_nivel_no_es_urgente(nivel):
    d = decidir(pub(nivel, "08:30", prefectura=AYER), pub(nivel, "08:00", prefectura=AYER))
    assert d["urgente"] is None and d["avisar"] is False


def test_sin_dato_no_avisa():
    # El nuevo sin_dato: nada (ni urgente ni resumen), aunque antes hubiera alerta.
    d = decidir(sin_dato("15:00"), pub("alerta", "14:30", prefectura=AYER))
    assert d == {"avisar": False, "urgente": None, "resumen": False, "fuente": None,
                 "motivo": "Sin aviso: la publicación nueva no tiene nivel."}
    # Solo anteriores sin_dato: no hay contra qué comparar, no es urgente.
    d = decidir(pub("evacuacion", "08:30", prefectura=AYER), sin_dato("08:00"), sin_dato("07:30"))
    assert d["urgente"] is None


def test_sin_anterior_no_es_urgente():
    assert decidir(pub("evacuacion", "08:30", prefectura=AYER))["urgente"] is None


def test_busqueda_hacia_atras_saltea_sin_dato():
    d = decidir(pub("alerta", "09:00", prefectura=AYER),
                sin_dato("08:30"), sin_dato("08:00"), pub("atencion", "07:30", prefectura=AYER))
    assert d["urgente"] == "alerta"
    assert d["motivo"] == "El nivel subió de atención a alerta."
    # Volver de la caída al mismo nivel no avisa.
    d = decidir(pub("alerta", "09:00", prefectura=AYER),
                sin_dato("08:30"), pub("alerta", "08:00", prefectura=AYER))
    assert d["urgente"] is None


@pytest.mark.parametrize("raro", ["inundado", "", "ALERTA", "sin_dato", None, 3, ["alerta"], {"a": 1}])
def test_nivel_desconocido_no_avisa(raro):
    nuevo = pub(hora="15:00")
    nuevo["nivel"] = raro
    assert decidir(nuevo, pub("normal", "14:30"))["avisar"] is False
    # Como anterior, se saltea: se compara contra el anterior con dato.
    otro = pub(hora="14:30")
    otro["nivel"] = raro
    assert decidir(pub("alerta", "09:00", prefectura=AYER), otro,
                   pub("atencion", "08:00", prefectura=AYER))["urgente"] == "alerta"


# ---------- resumen_listo ----------

def test_resumen_listo_con_prefectura_del_dia():
    assert avisos.resumen_listo(MANANA) == "prefectura"


@pytest.mark.parametrize("hora,esperado", [("00:00", None), ("09:59", None),
                                           ("10:00", "estacion"), ("23:59", "estacion")])
def test_resumen_listo_sin_prefectura_del_dia(hora, esperado):
    assert avisos.resumen_listo(pub("atencion", hora, prefectura=AYER)) == esperado
    assert avisos.resumen_listo(pub("atencion", hora, prefectura=None)) == esperado


@pytest.mark.parametrize("nivel", ["normal", "sin_dato", None, "x"])
def test_resumen_listo_sin_nivel_que_amerite(nivel):
    for hora in ("07:40", "12:00"):
        p = pub("alerta", hora, prefectura=DIA)
        p["nivel"] = nivel
        assert avisos.resumen_listo(p) is None


# ---------- resumen del día ----------

def test_resumen_con_prefectura_a_las_7_40():
    d = decidir(MANANA, pub("atencion", "07:10", prefectura=AYER))
    assert d == {"avisar": True, "urgente": None, "resumen": True, "fuente": "prefectura",
                 "motivo": "Resumen del día con la lectura de Prefectura."}


def test_sin_prefectura_espera_hasta_las_10():
    anterior = pub("alerta", "09:20", prefectura=AYER)
    d = decidir(pub("alerta", "09:50", prefectura=AYER), anterior)
    assert d["resumen"] is False and d["avisar"] is False
    assert "antes de las 10" in d["motivo"]
    d = decidir(pub("alerta", "10:05", prefectura=AYER), pub("alerta", "09:50", prefectura=AYER), anterior)
    assert d["resumen"] is True and d["fuente"] == "estacion" and d["avisar"] is True


def test_sin_lectura_de_prefectura_a_las_10_05_es_estacion():
    d = decidir(pub("atencion", "10:05", prefectura=None), pub("atencion", "09:50", prefectura=None))
    assert d["resumen"] is True and d["fuente"] == "estacion"


def test_prefectura_del_dia_anterior_a_las_10_05_es_estacion():
    d = decidir(pub("evacuacion", "10:05", prefectura=AYER))
    assert d["resumen"] is True and d["fuente"] == "estacion"


def test_segunda_publicacion_del_dia_no_repite_resumen():
    primera = copy.deepcopy(MANANA)
    segunda = copy.deepcopy(MANANA)
    segunda["generado"] = f"{DIA}T08:10:00-03:00"
    d = decidir(segunda, primera)
    assert d["resumen"] is False and d["avisar"] is False
    assert d["motivo"] == "Sin aviso: el nivel no subió y el resumen de hoy ya salió."


def test_prefectura_que_llega_a_las_13_despues_del_resumen_de_las_10():
    resumen_10 = pub("alerta", "10:00", prefectura=AYER)
    assert decidir(resumen_10, pub("alerta", "09:30", prefectura=AYER))["fuente"] == "estacion"
    d = decidir(pub("alerta", "13:00", prefectura=DIA),
                pub("alerta", "12:30", prefectura=AYER), resumen_10,
                pub("alerta", "09:30", prefectura=AYER))
    assert d["resumen"] is False and d["avisar"] is False


@pytest.mark.parametrize("hora", ["07:40", "10:05", "15:00", "23:50"])
def test_nivel_normal_nunca_resumen(hora):
    d = decidir(pub("normal", hora, prefectura=DIA), pub("normal", "06:30", prefectura=AYER))
    assert d == {"avisar": False, "urgente": None, "resumen": False, "fuente": None,
                 "motivo": "Sin aviso: nivel normal."}


def test_nivel_que_entra_en_atencion_a_las_15_manda_resumen():
    d = decidir(pub("atencion", "15:00", prefectura=DIA),
                pub("normal", "14:30", prefectura=DIA), pub("normal", "07:40", prefectura=DIA))
    assert d["resumen"] is True and d["fuente"] == "prefectura" and d["urgente"] is None
    d = decidir(pub("atencion", "15:00", prefectura=AYER), pub("normal", "14:30", prefectura=AYER))
    assert d["resumen"] is True and d["fuente"] == "estacion"


def test_cambio_de_dia():
    noche = pub("alerta", "23:50", dia=AYER, prefectura=AYER)
    assert decidir(noche, pub("alerta", "23:20", dia=AYER, prefectura=AYER),
                   pub("alerta", "08:00", dia=AYER, prefectura=AYER))["resumen"] is False
    assert decidir(noche, pub("alerta", "09:00", dia=AYER, prefectura=None))["fuente"] == "prefectura"
    # 00:10 del día siguiente: la Prefectura es de ayer y no son las 10.
    d = decidir(pub("alerta", "00:10", prefectura=AYER), noche)
    assert d["resumen"] is False and d["avisar"] is False
    d = decidir(pub("alerta", "09:50", prefectura=AYER), pub("alerta", "00:10", prefectura=AYER), noche)
    assert d["resumen"] is False
    # Los resúmenes de ayer no cuentan para hoy.
    d = decidir(pub("alerta", "10:05", prefectura=AYER),
                pub("alerta", "09:50", prefectura=AYER), pub("alerta", "00:10", prefectura=AYER), noche)
    assert d["resumen"] is True and d["fuente"] == "estacion"


@pytest.mark.parametrize("generado", ["", "ayer", "2026-10-17", "2026-10-17T07:40:00",
                                      "2026-13-01T10:00:00-03:00", "2026-10-17T25:00:00-03:00",
                                      None, 1760000000, ["2026-10-17T10:00:00-03:00"], "9" * 200])
def test_generado_invalido_no_hay_resumen(generado):
    nuevo = pub("alerta", prefectura=DIA, generado=generado)
    nuevo["generado"] = generado
    assert avisos.resumen_listo(nuevo) is None
    d = decidir(nuevo, pub("atencion", "07:00", prefectura=AYER))
    assert d["resumen"] is False and d["fuente"] is None
    assert d["urgente"] == "alerta"         # el urgente no depende de la fecha
    d = decidir(nuevo, pub("alerta", "07:00", prefectura=AYER))
    assert d["motivo"] == ("Sin aviso: el nivel no subió y la fecha de la publicación "
                           "no es válida.")


@pytest.mark.parametrize("generado,prefectura,esperado", [
    ("2026-10-17T13:05:00Z", f"{DIA}T06:00:00-03:00", "prefectura"),
    ("2026-10-17T13:05:00+00:00", f"{AYER}T06:00:00-03:00", "estacion"),    # 10:05 local
    ("2026-10-17T12:50:00+00:00", f"{AYER}T06:00:00-03:00", None),          # 09:50 local
    ("2026-10-18T02:30:00+00:00", f"{DIA}T06:00:00-03:00", "prefectura"),   # 17/10 23:30 local
    # 16/10 23:30 local: la Prefectura del 17 no es "del día" y ya pasaron las 10.
    ("2026-10-17T02:30:00+00:00", f"{DIA}T06:00:00-03:00", "estacion"),
    ("2026-10-17T07:40:00-03:00", "2026-10-17T09:00:00Z", "prefectura"),    # 06:00 local
    ("2026-10-17T07:40:00-03:00", "2026-10-17T02:00:00Z", None),            # 16/10 23:00 local
    ("2026-10-17T15:05:00+02:00", f"{AYER}T06:00:00-03:00", "estacion"),    # 10:05 local
    ("2026-10-17T07:40:00-03:00", "basura", None),
])
def test_generado_con_otro_offset_se_pasa_a_utc_menos_3(generado, prefectura, esperado):
    p = pub("alerta", generado=generado)
    p["lectura_prefectura"]["fecha"] = prefectura
    assert avisos.resumen_listo(p) == esperado


def test_resumen_del_dia_cuenta_publicaciones_anteriores_en_utc():
    # La publicación anterior está en UTC pero es del mismo día local y ya tenía resumen.
    anterior = pub("alerta", generado="2026-10-17T13:00:00Z", prefectura=AYER)   # 10:00 local
    d = decidir(pub("alerta", "11:00", prefectura=AYER), anterior)
    assert d["resumen"] is False
    # Esta otra es de ayer a la noche en hora local, aunque en UTC sea el 17.
    anterior = pub("alerta", generado="2026-10-17T02:00:00Z", prefectura=AYER)   # 16/10 23:00
    d = decidir(pub("alerta", "11:00", prefectura=AYER), anterior)
    assert d["resumen"] is True


def test_anteriores_sin_fecha_o_posteriores_no_cuentan_para_el_dia():
    roto = pub("alerta", generado="roto")
    futuro = pub("alerta", "09:00", dia="2026-10-18")
    d = decidir(pub("alerta", "11:00", prefectura=AYER), roto, futuro,
                pub("alerta", "09:00", prefectura=AYER))
    assert d["resumen"] is True and d["fuente"] == "estacion"


def test_urgente_y_resumen_en_la_misma_pasada():
    d = decidir(pub("evacuacion", "10:05", prefectura=AYER), pub("alerta", "09:35", prefectura=AYER))
    assert d == {"avisar": True, "urgente": "evacuacion", "resumen": True, "fuente": "estacion",
                 "motivo": "El nivel subió de alerta a evacuación. Resumen del día con la "
                           "estación automática (no llegó la lectura de Prefectura antes de las 10)."}
    d = decidir(MANANA | {"nivel": "alerta"}, pub("atencion", "07:10", prefectura=AYER))
    assert d["urgente"] == "alerta" and d["fuente"] == "prefectura"


def test_urgente_despues_del_resumen_sale_igual():
    d = decidir(pub("alerta", "15:00"), pub("atencion", "14:30"), pub("atencion", "07:40"))
    assert d["urgente"] == "alerta" and d["resumen"] is False and d["avisar"] is True


def test_lee_solo_las_anteriores_necesarias():
    def historia():
        yield pub("alerta", "09:00", prefectura=AYER)
        yield pub("normal", "08:00", dia=AYER, prefectura=AYER)
        raise AssertionError("no tenía que seguir leyendo")
    d = avisos.decidir(pub("evacuacion", "11:00", prefectura=AYER), historia())
    assert d["urgente"] == "evacuacion" and d["resumen"] is True


# ---------- datos mal formados ----------

@pytest.mark.parametrize("raro", [None, [], "texto", 5, {}, {"nivel": None},
                                  {"nivel": "alerta", "generado": None},
                                  {"nivel": "alerta", "generado": f"{DIA}T07:40:00-03:00",
                                   "lectura_prefectura": []},
                                  {"nivel": "alerta", "generado": f"{DIA}T07:40:00-03:00",
                                   "lectura_prefectura": {"fecha": 5}}])
def test_datos_mal_formados_no_lanzan(raro):
    for nuevo, anteriores in ((raro, [BASE]), (BASE, [raro]), (raro, [raro, raro]), (raro, [])):
        d = avisos.decidir(nuevo, anteriores)
        assert set(d) == CLAVES
        assert d["urgente"] in (None, "alerta", "evacuacion")
        assert d["fuente"] in (None, "prefectura", "estacion")
        assert d["avisar"] == bool(d["urgente"] or d["resumen"])


def test_motivo_no_copia_texto_del_json():
    nuevo = pub("evacuacion", "10:05", prefectura=AYER)
    nuevo["pronostico"]["texto"] = "Evacuar ya\nfalso=1"
    nuevo["altura_actual"]["fuente"] = "Evacuar\nurgente=evacuacion"
    d = decidir(nuevo, pub("alerta", "09:00", prefectura=AYER))
    assert "Evacuar" not in d["motivo"] and "\n" not in d["motivo"]


def test_el_pronostico_no_avisa():
    nuevo = pub("normal", "15:00")
    nuevo["pronostico"]["altura_esperada_m"] = 9.5
    assert decidir(nuevo, pub("normal", "14:30"))["avisar"] is False


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


def test_cli_archivos_urgente_y_resumen_escribe_github_output(tmp_path):
    anterior = escribir(tmp_path / "a.json", pub("alerta", "09:35", prefectura=AYER))
    nuevo = escribir(tmp_path / "n.json", pub("evacuacion", "10:05", prefectura=AYER))
    salida = tmp_path / "github_output"
    salida.write_text("previo=1\n", encoding="utf-8")
    r = correr([str(anterior), str(nuevo)], tmp_path, salida)
    assert r.returncode == 0, r.stderr
    d = json.loads(r.stdout)
    assert (d["avisar"], d["urgente"], d["resumen"], d["fuente"]) == (True, "evacuacion", True, "estacion")
    assert r.stdout.count("\n") == 1
    assert salida.read_text(encoding="utf-8") == (
        "previo=1\navisar=true\nurgente=evacuacion\nresumen=true\nfuente=estacion\n")


def test_cli_archivos_sin_aviso_y_solo_resumen(tmp_path):
    salida = tmp_path / "out"
    a = escribir(tmp_path / "a.json", pub("alerta", "09:20", prefectura=AYER))
    n = escribir(tmp_path / "n.json", pub("alerta", "09:50", prefectura=AYER))
    r = correr([str(a), str(n)], tmp_path, salida)
    assert r.returncode == 0 and json.loads(r.stdout)["avisar"] is False
    a = escribir(tmp_path / "a.json", pub("atencion", "07:10", prefectura=AYER))
    n = escribir(tmp_path / "n.json", MANANA)
    r = correr([str(a), str(n)], tmp_path, salida)
    assert r.returncode == 0 and json.loads(r.stdout)["fuente"] == "prefectura"
    a = escribir(tmp_path / "a.json", pub("alerta", "09:00", prefectura=AYER))
    n = escribir(tmp_path / "n.json", pub("alerta", "09:30", prefectura=AYER))
    correr([str(a), str(n)], tmp_path, salida)
    a = escribir(tmp_path / "a.json", pub("atencion", "09:00", prefectura=AYER))
    n = escribir(tmp_path / "n.json", pub("alerta", "09:30", prefectura=AYER))
    correr([str(a), str(n)], tmp_path, salida)
    assert salida.read_text(encoding="utf-8") == (
        "avisar=false\nurgente=ninguno\nresumen=false\nfuente=ninguna\n"
        "avisar=true\nurgente=ninguno\nresumen=true\nfuente=prefectura\n"
        "avisar=false\nurgente=ninguno\nresumen=false\nfuente=ninguna\n"
        "avisar=true\nurgente=alerta\nresumen=false\nfuente=ninguna\n")


def test_cli_archivos_segunda_publicacion_no_repite_resumen(tmp_path):
    resumen_10 = escribir(tmp_path / "a.json", pub("alerta", "10:00", prefectura=AYER))
    trece = escribir(tmp_path / "n.json", pub("alerta", "13:00", prefectura=DIA))
    r = correr([str(resumen_10), str(trece)], tmp_path)
    assert r.returncode == 0 and json.loads(r.stdout)["resumen"] is False
    primera = escribir(tmp_path / "a.json", MANANA)
    segunda = escribir(tmp_path / "n.json", MANANA | {"generado": f"{DIA}T08:10:00-03:00"})
    r = correr([str(primera), str(segunda)], tmp_path)
    assert r.returncode == 0 and json.loads(r.stdout)["avisar"] is False


def test_cli_anterior_ilegible_equivale_a_sin_anterior(tmp_path):
    nuevo = escribir(tmp_path / "n.json", pub("evacuacion", "08:30", prefectura=AYER))
    for anterior in (escribir(tmp_path / "a.json", "{roto"), tmp_path / "no_existe.json"):
        r = correr([str(anterior), str(nuevo)], tmp_path)
        assert r.returncode == 0 and json.loads(r.stdout)["avisar"] is False
    # Sin anterior, el resumen sí puede salir.
    nuevo = escribir(tmp_path / "n.json", MANANA)
    r = correr([str(tmp_path / "no_existe.json"), str(nuevo)], tmp_path)
    assert r.returncode == 0 and json.loads(r.stdout)["fuente"] == "prefectura"


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


@pytest.mark.parametrize("args", [[], ["uno.json"], ["a", "b", "c"], ["--commit"],
                                  ["--commit", "HEAD", "a.json"], ["--commit", "HEAD", "a.json", "b.json"],
                                  ["--anterior", "HEAD"], ["--nuevo", "HEAD"],
                                  ["a.json", "b.json", "--umbrales", "u.json"], ["--otra"]])
def test_cli_argumentos_mal_sale_con_2(tmp_path, args):
    escribir(tmp_path / "a.json", BASE)
    escribir(tmp_path / "b.json", BASE)
    salida = tmp_path / "out"
    r = correr(args, tmp_path, salida)
    assert r.returncode == 2 and r.stdout == ""
    assert not salida.exists()


def test_cli_github_output_que_no_se_puede_escribir_sale_con_2(tmp_path):
    a = escribir(tmp_path / "a.json", BASE)
    r = correr([str(a), str(a)], tmp_path, tmp_path / "no_existe" / "out")
    assert r.returncode == 2


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

    def commit(self, actual=None, mensaje="datos"):
        if actual is not None:
            escribir(self.ruta / "data" / "actual.json", actual)
        else:
            escribir(self.ruta / "otro.txt", mensaje)
        self.git("add", "-A")
        self.git("commit", "-q", "-m", mensaje)
        return self.git("rev-parse", "HEAD")


@pytest.fixture
def repo(tmp_path):
    if shutil.which("git") is None:
        pytest.skip("git no disponible")
    return Repo(tmp_path)


def decision_git(repo, revision="HEAD", salida=None):
    r = correr(["--commit", revision], repo.ruta, salida)
    assert r.returncode == 0, r.stderr
    return json.loads(r.stdout)


def test_git_subida_de_nivel(repo):
    repo.commit(pub("atencion", "08:00", prefectura=AYER))
    c = repo.commit(pub("alerta", "08:30", prefectura=AYER))
    salida = repo.ruta / "out"
    d = decision_git(repo, c, salida)
    assert d["urgente"] == "alerta" and d["resumen"] is False
    assert salida.read_text(encoding="utf-8") == (
        "avisar=true\nurgente=alerta\nresumen=false\nfuente=ninguna\n")
    # También acepta revisiones relativas.
    assert decision_git(repo, "HEAD~1")["avisar"] is False


def test_git_busca_hacia_atras_saltando_sin_dato(repo):
    repo.commit(pub("normal", "07:00", prefectura=AYER), "normal")
    repo.commit(pub("atencion", "07:30", prefectura=AYER), "atencion")
    repo.commit(sin_dato("08:00"), "caída")
    repo.commit(mensaje="commit que no toca actual.json")
    repo.commit(sin_dato("08:30"), "sigue la caída")
    vuelta = repo.commit(pub("alerta", "09:00", prefectura=AYER), "vuelve")
    d = decision_git(repo, vuelta)
    assert d == {"avisar": True, "urgente": "alerta", "resumen": False, "fuente": None,
                 "motivo": "El nivel subió de atención a alerta."}


def test_git_vuelta_al_mismo_nivel_no_avisa(repo):
    repo.commit(pub("alerta", "08:00", prefectura=AYER))
    repo.commit(sin_dato("08:30"))
    assert decision_git(repo, repo.commit(pub("alerta", "09:00", prefectura=AYER)))["avisar"] is False


def test_git_sin_historia_con_dato_no_es_urgente(repo):
    repo.commit(sin_dato("08:00"))
    assert decision_git(repo, repo.commit(pub("evacuacion", "08:30", prefectura=AYER)))["avisar"] is False


def test_git_primera_publicacion(repo):
    d = decision_git(repo, repo.commit(MANANA))
    assert d["urgente"] is None and d["resumen"] is True and d["fuente"] == "prefectura"


def test_git_un_dia_entero(repo):
    """Secuencia de publicaciones de dos días: cuándo sale cada resumen."""
    esperado = [
        (pub("alerta", "22:50", dia=AYER, prefectura=AYER), (None, "prefectura")),
        (pub("alerta", "23:50", dia=AYER, prefectura=AYER), (None, None)),
        (pub("alerta", "00:10", prefectura=AYER), (None, None)),
        (pub("alerta", "07:40", prefectura=AYER), (None, None)),
        (sin_dato("08:10"), (None, None)),
        (pub("alerta", "09:50", prefectura=AYER), (None, None)),
        (pub("alerta", "10:05", prefectura=AYER), (None, "estacion")),
        (pub("alerta", "10:35", prefectura=AYER), (None, None)),
        (pub("alerta", "13:00", prefectura=DIA), (None, None)),       # Prefectura llega tarde
        (pub("evacuacion", "15:00", prefectura=DIA), ("evacuacion", None)),
        (pub("alerta", "18:00", prefectura=DIA), (None, None)),
        (pub("alerta", "00:10", dia="2026-10-18", prefectura=DIA), (None, None)),
        (pub("alerta", "08:00", dia="2026-10-18", prefectura="2026-10-18"), (None, "prefectura")),
        (pub("alerta", "08:30", dia="2026-10-18", prefectura="2026-10-18"), (None, None)),
    ]
    for publicacion, (urgente, fuente) in esperado:
        c = repo.commit(publicacion, publicacion["generado"])
        d = decision_git(repo, c)
        assert (d["urgente"], d["fuente"]) == (urgente, fuente), publicacion["generado"]
        assert d["resumen"] is (fuente is not None)


def test_git_atencion_a_las_15_manda_resumen(repo):
    repo.commit(pub("normal", "07:40", prefectura=DIA))
    repo.commit(pub("normal", "10:05", prefectura=DIA))
    repo.commit(pub("normal", "14:30", prefectura=DIA))
    d = decision_git(repo, repo.commit(pub("atencion", "15:00", prefectura=DIA)))
    assert d["resumen"] is True and d["fuente"] == "prefectura"
    assert decision_git(repo, repo.commit(pub("atencion", "15:30", prefectura=DIA)))["avisar"] is False


def test_git_commit_que_no_toca_actual_json_no_repite_avisos(repo):
    # Revisión del 17/10: antes decidía como el commit que publicó actual.json y
    # repetía el urgente y el resumen (el lector hace `git add data`).
    repo.commit(pub("atencion", "09:35", prefectura=AYER))
    c = repo.commit(pub("alerta", "10:05", prefectura=AYER))
    d = decision_git(repo, c)
    assert d["urgente"] == "alerta" and d["resumen"] is True
    otro = repo.commit(mensaje="solo historial.json")
    salida = repo.ruta / "out"
    assert decision_git(repo, otro, salida) == {
        "avisar": False, "urgente": None, "resumen": False, "fuente": None,
        "motivo": "Sin aviso: el commit no cambió data/actual.json."}
    assert salida.read_text(encoding="utf-8") == (
        "avisar=false\nurgente=ninguno\nresumen=false\nfuente=ninguna\n")


def clonar_poco_profundo(repo, destino, profundidad):
    subprocess.run(["git", "clone", "-q", "--no-local", f"--depth={profundidad}",
                    repo.ruta.as_uri(), str(destino)], check=True, capture_output=True)
    return destino


def test_git_historia_poco_profunda_que_no_alcanza_sale_con_2(repo, tmp_path_factory):
    # Revisión del 17/10: en un clon --depth, git ve el commit del borde como si
    # creara actual.json y nada más atrás; decidir con eso podía perder un urgente.
    repo.commit(pub("atencion", "07:00", prefectura=AYER))
    repo.commit(sin_dato("08:00"))
    repo.commit(sin_dato("08:30"))
    c = repo.commit(pub("alerta", "09:00", prefectura=AYER))
    assert decision_git(repo, c)["urgente"] == "alerta"
    corto = clonar_poco_profundo(repo, tmp_path_factory.mktemp("corto") / "r", 3)
    salida = corto / "out"
    r = correr(["--commit", c], corto, salida)
    assert r.returncode == 2 and "historia" in r.stderr and not salida.exists()
    # Si el recorrido termina antes del borde, decide igual.
    largo = clonar_poco_profundo(repo, tmp_path_factory.mktemp("largo") / "r", 4)
    assert correr(["--commit", c], largo).returncode == 0
    assert json.loads(correr(["--commit", c], largo).stdout)["urgente"] == "alerta"
    # Con el nivel nuevo normal no se mira atrás: el borde no molesta.
    n = repo.commit(pub("normal", "09:30", prefectura=AYER))
    borde = clonar_poco_profundo(repo, tmp_path_factory.mktemp("borde") / "r", 2)
    r = correr(["--commit", n], borde)
    assert r.returncode == 0 and json.loads(r.stdout)["avisar"] is False


def test_git_historia_mas_larga_que_el_limite(repo, monkeypatch):
    # Más de MAX_HISTORIA versiones sin dato: no se encuentra el anterior, no es urgente.
    repo.commit(pub("normal", "07:00", dia=AYER, prefectura=AYER))
    for minuto in range(4):
        repo.commit(sin_dato(f"08:0{minuto}"))
    c = repo.commit(pub("evacuacion", "09:00", prefectura=AYER))
    assert decision_git(repo, c)["urgente"] == "evacuacion"
    monkeypatch.chdir(repo.ruta)
    monkeypatch.setattr(avisos, "MAX_HISTORIA", 3)
    assert avisos.decidir(avisos._leer_de_commit(c, avisos.RUTA_ACTUAL),
                          avisos._anteriores_de_git(avisos._log_de_actual(c)))["urgente"] is None


def test_git_versiones_rotas_se_saltean(repo):
    repo.commit(pub("atencion", "08:00", prefectura=AYER))
    repo.commit("{roto")
    repo.commit("[1, 2]")
    assert decision_git(repo, repo.commit(pub("alerta", "09:00", prefectura=AYER)))["urgente"] == "alerta"


def test_git_nuevo_sin_actual_json_o_roto_sale_con_2(repo):
    repo.commit(mensaje="sin datos")
    salida = repo.ruta / "out"
    assert correr(["--commit", "HEAD"], repo.ruta, salida).returncode == 2
    repo.commit("{roto")
    assert correr(["--commit", "HEAD"], repo.ruta, salida).returncode == 2
    assert not salida.exists()


@pytest.mark.parametrize("revision", ["-h", "--output=/tmp/x", "-", "HEAD;ls", "HEAD:data/x",
                                      "HEAD@{1}", "HEAD a", "", "no-existe", "HEAD~5"])
def test_git_revision_invalida_sale_con_2(repo, revision):
    repo.commit(pub())
    salida = repo.ruta / "out"
    # Con "=" la revisión llega entera a avisos.py (argparse no la toma como opción).
    r = correr([f"--commit={revision}"], repo.ruta, salida)
    assert r.returncode == 2 and r.stdout == ""
    assert not salida.exists()


def test_revision_que_empieza_con_guion_se_rechaza_sin_llamar_a_git(monkeypatch):
    def no_llamar(*args):
        raise AssertionError("no tenía que correr git")
    monkeypatch.setattr(avisos, "_git", no_llamar)
    for revision in ("-h", "--output=x", "-", "-HEAD", "HEAD;ls", "HEAD:data/x", "", None):
        with pytest.raises(avisos.ErrorAvisos):
            avisos._resolver(revision)
