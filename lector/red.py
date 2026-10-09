"""Descargas con reintentos y con límites.

Todo lo que se baja es contenido ajeno y no confiable (el registro de CARU
además viaja sin cifrar). Por eso solo se piden direcciones de una lista
cerrada de orígenes, con tope de tamaño y de tiempo, y sin seguir
redirecciones a otros sitios.
"""
import time
from urllib.parse import urljoin, urlsplit

import requests

USER_AGENT = "rio-paysandu-lector/1.0 (+https://github.com/MatiCascoV/rio-paysandu)"

# (esquema, host, puerto) desde donde se puede descargar y hacia donde pueden
# apuntar los enlaces que se publican. lector.py agrega los de config.json.
ORIGENES = {
    ("http", "190.0.152.194", 8080),
    ("https", "caru.org.uy", None),
    ("https", "www.caru.org.uy", None),
}

MAX_BYTES = 5_000_000
MAX_SEGUNDOS = 90
MAX_REDIRECCIONES = 3


def permitir_origen_de(url):
    """Agrega a la lista el origen de una URL de la configuración."""
    u = urlsplit(url)
    ORIGENES.add((u.scheme, u.hostname, u.port))


def url_permitida(url):
    """True si la URL apunta a uno de los orígenes conocidos (y nada más)."""
    try:
        u = urlsplit(url)
        return (u.scheme, u.hostname, u.port) in ORIGENES and not u.username and not u.password
    except (ValueError, AttributeError):
        return False


def _bajar_una_vez(url, timeout_s):
    fin = time.monotonic() + MAX_SEGUNDOS
    for _ in range(MAX_REDIRECCIONES + 1):
        if not url_permitida(url):
            raise ValueError(f"URL no permitida: {url!r}")
        with requests.get(url, timeout=(10, timeout_s), headers={"User-Agent": USER_AGENT},
                          stream=True, allow_redirects=False) as r:
            if r.is_redirect:
                # Se sigue a mano para validar cada salto contra la lista.
                url = urljoin(url, r.headers.get("Location", ""))
                continue
            r.raise_for_status()
            partes, total = [], 0
            for bloque in r.iter_content(65536):
                total += len(bloque)
                if total > MAX_BYTES:
                    raise ValueError("respuesta demasiado grande")
                if time.monotonic() > fin:
                    raise ValueError("respuesta demasiado lenta")
                partes.append(bloque)
            return b"".join(partes)
    raise ValueError("demasiadas redirecciones")


def descargar(url, intentos=3, espera_s=5, timeout_s=30):
    """Devuelve el contenido (bytes) de `url`. Reintenta ante errores de red
    esperando cada vez un poco más; si se agotan los intentos, lanza el último
    error. Una URL fuera de la lista o una respuesta desmedida no se reintenta."""
    ultimo_error = None
    for intento in range(1, intentos + 1):
        try:
            return _bajar_una_vez(url, timeout_s)
        except requests.RequestException as e:
            ultimo_error = e
            if intento < intentos:
                time.sleep(espera_s * intento)
    raise ultimo_error
