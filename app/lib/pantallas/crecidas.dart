/// Pestaña Crecidas: hasta dónde llegó el agua en crecidas reales anteriores,
/// según los bordes medidos por Dinagua. No calcula agua ni dice nada del
/// nivel de hoy: es una referencia histórica, con el aviso aprobado siempre a
/// la vista. Qué muestra y qué se dejó afuera: docs/crecidas-anteriores.md.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../crecidas/estilo_crecidas.dart';
import '../crecidas/modelos_crecidas.dart';
import '../crecidas/repositorio_crecidas.dart';
import '../tema.dart';
import '../textos.dart';
import 'comunes.dart';

// ---------------------------------------------------------------------------
// Textos

/// Aviso aprobado por el dueño (27/10/2026). Va siempre a la vista, pegado
/// al mapa. No cambiarlo sin su visto bueno.
const textoAvisoCrecidas =
    'Muestra hasta dónde llegó el agua en crecidas anteriores, según Dinagua. La ciudad cambió desde entonces, '
    'así que una crecida igual no llega necesariamente al mismo lugar. No es un pronóstico ni reemplaza las '
    'indicaciones del Cecoed.';

/// Fuente, a la vista debajo del aviso.
const textoFuenteCrecidas =
    'Fuente: Dirección Nacional de Aguas (Dinagua), Ministerio de Ambiente. Calles y río: © colaboradores de OpenStreetMap.';

/// Atribución que va siempre sobre el mapa.
const textoAtribucionCrecidas = '© OpenStreetMap · Dinagua';

const textoCrecidasNoDisponibles = 'Las crecidas anteriores no están disponibles';

/// Las líneas cubren solo la zona que relevó Dinagua.
const textoZonaRelevada =
    'La línea cubre solo la zona que relevó Dinagua, sobre la costa. Donde no hay línea no quiere decir que '
    'el agua no haya llegado.';

const textoDosDedos = 'Para mover el mapa usá dos dedos o las flechas de abajo.';

/// Hoja de fuentes (solo texto, sin enlaces, como en el resto de la app).
const textosFuentesCrecidas = [
  (
    'Bordes de las crecidas',
    'Curvas de inundación de la Dirección Nacional de Aguas (Dinagua), Ministerio de Ambiente, servicio de '
        'mapas de ambiente.gub.uy. Información pública; la citamos como fuente. La altura y la fecha de cada '
        'crecida son las que da Dinagua. Cambios nuestros: recorte a Paysandú, simplificación y sacamos los '
        'tramos rectos con que Dinagua cierra la zona relevada sobre el río, que no marcan hasta dónde llegó '
        'el agua.',
  ),
  (
    'Calles, río y barrios',
    '© colaboradores de OpenStreetMap. Esos datos se comparten con la misma licencia, ODbL 1.0 '
        '(openstreetmap.org/copyright).',
  ),
];

const textoFuentesDeslinde =
    'Ni el Ministerio de Ambiente ni OpenStreetMap avalan esta app ni son responsables de lo que muestra.';

const _meses = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', //
  'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
];

/// "3 de julio de 2025".
String fechaLarga(DateTime f) => '${f.day} de ${_meses[f.month - 1]} de ${f.year}';

/// "6,58 m según Dinagua".
String alturaSegun(Crecida c) => '${formatoAltura(c.alturaM)} m según ${c.fuente}';

/// "6,58 metros según Dinagua" (para el lector de pantalla).
String _alturaSegunHablada(Crecida c) => '${formatoAltura(c.alturaM)} metros según ${c.fuente}';

/// Resumen textual del mapa para TalkBack (el dibujo no se puede recorrer).
/// [crecida] null: "Ver todas". [sinBorde]: crecidas cuyo borde no se pudo leer.
String resumenCrecidas({Crecida? crecida, required List<Crecida> todas, Set<String> sinBorde = const {}}) {
  if (crecida != null) {
    if (sinBorde.contains(crecida.clave)) {
      return '${crecida.nombre}, ${_alturaSegunHablada(crecida)}: no se pudo leer el borde de esta crecida, '
          'así que el mapa no la muestra.';
    }
    return '${crecida.nombre}, ${_alturaSegunHablada(crecida)}, del ${fechaLarga(crecida.fecha)}: una línea marca '
        'hasta dónde llegó el agua en la costa de Paysandú. $textoZonaRelevada';
  }
  final vistas = [for (final c in todas) if (!sinBorde.contains(c.clave)) c];
  final lista = [for (final c in vistas) '${c.nombre.replaceFirst('Crecida de ', '')}, ${_alturaSegunHablada(c)}'];
  return 'Las ${vistas.length} crecidas medidas por Dinagua, cada una con su color y su tipo de línea: '
      '${lista.join('; ')}. $textoZonaRelevada';
}

