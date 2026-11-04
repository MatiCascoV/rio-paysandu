"""Casos de M-1 (el urgente espera una segunda lectura) decididos por avisos.py,
para que la app compruebe que su respaldo local da lo mismo.

La app (app/lib/confirmacion_urgente.dart) repite la regla del servidor en el
teléfono. Este módulo arma secuencias de publicaciones, las decide con
`avisos.decidir` como lo hace avisos.yml (cada una con su historial) y las
escribe en app/test/fixtures/casos_m1_servidor.json. La prueba de la app las
pasa por su regla, una por una, y exige el mismo urgente en cada publicación.
test_casos_m1_app.py comprueba que el archivo está al día con avisos.py.

Para regenerarlo (desde la raíz del repositorio):
    python lector/tests/casos_m1.py
"""
import copy
import json
import random
import sys
from datetime import datetime, timedelta
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(RAIZ / "lector"))

import avisos  # noqa: E402

FIXTURE = Path(__file__).parent / "fixtures" / "avisos" / "actual_alerta.json"
SALIDA = RAIZ / "app" / "test" / "fixtures" / "casos_m1_servidor.json"

BASE = avisos.datetime(2026, 10, 17, tzinfo=avisos.ZONA_LOCAL)
FUENTES = ["CARU – estación automática Paysandú", "Prefectura"]


def _pub(plantilla, minutos, nivel, valor, lectura_min, fuente=0, retenido=None):
    p = copy.deepcopy(plantilla)
    p["nivel"] = nivel
    p["generado"] = (BASE + timedelta(minutes=minutos)).isoformat()
    p["altura_actual"]["valor_m"] = valor
    p["altura_actual"]["fecha"] = (BASE + timedelta(minutes=lectura_min)).isoformat()
    p["altura_actual"]["fuente"] = FUENTES[fuente]
    p["lectura_prefectura"] = None      # sin Prefectura: solo cuenta el urgente
    if retenido is not None:
        p["nivel_retenido"] = {"nivel": retenido}
    return p


def _decidir_secuencia(plantilla, filas):
    """filas: [minutos, nivel, valor, lectura_min, fuente, retenido]. Devuelve el
    urgente de cada publicación, decidida con su historial (como avisos.yml)."""
    historia, salidas = [], []
    for f in filas:
        p = _pub(plantilla, *f)
        salidas.append(avisos.decidir(p, list(historia))["urgente"])
        historia.insert(0, p)
    return salidas


def _fila(minutos, nivel, valor, lectura_min=None, fuente=0, retenido=None):
    return [minutos, nivel, valor, minutos - 5 if lectura_min is None else lectura_min, fuente, retenido]


