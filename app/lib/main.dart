import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'avisos.dart';
import 'crecidas/repositorio_crecidas.dart';
import 'datos.dart';
import 'ejemplo.dart';
import 'enlaces.dart';
import 'notificaciones.dart';
import 'pantallas/ajustes.dart';
import 'pantallas/crecidas.dart';
import 'pantallas/grafico.dart';
import 'pantallas/inicio.dart';
import 'pantallas/que_hacer.dart';
import 'push.dart';
import 'tema.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = await Config.cargar();
  permitirOrigenes(config.enlacesPermitidos);
  final prefs = await SharedPreferences.getInstance();
  // Datos de ejemplo por nivel: solo con --dart-define=DATOS_EJEMPLO o en debug (ver ejemplo.dart).
  // Con ellos no se preparan los avisos ni se toca la copia guardada.
  final ejemplo = nivelDeEjemplo();
  if (ejemplo == null) {
    try {
      await Notificaciones.iniciar(config, prefs);
    } catch (_) {
      // Si los avisos no se pueden preparar en este teléfono, la app igual
      // tiene que abrir y mostrar el nivel del río.
    }
    // Aparte: sin Firebase (por ejemplo, sin servicios de Google) queda la revisión local.
    try {
      await Push.iniciar(prefs);
    } catch (_) {}
  }
  final repositorio = ejemplo == null
      ? Repositorio(config.urlBase)
      : Repositorio(config.urlBase, cliente: clienteDeEjemplo(ejemplo), soloLectura: true);
  // Los bordes de las crecidas vienen dentro de la app; el fondo se lee en otro hilo.
  final repositorioCrecidas = RepositorioCrecidas(const FuenteAssets(), enSegundoPlano: true);
  runApp(RioPaysanduApp(
      config: config, prefs: prefs, repositorio: repositorio, repositorioCrecidas: repositorioCrecidas));
  // El permiso se pide con la app ya a la vista, una sola vez (ver pedirPermisoInicial).
  if (ejemplo == null) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(Notificaciones.pedirPermisoInicial(prefs).catchError((_) {}));
    });
  }
}

/// Pestañas de abajo, en orden. Los saltos entre pestañas usan esto y no
/// números sueltos, para que agregar una no haga apuntar a la equivocada.
enum Pestana { inicio, grafico, crecidas, queHacer, avisos }

/// Preferencia guardada del modo: 'claro', 'oscuro' o nada (seguir al teléfono).
const claveTema = 'tema';

class RioPaysanduApp extends StatefulWidget {
  final Config config;
  final SharedPreferences prefs;
  final Repositorio repositorio;

  /// Datos de la pestaña Crecidas. Si no se pasa, se leen de assets/crecidas/.
  final RepositorioCrecidas? repositorioCrecidas;

  const RioPaysanduApp(
      {super.key, required this.config, required this.prefs, required this.repositorio, this.repositorioCrecidas});

  @override
  State<RioPaysanduApp> createState() => _RioPaysanduAppState();
}

class _RioPaysanduAppState extends State<RioPaysanduApp> with WidgetsBindingObserver {
  Config get config => widget.config;
  SharedPreferences get prefs => widget.prefs;
  Repositorio get repositorio => widget.repositorio;

  /// Vive acá y no en la página: al cambiar claro/oscuro la página se rehace,
  /// pero lo ya leído queda en memoria.
  late final RepositorioCrecidas _repositorioCrecidas =
      widget.repositorioCrecidas ?? RepositorioCrecidas(const FuenteAssets());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Si el teléfono cambia entre claro y oscuro, la app lo sigue.
  @override
  void didChangePlatformBrightness() => setState(() {});

  bool get _oscuro => switch (prefs.getString(claveTema)) {
        'oscuro' => true,
        'claro' => false,
        _ => WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark,
      };

