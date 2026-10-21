/// Pestaña "Mapa": la costa de Paysandú con hasta dónde llegaría el agua.
///
/// Abre en la altura de hoy (la misma de Inicio y Gráfico, de actual.json),
/// redondeada hacia arriba a 10 cm. Con el deslizador o los botones − / + se
/// prueban otras alturas. Versión funcional: el diseño fino viene después
/// (docs/mapa/03-diseno-visual.md).
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../datos.dart';
import '../mapa/logica_mapa.dart';
import '../mapa/modelos_mapa.dart';
import '../mapa/repositorio_mapa.dart';
import '../modelos.dart';
import '../tema.dart';
import '../textos.dart';
import 'comunes.dart';

/// Atribución que va siempre a la vista sobre el mapa.
const textoAtribucion = '© OpenStreetMap · IDE Uruguay · Dinagua';

/// Aviso corto que va siempre debajo del mapa.
const textoAvisoMapa = 'Aproximado. No reemplaza la alerta oficial.';

const textoMapaNoDisponible = 'El mapa todavía no está disponible';

/// Alto del mapa en la pantalla.
const altoMapa = 320.0;

/// La altura del río que el mapa puede usar como "hoy".
class HoyMapa {
  /// null si no hay un dato que se pueda pintar (ver [motivo]).
  final Lectura? lectura;
  final Nivel nivel;
  final bool viejo;
  final bool sinConexion;

  /// Por qué no hay "hoy": 'sin_dato' o 'cero' (el mapa usa otra referencia).
  final String? motivo;

  /// Avisos del lector que conviene repetir (por ejemplo dato_a_verificar).
  final List<String> avisos;

  const HoyMapa({
    this.lectura,
    this.nivel = Nivel.sinDato,
    this.viejo = false,
    this.sinConexion = false,
    this.motivo,
    this.avisos = const [],
  });

  bool get hay => lectura != null;
}

/// Decide qué altura de hoy se puede pintar, con los mismos criterios que
/// Inicio: nivel vigente, dato viejo, sin conexión, y además que el mapa y
/// actual.json usen el mismo cero.
HoyMapa hoyParaMapa(Datos? datos, Config config, IndiceMapa indice, DateTime ahora) {
  final actual = datos?.actual;
  final altura = actual?.altura;
  final sinConexion = datos?.sinConexion ?? false;
  if (actual == null || altura == null) return HoyMapa(sinConexion: sinConexion, motivo: 'sin_dato');
  // Misma regla que nivelVigente (dato muy viejo o posterior a "generado"),
  // aunque el lector no haya podido calcular el nivel.
  final usable =
      Actual(altura: altura, generado: actual.generado, nivel: Nivel.normal).nivelVigente(ahora, config.horasSinDato) !=
          Nivel.sinDato;
  if (!usable) return HoyMapa(sinConexion: sinConexion, motivo: 'sin_dato');
  if (actual.cero != indice.cero) return HoyMapa(sinConexion: sinConexion, motivo: 'cero');
  return HoyMapa(
    lectura: altura,
    nivel: actual.nivelVigente(ahora, config.horasSinDato),
    viejo: ahora.difference(altura.fecha).inMinutes / 60 > config.horasAvisoDatoViejo,
    sinConexion: sinConexion,
    avisos: actual.avisos,
  );
}

class PantallaMapa extends StatefulWidget {
  final Datos? datos;
  final Config config;
  final RepositorioMapa repositorio;

  /// Solo para pruebas: permite fijar la hora actual.
  final DateTime? ahora;

  const PantallaMapa({super.key, required this.datos, required this.config, required this.repositorio, this.ahora});

  @override
  State<PantallaMapa> createState() => _PantallaMapaState();
}

enum _Carga { cargando, lista, noDisponible }

class _PantallaMapaState extends State<PantallaMapa> {
  _Carga _carga = _Carga.cargando;
  IndiceMapa? _indice;
  BaseMapa? _base;

  /// Altura elegida en cm (múltiplo del paso). null hasta tener datos.
  int? _cm;

  /// true mientras la altura elegida sigue a la de hoy (si llega un dato
  /// nuevo, el mapa se mueve con él).
  bool _siguiendoHoy = true;