def _fijos():
    """Los casos de test_avisos.py (con las horas pasadas a minutos desde las 00:00)."""
    h = lambda t: int(t[:2]) * 60 + int(t[3:])     # noqa: E731
    f = _fila
    return {
        "segunda lectura confirma": [f(h("08:00"), "atencion", 5.5), f(h("08:30"), "alerta", 5.9),
                                     f(h("09:00"), "alerta", 5.95), f(h("09:30"), "alerta", 6.0)],
        "normal a evacuacion": [f(h("08:00"), "normal", 4.0), f(h("08:30"), "evacuacion", 6.7),
                                f(h("09:00"), "evacuacion", 6.75)],
        "misma lectura repetida y tope de 60 min": [
            f(h("08:00"), "atencion", 5.5), f(h("08:30"), "alerta", 5.9, h("08:25")),
            f(h("09:00"), "alerta", 5.9, h("08:25")), f(h("09:29"), "alerta", 5.9, h("08:25")),
            f(h("09:30"), "alerta", 5.9, h("08:25")), f(h("10:00"), "alerta", 5.9, h("08:25"))],
        "una baja reinicia": [f(h("07:30"), "atencion", 5.5), f(h("08:00"), "alerta", 5.9),
                              f(h("08:30"), "atencion", 5.6), f(h("09:00"), "atencion", 5.6),
                              f(h("09:30"), "alerta", 5.9), f(h("10:00"), "alerta", 5.95)],
        "retencion liberada ya viene confirmada": [
            f(h("08:00"), "atencion", 5.5), f(h("08:30"), "atencion", 5.6, retenido="alerta"),
            f(h("09:00"), "alerta", 5.9), f(h("09:30"), "alerta", 5.95)],
        "retencion liberada a otro nivel no confirma": [
            f(h("08:00"), "atencion", 5.5), f(h("08:30"), "atencion", 5.6, retenido="alerta"),
            f(h("09:00"), "evacuacion", 6.7), f(h("09:30"), "evacuacion", 6.75)],
        "salto brusco no confirma": [f(h("08:00"), "atencion", 5.0), f(h("08:30"), "evacuacion", 7.5),
                                     f(h("09:00"), "evacuacion", 9.0), f(h("09:30"), "evacuacion", 7.6)],
        "salto brusco persistente sale a los 60 min": [
            f(h("08:00"), "atencion", 5.0), f(h("08:30"), "alerta", 6.0), f(h("09:00"), "alerta", 8.0),
            f(h("09:30"), "alerta", 10.0), f(h("10:00"), "alerta", 12.0)],
        "salto de justo 1 m": [f(h("08:00"), "atencion", 5.0), f(h("08:30"), "alerta", 5.5),
                               f(h("09:00"), "alerta", 6.5)],
        "salto de 1 m en coma flotante": [f(h("08:00"), "atencion", 5.0), f(h("08:30"), "alerta", 4.95),
                                          f(h("09:00"), "alerta", 5.95)],
        "lectura anterior no confirma": [f(h("08:00"), "atencion", 5.5), f(h("08:30"), "alerta", 5.9),
                                         f(h("09:00"), "alerta", 5.9, h("08:00")),
                                         f(h("09:30"), "alerta", 5.95)],
        "otra fuente no confirma": [f(h("08:00"), "atencion", 5.5), f(h("08:30"), "alerta", 5.9),
                                    f(h("09:00"), "alerta", 5.95, fuente=1),
                                    f(h("09:30"), "alerta", 5.95, fuente=1)],
        "alerta, evacuacion y vuelve a alerta": [
            f(h("08:00"), "atencion", 5.0), f(h("08:30"), "alerta", 6.0), f(h("09:00"), "evacuacion", 7.0),
            f(h("09:30"), "alerta", 6.1), f(h("10:00"), "alerta", 6.2), f(h("10:30"), "alerta", 6.3)],
        "evacuacion confirmada sin alerta redundante": [
            f(h("08:00"), "atencion", 5.0), f(h("08:30"), "alerta", 6.0), f(h("09:00"), "evacuacion", 7.0),
            f(h("09:30"), "evacuacion", 7.1), f(h("10:00"), "alerta", 6.1), f(h("10:30"), "alerta", 6.2)],
        "alerta y despues evacuacion avisan las dos": [
            f(h("08:00"), "atencion", 5.0), f(h("08:30"), "alerta", 6.0), f(h("09:00"), "alerta", 6.1),
            f(h("09:30"), "evacuacion", 7.0), f(h("10:00"), "evacuacion", 7.1), f(h("10:30"), "alerta", 6.2)],
        "evacuacion sin confirmar y alerta sostenida": [
            f(h("08:00"), "atencion", 5.0), f(h("08:30"), "alerta", 6.0), f(h("09:00"), "evacuacion", 9.0),
            f(h("09:30"), "alerta", 6.1), f(h("10:00"), "alerta", 6.2)],
        "hueco de 130 min con la misma lectura": [
            f(0, "atencion", 5.5, 5), f(10, "alerta", 5.9, 5), f(140, "alerta", 5.9, 5)],
        "sin anterior no avisa": [f(h("08:00"), "alerta", 5.9), f(h("08:30"), "alerta", 5.95),
                                  f(h("09:30"), "alerta", 6.0)],
        # Bordes en los que avisos.py no avisa nunca aunque el río siga en alerta; la
        # app sí avisa (ver DIFERENCIAS_CONOCIDAS en confirmacion_urgente_test.dart).
        "borde servidor: retencion soltada en evacuacion y despues alerta": [
            f(h("08:00"), "atencion", 5.5), f(h("08:30"), "atencion", 5.6, retenido="alerta"),
            f(h("09:00"), "evacuacion", 6.7), f(h("09:30"), "alerta", 6.0), f(h("10:00"), "alerta", 6.05),
            f(h("10:30"), "alerta", 6.1), f(h("11:40"), "alerta", 6.1)],
        "borde servidor: evacuacion de una lectura tras un hueco y alerta sostenida": [
            f(0, "atencion", 5.0, 0), f(60, "alerta", 5.92, 60), f(70, "alerta", 5.92, 60),
            f(270, "evacuacion", 6.89, 270), f(280, "alerta", 5.99, 270), f(300, "alerta", 6.0, 300),
            f(330, "alerta", 6.0, 330), f(400, "alerta", 6.0, 390)],
    }


