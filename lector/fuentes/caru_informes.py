"""Informes de crecida de CARU: página índice con enlaces a PDF, y el PDF."""
import io
import re
import unicodedata
from datetime import date
from urllib.parse import urljoin

import pdfplumber
from bs4 import BeautifulSoup

from red import url_permitida

# Los informes reales son de una página y pesan menos de 1 MB.
MAX_BYTES_PDF = 5_000_000
MAX_PAGINAS_PDF = 10
MAX_TEXTO_PDF = 50_000
MAX_RESUMEN = 600
MAX_CAUDAL_M3S = 100_000  # la mayor crecida registrada en Salto Grande no llegó a 40.000

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
        # El PDF se descarga y su dirección se publica: solo desde el sitio de CARU.
        if not url_permitida(url):
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
    if len(pdf_bytes) > MAX_BYTES_PDF or not pdf_bytes.startswith(b"%PDF-"):
        raise ValueError("el archivo no es un PDF de informe válido")
    with pdfplumber.open(io.BytesIO(pdf_bytes)) as pdf:
        if len(pdf.pages) > MAX_PAGINAS_PDF:
            raise ValueError("PDF con demasiadas páginas")
        texto = "\n".join(p.extract_text() or "" for p in pdf.pages)
    texto = texto[:MAX_TEXTO_PDF]
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
    candidatos = []
    m = re.search(r"Salto Grande \(\s*([\d.]{1,12})\s*m[3³]/s\s*\)", plano)
    if m:
        candidatos = [m.group(1)]
    else:
        m = re.search(r"variar[áa] entre ([\d.]{1,12}) y ([\d.]{1,12}) m[3³]/s", plano)
        if m:
            candidatos = list(m.groups())
    caudales = []
    for txt in candidatos:
        try:
            caudales.append(_entero_con_puntos(txt))
        except ValueError:
            pass
    if caudales and 0 < max(caudales) <= MAX_CAUDAL_M3S:
        datos["caudal_salto_grande_m3s"] = max(caudales)

    # Resumen: el párrafo "Tendencia" tal cual lo escribe CARU, recorriendo las
    # líneas (sin expresiones regulares sobre todo el texto) y con largo acotado.
    lineas = [linea.strip() for linea in texto.splitlines()]
    if "Tendencia" in lineas:
        desde = lineas.index("Tendencia") + 1
        hasta = next((k for k in range(desde, len(lineas)) if lineas[k] in ("Pronóstico", "Pronostico")), None)
        if hasta is not None:
            resumen = " ".join(" ".join(lineas[desde:hasta]).split())
            resumen = "".join(c for c in resumen if c.isprintable())
            if len(resumen) > MAX_RESUMEN:
                resumen = resumen[:MAX_RESUMEN].rsplit(" ", 1)[0] + "…"
            datos["texto"] = resumen or None

    return datos
