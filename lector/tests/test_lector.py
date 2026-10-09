"""Reglas del lector: elección de la lectura principal, avisos, nivel,
pronóstico e historial. No usan la red."""
import json
from datetime import date, datetime, timedelta
from pathlib import Path

import pytest

import lector
import validar
from fuentes import caru_registro
from fuentes.caru_registro import TZ_UY
from nivel import calcular_nivel

# Umbrales fijos para los tests (no dependen de data/umbrales.json).
UMBRALES_PROVISORIOS = {"atencion_m": 5.0, "alerta_m": 6.0, "evacuacion_m": 6.89}

FIXTURES = Path(__file__).parent / "fixtures"
CFG = json.loads((Path(lector.__file__).parent / "config.json").read_text(encoding="utf-8"))
AHORA = datetime(2026, 10, 9, 8, 0, tzinfo=TZ_UY)  # una hora después del dato de la estación
PRONOSTICO = {"vigente": False}


def registro_real():
    html = (FIXTURES / "registro_alturas_2026-10-09.html").read_text(encoding="utf-8")
    return caru_registro.parsear_registro(html, CFG["registro_url"])


def armar(registro, anterior=None, ahora=AHORA):
    return lector.armar_actual(registro, PRONOSTICO, UMBRALES_PROVISORIOS, anterior, ahora, CFG)


# ----- nivel -----

@pytest.mark.parametrize("valor, esperado", [
    (None, "sin_dato"), (4.99, "normal"), (5.0, "atencion"), (5.99, "atencion"),
    (6.0, "alerta"), (6.88, "alerta"), (6.89, "evacuacion"), (9.0, "evacuacion"),
])
def test_calcular_nivel(valor, esperado):
    assert calcular_nivel(valor, UMBRALES_PROVISORIOS) == esperado


def test_nivel_sin_umbral_de_atencion():
    u = {"atencion_m": None, "alerta_m": 4.39, "evacuacion_m": 6.89}
    assert calcular_nivel(4.38, u) == "normal"
    assert calcular_nivel(4.39, u) == "alerta"
    assert calcular_nivel(5.94, u) == "alerta"
    assert calcular_nivel(6.89, u) == "evacuacion"


# ----- validación -----

def test_en_rango():
    assert validar.en_rango(0) and validar.en_rango(20) and validar.en_rango(5.7)
    assert not validar.en_rango(-0.1) and not validar.en_rango(20.1) and not validar.en_rango(None)


def test_salto_sospechoso():
    t = AHORA
    assert validar.salto_sospechoso(7.0, t, [(5.9, t - timedelta(hours=5))])
    assert not validar.salto_sospechoso(7.0, t, [(5.9, t - timedelta(hours=7))])   # pasó mucho tiempo
    assert not validar.salto_sospechoso(6.5, t, [(5.9, t - timedelta(hours=1))])   # cambio chico
    assert not validar.salto_sospechoso(7.0, t, [(None, None)])


# ----- actual.json -----

def test_actual_con_datos_reales():
    a = armar(registro_real())
    assert a["generado"] == "2026-10-09T08:00:00-03:00"
    assert a["cero"] == "Local"
    assert a["altura_actual"] == {
        "valor_m": 5.89, "fecha": "2026-10-09T07:00:00-03:00", "variacion_m": 0.0,
        "periodo": "30 min", "estado": "estacionado",
        "fuente": "CARU – estación automática Paysandú",
        "url": "http://190.0.152.194:8080/alturas/web/user/estacion/19/0"}
    assert a["lectura_prefectura"] == {
        "valor_m": 5.9, "fecha": "2026-10-09T06:00:00-03:00", "variacion_m": 0.3,
        "periodo": "24 hs", "estado": "crece",
        "url": "http://190.0.152.194:8080/alturas/web/user/altura/24"}
    assert a["nivel"] == "atencion"
    assert a["avisos"] == []


def test_estacion_vieja_pero_mas_reciente_se_muestra_con_aviso():
    # 4 h después del último dato de la estación (07:00). Prefectura es de las 06:00:
    # se muestra igual la estación, que es la lectura más reciente, avisando.
    a = armar(registro_real(), ahora=datetime(2026, 10, 9, 11, 0, tzinfo=TZ_UY))
    assert a["altura_actual"]["valor_m"] == 5.89
    assert a["avisos"] == ["dato_desactualizado"]