  /// Lo que está pintado ahora (de la última carga terminada).
  EleccionAgua? _eleccion;
  CapaElegida? _capa;
  CapaElegida? _margen;
  int _turno = 0;

  final _controlador = MapController();
  final _rotulos = _CacheRotulos();
  final _poligonos = <(int, bool), List<Polygon>>{};
  List<Polygon> _cauce = const [];
  List<Polyline> _calles = const [];
  List<Polyline> _cursos = const [];
  List<_Rotulo> _candidatos = const [];

  DateTime get _ahora => widget.ahora ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  @override
  void dispose() {
    _controlador.dispose();
    super.dispose();
  }

  Future<void> _iniciar() async {
    final e = await widget.repositorio.indice();
    if (e is! IndiceListo) {
      if (mounted) setState(() => _carga = _Carga.noDisponible);
      return;
    }
    final base = await widget.repositorio.base();
    if (!mounted) return;
    if (base == null) {
      setState(() => _carga = _Carga.noDisponible);
      return;
    }
    _indice = e.indice;
    _base = base;
    _armarFondo(base);
    setState(() => _carga = _Carga.lista);
    _elegirInicial();
  }

  @override
  void didUpdateWidget(PantallaMapa anterior) {
    super.didUpdateWidget(anterior);
    // Llegó un dato nuevo del río: si se está mirando "hoy", se sigue.
    if (anterior.datos != widget.datos && _indice != null && (_cm == null || _siguiendoHoy)) _elegirInicial();
  }

  HoyMapa? get _hoy => _indice == null ? null : hoyParaMapa(widget.datos, widget.config, _indice!, _ahora);

  int? get _hoyCm {
    final h = _hoy?.lectura;
    return h == null ? null : redondearArriba(h.valorM, pasoCm: _indice!.pasoCm);
  }

  /// Abre en la altura de hoy; sin un dato confiable, en el nivel de alerta
  /// (o en la capa más baja si no hay umbral).
  void _elegirInicial() {
    if (widget.datos == null) return; // todavía cargando el nivel del río
    final ind = _indice!;
    final hoy = _hoyCm;
    final alerta = widget.datos?.umbrales?.alertaM;
    final cm = hoy ?? (alerta != null ? redondearArriba(alerta, pasoCm: ind.pasoCm) : ind.minCm);
    _siguiendoHoy = hoy != null;
    _ir(cm, anunciar: false);
  }

  (int, int) get _rango {
    final ind = _indice!;
    final hoy = _hoyCm;
    final bajo = math.min(ind.minCm - ind.pasoCm, hoy ?? 1 << 30);
    final alto = math.max(ind.maxCm, hoy ?? 0);
    return (math.max(0, bajo), alto);
  }

  void _ir(int cm, {bool anunciar = true}) {
    final (bajo, alto) = _rango;
    final nuevo = cm.clamp(bajo, alto);
    setState(() {
      _cm = nuevo;
      _siguiendoHoy = nuevo == _hoyCm;
    });
    _cargarCapas(anunciar: anunciar);
  }

  Future<void> _cargarCapas({required bool anunciar}) async {
    final ind = _indice!, cm = _cm!;
    final turno = ++_turno;
    final e = elegirAgua(cm, ind);
    final capa = e.capaCm == null ? null : await widget.repositorio.capa(e.capaCm!);
    final margen = e.margenCm == null ? null : await widget.repositorio.capa(e.margenCm!);
    if (!mounted || turno != _turno) return; // ya se pidió otra altura
    setState(() {
      _eleccion = e;
      _capa = capa;
      _margen = margen;
    });
    if (anunciar) {
      SemanticsService.sendAnnouncement(View.of(context), _textoAnuncio(), TextDirection.ltr);
    }
  }

  String _textoAnuncio() {
    final e = _eleccion!;
    final altura = formatoAltura(e.alturaCm / 100);
    return switch (e.situacion) {
      SituacionAgua.enCauce => 'Con $altura metros el agua queda en su cauce.',
      SituacionAgua.enRango => 'Se muestra el agua con $altura metros.',
      SituacionAgua.sobreMaximo =>
        'El río supera lo que cubre el mapa. Se muestra el agua con ${formatoAltura(_indice!.maxCm / 100)} metros.',
    };
  }

  // ----- Fondo -----

