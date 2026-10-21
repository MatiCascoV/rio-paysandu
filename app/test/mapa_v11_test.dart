/// Contrato v1.1 (docs/mapa/05-contrato.md, "Agregados v1.1") y condiciones
/// para publicar con `validado: false` (docs/mapa/11-control-calidad.md §8):
/// zonas sin validar, lomas aisladas, zona baja de la costa y margen siempre.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:rio_paysandu/mapa/estilo_mapa.dart';
import 'package:rio_paysandu/mapa/fuente_mapa.dart';
import 'package:rio_paysandu/mapa/logica_mapa.dart';
import 'package:rio_paysandu/mapa/modelos_mapa.dart';
import 'package:rio_paysandu/mapa/repositorio_mapa.dart';
import 'package:rio_paysandu/pantallas/mapa.dart';

import 'fixtures_mapa.dart';
import 'mapa_test.dart' show datosCon, lectura, mostrarMapa;

/// El rango real (4,00 a 10,50 m) con el margen real de 50 cm.
FuenteMemoria fuenteReal({bool sinValidar = false, Map<int, List<Object>> aisladas = const {}, bool zonaBaja = true}) =>
    fuenteDePrueba(
      desde: 400,
      hasta: 1050,
      sinValidar: sinValidar,
      aisladas: aisladas,
      zonaBaja: zonaBaja,
      indice: (j) => (j['modelo'] as Map)['margen_m'] = 0.5,
    );

IndiceMapa indiceDe(FuenteMemoria f) => IndiceMapa.desdeJson(jsonDecode(utf8.decode(f.archivos['indice.json']!)));

/// Polígonos pintados con el estilo del margen (puntos), en todas las capas.
int poligonosDelMargen(WidgetTester t) {
  final c = ColoresMapa.actuales();
  return t
      .widgetList<PolygonLayer>(find.byType(PolygonLayer))
      .expand((l) => l.polygons)
      .where((p) => p.color == c.margen && p.borderColor == c.bordeMargen)
      .length;
}

/// La mención de la zona sin validar en el resumen del mapa: con el texto fijo
/// o con los nombres del archivo (no la fila de la leyenda, que no nombra
/// lugar).
final mencionSinValidar = RegExp('San Francisco.*no se pudo comparar con crecidas reales');

/// Puntos del margen repetidos encima de otra capa (líneas de puntos).
int puntosDelMargenEncima(WidgetTester t) {
  final c = ColoresMapa.actuales();
  return t
      .widgetList<PolylineLayer>(find.byType(PolylineLayer))
      .expand((l) => l.polylines)
      .where((p) => p.color == c.bordeMargen && p.pattern == TrazosMapa.patronMargen)
      .length;
}

