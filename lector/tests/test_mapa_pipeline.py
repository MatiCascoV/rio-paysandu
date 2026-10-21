"""Salida completa con un terreno sintético (sin internet): archivos, índice y validaciones."""
import copy
import hashlib
import json

import pytest

np = pytest.importorskip("numpy")
pytest.importorskip("scipy")
pytest.importorskip("shapely")
pytest.importorskip("rasterio")
pytest.importorskip("pyproj")

from mapa import validar as V  # noqa: E402
from mapa.llegada import llegada_cm  # noqa: E402
from mapa.pipeline import armar_indice, generar  # noqa: E402
from mapa.terreno import Grilla  # noqa: E402

CFG = {
    "cero": "Local", "resolucion_m": 2.0, "min_m": 4.0, "max_m": 4.6, "paso_m": 0.1, "margen_m": 0.5,
    "limites": [[-32.40, -58.20], [-32.20, -57.95]],
    "mdt_urbano": {"fecha_vuelo": "2017-10"},
    "curvas": {"simplify_grados": 0.00002},
    "capas": {"sieve_m2": 16, "simplify_m": 1.5, "buffer_m": 2.5, "decimales": 5, "tolerancia_anidado": 0.01,
              "tope_capa_bytes": 200000, "tope_base_bytes": 200000, "tope_total_bytes": 2000000},
    "fuentes": ["© colaboradores de OpenStreetMap, ODbL"],
    "llegada": {"cuantizacion_cm": 2, "min_cm": 360, "max_cm": 1200},
}
BASE = {"type": "FeatureCollection", "features": [], "lugares": [], "caja": [-58.2, -32.4, -57.95, -32.2]}


@pytest.fixture
def salida(tmp_path):
    grilla = Grilla("EPSG:5382", 396000.0, 6424000.0, 2.0, 60, 40)
    rng = np.random.default_rng(0)
    col = np.arange(60)[None, :].repeat(40, 0)
    dem = (3.0 + 0.05 * col + rng.normal(0, 0.05, (40, 60))).astype("float32")
    cauce = np.zeros(dem.shape, bool); cauce[:, :4] = True
    lleg = llegada_cm(dem, cauce, 360, 1200, 2)
    carpeta = tmp_path / "salida"
    carpeta.mkdir()
    entradas, geoms, base_ent, refs, areas, errores, extra = generar(CFG, carpeta, grilla, lleg, cauce, 0.4, BASE, [])
    assert errores == []
    ind = armar_indice(CFG, "2026-10-19T18:00:00-03:00", False, 0.4, 0.75, base_ent, entradas, refs)
    (carpeta / "indice.json").write_text(json.dumps(ind), encoding="utf-8")
    return carpeta, ind, geoms, areas


def test_archivos_y_nombres(salida):
    carpeta, ind, _, _ = salida
    nombres = sorted(p.name for p in (carpeta / "agua").iterdir())
    assert nombres == ["0400.json", "0410.json", "0420.json", "0430.json", "0440.json", "0450.json", "0460.json"]
    assert (carpeta / "base.json").exists() and (carpeta / "curvas").is_dir()


def test_indice_conforme_al_contrato(salida):
    carpeta, ind, _, _ = salida
    assert V.validar_indice(ind) == []
    assert V.validar_archivos(carpeta, ind) == []
    assert ind["cero"] == "Local" and ind["validado"] is False
    assert [c["altura_m"] for c in ind["capas"]] == [4.0, 4.1, 4.2, 4.3, 4.4, 4.5, 4.6]
    for c in ind["capas"]:
        datos = (carpeta / c["archivo"]).read_bytes()
        assert c["bytes"] == len(datos) and c["sha256"] == hashlib.sha256(datos).hexdigest()


def test_capas_validas_crecientes_y_anidadas(salida):
    carpeta, ind, geoms, areas = salida
    for c in ind["capas"]:
        fc = json.loads((carpeta / c["archivo"]).read_text(encoding="utf-8"))
        assert V.validar_capa(fc, c["altura_m"], ind["limites"]) == []
    a = [areas[c["archivo"]]["area_ha"] for c in ind["capas"]]
    assert a == sorted(a) and a[-1] > a[0] > 0
    assert V.validar_anidado(geoms, 0.01) == []


