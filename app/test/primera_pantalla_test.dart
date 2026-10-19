/// En alerta y evacuación «Ver qué hacer» tiene que verse sin desplazar, aun
/// en el peor caso: celular angosto (360 × 740 dp), letra al 130 %, dato viejo
/// y sin conexión (dos avisos más arriba).
///
/// Va en un archivo aparte porque carga la letra Roboto real (la del teléfono,
/// que trae el SDK de Flutter): con la letra de prueba, que dibuja cada letra
/// como un cuadrado, los renglones salen mucho más largos que en un teléfono y
/// la medida no diría nada. Las otras pruebas siguen con la letra de prueba,
/// que es más exigente para buscar desbordes.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rio_paysandu/datos.dart';
import 'package:rio_paysandu/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'datos_de_prueba.dart';

const config = Config(urlBase: 'https://ejemplo.test/data/');

/// Carga Roboto (normal, media, negrita y negra) desde el SDK de Flutter.
Future<void> cargarRoboto() async {
  final raiz = Platform.environment['FLUTTER_ROOT'];
  final carpeta = Directory('$raiz/bin/cache/artifacts/material_fonts');
  if (raiz == null || !carpeta.existsSync()) {
    fail('No se encontró la letra Roboto del SDK de Flutter (FLUTTER_ROOT=$raiz).');
  }
  final cargador = FontLoader('Roboto');
  for (final peso in ['Regular', 'Medium', 'Bold', 'Black']) {
    final bytes = File('${carpeta.path}/Roboto-$peso.ttf').readAsBytesSync();
    cargador.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await cargador.load();
}

void main() {
  setUpAll(cargarRoboto);

  for (final nivel in ['alerta', 'evacuacion']) {
    for (final (viejo, sinRed) in [(false, false), (true, false), (false, true), (true, true)]) {
      testWidgets('"Ver qué hacer" a la vista sin desplazar ($nivel, '
          '${viejo ? 'dato viejo' : 'dato nuevo'}, ${sinRed ? 'sin conexión' : 'con conexión'})', (t) async {
        t.view.physicalSize = const Size(720, 1480); // 360 x 740 dp
        t.view.devicePixelRatio = 2.0;
        t.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(t.view.reset);
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        final falso = actualFalso(nivel, nivel == 'alerta' ? 5.95 : 7.05);
        final fecha = DateTime.now().toUtc().subtract(Duration(hours: viejo ? 8 : 0));
        (falso['altura_actual'] as Map)['fecha'] = fecha.toIso8601String();
        falso['generado'] = fecha.add(const Duration(minutes: 5)).toIso8601String();
        final historial = '[{"fecha": "${fecha.toIso8601String()}", "valor_m": 5.9, "fuente": "estacion"}]';
        // Sin conexión: la red falla y queda la copia guardada en el teléfono.
        SharedPreferences.setMockInitialValues(sinRed
            ? {'cache_actual': jsonEncode(falso), 'cache_umbrales': umbralesReal, 'cache_historial': historial}
            : {});
        final prefs = await SharedPreferences.getInstance();
        final cliente = MockClient((pedido) async {
          if (sinRed) throw http.ClientException('sin red');
          return http.Response.bytes(
              utf8.encode(switch (pedido.url.pathSegments.last) {
                'actual.json' => jsonEncode(falso),
                'umbrales.json' => umbralesReal,
                _ => historial,
              }),
              200);
        });
        await t.pumpWidget(
            RioPaysanduApp(config: config, prefs: prefs, repositorio: Repositorio(config.urlBase, cliente: cliente)));
        await t.pumpAndSettle();
        if (viejo) expect(find.textContaining('Después no llegó información nueva'), findsOneWidget);
        if (sinRed) expect(find.text('Sin conexión. Dato guardado en este teléfono.'), findsOneWidget);
        final boton = find.ancestor(of: find.text('Ver qué hacer'), matching: find.byType(FilledButton));
        expect(boton, findsOneWidget);
        final abajo = t.getRect(boton).bottom;
        expect(abajo, lessThan(740));
        // y sin quedar tapado por la barra de pestañas
        expect(abajo, lessThanOrEqualTo(t.getTopLeft(find.byType(NavigationBar)).dy));
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      });
    }
  }
}
