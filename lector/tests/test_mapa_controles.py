"""Controles que frenan la publicación (revisión de código I3, I4, M2/M3). Sin internet."""
import copy
import json
from pathlib import Path

import pytest

np = pytest.importorskip("numpy")
pytest.importorskip("scipy")
pytest.importorskip("shapely")
pytest.importorskip("rasterio")
pytest.importorskip("pyproj")

from mapa import calibracion as K  # noqa: E402
from mapa import pipeline as P  # noqa: E402
from mapa import validar as V  # noqa: E402
from mapa.curvas import Curva  # noqa: E402
from mapa.llegada import NUNCA, llegada_cm, umbral_en_grilla  # noqa: E402
from mapa.pipeline import ErrorPipeline  # noqa: E402
from mapa.terreno import SIN_DATO, URBANO, Grilla  # noqa: E402

RAIZ = Path(__file__).resolve().parents[2]
CONFIG = RAIZ / "lector" / "mapa" / "config.json"
ASSETS = RAIZ / "app" / "assets" / "mapa"
X0, Y0 = 396000.0, 6424000.0          # cerca de Paysandú en EPSG:5382


def a4326(x, y):
    from pyproj import Transformer
    return Transformer.from_crs("EPSG:5382", "EPSG:4326", always_xy=True).transform(x, y)


def limites_de(grilla):
    x0, y0, x1, y1 = grilla.bounds
    o, s = a4326(x0, y0); e, n = a4326(x1, y1)
    o2, n2 = a4326(x0, y1); e2, s2 = a4326(x1, y0)
    return [[round(max(s, s2), 5), round(max(o, o2), 5)], [round(min(n, n2), 5), round(min(e, e2), 5)]]


def caja_cols(c0, c1, alto):
    """Polígono EPSG:4326 de las columnas c0..c1-1 de la grilla de prueba (todas las filas)."""
    from shapely.geometry import Polygon
    pts = [(X0 + 2 * c0, Y0), (X0 + 2 * c1, Y0), (X0 + 2 * c1, Y0 - 2 * alto), (X0 + 2 * c0, Y0 - 2 * alto)]
    return Polygon([a4326(x, y) for x, y in pts])


def escribir_cfg(tmp_path, cambio):
    cfg = json.loads(CONFIG.read_text(encoding="utf-8"))
    for k, v in cambio.items():
        if isinstance(v, dict) and isinstance(cfg.get(k), dict):
            cfg[k] = {**cfg[k], **v}
        elif v is None:
            cfg.pop(k, None)
        else:
            cfg[k] = v
    r = tmp_path / "c.json"
    r.write_text(json.dumps(cfg), encoding="utf-8")
    return r


# ---------------------------------------------------------------- I4: grilla de cuantización

def test_umbral_en_grilla_exacto_y_fallas():
    assert umbral_en_grilla(400, 360, 2, 1200) == 400
    assert umbral_en_grilla(1200, 360, 2, 1200) == 1200
    with pytest.raises(ValueError, match="fuera de la grilla"):
        umbral_en_grilla(401, 360, 2, 1200)
    with pytest.raises(ValueError, match="max_cm"):
        umbral_en_grilla(1202, 360, 2, 1200)
    with pytest.raises(ValueError, match="min_cm"):
        umbral_en_grilla(358, 360, 2, 1200)
    with pytest.raises(ValueError):
        umbral_en_grilla(400, 360, 0, 1200)


def test_umbral_en_grilla_redondea_hacia_arriba_las_curvas():
    assert umbral_en_grilla(835 + 66, 360, 2, 1200, redondear=True) == 902   # 8,35 m con δ 0,66
    assert umbral_en_grilla(401, 360, 5, 1200, redondear=True) == 405
    assert umbral_en_grilla(900, 360, 2, 1200, redondear=True) == 900
    with pytest.raises(ValueError, match="max_cm"):                         # subir no puede pasar max_cm
        umbral_en_grilla(1199, 360, 2, 1199, redondear=True)


