"""Pruebas del corte de cierres de bordes_crecidas.py con anillos inventados.

Correr desde la raíz del repositorio (necesita shapely y pytest):
    python -m pytest docs/crecidas
"""

import os
import sys

import pytest
from shapely.geometry import Polygon

sys.path.insert(0, os.path.dirname(__file__))
import bordes_crecidas as bc  # noqa: E402

# Un "río" al oeste de la longitud -58.10.
RIO = Polygon([(-58.20, -32.40), (-58.10, -32.40), (-58.10, -32.20), (-58.20, -32.20)])


def costa(lat_desde, lat_hasta, paso=0.001, lon=-58.099):
    """Puntos de un borde en tierra, de norte a sur, cada ~110 m."""
    n = round((lat_desde - lat_hasta) / paso)
    return [(lon, round(lat_desde - k * paso, 6)) for k in range(n + 1)]


def anillo_con_cierre(tierra):
    """Borde en tierra cerrado por el río como lo cierra Dinagua: recta al
    oeste al sur, tramo largo por dentro del río y recta al este al norte."""
    sur, norte = tierra[-1], tierra[0]
    return tierra + [(-58.105, sur[1]), (-58.105, norte[1]), norte]


def test_saca_el_cierre_y_deja_el_borde_en_tierra_con_sus_puntos():
    tierra = costa(-32.28, -32.32)
    lineas = bc.bordes(anillo_con_cierre(tierra), RIO)
    assert lineas == [tierra]


def test_un_tramo_largo_entero_en_tierra_queda():
    tierra = costa(-32.28, -32.30) + costa(-32.304, -32.32)  # salto de 440 m en tierra
    lineas = bc.bordes(anillo_con_cierre(tierra), RIO)
    assert lineas == [tierra]


def test_anillo_sin_cierres_queda_entero():
    chico = [(-58.09, -32.30), (-58.0899, -32.30), (-58.0899, -32.3001), (-58.09, -32.30)]
    assert bc.bordes(chico, RIO) == [chico]


def test_un_resto_dentro_del_rio_se_descarta():
    # Entre dos cierres queda un pedacito de 330 m metido en el río.
    tierra = costa(-32.28, -32.32)
    resto = [(-58.15, -32.30), (-58.15, -32.303)]
    anillo = tierra + [(-58.105, -32.32), resto[1], resto[0], (-58.105, -32.28), tierra[0]]
    lineas = bc.bordes(anillo, RIO)
    assert lineas == [tierra]


def test_un_corte_que_no_es_un_cierre_conocido_frena_el_script():
    # Río con una punta hacia el este: una recta norte-sur en tierra la
    # atraviesa (33 % en el río) sin tener ningún extremo adentro.
    rio = Polygon([(-58.20, -32.40), (-58.10, -32.40), (-58.095, -32.30), (-58.10, -32.20), (-58.20, -32.20)])
    anillo = [(-58.097, -32.24), (-58.097, -32.36), (-58.05, -32.36), (-58.05, -32.24), (-58.097, -32.24)]
    with pytest.raises(bc.CorteSospechoso):
        bc.bordes(anillo, rio)
