"""Tests de lector/avisos.py: aviso urgente, resumen del día y la línea de comandos."""
import copy
import json
import os
import shutil
import subprocess
import sys
from datetime import datetime, timedelta
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


def pub(nivel="alerta", hora="12:00", dia=DIA, prefectura=DIA, generado=None, lectura=None, avisos_=None, valor=None):
    """Publicación realista a partir del fixture, cambiando solo lo que importa.

    `hora`/`dia` arman `generado` en UTC-3 (o se pasa `generado` entero).
    `prefectura` es el día de la lectura de Prefectura de las 06:00 (None = sin lectura).
    `lectura` es la fecha de la lectura de altura (por defecto, 5 min antes de `generado`:
    cada publicación trae una lectura nueva); `avisos_` reemplaza la lista de avisos."""
    p = copy.deepcopy(BASE)
    p["nivel"] = nivel
    p["generado"] = generado if generado is not None else f"{dia}T{hora}:00-03:00"
    if lectura is None:
        momento = avisos._hora_local(p["generado"])
        lectura = (momento - timedelta(minutes=5)).isoformat() if momento else p["altura_actual"]["fecha"]
    p["altura_actual"]["fecha"] = lectura
    if valor is not None:
        p["altura_actual"]["valor_m"] = valor
    if avisos_ is not None:
        p["avisos"] = avisos_
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
    # Antes de las 10 y sin Prefectura del día: solo el urgente, a la segunda lectura.
    d = decidir(pub(ahora, "09:00", prefectura=AYER),
                pub(ahora, "08:30", prefectura=AYER), pub(antes, "08:00", prefectura=AYER))
    assert d["urgente"] == ahora and d["avisar"] is True
    assert d["resumen"] is False and d["fuente"] is None


def test_normal_a_evacuacion_se_confirma_con_la_segunda_lectura():
    d = decidir(pub("evacuacion", "09:00", prefectura=AYER),
                pub("evacuacion", "08:30", prefectura=AYER), pub("normal", "08:00", prefectura=AYER))
    assert d == {"avisar": True, "urgente": "evacuacion", "resumen": False, "fuente": None,
                 "motivo": "El nivel subió de normal a evacuación."}


# ---------- M-1: segunda lectura antes del urgente ----------

@pytest.mark.parametrize("antes,ahora", [("atencion", "alerta"), ("normal", "evacuacion"),
                                         ("alerta", "evacuacion")])
def test_primera_lectura_de_la_subida_no_avisa(antes, ahora):
    d = decidir(pub(ahora, "08:30", prefectura=AYER), pub(antes, "08:00", prefectura=AYER))
    assert d["urgente"] is None and d["avisar"] is False
    assert "Urgente en espera" in d["motivo"] and "60 min" in d["motivo"]


def test_segunda_lectura_con_otra_fecha_confirma():
    d = decidir(pub("alerta", "09:00", prefectura=AYER),
                pub("alerta", "08:30", prefectura=AYER), pub("atencion", "08:00", prefectura=AYER))
    assert d["urgente"] == "alerta" and d["avisar"] is True


def test_misma_lectura_repetida_no_confirma():
    # La estación no informó nada nuevo: las dos publicaciones traen la misma lectura.
    lectura = "2026-10-17T08:25:00-03:00"
    d = decidir(pub("alerta", "09:00", prefectura=AYER, lectura=lectura),
                pub("alerta", "08:30", prefectura=AYER, lectura=lectura),
                pub("atencion", "08:00", prefectura=AYER))
    assert d["urgente"] is None and "Urgente en espera" in d["motivo"]


def test_lectura_sin_fecha_valida_no_confirma_y_espera_el_plazo():
    primera = pub("alerta", "08:30", prefectura=AYER)
    segunda = pub("alerta", "09:00", prefectura=AYER)
    segunda["altura_actual"]["fecha"] = "ayer"
    antes = pub("atencion", "08:00", prefectura=AYER)
    assert decidir(segunda, primera, antes)["urgente"] is None
    assert decidir(pub("alerta", "09:30", prefectura=AYER, lectura="roto"),
                   segunda, primera, antes)["urgente"] == "alerta"


def test_el_plazo_de_60_min_publica_igual():
    lectura = "2026-10-17T08:25:00-03:00"
    kw = dict(prefectura=AYER, lectura=lectura)
    antes = pub("atencion", "08:00", prefectura=AYER)
    primera = pub("alerta", "08:30", **kw)
    # 59 min después de la primera: todavía no.
    d = decidir(pub("alerta", "09:29", **kw), pub("alerta", "09:00", **kw), primera, antes)
    assert d["urgente"] is None
    # 60 min: sale, aunque la estación siga con la misma lectura.
    d = decidir(pub("alerta", "09:30", **kw), pub("alerta", "09:00", **kw), primera, antes)
    assert d["urgente"] == "alerta" and d["avisar"] is True and "sale igual" in d["motivo"]


def test_despues_del_plazo_no_se_repite():
    lectura = "2026-10-17T08:25:00-03:00"
    kw = dict(prefectura=AYER, lectura=lectura)
    antes = pub("atencion", "08:00", prefectura=AYER)
    historia = [pub("alerta", "09:30", **kw), pub("alerta", "09:00", **kw),
                pub("alerta", "08:30", **kw), antes]
    d = decidir(pub("alerta", "10:00", **kw), *historia)
    assert d["urgente"] is None


def test_sin_duplicados_tras_la_confirmacion():
    antes = pub("atencion", "08:00", prefectura=AYER)
    historia = [pub("alerta", "08:30", prefectura=AYER), antes]
    salidas = []
    for hora in ("09:00", "09:30", "10:00", "10:30", "11:00", "13:00"):
        nueva = pub("alerta", hora, prefectura=AYER)
        salidas.append(decidir(nueva, *historia)["urgente"])
        historia.insert(0, nueva)
    assert salidas == ["alerta", None, None, None, None, None]


