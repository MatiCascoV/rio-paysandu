/// Modelos de los archivos del mapa (docs/mapa/05-contrato.md) y su validación.
///
/// Mismo espíritu que modelos.dart: lectura desconfiada. Un índice con un
/// campo raro se rechaza entero (con el motivo), y un dibujo de agua que no
/// cuadra con el índice se descarta sin romper la pantalla.
library;

import 'package:latlong2/latlong.dart';

/// Topes de tamaño. Los archivos reales pesan unos cientos de KB; un archivo
/// mucho más grande es un error (o algo que no es nuestro) y no se lee.
abstract final class TopesMapa {
  static const bytesIndice = 256 * 1024;
  static const bytesBase = 4 * 1024 * 1024;
  static const bytesCapa = 2 * 1024 * 1024;
  static const bytesCurva = 2 * 1024 * 1024;

  /// Suma de todo lo que declara el índice (base + capas + curvas).
  static const bytesTotales = 48 * 1024 * 1024;

  /// Más de esto en una sola capa es un error del pipeline.
  static const puntosPorCapa = 400000;
}

/// Escala de alturas que entiende la app: la de CARU en el puerto de Paysandú
/// (el `cero` de actual.json y umbrales.json). Un mapa hecho en otra escala no
/// se pinta: un error de cero corre el borde del agua varias cuadras.
const ceroDelMapa = 'Local';

/// Rectángulo grueso de Uruguay: un límite fuera de acá es un error.
const _latMin = -35.2, _latMax = -30.0, _lonMin = -58.7, _lonMax = -53.0;

/// Alturas del mapa, en centímetros enteros: así no hay errores de redondeo
/// al comparar 6,70 con 6,6999999.
int aCm(double metros) => (metros * 100).round();

/// Error de validación con un motivo legible (para el informe y los tests).
class ErrorMapa implements Exception {
  final String motivo;
  const ErrorMapa(this.motivo);
  @override
  String toString() => 'ErrorMapa: $motivo';
}

double? _numero(Object? v) => v is num && v.isFinite ? v.toDouble() : null;
String? _texto(Object? v) => v is String ? v : null;

/// Altura en metros: de 0 a 20, como en modelos.dart.
double _altura(Object? v, String campo) {
  final n = _numero(v);
  if (n == null || n < 0 || n > 20) throw ErrorMapa('$campo fuera de rango o ausente');
  return n;
}

final _hex64 = RegExp(r'^[0-9a-f]{64}$');

/// Ruta relativa, sin subir de carpeta ni empezar en "/": solo letras,
/// números, guiones, puntos y barras, y terminada en .json.
final _ruta = RegExp(r'^[a-z0-9_\-]+(/[a-z0-9_\-]+)*\.json$');

/// Un archivo que nombra el índice, con su tamaño y su huella.
class ArchivoMapa {
  final String archivo;
  final int bytes;
  final String sha256;

  const ArchivoMapa(this.archivo, this.bytes, this.sha256);

  static ArchivoMapa desdeJson(Object? j, String campo, int tope) {
    if (j is! Map) throw ErrorMapa('$campo no es un objeto');
    final archivo = _texto(j['archivo']);
    final bytes = j['bytes'];
    final sha = _texto(j['sha256']);
    if (archivo == null || !_ruta.hasMatch(archivo) || archivo.contains('..')) {
      throw ErrorMapa('$campo: nombre de archivo inválido');
    }
    if (bytes is! int || bytes <= 0 || bytes > tope) throw ErrorMapa('$campo: bytes fuera de rango');
    if (sha == null || !_hex64.hasMatch(sha)) throw ErrorMapa('$campo: sha256 inválido');
    return ArchivoMapa(archivo, bytes, sha);
  }
}

class CapaIndice extends ArchivoMapa {
  final int alturaCm;
  const CapaIndice(this.alturaCm, super.archivo, super.bytes, super.sha256);
}

/// Crecida real u otra altura de referencia. Se lee de forma tolerante: una
/// referencia rara se saltea y no invalida el índice. Si trae un archivo de
/// curva (curvas/AAAA-MM.json) que no valida, la referencia queda igual como
/// altura, pero sin contorno.
class ReferenciaMapa {
  final String tipo;
  final String nombre;
  final double alturaM;
  final DateTime? fecha;
  final String? fuente;

