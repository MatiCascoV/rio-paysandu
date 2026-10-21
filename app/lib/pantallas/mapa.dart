/// Pestaña "Mapa": la costa de Paysandú con hasta dónde llegaría el agua.
///
/// Abre en la altura de hoy (la misma de Inicio y Gráfico, de actual.json),
/// redondeada hacia arriba a 10 cm. Con el deslizador o los botones − / + se
/// prueban otras alturas (simulación). Diseño de la pantalla:
/// docs/mapa/09-diseno-pantalla.md; dibujo: docs/mapa/08-cartografia.md.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../datos.dart';
import '../mapa/estilo_mapa.dart';
import '../mapa/logica_mapa.dart';
import '../mapa/modelos_mapa.dart';
import '../mapa/repositorio_mapa.dart';
import '../modelos.dart';
import '../tema.dart';
import '../textos.dart';
import 'comunes.dart';
import 'mapa_partes.dart';

export 'mapa_partes.dart';

class PantallaMapa extends StatefulWidget {
  final Datos? datos;
  final Config config;
  final RepositorioMapa repositorio;

  /// Para recordar que ya se vio "Cómo se usa". Sin prefs no se muestra la tarjeta.
  final SharedPreferences? prefs;

  /// Lleva a "Qué hacer" (en alerta o evacuación de hoy).
  final VoidCallback? alVerQueHacer;

  /// false mientras la pestaña no está a la vista. Al volver a ella, si se
  /// estaba simulando otra altura, el mapa vuelve a hoy.
  final bool activa;

  /// Solo para pruebas: permite fijar la hora actual.
  final DateTime? ahora;

  const PantallaMapa({
    super.key,
    required this.datos,
    required this.config,
    required this.repositorio,
    this.prefs,
    this.alVerQueHacer,
    this.activa = true,
    this.ahora,
  });

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

  /// Zona baja de la costa (capa de `min_m`): se dibuja siempre (v1.1 §3).
  CapaElegida? _zonaBaja;

  /// Agua con el río de hoy, para la línea de hoy al simular otra altura.
  CapaElegida? _capaHoy;

  /// Zonas donde el mapa no se pudo comparar con crecidas reales (v1.1 §1).
  ZonasSinValidar? _sinValidar;
  int _turno = 0;

  final _controlador = MapController();
  final _rotulos = CacheRotulos();
  final _poligonos = <(int, bool), List<Polygon>>{};

  /// Contorno del agua visible ya proyectado, para el rayado (uno solo).
  (int, TrazadoAgua)? _rayado;

  /// Contorno de la zona baja ya proyectado (para pintarla y para que el
  /// rayado del agua no entre en ella).
  (int, TrazadoAgua)? _trazadoZonaBaja;

  /// Líneas armadas una vez por capa (y por paleta): la de hoy y los puntos
  /// del margen dibujados encima.
  (int, List<Polyline>)? _lineasHoy;
  (int, List<Polyline>)? _margenEncima;

  /// Borde de la zona sin validar y dónde puede ir su nombre.
  List<Polyline> _lineasSinValidar = const [];
  List<LatLng> _anclasSinValidar = const [];

  /// Paleta con la que se armó el fondo (si cambia el tema, se rearma).
  ColoresMapa? _coloresFondo;
  List<Polygon> _cauce = const [];
  List<Polygon> _contorno = const [];
  List<Polyline> _calles = const [];
  List<Polyline> _cursos = const [];
  List<Rotulo> _candidatos = const [];

  /// Altura al empezar a arrastrar (para vibrar si al soltar cruzó un umbral).
  int? _cmAlEmpezar;

  /// Aviso de "dos dedos" sobre el mapa (un momento, tras arrastrar con uno).
  bool _avisoDosDedos = false;
  Timer? _relojAviso;
  final _dedos = <int, Offset>{};
  Offset _arrastre = Offset.zero;

  /// La tarjeta "Cómo se usa" de la primera vez.
  late bool _comoSeUsa = widget.prefs != null && !(widget.prefs!.getBool(claveComoSeUsa) ?? false);

