"""Lector de CARU: baja las fuentes, valida y escribe los JSON de data/.

Uso (desde la raíz del repositorio):
    python lector/lector.py
"""
import json
import os
import sys
from datetime import date, datetime, timedelta
from pathlib import Path

import red
import validar
from fuentes import caru_informes, caru_registro
from fuentes.caru_registro import TZ_UY
from nivel import UMBRALES_PROVISORIOS, calcular_nivel

RAIZ = Path(__file__).resolve().parent.parent
DATA = RAIZ / "data"

FUENTE_ESTACION = "CARU – estación automática Paysandú"
FUENTE_PREFECTURA = "CARU – registro de puertos (Prefectura), Paysandú"


# ---------- archivos ----------

def leer_json(ruta, por_defecto=None):
    """Si el archivo no existe devuelve `por_defecto`. Si existe pero está mal
    escrito lanza ValueError: preferimos frenar antes que pisarlo."""
    try:
        texto = Path(ruta).read_text(encoding="utf-8-sig")
    except FileNotFoundError:
        return por_defecto
    try:
        return json.loads(texto)
    except ValueError as e:
        raise ValueError(f"{ruta} no es un JSON válido: {e}") from e


def escribir_texto(ruta, texto):
    """Escribe a un archivo temporal y lo renombra, para que nunca quede un
    JSON a medio escribir si el proceso se corta."""
    ruta = Path(ruta)
    ruta.parent.mkdir(parents=True, exist_ok=True)
    tmp = ruta.with_suffix(ruta.suffix + ".tmp")
    tmp.write_text(texto, encoding="utf-8", newline="\n")
    os.replace(tmp, ruta)


# ---------- altura actual ----------

def _lectura_json(lectura, fuente=None):
    """Lectura interna -> forma del contrato (sección 5)."""
    salida = {
        "valor_m": lectura["valor_m"],
        "fecha": lectura["fecha"].isoformat(),
        "variacion_m": lectura["variacion_m"],
        "periodo": lectura["periodo"],
        "estado": lectura["estado"],
    }
    if fuente:
        salida["fuente"] = fuente
    salida["url"] = lectura["url"]
    return salida


def elegir_principal(estacion, prefectura, ahora, cfg):
    """Decide qué lectura se muestra como altura actual.
    Devuelve (lectura, fuente, max_horas, avisos)."""
    avisos = []

    def depurar(lectura):
        if lectura and not validar.en_rango(lectura["valor_m"]):
            avisos.append("dato_fuera_de_rango")
            return None
        # Una fecha en el futuro es un error de la fuente: no la tomamos como actual.
        if lectura and validar.horas_de_antiguedad(lectura["fecha"], ahora) < -0.5:
            avisos.append("dato_a_verificar")
            return None
        return lectura

    estacion, prefectura = depurar(estacion), depurar(prefectura)

    # Si las dos fuentes son de fechas cercanas y difieren mucho, alguna está mal.
    if estacion and prefectura:
        horas = abs(validar.horas_de_antiguedad(estacion["fecha"], prefectura["fecha"]))
        if horas <= cfg["prefectura_max_horas"] and abs(estacion["valor_m"] - prefectura["valor_m"]) > validar.SALTO_MAX_M:
            avisos.append("dato_a_verificar")

    def al_dia(lectura, max_horas):
        return lectura and validar.horas_de_antiguedad(lectura["fecha"], ahora) <= max_horas

    est = (estacion, FUENTE_ESTACION, cfg["estacion_max_horas"])
    pre = (prefectura, FUENTE_PREFECTURA, cfg["prefectura_max_horas"])

    if al_dia(*est[::2]):
        elegida = est
    elif al_dia(*pre[::2]):
        # La estación automática se quedó sin transmitir: mostramos Prefectura y avisamos.
        elegida = pre
        avisos.append("estacion_desactualizada")
    else:
        # Ninguna está al día: mostramos la más reciente que haya.
        candidatas = [c for c in (est, pre) if c[0]]
        if not candidatas:
            return None, None, None, avisos
        elegida = max(candidatas, key=lambda c: c[0]["fecha"])
        avisos.append("dato_desactualizado")
    return (*elegida, avisos)


def _fecha_iso(txt):
    try:
        return datetime.fromisoformat(txt)
    except (TypeError, ValueError):
        return None


