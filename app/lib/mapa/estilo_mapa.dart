/// Cartografía de la pestaña Mapa: colores, trazos, rayado del agua y rótulos.
///
/// Todo lo que decide cómo se ve el mapa vive acá; la pantalla
/// (pantallas/mapa.dart) solo arma las capas con estas piezas. Las razones de
/// cada color y los contrastes calculados están en docs/mapa/08-cartografia.md.
///
/// Jerarquía (de lo más visible a lo menos):
///   1. Lomas que quedarían rodeadas de agua: rombo de aviso (v1.1).
///   2. Borde del agua con el río de hoy (solo al simular): línea gruesa con
///      ribete claro (v1.1).
///   3. Agua a la altura elegida: azul fuerte + rayado a 45° + borde continuo.
///   4. Margen "puede llegar un poco más": azul pálido, sin rayado, borde de puntos.
///   5. Zona baja de la costa (capa de `min_m`, siempre): celeste con rayas
///      horizontales y borde fino; es agua, pero la del río normal (v1.1).
///   6. Zona sin validar: borde de trazo y punto violeta con ribete + rótulo,
///      sin relleno: no tapa el agua (v1.1).
///   7. Borde medido de una crecida real (opcional): trazos marrones / arena.
///   8. Nombres (barrios, arroyos, calles) con halo del color del terreno.
///   9. Río y arroyos en su cauce: celeste liso con orilla fina.
///  10. Calles: líneas finas de tono tierra, más gruesas cuanto más importantes.
///
/// El agua es siempre azul (el nivel del río se dice con palabra e ícono fuera
/// del mapa) y nada se distingue solo por el color: rayado / liso, borde
/// continuo / de puntos / de trazos.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../tema.dart';
import 'modelos_mapa.dart';

// ---------------------------------------------------------------------------
// Colores

/// Paleta del mapa, clara y oscura. Ver la tabla de contrastes en
/// docs/mapa/08-cartografia.md (todo trazo que hay que ver da ≥ 3:1 contra el
/// terreno y los textos ≥ 4,5:1 contra su halo).
class ColoresMapa {
  final bool oscuro;

  /// Fondo del mapa (tierra).
  final Color terreno;

  /// Río y espejos de agua en su cauce normal (relleno liso).
  final Color cauce;

  /// Orilla del cauce y línea de los arroyos (lleva el contraste del cauce).
  final Color orilla;

  /// Relleno del agua a la altura elegida (translúcido: deja ver las calles).
  final Color agua;

  /// Líneas del rayado a 45° del agua.
  final Color rayado;

  /// Borde continuo del agua.
  final Color bordeAgua;

  /// Relleno del margen "puede llegar un poco más" (más pálido que [agua]).
  final Color margen;

  /// Borde de puntos del margen.
  final Color bordeMargen;

  /// Trazos del borde medido en una crecida real.
  final Color contorno;

  /// Halo de los nombres (el color del terreno, casi opaco).
  final Color halo;

  /// Nombres de barrios.
  final Color texto;

  /// Nombres de calles.
  final Color textoCalle;

  /// Nombres de arroyos (en itálica, como el agua en los mapas de papel).
  final Color textoCurso;

  /// Calles por clase: principal, avenida, de barrio.
  final List<Color> calles;

  /// Zona baja de la costa (v1.1): relleno casi opaco (no cambia de aspecto
  /// con el agua que tenga debajo), rayas horizontales y borde fino.
  final Color zonaBaja;
  final Color rayasZonaBaja;
  final Color bordeZonaBaja;

  /// Zona sin validar (v1.1): borde de trazo y punto y su rótulo.
  final Color sinValidar;

  /// Ribete de las líneas que van sobre el agua (zona sin validar, puntos del
  /// margen encima): el terreno, opaco.
  final Color ribete;

  /// Borde del agua con el río de hoy (v1.1) y su ribete.
  final Color hoy;
  final Color ribeteHoy;

  const ColoresMapa._({
    required this.oscuro,
    required this.terreno,
    required this.cauce,
    required this.orilla,
    required this.agua,
    required this.rayado,
    required this.bordeAgua,
    required this.margen,
    required this.bordeMargen,
    required this.contorno,
    required this.halo,
    required this.texto,
    required this.textoCalle,
    required this.textoCurso,
    required this.calles,
    required this.zonaBaja,
    required this.rayasZonaBaja,
    required this.bordeZonaBaja,
    required this.sinValidar,
    required this.ribete,
    required this.hoy,
    required this.ribeteHoy,
  });

  /// Color de una calle de clase [clase] (1 principal, 2 avenida, 3 barrio).
  Color calle(int clase) => calles[(clase - 1).clamp(0, 2)];