def test_estacion_caida_usa_prefectura_si_es_mas_reciente():
    r = registro_real()
    r["estacion"]["fecha"] = datetime(2026, 10, 8, 20, 0, tzinfo=TZ_UY)  # dejó de transmitir anoche
    a = armar(r)
    assert a["altura_actual"]["valor_m"] == 5.9
    assert "Prefectura" in a["altura_actual"]["fuente"]
    assert a["avisos"] == ["estacion_desactualizada"]


def test_todo_viejo_avisa_y_no_da_nivel():
    a = armar(registro_real(), ahora=datetime(2026, 10, 12, 8, 0, tzinfo=TZ_UY))
    assert a["altura_actual"]["valor_m"] == 5.89  # la más reciente, con su fecha real
    assert "dato_desactualizado" in a["avisos"]
    assert a["nivel"] == "sin_dato"


def test_dato_fuera_de_rango_se_descarta():
    r = registro_real()
    r["estacion"]["valor_m"] = 57.0  # por ejemplo, un error de tipeo en la fuente
    a = armar(r)
    assert a["altura_actual"]["valor_m"] == 5.9
    assert "dato_fuera_de_rango" in a["avisos"]


def test_salto_brusco_avisa():
    r = registro_real()
    r["estacion"]["valor_m"] = 7.2  # el anterior (06:30) era 5.89
    a = armar(r)
    assert "dato_a_verificar" in a["avisos"]


SIN_FILAS = {"cero": None, "prefectura": None, "estacion": None}


def test_sin_filas_es_sin_dato():
    a = armar(SIN_FILAS)
    assert a["altura_actual"] is None
    assert a["nivel"] == "sin_dato"
    assert a["avisos"] == ["fuente_no_disponible"]


def test_pagina_sin_filas_conserva_ultimo_dato():
    # CARU responde pero sin la fila de Paysandú (página de error, cambio de formato...)
    anterior = armar(registro_real())
    a = armar(SIN_FILAS, anterior, ahora=AHORA + timedelta(minutes=30))
    assert a["altura_actual"] == anterior["altura_actual"]
    assert a["lectura_prefectura"] == anterior["lectura_prefectura"]
    assert a["avisos"] == ["fuente_no_disponible"]


def test_fuente_caida_conserva_avisos_del_dato():
    r = registro_real()
    r["estacion"]["valor_m"] = 7.2
    anterior = armar(r)
    a = armar(None, anterior, ahora=AHORA + timedelta(minutes=30))
    assert a["avisos"] == ["dato_a_verificar", "fuente_no_disponible"]


def test_fuentes_que_no_coinciden_avisan_mientras_dure():
    # Sensor de la estación clavado en 0: el "anterior" ya es 0, pero Prefectura dice 5.9.
    r = registro_real()
    r["estacion"].update(valor_m=0.0, anterior_m=0.0)
    assert "dato_a_verificar" in armar(r)["avisos"]


def test_fecha_futura_no_se_toma_como_actual():
    r = registro_real()
    r["estacion"]["fecha"] = datetime(2026, 11, 9, 7, 0, tzinfo=TZ_UY)  # mes mal tipeado
    a = armar(r)
    assert a["altura_actual"]["valor_m"] == 5.9  # se usa Prefectura
    assert "dato_a_verificar" in a["avisos"]


def test_json_mal_escrito_no_se_pisa(tmp_path):
    ruta = tmp_path / "umbrales.json"
    assert lector.leer_json(ruta, "no existe") == "no existe"
    ruta.write_text('{"validado": true, "alerta_m": 6.0,}', encoding="utf-8")
    with pytest.raises(ValueError):
        lector.leer_json(ruta)


def test_fuente_caida_conserva_ultimo_dato():
    anterior = armar(registro_real())
    a = armar(None, anterior, ahora=AHORA + timedelta(minutes=30))
    assert a["altura_actual"] == anterior["altura_actual"]
    assert a["lectura_prefectura"] == anterior["lectura_prefectura"]
    assert a["avisos"] == ["fuente_no_disponible"]
    assert a["nivel"] == "atencion"
    # si la caída se prolonga, el dato pasa a estar desactualizado
    a = armar(None, anterior, ahora=AHORA + timedelta(hours=5))
    assert a["avisos"] == ["dato_desactualizado", "fuente_no_disponible"]


