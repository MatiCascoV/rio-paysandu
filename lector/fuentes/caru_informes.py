"""Informes de crecida de CARU: página índice con enlaces a PDF, y el PDF."""
import io
import re
import unicodedata
from datetime import date
from urllib.parse import urljoin

import pdfplumber
from bs4 import BeautifulSoup

MESES = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio",
         "agosto", "septiembre", "octubre", "noviembre", "diciembre"]


def _fecha_segura(a, m, d):
    try:
        return date(a, m, d)
    except ValueError:
        return None


def listar_informes(html, base_url, hoy=None):
    """Lee los enlaces a PDF del índice (no construye URLs: el nombre del archivo
    varía). Devuelve [{"fecha": date, "url": str}], el más reciente primero.
    Si se pasa `hoy`, descarta fechas futuras (errores de tipeo en el índice)."""
    sopa = BeautifulSoup(html, "html.parser")
    informes = {}
    for a in sopa.find_all("a", href=True):
        url = urljoin(base_url, a["href"])
        if not url.lower().split("?")[0].endswith(".pdf"):
            continue
        texto = a.get_text(" ", strip=True)
        if "informe" not in texto.lower() and "crecida" not in url.lower():
            continue
        fecha = None
        m = re.search(r"(\d{1,2})/(\d{1,2})/(\d{4})", texto)
        if m:
            fecha = _fecha_segura(int(m.group(3)), int(m.group(2)), int(m.group(1)))
        if not fecha:  # si el texto no trae fecha, probar con el nombre del archivo
            m = re.search(r"/(\d{4})(\d{2})(\d{2})[^/]*$", url)
            if m:
                fecha = _fecha_segura(int(m.group(1)), int(m.group(2)), int(m.group(3)))
        if fecha and (hoy is None or fecha <= hoy):
            informes.setdefault(url, {"fecha": fecha, "url": url})
    return sorted(informes.values(), key=lambda i: i["fecha"], reverse=True)


def _decimal(txt):
    return float(txt.replace(",", "."))


def _entero_con_puntos(txt):
    return int(txt.replace(".", "").replace(",", ""))


def parsear_informe(pdf_bytes, puerto="Paysandú"):
    """Extrae del PDF la fila del puerto y datos generales. Trabaja sobre el texto
    (la tabla no siempre se detecta como tabla). Los campos que no encuentra
    quedan en None; nunca se inventan."""
    with pdfplumber.open(io.BytesIO(pdf_bytes)) as pdf:
        texto = "\n".join(p.extract_text() or "" for p in pdf.pages)
    texto = unicodedata.normalize("NFC", texto)
    plano = re.sub(r"\s+", " ", texto)

    datos = {"informe_fecha": None, "altura_esperada_m": None, "nivel_alerta_m": None,
             "nivel_evacuacion_m": None, "caudal_salto_grande_m3s": None, "texto": None}

    m = re.search(r"(\d{1,2}) de ([a-záéíóú]+) de (\d{4})", plano, re.IGNORECASE)
    if m:
        mes = m.group(2).lower().replace("setiembre", "septiembre")
        if mes in MESES:
            datos["informe_fecha"] = _fecha_segura(int(m.group(3)), MESES.index(mes) + 1, int(m.group(1)))

    # Fila de la tabla: "Paysandú 6,66 4,39 6,89" = esperada, alerta, evacuación.
    num = r"(\d{1,2}[.,]\d{1,2})"
    nombre = re.escape(puerto).replace("ú", "[uú]")
    m = re.search(rf"^{nombre}\s+{num}\s+{num}\s+{num}\s*$", texto, re.MULTILINE | re.IGNORECASE)
    if m:
        esperada, alerta, evacuacion = (_decimal(g) for g in m.groups())
        # El nivel de alerta siempre es menor que el de evacuación; si no, las
        # columnas cambiaron de orden y preferimos no publicar nada.
        if 0 <= esperada <= 20 and alerta < evacuacion:
            datos["altura_esperada_m"] = esperada
            datos["nivel_alerta_m"] = alerta
            datos["nivel_evacuacion_m"] = evacuacion

    # Caudal máximo previsto: "...erogado por Salto Grande (18.000 m3/s)".
    m = re.search(r"Salto Grande \(\s*([\d.]+)\s*m[3³]/s\s*\)", plano)
    if m:
        datos["caudal_salto_grande_m3s"] = _entero_con_puntos(m.group(1))
    else:
        m = re.search(r"variar[áa] entre ([\d.]+) y ([\d.]+) m[3³]/s", plano)
        if m:
            datos["caudal_salto_grande_m3s"] = max(_entero_con_puntos(g) for g in m.groups())

    # Resumen: el párrafo "Tendencia" tal cual lo escribe CARU.
    m = re.search(r"^Tendencia\s*$(.*?)^Pron[oó]stico\s*$", texto, re.MULTILINE | re.DOTALL)
    if m:
        datos["texto"] = re.sub(r"\s+", " ", m.group(1)).strip() or None

    return datos
