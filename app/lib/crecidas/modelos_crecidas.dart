/// Archivos de la pestaña Crecidas (assets/crecidas/) y su validación.
///
/// Mismo espíritu que modelos.dart: lectura desconfiada. Un índice con un
/// campo raro se rechaza entero (con el motivo); una crecida rara se saltea y
/// las demás siguen sirviendo. Formato y origen de los datos:
/// docs/crecidas-anteriores.md.
library;

import 'package:latlong2/latlong.dart';

/// Topes de tamaño. Los archivos reales pesan decenas o cientos de KB; uno
/// mucho más grande es un error (o algo que no es nuestro) y no se lee.
abstract final class TopesCrecidas {
  static const bytesIndice = 64 * 1024;
  static const bytesBase = 4 * 1024 * 1024;
  static const bytesBorde = 1024 * 1024;

  /// Más crecidas que esto no entran en la pantalla.
  static const crecidas = 12;

  /// Más puntos que esto en un borde es un error.
  static const puntosPorBorde = 100000;
}

/// Única versión del formato que entiende la app.
const versionCrecidas = 1;

/// Rectángulo grueso de Uruguay: un límite fuera de acá es un error.
const _latMin = -35.2, _latMax = -30.0, _lonMin = -58.7, _lonMax = -53.0;

/// Error de validación con un motivo legible (para el informe y los tests).
class ErrorCrecidas implements Exception {
  final String motivo;
  const ErrorCrecidas(this.motivo);
  @override
  String toString() => 'ErrorCrecidas: $motivo';
}

double? _numero(Object? v) => v is num && v.isFinite ? v.toDouble() : null;
String? _texto(Object? v) => v is String ? v : null;

final _hex64 = RegExp(r'^[0-9a-f]{64}$');

/// Ruta relativa, sin subir de carpeta ni empezar en "/", terminada en .json.
final _ruta = RegExp(r'^[a-z0-9_\-]+(/[a-z0-9_\-]+)*\.json$');

final _fecha = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// Un archivo que nombra el índice, con su tamaño y su huella.
class ArchivoCrecidas {
  final String archivo;
  final int bytes;
  final String sha256;

  const ArchivoCrecidas(this.archivo, this.bytes, this.sha256);

  static ArchivoCrecidas desdeJson(Object? j, String campo, int tope) {
    if (j is! Map) throw ErrorCrecidas('$campo no es un objeto');
    final archivo = _texto(j['archivo']);
    final bytes = j['bytes'];
    final sha = _texto(j['sha256']);
    if (archivo == null || !_ruta.hasMatch(archivo) || archivo.contains('..')) {
      throw ErrorCrecidas('$campo: nombre de archivo inválido');
    }
    if (bytes is! int || bytes <= 0 || bytes > tope) throw ErrorCrecidas('$campo: bytes fuera de rango');
    if (sha == null || !_hex64.hasMatch(sha)) throw ErrorCrecidas('$campo: sha256 inválido');
    return ArchivoCrecidas(archivo, bytes, sha);
  }
}

/// Una crecida real medida por Dinagua: nombre, altura y fecha tal como las
/// da Dinagua, y el archivo con el borde hasta donde llegó el agua.
class Crecida {
  final String nombre;
  final double alturaM;
  final DateTime fecha;
  final String fuente;
  final ArchivoCrecidas archivo;

  const Crecida({
    required this.nombre,
    required this.alturaM,
    required this.fecha,
    required this.fuente,
    required this.archivo,
  });

  /// Para distinguir crecidas (el archivo es único).
  String get clave => archivo.archivo;

  /// Tolerante: una entrada rara da null y se saltea.
  static Crecida? desdeJson(Object? j) {
    if (j is! Map) return null;
    final nombre = _texto(j['nombre'])?.trim();
    final altura = _numero(j['altura_m']);
    final f = _texto(j['fecha']);
    final fuente = _texto(j['fuente'])?.trim();
    if (nombre == null || nombre.isEmpty || nombre.length > 80) return null;
    if (altura == null || altura <= 0 || altura > 20) return null;
    if (f == null || !_fecha.hasMatch(f)) return null;
    final fecha = DateTime.tryParse(f);
    if (fecha == null) return null;
    // Toda altura lleva su fuente (PROMPT_MAESTRO §9): sin fuente no se muestra.
    if (fuente == null || fuente.isEmpty || fuente.length > 40) return null;
    try {
      final a = ArchivoCrecidas.desdeJson(j, 'crecida', TopesCrecidas.bytesBorde);
      if (!a.archivo.startsWith('curvas/')) return null;
      return Crecida(nombre: nombre, alturaM: altura, fecha: DateTime(fecha.year, fecha.month, fecha.day), fuente: fuente, archivo: a);
    } on ErrorCrecidas {
      return null;
    }
  }
}