  /// Contorno medido de esa crecida (Dinagua), o null si no hay.
  final ArchivoMapa? archivo;

  const ReferenciaMapa({
    required this.tipo,
    required this.nombre,
    required this.alturaM,
    this.fecha,
    this.fuente,
    this.archivo,
  });

  int get alturaCm => aCm(alturaM);

  static ReferenciaMapa? desdeJson(Object? j) {
    if (j is! Map) return null;
    final tipo = _texto(j['tipo']), nombre = _texto(j['nombre'])?.trim();
    final altura = _numero(j['altura_m']);
    if (tipo == null || nombre == null || nombre.isEmpty || altura == null || altura < 0 || altura > 20) return null;
    final fecha = _texto(j['fecha']);
    ArchivoMapa? archivo;
    if (j['archivo'] != null) {
      try {
        final a = ArchivoMapa.desdeJson(j, 'referencia', TopesMapa.bytesCurva);
        if (a.archivo.startsWith('curvas/')) archivo = a;
      } on ErrorMapa {
        // Sin contorno: la altura de la crecida sigue sirviendo.
      }
    }
    final fuente = _texto(j['fuente']);
    return ReferenciaMapa(
      tipo: tipo,
      nombre: nombre.length > 80 ? nombre.substring(0, 80) : nombre,
      alturaM: altura,
      fecha: fecha == null ? null : DateTime.tryParse(fecha),
      fuente: fuente == null || fuente.length > 80 ? null : fuente,
      archivo: archivo,
    );
  }
}

class ModeloMapa {
  final String metodo;
  final double margenM;
  final double? deltaM;
  final double? iouValidacion;

  const ModeloMapa({required this.metodo, required this.margenM, this.deltaM, this.iouValidacion});

  /// Datos inventados para ver la pantalla antes de tener los reales.
  bool get esProvisorio => metodo.trim().toUpperCase().startsWith('PROVISORIO');
}

class IndiceMapa {
  final int version;
  final DateTime? generado;
  final String cero;
  final bool validado;
  final ModeloMapa modelo;

  /// Sur-oeste y norte-este.
  final LatLng surOeste, norEste;
  final int pasoCm, minCm, maxCm;
  final ArchivoMapa base;
  final List<CapaIndice> capas;
  final List<ReferenciaMapa> referencias;
  final List<String> fuentes;

  const IndiceMapa({
    required this.version,
    required this.generado,
    required this.cero,
    required this.validado,
    required this.modelo,
    required this.surOeste,
    required this.norEste,
    required this.pasoCm,
    required this.minCm,
    required this.maxCm,
    required this.base,
    required this.capas,
    this.referencias = const [],
    this.fuentes = const [],
  });

  int get margenCm => aCm(modelo.margenM);

  CapaIndice? capaDe(int cm) {
    if (cm < minCm || cm > maxCm || (cm - minCm) % pasoCm != 0) return null;
    return capas[(cm - minCm) ~/ pasoCm];
  }

  bool dentro(double lat, double lon, {double holgura = 0.01}) =>
      lat >= surOeste.latitude - holgura &&
      lat <= norEste.latitude + holgura &&
      lon >= surOeste.longitude - holgura &&
      lon <= norEste.longitude + holgura;