def test_idempotente_sobre_el_mismo_commit():
    historia = [pub("alerta", "08:30", prefectura=AYER), pub("atencion", "08:00", prefectura=AYER)]
    nueva = pub("alerta", "09:00", prefectura=AYER)
    assert decidir(nueva, *historia) == decidir(copy.deepcopy(nueva), *copy.deepcopy(historia))


def test_subida_real_gradual_sale_a_la_segunda_lectura_de_cada_nivel():
    # atención -> alerta -> evacuación: cada nivel avisa una sola vez, a su segunda lectura.
    niveles = ["atencion", "atencion", "alerta", "alerta", "alerta", "evacuacion", "evacuacion", "evacuacion"]
    historia, salidas = [], []
    for i, nivel in enumerate(niveles):
        nueva = pub(nivel, f"{8 + i // 2:02d}:{30 * (i % 2):02d}", prefectura=AYER)
        salidas.append(decidir(nueva, *historia)["urgente"])
        historia.insert(0, nueva)
    assert salidas == [None, None, None, "alerta", None, None, "evacuacion", None]


def test_una_baja_entre_medio_reinicia_la_confirmacion():
    # Un pico falso de una sola lectura que vuelve a bajar nunca avisa.
    historia = [pub("atencion", "08:30", prefectura=AYER), pub("alerta", "08:00", prefectura=AYER),
                pub("atencion", "07:30", prefectura=AYER)]
    assert decidir(pub("atencion", "09:00", prefectura=AYER), *historia)["avisar"] is False
    # Y si vuelve a subir, empieza otra confirmación.
    historia.insert(0, pub("atencion", "09:00", prefectura=AYER))
    d = decidir(pub("alerta", "09:30", prefectura=AYER), *historia)
    assert d["urgente"] is None and "Urgente en espera" in d["motivo"]


def test_sin_dato_en_el_medio_no_corta_la_confirmacion():
    d = decidir(pub("alerta", "09:30", prefectura=AYER), sin_dato("09:00"),
                pub("alerta", "08:30", prefectura=AYER), pub("atencion", "08:00", prefectura=AYER))
    assert d["urgente"] == "alerta"


def test_retencion_del_lector_liberada_ya_viene_confirmada():
    # El lector retuvo el nivel hasta ver una lectura más nueva: no se espera otra vez.
    retenida = pub("atencion", "08:30", prefectura=AYER, avisos_=["dato_a_verificar"])
    retenida["nivel_retenido"] = {"fecha_lectura": "2026-10-17T08:25:00-03:00",
                                  "desde": "2026-10-17T08:30:00-03:00", "nivel": "alerta"}
    liberada = pub("alerta", "09:00", prefectura=AYER, avisos_=["dato_a_verificar"])
    d = decidir(liberada, retenida, pub("atencion", "08:00", prefectura=AYER))
    assert d["urgente"] == "alerta"
    # La siguiente publicación no repite el aviso.
    assert decidir(pub("alerta", "09:30", prefectura=AYER), liberada, retenida)["urgente"] is None


# ---------- dato_a_verificar ----------

def test_salto_brusco_entre_lecturas_no_confirma():
    # Bug: antes salía "subió a EVACUACIÓN" aunque el dato estuviera marcado.
    marcado = ["dato_a_verificar"]
    antes = pub("atencion", "08:00", prefectura=AYER, valor=5.0)
    primera = pub("evacuacion", "08:30", prefectura=AYER, avisos_=marcado, valor=7.5)
    assert decidir(primera, antes)["urgente"] is None
    # Una lectura nueva a más de 1 m de la primera no la confirma (el salto sigue siendo dudoso).
    segunda = pub("evacuacion", "09:00", prefectura=AYER, avisos_=marcado, valor=9.0)
    d = decidir(segunda, primera, antes)
    assert d["urgente"] is None and d["avisar"] is False
    # Una lectura nueva a menos de 1 m de la primera sí confirma.
    tercera = pub("evacuacion", "09:30", prefectura=AYER, valor=7.6)
    assert decidir(tercera, segunda, primera, antes)["urgente"] == "evacuacion"


def test_salto_brusco_persistente_sale_a_los_60_min():
    antes = pub("atencion", "08:00", prefectura=AYER, valor=5.0)
    historia = [pub("alerta", "08:30", prefectura=AYER, valor=6.0), antes]
    salidas = []
    for hora, valor in (("09:00", 8.0), ("09:30", 10.0), ("10:00", 12.0)):
        nueva = pub("alerta", hora, prefectura=AYER, valor=valor)
        salidas.append(decidir(nueva, *historia)["urgente"])
        historia.insert(0, nueva)
    assert salidas == [None, "alerta", None]      # nunca callar: sale a los 60 min


def test_marca_por_pronostico_o_discrepancia_persistente_no_frena_la_confirmacion():
    # Una crecida real más alta que el informe de CARU: dato_a_verificar en cada publicación.
    marcado = ["dato_a_verificar"]
    antes = pub("atencion", "08:00", prefectura=AYER, valor=5.9)
    historia = [pub("alerta", "08:30", prefectura=AYER, avisos_=marcado, valor=6.1), antes]
    salidas = []
    for hora, valor in (("09:00", 6.2), ("09:30", 6.3), ("10:00", 6.4)):
        nueva = pub("alerta", hora, prefectura=AYER, avisos_=marcado, valor=valor)
        salidas.append(decidir(nueva, *historia)["urgente"])
        historia.insert(0, nueva)
    assert salidas == ["alerta", None, None]      # sale a la segunda lectura, no a los 60 min


def test_marca_sin_alturas_comparables_no_confirma():
    marcado = ["dato_a_verificar"]
    primera = pub("alerta", "08:30", prefectura=AYER)
    segunda = pub("alerta", "09:00", prefectura=AYER, avisos_=marcado)
    segunda["altura_actual"]["valor_m"] = None
    assert decidir(segunda, primera, pub("atencion", "08:00", prefectura=AYER))["urgente"] is None


