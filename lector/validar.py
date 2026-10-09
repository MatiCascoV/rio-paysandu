"""Controles sobre las lecturas. No corrigen datos: solo los descartan o avisan."""
from datetime import timedelta

ALTURA_MIN_M = 0.0
ALTURA_MAX_M = 20.0
SALTO_MAX_M = 1.0
SALTO_VENTANA = timedelta(hours=6)


def en_rango(valor_m):
    return valor_m is not None and ALTURA_MIN_M <= valor_m <= ALTURA_MAX_M


def horas_de_antiguedad(fecha, ahora):
    return (ahora - fecha).total_seconds() / 3600


def salto_sospechoso(valor_m, fecha, referencias):
    """True si la altura cambió más de 1 m en menos de 6 h respecto de alguna
    lectura de referencia. `referencias` es una lista de (valor_m, fecha)."""
    for ref_valor, ref_fecha in referencias:
        if ref_valor is None or ref_fecha is None or ref_fecha == fecha:
            continue
        if abs(fecha - ref_fecha) < SALTO_VENTANA and abs(valor_m - ref_valor) > SALTO_MAX_M:
            return True
    return False