  void _armarFondo(BaseMapa base) {
    final c = _ColoresMapa.actuales();
    _cauce = [
      for (final p in base.agua)
        Polygon(points: p.exterior, holePointsList: p.huecos, color: c.cauce, borderStrokeWidth: 0),
    ];
    final calles = [...base.calles]..sort((a, b) => b.clase.compareTo(a.clase)); // las principales, arriba
    _calles = [
      for (final t in calles)
        for (final l in t.lineas)
          Polyline(points: l.puntos, color: c.calle(t.clase), strokeWidth: switch (t.clase) { 1 => 4.0, 2 => 3.0, _ => 1.6 }),
    ];
    _cursos = [
      for (final t in base.cursos)
        for (final l in t.lineas) Polyline(points: l.puntos, color: c.cauce, strokeWidth: 2.2),
    ];
    _candidatos = _armarRotulos(base);
  }

  List<Polygon> _poligonosDe(CapaElegida capa, {required bool margen}) {
    final clave = (capa.alturaCm, margen);
    final c = _ColoresMapa.actuales();
    return _poligonos[clave] ??= [
      for (final p in capa.capa.poligonos)
        Polygon(
          points: p.exterior,
          holePointsList: p.huecos,
          color: margen ? c.margen : c.agua,
          borderColor: c.bordeAgua,
          borderStrokeWidth: margen ? 1.6 : 1.4,
          pattern: margen ? StrokePattern.dotted(spacingFactor: 2.5) : const StrokePattern.solid(),
        ),
    ];
  }