def test_lectura_anterior_o_de_otra_fuente_no_confirma():
    antes = pub("atencion", "08:00", prefectura=AYER)
    primera = pub("alerta", "08:30", prefectura=AYER)
    # Fecha anterior a la primera (la fuente retrocedió).
    vieja = pub("alerta", "09:00", prefectura=AYER, lectura="2026-10-17T08:00:00-03:00")
    assert decidir(vieja, primera, antes)["urgente"] is None
    # Otra fuente (por ejemplo, cambió de estación a Prefectura).
    otra = pub("alerta", "09:00", prefectura=AYER)
    otra["altura_actual"]["fuente"] = "otra fuente"
    assert decidir(otra, primera, antes)["urgente"] is None


def test_alerta_pendiente_seguida_de_evacuacion():
    atencion = pub("atencion", "08:00", prefectura=AYER)
    alerta = pub("alerta", "08:30", prefectura=AYER)
    evac1 = pub("evacuacion", "09:00", prefectura=AYER)
    # La alerta nunca salió y la evacuación es una primera lectura: nada todavía.
    assert decidir(alerta, atencion)["urgente"] is None
    d = decidir(evac1, alerta, atencion)
    assert d["urgente"] is None and "Urgente en espera" in d["motivo"]
    # La segunda lectura de evacuación confirma la evacuación (una sola vez).
    evac2 = pub("evacuacion", "09:30", prefectura=AYER)
    assert decidir(evac2, evac1, alerta, atencion)["urgente"] == "evacuacion"
    assert decidir(pub("evacuacion", "10:00", prefectura=AYER), evac2, evac1, alerta, atencion)["urgente"] is None


def test_retencion_liberada_a_otro_nivel_no_confirma():
    # El lector retuvo una lectura que daba "alerta" y la lectura nueva da "evacuacion":
    # solo hay una lectura alta, hace falta otra.
    retenida = pub("atencion", "08:30", prefectura=AYER, avisos_=["dato_a_verificar"])
    retenida["nivel_retenido"] = {"fecha_lectura": "2026-10-17T08:25:00-03:00",
                                  "desde": "2026-10-17T08:30:00-03:00", "nivel": "alerta"}
    liberada = pub("evacuacion", "09:00", prefectura=AYER, avisos_=["dato_a_verificar"])
    antes = pub("atencion", "08:00", prefectura=AYER)
    assert decidir(liberada, retenida, antes)["urgente"] is None
    # Una retención vieja sin el nivel guardado tampoco confirma.
    del retenida["nivel_retenido"]["nivel"]
    assert decidir(liberada, retenida, antes)["urgente"] is None
    # Con una segunda lectura de evacuación sale.
    siguiente = pub("evacuacion", "09:30", prefectura=AYER)
    assert decidir(siguiente, liberada, retenida, antes)["urgente"] == "evacuacion"


