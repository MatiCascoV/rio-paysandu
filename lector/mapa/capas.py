"""De la llegada a los polígonos de cada nivel (contrato: agua/NNNN.json)."""
from __future__ import annotations

import json
import math

import numpy as np

from .llegada import CRUZ


def nombre_capa(altura_m: float) -> str:
    """6.70 → 'agua/0670.json' (altura en cm, 4 dígitos)."""
    cm = int(round(altura_m * 100))
    if cm < 0 or cm > 9999:
        raise ValueError(f"altura fuera de rango para el nombre de archivo: {altura_m}")
    return f"agua/{cm:04d}.json"


def alturas(min_m: float, max_m: float, paso_m: float) -> list[float]:
    n = int(round((max_m - min_m) / paso_m))
    if abs(min_m + n * paso_m - max_m) > 1e-6:
        raise ValueError("max_m - min_m no es múltiplo de paso_m")
    return [round(min_m + i * paso_m, 2) for i in range(n + 1)]


def mascara_nivel(llegada: np.ndarray, umbral: int, excluir: np.ndarray) -> np.ndarray:
    """Agua sobre tierra conectada al río: llegada ≤ umbral, sin el cauce normal."""
    return (llegada <= umbral) & ~excluir


def tamizar(mojado: np.ndarray, excluir: np.ndarray, min_celdas: int) -> np.ndarray:
    """Saca manchas de agua y rellena islas secas de menos de `min_celdas` (4-conectividad).

    Conserva el anidado: si A ⊆ B, tamizar(A) ⊆ tamizar(B) (las manchas de A que quedan
    están dentro de manchas de B más grandes, y los huecos de B están dentro de huecos de A).
    """
    from scipy import ndimage
    if min_celdas <= 1:
        return mojado.copy()
    out = mojado.copy()
    etq, n = ndimage.label(out, structure=CRUZ)
    if n:
        tam = np.bincount(etq.ravel())
        chico = tam < min_celdas
        chico[0] = False
        out[chico[etq]] = False
    seco = ~out & ~excluir
    etq, n = ndimage.label(seco, structure=CRUZ)
    if n:
        tam = np.bincount(etq.ravel())
        chico = tam < min_celdas
        chico[0] = False
        out[chico[etq]] = True
    return out


def poligonizar(mojado: np.ndarray, transform, simplify_m: float):
    """Polígonos (en el CRS de la grilla) de las celdas mojadas, simplificados y válidos."""
    import shapely
    from rasterio import features
    from shapely.geometry import MultiPolygon, shape

    if not mojado.any():
        return MultiPolygon()
    # recorte a la caja de las celdas mojadas: polygonize es más rápido
    filas = np.flatnonzero(mojado.any(axis=1)); cols = np.flatnonzero(mojado.any(axis=0))
    f0, f1, c0, c1 = filas[0], filas[-1] + 1, cols[0], cols[-1] + 1
    sub = mojado[f0:f1, c0:c1].astype("uint8")
    t = transform * transform.translation(c0, f0)
    polis = [shape(g) for g, v in features.shapes(sub, mask=sub.astype(bool), transform=t, connectivity=4) if v == 1]
    geom = shapely.union_all(polis) if len(polis) > 1 else polis[0]
    if simplify_m > 0:
        geom = geom.simplify(simplify_m, preserve_topology=True)
    geom = shapely.make_valid(geom)
    return solo_poligonos(geom)


def solo_poligonos(geom):
    from shapely.geometry import MultiPolygon, Polygon
    if geom.is_empty:
        return MultiPolygon()
    if isinstance(geom, Polygon):
        return MultiPolygon([geom])
    if isinstance(geom, MultiPolygon):
        return geom
    partes = []
    for g in getattr(geom, "geoms", []):
        if isinstance(g, Polygon) and not g.is_empty:
            partes.append(g)
        elif isinstance(g, MultiPolygon):
            partes.extend(g.geoms)
    return MultiPolygon(partes)


def a_4326(geom, crs_origen: str, decimales: int):
    """Reproyecta a EPSG:4326 [lon, lat] y redondea a `decimales` manteniendo validez."""
    import shapely
    from pyproj import Transformer
    if geom.is_empty:
        return geom
    t = Transformer.from_crs(crs_origen, "EPSG:4326", always_xy=True)
    g = shapely.transform(geom, lambda xy: np.column_stack(t.transform(xy[:, 0], xy[:, 1])))
    g = shapely.set_precision(g, 10 ** (-decimales))
    if not g.is_valid:
        g = shapely.set_precision(shapely.make_valid(g), 10 ** (-decimales))
    return solo_poligonos(g)


def coords_geojson(geom, decimales: int) -> list:
    """MultiPolygon → lista de coordenadas GeoJSON con anillo exterior antihorario."""
    from shapely.geometry.polygon import orient
    out = []
    for p in geom.geoms:
        p = orient(p, sign=1.0)
        anillos = [p.exterior] + list(p.interiors)
        out.append([[[round(x, decimales), round(y, decimales)] for x, y in a.coords] for a in anillos])
    return out


def feature_collection(geom, properties: dict, decimales: int) -> dict:
    return {"type": "FeatureCollection", "features": [{
        "type": "Feature", "properties": properties,
        "geometry": {"type": "MultiPolygon", "coordinates": coords_geojson(geom, decimales) if not geom.is_empty else []},
    }]}


def serializar(obj: dict) -> bytes:
    """JSON compacto y determinista (mismo contenido → mismos bytes)."""
    return json.dumps(obj, ensure_ascii=False, separators=(",", ":"), allow_nan=False).encode("utf-8")


def area_m2_4326(geom) -> float:
    """Área aproximada en m² de una geometría en grados (proyección local equirectangular)."""
    import shapely
    if geom.is_empty:
        return 0.0
    lat0 = geom.centroid.y
    kx = 111320.0 * math.cos(math.radians(lat0)); ky = 110574.0
    return shapely.transform(geom, lambda xy: xy * np.array([kx, ky])).area