  DateTime get _ahora => widget.ahora ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  void _entendido() {
    widget.prefs?.setBool(claveComoSeUsa, true);
    setState(() => _comoSeUsa = false);
  }

  @override
  void dispose() {
    _relojAviso?.cancel();
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
    // Opcional: si falta o no valida, el mapa sigue sin esa zona.
    final sinValidar = await repo.sinValidar();
    if (!mounted || repo != widget.repositorio) return;
    _indice = e.indice;
    _base = base;
    _sinValidar = sinValidar;
    _anclasSinValidar = sinValidar == null ? const [] : CapaRotuloZona.anclasDe(sinValidar.poligonos);
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
      _capa = _margen = _zonaBaja = _capaHoy = null;
      _sinValidar = null;
      _elegidaPorUsuario = false;
      _referencia = null;
      _verContorno = false;
      _curva = null;
      _contorno = const [];
      _motivoNoDisponible = null;
      _poligonos.clear();
      _rayado = _trazadoZonaBaja = _lineasHoy = _margenEncima = null;
      _lineasSinValidar = const [];
      _anclasSinValidar = const [];
      _turno++;
      _iniciar();
      return;
    }
    // Se volvió a la pestaña: una simulación no puede quedar a la vista como
    // si fuera el río (alguien podría volver días después y confundirse).
    if (!anterior.activa && widget.activa && _indice != null && (_elegidaPorUsuario || _referencia != null)) {
      _elegidaPorUsuario = false;
      _elegirInicial();
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
    // Al tocar − / + o un botón: vibración corta si cruzó alerta o evacuación.
    if (usuario && anunciar && _cm != null) _vibrarSiCruza(_cm!, nuevo);
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
    final repo = widget.repositorio;
    final e = elegirAgua(cm, ind);
    final capa = e.capaCm == null ? null : await repo.capa(e.capaCm!);
    // El margen y la zona baja van siempre (v1.1 §3 y §4).
    final margen = await repo.capa(e.margenCm);
    // Si la capa de `min_m` no se pudo leer, el repositorio da la de arriba:
    // esa no es la zona baja y no se dibuja con su estilo (se dice en la
    // lectura; por encima del mínimo el agua ya la cubre).
    final leidaZonaBaja = await repo.capa(e.zonaBajaCm);
    final zonaBaja = leidaZonaBaja == null || leidaZonaBaja.reemplazada ? null : leidaZonaBaja;
    // Al simular otra altura, también el agua de hoy (para su línea).
    final hoyCm = _hoyCm;
    final hoyCapaCm = hoyCm == null || hoyCm == cm ? null : elegirAgua(hoyCm, ind).capaCm;
    final capaHoy = hoyCapaCm == null ? null : await repo.capa(hoyCapaCm);
    if (!mounted || turno != _turno) return; // ya se pidió otra altura
    setState(() {
      _eleccion = e;
      _capa = capa;
      _margen = margen;
      _zonaBaja = zonaBaja;
      _capaHoy = capaHoy;
      // Solo quedan armados los polígonos que se ven: lo demás lo guarda (con
      // tope) el repositorio, y así la memoria no crece con cada altura.
      _poligonos.removeWhere((k, _) => k != (capa?.alturaCm, false) && k != (margen?.alturaCm, true));
    });
    if (anunciar) {
      SemanticsService.sendAnnouncement(View.of(context), _textoAnuncio(), TextDirection.ltr);
    }
  }

  /// Lo que se anuncia al soltar o tocar: la lectura en palabras y qué pasó
  /// con el agua en el mapa.
  String _textoAnuncio() {
    final e = _eleccion!;
    final agua = fraseAgua(e, _capa?.alturaCm);
    return [_datosLectura(e).anuncio, ?agua].join(' ');
  }

