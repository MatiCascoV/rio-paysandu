"""Cota de llegada del agua desde el cauce (priority-flood por umbrales, conectividad 4).

Para cada celda, `llegada` es la cota mínima del río (en la referencia vertical del MDT)
a la que el agua la alcanza por superficie: el mínimo, sobre todos los caminos 4-conexos
desde el cauce, del máximo de cota a lo largo del camino. Es exactamente lo que da un
priority-flood.

Implementación: se recorren umbrales enteros en centímetros (`min_cm`, `min_cm + q`, …,
`max_cm`). En cada umbral se etiquetan (scipy, 4-conectividad) las celdas con cota ≤ umbral
más el cauce, y se mojan las componentes que tocan el cauce. La llegada de una celda es
el primer umbral en que se moja. Así:
- `llegada <= t` es exacto para todo umbral t de la grilla de cuantización;
- las capas quedan anidadas por construcción;
- la memoria es lineal (unas pocas copias de la grilla), sin colas de prioridad en Python.

Valores especiales (int32, centímetros):
- `NUNCA` (2**31-1): no se moja ni en `max_cm` (o sin dato).
"""
from __future__ import annotations

import logging

import numpy as np

log = logging.getLogger("mapa")

NUNCA = np.iinfo(np.int32).max
CRUZ = np.array([[0, 1, 0], [1, 1, 1], [0, 1, 0]], dtype=bool)


def llegada_cm(dem: np.ndarray, semilla: np.ndarray, min_cm: int, max_cm: int, paso_cm: int,
               valido: np.ndarray | None = None) -> np.ndarray:
    """Devuelve la cota de llegada en cm (int32) para cada celda.

    dem: cota del terreno en metros (NaN = sin dato, actúa como pared).
    semilla: máscara del cauce (siempre mojado; su llegada es `min_cm`).
    """
    from scipy import ndimage

    if dem.shape != semilla.shape:
        raise ValueError("dem y semilla con distinta forma")
    if paso_cm <= 0 or max_cm < min_cm:
        raise ValueError("umbrales inválidos")
    if not semilla.any():
        raise ValueError("la máscara del cauce está vacía: no hay de dónde llenar")
    if valido is None:
        valido = ~np.isnan(dem)
    cota_cm = np.full(dem.shape, NUNCA, dtype=np.int32)
    ok = valido & ~np.isnan(dem)
    # redondeo hacia arriba al cm: una celda de 4,661 m se moja con el agua a 4,67 m
    cota_cm[ok] = np.ceil(np.round(dem[ok].astype(np.float64) * 100, 6)).astype(np.int32)

    llegada = np.full(dem.shape, NUNCA, dtype=np.int32)
    llegada[semilla] = min_cm
    mojado = semilla.copy()
    # recorte: solo importan las celdas que se pueden mojar antes de max_cm
    candidato = (cota_cm <= max_cm) | semilla
    filas = np.flatnonzero(candidato.any(axis=1))
    cols = np.flatnonzero(candidato.any(axis=0))
    f0, f1 = filas[0], filas[-1] + 1
    c0, c1 = cols[0], cols[-1] + 1
    sub_cota = cota_cm[f0:f1, c0:c1]
    sub_moj = mojado[f0:f1, c0:c1]
    sub_lleg = llegada[f0:f1, c0:c1]
    sub_sem = semilla[f0:f1, c0:c1]

    for t in range(min_cm, max_cm + 1, paso_cm):
        mascara = (sub_cota <= t) | sub_sem
        etq, n = ndimage.label(mascara, structure=CRUZ)
        if n == 0:
            continue
        tabla = np.zeros(n + 1, dtype=bool)
        tabla[etq[sub_sem]] = True
        tabla[0] = False
        nuevo = tabla[etq] & ~sub_moj
        if nuevo.any():
            sub_lleg[nuevo] = t
            sub_moj |= nuevo
    return llegada


def llegada_referencia(dem: np.ndarray, semilla: np.ndarray) -> np.ndarray:
    """Priority-flood clásico con cola de prioridad (lento; solo para tests chicos).
    Devuelve la llegada en metros (inf = nunca)."""
    import heapq
    alto, ancho = dem.shape
    out = np.full(dem.shape, np.inf)
    cola = []
    for f, c in zip(*np.nonzero(semilla)):
        out[f, c] = -np.inf
        heapq.heappush(cola, (-np.inf, f, c))
    while cola:
        v, f, c = heapq.heappop(cola)
        if v > out[f, c]:
            continue
        for df, dc in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            g, d = f + df, c + dc
            if 0 <= g < alto and 0 <= d < ancho and not np.isnan(dem[g, d]):
                nv = max(v, dem[g, d])
                if nv < out[g, d]:
                    out[g, d] = nv
                    heapq.heappush(cola, (nv, g, d))
    return out


def umbral_cm(h_local: float, delta: float) -> int:
    """Umbral entero (cm) en la referencia del MDT para una altura local y un desfase δ."""
    return int(round((h_local + delta) * 100))


def umbral_en_grilla(t: int, min_cm: int, q: int, max_cm: int, redondear: bool = False) -> int:
    """Comprueba que el umbral t (cm) sea uno de los que recorre `llegada_cm`.

    `llegada <= t` solo es exacto si t está en la grilla de cuantización
    (min_cm, min_cm + q, …) y entre min_cm y max_cm:
    - con t fuera de la grilla, `llegada <= t` equivale a `llegada <= t'` con t' el umbral
      de la grilla de abajo: se moja **menos** de lo que corresponde a t;
    - con t > max_cm, las celdas que se mojarían entre max_cm y t quedan en NUNCA (secas);
    - con t < min_cm no se moja nada (la llegada mínima es min_cm).

    Con `redondear=False` (capas publicadas) cualquiera de esos casos es ValueError.
    Con `redondear=True` (curvas de calibración, que pueden tener una cota impar en cm) un t
    fuera de la grilla se sube al umbral siguiente de la grilla: del lado prudente (más
    agua), en vez de evaluarlo un escalón abajo. Si al subir pasa max_cm, igual es error.
    """
    t, min_cm, q, max_cm = int(t), int(min_cm), int(q), int(max_cm)
    if q <= 0:
        raise ValueError(f"cuantizacion_cm {q} tiene que ser > 0")
    if t < min_cm:
        raise ValueError(f"umbral {t} cm debajo de min_cm {min_cm}: no se mojaría nada")
    resto = (t - min_cm) % q
    if resto:
        if not redondear:
            raise ValueError(f"umbral {t} cm fuera de la grilla de cuantización ({min_cm} + k·{q})")
        t += q - resto
    if t > max_cm:
        raise ValueError(f"umbral {t} cm por encima de max_cm {max_cm}: faltaría agua")
    return t