  static const claro = ColoresMapa._(
    oscuro: false,
    terreno: Color(0xFFF3F0E8),
    cauce: Color(0xFFBCD7EF),
    orilla: Color(0xFF3F7FBF),
    agua: Color(0x801F6FC0), // 50 %
    rayado: Color(0xB30B3C5D), // 70 %
    bordeAgua: Color(0xFF0B3C5D),
    margen: Color(0x421F6FC0), // 26 %
    bordeMargen: Color(0xFF0B3C5D),
    contorno: Color(0xFF5E2F00),
    halo: Color(0xEBF3F0E8),
    texto: Color(0xFF0B2A3F),
    textoCalle: Color(0xFF33434F),
    textoCurso: Color(0xFF164A7A),
    calles: [Color(0xFF9C8F76), Color(0xFFB3A890), Color(0xFFCEC6B6)],
    zonaBaja: Color(0xEBA9CBEA), // 92 %
    rayasZonaBaja: Color(0xFF2F6CA6),
    bordeZonaBaja: Color(0xFF1F5F99),
    sinValidar: Color(0xFF5B2A86),
    ribete: Color(0xFFF3F0E8),
    hoy: Color(0xFF0B2A3F),
    ribeteHoy: Color(0xFFFFFFFF),
  );

  static const noche = ColoresMapa._(
    oscuro: true,
    terreno: Color(0xFF1B2A37),
    cauce: Color(0xFF173F63),
    orilla: Color(0xFF5B9BD5),
    agua: Color(0x736CB4FF), // 45 %
    rayado: Color(0xC7E3F4FF), // 78 %
    bordeAgua: Color(0xFFE3F1FF),
    margen: Color(0x3D6CB4FF), // 24 %
    bordeMargen: Color(0xFFBFE0FF),
    contorno: Color(0xFFFFD89E),
    halo: Color(0xEB1B2A37),
    texto: Color(0xFFEAF2F8),
    textoCalle: Color(0xFFC9D7E2),
    textoCurso: Color(0xFF9CCBFF),
    calles: [Color(0xFF7A90A4), Color(0xFF61778B), Color(0xFF46596B)],
    zonaBaja: Color(0xEB1E4E7A), // 92 %
    rayasZonaBaja: Color(0xFF6FA8DC),
    bordeZonaBaja: Color(0xFF8CC2F0),
    sinValidar: Color(0xFFD9B8FF),
    ribete: Color(0xFF1B2A37),
    hoy: Color(0xFFFFFFFF),
    ribeteHoy: Color(0xFF0E1A24),
  );

  /// La paleta del tema elegido en la app ([Colores.oscuro]).
  static ColoresMapa actuales() => Colores.oscuro ? noche : claro;
}

// ---------------------------------------------------------------------------
// Trazos

/// Anchos (en píxeles lógicos, iguales en todo zoom) y patrones de línea.
abstract final class TrazosMapa {
  static const orilla = 1.0;
  static const curso = 2.4;

  /// Calles por clase: principal, avenida, de barrio.
  static const calles = [3.2, 2.4, 1.4];
  static double calle(int clase) => calles[(clase - 1).clamp(0, 2)];

  static const bordeAgua = 2.0;
  static const bordeMargen = 2.4;
  static const patronMargen = StrokePattern.dotted(spacingFactor: 2.0);
  static const contorno = 2.2;
  static final patronContorno = StrokePattern.dashed(segments: const [9, 6]);

  /// Rayado del agua: una línea de [grosorRayado] cada [periodoRayado] px.
  static const periodoRayado = 7.0;
  static const grosorRayado = 1.4;

  /// Zona baja (v1.1): rayas horizontales de 1,3 px cada 5 px y borde de 1,5.
  static const periodoZonaBaja = 5.0;
  static const grosorZonaBaja = 1.3;
  static const bordeZonaBaja = 1.5;

  /// Zona sin validar (v1.1): trazo y punto de 2,5 px con 1,5 px de ribete
  /// a cada lado (flutter_map suma el ribete al ancho: 3 = 1,5 + 1,5).
  static const sinValidar = 2.5;
  static const ribeteSinValidar = 3.0;
  static final patronSinValidar = StrokePattern.dashed(segments: const [14, 5, 3, 5]);

  /// Borde con el río de hoy (v1.1): 3,5 px con 2 px de ribete a cada lado.
  static const hoy = 3.5;
  static const ribeteHoy = 4.0;

  /// Puntos del margen dibujados encima de otra capa (v1.1, cuando el margen
  /// coincide con el agua o con la zona baja): ribete de 1 px a cada lado.
  static const ribeteMargen = 2.0;