  /// La línea "agua de hoy" se dibuja al simular otra altura, si el río de
  /// hoy tiene capa en el mapa y es otro dibujo que el del agua (por encima
  /// del máximo los dos son la capa máxima: la línea no diría nada).
  bool get _lineaHoyVisible =>
      _capaHoy != null && _eleccion != null && _eleccion!.alturaCm != _hoyCm && _capaHoy!.alturaCm != _capa?.alturaCm;

  /// Los puntos del margen van también ENCIMA cuando su capa es la misma que
  /// otra que se dibuja arriba (el agua en el máximo o por encima, la zona
  /// baja por debajo del mínimo, o la línea de hoy): el margen se ve siempre
  /// (contrato v1.1 §4).
  bool get _margenEncimaVisible {
    final m = _margen?.alturaCm;
    if (m == null) return false;
    return m == _capa?.alturaCm || m == _zonaBaja?.alturaCm || (_lineaHoyVisible && m == _capaHoy!.alturaCm);
  }

  /// La capa de agua de esta altura (y todas las de arriba) no se pudo leer:
  /// el dibujo no sirve para esta altura y se tapa con un aviso.
  bool get _dibujoIlegible => _eleccion?.capaCm != null && _capa == null;

  /// Lomas aisladas de la capa pintada: la del agua o, por debajo del mínimo,
  /// la de la zona baja (contrato v1.1 §2).
  List<LomaAislada> get _aisladas => (_capa ?? _zonaBaja)?.capa.aisladas ?? const [];

  /// Umbrales que el mapa puede marcar, de menor a mayor.
  List<MarcaUmbral> get _marcas {
    final u = _umbrales;
    if (u == null) return const [];
    return [for (final (n, m) in umbralesOrdenados(u).reversed) (nivel: n, metros: m)];
  }

  void _vibrarSiCruza(int antes, int despues) {
    final bajo = math.min(antes, despues), alto = math.max(antes, despues);
    if (_marcas.any((m) => aCm(m.metros) > bajo && aCm(m.metros) <= alto)) HapticFeedback.selectionClick();
  }

  String _valorParaLector(int cm) {
    final texto = '${formatoAltura(cm / 100)} metros';
    if (cm <= _indice!.minCm) return '$texto, el agua no pasa de la zona baja de la costa';
    final u = _umbrales;
    return u == null ? texto : '$texto, nivel ${estiloNivel(nivelSegunUmbrales(cm / 100, u)).nombre}';
  }

