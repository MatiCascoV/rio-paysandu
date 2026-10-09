import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'datos.dart';
import 'notificaciones.dart';
import 'pantallas/ajustes.dart';
import 'pantallas/grafico.dart';
import 'pantallas/inicio.dart';
import 'pantallas/que_hacer.dart';
import 'tema.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = await Config.cargar();
  final prefs = await SharedPreferences.getInstance();
  try {
    await Notificaciones.iniciar(config, prefs);
  } catch (_) {
    // Si los avisos no se pueden preparar en este teléfono, la app igual
    // tiene que abrir y mostrar el nivel del río.
  }
  runApp(RioPaysanduApp(config: config, prefs: prefs, repositorio: Repositorio(config.urlBase)));
}

/// Preferencia guardada del modo: 'claro', 'oscuro' o nada (seguir al teléfono).
const claveTema = 'tema';

class RioPaysanduApp extends StatefulWidget {
  final Config config;
  final SharedPreferences prefs;
  final Repositorio repositorio;

  const RioPaysanduApp({super.key, required this.config, required this.prefs, required this.repositorio});

  @override
  State<RioPaysanduApp> createState() => _RioPaysanduAppState();
}

class _RioPaysanduAppState extends State<RioPaysanduApp> with WidgetsBindingObserver {
  Config get config => widget.config;
  SharedPreferences get prefs => widget.prefs;
  Repositorio get repositorio => widget.repositorio;

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
      title: 'Río Paysandú',
      debugShowCheckedModeBanner: false,
      locale: const Locale('es'),
      supportedLocales: const [Locale('es')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: temaApp(),
      // La clave hace que toda la pantalla se vuelva a dibujar al cambiar de modo.
      home: KeyedSubtree(
        key: ValueKey(_oscuro),
        child: PaginaPrincipal(
            config: config, prefs: prefs, repositorio: repositorio, oscuro: _oscuro, alCambiarTema: _cambiarTema),
      ),
    );
  }
}

class PaginaPrincipal extends StatefulWidget {
  final Config config;
  final SharedPreferences prefs;
  final Repositorio repositorio;
  final bool oscuro;
  final VoidCallback? alCambiarTema;

  const PaginaPrincipal({
    super.key,
    required this.config,
    required this.prefs,
    required this.repositorio,
    this.oscuro = false,
    this.alCambiarTema,
  });

  @override
  State<PaginaPrincipal> createState() => _PaginaPrincipalState();
}

class _PaginaPrincipalState extends State<PaginaPrincipal> with WidgetsBindingObserver {
  Datos? _datos; // null mientras carga por primera vez
  bool _actualizando = false;
  int _pestana = 0;
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
      if (!datos.sinConexion) await revisarNivel(datos.actual, widget.prefs);
    } catch (_) {
      // Pase lo que pase, la pantalla no puede quedar en "Cargando…".
      if (mounted && _datos == null) setState(() => _datos = const Datos(sinConexion: true));
    } finally {
      if (mounted) setState(() => _actualizando = false);
    }
  }

  Future<void> _actualizarAPedido() => _cargar(aPedido: true);

  void _irAQueHacer() {
    setState(() => _pestana = 2);
    // La pestaña conserva su posición: se vuelve arriba, donde están los teléfonos.
    if (_scrollQueHacer.hasClients) _scrollQueHacer.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final datos = _datos;
    final paginas = [
      PantallaInicio(
        datos: datos,
        config: widget.config,
        alActualizar: _actualizarAPedido,
        avisosActivos: widget.prefs.getBool(claveActivos) ?? false,
        alPedirAvisos: () => setState(() => _pestana = 3),
        alVerQueHacer: _irAQueHacer,
      ),
      PantallaGrafico(datos: datos),
      PantallaQueHacer(config: widget.config, controlador: _scrollQueHacer),
      PantallaAjustes(
        prefs: widget.prefs,
        datos: datos,
        config: widget.config,
        // Al prender los avisos se revisa el nivel en el momento.
        alCambiar: () => _cargar(),
      ),
    ];
    return Scaffold(
      appBar: AppBar(
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
      body: SafeArea(
        // En pantallas anchas (tablet, apaisado) el contenido no se estira de más.
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: IndexedStack(index: _pestana, children: paginas),
          ),
        ),
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(border: Border(top: BorderSide(color: Colores.bordeSuave))),
        // Tope al agrandado de letra: con más, las cuatro etiquetas no entran.
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.3,
          child: NavigationBar(
            selectedIndex: _pestana,
            onDestinationSelected: (i) => setState(() => _pestana = i),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.water), label: 'Inicio'),
              NavigationDestination(icon: Icon(Icons.show_chart), label: 'Gráfico'),
              NavigationDestination(icon: Icon(Icons.health_and_safety), label: 'Qué hacer'),
              NavigationDestination(icon: Icon(Icons.notifications), label: 'Avisos'),
            ],
          ),
        ),
      ),
    );
  }
}