  // ----- Pantalla -----

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    if (widget.datos == null && _carga != _Carga.noDisponible) {
      return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Cargando el nivel del río…')));
    }
    switch (_carga) {
      case _Carga.cargando:
        // Sin ruedita que gira: el texto alcanza y no consume batería.
        return Center(
          child: Semantics(
            liveRegion: true,
            child: Padding(padding: const EdgeInsets.all(24), child: Text('Preparando el mapa…', style: tema.bodyLarge)),
          ),
        );
      case _Carga.noDisponible:
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Semantics(header: true, child: Text(textoMapaNoDisponible, style: tema.titleLarge)),
            const SizedBox(height: 12),
            Text('La altura del río sigue en Inicio y en Gráfico.', style: tema.bodyLarge),
          ],
        );
      case _Carga.lista:
        break;
    }
    final ind = _indice!;
    final hoy = _hoy!;
    final cm = _cm;
    final eleccion = _eleccion;
    final umbrales = widget.datos?.umbrales;
    final apoyo = tema.bodyMedium?.copyWith(color: Colores.tintaSecundaria);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        if (ind.modelo.esProvisorio) ...[
          const Recuadro(
            icono: Icons.science_outlined,
            texto: 'Datos de prueba: el agua de este mapa es inventada. No la uses para decidir nada.',
          ),
          const SizedBox(height: 12),
        ],
        _FranjaHoy(hoy: hoy, ahora: _ahora),
        if (_aviso(hoy) case final aviso?) ...[
          const SizedBox(height: 12),
          Recuadro(icono: aviso.$1, texto: aviso.$2),
        ],
        const SizedBox(height: 16),
        if (cm != null && eleccion != null)
          _Lectura(
            eleccion: eleccion,
            indice: ind,
            hoyCm: _hoyCm,
            umbrales: umbrales,
            capa: _capa,
            alVolverAHoy: _hoyCm == null || cm == _hoyCm ? null : () => _ir(_hoyCm!),
          ),
        const SizedBox(height: 12),
        _mapa(ind, eleccion),
        const SizedBox(height: 12),
        if (cm != null) _control(ind, cm),
        const SizedBox(height: 16),
        const _Leyenda(),
        const Separador(),
        Text(textoAvisoMapa, style: tema.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Muestra hasta dónde podría llegar el río con esa altura, según el terreno. '
          'No tiene en cuenta la lluvia, los desagües ni las calles cortadas. '
          'Ante una evacuación, seguí las indicaciones del Cecoed.',
          style: tema.bodyMedium,
        ),
        if (!ind.validado && !ind.modelo.esProvisorio) ...[
          const SizedBox(height: 8),
          Text('El mapa todavía no fue validado con crecidas reales.', style: apoyo),
        ],
        const SizedBox(height: 12),
        Semantics(header: true, child: Text('Fuentes', style: tema.titleMedium)),
        const SizedBox(height: 4),
        for (final f in ind.fuentes.isEmpty ? const [textoAtribucion] : ind.fuentes) Text(f, style: apoyo),
        if (ind.generado != null) Text('Mapa armado el ${formatoDia(enHoraUruguay(ind.generado!))}.', style: apoyo),
      ],
    );
  }

  /// El aviso más grave del dato de hoy (uno solo, como pide el diseño).
  (IconData, String)? _aviso(HoyMapa hoy) {
    final cuando = hoy.lectura == null ? null : formatoFecha(hoy.lectura!.fecha, _ahora);
    if (hoy.motivo == 'cero') {
      return (
        Icons.straighten,
        'El mapa usa otra referencia de altura que el dato del río, así que no se pinta el río de hoy. '
            'Igual podés elegir una altura.'
      );
    }
    if (!hoy.hay) {
      return (
        Icons.help_outline,
        '${hoy.sinConexion ? 'Sin conexión y sin' : 'No hay'} un dato confiable de hoy. '
            'Igual podés elegir una altura para ver hasta dónde llegaría el agua.'
      );
    }
    if (hoy.viejo) return (Icons.schedule, 'El último dato es de $cuando. El río pudo cambiar.');
    if (hoy.sinConexion) {
      return (Icons.wifi_off, 'Sin conexión. El mapa funciona igual, pero el dato del río es el último guardado ($cuando).');
    }
    if (hoy.avisos.contains('dato_a_verificar')) return (Icons.warning_amber, textoAviso('dato_a_verificar')!);
    return null;
  }

  Widget _mapa(IndiceMapa ind, EleccionAgua? eleccion) {
    final c = _ColoresMapa.actuales();
    final limites = LatLngBounds(ind.surOeste, ind.norEste);
    final lugares = _base!.lugares;
    // Arranca en el centro de los barrios (la ciudad), no en todo el recorte.
    final centro = lugares.isEmpty
        ? limites.center
        : LatLng(lugares.map((l) => l.punto.latitude).reduce((a, b) => a + b) / lugares.length,
            lugares.map((l) => l.punto.longitude).reduce((a, b) => a + b) / lugares.length);
    final margen = _margen, capa = _capa;
    final altura = eleccion == null ? '' : formatoAltura((eleccion.capaCm ?? eleccion.alturaCm) / 100);
    final descripcion = 'Mapa de la costa de Paysandú, con el río, las calles y los barrios. '
        '${eleccion == null ? '' : eleccion.situacion == SituacionAgua.enCauce ? 'Con esta altura el agua queda en su cauce. ' : 'Agua dibujada con $altura metros. '}'
        'Es aproximado.';
    return Semantics(
      container: true,
      image: true,
      label: descripcion,
      child: ClipRRect(
        borderRadius: radioSuperficie,
        child: SizedBox(
          height: altoMapa,
          child: Stack(
            children: [
              ExcludeSemantics(
                child: FlutterMap(
                  mapController: _controlador,
                  options: MapOptions(
                    initialCenter: centro,
                    initialZoom: 13.5,
                    minZoom: 11,
                    maxZoom: 18,
                    backgroundColor: c.terreno,
                    cameraConstraint: CameraConstraint.containCenter(bounds: limites),
                    interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
                  ),
                  children: [
                    PolygonLayer(polygons: _cauce),
                    if (margen != null) PolygonLayer(polygons: _poligonosDe(margen, margen: true)),
                    if (capa != null) PolygonLayer(polygons: _poligonosDe(capa, margen: false)),
                    PolylineLayer(polylines: _calles),
                    PolylineLayer(polylines: _cursos),
                    _CapaRotulos(candidatos: _candidatos, cache: _rotulos, colores: c),
                  ],
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
                    child: Text(textoAtribucion, style: TextStyle(fontSize: 12, color: Colores.tinta)),
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
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _zoom(double cuanto) {
    final cam = _controlador.camera;
    _controlador.move(cam.center, cam.clampZoom(cam.zoom + cuanto));
  }

  Widget _control(IndiceMapa ind, int cm) {
    final (bajo, alto) = _rango;
    final paso = ind.pasoCm;
    final pasoTexto = formatoDiferencia(paso / 100);
    return Row(
      children: [
        _BotonPaso(
          icono: Icons.remove,
          texto: 'Bajar $pasoTexto',
          alTocar: cm - paso >= bajo ? () => _ir(cm - paso) : null,
        ),
        Expanded(
          child: Slider(
            value: cm.toDouble(),
            min: bajo.toDouble(),
            max: alto.toDouble(),
            divisions: math.max(1, (alto - bajo) ~/ paso),
            semanticFormatterCallback: (v) => '${formatoAltura(v.round() / 100)} metros',
            onChanged: (v) {
              final nuevo = bajo + ((v.round() - bajo) / paso).round() * paso;
              if (nuevo != _cm) _ir(nuevo, anunciar: false);
            },
            onChangeEnd: (_) => _cargarCapas(anunciar: true),
          ),
        ),
        _BotonPaso(
          icono: Icons.add,
          texto: 'Subir $pasoTexto',
          alTocar: cm + paso <= alto ? () => _ir(cm + paso) : null,
        ),
      ],
    );
  }

  // ----- Rótulos -----

  List<_Rotulo> _armarRotulos(BaseMapa base) {
    final lista = <_Rotulo>[
      for (final l in base.lugares) _Rotulo(l.nombre, 0, 12.5, l.punto, null, null, 0),
    ];
    void tramos(List<TramoConNombre> ts, int Function(int clase) prioridad, double Function(int clase) zoom) {
      for (final t in ts) {
        final nombre = t.nombre;
        if (nombre == null) continue;
        for (final l in t.lineas) {
          final r = _medio(l.puntos);
          if (r == null || r.$4 < 60) continue; // tramos muy cortos no llevan nombre
          lista.add(_Rotulo(nombre, prioridad(t.clase), zoom(t.clase), r.$1, r.$2, r.$3, r.$4));
        }
      }
    }

    tramos(base.cursos, (_) => 1, (_) => 13.5);
    tramos(base.calles, (k) => k + 1, (k) => switch (k) { 1 => 14.0, 2 => 14.5, _ => 15.5 });
    lista.sort((a, b) => a.prioridad != b.prioridad ? a.prioridad - b.prioridad : b.largoM.compareTo(a.largoM));
    return lista;
  }
}

/// Punto medio de una línea (por largo), el tramo donde cae y el largo en metros.
(LatLng, LatLng, LatLng, double)? _medio(List<LatLng> pts) {
  const d = Distance();
  final tramos = [for (var i = 1; i < pts.length; i++) d.as(LengthUnit.Meter, pts[i - 1], pts[i])];
  final total = tramos.fold<double>(0, (a, b) => a + b);
  if (total <= 0) return null;
  var falta = total / 2;
  for (var i = 0; i < tramos.length; i++) {
    if (falta <= tramos[i] || i == tramos.length - 1) {
      final f = tramos[i] == 0 ? 0.0 : (falta / tramos[i]).clamp(0.0, 1.0);
      final a = pts[i], b = pts[i + 1];
      final medio = LatLng(a.latitude + (b.latitude - a.latitude) * f, a.longitude + (b.longitude - a.longitude) * f);
      return (medio, a, b, total);
    }
    falta -= tramos[i];
  }
  return null;
}

/// Colores del mapa. El agua es siempre azul; el nivel va en texto.
class _ColoresMapa {
  final Color terreno, cauce, agua, margen, bordeAgua, halo, texto, textoCurso;
  final List<Color> _calles;

  const _ColoresMapa(this.terreno, this.cauce, this.agua, this.margen, this.bordeAgua, this.halo, this.texto,
      this.textoCurso, this._calles);

  Color calle(int clase) => _calles[(clase - 1).clamp(0, 2)];

  static _ColoresMapa actuales() => Colores.oscuro
      ? const _ColoresMapa(Color(0xFF1B2A37), Color(0xFF0F4C85), Color(0x736CB4FF), Color(0x336CB4FF),
          Color(0xFFD6ECFF), Color(0xFF1B2A37), Color(0xFFEAF2F8), Color(0xFF9CCBFF),
          [Color(0xFF7D95AB), Color(0xFF5F7890), Color(0xFF3E566D)])
      : const _ColoresMapa(Color(0xFFF3F0E8), Color(0xFF2F6FAD), Color(0x8C3D8BD9), Color(0x383D8BD9),
          Color(0xFF0B3C5D), Color(0xFFF3F0E8), Color(0xFF0B2A3F), Color(0xFF1D4F80),
          [Color(0xFF9C9079), Color(0xFFB4AA96), Color(0xFFD3CCBE)]);
}

// ---------------------------------------------------------------------------
// Bloques de la pantalla

class _FranjaHoy extends StatelessWidget {
  final HoyMapa hoy;
  final DateTime ahora;

  const _FranjaHoy({required this.hoy, required this.ahora});

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    final l = hoy.lectura;
    if (l == null) {
      return Semantics(
        container: true,
        child: Text('Río hoy: sin dato confiable', style: tema.titleLarge),
      );
    }
    final estilo = estiloNivel(hoy.nivel);
    final color = ColoresNivel.familia(hoy.nivel);
    final rotulo = hoy.viejo || hoy.sinConexion ? 'Último dato' : 'Río hoy';
    final cuando = formatoFecha(l.fecha, ahora);
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: '$rotulo: ${formatoAltura(l.valorM)} metros. Nivel: ${estilo.nombre}. '
          'Medido $cuando. Fuente: ${fuenteCorta(l.fuente)}.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Text('$rotulo: ${formatoAltura(l.valorM)} m', style: tema.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              // Ícono y palabra en un mismo texto: con letra muy grande, baja de renglón.
              Text.rich(
                TextSpan(children: [
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(estilo.icono, color: color, size: 24),
                    ),
                  ),
                  TextSpan(text: estilo.nombre),
                ]),
                style: tema.titleLarge?.copyWith(color: color, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          Text('${conMayuscula(cuando)} · ${fuenteCorta(l.fuente)}', style: tema.bodyMedium),
        ],
      ),
    );
  }
}

class _Lectura extends StatelessWidget {
  final EleccionAgua eleccion;
  final IndiceMapa indice;
  final int? hoyCm;
  final Umbrales? umbrales;
  final CapaElegida? capa;
  final VoidCallback? alVolverAHoy;

  const _Lectura({
    required this.eleccion,
    required this.indice,
    required this.hoyCm,
    required this.umbrales,
    required this.capa,
    required this.alVolverAHoy,
  });

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    final e = eleccion;
    final metros = e.alturaCm / 100;
    final pintada = (e.capaCm ?? e.alturaCm) / 100;
    final u = umbrales;
    final nivel = u == null ? null : nivelSegunUmbrales(metros, u);
    final esHoy = hoyCm != null && e.alturaCm == hoyCm;
    final linea = switch (e.situacion) {
      SituacionAgua.enCauce => 'Con ${formatoAltura(metros)} m el agua queda en su cauce: '
          'el mapa no muestra agua sobre la tierra.',
      SituacionAgua.sobreMaximo => 'El río supera lo que cubre el mapa (hasta ${formatoAltura(indice.maxCm / 100)} m). '
          'Se muestra el agua con ese máximo.',
      SituacionAgua.enRango => null,
    };
    final c = capa;
    final reemplazo = c != null && c.reemplazada
        ? 'No se pudo leer el dibujo de ${formatoAltura(c.pedidaCm / 100)} m; '
            'se muestra el de ${formatoAltura(c.alturaCm / 100)} m.'
        : e.capaCm != null && c == null
            ? 'No se pudo leer el dibujo del agua para esta altura.'
            : null;
    final mostrada = c?.alturaCm ?? (e.capaCm ?? e.alturaCm);
    final principal = e.situacion == SituacionAgua.enCauce
        ? 'Altura elegida: ${formatoAltura(metros)} m'
        : 'Se muestra el agua con ${formatoAltura(mostrada / 100)} m';
    return Semantics(
      container: true,
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.6,
            child: Text(principal,
                style: tema.headlineMedium?.copyWith(fontSize: 26, fontFeatures: const [FontFeature.tabularFigures()])),
          ),
          if (nivel != null && e.situacion != SituacionAgua.enCauce) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(estiloNivel(nivel).icono, color: ColoresNivel.familia(nivel), size: 22),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Con ${formatoAltura(pintada)} m: nivel ${estiloNivel(nivel).nombre}'
                    '${u!.validado ? '' : ' (de referencia)'}',
                    style: tema.bodyLarge,
                  ),
                ),
              ],
            ),
          ],
          if (linea != null) ...[const SizedBox(height: 6), Text(linea, style: tema.bodyLarge)],
          if (reemplazo != null) ...[const SizedBox(height: 6), Text(reemplazo, style: tema.bodyLarge)],
          if (esHoy && hoyCm != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Es la altura de hoy, redondeada hacia arriba a ${formatoDiferencia(indice.pasoCm / 100)}.',
                  style: tema.bodyMedium?.copyWith(color: Colores.tintaSecundaria)),
            ),
          if (!esHoy && hoyCm != null) ...[
            const SizedBox(height: 8),
            Text(
              'No es el río de hoy: es una prueba con ${formatoAltura(metros)} m '
              '(${formatoDiferencia((e.alturaCm - hoyCm!) / 100)} ${e.alturaCm > hoyCm! ? 'más' : 'menos'} que hoy).',
              style: tema.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
          if (alVolverAHoy != null) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(onPressed: alVolverAHoy, icon: const Icon(Icons.undo), label: const Text('Volver a hoy')),
          ],
        ],
      ),
    );
  }
}