// ---------------------------------------------------------------------------

/// Alto del mapa: 40 % de la pantalla, entre estos dos topes.
const altoMapa = 360.0;
const altoMapaMinimo = 260.0;

class PantallaCrecidas extends StatefulWidget {
  final RepositorioCrecidas repositorio;

  const PantallaCrecidas({super.key, required this.repositorio});

  @override
  State<PantallaCrecidas> createState() => _PantallaCrecidasState();
}

enum _Carga { cargando, lista, noDisponible }

class _PantallaCrecidasState extends State<PantallaCrecidas> {
  _Carga _carga = _Carga.cargando;
  IndiceCrecidas? _indice;
  BaseMapa? _base;

  /// Bordes leídos, por clave de crecida. Si falta uno, no se pudo leer.
  final _bordes = <String, BordeCrecida>{};

  /// La crecida elegida; null es "Ver todas".
  Crecida? _elegida;

  final _controlador = MapController();
  final _rotulos = CacheRotulos();

  /// Paleta con la que se armó el fondo (si cambia el tema, se rearma).
  ColoresMapa? _colores;
  List<Polygon> _cauce = const [];
  List<Polyline> _calles = const [];
  List<Polyline> _cursos = const [];
  List<Rotulo> _candidatos = const [];

  bool _avisoDosDedos = false;
  Timer? _relojAviso;
  final _dedos = <int, Offset>{};
  Offset _arrastre = Offset.zero;

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  @override
  void dispose() {
    _relojAviso?.cancel();
    _controlador.dispose();
    _rotulos.dispose();
    super.dispose();
  }

  Future<void> _iniciar() async {
    final repo = widget.repositorio;
    final e = await repo.indice();
    if (!mounted) return;
    if (e is! IndiceListo) {
      setState(() => _carga = _Carga.noDisponible);
      return;
    }
    final base = await repo.base();
    if (!mounted) return;
    if (base == null) {
      setState(() => _carga = _Carga.noDisponible);
      return;
    }
    // Son pocos y chicos: se leen todos de una vez (para "Ver todas" y para
    // encuadrar el mapa).
    for (final c in e.indice.crecidas) {
      final b = await repo.borde(c);
      if (b != null) _bordes[c.clave] = b;
    }
    if (!mounted) return;
    setState(() {
      _indice = e.indice;
      _base = base;
      // Por defecto, la más reciente.
      _elegida = e.indice.crecidas.first;
      _carga = _Carga.lista;
    });
  }

  void _seguirPaleta(ColoresMapa c) {
    if (identical(c, _colores)) return;
    final base = _base!;
    _colores = c;
    _cauce = poligonosCauce(base, c);
    _calles = lineasCalles(base, c);
    _cursos = lineasCursos(base, c);
    if (_candidatos.isEmpty) _candidatos = armarRotulos(base);
  }

  void _elegir(Crecida? c) => setState(() => _elegida = c);

  Set<String> get _sinBorde => {
    for (final c in _indice!.crecidas)
      if (!_bordes.containsKey(c.clave)) c.clave,
  };

