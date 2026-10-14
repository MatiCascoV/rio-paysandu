"""Plazos reales de descarga contra un servidor local que gotea (manda un byte
cada tanto: nunca dispara el timeout de lectura de requests)."""
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pytest

import red

PARAR = threading.Event()


class Goteo(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_GET(self):
        try:
            if self.path == "/encabezados":
                # Goteo antes de terminar los encabezados.
                self.wfile.write(b"HTTP/1.1 200 OK\r\n")
                while not PARAR.is_set():
                    self.wfile.write(b"X-Goteo: a\r\n")
                    self.wfile.flush()
                    time.sleep(0.2)
                return
            self.send_response(200)
            self.send_header("Content-Length", "100000")
            self.end_headers()
            while not PARAR.is_set():
                self.wfile.write(b"x")
                self.wfile.flush()
                time.sleep(0.2)
        except OSError:
            pass  # el cliente cortó


@pytest.fixture
def servidor(monkeypatch):
    PARAR.clear()
    srv = ThreadingHTTPServer(("127.0.0.1", 0), Goteo)
    srv.daemon_threads = True
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    puerto = srv.server_address[1]
    monkeypatch.setitem(red.ORIGENES, "prueba", {("http", "127.0.0.1", puerto)})
    yield f"http://127.0.0.1:{puerto}"
    PARAR.set()
    srv.shutdown()
    srv.server_close()


@pytest.mark.parametrize("camino", ["/cuerpo", "/encabezados"])
def test_goteo_se_corta_cerca_del_plazo(servidor, camino):
    inicio = time.monotonic()
    with pytest.raises(red.DescargaLenta):
        red.descargar(servidor + camino, intentos=1, timeout_s=30, proposito="prueba", hasta=inicio + 2)
    assert time.monotonic() - inicio < 4.5  # plazo 2 s, más el margen del vigilante


def test_goteo_respeta_max_segundos_sin_limite_total(servidor, monkeypatch):
    monkeypatch.setattr(red, "MAX_SEGUNDOS", 1.5)
    inicio = time.monotonic()
    with pytest.raises(red.DescargaLenta):
        red.descargar(servidor + "/cuerpo", intentos=1, timeout_s=30, proposito="prueba")
    assert time.monotonic() - inicio < 4


def test_descarga_lenta_se_reintenta(monkeypatch):
    intentos = []

    def bajar(url, timeout_s, proposito, hasta):
        intentos.append(url)
        if len(intentos) == 1:
            raise red.DescargaLenta("respuesta demasiado lenta")
        return b"ok"
    monkeypatch.setattr(red, "_bajar_una_vez", bajar)
    monkeypatch.setattr(red.time, "sleep", lambda s: None)
    assert red.descargar("http://190.0.152.194:8080/x", intentos=2, proposito="registro") == b"ok"
    assert len(intentos) == 2


def test_respuesta_grande_no_se_reintenta(monkeypatch):
    intentos = []

    def bajar(url, timeout_s, proposito, hasta):
        intentos.append(url)
        raise ValueError("respuesta demasiado grande")
    monkeypatch.setattr(red, "_bajar_una_vez", bajar)
    with pytest.raises(ValueError):
        red.descargar("http://190.0.152.194:8080/x", intentos=3, proposito="registro")
    assert len(intentos) == 1