  /// Qué dice la lectura para la altura elegida (09 §3.4): hoy o simulación.
  DatosLectura _datosLectura(EleccionAgua e) {
    final ind = _indice!, hoy = _hoy!;
    final hoyCm = _hoyCm;
    final metros = e.alturaCm / 100;
    final ultimo = hoy.esUltimoDato;
    final esHoy = hoyCm != null && e.alturaCm == hoyCm;
    LineaLectura linea(String texto, {bool aviso = false, bool chica = false}) =>
        (texto: texto, aviso: aviso, chica: chica);
    final lineas = <LineaLectura>[];
    if (esHoy) {
      final real = hoy.lectura!.valorM;
      if (aCm(real) != hoyCm) {
        lineas.add(
          linea(
            '${ultimo ? 'El último dato es' : 'Hoy el río está en'} ${formatoAltura(real)} m. '
            'El mapa lo redondea hacia arriba.',
            chica: true,
          ),
        );
      }
    } else if (hoyCm != null) {
      final dif = formatoDiferencia((e.alturaCm - hoyCm) / 100);
      lineas.add(linea('$dif ${e.alturaCm > hoyCm ? 'más' : 'menos'} que ${ultimo ? 'el último dato' : 'hoy'}.'));
    } else {
      lineas.add(
        linea(hoy.motivo == 'cero' ? 'El río de hoy no se puede pintar en este mapa.' : 'No hay dato del río de hoy.'),
      );
    }
    // Zona baja: igual con 3,90 que con 4,00 (sin salto de texto en el mínimo).
    if (e.noPasaDeLaZonaBaja) {
      final conPuntos = _margen != null && _margen!.alturaCm > e.alturaCm;
      lineas.add(linea(conPuntos ? '$textoZonaBaja $textoZonaBajaMargen' : textoZonaBaja));
      if (_zonaBaja == null) lineas.add(linea('No se pudo leer el dibujo de la zona baja de la costa.'));
    }
    switch (e.situacion) {
      case SituacionAgua.debajoDelMinimo:
        break;
      case SituacionAgua.sobreMaximo:
        lineas.add(
          linea(
            'El mapa llega hasta ${formatoAltura(ind.maxCm / 100)} m. '
            'Con más altura, el agua llega más lejos de lo que se ve.',
            aviso: true,
          ),
        );
      case SituacionAgua.enRango:
        // Altura + margen pasa del máximo: los puntos quedan recortados en
        // `max_m` (o pegados al agua en el máximo) y no muestran todo el margen.
        if (e.margenRecortado) lineas.add(linea(textoMargenRecortado(ind.maxCm), aviso: true));
    }
    final ref = _referencia;
    final refCm = ref == null ? null : redondearArriba(ref.alturaM, pasoCm: ind.pasoCm);
    if (ref != null && aCm(ref.alturaM) != refCm) {
      lineas.add(
        linea(
          '${ref.nombre}: ${formatoAltura(ref.alturaM)} m. El mapa lo redondea hacia arriba '
          'a ${formatoAltura(refCm! / 100)} m.',
          chica: true,
        ),
      );
    }
    final c = _capa;
    if (c != null && c.reemplazada) {
      lineas.add(
        linea(
          'No se pudo leer el dibujo de ${formatoAltura(c.pedidaCm / 100)} m. '
          'Se muestra el de ${formatoAltura(c.alturaCm / 100)} m, con un poco más de agua.',
        ),
      );
    } else if (_dibujoIlegible) {
      lineas.add(linea(textoDibujoIlegible, aviso: true));
    }
    // Lomas que quedarían rodeadas de agua: nunca se presentan como lugar seguro.
    if (_aisladas.isNotEmpty) lineas.add(linea(textoAvisoAisladas(_aisladas.length), aviso: true));
    if (esHoy) {
      return DatosLectura(
        simulacion: false,
        rotulo: ultimo ? 'Altura del último dato en el mapa' : 'Altura de hoy en el mapa',
        metros: metros,
        lineas: lineas,
      );
    }
    final u = _umbrales;
    // Sin pastilla en el cauce ni en Normal: un tilde verde junto a una altura
    // se leería como "estás a salvo" (09 §1).
    final calculado = u != null && e.situacion != SituacionAgua.debajoDelMinimo ? nivelSegunUmbrales(metros, u) : null;
    final nivel = calculado == Nivel.normal ? null : calculado;
    return DatosLectura(
      simulacion: true,
      titulo: hoyCm == null ? null : (ultimo ? 'No es el último dato' : 'No es el río de hoy'),
      rotulo: 'Simulación con',
      metros: metros,
      nivel: nivel,
      deReferencia: nivel != null && !u!.validado,
      lineas: lineas,
      textoVolver: hoyCm == null ? null : (ultimo ? 'Volver al último dato' : 'Volver a hoy'),
    );
  }

