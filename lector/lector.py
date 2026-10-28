"""Lector de CARU: baja las fuentes, valida y escribe los JSON de data/.

Uso (desde la raíz del repositorio):
    python lector/lector.py
"""
import json
import math
import os
import sys
import time
from datetime import date, datetime, timedelta
from pathlib import Path

import pdf_aislado
import red
import validar
from fuentes import caru_informes, caru_registro
from fuentes.caru_registro import TZ_UY
from nivel import NIVELES_CON_DATO, UMBRALES_PROVISORIOS, nivel_con_margen, umbrales_validos

RAIZ = Path(__file__).resolve().parent.parent
# En GitHub Actions los datos viven en otra rama (datos), traída en otra carpeta:
# LECTOR_DATOS apunta a su data/. Sin la variable, data/ del repositorio.
DATA = Path(os.environ["LECTOR_DATOS"]) if os.environ.get("LECTOR_DATOS") else RAIZ / "data"

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

    # Si las dos fuentes son de horas cercanas y difieren mucho, alguna está mal.
    # Solo se avisa: no retiene el nivel (en una crecida rápida, la lectura diaria
    # de Prefectura queda atrás de la estación y eso no es un error).
    if estacion and prefectura:
        horas = abs(validar.horas_de_antiguedad(estacion["fecha"], prefectura["fecha"]))
        if horas <= cfg["discrepancia_max_horas"] and abs(estacion["valor_m"] - prefectura["valor_m"]) > validar.SALTO_MAX_M:
            avisos.append("dato_a_verificar")

    def al_dia(lectura, max_horas):
        return lectura and validar.horas_de_antiguedad(lectura["fecha"], ahora) <= max_horas

    est = (estacion, FUENTE_ESTACION, cfg["estacion_max_horas"])
    pre = (prefectura, FUENTE_PREFECTURA, cfg["prefectura_max_horas"])

    # Se muestra siempre la lectura más reciente de las dos (si empatan, la estación).
    candidatas = [c for c in (est, pre) if c[0]]
    if not candidatas:
        return None, None, None, avisos
    elegida = max(candidatas, key=lambda c: c[0]["fecha"])
    if elegida is pre and estacion and not al_dia(*est[::2]):
        avisos.append("estacion_desactualizada")  # la estación dejó de transmitir
    if not al_dia(*elegida[::2]):
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
    salto = False  # la lectura principal saltó más de 1 m contra la anterior
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
            salto = True
        cero = registro["cero"] or cfg["cero"]
    else:
        # La fuente falló, o respondió sin una lectura utilizable de Paysandú (por
        # ejemplo, si cambió el formato): conservamos el último dato válido, con su
        # fecha original. "dato_a_verificar" solo se arrastra si la altura que queda
        # publicada es la lectura dudosa de un salto (retenida, o ya liberada durante
        # este mismo corte): un aviso por otra causa no tiene por qué durar todo el corte.
        avisos.append("fuente_no_disponible")
        avisos += [a for a in anterior.get("avisos", []) if a == "estacion_desactualizada"]
        altura = anterior.get("altura_actual")
        prefectura_json = anterior.get("lectura_prefectura")
        cero = anterior.get("cero", cfg["cero"])
        if altura:
            fecha_principal = _fecha_iso(altura.get("fecha"))
            previos = anterior.get("avisos", [])
            retenida = _fecha_iso((anterior.get("nivel_retenido") or {}).get("fecha_lectura"))
            if fecha_principal and retenida == fecha_principal:
                avisos.append("dato_a_verificar")
                salto = True  # la retención sigue, con el mismo tope de tiempo
            elif "fuente_no_disponible" in previos and "dato_a_verificar" in previos:
                avisos.append("dato_a_verificar")
            es_estacion = altura.get("fuente") == FUENTE_ESTACION
            max_horas = cfg["estacion_max_horas"] if es_estacion else cfg["prefectura_max_horas"]
            if fecha_principal and validar.horas_de_antiguedad(fecha_principal, ahora) > max_horas:
                avisos.append("dato_desactualizado")

    # Si el dato es demasiado viejo no lo usamos para decir en qué nivel está el río.
    confiable = (altura and fecha_principal
                 and validar.horas_de_antiguedad(fecha_principal, ahora) <= cfg["sin_dato_horas"])
    if not confiable:
        nivel = "sin_dato"
    elif not umbrales_validos(umbrales):
        # Con umbrales mal cargados no se puede decir en qué nivel está el río.
        nivel = "sin_dato"
        avisos.append("umbrales_invalidos")
    else:
        # El margen al bajar va antes de la retención: así la retención compara el
        # nivel ya con margen, y una oscilación dentro del margen no retiene nada.
        nivel = nivel_con_margen(altura["valor_m"], umbrales, anterior.get("nivel"), cfg["margen_bajada_m"])
    retenido = None
    if salto and nivel != "sin_dato" and anterior.get("nivel") in NIVELES_CON_DATO and nivel != anterior["nivel"]:
        nivel, retenido = retener_nivel(nivel, fecha_principal, anterior, ahora, cfg)

    # Contraste con el pronóstico de CARU (solo avisa, nunca retiene): un informe
    # reciente que espera una altura muy distinta sugiere un error en uno de los dos.
    if altura and contradice_pronostico(altura["valor_m"], pronostico, ahora, cfg):
        avisos.append("dato_a_verificar")

    actual = {
        "generado": ahora.replace(microsecond=0).isoformat(),
        "cero": cero,
        "altura_actual": altura,
        "lectura_prefectura": prefectura_json,
        "pronostico": pronostico,
        "nivel": nivel,
        "avisos": sorted(set(avisos)),
    }
    if retenido:
        actual["nivel_retenido"] = retenido
    return actual