def test_llegada_fuera_de_la_grilla_moja_menos():
    """Por qué importa I4: con t impar, `llegada <= t` es la capa de t-1 (menos agua)."""
    dem = np.array([[0.0, 3.61, 3.63, 3.65]], dtype="float32")
    cauce = np.array([[True, False, False, False]])
    lleg = llegada_cm(dem, cauce, 360, 400, 2)
    assert int((lleg <= 363).sum()) == 2          # la celda de 3,63 m quedaría seca con t = 363
    t = umbral_en_grilla(363, 360, 2, 400, redondear=True)
    assert t == 364 and int((lleg <= t).sum()) == 3


def test_barrido_con_umbral_evalua_la_curva_impar_hacia_arriba():
    lleg = np.array([660, 662, 664, 666, 668], np.int32)
    curva = np.array([1, 1, 1, 1, 0], bool)
    sube = lambda t: umbral_en_grilla(t, 360, 2, 1200, redondear=True)  # noqa: E731
    # h = 6,65 con δ 0: sin redondeo se evalúa en 665 (≡ 664) y pierde la celda de 666
    assert K.barrido(lleg, curva, 6.65, [0]) == [pytest.approx(3 / 4)]
    assert K.barrido(lleg, curva, 6.65, [0], sube) == [1.0]


def test_config_real_cumple_la_grilla_para_capas_curvas_y_deltas():
    cfg = P.cargar_config(CONFIG)
    L = cfg["llegada"]
    # curvas de Dinagua de la salida actual (5 crecidas) + Tr10 y Tr100 (06 §4): con cualquier
    # δ del barrido entran en la grilla redondeando hacia arriba, sin pasar max_cm
    alturas = [7.74, 9.49]
    if (ASSETS / "indice.json").exists():
        alturas += [r["altura_m"] for r in json.loads((ASSETS / "indice.json").read_text(encoding="utf-8"))["referencias"]]
    for h in alturas:
        for d in P.deltas_cm(cfg["calibracion"]):
            t = umbral_en_grilla(int(round(h * 100)) + d, L["min_cm"], L["cuantizacion_cm"], L["max_cm"], redondear=True)
            assert 0 <= t - (int(round(h * 100)) + d) < L["cuantizacion_cm"]


@pytest.mark.parametrize("cambio, texto", [
    ({"llegada": {"min_cm": 361}}, "fuera de la grilla"),
    ({"llegada": {"max_cm": 1100}}, "max_cm"),                          # 10,50 + 1,20 = 11,70 m
    ({"calibracion": {"delta_paso": 0.01}}, "fuera de la grilla"),      # δ impares
    ({"calibracion": {"delta_min": -0.70}}, "min_cm"),                  # 4,00 - 0,70 < 3,60
    ({"llegada": {"cuantizacion_cm": 2.0}}, "entero"),
    ({"llegada": {"cuantizacion_cm": 3}}, "fuera de la grilla"),
    ({"sin_dato": None}, "sin_dato"),
    ({"sin_dato": {"max_fraccion_tierra_uy": 1.5}}, "sin_dato"),
])
def test_cargar_config_rechaza_umbrales_inseguros(tmp_path, cambio, texto):
    with pytest.raises(ErrorPipeline, match=texto):
        P.cargar_config(escribir_cfg(tmp_path, cambio))


# ---------------------------------------------------------------- calibrar con curvas impares

GRILLA = Grilla("EPSG:5382", X0, Y0, 2.0, 60, 40)


def _terreno():
    col = np.arange(60)[None, :].repeat(40, 0)
    dem = (3.0 + 0.05 * col).astype("float32")            # columna c: 3,00 + 0,05·c m
    cauce = np.zeros(dem.shape, bool); cauce[:, :4] = True
    return dem, cauce, llegada_cm(dem, cauce, 360, 1200, 2)


def _curvas(alturas_y_cols):
    claves = ["2025-07", "2017-06", "2009-11"]
    return [Curva(k, "crecida", k, h, "2000-01-01", caja_cols(4, c1, 40), k)
            for k, (h, c1) in zip(claves, alturas_y_cols)]


