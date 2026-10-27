/// Cartografía de la pestaña Crecidas: colores, trazos y nombres del mapa.
///
/// Es la del mapa de la rama mapa-inundacion (docs/mapa/08-cartografia.md),
/// recortada a lo que queda: el fondo (río, arroyos, calles y barrios de
/// OpenStreetMap) y, encima, el borde medido de cada crecida como LÍNEA, sin
/// relleno: Dinagua midió hasta dónde llegó el agua, no cuánta hubo adentro.
///
/// Jerarquía (de lo más visible a lo menos):
///   1. Borde de la crecida: línea gruesa de color con ribete (blanco en
///      claro, casi negro en oscuro), para leerse igual sobre el terreno,
///      sobre las calles y sobre el río.
///   2. Nombres (barrios, arroyos, calles) con halo del color del terreno.
///   3. Río y arroyos en su cauce: celeste liso con orilla fina.
///   4. Calles: líneas finas de tono tierra.
///
/// Con "Ver todas", cada crecida lleva su color Y su tipo de trazo (continuo,
/// trazos, puntos…): nada se distingue solo por el color.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../tema.dart';
import 'modelos_crecidas.dart';

// ---------------------------------------------------------------------------
// Colores

class ColoresMapa {
  final bool oscuro;

  /// Fondo del mapa (tierra).
  final Color terreno;

  /// Río y espejos de agua en su cauce normal.
  final Color cauce;

  /// Orilla del cauce y línea de los arroyos.
  final Color orilla;

  /// Halo de los nombres (el color del terreno, casi opaco).
  final Color halo;
  final Color texto;
  final Color textoCalle;
  final Color textoCurso;

  /// Calles por clase: principal, avenida, de barrio.
  final List<Color> calles;

  /// Un color por crecida, en el orden del índice (de la más reciente a la
  /// más vieja). Todos dan al menos 4,5:1 contra el terreno y 3:1 contra el
  /// cauce; el ribete los separa de cualquier fondo.
  final List<Color> crecidas;

  /// Ribete de las líneas de crecida.
  final Color ribete;

  const ColoresMapa._({
    required this.oscuro,
    required this.terreno,
    required this.cauce,
    required this.orilla,
    required this.halo,
    required this.texto,
    required this.textoCalle,
    required this.textoCurso,
    required this.calles,
    required this.crecidas,
    required this.ribete,
  });

  Color calle(int clase) => calles[(clase - 1).clamp(0, 2)];

  /// Color de la crecida número [i] de la lista (se repite si hay más).
  Color crecida(int i) => crecidas[i % crecidas.length];

  static const claro = ColoresMapa._(
    oscuro: false,
    terreno: Color(0xFFF3F0E8),
    cauce: Color(0xFFBCD7EF),
    orilla: Color(0xFF3F7FBF),
    halo: Color(0xEBF3F0E8),
    texto: Color(0xFF0B2A3F),
    textoCalle: Color(0xFF33434F),
    textoCurso: Color(0xFF164A7A),
    calles: [Color(0xFF9C8F76), Color(0xFFB3A890), Color(0xFFCEC6B6)],
    crecidas: [
      Color(0xFFC0360C), // rojo teja
      Color(0xFF7B2D8E), // violeta
      Color(0xFF1E7B34), // verde
      Color(0xFF8A5300), // ocre oscuro
      Color(0xFF1F1F1F), // casi negro
    ],
    ribete: Color(0xFFFFFFFF),
  );

  static const noche = ColoresMapa._(
    oscuro: true,
    terreno: Color(0xFF1B2A37),
    cauce: Color(0xFF173F63),
    orilla: Color(0xFF5B9BD5),
    halo: Color(0xEB1B2A37),
    texto: Color(0xFFEAF2F8),
    textoCalle: Color(0xFFC9D7E2),
    textoCurso: Color(0xFF9CCBFF),
    calles: [Color(0xFF7A90A4), Color(0xFF61778B), Color(0xFF46596B)],
    crecidas: [
      Color(0xFFFF8A5C), // salmón
      Color(0xFFD9A8FF), // lila
      Color(0xFF7FD68F), // verde claro
      Color(0xFFFFCF4D), // amarillo
      Color(0xFFFFFFFF), // blanco
    ],
    ribete: Color(0xFF0E1A24),
  );

