/// Pestaña Crecidas: hasta dónde llegó el agua en crecidas reales anteriores,
/// según los bordes medidos por Dinagua. No calcula agua ni dice nada del
/// nivel de hoy: es una referencia histórica, con el aviso aprobado siempre a
/// la vista. Qué muestra y qué se dejó afuera: docs/crecidas-anteriores.md.
library;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../crecidas/estilo_crecidas.dart';
import '../crecidas/modelos_crecidas.dart';
import '../crecidas/repositorio_crecidas.dart';
import '../tema.dart';
import '../textos.dart';
import 'comunes.dart';

// ---------------------------------------------------------------------------
// Textos

/// Aviso aprobado por el dueño (27/10/2026). Va siempre a la vista, arriba
/// del mapa. No cambiarlo sin su visto bueno.
const textoAvisoCrecidas =
    'Muestra hasta dónde llegó el agua en crecidas anteriores, según Dinagua. La ciudad cambió desde entonces, '
    'así que una crecida igual no llega necesariamente al mismo lugar. No es un pronóstico ni reemplaza las '
    'indicaciones del Cecoed.';

/// Sobre la escala de las alturas, aprobada por el dueño (27/10/2026). Va
/// junto al aviso y en el resumen para el lector de pantalla.
const textoEscalaCrecidas = 'Las alturas de Dinagua pueden no coincidir exactamente con la escala de CARU.';

/// Fuente, a la vista debajo del mapa.
const textoFuenteCrecidas =
    'Fuente: Dirección Nacional de Aguas (Dinagua), Ministerio de Ambiente. Calles y río: © colaboradores de OpenStreetMap.';

/// Atribución que va siempre sobre el mapa.
const textoAtribucionCrecidas = '© OpenStreetMap · Dinagua';

/// Línea corta que acompaña al mapa en pantalla completa.
const textoNoEsPronostico = 'No es un pronóstico.';

const textoCrecidasNoDisponibles = 'Las crecidas anteriores no están disponibles';

/// Las líneas cubren solo la zona que relevó Dinagua.
const textoZonaRelevada =
    'La línea cubre solo la zona que relevó Dinagua, sobre la costa. Donde no hay línea no quiere decir que '
    'el agua no haya llegado.';

/// El resumen para el lector de pantalla no nombra calles ni barrios.
const textoResumenSinCalles = 'Este resumen no dice qué calles o barrios alcanzó el agua.';

/// Pista sobre el mapa con "Ver todas" y el mapa lejos.
const textoAcercarParaDistinguir = 'Acercá para distinguir las líneas.';

/// Hoja de fuentes (solo texto, sin enlaces, como en el resto de la app).
const textosFuentesCrecidas = [
  (
    'Bordes de las crecidas',
    'Curvas de inundación de la Dirección Nacional de Aguas (Dinagua), Ministerio de Ambiente, servicio de '
        'mapas de ambiente.gub.uy. Información pública; la citamos como fuente. La altura y la fecha de cada '
        'crecida son las que da Dinagua (Dinagua no publica la hora). Cambios nuestros: recorte a Paysandú, '
        'simplificación y sacamos los tramos rectos con que Dinagua cierra la zona relevada sobre el río, que '
        'no marcan hasta dónde llegó el agua.',
  ),
  (
    'Calles, río y barrios',
    '© colaboradores de OpenStreetMap. Esos datos se comparten con la misma licencia, ODbL 1.0 '
        '(openstreetmap.org/copyright).',
  ),
];

/// Igual que el aviso de assets/crecidas/LICENSE-DATOS.md (lo controla una
/// prueba).
const textoFuentesDeslinde =
    'Mi Río UY es un proyecto comunitario sin vínculo con el Ministerio de Ambiente, Dinagua, CARU, el Cecoed, '
    'la Intendencia ni la Fundación OpenStreetMap, que no avalan este trabajo. Los datos se ofrecen «tal cual», '
    'sin garantía.';

const _meses = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', //
  'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
];

/// "3 de julio de 2025". Dinagua da el día, no la hora.
String fechaLarga(DateTime f) => '${f.day} de ${_meses[f.month - 1]} de ${f.year}';

/// "6,58 m según Dinagua".
String alturaSegun(Crecida c) => '${formatoAltura(c.alturaM)} m según ${c.fuente}';

