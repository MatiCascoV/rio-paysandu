/// Pestaña Crecidas dentro de la app entera (barra de arriba, barra de
/// pestañas y barras del sistema), con la letra Roboto real:
///   - el aviso aprobado y la línea de la escala se leen sin desplazar;
///   - la pestaña no lee nada hasta que se la visita.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rio_paysandu/crecidas/repositorio_crecidas.dart';
import 'package:rio_paysandu/datos.dart';
import 'package:rio_paysandu/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'crecidas_test.dart' show archivosReales;
import 'datos_de_prueba.dart';
import 'primera_pantalla_test.dart' show cargarRoboto;

const config = Config(urlBase: 'https://ejemplo.test/data/');

/// La app entera en un teléfono de 393 × 873 dp, con barra de estado (24 dp)
/// y botones del sistema abajo (48 dp).
Future<FuenteMemoria> abrirApp(WidgetTester t, {double letra = 1.0}) async {
  const dpr = 2.75;
  t.view.physicalSize = const Size(393 * dpr, 873 * dpr);
  t.view.devicePixelRatio = dpr;
  t.view.padding = const FakeViewPadding(top: 24 * dpr, bottom: 48 * dpr);
  t.view.viewPadding = const FakeViewPadding(top: 24 * dpr, bottom: 48 * dpr);
  t.platformDispatcher.textScaleFactorTestValue = letra;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final falso = actualFalso('normal', 3.2);
  final ahora = DateTime.now().toUtc().toIso8601String();
  (falso['altura_actual'] as Map)['fecha'] = ahora;
  falso['generado'] = ahora;
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
  final fuente = FuenteMemoria(archivosReales());
  await t.pumpWidget(
    RioPaysanduApp(
      config: config,
      prefs: prefs,
      repositorio: Repositorio(config.urlBase, cliente: cliente),
      repositorioCrecidas: RepositorioCrecidas(fuente),
    ),
  );
  await t.pumpAndSettle();
  return fuente;
}

void main() {
  setUpAll(cargarRoboto);

  testWidgets('la pestaña Crecidas no lee nada hasta que se la visita', (t) async {
    final fuente = await abrirApp(t);
    expect(find.text('Crecidas anteriores'), findsNothing);
    expect(fuente.lecturas, isEmpty);
    await t.tap(find.text('Crecidas'));
    await t.pumpAndSettle();
    expect(find.text('Crecidas anteriores'), findsOneWidget);
    expect(fuente.lecturas.keys, containsAll(['indice.json', 'base.json', 'curvas/2025-07.json']));
    // Volver a otra pestaña y otra vez a Crecidas no relee nada.
    final antes = Map.of(fuente.lecturas);
    await t.tap(find.text('Inicio'));
    await t.pumpAndSettle();
    await t.tap(find.text('Crecidas'));
    await t.pumpAndSettle();
    expect(fuente.lecturas, antes);
    await t.pumpWidget(const SizedBox());
  });

  for (final letra in [1.0, 1.3]) {
    testWidgets('el aviso y la escala se leen sin desplazar, sobre la barra de pestañas (letra ${(letra * 100).round()} %)',
        (t) async {
      await abrirApp(t, letra: letra);
      await t.tap(find.text('Crecidas'));
      await t.pumpAndSettle();
      final barra = t.getTopLeft(find.byType(NavigationBar)).dy;
      final aviso = find.byKey(const ValueKey('aviso-crecidas'));
      final escala = find.byKey(const ValueKey('escala-crecidas'));
      final caja = find.byKey(const ValueKey('caja-aviso-crecidas'));
      // ignore: avoid_print
      print('${(letra * 100).round()} %: barra en $barra; fin de la escala en ${t.getRect(escala).bottom}');
      expect(t.getRect(aviso).bottom, lessThanOrEqualTo(barra));
      expect(t.getRect(escala).bottom, lessThanOrEqualTo(barra));
      expect(t.getRect(caja).bottom, lessThanOrEqualTo(barra));
      // Arranca debajo de la barra de arriba.
      expect(t.getRect(caja).top, greaterThanOrEqualTo(t.getRect(find.byType(AppBar)).bottom));
      // Sin haber desplazado la página.
      final scroll = t
          .state<ScrollableState>(
            find.descendant(of: find.byKey(const ValueKey('crecidas-scroll')), matching: find.byType(Scrollable)),
          )
          .position;
      expect(scroll.pixels, 0);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
  }

  // Con letra al 200 % el aviso puede no entrar entero: se mide y se informa
  // (el dueño lo aceptó si no entra), sin hacer fallar la prueba.
  testWidgets('letra al 200 %: dónde queda el aviso (solo informa)', (t) async {
    await abrirApp(t, letra: 2.0);
    await t.tap(find.text('Crecidas'));
    await t.pumpAndSettle();
    final barra = t.getTopLeft(find.byType(NavigationBar)).dy;
    final aviso = t.getRect(find.byKey(const ValueKey('aviso-crecidas'))).bottom;
    final escala = t.getRect(find.byKey(const ValueKey('escala-crecidas'))).bottom;
    // ignore: avoid_print
    print('200 %: barra de pestañas en $barra; fin del aviso en $aviso; fin de la escala en $escala');
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
}
