"""Margen al bajar de nivel (`margen_bajada_m`). Principio: con el río justo en un
umbral, el nivel no tiene que ir y venir en cada pasada (cada ida y vuelta es un
aviso "subió" y otro "bajó"). Para bajar hay que quedar 5 cm abajo del umbral;
para subir alcanza con tocarlo, como siempre."""
import json
import math
from datetime import datetime, timedelta
from pathlib import Path

import pytest

import lector
import red
from fuentes.caru_registro import TZ_UY
from nivel import nivel_con_margen

CFG = json.loads((Path(lector.__file__).parent / "config.json").read_text(encoding="utf-8"))
MARGEN = CFG["margen_bajada_m"]
UMBRALES = {"atencion_m": 3.80, "alerta_m": 4.39, "evacuacion_m": 6.89}
SIN_ATENCION = {"atencion_m": None, "alerta_m": 4.39, "evacuacion_m": 6.89}
T0 = datetime(2026, 10, 9, 7, 0, tzinfo=TZ_UY)
URL_EST = "http://190.0.152.194:8080/alturas/web/user/estacion/19/0"
URL_PRE = "http://190.0.152.194:8080/alturas/web/user/altura/24"


def lectura(valor, fecha, anterior_m, fecha_anterior, url, periodo):
    return {"valor_m": valor, "fecha": fecha, "variacion_m": round(valor - anterior_m, 2),
            "periodo": periodo, "estado": "estacionario", "anterior_m": anterior_m,
            "fecha_anterior": fecha_anterior, "url": url}


def registro(valor, fecha, anterior_m=None):
    """Estación con `valor` en `fecha`; Prefectura de hace 2 h con el mismo valor
    (sin discrepancia). Sin `anterior_m`, la lectura anterior es igual: sin salto."""
    anterior_m = valor if anterior_m is None else anterior_m
    pre = fecha - timedelta(hours=2)
    return {
        "cero": "Local",
        "estacion": lectura(valor, fecha, anterior_m, fecha - timedelta(minutes=30), URL_EST, "30 min"),
        "prefectura": lectura(valor, pre, valor, pre - timedelta(days=1), URL_PRE, "24 hs"),
    }


def pasada(reg, anterior, ahora, umbrales=UMBRALES):
    return lector.armar_actual(reg, {"vigente": False}, umbrales, anterior, ahora, CFG)


def serie(valores, umbrales=UMBRALES, anterior=None):
    """Una lectura nueva cada 30 min, encadenando cada actual.json con el siguiente.
    Devuelve los niveles publicados y el último actual.json."""
    niveles = []
    previo = None
    for i, valor in enumerate(valores):
        t = T0 + timedelta(minutes=30 * i)
        anterior = pasada(registro(valor, t, previo), anterior, t, umbrales)
        assert "nivel_retenido" not in anterior
        niveles.append(anterior["nivel"])
        previo = valor
    return niveles, anterior


def test_config_trae_margen_de_5_cm():
    assert MARGEN == 0.05


def test_oscilacion_sobre_el_umbral_no_cambia_el_nivel():
    niveles, _ = serie([4.40, 4.37, 4.41, 4.36, 4.40, 4.37])
    assert niveles == ["alerta"] * 6


def test_bajada_real_baja_y_el_borde_exacto_de_5_cm_cuenta():
    # 4,35 está a 4 cm de la alerta (4,39): sigue en alerta. 4,34 está a 5 cm justos
    # (se compara en milímetros): baja a atención.
    niveles, _ = serie([4.40, 4.35, 4.34, 4.30])
    assert niveles == ["alerta", "alerta", "atencion", "atencion"]
    assert nivel_con_margen(4.34, UMBRALES, "alerta", 0.05) == "atencion"
    assert nivel_con_margen(4.35, UMBRALES, "alerta", 0.05) == "alerta"
    assert nivel_con_margen(6.84, UMBRALES, "evacuacion", 0.05) == "alerta"
    assert nivel_con_margen(6.85, UMBRALES, "evacuacion", 0.05) == "evacuacion"
    # En flotante 2,01 + 0,05 da 2,0599999...: sin pasar a milímetros, 5 cm justos
    # no alcanzarían para bajar.
    assert 2.01 + 0.05 < 2.06
    bajos = {"atencion_m": 2.06, "alerta_m": 4.39, "evacuacion_m": 6.89}
    assert nivel_con_margen(2.01, bajos, "atencion", 0.05) == "normal"
    assert nivel_con_margen(2.02, bajos, "atencion", 0.05) == "atencion"


def test_subida_sin_margen_aun_despues_de_una_bajada():
    # Recién bajó a atención (4,34); al tocar otra vez la alerta (4,39) sube enseguida.
    niveles, _ = serie([4.40, 4.34, 4.39, 4.38])
    assert niveles == ["alerta", "atencion", "alerta", "alerta"]
    assert nivel_con_margen(6.89, UMBRALES, "normal", 0.05) == "evacuacion"