  /// Botones de "Alturas para comparar": hoy, pronóstico, umbrales y crecidas.
  List<AlturaComparar> _alturas(IndiceMapa ind, int cm) {
    final hoy = _hoy!, u = _umbrales, ref = _referencia;
    int cmDe(double metros) => redondearArriba(metros, pasoCm: ind.pasoCm);
    bool elegidoSin(double metros) => ref == null && cm == cmDe(metros);
    final deReferencia = u != null && !u.validado ? ' (de referencia)' : '';
    final pronostico = widget.datos?.actual?.pronostico;
    final esperada = pronostico?.alturaEsperadaM;
    final informe = pronostico?.informeFecha;
    return [
      if (hoy.lectura case final l?)
        AlturaComparar(
          tipo: TipoAltura.hoy,
          titulo: hoy.esUltimoDato ? 'Último dato' : 'Hoy',
          detalle: '${formatoAltura(cmDe(l.valorM) / 100)} m',
          metros: l.valorM,
          elegido: elegidoSin(l.valorM),
        ),
      if (pronostico != null && pronostico.vigente && esperada != null && hoy.motivo != 'cero')
        AlturaComparar(
          tipo: TipoAltura.pronostico,
          titulo: 'Pronóstico CARU',
          detalle: 'hasta ${formatoAltura(esperada)} m${informe == null ? '' : ' · ${informe.day}/${informe.month}'}',
          detalleVoz:
              'hasta ${formatoAltura(esperada)} m${informe == null ? '' : ', informe del ${informe.day}/${informe.month}'}',
          metros: esperada,
          elegido: elegidoSin(esperada),
        ),
      if (u?.alertaM case final a?)
        AlturaComparar(
          tipo: TipoAltura.alerta,
          titulo: 'Nivel de alerta',
          detalle: '${formatoAltura(a)} m$deReferencia',
          metros: a,
          elegido: elegidoSin(a),
        ),
      if (u?.evacuacionM case final e?)
        AlturaComparar(
          tipo: TipoAltura.evacuacion,
          titulo: 'Nivel de evacuación',
          detalle: '${formatoAltura(e)} m$deReferencia',
          metros: e,
          elegido: elegidoSin(e),
        ),
      for (final r in ind.referencias)
        AlturaComparar(
          tipo: TipoAltura.crecida,
          titulo: r.nombre,
          detalle: '${formatoAltura(r.alturaM)} m',
          metros: r.alturaM,
          referencia: r,
          elegido: r == ref,
        ),
    ];
  }

  /// Leyenda con las muestras del cartógrafo (estilo_mapa.dart, 08 §6).
  List<EntradaLeyenda> _leyenda(IndiceMapa ind) {
    final c = ColoresMapa.actuales();
    return [
      EntradaLeyenda(MuestraCauce(c), 'Río y arroyos, en su cauce'),
      EntradaLeyenda(MuestraAgua(c), 'Hasta dónde llegaría el agua con la altura elegida (rayado)'),
      EntradaLeyenda(
        MuestraMargen(c),
        '${_eleccion?.margenRecortado ?? false ? textoLeyendaMargenRecortado(ind.maxCm) : textoLeyendaMargen(ind.margenCm)}'
        ' (borde de puntos)',
      ),
      if (_zonaBaja != null) EntradaLeyenda(MuestraZonaBaja(c), '$textoLeyendaZonaBaja (rayas horizontales)'),
      if (_lineaHoyVisible)
        EntradaLeyenda(
          MuestraHoy(c),
          '${_hoy?.esUltimoDato ?? false ? textoLeyendaUltimoDato : textoLeyendaHoy} (línea gruesa)',
        ),
      if (_aisladas.isNotEmpty) EntradaLeyenda(MarcaAislada(c), '$textoLeyendaAisladas (rombo con "!")'),
      // Sin el archivo (los datos de hoy no lo traen) la zona igual existe:
      // fila sin muestra, porque no hay borde para dibujar (11 §8, condición 3).
      if (_sinValidar != null)
        EntradaLeyenda(MuestraSinValidar(c), '$textoLeyendaSinValidar (raya y punto)')
      else
        const EntradaLeyenda(null, textoLeyendaSinValidarSinDibujo),
      if (_verContorno && _contorno.isNotEmpty)
        EntradaLeyenda(
          MuestraContorno(c),
          'Borde medido en esa crecida, según ${_referencia?.fuente ?? 'Dinagua'} (trazos)',
        ),
    ];
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
    _lineasSinValidar = lineasSinValidar(_sinValidar?.poligonos ?? const [], c);
    _lineasHoy = _margenEncima = null;
  }

  /// Si cambió el modo claro / oscuro desde que se armó el fondo, se vuelve a
  /// pintar todo con la paleta nueva.
  void _seguirPaleta(ColoresMapa c) {
    if (identical(c, _coloresFondo) || _base == null) return;
    _armarFondo(_base!);
    _poligonos.clear();
    if (_curva case final curva?) _contorno = poligonosContorno(curva.poligonos, c);
  }

