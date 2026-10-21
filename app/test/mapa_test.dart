import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rio_paysandu/datos.dart';
import 'package:rio_paysandu/main.dart';
import 'package:rio_paysandu/mapa/fuente_mapa.dart';
import 'package:rio_paysandu/mapa/repositorio_mapa.dart';
import 'package:rio_paysandu/modelos.dart';
import 'package:rio_paysandu/pantallas/mapa.dart';
import 'package:rio_paysandu/pantallas/que_hacer.dart';
import 'package:rio_paysandu/tema.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'datos_de_prueba.dart';
import 'fixtures_mapa.dart';

const config = Config(urlBase: 'https://ejemplo.test/data/');
final ahora = DateTime.parse('2026-10-09T13:00:00-03:00');

/// Umbrales que caen dentro del set de prueba (4,00 a 4,30 m).
final umbralesPrueba = Umbrales.desdeJson({'validado': false, 'alerta_m': 4.15, 'evacuacion_m': 4.28});

Datos datosCon(double? altura, {String nivel = 'alerta', bool sinConexion = false, String? cero = 'Local'}) {
  final j = actualFalso(nivel, altura);
  if (cero == null) {
    j.remove('cero');
  } else {
    j['cero'] = cero;
  }
  return Datos(actual: Actual.desdeJson(j), umbrales: umbralesPrueba, sinConexion: sinConexion);
}