class IndiceCrecidas {
  /// Sur-oeste y norte-este.
  final LatLng surOeste, norEste;
  final ArchivoCrecidas base;

  /// De la más reciente a la más vieja.
  final List<Crecida> crecidas;
  final List<String> fuentes;

  const IndiceCrecidas({
    required this.surOeste,
    required this.norEste,
    required this.base,
    required this.crecidas,
    this.fuentes = const [],
  });

  bool dentro(double lat, double lon, {double holgura = 0.01}) =>
      lat >= surOeste.latitude - holgura &&
      lat <= norEste.latitude + holgura &&
      lon >= surOeste.longitude - holgura &&
      lon <= norEste.longitude + holgura;

  /// Lee y valida el índice. Tira [ErrorCrecidas] si algo no cuadra.
  static IndiceCrecidas desdeJson(Object? j) {
    if (j is! Map) throw const ErrorCrecidas('el índice no es un objeto');
    final version = j['version'];
    if (version is! int || version != versionCrecidas) throw const ErrorCrecidas('version inválida o desconocida');

    final lim = j['limites'];
    if (lim is! List || lim.length != 2 || lim[0] is! List || lim[1] is! List) {
      throw const ErrorCrecidas('limites inválidos');
    }
    final so = lim[0] as List, ne = lim[1] as List;
    if (so.length != 2 || ne.length != 2) throw const ErrorCrecidas('limites inválidos');
    final s = _numero(so[0]), o = _numero(so[1]), n = _numero(ne[0]), e = _numero(ne[1]);
    bool enUruguay(double? lat, double? lon) =>
        lat != null && lon != null && lat >= _latMin && lat <= _latMax && lon >= _lonMin && lon <= _lonMax;
    if (!enUruguay(s, o) || !enUruguay(n, e) || s! >= n! || o! >= e!) {
      throw const ErrorCrecidas('limites fuera de Uruguay o al revés');
    }

    final base = ArchivoCrecidas.desdeJson(j['base'], 'base', TopesCrecidas.bytesBase);

    final lista = j['crecidas'];
    if (lista is! List) throw const ErrorCrecidas('falta la lista de crecidas');
    final crecidas = <Crecida>[];
    for (final c in lista) {
      final crecida = Crecida.desdeJson(c);
      if (crecida == null || crecidas.any((x) => x.clave == crecida.clave)) continue;
      crecidas.add(crecida);
      if (crecidas.length >= TopesCrecidas.crecidas) break;
    }
    if (crecidas.isEmpty) throw const ErrorCrecidas('no hay ninguna crecida legible');
    crecidas.sort((a, b) => b.fecha.compareTo(a.fecha));

    final fuentes = j['fuentes'];
    return IndiceCrecidas(
      surOeste: LatLng(s, o),
      norEste: LatLng(n, e),
      base: base,
      crecidas: crecidas,
      fuentes: fuentes is List
          ? [
              for (final f in fuentes.take(8))
                if (f is String && f.length <= 300) f,
            ]
          : const [],
    );
  }
}

// ---------------------------------------------------------------------------
// GeoJSON

/// Polígono con huecos (el río y los espejos de agua del fondo).
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

  static BaseMapa desdeJson(Object? j, IndiceCrecidas indice) {
    if (j is! Map || j['type'] != 'FeatureCollection' || j['features'] is! List) {
      throw const ErrorCrecidas('base.json no es una FeatureCollection');
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
      } on ErrorCrecidas {
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
    if (agua.isEmpty && calles.isEmpty) throw const ErrorCrecidas('base.json no tiene ni agua ni calles');
    return BaseMapa(agua: agua, cursos: cursos, calles: calles, lugares: lugares);
  }
}

String? _nombre(Object? v) {
  final t = _texto(v)?.trim();
  if (t == null || t.isEmpty) return null;
  return t.length > 60 ? t.substring(0, 60) : t;
}

