"""Grilla de trabajo, selección de hojas y mosaico del MDT.

- La grilla es la caja `limites` reproyectada a EPSG:5382 (SIRGAS-ROU98 / UTM 21S),
  con celda `resolucion_m`. Cada hoja de 1 m se remuestrea a esa celda.
- MDT urbano (1 m, vuelo 2017) primero; los huecos que quedan se rellenan con el MDT
  nacional (2,5 m, otro vuelo) corrigiendo el sesgo vertical medido en el solape.
- Los huecos chicos que siguen (casas, sombras) se rellenan con el vecino más cercano.
- `fuente`: 0 = sin dato, 1 = urbano, 2 = nacional, 3 = hueco rellenado.
"""
from __future__ import annotations

import logging
from dataclasses import dataclass

import numpy as np

log = logging.getLogger("mapa")

SIN_DATO, URBANO, NACIONAL, RELLENO = 0, 1, 2, 3


@dataclass
class Grilla:
    crs: str
    x0: float      # borde oeste
    y0: float      # borde norte
    res: float
    ancho: int
    alto: int

    @property
    def transform(self):
        from rasterio.transform import from_origin
        return from_origin(self.x0, self.y0, self.res, self.res)

    @property
    def bounds(self):
        return (self.x0, self.y0 - self.alto * self.res, self.x0 + self.ancho * self.res, self.y0)


def grilla_desde_limites(limites, crs: str, res: float) -> Grilla:
    from pyproj import Transformer
    (s, o), (n, e) = limites
    t = Transformer.from_crs("EPSG:4326", crs, always_xy=True)
    xs, ys = [], []
    for lon in np.linspace(o, e, 21):
        for lat in (s, n):
            x, y = t.transform(lon, lat); xs.append(x); ys.append(y)
    for lat in np.linspace(s, n, 21):
        for lon in (o, e):
            x, y = t.transform(lon, lat); xs.append(x); ys.append(y)
    x0 = np.floor(min(xs) / res) * res
    x1 = np.ceil(max(xs) / res) * res
    y1 = np.ceil(max(ys) / res) * res
    y0 = np.floor(min(ys) / res) * res
    return Grilla(crs, float(x0), float(y1), float(res), int(round((x1 - x0) / res)), int(round((y1 - y0) / res)))


def hojas_en_limites(ruta_shp_sin_ext: str, limites, encoding: str, prefijo: str | None = None) -> list[str]:
    """Nombres de hoja de una grilla de articulación (en geográficas) que tocan los límites."""
    import shapefile
    from shapely.geometry import box, shape
    (s, o), (n, e) = limites
    caja = box(o, s, e, n)
    r = shapefile.Reader(ruta_shp_sin_ext, encoding=encoding)
    out = []
    for sh, rec in zip(r.shapes(), r.records()):
        nombre = str(rec["Nombre"]).strip()
        if prefijo and not nombre.startswith(prefijo):
            continue
        if shape(sh.__geo_interface__).intersects(caja):
            out.append(nombre)
    return sorted(set(out))


def _pegar(ruta, destino: np.ndarray, grilla: Grilla, remuestreo: str, nodata_min: float) -> int:
    """Remuestrea una hoja sobre `destino` (solo donde destino es NaN). Devuelve celdas escritas."""
    import rasterio
    from rasterio.enums import Resampling
    from rasterio.warp import reproject
    from rasterio.windows import from_bounds

    with rasterio.open(ruta) as src:
        if src.crs is None:
            raise ValueError(f"{ruta}: la hoja no declara CRS")
        b = src.bounds
        if str(src.crs).upper() != grilla.crs.upper():
            # Se acepta otro CRS pero se reproyecta explícitamente.
            from rasterio.warp import transform_bounds
            b = transform_bounds(src.crs, grilla.crs, *b)
        win = from_bounds(*b, transform=grilla.transform).round_offsets().round_lengths()
        c0 = max(int(win.col_off) - 1, 0); f0 = max(int(win.row_off) - 1, 0)
        c1 = min(int(win.col_off + win.width) + 1, grilla.ancho)
        f1 = min(int(win.row_off + win.height) + 1, grilla.alto)
        if c1 <= c0 or f1 <= f0:
            return 0
        sub = np.full((f1 - f0, c1 - c0), np.nan, dtype="float32")
        from rasterio.transform import from_origin
        t = from_origin(grilla.x0 + c0 * grilla.res, grilla.y0 - f0 * grilla.res, grilla.res, grilla.res)
        datos = src.read(1).astype("float32")
        datos[(datos < nodata_min) | ~np.isfinite(datos)] = np.nan
        if src.nodata is not None:
            datos[datos == src.nodata] = np.nan
        reproject(datos, sub, src_transform=src.transform, src_crs=src.crs, src_nodata=np.nan,
                  dst_transform=t, dst_crs=grilla.crs, dst_nodata=np.nan,
                  resampling=getattr(Resampling, remuestreo))
        zona = destino[f0:f1, c0:c1]
        poner = np.isnan(zona) & ~np.isnan(sub)
        zona[poner] = sub[poner]
        return int(poner.sum())


