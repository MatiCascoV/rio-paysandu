/// Pruebas del rediseño de Inicio: contraste de los colores nuevos, olas que
/// no gastan cuando no se ven, gráfico de la semana y el agua que sube con el río.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rio_paysandu/datos.dart';
import 'package:rio_paysandu/main.dart';
import 'package:rio_paysandu/modelos.dart';
import 'package:rio_paysandu/pantallas/grafico.dart';
import 'package:rio_paysandu/pantallas/inicio.dart';
import 'package:rio_paysandu/pantallas/olas.dart';
import 'package:rio_paysandu/tema.dart';
import 'package:rio_paysandu/textos.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'datos_de_prueba.dart';

const config = Config(urlBase: 'https://ejemplo.test/data/');
final ahora = DateTime.parse('2026-10-09T13:00:00-03:00');
final umbrales = Umbrales.desdeJson(jsonDecode(umbralesReal));

/// Una semana de lecturas cada hora hasta [hasta].
List<PuntoHistorial> semana(DateTime hasta) => [
      for (var h = 7 * 24 - 1; h >= 0; h--) PuntoHistorial(hasta.subtract(Duration(hours: h)), 5.2 + h * -0.004, 'estacion'),
    ];

Future<void> mostrar(WidgetTester t, Datos datos, {bool sinAnimaciones = false, VoidCallback? alVerGrafico}) async {
  t.view.physicalSize = const Size(1080, 6000);
  t.view.devicePixelRatio = 2.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    locale: const Locale('es'),
    supportedLocales: const [Locale('es')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: sinAnimaciones),
        child: Scaffold(
          body: PantallaInicio(
              datos: datos, config: config, alActualizar: () async {}, alVerGrafico: alVerGrafico, ahora: ahora),
        ),
      ),
    ),
  ));
}

Datos alerta({List<PuntoHistorial> historial = const []}) =>
    Datos(actual: Actual.desdeJson(actualFalso('alerta', 5.95)), umbrales: umbrales, historial: historial);

/// Algo pidió el próximo cuadro (un Ticker andando, por ejemplo las olas).
bool hayMovimiento(WidgetTester t) => SchedulerBinding.instance.transientCallbackCount > 0;