  /// Lee y valida el índice. Tira [ErrorMapa] con el motivo si algo no cuadra.
  static IndiceMapa desdeJson(Object? j) {
    if (j is! Map) throw const ErrorMapa('el índice no es un objeto');
    final version = j['version'];
    if (version is! int || version < 1) throw const ErrorMapa('version inválida');
    final cero = _texto(j['cero']);
    if (cero == null || cero.isEmpty) throw const ErrorMapa('falta cero');

    final m = j['modelo'];
    if (m is! Map) throw const ErrorMapa('falta modelo');
    final metodo = _texto(m['metodo']);
    final margen = _numero(m['margen_m']);
    if (metodo == null || metodo.isEmpty) throw const ErrorMapa('modelo sin metodo');
    if (margen == null || margen < 0 || margen > 2) throw const ErrorMapa('margen_m fuera de rango');
    final modelo = ModeloMapa(
      metodo: metodo,
      margenM: margen,
      deltaM: _numero(m['delta_m']),
      iouValidacion: _numero(m['iou_validacion']),
    );

    final lim = j['limites'];
    if (lim is! List || lim.length != 2 || lim[0] is! List || lim[1] is! List) {
      throw const ErrorMapa('limites inválidos');
    }
    final so = lim[0] as List, ne = lim[1] as List;
    if (so.length != 2 || ne.length != 2) throw const ErrorMapa('limites inválidos');
    final s = _numero(so[0]), o = _numero(so[1]), n = _numero(ne[0]), e = _numero(ne[1]);
    bool enUruguay(double? lat, double? lon) =>
        lat != null && lon != null && lat >= _latMin && lat <= _latMax && lon >= _lonMin && lon <= _lonMax;
    if (!enUruguay(s, o) || !enUruguay(n, e) || s! >= n! || o! >= e!) {
      throw const ErrorMapa('limites fuera de Uruguay o al revés');
    }

    final paso = _numero(j['paso_m']);
    if (paso == null || aCm(paso) < 1 || aCm(paso) > 100) throw const ErrorMapa('paso_m inválido');
    final pasoCm = aCm(paso);
    final minCm = aCm(_altura(j['min_m'], 'min_m'));
    final maxCm = aCm(_altura(j['max_m'], 'max_m'));
    if (minCm > maxCm) throw const ErrorMapa('min_m mayor que max_m');
    if ((maxCm - minCm) % pasoCm != 0) throw const ErrorMapa('min_m y max_m no cuadran con paso_m');

    final base = ArchivoMapa.desdeJson(j['base'], 'base', TopesMapa.bytesBase);

    final lista = j['capas'];
    if (lista is! List || lista.isEmpty) throw const ErrorMapa('sin capas');
    final esperadas = (maxCm - minCm) ~/ pasoCm + 1;
    if (lista.length != esperadas) {
      throw ErrorMapa('se esperaban $esperadas capas y hay ${lista.length}');
    }
    final capas = <CapaIndice>[];
    var total = base.bytes;
    for (var i = 0; i < lista.length; i++) {
      final c = lista[i];
      if (c is! Map) throw ErrorMapa('capa $i no es un objeto');
      final cm = aCm(_altura(c['altura_m'], 'capa $i'));
      if (cm != minCm + i * pasoCm) throw ErrorMapa('capa $i: altura fuera de orden o con hueco');
      final a = ArchivoMapa.desdeJson(c, 'capa $i', TopesMapa.bytesCapa);
      final nombre = 'agua/${cm.toString().padLeft(4, '0')}.json';
      if (a.archivo != nombre) throw ErrorMapa('capa $i: se esperaba $nombre');
      total += a.bytes;
      capas.add(CapaIndice(cm, a.archivo, a.bytes, a.sha256));
    }

    final referencias = <ReferenciaMapa>[];
    final refs = j['referencias'];
    if (refs is List) {
      for (final r in refs) {
        final ref = ReferenciaMapa.desdeJson(r);
        if (ref == null) continue;
        referencias.add(ref);
        final b = r is Map ? r['bytes'] : null;
        if (b is int && b > 0) total += b;
        if (referencias.length >= 40) break; // más que esto no entra en la pantalla
      }
    }
    if (total > TopesMapa.bytesTotales) throw const ErrorMapa('el mapa declara demasiados bytes');

    final fuentes = j['fuentes'];
    final generado = _texto(j['generado']);
    return IndiceMapa(
      version: version,
      generado: generado == null ? null : DateTime.tryParse(generado),
      cero: cero,
      validado: j['validado'] == true,
      modelo: modelo,
      surOeste: LatLng(s, o),
      norEste: LatLng(n, e),
      pasoCm: pasoCm,
      minCm: minCm,
      maxCm: maxCm,
      base: base,
      capas: capas,
      referencias: referencias..sort((a, b) => a.alturaCm.compareTo(b.alturaCm)),
      fuentes: fuentes is List
          ? [
              for (final f in fuentes.take(12))
                if (f is String && f.length <= 300) f,
            ]
          : const [],
    );
  }
}

// ---------------------------------------------------------------------------
// GeoJSON

/// Polígono con huecos (zonas altas que quedan secas dentro del agua).
class PoligonoMapa {
  final List<LatLng> exterior;
  final List<List<LatLng>> huecos;
  const PoligonoMapa(this.exterior, [this.huecos = const []]);
}

class LineaMapa {
  final List<LatLng> puntos;
  const LineaMapa(this.puntos);
}