class _BotonPaso extends StatelessWidget {
  final IconData icono;
  final String texto;
  final VoidCallback? alTocar;

  const _BotonPaso({required this.icono, required this.texto, required this.alTocar});

  @override
  Widget build(BuildContext context) => IconButton.filledTonal(
        tooltip: texto,
        onPressed: alTocar,
        constraints: const BoxConstraints.tightFor(width: 56, height: 56),
        icon: Icon(icono, size: 28),
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

class _Leyenda extends StatelessWidget {
  const _Leyenda();

  @override
  Widget build(BuildContext context) {
    final c = _ColoresMapa.actuales();
    final tema = Theme.of(context).textTheme;
    Widget fila(Widget muestra, String texto) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              ExcludeSemantics(child: SizedBox(width: 36, height: 22, child: muestra)),
              const SizedBox(width: 12),
              Expanded(child: Text(texto, style: tema.bodyLarge)),
            ],
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(header: true, child: Text('Cómo leer el mapa', style: tema.titleMedium)),
        fila(ColoredBox(color: c.cauce), 'Río y arroyos, en su cauce'),
        fila(
            DecoratedBox(
                decoration:
                    BoxDecoration(color: Color.alphaBlend(c.agua, c.terreno), border: Border.all(color: c.bordeAgua, width: 1.4))),
            'Hasta dónde llegaría el agua (borde continuo)'),
        fila(CustomPaint(painter: _MuestraMargen(c)), 'Puede llegar un poco más (borde de puntos)'),
      ],
    );
  }
}