def armar_actual(registro, pronostico, umbrales, anterior, ahora, cfg):
    """Arma el contenido de actual.json. No toca la red ni el disco.

    registro: salida de parsear_registro, o None si la fuente falló.
    pronostico: bloque ya armado (ver armar_pronostico).
    anterior: actual.json previo (o None), para no perder el último dato válido.
    """
    anterior = anterior or {}
    avisos = []
    altura = None
    prefectura_json = None
    fecha_principal = None

    principal = None
    if registro is not None:
        estacion, prefectura = registro["estacion"], registro["prefectura"]
        principal, fuente, _, avisos = elegir_principal(estacion, prefectura, ahora, cfg)

    if principal:
        if prefectura and validar.en_rango(prefectura["valor_m"]):
            prefectura_json = _lectura_json(prefectura)
        else:
            prefectura_json = anterior.get("lectura_prefectura")
        altura = _lectura_json(principal, fuente)
        fecha_principal = principal["fecha"]
        previa = anterior.get("altura_actual") or {}
        referencias = [(principal["anterior_m"], principal["fecha_anterior"]),
                       (previa.get("valor_m"), _fecha_iso(previa.get("fecha")))]
        if validar.salto_sospechoso(principal["valor_m"], principal["fecha"], referencias):
            avisos.append("dato_a_verificar")
        cero = registro["cero"] or cfg["cero"]
    else:
        # La fuente falló, o respondió sin una lectura utilizable de Paysandú (por
        # ejemplo, si cambió el formato): conservamos el último dato válido, con su
        # fecha original y los avisos que ya tenía.
        avisos.append("fuente_no_disponible")
        avisos += [a for a in anterior.get("avisos", [])
                   if a in ("dato_a_verificar", "estacion_desactualizada")]
        altura = anterior.get("altura_actual")
        prefectura_json = anterior.get("lectura_prefectura")
        cero = anterior.get("cero", cfg["cero"])
        if altura:
            fecha_principal = _fecha_iso(altura.get("fecha"))
            es_estacion = altura.get("fuente") == FUENTE_ESTACION
            max_horas = cfg["estacion_max_horas"] if es_estacion else cfg["prefectura_max_horas"]
            if fecha_principal and validar.horas_de_antiguedad(fecha_principal, ahora) > max_horas:
                avisos.append("dato_desactualizado")

    # Si el dato es demasiado viejo no lo usamos para decir en qué nivel está el río.
    confiable = (altura and fecha_principal
                 and validar.horas_de_antiguedad(fecha_principal, ahora) <= cfg["sin_dato_horas"])
    nivel = calcular_nivel(altura["valor_m"], umbrales) if confiable else "sin_dato"

    return {
        "generado": ahora.replace(microsecond=0).isoformat(),
        "cero": cero,
        "altura_actual": altura,
        "lectura_prefectura": prefectura_json,
        "pronostico": pronostico,
        "nivel": nivel,
        "avisos": sorted(set(avisos)),
    }


# ---------- pronóstico ----------

def armar_pronostico(informe, url, anterior, hoy, cfg):
    """informe: salida de parsear_informe (o None si no se pudo leer ninguno).
    Si no hay informe nuevo se conserva el anterior, recalculando si sigue vigente."""
    if informe and informe["informe_fecha"] and informe["altura_esperada_m"] is not None:
        bloque = {
            "informe_fecha": informe["informe_fecha"].isoformat(),
            "altura_esperada_m": informe["altura_esperada_m"],
            "texto": informe["texto"],
            "caudal_salto_grande_m3s": informe["caudal_salto_grande_m3s"],
            "url_informe": url,
        }
    else:
        bloque = {k: v for k, v in (anterior or {}).items() if k != "vigente"}

    vigente = False
    try:
        fecha = date.fromisoformat(bloque.get("informe_fecha") or "")
        vigente = 0 <= (hoy - fecha).days <= cfg["informe_vigente_dias"]
    except ValueError:
        pass
    return {"vigente": vigente, **bloque}


# ---------- historial ----------

def actualizar_historial(historial, nuevas, ahora, cfg):
    """Agrega lecturas sin duplicar (misma fecha y fuente), descarta las de más
    de `historial_dias` y aligera las viejas: de la estación automática (una cada
    30 min) se guarda todo en los últimos `historial_detalle_dias`; de antes,
    solo las lecturas reales de las 00, 06, 12 y 18 h. Así el archivo que baja
    el celular no pasa de unos cientos de KB."""
    por_clave = {(e["fecha"], e["fuente"]): e for e in historial}
    for fuente, lecturas in nuevas.items():
        for fecha, valor in lecturas:
            if validar.en_rango(valor):
                clave = (fecha.isoformat(), fuente)
                por_clave[clave] = {"fecha": clave[0], "valor_m": valor, "fuente": fuente}

    limite = ahora - timedelta(days=cfg["historial_dias"])
    detalle = ahora - timedelta(days=cfg["historial_detalle_dias"])
    salida = []
    for entrada in por_clave.values():
        fecha = _fecha_iso(entrada["fecha"])
        if not fecha or fecha < limite:
            continue
        if entrada["fuente"] == "estacion" and fecha < detalle:
            if fecha.minute != 0 or fecha.hour % 6 != 0:
                continue
        salida.append(entrada)
    return sorted(salida, key=lambda e: (_fecha_iso(e["fecha"]), e["fuente"]))