  /// La paleta del tema elegido en la app ([Colores.oscuro]).
  static ColoresMapa actuales() => Colores.oscuro ? noche : claro;
}

// ---------------------------------------------------------------------------
// Trazos

abstract final class TrazosMapa {
  static const orilla = 1.0;
  static const curso = 2.4;

  /// Calles por clase: principal, avenida, de barrio.
  static const calles = [3.2, 2.4, 1.4];
  static double calle(int clase) => calles[(clase - 1).clamp(0, 2)];

  /// Una sola crecida: línea continua de 4 px con 1,5 px de ribete a cada
  /// lado (flutter_map suma el ribete al ancho: 3 = 1,5 + 1,5).
  static const crecida = 4.0;
  static const ribeteCrecida = 3.0;

  /// "Ver todas": más finas, para que se vean las de abajo.
  static const crecidaTodas = 3.0;
  static const ribeteTodas = 2.0;

  /// Tipo de trazo de la crecida número [i] con "Ver todas" (null:
  /// continua). Largo de trazo y de hueco, en píxeles.
  static List<double>? segmentos(int i) => const [
    null,
    [14.0, 6.0],
    [4.0, 5.0],
    [16.0, 4.0, 3.0, 4.0],
    [26.0, 8.0],
  ][i % 5];
}

// ---------------------------------------------------------------------------
// Polígonos y líneas listos para flutter_map

/// Río y espejos de agua del fondo: relleno liso con orilla fina.
List<Polygon> poligonosCauce(BaseMapa base, ColoresMapa c) => [
  for (final p in base.agua)
    Polygon(
      points: p.exterior,
      holePointsList: p.huecos,
      color: c.cauce,
      borderColor: c.orilla,
      borderStrokeWidth: TrazosMapa.orilla,
    ),
];

/// Calles: de barrio abajo, principales arriba.
List<Polyline> lineasCalles(BaseMapa base, ColoresMapa c) {
  final calles = [...base.calles]..sort((a, b) => b.clase.compareTo(a.clase));
  return [
    for (final t in calles)
      for (final l in t.lineas)
        Polyline(points: l.puntos, color: c.calle(t.clase), strokeWidth: TrazosMapa.calle(t.clase)),
  ];
}

/// Arroyos. No se dibuja la línea de un curso que va por dentro del cauce
/// (la del medio del río Uruguay, por ejemplo): ahí la raya solo ensucia.
List<Polyline> lineasCursos(BaseMapa base, ColoresMapa c) => [
  for (final t in base.cursos)
    for (final l in t.lineas)
      if (!_dentroDelCauce(l.puntos, base.agua))
        Polyline(points: l.puntos, color: c.orilla, strokeWidth: TrazosMapa.curso),
];

/// Borde de la crecida número [i] (su lugar en la lista del índice). Con
/// [todas], más fino y con su tipo de trazo; si no, continuo y grueso.
List<Polyline> lineasCrecida(BordeCrecida borde, int i, ColoresMapa c, {required bool todas}) {
  final segmentos = todas ? TrazosMapa.segmentos(i) : null;
  return [
    for (final l in borde.lineas)
      Polyline(
        points: l.puntos,
        color: c.crecida(i),
        strokeWidth: todas ? TrazosMapa.crecidaTodas : TrazosMapa.crecida,
        borderColor: c.ribete,
        borderStrokeWidth: todas ? TrazosMapa.ribeteTodas : TrazosMapa.ribeteCrecida,
        strokeCap: StrokeCap.round,
        strokeJoin: StrokeJoin.round,
        pattern: segmentos == null ? const StrokePattern.solid() : StrokePattern.dashed(segments: segmentos),
      ),
  ];
}

/// Rectángulo que encierra todos los bordes (para encuadrar el mapa).
LatLngBounds? limitesDe(Iterable<BordeCrecida> bordes) {
  final puntos = [
    for (final b in bordes)
      for (final l in b.lineas) ...l.puntos,
  ];
  return puntos.isEmpty ? null : LatLngBounds.fromPoints(puntos);
}

