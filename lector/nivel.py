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


def _a_mm(v):
    # Las alturas vienen con 2 decimales y en flotante 4,34 + 0,05 no da 4,39
    # justo: se compara en milímetros enteros para que el borde sea exacto.
    return None if v is None else round(v * 1000)


def nivel_con_margen(valor_m, umbrales, anterior, margen_m):
    """Nivel con margen al bajar: para pasar a un nivel menor que el publicado
    antes, la altura tiene que quedar `margen_m` o más por debajo del umbral
    (justo `margen_m` por debajo ya baja). Al subir no hay margen: al tocar el
    umbral, sube. Evita avisos "subió" y "bajó" seguidos cuando el río oscila
    sobre un umbral. Puede bajar varios niveles de una, pero solo hasta donde lo
    permita el margen (de evacuación, a 3 cm bajo la alerta, queda en alerta).
    Sin nivel anterior con dato, o con margen 0, es el cálculo de siempre."""
    calculado = calcular_nivel(valor_m, umbrales)
    if calculado == "sin_dato" or anterior not in NIVELES_CON_DATO or not margen_m:
        return calculado
    if anterior == "atencion" and umbrales.get("atencion_m") is None:
        return calculado  # sacaron el umbral de atención: ese nivel ya no existe
    en_mm = {k: _a_mm(umbrales.get(k)) for k in ("atencion_m", "alerta_m", "evacuacion_m")}
    # Un nivel se sostiene mientras la altura esté a MENOS de `margen_m` de su
    # umbral, o sea, si altura + margen > umbral. En milímetros enteros, "> umbral"
    # es ">= umbral + 1 mm": se resta 1 mm y se usa calcular_nivel (que compara
    # con >=). Lo sostenible nunca pasa del nivel anterior.
    sostenible = calcular_nivel(_a_mm(valor_m) + _a_mm(margen_m) - 1, en_mm)
    orden = NIVELES_CON_DATO.index
    tope = min(anterior, sostenible, key=orden)
    return max(calculado, tope, key=orden)
