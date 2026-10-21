"""Agregados del contrato v1.1: buffer de 5 m sin celdas afuera, zona sin validar y lomas aisladas."""
import copy
import hashlib
import json
from pathlib import Path

import pytest

np = pytest.importorskip("numpy")
pytest.importorskip("scipy")
pytest.importorskip("shapely")
pytest.importorskip("rasterio")
pytest.importorskip("pyproj")

from mapa import capas as C  # noqa: E402
from mapa import validar as V  # noqa: E402
from mapa import zonas as Z  # noqa: E402
from mapa.terreno import Grilla  # noqa: E402

X0, Y0 = 396000.0, 6424000.0          # cerca de Paysandú en EPSG:5382


def a4326(x, y):
    from pyproj import Transformer
    return Transformer.from_crs("EPSG:5382", "EPSG:4326", always_xy=True).transform(x, y)


def limites_de(grilla, recorte_m=0.0):
    """limites [[S, O], [N, E]] que entran en la grilla (achicados `recorte_m`)."""
    x0, y0, x1, y1 = grilla.bounds
    o, s = a4326(x0 + recorte_m, y0 + recorte_m)
    e, n = a4326(x1 - recorte_m, y1 - recorte_m)
    o2, n2 = a4326(x0 + recorte_m, y1 - recorte_m)
    e2, s2 = a4326(x1 - recorte_m, y0 + recorte_m)
    return [[round(max(s, s2), 5), round(max(o, o2), 5)], [round(min(n, n2), 5), round(min(e, e2), 5)]]


