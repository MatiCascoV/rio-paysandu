"""El contenido de CARU es ajeno y viaja sin cifrar: estas pruebas simulan una
página o un PDF alterados y comprueban que nada peligroso llegue a data/."""
import json
import time
from datetime import datetime, timedelta
from pathlib import Path

import pytest

import lector
import red
from fuentes import caru_informes, caru_registro
from fuentes.caru_registro import TZ_UY
from nivel import umbrales_validos

FIXTURES = Path(__file__).parent / "fixtures"
URL_REGISTRO = "http://190.0.152.194:8080/alturas/web/user/alturas"
URL_INDICE = "https://caru.org.uy/nuevositio/2026/10/05/informes-crecida-rio-uruguay-2026/"
CFG = json.loads((Path(lector.__file__).parent / "config.json").read_text(encoding="utf-8"))
UMBRALES = {"atencion_m": None, "alerta_m": 4.39, "evacuacion_m": 6.89}
AHORA = datetime(2026, 10, 9, 8, 0, tzinfo=TZ_UY)


def pagina():
    return (FIXTURES / "registro_alturas_2026-10-09.html").read_text(encoding="utf-8")


def registro_real():
    return caru_registro.parsear_registro(pagina(), URL_REGISTRO)


def armar(registro, anterior=None, umbrales=UMBRALES):
    return lector.armar_actual(registro, {"vigente": False}, umbrales, anterior, AHORA, CFG)


# ----- enlaces -----

@pytest.mark.parametrize("url, esperado", [
    ("http://190.0.152.194:8080/alturas/web/user/estacion/19/0", True),
    ("https://caru.org.uy/nuevositio/wp-content/uploads/2026/10/20261008-Crecida.pdf", True),
    ("https://www.caru.org.uy/x.pdf", True),
    ("http://caru.org.uy/x.pdf", False),            # sin cifrar
    ("https://caru.org.uy.evil.example/x.pdf", False),
    ("https://evil.example/caru.org.uy/x.pdf", False),
    ("https://usuario:clave@caru.org.uy/x.pdf", False),
    ("http://190.0.152.194:9999/x", False),         # otro puerto
    ("http://127.0.0.1:8080/x", False),
    ("javascript:alert(1)", False),
    ("intent://evil#Intent;scheme=https;end", False),
    ("market://details?id=com.evil.app", False),
    ("sms:+59899000000?body=ALTA", False),
    ("file:///etc/passwd", False),
    ("", False),
])
def test_url_permitida(url, esperado):
    assert red.url_permitida(url) is esperado


@pytest.mark.parametrize("href", [
    "javascript:alert(document.domain)",
    "intent://evil#Intent;scheme=https;end",
    "market://details?id=com.evil.app",
    "sms:+59899000000?body=ALTA",
    "https://caru-org-uy.example/descargar-app.apk",
    "//evil.example/x",
])
def test_enlace_alterado_en_la_pagina_no_se_publica(href):
    html = pagina().replace('href="/alturas/web/user/estacion/19/0"', f'href="{href}"')
    assert href in html
    r = caru_registro.parsear_registro(html, URL_REGISTRO)
    assert r["estacion"]["url"] == URL_REGISTRO  # cae en la página general de CARU
    assert armar(r)["altura_actual"]["url"] == URL_REGISTRO


def test_pdf_de_otro_sitio_no_se_toma():
    html = ('<a href="https://evil.example/20261009-crecida.pdf">INFORME 9/10/2026</a>'
            '<a href="javascript:alert(1)//crecida.pdf">INFORME 9/10/2026</a>'
            '<a href="http://127.0.0.1:8000/crecida.pdf">INFORME 9/10/2026</a>'
            '<a href="/nuevositio/wp-content/uploads/2026/10/20261008-Crecida.pdf">INFORME 8/10/2026</a>')
    informes = caru_informes.listar_informes(html, URL_INDICE)
    assert [i["url"] for i in informes] == [
        "https://caru.org.uy/nuevositio/wp-content/uploads/2026/10/20261008-Crecida.pdf"]