void main() {
  group('contraste de los colores nuevos', () {
    for (final oscuro in [false, true]) {
      final modo = oscuro ? 'oscuro' : 'claro';
      setUp(() => Colores.oscuro = oscuro);
      tearDown(() => Colores.oscuro = false);

      test('paleta de la app ($modo)', () {
        expect(contraste(Colores.tinta, Colores.fondo), greaterThanOrEqualTo(4.5));
        expect(contraste(Colores.tinta, Colores.superficie), greaterThanOrEqualTo(4.5));
        expect(contraste(Colores.tintaSecundaria, Colores.fondo), greaterThanOrEqualTo(4.5));
        expect(contraste(Colores.tintaSecundaria, Colores.superficie), greaterThanOrEqualTo(4.5));
        expect(contraste(Colores.primario, Colores.fondo), greaterThanOrEqualTo(4.5));
        expect(contraste(Colores.primario, Colores.superficie), greaterThanOrEqualTo(4.5));
        expect(contraste(Colores.sobrePrimario, Colores.primario), greaterThanOrEqualTo(4.5));
        expect(contraste(Colores.primario, Colores.primarioSuave), greaterThanOrEqualTo(4.5)); // pestaña elegida
      });

      for (final nivel in Nivel.values) {
        test('${nivel.name} ($modo): textos sobre el tinte, el agua, el botón y el gráfico', () {
          final tinte = ColoresNivel.tinte(nivel);
          final razon = '${nivel.name} en modo $modo';
          // nombre del nivel, frase y barra de arriba sobre el tinte (y sobre el fondo, si la
          // frase es larga y baja hasta donde el degradé ya se fundió)
          for (final detras in [Color.lerp(tinte, Colores.fondo, 0.5)!, Colores.fondo]) {
            expect(contraste(ColoresNivel.familia(nivel), detras), greaterThanOrEqualTo(4.5), reason: razon);
            expect(contraste(Colores.tinta, detras), greaterThanOrEqualTo(4.5), reason: razon);
          }
          expect(contraste(ColoresNivel.familia(nivel), tinte), greaterThanOrEqualTo(4.5), reason: razon);
          expect(contraste(Colores.tinta, tinte), greaterThanOrEqualTo(4.5), reason: razon);
          expect(contraste(Colores.tintaSecundaria, tinte), greaterThanOrEqualTo(4.5), reason: razon);
          expect(contraste(Colores.primario, tinte), greaterThanOrEqualTo(4.5), reason: razon);

          // el agua puede quedar detrás del número: la tinta sobre 1, 2 y 3 capas en todos los
          // niveles; la tinta secundaria solo va sobre el agua en el caso gris (sin dato o dato viejo)
          final a = ColoresNivel.opacidadesOlas(nivel);
          expect(a, hasLength(3));
          expect(a[0], greaterThan(0), reason: 'la primera capa tiene que verse ($razon)');
          expect(ColoresNivel.textosSobreElAgua(nivel),
              nivel == Nivel.sinDato ? [Colores.tinta, Colores.tintaSecundaria] : [Colores.tinta]);
          // el bloque puede caer en cualquier punto del degradé: tinte, mitad del camino o fondo
          final fondos = [tinte, Color.lerp(tinte, Colores.fondo, 0.5)!, Colores.fondo];
          expect(ColoresNivel.fondosDelBloque(nivel), fondos);
          for (final (i, detras) in fondos.indexed) {
            for (var capas = 1; capas <= 3; capas++) {
              final agua = ColoresNivel.bajoElAgua(nivel, a.sublist(0, capas), sobre: detras);
              final donde = '$razon, $capas capas, fondo ${['tinte', 'mitad', 'fondo'][i]}';
              expect(contraste(Colores.tinta, agua), greaterThanOrEqualTo(4.5), reason: donde);
              if (nivel == Nivel.sinDato) {
                expect(contraste(Colores.tintaSecundaria, agua), greaterThanOrEqualTo(4.5), reason: donde);
              }
            }
          }
          // con dato viejo la pantalla va gris pero el nombre conserva el tono de su nivel
          final gris = ColoresNivel.tinte(Nivel.sinDato);
          for (final detras in [gris, Color.lerp(gris, Colores.fondo, 0.5)!, Colores.fondo]) {
            expect(contraste(ColoresNivel.familia(nivel), detras), greaterThanOrEqualTo(4.5),
                reason: '$razon, nombre sobre el gris del dato viejo');
          }
          // fuera del gris, las tres capas se ven: la de atrás queda entera y las otras no se apagan
          if (nivel != Nivel.sinDato) {
            expect(a[0], closeTo(ColoresNivel.opacidadBase, 1e-9), reason: razon);
            expect(a[2], greaterThan(0), reason: razon);
          }
          // las capas nunca son más fuertes que lo pedido
          expect(a.every((x) => x <= ColoresNivel.opacidadBase + 1e-9), isTrue);

          // botón "Ver qué hacer"
          final (fondoBoton, textoBoton) = ColoresNivel.boton(nivel);
          expect(contraste(textoBoton, fondoBoton), greaterThanOrEqualTo(4.5), reason: razon);

          // gráfico de la semana: tarjeta translúcida sobre el tinte (arriba) o el fondo (abajo)
          for (final detras in [tinte, Colores.fondo]) {
            final tarjeta = Color.lerp(detras, Colores.superficie, 0.72)!;
            expect(contraste(Colores.tintaSecundaria, tarjeta), greaterThanOrEqualTo(4.5), reason: razon);
            expect(contraste(Colores.primario, tarjeta), greaterThanOrEqualTo(4.5), reason: razon); // "Ver más"
            // líneas: la del río y las de alerta y evacuación (con la zona sombreada de alerta)
            final sombreada = Color.lerp(tarjeta, const Color(0xFFEF6C00), 0.10)!;
            for (final fondoLinea in [tarjeta, sombreada]) {
              expect(contraste(Colores.primario, fondoLinea), greaterThanOrEqualTo(3), reason: razon);
              expect(contraste(estiloNivel(Nivel.alerta).oscuro, fondoLinea), greaterThanOrEqualTo(3), reason: razon);
              expect(contraste(estiloNivel(Nivel.evacuacion).oscuro, fondoLinea), greaterThanOrEqualTo(3),
                  reason: razon);
            }
          }
        });
      }
    }
  });

  test('olas de atención en oscuro: amarillo más hondo, que se sigue leyendo como amarillo', () {
    Colores.oscuro = true;
    addTearDown(() => Colores.oscuro = false);
    final ola = ColoresNivel.ola(Nivel.atencion);
    expect(ola, const Color(0xFFB08900));
    final hsv = HSVColor.fromColor(ola);
    expect(hsv.hue, inInclusiveRange(40, 60));
    expect(hsv.saturation, greaterThan(0.9));
    // en claro y en los demás niveles, el color fuerte de siempre
    expect(ColoresNivel.ola(Nivel.alerta), ColoresNivel.fuerte(Nivel.alerta));
    Colores.oscuro = false;
    expect(ColoresNivel.ola(Nivel.atencion), const Color(0xFFFFD600));
  });

  testWidgets('sin conexión, «Último dato» (tinta secundaria) queda fuera del agua', (t) async {
    await mostrar(t, Datos(actual: Actual.desdeJson(actualFalso('alerta', 5.95)), umbrales: umbrales, sinConexion: true));
    final bloque = find.ancestor(of: find.byType(OlasNivel), matching: find.byType(Stack)).first;
    expect(t.getBottomLeft(find.text('Último dato')).dy, lessThanOrEqualTo(t.getTopLeft(bloque).dy));
  });

  group('agua que sube con el río', () {
    test('fracción: altura sobre evacuación, con mínimo y tope', () {
      expect(fraccionAgua(alturaM: 5.95, umbrales: umbrales, sinNivel: false), closeTo(5.95 / 6.89, 1e-9));
      expect(fraccionAgua(alturaM: 0.5, umbrales: umbrales, sinNivel: false), 0.15);
      expect(fraccionAgua(alturaM: 8.0, umbrales: umbrales, sinNivel: false), 1.0);
      expect(fraccionAgua(alturaM: 5.95, umbrales: null, sinNivel: false), 0.3);
      expect(fraccionAgua(alturaM: 5.95, umbrales: umbrales, sinNivel: true), 0.15);
      expect(fraccionAgua(alturaM: null, umbrales: umbrales, sinNivel: false), 0.15);
    });

    testWidgets('el agua cubre más del bloque con el río más alto', (t) async {
      Future<double> altoDelAgua(double valor) async {
        await mostrar(t, Datos(actual: Actual.desdeJson(actualFalso('alerta', valor)), umbrales: umbrales));
        await t.pumpAndSettle(); // termina la transición de 1,2 s
        return t.getSize(find.byType(OlasNivel)).height;
      }

      final bajo = await altoDelAgua(4.5);
      final alto = await altoDelAgua(6.5);
      expect(alto, greaterThan(bajo * 1.3));
      // es decoración: no le agrega nada al lector de pantalla
      expect(find.descendant(of: find.byType(OlasNivel), matching: find.byType(ExcludeSemantics)), findsOneWidget);
    });

    testWidgets('con «reducir movimiento» el agua llega directo a su altura', (t) async {
      await mostrar(t, alerta(), sinAnimaciones: true);
      final alto = t.getSize(find.byType(OlasNivel)).height;
      await t.pump(const Duration(seconds: 2));
      expect(t.getSize(find.byType(OlasNivel)).height, alto);
    });
  });

  group('olas', () {
    setUp(() => OlasNivel.animar = true);
    tearDown(() => OlasNivel.animar = false);

    testWidgets('se mueven en Inicio y quedan quietas con «reducir movimiento»', (t) async {
      await mostrar(t, alerta());
      await t.pump(const Duration(seconds: 2)); // termina la subida del agua
      expect(hayMovimiento(t), isTrue);

      await mostrar(t, alerta(), sinAnimaciones: true);
      await t.pump();
      expect(hayMovimiento(t), isFalse);
      await t.pumpAndSettle(); // no queda nada andando
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('se detienen con la app en segundo plano', (t) async {
      await mostrar(t, alerta());
      await t.pump(const Duration(seconds: 2));
      expect(hayMovimiento(t), isTrue);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await t.pump();
      expect(hayMovimiento(t), isFalse, reason: 'en inactive ya se detienen');
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await t.pump();
      expect(hayMovimiento(t), isFalse);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pump();
      expect(hayMovimiento(t), isTrue);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('no gastan cuando Inicio no es la pestaña visible', (t) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final falso = actualFalso('alerta', 5.95);
      (falso['altura_actual'] as Map)['fecha'] = DateTime.now().toUtc().toIso8601String();
      falso['generado'] = DateTime.now().toUtc().toIso8601String();
      final cliente = MockClient((pedido) async => http.Response.bytes(
          utf8.encode(switch (pedido.url.pathSegments.last) {
            'actual.json' => jsonEncode(falso),
            'umbrales.json' => umbralesReal,
            _ => '[]',
          }),
          200));
      await t.pumpWidget(
          RioPaysanduApp(config: config, prefs: prefs, repositorio: Repositorio(config.urlBase, cliente: cliente)));
      await t.pump(const Duration(seconds: 3));
      expect(find.byType(OlasNivel), findsOneWidget);
      expect(hayMovimiento(t), isTrue);

      await t.tap(find.text('Gráfico'));
      await t.pumpAndSettle(); // terminaría por tiempo si las olas siguieran andando
      expect(hayMovimiento(t), isFalse);

      await t.tap(find.text('Inicio'));
      await t.pump(const Duration(seconds: 1));
      expect(hayMovimiento(t), isTrue);
      await t.pumpWidget(const SizedBox());
    });
  });

  group('gráfico de la semana en Inicio', () {
    testWidgets('aparece con historial y lleva a la pestaña Gráfico', (t) async {
      var tocado = false;
      await mostrar(t, alerta(historial: semana(ahora)), alVerGrafico: () => tocado = true);
      expect(find.text('Últimos 7 días'), findsOneWidget);
      final grafico = t.widget<GraficoAltura>(find.byType(GraficoAltura));
      expect(grafico.compacto, isTrue);
      expect(find.bySemanticsLabel(RegExp(r'^Gráfico de la altura del río en los últimos 7 días\. Del ')),
          findsOneWidget);
      // la cifra de la altura sigue estando una sola vez a la vista
      expect(find.text('5,95 m'), findsOneWidget);
      await t.tap(find.text('Ver más'));
      expect(tocado, isTrue);
    });

    testWidgets('no aparece sin historial ni con lecturas de hace más de una semana', (t) async {
      await mostrar(t, alerta());
      expect(find.text('Últimos 7 días'), findsNothing);
      expect(find.byType(GraficoAltura), findsNothing);

      await mostrar(t, alerta(historial: semana(ahora.subtract(const Duration(days: 9)))));
      expect(find.text('Últimos 7 días'), findsNothing);
    });
  });
}
