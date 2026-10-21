"""Validaciones de la salida contra docs/mapa/05-contrato.md.

Cada función devuelve una lista de errores (vacía = bien). El pipeline no publica nada si
alguna lista sale con errores.
"""
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path

RE_CAPA = re.compile(r"^agua/(\d{4})\.json$")
RE_CURVA = re.compile(r"^curvas/\d{4}-\d{2}\.json$")
RE_SHA = re.compile(r"^[0-9a-f]{64}$")


def _num(x) -> bool:
    return isinstance(x, (int, float)) and not isinstance(x, bool)


def validar_indice(ind: dict, cero_esperado: str = "Local") -> list[str]:
    e: list[str] = []
    for k in ("version", "generado", "cero", "validado", "modelo", "limites", "paso_m", "min_m",
              "max_m", "base", "capas", "referencias", "fuentes"):
        if k not in ind:
            e.append(f"falta la clave '{k}'")
    if e:
        return e
    # estricto: True == 1 y 1.0 == 1 en Python, pero el contrato pide el entero 1
    if type(ind["version"]) is not int or ind["version"] != 1:
        e.append("version debe ser el entero 1")
    if ind["cero"] != cero_esperado:
        e.append(f"cero '{ind['cero']}' distinto de '{cero_esperado}'")
    if not isinstance(ind["validado"], bool):
        e.append("validado debe ser booleano")
    if not re.match(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{2}:\d{2}$", str(ind["generado"])):
        e.append("generado no es ISO 8601 con zona horaria")
    m = ind["modelo"]
    for k in ("metodo", "delta_m", "iou_validacion", "margen_m"):
        if k not in m:
            e.append(f"modelo sin '{k}'")
    # la franja de margen es lo que cubre el error del modelo: nunca menos de 10 cm (una capa)
    if "margen_m" in m and (not _num(m["margen_m"]) or m["margen_m"] < 0.1 - 1e-9):
        e.append(f"modelo.margen_m {m['margen_m']} tiene que ser un número ≥ 0,1")
    lim = ind["limites"]
    try:
        (s, o), (n, es) = lim
        if not (s < n and o < es and -90 <= s <= 90 and -180 <= o <= 180):
            e.append("limites mal ordenados ([[S, O], [N, E]])")
    except (TypeError, ValueError):
        e.append("limites no es [[S, O], [N, E]]")
    for k in ("paso_m", "min_m", "max_m"):
        if not _num(ind[k]):
            e.append(f"{k} no es número")
    if e:
        return e
    min_cm, paso_cm = round(ind["min_m"] * 100, 6), round(ind["paso_m"] * 100, 6)
    if paso_cm <= 0 or paso_cm != int(paso_cm) or min_cm != int(min_cm):
        e.append("paso_m tiene que ser > 0 y paso_m y min_m tienen que ser centímetros enteros")
        return e
    # la app redondea hacia arriba al paso (capa_para): min_m fuera de la grilla del paso
    # desarma los nombres agua/NNNN.json y el redondeo
    if int(min_cm) % int(paso_cm):
        e.append(f"min_m {ind['min_m']} no es múltiplo de paso_m {ind['paso_m']}")
    extra_sv = [(ind["sin_validar"], "sin_validar")] if "sin_validar" in ind else []
    if extra_sv and ind["sin_validar"].get("archivo") != "sin_validar.json":
        e.append("sin_validar: archivo debe ser 'sin_validar.json'")
    for ent, nombre in [(ind["base"], "base")] + [(c, f"capa {i}") for i, c in enumerate(ind["capas"])] \
            + [(r, f"referencia {i}") for i, r in enumerate(ind["referencias"])] + extra_sv:
        for k in ("archivo", "bytes", "sha256"):
            if k not in ent:
                e.append(f"{nombre} sin '{k}'")
        if "sha256" in ent and not RE_SHA.match(str(ent["sha256"])):
            e.append(f"{nombre}: sha256 inválido")
        if "bytes" in ent and (not isinstance(ent["bytes"], int) or ent["bytes"] <= 0):
            e.append(f"{nombre}: bytes inválido")
    capas = ind["capas"]
    n_esperado = int(round((ind["max_m"] - ind["min_m"]) / ind["paso_m"])) + 1
    if len(capas) != n_esperado:
        e.append(f"hay {len(capas)} capas y se esperaban {n_esperado}")
    for i, c in enumerate(capas):
        esperado = round(ind["min_m"] + i * ind["paso_m"], 2)
        if not _num(c.get("altura_m")) or abs(c["altura_m"] - esperado) > 1e-6:
            e.append(f"capa {i}: altura_m {c.get('altura_m')} y se esperaba {esperado} (orden/paso/huecos)")
            continue
        nombre = f"agua/{int(round(esperado * 100)):04d}.json"
        if c.get("archivo") != nombre:
            e.append(f"capa {i}: archivo {c.get('archivo')} y se esperaba {nombre}")
    for i, r in enumerate(ind["referencias"]):
        for k in ("tipo", "nombre", "altura_m", "fecha", "fuente"):
            if k not in r:
                e.append(f"referencia {i} sin '{k}'")
        if "archivo" in r and not RE_CURVA.match(r["archivo"]):
            e.append(f"referencia {i}: archivo {r['archivo']} no es curvas/AAAA-MM.json")
    if not isinstance(ind["fuentes"], list) or not ind["fuentes"]:
        e.append("fuentes vacío")
    return e


def validar_archivos(carpeta: Path, ind: dict) -> list[str]:
    """bytes y sha256 de cada archivo listado, tal como quedó en disco."""
    e = []
    ents = [ind["base"]] + list(ind["capas"]) + list(ind["referencias"]) + \
        ([ind["sin_validar"]] if "sin_validar" in ind else [])
    for ent in ents:
        ruta = Path(carpeta) / ent["archivo"]
        if not ruta.exists():
            e.append(f"falta {ent['archivo']}")
            continue
        datos = ruta.read_bytes()
        if len(datos) != ent["bytes"]:
            e.append(f"{ent['archivo']}: bytes {len(datos)} ≠ índice {ent['bytes']}")
        if hashlib.sha256(datos).hexdigest() != ent["sha256"]:
            e.append(f"{ent['archivo']}: sha256 no coincide")
    return e


def validar_capa(fc: dict, altura_m: float, limites, min_calles_m: float = 0) -> list[str]:
    """Una capa agua/NNNN.json: estructura, MultiPolygon válido, dentro de los límites y,
    si está, la lista `aisladas` (v1.1 §2)."""
    import shapely
    from shapely.geometry import Point, shape
    e = []
    if fc.get("type") != "FeatureCollection" or len(fc.get("features", [])) != 1:
        return ["no es una FeatureCollection con un solo Feature"]
    f = fc["features"][0]
    if f.get("type") != "Feature":
        e.append("el elemento no es un Feature")
    props = f.get("properties") or {}
    if props.get("altura_m") != altura_m or set(props) - {"altura_m", "aisladas"}:
        e.append(f"properties {props} ≠ {{'altura_m': {altura_m}[, 'aisladas': [...]]}}")
    g = f.get("geometry") or {}
    if g.get("type") != "MultiPolygon":
        return e + ["la geometría no es MultiPolygon"]
    if g.get("coordinates") == []:
        if props.get("aisladas"):
            e.append("capa vacía con lomas aisladas")
        return e
    geom = shape(g)
    if not geom.is_valid:
        e.append(f"geometría inválida: {shapely.is_valid_reason(geom)}")
    (s, o), (n, es) = limites
    x0, y0, x1, y1 = geom.bounds
    tol = 1e-5
    if x0 < o - tol or x1 > es + tol or y0 < s - tol or y1 > n + tol:
        e.append(f"bbox {geom.bounds} fuera de los límites")
    ais = props.get("aisladas")
    if ais is not None:
        if not isinstance(ais, list):
            return e + ["aisladas no es una lista"]
        for i, a in enumerate(ais):
            if not isinstance(a, dict) or set(a) != {"c", "ha", "calles_m"}:
                e.append(f"aislada {i}: claves {sorted(a) if isinstance(a, dict) else a} ≠ c, ha, calles_m")
                continue
            c = a["c"]
            if not (isinstance(c, list) and len(c) == 2 and all(_num(x) for x in c)):
                e.append(f"aislada {i}: c no es [lon, lat]")
                continue
            if not (o < c[0] < es and s < c[1] < n):
                e.append(f"aislada {i}: c {c} fuera de los límites")
            elif geom.intersects(Point(c)):
                e.append(f"aislada {i}: c {c} cae sobre el agua de la capa")
            if not _num(a["ha"]) or a["ha"] <= 0:
                e.append(f"aislada {i}: ha inválido")
            if not isinstance(a["calles_m"], int) or a["calles_m"] < min_calles_m:
                e.append(f"aislada {i}: calles_m {a['calles_m']} < {min_calles_m}")
    return e


def validar_sin_validar(fc: dict, limites, decimales: int = 5) -> list[str]:
    """sin_validar.json (v1.1 §1): FeatureCollection con un Feature Polygon/MultiPolygon por
    zona, válido, dentro de los límites, a `decimales` decimales, con nombre y motivo."""
    import shapely
    from shapely.geometry import shape
    e = []
    if fc.get("type") != "FeatureCollection" or not fc.get("features"):
        return ["no es una FeatureCollection con al menos un Feature"]
    (s, o), (n, es) = limites
    for i, f in enumerate(fc["features"]):
        pr = f.get("properties") or {}
        if set(pr) != {"nombre", "motivo"} or not all(isinstance(pr[k], str) and pr[k] for k in ("nombre", "motivo")):
            e.append(f"zona {i}: properties {pr} ≠ {{nombre, motivo}}")
        g = f.get("geometry") or {}
        if g.get("type") not in ("Polygon", "MultiPolygon") or not g.get("coordinates"):
            e.append(f"zona {i}: geometría {g.get('type')} vacía o no poligonal")
            continue
        geom = shape(g)
        if not geom.is_valid:
            e.append(f"zona {i}: geometría inválida: {shapely.is_valid_reason(geom)}")
        x0, y0, x1, y1 = geom.bounds
        if x0 < o - 1e-5 or x1 > es + 1e-5 or y0 < s - 1e-5 or y1 > n + 1e-5:
            e.append(f"zona {i}: fuera de los límites")
        xy = shapely.get_coordinates(geom)
        if (abs(xy - xy.round(decimales)) > 1e-9).any():
            e.append(f"zona {i}: coordenadas con más de {decimales} decimales")
    return e


def validar_anidado(geoms: list, tolerancia: float) -> list[str]:
    """geoms[i] (altura creciente) debe quedar dentro de geoms[i+1], salvo `tolerancia` del área."""
    e = []
    for i in range(len(geoms) - 1):
        a, b = geoms[i], geoms[i + 1]
        if a.is_empty:
            continue
        fuera = a.difference(b).area
        if fuera > tolerancia * a.area:
            e.append(f"capa {i} no está dentro de la {i + 1}: {fuera / a.area:.2%} afuera")
    return e


def validar_areas(alturas: list[float], areas_m2: list[float], max_vacia: bool) -> list[str]:
    """Controles de plausibilidad de las capas (I3 b):
    - la capa de `max_m` (la última) no puede estar vacía: con el río en el máximo del
      mapa siempre hay agua sobre tierra; vacía quiere decir terreno, cauce o δ roto;
    - el área mojada (raster, antes de poligonizar) no puede bajar al subir la altura
      (las capas son anidadas) y tiene que crecer entre `min_m` y `max_m`. Dos capas
      seguidas con la misma área se aceptan (en una franja angosta puede no entrar agua)."""
    e = []
    if not areas_m2:
        return ["no hay capas"]
    if max_vacia or areas_m2[-1] <= 0:
        e.append(f"la capa de {alturas[-1]:.2f} m (max_m) está vacía")
    for i in range(len(areas_m2) - 1):
        if areas_m2[i + 1] < areas_m2[i]:
            e.append(f"el área baja de {areas_m2[i] / 1e4:.2f} ha a {alturas[i]:.2f} m "
                     f"a {areas_m2[i + 1] / 1e4:.2f} ha a {alturas[i + 1]:.2f} m")
    if len(areas_m2) > 1 and areas_m2[-1] <= areas_m2[0]:
        e.append(f"el área no crece entre {alturas[0]:.2f} m y {alturas[-1]:.2f} m "
                 f"({areas_m2[0] / 1e4:.2f} ha → {areas_m2[-1] / 1e4:.2f} ha)")
    return e


def validar_bytes(tamanos: dict, tope_capa: int, tope_base: int, tope_total: int) -> list[str]:
    e = []
    for nombre, b in tamanos.items():
        tope = tope_base if nombre == "base.json" else tope_capa
        if nombre.startswith("agua/") or nombre == "base.json":
            if b > tope:
                e.append(f"{nombre}: {b} bytes supera el tope de {tope}")
    total = sum(tamanos.values())
    if total > tope_total:
        e.append(f"total {total} bytes supera el tope de {tope_total}")
    return e


def cargar_json(ruta: Path) -> dict:
    return json.loads(Path(ruta).read_text(encoding="utf-8"))