/// "6,58 m según Dinagua · 3 de julio de 2025".
String alturaYFecha(Crecida c) => '${alturaSegun(c)} · ${fechaLarga(c.fecha)}';

/// Un texto de pantalla dicho en voz alta: "m" como "metros" y sin "·".
String hablado(String texto) => unidadesEnPalabras(texto).replaceAll(' · ', ', ');

/// "crecida de enero de 2019" (el nombre en minúscula, para mitad de frase).
String _enMinuscula(Crecida c) => c.nombre.replaceFirst('Crecida', 'crecida');

/// "6,58 metros según Dinagua, del 3 de julio de 2025".
String _alturaYFechaHablada(Crecida c) => '${hablado(alturaSegun(c))}, del ${fechaLarga(c.fecha)}';

/// Resumen textual del mapa para TalkBack (el dibujo no se puede recorrer).
/// [crecida] null: "Ver todas". [sinBorde]: crecidas cuyo borde no se pudo leer.
String resumenCrecidas({Crecida? crecida, required List<Crecida> todas, Set<String> sinBorde = const {}}) {
  const cierre = '$textoResumenSinCalles $textoEscalaCrecidas';
  if (crecida != null) {
    if (sinBorde.contains(crecida.clave)) {
      return '${crecida.nombre}, ${_alturaYFechaHablada(crecida)}: no se pudo leer el borde de esta crecida, '
          'así que el mapa no la muestra. $textoEscalaCrecidas';
    }
    return '${crecida.nombre}, ${_alturaYFechaHablada(crecida)}: una línea marca hasta dónde llegó el agua en la '
        'costa de Paysandú. $textoZonaRelevada $cierre';
  }
  final vistas = [
    for (final (i, c) in todas.indexed)
      if (!sinBorde.contains(c.clave)) (i, c),
  ];
  final lista = [
    for (final (i, c) in vistas)
      '${c.nombre.replaceFirst('Crecida de ', '')}, ${_alturaYFechaHablada(c)}, ${TrazosMapa.nombre(i)}',
  ];
  final faltan = [
    for (final c in todas)
      if (sinBorde.contains(c.clave)) _enMinuscula(c),
  ];
  final cuantas = vistas.length == 1 ? 'La única crecida' : 'Las ${vistas.length} crecidas';
  return '$cuantas medidas por Dinagua que se pueden ver, cada una con su color y su tipo de línea: '
      '${lista.join('; ')}. '
      '${faltan.isEmpty ? '' : 'No se pudo leer el borde de la ${faltan.join(' ni de la ')}. '}'
      '$textoZonaRelevada $cierre';
}

/// Lo que dice TalkBack al elegir una opción (la lectura de arriba queda
/// fuera de la vista, así que se anuncia).
String anuncioCrecida({Crecida? crecida, required int cuantasVisibles}) => crecida == null
    ? 'Mapa: las $cuantasVisibles crecidas medidas por Dinagua, juntas.'
    : 'Mapa: ${_enMinuscula(crecida)}, ${_alturaYFechaHablada(crecida)}.';

// ---------------------------------------------------------------------------

/// Alto del mapa: 40 % de la pantalla, entre estos dos topes. Siempre menos
/// de la mitad: queda lugar fuera del mapa para desplazar la página con el
/// dedo, ya que con un dedo sobre el mapa se mueve el mapa.
const altoMapa = 360.0;
const altoMapaMinimo = 260.0;

/// Con "Ver todas" y el mapa lejos (zoom menor a este), las líneas se pisan.
const zoomParaDistinguir = 14.0;

/// Costa céntrica, donde las cinco líneas se separan bien.
const centroVerTodas = LatLng(-32.318, -58.098);
const zoomVerTodas = 14.5;

