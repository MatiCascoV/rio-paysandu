"""El programa completo (main) con la red simulada: orden de escritura, códigos
de salida, aviso de pronóstico y PDF que falla. No usa internet."""
import json
from datetime import datetime
from pathlib import Path

import pytest

import lector
import pdf_aislado
import red
from fuentes.caru_registro import TZ_UY

FIXTURES = Path(__file__).parent / "fixtures"
CFG = json.loads((Path(lector.__file__).parent / "config.json").read_text(encoding="utf-8"))
URL_PDF = "https://caru.org.uy/nuevositio/wp-content/uploads/2026/10/20261008-Crecida.pdf"
UMBRALES = {"atencion_m": None, "alerta_m": 4.39, "evacuacion_m": 6.89}


class Ahora(datetime):
    @classmethod
    def now(cls, tz=None):
        return datetime(2026, 10, 9, 8, 0, tzinfo=TZ_UY)


class Cortado(BaseException):
    """Simula que el workflow mata al lector (no es un Exception común)."""


def red_falsa(fallar=(), cortar=(), pdf=None):
    paginas = {
        CFG["registro_url"]: "registro_alturas_2026-10-09.html",
        CFG["informes_indice_url"]: "informes_indice_2026-10-09.html",
        "http://190.0.152.194:8080/alturas/web/user/estacion/19/0": "detalle_estacion_19_0.html",
        "http://190.0.152.194:8080/alturas/web/user/altura/24": "detalle_altura_24.html",
        URL_PDF: "20261008-Crecida.pdf",
    }
    pedidos = []

    def descargar(url, intentos=3, espera_s=5, timeout_s=30, proposito=None, hasta=None):
        pedidos.append((url, intentos))
        if url in cortar:
            raise Cortado(url)
        if url in fallar:
            raise red.requests.ConnectionError("caído")
        if url == URL_PDF and pdf is not None:
            return pdf
        return (FIXTURES / paginas[url]).read_bytes()
    return descargar, pedidos


@pytest.fixture
def entorno(tmp_path, monkeypatch):
    data = tmp_path / "data"
    data.mkdir()
    (data / "umbrales.json").write_text(json.dumps(UMBRALES), encoding="utf-8")
    monkeypatch.setattr(lector, "DATA", data)
    monkeypatch.setattr(lector, "datetime", Ahora)

    def correr(**kw):
        descargar, pedidos = red_falsa(**kw)
        monkeypatch.setattr(red, "descargar", descargar)
        codigo = lector.main()
        return codigo, pedidos
    return data, correr


def leer(data, nombre):
    return json.loads((data / nombre).read_text(encoding="utf-8"))


def test_pasada_normal(entorno):
    data, correr = entorno
    codigo, pedidos = correr()
    assert codigo == 0
    a = leer(data, "actual.json")
    assert a["altura_actual"]["valor_m"] == 5.89 and a["nivel"] == "alerta"
    assert a["pronostico"]["url_informe"] == URL_PDF and a["avisos"] == []
    assert len(leer(data, "historial.json")) > 10
    # Las fuentes secundarias se piden con un solo intento.
    assert all(n == 1 for url, n in pedidos if url != CFG["registro_url"])


def test_actual_se_escribe_antes_de_informes_e_historial(entorno):
    data, correr = entorno
    with pytest.raises(Cortado):
        correr(cortar={CFG["informes_indice_url"]})
    a = leer(data, "actual.json")
    assert a["altura_actual"]["valor_m"] == 5.89  # la altura nueva ya quedó publicada
    assert [e["valor_m"] for e in leer(data, "historial.json")] == [5.9, 5.89]  # lecturas actuales


def test_registro_caido_sale_con_3(entorno):
    data, correr = entorno
    codigo, _ = correr(fallar={CFG["registro_url"]})
    assert codigo == 3
    assert "fuente_no_disponible" in leer(data, "actual.json")["avisos"]


def test_umbrales_invalidos_sale_con_4(entorno, capsys):
    data, correr = entorno
    (data / "umbrales.json").write_text(json.dumps({"alerta_m": 40, "evacuacion_m": 68.9}), encoding="utf-8")
    codigo, _ = correr()
    assert codigo == 4
    assert "::error::" in capsys.readouterr().out
    assert leer(data, "actual.json")["nivel"] == "sin_dato"


def test_indice_caido_avisa_pronostico_no_disponible(entorno):
    data, correr = entorno
    codigo, _ = correr(fallar={CFG["informes_indice_url"]})
    assert codigo == 0
    assert leer(data, "actual.json")["avisos"] == ["pronostico_no_disponible"]
    # Cuando vuelve, el aviso se va.
    codigo, _ = correr()
    a = leer(data, "actual.json")
    assert a["avisos"] == [] and a["pronostico"]["vigente"]