def test_avisos_mal_formados_no_rompen_la_confirmacion():
    for raro in (None, "dato_a_verificar", {"dato_a_verificar": 1}, 5):
        segunda = pub("alerta", "09:00", prefectura=AYER)
        segunda["avisos"] = raro
        d = decidir(segunda, pub("alerta", "08:30", prefectura=AYER), pub("atencion", "08:00", prefectura=AYER))
        assert d["urgente"] == "alerta"


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
    d = decidir(pub("alerta", "09:30", prefectura=AYER), pub("alerta", "09:00", prefectura=AYER),
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
    assert decidir(pub("alerta", "09:30", prefectura=AYER), otro, pub("alerta", "09:00", prefectura=AYER),
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
    assert d["urgente"] is None             # primera lectura de la subida: en espera
    # Sin poder medir el tiempo se prefiere avisar a callar.
    assert decidir(nuevo, pub("alerta", "07:00", prefectura=AYER), pub("atencion", "06:30", prefectura=AYER))["urgente"] == "alerta"
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
    d = decidir(pub("evacuacion", "10:05", prefectura=AYER),
                pub("evacuacion", "09:35", prefectura=AYER), pub("alerta", "09:05", prefectura=AYER))
    assert d == {"avisar": True, "urgente": "evacuacion", "resumen": True, "fuente": "estacion",
                 "motivo": "El nivel subió de alerta a evacuación. Resumen del día con la "
                           "estación automática (no llegó la lectura de Prefectura antes de las 10)."}
    d = decidir(MANANA | {"nivel": "alerta"}, pub("alerta", "07:10", prefectura=AYER, valor=4.1),
                pub("atencion", "06:40", prefectura=AYER))
    assert d["urgente"] == "alerta" and d["fuente"] == "prefectura"
    # La primera lectura de la subida no manda el urgente, pero el resumen sí sale.
    d = decidir(MANANA | {"nivel": "alerta"}, pub("atencion", "07:10", prefectura=AYER))
    assert d["urgente"] is None and d["resumen"] is True and "Urgente en espera" in d["motivo"]


def test_urgente_despues_del_resumen_sale_igual():
    d = decidir(pub("alerta", "15:00"), pub("alerta", "14:30"), pub("atencion", "14:00"), pub("atencion", "07:40"))
    assert d["urgente"] == "alerta" and d["resumen"] is False and d["avisar"] is True


def test_lee_solo_las_anteriores_necesarias():
    def historia():
        yield pub("evacuacion", "10:30", prefectura=AYER)
        yield pub("alerta", "10:00", prefectura=AYER)
        yield pub("normal", "08:00", dia=AYER, prefectura=AYER)
        raise AssertionError("no tenía que seguir leyendo")
    d = avisos.decidir(pub("evacuacion", "11:00", prefectura=AYER), historia())
    assert d["urgente"] == "evacuacion" and d["resumen"] is False


def test_no_lee_la_racha_entera_de_un_nivel_estable():
    leidas = []

    def historia():
        for i in range(500):
            leidas.append(i)
            yield pub("alerta", f"{(23 - i // 2):02d}:{30 * (1 - i % 2):02d}", prefectura=AYER)
    d = avisos.decidir(pub("alerta", "23:59", prefectura=AYER), historia())
    assert d["urgente"] is None
    assert len(leidas) <= 4      # el plazo de 60 min corta la lectura de la historia


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


def test_cli_archivos_resumen_escribe_github_output(tmp_path):
    anterior = escribir(tmp_path / "a.json", pub("alerta", "09:35", prefectura=AYER))
    nuevo = escribir(tmp_path / "n.json", pub("evacuacion", "10:05", prefectura=AYER))
    salida = tmp_path / "github_output"
    salida.write_text("previo=1\n", encoding="utf-8")
    r = correr([str(anterior), str(nuevo)], tmp_path, salida)
    assert r.returncode == 0, r.stderr
    d = json.loads(r.stdout)
    # Con dos archivos no hay historial para la segunda lectura (M-1): el urgente queda en espera.
    assert (d["avisar"], d["urgente"], d["resumen"], d["fuente"]) == (True, None, True, "estacion")
    assert "Urgente en espera" in d["motivo"]
    assert r.stdout.count("\n") == 1
    assert salida.read_text(encoding="utf-8") == (
        "previo=1\navisar=true\nurgente=ninguno\nresumen=true\nfuente=estacion\n")


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
        "avisar=false\nurgente=ninguno\nresumen=false\nfuente=ninguna\n")


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
    primera = repo.commit(pub("alerta", "08:30", prefectura=AYER))
    assert decision_git(repo, primera)["urgente"] is None     # M-1: falta la segunda lectura
    c = repo.commit(pub("alerta", "09:00", prefectura=AYER))
    salida = repo.ruta / "out"
    d = decision_git(repo, c, salida)
    assert d["urgente"] == "alerta" and d["resumen"] is False
    assert salida.read_text(encoding="utf-8") == (
        "avisar=true\nurgente=alerta\nresumen=false\nfuente=ninguna\n")
    # También acepta revisiones relativas, y volver a correr el mismo commit da lo mismo.
    assert decision_git(repo, "HEAD~1")["avisar"] is False
    assert decision_git(repo, c) == d
    # Las publicaciones siguientes no repiten el aviso.
    assert decision_git(repo, repo.commit(pub("alerta", "09:30", prefectura=AYER)))["avisar"] is False


def test_git_busca_hacia_atras_saltando_sin_dato(repo):
    repo.commit(pub("normal", "07:00", prefectura=AYER), "normal")
    repo.commit(pub("atencion", "07:30", prefectura=AYER), "atencion")
    repo.commit(sin_dato("08:00"), "caída")
    repo.commit(mensaje="commit que no toca actual.json")
    repo.commit(sin_dato("08:30"), "sigue la caída")
    repo.commit(pub("alerta", "09:00", prefectura=AYER), "vuelve")
    vuelta = repo.commit(pub("alerta", "09:30", prefectura=AYER), "segunda lectura")
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
        (pub("evacuacion", "15:00", prefectura=DIA), (None, None)),   # M-1: primera lectura
        (pub("evacuacion", "15:30", prefectura=DIA), ("evacuacion", None)),
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
    repo.commit(pub("alerta", "10:05", prefectura=AYER))
    c = repo.commit(pub("alerta", "10:35", prefectura=AYER))
    d = decision_git(repo, c)
    assert d["urgente"] == "alerta" and d["resumen"] is False
    otro = repo.commit(mensaje="solo historial.json")
    salida = repo.ruta / "out"
    assert decision_git(repo, otro, salida) == {
        "avisar": False, "urgente": None, "resumen": False, "fuente": None,
        "motivo": "Sin aviso: el commit no cambió data/actual.json."}
    assert salida.read_text(encoding="utf-8") == (
        "avisar=false\nurgente=ninguno\nresumen=false\nfuente=ninguna\n")


def test_git_desde_un_subdirectorio(repo):
    repo.commit(pub("atencion", "08:00", prefectura=AYER))
    repo.commit(pub("alerta", "08:30", prefectura=AYER))
    c = repo.commit(pub("alerta", "09:00", prefectura=AYER))
    r = correr(["--commit", c], repo.ruta / "data")
    assert r.returncode == 0 and json.loads(r.stdout)["urgente"] == "alerta"


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
    repo.commit(pub("alerta", "09:00", prefectura=AYER))
    c = repo.commit(pub("alerta", "09:30", prefectura=AYER))
    assert decision_git(repo, c)["urgente"] == "alerta"
    corto = clonar_poco_profundo(repo, tmp_path_factory.mktemp("corto") / "r", 4)
    salida = corto / "out"
    r = correr(["--commit", c], corto, salida)
    assert r.returncode == 2 and "historia" in r.stderr and not salida.exists()
    # Si el recorrido termina antes del borde, decide igual.
    largo = clonar_poco_profundo(repo, tmp_path_factory.mktemp("largo") / "r", 5)
    assert correr(["--commit", c], largo).returncode == 0
    assert json.loads(correr(["--commit", c], largo).stdout)["urgente"] == "alerta"
    # El commit es el borde: no se sabe si cambió actual.json ni qué hubo antes.
    solo = clonar_poco_profundo(repo, tmp_path_factory.mktemp("solo") / "r", 1)
    r = correr(["--commit", c], solo)
    assert r.returncode == 2 and "borde" in r.stderr
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
    repo.commit(pub("evacuacion", "09:00", prefectura=AYER))
    c = repo.commit(pub("evacuacion", "09:30", prefectura=AYER))
    assert decision_git(repo, c)["urgente"] == "evacuacion"
    monkeypatch.chdir(repo.ruta)
    monkeypatch.setattr(avisos, "MAX_HISTORIA", 3)
    assert avisos.decidir(avisos._leer_de_commit(c, avisos.RUTA_ACTUAL),
                          avisos._anteriores_de_git(avisos._log_de_actual(c)))["urgente"] is None


def test_git_versiones_rotas_se_saltean(repo):
    repo.commit(pub("atencion", "08:00", prefectura=AYER))
    repo.commit("{roto")
    repo.commit("[1, 2]")
    repo.commit(pub("alerta", "09:00", prefectura=AYER))
    assert decision_git(repo, repo.commit(pub("alerta", "09:30", prefectura=AYER)))["urgente"] == "alerta"


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


# ---------- niveles mezclados: alerta -> evacuación -> alerta ----------

def secuencia(*publicaciones):
    """Urgente que sale en cada publicación (de la más vieja a la más nueva),
    decidiendo con el historial anterior. Además comprueba que re-correr cada
    commit da la misma decisión."""
    historia, salidas = [], []
    for p in publicaciones:
        d = decidir(p, *historia)
        assert d == decidir(copy.deepcopy(p), *copy.deepcopy(historia))
        salidas.append(d["urgente"])
        historia.insert(0, p)
    return salidas


def test_alerta_en_espera_evacuacion_y_vuelve_a_alerta_avisa_la_alerta():
    # Hueco de la 2.ª revisión: antes no salía ni la alerta ni la evacuación.
    salidas = secuencia(
        pub("atencion", "08:00", prefectura=AYER, valor=5.0),
        pub("alerta", "08:30", prefectura=AYER, valor=6.0),
        pub("evacuacion", "09:00", prefectura=AYER, valor=7.0),
        pub("alerta", "09:30", prefectura=AYER, valor=6.1),
        pub("alerta", "10:00", prefectura=AYER, valor=6.2),
        pub("alerta", "10:30", prefectura=AYER, valor=6.3))
    assert salidas == [None, None, None, "alerta", None, None]      # una alerta, sin repetir


def test_alerta_en_espera_y_evacuacion_confirmada_no_manda_alerta_redundante():
    salidas = secuencia(
        pub("atencion", "08:00", prefectura=AYER, valor=5.0),
        pub("alerta", "08:30", prefectura=AYER, valor=6.0),
        pub("evacuacion", "09:00", prefectura=AYER, valor=7.0),
        pub("evacuacion", "09:30", prefectura=AYER, valor=7.1),
        # Baja a alerta después de avisada la evacuación: es una bajada, no avisa.
        pub("alerta", "10:00", prefectura=AYER, valor=6.1),
        pub("alerta", "10:30", prefectura=AYER, valor=6.2),
        pub("alerta", "11:00", prefectura=AYER, valor=6.3))
    assert salidas == [None, None, None, "evacuacion", None, None, None]


def test_alerta_confirmada_y_despues_evacuacion_avisan_las_dos_una_vez():
    salidas = secuencia(
        pub("atencion", "08:00", prefectura=AYER, valor=5.0),
        pub("alerta", "08:30", prefectura=AYER, valor=6.0),
        pub("alerta", "09:00", prefectura=AYER, valor=6.1),
        pub("evacuacion", "09:30", prefectura=AYER, valor=7.0),
        pub("evacuacion", "10:00", prefectura=AYER, valor=7.1),
        pub("alerta", "10:30", prefectura=AYER, valor=6.2),
        pub("alerta", "11:00", prefectura=AYER, valor=6.3))
    assert salidas == [None, None, "alerta", None, "evacuacion", None, None]


def test_evacuacion_sin_confirmar_y_alerta_sostenida_sale_igual_por_plazo():
    # La evacuación tiene un salto dudoso y nunca se confirma; la alerta sostenida no puede quedar muda.
    salidas = secuencia(
        pub("atencion", "08:00", prefectura=AYER, valor=5.0),
        pub("alerta", "08:30", prefectura=AYER, valor=6.0),
        pub("evacuacion", "09:00", prefectura=AYER, valor=9.0),
        pub("alerta", "09:30", prefectura=AYER, valor=6.1),
        pub("alerta", "10:00", prefectura=AYER, valor=6.2))
    assert salidas == [None, None, None, "alerta", None]


def test_git_alerta_evacuacion_alerta_una_sola_alerta(repo):
    secuencia_pub = [
        pub("atencion", "08:00", prefectura=AYER, valor=5.0),
        pub("alerta", "08:30", prefectura=AYER, valor=6.0),
        pub("evacuacion", "09:00", prefectura=AYER, valor=7.0),
        pub("alerta", "09:30", prefectura=AYER, valor=6.1),
        pub("alerta", "10:00", prefectura=AYER, valor=6.2)]
    commits = [repo.commit(p, p["generado"]) for p in secuencia_pub]
    salidas = [decision_git(repo, c)["urgente"] for c in commits]
    assert salidas == [None, None, None, "alerta", None]
    assert [decision_git(repo, c)["urgente"] for c in commits] == salidas       # re-correr da lo mismo


# ---------- huecos de publicación y propiedades ----------

def hm(minutos):
    return f"{minutos // 60:02d}:{minutos % 60:02d}"


@pytest.mark.parametrize("hueco", [59, 60, 119, 120, 121, 130, 600])
@pytest.mark.parametrize("nivel", ["alerta", "evacuacion"])
def test_hueco_de_publicaciones_sale_por_plazo(nivel, hueco):
    # El lector estuvo parado y vuelve: la primera publicación posterior (60 min o más
    # después de la primera) saca el urgente por plazo, aunque la estación siga con la misma lectura.
    kw = dict(prefectura=AYER, lectura="2026-10-17T00:05:00-03:00")
    salidas = secuencia(pub("atencion", hm(0), **kw),
                        pub(nivel, hm(10), **kw),
                        pub(nivel, hm(10 + hueco), **kw))
    assert salidas == [None, None, nivel if hueco >= 60 else None]


@pytest.mark.parametrize("hueco", [119, 120, 121, 130])
def test_hueco_con_niveles_mezclados(hueco):
    kw = dict(prefectura=AYER, lectura="2026-10-17T00:05:00-03:00")
    # Evacuación que se confirma por plazo tras el hueco; volver a alerta es una bajada.
    salidas = secuencia(pub("atencion", hm(0), **kw),
                        pub("alerta", hm(10), **kw),
                        pub("evacuacion", hm(20), **kw),
                        pub("evacuacion", hm(20 + hueco), **kw),
                        pub("alerta", hm(30 + hueco), **kw))
    assert salidas == [None, None, None, "evacuacion", None]
    # Si la evacuación tiene una sola publicación, la alerta sostenida sale por plazo tras el hueco.
    salidas = secuencia(pub("atencion", hm(0), **kw),
                        pub("alerta", hm(10), **kw),
                        pub("evacuacion", hm(20), **kw),
                        pub("alerta", hm(20 + hueco), **kw))
    assert salidas == [None, None, None, "alerta"]


def _secuencia_aleatoria(azar):
    niveles = ["atencion"]
    for _ in range(azar.randint(8, 30)):
        niveles.append(niveles[-1] if azar.random() < 0.8
                       else azar.choice(["atencion", "alerta", "evacuacion"]))
    altura = {"atencion": 5.0, "alerta": 5.8, "evacuacion": 6.6}
    publicaciones = []
    for i, nivel in enumerate(niveles):
        minutos = 10 * i
        bloque = minutos // 30      # la estación informa cada 30 min y el lector corre cada 10
        lectura = f"{DIA}T{hm(30 * bloque)}:00-03:00"
        publicaciones.append(pub(nivel, hm(minutos), prefectura=AYER, valor=altura[nivel] + 0.01 * bloque,
                                 lectura=lectura))
    return niveles, publicaciones


def test_propiedades_con_secuencias_aleatorias():
    import random
    azar = random.Random(20261103)
    urgentes = ("alerta", "evacuacion")
    for _ in range(300):
        niveles, publicaciones = _secuencia_aleatoria(azar)
        historia, salidas = [], []
        for p in publicaciones:
            salidas.append(avisos.decidir(p, historia)["urgente"])
            historia.insert(0, p)
        # 1) Nunca callar: una racha continua en alerta o más de 80 min o más avisa algo.
        i = 0
        while i < len(niveles):
            if niveles[i] in urgentes and niveles[i - 1] not in urgentes:
                j = i
                while j + 1 < len(niveles) and niveles[j + 1] in urgentes:
                    j += 1
                if (j - i) * 10 >= 80:
                    assert any(salidas[i:j + 1]), (niveles, salidas)
                i = j + 1
            else:
                i += 1
        # 2) Ningún nivel avisa dos veces dentro de la misma subida continua (racha de ese nivel o más).
        for nivel in urgentes:
            racha = 0
            for k, n in enumerate(niveles):
                if n in urgentes and (nivel == "alerta" or n == "evacuacion"):
                    racha += salidas[k] == nivel
                else:
                    racha = 0
                assert racha <= 1, (nivel, niveles, salidas)
        # 3) Solo avisa un nivel que tiene la publicación.
        assert all(s is None or s == n for s, n in zip(salidas, niveles))


def test_propiedades_con_saltos_de_tiempo_aleatorios():
    """Como la anterior pero con huecos de publicación (el lector parado) y los
    cuatro niveles. Detecta, por ejemplo, un corte de historia que descarte la
    publicación nueva tras un hueco."""
    import random
    azar = random.Random(7)
    base = datetime(2026, 10, 17, tzinfo=avisos.ZONA_LOCAL)
    altura = {"normal": 4.0, "atencion": 5.0, "alerta": 5.9, "evacuacion": 6.8}
    urgentes = ("alerta", "evacuacion")
    for _ in range(400):
        niveles, tiempos = ["atencion"], [0]
        for _ in range(azar.randint(8, 30)):
            niveles.append(niveles[-1] if azar.random() < 0.75
                           else azar.choice(["normal", "atencion", "alerta", "evacuacion"]))
            tiempos.append(tiempos[-1] + azar.choice([10, 10, 10, 10, 20, 30, 70, 130, 200]))
        publicaciones = []
        for nivel, t in zip(niveles, tiempos):
            publicaciones.append(pub(
                nivel, prefectura=AYER, valor=altura[nivel] + 0.01 * (t // 30),
                generado=(base + timedelta(minutes=t)).isoformat(),
                lectura=(base + timedelta(minutes=30 * (t // 30))).isoformat()))
        historia, salidas = [], []
        for p in publicaciones:
            d = avisos.decidir(p, iter(historia))
            # (c) re-correr con una copia da lo mismo
            assert d == avisos.decidir(copy.deepcopy(p), iter(copy.deepcopy(historia)))
            salidas.append(d["urgente"])
            historia.insert(0, p)
        # (a) toda subida continua de 60 min o más avisa algo: con huecos de hasta 69 min en cualquier
        # mezcla de niveles, y con cualquier hueco si la racha es de un solo nivel.
        i = 0
        while i < len(niveles):
            if niveles[i] in urgentes and niveles[i - 1] not in urgentes:
                j = i
                while j + 1 < len(niveles) and niveles[j + 1] in urgentes:
                    j += 1
                huecos = [tiempos[k + 1] - tiempos[k] for k in range(i, j)] or [0]
                if tiempos[j] - tiempos[i] >= 60 and (max(huecos) <= 69 or len(set(niveles[i:j + 1])) == 1):
                    assert any(salidas[i:j + 1]), (list(zip(niveles, tiempos)), salidas)
                i = j + 1
            else:
                i += 1
        # (b) ningún nivel avisa dos veces dentro de la misma subida continua
        for nivel in urgentes:
            cuenta = 0
            for k, n in enumerate(niveles):
                if n in urgentes and (nivel == "alerta" or n == "evacuacion"):
                    cuenta += salidas[k] == nivel
                else:
                    cuenta = 0
                assert cuenta <= 1, (nivel, list(zip(niveles, tiempos)), salidas)


# ---------- silencios del servidor (revisión de M-1) ----------

def pm(minutos, nivel, valor, lectura_min=None, fuente=None, retenido=None, reloj=None):
    """Publicación a `minutos` desde las 00:00 del 17/10, con la lectura de altura
    a `lectura_min` (por defecto 5 min antes), `fuente` (None = la del fixture) y,
    si se pasa, la retención del lector con el nivel `retenido`. `reloj` pisa los
    minutos de `generado` (un reloj corrido) o, si es texto, lo deja inválido."""
    base = datetime(2026, 10, 17, tzinfo=avisos.ZONA_LOCAL)
    lectura_min = minutos - 5 if lectura_min is None else lectura_min
    reloj = minutos if reloj is None else reloj
    p = pub(nivel, prefectura=AYER, valor=valor,
            generado=reloj if isinstance(reloj, str) else (base + timedelta(minutes=reloj)).isoformat(),
            lectura=(base + timedelta(minutes=lectura_min)).isoformat())
    if fuente is not None:
        p["altura_actual"]["fuente"] = fuente
    if retenido is not None:
        p["nivel_retenido"] = {"nivel": retenido}
    return p


def test_retencion_de_alerta_soltada_en_evacuacion_y_vuelve_a_alerta_avisa_la_alerta():
    # Bug: la retención confirmaba la alerta solo en la primera publicación de la
    # subida, que era la de evacuación (de otro nivel, no avisa). La alerta quedaba
    # muda aunque el río siguiera horas en alerta.
    salidas = secuencia(
        pm(8 * 60, "atencion", 5.5),
        pm(8 * 60 + 30, "atencion", 5.6, retenido="alerta"),
        pm(9 * 60, "evacuacion", 6.7),
        pm(9 * 60 + 30, "alerta", 6.0),
        pm(10 * 60, "alerta", 6.05),
        pm(10 * 60 + 30, "alerta", 6.1),
        pm(11 * 60 + 40, "alerta", 6.1),
        *[pm(12 * 60 + 10 * i, "alerta", 6.1 + 0.01 * i) for i in range(72)])
    assert salidas[:4] == [None, None, None, "alerta"]
    assert salidas.count("alerta") == 1 and "evacuacion" not in salidas


def test_retencion_de_alerta_soltada_en_alerta_sigue_saliendo_de_una():
    # La retención del mismo nivel sigue confirmando en la primera publicación,
    # aunque después suba a evacuación y vuelva.
    salidas = secuencia(
        pm(0, "atencion", 5.5, retenido="alerta"),
        pm(10, "alerta", 5.9),
        pm(20, "evacuacion", 6.8),
        pm(30, "alerta", 6.0),
        pm(40, "alerta", 6.0))
    assert salidas == [None, "alerta", None, None, None]


def test_evacuacion_de_una_lectura_tras_un_hueco_y_alerta_sostenida_avisa_la_alerta():
    # Bug: tras un hueco de más de 2 h, la búsqueda hacia atrás cortaba suponiendo que
    # la evacuación ya había avisado; tenía una sola lectura y nunca salió, y la alerta
    # quedaba muda horas.
    salidas = secuencia(
        pm(0, "atencion", 5.0, 0),
        pm(60, "alerta", 5.92, 60),
        pm(70, "alerta", 5.92, 60),
        pm(270, "evacuacion", 6.89, 270),
        pm(280, "alerta", 5.99, 270),
        pm(300, "alerta", 6.0, 300),
        pm(330, "alerta", 6.0, 330),
        *[pm(400 + 10 * i, "alerta", 6.0, 390 + 10 * i) for i in range(100)])
    assert salidas[:5] == [None, None, None, None, "alerta"]
    assert salidas.count("alerta") == 1 and "evacuacion" not in salidas


def test_evacuacion_sostenida_tras_un_hueco_y_bajada_a_alerta_no_avisa_la_alerta():
    # Lo que cuidaba el corte viejo: la evacuación sí avisó (por plazo), así que
    # volver a alerta es una bajada.
    salidas = secuencia(
        pm(0, "atencion", 5.0),
        pm(60, "alerta", 5.92, 60),
        pm(270, "evacuacion", 6.89, 270),
        pm(280, "evacuacion", 6.89, 270),
        pm(340, "evacuacion", 6.9, 270),
        pm(350, "alerta", 6.0),
        pm(360, "alerta", 6.0))
    assert salidas == [None, None, None, None, "evacuacion", None, None]


@pytest.mark.parametrize("hueco", [0, 200])
def test_fuentes_alternadas_salen_por_el_tope(hueco):
    # Una fuente repite su lectura vieja y la otra trae lecturas nuevas: ninguna
    # confirma a la primera (otra fuente o misma fecha), pero el tope saca el urgente.
    a, b = "CARU – estación automática Paysandú", "Prefectura"
    salidas = secuencia(
        pm(0, "atencion", 5.5, fuente=a),
        pm(10, "alerta", 5.9, 5, fuente=a),
        pm(30 + hueco, "alerta", 5.92, fuente=b),
        pm(50 + hueco, "alerta", 5.9, 5, fuente=a),
        pm(70 + hueco, "alerta", 5.93, fuente=b),
        pm(90 + hueco, "alerta", 5.9, 5, fuente=a),
        pm(110 + hueco, "alerta", 5.94, fuente=b))
    tope = 2 if hueco else 4        # la primera publicación a 60 min o más de la primera
    esperado = [None] * 7
    esperado[tope] = "alerta"
    assert salidas == esperado


def test_salto_de_mas_de_1_m_persistente_tras_huecos_sale_por_el_tope():
    salidas = secuencia(
        pm(0, "atencion", 5.5),
        pm(10, "alerta", 5.9),
        pm(100, "alerta", 7.1),
        pm(190, "alerta", 5.9),
        pm(280, "alerta", 7.1))
    assert salidas == [None, None, "alerta", None, None]


def test_no_lee_la_racha_entera_de_evacuacion_al_bajar_a_alerta():
    # Sin el corte por "más de 2 h" la búsqueda sigue cortando: una evacuación sostenida
    # 60 min o más ya avisó, así que la alerta que sigue es una bajada.
    leidas = []

    def historia():
        for i in range(500):
            leidas.append(i)
            yield pm(23 * 60 + 30 - 30 * i, "evacuacion", 6.9)
    d = avisos.decidir(pm(23 * 60 + 59, "alerta", 6.0), historia())
    assert d["urgente"] is None
    assert len(leidas) <= 4


def test_generado_desordenado_no_hace_que_el_corte_calle_la_alerta():
    # Un revert o un commit a mano deja una publicación con el reloj 26 min adelantado.
    # El corte de la historia medía contra esa publicación y la alerta sostenida no
    # salía nunca; leyendo toda la historia sí sale. El plazo se mide desde el
    # `generado` más temprano de la racha, y cortar vuelve a dar lo mismo.
    salidas = secuencia(
        pm(0, "atencion", 5.5),
        pm(60, "evacuacion", 6.9, 55, reloj=86),
        pm(65, "evacuacion", 6.9, 55, reloj=60),
        pm(126, "evacuacion", 6.9, 55),             # misma lectura: no confirma
        *[pm(150 + 30 * i, "alerta", 6.0, 55) for i in range(12)])
    assert salidas[:4] == [None, None, None, "evacuacion"]
    assert salidas[4:] == [None] * 12               # bajada tras la evacuación avisada


def test_propiedad_ningun_nivel_sostenido_queda_mudo(monkeypatch):
    """Secuencias que mezclan fuentes, saltos de más de 1 m, lecturas repetidas,
    huecos, retenciones y sin_dato. (a) Si dos publicaciones DE NIVEL L (alerta o
    evacuación) de la misma racha continua con L o más quedan a 60 min o más, sale
    un urgente de L o más en esa racha hasta la segunda: nunca callar. (b) Cortar la
    lectura de la historia (_racha_vencida) nunca cambia la decisión, también con
    `generado` corrido (que no crece) o inválido."""
    import random
    azar = random.Random(20261104)
    rango = {"normal": 0, "atencion": 1, "alerta": 2, "evacuacion": 3}
    altura = {"normal": 4.0, "atencion": 5.0, "alerta": 5.9, "evacuacion": 6.8, "sin_dato": 5.0}
    fuentes = ["CARU – estación automática Paysandú", "Prefectura"]
    corte = avisos._racha_vencida

    def decidir_todo(publicaciones, cortar):
        monkeypatch.setattr(avisos, "_racha_vencida", corte if cortar else (lambda *_: False))
        historia, salidas = [], []
        for p in publicaciones:
            salidas.append(avisos.decidir(p, iter(historia))["urgente"])
            historia.insert(0, p)
        return salidas

    for _ in range(250):
        filas, t, lectura, fuente = [], 0, -5, 0
        nivel = azar.choice(["normal", "atencion"])
        for k in range(azar.randint(6, 30)):
            if k:
                if azar.random() > 0.65:
                    nivel = azar.choice(["sin_dato", "normal", "atencion", "alerta", "evacuacion"])
                t += azar.choice([10, 10, 10, 20, 30, 59, 60, 70, 119, 121, 200, 400])
            if azar.random() < 0.6:
                lectura = t - 5
            if azar.random() < 0.15:
                fuente = 1 - fuente
            salto = azar.choice([1.5, -1.5, 1.01]) if azar.random() < 0.15 else 0
            retenido = (azar.choice(["alerta", "evacuacion"])
                        if nivel in ("normal", "atencion") and azar.random() < 0.15 else None)
            filas.append((t, nivel, round(altura[nivel] + salto + 0.01 * (t // 30), 2), lectura,
                          fuentes[fuente], retenido))
        publicaciones = [pm(*f) for f in filas]
        salidas = decidir_todo(publicaciones, cortar=True)
        assert salidas == decidir_todo(publicaciones, cortar=False), filas       # (b)
        # (b) con el reloj sucio: corrido hasta 40 min para cualquier lado, o roto.
        relojes = [f[0] + azar.choice([-40, -26, -10, 10, 26, 40]) if azar.random() < 0.2
                   else ("roto" if azar.random() < 0.03 else f[0]) for f in filas]
        sucias = [pm(*f, reloj=r) for f, r in zip(filas, relojes)]
        assert decidir_todo(sucias, cortar=True) == decidir_todo(sucias, cortar=False), (filas, relojes)
        con_dato = [k for k, f in enumerate(filas) if f[1] in rango]
        for L in (2, 3):
            for a, k in enumerate(con_dato):
                if a == 0 or rango[filas[k][1]] < L or rango[filas[con_dato[a - 1]][1]] >= L:
                    continue        # no empieza una racha con L o más
                racha = [k]
                for k2 in con_dato[a + 1:]:
                    if rango[filas[k2][1]] < L:
                        break
                    racha.append(k2)
                de_l = [k2 for k2 in racha if rango[filas[k2][1]] == L]
                segunda = next((k2 for k2 in de_l if filas[k2][0] - filas[de_l[0]][0] >= 60), None)
                if segunda is not None:                                          # (a)
                    assert any(salidas[k2] and rango[salidas[k2]] >= L
                               for k2 in racha if k2 <= segunda), (filas, salidas)