def mascara_irregular(alto, ancho, semilla):
    rng = np.random.default_rng(semilla)
    m = np.zeros((alto, ancho), bool)
    for _ in range(alto * ancho // 120):
        f, c = rng.integers(0, alto), rng.integers(0, ancho)
        m[max(f - 3, 0):f + 3, max(c - 5, 0):c + 5] = True
    m[alto // 2, :] = True                       # canal de una celda de ancho
    m[:, ancho // 3] = True                      # otro, vertical, que cruza el borde
    m[5:alto - 5:7, 5:ancho - 5:9] = True        # celdas sueltas
    return m


# ---------------------------------------------------------------- 1. buffer de 5 m (11 §5)

@pytest.mark.parametrize("semilla", [1, 2, 3])
def test_buffer_5_no_deja_celdas_mojadas_afuera_despues_del_redondeo(semilla):
    """Cadena completa del pipeline: polígonos, buffer 5 / simplify 4, reproyección, recorte a
    limites, 5 decimales, JSON y vuelta. Ningún centro de celda mojada queda afuera."""
    from shapely.geometry import shape
    g = Grilla("EPSG:5382", X0, Y0, 2.0, 260, 200)
    moj = mascara_irregular(g.alto, g.ancho, semilla)
    lim = limites_de(g, 37.0)                   # recorta la máscara: hay celdas sobre el corte
    geom = C.poligonizar(moj, g.transform, 4.0, 5.0)
    geom = C.a_4326(geom, g.crs, 5, lim)
    pub = json.loads(C.serializar(C.feature_collection(geom, {"altura_m": 5.0}, 5)))
    gp = shape(pub["features"][0]["geometry"])
    ven = Z.Ventana(g, lim)
    assert (moj[ven.sl] & ven.enlim).sum() > 1000
    n, ej = Z.celdas_afuera(moj, gp, ven)
    assert n == 0, ej


def test_celdas_afuera_detecta_agua_que_falta():
    from shapely.geometry import box
    g = Grilla("EPSG:5382", X0, Y0, 2.0, 100, 100)
    moj = np.zeros((100, 100), bool); moj[20:80, 20:80] = True
    lim = limites_de(g)
    geom = C.a_4326(C.poligonizar(moj, g.transform, 4.0, 5.0), g.crs, 5, lim)
    ven = Z.Ventana(g, lim)
    assert Z.celdas_afuera(moj, geom, ven)[0] == 0
    o, s = a4326(X0 + 40, Y0 - 200); e, n = a4326(X0 + 200, Y0 - 40)   # le saco una esquina
    n_fuera, ej = Z.celdas_afuera(moj, geom.difference(box(o, s, e, n)), ven)
    assert n_fuera > 100 and len(ej) == 5


def test_config_agranda_5_m_y_simplifica_4_m():
    cfg = json.loads((Path(__file__).resolve().parents[1] / "mapa" / "config.json").read_text(encoding="utf-8"))
    assert cfg["capas"]["buffer_m"] == 5.0 and cfg["capas"]["simplify_m"] == 4.0


# ---------------------------------------------------------------- 2. zona sin validar

def test_voronoi_geodesico_camina_por_el_agua():
    dom = np.zeros((20, 30), bool)
    dom[:, 0:3] = True          # río (columna 1)
    dom[10, 3:30] = True        # valle angosto hacia el este
    dom[0:2, 3:30] = True       # costa al norte, conectada solo por el río
    a = np.zeros_like(dom); a[10, 20:30] = True     # arroyo
    b = np.zeros_like(dom); b[:, 1] = True          # río
    v = Z.voronoi_geodesico(dom, a, b)
    assert v[10, 12:30].all()           # el valle, más cerca del arroyo por el agua
    assert not v[0:2, 20:30].any()      # la costa norte está cerca en línea recta, pero no por el agua
    assert not v[:, 0:3].any()
    assert not (v & ~dom).any()


def test_voronoi_sin_semillas_del_arroyo_da_vacio():
    dom = np.ones((5, 5), bool)
    assert not Z.voronoi_geodesico(dom, np.zeros_like(dom), dom).any()


def test_bloques_any():
    m = np.zeros((7, 11), bool); m[6, 10] = True
    r = Z.bloques_any(m, 5)
    assert r.shape == (2, 3) and r[1, 2] and r.sum() == 1


def _escenario_valle():
    """Río al oeste, costa baja y un arroyo que entra hacia el este."""
    g = Grilla("EPSG:5382", X0, Y0, 2.0, 400, 300)
    moj = np.zeros((g.alto, g.ancho), bool)
    agua = np.zeros_like(moj); agua[:, :30] = True                 # cauce
    moj[:, 30:60] = True                                           # costa inundada
    moj[140:170, 60:380] = True                                    # valle del arroyo
    curso = np.zeros_like(moj); curso[155, 40:390] = True
    rio = np.zeros_like(moj); rio[:, 10] = True
    return g, moj, agua, curso, rio


def test_zona_sin_validar_cubre_el_valle_agrandado_y_no_la_costa_lejana():
    from shapely.geometry import Point
    g, moj, agua, curso, rio = _escenario_valle()
    lim = limites_de(g)
    gz, valle, t = Z.zona_sin_validar(moj, agua, curso, rio, g, 5, 100.0, 10.0, lim, 5)
    assert gz.is_valid and not gz.is_empty
    ven = Z.Ventana(g, lim)
    mv = np.repeat(np.repeat(valle, 5, 0), 5, 1)[:g.alto, :g.ancho] & moj
    assert mv[150, 100:370].all()                           # el valle está
    assert Z.celdas_afuera(mv, gz, ven)[0] == 0             # y todo adentro de la zona
    assert Z.celdas_afuera(moj[140:170, 60:380].copy(), gz, Z.Ventana(
        Grilla(g.crs, g.x0 + 120, g.y0 - 280, 2.0, 320, 30), lim))[0] == 0
    # agrandada unos 100 m: un punto 80 m al norte del valle, sobre tierra seca, está adentro
    assert gz.contains(Point(*a4326(X0 + 2 * 250, Y0 - 2 * 140 + 80)))
    # la costa del río lejos de la boca del arroyo no es parte del valle
    assert not gz.contains(Point(*a4326(X0 + 2 * 45, Y0 - 2 * 20)))
    assert not gz.contains(Point(*a4326(X0 + 2 * 45, Y0 - 2 * 290)))


def test_coleccion_zonas_y_su_validacion():
    g, moj, agua, curso, rio = _escenario_valle()
    lim = limites_de(g)
    gz, _, _ = Z.zona_sin_validar(moj, agua, curso, rio, g, 5, 100.0, 10.0, lim, 5)
    fc = Z.coleccion_zonas([(gz, {"nombre": "Valle", "motivo": "Sin crecidas medidas."})], 5)
    fc = json.loads(C.serializar(fc))
    assert V.validar_sin_validar(fc, lim) == []
    assert fc["features"][0]["geometry"]["type"] in ("Polygon", "MultiPolygon")
    malo = copy.deepcopy(fc); malo["features"][0]["properties"] = {"nombre": "Valle"}
    assert any("properties" in e for e in V.validar_sin_validar(malo, lim))
    malo = copy.deepcopy(fc)
    anillo = malo["features"][0]["geometry"]["coordinates"]
    anillo = anillo[0] if malo["features"][0]["geometry"]["type"] == "Polygon" else anillo[0][0]
    anillo[1] = [anillo[1][0] + 0.0000012, anillo[1][1]]
    assert any("decimales" in e for e in V.validar_sin_validar(malo, lim))
    assert V.validar_sin_validar({"type": "FeatureCollection", "features": []}, lim)


# ---------------------------------------------------------------- 3. lomas aisladas

LIM = [[-32.40, -58.20], [-32.20, -57.95]]


def _base(calles=(), agua=()):
    from shapely.geometry import mapping
    feats = [{"type": "Feature", "properties": {"t": "calle", "k": 3, "n": None}, "geometry": mapping(c)} for c in calles]
    feats += [{"type": "Feature", "properties": {"t": "agua"}, "geometry": mapping(a)} for a in agua]
    return {"type": "FeatureCollection", "features": feats, "lugares": [], "caja": [-58.2, -32.4, -57.95, -32.2]}


def _agua_con_huecos():
    """Capa: un cuadrado de ~1,9 km con dos lomas adentro, una con calle y otra sin."""
    from shapely.geometry import LineString, Polygon
    ext = [(-58.11, -32.31), (-58.09, -32.31), (-58.09, -32.29), (-58.11, -32.29)]
    loma1 = [(-58.105, -32.305), (-58.100, -32.305), (-58.100, -32.300), (-58.105, -32.300)]
    loma2 = [(-58.097, -32.297), (-58.094, -32.297), (-58.094, -32.294), (-58.097, -32.294)]
    capa = C.solo_poligonos(Polygon(ext, [loma1, loma2]))
    calle_larga = LineString([(-58.104, -32.3025), (-58.101, -32.3025)])      # ~280 m, adentro de loma1
    calle_corta = LineString([(-58.0960, -32.2955), (-58.0957, -32.2955)])    # ~28 m, adentro de loma2
    return capa, calle_larga, calle_corta


def test_lomas_aisladas_solo_con_calles():
    capa, larga, corta = _agua_con_huecos()
    calles = Z.Calles(_base([larga, corta]), "EPSG:5382")
    ais = Z.lomas_aisladas(capa, None, calles, LIM, 50, 5)
    assert len(ais) == 1
    a = ais[0]
    assert set(a) == {"c", "ha", "calles_m"}
    assert 250 < a["calles_m"] < 320 and isinstance(a["calles_m"], int)
    assert 20 < a["ha"] < 30             # 0,005° × 0,005° ≈ 470 m × 555 m
    from shapely.geometry import Point, box
    assert box(-58.105, -32.305, -58.100, -32.300).contains(Point(a["c"]))
    assert all(round(x, 5) == x for x in a["c"])
    # con el umbral en 10 m entran las dos
    assert len(Z.lomas_aisladas(capa, None, calles, LIM, 10, 5)) == 2


def test_hueco_que_toca_el_borde_de_limites_no_es_aislada():
    from shapely.geometry import LineString, Polygon
    lim = [[-32.31, -58.11], [-32.29, -58.09]]
    # el "hueco" llega al borde sur de limites: tras el recorte deja de ser hueco
    capa = C.solo_poligonos(Polygon([(-58.11, -32.31), (-58.09, -32.31), (-58.09, -32.29), (-58.11, -32.29)],
                                     [[(-58.105, -32.3099999), (-58.1, -32.3099999), (-58.1, -32.305), (-58.105, -32.305)]]))
    calles = Z.Calles(_base([LineString([(-58.104, -32.307), (-58.101, -32.307)])]), "EPSG:5382")
    assert Z.lomas_aisladas(capa, None, calles, lim, 50, 5) == []


def test_loma_rodeada_por_la_capa_y_el_agua_de_base():
    """Una loma entre el agua de la capa y el cauce de base.json también queda rodeada."""
    from shapely.geometry import LineString, Polygon
    capa = C.solo_poligonos(Polygon([(-58.10, -32.31), (-58.08, -32.31), (-58.08, -32.29), (-58.10, -32.29)],
                                    [[(-58.0999, -32.305), (-58.09, -32.305), (-58.09, -32.295), (-58.0999, -32.295)]]))
    # le saco a la capa la franja oeste: ahí la loma toca el cauce y deja de ser un hueco de la capa
    from shapely.geometry import box
    capa = C.solo_poligonos(capa.difference(box(-58.10, -32.31, -58.0995, -32.29)))
    cauce = Polygon([(-58.12, -32.33), (-58.0995, -32.33), (-58.0995, -32.27), (-58.12, -32.27)])
    calles = Z.Calles(_base([LineString([(-58.098, -32.30), (-58.092, -32.30)])], [cauce]), "EPSG:5382")
    assert Z.lomas_aisladas(capa, None, calles, LIM, 50, 5, con_agua_base=False) == []
    ais = Z.lomas_aisladas(capa, cauce, calles, LIM, 50, 5, con_agua_base=True)
    assert len(ais) == 1 and ais[0]["calles_m"] > 500


def test_bajo_mojado_adentro_de_la_loma_no_cuenta_como_seco():
    from shapely.geometry import LineString, Point, Polygon
    exterior = Polygon([(-58.11, -32.31), (-58.09, -32.31), (-58.09, -32.29), (-58.11, -32.29)],
                       [[(-58.105, -32.305), (-58.095, -32.305), (-58.095, -32.295), (-58.105, -32.295)]])
    bajo = Polygon([(-58.1025, -32.3025), (-58.0975, -32.3025), (-58.0975, -32.2975), (-58.1025, -32.2975)])
    capa = C.solo_poligonos(exterior.union(bajo))
    calles = Z.Calles(_base([LineString([(-58.104, -32.30), (-58.096, -32.30)])]), "EPSG:5382")
    ais = Z.lomas_aisladas(capa, None, calles, LIM, 50, 5)
    assert len(ais) == 1
    assert not bajo.contains(Point(ais[0]["c"])) and not capa.intersects(Point(ais[0]["c"]))
    # la calle que cruza el bajo mojado no cuenta en ese tramo (~470 m de los ~750)
    assert 200 < ais[0]["calles_m"] < 330


def _fc_capa(capa, aisladas):
    return json.loads(C.serializar(C.feature_collection(capa, {"altura_m": 6.0, "aisladas": aisladas}, 5)))


def test_validar_capa_con_aisladas():
    capa, larga, corta = _agua_con_huecos()
    ais = Z.lomas_aisladas(capa, None, Z.Calles(_base([larga]), "EPSG:5382"), LIM, 50, 5)
    assert V.validar_capa(_fc_capa(capa, ais), 6.0, LIM, 50) == []
    assert V.validar_capa(_fc_capa(capa, []), 6.0, LIM, 50) == []
    sobre_agua = [{"c": [-58.108, -32.308], "ha": 1.0, "calles_m": 100}]
    assert any("agua" in e for e in V.validar_capa(_fc_capa(capa, sobre_agua), 6.0, LIM, 50))
    pocas = [dict(ais[0], calles_m=20)]
    assert any("calles_m" in e for e in V.validar_capa(_fc_capa(capa, pocas), 6.0, LIM, 50))
    clave_de_mas = [dict(ais[0], x=1)]
    assert any("claves" in e for e in V.validar_capa(_fc_capa(capa, clave_de_mas), 6.0, LIM, 50))
    fc = _fc_capa(capa, ais); fc["features"][0]["properties"]["otra"] = 1
    assert any("properties" in e for e in V.validar_capa(fc, 6.0, LIM, 50))


# ---------------------------------------------------------------- 4. pipeline con todo junto

def test_generar_con_sin_validar_y_aisladas(tmp_path):
    from shapely.geometry import LineString, mapping, shape
    from mapa.pipeline import armar_indice, generar
    g, moj, agua, curso, rio = _escenario_valle()
    # terreno: 3 m en el cauce, 4,5 m en la costa y el valle, 9 m el resto (con lleg en cm)
    lleg = np.full(moj.shape, 2000, np.int32)
    lleg[agua] = 300
    lleg[moj] = 450
    lleg[150:160, 200:220] = 2000         # una loma de 20 m × 40 m adentro del valle: se rellena (< 2000 m²)
    lleg[145:166, 280:330] = 2000         # otra de 42 m × 100 m: queda seca y rodeada
    lim = limites_de(g)

    def linea(f, c0, c1):
        return LineString([a4326(X0 + 2 * c0, Y0 - 2 * f), a4326(X0 + 2 * c1, Y0 - 2 * f)])

    def vertical(c):
        return LineString([a4326(X0 + 2 * c, Y0), a4326(X0 + 2 * c, Y0 - 2 * g.alto)])
    osm = {"type": "FeatureCollection", "lugares": [], "caja": [], "features": [
        {"type": "Feature", "properties": {"t": "curso", "n": "Arroyo X"}, "geometry": mapping(linea(155.5, 40, 390))},
        {"type": "Feature", "properties": {"t": "curso", "n": "Río Uruguay"}, "geometry": mapping(vertical(10.5))}]}
    base = {"type": "FeatureCollection", "lugares": [], "caja": [], "features": [
        {"type": "Feature", "properties": {"t": "calle", "k": 3, "n": "Loma"}, "geometry": mapping(linea(155, 285, 325))}]}
    cfg = {
        "cero": "Local", "resolucion_m": 2.0, "min_m": 4.0, "max_m": 4.6, "paso_m": 0.1, "margen_m": 0.5,
        "limites": lim, "mdt_urbano": {"fecha_vuelo": "2017-10"}, "curvas": {"simplify_grados": 0.00002},
        "capas": {"sieve_m2": 16, "rellenar_secos_m2": 2000, "simplify_m": 4.0, "buffer_m": 5.0, "decimales": 5,
                  "tolerancia_anidado": 0.01, "tope_capa_bytes": 200000, "tope_base_bytes": 200000,
                  "tope_total_bytes": 2000000},
        "sin_validar": {"rio": ["Río Uruguay"], "factor_celdas": 5, "simplify_m": 10.0,
                        "zonas": [{"nombre": "Valle del arroyo X", "motivo": "Sin crecidas medidas.",
                                   "cursos": ["Arroyo X"], "buffer_m": 100.0}]},
        "aisladas": {"usar": True, "min_calles_m": 50, "con_agua_base": True},
        "fuentes": ["© colaboradores de OpenStreetMap, ODbL"],
    }
    carpeta = tmp_path / "s"; carpeta.mkdir()
    entradas, geoms, base_ent, refs, areas, errores, extra = generar(cfg, carpeta, g, lleg, agua, 0.0, base, [], osm)
    assert errores == []
    assert sum(extra["celdas_afuera"].values()) == 0
    ind = armar_indice(cfg, "2026-10-21T12:00:00-03:00", False, 0.0, 0.75, base_ent, entradas, refs,
                       extra["sin_validar"])
    assert V.validar_indice(ind) == [] and V.validar_archivos(carpeta, ind) == []
    datos = (carpeta / "sin_validar.json").read_bytes()
    assert ind["sin_validar"] == {"archivo": "sin_validar.json", "bytes": len(datos),
                                  "sha256": hashlib.sha256(datos).hexdigest()}
    fc = json.loads(datos)
    assert fc["features"][0]["properties"]["nombre"] == "Valle del arroyo X"
    # aisladas: la loma grande con calle, en todas las capas (el valle se moja desde 4,5 m)
    c45 = json.loads((carpeta / "agua/0450.json").read_text(encoding="utf-8"))["features"][0]["properties"]
    assert len(c45["aisladas"]) == 1 and c45["aisladas"][0]["calles_m"] >= 50
    c40 = json.loads((carpeta / "agua/0400.json").read_text(encoding="utf-8"))["features"][0]["properties"]
    assert c40["aisladas"] == []
    zona = shape(fc["features"][0]["geometry"])
    from shapely.geometry import Point
    assert zona.contains(Point(c45["aisladas"][0]["c"]))
    # un sha256 o bytes mal en sin_validar se detecta
    malo = copy.deepcopy(ind); malo["sin_validar"]["bytes"] += 1
    assert V.validar_archivos(carpeta, malo)
    malo = copy.deepcopy(ind); malo["sin_validar"]["archivo"] = "otra.json"
    assert V.validar_indice(malo)