Future<void> mostrarMapa(
  WidgetTester t,
  Datos? datos, {
  FuenteMapa? fuente,
  RepositorioMapa? repositorio,
  DateTime? cuando,
  Size tamano = const Size(1080, 4400),
}) async {
  t.view.physicalSize = tamano;
  t.view.devicePixelRatio = 2.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      locale: const Locale('es'),
      supportedLocales: const [Locale('es')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: temaApp(),
      home: Scaffold(
        body: PantallaMapa(
          datos: datos,
          config: config,
          repositorio: repositorio ?? RepositorioMapa(fuente ?? fuenteDePrueba()),
          ahora: cuando ?? ahora,
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

/// Polígonos de agua pintados (sin el cauce del fondo), por capa de flutter_map.
List<int> capasDeAguaPintadas(WidgetTester t) =>
    t.widgetList<PolygonLayer>(find.byType(PolygonLayer)).skip(1).map((c) => c.polygons.length).toList();

String formatoAlturaPrueba(double m) => m.toStringAsFixed(2).replaceAll('.', ',');

void main() {
  group('abre en la altura de hoy', () {
    testWidgets('redondea hacia arriba, dice las dos cifras y pinta la capa con su margen', (t) async {
      await mostrarMapa(t, datosCon(4.13));
      expect(find.text('Río hoy: 4,13 m'), findsOneWidget);
      expect(find.text('Alerta'), findsOneWidget); // el nivel, con palabra
      expect(find.text('Se muestra el agua con 4,20 m'), findsOneWidget);
      expect(find.textContaining('Es la altura de hoy, redondeada hacia arriba'), findsOneWidget);
      expect(find.text('Volver a hoy'), findsNothing);
      // margen (4,40 → tope 4,30) y agua (4,20): dos capas encima del cauce
      expect(capasDeAguaPintadas(t), [1, 1]);
      expect(find.text(textoAtribucion), findsOneWidget);
      expect(find.text(textoAvisoMapa), findsOneWidget);
      expect(find.textContaining('Datos de prueba'), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('− / + mueven 10 cm y "Volver a hoy" vuelve', (t) async {
      await mostrarMapa(t, datosCon(4.13));
      await t.tap(find.byTooltip('Subir 10 cm'));
      await t.pumpAndSettle();
      expect(find.text('Se muestra el agua con 4,30 m'), findsOneWidget);
      expect(find.textContaining('No es el río de hoy: es una prueba con 4,30 m (10 cm más que hoy)'), findsOneWidget);
      expect(find.text('Volver a hoy'), findsOneWidget);
      expect(capasDeAguaPintadas(t), [1]); // en el máximo no hay margen aparte
      // el + se apaga en el máximo
      expect(t.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.add).last).onPressed, isNull);

      await t.tap(find.text('Volver a hoy'));
      await t.pumpAndSettle();
      expect(find.text('Se muestra el agua con 4,20 m'), findsOneWidget);
      expect(find.text('Volver a hoy'), findsNothing);

      await t.tap(find.byTooltip('Bajar 10 cm'));
      await t.pumpAndSettle();
      expect(find.text('Se muestra el agua con 4,10 m'), findsOneWidget);
      expect(find.textContaining('10 cm menos que hoy'), findsOneWidget);
    });

    testWidgets('el deslizador lee la altura en metros para TalkBack', (t) async {
      final semantica = t.ensureSemantics();
      await mostrarMapa(t, datosCon(4.13));
      // Un solo nodo (MergeSemantics) del ancho de la barra: sus datos son los
      // que lee TalkBack, con la altura en metros.
      final slider = t.getSemantics(find.byType(Slider)).getSemanticsData();
      expect(slider.flagsCollection.isSlider, isTrue);
      expect(slider.value, '4,20 metros');
      expect(slider.increasedValue, '4,30 metros');
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
      await t.pumpWidget(
        MaterialApp(
          theme: temaApp(),
          home: Scaffold(
            body: PantallaMapa(
              datos: datosCon(4.21),
              config: config,
              repositorio: repo,
              ahora: ahora,
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Se muestra el agua con 4,30 m'), findsOneWidget);
    });
  });

  group('estados', () {
    testWidgets('río por debajo del mapa: el agua queda en su cauce', (t) async {
      await mostrarMapa(t, datosCon(3.20, nivel: 'normal'));
      expect(find.text('Altura elegida: 3,20 m'), findsOneWidget);
      expect(find.textContaining('el agua queda en su cauce'), findsOneWidget);
      expect(capasDeAguaPintadas(t), isEmpty);
    });

    testWidgets('río por encima del mapa: se pinta el máximo y se avisa', (t) async {
      await mostrarMapa(t, datosCon(9.00, nivel: 'evacuacion'));
      expect(find.text('Río hoy: 9,00 m'), findsOneWidget);
      expect(find.text('Se muestra el agua con 4,30 m'), findsOneWidget);
      expect(find.textContaining('El río supera lo que cubre el mapa (hasta 4,30 m)'), findsOneWidget);
      expect(capasDeAguaPintadas(t), [1]);
    });

    testWidgets('sin dato: lo dice y abre en el nivel de alerta', (t) async {
      await mostrarMapa(t, datosCon(null, nivel: 'sin_dato'));
      expect(find.text('Río hoy: sin dato confiable'), findsOneWidget);
      expect(find.textContaining('No hay un dato confiable de hoy'), findsOneWidget);
      expect(find.text('Se muestra el agua con 4,20 m'), findsOneWidget); // alerta 4,15 → 4,20
      expect(find.textContaining('No es el río de hoy'), findsNothing);
      expect(find.text('Volver a hoy'), findsNothing);
    });

    testWidgets('dato viejo: lo avisa y habla de "Último dato"', (t) async {
      await mostrarMapa(t, datosCon(4.13), cuando: ahora.add(const Duration(hours: 9)));
      expect(find.text('Último dato: 4,13 m'), findsOneWidget);
      expect(find.textContaining('El último dato es de hoy 12:00. El río pudo cambiar.'), findsOneWidget);
      expect(find.text('Se muestra el agua con 4,20 m'), findsOneWidget);
    });

    testWidgets('dato de más de 48 h: como sin dato', (t) async {
      await mostrarMapa(t, datosCon(4.13), cuando: ahora.add(const Duration(hours: 60)));
      expect(find.text('Río hoy: sin dato confiable'), findsOneWidget);
    });

    testWidgets('sin conexión: el mapa funciona y lo dice', (t) async {
      await mostrarMapa(t, datosCon(4.13, sinConexion: true));
      expect(find.text('Último dato: 4,13 m'), findsOneWidget);
      expect(find.textContaining('Sin conexión. El mapa funciona igual'), findsOneWidget);
      expect(find.text('Se muestra el agua con 4,20 m'), findsOneWidget);
    });

    testWidgets('cero distinto: no pinta la altura de hoy', (t) async {
      await mostrarMapa(t, datosCon(4.13, cero: 'Oficial'));
      expect(find.textContaining('otra referencia de altura'), findsOneWidget);
      expect(find.text('Río hoy: 4,13 m'), findsNothing);
      expect(find.textContaining('Es la altura de hoy'), findsNothing);
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
      expect(find.text('Se muestra el agua con 4,30 m'), findsOneWidget);
      expect(find.textContaining('No se pudo leer el dibujo de 4,20 m; se muestra el de 4,30 m.'), findsOneWidget);
    });

    testWidgets('datos PROVISORIOS: aviso bien visible', (t) async {
      await mostrarMapa(t, datosCon(4.13), fuente: fuenteDePrueba(metodo: 'PROVISORIO: inventado'));
      expect(find.textContaining('Datos de prueba: el agua de este mapa es inventada'), findsOneWidget);
    });

    testWidgets('esperando el nivel del río', (t) async {
      await mostrarMapa(t, null);
      expect(find.text('Cargando el nivel del río…'), findsOneWidget);
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
        for (final datos in [datosCon(4.13), datosCon(null, nivel: 'sin_dato'), datosCon(9.0, sinConexion: true)]) {
          await mostrarMapa(t, datos, tamano: const Size(640, 4400)); // 320 dp de ancho
          expect(t.takeException(), isNull);
          // Con letra al 200 % el control queda más abajo de lo que entra en
          // la pantalla: se baja hasta él, como haría la persona.
          await t.ensureVisible(find.byTooltip('Bajar 10 cm'));
          await t.pumpAndSettle();
          await t.tap(find.byTooltip('Bajar 10 cm'));
          await t.pumpAndSettle();
          await t.ensureVisible(find.text('Crecida de prueba: 4,25 m'));
          await t.tap(find.text('Crecida de prueba: 4,25 m'));
          await t.pumpAndSettle();
          await t.tap(find.byType(Switch));
          await t.pumpAndSettle();
          await t.ensureVisible(find.text(textoAvisoMapa));
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
        }
      });
    }
  }

  group('listo para los datos reales', () {
    testWidgets('validado: false → aviso visible de mapa aproximado en prueba; el pie siempre', (t) async {
      await mostrarMapa(t, datosCon(4.13));
      expect(find.text(textoMapaEnPrueba), findsOneWidget);
      expect(find.text(textoAvisoMapa), findsOneWidget);
      expect(textoAvisoMapa, contains('No reemplaza la alerta oficial'));
      // va antes del mapa, no escondido al pie
      expect(t.getRect(find.text(textoMapaEnPrueba)).top, lessThan(t.getRect(find.byType(FlutterMap)).top));

      await mostrarMapa(t, datosCon(4.13), fuente: fuenteDePrueba(validado: true));
      expect(find.text(textoMapaEnPrueba), findsNothing);
      expect(find.text(textoAvisoMapa), findsOneWidget);
    });

    testWidgets('nunca promete seguridad', (t) async {
      for (final datos in [datosCon(3.20, nivel: 'normal'), datosCon(4.13), datosCon(9.0)]) {
        await mostrarMapa(t, datos);
        for (final prohibido in [RegExp('a salvo', caseSensitive: false), RegExp('seguro', caseSensitive: false)]) {
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
      expect(find.textContaining('nivel Alerta'), findsNothing);
      // abre en la capa más baja del mapa, no en la alerta (4,15 → 4,20)
      expect(find.text('Se muestra el agua con 4,00 m'), findsOneWidget);
      expect(find.text('Se muestra el agua con 4,20 m'), findsNothing);
    });

    for (final (altura, texto, aviso) in [
      (6.73, 'Se muestra el agua con 6,80 m', null),
      (3.85, 'Altura elegida: 3,90 m', 'el agua queda en su cauce'),
      (10.80, 'Se muestra el agua con 10,50 m', 'El río supera lo que cubre el mapa (hasta 10,50 m)'),
    ]) {
      testWidgets('rango del contrato 4,00–10,50 m con ${formatoAlturaPrueba(altura)} m', (t) async {
        await mostrarMapa(t, datosCon(altura, nivel: 'evacuacion'), fuente: fuenteRangoReal());
        expect(find.text(texto), findsOneWidget);
        if (aviso != null) expect(find.textContaining(aviso), findsOneWidget);
        final slider = t.widget<Slider>(find.byType(Slider));
        expect(slider.max, greaterThanOrEqualTo(1050));
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('crecida real: botón, redondeo dicho y contorno opcional de la curva', (t) async {
      await mostrarMapa(t, datosCon(4.13));
      expect(find.byType(PolygonLayer), findsNWidgets(3)); // cauce, margen y agua
      await t.tap(find.text('Crecida de prueba: 4,25 m'));
      await t.pumpAndSettle();
      expect(find.text('Se muestra el agua con 4,30 m'), findsOneWidget);
      expect(find.textContaining('El mapa lo redondea hacia arriba a 4,30 m'), findsOneWidget);
      // el contorno es opcional: arranca apagado
      expect(t.widget<Switch>(find.byType(Switch)).value, isFalse);
      expect(find.textContaining('Borde medido en esa crecida real'), findsNothing);
      await t.tap(find.byType(Switch));
      await t.pumpAndSettle();
      final capas = t.widgetList<PolygonLayer>(find.byType(PolygonLayer)).toList();
      expect(capas.last.polygons.single.borderStrokeWidth, greaterThan(2));
      expect(find.textContaining('Borde medido en esa crecida real'), findsOneWidget);
      // al moverse a otra altura, el contorno se va
      await t.tap(find.byTooltip('Bajar 10 cm'));
      await t.pumpAndSettle();
      expect(find.byType(Switch), findsNothing);
      expect(find.textContaining('Borde medido en esa crecida real'), findsNothing);
    });

    testWidgets('curva con la huella rota: lo dice y no dibuja nada', (t) async {
      await mostrarMapa(
        t,
        datosCon(4.13),
        fuente: fuenteDePrueba(archivos: {'curvas/2015-12.json': jsonABytes(curvaDePrueba(nombre: 'otra'))}),
      );
      await t.tap(find.text('Crecida de prueba: 4,25 m'));
      await t.pumpAndSettle();
      await t.tap(find.byType(Switch));
      await t.pumpAndSettle();
      expect(find.text('No se pudo leer el borde medido de esa crecida.'), findsOneWidget);
      expect(find.byType(PolygonLayer), findsNWidgets(2)); // cauce y agua (4,30 no tiene margen aparte)
    });

    testWidgets('sin dato al abrir y después llega uno: el mapa pasa a la altura de hoy', (t) async {
      final repo = RepositorioMapa(fuenteDePrueba()); // el mismo, como en la app
      await mostrarMapa(t, datosCon(null, nivel: 'sin_dato'), repositorio: repo);
      expect(find.text('Se muestra el agua con 4,20 m'), findsOneWidget); // alerta 4,15
      await mostrarMapa(t, datosCon(4.27), repositorio: repo);
      expect(find.text('Se muestra el agua con 4,30 m'), findsOneWidget);
      expect(find.textContaining('Es la altura de hoy'), findsOneWidget);
    });

    testWidgets('si la persona eligió otra altura, un dato nuevo no se la cambia', (t) async {
      final repo = RepositorioMapa(fuenteDePrueba());
      await mostrarMapa(t, datosCon(4.13), repositorio: repo);
      await t.tap(find.byTooltip('Bajar 10 cm'));
      await t.pumpAndSettle();
      await mostrarMapa(t, datosCon(4.27), repositorio: repo);
      expect(find.text('Se muestra el agua con 4,10 m'), findsOneWidget);
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

    testWidgets('el mapa se arma recién al visitarlo y abre en la altura de hoy', (t) async {
      await app(t);
      expect(find.byType(PantallaMapa), findsNothing);
      await t.tap(find.text('Mapa'));
      await t.pumpAndSettle();
      expect(find.byType(PantallaMapa), findsOneWidget);
      expect(find.text('Se muestra el agua con 4,20 m'), findsOneWidget);
      // al irse y volver, sigue armado (no se vuelve a leer)
      await t.tap(find.text('Inicio'));
      await t.pumpAndSettle();
      expect(find.byType(PantallaMapa, skipOffstage: false), findsOneWidget);
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
          await t.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(p.etiqueta)));
          await t.pumpAndSettle();
          expect(t.takeException(), isNull, reason: 'desborde en ${p.etiqueta}');
        }
        // Cada etiqueta entra en su lugar (no se corta ni se sale de la barra).
        final barra = t.getRect(find.byType(NavigationBar));
        for (final p in Pestana.values) {
          final r = t.getRect(find.descendant(of: find.byType(NavigationBar), matching: find.text(p.etiqueta)));
          expect(r.left, greaterThanOrEqualTo(barra.left));
          expect(r.right, lessThanOrEqualTo(barra.right));
          expect(r.width, lessThanOrEqualTo(barra.width / 5 + 0.5), reason: '${p.etiqueta} más ancha que su lugar');
        }
        await t.pumpWidget(const SizedBox());
      });
    }
  });
}
