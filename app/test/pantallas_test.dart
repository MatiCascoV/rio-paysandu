import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rio_paysandu/datos.dart';
import 'package:rio_paysandu/modelos.dart';
import 'package:rio_paysandu/pantallas/ajustes.dart';
import 'package:rio_paysandu/pantallas/grafico.dart';
import 'package:rio_paysandu/pantallas/inicio.dart';
import 'package:rio_paysandu/pantallas/que_hacer.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'datos_de_prueba.dart';

const config = Config(
  urlBase: 'https://ejemplo.test/data/',
  contactos: [Contacto('Emergencias', '911', null), Contacto('Sinae', '150 1353', null)],
);
final ahora = DateTime.parse('2026-10-09T13:00:00-03:00');
final umbrales = Umbrales.desdeJson(jsonDecode(umbralesReal));

Widget enApp(Widget hijo) => MaterialApp(
      locale: const Locale('es'),
      supportedLocales: const [Locale('es')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Scaffold(body: hijo),
    );

Future<void> mostrarInicio(WidgetTester t, Datos? datos, {DateTime? cuando}) async {
  // Pantalla alta para que toda la lista quede construida.
  t.view.physicalSize = const Size(1080, 6000);
  t.view.devicePixelRatio = 2.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(enApp(PantallaInicio(datos: datos, config: config, alActualizar: () async {}, ahora: cuando ?? ahora)));
}

Datos datosCon(Map<String, dynamic> actual, {bool sinConexion = false}) =>
    Datos(actual: Actual.desdeJson(actual), umbrales: umbrales, sinConexion: sinConexion);

void main() {
  group('Inicio con un actual.json falso para cada nivel', () {
    final casos = {
      'normal': (3.20, 'NORMAL', 'por debajo de los niveles de aviso'),
      'atencion': (4.10, 'ATENCIÓN', 'nivel de atención'),
      'alerta': (5.95, 'ALERTA', 'nivel de alerta (4,39 m)'),
      'evacuacion': (7.05, 'EVACUACIÓN', 'nivel de evacuación (6,89 m)'),
    };
    casos.forEach((nivel, caso) {
      testWidgets(nivel, (t) async {
        final (valor, nombre, descripcion) = caso;
        await mostrarInicio(t, datosCon(actualFalso(nivel, valor)));
        expect(find.text(nombre), findsOneWidget); // el nivel se dice con texto, no solo color
        expect(find.textContaining(descripcion), findsOneWidget);
        expect(find.text('${valor.toStringAsFixed(2).replaceAll('.', ',')} m'), findsOneWidget);
        // toda altura lleva fecha, hora y fuente
        expect(find.text('Actualizado: hoy 12:00'), findsOneWidget);
        expect(find.text('Fuente: CARU – estación automática Paysandú'), findsOneWidget);
        expect(find.text('Ver fuente'), findsOneWidget);
        expect(find.text('Crece 1 cm en 30 min'), findsOneWidget);
        expect(find.textContaining('No reemplaza la alerta oficial'), findsOneWidget);
      });
    });

    testWidgets('sin_dato: no muestra ninguna altura', (t) async {
      await mostrarInicio(t, datosCon(actualFalso('sin_dato', null)));
      expect(find.text('SIN DATO'), findsOneWidget);
      expect(find.textContaining(RegExp(r'\d,\d\d m')), findsNothing);
      expect(find.text('Reintentar'), findsOneWidget);
    });
  });

  testWidgets('pronóstico vigente con enlace al PDF', (t) async {
    await mostrarInicio(t, datosCon(actualFalso('alerta', 5.95)));
    expect(find.text('CARU estima hasta 6,66 m'), findsOneWidget);
    expect(find.text('Informe del 8/10/2026'), findsOneWidget);
    expect(find.textContaining('18.000 metros cúbicos'), findsOneWidget);
    expect(find.text('Ver informe (PDF)'), findsOneWidget);
  });

  testWidgets('pronóstico no vigente no se muestra', (t) async {
    final j = actualFalso('alerta', 5.95);
    (j['pronostico'] as Map)['vigente'] = false;
    await mostrarInicio(t, datosCon(j));
    expect(find.textContaining('CARU estima'), findsNothing);
  });

  testWidgets('umbrales sin validar: se avisa', (t) async {
    await mostrarInicio(t, datosCon(actualFalso('alerta', 5.95)));
    expect(find.textContaining('provisorios'), findsOneWidget);
  });

  testWidgets('sin conexión: muestra el dato guardado y lo dice', (t) async {
    await mostrarInicio(t, datosCon(actualFalso('alerta', 5.95), sinConexion: true));
    expect(find.textContaining('último dato guardado'), findsOneWidget);
    expect(find.text('5,95 m'), findsOneWidget);
    expect(find.text('Actualizado: hoy 12:00'), findsOneWidget);
  });

  testWidgets('sin conexión y sin nada guardado', (t) async {
    await mostrarInicio(t, const Datos(sinConexion: true));
    expect(find.text('SIN DATO'), findsOneWidget);
    expect(find.text('No hay conexión a internet.'), findsOneWidget);
  });

  testWidgets('dato viejo: avisa, y pasadas 48 h deja de mostrar el nivel', (t) async {
    final datos = datosCon(actualFalso('alerta', 5.95));
    await mostrarInicio(t, datos, cuando: ahora.add(const Duration(hours: 8)));
    expect(find.textContaining('más de 6 horas'), findsOneWidget);
    expect(find.text('ALERTA'), findsOneWidget);

    await mostrarInicio(t, datos, cuando: ahora.add(const Duration(hours: 60)));
    expect(find.text('SIN DATO'), findsOneWidget);
    expect(find.text('ALERTA'), findsNothing);
    expect(find.textContaining('más de 48 horas'), findsOneWidget);
    expect(find.text('5,95 m'), findsOneWidget); // el valor sigue visible, con su fecha real
    expect(find.text('Actualizado: 9/10 12:00'), findsOneWidget);
  });

  testWidgets('avisos del lector en palabras simples', (t) async {
    await mostrarInicio(
        t, datosCon(actualFalso('alerta', 5.95, avisos: ['dato_a_verificar', 'fuente_no_disponible', 'aviso_nuevo'])));
    expect(find.textContaining('cambio brusco'), findsOneWidget);
    expect(find.textContaining('No se pudo consultar a CARU'), findsOneWidget);
    expect(find.textContaining('aviso_nuevo'), findsNothing);
  });

  testWidgets('cargando', (t) async {
    await mostrarInicio(t, null);
    expect(find.text('Cargando el nivel del río…'), findsOneWidget);
  });

  testWidgets('gráfico: rangos, resumen y leyenda con umbrales', (t) async {
    final historial = [
      for (var i = 0; i < 14 * 24; i++)
        PuntoHistorial(ahora.subtract(Duration(hours: 14 * 24 - i)), 4.0 + i * 0.005, 'estacion'),
      PuntoHistorial(ahora.subtract(const Duration(hours: 7)), 5.6, 'prefectura'),
    ];
    await t.pumpWidget(enApp(PantallaGrafico(datos: Datos(umbrales: umbrales, historial: historial), ahora: ahora)));
    expect(find.text('7 días'), findsOneWidget);
    expect(find.textContaining('Máximo:'), findsOneWidget);
    expect(find.text('Nivel de alerta: 4,39 m'), findsOneWidget);
    expect(find.text('Nivel de evacuación: 6,89 m'), findsOneWidget);
    expect(find.textContaining('Nivel de atención'), findsNothing); // no está definido
    await t.tap(find.text('90 días'));
    await t.pump();
    expect(find.textContaining('hay datos guardados desde'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('gráfico sin datos', (t) async {
    await t.pumpWidget(enApp(PantallaGrafico(datos: const Datos(), ahora: ahora)));
    expect(find.text('No hay lecturas en este período.'), findsOneWidget);
  });

  testWidgets('qué hacer: teléfonos y aviso oficial', (t) async {
    await t.pumpWidget(enApp(const PantallaQueHacer(config: config)));
    expect(find.text('Emergencias: 911'), findsOneWidget);
    expect(find.text('Sinae: 150 1353'), findsOneWidget);
    expect(find.textContaining('No reemplaza la alerta oficial'), findsOneWidget);
  });

  testWidgets('ajustes: elegir desde qué nivel avisar', (t) async {
    SharedPreferences.setMockInitialValues({'avisos_activos': true});
    final prefs = await SharedPreferences.getInstance();
    await t.pumpWidget(enApp(PantallaAjustes(prefs: prefs, umbrales: umbrales)));
    expect(find.text('Recibir avisos'), findsOneWidget);
    expect(find.text('Atención'), findsNothing); // sin valor definido, no se ofrece
    expect(find.text('4,39 m o más'), findsOneWidget);
    await t.tap(find.text('Evacuación'));
    await t.pump();
    expect(prefs.getString('avisar_desde'), 'evacuacion');
  });

  group('repositorio', () {
    http.Client servidor({bool caido = false}) => MockClient((pedido) async {
          if (caido) throw http.ClientException('sin red');
          final cuerpo = switch (pedido.url.pathSegments.last) {
            'actual.json' => actualReal,
            'umbrales.json' => umbralesReal,
            _ => '[{"fecha": "2026-10-09T12:00:00-03:00", "valor_m": 5.95, "fuente": "estacion"}]',
          };
          return http.Response.bytes(utf8.encode(cuerpo), 200);
        });

    test('baja, guarda y después funciona sin conexión', () async {
      SharedPreferences.setMockInitialValues({});
      final enLinea = await Repositorio(config.urlBase, cliente: servidor()).cargar();
      expect(enLinea.sinConexion, isFalse);
      expect(enLinea.actual!.altura!.valorM, 5.95);
      expect(enLinea.historial, hasLength(1));

      final sinRed = await Repositorio(config.urlBase, cliente: servidor(caido: true)).cargar();
      expect(sinRed.sinConexion, isTrue);
      expect(sinRed.actual!.altura!.valorM, 5.95);
      expect(sinRed.umbrales!.alertaM, 4.39);
    });

    test('sin conexión y sin copia guardada', () async {
      SharedPreferences.setMockInitialValues({});
      final d = await Repositorio(config.urlBase, cliente: servidor(caido: true)).cargar();
      expect(d.sinConexion, isTrue);
      expect(d.actual, isNull);
    });

    test('una respuesta que no es JSON no pisa la copia buena', () async {
      SharedPreferences.setMockInitialValues({'cache_actual': actualReal});
      final roto = MockClient((_) async => http.Response('<html>Error</html>', 200));
      final d = await Repositorio(config.urlBase, cliente: roto).cargar();
      expect(d.sinConexion, isTrue);
      expect(d.actual!.altura!.valorM, 5.95);
    });
  });
}