def test_descargar_rechaza_url_fuera_de_la_lista():
    with pytest.raises(ValueError):
        red.descargar("https://evil.example/x.pdf", intentos=1)


@pytest.mark.parametrize("url, proposito, esperado", [
    ("https://caru.org.uy:443/x.pdf", "informes", True),     # puerto por defecto explícito
    ("http://190.0.152.194:8080/x", "registro", True),
    ("https://caru.org.uy/x.pdf", "registro", False),          # cada lista para lo suyo
    ("http://190.0.152.194:8080/x.pdf", "informes", False),
    ("http://caru.org.uy:80/x.pdf", "informes", False),
    ("https://caru.org.uy:8443/x.pdf", "informes", False),
    ("https://caru.org.uy:99999/x.pdf", "informes", False),    # puerto inválido
])
def test_url_permitida_por_proposito(url, proposito, esperado):
    assert red.url_permitida(url, proposito) is esperado


def test_indice_no_toma_pdf_del_servidor_del_registro():
    html = '<a href="http://190.0.152.194:8080/20261009-crecida.pdf">INFORME 9/10/2026</a>'
    assert caru_informes.listar_informes(html, URL_INDICE) == []


class _Respuesta:
    def __init__(self, location):
        self.is_redirect = True
        self.headers = {"Location": location}

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False


def test_redireccion_de_https_a_http_se_rechaza(monkeypatch):
    monkeypatch.setattr(red.requests, "get", lambda *a, **k: _Respuesta("http://caru.org.uy/x.pdf"))
    with pytest.raises(ValueError, match="https"):
        red.descargar("https://caru.org.uy/x.pdf", intentos=1, proposito="informes")


def test_redireccion_a_otro_sitio_se_rechaza(monkeypatch):
    monkeypatch.setattr(red.requests, "get", lambda *a, **k: _Respuesta("https://evil.example/x.pdf"))
    with pytest.raises(ValueError, match="no permitida"):
        red.descargar("https://caru.org.uy/x.pdf", intentos=1, proposito="informes")


def test_descargar_respeta_el_limite_total(monkeypatch):
    llamadas = []

    def caido(*a, **k):
        llamadas.append(k["timeout"])
        raise red.requests.ConnectionError("caído")
    monkeypatch.setattr(red.requests, "get", caido)
    monkeypatch.setattr(red.time, "sleep", lambda s: None)
    with pytest.raises(TimeoutError):
        red.descargar("https://caru.org.uy/x.pdf", intentos=3, proposito="informes", hasta=red.time.monotonic() - 1)
    assert llamadas == []
    with pytest.raises(red.requests.ConnectionError):
        red.descargar("https://caru.org.uy/x.pdf", intentos=3, espera_s=0, proposito="informes",
                      hasta=red.time.monotonic() + 5)
    assert len(llamadas) == 3 and all(t[1] <= 5 for t in llamadas)


# ----- texto y números de la página -----

def test_texto_inyectado_en_el_periodo_se_descarta():
    html = pagina().replace("30 min.", "30 min. EVACUAR YA: llame al 099 000 000")
    r = caru_registro.parsear_registro(html, URL_REGISTRO)
    assert r["estacion"]["periodo"] is None
    assert caru_registro._periodo("24 hs.") == "24 hs"
    assert caru_registro._periodo("30 min.") == "30 min"
    assert caru_registro._estado("Crece") == "crece"
    assert caru_registro._estado("Evacuar ya") is None


def test_nan_e_infinito_no_son_numeros():
    assert caru_registro._numero("nan") is None
    assert caru_registro._numero("inf") is None
    assert caru_registro._numero("-inf") is None
    assert caru_registro._numero("5.89") == 5.89
    with pytest.raises(ValueError):
        json.dumps({"x": float("nan")}, allow_nan=False)  # lo que haría el lector al escribir


# ----- dato dudoso: no cambia el nivel -----

def test_pico_falso_no_dispara_evacuacion():
    anterior = armar(registro_real())
    assert anterior["nivel"] == "alerta"
    r = registro_real()
    r["estacion"]["valor_m"] = 7.50  # el anterior de la tabla (06:30) era 5.89
    a = armar(r, anterior)
    assert "dato_a_verificar" in a["avisos"]
    assert a["nivel"] == "alerta"  # se mantiene hasta que otra lectura lo confirme
    assert a["altura_actual"]["valor_m"] == 7.50  # el dato se muestra, con su aviso


