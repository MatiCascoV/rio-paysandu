"""base.json desde un extracto .osm.pbf (misma lógica que docs/mapa/herramientas/extraer_osm.py,
con la caja tomada de la configuración)."""
from __future__ import annotations

CLASES = {
    "motorway": 1, "trunk": 1, "primary": 1, "trunk_link": 1, "primary_link": 1,
    "secondary": 2, "secondary_link": 2, "tertiary": 2,
    "unclassified": 3, "residential": 3, "living_street": 3, "pedestrian": 3,
}


def extraer(pbf: str, limites) -> dict:
    import osmium
    import shapely
    from shapely import wkb
    from shapely.geometry import box, mapping

    (S, O), (N, E) = limites
    caja = box(O, S, E, N)
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
            g = g.intersection(caja)
            if g.is_empty:
                return
            if hw in CLASES:
                self.calles.append((w.id, CLASES[hw], w.tags.get("name"), g))
            else:
                self.cursos.append((w.id, w.tags.get("name"), g))

        def area(self, a):
            t = a.tags
            if not (t.get("natural") == "water" or t.get("waterway") == "riverbank" or t.get("landuse") == "reservoir"):
                return
            try:
                g = wkb.loads(fab.create_multipolygon(a), hex=True)
            except Exception:
                return
            if not g.intersects(caja):
                return
            g = g.intersection(caja)
            if not g.is_empty:
                self.agua.append((a.id, g))

    def coords(g, tol):
        return mapping(shapely.set_precision(g.simplify(tol, preserve_topology=True), 1e-5))

    lec = Lector()
    lec.apply_file(pbf, locations=True)
    # orden estable (determinismo)
    lec.agua.sort(key=lambda x: x[0]); lec.cursos.sort(key=lambda x: x[0]); lec.calles.sort(key=lambda x: x[0])
    lec.lugares.sort(key=lambda x: (x["n"], x["c"]))
    feats = []
    for _, g in lec.agua:
        feats.append({"type": "Feature", "properties": {"t": "agua"}, "geometry": coords(g, 0.00004)})
    for _, nombre, g in lec.cursos:
        feats.append({"type": "Feature", "properties": {"t": "curso", "n": nombre}, "geometry": coords(g, 0.00003)})
    for _, clase, nombre, g in lec.calles:
        feats.append({"type": "Feature", "properties": {"t": "calle", "k": clase, "n": nombre}, "geometry": coords(g, 0.00002)})
    return {"type": "FeatureCollection", "features": feats, "lugares": lec.lugares, "caja": [O, S, E, N]}


def poligonos_agua(base: dict):
    """Polígonos t=agua de base.json como lista shapely (EPSG:4326)."""
    from shapely.geometry import shape
    return [shape(f["geometry"]) for f in base["features"] if f["properties"].get("t") == "agua"]
