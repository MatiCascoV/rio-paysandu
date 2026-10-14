"""Controles sobre los archivos de data/ que se editan a mano."""
import json

import lector
from nivel import umbrales_validos


def test_umbrales_del_repositorio_son_validos():
    # data/umbrales.json se edita a mano (por ejemplo, cuando el Cecoed valide
    # los umbrales). Si quedara mal cargado, el lector publicaría "sin_dato".
    ruta = lector.DATA / "umbrales.json"
    umbrales = json.loads(ruta.read_text(encoding="utf-8-sig"))
    assert umbrales_validos(umbrales), f"{ruta} tiene valores inválidos: {umbrales}"