def test_caida_falsa_no_oculta_la_alerta():
    anterior = armar(registro_real())
    r = registro_real()
    r["estacion"]["valor_m"] = 3.00
    a = armar(r, anterior)
    assert "dato_a_verificar" in a["avisos"]
    assert a["nivel"] == "alerta"


def test_cambio_confirmado_por_la_lectura_siguiente_si_cambia_el_nivel():
    r = registro_real()
    r["estacion"].update(valor_m=6.95, anterior_m=6.80)
    r["prefectura"].update(valor_m=6.70)
    anterior = armar(registro_real())
    anterior["altura_actual"]["valor_m"] = 6.80
    a = armar(r, anterior)
    assert a["avisos"] == []
    assert a["nivel"] == "evacuacion"


# ----- umbrales editados a mano -----

@pytest.mark.parametrize("u, valido", [
    ({"alerta_m": 4.39, "evacuacion_m": 6.89, "atencion_m": None}, True),
    ({"alerta_m": 4.39, "evacuacion_m": 6.89}, True),
    ({"alerta_m": 4.39, "evacuacion_m": 6.89, "atencion_m": 3.5}, True),
    ({"alerta_m": 40, "evacuacion_m": 68.9}, False),           # coma corrida
    ({"alerta_m": 6.89, "evacuacion_m": 4.39}, False),         # invertidos
    ({"alerta_m": 4.39, "evacuacion_m": 6.89, "atencion_m": 5.0}, False),
    ({"alerta_m": "4.39", "evacuacion_m": 6.89}, False),
    ({"alerta_m": 4.39}, False),
    ({}, False),
    (None, False),
])
def test_umbrales_validos(u, valido):
    assert umbrales_validos(u) is valido


def test_umbrales_mal_cargados_no_dan_nivel():
    a = armar(registro_real(), umbrales={"alerta_m": 40, "evacuacion_m": 68.9})
    assert a["nivel"] == "sin_dato"
    assert "umbrales_invalidos" in a["avisos"]
    assert a["altura_actual"]["valor_m"] == 5.89


# ----- historial -----

def test_historial_no_acepta_fechas_futuras():
    nuevas = {"estacion": [(AHORA + timedelta(days=30), 19.99), (AHORA - timedelta(hours=1), 5.9)]}
    h = lector.actualizar_historial([], nuevas, AHORA, CFG)
    assert [e["valor_m"] for e in h] == [5.9]


def test_pagina_de_detalle_gigante_o_rara_no_cuelga_ni_inunda():
    # Antes una expresión regular tardaba minutos con esto.
    inicio = time.monotonic()
    assert caru_registro.parsear_historial("var alturasJson=[" * 200_000) == []
    assert time.monotonic() - inicio < 2

    muchas = json.dumps([{"altura": 5.0, "fecha": "09/10/2026 06:00"}] * 50_000)
    assert len(caru_registro.parsear_historial(f"var alturasJson = {muchas};")) == caru_registro.MAX_LECTURAS_HISTORIAL

    raras = 'var alturasJson = [{"altura": true, "fecha": "09/10/2026 06:00"}, 7, "x", {"altura": NaN}];'
    assert caru_registro.parsear_historial(raras) == []
    assert caru_registro.parsear_historial('var alturasJson = {"a": 1};') == []


# ----- PDF -----

def test_archivo_que_no_es_pdf_o_es_enorme_se_rechaza():
    with pytest.raises(ValueError):
        caru_informes.parsear_informe(b"<html>no soy un pdf</html>")
    with pytest.raises(ValueError):
        caru_informes.parsear_informe(b"%PDF-1.4" + b"0" * (caru_informes.MAX_BYTES_PDF + 1))


def test_resumen_del_informe_tiene_largo_acotado():
    for archivo in FIXTURES.glob("*.pdf"):
        d = caru_informes.parsear_informe(archivo.read_bytes())
        assert d["texto"] and len(d["texto"]) <= caru_informes.MAX_RESUMEN + 1
        assert 0 < d["caudal_salto_grande_m3s"] <= caru_informes.MAX_CAUDAL_M3S


