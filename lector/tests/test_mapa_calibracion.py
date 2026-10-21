"""Calibración de δ, curvas de Dinagua y descargas con caché (todo sin internet)."""
import json

import pytest

np = pytest.importorskip("numpy")
pytest.importorskip("scipy")

from mapa import calibracion as K  # noqa: E402
from mapa.llegada import llegada_cm  # noqa: E402

DELTAS = list(range(-20, 121, 2))


def test_recupera_el_desfase_de_un_terreno_sintetico():
    """Terreno = cota local + 0,66: la 'curva real' a 7,00 m local es MDT ≤ 7,66."""
    rng = np.random.default_rng(5)
    col = np.arange(200)[None, :].repeat(60, 0)
    dem = (4.0 + 0.03 * col + rng.normal(0, 0.02, (60, 200))).astype("float32")
    cauce = np.zeros(dem.shape, bool); cauce[:, :3] = True
    lleg = llegada_cm(dem, cauce, 360, 1200, 2)
    curva = (dem <= 7.66) & ~cauce
    dom = ~cauce
    ious = K.barrido(lleg[dom], curva[dom], 7.00, DELTAS)
    mejor = DELTAS[int(np.nanargmax(ious))] / 100
    assert abs(mejor - 0.66) <= 0.02
    assert max(ious) > 0.95


def test_iou_basico():
    a = np.array([1, 1, 0, 0], bool); b = np.array([1, 0, 1, 0], bool); d = np.ones(4, bool)
    assert K.iou(a, b, d) == pytest.approx(1 / 3)
    assert K.iou(a, b, np.array([1, 1, 0, 0], bool)) == pytest.approx(0.5)


def _tabla(centros, pico=0.8):
    d = np.array(DELTAS) / 100
    return {k: list(pico - 2 * np.abs(d - c)) for k, c in centros.items()}


def test_ajustar_cumple_con_curvas_coherentes():
    t = _tabla({"2025-07": 0.66, "2009-11": 0.62, "2015-12": 0.70, "2017-06": 0.60, "2019-01": 0.68})
    r = K.ajustar(t, DELTAS, "2025-07", ["2009-11", "2015-12", "2017-06", "2019-01"], 0.70, 0.10)
    assert r["delta_m"] == 0.66
    assert r["criterio_cumplido"] is True
    assert r["dispersion_delta_m"] <= 0.10


def test_ajustar_no_cumple_si_delta_inestable():
    t = _tabla({"2025-07": 0.66, "2009-11": 0.20, "2015-12": 1.0, "2017-06": 0.30, "2019-01": 0.95})
    r = K.ajustar(t, DELTAS, "2025-07", ["2009-11", "2015-12", "2017-06", "2019-01"], 0.70, 0.10)
    assert r["criterio_cumplido"] is False


def test_ajustar_no_cumple_si_iou_bajo():
    t = _tabla({"2025-07": 0.66, "2009-11": 0.66, "2015-12": 0.66, "2017-06": 0.66, "2019-01": 0.66}, pico=0.55)
    r = K.ajustar(t, DELTAS, "2025-07", ["2009-11", "2015-12", "2017-06", "2019-01"], 0.70, 0.10)
    assert r["cumple_iou"] is False and r["criterio_cumplido"] is False


def test_ajustar_falla_si_falta_una_curva():
    t = _tabla({"2025-07": 0.66})
    with pytest.raises(ValueError):
        K.ajustar(t, DELTAS, "2025-07", ["2009-11"], 0.70, 0.10)


def test_error_de_borde():
    dom = np.ones((20, 20), bool)
    a = np.zeros((20, 20), bool); a[:, :10] = True
    b = np.zeros((20, 20), bool); b[:, :12] = True
    assert K.error_borde_m(a, b, dom, 2.0) == pytest.approx(4.0)