CFG_CAL = {"min_m": 4.0, "llegada": {"cuantizacion_cm": 2, "min_cm": 360, "max_cm": 1200},
           "calibracion": {"delta_min": -0.20, "delta_max": 1.20, "delta_paso": 0.02, "fija": "2025-07",
                           "validacion": ["2017-06", "2009-11"], "iou_min": 0.7, "estabilidad_m": 0.1,
                           "solo_mdt_urbano": True}}


def test_calibrar_sube_las_curvas_impares_a_la_grilla():
    dem, cauce, lleg = _terreno()
    fuente = np.full(dem.shape, URBANO, np.uint8)
    # curvas "reales" con δ = 0,40: mojado si 3 + 0,05·c ≤ h + 0,40
    curvas = _curvas([(4.35, 36), (4.51, 39), (4.73, 43)])
    res = P.calibrar(CFG_CAL, GRILLA, lleg, fuente, cauce, curvas)
    assert res["delta_m"] == pytest.approx(0.40, abs=0.02)
    d_cm = int(round(res["delta_m"] * 100))
    for clave, h in (("2025-07", 4.35), ("2017-06", 4.51), ("2009-11", 4.73)):
        crudo = int(round(h * 100)) + d_cm
        assert res["curvas"][clave]["umbral_cm"] == crudo + (crudo - 360) % 2   # impar → +1 cm
        assert res["curvas"][clave]["curva_cubierta"] == 1.0


def test_calibrar_falla_si_una_curva_pasa_max_cm():
    dem, cauce, lleg = _terreno()
    fuente = np.full(dem.shape, URBANO, np.uint8)
    cfg = copy.deepcopy(CFG_CAL); cfg["llegada"]["max_cm"] = 500             # 4,73 + 1,20 > 5,00
    with pytest.raises(ErrorPipeline, match="max_cm"):
        P.calibrar(cfg, GRILLA, lleg, fuente, cauce, _curvas([(4.35, 36), (4.51, 39), (4.73, 43)]))


# ---------------------------------------------------------------- generar: umbral y áreas (I3 b, I4)

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


def _generar(tmp_path, lleg, cauce, delta, cfg=CFG):
    carpeta = tmp_path / "s"
    if carpeta.exists():
        import shutil; shutil.rmtree(carpeta)
    carpeta.mkdir()
    return P.generar(cfg, carpeta, GRILLA, lleg, cauce, delta, BASE, [])


def test_generar_rechaza_delta_fuera_de_la_grilla_y_umbral_arriba_de_max_cm(tmp_path):
    _, cauce, lleg = _terreno()
    with pytest.raises(ErrorPipeline, match="fuera de la grilla"):
        _generar(tmp_path, lleg, cauce, 0.41)
    cfg = copy.deepcopy(CFG); cfg["llegada"]["max_cm"] = 480                 # 4,60 + 0,40 = 5,00 m
    with pytest.raises(ErrorPipeline, match="max_cm"):
        _generar(tmp_path, lleg, cauce, 0.40, cfg)
    *_, errores, _ = _generar(tmp_path, lleg, cauce, 0.40)
    assert errores == []


def test_generar_frena_la_capa_max_vacia(tmp_path):
    _, cauce, _ = _terreno()
    lleg = np.full(cauce.shape, NUNCA, np.int32); lleg[cauce] = 360        # todo pared: nada se moja
    *_, errores, _ = _generar(tmp_path, lleg, cauce, 0.40)
    assert any("4.60 m (max_m) está vacía" in e for e in errores)
    assert any("no crece" in e for e in errores)


def test_generar_frena_si_el_area_no_crece(tmp_path):
    _, cauce, _ = _terreno()
    lleg = np.full(cauce.shape, NUNCA, np.int32); lleg[cauce] = 360
    lleg[:, 4:20] = 400                                                     # se moja todo a 4,00 y no crece más
    *_, errores, _ = _generar(tmp_path, lleg, cauce, 0.40)
    assert [e for e in errores if "no crece" in e] and not [e for e in errores if "vacía" in e]


