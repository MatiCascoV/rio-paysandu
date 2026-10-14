"""Retención del nivel ante un dato dudoso. Principio: durante una crecida, dejar
de informar es tan grave como informar mal. Un salto brusco retiene el nivel como
mucho una lectura (o `retencion_max_min`); nada más congela el nivel."""
import json
from datetime import datetime, timedelta
from pathlib import Path

import lector
from fuentes.caru_registro import TZ_UY
from nivel import calcular_nivel

CFG = json.loads((Path(lector.__file__).parent / "config.json").read_text(encoding="utf-8"))
UMBRALES = {"atencion_m": 5.0, "alerta_m": 6.0, "evacuacion_m": 6.89}
INICIO = datetime(2026, 10, 9, 0, 0, tzinfo=TZ_UY)
URL_EST = "http://190.0.152.194:8080/alturas/web/user/estacion/19/0"
URL_PRE = "http://190.0.152.194:8080/alturas/web/user/altura/24"


def lectura(valor, fecha, anterior_m, fecha_anterior, url, periodo):
    return {"valor_m": valor, "fecha": fecha, "variacion_m": round(valor - anterior_m, 2),
            "periodo": periodo, "estado": "crece", "anterior_m": anterior_m,
            "fecha_anterior": fecha_anterior, "url": url}


def registro(est_valor, est_fecha, est_anterior, pre_valor, pre_fecha, pre_anterior=None):
    return {
        "cero": "Local",
        "estacion": lectura(est_valor, est_fecha, est_anterior, est_fecha - timedelta(minutes=30), URL_EST, "30 min"),
        "prefectura": lectura(pre_valor, pre_fecha, pre_anterior if pre_anterior is not None else pre_valor,
                              pre_fecha - timedelta(days=1), URL_PRE, "24 hs"),
    }


def pasada(reg, anterior, ahora):
    return lector.armar_actual(reg, {"vigente": False}, UMBRALES, anterior, ahora, CFG)


def test_crecida_de_1_5_m_en_24_h_con_prefectura_diaria():
    # La estación sube 1,5 m en 24 h (de 5,6 a 7,1), lectura cada 30 min; Prefectura
    # informa solo a las 06:00. El lector corre cada 10 min. Cada cambio de nivel
    # tiene que publicarse a más tardar una pasada después de la lectura que lo cruza.
    anterior = None
    atrasos = []
    pre = (5.55, INICIO - timedelta(hours=18))
    for paso in range(0, 24 * 6 + 1):  # pasadas cada 10 min
        ahora = INICIO + timedelta(minutes=10 * paso)
        n = paso // 3  # lectura de la estación vigente (cada 30 min)
        est_fecha = INICIO + timedelta(minutes=30 * n)
        valor = round(5.6 + 1.5 * n / 48, 2)
        anterior_m = round(5.6 + 1.5 * max(n - 1, 0) / 48, 2)
        if ahora >= INICIO + timedelta(hours=6):
            pre = (round(5.6 + 1.5 * 12 / 48, 2), INICIO + timedelta(hours=6))
        a = pasada(registro(valor, est_fecha, anterior_m, pre[0], pre[1]), anterior, ahora)
        esperado = calcular_nivel(valor, UMBRALES)
        atrasos.append(a["nivel"] != esperado)
        assert "nivel_retenido" not in a
        anterior = a
    assert not any(atrasos)
    assert anterior["nivel"] == "evacuacion"


def test_estacion_7_20_y_prefectura_de_hace_17_h_no_congela():
    # Caso reproducido: nivel en alerta, la estación ya marca 7,20 (evacuación) y la
    # última de Prefectura es de hace 17 h (6,00). Antes quedaba "alerta" todo el día.
    ahora = datetime(2026, 10, 9, 23, 0, tzinfo=TZ_UY)
    anterior = {"nivel": "alerta", "avisos": [],
                "altura_actual": {"valor_m": 7.10, "fecha": (ahora - timedelta(hours=1)).isoformat()}}
    reg = registro(7.20, ahora - timedelta(minutes=30), 7.15, 6.00, ahora - timedelta(hours=17))
    for i in range(3):
        a = pasada(reg, anterior, ahora + timedelta(minutes=10 * i))
        assert a["nivel"] == "evacuacion"
        assert "dato_a_verificar" not in a["avisos"]
        anterior = a