  Future<void> _cambiarTema() async {
    await prefs.setString(claveTema, _oscuro ? 'claro' : 'oscuro');
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    Colores.oscuro = _oscuro; // todos los colores salen de la paleta elegida
    return MaterialApp(
      title: 'Mi Río UY',
      debugShowCheckedModeBanner: false,
      locale: const Locale('es'),
      supportedLocales: const [Locale('es')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: temaApp(),
      // La clave hace que toda la pantalla se vuelva a dibujar al cambiar de modo.
      home: KeyedSubtree(
        key: ValueKey(_oscuro),
        child: PaginaPrincipal(
            config: config,
            prefs: prefs,
            repositorio: repositorio,
            repositorioCrecidas: _repositorioCrecidas,
            oscuro: _oscuro,
            alCambiarTema: _cambiarTema),
      ),
    );
  }
}

class PaginaPrincipal extends StatefulWidget {
  final Config config;
  final SharedPreferences prefs;
  final Repositorio repositorio;
  final RepositorioCrecidas? repositorioCrecidas;
  final bool oscuro;
  final VoidCallback? alCambiarTema;

  const PaginaPrincipal({
    super.key,
    required this.config,
    required this.prefs,
    required this.repositorio,
    this.repositorioCrecidas,
    this.oscuro = false,
    this.alCambiarTema,
  });

  @override
  State<PaginaPrincipal> createState() => _PaginaPrincipalState();
}

class _PaginaPrincipalState extends State<PaginaPrincipal> with WidgetsBindingObserver {
  Datos? _datos; // null mientras carga por primera vez
  bool _actualizando = false;
  Pestana _pestana = Pestana.inicio;

  /// Pestañas ya abiertas. Crecidas se arma recién la primera vez que se
  /// visita, para no leer el mapa al arrancar la app.
  final _visitadas = <Pestana>{Pestana.inicio};
  late final RepositorioCrecidas _repositorioCrecidas =
      widget.repositorioCrecidas ?? RepositorioCrecidas(const FuenteAssets());
  Timer? _reloj;
  final _scrollQueHacer = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cargar(primeraVez: true);
    // Con la app abierta se vuelve a consultar cada 5 minutos, para que una
    // pantalla que queda encendida no siga mostrando un dato viejo como actual.
    _reloj = Timer.periodic(const Duration(minutes: 5), (_) => _cargar());
  }

  @override
  void dispose() {
    _reloj?.cancel();
    _scrollQueHacer.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    if (estado == AppLifecycleState.resumed) _cargar(); // al volver a la app, refrescar
  }