def contradice_pronostico(valor_m, pronostico, ahora, cfg):
    """True si hay un informe vigente y reciente (de hasta `contraste_pronostico_dias`)
    cuya altura esperada difiere más de `contraste_pronostico_m` de la medida."""
    pronostico = pronostico or {}
    esperada = pronostico.get("altura_esperada_m")
    if not pronostico.get("vigente") or type(esperada) not in (int, float):
        return False
    try:
        dias = (ahora.date() - date.fromisoformat(pronostico.get("informe_fecha") or "")).days
    except ValueError:
        return False
    return 0 <= dias <= cfg["contraste_pronostico_dias"] and abs(valor_m - esperada) > cfg["contraste_pronostico_m"]


def retener_nivel(calculado, fecha_lectura, anterior, ahora, cfg):
    """Un salto de más de 1 m contra la lectura anterior puede ser un error del
    sensor. Ese dato se publica (con "dato_a_verificar"), pero el nivel no cambia
    en esa pasada: se mantiene el anterior hasta que llegue una lectura MÁS NUEVA
    (otra fecha) o pasen `retencion_max_min` minutos, lo que ocurra primero. Así
    un pico falso no dispara una evacuación, y una crecida real se publica a más
    tardar media hora después (la estación informa cada 30 min).
    Devuelve (nivel, estado de retención o None)."""
    previa = anterior.get("nivel_retenido") or {}
    desde = _fecha_iso(previa.get("desde"))
    fecha_retenida = _fecha_iso(previa.get("fecha_lectura"))
    if not desde or not fecha_retenida:
        # Primera vez que se ve este salto: se retiene una pasada.
        return anterior["nivel"], {"fecha_lectura": fecha_lectura.isoformat(),
                                   "desde": ahora.replace(microsecond=0).isoformat()}
    if fecha_lectura > fecha_retenida:
        return calculado, None  # una lectura nueva lo confirma
    if ahora - desde >= timedelta(minutes=cfg["retencion_max_min"]):
        return calculado, None  # la misma lectura, pero ya pasó el tope: se publica
    return anterior["nivel"], previa


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

# Con la configuración real el historial tiene unos pocos miles de puntos (una
# semana de la estación cada 30 min más 4 por día de un año). 20.000 ya es una
# señal clara de archivo anómalo; la app (que lo baja con tope de 2 MB) no
# debería procesar más que eso. Si el archivo YA en disco lo supera, queda
# congelado (como uno ilegible) con un `::error::` y código de salida 0; se
# recupera borrándolo o recortándolo a mano en la rama `datos` (ver README).
MAX_PUNTOS_HISTORIAL = 20_000


