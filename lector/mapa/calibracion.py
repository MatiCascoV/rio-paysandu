"""Calibración del desfase δ (MDT ≈ cota local + δ) contra las curvas reales de Dinagua.

- Métrica: IoU solo en tierra (sin cauce), dentro de la caja de cada curva y de la
  cobertura del MDT urbano.
- δ se fija con la crecida de 2025 (Dinagua la trazó con este mismo MDT).
- Validación: IoU de 2009/2015/2017/2019 con ese δ, y dejando uno afuera (δ ajustado con
  los otros tres, evaluado en el que quedó afuera) para medir la estabilidad de δ.
- Tr10 y Tr100 son curvas de diseño: solo chequeo.
"""
from __future__ import annotations

import numpy as np

from .llegada import CRUZ


def iou(modelo: np.ndarray, curva: np.ndarray, dominio: np.ndarray) -> float:
    m = modelo & dominio
    c = curva & dominio
    union = np.count_nonzero(m | c)
    if union == 0:
        return float("nan")
    return np.count_nonzero(m & c) / union


def barrido(llegada_dom: np.ndarray, curva_dom: np.ndarray, h_local: float, deltas_cm: list[int]) -> list[float]:
    """IoU para cada δ. `llegada_dom` y `curva_dom` ya recortados al dominio (1-D)."""
    out = []
    c = curva_dom
    nc = np.count_nonzero(c)
    hc = int(round(h_local * 100))
    for d in deltas_cm:
        m = llegada_dom <= hc + d
        inter = np.count_nonzero(m & c)
        union = np.count_nonzero(m) + nc - inter
        out.append(inter / union if union else float("nan"))
    return out


def _argmax(valores) -> int:
    v = np.asarray(valores, dtype=float)
    if np.all(np.isnan(v)):
        raise ValueError("IoU indefinido en todo el barrido")
    return int(np.nanargmax(v))


def ajustar(tabla: dict[str, list[float]], deltas_cm: list[int], fija: str, validacion: list[str],
            iou_min: float, estabilidad_m: float) -> dict:
    """Decide δ y evalúa el criterio. `tabla[clave]` = IoU por δ."""
    if fija not in tabla:
        raise ValueError(f"falta la curva {fija} para fijar δ")
    faltan = [v for v in validacion if v not in tabla]
    if faltan:
        raise ValueError(f"faltan curvas de validación: {faltan}")
    i_fija = _argmax(tabla[fija])
    delta = deltas_cm[i_fija] / 100
    mejor = {k: deltas_cm[_argmax(v)] / 100 for k, v in tabla.items()}
    iou_con_delta = {k: round(float(v[i_fija]), 4) for k, v in tabla.items()}
    loo = {}
    for e in validacion:
        otros = [k for k in validacion if k != e]
        media = np.nanmean(np.array([tabla[k] for k in otros]), axis=0)
        i = _argmax(media)
        loo[e] = {"delta_m": deltas_cm[i] / 100, "iou_afuera": round(float(tabla[e][i]), 4)}
    iou_val = float(np.mean([iou_con_delta[e] for e in validacion]))
    iou_loo = float(np.mean([loo[e]["iou_afuera"] for e in validacion]))
    dispersion = max(abs(loo[e]["delta_m"] - delta) for e in validacion)
    # Criterio de docs/mapa/01 §4.1: IoU medio de validación (con el δ fijado) ≥ iou_min y δ
    # estable entre los eventos dejados afuera. El IoU dejando uno afuera se informa, pero no
    # es un segundo umbral (con δ reajustado en 3 curvas siempre da algo menos).
    cumple_iou = iou_val >= iou_min
    cumple_delta = dispersion <= estabilidad_m + 1e-9
    return {
        "delta_m": round(delta, 2),
        "iou_fija": round(float(tabla[fija][i_fija]), 4),
        "iou_con_delta": iou_con_delta,
        "mejor_delta_por_curva": mejor,
        "dejando_uno_afuera": loo,
        "iou_validacion_media": round(iou_val, 4),
        "iou_validacion_min": round(min(iou_con_delta[e] for e in validacion), 4),
        "iou_dejando_uno_afuera_media": round(iou_loo, 4),
        "dispersion_delta_m": round(dispersion, 2),
        "cumple_iou": bool(cumple_iou),
        "cumple_estabilidad": bool(cumple_delta),
        "criterio_cumplido": bool(cumple_iou and cumple_delta),
    }


def _borde(mascara: np.ndarray, dominio: np.ndarray) -> np.ndarray:
    """Celdas de la máscara con un vecino (4) del dominio que no está en la máscara."""
    from scipy import ndimage
    afuera = dominio & ~mascara
    return mascara & dominio & ndimage.binary_dilation(afuera, structure=CRUZ)


def error_borde_m(modelo: np.ndarray, curva: np.ndarray, dominio: np.ndarray, res: float) -> float:
    """Distancia media simétrica entre los bordes (m), dentro del dominio."""
    from scipy import ndimage
    bm = _borde(modelo, dominio)
    bc = _borde(curva, dominio)
    if not bm.any() or not bc.any():
        return float("nan")
    dc = ndimage.distance_transform_edt(~bc) * res
    dm = ndimage.distance_transform_edt(~bm) * res
    return float((dc[bm].mean() + dm[bc].mean()) / 2)
