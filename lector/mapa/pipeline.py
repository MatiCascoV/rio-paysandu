"""Pipeline del mapa de inundación: MDT de IDE + curvas de Dinagua + OSM → carpeta del contrato.

Uso (desde lector/):
    python -m mapa <carpeta_salida> [--config mapa/config.json] [--cache DIR] [--osm-pbf ARCHIVO]
                   [--generado 2026-10-19T18:00:00-03:00] [--sin-png]

Escribe en <carpeta_salida>: indice.json, base.json, agua/NNNN.json, curvas/AAAA-MM.json
(lo que define docs/mapa/05-contrato.md) y además calibracion.json, control.png y mapa.log.
Arma todo en una carpeta temporal y solo la pone en su lugar si todas las validaciones pasan.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import logging
import os
import shutil
import sys
import time
from pathlib import Path

import numpy as np

from . import capas as C
from . import validar as V
from .descarga import Cache, cache_por_defecto, listar_indice_apache, sha256_archivo

log = logging.getLogger("mapa")
AQUI = Path(__file__).resolve().parent
EXT_SHP = (".shp", ".shx", ".dbf", ".prj", ".cpg")


class ErrorPipeline(RuntimeError):
    pass


def cargar_config(ruta: Path) -> dict:
    cfg = json.loads(Path(ruta).read_text(encoding="utf-8"))
    for k in ("cero", "limites", "crs_trabajo", "resolucion_m", "min_m", "max_m", "paso_m", "margen_m",
              "mdt_urbano", "curvas", "llegada", "capas", "calibracion", "fuentes"):
        if k not in cfg:
            raise ErrorPipeline(f"config sin '{k}'")
    return cfg


def _bajar_grilla(cache: Cache, url_sin_ext: str) -> str:
    rutas = {ext: cache.obtener(url_sin_ext + ext) for ext in EXT_SHP}
    # pyshp necesita los archivos con el mismo nombre base: se copian a una subcarpeta.
    carpeta = cache.carpeta / ("grilla_" + hashlib.sha1(url_sin_ext.encode()).hexdigest()[:10])
    carpeta.mkdir(exist_ok=True)
    base = carpeta / Path(url_sin_ext).name
    for ext, r in rutas.items():
        destino = base.with_suffix(ext)
        if not destino.exists() or destino.stat().st_size != r.stat().st_size:
            shutil.copyfile(r, destino)
    return str(base)


def bajar_hojas(cache: Cache, sec: dict, limites, etiqueta: str) -> list[Path]:
    from .terreno import hojas_en_limites
    grilla = _bajar_grilla(cache, sec["grilla_url"])
    en_grilla = hojas_en_limites(grilla, limites, sec.get("grilla_encoding", "latin-1"), sec.get("prefijo"))
    disponibles = set(listar_indice_apache(cache.texto(sec["indice_url"])))
    hojas = [h for h in en_grilla if sec["patron"].format(hoja=h) in disponibles]
    faltan = [h for h in en_grilla if h not in hojas]
    log.info("%s: %d hojas en los límites según la grilla, %d publicadas", etiqueta, len(en_grilla), len(hojas))
    if faltan:
        log.info("%s: hojas de la grilla sin archivo publicado (no hay vuelo ahí): %s", etiqueta, " ".join(faltan))
    if not hojas:
        raise ErrorPipeline(f"{etiqueta}: ninguna hoja disponible dentro de los límites")
    rutas = []
    for i, h in enumerate(hojas, 1):
        rutas.append(cache.obtener(sec["indice_url"] + sec["patron"].format(hoja=h)))
        if i % 10 == 0:
            log.info("%s: %d/%d hojas listas", etiqueta, i, len(hojas))
    return rutas


def rasterizar(geoms_4326, grilla, crs: str, all_touched=False) -> np.ndarray:
    import shapely
    from pyproj import Transformer
    from rasterio import features
    t = Transformer.from_crs("EPSG:4326", crs, always_xy=True)
    gs = [shapely.transform(g, lambda xy: np.column_stack(t.transform(xy[:, 0], xy[:, 1]))) for g in geoms_4326 if not g.is_empty]
    if not gs:
        return np.zeros((grilla.alto, grilla.ancho), bool)
    return features.rasterize(((g, 1) for g in gs), out_shape=(grilla.alto, grilla.ancho),
                              transform=grilla.transform, fill=0, dtype="uint8", all_touched=all_touched).astype(bool)


def mascara_cauce(agua: np.ndarray) -> np.ndarray:
    """Semilla = la componente (4-conexa) más grande de agua de OSM: el río Uruguay."""
    from scipy import ndimage
    from .llegada import CRUZ
    etq, n = ndimage.label(agua, structure=CRUZ)
    if n == 0:
        raise ErrorPipeline("OSM no trae polígonos de agua dentro de los límites: no hay cauce")
    tam = np.bincount(etq.ravel()); tam[0] = 0
    return etq == int(np.argmax(tam))


def limites_computo(cfg) -> list:
    """Caja de cálculo: más grande que `limites` para que las desembocaduras de los arroyos
    queden adentro (si no, el remanso del río no entra). La salida se recorta a `limites`."""
    lc = cfg.get("limites_computo") or cfg["limites"]
    (s, o), (n, e) = lc
    (s0, o0), (n0, e0) = cfg["limites"]
    if not (s <= s0 and o <= o0 and n >= n0 and e >= e0):
        raise ErrorPipeline("limites_computo tiene que contener a limites")
    return lc


def _hash_dict(d) -> str:
    return hashlib.sha256(json.dumps(d, sort_keys=True).encode()).hexdigest()


def preparar_terreno(cfg, cache: Cache, grilla, pbf: Path, curvas_textos):
    """Mosaico + cauce + llegada, con caché en disco (npz) por hash de insumos y config."""
    from . import terreno as T
    from .llegada import llegada_cm
    from .base_osm import extraer, poligonos_agua

    lc = limites_computo(cfg)
    urb = bajar_hojas(cache, cfg["mdt_urbano"], lc, "MDT urbano 1 m")
    nac = []
    if cfg.get("mdt_nacional", {}).get("usar"):
        nac = bajar_hojas(cache, cfg["mdt_nacional"], lc, "MDT nacional 2,5 m")

    # base.json (OSM), con caché por sha256 del pbf
    sha_pbf = sha256_archivo(pbf)
    clave_base = _hash_dict({"pbf": sha_pbf, "limites": cfg["limites"], "v": 1})
    ruta_base = cache.carpeta / f"base_{clave_base[:16]}.json"
    if ruta_base.exists():
        base = json.loads(ruta_base.read_text(encoding="utf-8"))
    else:
        log.info("extrayendo base de OSM de %s", pbf)
        base = extraer(str(pbf), cfg["limites"])
        ruta_base.write_text(json.dumps(base, ensure_ascii=False), encoding="utf-8")
    log.info("base OSM: %d elementos, %d lugares (pbf sha256 %s)", len(base["features"]), len(base["lugares"]), sha_pbf[:12])
    # agua y cursos de OSM para el cálculo, en la caja de cálculo (puede ser más grande)
    if lc == cfg["limites"]:
        osm_calc = base
    else:
        clave_calc = _hash_dict({"pbf": sha_pbf, "limites": lc, "v": 1})
        ruta_calc = cache.carpeta / f"base_{clave_calc[:16]}.json"
        if ruta_calc.exists():
            osm_calc = json.loads(ruta_calc.read_text(encoding="utf-8"))
        else:
            log.info("extrayendo OSM de la caja de cálculo %s", lc)
            osm_calc = extraer(str(pbf), lc)
            ruta_calc.write_text(json.dumps(osm_calc, ensure_ascii=False), encoding="utf-8")

    insumos = {"urbano": [sha256_archivo(r) for r in urb], "nacional": [sha256_archivo(r) for r in nac],
               "pbf": sha_pbf}
    clave = _hash_dict({"insumos": insumos, "grilla": grilla.__dict__, "remuestreo": cfg["remuestreo"],
                        "nac": cfg.get("mdt_nacional"), "huecos": cfg.get("huecos"), "llegada": cfg["llegada"],
                        "nodata": cfg["mdt_urbano"].get("nodata_min"), "limites_computo": lc,
                        "quemar_cursos": cfg.get("quemar_cursos"), "v": 4})
    ruta_npz = cache.carpeta / f"terreno_{clave[:16]}.npz"
    if ruta_npz.exists():
        log.info("terreno y llegada desde la caché: %s", ruta_npz.name)
        z = np.load(ruta_npz, allow_pickle=False)
        info = json.loads(str(z["info"]))
        return base, z["llegada"], z["fuente"], z["cauce"], z["agua"], info, insumos, osm_calc

    t0 = time.time()
    dem = T.mosaico(urb, grilla, cfg["remuestreo"], cfg["mdt_urbano"].get("nodata_min", -1000))
    fuente = np.where(np.isnan(dem), T.SIN_DATO, T.URBANO).astype("uint8")
    info = {"celdas": int(dem.size), "celdas_urbano": int((fuente == T.URBANO).sum())}
    log.info("mosaico urbano: %d hojas, %.1f%% de la grilla con dato (%.0f s)", len(urb),
             100 * info["celdas_urbano"] / dem.size, time.time() - t0)
    if nac:
        dn = T.mosaico(nac, grilla, "bilinear", cfg["mdt_urbano"].get("nodata_min", -1000))
        info["nacional"] = T.rellenar_con_nacional(dem, dn, fuente, cfg["mdt_nacional"]["max_sesgo_abs_m"],
                                                   cfg["mdt_nacional"]["min_celdas_solape"])
        del dn
        log.info("MDT nacional: %s", info["nacional"])

    agua = rasterizar(poligonos_agua(osm_calc), grilla, grilla.crs)
    cauce = mascara_cauce(agua)
    qc = cfg.get("quemar_cursos", {})
    if qc.get("usar"):
        from shapely.geometry import shape
        lineas = [shape(f["geometry"]) for f in osm_calc["features"] if f["properties"].get("t") == "curso"]
        mascara_lineas = rasterizar(lineas, grilla, grilla.crs, all_touched=True) & ~agua
        info["cursos_quemados"] = T.quemar_cursos(dem, mascara_lineas, qc.get("radio_celdas", 1),
                                                   int(qc.get("max_hueco_m", 100) / grilla.res))
        log.info("cursos de agua de OSM quemados en el MDT: %s", info["cursos_quemados"])
    info["celdas_agua_osm"] = int(agua.sum()); info["celdas_cauce"] = int(cauce.sum())
    max_celdas = int(cfg.get("huecos", {}).get("rellenar_max_m2", 0) / grilla.res ** 2)
    info["celdas_huecos_rellenados"] = T.rellenar_huecos_chicos(dem, fuente, agua, max_celdas)
    info["celdas_sin_dato_fuera_del_agua"] = int((np.isnan(dem) & ~agua).sum())
    log.info("cauce: %d celdas; agua OSM: %d; huecos rellenados: %d; sin dato fuera del agua: %d",
             info["celdas_cauce"], info["celdas_agua_osm"], info["celdas_huecos_rellenados"],
             info["celdas_sin_dato_fuera_del_agua"])

    t0 = time.time()
    L = cfg["llegada"]
    lleg = llegada_cm(dem, cauce, L["min_cm"], L["max_cm"], L["cuantizacion_cm"])
    log.info("llegada calculada en %.0f s (%d umbrales)", time.time() - t0,
             (L["max_cm"] - L["min_cm"]) // L["cuantizacion_cm"] + 1)
    del dem
    np.savez_compressed(ruta_npz, llegada=lleg, fuente=fuente, cauce=cauce, agua=agua, info=json.dumps(info))
    return base, lleg, fuente, cauce, agua, info, insumos, osm_calc


def calibrar(cfg, grilla, lleg, fuente, excluir, curvas) -> dict:
    from . import calibracion as K
    from .terreno import URBANO
    kc = cfg["calibracion"]
    deltas = list(range(int(round(kc["delta_min"] * 100)), int(round(kc["delta_max"] * 100)) + 1,
                        int(round(kc["delta_paso"] * 100))))
    cobertura = (fuente == URBANO) if kc.get("solo_mdt_urbano", True) else (fuente > 0)
    tabla, detalle, mascaras = {}, {}, {}
    for cu in curvas:
        m = rasterizar([cu.geom], grilla, grilla.crs)
        filas = np.flatnonzero(m.any(axis=1)); cols = np.flatnonzero(m.any(axis=0))
        if len(filas) == 0:
            log.warning("curva %s fuera de la grilla", cu.clave); continue
        caja = np.zeros_like(m); caja[filas[0]:filas[-1] + 1, cols[0]:cols[-1] + 1] = True
        dom = caja & cobertura & ~excluir
        tabla[cu.clave] = K.barrido(lleg[dom], m[dom], cu.altura_m, deltas)
        mascaras[cu.clave] = (m, dom)
        detalle[cu.clave] = {"altura_m": cu.altura_m, "tipo": cu.tipo,
                             "celdas_dominio": int(dom.sum()),
                             "area_curva_en_dominio_ha": round(float((m & dom).sum()) * grilla.res ** 2 / 1e4, 1),
                             "cobertura_urbana_de_la_curva": round(float((m & caja & cobertura).sum()) / max(int((m & caja).sum()), 1), 3)}
    res = K.ajustar(tabla, deltas, kc["fija"], kc["validacion"], kc["iou_min"], kc["estabilidad_m"])
    d_cm = int(round(res["delta_m"] * 100))
    zona_baja = lleg <= int(round(cfg["min_m"] * 100)) + d_cm  # mojado ya con la capa mínima
    for clave, (m, dom) in mascaras.items():
        h = detalle[clave]["altura_m"]
        mod = lleg <= int(round(h * 100)) + d_cm
        cc = m & dom
        # fracción de la crecida real que el modelo SÍ marca (lo que no marca es lo peligroso)
        detalle[clave]["curva_cubierta"] = round(float((mod & cc).sum()) / max(int(cc.sum()), 1), 4)
        detalle[clave]["modelo_fuera_de_curva"] = round(
            float((mod & dom & ~m).sum()) / max(int((mod & dom).sum()), 1), 4)
        # IoU sin las celdas que ya se mojan a min_m (no dependen de h ni de δ e inflan el IoU)
        detalle[clave]["iou_sin_zona_baja"] = round(K.iou(mod, m, dom & ~zona_baja), 4)
        detalle[clave]["iou"] = round(K.iou(mod, m, dom), 4)
        detalle[clave]["error_borde_m"] = round(K.error_borde_m(mod, m, dom, grilla.res), 1)
        detalle[clave]["area_modelo_en_dominio_ha"] = round(float((mod & dom).sum()) * grilla.res ** 2 / 1e4, 1)
        detalle[clave]["mejor_delta_m"] = res["mejor_delta_por_curva"][clave]
        detalle[clave]["iou_mejor_delta"] = round(max(tabla[clave]), 4)
    res["curvas"] = detalle
    res["chequeo"] = {k: detalle[k]["iou"] for k in kc.get("chequeo", []) if k in detalle}
    res["barrido"] = {"deltas_m": [d / 100 for d in deltas],
                      "iou": {k: [round(x, 4) for x in v] for k, v in tabla.items()}}
    return res


def generar(cfg, salida_tmp: Path, grilla, lleg, excluir, delta_m, base: dict, curvas, osm_calc: dict | None = None):
    """Capas, curvas, base y (si la config lo pide) sin_validar.json en `salida_tmp`.

    Devuelve (entradas de capas, geoms, base_ent, refs, areas, errores, extra); `extra` trae
    la entrada de `sin_validar` para el índice y los números de los controles v1.1."""
    import shapely
    from shapely.geometry import shape
    from . import zonas as Z
    from .base_osm import poligonos_agua
    kc = cfg["capas"]
    dec = kc["decimales"]
    extra = {"celdas_afuera": {}, "aisladas": {}, "aisladas_solo_capa": {}}
    ventana = Z.Ventana(grilla, cfg["limites"])
    ca = cfg.get("aisladas") if (cfg.get("aisladas") or {}).get("usar", True) else None
    if ca:
        calles = Z.Calles(base, grilla.crs)
        polis_agua = poligonos_agua(base)
        agua_base = shapely.union_all(polis_agua) if polis_agua else None
    min_celdas = int(np.ceil(kc["sieve_m2"] / grilla.res ** 2))
    min_seco = int(np.ceil(kc.get("rellenar_secos_m2", kc["sieve_m2"]) / grilla.res ** 2))
    (salida_tmp / "agua").mkdir(parents=True)
    (salida_tmp / "curvas").mkdir()
    entradas, geoms, areas = [], [], {}
    d_cm = int(round(delta_m * 100))
    errores = []
    moj = None
    for h in C.alturas(cfg["min_m"], cfg["max_m"], cfg["paso_m"]):
        t = int(round(h * 100)) + d_cm
        moj = C.tamizar(C.mascara_nivel(lleg, t, excluir), excluir, min_celdas, min_seco)
        area_raster = float(moj.sum()) * grilla.res ** 2
        g = C.poligonizar(moj, grilla.transform, kc["simplify_m"], kc.get("buffer_m", 0.0))
        g = C.a_4326(g, grilla.crs, dec, cfg["limites"])
        props = {"altura_m": h}
        nombre = C.nombre_capa(h)
        if ca:
            props["aisladas"] = Z.lomas_aisladas(g, agua_base, calles, cfg["limites"], ca["min_calles_m"], dec,
                                                 ca.get("con_agua_base", True))
            extra["aisladas"][h] = len(props["aisladas"])
            extra["aisladas_solo_capa"][h] = len(Z.lomas_aisladas(g, None, calles, cfg["limites"],
                                                                  ca["min_calles_m"], dec, False))
        fc = C.feature_collection(g, props, dec)
        datos = C.serializar(fc)
        (salida_tmp / nombre).write_bytes(datos)
        publicada = json.loads(datos)
        errores += [f"{nombre}: {x}" for x in V.validar_capa(publicada, h, cfg["limites"],
                                                              (ca or {}).get("min_calles_m", 0))]
        # 11 §5: ninguna celda mojada afuera de la capa tal como se publica (después del redondeo)
        n_fuera, ej = Z.celdas_afuera(moj, shape(publicada["features"][0]["geometry"]), ventana)
        extra["celdas_afuera"][h] = n_fuera
        if n_fuera:
            errores.append(f"{nombre}: {n_fuera} celdas mojadas quedan afuera de la capa publicada (p. ej. {ej})")
        entradas.append({"altura_m": h, "archivo": nombre, "bytes": len(datos),
                         "sha256": hashlib.sha256(datos).hexdigest()})
        geoms.append(g)
        areas[nombre] = {"altura_m": h, "area_ha": round(area_raster / 1e4, 1),
                         "partes": len(g.geoms), "bytes": len(datos)}
        log.info("%s: %.1f ha, %d partes, %d bytes, %d aisladas, %d celdas afuera", nombre, area_raster / 1e4,
                 len(g.geoms), len(datos), len(props.get("aisladas", [])), n_fuera)
    errores += V.validar_anidado(geoms, kc["tolerancia_anidado"])

    # v1.1 §1: zonas sin validar (valle de un arroyo: todo lo que se moja hasta max_m)
    sv = cfg.get("sin_validar")
    if sv and moj is not None:
        if osm_calc is None:
            raise ErrorPipeline("sin_validar necesita las líneas de OSM de la caja de cálculo")
        rio = rasterizar(Z.lineas_por_nombre(osm_calc, sv["rio"]), grilla, grilla.crs, all_touched=True)
        if not rio.any():
            raise ErrorPipeline(f"sin_validar: no encontré en OSM el río {sv['rio']}")
        zonas = []
        extra["sin_validar_zonas"] = []
        f = sv["factor_celdas"]
        for z in sv["zonas"]:
            lineas = Z.lineas_por_nombre(osm_calc, z["cursos"])
            if not lineas:
                raise ErrorPipeline(f"sin_validar: no encontré en OSM los cursos {z['cursos']}")
            curso = rasterizar(lineas, grilla, grilla.crs, all_touched=True)
            gz, valle, _ = Z.zona_sin_validar(moj, excluir, curso, rio, grilla, f,
                                              z["buffer_m"], sv["simplify_m"], cfg["limites"], dec)
            if gz.is_empty:
                raise ErrorPipeline(f"sin_validar: la zona {z['nombre']} quedó vacía")
            zonas.append((gz, {"nombre": z["nombre"], "motivo": z["motivo"]}))
            # control: la zona tiene que cubrir todo lo mojado del valle (dentro de limites)
            mv = np.repeat(np.repeat(valle, f, 0), f, 1)[:moj.shape[0], :moj.shape[1]] & moj
            n_fuera, _ = Z.celdas_afuera(mv, gz, ventana)
            if n_fuera:
                errores.append(f"sin_validar {z['nombre']}: {n_fuera} celdas mojadas del valle quedan afuera")
            ha_valle = float((mv[ventana.sl] & ventana.enlim).sum()) * grilla.res ** 2 / 1e4
            extra["sin_validar_zonas"].append({"nombre": z["nombre"], "ha_mojadas_max_m": round(ha_valle, 1),
                                               "ha_zona": round(C.area_m2_4326(gz) / 1e4, 1),
                                               "partes": len(gz.geoms), "celdas_afuera": n_fuera})
            log.info("sin_validar %s: %.0f ha mojadas a %.2f m; zona de %.0f ha (%d partes)", z["nombre"], ha_valle,
                     cfg["max_m"], C.area_m2_4326(gz) / 1e4, len(gz.geoms))
        datos = C.serializar(Z.coleccion_zonas(zonas, dec))
        (salida_tmp / "sin_validar.json").write_bytes(datos)
        errores += [f"sin_validar.json: {x}" for x in V.validar_sin_validar(json.loads(datos), cfg["limites"], dec)]
        extra["sin_validar"] = {"archivo": "sin_validar.json", "bytes": len(datos),
                                "sha256": hashlib.sha256(datos).hexdigest()}
        extra["sin_validar_geoms"] = [g for g, _ in zonas]

    datos = C.serializar(base)
    (salida_tmp / "base.json").write_bytes(datos)
    base_ent = {"archivo": "base.json", "bytes": len(datos), "sha256": hashlib.sha256(datos).hexdigest()}

    import shapely
    refs = []
    for cu in curvas:
        if cu.tipo != "crecida":
            continue
        g = shapely.set_precision(cu.geom.simplify(cfg["curvas"]["simplify_grados"], preserve_topology=True), 10 ** -dec)
        g = C.solo_poligonos(shapely.make_valid(g))
        fc = C.feature_collection(g, {"nombre": cu.nombre, "altura_m": cu.altura_m, "fecha": cu.fecha,
                                      "fuente": "Dinagua"}, dec)
        datos = C.serializar(fc)
        nombre = f"curvas/{cu.clave}.json"
        (salida_tmp / nombre).write_bytes(datos)
        refs.append({"tipo": "crecida", "nombre": cu.nombre, "altura_m": cu.altura_m, "fecha": cu.fecha,
                     "archivo": nombre, "bytes": len(datos), "sha256": hashlib.sha256(datos).hexdigest(),
                     "fuente": "Dinagua"})
    return entradas, geoms, base_ent, refs, areas, errores, extra


def capa_para(h: float, min_m: float, max_m: float, paso_m: float) -> float | None:
    """Capa que pinta la app para la altura h: redondeo hacia arriba al paso (contrato).
    None si h < min_m (agua en el cauce); max_m si h > max_m."""
    import math
    if h < min_m - 1e-9:
        return None
    n = math.ceil(round((h - min_m) / paso_m, 4))  # ruido < 0,1 mm no sube de capa
    return round(min(min_m + n * paso_m, max_m), 2)


def armar_indice(cfg, generado: str, validado: bool, delta: float, iou_val: float, base_ent, entradas, refs,
                 sin_validar_ent: dict | None = None) -> dict:
    """indice.json según docs/mapa/05-contrato.md (con los agregados v1.1)."""
    res_txt = f"{cfg['resolucion_m']:g}".replace(".", ",")
    ind = {
        "version": 1,
        "generado": generado,
        "cero": cfg["cero"],
        "validado": validado,
        "modelo": {
            "metodo": (f"Relleno conectado al río sobre el MDT de IDE Uruguay (1 m remuestreado a {res_txt} m, "
                       f"vuelo {cfg['mdt_urbano']['fecha_vuelo'][:4]}), calibrado con crecidas de Dinagua"),
            "delta_m": delta,
            "iou_validacion": iou_val,
            "margen_m": cfg["margen_m"],
        },
        "limites": cfg["limites"],
        "paso_m": cfg["paso_m"],
        "min_m": cfg["min_m"],
        "max_m": cfg["max_m"],
        "base": base_ent,
        "capas": entradas,
        "referencias": refs,
        "fuentes": cfg["fuentes"],
    }
    if sin_validar_ent:
        ind["sin_validar"] = sin_validar_ent
    return ind


def correr(salida: Path, ruta_config: Path, carpeta_cache: Path | None, pbf: Path | None,
           generado: str | None, png: bool = True) -> dict:
    cfg = cargar_config(ruta_config)
    salida = Path(salida).resolve()
    tmp = salida.parent / (salida.name + ".parcial")
    if tmp.exists():
        shutil.rmtree(tmp)
    tmp.mkdir(parents=True)
    manejador = logging.FileHandler(tmp / "mapa.log", encoding="utf-8")
    manejador.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
    log.addHandler(manejador)
    t_ini = time.time()
    try:
        calib = _correr(cfg, ruta_config, salida, tmp, carpeta_cache, pbf, generado, png)
    finally:
        # en Windows no se puede renombrar la carpeta con mapa.log abierto
        log.removeHandler(manejador)
        manejador.close()
    # todo bien: se reemplaza la salida de una vez
    anterior = salida.parent / (salida.name + ".anterior")
    if anterior.exists():
        shutil.rmtree(anterior)
    if salida.exists():
        os.replace(salida, anterior)
    os.replace(tmp, salida)
    if anterior.exists():
        shutil.rmtree(anterior)
    log.info("listo en %.0f s: %s", time.time() - t_ini, salida)
    return calib


def _correr(cfg, ruta_config, salida, tmp, carpeta_cache, pbf, generado, png):
    from .curvas import leer_curvas, url_wfs
    from .terreno import grilla_desde_limites

    t_ini = time.time()
    cache = Cache(Path(carpeta_cache or cfg.get("cache_dir") or cache_por_defecto()))
    log.info("caché: %s; salida: %s", cache.carpeta, salida)
    grilla = grilla_desde_limites(limites_computo(cfg), cfg["crs_trabajo"], cfg["resolucion_m"])
    log.info("grilla %s: %d × %d celdas de %.1f m", grilla.crs, grilla.ancho, grilla.alto, grilla.res)

    textos = [cache.texto(url_wfs(cfg["curvas"]["wfs_url"], capa, cfg["curvas"]["filtro"]))
              for capa in cfg["curvas"]["capas"]]
    curvas = leer_curvas(textos, cfg["curvas"]["curso"])
    log.info("curvas de Dinagua: %s", ", ".join(f"{c.clave} ({c.altura_m} m)" for c in curvas))

    if pbf is None:
        pbf = cache.obtener(cfg["osm"]["pbf_url"])
    pbf = Path(pbf)
    if not pbf.exists():
        raise ErrorPipeline(f"no existe el extracto OSM {pbf}")

    base, lleg, fuente, cauce, agua, info_terreno, insumos, osm_calc = preparar_terreno(cfg, cache, grilla, pbf, textos)
    excluir = agua | cauce  # el cauce normal (y los espejos de agua de OSM) ya están en base.json

    cal = calibrar(cfg, grilla, lleg, fuente, excluir, curvas)
    delta = cal["delta_m"]
    log.info("δ = %.2f m; IoU 2025 %.3f; validación media %.3f (mín %.3f); dejando uno afuera %.3f; dispersión δ %.2f m; criterio %s",
             delta, cal["iou_fija"], cal["iou_validacion_media"], cal["iou_validacion_min"],
             cal["iou_dejando_uno_afuera_media"], cal["dispersion_delta_m"],
             "CUMPLE" if cal["criterio_cumplido"] else "NO CUMPLE")
    for k, v in cal["curvas"].items():
        log.info("  %s (%.2f m): IoU %.3f, borde %.1f m, mejor δ %.2f (IoU %.3f)", k, v["altura_m"], v["iou"],
                 v["error_borde_m"], v["mejor_delta_m"], v["iou_mejor_delta"])

    entradas, geoms, base_ent, refs, areas, errores, extra = generar(cfg, tmp, grilla, lleg, excluir, delta, base,
                                                                     curvas, osm_calc)

    revision = not cfg["calibracion"].get("validado_requiere_revision_externa", True)
    validado = bool(cal["criterio_cumplido"] and revision)
    if generado is None:
        generado = dt.datetime.now(dt.timezone(dt.timedelta(hours=-3))).replace(microsecond=0).isoformat()
    indice = armar_indice(cfg, generado, validado, delta, cal["iou_validacion_media"], base_ent, entradas, refs,
                          extra.get("sin_validar"))
    datos_ind = json.dumps(indice, ensure_ascii=False, indent=1).encode("utf-8")
    (tmp / "indice.json").write_bytes(datos_ind)

    errores += V.validar_indice(indice, cfg["cero"])
    errores += V.validar_archivos(tmp, indice)
    sv_ent = [extra["sin_validar"]] if extra.get("sin_validar") else []
    tamanos = {e["archivo"]: e["bytes"] for e in [base_ent] + entradas + refs + sv_ent}
    tamanos["indice.json"] = len(datos_ind)
    kc = cfg["capas"]
    errores += V.validar_bytes(tamanos, kc["tope_capa_bytes"], kc["tope_base_bytes"], kc["tope_total_bytes"])

    pesos = {"total_contrato_bytes": sum(tamanos.values()),
             "agua_bytes": sum(e["bytes"] for e in entradas),
             "curvas_bytes": sum(r["bytes"] for r in refs),
             "base_bytes": base_ent["bytes"], "indice_bytes": len(datos_ind),
             "sin_validar_bytes": sum(e["bytes"] for e in sv_ent),
             "capa_max": max(entradas, key=lambda e: e["bytes"])["archivo"],
             "capa_max_bytes": max(e["bytes"] for e in entradas)}
    import gzip
    pesos["agua_gzip_bytes"] = sum(len(gzip.compress((tmp / e["archivo"]).read_bytes(), 9, mtime=0)) for e in entradas)

    calib = {
        "version_config": cfg.get("version_config"),
        "generado": generado,
        "mdt": {"producto": "MDT urbano 1 m IDE Uruguay, Remesa Urbana 09 (Paysandú)",
                "fecha_vuelo": cfg["mdt_urbano"]["fecha_vuelo"], "datum_vertical": "EGM2008",
                "resolucion_trabajo_m": cfg["resolucion_m"], "remuestreo": cfg["remuestreo"]},
        "definicion": "terreno MDT (EGM2008) ≈ cota local de Paysandú + δ; capa h = celdas con llegada ≤ h + δ",
        "metrica": "IoU solo en tierra (sin agua de OSM), en la caja de cada curva y en la cobertura del MDT urbano",
        "criterio": {"iou_min": cfg["calibracion"]["iou_min"], "estabilidad_m": cfg["calibracion"]["estabilidad_m"]},
        "validado_indice": validado,
        "revision_externa": revision,
        **cal,
        "terreno": info_terreno,
        "areas": areas,
        "pesos": pesos,
        "v11": {"celdas_afuera_total": sum(extra["celdas_afuera"].values()),
                "celdas_afuera": {f"{h:.2f}": n for h, n in extra["celdas_afuera"].items() if n},
                "aisladas_por_capa": {f"{h:.2f}": n for h, n in extra["aisladas"].items()},
                "aisladas_solo_huecos_de_la_capa": {f"{h:.2f}": n for h, n in extra["aisladas_solo_capa"].items()},
                "sin_validar": extra.get("sin_validar_zonas", [])},
        "insumos_sha256": {**insumos, "config": sha256_archivo(Path(ruta_config)),
                           "descargas": {u: i["sha256"] for u, i in sorted(cache.usados.items())}},
        "errores_validacion": errores,
    }
    (tmp / "calibracion.json").write_text(json.dumps(calib, ensure_ascii=False, indent=1), encoding="utf-8")

    if png:
        from .control import dibujar
        pcs = cfg.get("control_png", [])
        pcs = [pcs] if isinstance(pcs, dict) else pcs
        alturas_capas = [e["altura_m"] for e in entradas]
        for pc in pcs:
            sel = []
            for h in pc.get("capas", []):
                hc = capa_para(h, cfg["min_m"], cfg["max_m"], cfg["paso_m"])
                if hc is not None and hc not in [x for x, _ in sel]:
                    sel.append((hc, geoms[alturas_capas.index(hc)]))
            cu = next((c for c in curvas if c.clave == pc.get("curva")), None)
            iou_txt = f" · IoU {cal['curvas'][cu.clave]['iou']:.2f}" if cu and cu.clave in cal["curvas"] else ""
            titulo = (f"Control (δ = {delta:.2f} m){iou_txt}: modelo vs {cu.nombre if cu else 'sin curva'}\n"
                      f"Calibración {'cumple' if cal['criterio_cumplido'] else 'NO cumple'} el criterio · "
                      f"NO validado por revisión externa")
            sv_g = extra.get("sin_validar_geoms") if pc.get("sin_validar") else None
            ais = None
            if pc.get("aisladas") and sel:
                h_ais = max(x for x, _ in sel)
                ais = json.loads((tmp / C.nombre_capa(h_ais)).read_text(encoding="utf-8"))["features"][0]["properties"].get("aisladas", [])
                titulo += f"\nLomas aisladas a {h_ais:.2f} m: {len(ais)}".replace(".", ",")
            dibujar(tmp / pc.get("archivo", "control.png"), base, sel, cu, titulo, cfg["limites"], sv_g, ais)

    log.info("pesos: %s", pesos)
    if errores:
        for e in errores:
            log.error("validación: %s", e)
        raise ErrorPipeline(f"{len(errores)} errores de validación; no se publica nada (ver {tmp / 'mapa.log'})")

    log.info("validaciones OK en %.0f s; se publica en %s", time.time() - t_ini, salida)
    return calib


def main(argv=None) -> int:
    p = argparse.ArgumentParser(prog="python -m mapa", description=__doc__.splitlines()[0])
    p.add_argument("salida", type=Path)
    p.add_argument("--config", type=Path, default=AQUI / "config.json")
    p.add_argument("--cache", type=Path, default=None)
    p.add_argument("--osm-pbf", type=Path, default=None)
    p.add_argument("--generado", default=None, help="fecha ISO fija (para corridas idénticas)")
    p.add_argument("--sin-png", action="store_true")
    a = p.parse_args(argv)
    # En Windows, con la salida redirigida, stdout queda en cp1252 y no puede escribir "δ".
    for flujo in (sys.stdout, sys.stderr):
        if hasattr(flujo, "reconfigure"):
            flujo.reconfigure(encoding="utf-8", errors="replace")
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s", stream=sys.stdout)
    try:
        correr(a.salida, a.config, a.cache, a.osm_pbf, a.generado, not a.sin_png)
    except Exception as e:  # fallar fuerte y claro
        log.error("el pipeline falló: %s", e)
        raise
    return 0