def test_discrepancia_entre_fuentes_avisa_pero_no_retiene():
    ahora = datetime(2026, 10, 9, 8, 0, tzinfo=TZ_UY)
    anterior = {"nivel": "alerta", "avisos": [],
                "altura_actual": {"valor_m": 6.95, "fecha": (ahora - timedelta(hours=1, minutes=30)).isoformat()}}
    # Prefectura de hace 2 h dice 5,5: más de 1 m de diferencia, a menos de 3 h.
    reg = registro(7.00, ahora - timedelta(minutes=30), 6.97, 5.50, ahora - timedelta(hours=2))
    a = pasada(reg, anterior, ahora)
    assert "dato_a_verificar" in a["avisos"]
    assert a["nivel"] == "evacuacion"
    assert "nivel_retenido" not in a


def test_salto_falso_unico_se_retiene_una_pasada_y_luego_se_publica():
    t0 = datetime(2026, 10, 9, 7, 0, tzinfo=TZ_UY)
    anterior = pasada(registro(6.10, t0, 6.10, 6.05, t0 - timedelta(hours=1)), None, t0 + timedelta(minutes=5))
    assert anterior["nivel"] == "alerta"
    # 07:30: salto de 1,4 m. Se publica el dato con aviso, pero el nivel se retiene.
    t1 = t0 + timedelta(minutes=30)
    a = pasada(registro(7.50, t1, 6.10, 6.05, t0 - timedelta(hours=1)), anterior, t1 + timedelta(minutes=5))
    assert a["altura_actual"]["valor_m"] == 7.50
    assert "dato_a_verificar" in a["avisos"]
    assert a["nivel"] == "alerta"
    assert a["nivel_retenido"]["fecha_lectura"] == t1.isoformat()
    # 08:00: la lectura siguiente (otra fecha) lo confirma: se publica evacuación.
    t2 = t1 + timedelta(minutes=30)
    b = pasada(registro(7.52, t2, 7.50, 6.05, t0 - timedelta(hours=1)), a, t2 + timedelta(minutes=5))
    assert b["nivel"] == "evacuacion"
    assert "nivel_retenido" not in b


def test_salto_falso_que_vuelve_no_cambia_el_nivel():
    t0 = datetime(2026, 10, 9, 7, 0, tzinfo=TZ_UY)
    anterior = pasada(registro(6.10, t0, 6.10, 6.05, t0 - timedelta(hours=1)), None, t0)
    t1 = t0 + timedelta(minutes=30)
    a = pasada(registro(7.50, t1, 6.10, 6.05, t0 - timedelta(hours=1)), anterior, t1)
    t2 = t1 + timedelta(minutes=30)
    b = pasada(registro(6.11, t2, 7.50, 6.05, t0 - timedelta(hours=1)), a, t2)
    assert b["nivel"] == "alerta"
    assert "nivel_retenido" not in b


def test_misma_lectura_repetida_no_congela_el_nivel():
    t0 = datetime(2026, 10, 9, 7, 0, tzinfo=TZ_UY)
    anterior = pasada(registro(6.10, t0, 6.10, 6.05, t0 - timedelta(hours=1)), None, t0)
    t1 = t0 + timedelta(minutes=30)
    reg = registro(7.50, t1, 6.10, 6.05, t0 - timedelta(hours=1))  # CARU no publica nada nuevo
    niveles = []
    for minutos in (0, 10, 20, 30, 40):
        anterior = pasada(reg, anterior, t1 + timedelta(minutes=minutos))
        niveles.append(anterior["nivel"])
    # Retenido como mucho `retencion_max_min` (30) minutos con la misma lectura.
    assert niveles == ["alerta", "alerta", "alerta", "evacuacion", "evacuacion"]
    assert "nivel_retenido" not in anterior


def test_fecha_futura_se_descarta_sin_retener():
    t0 = datetime(2026, 10, 9, 7, 0, tzinfo=TZ_UY)
    anterior = {"nivel": "alerta", "avisos": [],
                "altura_actual": {"valor_m": 6.95, "fecha": (t0 - timedelta(minutes=30)).isoformat()}}
    reg = registro(7.00, t0 + timedelta(days=30), 6.97, 7.00, t0 - timedelta(hours=1))
    a = pasada(reg, anterior, t0)
    assert "dato_a_verificar" in a["avisos"]
    assert a["altura_actual"]["valor_m"] == 7.00  # se usa Prefectura
    assert a["nivel"] == "evacuacion"
    assert "nivel_retenido" not in a
