import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rio_paysandu/datos.dart';
import 'package:rio_paysandu/main.dart';
import 'package:rio_paysandu/mapa/estilo_mapa.dart';
import 'package:rio_paysandu/mapa/fuente_mapa.dart';
import 'package:rio_paysandu/mapa/repositorio_mapa.dart';
import 'package:rio_paysandu/modelos.dart';
import 'package:rio_paysandu/pantallas/comunes.dart';
import 'package:rio_paysandu/pantallas/mapa.dart';
import 'package:rio_paysandu/pantallas/que_hacer.dart';
import 'package:rio_paysandu/tema.dart';
import 'package:rio_paysandu/textos.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'datos_de_prueba.dart';
import 'fixtures_mapa.dart';

const config = Config(urlBase: 'https://ejemplo.test/data/');
final ahora = DateTime.parse('2026-10-09T13:00:00-03:00');

/// Umbrales que caen dentro del set de prueba (4,00 a 4,30 m).
final umbralesPrueba = Umbrales.desdeJson({'validado': false, 'alerta_m': 4.15, 'evacuacion_m': 4.28});

Datos datosCon(
  double? altura, {
  String nivel = 'alerta',
  bool sinConexion = false,
  String? cero = 'Local',
  bool pronostico = true,
  List<String> avisos = const [],
}) {
  final j = actualFalso(nivel, altura, avisos: avisos);
  if (cero == null) {
    j.remove('cero');
  } else {
    j['cero'] = cero;
  }
  if (!pronostico) (j['pronostico'] as Map)['vigente'] = false;
  return Datos(actual: Actual.desdeJson(j), umbrales: umbralesPrueba, sinConexion: sinConexion);
}

Widget pantalla(
  Datos? datos, {
  RepositorioMapa? repositorio,
  FuenteMapa? fuente,
  DateTime? cuando,
  SharedPreferences? prefs,
  VoidCallback? alVerQueHacer,
  bool activa = true,
}) => MaterialApp(
  locale: const Locale('es'),
  supportedLocales: const [Locale('es')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  theme: temaApp(),
  home: Scaffold(
    body: PantallaMapa(
      datos: datos,
      config: config,
      repositorio: repositorio ?? RepositorioMapa(fuente ?? fuenteDePrueba()),
      prefs: prefs,
      alVerQueHacer: alVerQueHacer,
      activa: activa,
      ahora: cuando ?? ahora,
    ),
  ),
);

Future<void> mostrarMapa(
  WidgetTester t,
  Datos? datos, {
  FuenteMapa? fuente,
  RepositorioMapa? repositorio,
  DateTime? cuando,
  SharedPreferences? prefs,
  VoidCallback? alVerQueHacer,
  bool activa = true,
  Size tamano = const Size(1080, 4400),
}) async {
  t.view.physicalSize = tamano;
  t.view.devicePixelRatio = 2.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    pantalla(
      datos,
      repositorio: repositorio,
      fuente: fuente,
      cuando: cuando,
      prefs: prefs,
      alVerQueHacer: alVerQueHacer,
      activa: activa,
    ),
  );
  await t.pumpAndSettle();
}

/// El número grande de la lectura ("4,20 m"), no el de un botón o una marca.
Finder lectura(String metros) => find.descendant(of: find.byType(LecturaMapa), matching: find.text('$metros m'));

/// Polígonos de agua y de margen pintados, por capa de flutter_map (se
/// reconocen por su estilo: así no importa cuántas otras capas haya, como la
/// zona baja o la zona sin validar). Las capas vacías no cuentan.
List<int> capasDeAguaPintadas(WidgetTester t) {
  final c = ColoresMapa.actuales();
  return [
    for (final capa in t.widgetList<PolygonLayer>(find.byType(PolygonLayer)))
      if (capa.polygons.isNotEmpty &&
          capa.polygons.every(
            (p) =>
                (p.color == c.agua && p.borderColor == c.bordeAgua) ||
                (p.color == c.margen && p.borderColor == c.bordeMargen),
          ))
        capa.polygons.length,
  ];
}

String formatoAlturaPrueba(double m) => m.toStringAsFixed(2).replaceAll('.', ',');

Future<void> tocar(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pumpAndSettle();
}

