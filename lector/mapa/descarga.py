"""Descargas con caché en disco y sha256.

Cada URL se guarda una sola vez en la carpeta de caché (fuera del repo). Un manifiesto
(`manifiesto.json`) anota bytes y sha256 de cada archivo; si el archivo cacheado no
coincide con su manifiesto se vuelve a bajar. Toda falla de red o de tamaño corta el
pipeline con un error claro (fallar temprano y fuerte).
"""
from __future__ import annotations

import hashlib
import json
import logging
import os
import re
import tempfile
import time
import urllib.parse
from pathlib import Path

log = logging.getLogger("mapa")

USER_AGENT = "MiRioUY-mapa/1 (+https://github.com; pipeline de datos abiertos)"


class ErrorDescarga(RuntimeError):
    pass


def cache_por_defecto() -> Path:
    env = os.environ.get("MAPA_CACHE")
    if env:
        return Path(env)
    return Path(tempfile.gettempdir()) / "claude" / "mapa-cache"


def sha256_archivo(ruta: Path) -> str:
    h = hashlib.sha256()
    with open(ruta, "rb") as f:
        for bloque in iter(lambda: f.read(1 << 20), b""):
            h.update(bloque)
    return h.hexdigest()


def nombre_cache(url: str) -> str:
    """Nombre de archivo estable y legible para una URL."""
    p = urllib.parse.urlsplit(url)
    base = os.path.basename(p.path) or "index"
    base = re.sub(r"[^A-Za-z0-9._-]", "_", base)[:80]
    corto = hashlib.sha1(url.encode("utf-8")).hexdigest()[:10]
    return f"{corto}_{base}"


class Cache:
    def __init__(self, carpeta: Path):
        self.carpeta = Path(carpeta)
        self.carpeta.mkdir(parents=True, exist_ok=True)
        self.ruta_manifiesto = self.carpeta / "manifiesto.json"
        try:
            self.manifiesto = json.loads(self.ruta_manifiesto.read_text(encoding="utf-8"))
        except FileNotFoundError:
            self.manifiesto = {}
        self.usados: dict[str, dict] = {}

    def _guardar_manifiesto(self) -> None:
        tmp = self.ruta_manifiesto.with_suffix(".tmp")
        tmp.write_text(json.dumps(self.manifiesto, indent=1, sort_keys=True), encoding="utf-8")
        os.replace(tmp, self.ruta_manifiesto)

    def obtener(self, url: str, reintentos: int = 3, timeout: int = 120) -> Path:
        """Devuelve la ruta local de `url`, bajándola si no está o si está corrupta."""
        import requests  # import tardío: los tests no lo necesitan

        destino = self.carpeta / nombre_cache(url)
        info = self.manifiesto.get(url)
        if info and destino.exists() and destino.stat().st_size == info["bytes"]:
            if sha256_archivo(destino) == info["sha256"]:
                self.usados[url] = info
                return destino
            log.warning("caché corrupta para %s; se vuelve a bajar", url)
        ultimo = None
        for intento in range(1, reintentos + 1):
            try:
                with requests.get(url, stream=True, timeout=timeout,
                                  headers={"User-Agent": USER_AGENT}) as r:
                    if r.status_code != 200:
                        raise ErrorDescarga(f"HTTP {r.status_code} al bajar {url}")
                    esperado = r.headers.get("Content-Length")
                    parcial = destino.with_suffix(destino.suffix + ".part")
                    h = hashlib.sha256()
                    n = 0
                    with open(parcial, "wb") as f:
                        for bloque in r.iter_content(1 << 20):
                            f.write(bloque)
                            h.update(bloque)
                            n += len(bloque)
                    if esperado is not None and int(esperado) != n and "gzip" not in r.headers.get("Content-Encoding", ""):
                        parcial.unlink(missing_ok=True)
                        raise ErrorDescarga(f"{url}: se esperaban {esperado} bytes y llegaron {n}")
                    if n == 0:
                        parcial.unlink(missing_ok=True)
                        raise ErrorDescarga(f"{url}: respuesta vacía")
                    os.replace(parcial, destino)
                info = {"archivo": destino.name, "bytes": n, "sha256": h.hexdigest(),
                        "bajado": time.strftime("%Y-%m-%dT%H:%M:%S")}
                self.manifiesto[url] = info
                self._guardar_manifiesto()
                self.usados[url] = info
                log.info("bajado %s (%d bytes, sha256 %s)", url, n, info["sha256"][:12])
                return destino
            except (ErrorDescarga, requests.RequestException) as e:
                ultimo = e
                log.warning("intento %d/%d falló para %s: %s", intento, reintentos, url, e)
                time.sleep(2 * intento)
        raise ErrorDescarga(f"no se pudo bajar {url}: {ultimo}")

    def texto(self, url: str) -> str:
        return self.obtener(url).read_bytes().decode("utf-8", errors="replace")


def listar_indice_apache(html: str, extension: str = ".tif") -> list[str]:
    """Nombres de archivo de un índice de directorio de Apache."""
    nombres = re.findall(r'href="([^"?/][^"/]*)"', html)
    return sorted({urllib.parse.unquote(n) for n in nombres if n.lower().endswith(extension)})