void main() {
  group('índice: sin_validar opcional', () {
    test('sin el campo, el índice vale igual y no hay zona', () {
      final ind = IndiceMapa.desdeJson(indiceDePrueba());
      expect(ind.sinValidar, isNull);
    });

    test('con el campo, se lee con su tamaño y huella', () {
      final ind = indiceDe(fuenteDePrueba(sinValidar: true));
      expect(ind.sinValidar!.archivo, 'sin_validar.json');
      expect(ind.sinValidar!.bytes, greaterThan(0));
      expect(ind.sinValidar!.sha256, hasLength(64));
    });

    test('con el campo mal escrito, se ignora: el mapa sigue', () {
      for (final malo in <Object>[
        'sin_validar.json',
        {'archivo': '../afuera.json', 'bytes': 10, 'sha256': 'a' * 64},
        {'archivo': 'sin_validar.json', 'bytes': 0, 'sha256': 'a' * 64},
        {'archivo': 'sin_validar.json', 'bytes': 10, 'sha256': 'no'},
        {'archivo': 'agua/0400.json', 'bytes': 10, 'sha256': 'a' * 64},
      ]) {
        final j = indiceDePrueba()..['sin_validar'] = malo;
        final ind = IndiceMapa.desdeJson(j);
        expect(ind.sinValidar, isNull, reason: '$malo');
        expect(ind.capas, hasLength(4));
      }
    });

    test('sus bytes cuentan para el tope total', () {
      final j = indiceDePrueba()
        ..['sin_validar'] = {'archivo': 'sin_validar.json', 'bytes': TopesMapa.bytesSinValidar, 'sha256': 'a' * 64};
      expect(IndiceMapa.desdeJson(j).sinValidar, isNotNull);
      final grande = indiceDePrueba()
        ..['sin_validar'] = {'archivo': 'sin_validar.json', 'bytes': TopesMapa.bytesSinValidar + 1, 'sha256': 'a' * 64};
      expect(IndiceMapa.desdeJson(grande).sinValidar, isNull);
    });
  });

  group('repositorio: sin_validar.json', () {
    test('se lee y se arma la zona', () async {
      final repo = RepositorioMapa(fuenteDePrueba(sinValidar: true));
      final z = await repo.sinValidar();
      expect(z!.zonas.single.nombre, 'Valle del arroyo San Francisco');
      expect(z.zonas.single.motivo, contains('Dinagua'));
      expect(z.poligonos, hasLength(1));
      // se lee una sola vez
      await repo.sinValidar();
      expect((repo.fuente as FuenteMemoria).lecturas['sin_validar.json'], 1);
    });

    test('sin el campo en el índice: null, sin leer nada', () async {
      final f = fuenteDePrueba();
      expect(await RepositorioMapa(f).sinValidar(), isNull);
      expect(f.lecturas['sin_validar.json'], isNull);
    });

    test('huella que no coincide, archivo de otro tamaño o que falta: null', () async {
      final otra = jsonABytes({'type': 'FeatureCollection', 'features': <Object>[]});
      expect(
        await RepositorioMapa(fuenteDePrueba(sinValidar: true, archivos: {'sin_validar.json': otra})).sinValidar(),
        isNull,
      );
      expect(
        await RepositorioMapa(fuenteDePrueba(sinValidar: true, archivos: {'sin_validar.json': null})).sinValidar(),
        isNull,
      );
    });

    test('validación del archivo', () {
      final ind = IndiceMapa.desdeJson(indiceDePrueba());
      expect(
        () => ZonasSinValidar.desdeJson({'type': 'FeatureCollection', 'features': []}, ind),
        throwsA(isA<ErrorMapa>()),
      );
      expect(() => ZonasSinValidar.desdeJson([], ind), throwsA(isA<ErrorMapa>()));
      // una zona rota se saltea; sin nombre, se la llama "Zona sin validar"
      final j = sinValidarDePrueba();
      final features = j['features']! as List;
      features.add({
        'type': 'Feature',
        'properties': <String, Object>{},
        'geometry': {
          'type': 'Polygon',
          'coordinates': [
            [
              [-58.05, -32.39],
              [-58.04, -32.39],
              [-58.04, -32.38],
              [-58.05, -32.39],
            ],
          ],
        },
      });
      features.add({
        'type': 'Feature',
        'properties': {'nombre': 'Rota'},
        'geometry': {'type': 'Point', 'coordinates': <Object>[]},
      });
      final z = ZonasSinValidar.desdeJson(j, ind);
      expect(z.zonas.map((z) => z.nombre), ['Valle del arroyo San Francisco', 'Zona sin validar']);
    });
  });

  group('capa: aisladas opcional', () {
    test('sin la propiedad (datos de antes de la v1.1): lista vacía', () async {
      final c = await RepositorioMapa(fuenteDePrueba()).capa(420);
      expect(c!.capa.aisladas, isEmpty);
    });

    test('se leen punto, hectáreas y calles; lo raro se saltea', () async {
      final repo = RepositorioMapa(
        fuenteDePrueba(
          aisladas: {
            420: [
              lomaDePrueba(),
              {
                'c': [-58.05, -32.35],
              }, // sin ha ni calles: vale igual
              {
                'c': [-57.0, -32.35],
                'ha': 1,
              }, // fuera del mapa
              {'c': 'x'},
              'nada',
              {
                'c': [-58.05, -32.35],
                'ha': -3,
                'calles_m': 'mucho',
              },
            ],
          },
        ),
      );
      final aisladas = (await repo.capa(420))!.capa.aisladas;
      expect(aisladas, hasLength(3));
      expect(aisladas.first.punto.longitude, -58.0898);
      expect(aisladas.first.hectareas, 1.4);
      expect(aisladas.first.callesM, 320);
      expect(aisladas[1].hectareas, isNull);
      expect(aisladas[2].hectareas, isNull);
      expect(aisladas[2].callesM, isNull);
    });

    test('una lista que no es lista no rompe la capa', () async {
      final capa = capaDePrueba(420);
      ((capa['features']! as List).first as Map)['properties']['aisladas'] = 'muchas';
      final f = fuenteDePrueba(archivos: {});
      // reemplaza la capa y rehace la huella en el índice
      final bytes = jsonABytes(capa);
      final j = jsonDecode(utf8.decode(f.archivos['indice.json']!)) as Map<String, dynamic>;
      final c = (j['capas'] as List)[2] as Map<String, dynamic>;
      c['bytes'] = bytes.length;
      c['sha256'] = sha256.convert(bytes).toString();
      final repo = RepositorioMapa(
        FuenteMemoria({...f.archivos, archivoCapa(420): bytes, 'indice.json': jsonABytes(j)}),
      );
      final leida = await repo.capa(420);
      expect(leida!.alturaCm, 420);
      expect(leida.capa.aisladas, isEmpty);
    });
  });

  group('zona baja de la costa (v1.1 §3)', () {
    test('la elección siempre trae la zona baja', () {
      final ind = indiceDe(fuenteReal());
      for (final cm in [300, 390, 400, 410, 700, 1050, 1120]) {
        expect(elegirAgua(cm, ind).zonaBajaCm, 400, reason: '$cm');
      }
    });

    test('resumen: igual con 3,90 que con 4,00, y nunca "cauce"', () {
      String resumen(int cm) {
        final ind = indiceDe(fuenteReal());
        final e = elegirAgua(cm, ind);
        return resumenMapa(
          situacion: e.situacion,
          alturaCm: cm,
          dibujoCm: e.capaCm,
          margenCm: e.margenCm,
          minCm: ind.minCm,
          maxCm: ind.maxCm,
        );
      }

      const frase = 'el agua no pasa de la zona baja de la costa: islas y bañados que se mojan con el río normal.';
      expect(resumen(390), contains(frase));
      expect(resumen(400), contains(frase));
      expect(resumen(410), isNot(contains(frase)));
      expect(
        resumen(410),
        contains('La zona baja de la costa, que se moja con el río normal, tiene su propio dibujo.'),
      );
      for (final cm in [300, 390, 400, 410]) {
        expect(resumen(cm), isNot(contains('cauce')), reason: '$cm');
      }
    });

    for (final (altura, metros) in [(3.95, '4,00'), (3.85, '3,90'), (3.20, '3,20')]) {
      testWidgets('con ${metros.replaceAll(',', ',')} m la lectura dice zona baja, no cauce', (t) async {
        await mostrarMapa(t, datosCon(altura, nivel: 'normal'), fuente: fuenteReal());
        expect(lectura(metros), findsOneWidget);
        expect(find.textContaining(textoZonaBaja), findsOneWidget);
        expect(find.textContaining('cauce', findRichText: true), findsOneWidget); // solo la leyenda del río
        expect(find.text('Río y arroyos, en su cauce'), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('al pasar de 3,90 a 4,00 no cambia el texto de la zona baja', (t) async {
      await mostrarMapa(t, datosCon(3.85, nivel: 'normal'), fuente: fuenteReal());
      final antes = find.textContaining(textoZonaBaja).evaluate().single.widget as Text;
      await t.tap(find.byTooltip('Subir 10 cm'));
      await t.pumpAndSettle();
      expect(lectura('4,00'), findsOneWidget);
      final despues = find.textContaining(textoZonaBaja).evaluate().single.widget as Text;
      expect(despues.data, antes.data);
      await t.tap(find.byTooltip('Subir 10 cm'));
      await t.pumpAndSettle();
      expect(find.textContaining(textoZonaBaja), findsNothing);
    });

    testWidgets('la capa de la zona baja se lee siempre, también por debajo del mínimo', (t) async {
      final f = fuenteReal();
      await mostrarMapa(t, datosCon(3.20, nivel: 'normal'), fuente: f);
      expect(f.lecturas[archivoCapa(400)], 1);
      expect(find.bySemanticsLabel(RegExp('Con 3,20 metros el agua no pasa de la zona baja')), findsOneWidget);
    });
  });

  group('margen siempre (v1.1 §4, condición bloqueante para publicar)', () {
    test('elegirAgua siempre da un margen dentro de las capas', () {
      final ind = indiceDe(fuenteReal());
      final esperado = {350: 400, 400: 450, 700: 750, 1050: 1050, 1120: 1050, 0: 400, 1010: 1050};
      esperado.forEach((cm, margen) {
        final e = elegirAgua(cm, ind);
        expect(e.margenCm, margen, reason: '$cm');
        expect(ind.capaDe(e.margenCm), isNotNull, reason: '$cm');
      });
    });

    // BLOQUEANTE (11 §8, condición para publicar): las cinco alturas del
    // pedido: por debajo del rango, en los dos bordes, en el medio y por
    // encima. Si alguna deja de dibujar el margen, no se publica.
    const cincoAlturas = [
      (3.50, '3,50', SituacionAgua.debajoDelMinimo, 400),
      (4.00, '4,00', SituacionAgua.enRango, 450),
      (7.00, '7,00', SituacionAgua.enRango, 750),
      (10.50, '10,50', SituacionAgua.enRango, 1050),
      (11.20, '11,20', SituacionAgua.sobreMaximo, 1050),
    ];

    test('BLOQUEANTE: la elección trae margen en las cinco alturas (3,50 · 4,00 · 7,00 · 10,50 · 11,20)', () {
      final ind = indiceDe(fuenteReal());
      for (final (altura, texto, situacion, margen) in cincoAlturas) {
        final e = elegirAgua(redondearArriba(altura, pasoCm: ind.pasoCm), ind);
        expect(e.situacion, situacion, reason: texto);
        expect(e.margenCm, margen, reason: texto);
        expect(ind.capaDe(e.margenCm), isNotNull, reason: '$texto: el margen tiene que ser una capa que existe');
        // nunca por debajo del agua pintada
        expect(e.margenCm, greaterThanOrEqualTo(e.capaCm ?? ind.minCm), reason: texto);
      }
    });

    for (final (altura, texto, _, margen) in cincoAlturas) {
      testWidgets('BLOQUEANTE: con $texto m se dibuja la franja de margen (capa $margen)', (t) async {
        final f = fuenteReal();
        await mostrarMapa(t, datosCon(altura, nivel: 'evacuacion'), fuente: f);
        // el mapa abre justo en esa altura (hoy), no en otra
        expect(lectura(texto), findsOneWidget);
        expect(f.lecturas[archivoCapa(margen)], greaterThanOrEqualTo(1));
        // se pintan todos los polígonos de la capa del margen, con su estilo
        final capaMargen = (await RepositorioMapa(fuenteReal()).capa(margen))!.capa;
        expect(capaMargen.poligonos, isNotEmpty);
        expect(
          poligonosDelMargen(t),
          capaMargen.poligonos.length,
          reason: 'el margen tiene que estar pintado entero con $texto m',
        );
        // Si el margen coincide con una capa que va encima (la zona baja por
        // debajo del mínimo, el agua en el máximo o por encima), sus puntos
        // se repiten arriba: si no, quedaría tapado y no se vería.
        final tapado = margen == 400 && altura < 4.00 || margen == 1050 && altura >= 10.50;
        if (tapado) expect(puntosDelMargenEncima(t), greaterThan(0), reason: 'puntos del margen encima con $texto m');
        // y la leyenda lo explica
        expect(find.textContaining('Puede llegar un poco más'), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('también al simular cada altura con el deslizador en todo el rango', (t) async {
      await mostrarMapa(t, datosCon(4.13), fuente: fuenteReal());
      // bajar hasta el piso del deslizador y subir hasta el techo, mirando el margen
      final slider = t.widget<Slider>(find.byType(Slider));
      for (var cm = slider.min.round(); cm <= slider.max.round(); cm += 50) {
        slider.onChanged!(cm.toDouble());
        slider.onChangeEnd!(cm.toDouble());
        await t.pumpAndSettle();
        expect(poligonosDelMargen(t), greaterThan(0), reason: 'altura $cm');
      }
    });
  });

  group('lomas aisladas (v1.1 §2)', () {
    testWidgets('si la capa pintada tiene alguna, se avisa a la vista y en el resumen', (t) async {
      await mostrarMapa(
        t,
        datosCon(6.95, nivel: 'evacuacion'),
        fuente: fuenteReal(
          aisladas: {
            700: [lomaDePrueba()],
          },
        ),
      );
      expect(lectura('7,00'), findsOneWidget);
      expect(find.text('Hay una loma marcada en el mapa. $textoLomaAislada'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(RegExp.escape(textoLomaAislada))), findsWidgets);
      // otra altura sin lomas: el aviso se va
      await t.tap(find.byTooltip('Subir 10 cm'));
      await t.pumpAndSettle();
      expect(find.textContaining(textoLomaAislada), findsNothing);
    });

    testWidgets('varias: el aviso va en plural', (t) async {
      await mostrarMapa(
        t,
        datosCon(6.95, nivel: 'evacuacion'),
        fuente: fuenteReal(
          aisladas: {
            700: [lomaDePrueba(), lomaDePrueba(lon: -58.05)],
          },
        ),
      );
      expect(find.textContaining('Hay 2 lomas marcadas en el mapa. Quedarían rodeadas de agua'), findsOneWidget);
    });

    testWidgets('por debajo del mínimo cuentan las de la zona baja', (t) async {
      await mostrarMapa(
        t,
        datosCon(3.50, nivel: 'normal'),
        fuente: fuenteReal(
          aisladas: {
            400: [lomaDePrueba()],
          },
        ),
      );
      expect(find.text('Hay una loma marcada en el mapa. $textoLomaAislada'), findsOneWidget);
    });

    test('el resumen la nombra', () {
      final r = resumenMapa(
        situacion: SituacionAgua.enRango,
        alturaCm: 700,
        dibujoCm: 700,
        margenCm: 750,
        minCm: 400,
        maxCm: 1050,
        aisladas: 1,
      );
      expect(r, contains(textoLomaAislada));
    });

    testWidgets('la hoja de una loma dice el texto del contrato', (t) async {
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => mostrarLomaAislada(context, LomaAislada(const LatLng(-32.35, -58.05), hectareas: 1.4)),
              child: const Text('abrir'),
            ),
          ),
        ),
      );
      await t.tap(find.text('abrir'));
      await t.pumpAndSettle();
      expect(find.text(textoLomaAislada), findsOneWidget);
      expect(find.text('Mide unas 1,4 hectáreas.'), findsOneWidget);
    });
  });

  group('zona sin validar (v1.1 §1)', () {
    testWidgets('con el archivo: fila en la leyenda y mención en el resumen', (t) async {
      await mostrarMapa(t, datosCon(6.95, nivel: 'evacuacion'), fuente: fuenteReal(sinValidar: true));
      expect(find.textContaining(textoLeyendaSinValidar), findsOneWidget);
      expect(find.bySemanticsLabel(mencionSinValidar), findsOneWidget);
    });

    // B1 (revisión de código): los assets de hoy no traen `sin_validar` (el
    // pipeline v1.1 no se pudo correr). La zona existe igual (11 §8,
    // condición 3): se nombra en el resumen y en la leyenda, sin dibujar borde.
    testWidgets('sin el archivo (datos de hoy): se nombra igual, sin borde, y el mapa anda', (t) async {
      final s = t.ensureSemantics();
      await mostrarMapa(t, datosCon(6.95, nivel: 'evacuacion'), fuente: fuenteReal());
      expect(lectura('7,00'), findsOneWidget);
      // Resumen para TalkBack: el valle del San Francisco y que no está marcado.
      expect(find.bySemanticsLabel(mencionSinValidar), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp(RegExp.escape('$textoSinValidar $textoSinValidarSinDibujo'))),
        findsOneWidget,
      );
      // Leyenda: fila sin muestra (no hay borde), distinta de la del borde.
      expect(find.text(textoLeyendaSinValidarSinDibujo), findsOneWidget);
      expect(find.textContaining(textoLeyendaSinValidar), findsNothing);
      // Y ningún borde de zona sin validar dibujado.
      final c = ColoresMapa.actuales();
      expect(
        t
            .widgetList<PolylineLayer>(find.byType(PolylineLayer))
            .expand((l) => l.polylines)
            .where((p) => p.color == c.sinValidar),
        isEmpty,
      );
      s.dispose();
    });

    test('textos de la zona sin dibujo: nombran el valle del San Francisco Grande', () {
      expect(textoSinValidar, contains('San Francisco Grande'));
      expect(textoLeyendaSinValidarSinDibujo, contains('San Francisco Grande'));
      expect(textoLeyendaSinValidarSinDibujo, contains('No está marcada en el dibujo'));
      final r = resumenMapa(
        situacion: SituacionAgua.enRango,
        alturaCm: 700,
        dibujoCm: 700,
        margenCm: 750,
        minCm: 400,
        maxCm: 1050,
        sinValidarSinDibujo: true,
      );
      expect(r, contains('$textoSinValidar $textoSinValidarSinDibujo'));
      // Con la zona dibujada se usa el nombre del archivo, sin "no está marcada".
      final dibujada = resumenMapa(
        situacion: SituacionAgua.enRango,
        alturaCm: 700,
        dibujoCm: 700,
        margenCm: 750,
        minCm: 400,
        maxCm: 1050,
        sinValidar: true,
        sinValidarSinDibujo: true,
        nombresSinValidar: const ['Valle del arroyo San Francisco'],
      );
      expect(dibujada, isNot(contains(textoSinValidarSinDibujo)));
    });

    testWidgets('con el archivo roto: el mapa anda igual, sin la zona', (t) async {
      await mostrarMapa(
        t,
        datosCon(6.95, nivel: 'evacuacion'),
        fuente: fuenteDePrueba(
          desde: 400,
          hasta: 1050,
          sinValidar: true,
          archivos: {
            'sin_validar.json': jsonABytes({'roto': true}),
          },
        ),
      );
      expect(lectura('7,00'), findsOneWidget);
      expect(find.textContaining(textoLeyendaSinValidar), findsNothing);
      // Sin borde, pero la zona se sigue nombrando (B1).
      expect(find.text(textoLeyendaSinValidarSinDibujo), findsOneWidget);
    });
  });

  group('leyenda v1.1 (09 §3.9)', () {
    testWidgets('zona baja siempre; loma solo si la capa pintada tiene alguna; sin validar solo con archivo', (
      t,
    ) async {
      await mostrarMapa(
        t,
        datosCon(6.95, nivel: 'evacuacion'),
        fuente: fuenteReal(
          aisladas: {
            700: [lomaDePrueba()],
          },
        ),
      );
      expect(find.textContaining(textoLeyendaZonaBaja), findsOneWidget);
      expect(find.textContaining(textoLeyendaAisladas), findsOneWidget);
      expect(find.textContaining(textoLeyendaSinValidar), findsNothing);
      await t.tap(find.byTooltip('Subir 10 cm'));
      await t.pumpAndSettle();
      expect(find.textContaining(textoLeyendaAisladas), findsNothing);
      expect(find.textContaining(textoLeyendaZonaBaja), findsOneWidget);
    });

    test('la zona sin validar se nombra con lo que trae el archivo', () {
      expect(textoSinValidarDe(const []), textoSinValidar);
      expect(textoSinValidarDe(const ['  ']), textoSinValidar);
      expect(
        textoSinValidarDe(const ['Valle del arroyo San Francisco']),
        'Zona sin validar: Valle del arroyo San Francisco. Ahí el mapa no se pudo comparar con crecidas reales.',
      );
      expect(textoSinValidarDe(const ['A', 'B', 'C']), startsWith('Zonas sin validar: A, B y C.'));
      final r = resumenMapa(
        situacion: SituacionAgua.enRango,
        alturaCm: 700,
        dibujoCm: 700,
        margenCm: 750,
        minCm: 400,
        maxCm: 1050,
        sinValidar: true,
        nombresSinValidar: const ['Otra zona'],
      );
      expect(r, contains('Zona sin validar: Otra zona.'));
      expect(r, isNot(contains('San Francisco')));
      // sin zona dibujada no se nombra aunque haya nombres
      final sin = resumenMapa(
        situacion: SituacionAgua.enRango,
        alturaCm: 700,
        dibujoCm: 700,
        margenCm: 750,
        minCm: 400,
        maxCm: 1050,
        nombresSinValidar: const ['Otra zona'],
      );
      expect(sin, isNot(contains('sin validar')));
    });
  });

  group('dibujo v1.1 en el mapa', () {
    for (final (altura, texto) in [(3.20, '3,20'), (4.00, '4,00'), (7.00, '7,00'), (11.20, '11,20')]) {
      testWidgets('la zona baja se dibuja con su estilo con $texto m', (t) async {
        await mostrarMapa(t, datosCon(altura, nivel: 'evacuacion'), fuente: fuenteReal());
        expect(lectura(texto), findsOneWidget);
        expect(find.byType(CapaZonaBaja), findsOneWidget);
      });
    }

    testWidgets('lomas: una marca por punto, solo en la altura que las trae', (t) async {
      await mostrarMapa(
        t,
        datosCon(6.95, nivel: 'evacuacion'),
        fuente: fuenteReal(
          aisladas: {
            700: [lomaDePrueba(), lomaDePrueba(lon: -58.05)],
          },
        ),
      );
      int marcas() => t.widgetList<MarkerLayer>(find.byType(MarkerLayer)).expand((l) => l.markers).length;
      expect(marcas(), 2);
      await t.tap(find.byTooltip('Subir 10 cm'));
      await t.pumpAndSettle();
      expect(marcas(), 0);
    });

    testWidgets('zona sin validar: su borde se dibuja solo si el archivo validó', (t) async {
      int bordes() {
        final c = ColoresMapa.actuales();
        return t
            .widgetList<PolylineLayer>(find.byType(PolylineLayer))
            .expand((l) => l.polylines)
            .where((p) => p.color == c.sinValidar)
            .length;
      }

      await mostrarMapa(t, datosCon(6.95, nivel: 'evacuacion'), fuente: fuenteReal(sinValidar: true));
      expect(bordes(), greaterThan(0));
      await mostrarMapa(t, datosCon(6.95, nivel: 'evacuacion'), fuente: fuenteReal());
      expect(bordes(), 0);
    });
  });

  group('avisos de 01 §6 y 11 §8 (condición 2 y 5)', () {
    test('el texto fijo los tiene todos', () {
      expect(textoMapaAproximado, contains('una cuadra o más'));
      expect(textoMapaAproximado, contains('pluviales'));
      expect(textoMapaAproximado, contains('arroyos'));
      expect(textoMapaAproximado, contains('lluvia'));
      expect(textoMapaAproximado, contains('Cecoed'));
      expect(textoMapaAproximado, contains('Intendencia'));
      expect(textoMapaAproximado, contains('911'));
      expect(textoMapaAproximado, contains('no un mapa oficial'));
      expect(textoMapaAproximado, contains('Si quedás rodeado de agua, también estás en riesgo.'));
      expect(textoAvisoMapa, contains('No reemplaza la alerta oficial'));
    });

    test('ningún texto nuevo promete que no llega el agua', () {
      final prohibido = RegExp(
        r'a salvo|\bsegur[oa]\b|zona segura|no se inunda\b|sin peligro|en su cauce',
        caseSensitive: false,
      );
      for (final texto in [
        textoMapaAproximado,
        textoZonaBaja,
        textoZonaBajaMargen,
        textoLeyendaZonaBaja,
        textoLomaAislada,
        textoAvisoAisladas(1),
        textoAvisoAisladas(3),
        textoSinValidar,
        textoSinValidarDe(const ['Valle del arroyo San Francisco', 'Otra']),
        textoLeyendaSinValidar,
        textoLeyendaAisladas,
        textoSinValidarSinDibujo,
        textoLeyendaSinValidarSinDibujo,
        textoLeyendaHoy,
        textoLeyendaUltimoDato,
        textoLeyendaMargen(50),
        textoLeyendaMargenRecortado(1050),
        textoMargenRecortado(1050),
        textoDibujoIlegible,
        for (final (_, f) in textosFuentes) f,
      ]) {
        expect(texto, isNot(matches(prohibido)), reason: texto);
      }
    });
  });

  group('datos reales de app/assets/mapa (sin los campos nuevos)', () {
    test('el índice real vale y no trae sin_validar todavía (o lo trae bien)', () {
      final archivo = File('assets/mapa/indice.json');
      if (!archivo.existsSync()) return;
      final ind = IndiceMapa.desdeJson(jsonDecode(archivo.readAsStringSync()));
      expect(ind.capas, isNotEmpty);
      final e = elegirAgua(ind.minCm - 50, ind);
      expect(e.zonaBajaCm, ind.minCm);
      expect(ind.capaDe(e.margenCm), isNotNull);
    });
  });
}