def test_validar_areas():
    hs = [4.0, 4.1, 4.2]
    assert V.validar_areas(hs, [10.0, 10.0, 30.0], False) == []           # igual entre dos capas: se acepta
    assert any("baja" in e for e in V.validar_areas(hs, [10.0, 40.0, 30.0], False))
    assert any("no crece" in e for e in V.validar_areas(hs, [10.0, 10.0, 10.0], False))
    assert any("vacía" in e for e in V.validar_areas(hs, [0.0, 0.0, 0.0], False))
    assert any("vacía" in e for e in V.validar_areas(hs, [1.0, 2.0, 3.0], True))   # geometría publicada vacía


# ---------------------------------------------------------------- I3 c: sin dato en tierra uruguaya

def _orillas(alto=30, ancho=40):
    """Río en las columnas 10..14 (brazo más ancho al norte), Argentina sin dato al oeste."""
    cauce = np.zeros((alto, ancho), bool); cauce[:, 10:15] = True; cauce[:3, 15:18] = True
    sin_dato = np.zeros_like(cauce); sin_dato[:, :10] = True                 # la otra orilla
    return cauce, sin_dato


def test_fraccion_sin_dato_cuenta_solo_la_tierra_al_este_del_cauce():
    cauce, sin_dato = _orillas()
    tierra = ~cauce
    dentro = np.ones_like(cauce)
    r = P.fraccion_sin_dato_este(sin_dato, tierra, cauce, dentro)
    assert r["celdas_sin_dato_este"] == 0                                     # Argentina no cuenta
    assert r["celdas_tierra_este"] == 3 * 22 + 27 * 25
    sin_dato[20:30, 30:40] = True                                             # 100 celdas uruguayas sin dato
    r = P.fraccion_sin_dato_este(sin_dato, tierra, cauce, dentro)
    assert r["celdas_sin_dato_este"] == 100
    assert r["fraccion"] == pytest.approx(100 / (3 * 22 + 27 * 25), abs=1e-6)
    fuera = dentro.copy(); fuera[20:30, :] = False                            # fuera de limites no cuenta
    assert P.fraccion_sin_dato_este(sin_dato, tierra, cauce, fuera)["celdas_sin_dato_este"] == 0


def test_fraccion_sin_dato_filas_sin_cauce_y_sin_cauce_falla():
    cauce, sin_dato = _orillas()
    cauce[10:20, :] = False                                                  # filas sin cauce: orilla interpolada
    r = P.fraccion_sin_dato_este(sin_dato, ~cauce, cauce, np.ones_like(cauce))
    assert r["celdas_sin_dato_este"] == 0
    with pytest.raises(ErrorPipeline, match="cauce"):
        P.fraccion_sin_dato_este(sin_dato, ~cauce, np.zeros_like(cauce), np.ones_like(cauce))


def test_control_sin_dato_frena_con_el_umbral_de_la_config():
    g = Grilla("EPSG:5382", X0, Y0, 2.0, 80, 60)
    cfg = {"limites": limites_de(g), "sin_dato": {"max_fraccion_tierra_uy": 0.05}}
    cauce = np.zeros((60, 80), bool); cauce[:, 5:15] = True
    agua = cauce.copy()
    fuente = np.full(cauce.shape, URBANO, np.uint8); fuente[:, :5] = SIN_DATO
    r = P.control_sin_dato(cfg, g, fuente, agua, cauce)
    assert r["celdas_sin_dato_este"] == 0 and r["umbral"] == 0.05
    fuente[0:20, 40:80] = SIN_DATO                                            # un tercio de la tierra uruguaya
    with pytest.raises(ErrorPipeline, match="no tiene dato del MDT"):
        P.control_sin_dato(cfg, g, fuente, agua, cauce)
    cfg["sin_dato"]["max_fraccion_tierra_uy"] = 0.5
    assert P.control_sin_dato(cfg, g, fuente, agua, cauce)["fraccion"] > 0.05


# ---------------------------------------------------------------- I3 a: criterio y --forzar

CAL_NO = {"criterio_cumplido": False, "iou_validacion_media": 0.6, "cumple_iou": False,
          "dispersion_delta_m": 0.04, "cumple_estabilidad": True}