  /// Marca de loma aislada (v1.1): rombo de [rombo] px dentro de un área
  /// tocable de [toque] px.
  static const rombo = 26.0;
  static const toque = 48.0;
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

/// Agua a la altura elegida ([margen] false) o el margen "puede llegar un
/// poco más" ([margen] true). El rayado del agua va aparte, en [CapaRayado].
List<Polygon> poligonosAgua(List<PoligonoMapa> poligonos, ColoresMapa c, {required bool margen}) => [
  for (final p in poligonos)
    Polygon(
      points: p.exterior,
      holePointsList: p.huecos,
      color: margen ? c.margen : c.agua,
      borderColor: margen ? c.bordeMargen : c.bordeAgua,
      borderStrokeWidth: margen ? TrazosMapa.bordeMargen : TrazosMapa.bordeAgua,
      pattern: margen ? TrazosMapa.patronMargen : const StrokePattern.solid(),
    ),
];

/// Borde medido de una crecida real: solo trazos, sin relleno (no tapa el
/// agua del modelo).
List<Polygon> poligonosContorno(List<PoligonoMapa> poligonos, ColoresMapa c) => [
  for (final p in poligonos)
    Polygon(
      points: p.exterior,
      holePointsList: p.huecos,
      color: const Color(0x00000000),
      borderColor: c.contorno,
      borderStrokeWidth: TrazosMapa.contorno,
      pattern: TrazosMapa.patronContorno,
    ),
];

// ----- v1.1 -----

/// Los anillos (exterior y huecos) de [poligonos] como líneas cerradas.
Iterable<List<LatLng>> _anillos(List<PoligonoMapa> poligonos) sync* {
  for (final p in poligonos) {
    if (p.exterior.length >= 2) yield p.exterior;
    for (final h in p.huecos) {
      if (h.length >= 2) yield h;
    }
  }
}

/// Zona sin validar (v1.1): solo el borde, trazo y punto con ribete del color
/// del terreno, para leerse sobre el agua rayada sin taparla. Sin relleno: el
/// agua de adentro se sigue viendo igual. Su nombre lo pone [CapaRotuloZona].
List<Polyline> lineasSinValidar(List<PoligonoMapa> poligonos, ColoresMapa c) => [
  for (final a in _anillos(poligonos))
    Polyline(
      points: a,
      color: c.sinValidar,
      strokeWidth: TrazosMapa.sinValidar,
      borderColor: c.ribete,
      borderStrokeWidth: TrazosMapa.ribeteSinValidar,
      pattern: TrazosMapa.patronSinValidar,
    ),
];

/// Borde del agua con el río de hoy (v1.1), solo al simular otra altura:
/// línea gruesa continua con ribete claro (oscuro en modo noche), para que
/// se vea igual sobre el agua rayada que sobre el terreno.
List<Polyline> lineasHoy(List<PoligonoMapa> poligonos, ColoresMapa c) => [
  for (final a in _anillos(poligonos))
    Polyline(
      points: a,
      color: c.hoy,
      strokeWidth: TrazosMapa.hoy,
      borderColor: c.ribeteHoy,
      borderStrokeWidth: TrazosMapa.ribeteHoy,
    ),
];

/// Los puntos del margen, dibujados ENCIMA de otra capa (v1.1 §4: el margen
/// se ve siempre). Hace falta cuando la capa del margen es la misma que otra
/// que va arriba: el agua en el máximo o por encima (el borde del agua pasa a
/// verse de puntos: "puede llegar más lejos") o la zona baja con el río por
/// debajo del mínimo. Llevan ribete para cortar la línea continua de abajo.
List<Polyline> lineasMargenEncima(List<PoligonoMapa> poligonos, ColoresMapa c) => [
  for (final a in _anillos(poligonos))
    Polyline(
      points: a,
      color: c.bordeMargen,
      strokeWidth: TrazosMapa.bordeMargen,
      borderColor: c.ribete,
      borderStrokeWidth: TrazosMapa.ribeteMargen,
      pattern: TrazosMapa.patronMargen,
    ),
];

/// Lomas que quedarían rodeadas de agua (v1.1 §2): un rombo de aviso por
/// punto. Con [alTocar], cada marca es tocable en [TrazosMapa.toque] × toque
/// (48 dp) y avisa el índice del punto; sin él, no atrapa toques.
List<Marker> marcadoresAisladas(List<LatLng> puntos, ColoresMapa c, {ValueChanged<int>? alTocar}) => [
  for (var i = 0; i < puntos.length; i++)
    Marker(
      point: puntos[i],
      width: TrazosMapa.toque,
      height: TrazosMapa.toque,
      child: alTocar == null
          ? IgnorePointer(child: CustomPaint(painter: MarcaAislada(c)))
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => alTocar(i),
              child: CustomPaint(painter: MarcaAislada(c)),
            ),
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

/// Arroyos: del color de la orilla del río (la leyenda los junta con el cauce).
/// No se dibuja la línea de un curso que va por dentro del cauce (la del
/// medio del río Uruguay, por ejemplo): ahí el agua ya está pintada y la raya
/// solo ensucia. Su nombre sigue saliendo.
List<Polyline> lineasCursos(BaseMapa base, ColoresMapa c) => [
  for (final t in base.cursos)
    for (final l in t.lineas)
      if (!_dentroDelCauce(l.puntos, base.agua))
        Polyline(points: l.puntos, color: c.orilla, strokeWidth: TrazosMapa.curso),
];

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
// Rayado del agua

/// Pintura de rayado a 45° ("/") con [periodo] y [grosor] en las unidades del
/// lienzo. Es un degradé que se repite (lo pinta la placa de video, sin
/// imagen ni líneas sueltas), con medio píxel de borde suave.
///
/// Con [horizontal], rayas horizontales (la zona baja). Con [fondo], el
/// espacio entre rayas va de ese color en vez de transparente: relleno y
/// rayas en un solo dibujo.
Paint pinturaRayado(
  Color color, {
  double periodo = TrazosMapa.periodoRayado,
  double grosor = TrazosMapa.grosorRayado,
  bool horizontal = false,
  Color? fondo,
}) {
  // Dirección perpendicular a las líneas.
  final d = horizontal ? Offset(0, periodo) : Offset(periodo, periodo) / math.sqrt2;
  final nucleo = ((grosor - 0.5) / periodo).clamp(0.01, 0.45);
  final borde = (0.5 / periodo).clamp(0.0, 0.2);
  final entre = fondo ?? color.withValues(alpha: 0);
  return Paint()
    ..isAntiAlias = true
    ..shader = ui.Gradient.linear(
      Offset.zero,
      d,
      [color, color, entre, entre, color],
      [0, nucleo / 2, nucleo / 2 + borde, 1 - nucleo / 2 - borde, 1 - nucleo / 2],
      TileMode.repeated,
    );
}

/// Contorno del agua proyectado UNA vez (Web Mercator a zoom [zoomBase],
/// relativo a [origen] para que los números sean chicos y no pierdan
/// precisión). Cada cuadro solo se escala y se corre: no se vuelve a
/// proyectar punto por punto.
class TrazadoAgua {
  static const zoomBase = 16.0;
  final ui.Path camino;
  final Offset origen;

  /// true si no hay ningún anillo que pintar (capa vacía).
  final bool vacio;

  TrazadoAgua._(this.camino, this.origen, this.vacio);

  /// Todo menos este contorno (para que el rayado del agua no entre en la
  /// zona baja). Se arma una sola vez: un rectángulo enorme más los anillos,
  /// con relleno par-impar.
  late final ui.Path complemento = ui.Path()
    ..fillType = PathFillType.evenOdd
    ..addRect(camino.getBounds().inflate(1e6))
    ..addPath(camino, Offset.zero);

  factory TrazadoAgua(List<PoligonoMapa> poligonos, {Crs crs = const Epsg3857()}) {
    final camino = ui.Path()..fillType = PathFillType.evenOdd;
    Offset? origen;
    void anillo(List<LatLng> puntos) {
      if (puntos.length < 3) return;
      final o = origen ??= crs.latLngToOffset(puntos.first, zoomBase);
      final pts = [for (final p in puntos) crs.latLngToOffset(p, zoomBase) - o];
      camino.addPolygon(pts, true);
    }

    for (final p in poligonos) {
      anillo(p.exterior);
      p.huecos.forEach(anillo);
    }
    return TrazadoAgua._(camino, origen ?? Offset.zero, origen == null);
  }
}

/// Capa de flutter_map que pinta el rayado dentro del agua.
///
/// Por qué así y no con líneas de rayado generadas como polilíneas: cortar
/// cientos de líneas contra polígonos con huecos cuesta en cada cambio de
/// altura, multiplica los objetos que flutter_map proyecta en cada cuadro y el
/// rayado cambiaría de separación con el zoom. Acá hay un solo `drawPath` con
/// un degradé repetido: el costo por cuadro es fijo (no depende de cuántas
/// líneas se vean) y el contorno se proyecta una sola vez por capa.
///
/// Con [excluir] (la zona baja, v1.1) el rayado no entra ahí: el rayado es
/// para el agua que se agrega por encima del río normal.
class CapaRayado extends StatelessWidget {
  final TrazadoAgua trazado;
  final Color color;
  final TrazadoAgua? excluir;

  const CapaRayado({super.key, required this.trazado, required this.color, this.excluir});

  @override
  Widget build(BuildContext context) {
    final camara = MapCamera.of(context);
    return MobileLayerTransformer(
      child: IgnorePointer(
        child: CustomPaint(size: Size.infinite, painter: _PintorRayado(camara, trazado, color, excluir)),
      ),
    );
  }
}

/// Escala y corrimiento para dibujar un [TrazadoAgua] con la cámara actual.
(double, Offset) _ubicar(MapCamera camara, TrazadoAgua t) {
  final crs = camara.crs;
  final s = crs.scale(camara.zoom) / crs.scale(TrazadoAgua.zoomBase);
  return (s, t.origen * s - camara.pixelOrigin);
}

class _PintorRayado extends CustomPainter {
  final MapCamera camara;
  final TrazadoAgua trazado;
  final Color color;
  final TrazadoAgua? excluir;

  _PintorRayado(this.camara, this.trazado, this.color, this.excluir);

  @override
  void paint(Canvas canvas, Size size) {
    if (trazado.vacio) return;
    final (s, corrimiento) = _ubicar(camara, trazado);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final fuera = excluir;
    if (fuera != null && !fuera.vacio) {
      // Recorte "todo menos la zona baja", en las coordenadas de ese trazado;
      // después se vuelve a la pantalla. Sin suavizado: el borde de la zona
      // baja, que va encima, tapa la costura.
      final (_, c2) = _ubicar(camara, fuera);
      canvas.translate(c2.dx, c2.dy);
      canvas.scale(s);
      canvas.clipPath(fuera.complemento, doAntiAlias: false);
      canvas.scale(1 / s);
      canvas.translate(-c2.dx, -c2.dy);
    }
    canvas.translate(corrimiento.dx, corrimiento.dy);
    canvas.scale(s);
    // El rayado se define en las coordenadas del mapa (queda pegado al
    // terreno al arrastrar) pero con separación fija en pantalla.
    canvas.drawPath(
      trazado.camino,
      pinturaRayado(color, periodo: TrazosMapa.periodoRayado / s, grosor: TrazosMapa.grosorRayado / s),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PintorRayado old) =>
      old.camara != camara || old.trazado != trazado || old.color != color || old.excluir != excluir;
}

/// Zona baja de la costa (v1.1 §3): la capa de `min_m`, dibujada SIEMPRE y
/// encima del agua y del margen, con su propio estilo: relleno celeste casi
/// opaco con rayas horizontales (relleno y rayas en un solo dibujo) y borde
/// fino. Así se ve igual con cualquier altura (sin salto al pasar por 4,00 m)
/// y nunca como tierra seca. Mismo costo que el rayado: el contorno se
/// proyecta una vez y cada cuadro son dos `drawPath`.
class CapaZonaBaja extends StatelessWidget {
  final TrazadoAgua trazado;
  final ColoresMapa colores;

  const CapaZonaBaja({super.key, required this.trazado, required this.colores});

  @override
  Widget build(BuildContext context) {
    final camara = MapCamera.of(context);
    return MobileLayerTransformer(
      child: IgnorePointer(
        child: CustomPaint(size: Size.infinite, painter: _PintorZonaBaja(camara, trazado, colores)),
      ),
    );
  }
}

class _PintorZonaBaja extends CustomPainter {
  final MapCamera camara;
  final TrazadoAgua trazado;
  final ColoresMapa c;

  _PintorZonaBaja(this.camara, this.trazado, this.c);

  @override
  void paint(Canvas canvas, Size size) {
    if (trazado.vacio) return;
    final (s, corrimiento) = _ubicar(camara, trazado);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(corrimiento.dx, corrimiento.dy);
    canvas.scale(s);
    canvas.drawPath(
      trazado.camino,
      pinturaRayado(
        c.rayasZonaBaja,
        periodo: TrazosMapa.periodoZonaBaja / s,
        grosor: TrazosMapa.grosorZonaBaja / s,
        horizontal: true,
        fondo: c.zonaBaja,
      ),
    );
    canvas.drawPath(
      trazado.camino,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = TrazosMapa.bordeZonaBaja / s
        ..strokeJoin = StrokeJoin.round
        ..color = c.bordeZonaBaja,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PintorZonaBaja old) => old.camara != camara || old.trazado != trazado || old.c != c;
}

/// Rótulo de una zona (v1.1: "Zona sin validar"), con halo, dentro de sus
/// polígonos. Se ofrecen puntos interiores repartidos cada ~250 m y se pinta
/// UNO: el más cercano al centro de la vista que entre entero en pantalla y
/// no caiga debajo de los botones. Así hay un nombre a la vista mientras se
/// vea un pedazo de la zona.
class CapaRotuloZona extends StatelessWidget {
  /// Puntos candidatos, de [anclasDe] (calcularlos una vez, no en build).
  final List<LatLng> anclas;
  final String texto;
  final ColoresMapa colores;
  final List<Rect> Function(Size tamano)? tapadas;

  const CapaRotuloZona({super.key, required this.anclas, required this.texto, required this.colores, this.tapadas});

  /// Puntos interiores de [poligonos] en una grilla de ~[pasoM] m (y el
  /// centro de cada polígono si cae adentro).
  static List<LatLng> anclasDe(List<PoligonoMapa> poligonos, {double pasoM = 250}) {
    final salida = <LatLng>[];
    for (final p in poligonos) {
      if (p.exterior.length < 4) continue;
      var s = 90.0, n = -90.0, o = 180.0, e = -180.0;
      for (final q in p.exterior) {
        s = math.min(s, q.latitude);
        n = math.max(n, q.latitude);
        o = math.min(o, q.longitude);
        e = math.max(e, q.longitude);
      }
      bool dentro(LatLng q) => _adentro(q, p.exterior) && !p.huecos.any((h) => _adentro(q, h));
      final centro = LatLng((s + n) / 2, (o + e) / 2);
      if (dentro(centro)) salida.add(centro);
      final dLat = pasoM / 111320, dLon = pasoM / (111320 * math.cos(centro.latitude * math.pi / 180));
      for (var lat = s + dLat / 2; lat < n; lat += dLat) {
        for (var lon = o + dLon / 2; lon < e; lon += dLon) {
          final q = LatLng(lat, lon);
          if (dentro(q)) salida.add(q);
          if (salida.length > 4000) return salida; // tope de memoria y tiempo
        }
      }
    }
    return salida;
  }

  @override
  Widget build(BuildContext context) {
    final camara = MapCamera.of(context);
    final escala = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3).scale(1);
    final familia = Theme.of(context).textTheme.bodyMedium?.fontFamily;
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _PintorRotuloZona(camara, anclas, texto, colores, escala, familia, tapadas),
      ),
    );
  }
}

class _PintorRotuloZona extends CustomPainter {
  final MapCamera camara;
  final List<LatLng> anclas;
  final String texto;
  final ColoresMapa c;
  final double escala;
  final String? familia;
  final List<Rect> Function(Size tamano)? tapadas;