/// Gestos del mapa: un dedo lo mueve, pellizco y doble toque acercan. Sin
/// rotación (el norte siempre arriba).
const gestosMapa = InteractiveFlag.all & ~InteractiveFlag.rotate;

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

  /// Capas del fondo (río, arroyos y calles), armadas una vez por paleta: así
  /// un redibujo de la página (el reloj de 5 minutos de main.dart, por
  /// ejemplo) no vuelve a proyectar las ~1.200 calles.
  List<Widget> _fondo = const [];
  List<Rotulo> _candidatos = const [];

  /// Capa de bordes, por crecida elegida ("todas" para "Ver todas") y paleta.
  final _capasBorde = <String, Widget>{};

  /// El mapa ya armado y con qué se armó.
  Widget? _mapa;
  Object? _claveMapa;

  /// Con "Ver todas", el mapa está lejos y las líneas se pisan.
  bool _lejos = false;

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  @override
  void dispose() {
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
    _fondo = [
      PolygonLayer(polygons: poligonosCauce(base, c)),
      PolylineLayer(polylines: lineasCursos(base, c)),
      PolylineLayer(polylines: lineasCalles(base, c)),
    ];
    if (_candidatos.isEmpty) _candidatos = armarRotulos(base);
  }

  /// Capa con el borde de la elegida (o los de todas), guardada.
  Widget _capaBordes(ColoresMapa c) {
    final elegida = _elegida;
    final clave = '${elegida?.clave ?? 'todas'}-${c.oscuro}';
    return _capasBorde[clave] ??= () {
      // Con "Ver todas", la más vieja abajo y la más reciente arriba.
      final lineas = <Polyline>[
        for (final (i, cr) in _indice!.crecidas.indexed.toList().reversed)
          if ((elegida == null || elegida == cr) && _bordes[cr.clave] != null)
            ...lineasCrecida(_bordes[cr.clave]!, i, c, todas: elegida == null),
      ];
      return PolylineLayer(key: ValueKey('bordes-$clave'), polylines: lineas);
    }();
  }

  /// Todas las capas del mapa, de abajo hacia arriba: cauce y arroyos,
  /// calles, el borde de la crecida y los nombres.
  List<Widget> _capas(ColoresMapa c, List<Rect> Function(Size) tapadas) => [
    ..._fondo,
    _capaBordes(c),
    CapaRotulos(candidatos: _candidatos, cache: _rotulos, colores: c, tapadas: tapadas),
  ];

  List<Crecida> get _visibles => [
    for (final c in _indice!.crecidas)
      if (_bordes.containsKey(c.clave)) c,
  ];

  void _elegir(Crecida? c) {
    if (c == _elegida) return;
    setState(() => _elegida = c);
    if (c == null && _controlador.camera.zoom < zoomParaDistinguir) {
      // Con el mapa entero las líneas se pisan: se acerca a la costa céntrica,
      // donde se separan. Si ya estaba cerca, se deja donde está.
      _controlador.move(centroVerTodas, zoomVerTodas);
    }
    _seguirZoom(_controlador.camera);
    SemanticsService.sendAnnouncement(
      View.of(context),
      anuncioCrecida(crecida: c, cuantasVisibles: _visibles.length),
      TextDirection.ltr,
    );
  }

  Set<String> get _sinBorde => {
    for (final c in _indice!.crecidas)
      if (!_bordes.containsKey(c.clave)) c.clave,
  };

  /// Prende o apaga la pista "Acercá…" (solo con "Ver todas").
  void _seguirZoom(MapCamera camara) {
    final lejos = _elegida == null && camara.zoom < zoomParaDistinguir;
    if (lejos == _lejos || !mounted) return;
    // Puede llegar en medio de un cuadro (el mapa se movió al armarse).
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.idle) {
      setState(() => _lejos = lejos);
    } else {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted && _lejos != lejos) setState(() => _lejos = lejos);
      });
    }
  }

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
            Text(
              'No se pudieron leer los datos de esta pestaña. La altura del río sigue en Inicio y en Gráfico.',
              style: tema.bodyLarge,
            ),
          ],
        );
      case _Carga.lista:
        break;
    }
    final ind = _indice!;
    final elegida = _elegida;
    final c = ColoresMapa.actuales();
    _seguirPaleta(c);
    final sinBorde = _sinBorde;
    final faltan = [
      for (final cr in ind.crecidas)
        if (sinBorde.contains(cr.clave)) _enMinuscula(cr),
    ];

    // Columna y no ListView: el mapa no se desarma (ni pierde el zoom) al
    // bajar hasta las fuentes.
    return SingleChildScrollView(
      key: const ValueKey('crecidas-scroll'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(header: true, child: Text('Crecidas anteriores', style: tema.titleLarge)),
          const SizedBox(height: 4),
          _Lectura(crecida: elegida, cuantas: _visibles.length),
          const SizedBox(height: 8),
          const _Aviso(),
          const SizedBox(height: 12),
          _Marco(
            mapa: _mapaEnLinea(ind, c),
            controles: _Controles(alMover: _mover, alPantallaCompleta: () => _abrirPantallaCompleta(ind, c)),
          ),
          if (elegida != null && sinBorde.contains(elegida.clave)) ...[
            const SizedBox(height: 12),
            const Recuadro(icono: Icons.warning_amber, texto: 'No se pudo leer el borde de esta crecida.'),
          ] else if (elegida == null && faltan.isNotEmpty) ...[
            const SizedBox(height: 12),
            Recuadro(
              icono: Icons.warning_amber,
              texto: 'No se pudo leer el borde de la ${faltan.join(' ni de la ')}: no aparece en el mapa.',
            ),
          ],
          const SizedBox(height: 24),
          Semantics(header: true, child: Text('Elegí una crecida', style: tema.titleMedium)),
          const SizedBox(height: 8),
          for (final (i, cr) in ind.crecidas.indexed) ...[
            _Opcion(
              titulo: cr.nombre,
              detalle: alturaYFecha(cr),
              trazo: elegida == null && !sinBorde.contains(cr.clave) ? TrazosMapa.nombre(i) : null,
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
          _Leyenda(indice: ind, elegida: elegida, colores: c, sinBorde: sinBorde),
          const Separador(),
          const _Fuentes(),
        ],
      ),
    );
  }

  /// Encuadre inicial y de "Ver toda la zona": todos los bordes.
  LatLngBounds _encuadreTodo(IndiceCrecidas ind) =>
      limitesDe(_bordes.values) ?? LatLngBounds(ind.surOeste, ind.norEste);

  Widget _mapaEnLinea(IndiceCrecidas ind, ColoresMapa c) {
    final elegida = _elegida;
    final descripcion = resumenCrecidas(crecida: elegida, todas: ind.crecidas, sinBorde: _sinBorde);
    final quieto = MediaQuery.disableAnimationsOf(context);
    final clave = (elegida?.clave, c.oscuro, quieto);
    if (_mapa == null || clave != _claveMapa) {
      _claveMapa = clave;
      final encuadre = _encuadreTodo(ind);
      _mapa = FlutterMap(
        key: const ValueKey('crecidas-mapa'),
        mapController: _controlador,
        options: _opciones(
          ind,
          c,
          quieto: quieto,
          // Arranca en el centro de los bordes y, ya con tamaño, se encuadran
          // todos.
          centro: encuadre.center,
          zoom: 12.5,
          alListo: () => _controlador.fitCamera(_encuadre(encuadre)),
          alMoverse: _seguirZoom,
        ),
        children: _capas(
          c,
          (s) => [Rect.fromLTWH(s.width - 64, 0, 64, 176), Rect.fromLTWH(0, s.height - 26, s.width, 26)],
        ),
      );
    }
    return Semantics(
      container: true,
      image: true,
      label: descripcion,
      child: SizedBox(
        height: (MediaQuery.sizeOf(context).height * 0.40).clamp(altoMapaMinimo, altoMapa),
        child: Stack(
          children: [
            // El dibujo no se recorre con TalkBack: lo reemplaza el resumen.
            ExcludeSemantics(child: _mapa!),
            Positioned(left: 0, bottom: 0, child: _Atribucion(colores: c)),
            Positioned(
              right: 8,
              top: 8,
              child: Column(
                children: [
                  _BotonMapa(icono: Icons.add, texto: 'Acercar', alTocar: () => _zoom(_controlador, 1)),
                  const SizedBox(height: 8),
                  _BotonMapa(icono: Icons.remove, texto: 'Alejar', alTocar: () => _zoom(_controlador, -1)),
                  const SizedBox(height: 8),
                  _BotonMapa(
                    icono: Icons.zoom_out_map,
                    texto: 'Ver toda la zona',
                    alTocar: () => _controlador.fitCamera(_encuadre(_encuadreTodo(ind))),
                  ),
                ],
              ),
            ),
            if (_lejos && elegida == null)
              const Positioned(left: 8, right: 64, top: 8, child: _Pista(texto: textoAcercarParaDistinguir)),
          ],
        ),
      ),
    );
  }

  MapOptions _opciones(
    IndiceCrecidas ind,
    ColoresMapa c, {
    required bool quieto,
    required LatLng centro,
    required double zoom,
    VoidCallback? alListo,
    void Function(MapCamera)? alMoverse,
  }) => MapOptions(
    initialCenter: centro,
    initialZoom: zoom,
    onMapReady: alListo,
    onPositionChanged: alMoverse == null ? null : (camara, _) => alMoverse(camara),
    minZoom: 11,
    maxZoom: 18,
    backgroundColor: c.terreno,
    cameraConstraint: CameraConstraint.containCenter(bounds: LatLngBounds(ind.surOeste, ind.norEste)),
    interactionOptions: InteractionOptions(
      flags: gestosMapa,
      doubleTapZoomDuration: quieto ? Duration.zero : const Duration(milliseconds: 200),
    ),
  );

  Future<void> _abrirPantallaCompleta(IndiceCrecidas ind, ColoresMapa c) async {
    final elegida = _elegida;
    final camara = _controlador.camera;
    MapCamera? ultima;
    final titulo = elegida == null
        ? 'Todas las crecidas (${_visibles.length})'
        : '${elegida.nombre} · ${alturaSegun(elegida)}';
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (contexto) => PantallaCompletaCrecidas(
          titulo: titulo,
          descripcion: resumenCrecidas(crecida: elegida, todas: ind.crecidas, sinBorde: _sinBorde),
          colores: c,
          capas: (tapadas) => _capas(c, tapadas),
          opciones: (controlador) => _opciones(
            ind,
            c,
            quieto: MediaQuery.disableAnimationsOf(contexto),
            centro: camara.center,
            zoom: camara.zoom,
            alMoverse: (cam) => ultima = cam,
          ),
          encuadreTodo: _encuadreTodo(ind),
        ),
      ),
    );
    // Vuelve con el mismo encuadre que dejó en pantalla completa.
    final u = ultima;
    if (mounted && u != null) {
      _controlador.move(u.center, u.zoom);
      _seguirZoom(_controlador.camera);
    }
  }

  /// Encuadre de los bordes, sin que los tapen los botones de la derecha.
  static CameraFit _encuadre(LatLngBounds b) =>
      CameraFit.bounds(bounds: b, padding: const EdgeInsets.fromLTRB(16, 16, 64, 28), minZoom: 11);

  /// Mueve el mapa un tercio de lo que se ve (dx, dy en -1, 0, 1).
  void _mover(int dx, int dy) {
    final cam = _controlador.camera;
    final paso = Offset(dx * cam.nonRotatedSize.width / 3, dy * cam.nonRotatedSize.height / 3);
    _controlador.move(cam.unprojectAtZoom(cam.projectAtZoom(cam.center) + paso), cam.zoom);
  }
}