void main() {
  group('abre en la altura de hoy', () {
    testWidgets('redondea hacia arriba, dice las dos cifras y pinta la capa con su margen', (t) async {
      await mostrarMapa(t, datosCon(4.13));
      expect(find.text('Río hoy: 4,13 m'), findsOneWidget);
      expect(find.text('Alerta'), findsOneWidget); // el nivel, con palabra
      expect(find.text('Altura de hoy en el mapa'), findsOneWidget);
      expect(lectura('4,20'), findsOneWidget);
      expect(find.text('Hoy el río está en 4,13 m. El mapa lo redondea hacia arriba.'), findsOneWidget);
      expect(find.text('Simulación con'), findsNothing);
      expect(find.text('Volver a hoy'), findsNothing);
      // margen (4,40 → tope 4,30) y agua (4,20): dos capas encima del cauce
      expect(capasDeAguaPintadas(t), [1, 1]);
      expect(find.text(textoAtribucion), findsOneWidget);
      expect(find.text(textoAvisoMapa), findsOneWidget);
      expect(find.textContaining('Datos de prueba'), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('− / + mueven 10 cm, la simulación se dice y "Volver a hoy" vuelve', (t) async {
      await mostrarMapa(t, datosCon(4.13));
      await t.tap(find.byTooltip('Subir 10 cm'));
      await t.pumpAndSettle();
      expect(lectura('4,30'), findsOneWidget);
      expect(find.text('No es el río de hoy'), findsOneWidget);
      expect(find.text('Simulación con'), findsOneWidget);
      expect(find.text('10 cm más que hoy.'), findsOneWidget);
      expect(find.text('EVACUACIÓN'), findsOneWidget); // pastilla del nivel de esa altura
      expect(find.text('Volver a hoy'), findsOneWidget);
      // en el máximo el margen coincide con el agua y se dibuja igual (v1.1 §4)
      expect(capasDeAguaPintadas(t), [1, 1]);
      // el + se apaga en el máximo
      expect(t.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.add).last).onPressed, isNull);

      await tocar(t, find.text('Volver a hoy'));
      expect(lectura('4,20'), findsOneWidget);
      expect(find.text('Altura de hoy en el mapa'), findsOneWidget);
      expect(find.text('Volver a hoy'), findsNothing);

      await t.tap(find.byTooltip('Bajar 10 cm'));
      await t.pumpAndSettle();
      expect(lectura('4,10'), findsOneWidget);
      expect(find.text('10 cm menos que hoy.'), findsOneWidget);
      // Normal: sin pastilla (un tilde verde junto a una altura diría "a salvo")
      expect(find.text('NORMAL'), findsNothing);
    });

    testWidgets('el deslizador lee la altura en metros y el nivel para TalkBack', (t) async {
      final semantica = t.ensureSemantics();
      await mostrarMapa(t, datosCon(4.13));
      // Un solo nodo (MergeSemantics) del ancho de la barra: sus datos son los
      // que lee TalkBack, con la altura en metros.
      final slider = t.getSemantics(find.byType(Slider)).getSemanticsData();
      expect(slider.flagsCollection.isSlider, isTrue);
      expect(slider.value, '4,20 metros, nivel Alerta');
      expect(slider.increasedValue, '4,30 metros, nivel Evacuación');
      expect(slider.rect.width, greaterThan(200)); // toda la barra, no solo el pulgar
      expect(
        find.bySemanticsLabel(RegExp(r'^Mapa de la costa de Paysandú.*Agua dibujada con 4,20 metros')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp(r'^Río hoy: 4,13 metros\. Nivel: Alerta\.')), findsOneWidget);
      semantica.dispose();
    });

    testWidgets('si llega un dato nuevo y se está mirando hoy, el mapa lo sigue', (t) async {
      final repo = RepositorioMapa(fuenteDePrueba()); // el mismo, como en la app
      await mostrarMapa(t, datosCon(4.13), repositorio: repo);
      await t.pumpWidget(pantalla(datosCon(4.21), repositorio: repo));
      await t.pumpAndSettle();
      expect(lectura('4,30'), findsOneWidget);
      expect(find.text('Altura de hoy en el mapa'), findsOneWidget);
    });
  });

  group('estados', () {
    testWidgets('río por debajo del mapa: el agua no pasa de la zona baja (nunca "en su cauce")', (t) async {
      await mostrarMapa(t, datosCon(3.20, nivel: 'normal'));
      expect(lectura('3,20'), findsOneWidget);
      expect(find.text('Altura elegida: 3,20 m'), findsOneWidget);
      expect(find.textContaining('el agua no pasa de la zona baja de la costa'), findsOneWidget);
      expect(find.textContaining('el agua queda en su cauce'), findsNothing);
      expect(capasDeAguaPintadas(t), isEmpty); // la capa de 4,00 de prueba está vacía
    });

    testWidgets('río por encima del mapa: se pinta el máximo y se avisa', (t) async {
      await mostrarMapa(t, datosCon(9.00, nivel: 'evacuacion'));
      expect(find.text('Río hoy: 9,00 m'), findsOneWidget);
      expect(lectura('9,00'), findsOneWidget);
      expect(
        find.text('El mapa llega hasta 4,30 m. Con más altura, el agua llega más lejos de lo que se ve.'),
        findsOneWidget,
      );
      expect(capasDeAguaPintadas(t), [1, 1]); // la máxima, con su margen
    });

    testWidgets('sin dato: lo dice y abre en el nivel de alerta, como simulación', (t) async {
      await mostrarMapa(t, datosCon(null, nivel: 'sin_dato'));
      expect(find.text('Río hoy: sin dato'), findsOneWidget);
      expect(find.textContaining('No hay un dato confiable de hoy'), findsOneWidget);
      expect(lectura('4,20'), findsOneWidget); // alerta 4,15 → 4,20
      expect(find.text('Simulación con'), findsOneWidget);
      expect(find.text('No hay dato del río de hoy.'), findsOneWidget);
      expect(find.textContaining('No es el río de hoy'), findsNothing);
      expect(find.text('Volver a hoy'), findsNothing);
      expect(find.text('Hoy'), findsNothing); // sin botón Hoy
    });

    testWidgets('dato viejo: lo avisa y habla de "Último dato"', (t) async {
      await mostrarMapa(t, datosCon(4.13), cuando: ahora.add(const Duration(hours: 9)));
      expect(find.text('Último dato: 4,13 m'), findsOneWidget);
      expect(
        find.text('El último dato es de hoy 12:00. El río pudo cambiar: mirá Inicio o los canales oficiales.'),
        findsOneWidget,
      );
      expect(find.text('Altura del último dato en el mapa'), findsOneWidget);
      expect(lectura('4,20'), findsOneWidget);
      await t.tap(find.byTooltip('Subir 10 cm'));
      await t.pumpAndSettle();
      expect(find.text('No es el último dato'), findsOneWidget);
      expect(find.text('Volver al último dato'), findsOneWidget);
    });

    testWidgets('dato de más de 48 h: como sin dato', (t) async {
      await mostrarMapa(t, datosCon(4.13), cuando: ahora.add(const Duration(hours: 60)));
      expect(find.text('Río hoy: sin dato'), findsOneWidget);
    });

    testWidgets('sin conexión con dato fresco: renglón en la franja, no recuadro', (t) async {
      await mostrarMapa(t, datosCon(4.13, sinConexion: true));
      expect(find.text('Último dato: 4,13 m'), findsOneWidget);
      expect(find.text('Sin conexión. Dato guardado en este teléfono.'), findsOneWidget);
      expect(find.byType(Recuadro), findsNothing);
      expect(lectura('4,20'), findsOneWidget);
    });

    testWidgets('cero distinto: no pinta la altura de hoy', (t) async {
      await mostrarMapa(t, datosCon(4.13, cero: 'Oficial'));
      expect(find.textContaining('otra referencia de altura'), findsOneWidget);
      expect(find.text('Río hoy: no se puede pintar'), findsOneWidget);
      expect(find.text('Río hoy: 4,13 m'), findsNothing);
      expect(find.text('Altura de hoy en el mapa'), findsNothing);
    });

    testWidgets('sin archivos del mapa: estado claro, sin romper', (t) async {
      await mostrarMapa(t, datosCon(4.13), fuente: FuenteMemoria({}));
      expect(find.text(textoMapaNoDisponible), findsOneWidget);
      expect(find.byType(FlutterMap), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('índice que no valida: mismo estado', (t) async {
      await mostrarMapa(t, datosCon(4.13), fuente: fuenteDePrueba(indice: (j) => (j['capas'] as List).removeLast()));
      expect(find.text(textoMapaNoDisponible), findsOneWidget);
    });

    testWidgets('capa con huella rota: usa la de arriba y lo dice', (t) async {
      await mostrarMapa(
        t,
        datosCon(4.13),
        fuente: fuenteDePrueba(archivos: {'agua/0420.json': jsonABytes(capaDePrueba(430))}),
      );
      expect(lectura('4,20'), findsOneWidget);
      expect(
        find.text('No se pudo leer el dibujo de 4,20 m. Se muestra el de 4,30 m, con un poco más de agua.'),
        findsOneWidget,
      );
    });

    testWidgets('datos PROVISORIOS: sello bien visible arriba del mapa', (t) async {
      await mostrarMapa(t, datosCon(4.13), fuente: fuenteDePrueba(metodo: 'PROVISORIO: inventado'));
      expect(find.text(textoMapaProvisorio), findsOneWidget);
      expect(find.text(textoMapaEnPrueba), findsNothing); // gana el provisorio
      expect(t.getRect(find.text(textoMapaProvisorio)).top, lessThan(t.getRect(find.byType(FlutterMap)).top));
    });

    testWidgets('esperando el nivel del río', (t) async {
      await mostrarMapa(t, null);
      expect(find.text('Cargando el nivel del río…'), findsOneWidget);
    });

    testWidgets('"Ver qué hacer" solo con alerta o evacuación de hoy', (t) async {
      var tocado = 0;
      await mostrarMapa(t, datosCon(4.13), alVerQueHacer: () => tocado++);
      expect(find.byType(BotonQueHacer), findsOneWidget);
      await tocar(t, find.text('Ver qué hacer'));
      expect(tocado, 1);
      // Simular una altura de evacuación no lo hace aparecer si hoy es normal.
      await mostrarMapa(t, datosCon(3.20, nivel: 'normal'), alVerQueHacer: () => tocado++);
      expect(find.byType(BotonQueHacer), findsNothing);
      await tocar(t, find.text('Nivel de evacuación'));
      expect(find.byType(BotonQueHacer), findsNothing);
    });
  });

  group('avisos: uno solo y con prioridad', () {
    final lectura0 = Lectura.desdeJson({'valor_m': 4.13, 'fecha': '2026-10-09T12:00:00-03:00'});
    test('prioridad: otra referencia > sin dato > viejo > a verificar; sin conexión fresca no es recuadro', () {
      expect(avisoHoyMapa(const HoyMapa(motivo: 'cero'), ahora)!.texto, contains('otra referencia de altura'));
      expect(avisoHoyMapa(const HoyMapa(motivo: 'sin_dato'), ahora)!.texto, startsWith('No hay un dato confiable'));
      final sinRed = avisoHoyMapa(const HoyMapa(motivo: 'sin_dato', sinConexion: true), ahora)!;
      expect(sinRed.texto, startsWith('Sin conexión y sin un dato confiable'));
      expect(sinRed.icono, Icons.wifi_off);
      final viejoYDudoso = HoyMapa(
        lectura: lectura0,
        nivel: Nivel.alerta,
        viejo: true,
        avisos: const ['dato_a_verificar'],
      );
      expect(avisoHoyMapa(viejoYDudoso, ahora)!.icono, Icons.schedule);
      final dudoso = HoyMapa(lectura: lectura0, nivel: Nivel.alerta, avisos: const ['dato_a_verificar']);
      expect(avisoHoyMapa(dudoso, ahora)!.texto, textoAviso('dato_a_verificar'));
      expect(avisoHoyMapa(HoyMapa(lectura: lectura0, nivel: Nivel.alerta, sinConexion: true), ahora), isNull);
      expect(avisoHoyMapa(HoyMapa(lectura: lectura0, nivel: Nivel.alerta), ahora), isNull);
    });

    testWidgets('sin dato + mapa en prueba: un recuadro y el sello, nunca dos recuadros', (t) async {
      for (final (datos, cuando) in [
        (datosCon(null, nivel: 'sin_dato'), ahora),
        (datosCon(null, nivel: 'sin_dato', sinConexion: true), ahora),
        (datosCon(4.13), ahora.add(const Duration(hours: 9))),
        (datosCon(4.13, cero: 'Oficial'), ahora),
        (datosCon(4.13, avisos: const ['dato_a_verificar'], sinConexion: true), ahora),
      ]) {
        await mostrarMapa(t, datos, cuando: cuando);
        expect(find.byType(Recuadro), findsOneWidget);
        expect(find.text(textoMapaEnPrueba), findsOneWidget);
      }
    });
  });

  group('alturas para comparar', () {
    testWidgets('Hoy y Pronóstico CARU aparecen solo cuando corresponde', (t) async {
      await mostrarMapa(t, datosCon(4.13));
      expect(find.text('Hoy'), findsOneWidget);
      expect(find.text('Pronóstico CARU'), findsOneWidget);
      expect(find.text('hasta 6,66 m · 8/10'), findsOneWidget);
      expect(find.text('Nivel de alerta'), findsOneWidget);
      expect(find.text('4,15 m (de referencia)'), findsOneWidget);
      expect(find.text('Crecida de prueba'), findsOneWidget);
      // Hoy marcado, con tilde (no solo color)
      expect(find.descendant(of: find.byType(BotonAltura).first, matching: find.byIcon(Icons.check)), findsOneWidget);

      await mostrarMapa(t, datosCon(4.13, pronostico: false));
      expect(find.text('Pronóstico CARU'), findsNothing);
      await mostrarMapa(t, datosCon(4.13, cero: 'Oficial'));
      expect(find.text('Pronóstico CARU'), findsNothing);
      expect(find.text('Hoy'), findsNothing);
      await mostrarMapa(t, datosCon(4.13, sinConexion: true));
      expect(find.text('Último dato'), findsOneWidget);
    });

    test('columnas: dos si entran, una a 320 dp o con letra grande', () {
      expect(columnasAlturas(380, 1.0), 2);
      expect(columnasAlturas(328, 1.0), 2);
      expect(columnasAlturas(288, 1.0), 1);
      expect(columnasAlturas(380, 1.3), 1);
      expect(columnasAlturas(508, 1.3), 2);
    });

    testWidgets('grilla de dos columnas en un teléfono común y de una a 320 dp', (t) async {
      await mostrarMapa(t, datosCon(4.13), tamano: const Size(824, 4400)); // 412 dp
      Rect boton(String texto) => t.getRect(find.widgetWithText(BotonAltura, texto));
      expect(boton('Hoy').top, boton('Pronóstico CARU').top);
      expect(boton('Hoy').height, boton('Pronóstico CARU').height); // misma altura en la fila
      await mostrarMapa(t, datosCon(4.13), tamano: const Size(640, 4400)); // 320 dp
      expect(boton('Pronóstico CARU').top, greaterThan(boton('Hoy').bottom));
    });

    testWidgets('vibra solo al cruzar un umbral', (t) async {
      final vibraciones = <Object?>[];
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (llamada) async {
        if (llamada.method == 'HapticFeedback.vibrate') vibraciones.add(llamada.arguments);
        return null;
      });
      addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await mostrarMapa(t, datosCon(4.13)); // 4,20
      await t.tap(find.byTooltip('Bajar 10 cm')); // 4,10: cruza alerta (4,15)
      await t.pumpAndSettle();
      expect(vibraciones, ['HapticFeedbackType.selectionClick']);
      await t.tap(find.byTooltip('Bajar 10 cm')); // 4,00: no cruza nada
      await t.pumpAndSettle();
      expect(vibraciones, hasLength(1));
      await tocar(t, find.text('Nivel de evacuación')); // 4,00 → 4,30: cruza dos
      expect(vibraciones, hasLength(2));
    });
  });

  group('cómo se usa y vuelta a hoy', () {
    testWidgets('"Cómo se usa" se muestra una vez y queda guardado', (t) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await mostrarMapa(t, datosCon(4.13), prefs: prefs);
      expect(find.text('Entendido'), findsOneWidget);
      expect(find.text(pasosComoSeUsa.first), findsOneWidget);
      await tocar(t, find.text('Entendido'));
      expect(find.text('Entendido'), findsNothing);
      expect(prefs.getBool(claveComoSeUsa), isTrue);
      await mostrarMapa(t, datosCon(4.13), prefs: prefs, repositorio: RepositorioMapa(fuenteDePrueba()));
      expect(find.text('Entendido'), findsNothing);
      // Sigue a mano desde el pie.
      await tocar(t, find.widgetWithText(TextButton, 'Cómo se usa'));
      expect(find.text(pasosComoSeUsa.first), findsOneWidget);
      await tocar(t, find.text('Cerrar'));
      expect(find.text(pasosComoSeUsa.first), findsNothing);
    });

    testWidgets('"Ver fuentes": solo texto, con las cuatro fuentes', (t) async {
      await mostrarMapa(t, datosCon(4.13));
      await tocar(t, find.text('Ver fuentes'));
      expect(find.text('Fuentes del mapa'), findsOneWidget);
      expect(find.textContaining('© colaboradores de OpenStreetMap'), findsOneWidget);
      expect(find.textContaining('IDE Uruguay'), findsWidgets);
      expect(find.textContaining('Dinagua'), findsWidgets);
      expect(find.text(textoFuentesDeslinde), findsOneWidget);
      expect(find.text('Datos sintéticos de prueba'), findsOneWidget); // fuentes del índice
    });

    testWidgets('al volver a la pestaña, una simulación vuelve a hoy', (t) async {
      final repo = RepositorioMapa(fuenteDePrueba());
      await mostrarMapa(t, datosCon(4.13), repositorio: repo);
      await tocar(t, find.text('Crecida de prueba'));
      await tocar(t, find.byType(Switch));
      expect(find.text('Simulación con'), findsOneWidget);
      final datos = datosCon(4.13);
      await t.pumpWidget(pantalla(datos, repositorio: repo, activa: false));
      await t.pumpAndSettle();
      expect(find.text('Simulación con'), findsOneWidget); // mientras no se ve, no cambia
      await t.pumpWidget(pantalla(datos, repositorio: repo));
      await t.pumpAndSettle();
      expect(find.text('Simulación con'), findsNothing);
      expect(lectura('4,20'), findsOneWidget);
      expect(find.byType(Switch), findsNothing); // el borde medido se apagó
    });
  });

  group('colores', () {
    test('panel de simulación con contraste de 7:1 o más en los dos modos', () {
      for (final oscuro in [false, true]) {
        Colores.oscuro = oscuro;
        expect(contraste(ColoresSimulacion.texto, ColoresSimulacion.fondo), greaterThanOrEqualTo(7));
      }
      Colores.oscuro = false;
    });
  });

  for (final escala in [1.3, 2.0]) {
    for (final oscuro in [false, true]) {
      testWidgets('320 dp con letra al ${(escala * 100).round()} %${oscuro ? ', oscuro' : ''}: nada se desborda', (
        t,
      ) async {
        Colores.oscuro = oscuro;
        addTearDown(() => Colores.oscuro = false);
        t.platformDispatcher.textScaleFactorTestValue = escala;
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        for (final (datos, cuando) in [
          (datosCon(4.13), ahora),
          (datosCon(null, nivel: 'sin_dato'), ahora),
          (datosCon(9.0, sinConexion: true, nivel: 'evacuacion'), ahora),
          (datosCon(4.13), ahora.add(const Duration(hours: 9))),
          (datosCon(4.13, cero: 'Oficial'), ahora),
          (datosCon(3.2, nivel: 'normal'), ahora),
        ]) {
          await mostrarMapa(
            t,
            datos,
            cuando: cuando,
            prefs: prefs,
            alVerQueHacer: () {},
            repositorio: RepositorioMapa(fuenteDePrueba()),
            tamano: const Size(640, 4400), // 320 dp de ancho
          );
          expect(t.takeException(), isNull);
          // Con letra al 200 % el control queda más abajo de lo que entra en
          // la pantalla: se baja hasta él, como haría la persona.
          await tocar(t, find.byTooltip('Bajar 10 cm'));
          await tocar(t, find.text('Crecida de prueba'));
          await tocar(t, find.byType(Switch));
          await t.ensureVisible(find.text('Ver fuentes'));
          await t.pumpAndSettle();
          expect(find.byType(Recuadro).evaluate().length, lessThanOrEqualTo(1));
          expect(t.takeException(), isNull);
        }
        await tocar(t, find.text('Ver fuentes'));
        await t.ensureVisible(find.text('Cerrar'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      });
    }
  }

  group('listo para los datos reales', () {
    testWidgets('validado: false → sello de mapa en prueba arriba del mapa; el pie siempre', (t) async {
      await mostrarMapa(t, datosCon(4.13));
      expect(find.text(textoMapaEnPrueba), findsOneWidget);
      expect(find.text(textoAvisoMapa), findsOneWidget);
      expect(textoAvisoMapa, contains('No reemplaza la alerta oficial'));
      // va antes del mapa, no escondido al pie
      expect(t.getRect(find.text(textoMapaEnPrueba)).top, lessThan(t.getRect(find.byType(FlutterMap)).top));
      // y el pie, justo debajo del mapa
      expect(t.getRect(find.text(textoAvisoMapa)).top, greaterThan(t.getRect(find.byType(FlutterMap)).bottom));

      await mostrarMapa(t, datosCon(4.13), fuente: fuenteDePrueba(validado: true));
      expect(find.text(textoMapaEnPrueba), findsNothing);
      expect(find.text(textoAvisoMapa), findsOneWidget);
    });

    testWidgets('nunca promete seguridad, en ningún estado', (t) async {
      final prohibidos = [
        RegExp('a salvo', caseSensitive: false),
        RegExp(r'\bsegur[oa]\b', caseSensitive: false),
        RegExp('zona segura', caseSensitive: false),
        RegExp('no se inunda', caseSensitive: false),
        RegExp('sin peligro', caseSensitive: false),
      ];
      for (final (datos, cuando) in [
        (datosCon(3.20, nivel: 'normal'), ahora),
        (datosCon(4.13), ahora),
        (datosCon(9.0, nivel: 'evacuacion'), ahora),
        (datosCon(null, nivel: 'sin_dato'), ahora),
        (datosCon(4.13), ahora.add(const Duration(hours: 9))),
        (datosCon(4.13, sinConexion: true), ahora),
        (datosCon(4.13, cero: 'Oficial'), ahora),
      ]) {
        await mostrarMapa(t, datos, cuando: cuando, alVerQueHacer: () {});
        for (final prohibido in prohibidos) {
          expect(find.textContaining(prohibido), findsNothing);
        }
        await t.tap(find.byTooltip('Bajar 10 cm'));
        await t.pumpAndSettle();
        for (final prohibido in prohibidos) {
          expect(find.textContaining(prohibido), findsNothing);
        }
      }
    });

    testWidgets('índice en otra escala (cero distinto de "Local"): no dibuja agua', (t) async {
      await mostrarMapa(t, datosCon(4.13), fuente: fuenteDePrueba(indice: (j) => j['cero'] = 'Oficial'));
      expect(find.text(textoMapaNoDisponible), findsOneWidget);
      expect(find.textContaining('otra referencia de altura ("Oficial")'), findsOneWidget);
      expect(find.byType(FlutterMap), findsNothing);
    });

    testWidgets('actual.json en otra escala: ni hoy ni umbrales se llevan al mapa', (t) async {
      await mostrarMapa(t, datosCon(4.13, cero: 'Oficial'));
      expect(find.textContaining('Nivel de alerta'), findsNothing);
      expect(find.textContaining('Alerta:'), findsNothing);
      expect(find.text('ALERTA'), findsNothing);
      // abre en la capa más baja del mapa, no en la alerta (4,15 → 4,20)
      expect(lectura('4,00'), findsOneWidget);
      expect(lectura('4,20'), findsNothing);
    });

    for (final (altura, metros, aviso) in [
      (6.73, '6,80', null),
      (3.85, '3,90', 'el agua no pasa de la zona baja de la costa'),
      (10.80, '10,80', 'El mapa llega hasta 10,50 m'),
    ]) {
      testWidgets('rango del contrato 4,00–10,50 m con ${formatoAlturaPrueba(altura)} m', (t) async {
        await mostrarMapa(t, datosCon(altura, nivel: 'evacuacion'), fuente: fuenteRangoReal());
        expect(lectura(metros), findsOneWidget);
        if (aviso != null) expect(find.textContaining(aviso), findsOneWidget);
        final slider = t.widget<Slider>(find.byType(Slider));
        expect(slider.max, greaterThanOrEqualTo(1050));
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('crecida real: botón, redondeo dicho y contorno opcional de la curva', (t) async {
      await mostrarMapa(t, datosCon(4.13));
      expect(capasDeAguaPintadas(t), [1, 1]); // margen y agua
      await tocar(t, find.text('Crecida de prueba'));
      expect(lectura('4,30'), findsOneWidget);
      expect(find.textContaining('El mapa lo redondea hacia arriba a 4,30 m'), findsOneWidget);
      // el contorno es opcional: arranca apagado
      expect(t.widget<Switch>(find.byType(Switch)).value, isFalse);
      expect(find.textContaining('Borde medido en esa crecida'), findsNothing);
      await tocar(t, find.byType(Switch));
      final capas = t.widgetList<PolygonLayer>(find.byType(PolygonLayer)).toList();
      expect(capas.last.polygons.single.borderStrokeWidth, greaterThan(2));
      expect(find.textContaining('Borde medido en esa crecida'), findsOneWidget);
      // al moverse a otra altura, el contorno se va
      await tocar(t, find.byTooltip('Bajar 10 cm'));
      expect(find.byType(Switch), findsNothing);
      expect(find.textContaining('Borde medido en esa crecida'), findsNothing);
    });

    testWidgets('curva con la huella rota: lo dice y no dibuja nada', (t) async {
      await mostrarMapa(
        t,
        datosCon(4.13),
        fuente: fuenteDePrueba(archivos: {'curvas/2015-12.json': jsonABytes(curvaDePrueba(nombre: 'otra'))}),
      );
      await tocar(t, find.text('Crecida de prueba'));
      await tocar(t, find.byType(Switch));
      expect(find.text('No se pudo leer el borde medido de esa crecida.'), findsOneWidget);
      expect(capasDeAguaPintadas(t), [1, 1]); // margen (en 4,30 coincide con el agua) y agua, sin contorno
    });

    testWidgets('sin dato al abrir y después llega uno: el mapa pasa a la altura de hoy', (t) async {
      final repo = RepositorioMapa(fuenteDePrueba()); // el mismo, como en la app
      await mostrarMapa(t, datosCon(null, nivel: 'sin_dato'), repositorio: repo);
      expect(lectura('4,20'), findsOneWidget); // alerta 4,15
      expect(find.text('Simulación con'), findsOneWidget);
      await mostrarMapa(t, datosCon(4.27), repositorio: repo);
      expect(lectura('4,30'), findsOneWidget);
      expect(find.text('Altura de hoy en el mapa'), findsOneWidget);
    });

    testWidgets('si la persona eligió otra altura, un dato nuevo no se la cambia', (t) async {
      final repo = RepositorioMapa(fuenteDePrueba());
      await mostrarMapa(t, datosCon(4.13), repositorio: repo);
      await t.tap(find.byTooltip('Bajar 10 cm'));
      await t.pumpAndSettle();
      await mostrarMapa(t, datosCon(4.27), repositorio: repo);
      expect(lectura('4,10'), findsOneWidget);
      expect(find.text('Volver a hoy'), findsOneWidget);
    });
  });

  group('navegación con cinco pestañas', () {
    Future<SharedPreferences> app(WidgetTester t, {double escala = 1.0, Size tamano = const Size(1080, 2340)}) async {
      t.view.physicalSize = tamano;
      t.view.devicePixelRatio = 2.0;
      t.platformDispatcher.textScaleFactorTestValue = escala;
      addTearDown(t.view.reset);
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final falso = actualFalso('alerta', 4.13);
      (falso['altura_actual'] as Map)['fecha'] = DateTime.now().toUtc().toIso8601String();
      falso['generado'] = DateTime.now().toUtc().toIso8601String();
      final cliente = MockClient(
        (pedido) async => http.Response.bytes(
          utf8.encode(switch (pedido.url.pathSegments.last) {
            'actual.json' => jsonEncode(falso),
            'umbrales.json' => umbralesReal,
            _ => '[]',
          }),
          200,
        ),
      );
      await t.pumpWidget(
        RioPaysanduApp(
          config: config,
          prefs: prefs,
          repositorio: Repositorio(config.urlBase, cliente: cliente),
          repositorioMapa: RepositorioMapa(fuenteDePrueba()),
        ),
      );
      await t.pumpAndSettle();
      return prefs;
    }

    Finder pestana(Pestana p) => find.descendant(of: find.byType(NavigationBar), matching: find.text(p.etiqueta));

    testWidgets('orden de las pestañas y Mapa en la tercera', (t) async {
      await app(t);
      final barra = t.widget<NavigationBar>(find.byType(NavigationBar));
      expect(barra.destinations.map((d) => (d as NavigationDestination).label), [
        'Inicio',
        'Gráfico',
        'Mapa',
        'Qué hacer',
        'Avisos',
      ]);
      expect(Pestana.values.map((p) => p.etiqueta), ['Inicio', 'Gráfico', 'Mapa', 'Qué hacer', 'Avisos']);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('el mapa se arma recién al visitarlo, abre en hoy y se tiñe como Inicio', (t) async {
      await app(t);
      expect(find.byType(PantallaMapa), findsNothing);
      final tinteInicio = t.widget<AppBar>(find.byType(AppBar)).backgroundColor;
      expect(tinteInicio, ColoresNivel.tinte(Nivel.alerta));
      await t.tap(pestana(Pestana.mapa));
      await t.pumpAndSettle();
      expect(find.byType(PantallaMapa), findsOneWidget);
      expect(lectura('4,20'), findsOneWidget);
      expect(find.text('Altura de hoy en el mapa'), findsOneWidget);
      expect(t.widget<AppBar>(find.byType(AppBar)).backgroundColor, tinteInicio);
      // La primera vez, "Cómo se usa".
      expect(find.text('Entendido'), findsOneWidget);
      // Simular y salir: al volver, está en hoy otra vez.
      await tocar(t, find.byTooltip('Subir 10 cm'));
      expect(find.text('Simulación con'), findsOneWidget);
      expect(t.widget<AppBar>(find.byType(AppBar)).backgroundColor, tinteInicio); // el tinte es el de hoy
      await t.tap(pestana(Pestana.inicio));
      await t.pumpAndSettle();
      expect(find.byType(PantallaMapa, skipOffstage: false), findsOneWidget); // sigue armado
      await t.tap(pestana(Pestana.grafico));
      await t.pumpAndSettle();
      expect(t.widget<AppBar>(find.byType(AppBar)).backgroundColor, isNull); // Gráfico no se tiñe
      await t.tap(pestana(Pestana.mapa));
      await t.pumpAndSettle();
      expect(find.text('Simulación con'), findsNothing);
      expect(lectura('4,20'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('"Ver qué hacer" del Mapa lleva a Qué hacer', (t) async {
      await app(t);
      await t.tap(pestana(Pestana.mapa));
      await t.pumpAndSettle();
      await tocar(t, find.descendant(of: find.byType(PantallaMapa), matching: find.text('Ver qué hacer')));
      expect(t.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex, Pestana.queHacer.index);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('"Ver qué hacer" de Inicio lleva a Qué hacer, no a otra pestaña', (t) async {
      await app(t);
      await t.tap(find.text('Ver qué hacer').first);
      await t.pumpAndSettle();
      final barra = t.widget<NavigationBar>(find.byType(NavigationBar));
      expect(barra.selectedIndex, Pestana.queHacer.index);
      expect(find.byType(PantallaQueHacer), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });

    for (final escala in [1.0, 1.3, 2.0]) {
      testWidgets('cinco etiquetas a 320 dp con letra al ${(escala * 100).round()} %: sin desborde', (t) async {
        await app(t, escala: escala, tamano: const Size(640, 1400));
        for (final p in [...Pestana.values.skip(1), Pestana.inicio]) {
          await t.tap(pestana(p));
          await t.pumpAndSettle();
          expect(t.takeException(), isNull, reason: 'desborde en ${p.etiqueta}');
        }
        // Cada etiqueta entra en su lugar (no se corta ni se sale de la barra).
        final barra = t.getRect(find.byType(NavigationBar));
        for (final p in Pestana.values) {
          final r = t.getRect(pestana(p));
          expect(r.left, greaterThanOrEqualTo(barra.left));
          expect(r.right, lessThanOrEqualTo(barra.right));
          expect(r.width, lessThanOrEqualTo(barra.width / 5 + 0.5), reason: '${p.etiqueta} más ancha que su lugar');
        }
        await t.pumpWidget(const SizedBox());
      });
    }
  });
}
