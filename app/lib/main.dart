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

class RioPaysanduApp extends StatelessWidget {
  final Config config;
  final SharedPreferences prefs;
  final Repositorio repositorio;

  const RioPaysanduApp({super.key, required this.config, required this.prefs, required this.repositorio});

  @override
  Widget build(BuildContext context) {
    // Tema claro de alto contraste y letra un 15 % más grande que la habitual;
    // además se respeta el tamaño de letra que el usuario eligió en su teléfono.
    final esquema = ColorScheme.fromSeed(seedColor: const Color(0xFF0D47A1), contrastLevel: 1);
    final tipografia = Typography.material2021(colorScheme: esquema);
    final letras = tipografia.englishLike
        .merge(tipografia.black)
        .apply(fontSizeFactor: 1.15, bodyColor: Colors.black, displayColor: Colors.black);
    return MaterialApp(
      title: 'Río Paysandú',
      debugShowCheckedModeBanner: false,
      locale: const Locale('es'),
      supportedLocales: const [Locale('es')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
        colorScheme: esquema,
        useMaterial3: true,
        textTheme: letras,
        appBarTheme: AppBarTheme(backgroundColor: esquema.primary, foregroundColor: esquema.onPrimary),
        navigationBarTheme: NavigationBarThemeData(
          labelTextStyle: WidgetStatePropertyAll(letras.labelLarge?.copyWith(fontSize: 15, color: Colors.black)),
        ),
      ),
      home: PaginaPrincipal(config: config, prefs: prefs, repositorio: repositorio),
    );
  }
}

class PaginaPrincipal extends StatefulWidget {
  final Config config;
  final SharedPreferences prefs;
  final Repositorio repositorio;

  const PaginaPrincipal({super.key, required this.config, required this.prefs, required this.repositorio});

  @override
  State<PaginaPrincipal> createState() => _PaginaPrincipalState();
}

class _PaginaPrincipalState extends State<PaginaPrincipal> with WidgetsBindingObserver {
  Datos? _datos; // null mientras carga por primera vez
  bool _actualizando = false;
  int _pestana = 0;
  Timer? _reloj;

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
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    if (estado == AppLifecycleState.resumed) _cargar(); // al volver a la app, refrescar
  }

  /// [anunciar]: decirle al lector de pantalla cómo terminó (cuando lo pidió el usuario).
  Future<void> _cargar({bool primeraVez = false, bool anunciar = false}) async {
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
      if (anunciar) {
        SemanticsService.sendAnnouncement(
          View.of(context),
          datos.sinConexion ? 'No hay conexión. Se muestra el último dato guardado.' : 'Datos actualizados.',
          TextDirection.ltr,
        );
      }
      if (!datos.sinConexion) await revisarNivel(datos.actual, widget.prefs);
    } catch (_) {
      // Pase lo que pase, la pantalla no puede quedar en "Cargando…".
      if (mounted && _datos == null) setState(() => _datos = const Datos(sinConexion: true));
    } finally {
      if (mounted) setState(() => _actualizando = false);
    }
  }

  Future<void> _actualizarAPedido() => _cargar(anunciar: true);

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
      ),
      PantallaGrafico(datos: datos),
      PantallaQueHacer(config: widget.config),
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
          // El botón queda siempre en su lugar (el lector de pantalla no pierde el foco).
          IconButton(
            tooltip: _actualizando ? 'Actualizando' : 'Actualizar',
            onPressed: _actualizando ? null : _actualizarAPedido,
            icon: _actualizando
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(child: IndexedStack(index: _pestana, children: paginas)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _pestana,
        onDestinationSelected: (i) => setState(() => _pestana = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.water), label: 'Inicio'),
          NavigationDestination(icon: Icon(Icons.show_chart), label: 'Gráfico'),
          NavigationDestination(icon: Icon(Icons.health_and_safety), label: 'Qué hacer'),
          NavigationDestination(icon: Icon(Icons.notifications), label: 'Avisos'),
        ],
      ),
    );
  }
}
