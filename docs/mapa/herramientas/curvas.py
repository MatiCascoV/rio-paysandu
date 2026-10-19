import json, sys
import shapely
from shapely.geometry import shape, mapping
D = sys.argv[1]
out = []
for f, campo in (("psd_curvas_cri.json", "fecha_evento"), ("psd_curvas_tr.json", "tipo_curva")):
    for ft in json.load(open(f"{D}/{f}", encoding="utf-8"))["features"]:
        p = ft["properties"]
        if p["cota_local"] is None or p["cota_local"] > 12:
            continue
        g = shapely.set_precision(shape(ft["geometry"]).simplify(0.00002, preserve_topology=True), 1e-5)
        etq = ("Crecida " + {"01":"ene","06":"jun","07":"jul","11":"nov","12":"dic"}[p[campo][5:7]] + " " + p[campo][:4]) if campo == "fecha_evento" else "Tr " + p[campo].strip()
        out.append({"type": "Feature", "properties": {"etq": etq, "cota": p["cota_local"], "real": campo == "fecha_evento", "nombre": p["nombre"]}, "geometry": mapping(g)})
out.sort(key=lambda x: x["properties"]["cota"])
json.dump({"type": "FeatureCollection", "features": out}, open(sys.argv[2], "w", encoding="utf-8"), ensure_ascii=False, separators=(",", ":"))
for o in out: print(o["properties"]["etq"], o["properties"]["cota"])