def actualizar_historial(historial, nuevas, ahora, cfg):
    """Agrega lecturas sin duplicar (misma fecha y fuente), descarta las de más
    de `historial_dias` y aligera las viejas: de la estación automática (una cada
    30 min) se guarda todo en los últimos `historial_detalle_dias`; de antes,
    solo las lecturas reales de las 00, 06, 12 y 18 h. Así el archivo que baja
    el celular no pasa de unos cientos de KB."""
    por_clave = {(e["fecha"], e["fuente"]): e for e in historial}
    limite = ahora - timedelta(days=cfg["historial_dias"])
    detalle = ahora - timedelta(days=cfg["historial_detalle_dias"])
    futuro = ahora + timedelta(minutes=30)
    corregible = ahora - timedelta(hours=cfg["historial_correccion_horas"])
    for fuente, lecturas in nuevas.items():
        for fecha, valor in lecturas:
            # Solo se aceptan lecturas de la última semana (lo que traen las páginas
            # de detalle). Un punto ya guardado solo se corrige si es de las últimas
            # `historial_correccion_horas` (así una corrección de CARU borra un pico
            # falso); lo más viejo no se reescribe: una página alterada no cambia el pasado.
            if validar.en_rango(valor) and detalle <= fecha <= futuro:
                clave = (fecha.isoformat(), fuente)
                entrada = {"fecha": clave[0], "valor_m": valor, "fuente": fuente}
                if fecha >= corregible:
                    por_clave[clave] = entrada
                else:
                    por_clave.setdefault(clave, entrada)

    salida = []
    for entrada in por_clave.values():
        fecha = _fecha_iso(entrada["fecha"])
        # Ni lecturas viejas ni con fecha futura (error o manipulación de la fuente).
        if not fecha or fecha < limite or fecha > ahora + timedelta(minutes=30):
            continue
        if entrada["fuente"] == "estacion" and fecha < detalle:
            if fecha.minute != 0 or fecha.hour % 6 != 0:
                continue
        salida.append(entrada)
    salida.sort(key=lambda e: (_fecha_iso(e["fecha"]), e["fuente"]))
    return salida[-MAX_PUNTOS_HISTORIAL:]  # si se pasara, se pierden los más viejos


def historial_a_texto(historial):
    return "[\n" + ",\n".join(json.dumps(e, ensure_ascii=False, allow_nan=False) for e in historial) + "\n]\n"


# ---------- programa ----------

def guardar_actual(actual, ultimo):
    """Escribe actual.json si cambió algo más que la hora de generación (para que
    el repositorio no acumule commits vacíos). Devuelve lo que quedó en disco."""
    sin_hora = lambda d: {k: v for k, v in (d or {}).items() if k != "generado"}
    if sin_hora(actual) == sin_hora(ultimo):
        return ultimo
    escribir_texto(DATA / "actual.json", json.dumps(actual, ensure_ascii=False, indent=2, allow_nan=False) + "\n")
    print("Actualicé data/actual.json")
    return actual


def guardar_historial(historial, ultimo):
    if historial == ultimo:
        return ultimo
    escribir_texto(DATA / "historial.json", historial_a_texto(historial))
    print(f"Actualicé data/historial.json ({len(historial)} lecturas)")
    return historial


def con_aviso(actual, aviso, poner):
    if poner:
        actual["avisos"] = sorted(set(actual["avisos"]) | {aviso})
    return actual


def _marcar_pdf_fallido(estado, url, ahora):
    estado["pdf_fallido"] = {"url": url, "fecha": ahora.replace(microsecond=0).isoformat()}


def leer_informe(cfg, anterior, estado, ahora, bajar, hay_tiempo):
    """Busca el informe de crecida más reciente. Devuelve (informe, url, falla):
    falla=True si no se pudo saber o leer el informe vigente (se avisa con
    "pronostico_no_disponible"). Anota en `estado` el PDF que no se pudo leer,
    para no volver a intentarlo en cada pasada."""
    if not hay_tiempo():
        print("AVISO: sin tiempo para revisar los informes de crecida en esta pasada")
        return None, None, True
    try:
        indice = bajar(cfg["informes_indice_url"], "informes").decode("utf-8", errors="replace")
        informes = caru_informes.listar_informes(indice, cfg["informes_indice_url"], ahora.date())
    except Exception as e:
        print(f"AVISO: no pude leer el índice de informes de crecida: {e}")
        return None, None, True
    previo = (anterior or {}).get("pronostico") or {}
    if not informes or informes[0]["url"] == previo.get("url_informe"):
        return None, None, False  # no hay informes, o ya tenemos leído el último

    url = informes[0]["url"]
    fallido = estado.get("pdf_fallido") or {}
    desde = _fecha_iso(fallido.get("fecha"))
    if fallido.get("url") == url and desde and ahora - desde < timedelta(hours=cfg["pdf_reintento_horas"]):
        print(f"AVISO: {url} falló hace poco; se reintenta cada {cfg['pdf_reintento_horas']} h")
        return None, None, True
    if not hay_tiempo():
        print("AVISO: sin tiempo para bajar el PDF del informe en esta pasada")
        return None, None, True

    try:
        pdf = bajar(url, "informes")
    except ValueError as e:  # PDF desmedido o redirección rara: no se reintenta enseguida
        print(f"AVISO: no pude bajar {url}: {e}")
        _marcar_pdf_fallido(estado, url, ahora)
        return None, None, True
    except Exception as e:  # error de red: se reintenta en la próxima pasada
        print(f"AVISO: no pude bajar {url}: {e}")
        return None, None, True
    try:
        informe = pdf_aislado.parsear_aislado(pdf, cfg["puerto"], cfg["pdf_timeout_s"])
    except pdf_aislado.PdfIlegible as e:
        print(f"AVISO: {e} ({url})")
        _marcar_pdf_fallido(estado, url, ahora)
        return None, None, True
    if informe["altura_esperada_m"] is None:
        print(f"AVISO: no encontré la fila de {cfg['puerto']} en {url}")
        _marcar_pdf_fallido(estado, url, ahora)
        return None, None, True
    estado.pop("pdf_fallido", None)
    # Si la fecha del PDF y la del índice no coinciden, nos quedamos con la
    # más vieja: así, ante la duda, el informe deja de ser vigente antes.
    informe["informe_fecha"] = min(informe["informe_fecha"] or informes[0]["fecha"], informes[0]["fecha"])
    return informe, url, False