  _PintorRotuloZona(this.camara, this.anclas, this.texto, this.c, this.escala, this.familia, this.tapadas);

  static const _estilo = TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.6, height: 1.1);

  @override
  void paint(Canvas canvas, Size size) {
    if (anclas.isEmpty) return;
    TextPainter armar(TextStyle estilo) => TextPainter(
      text: TextSpan(
        text: texto.toUpperCase(),
        style: _estilo.copyWith(fontFamily: familia).merge(estilo),
      ),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.linear(escala),
      maxLines: 1,
    )..layout();
    final frente = armar(TextStyle(color: c.sinValidar));
    final w = frente.width, h = frente.height;
    final pantalla = (Offset.zero & size).deflate(4);
    final reservadas = tapadas?.call(size) ?? const <Rect>[];
    final centro = size.center(Offset.zero);
    Offset? mejor;
    var distancia = double.infinity;
    for (final a in anclas) {
      final p = camara.getOffsetFromOrigin(a);
      final caja = Rect.fromCenter(center: p, width: w + 8, height: h + 4);
      if (!pantalla.contains(caja.topLeft) || !pantalla.contains(caja.bottomRight)) continue;
      if (reservadas.any((r) => r.overlaps(caja))) continue;
      final d = (p - centro).distanceSquared;
      if (d < distancia) {
        distancia = d;
        mejor = p;
      }
    }
    if (mejor == null) {
      frente.dispose();
      return;
    }
    final halo = armar(
      TextStyle(
        foreground: Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = anchoHalo
          ..strokeJoin = StrokeJoin.round
          ..color = c.ribete,
      ),
    );
    final origen = mejor - Offset(w / 2, h / 2);
    halo.paint(canvas, origen);
    frente.paint(canvas, origen);
    halo.dispose();
    frente.dispose();
  }

