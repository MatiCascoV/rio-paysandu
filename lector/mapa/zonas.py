"""Agregados del contrato v1.1 (docs/mapa/05-contrato.md, "Agregados v1.1"):

- `celdas_afuera`: control de que ninguna celda mojada quede fuera de la capa publicada
  (después del redondeo a 5 decimales; 11 §5).
- `zona_sin_validar`: el valle de un arroyo (todo lo que el modelo moja allí hasta `max_m`),
  agrandado unos metros. El valle se define sin dibujar nada a mano: cada celda mojada se
  asigna al curso de OSM más cercano *caminando por el agua* (Voronoi geodésico) entre
  el arroyo y el río Uruguay.
- `aisladas`: lomas secas totalmente rodeadas de agua, con calles adentro.

Todo lo de acá solo agrega avisos: nunca saca agua de una capa.
"""
from __future__ import annotations

import math

import numpy as np

from . import capas as C


# ----------------------------------------------------------------------------------------
# Celdas mojadas afuera de la capa publicada
# ----------------------------------------------------------------------------------------

class Ventana:
    """Recorte de la grilla que cubre `limites`, con la máscara de celdas cuyo centro está
    dentro de `limites` (en el CRS de la grilla). Se arma una vez y se usa en cada capa."""

    def __init__(self, grilla, limites):
        import shapely
        from pyproj import Transformer
        from rasterio import features
        from shapely.geometry import box
        (s, o), (n, e) = limites
        t = Transformer.from_crs("EPSG:4326", grilla.crs, always_xy=True)
        self._a_grilla = t
        caja = shapely.transform(box(o, s, e, n).segmentize(0.0005),
                                 lambda xy: np.column_stack(t.transform(xy[:, 0], xy[:, 1])))
        x0, y0, x1, y1 = caja.bounds
        c0 = max(int(math.floor((x0 - grilla.x0) / grilla.res)) - 1, 0)
        c1 = min(int(math.ceil((x1 - grilla.x0) / grilla.res)) + 1, grilla.ancho)
        f0 = max(int(math.floor((grilla.y0 - y1) / grilla.res)) - 1, 0)
        f1 = min(int(math.ceil((grilla.y0 - y0) / grilla.res)) + 1, grilla.alto)
        self.sl = (slice(f0, f1), slice(c0, c1))
        self.forma = (f1 - f0, c1 - c0)
        self.transform = grilla.transform @ grilla.transform.translation(c0, f0)
        self.crs = grilla.crs
        self.res = grilla.res
        self.enlim = features.rasterize([(caja, 1)], out_shape=self.forma, transform=self.transform,
                                        fill=0, dtype="uint8").astype(bool)

    def a_grilla(self, geom_4326):
        import shapely
        t = self._a_grilla
        return shapely.transform(geom_4326, lambda xy: np.column_stack(t.transform(xy[:, 0], xy[:, 1])))

    def rasterizar(self, geom_4326) -> np.ndarray:
        """Celdas de la ventana cuyo centro cae dentro de la geometría (en EPSG:4326)."""
        from rasterio import features
        if geom_4326.is_empty:
            return np.zeros(self.forma, bool)
        g = self.a_grilla(geom_4326)
        return features.rasterize([(g, 1)], out_shape=self.forma, transform=self.transform,
                                  fill=0, dtype="uint8").astype(bool)


def celdas_afuera(mojado: np.ndarray, geom_4326, ventana: Ventana) -> tuple[int, list]:
    """Celdas mojadas (centro dentro de `limites`) cuyo centro queda fuera de la capa tal
    como se publica. Devuelve (cantidad, hasta 5 ejemplos [lon, lat])."""
    m = mojado[ventana.sl] & ventana.enlim
    fuera = m & ~ventana.rasterizar(geom_4326)
    n = int(fuera.sum())
    ejemplos = []
    if n:
        from pyproj import Transformer
        t = Transformer.from_crs(ventana.crs, "EPSG:4326", always_xy=True)
        ff, cc = np.nonzero(fuera)
        for f, c in list(zip(ff, cc))[:5]:
            x, y = ventana.transform @ (c + 0.5, f + 0.5)
            lon, lat = t.transform(x, y)
            ejemplos.append([round(lon, 6), round(lat, 6)])
    return n, ejemplos


# ----------------------------------------------------------------------------------------
# Zona sin validar: valle de un arroyo
# ----------------------------------------------------------------------------------------