def test_criterio_no_cumplido_es_error_salvo_forzar():
    assert P.errores_criterio({**CAL_NO, "criterio_cumplido": True}, False) == []
    e = P.errores_criterio(CAL_NO, False)
    assert len(e) == 1 and "NO cumple el criterio" in e[0] and "--forzar" in e[0]
    assert P.errores_criterio(CAL_NO, True) == []


def test_cli_pasa_forzar(monkeypatch, tmp_path):
    vistos = []
    monkeypatch.setattr(P, "correr", lambda *a: vistos.append(a))
    assert P.main([str(tmp_path / "s")]) == 0
    assert P.main([str(tmp_path / "s"), "--forzar"]) == 0
    assert vistos[0][-1] is False and vistos[1][-1] is True


# ---------------------------------------------------------------- M2/M3: validar_indice

def _indice_bueno():
    ent = {"archivo": "x", "bytes": 1, "sha256": "0" * 64}
    capas = [{"altura_m": round(4.0 + i * 0.1, 2), "archivo": f"agua/{400 + 10 * i:04d}.json", "bytes": 1,
              "sha256": "0" * 64} for i in range(3)]
    return {"version": 1, "generado": "2026-10-21T12:00:00-03:00", "cero": "Local", "validado": False,
            "modelo": {"metodo": "m", "delta_m": 0.66, "iou_validacion": 0.9, "margen_m": 0.5},
            "limites": [[-32.4, -58.2], [-32.2, -57.9]], "paso_m": 0.1, "min_m": 4.0, "max_m": 4.2,
            "base": dict(ent, archivo="base.json"), "capas": capas, "referencias": [], "fuentes": ["OSM"]}


@pytest.mark.parametrize("cambio, texto", [
    ({"version": True}, "version"),
    ({"version": 1.0}, "version"),
    ({"version": 2}, "version"),
    ({"modelo": {"metodo": "m", "delta_m": 0.66, "iou_validacion": 0.9, "margen_m": 0.05}}, "margen_m"),
    ({"modelo": {"metodo": "m", "delta_m": 0.66, "iou_validacion": 0.9, "margen_m": "0.5"}}, "margen_m"),
    ({"min_m": 4.05, "max_m": 4.25}, "múltiplo"),
    ({"paso_m": 0}, "paso_m"),
])
def test_validar_indice_m2_m3(cambio, texto):
    assert V.validar_indice(_indice_bueno()) == []
    ind = {**_indice_bueno(), **cambio}
    assert any(texto in e for e in V.validar_indice(ind)), V.validar_indice(ind)


def test_margen_de_10_cm_se_acepta():
    ind = _indice_bueno(); ind["modelo"]["margen_m"] = 0.1
    assert V.validar_indice(ind) == []


# ---------------------------------------------------------------- la salida actual no dispara nada nuevo

@pytest.mark.skipif(not (ASSETS / "indice.json").exists(), reason="sin app/assets/mapa")
def test_assets_actuales_pasan_los_controles_nuevos():
    from shapely.geometry import shape
    import shapely
    ind = json.loads((ASSETS / "indice.json").read_text(encoding="utf-8"))
    assert V.validar_indice(ind) == []
    assert V.validar_archivos(ASSETS, ind) == []
    areas, vacia = [], False
    for c in ind["capas"]:
        g = json.loads((ASSETS / c["archivo"]).read_text(encoding="utf-8"))["features"][0]["geometry"]
        geom = shape(g) if g["coordinates"] else shapely.MultiPolygon()
        areas.append(geom.area)
        vacia = geom.is_empty
    # área en grados² (misma latitud en todas las capas): alcanza para ver que crece
    assert V.validar_areas([c["altura_m"] for c in ind["capas"]], areas, vacia) == []
    # la config actual con el δ publicado deja todas las capas en la grilla
    cfg = P.cargar_config(CONFIG)
    L = cfg["llegada"]
    d = int(round(ind["modelo"]["delta_m"] * 100))
    for c in ind["capas"]:
        umbral_en_grilla(int(round(c["altura_m"] * 100)) + d, L["min_cm"], L["cuantizacion_cm"], L["max_cm"])
