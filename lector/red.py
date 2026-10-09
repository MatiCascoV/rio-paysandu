"""Descargas con reintentos."""
import time

import requests

USER_AGENT = "rio-paysandu-lector/1.0 (Intendencia de Paysandu)"


def descargar(url, intentos=3, espera_s=5, timeout_s=30):
    """Devuelve el contenido (bytes) de `url`. Reintenta ante errores de red
    esperando cada vez un poco más; si se agotan los intentos, lanza el último error."""
    ultimo_error = None
    for intento in range(1, intentos + 1):
        try:
            r = requests.get(url, timeout=timeout_s, headers={"User-Agent": USER_AGENT})
            r.raise_for_status()
            return r.content
        except requests.RequestException as e:
            ultimo_error = e
            if intento < intentos:
                time.sleep(espera_s * intento)
    raise ultimo_error