class _MuestraMargen extends CustomPainter {
  final _ColoresMapa c;
  _MuestraMargen(this.c);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Color.alphaBlend(c.margen, c.terreno));
    final punto = Paint()..color = c.bordeAgua;
    for (var x = 2.0; x < size.width; x += 6) {
      canvas.drawCircle(Offset(x, 1.5), 1.3, punto);
      canvas.drawCircle(Offset(x, size.height - 1.5), 1.3, punto);
    }
    for (var y = 2.0; y < size.height; y += 6) {
      canvas.drawCircle(Offset(1.5, y), 1.3, punto);
      canvas.drawCircle(Offset(size.width - 1.5, y), 1.3, punto);
    }
  }

  @override
  bool shouldRepaint(_MuestraMargen old) => false;
}

// ---------------------------------------------------------------------------
// Rótulos: nombres de barrios, arroyos y calles, sin pisarse.

class _Rotulo {
  final String texto;

  /// 0 barrio · 1 arroyo · 2 principal · 3 avenida · 4 calle.
  final int prioridad;
  final double zoomMin;
  final LatLng punto;

  /// Tramo donde va el nombre (para girarlo como la calle); null en barrios.
  final LatLng? a, b;
  final double largoM;

  const _Rotulo(this.texto, this.prioridad, this.zoomMin, this.punto, this.a, this.b, this.largoM);
}