def test_bajada_de_varios_niveles_limitada_por_el_margen():
    # Desde evacuación: 3 cm bajo la alerta queda en alerta; 3 cm bajo la atención
    # queda en atención; bien abajo de todo, normal de una.
    assert nivel_con_margen(4.36, UMBRALES, "evacuacion", MARGEN) == "alerta"
    assert nivel_con_margen(3.77, UMBRALES, "evacuacion", MARGEN) == "atencion"
    assert nivel_con_margen(3.75, UMBRALES, "evacuacion", MARGEN) == "normal"
    assert nivel_con_margen(4.30, UMBRALES, "evacuacion", MARGEN) == "atencion"
    # Por armar_actual (sin salto: el anterior publicado no trae altura).
    anterior = {"nivel": "evacuacion", "avisos": []}
    assert pasada(registro(4.36, T0), anterior, T0)["nivel"] == "alerta"
    a = pasada(registro(3.77, T0), anterior, T0)
    assert a["nivel"] == "atencion" and "nivel_retenido" not in a


def test_sin_umbral_de_atencion_el_margen_va_contra_la_alerta():
    niveles, _ = serie([4.40, 4.36, 4.35, 4.34, 4.38], umbrales=SIN_ATENCION)
    assert niveles == ["alerta", "alerta", "alerta", "normal", "normal"]
    # Si antes estaba en atención y después se sacó ese umbral, no se queda en un
    # nivel que ya no existe.
    assert nivel_con_margen(4.37, SIN_ATENCION, "atencion", MARGEN) == "normal"


def test_umbrales_invalidos_siguen_en_sin_dato():
    malos = {"atencion_m": None, "alerta_m": 4.39, "evacuacion_m": 4.0}
    a = pasada(registro(4.36, T0), {"nivel": "alerta", "avisos": []}, T0, malos)
    assert a["nivel"] == "sin_dato" and a["avisos"] == ["umbrales_invalidos"]
    assert "nivel_retenido" not in a


def test_primer_arranque_y_anterior_sin_dato_van_sin_margen():
    for anterior in (None, {}, {"nivel": "sin_dato", "avisos": []}, {"nivel": "otro", "avisos": []}):
        assert pasada(registro(4.37, T0), anterior, T0, SIN_ATENCION)["nivel"] == "normal"
        assert pasada(registro(4.37, T0), anterior, T0)["nivel"] == "atencion"
    assert nivel_con_margen(4.37, SIN_ATENCION, None, MARGEN) == "normal"
    assert nivel_con_margen(None, SIN_ATENCION, "alerta", MARGEN) == "sin_dato"


def test_margen_cero_lo_desactiva():
    assert nivel_con_margen(4.38, UMBRALES, "alerta", 0) == "atencion"
    cfg = dict(CFG, margen_bajada_m=0)
    a = lector.armar_actual(registro(4.38, T0), {"vigente": False}, UMBRALES,
                            {"nivel": "alerta", "avisos": []}, T0, cfg)
    assert a["nivel"] == "atencion"


def test_salto_falso_que_vuelve_dentro_del_margen_no_cambia_nivel_ni_retiene():
    # Alerta con 4,40; la estación marca 3,30 (baja 1,1 m: dudosa) y la siguiente
    # vuelve a 4,36, dentro del margen. Nunca deja de ser alerta en lo publicado.
    t1, t2 = T0 + timedelta(minutes=30), T0 + timedelta(minutes=60)
    anterior = pasada(registro(4.40, T0), None, T0)
    a = pasada(registro(3.30, t1, 4.40), anterior, t1)
    assert a["nivel"] == "alerta" and "dato_a_verificar" in a["avisos"]
    assert "nivel_retenido" in a  # el margen se aplica contra el nivel retenido
    b = pasada(registro(4.36, t2, 3.30), a, t2)
    assert b["nivel"] == "alerta"
    assert "nivel_retenido" not in b


def test_salto_que_cae_dentro_del_margen_no_crea_retencion():
    # La retención compara el nivel YA con margen: una caída brusca de 5,50 a 4,36
    # (sin margen sería atención) queda en alerta, igual que antes, y no retiene.
    anterior = {"nivel": "alerta", "avisos": [],
                "altura_actual": {"valor_m": 5.50, "fecha": (T0 - timedelta(minutes=30)).isoformat()}}
    a = pasada(registro(4.36, T0, 5.50), anterior, T0)
    assert "dato_a_verificar" in a["avisos"]
    assert a["nivel"] == "alerta"
    assert "nivel_retenido" not in a


def test_corte_de_la_fuente_mantiene_el_nivel_con_margen():
    # Sin respuesta de CARU se conserva la altura anterior (4,36): el nivel no cambia.
    _, anterior = serie([4.40, 4.36])
    a = pasada(None, anterior, T0 + timedelta(hours=1))
    assert a["nivel"] == "alerta" and a["avisos"] == ["fuente_no_disponible"]


@pytest.mark.parametrize("margen", [-0.01, 0.51, math.nan, math.inf, "0.05", True, None])
def test_margen_mal_configurado_frena_con_codigo_1(monkeypatch, capsys, margen):
    cfg = dict(CFG, margen_bajada_m=margen)
    if margen is None:
        del cfg["margen_bajada_m"]
    original = lector.leer_json
    monkeypatch.setattr(lector, "leer_json",
                        lambda ruta, por_defecto=None: dict(cfg) if Path(ruta).name == "config.json"
                        else original(ruta, por_defecto))

    def sin_red(*a, **k):
        raise AssertionError("no tendría que bajar nada")
    monkeypatch.setattr(red, "descargar", sin_red)
    assert lector.main() == 1
    assert "ERROR: margen_bajada_m" in capsys.readouterr().out