  @override
  bool shouldRepaint(_PintorRotuloZona old) =>
      old.camara != camara || old.anclas != anclas || old.texto != texto || old.c != c || old.escala != escala;
}

// ---------------------------------------------------------------------------
// Muestras para la leyenda (36 × 22): el mismo dibujo que el mapa.

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

/// Agua a la altura elegida: relleno + rayado + borde continuo.
class MuestraAgua extends CustomPainter {
  final ColoresMapa c;
  const MuestraAgua(this.c);

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas.drawRect(r, Paint()..color = c.terreno);
    canvas.drawRect(r, Paint()..color = c.margen); // en el mapa, el agua va sobre el margen
    canvas.drawRect(r, Paint()..color = c.agua);
    canvas.drawRect(r, pinturaRayado(c.rayado));
    canvas.drawRect(
      r.deflate(TrazosMapa.bordeAgua / 2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = TrazosMapa.bordeAgua
        ..color = c.bordeAgua,
    );
  }

  @override
  bool shouldRepaint(MuestraAgua old) => old.c != c;
}

/// Margen "puede llegar un poco más": relleno pálido, sin rayado, borde de puntos.
class MuestraMargen extends CustomPainter {
  final ColoresMapa c;
  const MuestraMargen(this.c);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Color.alphaBlend(c.margen, c.terreno));
    final punto = Paint()..color = c.bordeMargen;
    const radio = TrazosMapa.bordeMargen / 2;
    const paso = TrazosMapa.bordeMargen * 2;
    for (var x = radio; x < size.width; x += paso) {
      canvas.drawCircle(Offset(x, radio), radio, punto);
      canvas.drawCircle(Offset(x, size.height - radio), radio, punto);
    }
    for (var y = radio + paso; y < size.height - paso / 2; y += paso) {
      canvas.drawCircle(Offset(radio, y), radio, punto);
      canvas.drawCircle(Offset(size.width - radio, y), radio, punto);
    }
  }

  @override
  bool shouldRepaint(MuestraMargen old) => old.c != c;
}

