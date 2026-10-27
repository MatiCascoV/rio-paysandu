"""Arma los datos de la pestaña Crecidas (app/assets/crecidas/).

Uso:
    python bordes_crecidas.py <carpeta de salida del mapa> <app/assets/crecidas>

Entrada (salida del pipeline del mapa, rama mapa-inundacion):
    indice.json   -> solo se usan `limites`, `base` y `referencias`
    base.json     -> se copia tal cual (calles, río y arroyos de OSM)
    curvas/*.json -> polígonos de Dinagua (capa dinagua:curvas_cri)

Qué hace con cada curva: Dinagua entrega cada crecida como un polígono
cerrado. Del lado del río, y en los extremos norte y sur, ese polígono se
cierra con tramos rectos que cruzan el cauce: es el límite del área
relevada, no hasta dónde llegó el agua. Si se dibujara el contorno entero,
aparecería una raya en medio del río Uruguay.

Regla (no mueve ningún punto, solo deja de dibujar tramos):
  1. Se recorre cada anillo segmento por segmento.
  2. Se saca un segmento si mide más de TOPE_M y al menos el 10 % de su
     largo cae dentro del agua de base.json (el cauce). Esos son los
     cierres del relevamiento.
  3. Lo que queda se parte en líneas. Se descartan las líneas que caen casi
     enteras (90 % o más) dentro del cauce y las de menos de MIN_M.
Los bordes en tierra quedan con los mismos puntos que da Dinagua.

Salida: base.json, curvas/AAAA-MM.json (MultiLineString) e indice.json con
bytes y sha256 de cada archivo. Necesita shapely.
"""

import hashlib
import json
import math
import os
import shutil
import sys

from shapely.geometry import LineString, shape
from shapely.ops import unary_union

TOPE_M = 250.0
EN_RIO_CORTE = 0.10
EN_RIO_LINEA = 0.90
MIN_M = 20.0


def metros(a, b):
    dx = (a[0] - b[0]) * 111320 * math.cos(math.radians(32.3))
    dy = (a[1] - b[1]) * 110574
    return math.hypot(dx, dy)


def largo(linea):
    return sum(metros(linea[i], linea[i + 1]) for i in range(len(linea) - 1))


def fraccion_en(agua, a, b):
    seg = LineString([a, b])
    return seg.intersection(agua).length / seg.length if seg.length else 0.0


def bordes(anillo, agua):
    """Partes del anillo que son borde del agua (sin cierres)."""
    n = len(anillo) - 1  # el último repite el primero
    corta = [
        metros(anillo[i], anillo[i + 1]) > TOPE_M and fraccion_en(agua, anillo[i], anillo[i + 1]) >= EN_RIO_CORTE
        for i in range(n)
    ]
    if not any(corta):
        return [anillo]
    # Empezar justo después de un corte para no partir una línea en dos.
    inicio = corta.index(True) + 1
    lineas, actual = [], [anillo[inicio % n]]
    for k in range(n):
        i = (inicio + k) % n
        if corta[i]:
            if len(actual) > 1:
                lineas.append(actual)
            actual = [anillo[(i + 1) % n]]
        else:
            actual.append(anillo[(i + 1) % n])
    if len(actual) > 1:
        lineas.append(actual)
    salida = []
    for l in lineas:
        if largo(l) < MIN_M:
            continue
        g = LineString(l)
        if g.intersection(agua).length / g.length >= EN_RIO_LINEA:
            continue
        salida.append(l)
    return salida


def huella(ruta):
    with open(ruta, "rb") as f:
        datos = f.read()
    return len(datos), hashlib.sha256(datos).hexdigest()


def main(entrada, salida):
    indice = json.load(open(os.path.join(entrada, "indice.json"), encoding="utf-8"))
    base = json.load(open(os.path.join(entrada, "base.json"), encoding="utf-8"))
    agua = unary_union(
        [shape(f["geometry"]).buffer(0) for f in base["features"] if f["properties"].get("t") == "agua"]
    )
    os.makedirs(os.path.join(salida, "curvas"), exist_ok=True)
    shutil.copyfile(os.path.join(entrada, "base.json"), os.path.join(salida, "base.json"))
    b_bytes, b_sha = huella(os.path.join(salida, "base.json"))

    crecidas = []
    for ref in indice["referencias"]:
        if ref.get("tipo") != "crecida" or not ref.get("archivo", "").startswith("curvas/"):
            continue
        curva = json.load(open(os.path.join(entrada, ref["archivo"]), encoding="utf-8"))
        lineas = []
        for f in curva["features"]:
            g = f["geometry"]
            poligonos = g["coordinates"] if g["type"] == "MultiPolygon" else [g["coordinates"]]
            for p in poligonos:
                for anillo in p:
                    lineas.extend(bordes(anillo, agua))
        props = curva["features"][0]["properties"]
        assert abs(props["altura_m"] - ref["altura_m"]) < 1e-9, ref["archivo"]
        salida_curva = {
            "type": "FeatureCollection",
            "features": [
                {
                    "type": "Feature",
                    "properties": {
                        "nombre": ref["nombre"],
                        "altura_m": ref["altura_m"],
                        "fecha": ref["fecha"],
                        "fuente": ref["fuente"],
                    },
                    "geometry": {"type": "MultiLineString", "coordinates": lineas},
                }
            ],
        }
        ruta = os.path.join(salida, ref["archivo"])
        with open(ruta, "w", encoding="utf-8", newline="\n") as f:
            json.dump(salida_curva, f, ensure_ascii=False, separators=(",", ":"))
        n_bytes, n_sha = huella(ruta)
        quedan = sum(largo(l) for l in lineas)
        print(f"{ref['archivo']}: {len(lineas)} líneas, {quedan / 1000:.1f} km de borde")
        crecidas.append(
            {
                "nombre": ref["nombre"],
                "altura_m": ref["altura_m"],
                "fecha": ref["fecha"],
                "fuente": ref["fuente"],
                "archivo": ref["archivo"],
                "bytes": n_bytes,
                "sha256": n_sha,
            }
        )
    crecidas.sort(key=lambda c: c["fecha"], reverse=True)
    nuevo = {
        "version": 1,
        "limites": indice["limites"],
        "base": {"archivo": "base.json", "bytes": b_bytes, "sha256": b_sha},
        "crecidas": crecidas,
        "fuentes": [
            "Bordes de las crecidas: Dirección Nacional de Aguas (Dinagua), Ministerio de Ambiente",
            "Calles, río y arroyos: © colaboradores de OpenStreetMap, ODbL",
        ],
    }
    with open(os.path.join(salida, "indice.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump(nuevo, f, ensure_ascii=False, indent=1)
        f.write("\n")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
