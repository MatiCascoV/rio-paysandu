"""Curvas de inundación de Dinagua (WFS) para calibrar y como referencias."""
from __future__ import annotations

import json
import urllib.parse
from dataclasses import dataclass

MESES = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto",
         "septiembre", "octubre", "noviembre", "diciembre"]


@dataclass
class Curva:
    clave: str          # "2015-12" para crecidas, "Tr10" / "Tr100" para curvas de diseño
    tipo: str           # "crecida" | "diseno"
    nombre: str
    altura_m: float     # cota_local
    fecha: str | None   # "2015-12-10"
    geom: object        # shapely, EPSG:4326 [lon, lat]
    nombre_dinagua: str


def url_wfs(base: str, capa: str, filtro: str) -> str:
    q = {"service": "WFS", "version": "2.0.0", "request": "GetFeature", "typeNames": capa,
         "outputFormat": "application/json", "srsName": "EPSG:4326", "CQL_FILTER": filtro}
    return base + "?" + urllib.parse.urlencode(q)


def leer_curvas(textos_geojson: list[str], curso: str, max_cota: float = 12.0) -> list[Curva]:
    """Interpreta las respuestas del WFS (una por capa). Devuelve las del curso pedido con cota."""
    import shapely
    from shapely.geometry import shape
    out = []
    for txt in textos_geojson:
        fc = json.loads(txt)
        crs = (fc.get("crs") or {}).get("properties", {}).get("name", "")
        if crs and "4326" not in crs:
            raise ValueError(f"las curvas vienen en {crs}, se esperaba EPSG:4326")
        for ft in fc.get("features", []):
            p = ft["properties"]
            if p.get("curso") != curso or p.get("cota_local") is None or p["cota_local"] > max_cota:
                continue
            g = shape(ft["geometry"])
            # WFS 2.0 con EPSG:4326 puede devolver lat,lon: se detecta y se corrige.
            x0, y0, x1, y1 = g.bounds
            if -40 < x0 < -25 and -65 < y0 < -50:
                g = shapely.transform(g, lambda xy: xy[:, ::-1])
            if not g.is_valid:
                g = shapely.make_valid(g)
            if "fecha_evento" in p and p["fecha_evento"]:
                fecha = p["fecha_evento"][:10]
                anio, mes = fecha[:4], int(fecha[5:7])
                out.append(Curva(f"{anio}-{mes:02d}", "crecida", f"Crecida de {MESES[mes - 1]} de {anio}",
                                 float(p["cota_local"]), fecha, g, p.get("nombre", "")))
            else:
                sig = str(p.get("sigla_tipo_curva", "")).strip().replace(" ", "")
                tr = "Tr" + sig[2:] if sig.upper().startswith("TR") else sig
                out.append(Curva(tr, "diseno", f"Curva de recurrencia {tr[2:]} años" if tr.startswith("Tr") else tr,
                                 float(p["cota_local"]), None, g, p.get("nombre", "")))
    claves = [c.clave for c in out]
    if len(set(claves)) != len(claves):
        raise ValueError(f"curvas repetidas: {claves}")
    return sorted(out, key=lambda c: c.altura_m)