/// Borde medido en una crecida real: trazos sobre el terreno.
class MuestraContorno extends CustomPainter {
  final ColoresMapa c;
  const MuestraContorno(this.c);

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final trazo = Paint()
      ..color = c.contorno
      ..strokeWidth = TrazosMapa.contorno;
    for (var x = 0.0; x < size.width; x += 15) {
      canvas.drawLine(Offset(x, y), Offset(math.min(x + 9, size.width), y), trazo);
    }
  }

  @override
  bool shouldRepaint(MuestraContorno old) => old.c != c;
}

/// Zona baja de la costa (v1.1): celeste con rayas horizontales y borde fino.
class MuestraZonaBaja extends CustomPainter {
  final ColoresMapa c;
  const MuestraZonaBaja(this.c);

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas.drawRect(r, Paint()..color = c.terreno);
    canvas.drawRect(
      r,
      pinturaRayado(
        c.rayasZonaBaja,
        periodo: TrazosMapa.periodoZonaBaja,
        grosor: TrazosMapa.grosorZonaBaja,
        horizontal: true,
        fondo: c.zonaBaja,
      ),
    );
    canvas.drawRect(
      r.deflate(TrazosMapa.bordeZonaBaja / 2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = TrazosMapa.bordeZonaBaja
        ..color = c.bordeZonaBaja,
    );
  }