/// true si el principio, el medio y el final de la línea caen en el cauce.
bool _dentroDelCauce(List<LatLng> puntos, List<PoligonoMapa> cauce) {
  if (puntos.isEmpty || cauce.isEmpty) return false;
  final muestras = [puntos.first, puntos[puntos.length ~/ 2], puntos.last];
  return muestras.every((m) => cauce.any((p) => _adentro(m, p.exterior) && !p.huecos.any((h) => _adentro(m, h))));
}

/// Punto en polígono (rayo hacia el este), en grados: alcanza a esta escala.
bool _adentro(LatLng q, List<LatLng> anillo) {
  var dentro = false;
  for (var i = 0, j = anillo.length - 1; i < anillo.length; j = i++) {
    final a = anillo[i], b = anillo[j];
    if ((a.latitude > q.latitude) != (b.latitude > q.latitude) &&
        q.longitude <
            (b.longitude - a.longitude) * (q.latitude - a.latitude) / (b.latitude - a.latitude) + a.longitude) {
      dentro = !dentro;
    }
  }
  return dentro;
}

// ---------------------------------------------------------------------------
// Muestras para la leyenda y la lista (36 × 22): el mismo dibujo que el mapa.

/// Río y arroyos en su cauce: relleno liso con orilla.
class MuestraCauce extends CustomPainter {
  final ColoresMapa c;
  const MuestraCauce(this.c);

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas.drawRect(r, Paint()..color = c.cauce);
    canvas.drawRect(
      r.deflate(TrazosMapa.orilla / 2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = TrazosMapa.orilla
        ..color = c.orilla,
    );
  }

  @override
  bool shouldRepaint(MuestraCauce old) => old.c != c;
}

/// Línea de la crecida número [i], sobre un pedazo de terreno.
class MuestraCrecida extends CustomPainter {
  final ColoresMapa c;
  final int i;
  final bool todas;
  const MuestraCrecida(this.c, this.i, {required this.todas});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(4)),
      Paint()..color = c.terreno,
    );
    final y = size.height / 2;
    final ancho = todas ? TrazosMapa.crecidaTodas : TrazosMapa.crecida;
    final ribete = todas ? TrazosMapa.ribeteTodas : TrazosMapa.ribeteCrecida;
    final segmentos = todas ? TrazosMapa.segmentos(i) : null;
    void trazo(Color color, double grosor) {
      final p = Paint()
        ..color = color
        ..strokeWidth = grosor
        ..strokeCap = StrokeCap.round;
      const x0 = 4.0;
      final x1 = size.width - 4;
      if (segmentos == null) {
        canvas.drawLine(Offset(x0, y), Offset(x1, y), p);
        return;
      }
      var x = x0;
      var k = 0;
      while (x < x1) {
        final largo = segmentos[k % segmentos.length];
        if (k.isEven) canvas.drawLine(Offset(x, y), Offset(math.min(x + largo, x1), y), p);
        x += largo;
        k++;
      }
    }

    trazo(c.ribete, ancho + ribete);
    trazo(c.crecida(i), ancho);
  }

  @override
  bool shouldRepaint(MuestraCrecida old) => old.c != c || old.i != i || old.todas != todas;
}

// ---------------------------------------------------------------------------
// Rótulos: nombres de barrios, arroyos y calles, sin pisarse.

/// Un nombre candidato a dibujarse.
class Rotulo {
  final String texto;

  /// 0 barrio · 1 arroyo · 2 principal · 3 avenida · 4 calle. Entra primero
  /// el de menor número; si no hay lugar, el siguiente no se dibuja.
  final int prioridad;

  /// Zoom desde el que aparece.
  final double zoomMin;
  final LatLng punto;

  /// Tramo donde va el nombre (para girarlo como la calle); null en barrios.
  final LatLng? a, b;
  final double largoM;

  const Rotulo(this.texto, this.prioridad, this.zoomMin, this.punto, this.a, this.b, this.largoM);
}

/// Estilo de letra de cada prioridad (tamaño base, antes de la letra del
/// teléfono), nunca por debajo de 12.
TextStyle estiloRotulo(int prioridad) => switch (prioridad) {
  0 => const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, letterSpacing: 0.8, height: 1.1),
  1 => const TextStyle(fontSize: 13, fontStyle: FontStyle.italic, fontWeight: FontWeight.w600, height: 1.1),
  2 => const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, height: 1.1),
  3 => const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.1),
  _ => const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, height: 1.1),
};

