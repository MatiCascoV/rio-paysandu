"""Parsers contra páginas y PDF reales de CARU guardados en fixtures/."""
from datetime import date, datetime
from pathlib import Path

import pytest

from fuentes import caru_informes, caru_registro
from fuentes.caru_registro import TZ_UY

FIXTURES = Path(__file__).parent / "fixtures"
URL_REGISTRO = "http://190.0.152.194:8080/alturas/web/user/alturas"


def leer(nombre):
    return (FIXTURES / nombre).read_text(encoding="utf-8")


@pytest.fixture(scope="module")
def registro():
    return caru_registro.parsear_registro(leer("registro_alturas_2026-10-09.html"), URL_REGISTRO)


def test_registro_cero(registro):
    assert registro["cero"] == "Local"


def test_registro_prefectura(registro):
    p = registro["prefectura"]
    assert p["valor_m"] == 5.9
    assert p["fecha"] == datetime(2026, 10, 9, 6, 0, tzinfo=TZ_UY)
    assert p["fecha"].isoformat() == "2026-10-09T06:00:00-03:00"
    assert p["variacion_m"] == 0.30
    assert p["periodo"] == "24 hs"
    assert p["estado"] == "crece"
    assert p["anterior_m"] == 5.6
    assert p["fecha_anterior"] == datetime(2026, 10, 8, 6, 0, tzinfo=TZ_UY)
    assert p["url"] == "http://190.0.152.194:8080/alturas/web/user/altura/24"


def test_registro_estacion(registro):
    e = registro["estacion"]
    assert e["valor_m"] == 5.89
    assert e["fecha"] == datetime(2026, 10, 9, 7, 0, tzinfo=TZ_UY)
    assert e["variacion_m"] == 0.0
    assert e["periodo"] == "30 min"
    assert e["estado"] == "estacionado"
    assert e["anterior_m"] == 5.89
    assert e["url"] == "http://190.0.152.194:8080/alturas/web/user/estacion/19/0"


def test_registro_puerto_inexistente():
    r = caru_registro.parsear_registro(leer("registro_alturas_2026-10-09.html"), URL_REGISTRO, "Atlántida")
    assert r["prefectura"] is None and r["estacion"] is None


def test_registro_html_roto():
    r = caru_registro.parsear_registro("<html><body>Error 500</body></html>", URL_REGISTRO)
    assert r == {"cero": None, "prefectura": None, "estacion": None}


def test_historial_prefectura():
    h = caru_registro.parsear_historial(leer("detalle_altura_24.html"))
    assert len(h) == 7
    assert h[0] == (datetime(2026, 10, 9, 6, 0, tzinfo=TZ_UY), 5.9)
    assert h[-1] == (datetime(2026, 10, 3, 6, 0, tzinfo=TZ_UY), 4.5)


def test_historial_estacion():
    h = caru_registro.parsear_historial(leer("detalle_estacion_19_0.html"))
    assert len(h) > 200  # una semana de lecturas cada 30 min
    assert h[0] == (datetime(2026, 10, 2, 10, 0, tzinfo=TZ_UY), 4.42)
    assert all(0 <= v <= 20 for _, v in h)


def test_historial_sin_datos():
    assert caru_registro.parsear_historial("<html></html>") == []


def test_indice_informes():
    informes = caru_informes.listar_informes(
        leer("informes_indice_2026-10-09.html"),
        "https://caru.org.uy/nuevositio/2026/10/05/informes-crecida-rio-uruguay-2026/")
    assert len(informes) == 19
    assert informes[0] == {
        "fecha": date(2026, 10, 8),
        "url": "https://caru.org.uy/nuevositio/wp-content/uploads/2026/10/20261008-Crecida.pdf"}
    urls = [i["url"] for i in informes]
    # nombres de archivo irregulares: se toman tal cual del índice
    assert any(u.endswith("20260803-Crecida-2.pdf") for u in urls)
    assert any(u.endswith("20260726-Crecida.docx-1.pdf") for u in urls)
    fechas = [i["fecha"] for i in informes]
    assert fechas == sorted(fechas, reverse=True)


@pytest.mark.parametrize("archivo, fecha, esperada, caudal", [
    ("20261008-Crecida.pdf", date(2026, 10, 8), 6.66, 18000),
    ("20261005-Crecida.pdf", date(2026, 10, 5), 5.90, 16500),
    ("20260803-Crecida-2.pdf", date(2026, 8, 3), 6.35, 17500),
    ("20260726-Crecida.docx-1.pdf", date(2026, 7, 26), 5.40, 15000),
])
def test_informe_pdf(archivo, fecha, esperada, caudal):
    d = caru_informes.parsear_informe((FIXTURES / archivo).read_bytes())
    assert d["informe_fecha"] == fecha
    assert d["altura_esperada_m"] == esperada
    assert d["nivel_alerta_m"] == 4.39
    assert d["nivel_evacuacion_m"] == 6.89
    assert d["caudal_salto_grande_m3s"] == caudal
    assert d["texto"] and "represa" in d["texto"]


def test_indice_descarta_fechas_futuras():
    html = ('<a href="/a/20261107-Crecida.pdf">INFORME 7/11/2026</a>'
            '<a href="/a/20261006-Crecida.pdf">INFORME 6/10/2026</a>')
    informes = caru_informes.listar_informes(html, "https://caru.org.uy/", date(2026, 10, 9))
    assert [i["fecha"] for i in informes] == [date(2026, 10, 6)]


def test_fecha_imposible_no_rompe():
    assert caru_registro._fecha("31/02/2026 - 10:00") is None
    assert caru_registro._fecha("00/00/0000 - 00:00") is None


def test_informe_otro_puerto():
    d = caru_informes.parsear_informe((FIXTURES / "20261008-Crecida.pdf").read_bytes(), "Colón")
    assert d["altura_esperada_m"] == 7.62
