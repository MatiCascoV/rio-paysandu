"""Imagen PNG de control: capas elegidas sobre una curva real."""
from __future__ import annotations

import math


def dibujar(ruta_png, base: dict, capas: list[tuple[float, object]], curva, titulo: str, limites) -> None:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib.patches import Patch
    from matplotlib.lines import Line2D
    from shapely.geometry import shape

    (s, o), (n, e) = limites
    fig, ax = plt.subplots(figsize=(10, 11.5), dpi=130)
    ax.set_facecolor("#f4f1ea")

    from matplotlib.path import Path
    from matplotlib.patches import PathPatch
    import numpy as np

    def pintar(g, **kw):
        """Polígonos con huecos como un solo PathPatch (los huecos quedan transparentes)."""
        polys = [p for p in getattr(g, "geoms", [g]) if not p.is_empty and p.geom_type == "Polygon"]
        if not polys:
            return
        verts, codes = [], []
        from shapely.geometry.polygon import orient
        for p in polys:
            p = orient(p, 1.0)  # exterior antihorario, huecos horarios (regla nonzero)
            for anillo in [p.exterior, *p.interiors]:
                xy = np.asarray(anillo.coords)
                verts.append(xy)
                codes.append(np.r_[Path.MOVETO, np.full(len(xy) - 2, Path.LINETO), Path.CLOSEPOLY])
        kw.setdefault("lw", 0)
        color = kw.pop("color")
        ax.add_patch(PathPatch(Path(np.concatenate(verts), np.concatenate(codes)), facecolor=color, edgecolor="none", **kw))

    for f in base["features"]:
        t = f["properties"]["t"]
        g = shape(f["geometry"])
        if t == "agua":
            pintar(g, color="#9cc3e6", lw=0)
        elif t == "calle":
            k = f["properties"].get("k", 3)
            for ln in getattr(g, "geoms", [g]):
                ax.plot(*ln.xy, color="#888", lw={1: 1.2, 2: 0.8}.get(k, 0.35), zorder=2)
    colores = ["#1f4e9c", "#4fa3e0", "#7fd0ff"]
    leyenda = []
    for i, (h, g) in enumerate(sorted(capas, key=lambda x: -x[0])):
        c = colores[(len(capas) - 1 - i) % len(colores)]
        pintar(g, color=c, alpha=0.55 if i == 0 else 0.8, lw=0, zorder=3 + i)
        leyenda.append(Patch(color=c, alpha=0.7, label=f"Modelo {h:.2f} m".replace(".", ",")))
    if curva is not None:
        for p in getattr(curva.geom, "geoms", [curva.geom]):
            ax.plot(*p.exterior.xy, color="#d62728", lw=1.4, zorder=10)
        leyenda.append(Line2D([0], [0], color="#d62728", lw=1.4,
                              label=f"{curva.nombre} ({curva.altura_m:.2f} m, Dinagua)".replace(".", ",")))
    ax.set_xlim(o, e); ax.set_ylim(s, n)
    ax.set_aspect(1 / math.cos(math.radians((s + n) / 2)))
    ax.legend(handles=leyenda, loc="lower right", fontsize=9)
    ax.set_title(titulo, fontsize=11)
    ax.tick_params(labelsize=7)
    fig.tight_layout()
    fig.savefig(ruta_png)
    plt.close(fig)
