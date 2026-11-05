"""Los casos de M-1 que reproduce la app (app/test/fixtures/casos_m1_servidor.json)
tienen que estar al día con avisos.py: si cambia la regla del servidor, falla acá
hasta regenerarlos (python lector/tests/casos_m1.py) y la prueba de la app
(app/test/confirmacion_urgente_test.dart) vuelve a comparar las dos."""
import casos_m1


def test_casos_de_la_app_al_dia_con_avisos_py():
    escrito = casos_m1.SALIDA.read_text(encoding="utf-8")
    assert escrito == casos_m1.texto(), "regenerar con: python lector/tests/casos_m1.py"


def test_los_casos_tienen_urgentes_de_los_dos_niveles():
    casos = casos_m1.generar()["casos"]
    salidas = [u for c in casos for u in c["urgentes"]]
    assert "alerta" in salidas and "evacuacion" in salidas
    assert all(len(c["urgentes"]) == len(c["pubs"]) for c in casos)
