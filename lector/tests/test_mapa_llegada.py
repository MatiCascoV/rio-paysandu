"""Cota de llegada (priority-flood por umbrales) con terrenos sintéticos chicos."""
import pytest

np = pytest.importorskip("numpy")
pytest.importorskip("scipy")

from mapa.llegada import NUNCA, llegada_cm, llegada_referencia, umbral_cm  # noqa: E402


def _a_cm(ref, semilla, min_cm):
    """Pasa la llegada de referencia (m, float) a la convención de llegada_cm."""
    out = np.full(ref.shape, NUNCA, dtype=np.int64)
    fin = np.isfinite(ref)
    out[fin] = np.maximum(np.ceil(np.round(ref[fin] * 100, 6)), min_cm)
    out[semilla] = min_cm
    return out


@pytest.mark.parametrize("semilla_rng", range(4))
def test_coincide_con_priority_flood_clasico(semilla_rng):
    rng = np.random.default_rng(semilla_rng)
    dem = np.round(rng.uniform(3.6, 8.0, (30, 40)), 2).astype("float32")
    dem[rng.random(dem.shape) < 0.05] = np.nan
    sem = np.zeros(dem.shape, bool)
    sem[:, 0] = True
    got = llegada_cm(dem, sem, 360, 900, 1)
    esperado = _a_cm(llegada_referencia(dem, sem), sem, 360)
    esperado[esperado > 900] = NUNCA
    assert np.array_equal(got.astype(np.int64), esperado)


def test_bajo_detras_de_un_terraplen_se_moja_recien_al_superarlo():
    dem = np.full((5, 7), 5.0, dtype="float32")
    dem[:, 0] = 1.0           # cauce
    dem[:, 3] = 9.0           # terraplén
    dem[:, 4:] = 4.0          # bajo detrás
    sem = np.zeros(dem.shape, bool); sem[:, 0] = True
    lleg = llegada_cm(dem, sem, 360, 1000, 10)
    assert (lleg[:, 4:] == 900).all()   # aunque está a 4 m, recién se moja con el agua a 9 m
    assert (lleg[:, 1:3] == 500).all()


def test_conectividad_4_no_pasa_en_diagonal():
    dem = np.full((4, 4), 9.0, dtype="float32")
    dem[0, 0] = 1.0
    dem[1, 1] = 4.0   # solo toca la semilla en diagonal
    sem = np.zeros(dem.shape, bool); sem[0, 0] = True
    lleg = llegada_cm(dem, sem, 360, 800, 10)
    assert lleg[1, 1] == NUNCA


def test_sin_dato_es_pared():
    dem = np.full((3, 5), 4.0, dtype="float32")
    dem[:, 2] = np.nan
    sem = np.zeros(dem.shape, bool); sem[:, 0] = True
    lleg = llegada_cm(dem, sem, 360, 1000, 10)
    assert (lleg[:, 3:] == NUNCA).all()
    assert (lleg[:, 1] == 400).all()


def test_capas_anidadas_por_construccion():
    rng = np.random.default_rng(7)
    dem = rng.uniform(3.6, 9.0, (25, 25)).astype("float32")
    sem = np.zeros(dem.shape, bool); sem[0, :] = True
    lleg = llegada_cm(dem, sem, 360, 1000, 2)
    anterior = None
    for t in range(400, 1001, 10):
        capa = lleg <= t
        if anterior is not None:
            assert not (anterior & ~capa).any()
        anterior = capa


def test_cauce_vacio_falla():
    dem = np.zeros((3, 3), dtype="float32")
    with pytest.raises(ValueError):
        llegada_cm(dem, np.zeros((3, 3), bool), 360, 400, 2)


def test_umbral_cm():
    assert umbral_cm(6.70, 0.66) == 736
    assert umbral_cm(4.0, -0.2) == 380


def test_quemar_cursos_deja_entrar_el_remanso_por_el_arroyo():
    """Un valle bajo (5 m) separado del río por una loma de 9 m; el arroyo cruza la loma
    con un lecho angosto (2 m de ancho, promediado a 7,5 m) y un tramo sin dato (agua)."""
    pytest.importorskip("shapely")
    from mapa.terreno import quemar_cursos
    dem = np.full((20, 30), 5.0, dtype="float32")
    dem[:, 10:14] = 9.0                       # loma
    dem[9, 10:14] = 7.5                       # lecho promediado hacia arriba
    dem[10, 11] = 4.2                         # una celda del lecho con la cota real
    dem[9, 12] = np.nan                       # tramo sin dato (agua)
    sem = np.zeros(dem.shape, bool); sem[:, 0] = True
    valle = (slice(None), slice(16, 30))
    antes = llegada_cm(dem, sem, 360, 1200, 2)
    assert (antes[valle] >= 900).all()        # sin quemar: entra recién por arriba de la loma
    lineas = np.zeros(dem.shape, bool); lineas[9, :] = True
    info = quemar_cursos(dem, lineas, 1)
    assert info["celdas_bajadas"] > 0
    assert not np.isnan(dem[9]).any()
    despues = llegada_cm(dem, sem, 360, 1200, 2)
    assert (despues[valle] <= 500).all()      # el remanso entra por el arroyo
    assert (despues <= antes).all()           # quemar nunca saca agua


def test_quemar_cursos_sin_lineas_no_toca_nada():
    from mapa.terreno import quemar_cursos
    dem = np.arange(12, dtype="float32").reshape(3, 4)
    copia = dem.copy()
    quemar_cursos(dem, np.zeros(dem.shape, bool))
    assert (dem == copia).all()


def test_quemar_cursos_no_inventa_terreno_en_tramos_largos_sin_dato():
    from mapa.terreno import quemar_cursos
    dem = np.full((5, 200), np.nan, dtype="float32")
    dem[:, :5] = 3.0                          # tramo con dato
    lineas = np.zeros(dem.shape, bool); lineas[2, :] = True
    info = quemar_cursos(dem, lineas, 1, max_hueco_celdas=10)
    assert np.isfinite(dem[2, :15]).all()     # cerca del dato: se completa
    assert np.isnan(dem[2, 30:]).all()        # lejos: queda sin dato
    assert info["celdas_sin_dato_sin_completar"] > 0
