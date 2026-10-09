import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rio_paysandu/datos.dart';
import 'package:rio_paysandu/main.dart';
import 'package:rio_paysandu/modelos.dart';
import 'package:rio_paysandu/pantallas/ajustes.dart';
import 'package:rio_paysandu/pantallas/grafico.dart';
import 'package:rio_paysandu/pantallas/inicio.dart';
import 'package:rio_paysandu/pantallas/que_hacer.dart';
import 'package:rio_paysandu/tema.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'datos_de_prueba.dart';

const config = Config(
  urlBase: 'https://ejemplo.test/data/',
  contactos: [
    Contacto('Cecoed Paysandú', '4722 0700', null, 'De 6 a 18 horas · Cecoed Paysandú'),
    Contacto('Cecoed Paysandú', '092 634 993', 'celular', 'De 6 a 18 horas · Cecoed Paysandú'),
    Contacto('Emergencias', '911', null, 'De 18 a 6, o si hay personas en peligro'),
  ],
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
      'normal': (3.20, 'NORMAL', 'por debajo del nivel de alerta'),
      'atencion': (4.10, 'ATENCIÓN', 'nivel de atención'),
      'alerta': (5.95, 'ALERTA', 'El río pasó el nivel de alerta.'),
      'evacuacion': (7.05, 'EVACUACIÓN', 'La orden de evacuar la da el Cecoed'),
    };
    casos.forEach((nivel, caso) {
      testWidgets(nivel, (t) async {
        final (valor, nombre, descripcion) = caso;
        await mostrarInicio(t, datosCon(actualFalso(nivel, valor)));
        expect(find.text(nombre), findsOneWidget); // el nivel se dice con texto, no solo color
        expect(find.textContaining(descripcion), findsOneWidget);
        expect(find.text('${valor.toStringAsFixed(2).replaceAll('.', ',')} m'), findsNWidgets(2)); // número grande y escalera
        // toda altura lleva fecha, hora y fuente
        expect(find.text('Hoy 12:00'), findsOneWidget);
        expect(find.text('· CARU, estación automática'), findsOneWidget);
        expect(find.text('Ver en la página de CARU'), findsOneWidget);
        expect(find.text('Crece 1 cm en 30 min'), findsOneWidget);
        expect(find.textContaining('no es la altura del agua en tu calle'), findsOneWidget);
        expect(find.text('App de ayuda a la comunidad, sin vínculo oficial. No reemplaza la alerta oficial.'), findsOneWidget);
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
    expect(find.text('Máximo esperado por CARU'), findsOneWidget);
    expect(find.text('Informe del 8/10/2026'), findsOneWidget);
    expect(find.text('6,66 m'), findsOneWidget);
    expect(find.text('Queda 23 cm por debajo de evacuación.'), findsOneWidget);
    // el texto del informe queda plegado hasta que se toca
    expect(find.textContaining('18.000 m³'), findsNothing);
    await t.tap(find.text('Leer el informe'));
    await t.pumpAndSettle();
    expect(find.textContaining('18.000 m³'), findsOneWidget);
    expect(find.text('Abrir el informe de CARU (PDF)'), findsOneWidget);
  });

  testWidgets('dice cuánto falta para el nivel siguiente y compara el pronóstico', (t) async {
    await mostrarInicio(t, datosCon(actualFalso('alerta', 5.95)));
    expect(find.text('Faltan 94 cm para evacuación'), findsOneWidget);

    await mostrarInicio(t, datosCon(actualFalso('normal', 3.20)));
    expect(find.text('Faltan 1,19 m para alerta'), findsOneWidget);
  });

  testWidgets('la app completa arranca, muestra el dato y cambia de pestaña', (t) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final falso = actualFalso('alerta', 5.95);
    (falso['altura_actual'] as Map)['fecha'] = DateTime.now().toUtc().toIso8601String();
    final cliente = MockClient((pedido) async => http.Response.bytes(
        utf8.encode(switch (pedido.url.pathSegments.last) {
          'actual.json' => jsonEncode(falso),
          'umbrales.json' => umbralesReal,
          _ => '[]',
        }),
        200));
    await t.pumpWidget(
        RioPaysanduApp(config: config, prefs: prefs, repositorio: Repositorio(config.urlBase, cliente: cliente)));
    await t.pumpAndSettle();
    expect(find.text('ALERTA'), findsOneWidget);
    expect(find.text('5,95 m'), findsWidgets);
    await t.tap(find.text('Avisos'));
    await t.pumpAndSettle();
    expect(find.text('Recibir avisos'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox()); // cierra la app de prueba (detiene el reloj)
  });

  testWidgets('un JSON con tipos inesperados no deja la app en "Cargando"', (t) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final cliente = MockClient((_) async => http.Response(
        '{"nivel": 3, "cero": 0, "altura_actual": {"valor_m": 5.9, "fecha": "2020-01-01T12:00:00-03:00", '
        '"periodo": 30, "fuente": 5}, "pronostico": {"texto": 1}, "avisos": "x"}',
        200));
    await t.pumpWidget(
        RioPaysanduApp(config: config, prefs: prefs, repositorio: Repositorio(config.urlBase, cliente: cliente)));
    await t.pumpAndSettle();
    expect(find.text('Cargando el nivel del río…'), findsNothing);
    expect(find.text('SIN DATO'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('pronóstico no vigente no se muestra', (t) async {
    final j = actualFalso('alerta', 5.95);
    (j['pronostico'] as Map)['vigente'] = false;
    await mostrarInicio(t, datosCon(j));
    expect(find.textContaining('Máximo esperado'), findsNothing);
  });

  testWidgets('umbrales sin validar: se avisa', (t) async {
    await mostrarInicio(t, datosCon(actualFalso('alerta', 5.95)));
    expect(find.textContaining('los está revisando'), findsOneWidget); // una sola vez
  });

  testWidgets('sin conexión: muestra el dato guardado y lo dice', (t) async {
    await mostrarInicio(t, datosCon(actualFalso('alerta', 5.95), sinConexion: true));
    expect(find.text('Sin conexión. Dato guardado en este teléfono.'), findsOneWidget);
    expect(find.text('5,95 m'), findsWidgets);
    expect(find.text('Hoy 12:00'), findsOneWidget);
  });

  testWidgets('sin conexión y sin nada guardado', (t) async {
    await mostrarInicio(t, const Datos(sinConexion: true));
    expect(find.text('SIN DATO'), findsOneWidget);
    expect(find.text('Sin conexión a internet.'), findsOneWidget);
  });

  testWidgets('dato viejo: avisa, y pasadas 48 h deja de mostrar el nivel', (t) async {
    final datos = datosCon(actualFalso('alerta', 5.95));
    await mostrarInicio(t, datos, cuando: ahora.add(const Duration(hours: 8)));
    expect(find.textContaining('el río puede estar distinto'), findsOneWidget);
    expect(find.text('ALERTA'), findsOneWidget);
    expect(find.text('Crecía 1 cm en 30 min'), findsOneWidget); // en pasado: ya no se sabe si sigue creciendo

    await mostrarInicio(t, datos, cuando: ahora.add(const Duration(hours: 60)));
    expect(find.text('SIN DATO'), findsOneWidget);
    expect(find.text('ALERTA'), findsNothing);
    expect(find.text('No se puede saber el nivel actual del río.'), findsOneWidget);
    expect(find.text('5,95 m'), findsWidgets); // el valor sigue visible, con su fecha real
    expect(find.text('9/10 12:00'), findsOneWidget);
  });

  testWidgets('avisos del lector en palabras simples', (t) async {
    await mostrarInicio(
        t, datosCon(actualFalso('alerta', 5.95, avisos: ['dato_a_verificar', 'fuente_no_disponible', 'aviso_nuevo'])));
    expect(find.textContaining('puede tener un error'), findsOneWidget);
    expect(find.textContaining('No llegó información nueva de CARU'), findsOneWidget);
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
    expect(find.text('Estación automática'), findsOneWidget);
    expect(find.text('Prefectura (una por día)'), findsOneWidget);
    expect(find.text('Fuente: CARU. Los niveles marcados son de referencia.'), findsOneWidget);
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
    t.view.physicalSize = const Size(1080, 6000);
    t.view.devicePixelRatio = 2.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(enApp(const PantallaQueHacer(config: config)));
    expect(find.text('De 6 a 18 horas · Cecoed Paysandú'), findsOneWidget); // un título por grupo
    expect(find.text('4722 0700'), findsOneWidget);
    expect(find.text('celular'), findsOneWidget);
    expect(find.text('De 18 a 6, o si hay personas en peligro'), findsOneWidget);
    expect(find.text('911'), findsOneWidget);
    expect(find.text('Llamar'), findsNWidgets(3));
    expect(find.textContaining('No tiene vínculo con ningún organismo ni canal oficial'), findsOneWidget);
  });

  testWidgets('ajustes: elegir desde qué nivel avisar', (t) async {
    SharedPreferences.setMockInitialValues({'avisos_activos': true});
    final prefs = await SharedPreferences.getInstance();
    await t.pumpWidget(enApp(PantallaAjustes(prefs: prefs, datos: Datos(umbrales: umbrales))));
    expect(find.text('Recibir avisos'), findsOneWidget);
    expect(find.text('Atención'), findsNothing); // sin valor definido, no se ofrece
    expect(find.text('4,39 m o más'), findsOneWidget);
    await t.tap(find.text('Evacuación'));
    await t.pump();
    expect(prefs.getString('avisar_desde'), 'evacuacion');
  });

  testWidgets('escala de niveles: solo marca los umbrales que existen', (t) async {
    await mostrarInicio(t, datosCon(actualFalso('alerta', 5.95)));
    expect(find.text('Alerta'), findsOneWidget);
    expect(find.text('4,39 m'), findsOneWidget);
    expect(find.text('Evacuación'), findsOneWidget);
    expect(find.text('6,89 m'), findsOneWidget);
    expect(find.text('Ahora'), findsOneWidget);
    expect(find.textContaining('Atención'), findsNothing); // atencion_m viene en null
    expect(
        find.bySemanticsLabel(RegExp('^Escala de niveles. El río está en 5,95 metros, medido hoy 12:00. '
            'Nivel de alerta: 4,39 metros, ya superado. Nivel de evacuación: 6,89 metros, faltan 94 centímetros.')),
        findsOneWidget);

    // por encima de evacuación, "Ahora" pasa a ser el peldaño de arriba
    await mostrarInicio(t, datosCon(actualFalso('evacuacion', 7.20)));
    expect(find.text('31 cm por encima de evacuación'), findsOneWidget);
    expect(t.getTopLeft(find.text('Ahora')).dy, lessThan(t.getTopLeft(find.text('Evacuación')).dy));
  });

  testWidgets('en alerta hay un acceso directo a Qué hacer', (t) async {
    var tocado = false;
    t.view.physicalSize = const Size(1080, 6000);
    t.view.devicePixelRatio = 2.0;
    addTearDown(t.view.reset);
    Widget pantalla(String nivel, double valor) => enApp(PantallaInicio(
        // sin pronóstico (si CARU espera que pase la alerta, el botón también aparece)
        datos: datosCon(actualFalso(nivel, valor)..['pronostico'] = {'vigente': false}),
        config: config,
        alActualizar: () async {},
        alVerQueHacer: () => tocado = true,
        ahora: ahora));
    await t.pumpWidget(pantalla('normal', 3.2));
    expect(find.text('Ver qué hacer'), findsNothing);
    await t.pumpWidget(pantalla('alerta', 5.95));
    await t.tap(find.text('Ver qué hacer'));
    expect(tocado, isTrue);
  });

  for (final nivel in ['alerta', 'evacuacion', 'sin_dato']) {
    testWidgets('celular angosto con letra grande: nada se desborda ($nivel)', (t) async {
      t.view.physicalSize = const Size(720, 1480); // 360 x 740 dp
      t.view.devicePixelRatio = 2.0;
      t.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(t.view.reset);
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final falso = actualFalso(nivel, nivel == 'sin_dato' ? null : (nivel == 'alerta' ? 5.95 : 7.05));
      if (falso['altura_actual'] != null) {
        (falso['altura_actual'] as Map)['fecha'] = DateTime.now().toUtc().toIso8601String();
      }
      final cliente = MockClient((pedido) async => http.Response.bytes(
          utf8.encode(switch (pedido.url.pathSegments.last) {
            'actual.json' => jsonEncode(falso),
            'umbrales.json' => umbralesReal,
            _ => '[{"fecha": "${DateTime.now().toUtc().toIso8601String()}", "valor_m": 5.9, "fuente": "estacion"}]',
          }),
          200));
      await t.pumpWidget(
          RioPaysanduApp(config: config, prefs: prefs, repositorio: Repositorio(config.urlBase, cliente: cliente)));
      await t.pumpAndSettle();
      for (final pestana in ['Gráfico', 'Qué hacer', 'Avisos', 'Inicio']) {
        await t.tap(find.text(pestana));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull, reason: 'desborde en $pestana');
      }
      await t.pumpWidget(const SizedBox());
    });
  }

  testWidgets('modo oscuro: se cambia con el botón, se recuerda y no rompe ninguna pestaña', (t) async {
    addTearDown(() => Colores.oscuro = false);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final falso = actualFalso('alerta', 5.95);
    (falso['altura_actual'] as Map)['fecha'] = DateTime.now().toUtc().toIso8601String();
    final cliente = MockClient((pedido) async => http.Response.bytes(
        utf8.encode(switch (pedido.url.pathSegments.last) {
          'actual.json' => jsonEncode(falso),
          'umbrales.json' => umbralesReal,
          _ => '[{"fecha": "${DateTime.now().toUtc().toIso8601String()}", "valor_m": 5.9, "fuente": "estacion"}]',
        }),
        200));
    Widget app() => RioPaysanduApp(config: config, prefs: prefs, repositorio: Repositorio(config.urlBase, cliente: cliente));
    await t.pumpWidget(app());
    await t.pumpAndSettle();
    expect(Theme.of(t.element(find.text('ALERTA'))).brightness, Brightness.light);

    await t.tap(find.byTooltip('Cambiar a modo oscuro'));
    await t.pumpAndSettle();
    expect(prefs.getString('tema'), 'oscuro');
    expect(Theme.of(t.element(find.text('ALERTA'))).brightness, Brightness.dark);
    expect(find.text('5,95 m'), findsWidgets);
    for (final pestana in ['Gráfico', 'Qué hacer', 'Avisos', 'Inicio']) {
      await t.tap(find.text(pestana));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull, reason: 'error en $pestana en modo oscuro');
    }

    await t.tap(find.byTooltip('Cambiar a modo claro'));
    await t.pumpAndSettle();
    expect(prefs.getString('tema'), 'claro');
    expect(Theme.of(t.element(find.text('ALERTA'))).brightness, Brightness.light);
    await t.pumpWidget(const SizedBox());
  });

  test('assets/config.json es válido y trae los teléfonos', () {
    final c = Config.desdeJson(jsonDecode(File('assets/config.json').readAsStringSync()) as Map<String, dynamic>);
    expect(c.urlBase, startsWith('https://'));
    expect(c.contactos.map((x) => x.telefono), containsAll(['4722 0700', '4722 1505', '092 634 993', '911']));
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