/// Ancho del halo (trazo alrededor de cada letra, del color del terreno).
const anchoHalo = 4.0;

/// Cada cuántos metros de calle se ofrece repetir el nombre.
const espaciadoRotulosM = 400.0;

/// Arma los candidatos a rótulo del fondo, ya ordenados por prioridad.
List<Rotulo> armarRotulos(BaseMapa base) {
  final lista = <Rotulo>[
    for (final l in base.lugares) Rotulo(nombreDeBarrio(l.nombre), 0, 12.5, l.punto, null, null, 0),
  ];
  void tramos(List<TramoConNombre> ts, int Function(int clase) prioridad, double Function(int clase) zoom) {
    for (final t in ts) {
      final nombre = t.nombre;
      if (nombre == null) continue;
      for (final l in t.lineas) {
        for (final r in _anclas(l.puntos)) {
          if (r.$4 < 60) continue; // tramos muy cortos no llevan nombre
          lista.add(Rotulo(nombre, prioridad(t.clase), zoom(t.clase), r.$1, r.$2, r.$3, r.$4));
        }
      }
    }
  }

  tramos(base.cursos, (_) => 1, (_) => 13.5);
  tramos(
    base.calles,
    (k) => k.clamp(1, 3) + 1,
    (k) => switch (k) {
      1 => 14.0,
      2 => 14.5,
      _ => 15.5,
    },
  );
  lista.sort((a, b) => a.prioridad != b.prioridad ? a.prioridad - b.prioridad : b.largoM.compareTo(a.largoM));
  return lista;
}

/// "Barrio Paysandú Sur" → "Paysandú Sur".
String nombreDeBarrio(String nombre) {
  final corto = nombre.replaceFirst(RegExp(r'^Barrio\s+', caseSensitive: false), '').trim();
  return corto.isEmpty ? nombre : corto;
}

/// Puntos de una línea donde puede ir su nombre (uno cada
/// [espaciadoRotulosM]): el punto, el tramo donde cae y los metros que le tocan.
List<(LatLng, LatLng, LatLng, double)> _anclas(List<LatLng> pts) {
  const d = Distance();
  final tramos = [for (var i = 1; i < pts.length; i++) d.as(LengthUnit.Meter, pts[i - 1], pts[i])];
  final total = tramos.fold<double>(0, (a, b) => a + b);
  if (total <= 0) return const [];
  final n = math.max(1, (total / espaciadoRotulosM).floor());
  final salida = <(LatLng, LatLng, LatLng, double)>[];
  var i = 0;
  var recorrido = 0.0;
  for (var k = 0; k < n; k++) {
    final objetivo = total * (k + 0.5) / n;
    while (i < tramos.length - 1 && recorrido + tramos[i] < objetivo) {
      recorrido += tramos[i];
      i++;
    }
    final f = tramos[i] == 0 ? 0.0 : ((objetivo - recorrido) / tramos[i]).clamp(0.0, 1.0);
    final a = pts[i], b = pts[i + 1];
    final punto = LatLng(a.latitude + (b.latitude - a.latitude) * f, a.longitude + (b.longitude - a.longitude) * f);
    salida.add((punto, a, b, total / n));
  }
  return salida;
}

/// Textos ya medidos, para no medir cientos de nombres en cada cuadro.
class CacheRotulos {
  final _textos = <(String, int, double), TextPainter>{};
  ColoresMapa? _colores;
  String? _familia;

  TextPainter texto(String t, int prioridad, double escala, ColoresMapa c, {required bool halo, String? familia}) {
    if (!identical(c, _colores) || familia != _familia) {
      for (final p in _textos.values) {
        p.dispose();
      }
      _textos.clear();
      _colores = c;
      _familia = familia;
    }
    final clave = (t, prioridad * 2 + (halo ? 1 : 0), escala);
    return _textos[clave] ??= () {
      final base = estiloRotulo(prioridad).copyWith(fontFamily: familia);
      final color = switch (prioridad) {
        0 => c.texto,
        1 => c.textoCurso,
        _ => c.textoCalle,
      };
      final estilo = halo
          ? base.copyWith(
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = anchoHalo
                ..strokeJoin = StrokeJoin.round
                ..color = c.halo,
            )
          : base.copyWith(color: color);
      return TextPainter(
        text: TextSpan(text: prioridad == 0 ? t.toUpperCase() : t, style: estilo),
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.linear(escala),
        maxLines: 1,
      )..layout();
    }();
  }