def historial_a_texto(historial):
    return "[\n" + ",\n".join(json.dumps(e, ensure_ascii=False) for e in historial) + "\n]\n"


# ---------- programa ----------

def main():
    cfg = leer_json(Path(__file__).parent / "config.json")
    if cfg["cero"] != "Local":
        print(f"ERROR: el cero '{cfg['cero']}' todavía no está soportado; usá 'Local'.")
        return 1
    bajar = lambda url: red.descargar(url, cfg["red_intentos"], cfg["red_espera_s"], cfg["red_timeout_s"])
    ahora = datetime.now(TZ_UY)

    try:
        umbrales = leer_json(DATA / "umbrales.json")
        anterior = leer_json(DATA / "actual.json")
        historial_previo = leer_json(DATA / "historial.json", [])
    except ValueError as e:
        print(f"ERROR: {e}. No modifiqué nada; corregí ese archivo y volvé a correr.")
        return 1
    if umbrales is None:
        umbrales = UMBRALES_PROVISORIOS
        escribir_texto(DATA / "umbrales.json", json.dumps(umbrales, ensure_ascii=False, indent=2) + "\n")
        print("Creé data/umbrales.json con los valores provisorios (sin validar).")

    # 1) Registro de alturas
    registro = None
    try:
        html = bajar(cfg["registro_url"]).decode("utf-8", errors="replace")
        registro = caru_registro.parsear_registro(html, cfg["registro_url"], cfg["puerto"])
        if registro["cero"] and registro["cero"] != cfg["cero"]:
            print(f"AVISO: la página vino en cero '{registro['cero']}' y no en '{cfg['cero']}'; la descarto.")
            registro = None
    except Exception as e:  # una fuente caída no debe tirar abajo el resto
        print(f"AVISO: no pude leer el registro de alturas: {e}")

    # 2) Historial (páginas de detalle de la estación y de Prefectura)
    nuevas = {}
    for fuente in ("estacion", "prefectura"):
        lectura = registro and registro[fuente]
        if not lectura:
            continue
        try:
            html = bajar(lectura["url"]).decode("utf-8", errors="replace")
            nuevas[fuente] = caru_registro.parsear_historial(html)
        except Exception as e:
            print(f"AVISO: no pude leer el historial de {fuente}: {e}")
        # La lectura actual entra siempre, aunque falle la página de detalle.
        nuevas.setdefault(fuente, []).append((lectura["fecha"], lectura["valor_m"]))

    # 3) Informe de crecida más reciente
    informe, url_informe = None, None
    try:
        indice = bajar(cfg["informes_indice_url"]).decode("utf-8", errors="replace")
        informes = caru_informes.listar_informes(indice, cfg["informes_indice_url"], ahora.date())
        previo = (anterior or {}).get("pronostico") or {}
        if informes and informes[0]["url"] == previo.get("url_informe"):
            pass  # ya lo tenemos leído: no hace falta bajar el PDF otra vez
        elif informes:
            url_informe = informes[0]["url"]
            informe = caru_informes.parsear_informe(bajar(url_informe), cfg["puerto"])
            # Si la fecha del PDF y la del índice no coinciden, nos quedamos con la
            # más vieja: así, ante la duda, el informe deja de ser vigente antes.
            informe["informe_fecha"] = min(informe["informe_fecha"] or informes[0]["fecha"], informes[0]["fecha"])
            if informe["altura_esperada_m"] is None:
                print(f"AVISO: no encontré la fila de {cfg['puerto']} en {url_informe}")
    except Exception as e:
        print(f"AVISO: no pude leer los informes de crecida: {e}")

    pronostico = armar_pronostico(informe, url_informe, (anterior or {}).get("pronostico"), ahora.date(), cfg)
    actual = armar_actual(registro, pronostico, umbrales, anterior, ahora, cfg)

    # Solo reescribimos si cambió algo más que la hora de generación,
    # para que el repositorio no acumule commits vacíos.
    sin_hora = lambda d: {k: v for k, v in (d or {}).items() if k != "generado"}
    if sin_hora(actual) != sin_hora(anterior):
        escribir_texto(DATA / "actual.json", json.dumps(actual, ensure_ascii=False, indent=2) + "\n")
        print("Actualicé data/actual.json")
    else:
        print("Sin cambios en data/actual.json")

    historial = actualizar_historial(historial_previo, nuevas, ahora, cfg)
    if historial != historial_previo:
        escribir_texto(DATA / "historial.json", historial_a_texto(historial))
        print(f"Actualicé data/historial.json ({len(historial)} lecturas)")

    a = actual["altura_actual"]
    if a:
        print(f"Altura: {a['valor_m']} m ({a['fecha']}) · nivel: {actual['nivel']} · avisos: {actual['avisos']}")
    else:
        print(f"Sin dato de altura · avisos: {actual['avisos']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
