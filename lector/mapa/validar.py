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
    if ind["version"] != 1:
        e.append("version debe ser 1")
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
    for ent, nombre in [(ind["base"], "base")] + [(c, f"capa {i}") for i, c in enumerate(ind["capas"])] \
            + [(r, f"referencia {i}") for i, r in enumerate(ind["referencias"])]:
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
    ents = [ind["base"]] + list(ind["capas"]) + list(ind["referencias"])
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


def validar_capa(fc: dict, altura_m: float, limites) -> list[str]:
    """Una capa agua/NNNN.json: estructura, MultiPolygon válido, dentro de los límites."""
    import shapely
    from shapely.geometry import shape
    e = []
    if fc.get("type") != "FeatureCollection" or len(fc.get("features", [])) != 1:
        return ["no es una FeatureCollection con un solo Feature"]
    f = fc["features"][0]
    if f.get("type") != "Feature":
        e.append("el elemento no es un Feature")
    if f.get("properties") != {"altura_m": altura_m}:
        e.append(f"properties {f.get('properties')} ≠ {{'altura_m': {altura_m}}}")
    g = f.get("geometry") or {}
    if g.get("type") != "MultiPolygon":
        return e + ["la geometría no es MultiPolygon"]
    if g.get("coordinates") == []:
        return e
    geom = shape(g)
    if not geom.is_valid:
        e.append(f"geometría inválida: {shapely.is_valid_reason(geom)}")
    (s, o), (n, es) = limites
    x0, y0, x1, y1 = geom.bounds
    tol = 1e-5
    if x0 < o - tol or x1 > es + tol or y0 < s - tol or y1 > n + tol:
        e.append(f"bbox {geom.bounds} fuera de los límites")
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
