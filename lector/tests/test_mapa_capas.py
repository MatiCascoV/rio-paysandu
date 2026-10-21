"""Capas por nivel: nombres, tamizado, polígonos y GeoJSON."""
import json

import pytest

np = pytest.importorskip("numpy")
pytest.importorskip("scipy")
pytest.importorskip("shapely")
pytest.importorskip("rasterio")
pytest.importorskip("pyproj")

from mapa import capas as C  # noqa: E402


@pytest.mark.parametrize("h, nombre", [(6.70, "agua/0670.json"), (4.0, "agua/0400.json"),
                                       (10.5, "agua/1050.json"), (9.12, "agua/0912.json"),
                                       (4.1000000001, "agua/0410.json")])
def test_nombre_capa(h, nombre):
    assert C.nombre_capa(h) == nombre


def test_alturas_del_contrato():
    hs = C.alturas(4.0, 10.5, 0.1)
    assert len(hs) == 66 and hs[0] == 4.0 and hs[-1] == 10.5
    assert all(abs(b - a - 0.1) < 1e-9 for a, b in zip(hs, hs[1:]))
    with pytest.raises(ValueError):
        C.alturas(4.0, 10.55, 0.1)


def test_tamizar_saca_manchas_y_rellena_islas_chicas():
    moj = np.zeros((20, 20), bool)
    moj[2:12, 2:12] = True
    moj[6, 6] = False          # isla seca de 1 celda → se rellena
    moj[16, 16] = True         # mancha de 1 celda → se saca
    excl = np.zeros_like(moj)
    out = C.tamizar(moj, excl, 4)
    assert out[6, 6] and not out[16, 16]
    assert out[2:12, 2:12].all()


def test_tamizar_conserva_anidado():
    rng = np.random.default_rng(3)
    campo = rng.random((40, 40))
    excl = np.zeros((40, 40), bool); excl[:, :2] = True
    anterior = None
    for u in np.linspace(0.2, 0.9, 8):
        capa = C.tamizar((campo < u) & ~excl, excl, 6)
        if anterior is not None:
            assert not (anterior & ~capa).any()
        anterior = capa


def test_poligonizar_y_reproyectar_da_multipolygon_valido_redondeado():
    from rasterio.transform import from_origin
    moj = np.zeros((30, 30), bool)
    moj[5:20, 5:25] = True
    moj[10:13, 10:13] = False      # hueco
    moj[25:28, 2:5] = True         # segunda parte
    t = from_origin(396000.0, 6424000.0, 2.0, 2.0)
    g = C.poligonizar(moj, t, 1.5)
    assert g.is_valid and g.geom_type == "MultiPolygon" and len(g.geoms) == 2
    assert abs(g.area - moj.sum() * 4.0) < 0.05 * moj.sum() * 4.0
    g4 = C.a_4326(g, "EPSG:5382", 5)
    assert g4.is_valid
    x0, y0, x1, y1 = g4.bounds
    assert -58.2 < x0 < x1 < -58.0 and -32.4 < y0 < y1 < -32.2   # [lon, lat]
    fc = C.feature_collection(g4, {"altura_m": 6.7}, 5)
    txt = C.serializar(fc).decode()
    for n in json.loads(txt)["features"][0]["geometry"]["coordinates"][0][0]:
        assert round(n[0], 5) == n[0] and round(n[1], 5) == n[1]


def test_capa_vacia():
    from rasterio.transform import from_origin
    g = C.poligonizar(np.zeros((5, 5), bool), from_origin(0, 0, 1, 1), 1.0)
    fc = C.feature_collection(C.a_4326(g, "EPSG:5382", 5), {"altura_m": 4.0}, 5)
    assert fc["features"][0]["geometry"] == {"type": "MultiPolygon", "coordinates": []}


def test_serializar_es_determinista():
    a = C.serializar({"b": 1, "a": [1.5, "ñ"]})
    assert a == C.serializar({"b": 1, "a": [1.5, "ñ"]})
    assert "ñ" in a.decode("utf-8")


@pytest.mark.parametrize("h, capa", [(3.99, None), (4.0, 4.0), (6.58, 6.6), (9.12, 9.2), (6.6, 6.6),
                                     (6.6000001, 6.6), (6.61, 6.7), (10.5, 10.5), (12.0, 10.5)])
def test_capa_para_redondea_hacia_arriba(h, capa):
    from mapa.pipeline import capa_para
    assert capa_para(h, 4.0, 10.5, 0.1) == capa


def test_tamizar_rellena_huecos_secos_mas_grandes_sin_sacar_agua():
    moj = np.ones((40, 40), bool)
    moj[5:10, 5:10] = False          # hueco seco de 25 celdas
    moj[20:22, 20:22] = False        # hueco seco de 4 celdas
    excluir = np.zeros_like(moj)
    out = C.tamizar(moj, excluir, 3, 30)
    assert out.all()                 # los dos huecos (< 30) quedan mojados
    out = C.tamizar(moj, excluir, 3, 10)
    assert not out[5:10, 5:10].any() and out[20:22, 20:22].all()
    # anidado: con más umbral seco, siempre más (o igual) agua
    assert (C.tamizar(moj, excluir, 3, 10) <= C.tamizar(moj, excluir, 3, 30)).all()


def test_poligonizar_con_buffer_no_pierde_celdas_mojadas():
    from rasterio.transform import from_origin
    from shapely.geometry import box
    rng = np.random.default_rng(3)
    moj = np.zeros((80, 80), bool)
    for _ in range(60):  # bordes irregulares
        f, c = rng.integers(10, 70, 2); moj[f - 4:f + 4, c - 6:c + 6] = True
    t = from_origin(0, 160, 2, 2)
    g = C.poligonizar(moj, t, 4.0, 4.0)  # buffer >= simplify: garantía de no perder agua
    assert g.is_valid
    for f, c in zip(*np.nonzero(moj)):
        x, y = t @ (c + 0.5, f + 0.5)
        assert g.contains(box(x - 0.9, y - 0.9, x + 0.9, y + 0.9).centroid)
    sin_buffer = C.poligonizar(moj, t, 4.0, 0.0)
    assert g.area >= sin_buffer.area


def test_a_4326_recorta_a_los_limites():
    from shapely.geometry import box
    from pyproj import Transformer
    t = Transformer.from_crs("EPSG:4326", "EPSG:5382", always_xy=True)
    x0, y0 = t.transform(-58.10, -32.30)
    g = C.solo_poligonos(box(x0 - 5000, y0 - 5000, x0 + 5000, y0 + 5000))
    lim = [[-32.31, -58.11], [-32.29, -58.09]]
    out = C.a_4326(g, "EPSG:5382", 5, lim)
    b = out.bounds
    assert b[0] >= -58.11 - 1e-9 and b[2] <= -58.09 + 1e-9 and b[1] >= -32.31 - 1e-9 and b[3] <= -32.29 + 1e-9