/// Textos ya medidos, para no medir cientos de nombres en cada cuadro.
class _CacheRotulos {
  final _textos = <(String, int, double), TextPainter>{};

  TextPainter texto(String t, int prioridad, double escala, _ColoresMapa c, {required bool halo}) {
    final clave = (t, prioridad * 2 + (halo ? 1 : 0), escala);
    return _textos[clave] ??= () {
      final base = switch (prioridad) {
        0 => const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 0.3),
        1 => const TextStyle(fontSize: 12.5, fontStyle: FontStyle.italic, fontWeight: FontWeight.w600),
        2 || 3 => const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
        _ => const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500),
      };
      final color = prioridad == 1 ? c.textoCurso : c.texto;
      final estilo = halo
          ? base.copyWith(
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 3.5
                ..strokeJoin = StrokeJoin.round
                ..color = c.halo)
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

class _CapaRotulos extends StatelessWidget {
  final List<_Rotulo> candidatos;
  final _CacheRotulos cache;
  final _ColoresMapa colores;

  const _CapaRotulos({required this.candidatos, required this.cache, required this.colores});

  @override
  Widget build(BuildContext context) {
    final camara = MapCamera.of(context);
    // Los nombres crecen con la letra del teléfono, con tope para que entren.
    final escala = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3).scale(1);
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _PintorRotulos(camara, candidatos, cache, colores, escala),
      ),
    );
  }
}