def bloques_any(m: np.ndarray, f: int) -> np.ndarray:
    """Reduce la grilla en bloques de f×f: True si alguna celda del bloque es True."""
    if f == 1:
        return m.copy()
    a, b = m.shape
    pa, pb = (-a) % f, (-b) % f
    if pa or pb:
        m = np.pad(m, ((0, pa), (0, pb)))
    a2, b2 = m.shape
    return m.reshape(a2 // f, f, b2 // f, f).any(axis=(1, 3))


def voronoi_geodesico(dominio: np.ndarray, semillas_a: np.ndarray, semillas_b: np.ndarray) -> np.ndarray:
    """Celdas del dominio más cerca (caminando por el dominio, 4-vecinos) de las semillas A
    que de las B. Las celdas que no llegan a ninguna semilla quedan en False. En empate,
    gana B (el valle no se extiende sobre la costa del río por un empate)."""
    from scipy.sparse import coo_matrix
    from scipy.sparse.csgraph import dijkstra
    a = semillas_a & dominio
    b = semillas_b & dominio & ~a
    if not a.any():
        return np.zeros_like(dominio)
    idx = -np.ones(dominio.shape, np.int64)
    n = int(dominio.sum())
    idx[dominio] = np.arange(n)
    filas, cols = [], []
    for d0, d1 in ((idx[:, :-1], idx[:, 1:]), (idx[:-1, :], idx[1:, :])):
        ok = (d0 >= 0) & (d1 >= 0)
        filas.append(d0[ok]); cols.append(d1[ok])
    fi = np.concatenate(filas); co = np.concatenate(cols)
    g = coo_matrix((np.ones(fi.size), (fi, co)), shape=(n, n)).tocsr()
    sem_b = idx[b]
    sem_a = idx[a]
    fuentes = np.concatenate([sem_b, sem_a])  # B primero: en empate gana B
    _, _, origen = dijkstra(g, directed=False, indices=fuentes, min_only=True,
                            return_predecessors=True, unweighted=True)
    es_a = np.zeros(n, bool)
    alcanzado = origen >= 0
    marca_a = np.zeros(n, bool); marca_a[sem_a] = True
    es_a[alcanzado] = marca_a[origen[alcanzado]]
    out = np.zeros(dominio.shape, bool)
    out[dominio] = es_a
    return out


def lineas_por_nombre(osm: dict, nombres) -> list:
    """Líneas `t=curso` de base OSM cuyo nombre es exactamente uno de `nombres`."""
    from shapely.geometry import shape
    nombres = set(nombres)
    return [shape(f["geometry"]) for f in osm["features"]
            if f["properties"].get("t") == "curso" and f["properties"].get("n") in nombres]


def zona_sin_validar(mojado_max: np.ndarray, agua: np.ndarray, curso: np.ndarray, rio: np.ndarray,
                     grilla, factor: int, buffer_m: float, simplify_m: float, limites, decimales: int):
    """Valle del arroyo: celdas mojadas a la altura máxima más cerca (por el agua) de `curso`
    que de `rio`, en bloques de `factor` celdas, agrandado `buffer_m` y recortado a `limites`.

    Devuelve (geometría EPSG:4326 MultiPolygon, máscara del valle en la grilla reducida,
    transform de esa grilla reducida)."""
    if buffer_m < simplify_m:
        raise ValueError("buffer_m < simplify_m en la zona sin validar")
    moj_r = bloques_any(mojado_max, factor)
    dom = moj_r | bloques_any(agua, factor)
    valle = voronoi_geodesico(dom, bloques_any(curso, factor), bloques_any(rio, factor)) & moj_r
    t = grilla.transform @ grilla.transform.scale(factor, factor)
    g = C.poligonizar(valle, t, simplify_m, buffer_m)
    return C.a_4326(g, grilla.crs, decimales, limites), valle, t


def coleccion_zonas(zonas: list[tuple[object, dict]], decimales: int) -> dict:
    """sin_validar.json: un Feature (Polygon o MultiPolygon) por zona."""
    feats = []
    for g, props in zonas:
        if g.is_empty:
            continue
        coords = C.coords_geojson(g, decimales)
        geom = ({"type": "Polygon", "coordinates": coords[0]} if len(coords) == 1
                else {"type": "MultiPolygon", "coordinates": coords})
        feats.append({"type": "Feature", "properties": props, "geometry": geom})
    return {"type": "FeatureCollection", "features": feats}


# ----------------------------------------------------------------------------------------
# Lomas aisladas
# ----------------------------------------------------------------------------------------

class Calles:
    """Calles de base.json en el CRS de la grilla, con índice espacial."""

    def __init__(self, base: dict, crs: str):
        import shapely
        from pyproj import Transformer
        from shapely.geometry import shape
        t = Transformer.from_crs("EPSG:4326", crs, always_xy=True)
        self._t = t
        self.crs = crs
        self.geoms = [shapely.transform(shape(f["geometry"]), lambda xy: np.column_stack(t.transform(xy[:, 0], xy[:, 1])))
                      for f in base["features"] if f["properties"].get("t") == "calle"]
        self.arbol = shapely.STRtree(self.geoms) if self.geoms else None

    def largo_dentro(self, poligono) -> float:
        if self.arbol is None:
            return 0.0
        tot = 0.0
        for i in self.arbol.query(poligono, predicate="intersects"):
            tot += self.geoms[int(i)].intersection(poligono).length
        return tot

    def a_grilla(self, g):
        import shapely
        t = self._t
        return shapely.transform(g, lambda xy: np.column_stack(t.transform(xy[:, 0], xy[:, 1])))


def huecos_rodeados(geom_4326, agua_4326, limites, con_agua_base: bool = True,
                    decimales: int | None = None) -> list:
    """Tierra seca (EPSG:4326) totalmente rodeada de agua: cada hueco interior de la capa (o de
    la capa unida al agua de base.json si `con_agua_base`) que no toca el borde de `limites`,
    sin el agua que pueda haber adentro (un bajo mojado sobre la loma).

    "Toca el borde" se mide a la precisión publicada: con `decimales`, un hueco a menos de
    media unidad del último decimal del borde (≈ 0,5 m con 5 decimales) cae sobre el borde al
    redondear, así que en la capa publicada ya no es un hueco. Además, del otro lado del borde
    no sabemos nada: no se puede afirmar que esa tierra quede rodeada (contrato v1.1 §2)."""
    import shapely
    from shapely.geometry import Polygon, box
    if geom_4326.is_empty:
        return []
    (s, o), (n, e) = limites
    borde = box(o, s, e, n).exterior
    tol = 0.5 * 10 ** -decimales if decimales is not None else 1e-9
    g = geom_4326
    if con_agua_base and agua_4326 is not None and not agua_4326.is_empty:
        g = C.solo_poligonos(shapely.make_valid(shapely.union_all([geom_4326, agua_4326.intersection(box(o, s, e, n))])))
    arbol = shapely.STRtree(list(g.geoms))
    out = []
    for p in g.geoms:
        for anillo in p.interiors:
            h = Polygon(anillo)
            if h.is_empty or h.area == 0 or h.distance(borde) <= tol:
                continue
            adentro = [g.geoms[int(k)] for k in arbol.query(h, predicate="intersects")]
            seco = h.difference(shapely.union_all(adentro)) if adentro else h
            if not seco.is_empty and seco.area > 0:
                out.append(seco)
    return out


def punto_interior(seco_4326, a_grilla, decimales: int):
    """Punto bien adentro de la parte más grande de la loma (polylabel en metros),
    redondeado a `decimales` y verificado adentro."""
    from pyproj import Transformer
    from shapely.geometry import Point
    from shapely.ops import polylabel
    partes = [q for q in getattr(seco_4326, "geoms", [seco_4326]) if q.geom_type == "Polygon"]
    p = max(partes, key=lambda q: q.area)
    pg_ = a_grilla(p)
    try:
        pg = polylabel(pg_, tolerance=1.0)
    except Exception:  # noqa: BLE001 - polígonos degenerados
        pg = pg_.representative_point()
    t = Transformer.from_crs(a_grilla.crs, "EPSG:4326", always_xy=True)
    lon, lat = t.transform(pg.x, pg.y)
    candidatos = [(lon, lat), (p.representative_point().x, p.representative_point().y)]
    paso = 10 ** -decimales
    for x, y in candidatos:
        for dx in (0, -paso, paso):
            for dy in (0, -paso, paso):
                c = [round(x + dx, decimales), round(y + dy, decimales)]
                if p.contains(Point(c)):
                    return c
    raise ValueError("no encontré un punto interior redondeado para una loma aislada")


def lomas_aisladas(geom_4326, agua_4326, calles: Calles, limites, min_calles_m: float, decimales: int,
                   con_agua_base: bool = True) -> list[dict]:
    """Lista `aisladas` de una capa: [{"c": [lon, lat], "ha": …, "calles_m": …}] con al menos
    `min_calles_m` de calle adentro, ordenada por área (mayor primero)."""
    out = []
    a_grilla = _Proyector(calles)
    for seco in huecos_rodeados(geom_4326, agua_4326, limites, con_agua_base, decimales):
        sg = a_grilla(seco)
        largo = calles.largo_dentro(sg)
        if largo < min_calles_m:
            continue
        out.append({"c": punto_interior(seco, a_grilla, decimales), "ha": round(sg.area / 1e4, 2),
                    "calles_m": int(round(largo))})
    out.sort(key=lambda d: (-d["ha"], d["c"]))
    return out


class _Proyector:
    def __init__(self, calles: Calles):
        self._c = calles
        self.crs = calles.crs

    def __call__(self, g):
        return self._c.a_grilla(g)