  @override
  bool shouldRepaint(MuestraZonaBaja old) => old.c != c;
}

/// Zona sin validar (v1.1): el borde de trazo y punto, con ribete, sobre
/// medio recuadro de agua rayada (como se ve en el mapa).
class MuestraSinValidar extends CustomPainter {
  final ColoresMapa c;
  const MuestraSinValidar(this.c);

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas.drawRect(r, Paint()..color = c.terreno);
    final abajo = Rect.fromLTRB(0, size.height / 2, size.width, size.height);
    canvas.drawRect(abajo, Paint()..color = Color.alphaBlend(c.agua, Color.alphaBlend(c.margen, c.terreno)));
    canvas.drawRect(abajo, pinturaRayado(c.rayado));
    final y = size.height / 2;
    final ribete = Paint()
      ..color = c.ribete
      ..strokeWidth = TrazosMapa.sinValidar + TrazosMapa.ribeteSinValidar;
    final trazo = Paint()
      ..color = c.sinValidar
      ..strokeWidth = TrazosMapa.sinValidar;
    // trazo 14, hueco 5, punto 3, hueco 5 (igual que el mapa)
    for (final pintura in [ribete, trazo]) {
      for (var x = 0.0; x < size.width; x += 27) {
        canvas.drawLine(Offset(x, y), Offset(math.min(x + 14, size.width), y), pintura);
        if (x + 19 < size.width) canvas.drawLine(Offset(x + 19, y), Offset(math.min(x + 22, size.width), y), pintura);
      }
    }
  }

  @override
  bool shouldRepaint(MuestraSinValidar old) => old.c != c;
}

/// Borde del agua con el río de hoy (v1.1): línea gruesa con ribete, entre
/// agua rayada (arriba) y terreno (abajo).
class MuestraHoy extends CustomPainter {
  final ColoresMapa c;
  const MuestraHoy(this.c);

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas.drawRect(r, Paint()..color = c.terreno);
    final arriba = Rect.fromLTRB(0, 0, size.width, size.height / 2);
    canvas.drawRect(arriba, Paint()..color = Color.alphaBlend(c.agua, Color.alphaBlend(c.margen, c.terreno)));
    canvas.drawRect(arriba, pinturaRayado(c.rayado));
    final y = size.height / 2;
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width, y),
      Paint()
        ..color = c.ribeteHoy
        ..strokeWidth = TrazosMapa.hoy + TrazosMapa.ribeteHoy,
    );
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width, y),
      Paint()
        ..color = c.hoy
        ..strokeWidth = TrazosMapa.hoy,
    );
  }

  @override
  bool shouldRepaint(MuestraHoy old) => old.c != c;
}

/// Loma que quedaría rodeada de agua (v1.1): rombo de aviso. Es el mismo
/// pintor de la marca del mapa, centrado en el lienzo que le den: un rombo
/// de [TrazosMapa.rombo] px (o más chico si no entra) con anillo azul de
/// agua, centro del color del terreno (tierra seca rodeada de agua), un "!"
/// y ribete claro para separarse del agua rayada.
class MarcaAislada extends CustomPainter {
  final ColoresMapa c;
  const MarcaAislada(this.c);

  @override
  void paint(Canvas canvas, Size size) {
    final lado = math.min(TrazosMapa.rombo, math.min(size.width, size.height) - 2);
    final m = size.center(Offset.zero);
    final r = lado / 2;
    ui.Path rombo(double radio) => ui.Path()
      ..moveTo(m.dx, m.dy - radio)
      ..lineTo(m.dx + radio, m.dy)
      ..lineTo(m.dx, m.dy + radio)
      ..lineTo(m.dx - radio, m.dy)
      ..close();
    final anillo = math.max(2.5, lado * 0.13);
    canvas.drawPath(rombo(r), Paint()..color = c.ribeteHoy); // ribete
    canvas.drawPath(rombo(r - 1.5), Paint()..color = c.bordeAgua); // agua alrededor
    canvas.drawPath(rombo(r - 1.5 - anillo), Paint()..color = c.terreno); // loma seca
    // "!" dibujado (no con letra: no depende de la fuente ni de su tamaño)
    final tinta = Paint()
      ..color = c.texto
      ..strokeWidth = math.max(2.0, lado * 0.1)
      ..strokeCap = StrokeCap.round;
    final alto = (r - 1.5 - anillo) * 0.9;
    canvas.drawLine(Offset(m.dx, m.dy - alto * 0.55), Offset(m.dx, m.dy + alto * 0.12), tinta);
    canvas.drawCircle(Offset(m.dx, m.dy + alto * 0.48), tinta.strokeWidth * 0.6, Paint()..color = c.texto);
  }