def test_fuente_caida_sin_dato_previo():
    a = armar(None, None)
    assert a["altura_actual"] is None and a["nivel"] == "sin_dato"


# ----- pronóstico -----

INFORME = {"informe_fecha": date(2026, 10, 8), "altura_esperada_m": 6.66, "nivel_alerta_m": 4.39,
           "nivel_evacuacion_m": 6.89, "caudal_salto_grande_m3s": 18000, "texto": "El río continuará creciendo."}
URL_PDF = "https://caru.org.uy/nuevositio/wp-content/uploads/2026/10/20261008-Crecida.pdf"


def test_pronostico_vigente():
    p = lector.armar_pronostico(INFORME, URL_PDF, None, date(2026, 10, 9), CFG)
    assert p == {"vigente": True, "informe_fecha": "2026-10-08", "altura_esperada_m": 6.66,
                 "texto": "El río continuará creciendo.", "caudal_salto_grande_m3s": 18000,
                 "url_informe": URL_PDF}


def test_pronostico_vence_a_los_dos_dias():
    assert lector.armar_pronostico(INFORME, URL_PDF, None, date(2026, 10, 10), CFG)["vigente"]
    assert not lector.armar_pronostico(INFORME, URL_PDF, None, date(2026, 10, 11), CFG)["vigente"]


def test_pronostico_conserva_el_anterior_si_falla_la_fuente():
    previo = lector.armar_pronostico(INFORME, URL_PDF, None, date(2026, 10, 9), CFG)
    p = lector.armar_pronostico(None, None, previo, date(2026, 10, 9), CFG)
    assert p == previo
    assert not lector.armar_pronostico(None, None, previo, date(2026, 10, 20), CFG)["vigente"]


def test_pronostico_sin_nada():
    assert lector.armar_pronostico(None, None, None, date(2026, 10, 9), CFG) == {"vigente": False}


def test_pronostico_pdf_sin_fila_no_inventa():
    roto = dict(INFORME, altura_esperada_m=None)
    assert lector.armar_pronostico(roto, URL_PDF, None, date(2026, 10, 9), CFG) == {"vigente": False}


# ----- historial -----

def test_historial_no_duplica():
    t = datetime(2026, 10, 9, 7, 0, tzinfo=TZ_UY)
    nuevas = {"estacion": [(t, 5.89), (t - timedelta(minutes=30), 5.89)], "prefectura": [(t, 5.9)]}
    h1 = lector.actualizar_historial([], nuevas, AHORA, CFG)
    h2 = lector.actualizar_historial(h1, nuevas, AHORA, CFG)
    assert len(h1) == 3 and h2 == h1
    assert h1[0] == {"fecha": "2026-10-09T06:30:00-03:00", "valor_m": 5.89, "fuente": "estacion"}


def test_historial_descarta_viejas_y_fuera_de_rango():
    nuevas = {"prefectura": [(AHORA - timedelta(days=366), 3.0), (AHORA - timedelta(days=364), 3.1),
                             (AHORA, 99.0)]}
    h = lector.actualizar_historial([], nuevas, AHORA, CFG)
    assert [e["valor_m"] for e in h] == [3.1]


def test_historial_aligera_lecturas_viejas_de_la_estacion():
    viejo = datetime(2026, 9, 1, 0, 0, tzinfo=TZ_UY)
    lecturas = [(viejo + timedelta(minutes=30 * i), 4.0) for i in range(48)]  # un día entero
    h = lector.actualizar_historial([], {"estacion": lecturas}, AHORA, CFG)
    assert [e["fecha"][11:16] for e in h] == ["00:00", "06:00", "12:00", "18:00"]


def test_historial_con_fixtures_reales():
    nuevas = {
        "estacion": caru_registro.parsear_historial((FIXTURES / "detalle_estacion_19_0.html").read_text(encoding="utf-8")),
        "prefectura": caru_registro.parsear_historial((FIXTURES / "detalle_altura_24.html").read_text(encoding="utf-8")),
    }
    h = lector.actualizar_historial([], nuevas, AHORA, CFG)
    assert len({(e["fecha"], e["fuente"]) for e in h}) == len(h)
    assert [e["fecha"] for e in h] == sorted(e["fecha"] for e in h)
    assert json.loads(lector.historial_a_texto(h)) == h