/// Una línea con nombre (calle o arroyo). [clase]: 1 principal, 2 avenida,
/// 3 calle de barrio; 0 para los arroyos.
class TramoConNombre {
  final int clase;
  final String? nombre;
  final List<LineaMapa> lineas;
  const TramoConNombre(this.clase, this.nombre, this.lineas);
}

class LugarMapa {
  final String nombre;
  final LatLng punto;
  const LugarMapa(this.nombre, this.punto);
}

/// Fondo del mapa: río, arroyos, calles y barrios (de OpenStreetMap).
class BaseMapa {
  final List<PoligonoMapa> agua;
  final List<TramoConNombre> cursos;
  final List<TramoConNombre> calles;
  final List<LugarMapa> lugares;

  const BaseMapa({required this.agua, required this.cursos, required this.calles, required this.lugares});

  static BaseMapa desdeJson(Object? j, IndiceMapa indice) {
    if (j is! Map || j['type'] != 'FeatureCollection' || j['features'] is! List) {
      throw const ErrorMapa('base.json no es una FeatureCollection');
    }
    final agua = <PoligonoMapa>[];
    final cursos = <TramoConNombre>[];
    final calles = <TramoConNombre>[];
    for (final f in j['features'] as List) {
      if (f is! Map || f['properties'] is! Map) continue;
      final p = f['properties'] as Map;
      final g = f['geometry'];
      final nombre = _nombre(p['n']);
      try {
        switch (p['t']) {
          case 'agua':
            agua.addAll(_poligonos(g, indice));
          case 'curso':
            final l = _lineas(g, indice);
            if (l.isNotEmpty) cursos.add(TramoConNombre(0, nombre, l));
          case 'calle':
            final k = p['k'];
            final l = _lineas(g, indice);
            if (l.isNotEmpty) calles.add(TramoConNombre(k is int && k >= 1 && k <= 3 ? k : 3, nombre, l));
        }
      } on ErrorMapa {
        // Una geometría rota se saltea: el resto del fondo sigue sirviendo.
      }
    }
    final lugares = <LugarMapa>[];
    final ls = j['lugares'];
    if (ls is List) {
      for (final l in ls) {
        if (l is! Map) continue;
        final n = _nombre(l['n']);
        final c = l['c'];
        if (n == null || c is! List || c.length < 2) continue;
        final lon = _numero(c[0]), lat = _numero(c[1]);
        if (lon == null || lat == null || !indice.dentro(lat, lon)) continue;
        lugares.add(LugarMapa(n, LatLng(lat, lon)));
      }
    }
    if (agua.isEmpty && calles.isEmpty) throw const ErrorMapa('base.json no tiene ni agua ni calles');
    return BaseMapa(agua: agua, cursos: cursos, calles: calles, lugares: lugares);
  }
}

String? _nombre(Object? v) {
  final t = _texto(v)?.trim();
  if (t == null || t.isEmpty) return null;
  return t.length > 60 ? t.substring(0, 60) : t;
}

/// Agua sobre tierra a una altura: un MultiPolygon (puede estar vacío).
class CapaAgua {
  final int alturaCm;
  final List<PoligonoMapa> poligonos;
  const CapaAgua(this.alturaCm, this.poligonos);

  bool get vacia => poligonos.isEmpty;

  static CapaAgua desdeJson(Object? j, CapaIndice capa, IndiceMapa indice) {
    if (j is! Map || j['type'] != 'FeatureCollection' || j['features'] is! List) {
      throw const ErrorMapa('la capa no es una FeatureCollection');
    }
    final features = j['features'] as List;
    if (features.length != 1 || features.first is! Map) throw const ErrorMapa('la capa debe tener un solo Feature');
    final f = features.first as Map;
    final p = f['properties'];
    final altura = p is Map ? _numero(p['altura_m']) : null;
    if (altura == null || aCm(altura) != capa.alturaCm) throw const ErrorMapa('altura_m no coincide con el índice');
    final poligonos = _poligonos(f['geometry'], indice);
    if (_puntos(poligonos) > TopesMapa.puntosPorCapa) throw const ErrorMapa('la capa tiene demasiados puntos');
    return CapaAgua(capa.alturaCm, poligonos);
  }
}

int _puntos(List<PoligonoMapa> ps) =>
    ps.fold<int>(0, (s, p) => s + p.exterior.length + p.huecos.fold<int>(0, (t, h) => t + h.length));