def test_leer_curvas_de_dinagua():
    pytest.importorskip("shapely")
    from mapa.curvas import leer_curvas
    cuad = [[[[-58.10, -32.30], [-58.09, -32.30], [-58.09, -32.29], [-58.10, -32.29], [-58.10, -32.30]]]]
    cri = {"type": "FeatureCollection", "crs": {"type": "name", "properties": {"name": "urn:ogc:def:crs:EPSG::4326"}},
           "features": [
               {"type": "Feature", "geometry": {"type": "MultiPolygon", "coordinates": cuad},
                "properties": {"nombre": "PA-PSD_CRI-dic2015", "curso": "Río Uruguay", "fecha_evento": "2015-12-10Z",
                               "cota_local": 9.12}},
               {"type": "Feature", "geometry": {"type": "MultiPolygon", "coordinates": cuad},
                "properties": {"nombre": "otro", "curso": "Arroyo Sacra", "fecha_evento": "2015-12-10Z", "cota_local": 9.0}}]}
    tr = {"type": "FeatureCollection", "features": [
        {"type": "Feature", "geometry": {"type": "MultiPolygon", "coordinates": cuad},
         "properties": {"nombre": "PA-PSD_Tr100", "curso": "Río Uruguay", "cota_local": 9.49, "sigla_tipo_curva": "TR 100    "}},
        {"type": "Feature", "geometry": {"type": "MultiPolygon", "coordinates": cuad},
         "properties": {"nombre": "PA-PSD_CMP", "curso": "Río Uruguay", "cota_local": 14.07, "sigla_tipo_curva": "CMP"}}]}
    cs = leer_curvas([json.dumps(cri), json.dumps(tr)], "Río Uruguay")
    assert [(c.clave, c.tipo, c.altura_m) for c in cs] == [("2015-12", "crecida", 9.12), ("Tr100", "diseno", 9.49)]
    assert cs[0].nombre == "Crecida de diciembre de 2015" and cs[0].fecha == "2015-12-10"
    assert cs[0].geom.bounds[0] < -58  # [lon, lat]


def test_listar_indice_apache():
    from mapa.descarga import listar_indice_apache
    html = ('<a href="?C=N;O=D">Name</a><a href="/descargas/">x</a><a href="P15B1P6_MDT_Remesa_09_PSD.tif">'
            '</a><a href="P15B1P8_MDT_Remesa_09_PSD.tif">x</a><a href="leeme.txt">')
    assert listar_indice_apache(html) == ["P15B1P6_MDT_Remesa_09_PSD.tif", "P15B1P8_MDT_Remesa_09_PSD.tif"]


def test_cache_usa_sha256_y_no_vuelve_a_bajar(tmp_path, monkeypatch):
    requests = pytest.importorskip("requests")
    from mapa.descarga import Cache, ErrorDescarga

    llamadas = []

    class Resp:
        def __init__(self, contenido, status=200, largo=None):
            self.status_code = status
            self._c = contenido
            self.headers = {"Content-Length": str(largo if largo is not None else len(contenido))}

        def iter_content(self, n):
            yield self._c

        def __enter__(self):
            return self

        def __exit__(self, *a):
            return False

    respuestas = {"http://x/a.tif": Resp(b"hola"), "http://x/corta.tif": Resp(b"ho", largo=10),
                  "http://x/404.tif": Resp(b"", status=404)}

    def falso_get(url, **kw):
        llamadas.append(url)
        return respuestas[url]

    monkeypatch.setattr(requests, "get", falso_get)
    monkeypatch.setattr("time.sleep", lambda s: None)
    c = Cache(tmp_path)
    r = c.obtener("http://x/a.tif")
    assert r.read_bytes() == b"hola"
    assert Cache(tmp_path).obtener("http://x/a.tif") == r      # segunda vez: desde la caché
    assert llamadas.count("http://x/a.tif") == 1
    man = json.loads((tmp_path / "manifiesto.json").read_text())
    assert man["http://x/a.tif"]["sha256"] == "b221d9dbb083a7f33428d7c2a3c3198ae925614d70210e28716ccaa7cd4ddb79"
    r.write_bytes(b"chau")                                       # corrupción → se vuelve a bajar
    assert Cache(tmp_path).obtener("http://x/a.tif").read_bytes() == b"hola"
    with pytest.raises(ErrorDescarga):
        c.obtener("http://x/corta.tif", reintentos=1)
    with pytest.raises(ErrorDescarga):
        c.obtener("http://x/404.tif", reintentos=1)
