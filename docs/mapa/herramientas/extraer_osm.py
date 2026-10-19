"""Recorta de un .osm.pbf las calles, el agua y los nombres de barrios de la costa de Paysandú.

Uso: python extraer_osm.py <entrada.osm.pbf> <salida.json>
"""
import json
import sys

import osmium
import shapely
from shapely.geometry import box, mapping, shape
from shapely import wkb

O, S, E, N = -58.150, -32.365, -58.030, -32.240
CAJA = box(O, S, E, N)

CLASES = {
    "motorway": 1, "trunk": 1, "primary": 1, "trunk_link": 1, "primary_link": 1,
    "secondary": 2, "secondary_link": 2, "tertiary": 2,
    "unclassified": 3, "residential": 3, "living_street": 3, "pedestrian": 3,
}
fab = osmium.geom.WKBFactory()


def dentro(lon, lat):
    return O <= lon <= E and S <= lat <= N


class Lector(osmium.SimpleHandler):
    def __init__(self):
        super().__init__()
        self.calles, self.cursos, self.agua, self.lugares = [], [], [], []

    def node(self, n):
        p = n.tags.get("place")
        if p in ("suburb", "neighbourhood", "quarter") and "name" in n.tags and dentro(n.location.lon, n.location.lat):
            self.lugares.append({"n": n.tags["name"], "c": [round(n.location.lon, 5), round(n.location.lat, 5)]})

    def way(self, w):
        hw = w.tags.get("highway")
        ww = w.tags.get("waterway")
        if hw not in CLASES and ww not in ("river", "stream", "canal"):
            return
        try:
            if not any(dentro(nd.lon, nd.lat) for nd in w.nodes):
                return
            g = wkb.loads(fab.create_linestring(w), hex=True)
        except Exception:
            return
        g = g.intersection(CAJA)
        if g.is_empty:
            return
        if hw in CLASES:
            self.calles.append((CLASES[hw], w.tags.get("name"), g))
        else:
            self.cursos.append((w.tags.get("name"), g))

    def area(self, a):
        t = a.tags
        if not (t.get("natural") == "water" or t.get("waterway") == "riverbank" or t.get("landuse") == "reservoir"):
            return
        try:
            g = wkb.loads(fab.create_multipolygon(a), hex=True)
        except Exception:
            return
        if not g.intersects(CAJA):
            return
        g = g.intersection(CAJA)
        if not g.is_empty:
            self.agua.append(g)


def coords(g, tol):
    g = shapely.set_precision(g.simplify(tol, preserve_topology=True), 1e-5)
    return mapping(g)


def main():
    l = Lector()
    l.apply_file(sys.argv[1], locations=True)
    feats = []
    for g in l.agua:
        feats.append({"type": "Feature", "properties": {"t": "agua"}, "geometry": coords(g, 0.00004)})
    for nombre, g in l.cursos:
        feats.append({"type": "Feature", "properties": {"t": "curso", "n": nombre}, "geometry": coords(g, 0.00003)})
    for clase, nombre, g in l.calles:
        feats.append({"type": "Feature", "properties": {"t": "calle", "k": clase, "n": nombre}, "geometry": coords(g, 0.00002)})
    salida = {"type": "FeatureCollection", "features": feats, "lugares": l.lugares,
              "caja": [O, S, E, N]}
    with open(sys.argv[2], "w", encoding="utf-8") as f:
        json.dump(salida, f, ensure_ascii=False, separators=(",", ":"))
    print(len(l.agua), "agua;", len(l.cursos), "cursos;", len(l.calles), "calles;", len(l.lugares), "lugares")


if __name__ == "__main__":
    main()
