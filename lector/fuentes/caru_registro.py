"""Registro de alturas de CARU (página HTML con las tablas "Puertos" y
"Estaciones Automáticas") y sus páginas de detalle.

Sobre el filtro "Ceros": es un formulario POST (campo form[escala] más un token
de sesión). Sin enviar nada, la página viene en cero "Local", que es el que usamos.
Los otros ceros todavía no están soportados.
"""
import json
import re
import unicodedata
from datetime import datetime, timedelta, timezone
from urllib.parse import urljoin

from bs4 import BeautifulSoup

# CARU publica en hora de Uruguay, que es UTC-3 todo el año.
TZ_UY = timezone(timedelta(hours=-3))


def _texto(nodo):
    return re.sub(r"\s+", " ", nodo.get_text()).strip()


def _sin_tildes(s):
    s = unicodedata.normalize("NFD", s)
    return "".join(c for c in s if unicodedata.category(c) != "Mn").lower().strip()


def _numero(txt):
    try:
        return float(txt.replace(",", "."))
    except ValueError:
        return None


def _fecha(txt):
    """'09/10/2026 - 06:00' (o sin el guion) -> datetime con zona -03:00."""
    m = re.search(r"(\d{2})/(\d{2})/(\d{4})\D+(\d{2}):(\d{2})", txt)
    if not m:
        return None
    d, mes, a, h, mi = map(int, m.groups())
    try:
        return datetime(a, mes, d, h, mi, tzinfo=TZ_UY)
    except ValueError:  # fecha imposible, p. ej. 31/02
        return None


def _fila_del_puerto(tabla, puerto, base_url):
    """Busca la fila de `puerto` y la devuelve como dict usando los títulos de
    las columnas (así no dependemos del orden)."""
    titulos = [_sin_tildes(_texto(th)) for th in tabla.find_all("th")]
    for tr in tabla.find_all("tr"):
        celdas = tr.find_all("td")
        if not celdas or _sin_tildes(_texto(celdas[0])) != _sin_tildes(puerto):
            continue
        fila = dict(zip(titulos, (_texto(c) for c in celdas)))
        enlace = celdas[0].find("a")
        valor = _numero(fila.get("ultimo registro", ""))
        fecha = _fecha(fila.get("fecha - hora", ""))
        if valor is None or fecha is None:
            return None
        return {
            "valor_m": valor,
            "fecha": fecha,
            "variacion_m": _numero(fila.get("variacion", "")),
            "periodo": fila.get("periodo", "").rstrip(". ") or None,
            "estado": fila.get("estado", "").lower() or None,
            "anterior_m": _numero(fila.get("registro anterior", "")),
            "fecha_anterior": _fecha(fila.get("fecha - hora anterior", "")),
            "url": urljoin(base_url, enlace["href"]) if enlace else base_url,
        }
    return None


def parsear_registro(html, base_url, puerto="Paysandú"):
    """Devuelve {"cero", "prefectura", "estacion"}; cada lectura es un dict o
    None si la fila no está o no se pudo leer."""
    sopa = BeautifulSoup(html, "html.parser")

    cero = None
    selector = sopa.find("select", id="form_escala")
    if selector:
        opcion = selector.find("option", selected=True) or selector.find("option")
        cero = _texto(opcion) if opcion else None

    resultado = {"cero": cero, "prefectura": None, "estacion": None}
    for tabla in sopa.find_all("table"):
        primer_titulo = tabla.find("th")
        if not primer_titulo:
            continue
        tipo = {"puerto": "prefectura", "estacion": "estacion"}.get(_sin_tildes(_texto(primer_titulo)))
        if tipo:
            resultado[tipo] = _fila_del_puerto(tabla, puerto, base_url)
    return resultado


def parsear_historial(html):
    """Las páginas de detalle traen la última semana en una variable JavaScript
    `alturasJson`. Devuelve una lista de (fecha, valor_m)."""
    m = re.search(r"var\s+alturasJson\s*=\s*(\[.*?\])\s*;", html, re.DOTALL)
    if not m:
        return []
    lecturas = []
    for item in json.loads(m.group(1)):
        fecha = _fecha(str(item.get("fecha", "")))
        valor = item.get("altura")
        if fecha and isinstance(valor, (int, float)):
            lecturas.append((fecha, float(valor)))
    return lecturas