/// Contorno medido de una crecida real (curvas/AAAA-MM.json): solo se dibuja
/// como línea de referencia, nunca en lugar de la capa del modelo.
class CurvaMapa {
  final ReferenciaMapa referencia;
  final List<PoligonoMapa> poligonos;
  const CurvaMapa(this.referencia, this.poligonos);

  static CurvaMapa desdeJson(Object? j, ReferenciaMapa ref, IndiceMapa indice) {
    if (j is! Map || j['type'] != 'FeatureCollection' || j['features'] is! List) {
      throw const ErrorMapa('la curva no es una FeatureCollection');
    }
    final features = j['features'] as List;
    if (features.isEmpty || features.length > 50) throw const ErrorMapa('la curva no tiene Features');
    final poligonos = <PoligonoMapa>[];
    for (final f in features) {
      if (f is! Map) throw const ErrorMapa('Feature inválido');
      final p = f['properties'];
      final altura = p is Map ? _numero(p['altura_m']) : null;
      if (altura != null && aCm(altura) != ref.alturaCm) throw const ErrorMapa('altura_m no coincide con el índice');
      poligonos.addAll(_poligonos(f['geometry'], indice));
    }
    if (poligonos.isEmpty) throw const ErrorMapa('la curva está vacía');
    if (_puntos(poligonos) > TopesMapa.puntosPorCapa) throw const ErrorMapa('la curva tiene demasiados puntos');
    return CurvaMapa(ref, poligonos);
  }
}

/// [lon, lat] → LatLng, solo si es un número finito dentro de los límites.
LatLng _punto(Object? c, IndiceMapa indice) {
  if (c is! List || c.length < 2) throw const ErrorMapa('coordenada inválida');
  final lon = _numero(c[0]), lat = _numero(c[1]);
  if (lon == null || lat == null || !indice.dentro(lat, lon)) throw const ErrorMapa('coordenada fuera del mapa');
  return LatLng(lat, lon);
}

List<LatLng> _anillo(Object? a, IndiceMapa indice) {
  if (a is! List) throw const ErrorMapa('anillo inválido');
  final pts = [for (final c in a) _punto(c, indice)];
  // Se tolera un anillo sin cerrar: se cierra.
  if (pts.isNotEmpty && pts.first != pts.last) pts.add(pts.first);
  if (pts.length < 4) throw const ErrorMapa('anillo con menos de 3 puntos');
  return pts;
}

PoligonoMapa _poligono(Object? coords, IndiceMapa indice) {
  if (coords is! List || coords.isEmpty) throw const ErrorMapa('polígono vacío');
  final exterior = _anillo(coords.first, indice);
  final huecos = <List<LatLng>>[];
  for (final h in coords.skip(1)) {
    try {
      huecos.add(_anillo(h, indice));
    } on ErrorMapa {
      // Un hueco roto se ignora: queda más agua, del lado de la prudencia.
    }
  }
  return PoligonoMapa(exterior, huecos);
}

List<PoligonoMapa> _poligonos(Object? g, IndiceMapa indice) {
  if (g is! Map) throw const ErrorMapa('geometría ausente');
  final coords = g['coordinates'];
  if (coords is! List) throw const ErrorMapa('geometría sin coordenadas');
  return switch (g['type']) {
    'Polygon' => coords.isEmpty ? const [] : [_poligono(coords, indice)],
    'MultiPolygon' => [for (final p in coords) _poligono(p, indice)],
    _ => throw const ErrorMapa('se esperaba Polygon o MultiPolygon'),
  };
}

List<LineaMapa> _lineas(Object? g, IndiceMapa indice) {
  if (g is! Map) throw const ErrorMapa('geometría ausente');
  final coords = g['coordinates'];
  if (coords is! List) throw const ErrorMapa('geometría sin coordenadas');
  LineaMapa linea(Object? l) {
    if (l is! List || l.length < 2) throw const ErrorMapa('línea con menos de 2 puntos');
    return LineaMapa([for (final c in l) _punto(c, indice)]);
  }

  return switch (g['type']) {
    'LineString' => [linea(coords)],
    'MultiLineString' => [for (final l in coords) linea(l)],
    _ => throw const ErrorMapa('se esperaba LineString o MultiLineString'),
  };
}