  /// [aPedido]: la pidió el usuario, así que se le dice cómo terminó (en
  /// pantalla y por el lector de pantalla). Las automáticas son silenciosas.
  Future<void> _cargar({bool primeraVez = false, bool aPedido = false}) async {
    if (_actualizando) return;
    setState(() => _actualizando = true);
    try {
      if (primeraVez) {
        // Primero lo guardado (aparece al instante), después lo nuevo.
        final guardado = await widget.repositorio.cargar(usarRed: false);
        if (mounted && guardado.actual != null) setState(() => _datos = guardado);
      }
      final datos = await widget.repositorio.cargar();
      if (!mounted) return;
      setState(() => _datos = datos);
      if (aPedido) {
        final mensaje =
            datos.sinConexion ? 'No hay conexión. Se muestra el último dato guardado.' : 'Datos actualizados.';
        SemanticsService.sendAnnouncement(View.of(context), mensaje, TextDirection.ltr);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(mensaje), duration: const Duration(seconds: 3)));
      }
      // Con datos de ejemplo nunca se avisa: serían avisos inventados. Con la app a
      // la vista el resumen del día no se notifica (el dato ya se está viendo); el
      // reloj de 5 minutos también corre con la app de fondo, y ahí sí.
      final estado = WidgetsBinding.instance.lifecycleState;
      final aLaVista = estado == null || estado == AppLifecycleState.resumed;
      if (!datos.sinConexion && !widget.repositorio.soloLectura) {
        await revisarNivel(datos.actual, widget.prefs, origen: aLaVista ? Origen.app : Origen.respaldo);
      }
    } catch (_) {
      // Pase lo que pase, la pantalla no puede quedar en "Cargando…".
      if (mounted && _datos == null) setState(() => _datos = const Datos(sinConexion: true));
    } finally {
      if (mounted) setState(() => _actualizando = false);
    }
  }

  Future<void> _actualizarAPedido() => _cargar(aPedido: true);

  void _ir(Pestana p) => setState(() {
        _pestana = p;
        _visitadas.add(p);
      });

  void _irAQueHacer() {
    _ir(Pestana.queHacer);
    // La pestaña conserva su posición: se vuelve arriba, donde están los teléfonos.
    if (_scrollQueHacer.hasClients) _scrollQueHacer.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final datos = _datos;
    final paginas = <Pestana, Widget>{
      Pestana.inicio: PantallaInicio(
        datos: datos,
        config: widget.config,
        alActualizar: _actualizarAPedido,
        avisosActivos: PreferenciasAvisos.leer(widget.prefs).urgente,
        alPedirAvisos: () => _ir(Pestana.avisos),
        alVerQueHacer: _irAQueHacer,
        alVerGrafico: () => _ir(Pestana.grafico),
      ),
      Pestana.grafico: PantallaGrafico(datos: datos),
      Pestana.crecidas: _visitadas.contains(Pestana.crecidas)
          ? PantallaCrecidas(repositorio: _repositorioCrecidas)
          : const SizedBox.shrink(),
      Pestana.queHacer: PantallaQueHacer(config: widget.config, controlador: _scrollQueHacer),
      Pestana.avisos: PantallaAjustes(
        prefs: widget.prefs,
        datos: datos,
        config: widget.config,
        // Al cambiar los avisos se revisa el nivel en el momento.
        alCambiar: () => _cargar(),
      ),
    };
    // En Inicio la pantalla se tiñe con el color del nivel, barra de arriba incluida.
    final enInicio = _pestana == Pestana.inicio;
    final tinte = enInicio ? tinteInicio(datos, widget.config, DateTime.now()) : null;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: tinte,
        shape: enInicio ? const Border() : null,
        title: const FittedBox(fit: BoxFit.scaleDown, child: Text('Río Uruguay en Paysandú')),
        actions: [
          if (widget.alCambiarTema != null)
            IconButton(
              tooltip: widget.oscuro ? 'Cambiar a modo claro' : 'Cambiar a modo oscuro',
              onPressed: widget.alCambiarTema,
              icon: Icon(widget.oscuro ? Icons.light_mode : Icons.dark_mode),
            ),
          // El botón queda siempre en su lugar (el lector de pantalla no pierde el foco).
          IconButton(
            tooltip: _actualizando ? 'Actualizando' : 'Actualizar',
            onPressed: _actualizando ? null : _actualizarAPedido,
            icon: _actualizando
                ? SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(color: Colores.primario, strokeWidth: 3),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: tinte == null ? null : degradeInicio(tinte)),
        child: SafeArea(
          // En pantallas anchas (tablet, apaisado) el contenido no se estira de más.
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: IndexedStack(
                index: _pestana.index,
                children: [
                  // Lo que se mueve (las olas de Inicio) se detiene en las pestañas que no están a la vista.
                  for (final p in Pestana.values) TickerMode(enabled: p == _pestana, child: paginas[p]!),
                ],
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(border: Border(top: BorderSide(color: Colores.bordeSuave))),
        // Tope al agrandado de letra: con más, las cinco etiquetas no entran
        // en 320 dp (lo mide la prueba de desborde).
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: topeLetraPestanas,
          child: NavigationBar(
            selectedIndex: _pestana.index,
            onDestinationSelected: (i) => _ir(Pestana.values[i]),
            destinations: [
              for (final p in Pestana.values) NavigationDestination(icon: Icon(p.icono), label: p.etiqueta),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tope al agrandado de letra en la barra de pestañas.
const topeLetraPestanas = 1.3;

extension DatosPestana on Pestana {
  String get etiqueta => switch (this) {
        Pestana.inicio => 'Inicio',
        Pestana.grafico => 'Gráfico',
        Pestana.crecidas => 'Crecidas',
        Pestana.queHacer => 'Qué hacer',
        Pestana.avisos => 'Avisos',
      };

  IconData get icono => switch (this) {
        Pestana.inicio => Icons.water,
        Pestana.grafico => Icons.show_chart,
        Pestana.crecidas => Icons.history,
        Pestana.queHacer => Icons.health_and_safety,
        Pestana.avisos => Icons.notifications,
      };
}
