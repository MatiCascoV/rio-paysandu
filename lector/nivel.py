"""Cálculo del nivel (normal / atención / alerta / evacuación) contra los umbrales."""
import math

# Valores con los que se crea data/umbrales.json si no existe. Alerta y evacuación
# son los que publica CARU para Paysandú (informes de crecida 2026 y registro de
# alturas). No hay un valor oficial de "atención" por debajo de la alerta, así que
# queda sin definir (null) hasta que el Cecoed indique uno.
UMBRALES_PROVISORIOS = {
    "validado": False,
    "cero": "Local",
    "atencion_m": None,
    "alerta_m": 4.39,
    "evacuacion_m": 6.89,
    "actualizado": "2026-10-09",
}


NIVELES_CON_DATO = ("normal", "atencion", "alerta", "evacuacion")


def _altura_valida(v):
    return type(v) in (int, float) and math.isfinite(v) and 0 < v <= 20


def umbrales_validos(u):
    """Los umbrales se editan a mano: se controla que sean alturas razonables y
    que estén en orden (atención < alerta < evacuación). Atención puede faltar."""
    try:
        alerta, evacuacion, atencion = u["alerta_m"], u["evacuacion_m"], u.get("atencion_m")
    except (KeyError, TypeError, AttributeError):
        return False
    if not (_altura_valida(alerta) and _altura_valida(evacuacion) and alerta < evacuacion):
        return False
    return atencion is None or (_altura_valida(atencion) and atencion < alerta)


def calcular_nivel(valor_m, umbrales):
    if valor_m is None:
        return "sin_dato"
    if valor_m >= umbrales["evacuacion_m"]:
        return "evacuacion"
    if valor_m >= umbrales["alerta_m"]:
        return "alerta"
    atencion = umbrales.get("atencion_m")
    if atencion is not None and valor_m >= atencion:
        return "atencion"
    return "normal"