def test_sin_cauce_normal(salida):
    """La capa no incluye el cauce (columnas 0-3 de la grilla sintética)."""
    from pyproj import Transformer
    from shapely.geometry import Point, shape
    carpeta, ind, _, _ = salida
    t = Transformer.from_crs("EPSG:5382", "EPSG:4326", always_xy=True)
    lon, lat = t.transform(396000.0 + 3.0, 6424000.0 - 40.0)      # centro del cauce
    g = shape(json.loads((carpeta / "agua/0460.json").read_text())["features"][0]["geometry"])
    assert not g.contains(Point(lon, lat))


# ---- validaciones que tienen que fallar ----

def test_indice_con_cero_distinto_falla(salida):
    _, ind, _, _ = salida
    mal = copy.deepcopy(ind); mal["cero"] = "Oficial"
    assert any("cero" in e for e in V.validar_indice(mal))


def test_indice_con_hueco_en_capas_falla(salida):
    _, ind, _, _ = salida
    mal = copy.deepcopy(ind); del mal["capas"][3]
    assert V.validar_indice(mal)


def test_indice_con_nombre_mal_falla(salida):
    _, ind, _, _ = salida
    mal = copy.deepcopy(ind); mal["capas"][2]["archivo"] = "agua/420.json"
    assert any("archivo" in e for e in V.validar_indice(mal))


def test_indice_desordenado_falla(salida):
    _, ind, _, _ = salida
    mal = copy.deepcopy(ind); mal["capas"][1], mal["capas"][2] = mal["capas"][2], mal["capas"][1]
    assert V.validar_indice(mal)


def test_indice_sin_clave_falla(salida):
    _, ind, _, _ = salida
    mal = copy.deepcopy(ind); del mal["modelo"]
    assert V.validar_indice(mal)


def test_archivo_modificado_falla(salida):
    carpeta, ind, _, _ = salida
    ruta = carpeta / ind["capas"][0]["archivo"]
    ruta.write_bytes(ruta.read_bytes() + b" ")
    errores = V.validar_archivos(carpeta, ind)
    assert any("bytes" in e for e in errores) and any("sha256" in e for e in errores)


def test_tope_de_bytes_falla():
    assert V.validar_bytes({"agua/0400.json": 10, "base.json": 5}, 100, 100, 1000) == []
    assert V.validar_bytes({"agua/0400.json": 101}, 100, 100, 1000)
    assert V.validar_bytes({"base.json": 101}, 1000, 100, 10000)
    assert V.validar_bytes({"agua/0400.json": 90, "agua/0410.json": 90}, 100, 100, 150)


def test_geometria_invalida_falla():
    moño = {"type": "FeatureCollection", "features": [{"type": "Feature", "properties": {"altura_m": 5.0},
            "geometry": {"type": "MultiPolygon", "coordinates": [[[[-58.1, -32.3], [-58.09, -32.29],
                                                                    [-58.1, -32.29], [-58.09, -32.3], [-58.1, -32.3]]]]}}]}
    assert any("inválida" in e for e in V.validar_capa(moño, 5.0, [[-32.4, -58.2], [-32.2, -57.9]]))


def test_capa_fuera_de_limites_y_properties_mal_falla():
    fc = {"type": "FeatureCollection", "features": [{"type": "Feature", "properties": {"altura_m": 5.1},
          "geometry": {"type": "MultiPolygon", "coordinates": [[[[-57.0, -32.3], [-56.9, -32.3],
                                                                 [-56.9, -32.2], [-57.0, -32.3]]]]}}]}
    errores = V.validar_capa(fc, 5.0, [[-32.4, -58.2], [-32.2, -57.9]])
    assert any("límites" in e for e in errores) and any("properties" in e for e in errores)


def test_anidado_roto_falla():
    from shapely.geometry import MultiPolygon, box
    a = MultiPolygon([box(0, 0, 2, 2)])
    b = MultiPolygon([box(1, 0, 3, 2)])
    assert V.validar_anidado([a, b], 0.01)
    assert V.validar_anidado([b.intersection(a), b], 0.01) == []


def test_limites_computo_tiene_que_contener_a_limites():
    from mapa.pipeline import ErrorPipeline, limites_computo
    lim = [[-32.365, -58.150], [-32.240, -58.030]]
    assert limites_computo({"limites": lim}) == lim
    grande = [[-32.38, -58.17], [-32.215, -58.005]]
    assert limites_computo({"limites": lim, "limites_computo": grande}) == grande
    with pytest.raises(ErrorPipeline):
        limites_computo({"limites": lim, "limites_computo": [[-32.30, -58.17], [-32.215, -58.005]]})