  List<Polygon> _poligonosDe(CapaElegida capa, {required bool margen}) => _poligonos[(capa.alturaCm, margen)] ??=
      poligonosAgua(capa.capa.poligonos, ColoresMapa.actuales(), margen: margen);

  /// El contorno del agua visible, proyectado una sola vez para el rayado.
  TrazadoAgua _rayadoDe(CapaElegida capa) {
    final r = _rayado;
    if (r != null && r.$1 == capa.alturaCm) return r.$2;
    final nuevo = TrazadoAgua(capa.capa.poligonos);
    _rayado = (capa.alturaCm, nuevo);
    return nuevo;
  }

  /// El contorno de la zona baja, proyectado una sola vez.
  TrazadoAgua _trazadoZonaBajaDe(CapaElegida capa) {
    final r = _trazadoZonaBaja;
    if (r != null && r.$1 == capa.alturaCm) return r.$2;
    final nuevo = TrazadoAgua(capa.capa.poligonos);
    _trazadoZonaBaja = (capa.alturaCm, nuevo);
    return nuevo;
  }

  List<Polyline> _lineasHoyDe(CapaElegida capa) {
    final r = _lineasHoy;
    if (r != null && r.$1 == capa.alturaCm) return r.$2;
    final nuevo = lineasHoy(capa.capa.poligonos, ColoresMapa.actuales());
    _lineasHoy = (capa.alturaCm, nuevo);
    return nuevo;
  }

