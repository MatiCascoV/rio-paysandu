"""Cálculo del nivel (normal / atención / alerta / evacuación) contra los umbrales."""

UMBRALES_PROVISORIOS = {
    "validado": False,
    "cero": "Local",
    "atencion_m": 5.0,
    "alerta_m": 6.0,
    "evacuacion_m": 6.89,
    "actualizado": "2026-10-09",
}


def calcular_nivel(valor_m, umbrales):
    if valor_m is None:
        return "sin_dato"
    if valor_m >= umbrales["evacuacion_m"]:
        return "evacuacion"
    if valor_m >= umbrales["alerta_m"]:
        return "alerta"
    if valor_m >= umbrales["atencion_m"]:
        return "atencion"
    return "normal"