/// Borde medido de una crecida (curvas/AAAA-MM.json): solo líneas. Es hasta
/// dónde llegó el agua según Dinagua, sin los tramos rectos con que Dinagua
/// cierra la zona relevada sobre el río (docs/crecidas-anteriores.md).
class BordeCrecida {
  final Crecida crecida;
  final List<LineaMapa> lineas;
  const BordeCrecida(this.crecida, this.lineas);

  static BordeCrecida desdeJson(Object? j, Crecida crecida, IndiceCrecidas indice) {
    if (j is! Map || j['type'] != 'FeatureCollection' || j['features'] is! List) {
      throw const ErrorCrecidas('el borde no es una FeatureCollection');
    }
    final features = j['features'] as List;
    if (features.isEmpty || features.length > 50) throw const ErrorCrecidas('el borde no tiene Features');
    final lineas = <LineaMapa>[];
    for (final f in features) {
      if (f is! Map) throw const ErrorCrecidas('Feature inválido');
      final p = f['properties'];
      final altura = p is Map ? _numero(p['altura_m']) : null;
      // La altura del archivo tiene que ser la del índice: si no, el borde
      // sería de otra crecida.
      if (altura == null || (altura - crecida.alturaM).abs() > 0.005) {
        throw const ErrorCrecidas('altura_m no coincide con el índice');
      }
      lineas.addAll(_lineas(f['geometry'], indice));
    }
    if (lineas.isEmpty) throw const ErrorCrecidas('el borde está vacío');
    final puntos = lineas.fold<int>(0, (s, l) => s + l.puntos.length);
    if (puntos > TopesCrecidas.puntosPorBorde) throw const ErrorCrecidas('el borde tiene demasiados puntos');
    return BordeCrecida(crecida, lineas);
  }
}

/// [lon, lat] → LatLng, solo si es un número finito dentro de los límites.
LatLng _punto(Object? c, IndiceCrecidas indice) {
  if (c is! List || c.length < 2) throw const ErrorCrecidas('coordenada inválida');
  final lon = _numero(c[0]), lat = _numero(c[1]);
  if (lon == null || lat == null || !indice.dentro(lat, lon)) throw const ErrorCrecidas('coordenada fuera del mapa');
  return LatLng(lat, lon);
}

List<LatLng> _anillo(Object? a, IndiceCrecidas indice) {
  if (a is! List) throw const ErrorCrecidas('anillo inválido');
  final pts = [for (final c in a) _punto(c, indice)];
  if (pts.isNotEmpty && pts.first != pts.last) pts.add(pts.first);
  if (pts.length < 4) throw const ErrorCrecidas('anillo con menos de 3 puntos');
  return pts;
}

PoligonoMapa _poligono(Object? coords, IndiceCrecidas indice) {
  if (coords is! List || coords.isEmpty) throw const ErrorCrecidas('polígono vacío');
  final exterior = _anillo(coords.first, indice);
  final huecos = <List<LatLng>>[];
  for (final h in coords.skip(1)) {
    try {
      huecos.add(_anillo(h, indice));
    } on ErrorCrecidas {
      // Un hueco roto se ignora.
    }
  }
  return PoligonoMapa(exterior, huecos);
}

List<PoligonoMapa> _poligonos(Object? g, IndiceCrecidas indice) {
  if (g is! Map) throw const ErrorCrecidas('geometría ausente');
  final coords = g['coordinates'];
  if (coords is! List) throw const ErrorCrecidas('geometría sin coordenadas');
  return switch (g['type']) {
    'Polygon' => coords.isEmpty ? const [] : [_poligono(coords, indice)],
    'MultiPolygon' => [for (final p in coords) _poligono(p, indice)],
    _ => throw const ErrorCrecidas('se esperaba Polygon o MultiPolygon'),
  };
}

List<LineaMapa> _lineas(Object? g, IndiceCrecidas indice) {
  if (g is! Map) throw const ErrorCrecidas('geometría ausente');
  final coords = g['coordinates'];
  if (coords is! List) throw const ErrorCrecidas('geometría sin coordenadas');
  LineaMapa linea(Object? l) {
    if (l is! List || l.length < 2) throw const ErrorCrecidas('línea con menos de 2 puntos');
    return LineaMapa([for (final c in l) _punto(c, indice)]);
  }

  return switch (g['type']) {
    'LineString' => [linea(coords)],
    'MultiLineString' => [for (final l in coords) linea(l)],
    _ => throw const ErrorCrecidas('se esperaba LineString o MultiLineString'),
  };
}