  List<Polyline> _margenEncimaDe(CapaElegida capa) {
    final r = _margenEncima;
    if (r != null && r.$1 == capa.alturaCm) return r.$2;
    final nuevo = lineasMargenEncima(capa.capa.poligonos, ColoresMapa.actuales());
    _margenEncima = (capa.alturaCm, nuevo);
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
    final aviso = avisoHoyMapa(hoy, _ahora);
    final ref = _referencia;

    // Columna y no ListView: son pocos bloques, y así el mapa no se desarma
    // (ni pierde el zoom) al bajar hasta las fuentes con letra grande.
    // Orden: docs/mapa/09-diseno-pantalla.md §2.
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FranjaHoyMapa(hoy: hoy, ahora: _ahora),
          // Un solo recuadro: el del dato de hoy. La calidad del mapa va en el sello.
          if (aviso != null) ...[const SizedBox(height: 12), RecuadroHoyMapa(aviso: aviso)],
          if (_comoSeUsa) ...[const SizedBox(height: 12), TarjetaComoSeUsa(alEntender: _entendido)],
          const SizedBox(height: 16),
          if (cm != null && eleccion != null)
            LecturaMapa(
              datos: _datosLectura(eleccion),
              alVolver: _hoyCm == null || cm == _hoyCm ? null : () => _ir(_hoyCm!),
            ),
          const SizedBox(height: 12),
          MarcoMapa(indice: ind, mapa: _mapa(ind, eleccion), mover: _flechas()),
          if (hoy.grave && widget.alVerQueHacer != null) ...[
            const SizedBox(height: 16),
            BotonQueHacer(nivel: hoy.nivel, alTocar: widget.alVerQueHacer),
          ],
          if (cm != null) ...[const SizedBox(height: 24), _control(ind, cm)],
          if (cm == null ? const <AlturaComparar>[] : _alturas(ind, cm) case final alturas when alturas.isNotEmpty) ...[
            const SizedBox(height: 24),
            Semantics(header: true, child: Text('Alturas para comparar', style: tema.titleMedium)),
            const SizedBox(height: 8),
            GrillaAlturas(
              alturas: alturas,
              alTocar: (a) => _ir(redondearArriba(a.metros, pasoCm: ind.pasoCm), referencia: a.referencia),
            ),
          ],
          if (ref != null && ref.archivo != null)
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
          if (ref != null && _verContorno && _curvaFallo)
            Text('No se pudo leer el borde medido de esa crecida.', style: tema.bodyMedium),
          const SizedBox(height: 24),
          LeyendaMapa(entradas: _leyenda(ind)),
          const Separador(),
          PieMapa(indice: ind),
        ],
      ),
    );
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
    final margen = _margen, capa = _capa, zonaBaja = _zonaBaja, capaHoy = _capaHoy;
    final aisladas = _aisladas;
    // Sin nombres debajo de los botones + / − ni de la atribución.
    List<Rect> tapadas(Size s) => [
      Rect.fromLTWH(s.width - 64, 0, 64, 120),
      Rect.fromLTWH(0, s.height - 26, math.min(s.width, 300), 26),
    ];
    // El dibujo no se puede recorrer con TalkBack: lo reemplaza este resumen.
    final descripcion = resumenMapa(
      situacion: eleccion?.situacion,
      alturaCm: eleccion?.alturaCm,
      dibujoCm: capa?.alturaCm,
      margenCm: margen?.alturaCm,
      minCm: ind.minCm,
      maxCm: ind.maxCm,
      zonaBajaDibujada: _zonaBaja != null,
      simulacion: eleccion != null && eleccion.alturaCm != _hoyCm,
      dibujoIlegible: _dibujoIlegible,
      margenRecortado: eleccion?.margenRecortado ?? false,
      aisladas: _aisladas.length,
      sinValidar: _sinValidar != null,
      sinValidarSinDibujo: _sinValidar == null,
      nombresSinValidar: [for (final z in _sinValidar?.zonas ?? const <ZonaSinValidar>[]) z.nombre],
      hoyCm: _lineaHoyVisible ? _capaHoy?.alturaCm : null,
      contorno: _verContorno && _contorno.isNotEmpty ? _referencia?.nombre : null,
    );
    final quieto = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      container: true,
      image: true,
      label: descripcion,
      // Las esquinas redondeadas las pone el marco (sello arriba, pie abajo).
      child: ClipRRect(
        borderRadius: BorderRadius.zero,
        child: SizedBox(
          // No se achica por la letra grande: entre 240 y 320 dp según la pantalla.
          height: (MediaQuery.sizeOf(context).height * 0.40).clamp(altoMapaMinimo, altoMapa),
          child: Stack(
            children: [
              ExcludeSemantics(
                // Con un dedo se mueve la página, no el mapa: así el mapa no
                // atrapa el desplazamiento (ni el de dos dedos de TalkBack,
                // que llega como un dedo). El mapa se mueve con dos dedos o
                // con las flechas, y se acerca con + / −, pellizcando o con
                // doble toque.
                child: Listener(
                  onPointerDown: (e) => _dedos[e.pointer] = e.position,
                  onPointerMove: _alMoverDedo,
                  onPointerUp: (e) => _soltarDedo(e.pointer),
                  onPointerCancel: (e) => _soltarDedo(e.pointer),
                  child: FlutterMap(
                    mapController: _controlador,
                    options: MapOptions(
                      initialCenter: centro,
                      initialZoom: 13.5,
                      minZoom: 11,
                      maxZoom: 18,
                      backgroundColor: c.terreno,
                      cameraConstraint: CameraConstraint.containCenter(bounds: limites),
                      interactionOptions: InteractionOptions(
                        flags: InteractiveFlag.pinchZoom | InteractiveFlag.pinchMove | InteractiveFlag.doubleTapZoom,
                        // "Quitar animaciones" de Android: el doble toque acerca sin animar.
                        doubleTapZoomDuration: quieto ? Duration.zero : const Duration(milliseconds: 200),
                      ),
                    ),
                    // De abajo hacia arriba (docs/mapa/08-cartografia.md §3 y §7):
                    // cauce y arroyos; calles (los puentes quedan sobre el río);
                    // el margen y el agua, translúcidos sobre las calles; el
                    // rayado (fuera de la zona baja); la zona baja, que está
                    // dentro de toda capa de agua y por eso no tapa agua: la
                    // muestra con su dibujo; después solo LÍNEAS sin relleno
                    // (crecida medida, zona sin validar, hoy, puntos del
                    // margen); los nombres y, arriba, las lomas aisladas.
                    // Ninguna capa con relleno va encima del agua y del margen.
                    children: [
                      PolygonLayer(polygons: _cauce),
                      PolylineLayer(polylines: _cursos),
                      PolylineLayer(polylines: _calles),
                      if (margen != null) PolygonLayer(polygons: _poligonosDe(margen, margen: true)),
                      if (capa != null) PolygonLayer(polygons: _poligonosDe(capa, margen: false)),
                      if (capa != null)
                        CapaRayado(
                          trazado: _rayadoDe(capa),
                          color: c.rayado,
                          excluir: zonaBaja == null ? null : _trazadoZonaBajaDe(zonaBaja),
                        ),
                      if (zonaBaja != null) CapaZonaBaja(trazado: _trazadoZonaBajaDe(zonaBaja), colores: c),
                      if (_verContorno && _contorno.isNotEmpty) PolygonLayer(polygons: _contorno),
                      if (_lineasSinValidar.isNotEmpty) PolylineLayer(polylines: _lineasSinValidar),
                      if (_lineaHoyVisible) PolylineLayer(polylines: _lineasHoyDe(capaHoy!)),
                      if (_margenEncimaVisible) PolylineLayer(polylines: _margenEncimaDe(margen!)),
                      CapaRotulos(candidatos: _candidatos, cache: _rotulos, colores: c, tapadas: tapadas),
                      if (_anclasSinValidar.isNotEmpty)
                        CapaRotuloZona(
                          anclas: _anclasSinValidar,
                          texto: 'Zona sin validar',
                          colores: c,
                          tapadas: tapadas,
                        ),
                      if (aisladas.isNotEmpty)
                        MarkerLayer(
                          markers: marcadoresAisladas(
                            [for (final l in aisladas) l.punto],
                            c,
                            alTocar: (i) => mostrarLomaAislada(context, aisladas[i]),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              // Sin la capa de esta altura, el dibujo (casi sin agua) no se
              // muestra como si valiera: se tapa con el aviso. TalkBack ya lo
              // oye en la descripción del mapa y en la lectura.
              if (_dibujoIlegible)
                Positioned.fill(
                  child: ExcludeSemantics(
                    child: ColoredBox(
                      key: const ValueKey('mapa-dibujo-ilegible'),
                      color: Colores.superficie,
                      // Con letra grande el aviso puede pasar el alto del
                      // mapa: se desplaza adentro en vez de desbordar.
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 72, 32),
                        child: Recuadro(icono: Icons.warning_amber, texto: textoDibujoIlegible),
                      ),
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
              if (_avisoDosDedos)
                Positioned(
                  left: 8,
                  right: 64,
                  top: 8,
                  // Solo a la vista: quien usa TalkBack no arrastra el mapa.
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
      ),
    );
  }

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

  /// Flechas para mover el mapa sin arrastrar (WCAG 2.5.7).
  Widget _flechas() => FilaMoverMapa(alMover: _mover);

  Widget _control(IndiceMapa ind, int cm) {
    final (bajo, alto) = _rango;
    final u = _umbrales;
    return ControlAltura(
      cm: cm,
      bajo: bajo,
      alto: alto,
      paso: ind.pasoCm,
      marcas: _marcas,
      deReferencia: u != null && !u.validado,
      valorParaLector: _valorParaLector,
      alTocarPaso: _ir,
      alCambiar: (nuevo) => _ir(nuevo, anunciar: false),
      alEmpezar: () => _cmAlEmpezar = _cm,
      alSoltar: () {
        final antes = _cmAlEmpezar;
        if (antes != null && _cm != null) _vibrarSiCruza(antes, _cm!);
        _cmAlEmpezar = null;
        _cargarCapas(anunciar: true);
      },
    );
  }
}

// ---------------------------------------------------------------------------

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
