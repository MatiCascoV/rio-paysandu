import 'package:flutter/material.dart';
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
  await Notificaciones.iniciar(config, prefs);
  runApp(RioPaysanduApp(config: config, prefs: prefs, repositorio: Repositorio(config.urlBase)));
}

class RioPaysanduApp extends StatelessWidget {
  final Config config;
  final SharedPreferences prefs;
  final Repositorio repositorio;

  const RioPaysanduApp({super.key, required this.config, required this.prefs, required this.repositorio});

  @override
  Widget build(BuildContext context) {
    // Tema claro de alto contraste y letra grande; además se respeta el tamaño
    // de letra que el usuario eligió en su teléfono.
    final esquema = ColorScheme.fromSeed(seedColor: const Color(0xFF0D47A1), contrastLevel: 1);
    final base = ThemeData(colorScheme: esquema, useMaterial3: true);
    return MaterialApp(
      title: 'Río Paysandú',
      debugShowCheckedModeBanner: false,
      locale: const Locale('es'),
      supportedLocales: const [Locale('es')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: base.copyWith(
        textTheme: base.textTheme
            .apply(fontSizeFactor: 1.15, bodyColor: Colors.black, displayColor: Colors.black),
        appBarTheme: AppBarTheme(backgroundColor: esquema.primary, foregroundColor: esquema.onPrimary),
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cargar(primeraVez: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    if (estado == AppLifecycleState.resumed) _cargar(); // al volver a la app, refrescar
  }

  Future<void> _cargar({bool primeraVez = false}) async {
    if (_actualizando) return;
    setState(() => _actualizando = true);
    if (primeraVez) {
      // Primero lo guardado (aparece al instante), después lo nuevo.
      final guardado = await widget.repositorio.cargar(usarRed: false);
      if (mounted && guardado.actual != null) setState(() => _datos = guardado);
    }
    final datos = await widget.repositorio.cargar();
    if (!mounted) return;
    setState(() {
      _datos = datos;
      _actualizando = false;
    });
    if (!datos.sinConexion) await revisarNivel(datos.actual, widget.prefs);
  }

  @override
  Widget build(BuildContext context) {
    final datos = _datos;
    final paginas = [
      PantallaInicio(datos: datos, config: widget.config, alActualizar: _cargar),
      PantallaGrafico(datos: datos),
      PantallaQueHacer(config: widget.config),
      PantallaAjustes(prefs: widget.prefs, umbrales: datos?.umbrales),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Río Uruguay en Paysandú'),
        actions: [
          if (_actualizando)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3, semanticsLabel: 'Actualizando'),
              ),
            )
          else
            IconButton(icon: const Icon(Icons.refresh), tooltip: 'Actualizar', onPressed: _cargar),
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
          NavigationDestination(icon: Icon(Icons.settings), label: 'Ajustes'),
        ],
      ),
    );
  }
}
