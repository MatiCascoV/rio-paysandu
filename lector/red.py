"""Descargas con reintentos y con límites.

Todo lo que se baja es contenido ajeno y no confiable (el registro de CARU
además viaja sin cifrar). Por eso solo se piden direcciones de una lista
cerrada de orígenes, separada por propósito, con tope de tamaño y de tiempo,
y sin seguir redirecciones a otros sitios ni de https a http.
"""
import socket
import threading
import time
from urllib.parse import urljoin, urlsplit

import requests

USER_AGENT = "rio-paysandu-lector/1.0 (+https://github.com/MatiCascoV/rio-paysandu)"

PUERTOS_POR_DEFECTO = {"http": 80, "https": 443}

# Propósito -> (esquema, host, puerto) desde donde se puede descargar y hacia
# donde pueden apuntar los enlaces que se publican. lector.py agrega los de
# config.json.
#   registro: tabla de alturas y páginas de detalle (servidor de CARU, solo http).
#   informes: índice de informes de crecida y sus PDF (sitio de CARU, solo https).
ORIGENES = {
    "registro": {("http", "190.0.152.194", 8080)},
    "informes": {("https", "caru.org.uy", 443), ("https", "www.caru.org.uy", 443)},
}

MAX_BYTES = 5_000_000
MAX_SEGUNDOS = 90
MAX_REDIRECCIONES = 3


def _origen(url):
    """(esquema, host, puerto) con el puerto por defecto explícito, o None."""
    u = urlsplit(url)
    if u.username or u.password or not u.hostname:
        return None
    puerto = u.port or PUERTOS_POR_DEFECTO.get(u.scheme)  # u.port valida el número
    return (u.scheme, u.hostname, puerto)


def permitir_origen_de(url, proposito):
    """Agrega a la lista del propósito el origen de una URL de la configuración."""
    origen = _origen(url)
    if origen is None:
        raise ValueError(f"URL de configuración inválida: {url!r}")
    ORIGENES[proposito].add(origen)


def url_permitida(url, proposito=None):
    """True si la URL apunta a uno de los orígenes del propósito (o de cualquiera
    si no se indica) y nada más."""
    try:
        origen = _origen(url)
    except (ValueError, AttributeError, TypeError):
        return False
    if origen is None:
        return False
    listas = [ORIGENES[proposito]] if proposito else ORIGENES.values()
    return any(origen in lista for lista in listas)


class DescargaLenta(TimeoutError):
    """Se acabó el plazo. Es un error pasajero: se puede reintentar más tarde."""


def _cortar(respuestas):
    """Corta las conexiones de una descarga vencida. Solo shutdown() del socket:
    despierta al recv() bloqueado del hilo de descarga, que termina solo. No se
    llama a r.close() desde acá: esperaría el lock de lectura que ese hilo tiene
    tomado y se colgaría igual."""
    for r in respuestas:
        try:
            r.raw._connection.sock.shutdown(socket.SHUT_RDWR)  # urllib3 2.x
        except Exception:
            pass


def _bajar_sin_vigilar(url, timeout_s, proposito, fin, respuestas):
    for _ in range(MAX_REDIRECCIONES + 1):
        if not url_permitida(url, proposito):
            raise ValueError(f"URL no permitida: {url!r}")
        restante = fin - time.monotonic()
        if restante <= 0:
            raise DescargaLenta("se acabó el tiempo para esta descarga")
        espera = max(1.0, min(timeout_s, restante))
        with requests.get(url, timeout=(min(10.0, espera), espera), headers={"User-Agent": USER_AGENT},
                          stream=True, allow_redirects=False) as r:
            respuestas.append(r)
            if r.is_redirect:
                # Se sigue a mano para validar cada salto contra la lista.
                siguiente = urljoin(url, r.headers.get("Location", ""))
                if urlsplit(url).scheme == "https" and urlsplit(siguiente).scheme != "https":
                    raise ValueError(f"redirección de https a {siguiente!r}")
                url = siguiente
                continue
            r.raise_for_status()
            partes, total = [], 0
            for bloque in r.iter_content(65536):
                total += len(bloque)
                if total > MAX_BYTES:
                    raise ValueError("respuesta demasiado grande")
                if time.monotonic() > fin:
                    raise DescargaLenta("respuesta demasiado lenta")
                partes.append(bloque)
            return b"".join(partes)
    raise ValueError("demasiadas redirecciones")


def _bajar_una_vez(url, timeout_s, proposito, hasta):
    """Una descarga con plazo real. El timeout de requests es por cada lectura del
    socket: un servidor que manda un byte cada pocos segundos (goteo) nunca lo
    dispara. Por eso la descarga corre en un hilo vigilado: al vencer el plazo se
    cortan sus conexiones y se sigue sin esperarla."""
    fin = time.monotonic() + MAX_SEGUNDOS
    if hasta is not None:
        fin = min(fin, hasta)
    resultado, respuestas = {}, []

    def correr():
        try:
            resultado["ok"] = _bajar_sin_vigilar(url, timeout_s, proposito, fin, respuestas)
        except BaseException as e:  # se relanza en el hilo principal
            resultado["error"] = e

    hilo = threading.Thread(target=correr, name="descarga", daemon=True)
    hilo.start()
    hilo.join(max(0.0, fin - time.monotonic()) + 1.0)
    if hilo.is_alive():
        _cortar(respuestas)
        raise DescargaLenta("respuesta demasiado lenta")
    if "error" in resultado:
        raise resultado["error"]
    return resultado["ok"]


def descargar(url, intentos=3, espera_s=5, timeout_s=30, proposito=None, hasta=None):
    """Devuelve el contenido (bytes) de `url`. Reintenta ante errores de red
    esperando cada vez un poco más; si se agotan los intentos, lanza el último
    error. `hasta` (time.monotonic()) es un límite total: después de esa hora no
    se empieza otro intento y la descarga en curso se corta. Un error de red o una
    descarga lenta (DescargaLenta) se reintentan; una URL fuera de la lista o una
    respuesta desmedida (ValueError), no."""
    ultimo_error = None
    for intento in range(1, intentos + 1):
        if hasta is not None and time.monotonic() >= hasta:
            break
        try:
            return _bajar_una_vez(url, timeout_s, proposito, hasta)
        except (requests.RequestException, DescargaLenta) as e:
            ultimo_error = e
            if intento < intentos:
                pausa = espera_s * intento
                if hasta is not None and time.monotonic() + pausa >= hasta:
                    break
                time.sleep(pausa)
    raise ultimo_error or DescargaLenta("se acabó el tiempo para esta descarga")