def test_pdf_ilegible_se_recuerda_y_no_se_reintenta_cada_pasada(entorno, monkeypatch):
    data, correr = entorno
    codigo, pedidos = correr(pdf=b"%PDF-1.4 roto")
    assert codigo == 0
    assert leer(data, "estado_lector.json")["pdf_fallido"]["url"] == URL_PDF
    assert "pronostico_no_disponible" in leer(data, "actual.json")["avisos"]
    # Pasada siguiente: no vuelve a bajar el PDF.
    codigo, pedidos = correr()
    assert URL_PDF not in [u for u, _ in pedidos]
    assert "pronostico_no_disponible" in leer(data, "actual.json")["avisos"]
    # A las 6 h se reintenta y, si sale bien, se olvida la falla.
    monkeypatch.setattr(Ahora, "now", classmethod(lambda cls, tz=None: datetime(2026, 10, 9, 14, 1, tzinfo=TZ_UY)))
    codigo, pedidos = correr()
    assert URL_PDF in [u for u, _ in pedidos]
    assert "pdf_fallido" not in leer(data, "estado_lector.json")
    assert leer(data, "actual.json")["pronostico"]["url_informe"] == URL_PDF


def test_sin_tiempo_no_pide_fuentes_secundarias(entorno, monkeypatch):
    data, correr = entorno
    monkeypatch.setitem(CFG, "presupuesto_secundarias_s", 0)
    monkeypatch.setattr(lector, "leer_json", _leer_json_con(CFG))
    codigo, pedidos = correr()
    assert [u for u, _ in pedidos] == [CFG["registro_url"]]
    a = leer(data, "actual.json")
    assert a["altura_actual"]["valor_m"] == 5.89
    assert "pronostico_no_disponible" in a["avisos"]


ROTO = '{"esto": no es JSON,'


def test_umbrales_ilegibles_publican_altura_sin_nivel(entorno):
    data, correr = entorno
    (data / "umbrales.json").write_text(ROTO, encoding="utf-8")
    codigo, _ = correr()
    assert codigo == 4
    a = leer(data, "actual.json")
    assert a["altura_actual"]["valor_m"] == 5.89 and a["nivel"] == "sin_dato"
    assert "umbrales_invalidos" in a["avisos"]
    assert (data / "umbrales.json").read_text(encoding="utf-8") == ROTO  # no se pisa


def test_historial_ilegible_no_se_toca_pero_actual_se_escribe(entorno):
    data, correr = entorno
    (data / "historial.json").write_text(ROTO, encoding="utf-8")
    codigo, pedidos = correr()
    assert codigo == 0
    assert leer(data, "actual.json")["altura_actual"]["valor_m"] == 5.89
    assert (data / "historial.json").read_text(encoding="utf-8") == ROTO
    assert not any("estacion/19" in u for u, _ in pedidos)  # ni se piden las páginas de detalle


def test_historial_con_entradas_raras_no_se_toca(entorno):
    data, correr = entorno
    raro = '[{"sin": "fecha"}, 3]'
    (data / "historial.json").write_text(raro, encoding="utf-8")
    codigo, _ = correr()
    assert codigo == 0 and (data / "historial.json").read_text(encoding="utf-8") == raro


def test_actual_y_estado_ilegibles_no_frenan(entorno):
    data, correr = entorno
    (data / "actual.json").write_text(ROTO, encoding="utf-8")
    (data / "estado_lector.json").write_text("[1, 2]", encoding="utf-8")
    codigo, _ = correr()
    assert codigo == 0
    a = leer(data, "actual.json")
    assert a["altura_actual"]["valor_m"] == 5.89 and a["pronostico"]["url_informe"] == URL_PDF


def _leer_json_con(cfg):
    original = lector.leer_json

    def leer_json(ruta, por_defecto=None):
        if Path(ruta).name == "config.json":
            return dict(cfg)
        return original(ruta, por_defecto)
    return leer_json


# ----- PDF en proceso aparte -----

def test_pdf_aislado_lee_el_informe_real():
    d = pdf_aislado.parsear_aislado((FIXTURES / "20261008-Crecida.pdf").read_bytes(), "Paysandú", 60)
    assert d["altura_esperada_m"] == 6.66 and d["caudal_salto_grande_m3s"] == 18000
    assert d["informe_fecha"].isoformat() == "2026-10-08"


def test_pdf_aislado_basura_o_lento_es_ilegible():
    with pytest.raises(pdf_aislado.PdfIlegible):
        pdf_aislado.parsear_aislado(b"<html>no</html>", "Paysandú", 60)
    with pytest.raises(pdf_aislado.PdfIlegible, match="tardó"):
        pdf_aislado.parsear_aislado((FIXTURES / "20261008-Crecida.pdf").read_bytes(), "Paysandú", 0.01)


def test_pdf_aislado_controla_la_salida_del_hijo():
    malo = json.dumps({"informe_fecha": "2026-10-08", "altura_esperada_m": 1e9, "texto": "x" * 5000,
                       "caudal_salto_grande_m3s": -3})
    d = pdf_aislado._validar_salida(malo.encode())
    assert d["altura_esperada_m"] is None and d["texto"] is None and d["caudal_salto_grande_m3s"] is None
    with pytest.raises(pdf_aislado.PdfIlegible):
        pdf_aislado._validar_salida(b"no es json")