def main():
    inicio = time.monotonic()
    cfg = leer_json(Path(__file__).parent / "config.json")
    if cfg["cero"] != "Local":
        print(f"ERROR: el cero '{cfg['cero']}' todavía no está soportado; usá 'Local'.")
        return 1
    margen = cfg.get("margen_bajada_m")
    if type(margen) not in (int, float) or not math.isfinite(margen) or not 0 <= margen <= 0.5:
        print(f"ERROR: margen_bajada_m tiene que ser un número de 0 a 0,5 m (0 lo desactiva); vino {margen!r}.")
        return 1
    red.permitir_origen_de(cfg["registro_url"], "registro")
    red.permitir_origen_de(cfg["informes_indice_url"], "informes")
    ahora = datetime.now(TZ_UY)

    # Tiempos: el workflow corta al lector a los 420 s. El registro (lo principal)
    # tiene reintentos hasta `limite_registro_s`; lo demás (informes, páginas de
    # detalle) se pide con un solo intento, solo si no pasaron
    # `presupuesto_secundarias_s`, y nunca después de `limite_descargas_s`.
    def bajar_registro(url):
        return red.descargar(url, cfg["red_intentos"], cfg["red_espera_s"], cfg["red_timeout_s"],
                             "registro", hasta=inicio + cfg["limite_registro_s"])

    def bajar_secundaria(url, proposito):
        return red.descargar(url, 1, cfg["red_espera_s"], cfg["red_timeout_s"],
                             proposito, hasta=inicio + cfg["limite_descargas_s"])

    def hay_tiempo():
        return time.monotonic() - inicio < cfg["presupuesto_secundarias_s"]

    # Un archivo de data/ ilegible no frena la pasada: la altura se publica igual.
    #   umbrales.json  -> se trata como umbrales inválidos (nivel sin_dato, código 4); no se pisa.
    #   actual.json    -> como si no hubiera dato anterior (se reescribe entero).
    #   historial.json -> no se toca en esta pasada.
    #   estado_lector.json -> se empieza de cero.
    def leer_o(nombre, por_defecto, tipo):
        try:
            valor = leer_json(DATA / nombre, por_defecto)
        except ValueError as e:
            print(f"::error::{e}")
            return por_defecto, True
        if valor is not None and not isinstance(valor, tipo):
            print(f"::error::data/{nombre} no tiene la forma esperada")
            return por_defecto, True
        return valor, False

    umbrales, umbrales_rotos = leer_o("umbrales.json", None, dict)
    anterior, _ = leer_o("actual.json", None, dict)
    historial_previo, historial_roto = leer_o("historial.json", [], list)
    if len(historial_previo) > MAX_PUNTOS_HISTORIAL:
        print(f"::error::data/historial.json tiene {len(historial_previo)} puntos (tope {MAX_PUNTOS_HISTORIAL})")
        historial_previo, historial_roto = [], True
    estado, _ = leer_o("estado_lector.json", {}, dict)
    if umbrales_rotos:
        umbrales = {}  # inválidos: no hay nivel hasta que se corrija el archivo
    elif umbrales is None:
        umbrales = UMBRALES_PROVISORIOS
        escribir_texto(DATA / "umbrales.json", json.dumps(umbrales, ensure_ascii=False, indent=2) + "\n")
        print("Creé data/umbrales.json con los valores provisorios (sin validar).")
    if historial_roto:
        print("AVISO: no toco data/historial.json en esta pasada; corregilo a mano.")
    estado_previo = dict(estado)

    # 1) Registro de alturas
    registro = None
    try:
        html = bajar_registro(cfg["registro_url"]).decode("utf-8", errors="replace")
        registro = caru_registro.parsear_registro(html, cfg["registro_url"], cfg["puerto"])
        if registro["cero"] and registro["cero"] != cfg["cero"]:
            print(f"AVISO: la página vino en cero '{registro['cero']}' y no en '{cfg['cero']}'; la descarto.")
            registro = None
    except Exception as e:  # una fuente caída no debe tirar abajo el resto
        print(f"AVISO: no pude leer el registro de alturas: {e}")

    # actual.json se escribe ya, con el pronóstico que había: si después algo
    # cuelga y el workflow corta al lector, la altura nueva igual queda publicada.
    pronostico_previo = (anterior or {}).get("pronostico")
    falla_previa = "pronostico_no_disponible" in (anterior or {}).get("avisos", [])
    pronostico = armar_pronostico(None, None, pronostico_previo, ahora.date(), cfg)
    actual = con_aviso(armar_actual(registro, pronostico, umbrales, anterior, ahora, cfg),
                       "pronostico_no_disponible", falla_previa)
    escrito = guardar_actual(actual, anterior)

    # La lectura actual entra al historial siempre, aunque después no haya
    # tiempo para las páginas de detalle.
    actuales = {}
    for fuente in ("estacion", "prefectura"):
        lectura = registro and registro[fuente]
        if lectura:
            actuales[fuente] = [(lectura["fecha"], lectura["valor_m"])]
    historial = historial_previo

    def sumar_al_historial(nuevas):
        nonlocal historial, historial_roto
        if historial_roto:
            return
        try:
            historial = guardar_historial(actualizar_historial(historial, nuevas, ahora, cfg), historial)
        except (KeyError, TypeError, AttributeError) as e:  # entradas con forma rara
            print(f"::error::data/historial.json tiene entradas inválidas ({e!r}); no lo toco.")
            historial_roto = True

    sumar_al_historial(actuales)

    # 2) Informe de crecida más reciente (antes que el historial detallado: en
    # una crecida importa más el pronóstico que completar el gráfico).
    informe, url_informe, falla = leer_informe(cfg, anterior, estado, ahora, bajar_secundaria, hay_tiempo)
    pronostico = armar_pronostico(informe, url_informe, pronostico_previo, ahora.date(), cfg)
    actual = con_aviso(armar_actual(registro, pronostico, umbrales, anterior, ahora, cfg),
                       "pronostico_no_disponible", falla)
    escrito = guardar_actual(actual, escrito)
    if estado != estado_previo:
        escribir_texto(DATA / "estado_lector.json", json.dumps(estado, ensure_ascii=False, indent=2) + "\n")

    # 3) Historial (páginas de detalle de la estación y de Prefectura)
    detalle = {}
    for fuente in ([] if historial_roto else actuales):
        if not hay_tiempo():
            print(f"AVISO: sin tiempo para el historial de {fuente} en esta pasada")
            continue
        try:
            html = bajar_secundaria(registro[fuente]["url"], "registro").decode("utf-8", errors="replace")
            detalle[fuente] = caru_registro.parsear_historial(html)
        except Exception as e:
            print(f"AVISO: no pude leer el historial de {fuente}: {e}")
    if detalle:
        sumar_al_historial(detalle)

    a = actual["altura_actual"]
    if a:
        print(f"Altura: {a['valor_m']} m ({a['fecha']}) · nivel: {actual['nivel']} · avisos: {actual['avisos']}")
    else:
        print(f"Sin dato de altura · avisos: {actual['avisos']}")
    print(f"Tiempo: {time.monotonic() - inicio:.1f} s")

    # Códigos de salida (el workflow cuenta las pasadas seguidas con error y, si
    # se repiten, abre un issue para avisar al dueño):
    #   4 = data/umbrales.json mal cargado: no se puede dar el nivel.
    #   3 = no se pudo leer el registro de CARU, o respondió sin dato de Paysandú
    #       (se publicó lo que había, con "fuente_no_disponible").
    if not umbrales_validos(umbrales):
        print("::error::data/umbrales.json tiene valores inválidos (alturas de 0 a 20 m y "
              "atención < alerta < evacuación); el nivel se publica como sin_dato.")
        return 4
    if registro is None or "fuente_no_disponible" in actual["avisos"]:
        return 3
    return 0


if __name__ == "__main__":
    sys.exit(main())