class _PintorRotulos extends CustomPainter {
  final MapCamera camara;
  final List<_Rotulo> candidatos;
  final _CacheRotulos cache;
  final _ColoresMapa c;
  final double escala;

  _PintorRotulos(this.camara, this.candidatos, this.cache, this.c, this.escala);

  /// Tope de nombres a la vez: más que esto es ruido en un celular.
  static const maximo = 70;

  /// Distancia mínima entre dos rótulos con el mismo nombre (en píxeles).
  static const separacionMismoNombre = 260.0;

  @override
  void paint(Canvas canvas, Size size) {
    final zoom = camara.zoom;
    final pantalla = Offset.zero & size;
    final ocupados = <Rect>[];
    final porNombre = <String, List<Offset>>{};
    for (final r in candidatos) {
      if (ocupados.length >= maximo) break;
      if (zoom < r.zoomMin) continue;
      final p = camara.getOffsetFromOrigin(r.punto);
      if (!pantalla.inflate(-8).contains(p)) continue;
      final texto = cache.texto(r.texto, r.prioridad, escala, c, halo: false);
      final w = texto.width, h = texto.height;
      var angulo = 0.0;
      if (r.a != null && r.b != null) {
        final pa = camara.getOffsetFromOrigin(r.a!), pb = camara.getOffsetFromOrigin(r.b!);
        // El nombre no puede ser más largo que el tramo de calle que se ve.
        final largoPantalla = r.largoM / _metrosPorPixel(r.punto.latitude, zoom);
        if (largoPantalla < w * 1.1) continue;
        angulo = math.atan2(pb.dy - pa.dy, pb.dx - pa.dx);
        if (angulo > math.pi / 2) angulo -= math.pi;
        if (angulo < -math.pi / 2) angulo += math.pi;
      }
      final cos = math.cos(angulo).abs(), sin = math.sin(angulo).abs();
      final caja = Rect.fromCenter(center: p, width: w * cos + h * sin, height: w * sin + h * cos).inflate(3);
      if (!pantalla.contains(caja.topLeft) || !pantalla.contains(caja.bottomRight)) continue;
      if (ocupados.any((o) => o.overlaps(caja))) continue;
      final cerca = porNombre[r.texto];
      if (cerca != null && cerca.any((q) => (q - p).distance < separacionMismoNombre)) continue;
      ocupados.add(caja);
      (porNombre[r.texto] ??= []).add(p);
      canvas.save();
      canvas.translate(p.dx, p.dy);
      canvas.rotate(angulo);
      final origen = Offset(-w / 2, -h / 2);
      cache.texto(r.texto, r.prioridad, escala, c, halo: true).paint(canvas, origen);
      texto.paint(canvas, origen);
      canvas.restore();
    }
  }

  /// Metros por píxel lógico en Web Mercator a esa latitud y zoom.
  static double _metrosPorPixel(double lat, double zoom) =>
      156543.03392 * math.cos(lat * math.pi / 180) / math.pow(2, zoom);

  @override
  bool shouldRepaint(_PintorRotulos old) => old.camara != camara || old.candidatos != candidatos || old.escala != escala;
}
