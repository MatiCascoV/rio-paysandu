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
import '../mapa/estilo_mapa.dart';
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

/// Aviso cuando el índice dice `validado: false` (el caso de los datos reales
/// hasta que se comparen con crecidas medidas y los revise alguien de afuera).
const textoMapaEnPrueba =
    'Mapa aproximado, en prueba: todavía no se comprobó con suficientes crecidas reales. '
    'El agua puede llegar más lejos de lo que muestra.';

/// Aviso cuando los archivos son los provisorios (agua inventada).
const textoMapaProvisorio = 'Datos de prueba: el agua de este mapa es inventada. No la uses para decidir nada.';

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

  /// true si la persona eligió otra altura que la de apertura. Mientras sea
  /// false, si llega un dato nuevo del río (o aparece uno que faltaba) el
  /// mapa se mueve con él.
  bool _elegidaPorUsuario = false;

  /// Crecida real elegida con su botón (para ofrecer su contorno medido).
  ReferenciaMapa? _referencia;
  bool _verContorno = false;
  CurvaMapa? _curva;
  bool _curvaFallo = false;

  /// Por qué no hay mapa (para el texto); null si es que faltan los archivos.
  String? _motivoNoDisponible;

  /// Lo que está pintado ahora (de la última carga terminada).
  EleccionAgua? _eleccion;
  CapaElegida? _capa;
  CapaElegida? _margen;
  int _turno = 0;

  final _controlador = MapController();
  final _rotulos = CacheRotulos();
  final _poligonos = <(int, bool), List<Polygon>>{};

  /// Contorno del agua visible ya proyectado, para el rayado (uno solo).
  (int, TrazadoAgua)? _rayado;

  /// Paleta con la que se armó el fondo (si cambia el tema, se rearma).
  ColoresMapa? _coloresFondo;
  List<Polygon> _cauce = const [];
  List<Polygon> _contorno = const [];
  List<Polyline> _calles = const [];
  List<Polyline> _cursos = const [];
  List<Rotulo> _candidatos = const [];

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
    final repo = widget.repositorio;
    final e = await repo.indice();
    if (!mounted || repo != widget.repositorio) return; // llegó otro repositorio mientras tanto
    if (e is! IndiceListo) {
      setState(() => _carga = _Carga.noDisponible);
      return;
    }
    final base = await repo.base();
    if (!mounted || repo != widget.repositorio) return;
    if (base == null) {
      setState(() => _carga = _Carga.noDisponible);
      return;
    }
    if (e.indice.cero != ceroDelMapa) {
      // Otra escala de alturas: pintar el agua sería mostrar algo falso.
      setState(() {
        _carga = _Carga.noDisponible;
        _motivoNoDisponible =
            'El mapa usa otra referencia de altura ("${e.indice.cero}") que la escala de CARU, '
            'así que no se dibuja el agua.';
      });
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
    if (anterior.repositorio != widget.repositorio) {
      // Otros archivos del mapa: se arma todo de nuevo.
      _carga = _Carga.cargando;
      _indice = null;
      _base = null;
      _cm = null;
      _eleccion = null;
      _capa = _margen = null;
      _elegidaPorUsuario = false;
      _referencia = null;
      _verContorno = false;
      _curva = null;
      _contorno = const [];
      _motivoNoDisponible = null;
      _poligonos.clear();
      _rayado = null;
      _turno++;
      _iniciar();
      return;
    }
    // Llegó un dato nuevo del río: si se está mirando "hoy", se sigue.
    if (anterior.datos != widget.datos && _indice != null && (_cm == null || !_elegidaPorUsuario || _cm == _hoyCm)) {
      _elegirInicial();
    }
  }

  HoyMapa? get _hoy => _indice == null ? null : hoyParaMapa(widget.datos, widget.config, _indice!, _ahora);

  int? get _hoyCm {
    final h = _hoy?.lectura;
    return h == null ? null : redondearArriba(h.valorM, pasoCm: _indice!.pasoCm);
  }

  /// Umbrales de CARU que se pueden usar en el mapa: si actual.json viene en
  /// otra escala que el mapa, tampoco se usan (vienen del mismo lector).
  Umbrales? get _umbrales => _hoy?.motivo == 'cero' ? null : widget.datos?.umbrales;

  /// Abre en la altura de hoy; sin un dato confiable, en el nivel de alerta
  /// (o en la capa más baja si no hay umbral).
  void _elegirInicial() {
    if (widget.datos == null) return; // todavía cargando el nivel del río
    final ind = _indice!;
    final hoy = _hoyCm;
    final alerta = _umbrales?.alertaM;
    final cm = hoy ?? (alerta != null ? redondearArriba(alerta, pasoCm: ind.pasoCm) : ind.minCm);
    _ir(cm, anunciar: false, usuario: false);
  }

  (int, int) get _rango {
    final ind = _indice!;
    final hoy = _hoyCm;
    final bajo = math.min(ind.minCm - ind.pasoCm, hoy ?? 1 << 30);
    final alto = math.max(ind.maxCm, hoy ?? 0);
    return (math.max(0, bajo), alto);
  }

  void _ir(int cm, {bool anunciar = true, bool usuario = true, ReferenciaMapa? referencia}) {
    final (bajo, alto) = _rango;
    final nuevo = cm.clamp(bajo, alto);
    setState(() {
      _cm = nuevo;
      _elegidaPorUsuario = usuario && nuevo != _hoyCm;
      if (referencia != _referencia) {
        _referencia = referencia;
        _verContorno = false;
        _curva = null;
        _curvaFallo = false;
        _contorno = const [];
      }
    });
    _cargarCapas(anunciar: anunciar);
  }

  Future<void> _mostrarContorno(bool ver) async {
    final ref = _referencia;
    setState(() => _verContorno = ver);
    if (!ver || ref == null || _curva != null) return;
    final curva = await widget.repositorio.curva(ref);
    if (!mounted || ref != _referencia) return;
    setState(() {
      _curva = curva;
      _curvaFallo = curva == null;
      _contorno = poligonosContorno(curva?.poligonos ?? const [], ColoresMapa.actuales());
    });
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
      // Solo quedan armados los polígonos que se ven: lo demás lo guarda (con
      // tope) el repositorio, y así la memoria no crece con cada altura.
      _poligonos.removeWhere((k, _) => k != (capa?.alturaCm, false) && k != (margen?.alturaCm, true));
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

  /// Arma el fondo (cauce, calles, arroyos y nombres) con la paleta actual.
  /// El estilo está en mapa/estilo_mapa.dart.
  void _armarFondo(BaseMapa base) {
    final c = _coloresFondo = ColoresMapa.actuales();
    _cauce = poligonosCauce(base, c);
    _calles = lineasCalles(base, c);
    _cursos = lineasCursos(base, c);
    _candidatos = armarRotulos(base);
  }

  /// Si cambió el modo claro / oscuro desde que se armó el fondo, se vuelve a
  /// pintar todo con la paleta nueva.
  void _seguirPaleta(ColoresMapa c) {
    if (identical(c, _coloresFondo) || _base == null) return;
    _armarFondo(_base!);
    _poligonos.clear();
    if (_curva case final curva?) _contorno = poligonosContorno(curva.poligonos, c);
  }

  List<Polygon> _poligonosDe(CapaElegida capa, {required bool margen}) =>
      _poligonos[(capa.alturaCm, margen)] ??= poligonosAgua(capa.capa.poligonos, ColoresMapa.actuales(), margen: margen);

  /// El contorno del agua visible, proyectado una sola vez para el rayado.
  TrazadoAgua _rayadoDe(CapaElegida capa) {
    final r = _rayado;
    if (r != null && r.$1 == capa.alturaCm) return r.$2;
    final nuevo = TrazadoAgua(capa.capa.poligonos);
    _rayado = (capa.alturaCm, nuevo);
    return nuevo;
  }

  // ----- Pantalla -----

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    if (widget.datos == null && _carga != _Carga.noDisponible) {
      return const Center(
        child: Padding(padding: EdgeInsets.all(24), child: Text('Cargando el nivel del río…')),
      );
    }
    switch (_carga) {
      case _Carga.cargando:
        // Sin ruedita que gira: el texto alcanza y no consume batería.
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
            Semantics(header: true, child: Text(textoMapaNoDisponible, style: tema.titleLarge)),
            if (_motivoNoDisponible case final m?) ...[const SizedBox(height: 12), Text(m, style: tema.bodyLarge)],
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
    final umbrales = _umbrales;
    final apoyo = tema.bodyMedium?.copyWith(color: Colores.tintaSecundaria);

    // Columna y no ListView: son pocos bloques, y así el mapa no se desarma
    // (ni pierde el zoom) al bajar hasta las fuentes con letra grande.
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (ind.modelo.esProvisorio) ...[
            const Recuadro(icono: Icons.science_outlined, texto: textoMapaProvisorio),
            const SizedBox(height: 12),
          ] else if (!ind.validado) ...[
            const Recuadro(icono: Icons.construction, texto: textoMapaEnPrueba),
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
          if (cm != null) ..._alturasDeReferencia(ind, umbrales, cm),
          const SizedBox(height: 16),
          _Leyenda(conContorno: _contorno.isNotEmpty && _verContorno),
          const Separador(),
          Text(textoAvisoMapa, style: tema.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Muestra hasta dónde podría llegar el río con esa altura, según el terreno. '
            'No tiene en cuenta la lluvia, los desagües ni las calles cortadas. '
            'Ante una evacuación, seguí las indicaciones del Cecoed.',
            style: tema.bodyMedium,
          ),
          const SizedBox(height: 12),
          Semantics(header: true, child: Text('Fuentes', style: tema.titleMedium)),
          const SizedBox(height: 4),
          for (final f in ind.fuentes.isEmpty ? const [textoAtribucion] : ind.fuentes) Text(f, style: apoyo),
          if (ind.generado != null) Text('Mapa armado el ${formatoDia(enHoraUruguay(ind.generado!))}.', style: apoyo),
        ],
      ),
    );
  }

  /// Botones para saltar a alturas con nombre: los niveles de CARU y las
  /// crecidas reales del índice. De una crecida con curva medida se puede
  /// ver además su contorno (opcional, encima del agua del modelo).
  List<Widget> _alturasDeReferencia(IndiceMapa ind, Umbrales? u, int cm) {
    final tema = Theme.of(context).textTheme;
    final deReferencia = u != null && !u.validado ? ' (de referencia)' : '';
    final botones = <(String, double, ReferenciaMapa?)>[
      if (u?.alertaM case final a?) ('Nivel de alerta$deReferencia', a, null),
      if (u?.evacuacionM case final e?) ('Nivel de evacuación$deReferencia', e, null),
      for (final r in ind.referencias) (r.nombre, r.alturaM, r),
    ];
    if (botones.isEmpty) return const [];
    final ref = _referencia;
    int cmDe(double metros) => redondearArriba(metros, pasoCm: ind.pasoCm);
    return [
      const SizedBox(height: 16),
      Semantics(header: true, child: Text('Alturas para comparar', style: tema.titleMedium)),
      for (final (nombre, metros, r) in botones)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: _BotonAltura(
            texto: '$nombre: ${formatoAltura(metros)} m',
            elegido: r != null ? r == ref : ref == null && cm == cmDe(metros),
            alTocar: () => _ir(cmDe(metros), referencia: r),
          ),
        ),
      if (ref != null) ...[
        if (aCm(ref.alturaM) != cmDe(ref.alturaM)) ...[
          const SizedBox(height: 8),
          Text(
            '${ref.nombre}: ${formatoAltura(ref.alturaM)} m. El mapa lo redondea hacia arriba '
            'a ${formatoAltura(cmDe(ref.alturaM) / 100)} m.',
            style: tema.bodyMedium,
          ),
        ],
        if (ref.archivo != null)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _verContorno,
            onChanged: _mostrarContorno,
            title: Text('Ver el borde medido en esa crecida', style: tema.bodyLarge),
            subtitle: Text(
              'Línea de trazos sobre el mapa. Fuente: ${ref.fuente ?? 'Dinagua'}.',
              style: tema.bodyMedium,
            ),
          ),
        if (_verContorno && _curvaFallo)
          Text('No se pudo leer el borde medido de esa crecida.', style: tema.bodyMedium),
      ],
    ];
  }

  /// El aviso más grave del dato de hoy (uno solo, como pide el diseño).
  (IconData, String)? _aviso(HoyMapa hoy) {
    final cuando = hoy.lectura == null ? null : formatoFecha(hoy.lectura!.fecha, _ahora);
    if (hoy.motivo == 'cero') {
      return (
        Icons.straighten,
        'El mapa usa otra referencia de altura que el dato del río, así que no se pinta el río de hoy. '
            'Igual podés elegir una altura.',
      );
    }
    if (!hoy.hay) {
      return (
        Icons.help_outline,
        '${hoy.sinConexion ? 'Sin conexión y sin' : 'No hay'} un dato confiable de hoy. '
            'Igual podés elegir una altura para ver hasta dónde llegaría el agua.',
      );
    }
    if (hoy.viejo) return (Icons.schedule, 'El último dato es de $cuando. El río pudo cambiar.');
    if (hoy.sinConexion) {
      return (
        Icons.wifi_off,
        'Sin conexión. El mapa funciona igual, pero el dato del río es el último guardado ($cuando).',
      );
    }
    if (hoy.avisos.contains('dato_a_verificar')) return (Icons.warning_amber, textoAviso('dato_a_verificar')!);
    return null;
  }

  Widget _mapa(IndiceMapa ind, EleccionAgua? eleccion) {
    final c = ColoresMapa.actuales();
    _seguirPaleta(c);
    final limites = LatLngBounds(ind.surOeste, ind.norEste);
    final lugares = _base!.lugares;
    // Arranca en el centro de los barrios (la ciudad), no en todo el recorte.
    final centro = lugares.isEmpty
        ? limites.center
        : LatLng(
            lugares.map((l) => l.punto.latitude).reduce((a, b) => a + b) / lugares.length,
            lugares.map((l) => l.punto.longitude).reduce((a, b) => a + b) / lugares.length,
          );
    final margen = _margen, capa = _capa;
    final altura = eleccion == null ? '' : formatoAltura((eleccion.capaCm ?? eleccion.alturaCm) / 100);
    final descripcion =
        'Mapa de la costa de Paysandú, con el río, las calles y los barrios. '
        '${eleccion == null
            ? ''
            : eleccion.situacion == SituacionAgua.enCauce
            ? 'Con esta altura el agua queda en su cauce. '
            : 'Agua dibujada con $altura metros. '}'
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
                  // De abajo hacia arriba (docs/mapa/08-cartografia.md): cauce
                  // y arroyos; calles (los puentes quedan sobre el río); el
                  // margen y el agua, translúcidos sobre las calles para que
                  // se lean primero y dejen ver por dónde pasan; el rayado; el
                  // borde medido de una crecida y, arriba, los nombres con halo.
                  children: [
                    PolygonLayer(polygons: _cauce),
                    PolylineLayer(polylines: _cursos),
                    PolylineLayer(polylines: _calles),
                    if (margen != null) PolygonLayer(polygons: _poligonosDe(margen, margen: true)),
                    if (capa != null) PolygonLayer(polygons: _poligonosDe(capa, margen: false)),
                    if (capa != null) CapaRayado(trazado: _rayadoDe(capa), color: c.rayado),
                    if (_verContorno && _contorno.isNotEmpty) PolygonLayer(polygons: _contorno),
                    CapaRotulos(
                      candidatos: _candidatos,
                      cache: _rotulos,
                      colores: c,
                      // Sin nombres debajo de los botones + / − ni de la atribución.
                      tapadas: (s) => [
                        Rect.fromLTWH(s.width - 64, 0, 64, 120),
                        Rect.fromLTWH(0, s.height - 26, math.min(s.width, 300), 26),
                      ],
                    ),
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
          // Un solo nodo para TalkBack, del ancho de toda la barra (no solo
          // del pulgar), que dice la altura en metros.
          child: MergeSemantics(
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
        ),
        _BotonPaso(
          icono: Icons.add,
          texto: 'Subir $pasoTexto',
          alTocar: cm + paso <= alto ? () => _ir(cm + paso) : null,
        ),
      ],
    );
  }
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
      return Semantics(container: true, child: Text('Río hoy: sin dato confiable', style: tema.titleLarge));
    }
    final estilo = estiloNivel(hoy.nivel);
    final color = ColoresNivel.familia(hoy.nivel);
    final rotulo = hoy.viejo || hoy.sinConexion ? 'Último dato' : 'Río hoy';
    final cuando = formatoFecha(l.fecha, ahora);
    return Semantics(
      container: true,
      excludeSemantics: true,
      label:
          '$rotulo: ${formatoAltura(l.valorM)} metros. Nivel: ${estilo.nombre}. '
          'Medido $cuando. Fuente: ${fuenteCorta(l.fuente)}.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Text(
                '$rotulo: ${formatoAltura(l.valorM)} m',
                style: tema.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              // Ícono y palabra juntos: con letra muy grande, el par baja de
              // renglón entero (el Wrap) y la palabra sigue siendo un texto.
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(estilo.icono, color: color, size: 24),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      estilo.nombre,
                      style: tema.titleLarge?.copyWith(color: color, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
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
      SituacionAgua.enCauce =>
        'Con ${formatoAltura(metros)} m el agua queda en su cauce: '
            '${e.margenCm == null ? 'el mapa no muestra agua sobre la tierra.' : 'los puntos muestran hasta dónde podría llegar con un poco más.'}',
      SituacionAgua.sobreMaximo =>
        'El río supera lo que cubre el mapa (hasta ${formatoAltura(indice.maxCm / 100)} m). '
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
            child: Text(
              principal,
              style: tema.headlineMedium?.copyWith(fontSize: 26, fontFeatures: const [FontFeature.tabularFigures()]),
            ),
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
              child: Text(
                'Es la altura de hoy, redondeada hacia arriba a ${formatoDiferencia(indice.pasoCm / 100)}.',
                style: tema.bodyMedium?.copyWith(color: Colores.tintaSecundaria),
              ),
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
            OutlinedButton.icon(
              onPressed: alVolverAHoy,
              icon: const Icon(Icons.undo),
              label: const Text('Volver a hoy'),
            ),
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

/// Botón ancho para una altura con nombre. Una columna: con letra grande el
/// texto baja de renglón en vez de cortarse.
class _BotonAltura extends StatelessWidget {
  final String texto;
  final bool elegido;
  final VoidCallback alTocar;

  const _BotonAltura({required this.texto, required this.elegido, required this.alTocar});

  @override
  Widget build(BuildContext context) {
    final hijo = Align(alignment: Alignment.centerLeft, child: Text(texto));
    final estilo = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(double.infinity, 56)),
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
    );
    return Semantics(
      selected: elegido,
      child: elegido
          ? FilledButton.tonal(onPressed: alTocar, style: estilo, child: hijo)
          : OutlinedButton(onPressed: alTocar, style: estilo, child: hijo),
    );
  }
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
  final bool conContorno;
  const _Leyenda({this.conContorno = false});

  @override
  Widget build(BuildContext context) {
    final c = ColoresMapa.actuales();
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
        fila(CustomPaint(painter: MuestraCauce(c)), 'Río y arroyos, en su cauce'),
        fila(CustomPaint(painter: MuestraAgua(c)), 'Hasta dónde llegaría el agua (borde continuo)'),
        fila(CustomPaint(painter: MuestraMargen(c)), 'Puede llegar un poco más (borde de puntos)'),
        if (conContorno) fila(CustomPaint(painter: MuestraContorno(c)), 'Borde medido en esa crecida real (trazos)'),
      ],
    );
  }
}