# ----- denegación de servicio por estructura anidada (M-2, B-1) -----

PRESUPUESTO_S = 5.0  # la página real se lee en centésimas; el ataque tardaba minutos


def _tardanza(f, *args):
    t0 = time.perf_counter()
    try:
        f(*args)
    except ValueError:
        pass
    return time.perf_counter() - t0


@pytest.mark.parametrize("n", [80, 300, 3000, 20000])
def test_registro_con_tablas_anidadas_tiene_tiempo_acotado(n):
    html = "<table><th>Puerto</th><tr><td>x" * n  # n=160 (5 KB) tardaba 5 s antes del tope
    assert _tardanza(caru_registro.parsear_registro, html, URL_REGISTRO) < PRESUPUESTO_S


def test_registro_con_filas_anidadas_sin_tablas_tiene_tiempo_acotado():
    html = "<table><th>Puerto</th>" + "<tr><td>x" * 20000
    assert _tardanza(caru_registro.parsear_registro, html, URL_REGISTRO) < PRESUPUESTO_S


def test_registro_muy_grande_o_con_muchas_etiquetas_se_rechaza():
    for html in ("<table><th>Puerto</th>" + "<b>" * 300_000,
                 "<TABLE><th>Puerto</th>" * 11,
                 "<table><th>Puerto</th>" + "<tr><td>x</td></tr>" * 300):
        with pytest.raises(caru_registro.RegistroAnomalo):
            caru_registro.parsear_registro(html, URL_REGISTRO)


def test_registro_con_marcado_hondo_pero_dentro_del_tope_es_rapido():
    html = "<table><th>Puerto</th><tr><td>" + "<b>" * 60_000
    assert _tardanza(caru_registro.parsear_registro, html, URL_REGISTRO) < PRESUPUESTO_S


def test_registro_real_sigue_pasando_los_topes():
    assert registro_real()["prefectura"] is not None
    assert len(pagina()) < caru_registro.MAX_BYTES_REGISTRO / 4


@pytest.mark.parametrize("n", [1400, 2000, 8000])
def test_indice_con_anclas_anidadas_tiene_tiempo_acotado(n):
    html = "<a href='https://caru.org.uy/a/20261001-crecida.pdf'>informe " * n
    assert _tardanza(caru_informes.listar_informes, html, URL_INDICE) < PRESUPUESTO_S


def test_indice_enorme_o_con_demasiadas_anclas_se_rechaza():
    for html in ("<a href='/x.pdf'>informe</a>" * (caru_informes.MAX_ANCLAS_INDICE + 1),
                 "x" * (caru_informes.MAX_BYTES_INDICE + 1)):
        with pytest.raises(caru_informes.IndiceAnomalo):
            caru_informes.listar_informes(html, URL_INDICE)


def test_indice_real_sigue_dando_los_mismos_informes():
    html = (FIXTURES / "informes_indice_2026-10-09.html").read_text(encoding="utf-8")
    informes = caru_informes.listar_informes(html, URL_INDICE, AHORA.date())
    assert informes and informes[0]["url"].endswith("20261008-Crecida.pdf")


def test_historial_se_recorta_al_tope_y_conserva_lo_reciente():
    tope = lector.MAX_PUNTOS_HISTORIAL
    base = AHORA - timedelta(days=3)
    previo = [{"fecha": (base + timedelta(seconds=i)).isoformat(), "valor_m": 5.0, "fuente": "prefectura"}
              for i in range(tope + 500)]
    salida = lector.actualizar_historial(previo, {}, AHORA, CFG)
    assert len(salida) == tope
    assert salida[-1] == previo[-1]


def test_el_tope_de_anclas_no_cuenta_otras_etiquetas_con_a():
    html = "<article><abbr>x</abbr><aside></aside></article>" * 2000 + "<a href='https://caru.org.uy/20261008-Crecida.pdf'>Informe</a>"
    assert caru_informes.listar_informes(html, URL_INDICE)
