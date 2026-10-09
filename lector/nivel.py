"""Cálculo del nivel (normal / atención / alerta / evacuación) contra los umbrales."""

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