void _zoom(MapController controlador, double cuanto) {
  final cam = controlador.camera;
  controlador.move(cam.center, cam.clampZoom(cam.zoom + cuanto));
}

// ---------------------------------------------------------------------------
// Pantalla completa

/// El mapa ocupando todo el teléfono, con la misma crecida (o todas). Se
/// cierra con el botón "Cerrar" o con Atrás.
class PantallaCompletaCrecidas extends StatefulWidget {
  final String titulo;
  final String descripcion;
  final ColoresMapa colores;
  final List<Widget> Function(List<Rect> Function(Size) tapadas) capas;
  final MapOptions Function(MapController controlador) opciones;
  final LatLngBounds encuadreTodo;

  const PantallaCompletaCrecidas({
    super.key,
    required this.titulo,
    required this.descripcion,
    required this.colores,
    required this.capas,
    required this.opciones,
    required this.encuadreTodo,
  });

  @override
  State<PantallaCompletaCrecidas> createState() => _PantallaCompletaCrecidasState();
}

class _PantallaCompletaCrecidasState extends State<PantallaCompletaCrecidas> {
  final _controlador = MapController();

  @override
  void dispose() {
    _controlador.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colores;
    final borde = MediaQuery.paddingOf(context);
    final tema = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: c.terreno,
      body: Stack(
        children: [
          Positioned.fill(
            child: Semantics(
              container: true,
              image: true,
              label: widget.descripcion,
              child: ExcludeSemantics(
                child: FlutterMap(
                  key: const ValueKey('crecidas-mapa-completo'),
                  mapController: _controlador,
                  options: widget.opciones(_controlador),
                  children: widget.capas(
                    (s) => [
                      Rect.fromLTWH(0, 0, s.width, borde.top + 72),
                      Rect.fromLTWH(s.width - 72, 0, 72, borde.top + 240),
                      Rect.fromLTWH(0, s.height - borde.bottom - 72, s.width, borde.bottom + 72),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Con letra muy grande el título puede ocupar mucho: se
                  // desplaza dentro de su lugar en vez de tapar el mapa.
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.3),
                    child: SingleChildScrollView(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          MediaQuery.withClampedTextScaling(
                            maxScaleFactor: 1.5,
                            child: FilledButton.icon(
                              key: const ValueKey('cerrar-pantalla-completa'),
                              onPressed: () => Navigator.of(context).maybePop(),
                              style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
                              icon: const Icon(Icons.close),
                              label: const Text('Cerrar'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              constraints: const BoxConstraints(minHeight: 48),
                              alignment: Alignment.centerLeft,
                              decoration: BoxDecoration(
                                color: Colores.superficie.withValues(alpha: 0.94),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colores.bordeControl),
                              ),
                              child: MediaQuery.withClampedTextScaling(
                                maxScaleFactor: 1.5,
                                child: Semantics(
                                  label: hablado(widget.titulo),
                                  excludeSemantics: true,
                                  child: Text(
                                    widget.titulo,
                                    style: tema.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Con letra muy grande puede no haber lugar: los botones se
                  // desplazan en vez de desbordar.
                  Expanded(
                    child: Align(
                      alignment: Alignment.topRight,
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _BotonMapa(icono: Icons.add, texto: 'Acercar', alTocar: () => _zoom(_controlador, 1)),
                            const SizedBox(height: 8),
                            _BotonMapa(icono: Icons.remove, texto: 'Alejar', alTocar: () => _zoom(_controlador, -1)),
                            const SizedBox(height: 8),
                            _BotonMapa(
                              icono: Icons.zoom_out_map,
                              texto: 'Ver toda la zona',
                              alTocar: () => _controlador.fitCamera(
                                CameraFit.bounds(
                                  bounds: widget.encuadreTodo,
                                  padding: const EdgeInsets.fromLTRB(16, 72, 72, 72),
                                  minZoom: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Flexible(
                        child: Container(
                          key: const ValueKey('no-es-pronostico'),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(color: Colores.tinta, borderRadius: BorderRadius.circular(12)),
                          child: MediaQuery.withClampedTextScaling(
                            maxScaleFactor: 1.5,
                            child: Text(
                              textoNoEsPronostico,
                              style: tema.bodyLarge?.copyWith(color: Colores.fondo, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.bottomLeft,
                    child: _Atribucion(colores: c),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Partes

/// Qué se está mirando: nombre, altura según Dinagua y fecha. No es región en
/// vivo: al elegir otra crecida se anuncia (ver _elegir).
class _Lectura extends StatelessWidget {
  final Crecida? crecida;
  final int cuantas;

  const _Lectura({required this.crecida, required this.cuantas});

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    final c = crecida;
    final (titulo, detalle) = c == null
        ? ('Todas las crecidas', 'Las $cuantas crecidas medidas por Dinagua, juntas.')
        : (c.nombre, alturaYFecha(c));
    return Semantics(
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: tema.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          Semantics(
            label: hablado(detalle),
            excludeSemantics: true,
            child: Text(detalle, style: tema.bodyLarge),
          ),
        ],
      ),
    );
  }
}

/// El aviso aprobado y la línea sobre la escala, arriba del mapa: se leen
/// antes de mirarlo, sin desplazar.
class _Aviso extends StatelessWidget {
  const _Aviso();

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    return Container(
      key: const ValueKey('caja-aviso-crecidas'),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colores.superficie,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colores.bordeSuave),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(child: Icon(Icons.info_outline, size: 22, color: Colores.tinta)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  textoAvisoCrecidas,
                  key: const ValueKey('aviso-crecidas'),
                  style: tema.bodyLarge?.copyWith(fontWeight: FontWeight.w600, height: 1.35),
                ),
                const SizedBox(height: 6),
                Text(
                  textoEscalaCrecidas,
                  key: const ValueKey('escala-crecidas'),
                  style: tema.bodyMedium?.copyWith(color: Colores.tintaSecundaria),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Marco del mapa: el dibujo, los controles y la fuente.
class _Marco extends StatelessWidget {
  final Widget mapa;
  final Widget controles;

  const _Marco({required this.mapa, required this.controles});

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
            controles,
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Text(textoFuenteCrecidas, style: tema.bodyMedium?.copyWith(color: Colores.tintaSecundaria)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Atribución sobre el mapa. Para TalkBack está en la fuente de abajo.
class _Atribucion extends StatelessWidget {
  final ColoresMapa colores;
  const _Atribucion({required this.colores});

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      color: colores.terreno.withValues(alpha: 0.85),
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.2,
        child: Text(textoAtribucionCrecidas, style: TextStyle(fontSize: 12, color: Colores.tinta)),
      ),
    ),
  );
}

/// Cartelito sobre el mapa (no se toca; TalkBack tiene el resumen).
class _Pista extends StatelessWidget {
  final String texto;
  const _Pista({required this.texto});

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: IgnorePointer(
      child: Align(
        alignment: Alignment.topLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: Colores.tinta, borderRadius: BorderRadius.circular(12)),
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.5,
            child: Text(
              texto,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: Colores.fondo, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Debajo del mapa: "Pantalla completa" y las flechas de 48 dp para moverlo
/// sin arrastrar (WCAG 2.5.7).
class _Controles extends StatelessWidget {
  final void Function(int dx, int dy) alMover;
  final VoidCallback alPantallaCompleta;

  const _Controles({required this.alMover, required this.alPantallaCompleta});

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
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          key: const ValueKey('pantalla-completa'),
          onPressed: alPantallaCompleta,
          style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
          icon: const Icon(Icons.fullscreen),
          label: const Text('Pantalla completa'),
        ),
        Wrap(
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
    style: IconButton.styleFrom(
      backgroundColor: Colores.superficie,
      foregroundColor: Colores.primario,
      // Borde de 1 dp: el botón se distingue del mapa de abajo (3:1).
      side: BorderSide(color: Colores.bordeControl),
    ),
    constraints: const BoxConstraints.tightFor(width: 48, height: 48),
    icon: Icon(icono),
  );
}

/// Una opción de la lista: tocable entera, con marca de elegida (no solo
/// color). Para TalkBack es un botón de radio de un grupo excluyente.
class _Opcion extends StatelessWidget {
  final String titulo;
  final String detalle;

  /// Con "Ver todas": cómo es su línea en el mapa ("trazos", "puntos"…).
  final String? trazo;
  final bool elegida;
  final CustomPainter? muestra;
  final VoidCallback alTocar;

  const _Opcion({
    required this.titulo,
    required this.detalle,
    this.trazo,
    required this.elegida,
    this.muestra,
    required this.alTocar,
  });

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    final enElMapa = trazo == null ? null : 'En el mapa: $trazo.';
    return Semantics(
      checked: elegida,
      inMutuallyExclusiveGroup: true,
      label: [titulo, hablado(detalle), ?enElMapa].join('. '),
      onTap: alTocar,
      excludeSemantics: true,
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
                  Icon(
                    elegida ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    color: elegida ? Colores.primario : Colores.bordeControl,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(titulo, style: tema.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
                        Text(detalle, style: tema.bodyMedium),
                        if (enElMapa != null) Text(enElMapa, style: tema.bodyMedium),
                      ],
                    ),
                  ),
                  if (muestra != null) ...[
                    const SizedBox(width: 8),
                    SizedBox(
                      width: anchoMuestra,
                      height: altoMuestra,
                      child: CustomPaint(painter: muestra),
                    ),
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

/// "Qué muestra el mapa": siempre abierta. Cada línea se nombra con su
/// trazo, no solo con su color.
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
          'Línea continua: hasta dónde llegó el agua en la ${_enMinuscula(e)} '
              '(${alturaSegun(e)}, ${fechaLarga(e.fecha)}).',
        )
      else
        for (final (i, c) in indice.crecidas.indexed)
          if (!sinBorde.contains(c.clave))
            (
              MuestraCrecida(colores, i, todas: true),
              '${conMayuscula(TrazosMapa.nombre(i))}: ${_enMinuscula(c)} (${alturaSegun(c)}, ${fechaLarga(c.fecha)}).',
            ),
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
                      width: anchoMuestra,
                      height: altoMuestra,
                      child: muestra == null
                          ? Align(
                              alignment: Alignment.centerLeft,
                              child: Icon(Icons.info_outline, size: 22, color: Colores.tintaSecundaria),
                            )
                          : CustomPaint(painter: muestra),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Semantics(
                    label: hablado(texto),
                    excludeSemantics: true,
                    child: Text(texto, style: tema.bodyLarge),
                  ),
                ),
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