  @override
  bool shouldRepaint(MarcaAislada old) => old.c != c;
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
/// teléfono). Barrios en mayúsculas espaciadas, arroyos en itálica, calles
/// más chicas cuanto menos importantes, nunca por debajo de 12.
TextStyle estiloRotulo(int prioridad) => switch (prioridad) {
  0 => const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, letterSpacing: 0.8, height: 1.1),
  1 => const TextStyle(fontSize: 13, fontStyle: FontStyle.italic, fontWeight: FontWeight.w600, height: 1.1),
  2 => const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, height: 1.1),
  3 => const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.1),
  _ => const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, height: 1.1),
};

/// Ancho del halo (trazo alrededor de cada letra, del color del terreno).
const anchoHalo = 4.0;

/// Cada cuántos metros de calle se ofrece repetir el nombre. Al alejarse, la
/// separación mínima entre nombres iguales ([_PintorRotulos]) deja uno solo;
/// al acercarse, sigue habiendo un nombre a la vista aunque la mitad de la
/// calle haya quedado fuera de la pantalla.
const espaciadoRotulosM = 400.0;

/// Arma los candidatos a rótulo del fondo, ya ordenados por prioridad (y, a
/// igual prioridad, los tramos más largos primero).
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

/// "Barrio Paysandú Sur" → "Paysandú Sur": en el mapa ya se ve que es un
/// barrio, y el nombre corto entra en más lugares.
String nombreDeBarrio(String nombre) {
  final corto = nombre.replaceFirst(RegExp(r'^Barrio\s+', caseSensitive: false), '').trim();
  return corto.isEmpty ? nombre : corto;
}

/// Puntos de una línea donde puede ir su nombre: el medio si es corta, o
/// uno cada [espaciadoRotulosM] (repartidos parejo) si es larga. De cada uno:
/// el punto, el tramo donde cae (para girar el texto) y los metros de calle
/// que le tocan (el nombre no puede ser más largo que eso en pantalla).
List<(LatLng, LatLng, LatLng, double)> _anclas(List<LatLng> pts) {
  const d = Distance();
  final tramos = [for (var i = 1; i < pts.length; i++) d.as(LengthUnit.Meter, pts[i - 1], pts[i])];
  final total = tramos.fold<double>(0, (a, b) => a + b);
  if (total <= 0) return const [];
  final n = math.max(1, (total / espaciadoRotulosM).floor());
  final salida = <(LatLng, LatLng, LatLng, double)>[];
  var i = 0;
  var recorrido = 0.0; // metros hasta el comienzo del tramo i
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

/// Textos ya medidos, para no medir cientos de nombres en cada cuadro. Si
/// cambia la paleta (modo claro / oscuro) o la letra, se descartan.
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
}

/// Capa de flutter_map con los nombres. Va arriba de todo.
class CapaRotulos extends StatelessWidget {
  final List<Rotulo> candidatos;
  final CacheRotulos cache;
  final ColoresMapa colores;

  /// Partes del mapa tapadas por otra cosa (botones, atribución), según el
  /// tamaño del mapa: ahí no se ponen nombres.
  final List<Rect> Function(Size tamano)? tapadas;

  const CapaRotulos({super.key, required this.candidatos, required this.cache, required this.colores, this.tapadas});

  @override
  Widget build(BuildContext context) {
    final camara = MapCamera.of(context);
    // Los nombres crecen con la letra del teléfono, con tope para que entren.
    final escala = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3).scale(1);
    // La misma letra que el resto de la app.
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

  /// Tope de nombres a la vez: más que esto es ruido en un celular.
  static const maximo = 60;

  /// Distancia mínima entre dos rótulos con el mismo nombre (en píxeles).
  static const separacionMismoNombre = 260.0;

  /// Aire alrededor de cada nombre (en píxeles) para que no se toquen.
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
        // El nombre no puede ser más largo que el tramo de calle que se ve.
        final largoPantalla = r.largoM / _metrosPorPixel(r.punto.latitude, zoom);
        if (largoPantalla < w * 1.1) continue;
        angulo = math.atan2(pb.dy - pa.dy, pb.dx - pa.dx);
        // Nunca cabeza abajo.
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

  /// Metros por píxel lógico en Web Mercator a esa latitud y zoom.
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
