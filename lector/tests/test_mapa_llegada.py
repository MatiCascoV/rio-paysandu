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