  // ----- Pantalla -----

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    switch (_carga) {
      case _Carga.cargando:
        return Center(
          child: Semantics(
            liveRegion: true,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Preparando el mapa…', style: tema.bodyLarge),
            ),
          ),
        );
      case _Carga.noDisponible:
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Semantics(header: true, child: Text(textoCrecidasNoDisponibles, style: tema.titleLarge)),
            const SizedBox(height: 12),
            Text('No se pudieron leer los datos de esta pestaña. La altura del río sigue en Inicio y en Gráfico.',
                style: tema.bodyLarge),
          ],
        );
      case _Carga.lista:
        break;
    }
    final ind = _indice!;
    final elegida = _elegida;
    final c = ColoresMapa.actuales();
    _seguirPaleta(c);

    // Columna y no ListView: el mapa no se desarma (ni pierde el zoom) al
    // bajar hasta las fuentes.
    return SingleChildScrollView(
      key: const ValueKey('crecidas-scroll'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(header: true, child: Text('Crecidas anteriores', style: tema.titleLarge)),
          const SizedBox(height: 8),
          _Lectura(crecida: elegida, cuantas: ind.crecidas.length),
          const SizedBox(height: 12),
          _Marco(mapa: _mapa(ind, c), mover: _FilaMoverMapa(alMover: _mover)),
          if (elegida != null && !_bordes.containsKey(elegida.clave)) ...[
            const SizedBox(height: 12),
            const Recuadro(icono: Icons.warning_amber, texto: 'No se pudo leer el borde de esta crecida.'),
          ],
          const SizedBox(height: 24),
          Semantics(header: true, child: Text('Elegí una crecida', style: tema.titleMedium)),
          const SizedBox(height: 8),
          for (final (i, cr) in ind.crecidas.indexed) ...[
            _Opcion(
              titulo: cr.nombre,
              detalle: '${alturaSegun(cr)} · ${fechaLarga(cr.fecha)}',
              elegida: elegida == cr,
              muestra: MuestraCrecida(c, i, todas: elegida == null),
              alTocar: () => _elegir(cr),
            ),
            const SizedBox(height: 8),
          ],
          _Opcion(
            titulo: 'Ver todas',
            detalle: 'Cada crecida con su color y su tipo de línea.',
            elegida: elegida == null,
            alTocar: () => _elegir(null),
          ),
          const SizedBox(height: 24),
          _Leyenda(indice: ind, elegida: elegida, colores: c, sinBorde: _sinBorde),
          const Separador(),
          const _Fuentes(),
        ],
      ),
    );
  }

  Widget _mapa(IndiceCrecidas ind, ColoresMapa c) {
    final elegida = _elegida;
    final crecidas = ind.crecidas;
    final limites = LatLngBounds(ind.surOeste, ind.norEste);
    final encuadre = limitesDe(_bordes.values) ?? limites;
    // Con "Ver todas", la más vieja abajo y la más reciente arriba.
    final lineas = <Polyline>[
      for (final (i, cr) in crecidas.indexed.toList().reversed)
        if ((elegida == null || elegida == cr) && _bordes[cr.clave] != null)
          ...lineasCrecida(_bordes[cr.clave]!, i, c, todas: elegida == null),
    ];
    List<Rect> tapadas(Size s) => [
      Rect.fromLTWH(s.width - 64, 0, 64, 176),
      Rect.fromLTWH(0, s.height - 26, s.width, 26),
    ];
    final descripcion = resumenCrecidas(crecida: elegida, todas: crecidas, sinBorde: _sinBorde);
    final quieto = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      container: true,
      image: true,
      label: descripcion,
      child: SizedBox(
        height: (MediaQuery.sizeOf(context).height * 0.40).clamp(altoMapaMinimo, altoMapa),
        child: Stack(
          children: [
            ExcludeSemantics(
              // Con un dedo se mueve la página, no el mapa: así el mapa no
              // atrapa el desplazamiento (ni el de TalkBack). El mapa se mueve
              // con dos dedos o con las flechas, y se acerca con + / −,
              // pellizcando o con doble toque.
              child: Listener(
                onPointerDown: (e) => _dedos[e.pointer] = e.position,
                onPointerMove: _alMoverDedo,
                onPointerUp: (e) => _soltarDedo(e.pointer),
                onPointerCancel: (e) => _soltarDedo(e.pointer),
                child: FlutterMap(
                  key: const ValueKey('crecidas-mapa'),
                  mapController: _controlador,
                  options: MapOptions(
                    // Arranca en el centro de los bordes y, ya con tamaño,
                    // se encuadran todos.
                    initialCenter: encuadre.center,
                    initialZoom: 12.5,
                    onMapReady: () => _controlador.fitCamera(_encuadre(encuadre)),
                    minZoom: 11,
                    maxZoom: 18,
                    backgroundColor: c.terreno,
                    cameraConstraint: CameraConstraint.containCenter(bounds: limites),
                    interactionOptions: InteractionOptions(
                      flags: InteractiveFlag.pinchZoom | InteractiveFlag.pinchMove | InteractiveFlag.doubleTapZoom,
                      doubleTapZoomDuration: quieto ? Duration.zero : const Duration(milliseconds: 200),
                    ),
                  ),
                  // De abajo hacia arriba: cauce y arroyos, calles, el borde
                  // de la crecida y los nombres.
                  children: [
                    PolygonLayer(polygons: _cauce),
                    PolylineLayer(polylines: _cursos),
                    PolylineLayer(polylines: _calles),
                    PolylineLayer(key: ValueKey('bordes-${elegida?.clave ?? 'todas'}-${c.oscuro}'), polylines: lineas),
                    CapaRotulos(candidatos: _candidatos, cache: _rotulos, colores: c, tapadas: tapadas),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                color: c.terreno.withValues(alpha: 0.85),
                child: MediaQuery.withClampedTextScaling(
                  maxScaleFactor: 1.2,
                  child: Text(textoAtribucionCrecidas, style: TextStyle(fontSize: 12, color: Colores.tinta)),
                ),
              ),
            ),
            Positioned(
              right: 8,
              top: 8,
              child: Column(
                children: [
                  _BotonMapa(icono: Icons.add, texto: 'Acercar', alTocar: () => _zoom(1)),
                  const SizedBox(height: 8),
                  _BotonMapa(icono: Icons.remove, texto: 'Alejar', alTocar: () => _zoom(-1)),
                  const SizedBox(height: 8),
                  _BotonMapa(
                    icono: Icons.zoom_out_map,
                    texto: 'Ver toda la zona',
                    alTocar: () => _controlador.fitCamera(_encuadre(encuadre)),
                  ),
                ],
              ),
            ),
            if (_avisoDosDedos)
              Positioned(
                left: 8,
                right: 64,
                top: 8,
                child: ExcludeSemantics(
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(color: Colores.tinta, borderRadius: BorderRadius.circular(12)),
                      child: Text(
                        textoDosDedos,
                        style: Theme.of(context).textTheme.bodyMedium
                            ?.copyWith(color: Colores.fondo, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Encuadre de los bordes, sin que los tapen los botones de la derecha.
  static CameraFit _encuadre(LatLngBounds b) =>
      CameraFit.bounds(bounds: b, padding: const EdgeInsets.fromLTRB(16, 16, 64, 28), minZoom: 11);

  void _zoom(double cuanto) {
    final cam = _controlador.camera;
    _controlador.move(cam.center, cam.clampZoom(cam.zoom + cuanto));
  }

  /// Mueve el mapa un tercio de lo que se ve (dx, dy en -1, 0, 1).
  void _mover(int dx, int dy) {
    final cam = _controlador.camera;
    final paso = Offset(dx * cam.nonRotatedSize.width / 3, dy * cam.nonRotatedSize.height / 3);
    _controlador.move(cam.unprojectAtZoom(cam.projectAtZoom(cam.center) + paso), cam.zoom);
  }

  /// Un dedo que arrastra de costado sobre el mapa: seguramente quiere
  /// moverlo. Se le dice cómo, un momento.
  void _alMoverDedo(PointerMoveEvent e) {
    if (_dedos.length != 1 || !_dedos.containsKey(e.pointer)) {
      _arrastre = Offset.zero;
      return;
    }
    _arrastre += e.delta;
    if (_arrastre.dx.abs() > 32 && _arrastre.dx.abs() > 2 * _arrastre.dy.abs() && !_avisoDosDedos) {
      setState(() => _avisoDosDedos = true);
      _relojAviso?.cancel();
      _relojAviso = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _avisoDosDedos = false);
      });
    }
  }

  void _soltarDedo(int puntero) {
    _dedos.remove(puntero);
    if (_dedos.isEmpty) _arrastre = Offset.zero;
  }
}

// ---------------------------------------------------------------------------
// Partes

/// Qué se está mirando: nombre, altura según Dinagua y fecha.
class _Lectura extends StatelessWidget {
  final Crecida? crecida;
  final int cuantas;

  const _Lectura({required this.crecida, required this.cuantas});

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    final c = crecida;
    return Semantics(
      container: true,
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: c == null
            ? [
                Text('Todas las crecidas', style: tema.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                Text('Las $cuantas crecidas medidas por Dinagua, juntas.', style: tema.bodyLarge),
              ]
            : [
                Text(c.nombre, style: tema.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                Text('${alturaSegun(c)} · ${fechaLarga(c.fecha)}', style: tema.bodyLarge),
              ],
      ),
    );
  }
}

/// Marco del mapa: el dibujo, las flechas y, pegados, el aviso y la fuente.
class _Marco extends StatelessWidget {
  final Widget mapa;
  final Widget mover;

  const _Marco({required this.mapa, required this.mover});

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    return ClipRRect(
      borderRadius: radioSuperficie,
      child: ColoredBox(
        color: Colores.superficie,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            mapa,
            mover,
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ExcludeSemantics(child: Icon(Icons.info_outline, size: 24, color: Colores.tinta)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          textoAvisoCrecidas,
                          key: const ValueKey('aviso-crecidas'),
                          style: tema.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        Text(textoFuenteCrecidas, style: tema.bodyMedium?.copyWith(color: Colores.tintaSecundaria)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Flechas de 48 dp para mover el mapa sin arrastrar (WCAG 2.5.7).
class _FilaMoverMapa extends StatelessWidget {
  final void Function(int dx, int dy) alMover;

  const _FilaMoverMapa({required this.alMover});

  static const flechas = [
    (Icons.arrow_back, 'Ver más al oeste, hacia el río', -1, 0),
    (Icons.arrow_upward, 'Ver más al norte', 0, -1),
    (Icons.arrow_downward, 'Ver más al sur', 0, 1),
    (Icons.arrow_forward, 'Ver más al este', 1, 0),
  ];

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
    child: Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 4,
      children: [
        Text('Mover el mapa', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (i, (icono, texto, dx, dy)) in flechas.indexed) ...[
              if (i > 0) const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: texto,
                onPressed: () => alMover(dx, dy),
                constraints: const BoxConstraints.tightFor(width: 48, height: 48),
                icon: Icon(icono),
              ),
            ],
          ],
        ),
      ],
    ),
  );
}

class _BotonMapa extends StatelessWidget {
  final IconData icono;
  final String texto;
  final VoidCallback alTocar;

  const _BotonMapa({required this.icono, required this.texto, required this.alTocar});

  @override
  Widget build(BuildContext context) => IconButton.filled(
    tooltip: texto,
    onPressed: alTocar,
    style: IconButton.styleFrom(backgroundColor: Colores.superficie, foregroundColor: Colores.primario),
    constraints: const BoxConstraints.tightFor(width: 48, height: 48),
    icon: Icon(icono),
  );
}

/// Una opción de la lista: tocable entera, con marca de elegida (no solo color).
class _Opcion extends StatelessWidget {
  final String titulo;
  final String detalle;
  final bool elegida;
  final CustomPainter? muestra;
  final VoidCallback alTocar;

  const _Opcion({required this.titulo, required this.detalle, required this.elegida, this.muestra, required this.alTocar});

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      selected: elegida,
      inMutuallyExclusiveGroup: true,
      child: Material(
        color: elegida ? Colores.primarioSuave : Colores.superficie,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: elegida ? Colores.primario : Colores.bordeSuave, width: elegida ? 2 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: alTocar,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  ExcludeSemantics(
                    child: Icon(
                      elegida ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                      color: elegida ? Colores.primario : Colores.bordeControl,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(titulo, style: tema.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
                        Text(detalle, style: tema.bodyMedium),
                      ],
                    ),
                  ),
                  if (muestra != null) ...[
                    const SizedBox(width: 8),
                    ExcludeSemantics(child: SizedBox(width: 40, height: 22, child: CustomPaint(painter: muestra))),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Qué muestra el mapa": siempre abierta.
class _Leyenda extends StatelessWidget {
  final IndiceCrecidas indice;
  final Crecida? elegida;
  final ColoresMapa colores;
  final Set<String> sinBorde;

  const _Leyenda({required this.indice, required this.elegida, required this.colores, required this.sinBorde});

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    final e = elegida;
    final filas = <(CustomPainter?, String)>[
      if (e != null)
        (
          MuestraCrecida(colores, indice.crecidas.indexOf(e), todas: false),
          'Hasta dónde llegó el agua en la ${e.nombre.replaceFirst('Crecida', 'crecida')} '
              '(${alturaSegun(e)}).',
        )
      else
        for (final (i, c) in indice.crecidas.indexed)
          if (!sinBorde.contains(c.clave))
            (MuestraCrecida(colores, i, todas: true), '${c.nombre} (${alturaSegun(c)}).'),
      (MuestraCauce(colores), 'Río Uruguay y arroyos en su cauce normal, según OpenStreetMap.'),
      (null, textoZonaRelevada),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(header: true, child: Text('Qué muestra el mapa', style: tema.titleMedium)),
        for (final (muestra, texto) in filas)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: ExcludeSemantics(
                    child: SizedBox(
                      width: 40,
                      height: 22,
                      child: muestra == null
                          ? Icon(Icons.info_outline, size: 22, color: Colores.tintaSecundaria)
                          : CustomPaint(painter: muestra),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(texto, style: tema.bodyLarge)),
              ],
            ),
          ),
      ],
    );
  }
}

/// Fuentes, a la vista (solo texto).
class _Fuentes extends StatelessWidget {
  const _Fuentes();

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(header: true, child: Text('Fuentes', style: tema.titleMedium)),
        for (final (titulo, texto) in textosFuentesCrecidas) ...[
          const SizedBox(height: 8),
          Text(titulo, style: tema.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
          Text(texto, style: tema.bodyMedium),
        ],
        const SizedBox(height: 12),
        Text(textoFuentesDeslinde, style: tema.bodyMedium?.copyWith(color: Colores.tintaSecundaria)),
      ],
    );
  }
}
