// Pruebas del endurecimiento de seguridad: enlaces, teléfonos, datos raros,
// tope de descarga, avisos y manifiesto.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rio_paysandu/datos.dart';
import 'package:rio_paysandu/enlaces.dart';
import 'package:rio_paysandu/modelos.dart';
import 'package:rio_paysandu/notificaciones.dart';
import 'package:rio_paysandu/pantallas/inicio.dart';
import 'package:rio_paysandu/textos.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'datos_de_prueba.dart';

final configReal =
    Config.desdeJson(jsonDecode(File('assets/config.json').readAsStringSync()) as Map<String, dynamic>);

Map<String, dynamic> actualCon(void Function(Map<String, dynamic> j) cambio) {
  final j = jsonDecode(actualReal) as Map<String, dynamic>;
  cambio(j);
  return j;
}

void main() {
  setUpAll(() => permitirOrigenes(configReal.enlacesPermitidos));

  group('enlaces (11)', () {
    test('la lista sale de config.json', () {
      expect(configReal.enlacesPermitidos,
          containsAll(['https://caru.org.uy', 'https://www.caru.org.uy', 'http://190.0.152.194:8080']));
    });

    test('se abren los sitios de CARU', () {
      expect(enlacePermitido('https://caru.org.uy/nuevositio/informe.pdf'), isTrue);
      expect(enlacePermitido('https://www.caru.org.uy/'), isTrue);
      expect(enlacePermitido('https://CARU.org.uy/x'), isTrue);
      expect(enlacePermitido('https://caru.org.uy:443/x'), isTrue);
      expect(enlacePermitido('http://190.0.152.194:8080/alturas/web/user/estacion/19/0'), isTrue);
    });

    test('se rechaza todo lo demás', () {
      for (final url in [
        null,
        '',
        'javascript:alert(1)',
        'intent://caru.org.uy#Intent;scheme=https;end',
        'market://details?id=algo',
        'sms:+59899123456',
        'tel:911',
        'file:///sdcard/algo',
        'https://caru.org.uy.evil.com/',
        'https://evil.com/caru.org.uy',
        'https://evil.com/?r=https://caru.org.uy',
        'https://caru.org.uy@evil.com/',
        'https://usuario@caru.org.uy/',
        'https://usuario:clave@caru.org.uy/',
        'https://ejemplo.com/',
        'http://caru.org.uy/', // otro esquema
        'https://190.0.152.194:8080/', // otro esquema
        'http://190.0.152.194/', // otro puerto
        'http://190.0.152.194:8081/', // otro puerto
        'https://xcaru.org.uy/',
        '//caru.org.uy/x',
        'caru.org.uy',
      ]) {
        expect(enlacePermitido(url), isFalse, reason: '$url');
      }
    });

    test('se abre la dirección ya analizada y recortada', () {
      final uri = uriPermitida('  https://caru.org.uy/informe.pdf\n');
      expect(uri, Uri.parse('https://caru.org.uy/informe.pdf'));
      expect(uriPermitida('https://caru.org.uy@evil.com/'), isNull);
      expect(uriPermitida('javascript:alert(1)'), isNull);
    });

    test('sin lista cargada no se abre nada', () {
      permitirOrigenes(const []);
      addTearDown(() => permitirOrigenes(configReal.enlacesPermitidos));
      expect(enlacePermitido('https://caru.org.uy/'), isFalse);
    });

    test('los JSON no pueden meter enlaces ajenos', () {
      final a = Actual.desdeJson(actualCon((j) {
        (j['altura_actual'] as Map)['url'] = 'javascript:alert(1)';
        (j['pronostico'] as Map)['url_informe'] = 'https://caru.org.uy.evil.com/x.pdf';
      }))!;
      expect(a.altura!.url, isNull);
      expect(a.pronostico!.urlInforme, isNull);
      final real = Actual.desdeJson(jsonDecode(actualReal))!;
      expect(real.altura!.url, isNotNull);
      expect(real.pronostico!.urlInforme, isNotNull);
    });

    testWidgets('con un enlace ajeno no aparecen los botones', (t) async {
      t.view.physicalSize = const Size(1080, 6000);
      t.view.devicePixelRatio = 2.0;
      addTearDown(t.view.reset);
      final datos = Datos(
        actual: Actual.desdeJson(actualCon((j) {
          (j['altura_actual'] as Map)['url'] = 'https://evil.com/caru.org.uy';
          (j['pronostico'] as Map)['url_informe'] = 'intent://x#Intent;end';
        })),
        umbrales: Umbrales.desdeJson(jsonDecode(umbralesReal)),
      );
      await t.pumpWidget(MaterialApp(
        locale: const Locale('es'),
        supportedLocales: const [Locale('es')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(
          body: PantallaInicio(
            datos: datos,
            config: configReal,
            alActualizar: () async {},
            ahora: DateTime.parse('2026-10-09T13:00:00-03:00'),
          ),
        ),
      ));
      expect(find.text('ALERTA'), findsWidgets);
      expect(find.text('Ver en la página de CARU'), findsNothing);
      expect(find.text('Abrir el informe de CARU (PDF)'), findsNothing);
    });

    test('teléfonos: solo dígitos y un + inicial', () {
      expect(numeroParaLlamar('4722 0700'), '47220700');
      expect(numeroParaLlamar('911'), '911');
      expect(numeroParaLlamar('+598 99 123 456'), '+59899123456');
      for (final n in ['', '+', '91*1', '911#', '1;2', '++598', '59+8', '*99#', '911,1', 'abc', '911\n']) {
        expect(numeroParaLlamar(n), isNull, reason: n);
      }
      // Todos los teléfonos de la configuración se pueden llamar.
      for (final c in configReal.contactos) {
        expect(numeroParaLlamar(c.telefono), isNotNull, reason: c.telefono);
      }
    });
  });

  group('notificaciones (12)', () {
    final ahora = DateTime.parse('2026-10-09T13:00:00-03:00');

    test('un dato a verificar igual avisa, lo aclara y se recuerda', () async {
      SharedPreferences.setMockInitialValues({'ultimo_nivel': 'normal', claveActivos: true});
      final prefs = await SharedPreferences.getInstance();
      final dudoso = Actual.desdeJson(actualCon((j) => j['avisos'] = ['dato_a_verificar']))!;
      final aviso = await avisoPendiente(dudoso, prefs, ahora);
      expect(aviso, isNotNull);
      expect(aviso!.$1, 'Río Uruguay: nivel de ALERTA');
      expect(aviso.$2, contains('Dato a verificar por CARU.'));
      expect(prefs.getString('ultimo_nivel'), 'alerta');
      // Mismo nivel en la pasada siguiente: no se repite.
      expect(await avisoPendiente(dudoso, prefs, ahora), isNull);
    });

    test('sin el aviso del lector el texto no habla de verificar', () async {
      SharedPreferences.setMockInitialValues({'ultimo_nivel': 'normal', claveActivos: true});
      final prefs = await SharedPreferences.getInstance();
      final aviso = await avisoPendiente(Actual.desdeJson(jsonDecode(actualReal))!, prefs, ahora);
      expect(aviso!.$2, isNot(contains('verificar')));
    });

    test('con el reloj del teléfono 3 h atrasado igual avisa', () async {
      SharedPreferences.setMockInitialValues({'ultimo_nivel': 'normal', claveActivos: true});
      final prefs = await SharedPreferences.getInstance();
      final atrasado = DateTime.parse('2026-10-09T09:00:00-03:00'); // la lectura es de las 12:00
      final aviso = await avisoPendiente(Actual.desdeJson(jsonDecode(actualReal))!, prefs, atrasado);
      expect(aviso, isNotNull);
      expect(prefs.getString('ultimo_nivel'), 'alerta');
    });
  });

  group('datos raros (13)', () {
    final ahora = DateTime.parse('2026-10-09T13:00:00-03:00');

    test('infinitos, NaN y alturas fuera de 0–20 m', () {
      expect(Lectura.desdeJson({'valor_m': double.infinity, 'fecha': '2026-10-09T12:00:00-03:00'}), isNull);
      expect(Lectura.desdeJson({'valor_m': double.nan, 'fecha': '2026-10-09T12:00:00-03:00'}), isNull);
      expect(Lectura.desdeJson({'valor_m': -0.5, 'fecha': '2026-10-09T12:00:00-03:00'}), isNull);
      expect(Lectura.desdeJson({'valor_m': 20.5, 'fecha': '2026-10-09T12:00:00-03:00'}), isNull);
      expect(Lectura.desdeJson({'valor_m': 20, 'fecha': '2026-10-09T12:00:00-03:00'})!.valorM, 20);
      final l = Lectura.desdeJson(
          {'valor_m': 5, 'fecha': '2026-10-09T12:00:00-03:00', 'variacion_m': double.negativeInfinity})!;
      expect(l.variacionM, isNull);
      final u = Umbrales.desdeJson({'atencion_m': 25, 'alerta_m': -1, 'evacuacion_m': double.infinity})!;
      expect([u.atencionM, u.alertaM, u.evacuacionM], [null, null, null]);
    });

    test('pronóstico: caudal acotado, altura posible y texto corto', () {
      for (final caudal in [1e300, double.infinity, double.nan, -5, 1e7]) {
        expect(Pronostico.desdeJson({'caudal_salto_grande_m3s': caudal})!.caudalM3s, isNull, reason: '$caudal');
      }
      expect(Pronostico.desdeJson({'caudal_salto_grande_m3s': 18000.4})!.caudalM3s, 18000);
      expect(Pronostico.desdeJson({'altura_esperada_m': 99})!.alturaEsperadaM, isNull);
      final largo = Pronostico.desdeJson({'texto': 'á' * 5000})!.texto!;
      expect(largo.runes.length, 600);
      expect(largo, endsWith('…'));
      expect(Pronostico.desdeJson({'texto': 'corto'})!.texto, 'corto');
    });

    // actualReal se generó a las 12:25:36 (hora de Uruguay).
    final generado = DateTime.parse('2026-10-09T12:25:36-03:00');

    test('una lectura posterior a "generado" no da nivel', () {
      Actual conFecha(String fecha) =>
          Actual.desdeJson(actualCon((j) => (j['altura_actual'] as Map)['fecha'] = fecha))!;
      expect(Actual.desdeJson(jsonDecode(actualReal))!.generado, generado);
      expect(conFecha('2026-10-09T13:20:00-03:00').nivelVigente(ahora, 48), Nivel.alerta);
      expect(conFecha('2026-10-09T13:30:00-03:00').nivelVigente(ahora, 48), Nivel.sinDato);
      expect(conFecha('2030-01-01T00:00:00-03:00').nivelVigente(ahora, 48), Nivel.sinDato);
      // Sin "generado" no hay con qué comparar: manda el nivel publicado.
      final sinGenerado = Actual.desdeJson(actualCon((j) => j.remove('generado')))!;
      expect(sinGenerado.nivelVigente(ahora, 48), Nivel.alerta);
    });

    test('con el reloj del teléfono 3 h atrasado se ve el nivel', () {
      final atrasado = DateTime.parse('2026-10-09T09:00:00-03:00');
      expect(Actual.desdeJson(jsonDecode(actualReal))!.nivelVigente(atrasado, 48), Nivel.alerta);
      final h = PuntoHistorial.listaDesdeJson([
        {'fecha': '2026-10-09T12:00:00-03:00', 'valor_m': 5.95},
        {'fecha': '2026-10-09T11:00:00-03:00', 'valor_m': 5.9},
      ], generado: generado);
      expect(h, hasLength(2));
    });

    testWidgets('con el reloj del teléfono 3 h atrasado, Inicio muestra el nivel', (t) async {
      t.view.physicalSize = const Size(1080, 6000);
      t.view.devicePixelRatio = 2.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        locale: const Locale('es'),
        supportedLocales: const [Locale('es')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(
          body: PantallaInicio(
            datos: Datos(
                actual: Actual.desdeJson(jsonDecode(actualReal)),
                umbrales: Umbrales.desdeJson(jsonDecode(umbralesReal))),
            config: configReal,
            alActualizar: () async {},
            ahora: DateTime.parse('2026-10-09T09:00:00-03:00'),
          ),
        ),
      ));
      expect(find.text('ALERTA'), findsWidgets);
      expect(find.text('SIN DATO'), findsNothing);
    });

    test('historial sin puntos posteriores a "generado" ni alturas imposibles', () {
      final h = PuntoHistorial.listaDesdeJson([
        {'fecha': '2026-10-09T12:00:00-03:00', 'valor_m': 5.95},
        {'fecha': '2026-10-09T13:20:00-03:00', 'valor_m': 6.0}, // dentro del margen
        {'fecha': '2026-10-09T15:00:00-03:00', 'valor_m': 6.1}, // imposible
        {'fecha': '2026-10-08T12:00:00-03:00', 'valor_m': 1e308},
        {'fecha': '2026-10-08T12:00:00-03:00', 'valor_m': -3},
      ], generado: generado);
      expect(h.map((p) => p.valorM), [5.95, 6.0]);
    });
  });

  group('descarga (14)', () {
    http.Client servidor(String actual) => MockClient((pedido) async {
          final cuerpo = switch (pedido.url.pathSegments.last) {
            'actual.json' => actual,
            'umbrales.json' => umbralesReal,
            _ => '[]',
          };
          return http.Response.bytes(utf8.encode(cuerpo), 200);
        });

    test('una respuesta de más de 2 MB se rechaza', () async {
      SharedPreferences.setMockInitialValues({'cache_actual': actualReal});
      final enorme = '{"nivel": "normal", "relleno": "${'x' * (Repositorio.bytesMaximos + 10)}"}';
      final d = await Repositorio('https://ejemplo.test/data/', cliente: servidor(enorme)).cargar();
      expect(d.sinConexion, isTrue);
      expect(d.actual!.altura!.valorM, 5.95);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('cache_actual'), actualReal);
    });

    test('un JSON válido pero con forma rara no pisa la copia buena', () async {
      for (final raro in [
        '[]',
        '{}',
        '"hola"',
        '{"nivel": "alerta", "altura_actual": {"valor_m": 99, "fecha": "2026-10-09T12:00:00-03:00"}}',
        '{"nivel": 3}',
      ]) {
        SharedPreferences.setMockInitialValues({'cache_actual': actualReal});
        final d = await Repositorio('https://ejemplo.test/data/', cliente: servidor(raro)).cargar();
        expect(d.sinConexion, isTrue, reason: raro);
        expect(d.actual!.altura!.valorM, 5.95, reason: raro);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('cache_actual'), actualReal, reason: raro);
      }
    });

    test('una respuesta buena sí se guarda', () async {
      SharedPreferences.setMockInitialValues({});
      final d = await Repositorio('https://ejemplo.test/data/', cliente: servidor(actualReal)).cargar();
      expect(d.sinConexion, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('cache_actual'), actualReal);
      expect(prefs.getString('cache_umbrales'), umbralesReal);
    });

    // Respuesta que se queda abierta: registra si alguien soltó la conexión.
    (http.Client, bool Function()) colgado({int estado = 200, int? largo, bool mandaAlgo = true}) {
      var soltado = false;
      final cliente = MockClient.streaming((pedido, _) async {
        final c = StreamController<List<int>>(onCancel: () => soltado = true);
        if (mandaAlgo) c.add(utf8.encode('{"nivel": '));
        return http.StreamedResponse(c.stream, estado, contentLength: largo);
      });
      return (cliente, () => soltado);
    }

    test('si vence el tiempo se suelta la conexión y queda la copia', () async {
      SharedPreferences.setMockInitialValues({'cache_actual': actualReal});
      final (cliente, soltado) = colgado();
      final d = await Repositorio('https://ejemplo.test/data/',
              cliente: cliente, tiempoMaximo: const Duration(milliseconds: 50))
          .cargar();
      expect(d.sinConexion, isTrue);
      expect(d.actual!.altura!.valorM, 5.95);
      expect(soltado(), isTrue);
    });

    test('con un error o un tamaño declarado excesivo no se lee y se suelta', () async {
      for (final (estado, largo) in [(500, null), (404, 10), (200, Repositorio.bytesMaximos + 1)]) {
        SharedPreferences.setMockInitialValues({'cache_actual': actualReal});
        final (cliente, soltado) = colgado(estado: estado, largo: largo, mandaAlgo: false);
        final d = await Repositorio('https://ejemplo.test/data/', cliente: cliente).cargar();
        expect(d.actual!.altura!.valorM, 5.95, reason: '$estado');
        expect(soltado(), isTrue, reason: '$estado $largo');
      }
    });

    test('si el envío no responde, vence el tiempo igual', () async {
      SharedPreferences.setMockInitialValues({'cache_actual': actualReal});
      final nunca = MockClient.streaming((pedido, _) => Completer<http.StreamedResponse>().future);
      final d = await Repositorio('https://ejemplo.test/data/',
              cliente: nunca, tiempoMaximo: const Duration(milliseconds: 50))
          .cargar();
      expect(d.sinConexion, isTrue);
      expect(d.actual!.altura!.valorM, 5.95);
    });

    test('sin altura (CARU caída) también es válido', () {
      expect(Repositorio.esValido('actual', {'nivel': 'sin_dato', 'altura_actual': null}), isTrue);
    });
  });

  test('Android no copia los datos en las copias de seguridad (15)', () {
    final manifiesto = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifiesto, contains('android:allowBackup="false"'));
  });

  test('aviso de umbrales inválidos (16)', () {
    expect(textoAviso('umbrales_invalidos'),
        'Los niveles de referencia que llegaron tienen un error; no se usan para calcular el nivel.');
  });
}