def _aleatoria_cada_10(azar):
    """Como _secuencia_aleatoria de test_avisos.py: el lector cada 10 min, la estación cada 30."""
    niveles = ["atencion"]
    for _ in range(azar.randint(8, 30)):
        niveles.append(niveles[-1] if azar.random() < 0.8 else azar.choice(["atencion", "alerta", "evacuacion"]))
    altura = {"atencion": 5.0, "alerta": 5.8, "evacuacion": 6.6}
    return [_fila(10 * i, n, round(altura[n] + 0.01 * (i // 3), 2), 30 * (i // 3)) for i, n in enumerate(niveles)]


def _aleatoria_con_huecos(azar):
    """Como test_propiedades_con_saltos_de_tiempo_aleatorios: con huecos de publicación."""
    niveles, tiempos = ["atencion"], [0]
    for _ in range(azar.randint(8, 30)):
        niveles.append(niveles[-1] if azar.random() < 0.75
                       else azar.choice(["normal", "atencion", "alerta", "evacuacion"]))
        tiempos.append(tiempos[-1] + azar.choice([10, 10, 10, 10, 20, 30, 70, 130, 200]))
    altura = {"normal": 4.0, "atencion": 5.0, "alerta": 5.9, "evacuacion": 6.8}
    return [_fila(t, n, round(altura[n] + 0.01 * (t // 30), 2), 30 * (t // 30)) for n, t in zip(niveles, tiempos)]


def generar():
    plantilla = json.loads(FIXTURE.read_text(encoding="utf-8"))
    casos = []
    for nombre, filas in _fijos().items():
        casos.append({"nombre": nombre, "pubs": filas})
    azar = random.Random(20261104)
    for i in range(100):
        casos.append({"nombre": f"cada 10 min #{i}", "pubs": _aleatoria_cada_10(azar)})
    for i in range(100):
        casos.append({"nombre": f"con huecos #{i}", "pubs": _aleatoria_con_huecos(azar)})
    for c in casos:
        c["urgentes"] = _decidir_secuencia(plantilla, c["pubs"])
    return {
        "_": "Generado por lector/tests/casos_m1.py con avisos.decidir. No editar a mano.",
        "base": BASE.isoformat(),
        "fuentes": FUENTES,
        "pubs": "[minutos, nivel, valor_m, minutos de la lectura, fuente, nivel_retenido.nivel]",
        "casos": casos,
    }


def texto():
    """El JSON tal cual se escribe: un caso por línea, para que el diff se lea."""
    datos = generar()
    casos = datos.pop("casos")
    cabeza = json.dumps(datos, ensure_ascii=False)[:-1]
    lineas = ",\n".join(json.dumps(c, ensure_ascii=False, separators=(",", ":")) for c in casos)
    return f'{cabeza}, "casos": [\n{lineas}\n]}}\n'


if __name__ == "__main__":
    SALIDA.parent.mkdir(parents=True, exist_ok=True)
    SALIDA.write_text(texto(), encoding="utf-8", newline="\n")
    print(f"escrito {SALIDA.relative_to(RAIZ)}")