def mosaico(rutas, grilla: Grilla, remuestreo: str = "average", nodata_min: float = -1000) -> np.ndarray:
    dem = np.full((grilla.alto, grilla.ancho), np.nan, dtype="float32")
    for i, r in enumerate(rutas, 1):
        n = _pegar(r, dem, grilla, remuestreo, nodata_min)
        log.debug("hoja %d/%d %s: %d celdas", i, len(rutas), r, n)
    return dem


def rellenar_con_nacional(dem: np.ndarray, nac: np.ndarray, fuente: np.ndarray,
                          max_sesgo: float, min_solape: int) -> dict:
    """Rellena huecos de `dem` con `nac - sesgo`, donde sesgo = mediana(nac - dem) en el solape."""
    solape = ~np.isnan(dem) & ~np.isnan(nac)
    n = int(solape.sum())
    info = {"celdas_solape": n}
    if n < min_solape:
        info["usado"] = False
        info["motivo"] = f"solape insuficiente ({n} < {min_solape})"
        return info
    d = (nac - dem)[solape]
    sesgo = float(np.median(d))
    info.update({"sesgo_m": round(sesgo, 3),
                 "p25_m": round(float(np.percentile(d, 25)), 3),
                 "p75_m": round(float(np.percentile(d, 75)), 3)})
    if abs(sesgo) > max_sesgo:
        info["usado"] = False
        info["motivo"] = f"sesgo {sesgo:.2f} m fuera de ±{max_sesgo} m"
        return info
    poner = np.isnan(dem) & ~np.isnan(nac)
    dem[poner] = nac[poner] - sesgo
    fuente[poner] = NACIONAL
    info["usado"] = True
    info["celdas_rellenadas"] = int(poner.sum())
    return info


def rellenar_huecos_chicos(dem: np.ndarray, fuente: np.ndarray, protegido: np.ndarray, max_celdas: int) -> int:
    """Rellena con el vecino válido más cercano los huecos (NaN) de menos de `max_celdas`
    celdas que no tocan `protegido` (el cauce: el río sin dato no se inventa)."""
    from scipy import ndimage
    hueco = np.isnan(dem)
    if not hueco.any():
        return 0
    etq, n = ndimage.label(hueco)
    if n == 0:
        return 0
    tam = np.bincount(etq.ravel())
    toca = np.zeros(n + 1, bool)
    toca[np.unique(etq[protegido & hueco])] = True
    # huecos que tocan el borde de la grilla tampoco se rellenan
    for borde in (etq[0], etq[-1], etq[:, 0], etq[:, -1]):
        toca[np.unique(borde)] = True
    chico = (tam <= max_celdas) & ~toca
    chico[0] = False
    total = 0
    for i, sl in enumerate(ndimage.find_objects(etq), 1):
        if sl is None or not chico[i]:
            continue
        f0 = max(sl[0].start - 2, 0); f1 = min(sl[0].stop + 2, dem.shape[0])
        c0 = max(sl[1].start - 2, 0); c1 = min(sl[1].stop + 2, dem.shape[1])
        sub = dem[f0:f1, c0:c1]
        h = np.isnan(sub)
        este = etq[f0:f1, c0:c1] == i
        _, (fi, ci) = ndimage.distance_transform_edt(h, return_indices=True)
        sub[este] = sub[fi[este], ci[este]]
        fuente[f0:f1, c0:c1][este] = RELLENO
        total += int(este.sum())
    return total