  void dispose() {
    for (final p in _textos.values) {
      p.dispose();
    }
    _textos.clear();
  }
}

/// Capa de flutter_map con los nombres.
class CapaRotulos extends StatelessWidget {
  final List<Rotulo> candidatos;
  final CacheRotulos cache;
  final ColoresMapa colores;

  /// Partes del mapa tapadas por otra cosa (botones, atribución).
  final List<Rect> Function(Size tamano)? tapadas;

  const CapaRotulos({super.key, required this.candidatos, required this.cache, required this.colores, this.tapadas});

  @override
  Widget build(BuildContext context) {
    final camara = MapCamera.of(context);
    final escala = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3).scale(1);
    final familia = Theme.of(context).textTheme.bodyMedium?.fontFamily;
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _PintorRotulos(camara, candidatos, cache, colores, escala, familia, tapadas),
      ),
    );
  }
}

class _PintorRotulos extends CustomPainter {
  final MapCamera camara;
  final List<Rotulo> candidatos;
  final CacheRotulos cache;
  final ColoresMapa c;
  final double escala;
  final String? familia;
  final List<Rect> Function(Size tamano)? tapadas;

  _PintorRotulos(this.camara, this.candidatos, this.cache, this.c, this.escala, this.familia, this.tapadas);

  static const maximo = 60;
  static const separacionMismoNombre = 260.0;
  static const aire = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final zoom = camara.zoom;
    final pantalla = Offset.zero & size;
    final reservadas = tapadas?.call(size) ?? const <Rect>[];
    final ocupados = <Rect>[];
    final porNombre = <String, List<Offset>>{};
    for (final r in candidatos) {
      if (ocupados.length >= maximo) break;
      if (zoom < r.zoomMin) continue;
      final p = camara.getOffsetFromOrigin(r.punto);
      if (!pantalla.inflate(-8).contains(p)) continue;
      final texto = cache.texto(r.texto, r.prioridad, escala, c, halo: false, familia: familia);
      final w = texto.width, h = texto.height;
      var angulo = 0.0;
      if (r.a != null && r.b != null) {
        final pa = camara.getOffsetFromOrigin(r.a!), pb = camara.getOffsetFromOrigin(r.b!);
        final largoPantalla = r.largoM / _metrosPorPixel(r.punto.latitude, zoom);
        if (largoPantalla < w * 1.1) continue;
        angulo = math.atan2(pb.dy - pa.dy, pb.dx - pa.dx);
        if (angulo > math.pi / 2) angulo -= math.pi;
        if (angulo < -math.pi / 2) angulo += math.pi;
      }
      final cos = math.cos(angulo).abs(), sin = math.sin(angulo).abs();
      final caja = Rect.fromCenter(center: p, width: w * cos + h * sin, height: w * sin + h * cos).inflate(aire);
      if (!pantalla.contains(caja.topLeft) || !pantalla.contains(caja.bottomRight)) continue;
      if (ocupados.any((o) => o.overlaps(caja)) || reservadas.any((o) => o.overlaps(caja))) continue;
      final cerca = porNombre[r.texto];
      if (cerca != null && cerca.any((q) => (q - p).distance < separacionMismoNombre)) continue;
      ocupados.add(caja);
      (porNombre[r.texto] ??= []).add(p);
      canvas.save();
      canvas.translate(p.dx, p.dy);
      canvas.rotate(angulo);
      final origen = Offset(-w / 2, -h / 2);
      cache.texto(r.texto, r.prioridad, escala, c, halo: true, familia: familia).paint(canvas, origen);
      texto.paint(canvas, origen);
      canvas.restore();
    }
  }

  static double _metrosPorPixel(double lat, double zoom) =>
      156543.03392 * math.cos(lat * math.pi / 180) / math.pow(2, zoom);

  @override
  bool shouldRepaint(_PintorRotulos old) =>
      old.camara != camara ||
      old.candidatos != candidatos ||
      old.escala != escala ||
      old.c != c ||
      old.familia != familia;
}
